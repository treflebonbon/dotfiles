# ツール・管理スキル更新（2026-11-09）

## 依頼と作業境界

今回の依頼原文は「`$implement ツールとスキル更新`」。AI ツール・全管理スキル・個別に固定した CLI を調査し、現行の配布経路と検証ゲートで採否を判断する。言語ランタイム・テンプレート・root 開発依存の一括更新は含めない。過去の調査記録は参考資料であり、今回の追加要件とは扱わない。

開始点は HEAD / fetch 後の `origin/main` `c3fc1958d1034b0c7a1eca6e6e6da8ed6b9a4036`。Orca native task worktree `/home/ubuntu/orca/workspaces/dotfiles/beluga`、branch `test/beluga` の physical root・Git dir・common dir・clean status を確認し、既存 PR がないことも確認した。実装・検証・独立レビュー・コミットまでを行い、PR 公開・merge・live 配備は含めない。

## 更新単位と予定変更

| 更新単位 | 適用する判断 | 予定する変更・判定 |
| --- | --- | --- |
| AI snapshot | ADR-0045 の更新単位分離と2026-10-31 amendment、ADR-0047 の品質 floor | upstream default branch HEAD を固定し、6ツール×3 system の版・output・cache と Linux 起動を照合する。独立した APM は修正済み既存 output を維持する。 |
| 通常 APM payload | ADR-0045、runtime/skill-harness.md の隔離 lock 生成・配備比較 | 全 dependency の selected subtree を比較し、native install・frozen 不変・audit・両 target・所有権 ledger を照合する。 |
| Impeccable skill / engine | ADR-0053 の一体検証 | 安定 release に差分があれば Design Hook gate で検証する。 |
| Matt Pocock managed set | ADR-0042 の ordered gate | 公式 full set に実体差分がある場合に専用 gate で検証する。 |
| 公開 skills plugin | ADR-0082 の完全な pin record・公式導入・current payload 照合 | 公開 release と現行0.2.7を比較し、受入条件を満たす候補だけ採用する。 |
| 個別 CLI | 現行の公式 binary / Nix 配布方式、Cloudflare CLI の満7日条件 | Playwright CLI、waza、design.md、文書変換 CLI、Cloudflare CLI を調査し、配布経路を変えず検証できる候補を採用する。 |

pin 更新に伴うテスト期待値と現行 runtime 文書の訂正を含む。新しい独自 patch・source build は追加しない。採用・却下・保留と理由、分割で外した変更があればその対応先と検証状態を追跡する。

## 証跡

調査・候補 runtime は `/tmp/codex/update-tools-skills-20261109.AxGmKd/` に保存する。検証は task worktree の `scripts/verification_env.py` / `scripts/verify-ai-tools.py` から開始し、通常 HOME を書込み対象にしない。

## 調査結果と採否

