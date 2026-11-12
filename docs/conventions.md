---
type: concept
title: Conventions
description: コミット・lint・認証の規約
tags: [conventions, git, lint, lefthook]
---

# Conventions

- **コミット**: Conventional Commits 形式（`cog verify` で検証、`commit-msg` hook）。squash merge では PR タイトルが commit message になるので、PR タイトルも同じ形式にし、CI の [`conventional-commits`](../.github/workflows/ci.yml) が検査する
- **Linting / format**: lefthook `pre-commit` hook で自動実行（`lefthook.yml`）。pinact / shfmt / oxfmt / oxlint / ghalint / actionlint / shellcheck / gitleaks / typecheck の汎用品質ゲートと、指示ファイル変更時の `instruction-contract`
- **認証**: HTTPS + `gh auth git-credential`。SSH は不使用

## レビュー

Standards 軸の判断基準（機械的な check にできないもの）は [coding-standards.md](coding-standards.md) を読む。

削除・権限判定の変更では、承認された要件に照らし、検査不能な状態を接続コードから最終操作まで追う。読取り失敗・一部しか見えない状態・検査中の対象消失をどう扱うか、許可条件と拒否条件の両方をレビュー担当が確認する。

公開 skill plugin からの旧配備移行では、[ADR-0082](adr/0082-extract-local-skills-to-public-repository.md) の完全な現行状態照合を撤去直前に行い、既知の旧 baseline と一致しない項目は理由と path を残して保持する。receipt の過去成功や public payload との類似は撤去許可にならない。

sandbox・権限・秘密値の境界を守る入力検査（起動引数、設定の上書き、受け付ける path など）は、通すものを列挙する許可リストで書く。拒否リストは、まだ知らない設定キーや入力の形（改行で区切った別の設定など）で境界を外から広げられる。レビュー担当は、許可した値ごとに境界を広げないことを確認する（[ADR-0080](adr/0080-grant-reviewer-codex-read-only-git-metadata.md) の `-c` 検査が実例）。

確度ラベル（confirmed／inferred／unconfirmed）を使う文書では、レビュー担当が次を確認する。一般化は実測した条件・経路・件数の範囲に収まっていること。inferred・unconfirmed の項目を消すときは、解消・陳腐化・対象外化のどれによるかの根拠が書かれていること。

テストと、テストから起動するスクリプトは、他のテストファイルと並列に動く前提でレビューする（[ADR-0079](adr/0079-run-bats-files-in-parallel.md)）。直列では表に出ず、並列の負荷や順序で表に出る次の形を確認する。

- 資源はテストごとの領域（テスト節）に置く。テスト対象の仕様で共有が決まっている資源（`/tmp/codex` など）は、既に存在しても成功する形で作り、その後に種類と所有者を確かめる。「存在確認 → 作成」は競合する。
- 待ち時間・タイムアウトは負荷で延びる処理を見込み、production の既定値以上にする。短い値が要るのは、時間切れそのものを検証するテストに限る。
- background job（`&`）の直後に `disown`・`kill`・`wait` する箇所は、job が先に終了・回収されても成功する。

## テスト

Linux の `tests/skills-plugin.bats` の検証と `tests/codex-tmp.bats` の sandbox probe は、専用の `/tmp` namespace で実行する。Codex の probe には自分の fixture・共有領域・許可外の比較対象だけを bind し、他 suite の一時 directory の作成・撤去や unreadable fixture を glob scan に見せない。共有 `/tmp/codex` の権限は、session TMPDIR と別の fixture で確認する。

`lefthook run test` で `tests/` の全 Bats を実行し、install.sh / nix-devshell / direnv / codex-config / apm-runtime / zsh→bash 移行等を検証する。lefthook の `test` は `bun run test` → `scripts/test.sh` を呼ぶ。入口で実際の `python3 -I` が `dotenv.parser` を import でき、`with-env` と `parallel` が Nix store 内へ解決されることを確認してから、依存関係の frozen install と Bats の実行を行う。Bats はテストファイルを CPU コア数で並列に、ファイル内のテストを直列に実行し、GNU parallel は repo の devShell が提供する（[ADR-0079](adr/0079-run-bats-files-in-parallel.md)）。テストはファイルをまたいで共有資源を使わず、`BATS_TEST_TMPDIR` などテストごとの領域を使う。pre-push など git hook が設定する `GIT_DIR` 等は fixture の git を実 repo へ向けるため、`scripts/test.sh` と `tests/setup_suite.bash` の両方で外す（直接 `bats` を実行しても外れる。`tests/suite-git-env.bats` が使い捨て repo で検証する）。不足時は devShell を準備して再実行する。Linux では、入口（`scripts/test.sh` と、文書だけの変更用の `scripts/test-docs.sh`。判定は `scripts/scratch-tmpdir.sh` で共有する）が Bats の起動前に `TMPDIR` を `/tmp/codex` 配下へ寄せる（既存の `TMPDIR` は解決先が配下ならそのまま使い、どちらの場合も `/tmp/codex` の所有者・権限・symlink を検査して不正なら失敗する。検証用 bwrap が書込み可で残すのは `/tmp/codex` だけで、`bats` 本体は `setup_suite` より前に `TMPDIR` から一時領域を作るため、設定は入口で行う）。入口を通さず直接 `bats` を実行するときは `TMPDIR=/tmp/codex` を付ける。付けないと `verify-ai-tools`・`run-canonical`・`codex-config` などの bwrap 関連が環境起因で失敗する。statusline は `tests/statusline_smoke.sh`（手動実行の smoke スクリプト、Bats 非対象）。`.chezmoiignore` で home には非配備。

