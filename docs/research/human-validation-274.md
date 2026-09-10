---
type: research
title: Issue 274 秘密なし開発と人間の実値検証の分離
description: 公開 with-env の回帰、固定コードと出力の分離、6言語テンプレートの移行
tags: [nix, codex, dotenv, verification]
---

# Issue #274 の検証記録

2026-09-10。[#274](https://github.com/treflebonbon/dotfiles/issues/274)、親 [#268](https://github.com/treflebonbon/dotfiles/issues/268)。開始点は `63e47ffc471ff5e01f58a8a268ea553b0c9ab976`。依存 [#271](raw-codex-isolation-271.md) の共通入口を変更せず、公開入口の回帰検証と利用手順・テンプレートの移行を行った。未 merge の source から利用者設定を配備していない。

以下の「変更と入力」から「適用と未確認事項」は PR #284 の実装・検証時点の記録。後半に PR #285 の独立した検証と統合後の結果を記載する。

## 変更と入力

README と runtime、6言語の独立した `DEVELOPMENT.md` に、秘密なしの AI 操作と人間の実値検証を記載した。人間はコード・依存・初期化処理・実行コマンドを確認して完全な SHA に固定し、Codex がアクセスできない別環境にコード・秘密・出力を置く。検証結果は人間が確認して必要な要約だけを手動共有する。正本は[人間による実値検証](../../runtime/shell-environment.md#人間による実値検証)。旧 #257／#258 記録には現行手順への案内を追加した。

6テンプレートの共通 dotfiles input を、旧 `002085017c4260e3044156ab474823dad3bd1378` から、#271 を含む merge 済みの開始点へ揃えた。言語用 nixpkgs の系統・follows・公開 app 名・devShell・任意の `.envrc` は維持する。利用者の既存 repo や lock を一括変更する処理は追加していない。

`tests/human-validation.bats` は実 Nix、公開 `with-env` package、`codex-worktree sandbox` を使う。Nix／Codex を mock しない。人間側も列挙した公開ツール環境から起動し、任意の host 変数は渡さない。専用 HOME の設定は管理 template からレンダリングし、公開のテストコード・Git 履歴・通常変数・JSON fixture だけを raw 入口へ登録する。プロジェクト秘密や外部サービスの認証は使用しない。

## 分離検証

1. 公開 commit を `git archive FULL_SHA` で独立した人間側ディレクトリに展開し、共有 object directory のない Git root を作る。
2. 人間側だけにダミーの `.env` と出力を置き、公開 `with-env` から固定版の検証コードを実行して待機させる。
3. 同時に共通 raw 入口から Codex の実 sandbox を起動する。通常変数と JSON fixture、明示したダミー変数を使ってテストし、コードを変更・compile・再テストする。
4. Codex の子が人間側コード・dotenv・出力と `/proc/<human-pid>/environ`、`/proc/<human-pid>/root` を、通常 command と `with-env --prepared` の両方から read／write open する。値が表示されないだけで成功とせず、OS の拒否を判定する。
5. 人間側の検証を再開し、固定したソースが変わっていないことと、ダミー値を含む出力の生成を確認する。Codex 側で完成後の出力も再び read／write できないことを確認して commit・返却する。返却した commit の内容と、人間側の固定ファイル・秘密・出力の保持を確認する。

この fixture の人間側は共通 raw namespace の外側にあり、検証 controller が両側のダミー結果を検査する。現在の任意の agent session や、別ディレクトリという配置自体への非開示保証ではない。本番では別マシン／独立 VM 等のアクセス条件を人間が確認する。実値、外部サービス、本番 CI、秘密の自動送信の検証は行わない。

## 実行記録

Session Scratchpad が提示されていないため、証跡は `/tmp` を明示 fallback として使用した。

- WSL2: `nix develop .#wsl -c bats tests/human-validation.bats` で分離ケース成功。kernel `6.18.33.2-microsoft-standard-WSL2`、Nix 2.34.6、Codex 0.153.4、bubblewrap 0.11.2、repo devShell の Python 3.13.13 を使用。
- 6言語: `nix develop .#wsl -c python3 tests/helpers/template-with-env.py` で Go／Rust／Elixir／Perl／Gleam／Bun すべて成功。6個の生成 lock が新しい完全 SHA を指すことも確認した。証跡は `/tmp/template-with-env-258-kspy5vz4/commands.log` と各 repo の lock・Nix 出力。3 system を評価し、x86_64 WSL2 で実行した。
- Linux VM: `nix develop .#wsl -c python3 scripts/secret-isolation-linux-vm.py --human-validation --output /tmp/human-validation-274-linux-verified`。分離ケース成功。証跡は同ディレクトリの `test.log` と `evidence/human-tests.log`。VM は列挙した CLI closure と fixture だけの image を使い、host HOME／store を共有しない。kernel `6.18.33`、通常ユーザー uid 1000、外部サービスへのネットワークは無効。
- 全 Bats: `WITH_ENV_REAL_NIX=1 SECRET_ISOLATION_REAL_RUNTIME=1` と公開 CA を指定し、全677ケースを重複なく4群に分けて各群内は逐次実行。初回663成功・9 opt-in skip・5失敗。`/tmp/human-validation-274-suite/manifest.json` と各 log に初回結果を保持した。

初回失敗の4件は既存 `secret-isolation.bats` の UNIX socket が入れ子の `TMPDIR` でパス長上限を超えたもの。`nix develop .#wsl -c env TMPDIR=/tmp SECRET_ISOLATION_REAL_RUNTIME=1 bats tests/secret-isolation.bats` で5ケースすべて成功した。残る既存 dogfood annotation の1件も `TMPDIR=/tmp` の個別再実行で成功したが、初回の原因は未確定として区別する。再実行結果は `secret-isolation-short-path.log`・`dogfood-recheck.log` と `rechecks.json` に記録し、失敗を skip や期待値変更で回避していない。

全体実行で skip した9件のうちテンプレート1件は上記の6言語実行で別途完了した。他の8件は実 Herdr、hosted model、認証済み GitHub／管理 MCP、追加の network probe で、この移行では再実行していない。新規分離ケース、公開 `with-env` package の実 Nix 実行、Claude の非秘密環境起動は全体実行内で成功している。TypeScript typecheck、変更 Python の Ruff、Nix format、`git diff --check`、通常の commit hook も成功した。

`2104b6b` を Standards／Spec の独立サブエージェントでレビューし、標準違反0件・仕様finding0件。Standards の命名に関する判断事項1件を採用し、fixture の CLI closure を示す変数を `bash_root`／`coreutils_root`／`python_root` に明確化した。上記実測の後に行った実行コードの変更はこの名前変更だけで、Ruff と Python compile で確認した。

## Verification Matrix

| Issue #274 の受入条件 | 検証 | 結果 |
| --- | --- | --- |
| 1: 人間向け公開入口と dotenv 契約 | `tests/with-env.bats`、実 Nix package。解析・既存変数優先・引数・終了コード・失敗時未起動 | 成功 |
| 2: Codex の秘密なし開発 | `tests/devshell-env.bats`、`tests/raw-codex-integration.bats`、新規分離ケース。通常変数・JSON fixture・ダミー変数・編集・compile・test・commit | 成功 |
| 3: 固定コード・秘密・出力を別環境へ分離 | runtime と6言語ガイドに完全 SHA、非共有コード、制御経路を含む実行条件を記載。新規ケースで固定コードと並行編集を確認 | 成功 |
| 4: 人間が必要な結果だけを共有 | 人間による確認と手動共有を明記。秘密注入サービス・未確認ログの自動送信を追加していない | 文書・差分確認 |
| 5: ダミー値で分離を実測 | 実共通入口から人間側の read／write 拒否、固定コード・秘密・完成後出力の保持を WSL2 と Linux VM で確認 | 成功 |
| 6: dotfiles と6言語の公開利用例 | 独立 repo の3 system 評価と WSL2 実行。`.envrc` 不在・副作用を持つ既存ファイルの両方を確認 | 成功 |
| 7: 旧期待値・案内の移行、対象外 runtime 維持 | README／旧検証記録／runtime を更新。現行 raw、dotenv、Claude の既存テストを回帰実行 | 成功 |
| 8: Linux／WSL2 の移行・境界 | 新規実測と #271 の起動・復旧案内を接続。既存 repo、配備済み秘密、実値サービスを操作していない | 成功・未確認事項は下記 |

## 適用と未確認事項

受入・merge 後に live source から配備し、新しい端末で公開ファイル・到達可能履歴を確認して `trust`／`admit`、`codex-worktree` を起動する。flake・lock・import を変えたら確認・再登録・再起動する。初期化失敗は非0終了し、秘密なしの入力を修正して正式入口から再試行する。詳細な導入条件・専用 store の初回準備・保持された session の復旧は [raw 共通入口](../../runtime/shell-environment.md#raw-codex-のプロジェクト開発環境)を参照。

既存セッション、直接 Codex、Desktop、Orca／Herdr native 起動、macOS raw の非開示保証には拡張しない。6テンプレートの3 system の評価は実機での実行とは区別する。ARM Linux／macOS の実行、人間の実値サービス・CI、本番別環境の運用は未検証。Claude は既存の非秘密 devShell 起動を回帰確認し、dotenv 注入や新しい OS sandbox は追加しない。

## PR #285 の統合前の検証

この節は `fb5d7d4`・`10b08be` の記録であり、当時の input revision・コマンド・件数を保持する。現在の実装と統合後の検証は次節を参照。

2026-09-10。[#274](https://github.com/treflebonbon/dotfiles/issues/274)、親 [#268](https://github.com/treflebonbon/dotfiles/issues/268) の移行・検証記録。共通入口は受入済み [#271](raw-codex-isolation-271.md) の `codex-worktree`。利用方法の正本は [人間の実値検証手順](../../runtime/human-validation.md)。

### 変更と確認する境界

人間向け公開 `with-env` の実装・注入契約は維持する。README、runtime の案内、独立して展開される6言語の `DEVELOPMENT.md` に、公開入力・ダミー値での AI 開発と、確認済み固定版を別環境で実行する手順を揃えた。6テンプレートの共通 package input は #271 の merge commit `b4931c5e0d2152e8fb89eba01b3ac130597e55b3` に固定し、言語用 nixpkgs は引き続き `follows` で共有する。

`tests/human-validation.bats` は一時 repo で公開ファイルだけを commit・admit し、実 Nix と実 Codex の `codex-worktree sandbox` を起動する。人間役はその SHA の Git bundle から独立 clone を作り、公開 `devshell-env with-env` で実 Nix を準備してダミー値を注入する。実行ごとに作るダミー秘密は、raw へ登録するコードには含めない。

人間役が待機中に raw 側は公開 fixture・通常変数・ダミー値でテストし、コードと fixture を変更して commit する。raw の通常 Python と `with-env --prepared` の子は、人間側のコード・dotenv・ログ・成果物と host PID の環境／root を `open` の read／write で取得できないことを検証する。人間側の結果生成後も試行し、元の SHA・ファイル内容・秘密・出力を保持する。隔離外で同じ probe をダミー dotenv に向けると失敗する対照試験により、単に値がログに出なかっただけの判定を避ける。

この fixture の人間役は raw namespace の外にある専用ディレクトリと別プロセスであり、汎用の VM 構築・実値実行サービスではない。実利用では人間が独立 VM／別マシンのアクセス条件を確認する。人間によるコード審査やログの共有判断をテストで代行したとは扱わない。自動試験が扱うのは生成したダミー値と公開依存だけで、配備済み秘密の読取り・コピー、実値サービスの呼出し、利用者設定の配備は行わない。

### Verification Matrix

| #274 の AC | 検証・結果 |
| --- | --- |
| 1: 公開 with-env の parser・優先順位・argv・終了コード・失敗時停止 | `WITH_ENV_REAL_NIX=1 bats tests/with-env.bats tests/claude-devshell-env.bats`: 29 成功。実 Nix app と raw 内 package を含む。 |
| 2: #271 の入口で秘密なし・ダミー値・通常操作 | `tests/human-validation.bats` の実 namespace、公開 fixture・ダミー値テスト、commit・返却。WSL2 成功。6テンプレートの実 raw 起動・public package・commit・再起動も成功。 |
| 3: 固定版・コード／秘密／出力の分離条件 | runtime の手順と6言語の独立利用案内。SHA・依存・コマンドの確認、共有 mount／制御／認証経路の禁止を明示。 |
| 4: 人間が確認した結果だけ共有 | 同手順に未確認ログ・成果物の自動送信禁止を記載。fixture は非公開結果を別保存し、公開要約だけを返す。 |
| 5: ダミー別環境への継続編集・取得拒否 | WSL2 の公開 CLI による並行実行・read／write 拒否と固定版・出力保持に成功。Linux VM でも成功。 |
| 6: dotfiles と6テンプレート、envrc 不要／非自動実行 | 公開利用例を更新。6言語独立 repo の実 Nix と raw 起動がすべて成功。envrc 不在でも実行でき、存在時も自動実行しない。 |
| 7: 旧 secret 継承・read 期待の移行、Claude 回帰 | 旧 dotenv grant を用いたテストを、grant なしの deny と公開 `.env.example` 読取りに変更し成功。Claude の10ケースも成功。 |
| 8: Linux／WSL2 の移行・対象・初期化・再起動・未確認事項 | 新手順と下記の OS ごとの記録。既存 repo を一括変更せず、live source への配備は実施しない。 |

### 実行環境と再現

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

### レビューと静的検証

固定点 `6412429243a4326fa2fc748eae445f35f10fcdc9` から実装 commit `fb5d7d446302933dbb085a5e6e6ca87616c2122f` までを独立した Standards／Spec の2軸でレビューし、いずれもコード上の指摘は0件。実行中だった検証は上記の証跡で完了を確認した。TypeScript typecheck、変更 Python の Ruff check／format、追加 Bats の ShellCheck、変更 Nix の nixfmt check、Markdown format、ローカル文書リンク、`git diff --check`、通常の commit hook が成功した。

## PR #285 の統合後の検証

`main` の `ab0c8517d4e912928a10949db05bceaa68ea8e19`（PR #284）を取り込み、同じ #274 の変更を統合した。テンプレート input は #284 の `63e47ffc471ff5e01f58a8a268ea553b0c9ab976` を維持する。Herdr の統合と VM runner の `--herdr`／`--human-validation`／通常モードは main 側を保持し、人間検証 fixture は専用モードで実行する。

人間側は公開 Nix package の `with-env` を、列挙した公開環境変数だけで起動する。固定版の受渡しは Git bundle からの独立 clone と SHA の照合に揃え、毎回異なるダミー秘密・非公開ログ・出力を保持する。隔離外の対照試験で取得可能性を検出し、隔離内では通常 Python と `with-env` の両方から read／write を拒否する。raw 側の編集後の compile・再テスト・commit と、完成後の人間側出力への再試行も組み合わせた。案内は archive と独立 clone の両方を残し、詳細なアクセス条件を `runtime/human-validation.md` に集約した。

- WSL2: `nix develop .#wsl -c env TMPDIR=/tmp bats tests/human-validation.bats` で最終版1件成功。`human-wsl-final.log` に記録した。終了後の envrc 非実行と人間側出力の非返却も確認する。
- Linux VM: `nix develop .#wsl -c env TMPDIR=/tmp python3 scripts/secret-isolation-linux-vm.py --human-validation --output /tmp/issue-285-merge.hFygDA/linux-vm-final` は exit 0、分離ケース1件成功。
- 回帰: `TMPDIR=/tmp WITH_ENV_REAL_NIX=1 bats tests/with-env.bats tests/claude-devshell-env.bats tests/herdr-codex-isolation.bats` と `TMPDIR=/tmp bats --filter 'Codex config migration keeps dotenv denied' tests/codex-config.bats` は計31件成功・実 Herdr の opt-in 1件 skip。`regressions.log` に記録した。
- 静的確認: TypeScript typecheck、変更 Python の Ruff check／format、Bats の ShellCheck、Nix format、Markdown format、ローカル文書リンク35件、差分の whitespace check が成功。

証跡の保存先は `/tmp/issue-285-merge.hFygDA/`。Session Scratchpad が提示されていないため `/tmp` へ保存した。上記は統合後に必要な範囲を再検証した結果であり、統合前の全 Bats の件数と合算しない。実シークレット、実値サービス、実モデル・認証サービスの追加 opt-in は実行しない。

6言語の再検証では、新規 `nix flake lock` が GitHub API のレート制限（HTTP 403）で停止した。通常実行は `templates.log`、cache TTL を変えた再試行は `templates-cached.log` に残した。`--reference-lock-file` だけでは生成先に lock が作られず停止した準備ログも `templates-pinned.log` に保持する。

そのため、#284 の `/tmp/template-with-env-258-kspy5vz4/` にある検証済みの公開 lock を、新たに展開した各 repo へ置いてから元の `nix flake lock` を実行した。調整は一時 harness `templates-with-reference-locks.py` に限定し、リポジトリのテスト本体・期待値は変えていない。この実行は検証済み revision での回帰確認であり、現在の branch から新規 lock を解決する経路はレート制限により未確認として残す。

検証済み lock を使った最終実行は `templates-pinned-final.log` に記録し、exit 0。Go・Rust・Elixir・Perl・Gleam・Bun の6言語すべてで、3 system の評価、公開 devShell／with-env の人間向け契約、envrc 非自動実行、実 raw 起動・public app・ダミーテスト・commit・再起動が成功した。展開先は `/tmp/template-with-env-258-t63_aj_p/`。生成された全6 lock の dotfiles は `63e47ffc471ff5e01f58a8a268ea553b0c9ab976`、nixpkgs は `104a7c61006cd22d11c0379663afee90c62273ab`、Rust overlay は `5280ed136f4359ce3f977b0c4c4dab6a34254201` と照合済み。

統合後の6言語の実行は WSL2 x86_64 Linux。Linux VM では専用の人間境界 fixture を実行し、6言語すべてを再実行したものではない。ARM／macOS の評価と実機実行も区別する。
