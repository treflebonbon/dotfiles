#!/usr/bin/env python3
"""Checkpoint explicit public evidence and restore its original bytes and paths."""

import base64
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import stat
import sys
import tempfile


candidate_record = runpy.run_path(str(Path(__file__).with_name("candidate-record.py")))
SHARED = Path("/tmp/codex")
SENSITIVE = (
    "*.pem", "*.key", "*.pfx", "*.p12", "credentials*.json", "auth.json",
    "secret.json", "secrets.json", "service-account*.json", "id_*",
    "token.json", "tokens.json", "token.*.json", "credentials", ".netrc", ".npmrc", ".pypirc",
    "application_default_credentials.json", "access_tokens.db", ".git-credentials", ".credentials*.json",
)
SENSITIVE_DIRECTORIES = (".aws", ".ssh", ".gnupg", ".kube", ".docker", ".azure", "gcloud")


def fail(message):
    raise ValueError(message)


def public_path(value, artifact_path=None):
    path = Path(value)
    if not path.is_absolute() or ".." in path.parts or path == SHARED:
        fail("証跡は正規の絶対パスで指定してください")
    shared = path.is_relative_to(SHARED)
    if not shared and str(path) != artifact_path:
        fail("証跡は /tmp/codex 配下の絶対パスで指定してください")
    parts = tuple(part.lower() for part in path.parts)
    for part in parts:
        if (part.startswith(".env") and part != ".env.example") or part in SENSITIVE_DIRECTORIES or any(
            fnmatch.fnmatchcase(part, pattern) for pattern in SENSITIVE
        ):
            fail("機密ファイル名を証跡に含められません")
    if any(parts[i:i + 2] == (".config", "gh") for i in range(len(parts) - 1)):
        fail("機密ファイル名を証跡に含められません")
    for parent in (path, *path.parents):
        if parent.is_symlink():
            fail("証跡のパスに symlink を含められません")
        if parent != path and parent.exists() and not parent.is_dir():
            fail("証跡の親パスが directory ではありません")
        if shared and parent == SHARED:
            break
    return path


def read_public(value, artifact_path=None):
    path = public_path(value, artifact_path)
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            fail("証跡は通常ファイルで指定してください")
        return stream.read()


def storage(fingerprint):
    if not re.fullmatch(r"[0-9a-f]{64}", fingerprint):
        fail("record fingerprint は SHA-256 で指定してください")
    root = Path(candidate_record["repo_identity"]()) / "peer-refactor-evidence"
    folder = root / fingerprint
    if root.is_symlink() or folder.is_symlink():
        fail("証跡保管先に symlink を含められません")
    return folder


def original_artifact(raw_record, fingerprint):
    if hashlib.sha256(raw_record).hexdigest() != fingerprint:
        fail("記録ファイルの fingerprint が一致しません")
    record = json.loads(raw_record)
    if not isinstance(record, dict) or not isinstance(record.get("artifact_path"), str):
        fail("記録ファイルの形式が不正です")
    return record["artifact_path"]


def checkpoint(record_path, candidates_path, fingerprint, *extra_paths):
    artifact_path = original_artifact(read_public(record_path), fingerprint)
    public_path(candidates_path)
    paths = sorted(set((record_path, candidates_path, artifact_path, *extra_paths)))
    files = {path: read_public(path, artifact_path) for path in paths}
    candidate_record["check"](record_path, candidates_path, fingerprint, files.__getitem__)
    data = {
        "version": 1,
        "record_path": record_path,
        "candidates_path": candidates_path,
        "fingerprint": fingerprint,
        "files": {path: base64.b64encode(raw).decode("ascii") for path, raw in files.items()},
    }
    raw = (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    digest = hashlib.sha256(raw).hexdigest()
    folder = storage(fingerprint)
    folder.parent.mkdir(mode=0o700, exist_ok=True)
    folder.mkdir(parents=True, mode=0o700, exist_ok=True)
    destination = folder / (digest + ".json")
    # Publish only a complete snapshot; concurrent identical checkpoints share it.
    with tempfile.NamedTemporaryFile(dir=folder, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
            try:
                os.link(temporary, destination)
            except FileExistsError:
                if destination.is_symlink() or destination.read_bytes() != raw:
                    fail("既存の checkpoint が破損しています")
        finally:
            temporary.unlink()
    print(json.dumps({"checkpoint": digest, "fingerprint": fingerprint, "path": str(destination)}, ensure_ascii=False))


def restore(fingerprint, digest):
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        fail("checkpoint は SHA-256 で指定してください")
    source = storage(fingerprint) / (digest + ".json")
    if source.is_symlink():
        fail("checkpoint に symlink を使えません")
    raw = source.read_bytes()
    if hashlib.sha256(raw).hexdigest() != digest:
        fail("checkpoint の hash が一致しません")
    data = json.loads(raw)
    if not isinstance(data, dict) or data.get("version") != 1 or data.get("fingerprint") != fingerprint:
        fail("checkpoint の形式または fingerprint が不正です")
    encoded = data.get("files")
    if not isinstance(encoded, dict) or not encoded:
        fail("checkpoint のファイル一覧が不正です")
    files = {}
    for path, content in encoded.items():
        if not isinstance(content, str):
            fail("checkpoint のファイル内容が不正です")
        files[path] = base64.b64decode(content, validate=True)
    public_path(data["record_path"])
    public_path(data["candidates_path"])
    artifact_path = original_artifact(files[data["record_path"]], fingerprint)
    candidate_record["check"](data["record_path"], data["candidates_path"], fingerprint, files.__getitem__)
    for path, content in files.items():
        target = public_path(path, artifact_path)
        if target.exists() and read_public(path, artifact_path) != content:
            fail("既存の証跡と異なるため復元を中止しました。待機台帳も上書きしません")
    created = []
    for path, content in files.items():
        target = public_path(path, artifact_path)
        try:
            target.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
            if not target.exists():
                stream = target.open("xb")
                created.append(target)
                with stream:
                    os.fchmod(stream.fileno(), 0o600)
                    stream.write(content)
        except OSError:
            for done in created:
                try:
                    done.unlink()
                except OSError:
                    pass  # 元の復元エラーを保持する。
            raise
    candidate_record["check"](
        data["record_path"], data["candidates_path"], fingerprint,
        lambda path: read_public(path, artifact_path),
    )
    print(json.dumps({"restored": len(files), "record_path": data["record_path"], "checkpoint": digest}, ensure_ascii=False))


def main(argv):
    if len(argv) >= 5 and argv[1] == "checkpoint":
        checkpoint(*argv[2:])
    elif len(argv) == 4 and argv[1] == "restore":
        restore(*argv[2:])
    else:
        fail("使い方: run-evidence.py checkpoint <record> <candidates> <record-sha256> [public-file ...] | restore <record-sha256> <checkpoint-sha256>")


if __name__ == "__main__":
    try:
        main(sys.argv)
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(f"エラー: {error}", file=sys.stderr)
        sys.exit(1)