テスト入口は明示的に TAP 形式を使い、試行ごとに `tmp/test-run.*/` へ `tap.log`、環境確認・install のログ（`setup.log`）、選択された Python・with-env の実体パス（`environment`）、終了コード（`exit-code`）を保存する。環境確認や install が失敗した場合も記録し、Bats 未実行なら TAP ログは空になる。lefthook が出力をまとめて表示する場合も、このログで実行中の進捗を確認できる。進捗はログ全体の TAP 結果行から集計する。成功はスキップ指定のない `ok` 行、失敗は `not ok` 行、スキップは `# skip` 指定付きの `ok` 行として数える。入口は Bats が正常終了した後も、計画が1つで結果件数と一致し、結果番号が1から連続し、失敗結果や中断宣言がないことを確認する。不整合な TAP は終了コード1で拒否し、元のログを残す。Bats が正常終了する空 suite（`--allow-empty-suite` の `1..0`）は受け入れる。完了時は保存された終了コードも確認する。再実行の結果は初回の結果と分けて報告する。

進捗は `scripts/test-status.sh [tmp/test-run.*]` で確認する。最新の `tmp/test-run.*/` の `exit-code` の有無で完了を判定し、成功・失敗・スキップ・計画件数を表示する。プロセス検索（`pgrep` など）は使わない。長時間の検証は通常60秒間隔で確認し、状態が変わったときに経過を報告する。新しいエラーや進行停止の根拠が出た場合は、該当実行のログを詳しく調べる。コード・文書は `rg -n` で対象を特定して必要な範囲を読み、ツール出力の切り詰めが生じた場合は範囲を狭めて読み直す。

実機のモデルを呼ぶ検証（`tests/live-hook.bats`。両方なら `GCLOUD_INSPECT_HOOK_LIVE="claude codex" CODEX_BYPASS_HOOK_TRUST=1 bats tests/live-hook.bats`。Codex は `CODEX_BYPASS_HOOK_TRUST=1` が必要）は既定で skip し、環境変数で opt-in する。Cloudflare の書換え後の allow・deny・ask / prompt、hook と helper の失敗は `CLOUDFLARE_INSPECT_HOOK_LIVE="claude codex"` で有効にする。保護付き検証入口の一時 HOME から実 CLI の既存認証を使う場合は、`LIVE_HOOK_CODEX_AUTH` と `LIVE_HOOK_CLAUDE_AUTH` にそれぞれの credential file の絶対パスだけを渡す。CLI が内部で利用する symlink を作り、値は読み出さない。差分テスト（`tests/gcloud-inspect-hook.bats`）は既定でも100件を毎回実行し、`GCLOUD_INSPECT_HOOK_FUZZ=1` で5000件に増やす。道具は `tests/helpers/live-hook-*.sh`。

