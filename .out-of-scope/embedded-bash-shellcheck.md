# Python 文字列に埋め込んだ bash への shellcheck

`private_dot_local/share/codex-isolation/secret-isolation-worktree.py` の `bridge_startup` は、sandbox 内で実行する bash を Python の f-string として返す。この bash は lefthook の shellcheck／shfmt の対象外で、静的チェックの仕組みはあえて追加していない。

## Why this is out of scope

lefthook で shellcheck を実行する job の glob は `**/*.sh` と `private_dot_local/bin/executable_*` だけで、`.py` に埋め込んだ bash は対象にならない。Python 側で bash を組み立てる箇所は `bridge_startup` の1か所しかない。

#464 では、EOF の分岐で `wait` が終わらなくなる不具合を、静的チェックではなく review と回帰テスト（`tests/secret-isolation-gateway.bats`）で捕まえた。一度の不具合のために lint の経路を増やすより、既存の review と回帰テストに任せるほうが保守の負担が小さい。

## When to reconsider

埋め込み bash の不具合が繰り返された場合は見直す。そのときは、テストで生成した script（例: `tests/secret-isolation-gateway.bats` の `startup.sh`）に shellcheck をかけるテストを1つ足す。lefthook の glob を広げたり、Python 側で bash を抽出したりする必要はない。

## Prior requests

- #468: "Python 文字列に埋め込んだ bash が shellcheck の対象外"
