"""gcloud-inspect-hook の引数保存を bash の単語分割と突き合わせる差分テスト。

使い方: gcloud-inspect-hook-fuzz.py HOOK SEED COUNT
乱数列は seed で固定する。守る不変条件は「hook が書換えたなら、書換え後の引数列は、元の command を
bash が単語分割した結果と一致する」こと。deny や素通しは安全側なので不一致に数えない。
ただし書換えが少なすぎると何も検証していないため、書換えの件数が足りなければ失敗にする。
2種類の入力を作る。
- quoted: 引用符・エスケープで組み立てた引数。メタ文字が文字列として保存されることを見る。
- raw: メタ文字を引用符なしで混ぜた断片。展開を伴う入力を書換えていないことを見る。
bash は gcloud のない PATH と使い捨ての作業ディレクトリで動かす（入力に含まれるコマンドを実行しないため）。
"""

import json
import random
import subprocess
import sys
import tempfile

hook, seed, count = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
rng = random.Random(seed)
ALPHABET = list("ab 1-=:,.@/_") + ["'", '"', "\\", "$", "`", ";", "|", "&", ">", "<", "#", "*", "?", "~", "{", "}", "!", "(", ")", "é"]
# 無害な断片を多く、展開・構文を起こす断片を一定の割合で混ぜる。書換えが十分に起き、かつ x=~ のように
# 名前と = ~ が隣り合うような入力も出るようにする。
BENIGN_ATOMS = ["projects", "list", "x", "a b", "a=b", "x=", "--", "-", " ", " "]
SPECIAL_ATOMS = [
    "x=~", "p=a:~", "~", "~u", "=~", ":~", "$HOME", "$(", ")", "`", ";", "|", "&", ">", "<", "#", "*", "?", "[", "{", "}",
    "!", "\\", "'", '"', "<<EOF", "EOF", "\n", "time", "if", "then",
]
SPECIAL_RATE = 0.3
MIN_REWRITE_RATE = 0.2


def quote(word):
    style = rng.choice(["single", "double", "escape", "bare"])
    if style == "bare" and word and all(c.isalnum() or c in "-_=:,.@/" for c in word) and not word.startswith("-"):
        return word
    if style == "double":
        return '"' + "".join("\\" + c if c in '\\"$`' else c for c in word) + '"'
    if style == "escape" and word:
        return "".join("\\" + c if not c.isalnum() else c for c in word)
    return "'" + word.replace("'", "'\"'\"'") + "'"


def quoted_command():
    words = ["".join(rng.choices(ALPHABET, k=rng.randint(0, 6))) for _ in range(rng.randint(1, 4))]
    words[0] = "x" + words[0]  # 先頭の --reviewed 判定を避ける
    return "gcloud " + " ".join(quote(w) for w in words)


def raw_command():
    atoms = (rng.choice(SPECIAL_ATOMS if rng.random() < SPECIAL_RATE else BENIGN_ATOMS) for _ in range(rng.randint(1, 6)))
    return "gcloud " + "".join(atoms)


def split(args, cwd):
    result = subprocess.run(
        ["bash", "-c", "printf '%s\\0' " + args],
        capture_output=True,
        cwd=cwd,
        env={"PATH": "/usr/bin:/bin"},
    )
    return result.returncode, result.stdout.split(b"\0")


bad = rewrites = 0
with tempfile.TemporaryDirectory() as cwd:
    for n in range(count):
        command = quoted_command() if n % 2 == 0 else raw_command()
        stdin = json.dumps({"tool_name": "Bash", "tool_input": {"command": command}})
        out = subprocess.run([hook], input=stdin, capture_output=True, text=True, check=True).stdout
        decision = json.loads(out)["hookSpecificOutput"] if out else {}
        if decision.get("permissionDecision") != "allow":
            continue
        rewrites += 1
        rewritten = decision["updatedInput"]["command"]
        prefix = "gcloud-inspect"
        rest = rewritten[len(prefix) :]
        expected = split(command[len("gcloud ") :], cwd)
        if not rewritten.startswith(prefix) or rest[:1] not in ("", " ") or expected[0] != 0 or split(rest, cwd) != expected:
            bad += 1
            print(f"MISMATCH: {command!r} => {rewritten!r}")
print(f"{count} cases, seed {seed}, {rewrites} rewrites, {bad} mismatches")
if rewrites < count * MIN_REWRITE_RATE:
    print(f"rewrites {rewrites} < {MIN_REWRITE_RATE:.0%} of cases: the check verified too little")
    sys.exit(1)
sys.exit(1 if bad else 0)