topic branch の push・PR 公開前に、validated task worktree で `lefthook run test` を実行する。同じソース・依存関係・検証環境で全 Bats が成功済みなら、公開直前の繰り返しは不要。検証後にソース・依存関係・検証環境を変更した場合は再実行する。失敗が残る場合は修正してから公開する。変更が指示・文書 Markdown（`instruction-contract` の glob のうち `*.md` と、triage の却下記録 `.out-of-scope/*.md`。`tests/*.bats`・`lefthook.yml`・`.chezmoiignore`・`*.tmpl`・`*.toml`・実行ファイルは含めない）だけなら、全 Bats の代わりに `scripts/test-docs.sh` で契約テストと変更ファイルを参照する Bats だけを実行して公開できる。入口は対象外の変更を見つけると exit 2 で全 Bats を求める。参照の選別は直接参照（パスまたは basename の文字列一致）だけで、glob・間接参照の Bats は漏れる。例外で公開した後に全 Bats が落ちた事例は、この節の下に件数を足して母数にする。認証・実モデル等の opt-in 検証は既定の skip を維持し、skip を実行済みの検証として扱わない。`pre-commit` は軽い lint と、指示ファイルを変更したときだけ動く契約テスト（`instruction-contract`、数秒）に留める。全 Bats の実行漏れは `pre-push`（`scripts/pre-push.sh`）が止める。CI で Bats を走らせなくなったため、ローカルの自動の関門はこの hook だけになる。`pre-push` は削除だけの push を通し、push 対象の commit の tree が検証済みなら再実行せず、未検証で HEAD の tree なら `scripts/test-docs.sh` を先に呼ぶ（exit 0 なら関連 Bats だけで通り、exit 2 なら `bun run test` で全 Bats を実行する）。検証済みの tree は worktree ごとの git dir の `tested-trees` に記録する。記録は `lefthook run test` の成功時と `pre-push` の成功時で、未 commit・未追跡の変更があるときは検証内容と tree が食い違うため記録しない。`lefthook run test` は `lefthook install` も実行するので、新しい clone や worktree でもこの入口を一度通せば hook が有効になる。事前に `lefthook run test` を通しておけば、push は記録の照合だけで通る（全 Bats は実測で 5〜8 分かかる。[ADR-0079](adr/0079-run-bats-files-in-parallel.md) の実測は約 8 分）。未検証で HEAD 以外の commit を push しようとすると、テストを走らせずに拒否する。未検証の tree で未 commit・未追跡の変更があるときも、テストを走らせずに拒否する（テストと文書判定は作業ツリーに対して走り、push する tree とは別の内容を検証してしまうため）。この hook の判定は `tests/pre-push.bats`、`lefthook.yml` との結線は `tests/pre-push-wiring.bats` で検証する。

アーキテクチャHTML report checkerの実ブラウザ再検証は、全Batsへ組み込まず、repo root で `nix develop ./private_dot_config/nix-devshell --command nix develop . --command scripts/run-architecture-render-smoke.sh` を個別に実行する。`playwright-cli` が管理する一時session、loopback HTTP server、追跡fixtureを使う。実report用 `check-architecture-render.js` を正本とし、既存SKILL.mdの手順と同じ `sed '$s/;$//'` を `run-code` へ渡す一時入力にだけ適用する。Mermaid 11.17.2 をjsDelivrから一時web rootへ取得し、vendoringしない。`curl` / `python3` / `playwright-cli` とjsDelivrへの接続が実行前提であり、未達時は失敗理由を表示する。TAPとconsoleの記録は試行ごとに `.tmp/architecture-render-smoke.*` へ保持する。図なしHTMLはHTTP 200なら成功、HTTP 404なら失敗として検査する。

`assume-unchanged` または `skip-worktree` が付いた tracked file は、`git status` が clean でも実内容の変更を隠せる。未検証 tree の公開前検証はこれらのフラグを拒否し、検証済み記録も作らない。検査は呼出元の directory にかかわらず repo 全体を対象にし、Git status・フラグ列挙の失敗も非0終了する。テスト後にフラグを検出した場合も push を拒否する。フラグを解除してから再検証する。

canonical検証の環境準備から開始する場合は、linked task worktree で次の入口を使う。検証する変更をcommitしてcleanにし、関連テストとレビュー指摘の修正を終えたHEADで実行する。通常Linuxでは `--shell default`、WSL2では `--shell wsl` を選ぶ。

採否・判断・関連検証・レビュー結果の追跡ファイルへの記録も、この最終commitまでに終える。canonicalの結果の正本は生成された `result.json` と前後記録・TAPとし、要約はPR本文、公開しない場合は最終報告へ記載する。セッション間で共有する証跡は `/tmp/codex/<task>.XXXXXX/` 配下へコピーして保持する。成功後は検証結果の追記だけを目的に追跡ファイルを変更しない。変更が必要になった場合はcommit後のsourceに既存の再検証規則を適用し、検証済みtreeの判定は維持する。

```bash
python3 scripts/run-canonical.py --shell wsl --no-codex-build
```

この入口は最初のNix評価から `verify-ai-tools.py` の境界を使い、両devShellとPlaywright packageを準備する。Impeccable hookは `IMPECCABLE_HOOK_RUNTIME` の明示指定、または呼出元の `~/.agents/skills/impeccable/scripts/impeccable` から取得する。不足時はNix起動前に停止し、APMの導入を自動追加しない。`bats --count` の上限は300秒とし、超過時は準備失敗を保存して検証本体を起動しない。環境準備の記録は表示された `/tmp/codex/canonical-env.*/` に残り、検証本体が書く `canonical-path` がその記録先を指す。検証本体の出力は `canonical.log` へ保存する。中断時は保護された子プロセスを終了し、終了状態を保存する。

