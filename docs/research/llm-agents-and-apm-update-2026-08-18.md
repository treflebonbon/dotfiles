---
type: research
title: llm-agents.nix と APM 管理 skill の更新候補（2026-08-18）
description: 2026-08-15 の採用済み基準から llm-agents.nix と apm.yml 全依存が進んだ範囲を、固定 commit、selected subtree、品質 floor、Design Hook、Matt Pocock workflow 契約ごとに一次情報で整理した調査ノート。
tags: [research, llm-agents, apm, skills, claude-code, impeccable, matt-pocock]
timestamp: 2026-08-18
---

# llm-agents.nix と APM 管理 skill の更新候補（2026-08-18）

## 結論

調査基準時刻は **2026-08-18 00:05 JST / 2026-08-17 15:05 UTC**。moving HEAD はこの時刻に取得した exact commit へ固定した。調査中にも Orca の `main` が先へ進んだため、以下の判定は常に表の commit を指し、後から見た `main` を指さない。

2026-08-15 の調査・実装基準は現行 source へすべて反映済みである。現行 `llm-agents.nix` pin は [`9b760dd7`](https://github.com/numtide/llm-agents.nix/commit/9b760dd766fc31e5ab8c5d6cc6c2c0a7fdd4fa0a)、Claude Code / Codex の floor は 2.1.232 / 0.147.0、Impeccable は `5a149f3f`、Matt Pocock 20 skill は `ed37663c` のままである。

**判断:** 一括更新はしない。更新単位を次の3群に分ける。

1. **採用推奨（実装時ゲート付き）— `llm-agents.nix` [`5b3a7eff`](https://github.com/numtide/llm-agents.nix/commit/5b3a7eff4326cb9001a79938a53e2fc8662d38c2)。** 当 repo が直接消費する7 packageのうち変わるのは Claude Code 2.1.232 → 2.1.233 だけで、Codex / Copilot CLI / Antigravity CLI / RTK / APM / code-review-graph の package tree は同一である。2.1.233 は Windows `\\??\\` device path による UNC validation bypass / NTLM credential leak、skill argument の template marker 再展開、Linux sandbox idle CPU、MCP v2 reconnect 等を修正する。一方、2.1.232 の Cygwin-style symlink と input redirection の permission 変更を revert し、新しい model では Task\*/TodoWrite を既定で外すため、単純な「security の単調増加」ではない。3-system deep eval、CRG gate、Claude interactive workflow smoke を採用条件にする。
2. **採用推奨 — Impeccable [`5c5553b1`](https://github.com/pbakaus/impeccable/commit/5c5553b1d7f9e89bb833f9179cea681742a17720)、Remotion [`9f0faa50`](https://github.com/remotion-dev/skills/commit/9f0faa5056c3167d0fc0b7e9575d35284dce98c8)、Orca [`b2612de1`](https://github.com/stablyai/orca/commit/b2612de157d58320f2b90fa319d04c4f8bbab2cd)。** APM 0.28.0 の隔離 materialization で候補 hash を確定した。Impeccable の Design Hook gate は候補 runtime で 9/9、managed fail-open は 1/1 通過した。Remotion は 13 file の version marker 4.0.509 → 4.0.512 だけ、Orca は `orca-cli` の discovery trigger に skill sharing を足すだけである。Anthropic / Shadcn は repository revision だけ進み selected payload は不変なので、同じ lock 再生成へ含めてよい。
3. **据え置き — Matt Pocock [`ed37663c`](https://github.com/mattpocock/skills/commit/ed37663cc5fbef691ddfecd080dff42f7e7e350d)。** 候補 [`9c9f36cc`](https://github.com/mattpocock/skills/commit/9c9f36ccd3995266cd675468af71639c8dde1ec5) は `writing-great-skills` を alias なしで削除し `writing-for-agents` へ置換するうえ、grilling を一問一答から frontier round へ変え、logic prototype を TUI から単一 HTML へ変え、handoff / compact / clear の phase boundary を再定義する。これは pin 前進ではなく workflow migration であり、現行の one-question UI grill、120k smart-zone handoff、cross-ticket Builder-Evaluator 契約と衝突する。8月15日の候補 `8b78b531` 以降の修正もこの不整合を解消していない。

APM CLI の latest release は現行と同じ [`v0.28.0`](https://github.com/microsoft/apm/releases/tag/v0.28.0)。`main` は固定時点の [`8993dcc6`](https://github.com/microsoft/apm/commit/8993dcc6fd7171ef3881a9021a7f25b9439e1a29) まで進み、plugin `bin/` consent、YAML alias budget、gitignored deploy path、marketplace validation 等を直しているが未releaseであり、`llm-agents.nix` 候補も APM 0.28.0 のままである。APM binary は**据え置く**。

## 現行基準（確認済み）

- [`private_dot_config/nix-devshell/flake.nix`](../../private_dot_config/nix-devshell/flake.nix) と [`flake.lock`](../../private_dot_config/nix-devshell/flake.lock) は `llm-agents.nix` `9b760dd766fc31e5ab8c5d6cc6c2c0a7fdd4fa0a` を固定する。shared nixpkgs は `fca2dbd4c00c3063235e56bb91758e24fc67b7b8`、source-only nixpkgs は `421eebfd0ec7bccd4abe826ce62d7e6e83129493`。
- [`modules/ai.nix`](../../private_dot_config/nix-devshell/modules/ai.nix) の floor は Claude Code 2.1.232 / Codex 0.147.0。直接消費する version は Claude Code 2.1.232、Codex 0.147.0、Copilot CLI 1.0.80、Antigravity CLI 1.1.13、RTK 0.45.0、APM 0.28.0、local override を通した code-review-graph 2.3.7。
- [`apm.lock.yaml`](../../apm.lock.yaml) は APM 0.28.0 が `2026-08-14T16:07:05.323344+00:00` に生成した全37 dependencyの materialization record。2026-08-15 の [調査](llm-agents-and-apm-update-2026-08-15.md) と [ADR-0036](../adr/0036-update-llm-agents-and-validated-skill-pins.md) の採用値に一致する。

## 固定した upstream HEAD

| upstream                         | 固定 commit                                                                                                       | selected dependency の現行 revision との差 |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| numtide/llm-agents.nix           | [`5b3a7eff`](https://github.com/numtide/llm-agents.nix/commit/5b3a7eff4326cb9001a79938a53e2fc8662d38c2)           | `9b760dd7` から前進                        |
| anthropics/skills                | [`89dcaa3a`](https://github.com/anthropics/skills/commit/89dcaa3a283f79ed84fd8fe53e2208b9442a6427)                | `f6656c12` から前進                        |
| Effect-TS/skills                 | [`28822c9e`](https://github.com/Effect-TS/skills/commit/28822c9e19998876a6b0e0d97877442012ed4391)                 | exact current                              |
| GoogleChrome/modern-web-guidance | [`9e70fa4c`](https://github.com/GoogleChrome/modern-web-guidance/commit/9e70fa4c808b52364eb85c645e261523231176f6) | exact current                              |
| mattpocock/skills                | [`9c9f36cc`](https://github.com/mattpocock/skills/commit/9c9f36ccd3995266cd675468af71639c8dde1ec5)                | explicit pin `ed37663c` から前進           |
| mizchi/skills                    | [`7a0d7286`](https://github.com/mizchi/skills/commit/7a0d72866a0bb3e9ac3e2768c328b09ba2bc40c4)                    | exact current                              |
| pbakaus/impeccable               | [`5c5553b1`](https://github.com/pbakaus/impeccable/commit/5c5553b1d7f9e89bb833f9179cea681742a17720)               | explicit pin `5a149f3f` から前進           |
| remotion-dev/skills              | [`9f0faa50`](https://github.com/remotion-dev/skills/commit/9f0faa5056c3167d0fc0b7e9575d35284dce98c8)              | `2a204c9b` から前進                        |
| shadcn-ui/ui                     | [`8a7701ec`](https://github.com/shadcn-ui/ui/commit/8a7701ec27eb9cb8e0377db769fbe6d744113c52)                     | `d4fc45b1` から前進                        |
| stablyai/orca                    | [`b2612de1`](https://github.com/stablyai/orca/commit/b2612de157d58320f2b90fa319d04c4f8bbab2cd)                    | `cb42b608` から前進                        |
| supabase/agent-skills            | [`8331f910`](https://github.com/supabase/agent-skills/commit/8331f910845103c08d51f6ca1d86ebb7d1f745e3)            | exact current                              |
| vercel-labs/agent-skills         | [`b8caa260`](https://github.com/vercel-labs/agent-skills/commit/b8caa260a420a73042e35521de4b5c8baf6446cc)         | exact current                              |
| vercel-labs/skills               | [`c6f69c63`](https://github.com/vercel-labs/skills/commit/c6f69c631292444cc541ac6d91e2226b0ff247da)               | exact current                              |
| microsoft/apm                    | [`8993dcc6`](https://github.com/microsoft/apm/commit/8993dcc6fd7171ef3881a9021a7f25b9439e1a29)                    | release v0.28.0 より前進、未release        |

## llm-agents.nix 経路

### 直接消費 package の差分

固定 compare は [`9b760dd7...5b3a7eff`](https://github.com/numtide/llm-agents.nix/compare/9b760dd766fc31e5ab8c5d6cc6c2c0a7fdd4fa0a...5b3a7eff4326cb9001a79938a53e2fc8662d38c2)。各 package directory の Git tree object を比較した結果、Claude Code 以外の6件は byte-level で同一だった。

| package           | 現行 → 候補           | package/source/interface 差分                                                                                                                                                                                      | 判断                                                                               |
| ----------------- | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------- |
| claude-code       | 2.1.232 → **2.1.233** | `hashes.json` の version と3 system hashを更新（[候補 blob](https://github.com/numtide/llm-agents.nix/blob/5b3a7eff4326cb9001a79938a53e2fc8662d38c2/packages/claude-code/hashes.json)）。package interfaceは不変。 | 採用推奨。floor も 2.1.233 へ合わせるが、下記の revert を根拠 comment に明記する。 |
| codex             | 0.147.0 → 0.147.0     | directory tree `73920d00...` で同一（[候補 tree](https://github.com/numtide/llm-agents.nix/tree/5b3a7eff4326cb9001a79938a53e2fc8662d38c2/packages/codex)）。                                                       | snapshot と共に採用。floor 0.147.0維持。                                           |
| copilot-cli       | 1.0.80 → 1.0.80       | directory tree `7c8c02bc...` で同一。                                                                                                                                                                              | snapshot と共に採用。                                                              |
| antigravity-cli   | 1.1.13 → 1.1.13       | directory tree `c91520ce...` で同一。version固有 changelog が未確認という8月15日の留保も継続。                                                                                                                     | snapshot と共に採用。host smokeは維持。                                            |
| rtk               | 0.45.0 → 0.45.0       | directory tree `ba1c84f3...` で同一。                                                                                                                                                                              | snapshot と共に採用。                                                              |
| apm               | 0.28.0 → 0.28.0       | directory tree `bda92b2c...` で同一。                                                                                                                                                                              | 据え置き。                                                                         |
| code-review-graph | 2.3.7 → 2.3.7         | directory tree `f0318a48...` で同一。local override が importする `package.nix` も不変。                                                                                                                           | snapshot と共に採用するが CRG gate は再実行。                                      |

### Claude Code 2.1.233 と quality floor

公式 [`v2.1.233` release](https://github.com/anthropics/claude-code/releases/tag/v2.1.233) から、現行契約に効く変更は次のとおり。

- **security / correctness の採用根拠:** NT `\\??\\` device prefix で UNC validation を迂回し NTLM credential を漏らせる経路を修正。skill / command argument value が template marker として再展開される問題も修正した。後者は APM / chezmoi で多数の skill を配る現構成に直接関係する。
- **Linux / MCP reliability:** sandbox 有効時の idle session が CPU core を100%使い続ける問題、timeoutする MCP v2 listen stream を無限に reopen する問題を修正した。Linux/WSL と多MCP運用に直接関係する。
- **2.1.232 hardening の部分 revert:** Cygwin-style symlink と input redirection に対する2.1.232 Bash permission変更を戻した。したがって現行 floor comment の「Git Bash symlink bypass 修正」を無条件に 2.1.233 へ引き継いだと書いてはいけない。native Windows は当 repo の3 system外であり、Linux protected-path、nested repository trust、cross-session `/tmp` 等を revert したとは release に書かれていないため、対応 systemでは更新を妨げる理由にしない。
- **workflow surface:** Opus 4.8 / Sonnet 5 / Fable 5 / Mythos 5 以降では TaskCreate/Get/Update/List、TodoWrite を既定で外し、必要なら `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` で戻せる。現行 `implement` / `tdd` / `code-review` と repo docs はこれらの tool 名へ依存しないため manifest-level break ではない。ただし AFK multi-ticket work と agent view の進捗観測は interactive smoke で確認し、確認前に env var を追加しない。

**判断:** `minClaudeCode` を 2.1.233 へ上げる根拠はある。ただし「2.1.232 のすべての permission hardeningを保持した上位版」ではなく、対応3 systemでの skill / sandbox / MCP reliability と floor/pin一致を根拠にする。Windows hardeningの後退は明記する。

### flake / overlay / 3-system / CRG

直接 package 以外では、bun2nix overlay を nixpkgs 全体の `pkgs.extend` ではなく package scopeへ直接適用する評価高速化（[`e3b92d0a`](https://github.com/numtide/llm-agents.nix/commit/e3b92d0a453d81a317b55a2964c447c62c585dc8)）と、bun dependency fetchを `builtin:fetchurl` へ寄せる変更（[`abf6bd23`](https://github.com/numtide/llm-agents.nix/commit/abf6bd23c1aeac63cbd628cce2c58e36d1829416)）が入る。`overlays.shared-nixpkgs` の公開名は維持されるが、当 repo は overlay から package scope全体を再構成するため、version表だけで採用完了とはしない。

- `x86_64-linux` / `aarch64-linux` / `aarch64-darwin` の Claude artifact map は維持。x86_64-darwin復活はない。
- `code-review-graph` source treeは同一で、local FastMCP >=3.2.4 / tree-sitter-language-pack >=0.9,<1 overrideも変更不要。ただし scope/evaluation変更を跨ぐので passthru version assert と CLI/MCP smokeを再実行する。
- **未確認:** この調査では候補 pinを入れた `nix flake check --all-systems`、3 systemの `devShells.<system>.default.drvPath` / 7 package deep version eval、Linux build/host CLI smoke、aarch64-darwin実機実行は行っていない。実装の必須 gate とする。

## APM skill 経路

### 全37 dependency の selected content

現行 hash は `apm.lock.yaml`、候補 hash は固定候補を APM 0.28.0 の隔離 `--root` layout に materialize して得た。表で「不変」は candidateの selected tree/blobと `content_hash` が現行と同一、「revisionのみ」は lockの `resolved_commit` だけが変わることを表す。hashは `sha256:` 後の先頭12桁で略記する。隔離解決中に Orca `main` は [`a1cd7eaa`](https://github.com/stablyai/orca/commit/a1cd7eaa7ed558f43312b8608a34181727b2a77c) へ進んだが、固定 `b2612de1` と3 selected `SKILL.md` の blob SHAがすべて同一であることを別途確認したため、表の候補hashは固定時点にも適用できる。実装lockの revisionはその実装時に再固定する。

| upstream / selected dependency   | 現行 revision / hash                  | 固定候補                                                                                                                                                         | selected content                                                                                                                                                                                                                                                                                                            | 判断                                  |
| -------------------------------- | ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- |
| Anthropic `pdf`                  | `f6656c12` / `69e2ac9eb2bb`           | [`89dcaa3a`](https://github.com/anthropics/skills/commit/89dcaa3a283f79ed84fd8fe53e2208b9442a6427)                                                               | tree / hash不変。候補は別 skill `claude-academy-guide` の追加だけ。                                                                                                                                                                                                                                                         | lock再生成時にrevisionのみ採用。      |
| Anthropic `skill-creator`        | `f6656c12` / `b2bfe91d69ca`           | `89dcaa3a`                                                                                                                                                       | tree / hash不変。                                                                                                                                                                                                                                                                                                           | 同上。                                |
| Effect-TS `effect-ts`            | `28822c9e` / `261b9f3f0a89`           | exact current                                                                                                                                                    | 不変。                                                                                                                                                                                                                                                                                                                      | 据え置き。                            |
| Modern Web Guidance              | `9e70fa4c` / `84bf02ecd8c3`           | exact current                                                                                                                                                    | 不変。                                                                                                                                                                                                                                                                                                                      | 据え置き。                            |
| mizchi `empirical-prompt-tuning` | `7a0d7286` / `20e7fba93c72`           | exact current                                                                                                                                                    | 不変。                                                                                                                                                                                                                                                                                                                      | 据え置き。                            |
| Impeccable                       | `5a149f3f` / `b34f5d2af061`           | [`5c5553b1`](https://github.com/pbakaus/impeccable/compare/5a149f3fdb1b5793f10567233b1dcab98fc305fd...5c5553b1d7f9e89bb833f9179cea681742a17720) / `c8bc2e72ad74` | 9 files変更。Design Hook coreは下記のとおり同一。                                                                                                                                                                                                                                                                           | gate通過済み、採用推奨。              |
| Remotion                         | `2a204c9b` / `6a13aa3c04da`           | [`9f0faa50`](https://github.com/remotion-dev/skills/commit/9f0faa5056c3167d0fc0b7e9575d35284dce98c8) / `7bf070f6a8d8`                                            | 13 fileで `version: 4.0.509` → `4.0.512` のみ（[old](https://github.com/remotion-dev/skills/blob/2a204c9b71f7a98997128759cbd2ab557b197fd3/skills/remotion-best-practices/SKILL.md)、[new](https://github.com/remotion-dev/skills/blob/9f0faa5056c3167d0fc0b7e9575d35284dce98c8/skills/remotion-best-practices/SKILL.md)）。 | 採用推奨。                            |
| Shadcn                           | `d4fc45b1` / `8b8c1296ad94`           | [`8a7701ec`](https://github.com/shadcn-ui/ui/commit/8a7701ec27eb9cb8e0377db769fbe6d744113c52)                                                                    | selected tree / hash不変。repo差分はregistry directory。                                                                                                                                                                                                                                                                    | revisionのみ採用。                    |
| Orca `orca-cli`                  | `cb42b608` / `7363d202b2ac`           | [`b2612de1`](https://github.com/stablyai/orca/blob/b2612de157d58320f2b90fa319d04c4f8bbab2cd/skills/orca-cli/SKILL.md) / `cca6a9098e0d`                           | descriptionへ `skill sharing` / `share skills` triggerを追加。usage bodyは不変。                                                                                                                                                                                                                                            | 採用推奨。                            |
| Orca `orchestration`             | `cb42b608` / `b5c364878fb0`           | `b2612de1`                                                                                                                                                       | blob / hash不変。                                                                                                                                                                                                                                                                                                           | revisionのみ採用。                    |
| Orca `computer-use`              | `cb42b608` / `afe48be623c1`           | `b2612de1`                                                                                                                                                       | blob / hash不変。                                                                                                                                                                                                                                                                                                           | revisionのみ採用。                    |
| Supabase Postgres                | `8331f910` / `5766a8e9524c`           | exact current                                                                                                                                                    | 不変。                                                                                                                                                                                                                                                                                                                      | 据え置き。                            |
| Vercel `composition-patterns`    | `b8caa260` / `5b3564ca435f`           | exact current                                                                                                                                                    | 不変。                                                                                                                                                                                                                                                                                                                      | 据え置き。                            |
| Vercel `react-best-practices`    | `b8caa260` / `74f142d28d36`           | exact current                                                                                                                                                    | 不変。                                                                                                                                                                                                                                                                                                                      | 据え置き。                            |
| Vercel `react-view-transitions`  | `b8caa260` / `aa4cf8be5be5`           | exact current                                                                                                                                                    | 不変。                                                                                                                                                                                                                                                                                                                      | 据え置き。                            |
| Vercel `web-design-guidelines`   | `b8caa260` / `a6a44d5498f7`           | exact current                                                                                                                                                    | 不変。                                                                                                                                                                                                                                                                                                                      | 据え置き。                            |
| Vercel `find-skills`             | `c6f69c63` / `913b9d37d0d5`           | exact current                                                                                                                                                    | 不変。                                                                                                                                                                                                                                                                                                                      | 据え置き。                            |
| Matt Pocock 20件                 | `ed37663c` / dependencyごとの現行hash | [`9c9f36cc`](https://github.com/mattpocock/skills/compare/ed37663cc5fbef691ddfecd080dff42f7e7e350d...9c9f36ccd3995266cd675468af71639c8dde1ec5)                   | 3 tree不変、16変更、`writing-great-skills`削除。                                                                                                                                                                                                                                                                            | 全20件を据え置き。別migrationで扱う。 |

以上で `2 + 1 + 1 + 1 + 1 + 1 + 1 + 3 + 1 + 4 + 1 + 20 = 37` dependencyを網羅する。

### Impeccable Design Hook 契約

候補 selected subtree は9 files / +320 -56。主変更は finish reviewer の GROUND fidelity、raster provenance / prompt scan、surface route normalization、static HTML selector compile cacheである（[固定 compare](https://github.com/pbakaus/impeccable/compare/5a149f3fdb1b5793f10567233b1dcab98fc305fd...5c5553b1d7f9e89bb833f9179cea681742a17720)）。

自動実行される契約の source object を比較すると、次は**同一 blob**だった。

- `scripts/hook.mjs`、`scripts/hook-lib.mjs`: stdin JSON event、PostToolUse / Stop分岐、always-exit-0、quiet output、full/short footer、dedupe、both-tiers memory挙動。
- `scripts/hook-admin.mjs`: `ignore-value --reason`、`ignore-file`、`ignore-rule` の永続化interface。
- `scripts/detector/findings.mjs`、`scripts/lib/impeccable-config.mjs`: finding policyとignore config。

変わる detector code は `closest()` selectorを document単位で compile/cacheする性能修正（[候補 source](https://github.com/pbakaus/impeccable/blob/5c5553b1d7f9e89bb833f9179cea681742a17720/.agents/skills/impeccable/scripts/detector/engines/static-html/css-cascade.mjs#L835-L904)）で、意図された finding policy 変更ではない。ただし自動実行 runtime の selected payload自体は変わるため、source比較だけで採用とはしなかった。

APM 0.28.0 の隔離候補 runtimeに対する実測:

- `tests/design-hook.bats`: **9/9 pass**。immediate tier、full footer初回 / short footer後続、理由付き `ignore-value` の finding value限定保存、`ignore-file` / `ignore-rule` の承認境界、quiet path、Stop deep pass、dedupe、edit threshold、Stop re-entryを維持。
- both-tiers Stop の immediate / deferred交互報告 characterizationは候補でも passした。つまり既知 defectは**修正されていない**ため、願望仕様へtestを書き換えない。
- `tests/codex-config.bats` の managed Design Hook fail-open slice: **1/1 pass**。runtime未配備 / 内部失敗 / 非0終了を advisory成功として扱うwrapper契約を維持。

**判断:** `5c5553b1` を新しい検証済み pin 候補として採用してよい。`ignore-value` の自己適用は確信ある false positive / 許容済み例外だけ、理由をユーザーへ開示する。file / rule全体を隠す `ignore-file` / `ignore-rule` は明示承認を要する。Claude / Codex の PostToolUse + Stop配線、timeout、fail-open wrapperは変更しない。

## Matt Pocock workflow 契約

現行は package metadata 1.1.0の `ed37663c`、候補は metadata 1.2.3の `9c9f36cc`。8月15日に固定した候補 [`8b78b531`](https://github.com/mattpocock/skills/commit/8b78b531ab965735c5dc74f6f7a219e1e37326df) から今回HEADまでの selected skill差分は、cross-skill invocationを harness-neutralな “call the Skill tool” へ揃え、user-invoked preconditionを別skillから直接呼ばずユーザーへ案内する修正が中心（[固定 compare](https://github.com/mattpocock/skills/compare/8b78b531ab965735c5dc74f6f7a219e1e37326df...9c9f36ccd3995266cd675468af71639c8dde1ec5)）。良い修正だが、8月15日に見つかったmigration blockerは残る。

| 契約面                     | 候補の実差分                                                                                                                                                                                                                                                                                                                                                     | 現行ローカル契約との判定                                                                                                                                |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ask-matt` router          | 新しい [`PHASE-BOUNDARIES.md`](https://github.com/mattpocock/skills/blob/9c9f36ccd3995266cd675468af71639c8dde1ec5/skills/engineering/ask-matt/PHASE-BOUNDARIES.md) を追加。Continue → clear → handoff → subagent → compact の順で判断し、smart zone目安を120kから150kへ変更。`to-questionnaire` / `wizard` / `wait-what` / `writing-for-agents` もrouterへ追加。 | 現行の120k到達時 `/handoff`、同一worktree/branchでのcross-ticket継続、導入skill最小集合と不一致。新規router先3件も未導入。                              |
| `grill-with-docs`          | `Run a /grilling session` から `grilling` と `domain-modeling` を別々に Skill toolで呼ぶ形へ明確化（[candidate](https://github.com/mattpocock/skills/blob/9c9f36ccd3995266cd675468af71639c8dde1ec5/skills/engineering/grill-with-docs/SKILL.md)）。                                                                                                              | cross-skill invocationの明確化自体は互換。依存先 `grilling` の意味変更が非互換。                                                                        |
| `grilling`                 | 一問ずつ待つ方式から、依存が解けた全質問を1 roundで聞く **frontier interview** へ変更し、facts探索をsubagentへdispatchする（[candidate](https://github.com/mattpocock/skills/blob/9c9f36ccd3995266cd675468af71639c8dde1ec5/skills/productivity/grilling/SKILL.md)）。                                                                                            | `local-skills/ui-grill-with-docs` の「same one-question-at-a-time loop」と正面衝突。採用には派生skillと質問UXの再設計が必要。                           |
| `prototype`                | logic prototypeを host languageのTUIから、非開発者へ渡せる単一HTML + free-play + guided walkthroughへ変更（[candidate LOGIC](https://github.com/mattpocock/skills/blob/9c9f36ccd3995266cd675468af71639c8dde1ec5/skills/engineering/prototype/LOGIC.md)）。prototype branchをprimary sourceとして残す方針は維持。                                                 | artifact / runtime / handoffが変わるため、単純pin前進ではない。HTML prototypeの配置・ブラウザ検証・削除方針を決める必要がある。                         |
| `handoff` / phase boundary | `handoff` skill本体は Skill tool wordingのみだが、routerは用途を「別harness・別directory・同僚・mid-phase side task」に狭め、同じdirectoryでの通常継続はcompactをdefaultにする。ticket間は `/clear`。                                                                                                                                                            | ADR-0019 / ADR-0022 と `runtime/skill-harness.md` の smart-zone handoff と、同一worktree内でticketを跨ぐBuilder-Evaluator方針を先に調停する必要がある。 |
| `to-spec` / `to-tickets`   | setupが無い時に別user-invoked skillを自動callせず「ユーザーへsetup実行を案内」に変更。spec/ticket templateとvertical slice本体は維持。                                                                                                                                                                                                                           | precondition境界は改善で互換。routerのticket間clearはローカル上書きと非互換。                                                                           |
| `implement`                | selected treeは**完全同一**。TDD → typecheck / focused test → full suite → code-review → commitの単位は不変。                                                                                                                                                                                                                                                    | Builder-Evaluator入口自体は互換。ただしrouter側のclear policyを採らない。                                                                               |
| `tdd`                      | interfaceのshape自体が問題なら `codebase-design` をSkill toolで参照する一段を追加。                                                                                                                                                                                                                                                                              | 現行のdeep-module vocabularyと整合し、単独では採用可能な変更。                                                                                          |
| `code-review`              | Standards + Spec parallel subagentsは維持。Claude固有のAgent tool名を削り、setup preconditionをユーザー案内へ変更。                                                                                                                                                                                                                                              | 現行のknown-base local overrideと併用可能。core review契約は互換。                                                                                      |
| rename                     | `skills/productivity/writing-great-skills` を削除し、`writing-for-agents`へaliasなしrename（[rename commit](https://github.com/mattpocock/skills/commit/1fc6573e0e300118ce342fb9365521c9c34eefd4)）。                                                                                                                                                            | 現 `apm.yml` pathは候補commitで解決不能。manifest、ADR-0010、runtime docs、trigger/selection auditを同時移行する必要がある。                            |
| その他 selected skills     | `research` / `resolving-merge-conflicts` はtree同一。`diagnosing-bugs` のsecret redaction、`domain-modeling` trigger、wayfinder / triage等のinvocation wordingは改善。                                                                                                                                                                                           | 個別改善はあるが、20件を同一workflow snapshotとして固定する現方針を崩してcherry-pickする緊急性はない。                                                  |

**判断:** Matt 20 dependencyは `ed37663c` に据え置く。採用するなら最低限、(1) `writing-for-agents` rename、(2) routerが指す未導入skillの採否、(3) grilling frontier roundと `ui-grill-with-docs`、(4) prototype HTML、(5) handoff / compact / clearとcross-ticket autonomy、(6) 120k/150k smart-zone表記を一つの ADR / workflow migrationとして決める。pinだけを動かさない。

## APM CLI 0.28.0 以降

latest releaseは v0.28.0のまま。固定 `main` との差は [`v0.28.0...8993dcc6`](https://github.com/microsoft/apm/compare/v0.28.0...8993dcc6fd7171ef3881a9021a7f25b9439e1a29)。未release差分には次がある。

- plugin `bin/` 実行への `--trust-bin` / `--no-trust-bin` consent。
- anchor-free YAMLをalias-expansion budgetから外しつつ、alias bomb testを追加。
- gitignored deploy pathの `deployed-files-present` false positive修正。
- malformed marketplace/plugin structureの診断強化。
- SSH passphrase hangのfail-fast、multi-target compile解析の再利用、Windows Authenticode signing。

現行 manifestはskill subdirectoryだけでplugin `bin/`を配らず、候補lockのmaterializationも APM 0.28.0 で成功した。未release `main` を別経路でpackageする理由はない。次のreleaseが出た時に lock schema、`install --frozen --https`、shared hub / Claude target deployment、new consent promptの非対話動作を再評価する。

## 推奨する実装順と verification

### 1. llm-agents snapshot

1. `llm-agents` を `5b3a7eff`へ固定し、`minClaudeCode`を2.1.233へ上げる。floor commentから「Cygwin/Git Bash symlink hardeningが維持される」という誤読を除き、revertを明記する。
2. `nix flake check --all-systems`。
3. `x86_64-linux` / `aarch64-linux` / `aarch64-darwin` の `devShells.<system>.default.drvPath` と7 package versionを同じ shared overlay経路でdeep eval。
4. Linuxで7 CLIの `--version` / 起動 smoke、CRGの FastMCP / tree-sitter passthru assert、core graph + stdio MCP smoke。
5. Claude interactiveで background/fork、wait/message、worktree context、skill argument、Task\*/TodoWriteなしでの implement進捗を確認。必要性が実測されるまで `CLAUDE_CODE_ENABLE_TODO_TOOLS` は追加しない。

### 2. APM non-Matt lock round

1. Impeccableだけ exact `5c5553b1`へ進め、Matt 20件は `ed37663c`維持。floating dependencyは固定時点HEADへ解決してlockを再生成。
2. APM 0.28.0の隔離runtime layoutで `apm install --frozen --https` が書戻しなしになることを確認。
3. `tests/design-hook.bats` 9/9、managed fail-open、`tests/apm-runtime.bats`、全suiteを再実行。候補runtime単体のDesign Hook gateは本調査で通過済みだが、repo変更後の統合testは別に必要。
4. `chezmoi apply`前に生成lockとsource pinをreviewし、ライブ `~/.agents/skills` / `~/.claude/skills` は調査段階では触らない。

### 3. Matt migrationは別作業

`grill-with-docs` から開始し、上記6 decisionを解いた後に spec / ticket化する。現更新roundへ混ぜない。

## 未確認と留保

- 候補 `llm-agents.nix` の3-system Nix評価・build・host runtimeは未実行。
- aarch64-darwin実機、Antigravity 1.1.13 version固有差分、Claude 2.1.233 interactive agent workflowは未確認。
- APM候補runtimeの Design Hook 9/9とfail-open 1/1は確認済みだが、全Bats suiteと候補lockのfrozen再現は実装roundで行う。
- Matt候補はsource-level比較だけで、現行workflow docsを候補へ書換えた end-to-end rehearsalは行っていない。これは据え置き判断の前提であり、互換確認済みを意味しない。