| 更新単位 | 採否と根拠 |
| --- | --- |
| AI snapshot | [`3327b7d82f31f2444533e935f06caf1a1b4da18c`](https://github.com/numtide/llm-agents.nix/tree/3327b7d82f31f2444533e935f06caf1a1b4da18c) を採用する。Claude Code 2.1.318 → 2.1.319、Codex 0.166.0 → 0.167.0、Copilot CLI 1.0.105 → 1.0.107、Antigravity CLI 1.5.0 → 1.5.3。code-review-graph 2.3.9 は版据え置きで依存と output が変わり、FastMCP 3.4.7 を使う。Herdr 0.9.5 は3 system の derivation・output とも不変。native lock は upstream 内部の nixpkgs 更新を含み、共有 nixpkgs と独立 APM input は維持する。 |
| 通常 APM | PDF、Remotion、Orca orchestration の payload 更新を採用する。PDF は [`2c5958ec…`](https://github.com/anthropics/skills/tree/2c5958ecac7cee2b583967a2c4981d0f4a75c579/skills/pdf) の Apache-2.0 license と frontmatter の更新。Remotion は [`a2824c67…`](https://github.com/remotion-dev/skills/tree/a2824c67f8b4585c294a8101db9f9f0ad3c643f8/skills/remotion-best-practices) の4.0.541表記への更新。Orchestration は version-matched guide への委譲を維持し、重複した説明を整理する。native install の解決先 [`fb9adc7b…`](https://github.com/stablyai/orca/tree/fb9adc7bc5b1556a9f2528300e8d7b575294f089/skills/orchestration) と調査時 HEAD `1a605958…` の selected subtree は同一だった。skill-creator・shadcn・find-skills は floating revision だけが前進し、全配備 bytes とその他 metadata は不変。 |
| Impeccable skill / engine | [Skill 4.8.1](https://github.com/pbakaus/impeccable/releases/tag/skill-v4.8.1) `924bbd19…` と、そのスキルの `scripts/VERSION` が指定する [engine 0.1.19](https://github.com/pbakaus/impeccable/releases/tag/engine-v0.1.19) を一体で採用する。launcher の古い同梱 engine 判定、cache checksum stamp、hook の wiring 検出・local consent に基づく修復、live mode の修正を含む。より新しい engine 0.1.20 / 0.1.21 や未リリース HEAD は、この公開スキルの指定した組合せではないため採用しない。既存の管理 hook の契約13件が候補の公式 engine で全て成功した。 |
| Matt Pocock / その他の exact pin | 公式27件の Matt 1.3.2、Modern Web Guidance、security-audit、Herdr の selected subtree は HEAD と同一で、現行 pin を維持する。Matt の全 metadata も不変であり、専用 ordered gate を必要とする更新はない。computer-use の上流削除は採用せず、既存 exact pin と payload を維持する。 |
| 公開 skills plugin | 上流 HEAD / 最新公開版は現行 [0.2.7](https://github.com/treflebonbon/skills/releases/tag/v0.2.7) `126690ce…` と一致するため、complete pin record 全体を維持する。AI CLI 更新後の公式同期も2回成功した。 |
| waza | [0.40.1](https://github.com/microsoft/waza/releases/tag/v0.40.1) を採用する。request を取り消さずに first-event watchdog を解除する修正、相対 artifact directory、group_by tag、hook の入力変数、同秒の複数モデル実行、strict token budget の終了コード、coverage 集計の修正を含む。3 system の公式 standalone binary を取得し、既存の配布方式で hash を更新する。モデル・有料 provider は呼ばない。 |
| Cloudflare CLI | [1.0.0-beta.26](https://github.com/cloudflare/cf/releases/tag/cf%401.0.0-beta.26) を採用する。npm 公開日時は2026-10-29T20:18:01.643Z。調査時刻2026-11-09T07:55:44Zで満7日条件を満たす。beta.27 / beta.28 は未達のため却下する。既存7操作の schema JSON 全体は beta.25 と同一。公式 npm・install script 無効化・固定 endpoint・版照合と安全境界を維持する。 |
| 他の CLI / plugin | Playwright CLI 0.1.23、design.md 0.4.0、Ponytail 5.3.3 は公開安定版と一致し維持する。Ponytail は最初に誤った repository URL を調査して失敗したが、管理設定の正しい `dietrichgebert/ponytail` の公開 tag を確認した。runtime が独自に管理する plugin の導入状態は変更しない。 |
| 文書変換 CLI / APM 本体 | Defuddle の公開版0.19.6と現行0.19.3には差分があるが、source-only Nix 定義の新しい source build を追加しない範囲では採用しない。MarkItDown の公開版0.1.9も同じ理由で採用せず、現行0.1.7の配布経路を維持する。APM は ADR-0045 の独立単位どおり、修正済み0.35.0の既存 output を維持し、新規 patch・build を追加しない。 |

今回の変更は一つの branch に集約し、PR 分割は行わない。外した候補は上表で理由付きの却下として扱い、必要変更を対応先なしの保留にはしない。実装ロジックは変更せず、既存の公開境界テストで pin・version と安全契約を検証するため、新しい TDD seam の設計は行わない。

## 個別検証

- **確認済み（metadata / cache）:** `base-matrix.json` / `candidate-matrix.json` で6ツール×3 systemの新旧版・derivation・outputを照合した。独立 APM の3 systemのderivation・outputは全て不変。Numtide cache への18 output照会は成功した（`cache-query.exit-code` は0）。`cache-realise.exit-code` も0で、Linuxの6 outputは `--max-jobs 0 --builders ''` により取得済み。独自buildへのfallbackはなく、ARM / Darwinの実機起動は未確認。
- **確認済み（APM）:** 共通生成スクリプト・frozen前後の SHA-256 `9fc12c9696dd1c0e3cb10116de24a732a47315630f873c70c9192fea1f8c037d` 不変・audit 10/10が成功。配備比較は21 dependency、両target各47 skill、追加0・削除0。`apm-ledger-result.json` でroot metadataと全1516件の所有権不変、候補4件の68 hash recordのみの変更、候補外14件の完全不変と3件のfloating revisionのみの変更を独立に照合した。共有owner recordは0件。これらの成功後にnative lockをsourceへコピーした。
- **確認済み（公式 asset / npm）:** wazaとImpeccableの対応3 systemの全6 binaryを取得した（`assets-verified.json` は全件 `download_verified: true`）。Impeccableの3 binaryは公開スキルに同梱されたchecksumと一致する。Linux arm64は初回と再試行でHTTP 504になったが、公式releaseのasset一覧で存在とchecksumを確認後、同じ公式assetの `?download=1` URLで取得し、SHA-256 `73b5662e42f060aba716016c34a7274cc49a998cd0d5da8b84a95d9e4edea729` の一致を確認した。この取得不確実性は解消済みであり、ARM実機での起動は別途未確認である。Linux raw binaryの版表示はwaza 0.40.1 / engine 0.1.19。Cloudflareはnative npm lock生成・install scriptなしのfrozen install・既存 `prefetch-npm-deps` による依存hash取得と、7操作のschema全体不変を確認した。実credential・実APIは呼んでいない。
- **確認済み（Nix評価）:** 両flakeの `nix flake check --no-build --all-systems` が成功した。root appの既存meta warningは残る。

**確認済み（Design Hook）:** 候補の公式 engine 0.1.19とAPM launcherを使い、`design-gate.tap` の13件全てが成功・skipなし。Claude / Codexのper-edit / Stop出力、quiet・機密／生成file除外、dedupe・silent convergence、global新規projectとmonorepo / symlink、設定とcacheの所有境界を維持している。

**確認済み（graph）:** 更新したcode-review-graphのCLIでPython fixtureをbuild / statusし、1 file・3 nodes・3 edgesを得た。FastMCP Clientのin-process MCP接続で30 toolを列挙し、`list_graph_stats_tool` が同じ統計を返した（`graph-smoke.log` / `graph-mcp-result.json`）。embedding provider・モデル・実APIは呼んでいない。他言語のgrammarとARM / Darwinの実機実行は未確認。

**確認済み（CLI / 公式同期）:** 候補devShellが選ぶ6 CLIの実体pathと版表示が一致した。Claude Code 2.1.319で公開plugin0.2.7を公式導入し、管理設定をrender後に2回再同期した。両回とも設定bytesと283 files、inventory・version・payload照合を維持した（`/tmp/codex/claude-plugin-native.rsbgmzhv/result.json`）。cache取得前に開始した2つの検証入口は、同じCodexの重複取得を待っていたためSIGTERMで中断し、取得済みoutputを確認後に同じ入口から再開した。中断を検証成功とは扱わない。

**確認済み（関連検証）:** `related.tap` は87/87成功・skip0・失敗0で、実行入口 `/tmp/codex/ai-tools-fbjb7itl/exit-code` も0。Design Hookの13件を合わせて個別検証は100件成功した。品質floor、3 systemのupstream direct output、修正済みAPMの既存outputとBrotli closure、Impeccable engine、Playwrightの実package / runtime、Cloudflareの実CLI schemaとhelperの安全境界を含む。Nixが組み立てたwaza 0.40.1 / cf beta.26 / code-review-graph 2.3.9の版表示、root依存のfrozen install、TypeScript型検査、整形・registry検査、commit hookも成功した。tests・runtime・現行packageの旧pin / 版を検索し、更新対象の取り残しがないことを確認した。

**確認済み（独立レビュー）:** 実装commit `0459d857ee18cf8f16c4525b73d5c23ee15aa335` を固定し、Standards / Specを独立したreviewerで並列に検証した。現在の依頼原文・実装判断・適用ADR・本記録・不採用候補の扱いを両担当へ渡した。両軸とも同じARM Linux asset取得の記録訂正1件を指摘し、上記の確認済み結果へ訂正した。他の規約違反・smell・要件欠落・範囲拡大・誤動作の指摘はない。

個別検証・採否・レビュー指摘の反映を終えたcleanな最終commitでcanonical検証を一度実行する。canonical結果は生成された `result.json`・前後記録・TAPを正本として最終報告に記載し、成功後にこの文書への結果追記だけの変更は行わない。