検証本体は既存の `scripts/verify-canonical.py` とする。準備済み環境から直接呼ぶ場合は、`IMPECCABLE_HOOK_RUNTIME`、`IMPECCABLE_BIN`、`TEST_PLAYWRIGHT_PACKAGE` に準備済みの絶対パスを渡す。`lefthook run test` を一度だけ呼び、開始前後のHEAD・全tracked内容・runtime、同じ実行のTAP・終了コード、Design Hook 13件とPlaywright runtime 2件の存在・成功・skipなしを照合する。準備入口は `bats --count` でsourceの全Bats件数を測り、一時的な環境値 `DOTFILES_CANONICAL_SOURCE_TEST_COUNT` と `DOTFILES_CANONICAL_PATH_RECEIPT`（`canonical-path` の保存先）を検証本体へ渡す。検証本体は新しい記録directoryの絶対pathを既存形式のreceiptへ一度だけ公開し、その実行のTAP計画と件数を照合して不一致を `errors` に記録する。2つの値は検証本体が読んだ後に除き、`lefthook` やBatsへは渡さない。片方だけの指定、不正な件数、既存・symlinkのreceiptは検証前に拒否する。値を渡さない直接実行は、件数を新たに測らず従来どおり動く。準備入口は表示ログを解析せず、receiptと終了状態だけを受け取り、記録先が現在のsourceの `tmp/canonical-run.*` の通常directoryで `result.json` が通常fileであることだけを確かめ、その中身は読まない。

開始前は `git status` に加えて、全tracked内容とGit modeをHEADのtree/blobへ直接照合する。`assume-unchanged`／`skip-worktree` に隠れた未commitの変更もBats開始前に拒否し、flag自体は変更しない。実行後にHEADの内容・Git modeと異なるfileは `after.json` の `head_mismatches` に記録し、前後記録とTAPを保持する。

記録は `tmp/canonical-run.*/` の `before.json`／`after.json`、`command.log`、`runner-path`、`result.json` に残る。runnerが作成した `tmp/test-run.*/` と相互参照し、最新directory探索やconsoleの表示文言には依存しない。通常のテスト入口は維持し、受渡し情報をテスト内の別runnerへ引き継がない。Bats自体の結果と証拠照合の問題を区別し、不足・不一致・中断は非0終了する。全Batsコマンドの所要時間は実測し、環境準備の時間は含めない。自動再実行やNix build／APM再生成、PR／CIの照合は行わない。これは実行時点の証拠であり、後続のPR HEADや配備との一致確認は別に行う。

進捗は `python3 scripts/verify-canonical.py --status <canonical-run-directory>` でJSON表示する。この操作は保存記録を読むだけで、全Batsやruntime検査を開始しない。`state` は完了記録がなければ `incomplete`、`result.json` の終了コードが0なら `passed`、非0なら `failed`。`plan`／`pass`／`skip`／`fail` と `exit_code` を表示し、完了前の終了コードは `null`、完了後は記録の終了コードをコマンドの終了コードにも使う。`incomplete` は実行中か中断済みかを区別せず、TAPの全結果が出そろっても成功とはしない。JSON・終了コード・TAP集計形式の不正や、異なる実行のrunner参照は非0終了で拒否する。成功記録の件数合計と失敗0件も確認する。現在のsourceやruntimeの再検証は行わない。

canonical の進捗には、この実行が渡した `canonical-path` と `runner-path` を使う。TAP は並列テストの結果を順番に表示するため、件数が増えない状態だけでは停止と判断しない。

検証は Linux／WSL2 の linked task worktree から、[verify-ai-tools.py](../scripts/verify-ai-tools.py) を使って開始する。最初の Nix 評価より前に、一時 HOME・全 XDG・TMP と bubblewrap の書込み境界を用意する。コマンドと子プロセスから見えるホスト filesystem を read-only にし、ホスト側の書込み先は対象 task worktree、その Git metadata（common dir を含む）、`/tmp/codex` に限定する。`/tmp` を固定利用する CLI には namespace 内の専用 tmpfs を与え、その中へ共有 `/tmp/codex` を bind する。専用 `/tmp` の内容はホストへ残らない。Nix store の `bwrap` がない、linked worktree の所属が不正、または OS 境界を作れない場合は停止する。通常 Linux は `--shell default`、WSL2 は `--shell wsl` を指定する。Linux 以外の保護付き検証起動は未対応で拒否する。

```bash
python3 scripts/verify-ai-tools.py "$PWD" --shell wsl --no-codex-build -- lefthook run test
```

