# ツール更新とスキル候補の検証記録（2026-10-05）

## PR #378 の採用範囲（レビュー対応後）

[指定レビュー](https://github.com/treflebonbon/dotfiles/pull/378#pullrequestreview-5412613191)の指摘を採用する。個別ゲートの成功だけでは rollback 境界の独立性を満たさず、初回の一括コミットは [ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md) の直列 PR 契約に違反していた。以下の旧一括候補の記録は調査・検証履歴であり、現在の PR の採用範囲を示さない。

PR #378 は Tool Snapshot のみを採用する。`apm.yml`／`apm.lock.yaml`、Impeccable engine 0.1.8、通常 APM payload、Matt Pocock managed set と関連する期待値・runtime 文書を base `d7c30bf` の採用済み内容へ戻し、APM 0.33.0 との互換性を確認する。通常 APM、Impeccable、Matt Pocock はそれぞれ別の PR と検証・rollback 境界で扱い、通常 APM は Tool Snapshot の main への merge を待つ。候補の exact revision と過去の証拠は本記録と元コミット `21f43fc` に保持し、後続の採用時にはその単位の最終 source で再検証する。公開済み履歴は書き換えず、スキル更新を取り除く一つの Review Round commit を追加する。

分割後の標準 `lefthook run test` は735件中713成功・22 skip・失敗0、終了コード0で完了した。対応3 system の root／user devShell 評価も成功した。テスト環境の package 出力は旧一括候補の検証環境と照合し、Impeccable engine を0.1.11から採用済み0.1.8へ戻した差分のみだった。

APM 0.33.0で base の manifest／lock を空の隔離 runtime へ frozen installし、lock SHA-256 `22d8728d76bc905c70f8ed98f8e4c940ee5a2759ba4592032009821c64853944` の不変性、audit 10/10、20依存・1,300ファイルの hash、Claude／Codex 各46スキルの一致を確認した。組織ポリシーの enforcement は Git remote のない隔離環境で warning 付き skipであり、その適合は未検証。分割後の結果は旧一括候補の実行結果とは別のログに記録した。

## 初回の要件と作業範囲

ユーザーの `$implement ツールとスキルの更新` に基づき、導入済み AI ツール、APM 20依存、管理済み Ponytail native plugin pin を確認する。Codex の native `--worktree` で作成した `/home/ubuntu/.codex/worktrees/f037/dotfiles` を使用し、main `d7c30bf1f5a4d4d203f43e8ff7adaf258e2bd23d` から `chore/update-tools-skills-20261005` を開始した。親の実行環境から physical root、HEAD、status、worktree 固有 Git dir、common dir と back-pointer を検証した。作成確認セッションでは Git metadata を参照できなかったが、親では同じ checkout を検証できたため、親が実装を担当する。

[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md) に沿い、ツール snapshot、通常 APM payload、Impeccable、Matt Pocock を各互換性ゲートで確認する。source の更新、検証、二軸レビュー、コミットまでを実施する。後続の「自前ビルドではなく llm-agents のものは使えないのか」には配布版を実測し、「推奨バージョンを利用するためにビルドが必要であればしょうがない」に従って、修正を維持した Codex 0.160.0 のビルドを続ける。言語ランタイムは直前の PR #373 で更新済みで、今回確認した AI ツールとスキルの更新単位には含めない。live apply と公開は受入後の境界に残す。

## ツールの候補

実装入口で [llm-agents default HEAD](https://github.com/numtide/llm-agents.nix/commit/59d0417c2017794f8872b5556f133c8b0b413734) を一度確認し、immutable snapshot `59d0417c2017794f8872b5556f133c8b0b413734` に固定した。共有 nixpkgs と言語ソースの pin は維持する。

| ツール            | 旧版    | 採用版  |
| ----------------- | ------- | ------- |
| Claude Code       | 2.1.286 | 2.1.289 |
| Codex             | 0.159.2 | 0.160.0 |
| Copilot CLI       | 1.0.90  | 1.0.91  |
| Antigravity CLI   | 1.2.14  | 1.2.16  |
| RTK               | 0.50.0  | 0.51.0  |
| APM               | 0.32.0  | 0.33.0  |
| Herdr             | 0.9.3   | 0.9.3   |
| code-review-graph | 2.3.9   | 2.3.9   |

[Claude Code の公式 CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md#21289) は、symlink 経由の IDE ファイル参照の Read deny と、複合 Bash command・展開を含む環境変数 prefix・変数代入後の deny / ask 判定を修正している。この根拠で品質 floor を `2.1.289` へ上げ、`tests/ai-quality-floor.bats` の独立期待値も揃える。[Codex 0.160.0](https://github.com/openai/codex/releases/tag/rust-v0.160.0) は設定・session・subagent 環境の修正等を含む。既存の品質 floor `0.159.1` と Linux の独立 FD／sandbox cleanup パッチは維持する。[APM 0.33.0](https://github.com/microsoft/apm/releases/tag/v0.33.0) は Codex hooks の native shape、home alias を通した配備、audit 等の修正を含む。

## スキルの候補と採否

全20依存の selected subtree を Git tree SHA で比較した。巨大な GitHub compare の file list だけで payload 不変とは判断しない。

| 対象 | 差分と判断 |
| --- | --- |
| Remotion | `0b5db9daae40f42c73544d1cc0a8c733bd530eaa`／4.0.532。inline effects と timing props の説明を個別の参照ファイルへ分離 |
| Impeccable | `6b9d0ffa3a9a884fc95928d2d2d896b0befa5d3e`／4.5.0 と engine 0.1.11。用途別の design mode、responsive review、modal 上の live browser UI と context 抽出を改善 |
| Matt Pocock | `24fe0ef7737efae15c87225755e9f6f5965e4888`／1.3.1 を専用 gate 通過後に採用した。公式27スキルの membership は不変で、ask-matt の古い post-mortem 案内を retro／明示的な改善依頼へ修正 |
| empirical-prompt-tuning、shadcn、Orca computer-use／orchestration、Supabase、find-skills | selected subtree と content hash は不変。floating revision のみ native lock へ反映 |
| Herdr、Orca CLI、Modern Web Guidance、security-audit | selected subtree は不変のため既存 exact pin を維持 |
| その他 | revision と selected payload は不変 |

一次資料: [Remotion 比較](https://github.com/remotion-dev/skills/compare/a9b199e165505267eda1ed3e0ef3dd3567c43411...0b5db9daae40f42c73544d1cc0a8c733bd530eaa)、[Impeccable 比較](https://github.com/pbakaus/impeccable/compare/dc78b325e753a6971800e3bddc9089bf5954f608...6b9d0ffa3a9a884fc95928d2d2d896b0befa5d3e)、[engine release](https://github.com/pbakaus/impeccable/releases/tag/engine-v0.1.11)、[Matt Pocock 比較](https://github.com/mattpocock/skills/compare/d81f3a183412e71a5b1e84ca21bc1a35eea03a60...24fe0ef7737efae15c87225755e9f6f5965e4888)。engine の対応3 systemは公式 asset digest を固定 hash に使う。

## Native plugin の候補却下

Ponytail v4.11.0（`6d6317716fb15eb1bafb898f74498bd9331b31c8`）も確認した。[公式release](https://github.com/DietrichGebert/ponytail/releases/tag/v4.11.0)はCodexなどでhookが読み込まれなくなった4.10.2以降のregressionを修正しており、tag checkoutの上流hook compatibility checkは成功した。

ただし隔離 HOME のCodex 0.159.2でcatalogueを `--ref v4.11.0` に固定しても、plugin 本体は `main` から4.12.0を取得し、4.11.0の独立期待値は失敗した。既存 `v4.9.0` でも同じ挙動を再現した。両tagの `.agents/plugins/marketplace.json` が本体の `ref: main` を明示しており、Codex 0.160.0の[manifest選択順](https://github.com/openai/codex/blob/rust-v0.160.0/codex-rs/core-plugins/src/marketplace.rs#L20)でも `.claude-plugin/marketplace.json` より優先される。

既存catalogue tagは維持し、単純なpin変更を本体の固定版更新として採用しない。[ADR-0058](../adr/0058-adopt-ponytail-plugin.md)の過去の固定範囲の説明を訂正し、native配布、full mode、subagent scope、fail-open／再登録は維持する。本体まで固定する経路の設計やvendor manifest改稿は追加しない。live plugin directoryは変更していない。

## 検証環境と再実行

初回は継承された `PYTHONPATH` により、Nix の APM 0.33.0 が旧0.32.0の Python module を読み込んだ。CLI version と lock の不一致で検出し、その生成物は採用しなかった。以降は `PYTHONPATH`／`PYTHONHOME` を除き、空の隔離 cwd／HOME で実0.33.0を使う。

Matt gate の初回全件テストでは、複数 Chromium を含む user cache を継承して dogfood fixture が失敗した。単一の Nix browser bundle を `PLAYWRIGHT_BROWSERS_PATH` に指定すると同じ fixture が成功し、関連24テストも成功した。gateway bridge の起動失敗も1件あったが、単独再実行は成功し、原因は未確定。テストの例外化・削除はせず、修正した環境で全ゲートを再実行する。

セッション再開時に旧 `/tmp` ログと未完了プロセスが消失したため、同じ task worktree で未完了の build とゲートを再実行した。以降のログは gitignored `tmp/update-tools-skills-20261005/` に保存する。再開時の検証runtimeを同worktree配下の `TMPDIR` に置くと、trust stateをGit管理外に置くfixtureが失敗したため、Git管理外の `.cache` 配下へ移した後は、ImpeccableがUI fixtureをcache扱いして解析しないことを検出した。同一のimmediate-tierテストでcache配下の失敗と `/var/tmp` 配下の成功を再現し、runtime／Bats fixtureはGit管理外かつcache扱いされない永続 `/var/tmp/dotfiles-update-tools-skills-20261005/` へ移して全ゲートをやり直す。browser attachmentの1件も単独再実行で成功したが、その失敗原因は未確定。

## Codex が止まる現象の切り分け

後続の「再開」について、ユーザーは `Selected model is at capacity. Please try a different model.` が表示されたためだと説明した。これは検証対象の Codex 0.160.0 実装で `CodexErrorDetails::ServerOverloaded` に対応し、API の `server_is_overloaded` をこの表示へ変換している。`retry_delay()` はこのエラーに自動再試行を返さないため、ターンが終了して再開入力が必要になる。今回のモデル容量エラーはサーバー側の混雑であり、WSL のメモリ負荷とは区別する。過去の全停止が同じ原因だったかは未確認。[OpenAI公式の復旧案内](https://developers.openai.com/api/docs/guides/agents-api/errors)も、少し待って未完了の作業を再試行し、続く場合は後続ターンのモデル変更を案内している。モデル設定はユーザーが選択するため変更していない。

ユーザーから、Codex が止まったため復旧操作として WSL を再起動したと確認した。WSL の再起動は停止後の操作であり、Codex 停止の原因とは扱わない。ユーザーは停止時の Esc／Ctrl+C を試しておらず、キー操作まで失われていたかは未確認とする。`journalctl --list-boots` と前回 boot のログで、2026-10-05 15:18:38 JST の正常な poweroff と15:18:56の次回起動を確認した。中断されたビルド／ゲートには終了コードがなく、完了扱いにはしない。

前回 boot では15:16から停止直前まで journald のメモリ圧迫通知が繰り返された。同時期の Codex 0.159.2 のローカル SQLite log には、15:15:31のモデル一覧取得タイムアウトと15:16:24の TUI `account/rateLimits/read` タイムアウトがある。Linux の OOM kill／panic は見つからず、Windows の Resource Exhaustion Detector にも該当イベントを確認できなかった。メモリ負荷と応答停止の相関はあるが、直接の因果関係は未確定。

再開後に繰り返される「Custom tool call output is missing」は、中断された tool call の応答を `aborted` で補完する処理の記録である。Codex 0.160.0 の `core/src/context_manager/normalize.rs` で補完処理を確認した。これだけで停止原因とは判断しない。ログは対象 thread に絞って read-only で参照し、auth ファイルや DB 本体は編集していない。

配布済み Codex 0.160.0 は Numtide cache から取得できたが、既存の複数 denied-file mask と process-group SIGKILL cleanup の回帰テストがともに失敗した。このため2件のローカルパッチは維持する。ビルドは同じ derivation を `--cores 1 --max-jobs 1 --keep-failed` で実行し、8並列だった Cargo が `-j 1` になることを確認した。パッケージ内容と最適化は変えず、全件テストはビルド完了後に実行する。`/proc/meminfo` と `/proc/pressure/memory` の時系列を ignored artifact へ記録する。WSL の global 設定と他のプロセスは変更しない。 1並列ビルドは同じboot内で完了し、Cargoのリリースコンパイルは136分29秒だった。15秒ごとの551観測では最小空きメモリ約6.8GiB、最大スワップ使用増加約42MiBだった。リンク前のメモリ圧迫指標は時間平均0.00で、終盤のリンク時にsome/full avg10が最大2.23%となった。短い圧迫は残るが、中断なく完走した。今回のビルド開始後、モデル一覧／TUIのタイムアウトを同じログ条件で再検索した結果は0件だった。これはビルド負荷の観測であり、ユーザーが確認したサーバー側のモデル容量エラーを解消する変更ではない。

## 旧一括候補の確認済み結果と残作業

- Nix metadata は対応3 systemで候補版が一致する。root／ユーザー devShell の全 system評価は成功し、共有 nixpkgs と言語ソースは維持する。
- Linux では8 CLIの version／help による起動が成功。Codex 0.160.0の修正版は source build が終了コード0で完了し、独立 FD と sandbox cleanup の回帰テスト9/9も成功した。配布版0.160.0の失敗2件に対し、修正版では同じケースが成功することを確認した。
- APM 0.33.0の現 source lock を別の空 runtime に frozen installして SHA-256 no-rewriteを確認。audit 10/10、20依存、1,310配布ファイルの SHA-256、Claude／Codex 各46スキルの一致を確認した。
- Matt 候補を含む実 manifest から別の空 runtime へ native lock を生成した。frozen no-rewrite、audit 10/10、1,310ファイルの SHA-256、各46スキルの一致が成功。非 Matt dependency の content hash は現 source lock と一致する。専用ゲート通過後、この実manifestとnative lockをsourceへ採用した。gate内部だけで一時pinしたlockは配備sourceに使わない。
- Impeccable engine 0.1.11を公式固定 hashで Linux buildし、candidate launcher を使う Design Hook gateは13/13成功。quiet、per-edit／Stop、silent convergence、project設定・cache、両 provider の正常出力を維持する。CLI の `--version` は上流の静的ラベル `4.0.0` を返すため、engine releaseは asset／hash と skillの `scripts/VERSION` で判定する。
- 型検査は成功。再開前の code-review-graph smokeでは隔離fixtureの graph buildと in-process FastMCP `list_graph_stats_tool` が成功した。
- Claude 2.1.289配布 binaryには kill switch、experimental enable、`tengu_sage_compass2`、`advisorModel` が残る。ただし string pool の確認から制御フローの順序や旧版との同一性は判断できず、実モデルでの advisor呼出しは未検証。モデル／env設定は維持する。
- ARM Linux／Darwin は評価のみで、実機起動は未検証。
- Matt専用ゲートは関連71/71、全件735結果（成功713、skip22、失敗0）、隔離chezmoi dry-run／HOME不変まで通過し、終了コード0を確認した。非Matt lock fieldを維持する比較も成功した。
- auditのbaselineは10/10成功したが、Git remoteのない隔離環境ではorganization policy enforcementはwarning付きskipであり、組織ポリシーの適合を保証しない。
- 最終sourceでの標準 `lefthook run test` 初回は735結果（成功712、skip22、失敗1）、終了コード1だった。失敗は `tests/mattpocock-update-gate.bats` の独立期待hashを更新し忘れた1件で、採用済みMatt payloadのhashへ更新した。修正後の該当14/14が成功した。標準全件の2回目は735結果（成功713、skip22、失敗0）、終了コード0で完了した。初回失敗を含む試行ごとのログを保持した。
- `742904f` に実装をコミットし、既知base `d7c30bf1f5a4d4d203f43e8ff7adaf258e2bd23d` からの差分を規約・要件の二軸でレビューした。両軸とも指摘0件。後続コミットはこの検証記録の追記のみとする。
- 最終native lockのSHA-256は `ff66e373e078fed47af34b5925fddcc6e061704f4058f640232fb068d2bf40c2`。空runtimeのfrozen install後、採用時、コミット後も同一である。
- source実装と必要な検証は完了。live sourceへの受入・merge・HOME配備は後続の境界に残る。

## 初回 Standards

規約軸レビューは指摘なし。文書化された規約違反とFowler smellの両方で問題は見つからなかった。task worktree source、既存APM/Nix/native plugin配布経路、APM native lock形式、独立したfloor・pin・hash期待値、Linux Codexの既存2パッチを確認した。テスト実行は親が担当し、修正後の標準全件結果はレビュー時点で未完了として扱った。

## 初回 Spec

要件軸レビューは指摘なし。欠落・部分対応、未依頼のscope増大、誤った実装はいずれもなし。ツール／skill更新と停止理由の切り分けが差分に反映され、別設計が必要なPonytail本体固定は追加していない。今回のモデル容量エラーと過去の因果関係を区別している。未完了の標準全件テストを成功扱いしていない。

Standards: 0件（最重大の指摘なし）、Spec: 0件（最重大の指摘なし）。
