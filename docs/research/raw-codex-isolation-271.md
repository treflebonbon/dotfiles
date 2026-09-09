# raw Codex の秘密なし起動 — #271

2026-09-10。[#271](https://github.com/treflebonbon/dotfiles/issues/271) と親 [#268](https://github.com/treflebonbon/dotfiles/issues/268) の実装・検証記録。前提は [#270 の追加成立確認](secret-isolation-worktree-270.md)。この task worktree から利用者設定を配備していない。

## 起動と入力

`codex-worktree` → `devshell-env codex` → 共通 isolation module が公開入口となる。`devshell-env trust` は既存の repo 単位の信頼を維持し、`devshell-env admit --git-head FULL_SHA -- FILES` が worktree ごとの公開入力を記録する。HEAD から到達可能な履歴全体、列挙したファイルの hash と実行属性、managed config・AGENTS・rules、Git identity と実行可能 hook を公開と宣言する。登録時の index は HEAD と一致させる。ファイル名だけから秘密を分類しない。

Python の trusted bootstrap が user/network namespace を作り、その network namespace 内だけで DNS の低位 port を使用可能にする。続く bubblewrap はこの新しい network だけを共有し、filesystem・PID・IPC 等を分離して capability を全て落とす。host HOME・process・daemon・cache・継承変数を入れず、公開 snapshot と専用 Nix store で Nix／shellHook を実行する。

選択した Nix CLI closure はコピーした後に読み取り専用 mount にする。新しい derivation の追加領域は専用 store に残す。launcher、runtime specification、managed config、`/etc/codex/requirements.toml` も読み取り専用。標準 `dotfiles-secure` と当該 Git metadata の write を requirements に固定し、project config の同名 profile は conflict として拒否する。

通常ファイル・index・commit を終了後に host worktree に返す。host の並行変更、symlink 等の結果、未登録ファイルとの衝突は返却を拒否する。Codex が concrete deny に作る空の未追跡 placeholder は返却対象にしない。初期化失敗は返却せず session を保持する。複数ファイルの返却途中の I/O 障害に対する atomic rollback は保証しない。

## 通信

ChatGPT gateway は host の既存 login を固定 endpoint にだけ使い、token を agent 側へ渡さない。remote conversation／response／file reference と hosted remote tools を拒否する。管理 GitHub／MCP／plugin の本番接続は #272 のため、この入口の入力 config では無効にする。

依存取得は managed domain allowlist の HTTPS CONNECT、名前解決は同じ allowlist の公開 IP に限定する。host で全 DNS 回答を検査し、CONNECT は検査済み numeric address に接続して再解決による差替えを防ぐ。専用 DNS は Codex 自身の private-address 検査を維持するために必要だった。Codex 0.153.4 は DNS 失敗も private-address 拒否として扱う。public CA は標準 `/nix` read 範囲に置く。

実際に `github:NixOS/nixpkgs/<repo lock の revision>` から devShell と hello を取得した後、Codex command proxy → upstream proxy → allowlisted gateway で Nix cache を読み、未許可ドメインを拒否できた。初期化と agent command の双方で外部通信を実測している。

## 検証

| 条件                                                 | 実行経路・証拠                                                                  |
| ---------------------------------------------------- | ------------------------------------------------------------------------------- |
| trust／untrust／継承、固定 root、metadata、引数制限  | 更新した `tests/devshell-env.bats`・`tests/codex-config.bats`、実 Codex sandbox |
| 通常変数、shellHook、WSL／明示 output、終了コード 23 | `tests/devshell-env.bats`、初回と再起動                                         |
| root／別名／下位／別 worktree の秘密、継承値         | 初期化と実 Codex／子 command／with-env、dummy 値の非到達                        |
| リンク、内容差替え、後発追加                         | `tests/raw-codex-integration.bats` と #270 の snapshot／return テスト           |
| launcher・policy・選択 CLI の改変拒否                | 実 namespace 内から write／rename を試行                                        |
| Git 保存                                             | 実 sandbox で stage と commit を別起動、同じ SHA を返却                         |
| hosted model                                         | 共通 raw entry から実モデルが script を実行し、編集・テスト・commit・返却に成功 |
| network                                              | pinned nixpkgs と hello の初回取得、Codex proxy で許可／拒否を実測              |
| 人間向け dotenv                                      | 既存 `tests/with-env.bats` の注入契約を保持                                     |
| Linux と WSL2                                        | 下記の別 kernel の記録を区別                                                    |

WSL2 kernel `6.18.33.2-microsoft-standard-WSL2`、Nix 2.34.6、Codex 0.153.4、bubblewrap 0.11.2、Git 2.54.0、Python 3.13.14 を使用。

- `/tmp/raw-271-integration-2.log`: network・hosted model を opt-in した公開入口の 4 ケースすべて成功。
- `/tmp/raw-271-regressions.log`: 修正した秘密非継承、project PATH、別 Git directory、prepared context、metadata 拒否の 5 ケース成功。
- `/tmp/raw-271-final-focus.log`: 起動後の host 差替え・追加、shell／Python startup code の非読込み、DNS の公開 IP 制限、人間向け dotenv の 4 ケース成功。
- `/tmp/with-env-271-preflight-lz4pglb5/preflight.log`: この revision の公開 `with-env` Nix package を専用 store 内で build し、引数・終了コード・秘密非継承・Git commit・信頼解除を確認。
- `/tmp/secret-isolation-linux-vm-271-dns/`: KVM 上の NixOS、通常ユーザー uid 1000、kernel `6.18.33`。#270 の既存 runtime probe と worktree テストに続き、raw 21 ケース成功。外部 network／model 2 ケースは VM に認証を置かないため opt-in 対象外で、WSL2 の実測と区別する。

Linux VM は host HOME や host store を共有せず、列挙した公開 fixture と CLI closure を image に入れる。再現コマンド:

```bash
python3 scripts/secret-isolation-linux-vm.py --output /tmp/secret-isolation-linux-vm-271-new
CODEX_ISOLATION_CA_BUNDLE=/nix/store/.../etc/ssl/certs/ca-bundle.crt \
  SECRET_ISOLATION_REAL_MODEL=1 SECRET_ISOLATION_REAL_DEPENDENCIES=1 \
  bats tests/raw-codex-integration.bats
CODEX_ISOLATION_CA_BUNDLE=/nix/store/.../etc/ssl/certs/ca-bundle.crt \
  SECRET_ISOLATION_REAL_RUNTIME=1 bun run test
```

## 導入・復旧と限界

[利用方法](../../runtime/shell-environment.md#raw-codex-のプロジェクト開発環境) を正本とする。必要なファイルと公開履歴の宣言は人間が所有する。既存 session・直接 Codex・Desktop・Orca／Herdr native 起動に遡及適用しない。macOS raw は未対応。現在の model gateway は既存 ChatGPT login を使い、API key provider は未統合。

専用 store は起動ごとに新規作成し、復旧用 session を保持する。返却前は host の同じ worktree を並行編集しない。host で公開ファイルや設定を変更した場合は再登録し、初期化失敗時は修正した入力から再起動する。結果の復旧前に session を削除しない。GitHub／管理 MCP、Herdr、人間の実値検証フローはそれぞれ #272／#273／#274 の範囲。