入口は source の `nativeBuildInputs` が選ぶ5 CLIの絶対パスと `command -v` を照合する。同じ版の別 output も拒否し、全 CLI の `--version` が成功した後だけ `--` 以降のコマンドを実行する。文書 Markdown だけの変更では、末尾を `scripts/test-docs.sh` に置き換える。

Nix の準備を要しない調査・検証コマンドには [verification_env.py](../scripts/verification_env.py) を使う。環境変数の切替を省略しても、入口が一時環境と OS 境界を用意する。コマンドは `--` 以降の argv として渡す。

```bash
python3 scripts/verification_env.py "$PWD" -- rg -n --fixed-strings 'chezmoi apply' docs runtime
```

単体 Bats の診断で分離 stderr を保持する場合は、作業用記録内の `TMPDIR` と Bats の `--no-tempdir-cleanup` を組み合わせる。次の例は Bun の1件を実行し、成功・失敗のどちらでも終了コードとログを残す。`verification_env.py` が後片付けする一時環境とは別に、記録内の `bats-tmp/bats-run-*/` へ Bats の出力を保持する。`run --separate-stderr` の生ログは、その配下の `test/*/separate-stderr-*` に残る。

```bash
diagnostic_record="$(mktemp -d /tmp/codex/bats-diagnostic.XXXXXX)"
mkdir "$diagnostic_record/bats-tmp"
diagnostic_status=0
python3 scripts/verification_env.py "$PWD" -- \
  env TMPDIR="$diagnostic_record/bats-tmp" bats --tap --no-tempdir-cleanup \
  --filter '^standalone Bun template selects the patched Bun runtime$' \
  tests/runtime-security.bats \
  >"$diagnostic_record/stdout.log" 2>"$diagnostic_record/stderr.log" || diagnostic_status=$?
printf '%s\n' "$diagnostic_status" >"$diagnostic_record/exit-code"
printf '診断記録 %s\n' "$diagnostic_record"
```

Managed Chromeの所有権記録は同じWindows資源を共有するため、`BROWSER_OWNERSHIP_DIR` は呼出元の共通記録先を保持する。未指定なら隔離前の `XDG_RUNTIME_DIR`、`TMPDIR`、`/tmp` の順で `browser-ownership` を解決し、最初のNix評価から後続コマンドまで同じ値を渡す。HOME/XDGを手動で分離する場合も、分離前にこの記録先を引き継ぐ。別の空の記録先を使うと、使用中のCDP portの予約を参照できなくなる。例外として `tests/dogfood.bats` は利用者の記録を汚さないよう `BATS_TEST_TMPDIR` 配下を使う。そのため実際のDogfood session や、Cleanup 失敗で残ったテストの Chrome と同時に動くと、`port-conflict` で失敗することがある。

共通記録先が `/tmp/codex` 以外の `/tmp` 配下にある場合、既存 directory を read-only で引き継ぎ、専用 tmpfs で隠さない。`BROWSER_OWNERSHIP_DIR=/tmp` は専用 `/tmp` と競合するため拒否する。

既定モードは共通記録を read-only で引き継ぎ、PID namespace も分離する。実際の Managed Chrome を操作する検証では `--managed-browser` を明示する。このモードは共通記録先だけを書込み可能にし、caller PID をホストと同じ主体で照合するためホストの PID namespace と `/proc` を使う。同じ利用者のホスト process を参照・signal できるため、必要なときだけ指定する。記録先は絶対 path で指定した、本人所有・厳密に mode 700・symlink なしの既存 `browser-ownership` directory に限り、保護対象そのもの・それを包含する directory は拒否する。条件を満たさない場合は記録先を変更せずに起動を拒否する（[ADR-0085](adr/0085-share-managed-chrome-ownership-in-verification.md)）。

```bash
python3 scripts/verification_env.py --managed-browser "$PWD" -- COMMAND...
```

WSL から `powershell.exe` へ複数行のスクリプトを渡すときは、`-Command "$script"` の引数で渡す（confirmed、2026-10-23、#496）。stdin（`-Command -`）で渡すと、`-NonInteractive` の有無にかかわらず、エラーも含めて出力が消えた。`MSFT_NetTCPConnection` の `-Filter` に `LocalPort >= …` のような範囲比較を書くと `0x80041017` で失敗するため、`State` などの等価条件だけをプロバイダに渡し、範囲の絞り込みは PowerShell 側の `Where-Object` で行う。

既存バイナリを使う方針の検証では `--no-codex-build` を指定する。最初の devShell 起動前に、選択された Codex output を既存の store または binary cache から確保し、取得できなければ後続の shellHook・コマンドを実行せず停止する。取得ログは `codex-cache.log`、検証中の GC を防ぐ output へのリンクは `codex` に残す。この指定は Codex に適用し、devShell や他の依存関係のビルドは従来どおり許可する。

