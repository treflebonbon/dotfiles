---
type: research
title: Issue 256 Claude のプロジェクト環境と lifecycle 検証
description: SessionStart・CwdChanged・同期 Bash hook・reload、秘密値の非保存、Orca の実測と未確認条件
tags: [nix, claude-code, worktree, verification]
---

# Issue #256 の検証記録

対象は [#256](https://github.com/treflebonbon/dotfiles/issues/256)、親は [Spec #254](https://github.com/treflebonbon/dotfiles/issues/254)。2026-09-09、依存 #255 を含む `e025054ee38e80d7e08e7080f6c74faf73bd0823` を validated task worktree へ fast-forward して実装した。live source の `chezmoi apply` は行っていない。利用方法は [Claude のプロジェクト開発環境](../../runtime/shell-environment.md#claude-のプロジェクト開発環境) を参照。

## 実 lifecycle で判明した接続条件

[公式の環境ファイル仕様](https://code.claude.com/docs/en/hooks#persist-environment-variables) を基に、既存 #255 の loopback model fixture を拡張した。モデル応答だけを固定し、実 Claude Code 2.1.263 の SessionStart、Bash、EnterWorktree、ExitWorktree、CwdChanged を動かした。隔離 HOME・設定・Git repo・ダミー値を使い、実 credential と外部 API は使っていない。fixture の `--allowedTools` はテスト用 Bash 等に限定し、本番 Auto mode の classifier が成立する証拠とは分ける。

最初の実験では、`SessionStart` と `CwdChanged` だけの実装は不十分だった。

- `EnterWorktree` 後に CwdChanged が発火せず、旧 root の環境が残った。
- 通常の cd では CwdChanged が非同期に走り、次の Bash が準備を待たず旧環境を観測した。
- Bash ツールの backend は zsh になる場合があり、Bash 固有の配列・間接参照では失敗した。
- worktree session の cwd は Claude が固定する。別 repo への移動は `ExitWorktree(action=keep)` を経由し、fixture 全体を追加 workspace として宣言して検証した。既存の worktree 制限は迂回しない。

最終実装では `SessionStart` が初期化し、`SessionStart` と `CwdChanged` が環境ファイルの接続を維持する。`PreToolUse(Bash)` が実際の cwd を同期確認して環境を切り替える。CwdChanged は環境を更新しないため、遅延イベントで新しい環境を上書きする競合も避けられる。同じ root・output・信頼・flake 有無では初期化を省略する。bash/zsh 共通の script は初期化時の差分だけを適用する。

CLI は `Repository.discover`・`trusted`・`selected_output`・`prepare_environment` を #255 と共有する。Claude 用 Nix 準備には HOME と解決済みツールの最小 PATH を渡し、任意の継承変数を渡さない。PATH の bootstrap 要素も保存対象から外し、後続 Bash の PATH にプロジェクト要素を加える。復元元の値は非exportの shell 変数だけで保持し、session script や JSON には書かない。値を別名へ加工する shellHook と、同名変数の上書きもダミー値で検証した。

## Verification Matrix

| #256 の条件（親 AC）                    | 検証入口                                                     | 結果・制約                                                                                                                                              |
| --------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 信頼と output、後続 Bash（AC04・AC05）  | managed hook の Bats、実 Claude＋実 Nix                      | 登録済み repo/worktree のツール・通常変数を反映。未登録・flake 不在・Git 外では Nix を起動しない。共通の WSL／明示 output 選択を利用                    |
| 起動・EnterWorktree・別 repo（AC06）    | 実 Claude lifecycle、公開イベント記録                        | 通常 CLI は成功。Orca は built-in 起動と hook 発火まで確認し、後続 Bash は下記の理由で未確認                                                            |
| 同一 root・各 Bash の初期化省略（AC06） | shellHook の外部カウンタ、Bats、実 Claude                    | 起動後の同一 root 移動と Bash では増えず、別 root・reload のときだけ増える                                                                              |
| 旧環境の解除・初期化失敗（AC07・AC10）  | Bash の環境とツール観測、Nix／shellHook の失敗 fixture       | 旧通常変数・追加 PATH を解除し、部分初期化を捨てる。理由を表示して調査を継続、reload で復旧                                                             |
| 他 hook と共存（AC07）                  | 他 hook の export、同一 shell で再sourceする Bats、実 Claude | 他 hook の内容・別値への上書き・PATH 追加を保持。外部副作用の巻戻しは対象外                                                                             |
| 明示 reload（AC08）                     | `devshell-env reload` → 次の Bash                            | CLAUDE_ENV_FILE が通常 Bash にない状態で成功。flake が読む追跡済み環境定義の編集を反映。自動監視なし                                                    |
| 秘密の非保存（AC15）                    | 継承・同名衝突・加工・dotenv のダミー値、保存先検索          | Claude の session-env、新しい session 状態、隔離 Nix cache にダミー秘密なし。dotenv・envrc を読まない。任意 flake の外部読取りを封じる sandbox ではない |
| runtime 境界（AC05・AC19）              | settings 差分、既存設定 Bats、Orca launch metadata           | permission・OS sandbox・MCP 設定・built-in launch を維持。更新対象は後続 Bash                                                                           |
| 文書・品質・環境差（AC20）              | 下記コマンドと環境一覧                                       | 最終結果は下記へ記録。未 merge source の実配備なし                                                                                                      |

## 再現コマンドと証跡

```bash
bats tests/claude-devshell-env.bats tests/devshell-env.bats tests/codex-config.bats
python3 tests/helpers/claude-env-preflight.py --real-nix --shell bash
python3 tests/helpers/claude-env-preflight.py --real-nix --shell zsh
bunx tsc --noEmit
ruff check private_dot_local/bin/executable_devshell-env tests/helpers/claude-env-preflight.py
ruff format --check private_dot_local/bin/executable_devshell-env tests/helpers/claude-env-preflight.py
shellcheck private_dot_local/share/devshell-env/claude-env.sh
TMPDIR=/tmp bun run test
```

Session Scratchpad の指定がないため、一時証跡は `/tmp` を使用した。fixture は終了後もダミー repo と証跡を残す。

- 実 Nix＋bash: `/tmp/claude-env-preflight-mcx91egq/`、要約ログ `/tmp/devshell-256-claude-bash.log`
- 実 Nix＋zsh: `/tmp/claude-env-preflight-7gl83d0h/`
- 全 Bats: `/tmp/devshell-256-full-bats.log`

各 fixture の `claude-state/events.jsonl` は公開 hook 入力、`output.jsonl` は実 Bash／worktree tool 結果、`requests.jsonl` は loopback model への fixture リクエストを記録する。

## Orca の検証限界

Orca 1.4.198 の `worktree create --agent claude --setup skip --no-parent` で専用 dummy repo の native worktree を作り、built-in `claude --permission-mode auto` の起動を確認した。project-local fixture 設定を使い、live user settings と built-in command を変更していない。実在秘密のコピー・利用や外部 model API 呼出しはしていない。

Orca のテスト専用 terminal では、作成した dummy repo の trust とダミー API key を選び、無関係な MCP の有効化は拒否した。その後 SessionStart と PreToolUse(Bash) の公開イベントを取得できた。しかし Auto mode の classifier は loopback fixture の応答を評価できず、環境観測・reload の Bash を拒否した。拒否理由は安全性を評価できなかったことであり、コマンドを危険と判定した結果ではない。permission mode の変更や classifier の承認応答の偽装で通さず、Bash への環境反映は未確認として残す。通常 CLI fixture の成功で代替しない。

証跡は `/tmp/claude-env-preflight-le2xmoem/claude-state/`、試行用 script は `/tmp/devshell-256-orca-attempt.py`。Orca repo id は `186032c0-eacb-4e22-8eec-b5efc7821bfc`、worktree は `/home/ubuntu/orca/workspaces/project/claude-env-preflight-le2xmoem`。テスト terminal と loopback server は停止済み。テスト用 repo・branch は削除せず残している。最初の repo selector 変換が失敗した登録だけの fixture は `/tmp/claude-env-preflight-lmynf764/project`（Orca repo id `d7a05519-4949-419d-a464-482b553446f9`）。

## 対応環境

| 環境                                | 実行結果                                                                                      |
| ----------------------------------- | --------------------------------------------------------------------------------------------- |
| WSL2 x86_64-linux、kernel 6.18.33.2 | Nix 2.34.6、Claude 2.1.263、bash 5.3.9／zsh 5.9.1 で成功。Orca の後続 Bash は上記理由で未確認 |
| native x86_64-linux／aarch64-linux  | 今回は独立 host がなく未実行。Nix 定義は変更していない                                        |
| Apple Silicon macOS                 | host がなく未実行。WSL 上の zsh 成功を macOS の実行証拠とはしない                             |

## 最終品質確認

新規 Bats 10件、既存 Claude settings の回帰検証、型チェック、ruff check/format、ShellCheck が成功した。全 Bats とコミット後の2軸レビューの結果は確定後に追記する。
