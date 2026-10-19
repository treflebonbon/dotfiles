"""gcloud-inspect-hook の引数保存を bash の単語分割と突き合わせる差分テスト。

使い方: gcloud-inspect-hook-fuzz.py HOOK SEED COUNT
乱数列は seed で固定する。hook が書換えた command の引数列が、元の command を
bash が単語分割した結果と一致しなければ、該当ケースを出力して終了コード1にする。
"""

import json
import random
import subprocess
import sys

hook, seed, count = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
rng = random.Random(seed)
ALPHABET = list("ab 1-=:,.@/_") + ["'", '"', "\\", "$", "`", ";", "|", "&", ">", "<", "#", "*", "?", "~", "{", "}", "!", "(", ")", "é"]


def quote(word):
    style = rng.choice(["single", "double", "escape", "bare"])
    if style == "bare" and word and all(c.isalnum() or c in "-_=:,.@/" for c in word) and not word.startswith("-"):
        return word
    if style == "double":
        return '"' + "".join("\\" + c if c in '\\"$`' else c for c in word) + '"'
    if style == "escape" and word:
        return "".join("\\" + c if not c.isalnum() else c for c in word)
    return "'" + word.replace("'", "'\"'\"'") + "'"


def split(args):
    out = subprocess.run(["bash", "-c", "printf '%s\\0' " + args], capture_output=True, check=True).stdout
    return out.split(b"\0")


bad = 0
for _ in range(count):
    words = ["".join(rng.choices(ALPHABET, k=rng.randint(0, 6))) for _ in range(rng.randint(1, 4))]
    words[0] = "x" + words[0]  # 先頭の --reviewed 判定を避ける
    command = "gcloud " + " ".join(quote(w) for w in words)
    stdin = json.dumps({"tool_name": "Bash", "tool_input": {"command": command}})
    out = subprocess.run([hook], input=stdin, capture_output=True, text=True, check=True).stdout
    rewritten = json.loads(out)["hookSpecificOutput"].get("updatedInput", {}).get("command", "") if out else ""
    prefix = "gcloud-inspect "
    if not rewritten.startswith(prefix) or split(rewritten[len(prefix):]) != split(command[len("gcloud "):]):
        bad += 1
        print(f"MISMATCH: {command!r} => {rewritten!r}")
print(f"{count} cases, seed {seed}, {bad} mismatches")
sys.exit(1 if bad else 0)