評価・起動ログ、Nix の metadata 出力、終了コードは `/tmp/codex/ai-tools-*/` の `evaluation.log`／`startup.log`／`metadata.json`／`exit-code` に残す。隔離した HOME／XDG／TMP の各 directory は終了時に削除し、診断用の log root は残す。source tree には隔離用の `tmp/` を作らない。不正 metadata の原文と診断も保持し、評価・metadata・version 検証に失敗した場合は後続コマンドを実行しない。後続テストの TAP は既存の `tmp/test-run.*/tap.log` で確認する。この helper は repo 内の手動入口で、HOME への配備や既存 runner／hook への自動配線はしない。認証・環境変数・network の分離が必要な Codex 検証セッションは、`runtime/skill-harness.md` の既存 raw Codex 入口を使う。現在のセッションや Claude／Antigravity の対話セッションの起動方法は、この検証 helper では変更しない。品質 floor の根拠機能、Playwright／Impeccable の runtime は既存の個別 gate で検証する。

### 変更対象の実ランタイム検証

`scripts/runtime_test_checks.py` は `origin/main` との merge-base から公開する HEAD の変更を調べる。`codex-repo-state`、Treesitter 設定と各回帰テストを変更した場合、対応する実ランタイムの検証を必須にする。対象パスと必須テスト名の正本はこのスクリプトに置く。スクリプト自身の変更では両方を検証する。

- Bash 対象では `TEST_COMPAT_BASH` に実行可能な Bash 3.2 の絶対パスを指定する。実行して版を確認し、新しい Bash による代用を拒否する。macOS では、版が一致する既存の `/bin/bash` を使える。
- Treesitter 対象では `NVIM_TREESITTER_RUNTIME` に plugin の checkout の絶対パスを指定する。変更や追加ファイル（ignore 対象の生成物も含む）がない検証用 checkout を使う。`private_dot_config/nvim/lua/plugins/lsp.lua` に記載された固定 commit との一致は、既存の実 API テストが確認する。

pre-push は未検証の対象変更で準備不足なら全 Bats の開始前に停止する。全 Bats の成功後も、検証済み tree の記録直前に対象の回帰テストを実行し、欠落・重複・失敗・skip を拒否する。同じ tree の成功記録は従来どおり再利用する。canonical 検証も対応テストを必須一覧へ追加し、準備した Bash と Treesitter module の指紋を前後記録へ含める。対象外の変更では、これらのランタイムを要求しない。

```bash
TEST_COMPAT_BASH=/absolute/path/to/bash-3.2 \
NVIM_TREESITTER_RUNTIME=/absolute/path/to/nvim-treesitter \
python3 scripts/run-canonical.py --shell default --no-codex-build
```

Linux x86_64 で Bash 3.2 が未導入の場合は、検証専用に Debian archive の配布済みバイナリを使える。以下は `curl`・`dpkg-deb`・`sha256sum` がある環境向けで、リポジトリ root から実行する。既存の `ensure_scratch_root()` で一時領域の作成・所有権・権限を確認し、通常の PATH は変更しない。他の OS／architecture では、その環境で実行できる Bash 3.2 を明示指定する。

```bash
compat_runtime="$(
  python3 -B -c 'from scripts.verification_env import ensure_scratch_root; ensure_scratch_root()' &&
    mktemp -d /tmp/codex/bash32-runtime.XXXXXX
)" &&
(
set -eu
curl --fail --location --silent --show-error \
  https://archive.debian.org/debian/pool/main/b/bash/bash_3.2-4_amd64.deb \
  --output "$compat_runtime/bash.deb"
curl --fail --location --silent --show-error \
  https://archive.debian.org/debian/pool/main/n/ncurses/libncurses5_5.7+20081213-1_amd64.deb \
  --output "$compat_runtime/ncurses.deb"
(
  cd "$compat_runtime" || exit
  sha256sum --check <<'SUMS'
76d5970005b906dc662d7945575804cba1b4dd72b97bae0cea0a76d7bb7ea5b7  bash.deb
0f8ed8c1a85b27011af342bec58a6bd851d27720d2ed58e632d34d385461a48a  ncurses.deb
SUMS
)
dpkg-deb --extract "$compat_runtime/bash.deb" "$compat_runtime/runtime"
dpkg-deb --extract "$compat_runtime/ncurses.deb" "$compat_runtime/runtime"
cat >"$compat_runtime/bash" <<EOF
#!/bin/sh
export LD_LIBRARY_PATH='$compat_runtime/runtime/lib' LC_ALL=C
exec '$compat_runtime/runtime/bin/bash' "\$@"
EOF
chmod +x "$compat_runtime/bash"
) && export TEST_COMPAT_BASH="$compat_runtime/bash"
```

