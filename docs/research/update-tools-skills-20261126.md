# ツール・管理スキル更新（2026-11-26）

依頼は「`$implement ツールとスキルの更新`」。前回の定例更新と同様に、管理中の AI ツール、個別 CLI、APM スキル、公開 skills plugin を点検し、既存の配布経路で検証できた候補を採用する。Orca の `test/bichir` で作業する。fetch 後の開始点 `c91da1f` は `origin/main` と一致し、このブランチの既存 PR はなかった。

| 更新単位 | 適用する判断と予定 |
| --- | --- |
| AI ツール | [ADR-0045 の 2026-10-31 amendment](../adr/0045-separate-llm-agents-and-apm-update-units.md#2026-10-31-amendment-apmを除いてllm-agentsの出力を更新する) と [ADR-0047](../adr/0047-test-quality-floors-through-package-outputs.md) に従い、共通 snapshot の3 system の出力と品質 floor を検証する。独立した修正済み APM output は別単位として扱う。 |
| 通常 APM | [native lock と配備比較](../../runtime/skill-harness.md#apm-lock-の生成) に従い、選択 payload を照合し、native lock、frozen install、audit、両 target の配備を確認する。 |
| Impeccable と Matt Pocock | [ADR-0053](../adr/0053-separate-impeccable-skill-and-engine.md) の skill・engine 互換性と [ADR-0042](../adr/0042-mattpocock-managed-set-update-gate.md) の公式 full set を個別に検証する。 |
| 公開 skills plugin | [ADR-0082](../adr/0082-extract-local-skills-to-public-repository.md) に従い、公開 tag と固定 pin を照合する。 |
| 個別 CLI | 公式配布の版・対応 system・チェックサムを照合する。Cloudflare CLI は [ADR-0083](../adr/0083-add-read-only-cloudflare-inspection.md) の満7日条件と既存操作の schema を確認する。 |

実装範囲は task worktree のコミットまでとする。

## 採用した候補

| 更新単位 | 内容と根拠 |
| --- | --- |
| AI ツール | `llm-agents` は [`0cde397`](https://github.com/numtide/llm-agents.nix/tree/0cde3970ab62414aaba209787c74b11b951ec7e8) を採用する。Antigravity CLI 1.5.12 → 1.5.14、Claude Code 2.1.328 → 2.1.330。Codex は 0.170.0、Copilot CLI は 1.0.114、Herdr は 0.9.5。code-review-graph は 2.4.0 のまま依存と出力が変わる。対応3 system × 6 package の Numtide cache 登録を確認した。 |
| 通常 APM | Modern Web Guidance の context menu・teaser・セキュリティ等の案内、Remotion 4.0.547 の Elements、Animated Architecture Diagram の carry-loop 例、Web Interface Guidelines 1.1.0 の同梱ルール、Orca CLI と orchestration の実行ファイル選択ガイドを取り込む。Web Interface Guidelines の同梱ルールは [公式 source](https://github.com/vercel-labs/web-interface-guidelines/blob/434b7f91364665f2f733b310ec54809bf8f37937/command.md) および skill 記載 SHA-256 と一致した。 |
| Impeccable | [スキル 4.11.1](https://github.com/pbakaus/impeccable/releases/tag/skill-v4.11.1) と、それが要求する [engine 0.1.31](https://github.com/pbakaus/impeccable/releases/tag/engine-v0.1.31) を一緒に採用する。3 system の公式配布物は公開値とスキル同梱の SHA-256 に一致し、Linux で新 launcher と engine を通す Design Hook 13件が成功した。 |
| Matt Pocock | [`6f7f783`](https://github.com/mattpocock/skills/tree/6f7f7831a625f040a8e06a0e7954826b87ce775a) の公式27スキルを採用する。管理対象では domain-modeling の glossary 定義から関連用語を太字で参照する書式が加わった。専用ゲートは workflow 71件、全835件（798成功・37スキップ・失敗0）、`chezmoi` dry-run を通過した。 |
| 公開 plugin | [0.4.2](https://github.com/treflebonbon/skills/compare/v0.4.1...v0.4.2) を採用する。domain-modeling-studio の業務ルール・検証候補の追跡と、Sprites の WSL recipe を含む。公開 tag と Nix の取得物で全458ファイルの内容・Git mode が一致した。 |
| Cloudflare CLI | 2026-11-26 07:11 UTC 時点で [`cf@1.0.0-rc.1`](https://registry.npmjs.org/cf/1.0.0-rc.1) が公開から満7日を経過した最新候補。rc.2 は同日 13:41 UTC まで満7日未達。既存7操作の同梱 schema は beta.31 と全体が一致した。npm の lock を install script 無効の状態で再生成し、`npm ci --ignore-scripts` と Nix 依存 hash 取得を確認した。 |
| Waza・flyline | [Waza 0.42.0](https://github.com/microsoft/waza/releases/tag/v0.42.0) の3 system と [flyline 1.11.0](https://github.com/HalFrgrd/flyline/releases/tag/v1.11.0) の2 Linux system で公式配布物の SHA-256 を照合した。Linux で `waza --version` と、制御 PTY の Bash で flyline のロード、版表示、ヘルプ、既定の mouse 設定を確認した。 |

当初の [`a8e2ca87`](https://github.com/numtide/llm-agents.nix/tree/a8e2ca87ef6a622821d175555d320e196cac2d34) では、Codex 0.171.0 の依存一式が 689.9 MiB から 2.8 GiB へ増えた。追加された `codex-vendor` は出力自身が参照する。隔離 runtime が Nix store をコピーする既存の raw Codex 境界テストは単独で通ったが、全 Bats では2回とも `AI_EDITED` を待つ180秒の制限を超えた。2回目は入力なしの PTY での Bash 起動も30秒の制限を超えた。[上流の依存分割](https://github.com/numtide/llm-agents.nix/pull/12639) の直前の共通 snapshot を選んだ。Codex、Copilot CLI、Herdr は3 system とも旧 snapshot と同じ出力を使う。切り替え後は raw Codex の境界テストが全体実行でも通った。

残った PTY テストのタイムアウトは、Bats の並列数を環境変数で設定して子 Bats に継承させると、単独でも再現した。並列設定を suite 自身の `--jobs 6 --no-parallelize-within-files` 引数で渡すと単独で通った。この引数の形で専用ゲートを再実行した。

共有 nixpkgs、Claude Code と Codex の承認済み品質 floor、Brotli 修正済みの独立 APM 0.35.0 を使う。後継の APM 本体への切替は ADR-0045 の独立した更新単位に従う。Playwright CLI 0.1.25、design.md 0.4.0、gws 0.22.5、gwq 0.1.2、Ponytail 5.3.3 は公式公開版と一致した。Orca の `computer-use` は選定済みの旧 path を固定する。

Defuddle 0.19.13 と MarkItDown 0.1.9 は公式公開済みで、確認した Nix の upstream 定義はそれぞれ 0.19.6 と 0.1.8 だった。文書変換 CLI は現行の source backport を使う。Sprites CLI の公式 release channel は日付版の manifest と直接バイナリを返す。現行の `v0.0.1-rc48` は固定 tarball 由来で、配布方式をそろえる検討は別途行う。

flyline の明示的な `enable -d flyline` 後に Bash が終了する条件では、新旧両版で SIGSEGV を再現した。管理下の Bash 初期化はロードと mouse 設定を行う。ロードしたままの終了は新旧両版で成功した。

検証記録は `/tmp/codex/update-tools-skills-20261126.QzbK3M/` に保存する。

## 関連検証

- repo と user の両 flake を3 systemで評価した。WSL2 の隔離 devShell で対象5 CLI の Nix output と起動時の版が一致し、Herdr と code-review-graph の版表示も成功した。品質 floor・Brotli 修正済み APM・Impeccable の固定版を含む関連 Bats 14件と TypeScript 型検査が通った。
- 公開 plugin を候補 CLI の公式経路で隔離 HOME に導入した。Codex と Antigravity CLI は10スキルと全458ファイル、Claude Code は2回の再同期で設定と同じ固定配布物を確認した。検証は Linux x86_64 / WSL2 で行い、他 system は Nix 評価・キャッシュ・配布物の照合までとした。
- Cloudflare CLI の実 package と registry lock の Bats では、認証情報を使わず、版・CLI 委譲の抑止・schema・D1 の合成応答を確認した。既存 helper の Bats 25件も成功した。
- 最終 APM lock は native install で生成した。frozen install 前後で SHA-256 が一致し、audit 10件、20依存、両 target 各46スキルの配備を照合した。更新計画は追加14・削除2、台帳1522 → 1534件、予定どおり142件の hash が変わり、共有 owner と既存所有権を確認した。通常スキルの一次検証から最終生成までに orchestration の浮動解決先が `e05ac7b` → `58b7280` へ進み、選択内容と配備 hash は一致した。
