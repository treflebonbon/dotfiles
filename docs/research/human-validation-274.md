# 秘密なしの開発と人間の実値検証 — #274

2026-09-10。[#274](https://github.com/treflebonbon/dotfiles/issues/274)、親 [#268](https://github.com/treflebonbon/dotfiles/issues/268) の移行・検証記録。共通入口は受入済み [#271](raw-codex-isolation-271.md) の `codex-worktree`。利用方法の正本は [人間の実値検証手順](../../runtime/human-validation.md)。

## 変更と確認する境界

人間向け公開 `with-env` の実装・注入契約は維持する。README、runtime の案内、独立して展開される6言語の `DEVELOPMENT.md` に、公開入力・ダミー値での AI 開発と、確認済み固定版を別環境で実行する手順を揃えた。6テンプレートの共通 package input は #271 の merge commit `b4931c5e0d2152e8fb89eba01b3ac130597e55b3` に固定し、言語用 nixpkgs は引き続き `follows` で共有する。

`tests/human-validation.bats` は一時 repo で公開ファイルだけを commit・admit し、実 Nix と実 Codex の `codex-worktree sandbox` を起動する。人間役はその SHA の Git bundle から独立 clone を作り、公開 `devshell-env with-env` で実 Nix を準備してダミー値を注入する。実行ごとに作るダミー秘密は、raw へ登録するコードには含めない。

人間役が待機中に raw 側は公開 fixture・通常変数・ダミー値でテストし、コードと fixture を変更して commit する。raw の通常 Python と `with-env --prepared` の子は、人間側のコード・dotenv・ログ・成果物と host PID の環境／root を `open` の read／write で取得できないことを検証する。人間側の結果生成後も試行し、元の SHA・ファイル内容・秘密・出力を保持する。隔離外で同じ probe をダミー dotenv に向けると失敗する対照試験により、単に値がログに出なかっただけの判定を避ける。

この fixture の人間役は raw namespace の外にある専用ディレクトリと別プロセスであり、汎用の VM 構築・実値実行サービスではない。実利用では人間が独立 VM／別マシンのアクセス条件を確認する。人間によるコード審査やログの共有判断をテストで代行したとは扱わない。自動試験が扱うのは生成したダミー値と公開依存だけで、配備済み秘密の読取り・コピー、実値サービスの呼出し、利用者設定の配備は行わない。

## Verification Matrix

| #274 の AC                                                         | 検証・結果                                                                                                                             |
| ------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| 1: 公開 with-env の parser・優先順位・argv・終了コード・失敗時停止 | `WITH_ENV_REAL_NIX=1 bats tests/with-env.bats tests/claude-devshell-env.bats`: 29 成功。実 Nix app と raw 内 package を含む。          |
| 2: #271 の入口で秘密なし・ダミー値・通常操作                       | `tests/human-validation.bats` の実 namespace、公開 fixture・ダミー値テスト、commit・返却。WSL2 成功。6テンプレートの追加検証は実行中。 |
| 3: 固定版・コード／秘密／出力の分離条件                            | runtime の手順と6言語の独立利用案内。SHA・依存・コマンドの確認、共有 mount／制御／認証経路の禁止を明示。                               |
| 4: 人間が確認した結果だけ共有                                      | 同手順に未確認ログ・成果物の自動送信禁止を記載。fixture は非公開結果を別保存し、公開要約だけを返す。                                   |
| 5: ダミー別環境への継続編集・取得拒否                              | WSL2 の公開 CLI による並行実行・read／write 拒否と固定版・出力保持に成功。Linux VM 検証は実行中。                                      |
| 6: dotfiles と6テンプレート、envrc 不要／非自動実行                | 公開利用例を更新。6言語独立 repo の実 Nix と raw 起動を実行中。                                                                        |
| 7: 旧 secret 継承・read 期待の移行、Claude 回帰                    | 旧 dotenv grant を用いたテストを、grant なしの deny と公開 `.env.example` 読取りに変更し成功。Claude の10ケースも成功。                |
| 8: Linux／WSL2 の移行・対象・初期化・再起動・未確認事項            | 新手順と下記の OS ごとの記録。既存 repo を一括変更せず、live source への配備は実施しない。                                             |

## 実行環境と再現

WSL2 kernel `6.18.33.2-microsoft-standard-WSL2`、Nix 2.34.6、Codex 0.153.4、Git 2.54.0、bubblewrap 0.11.2。repo の `nix develop .#wsl` で Python 3.13.13（python-dotenv 同梱）と Bats 1.12.0 を使う。

```bash
nix develop .#wsl
bats tests/human-validation.bats
WITH_ENV_REAL_NIX=1 bats tests/with-env.bats tests/claude-devshell-env.bats
python3 tests/helpers/template-with-env.py
python3 scripts/secret-isolation-linux-vm.py --output /tmp/issue-274-linux-vm-new
SECRET_ISOLATION_REAL_RUNTIME=1 bun run test
bunx tsc --noEmit
```

専用 VM へ渡す repo 入力は既存の `linux-vm.nix` の明示リストに今回の Bats・fixture・helper を追加したもの。host HOME・store の共有は行わない。実モデル・認証サービスの opt-in はこの変更では有効にしない。

証跡は `/tmp/issue-274-verification/` に保存する。`with-env-claude.log` は29件成功、`human-wsl-final.log` は新しい2環境 fixture、`templates-final.log` は6言語の結果。全 Bats はファイルを重複なく4群へ分け、各群内を逐次実行する。結果は `full-0.log` ～ `full-3.log` と `full-manifest.json` に記録する。GNU parallel が無いため Bats の `--jobs` 入口ではテストが開始せず、その後に Python の subprocess で4群を実行した。

Linux VM、6言語全体、全 Bats の最終結果は検証完了後に追記する。macOS raw は未対応、ARM／macOS のテンプレートは評価と実行を区別する。実値検証、人間のレビュー判断、対象外ランタイムの非開示保証は検証対象に含めない。