### Claude plugin の実 CLI 再同期確認

[verify-claude-plugin-sync.py](../scripts/verify-claude-plugin-sync.py) は固定 pin と一致する既存の公開 checkout を検証し、専用 HOME 内へ local clone して公式 CLI で導入する。専用 `/tmp` で隠れる checkout も read-only bind で引き継ぐ。外側の `verify-ai-tools.py` にも `--read-only` で同じ入力を渡す。入力が共有 scratch 内にあっても read-only を維持し、task worktree・Git metadata・runtime 全体を覆う入力は拒否する。管理 `settings.json` を render した後、verified receipt を使って2回再同期し、設定 bytes と現在の inventory・登録・payload を確認する。CLI の対話・モデル呼出し・ログインは行わず、元 checkout と通常 HOME の plugin 配備は変更しない。

```bash
skills_checkout="$HOME/.cache/treflebonbon-skills/checkouts/$(jq -r .rev private_dot_config/nix-devshell/skills-plugin.json)"
python3 scripts/verify-ai-tools.py "$PWD" --shell wsl --no-codex-build --read-only "$skills_checkout" -- \
  python3 scripts/verify-claude-plugin-sync.py "$PWD" --checkout "$skills_checkout"
```

判定・CLI path/version・pin・各反復の結果は、表示された `/tmp/codex/claude-plugin-native.*/result.json` に残す。途中で失敗した場合も、判明済みの情報と失敗した反復を保持する。CLI の stdout/stderr は同じ領域へ保存し、設定本文は出力しない。実 CLI の worker へ渡す環境変数は、一時 HOME・XDG・TMP、PATH、locale、Nix と TLS の実行に必要なものに限定する。通常の Bats では mock CLI による成功・設定書換え・途中失敗・親環境の除外を検証する。実 CLI の Bats は `CLAUDE_PLUGIN_NATIVE=1` と `CLAUDE_PLUGIN_NATIVE_CHECKOUT` を指定して `tests/claude-plugin-native.bats` を opt-in する。

GitHub Actions で全 Bats とそのための Nix cache 準備は実行しない。OSV の [PR scan](../.github/workflows/osv-scanner-pr.yml) と [full scan](../.github/workflows/osv-scanner-full.yml) は引き続き GitHub Actions で実行する。PR タイトルの Conventional Commits 検査（[`ci.yml`](../.github/workflows/ci.yml) の `conventional-commits`、token は `GITHUB_TOKEN`）も GitHub Actions で実行する。

品質 floor 判定は `tests/ai-quality-floor.bats` が実際の Nix package 出力を通して検証する。床上げ時は `modules/ai.nix` の値と、このテストの独立した期待値を更新する（[ADR-0047](adr/0047-test-quality-floors-through-package-outputs.md)）。

## 引継ぎ対象の照合

引継ぎ文書の作成前に、validated task worktree で `publish-topic.py inspect` を実行し、root・branch・HEAD と PR の対応を JSON に保存する。番号が分かる場合は `--pr NUMBER` を渡す。省略時は現在の branch の PR を検索する。ユーザー devShell が提供する `TREFLEBONBON_SKILLS_LIB` と既存の GitHub 認証を使う。

```bash
export GH_CONFIG_DIR="${GH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/gh}"
handoff_record="$(mktemp -d /tmp/codex/handoff.XXXXXX)"
handoff_status=0
python3 scripts/verification_env.py "$PWD" -- \
  python3 scripts/publish-topic.py inspect --repo treflebonbon/dotfiles \
  >"$handoff_record/identity.json" 2>"$handoff_record/stderr.log" || handoff_status=$?
printf '%s\n' "$handoff_status" >"$handoff_record/exit-code"
printf '引継ぎ対象の記録 %s\n' "$handoff_record"
```

`confirmed` は PR の branch・HEAD が一致、`not_created` は検索結果0件、`mismatch` は branch または HEAD の不一致、`ambiguous` は複数候補を表す。前者2つは exit 0、不一致と複数候補は exit 1。API・認証・入力エラーも非0終了し、stderr を保存する。`gh` の失敗は終了コードと、認証要求（exit 4）・HTTP 400〜599・一般の API コマンド失敗を固定形式の診断情報として記録する。PR の `state` は観測値として記録する。引継ぎには照合結果と記録先を含め、照合不能はその理由を書く。ローカルの指定 HEAD に対する検証は、PR との対応状況を明記して続行できる。

## topic branch の公開と確認

公開の依頼を受けた場合、repo内の補助入口 `scripts/publish-topic.py` でpushと確認を分けて記録できる。既存の `git-push-topic` を使い、成功を保存してからPRの状態を読む。HOMEを切り替えた検証環境でも既存の認証を使えるよう、呼出元のGitHub CLI設定directoryをselectorとして引き継ぐ。認証値はコピー・出力しない。

