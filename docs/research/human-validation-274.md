# 秘密なしの開発と人間の実値検証 — #274

2026-09-10。[#274](https://github.com/treflebonbon/dotfiles/issues/274)、親 [#268](https://github.com/treflebonbon/dotfiles/issues/268) の移行・検証記録。共通入口は受入済み [#271](raw-codex-isolation-271.md) の `codex-worktree`。利用方法の正本は [人間の実値検証手順](../../runtime/human-validation.md)。

## 変更と確認する境界

人間向け公開 `with-env` の実装・注入契約は維持する。README、runtime の案内、独立して展開される6言語の `DEVELOPMENT.md` に、公開入力・ダミー値での AI 開発と、確認済み固定版を別環境で実行する手順を揃えた。6テンプレートの共通 package input は #271 の merge commit `b4931c5e0d2152e8fb89eba01b3ac130597e55b3` に固定し、言語用 nixpkgs は引き続き `follows` で共有する。

`tests/human-validation.bats` は一時 repo で公開ファイルだけを commit・admit し、実 Nix と実 Codex の `codex-worktree sandbox` を起動する。人間役はその SHA の Git bundle から独立 clone を作り、公開 `devshell-env with-env` で実 Nix を準備してダミー値を注入する。実行ごとに作るダミー秘密は、raw へ登録するコードには含めない。

人間役が待機中に raw 側は公開 fixture・通常変数・ダミー値でテストし、コードと fixture を変更して commit する。raw の通常 Python と `with-env --prepared` の子は、人間側のコード・dotenv・ログ・成果物と host PID の環境／root を `open` の read／write で取得できないことを検証する。人間側の結果生成後も試行し、元の SHA・ファイル内容・秘密・出力を保持する。隔離外で同じ probe をダミー dotenv に向けると失敗する対照試験により、単に値がログに出なかっただけの判定を避ける。

この fixture の人間役は raw namespace の外にある専用ディレクトリと別プロセスであり、汎用の VM 構築・実値実行サービスではない。実利用では人間が独立 VM／別マシンのアクセス条件を確認する。人間によるコード審査やログの共有判断をテストで代行したとは扱わない。自動試験が扱うのは生成したダミー値と公開依存だけで、配備済み秘密の読取り・コピー、実値サービスの呼出し、利用者設定の配備は行わない。

## Verification Matrix

| #274 の AC                                                         | 検証・結果                                                                                                                                                              |
| ------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1: 公開 with-env の parser・優先順位・argv・終了コード・失敗時停止 | `WITH_ENV_REAL_NIX=1 bats tests/with-env.bats tests/claude-devshell-env.bats`: 29 成功。実 Nix app と raw 内 package を含む。                                           |
| 2: #271 の入口で秘密なし・ダミー値・通常操作                       | `tests/human-validation.bats` の実 namespace、公開 fixture・ダミー値テスト、commit・返却。WSL2 成功。6テンプレートの実 raw 起動・public package・commit・再起動も成功。 |
| 3: 固定版・コード／秘密／出力の分離条件                            | runtime の手順と6言語の独立利用案内。SHA・依存・コマンドの確認、共有 mount／制御／認証経路の禁止を明示。                                                                |
| 4: 人間が確認した結果だけ共有                                      | 同手順に未確認ログ・成果物の自動送信禁止を記載。fixture は非公開結果を別保存し、公開要約だけを返す。                                                                    |
| 5: ダミー別環境への継続編集・取得拒否                              | WSL2 の公開 CLI による並行実行・read／write 拒否と固定版・出力保持に成功。Linux VM でも成功。                                                                           |
| 6: dotfiles と6テンプレート、envrc 不要／非自動実行                | 公開利用例を更新。6言語独立 repo の実 Nix と raw 起動がすべて成功。envrc 不在でも実行でき、存在時も自動実行しない。                                                     |
| 7: 旧 secret 継承・read 期待の移行、Claude 回帰                    | 旧 dotenv grant を用いたテストを、grant なしの deny と公開 `.env.example` 読取りに変更し成功。Claude の10ケースも成功。                                                 |
| 8: Linux／WSL2 の移行・対象・初期化・再起動・未確認事項            | 新手順と下記の OS ごとの記録。既存 repo を一括変更せず、live source への配備は実施しない。                                                                              |

## 実行環境と再現

WSL2 kernel `6.18.33.2-microsoft-standard-WSL2`、Nix 2.34.6、Codex 0.153.4、Git 2.54.0、bubblewrap 0.11.2。repo の `nix develop .#wsl` で Python 3.13.13（python-dotenv 同梱）と Bats 1.12.0 を使う。

```bash
nix develop .#wsl
bats tests/human-validation.bats
WITH_ENV_REAL_NIX=1 bats tests/with-env.bats tests/claude-devshell-env.bats
python3 tests/helpers/template-with-env.py
python3 scripts/secret-isolation-linux-vm.py --output /tmp/issue-274-linux-vm-new
TMPDIR=/tmp SECRET_ISOLATION_REAL_RUNTIME=1 bun run test
bunx tsc --noEmit
```

専用 VM へ渡す repo 入力は既存の `linux-vm.nix` の明示リストに今回の Bats・fixture・helper を追加したもの。host HOME・store の共有は行わない。実モデル・認証サービスの opt-in はこの変更では有効にしない。

証跡は `/tmp/issue-274-verification/` に保存する。`with-env-claude.log` は29件成功、`human-wsl-final.log` は新しい2環境 fixture、`templates-final.log` は6言語の結果。全 Bats はファイルを重複なく4群へ分け、各群内を逐次実行する。結果は `full-0.log` ～ `full-3.log` と `full-manifest.json` に記録する。GNU parallel が無いため Bats の `--jobs` 入口ではテストが開始せず、その後に Python の subprocess で4群を実行した。

全 Bats は675件を実行し、初回は661成功・10 opt-in skip・4失敗だった。4失敗は継承した長い `TMPDIR` による `AF_UNIX path too long` で検証本体に到達していなかった。`TMPDIR=/tmp SECRET_ISOLATION_REAL_RUNTIME=1 bats tests/secret-isolation.bats` で該当ファイル5件すべてが成功した（`secret-isolation-retry.log`）。初回結果を上書きせず、再実行を合わせて665件成功・10 opt-in skip と記録する。opt-in のうち公開 with-env 2ケースは上記29件で別途成功し、6言語の opt-in も別途すべて成功した。

最終コードの Linux VM は `/tmp/issue-274-linux-vm-final/` に記録し、exit 0。別 kernel `6.18.33`、通常ユーザー uid 1000 で共通 runtime probe が成功し、Bats は worktree 6成功・3 opt-in skip、raw（今回の人間境界を含む）31成功・2 opt-in skip、service 境界9成功・2 opt-in skip。実認証サービスの opt-in は有効にしていない。

6言語の独立 repo 検証は `/tmp/template-with-env-258-xnkavmlw/` と `templates-final.log` に記録し、exit 0。Go・Rust・Elixir・Perl・Gleam・Bun の全てで3 system の app／devShell を評価し、WSL2 の x86_64 Linux バイナリを実行した。dotenv の人間向け契約、Nix 出力・cache へのダミー値非混入、失敗時停止、envrc 非自動実行、worktree 選択、明示 output と WSL 選択、実 raw 入口のダミーテスト・Git commit・再起動が成功。root dotenv が Codex の空 placeholder になる場合は、読取り結果が空であることと、ホスト側の非空ファイルが保持されることを照合する。別名の非公開ファイルは読取り失敗を要求する。

生成した6 lock の nixpkgs は `104a7c61006cd22d11c0379663afee90c62273ab`、共通 dotfiles は上記 `b4931c5`。Rust の rust-overlay は `5280ed136f4359ce3f977b0c4c4dab6a34254201`。

テンプレート6言語の実起動は WSL2、別 Linux kernel は上記の共通入口・人間境界 fixture で検証した。Linux VM 内で6言語を全て再実行したわけではない。macOS raw は未対応、ARM／macOS のテンプレートは評価と実行を区別する。実値検証、人間のレビュー判断、対象外ランタイムの非開示保証は検証対象に含めない。

## レビューと静的検証

固定点 `6412429243a4326fa2fc748eae445f35f10fcdc9` から実装 commit `fb5d7d446302933dbb085a5e6e6ca87616c2122f` までを独立した Standards／Spec の2軸でレビューし、いずれもコード上の指摘は0件。実行中だった検証は上記の証跡で完了を確認した。TypeScript typecheck、変更 Python の Ruff check／format、追加 Bats の ShellCheck、変更 Nix の nixfmt check、Markdown format、ローカル文書リンク、`git diff --check`、通常の commit hook が成功した。
