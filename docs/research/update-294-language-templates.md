# #294: 6言語テンプレートの候補と検証

調査日: 2026-09-10。対象は [#294](https://github.com/treflebonbon/dotfiles/issues/294)、親仕様は [#283](https://github.com/treflebonbon/dotfiles/issues/283)。両 issue の本文とコメントを取得した（コメントは両方0件）。親の Testing Decisions に従い、公開テンプレートから独立生成した repo の lock・devShell・with-env・言語起動を検証境界とする。

**全6言語の必須実Nixゲートが成功。Rust1.98.1とGleam＋OTP29を採用し、Go1.27は実lint非互換のため保留する。** worker のソケット制約による失敗は、候補自体の互換性不良や保留理由に転用しない。root flake / npm / user devShell / 共有テスト / runtime 文書、コミット・PR・配備は別担当。

## 固定した取得元

入口で1回確認した候補を以下に固定し、検証中に HEAD を追わない。

| 対象 | revision | 位置付け |
| --- | --- | --- |
| 既存 stable channel `nixpkgs-26.05-darwin` | `104a7c61006cd22d11c0379663afee90c62273ab` | [候補](https://github.com/NixOS/nixpkgs/tree/104a7c61006cd22d11c0379663afee90c62273ab)。2026-09-09T15:04:08Z |
| 既存 `oxalica/rust-overlay` | `5280ed136f4359ce3f977b0c4c4dab6a34254201` | [候補](https://github.com/oxalica/rust-overlay/tree/5280ed136f4359ce3f977b0c4c4dab6a34254201)。2026-09-09T07:15:53Z |
| 全6テンプレートの共通 with-env | `63e47ffc471ff5e01f58a8a268ea553b0c9ab976` | 初回単位では0020850…を維持。main #284/#285取込み後は受入済み63e47ffを保持し、下記の全6言語gateを再実行 |
| #258 の生成 lock の nixpkgs | `555cb0f648dd138a7a3c250f4f4928767707c988` | [過去の実行記録](template-with-env-258.md)からの比較値。この実行で生成した lock ではない |
| #258 の生成 lock の rust-overlay | `6ae57a71bcb0bebc7a66cc2bd76942c4cf649167` | 同上 |

テンプレートは生成先で `flake.lock` を持ち、user devShell の lock を利用しない。検証用 revision 指定は `TEMPLATE_WITH_ENV_NIXPKGS_REV` / `TEMPLATE_WITH_ENV_RUST_OVERLAY_REV` から既存 `nix flake lock --override-input` へ渡す。テンプレート自体の channel URL、共通 input の `follows`、取得経路を変更するものではない。新規 override package / installer は導入しない。

## 言語の棚卸し

現行・候補の package version は、固定した上記 nixpkgs / overlay を使う読み取り専用の属性評価で確認した。3 system（x86_64-linux / aarch64-linux / aarch64-darwin）の値は一致した。**package metadata の評価であり、独立生成 repo の flake check、build、実バイナリの起動成功とは区別する。**

| テンプレート | 着手時の selector と解決版 | 上流 stable / 既存経路の候補 | 採否 |
| --- | --- | --- | --- |
| Go | `go_1_26` → 1.26.7 | [公式 1.27.1](https://go.dev/doc/devel/release)、同 channel の `go_1_27` → 1.27.1。旧系列の公式最新は1.26.8だが選択属性は1.26.7 | 1.27.1は実lintの不一致で保留。`go_1_26`を維持し、同じ統合検査で再検証 |
| Rust | `rust-bin.stable."1.98.0".default` → 1.98.0 | [公式 1.98.1](https://blog.rust-lang.org/2026/09/03/Rust-1.98.1/)。固定 overlay の `stable."1.98.1".default` で解決 | vtable の RED→GREENを確認し1.98.1採用 |
| Elixir / Erlang | `beam29Packages.elixir_1_20` → 1.20.4、`beam29Packages.erlang` → 29.0.6 | [Elixir 1.20.4](https://github.com/elixir-lang/elixir/releases/tag/v1.20.4)、[OTP 29.0.6](https://github.com/erlang/otp/releases/tag/OTP-29.0.6) と一致 | selector維持。組み合わせの実起動PASS |
| Gleam | `gleam` → 1.18.1、`erlang` → 28.5.0.6 | [Gleam 1.18.1](https://github.com/gleam-lang/gleam/releases/tag/v1.18.1) と一致。既存 `beam29Packages.erlang` → OTP 29.0.6 も選択可能 | `rand:shuffle/1` の RED→GREENを確認しOTP29採用 |
| Perl | `perl` → 5.42.0、`perlnavigator` → 0.6.3 | [公式 5.44.0](https://www.perl.org/get.html)。固定 channel の `perlInterpreters` は `perl5` だけで、版は5.42.0。5.44用の別属性なし | 5.42.0維持候補、5.44.0は既存経路未収録で保留。PerlNavigatorとの実起動PASS |
| Bun | `bun` → 1.3.13 | [公式 1.4.2](https://github.com/oven-sh/bun/releases/tag/bun-v1.4.2)。固定 channel の既存 `bun` は1.3.13 | 1.3.13維持候補、1.4.2は既存経路未収録で保留。Bun / typescript-language-server起動PASS |

既存 channel の `nodejs = nodejs_24` は24.19.0。Node 26への変更を行わない。

### 周辺ツール

以下も同じ固定 revision の3 systemで評価した package version。実行の証跡は後述の結果に追記する。

| 言語 | ツールと版 |
| --- | --- |
| Go | gopls 0.22.0、air 1.65.2、gotests 1.9.0、gomodifytags 1.17.0、delve 1.26.3、golangci-lint 2.12.2、ko 0.18.1、wire 0.7.0、goreleaser 2.15.4、impl 1.5.0、oapi-codegen 2.5.1、sqlc 1.31.1、gofumpt 0.10.0 |
| Rust | rust-analyzer 2026-06-01、bacon 3.23.0、cargo-nextest 0.9.136、sqlx-cli 0.8.6、cargo-audit 0.22.1 |
| Elixir | Expert 0.1.5、OTP 29.0.6 |
| Gleam | 現行 OTP 28.5.0.6、候補 OTP 29.0.6 |
| Perl | PerlNavigator 0.6.3 |
| Bun | typescript-language-server 5.3.0 |

Go 周辺ツールの `go.version` はすべて1.26.7だった。特に [gopls](https://github.com/NixOS/nixpkgs/blob/104a7c61006cd22d11c0379663afee90c62273ab/pkgs/by-name/go/gopls/package.nix) は `buildGoLatestModule` を使うが、この channel の `go_latest` は1.26.7。[golangci-lint](https://github.com/NixOS/nixpkgs/blob/104a7c61006cd22d11c0379663afee90c62273ab/pkgs/by-name/go/golangci-lint/package.nix) は `buildGo126Module` を使う。[公式 FAQ](https://golangci-lint.run/docs/welcome/faq/) はビルドに用いた Go 以下をサポート範囲としている。このため compiler の属性変更だけで1.27互換とは判断できない。

coordinatorが `go_1_27` のテンプレートから独立生成したrepoを同じhelperで検証したところ、`go version go1.27.1 linux/amd64`、`go test ./...`、`gopls check smoke.go` までは成功した。一方、`golangci-lint run --no-config ./...` は、ビルド時のGo1.26がmoduleのtarget1.27.1より古いという理由でexit 3になった。ログ `tmp/update-283/template-go-candidate.log` をworkerからも確認した。証跡は coordinator の `/tmp/nix-shell.2VWWVm/nix-shell.rF4HE8/template-with-env-258-4y_v2o2y/commands.log`。

親 AC2 / AC17 に従い、既存の互換単位 `go_1_26` と周辺ツールを維持する。既存candidate repoのmodule targetを下げる変更、lint無効化、新規compiler/package overrideは行わない。helperの生成moduleによるtest/check/lintも変更せず、維持するGo1.26テンプレートから別の新規repoを生成してbaseline側の成功を確認する。Go1.27の再評価条件は、同じ配布経路で同梱ツールが対応すること、または新規overrideの必要性が別途承認されることとする。

Elixir の [固定 channel 定義](https://github.com/NixOS/nixpkgs/blob/104a7c61006cd22d11c0379663afee90c62273ab/pkgs/development/interpreters/elixir/1.20.nix) は OTP 27–29 を受理する。[Gleam の公式互換表](https://gleam.run/documentation/compatibility-reference/) は1.18以降で OTP 28 / 29をサポートする。GleamのOTP 29候補は既存 `beam29Packages.erlang` の選択であり、channel / package取得経路の追加ではない。

## TDD と検証コマンド

Rust の検査は [上流の最小再現](https://github.com/rust-lang/rust/issues/161441#issuecomment-5381883955)を `tests/helpers/template-rust-vtable.rs` に置き、独立生成repoへコピーしてdevShell / with-envの両方からコンパイル・実行する。safe Rust の動的 dispatch が正常に戻ることを検査する。version文字列だけのテストではない。

Rust red 用（テンプレート1.98.0の状態）:

```bash
TEMPLATE_WITH_ENV_NIXPKGS_REV=104a7c61006cd22d11c0379663afee90c62273ab \
TEMPLATE_WITH_ENV_RUST_OVERLAY_REV=5280ed136f4359ce3f977b0c4c4dab6a34254201 \
python3 tests/helpers/template-with-env.py --language rust
```

coordinator の実行で `rustc 1.98.0 (88d9e12ae 2026-08-18)` によるコンパイル後の `./vtable` が `exit -11`（SIGSEGV）となった。ログ `tmp/update-283/template-rust-red.log` をworkerからも確認した。証跡は coordinator の `/tmp/nix-shell.2VWWVm/nix-shell.rF4HE8/template-with-env-258-f_wmjbwf/commands.log`。この red を受けてRustの選択版を1.98.1へ変更した。lock取得・build失敗を red に数えていない。

Gleam は外部dependencyのない生成projectをコンパイルし、[OTP 29で追加された `rand:shuffle/1`](https://www.erlang.org/patches/OTP-29.0)をGleamのErlang FFIから呼び、singleton listが保たれることを検査する。coordinatorが以下をOTP 28の状態で実行した:

```bash
TEMPLATE_WITH_ENV_NIXPKGS_REV=104a7c61006cd22d11c0379663afee90c62273ab \
python3 tests/helpers/template-with-env.py --language gleam
```

`gleam 1.18.1` でコンパイル後、実行時に `rand.shuffle` 未定義で exit 1 になった。ログ `tmp/update-283/template-gleam-red.log` をworkerからも確認した。証跡は coordinator の `/tmp/nix-shell.2VWWVm/nix-shell.rF4HE8/template-with-env-258-o9bcy192/commands.log`。この red の後で、既存 `beam29Packages.erlang` を選ぶよう変更した。

Go候補は同じhelperの `--language go` で確認する。生成したmoduleを `go test`、`gopls check`、`golangci-lint run --no-config` に通し、compilerと周辺ツールの組み合わせで採否を決める。Rustはvtable回帰に加え、生成Cargo projectのoffline test / nextest / clippy / fmtを確認する。変更のない言語に新たな動作要件を追加せず、既存version起動と周辺ツールの公開version/helpを使う。PerlNavigator 0.6.3は[公開entryにversion/helpがない](https://github.com/bscan/PerlNavigator/blob/v0.6.3/server/src/server.ts)ため、`perlnavigator --stdio </dev/null` による起動確認を行う。LSPプロトコルの検証や新しいclientは追加しない。

### CLI 起動の終了仕様

全6言語ゲートの初回は、Go1.26.7のproject test / gopls check / golangci-lintが成功した後、`impl -h` の終了コード2をhelperが0と誤認して停止した。ログは `tmp/update-283/templates-all-green.log`、証跡は coordinator の `/tmp/nix-shell.2VWWVm/nix-shell.rF4HE8/template-with-env-258-uns59toi/commands.log`。言語の回帰ではなくテストの期待値不良として記録する。

再実行前に固定版の上流entryを確認した（候補のlatest再取得は行っていない）。

| コマンド | 上流で確認した終了仕様・helperの扱い |
| --- | --- |
| `impl -h` | [1.5.0のusage実装](https://github.com/josharian/impl/blob/v1.5.0/impl.go#L625)はstderrへhelpを出してexit 2。この呼び出しに限りexit 2と `impl [-dir directory] <recv> <iface>` の出力を必須に修正 |
| `oapi-codegen -version` / `sqlc version` / `gofumpt -version` | [oapi-codegen](https://github.com/oapi-codegen/oapi-codegen/blob/v2.5.1/cmd/oapi-codegen/oapi-codegen.go#L114)、[sqlc](https://github.com/sqlc-dev/sqlc/blob/v1.31.1/internal/cmd/cmd.go#L74)、[gofumpt](https://github.com/mvdan/gofumpt/blob/v0.10.0/gofmt.go#L517)の表示後の正常終了を確認。期待値0を維持 |
| Rust周辺ツールのversion | [rust-analyzer](https://github.com/rust-lang/rust-analyzer/blob/2026-06-01/crates/rust-analyzer/src/bin/main.rs#L62)、[bacon](https://github.com/Canop/bacon/blob/v3.23.0/src/cli/mod.rs#L57)の正常終了、[cargo-audit](https://github.com/rustsec/rustsec/blob/cargo-audit/v0.22.1/cargo-audit/src/commands/audit.rs#L68)、[sqlx](https://github.com/launchbadge/sqlx/blob/v0.8.6/sqlx-cli/src/opt.rs#L16)のversion flagを確認。期待値0を維持。nextestは[固定版のoffline option](https://github.com/nextest-rs/nextest/blob/cargo-nextest-0.9.136/cargo-nextest/src/cargo_cli.rs)を使うproject実行で検証 |
| `expert --help` / `typescript-language-server --version` | [Expert](https://github.com/expert-lsp/expert/blob/v0.1.5/apps/expert/lib/expert/application.ex#L74)はhelp表示後 `System.halt(0)`。[TypeScript language server](https://github.com/typescript-language-server/typescript-language-server/blob/v5.3.0/src/cli.ts)はCommanderのversion flagを使用。期待値0を維持 |
| `perlnavigator --stdio </dev/null` | [固定lock](https://github.com/bscan/PerlNavigator/blob/v0.6.3/server/package-lock.json)のvscode-languageserver 7.0.0は[shutdown要求前のEOFでexit 1](https://github.com/microsoft/vscode-languageserver-node/blob/release/server/7.0.0/server/src/node/main.ts#L243)。この起動に限りexit 1と診断出力が空であることを必須に修正。プロトコルsessionの正常終了を検証したとは扱わない |

他のCLIの異常終了は引き続き失敗になる。Go1.27を保留としたproject target / lint条件も変更しない。

必須の全6言語ゲート:

```bash
TEMPLATE_WITH_ENV_NIXPKGS_REV=104a7c61006cd22d11c0379663afee90c62273ab \
TEMPLATE_WITH_ENV_RUST_OVERLAY_REV=5280ed136f4359ce3f977b0c4c4dab6a34254201 \
TEMPLATE_WITH_ENV_REAL_NIX=1 bats tests/template-with-env.bats
```

helper は `TMPDIR` を尊重し、evidence配下にHOME・XDG cache/config/data/state/runtimeを作り、Cargo / Rustup / Go / Mix / Hex / Bun / npmの保存先もそこへ向ける。Goの `GOTOOLCHAIN=local` により、選択toolchainの不足をネットワークからの自動取得で補わない。生成 lock とコマンドログ、3 system評価、実行version、dotenv / worktree / output選択 / lock不変の結果を記録する。shared full Batsはcoordinatorが直列に実施する。

## worker の実行結果と制約

host は WSL2 x86_64、kernel `6.18.33.2-microsoft-standard-WSL2`、Nix 2.34.6。worker専用セッションではGit metadataの参照先と配備済みスキルが見えず、Unix domain socket作成が拒否された。coordinatorは同じworktreeで通常のNixが利用可能と確認し、実Nixの検証を担当すると明示した。この境界を別storeや権限変更で迂回しない。

配備済みTDDスキルが見えなかったため、`apm.yml` の exact revision `6654f6b60cd9d5be8b54c6fafe44346dabeb3b76` の `skills/engineering/tdd/{SKILL,tests,mocking}.md` を GitHub API で読み、Herdrスキルは同梱 `herdr --skill` を読んだ。`HERDR_ENV=1` は確認したが、`herdr agent list` / `herdr pane current --current` は socket 作成で失敗した。

| コマンド / 検証 | 結果 | 意味 |
| --- | --- | --- |
| `gh issue view 283/294 --repo treflebonbon/dotfiles --json body,comments` | PASS | 仕様と承認済みseamを確認 |
| `gh api repos/NixOS/nixpkgs/commits/nixpkgs-26.05-darwin` / `repos/oxalica/rust-overlay/commits/master` | PASS | 候補revision固定 |
| `git status --short` / `git rev-parse --show-toplevel --git-dir --git-common-dir` | FAIL | このworkerからmetadata参照先が不可視。shared repoのGit状態はcoordinator管理 |
| `nix store ping --store daemon` | FAIL | `cannot create Unix domain socket: Operation not permitted` |
| 変更前 `TEMPLATE_WITH_ENV_REAL_NIX=1 bats tests/template-with-env.bats`（外側HOME/XDGを隔離） | FAIL: 1件失敗、skip 0、exit 1 | helperの固定 `/tmp` への `mkdtemp` が read-only filesystem で失敗。言語の検証開始前。`TMPDIR` を尊重するよう修正 |
| `nix eval --store dummy://` による属性調査 | FAIL | `addToStoreFromDump` 非対応。成功とは扱わない |
| `nix-instantiate --eval --strict --json --readonly-mode --store dummy:// inventory.nix` | PASS | 固定sourceの3 system package metadataのみ。coordinatorから境界について連絡を受ける前の調査。実Nix統合ゲートの代替にはしない |
| `ruff check tests/helpers/template-with-env.py` / `ruff format --check tests/helpers/template-with-env.py` / Python構文検査 | PASS | workerで実行可能な静的検証。CLI期待値の修正後もRuff通過 |
| `nix-instantiate --parse templates/{go,rust,elixir,gleam,perl,bun}/flake.nix`（各ファイル）/ `shellcheck tests/template-with-env.bats` | PASS | 全6テンプレートの構文と既存Batsの静的検査 |
| `oxfmt --check templates/{rust,gleam}/DEVELOPMENT.md docs/research/update-294-language-templates.md` | PASS | 変更したMarkdownのformat検査 |
| Rust1.98.0 vtable red | 期待したFAIL: SIGSEGV / exit -11 | coordinatorでコンパイル後のクラッシュを再現。workerがlog確認 |
| Gleam / OTP28 red | 期待したFAIL: exit 1 | coordinatorでコンパイル後の `rand.shuffle` 未定義を再現。workerがlog確認 |
| Go1.27.1候補 | FAIL: lint exit 3 | compiler / goplsの簡単な例は成功、golangci-lintのビルドGo版とmodule targetが不一致 |
| 全6言語green初回 | FAIL: impl help期待値不良 | Go1.26.7のproject / gopls / lintはPASS。上流仕様に合わせ、implと未到達のPerlNavigatorの起動期待値を個別修正 |
| Rust1.98.1 / Gleam + OTP29 green | PASS | 独立repoのdevShell / with-env双方でコンパイル・実行成功 |
| 全6言語の独立生成lock・3 system flake評価・devShell / with-env実行 | PASS | `tmp/update-283/templates-all-green-retry.log`、exit0、skip0 |
| ARM Linux / Apple Siliconの実機起動 | 未実施 | WSL hostからの評価とは区別 |

調査用scratchpadはセッション専用の指定を認識できなかったため、許可された `TMPDIR` の `/tmp/nix-shell.2VWWVm/nix-shell.kcIRxj/update-294-language-templates/` を使った。固定取得source、`inventory.nix`、`inventory.json` を保存した。このパスの寿命はworkerセッションに依存する。coordinatorの実Nix証跡パスと最終採否は次節に記録した。

## 最終のsource検証

coordinatorが2026-09-10に必須ゲートを実行し、6言語すべての独立生成・lock不変・3 system評価・devShell / with-env・dotenv・隔離・失敗時挙動・linked worktree・WSLと明示output選択を確認した。証跡は `/tmp/nix-shell.2VWWVm/nix-shell.rF4HE8/template-with-env-258-ituhlau0/`、実行結果は `tmp/update-283/templates-all-green-result.json` と `templates-all-green-retry.log`。

Go1.26.7のproject test / gopls / golangci-lint、Rust1.98.1のvtable回帰とCargo / nextest / clippy / fmt、Gleam1.18.1＋OTP29.0.6の生成project、その他の周辺CLI起動が成功した。Elixir1.20.4＋OTP29.0.6、Perl5.42.0、Bun1.3.13を維持する。ARM Linux / Apple Siliconは評価のみで実機実行とは扱わない。

同じsource状態でrepoのfull Batsはexit0（674件中643実行PASS、31件skip）だった。opt-inのこのテンプレート検証は上記の別実行でPASSしており、full suiteのskipを成功の代用にしない。最終二軸reviewと他更新単位を合わせた統合確認は [#295](update-295-integrated-acceptance.md) に記録した。

## main取込み後の再検証

PR #296 の統合時にmain `9e1ab06` をmergeし、6テンプレートの共通inputはmainで受入済みの `63e47ffc471ff5e01f58a8a268ea553b0c9ab976` となった。stable nixpkgs `104a7c6…` とrust-overlay `5280ed1…` の候補固定、Rust1.98.1、Gleam OTP29、Go1.26.7の採否は維持した。

`tmp/update-283/run-merge-templates.py` は短い隔離TMPDIRで `TEMPLATE_WITH_ENV_REAL_NIX=1 bats tests/template-with-env.bats` を実行し、全6言語が成功した（Bats 1/1、6/6言語、skip0、exit0）。各言語は独立repoで新規lockを生成し、3system評価・devShell/公開with-env・周辺CLI・既存の失敗条件に加え、mainの実codex-worktree入口からダミー値検証・commit・再起動まで通過した。証跡は `merge-templates.log` / `merge-templates-result.json`、独立repoは `/tmp/u283-template-2ujmqv0j/template-with-env-258-bwo00we_/`。

初回の0020850…を使った成功記録は上に保持する。main取込み後の全体回帰・2軸reviewは [#295](update-295-integrated-acceptance.md) を参照する。hostはx86_64 Linux/WSL2で、ARM実機・live配備は引き続き未実施。