```bash
export GH_CONFIG_DIR="${GH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/gh}"
publication_record="$(mktemp -d /tmp/codex/topic-publication.XXXXXX)"
python3 scripts/verify-ai-tools.py "$PWD" --shell wsl --no-codex-build -- \
  python3 scripts/publish-topic.py push --repo treflebonbon/dotfiles --record "$publication_record"
```

初回公開では、この後に従来どおり `gh pr create --body-file ...` でPRを作る。既存PRへの更新では作成を省き、番号が確定したPRを次の読取り専用操作で確認する。

```bash
python3 scripts/verify-ai-tools.py "$PWD" --shell wsl --no-codex-build -- \
  python3 scripts/publish-topic.py verify "$publication_record" --pr NUMBER
```

`publication.json` の `push` と `verification` は別の結果とする。同じ記録に対するpush・verifyは排他実行し、先行処理が終了してから最新の記録を読む。観測したHEAD・branch・stateは `observations` に残る。観測が0件の間は、誤指定したPR番号を同じ記録で訂正できる。観測後は照合先を固定し、別PRの履歴を混ぜない。確認が期限切れでもpushの成功は保持し、exit 2で照合待ちを示す。APIエラー・異なるbranch・閉じたPRは別の状態で停止する。`verify` を同じ記録で再開してもpushを実行しない。既存記録での `push` は拒否する。pushの実行上限は1800秒とし、超過時は成否不明の `started` を維持する。中断等で `push.status=started` が残る場合も、読取りで確認し、pushの終了状態を成功へ書き換えない。PR本文更新・返信・resolveは、公開確認後に既存の手順と `gh-review-thread` を使う。

## 自律 agent の peer 協働

- 元の候補を native peer と改善する契約の正本は、固定 plugin source の `contracts/autonomous-peer-contract.md` と `contracts/auto-peer-protection.md`。source の解決方法は [`runtime/autonomous-peer-contract.md`](../runtime/autonomous-peer-contract.md) を参照する（[ADR-0075](adr/0075-adopt-peer-refactor-skills.md)）。

## 言語バージョンの更新

変更前に、更新対象の汎用ランタイムと言語テンプレートを漏れなく確認し、公式安定版・採用する Nix revision の実解決版・lint/LSP の互換性・環境間の版差・採否理由を照合する。公式リリースの安定性と Nix チャンネルへの収録状況は別々に判断し、既存の配布経路を維持するかは現在の依頼と照らして決める。

候補を固定してから言語本体と必要な周辺ツールを検証し、評価のみの対象環境と実行確認した環境を区別して報告する。取得元の構造は [architecture](architecture.md#per-repo-言語テンプレート)、独立展開の検証は `tests/helpers/template-with-env.py` を参照する。

## ツール・スキル更新の追跡とレビュー

設定変更でも、本体パッチの追加や package の取得経路を変える場合はツール更新として扱う。既存バイナリで可能な代替案を先に確認し、新しいソースビルドや独自パッチ保守が必要になる時点で、予想ビルド時間と継続保守の負担を提示してユーザーと方針を合わせる。レビューでは、この範囲拡大の判断と根拠も確認する。

更新開始時に既存の調査記録へ、更新単位、適用するADRの箇所、予定する変更（文書訂正を含む）を記録する。更新単位の分離は [ADR-0045](adr/0045-separate-llm-agents-and-apm-update-units.md) に従う。PRを分割したときは、元の差分から外した変更を一件ずつ記録し、採用・却下・保留の扱い、理由、対応先のPR／commit、反映・検証の状態を追跡する。対応先が未定の必要変更は保留とする。

canonicalの実測結果の保存先と記録順序は、本ファイルの「テスト」節に従う。

スナップショットや pin を更新したら、全 Bats の前に旧版・旧 revision を `grep -rn` で探し、tests と runtime に残る固定値を直す。期待値を package や lock から導出できるテストは、固定値を足さずに導出する。

`code-review` のStandards／Spec両軸へ、現在の要件、適用するADRの箇所、調査記録を渡す。各軸は予定した変更と実際の差分を照合し、分割で外した変更の扱いも確認する。過去の調査記録は参考資料と現在の要件を区別する。

更新全体の完了報告前に、調査記録をマージ済みの成果物と照合する。今回必要な変更が保留・未反映・未検証なら、各PRの完了を個別に報告しても更新全体は未完了とする。今回の対象に採用しなかった候補は理由付きの却下として区別する。この追跡手順はツール・スキル更新に適用する。

関連: [architecture](architecture.md)（本ファイルも repo ローカル専用、`.chezmoiignore` で `~/docs/` へは非配備）
