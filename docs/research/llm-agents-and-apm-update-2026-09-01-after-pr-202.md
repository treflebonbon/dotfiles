---
type: research
title: PR #202 後の LLM agent tool と APM skill 更新候補（2026-09-01）
description: PR #202 の Orca native worktree 契約を基準に、llm-agents.nix の tool snapshot と APM 管理 skill の upstream 差分を一次情報だけで比較した調査ノート。
tags: [research, llm-agents, apm, skills, orca, worktree, claude-code, codex]
timestamp: 2026-09-01
---

# PR #202 後の LLM agent tool と APM skill 更新候補（2026-09-01）

このノートの日付・履歴表記は JST（Asia/Tokyo）を基準とする。外部リポジトリの時刻は原則 UTC で併記した。

## 結論

調査基準は PR #202 の merge commit [`a800002b`](https://github.com/treflebonbon/dotfiles/commit/a800002b9a77e9112532c707cf8acfd38ee225ae) を含む linked worktree の `HEAD` である。PR #202 と [ADR-0046](../adr/0046-separate-orca-native-worktree-entry.md) が確定した責務分離（Orca は native worktree + Agent Picker、`to-worktree` は非 Orca runtime、Orca native Codex に `codex-orca` / `codex-worktree` を使わない）を変更する候補は採用対象にしない。

現行の user devShell は [private_dot_config/nix-devshell/flake.nix](../../private_dot_config/nix-devshell/flake.nix) の `llm-agents` exact revision `4a9441120caf6c6aff273af68995267a35c20fcd` を [flake.lock](../../private_dot_config/nix-devshell/flake.lock) で固定している。公式 `llm-agents.nix` main は [`ea1dc213`](https://github.com/numtide/llm-agents.nix/commit/ea1dc2132fb2669899dc8b3cbe6fe82ed10d23d6)（2026-09-01 01:19:47 UTC）まで進み、当 repo が実際に配備する package のうち Claude Code、Codex、Copilot CLI、Antigravity CLI、APM が更新されている。その39分後に公式 OpenAI stable [`rust-v0.152.0`](https://github.com/openai/codex/releases/tag/rust-v0.152.0)（2026-09-01 01:58:32 UTC）が公開されたが、この調査時点の Nix snapshot は `0.151.0` までである。[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md) の「特定 release の収録を待ち続けない」契約に従い、`0.151.0` は更新候補とし、実装入口の一度だけの再確認で `0.152.0` が収録済みなら追加の互換性ゲートを適用する。

実装時の第一候補は、次の独立した更新単位である。

| 更新単位                  | 現行                      | 公式候補              | 分類                      | 主な理由・境界                                                                                                                                                                     |
| ------------------------- | ------------------------- | --------------------- | ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `llm-agents.nix` snapshot | `4a944112`                | `ea1dc213`            | 更新推奨（gate 必須）     | Claude 2.1.252、Codex 0.151.0、Copilot 1.0.82、Antigravity 1.1.22、APM 0.29.0 を収録。3 system metadata/build/startup smoke と APM gate が必要。                                   |
| Claude floor              | 2.1.247                   | 2.1.252               | 更新推奨（gate 必須）     | worktree lock、symlink TOCTOU、deny rule、background worktree、hook/plugin race、task output path の修正。settings/hooks/worktree の回帰確認が必要。                               |
| Codex floor               | 0.150.0                   | Nix candidate 0.151.0 | 更新推奨（gate 必須）     | 0.151.0 の permission/sandbox/Guardian 修正を floor 根拠にできる。実装入口で snapshot が 0.152.0 まで進んでいれば、`update_plan` opt-in と workflow 互換性も同じ gate で確認する。 |
| Copilot CLI               | 1.0.80                    | 1.0.82                | 更新推奨                  | `/worktree` / `/move` 準備中の入力で switch が壊れる問題を修正。                                                                                                                   |
| Antigravity CLI           | 1.1.21                    | 1.1.22                | 要追加検証                | 公式 package artifact metadata は確認できるが、version 固有の first-party changelog は確認できない。startup/version smoke を先に行う。                                             |
| APM                       | 0.28.0                    | 0.29.0                | 更新推奨（APM gate 必須） | frozen cold-cache、deterministic hash、audit、selected components、OpenCode user-scope、plugin consent 等を修正。ただし native Agent Plugin 登録など配備面の変更がある。           |
| OpenCode                  | snapshot metadata 1.18.23 | 1.18.25               | 据え置き                  | package は snapshot 内にあるが [modules/ai.nix](../../private_dot_config/nix-devshell/modules/ai.nix) の配備 list に含まれない。導入を別途決めるまで更新対象にしない。             |
| RTK / code-review-graph   | 0.46.0 / 2.3.8            | 変更なし              | 据え置き                  | `4a944...` → `ea1dc...` の当該 package source に実体差分なし。CRG の local Python override は別契約として維持。                                                                    |

APM skill は、通常 payload、Impeccable hook、Matt Pocock workflow を混在させない [ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md) の四単位に従う。通常 payload の候補は Modern Web Guidance、Remotion、shadcn、Effect-TS、Vercel View Transitions、Orca の3 skillである。Impeccable は main に大量の未タグ差分があるが現行 exact tag `skill-v4.1.2` を維持する。Matt Pocock は現行 exact revision と main が一致するため維持する。

## Plannerで確定した採用方針

2026-09-01の`grill-with-docs`では、調査後に残った判断を次のように確定した。

- Effect-TSの`effect@beta`から`effect@rc`へのguidance更新を、通常APM payload更新に含める。既存のfloating方針を維持し、candidate payloadと両target discoveryで確認する。
- Vercel React View Transitionsの大幅なreference更新を、通常APM payload更新に含める。React / Next.js一次ドキュメントとの互換性をcandidate-specific gateで確認する。
- 実装入口のsnapshotがCodex 0.152.0を収録していても、`tools.update_plan.enabled = true`は追加せずupstream既定を受け入れる。repository contractとしてplanning toolを必須化せず、planning toolなしで既存skill flowが成立することをsmokeで確認する。
- Tool snapshot更新と通常APM payload更新は、独立したreview・merge・rollback境界を持つ2本のPRへ分ける。
- 2本のPRはstackせず直列化する。Tool snapshot PRをmergeした後、更新済み`main`から新しいOrca native worktree / agent sessionを開始し、accepted APM 0.29.0で通常payloadのlockを生成する。
- 現在の`chezmoi source-path`はprimary checkoutを指しており、このlinked worktreeとは異なる。未mergeのworktreeをlive sourceとして適用せず、両source更新の受入後に正しいsourceを確認して最終配備する。

これらは既存の「更新単位」と[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md)の境界を変更しない。新しいdomain termやhard-to-reverseなarchitecture decisionではないため、`CONTEXT.md`の語彙追加や新規ADRは行わない。

## 確認した現行宣言・契約

- [apm.yml](../../apm.yml) は Claude / Codex の2 targetを宣言し、18 dependencyを APM のみで管理する。Impeccable、Remotion、Modern Web Guidance、Matt Pocock、Orca `orca-cli` は exact revision、その他は既存方針どおり floating である。
- [apm.lock.yaml](../../apm.lock.yaml) は `generated_at: 2026-08-27`、`apm_version: 0.28.0`。現行の selected content hash は各 entry に保持され、APM install を実行せず手書き変更してはならない。
- [runtime/skill-harness.md](../../runtime/skill-harness.md) は Worktree Entry Point を共通契約として残し、Orca native worktree と非 Orca `to-worktree` を分離する。Orca native launch に repository adapter を挿入しない。
- [ADR-0011](../adr/0011-orca-skills-via-apm.md) は Orca skill を APM で管理し、Orca in-app updater や `npx skills update` と混在させない。
- [ADR-0033](../adr/0033-update-llm-agents-snapshot-and-claude-baseline.md)、[ADR-0042](../adr/0042-mattpocock-managed-set-update-gate.md)、[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md)、[ADR-0046](../adr/0046-separate-orca-native-worktree-entry.md) は、それぞれ snapshot/floor、Matt full set、更新単位、Orca worktree ownership の正本である。

## `llm-agents.nix` と CLI の一次情報

### snapshot の差分

公式 compare [`4a944112...ea1dc213`](https://github.com/numtide/llm-agents.nix/compare/4a9441120caf6c6aff273af68995267a35c20fcd...ea1dc2132fb2669899dc8b3cbe6fe82ed10d23d6) は 394 commit ahead であり、当 repo の package に関係する変更は次の通りだった。

| package             | 現行 version | `ea1dc213` の package metadata | upstream 更新 commit                                                                                    | 判定                                              |
| ------------------- | -----------: | -----------------------------: | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| `claude-code`       |      2.1.247 |                        2.1.252 | [`fe4adeb1`](https://github.com/numtide/llm-agents.nix/commit/fe4adeb1ef72b390728e20980fba1f72e8d36410) | 更新推奨                                          |
| `codex`             |      0.150.0 |                        0.151.0 | [`4d05da6a`](https://github.com/numtide/llm-agents.nix/commit/4d05da6a69dfe525c74a55ea2e87b71aea011144) | 更新推奨。実装入口で0.152.0収録済みなら追加ゲート |
| `copilot-cli`       |       1.0.80 |                         1.0.82 | [`6c120d66`](https://github.com/numtide/llm-agents.nix/commit/6c120d6659b2e822998781c9cbc4976cd216954f) | 更新推奨                                          |
| `antigravity-cli`   |       1.1.21 |                         1.1.22 | [`854c16ae`](https://github.com/numtide/llm-agents.nix/commit/854c16aeead9711a7127fd560f51c3a471f00e40) | 要追加検証                                        |
| `apm`               |       0.28.0 |                         0.29.0 | [`ea282db9`](https://github.com/numtide/llm-agents.nix/commit/ea282db9bb50e63a8d1be32be0df8abcf3308cfd) | 更新推奨（APM gate）                              |
| `opencode`          |      1.18.23 |                        1.18.25 | [`9ab648f5`](https://github.com/numtide/llm-agents.nix/commit/9ab648f5e0c685fb3a4a53dcca8c8e671dd34bcd) | 据え置き（未配備）                                |
| `rtk`               |       0.46.0 |                         0.46.0 | main compare で差分なし                                                                                 | 据え置き                                          |
| `code-review-graph` |        2.3.8 |                          2.3.8 | package source差分なし                                                                                  | 据え置き                                          |

公式 hashes metadata は [`claude-code`](https://raw.githubusercontent.com/numtide/llm-agents.nix/ea1dc2132fb2669899dc8b3cbe6fe82ed10d23d6/packages/claude-code/hashes.json)、[`codex`](https://raw.githubusercontent.com/numtide/llm-agents.nix/ea1dc2132fb2669899dc8b3cbe6fe82ed10d23d6/packages/codex/hashes.json)、[`copilot-cli`](https://raw.githubusercontent.com/numtide/llm-agents.nix/ea1dc2132fb2669899dc8b3cbe6fe82ed10d23d6/packages/copilot-cli/hashes.json)、[`antigravity-cli`](https://raw.githubusercontent.com/numtide/llm-agents.nix/ea1dc2132fb2669899dc8b3cbe6fe82ed10d23d6/packages/antigravity-cli/hashes.json) にある。3 system の URL/hash を含むため、実装時は `nix flake check --no-build --all-systems` と host build/version smoke を行う。

### Claude Code

公式 stable [`v2.1.252`](https://github.com/anthropics/claude-code/releases/tag/v2.1.252)（2026-08-31公開）は、task output path が移動・リンクされた場合のエラー、project に local settings がない場合の always-allow 保存、Remote Control の degraded connection、巨大 failure output の request overflow を修正した。現行 floor 2.1.247 以降の公式 [`v2.1.251`](https://github.com/anthropics/claude-code/releases/tag/v2.1.251) は、file tool の symlink swap、plugin path traversal、Grep/Glob の symlink deny rule、background worktree lock、plugin skill refresh race、managed settings による sandbox 弱化などを修正している。これらは本 repo の worktree、hook、permission 契約に直接関係するため、2.1.252 への floor 更新は更新推奨である。

ただし 2.1.248〜2.1.251 は `--restricted`、managed settings approval、sandbox/telemetry、background session などの挙動も変更している。`settings.json`、managed hook、worktree session、teammate/auto mode の startup smoke を gate に含め、release note にない挙動を推測して floor を先に変えない。

### Codex

公式 stable [`rust-v0.151.0`](https://github.com/openai/codex/releases/tag/rust-v0.151.0) は permission profile 復元、`/cd` 後の sandbox 保持、remote executor の home/OS/path semantics、stale Guardian approval、MCP cache/error の修正を含む。現行 0.150.0 からの更新根拠は十分であり、Nix main の 0.151.0 は候補になる。

しかし調査時点の公式最新 stable は [`rust-v0.152.0`](https://github.com/openai/codex/releases/tag/rust-v0.152.0) である。0.152.0 は per-tool MCP output limit、remote plugin/cache refresh、trusted cloud-task URL、permission/Guardian compaction保持などを追加・修正する一方、planning tool を既定無効にし `tools.update_plan.enabled = true` の opt-in に変更した。この repo の Codex config と workflow 文書には `update_plan` の明示設定・参照がないため、repository contract への直接影響は未確認である。実装入口で `llm-agents.nix` が0.152.0を収録済みなら、実 runtime で planning tool が必要かを確認し、必要な場合だけ opt-in を snapshot/floor 更新と同じ gate に含める。収録されていなければ0.151.0候補を採用し、0.152.0を待機理由にしない（confirmed: release bodyとrepo内参照なし、inferred: planningを使うruntimeへの影響、unconfirmed: current model/runtimeによるtool提供状況）。

### Copilot CLI、Antigravity CLI、APM、OpenCode

公式 Copilot stable [`v1.0.82`](https://github.com/github/copilot-cli/releases/tag/v1.0.82) は、`/worktree` または `/move` の worktree preparation 中に入力されたメッセージで switch が壊れる問題を修正した。Orca native worktree ownership とは別の CLI の局所修正であり、1.0.80 からの更新を推奨する。

`llm-agents.nix` の [`antigravity-cli` metadata](https://raw.githubusercontent.com/numtide/llm-agents.nix/ea1dc2132fb2669899dc8b3cbe6fe82ed10d23d6/packages/antigravity-cli/hashes.json) は 1.1.22 の3 system artifact URL/hashを収録している。package updater commit は公式 CLI URL [`antigravity.google/cli`](https://antigravity.google/cli) を示すが、1.1.22 固有の release note/changelog は確認できなかったため、version metadata の更新候補に留め、起動・help・必要な auth boundary の確認を追加する。

公式 APM [`v0.29.0`](https://github.com/microsoft/apm/releases/tag/v0.29.0) は、frozen install の cold-cache failure、生成物の deterministic LF、audit hook preservation、selected component deployment、OpenCode user-scope skill、plugin bin consent (`--trust-bin` / `--no-trust-bin`)、native Agent Plugin foundation などを含む。これは現行 `apm.yml` の Claude/Codex target と lock/deployment ownership に効くため更新推奨だが、APM 0.29 の native plugin registration と既存の APM-only 経路が競合しないか、隔離 HOME の `apm install --https` / frozen / audit / discovery で検証する。Nix main の更新は [`ea282db9`](https://github.com/numtide/llm-agents.nix/commit/ea282db9bb50e63a8d1be32be0df8abcf3308cfd) である。

公式 OpenCode stable [`v1.18.25`](https://github.com/anomalyco/opencode/releases/tag/v1.18.25) は Azure CLI authentication の修正を含む。Nix snapshotにも metadata はあるが、当 repo の [modules/ai.nix](../../private_dot_config/nix-devshell/modules/ai.nix) では `llm.opencode` を packages に追加していないため、今回の更新で新規配備しない。

## APM skill の upstream 差分

候補は現行 lock の `resolved_commit` から各 repo の default branch / latest official release へ比較した。content hash の最終採否は APM の native lock 生成でしか確認できないため、本調査では upstream selected subtree の実体差分と compatibility risk を確認し、lock は変更していない。

### 更新推奨（通常 APM payload refresh）

#### Modern Web Guidance

現行 exact pin `457c381def89ce6213a171238f92eea63e9eaeb2`（v0.0.185）に対し、公式 [`v0.0.186`](https://github.com/GoogleChrome/modern-web-guidance/releases/tag/v0.0.186) / [`56c61c9e`](https://github.com/GoogleChrome/modern-web-guidance/commit/56c61c9ee79a8df1a98822309c04847a57f56000)（2026-08-31公開）は selected subtree を変更した。`ime-safe-enter-submit.md` を新設し、`KeyboardEvent.isComposing` と Safari 向け `keyCode === 229` / timestamp fallback を扱う。SKILL.md は retrieved guide との verification、出力 truncation 時のファイル redirect、`pnpx` 優先と scoped allowlist を追加した。日本語 IME を使うこの環境に直接有用であるため、exact pinを v0.0.186へ進める候補とする。APM materialization 後に両 target discovery と security guidance の差分を確認する。

#### Remotion

現行 exact pin [`7a3d0ca4`](https://github.com/remotion-dev/skills/commit/7a3d0ca45d2f6a00bf35cb3c525734a36d55a834) の selected subtree（version 4.0.518）に対し、公式 main [`357a2708`](https://github.com/remotion-dev/skills/commit/357a270803b23e16b32bec65df07c41a62e94bd9)（2026-08-31）は SKILL.md と12の reference の version marker を 4.0.519 に更新した。compare では各ファイルが1行の version-only changeで、guidance本文の変更は確認できない。このため exact pin を進める低リスク候補だが、APM lock の content hash と両 target discovery は必ず再確認する。

#### shadcn

現行 floating entry は lockで `683a5a9b...` に解決されている。公式 main の selected diff [`503a3a57`](https://github.com/shadcn-ui/ui/commit/503a3a57aec9a3817e37f90aa0817b1fabd284d0) は `rules/chat.md` に SSR transcript の hydration jump を避ける `data-pending-scroll` / `suppressHydrationWarning` / CSP nonce の guidance を追加した。chat UI を対象にする skill の実体改善であり、通常 APM refresh の更新推奨候補とする。lock hash、skill discovery、chat guidanceの内容確認を行う。

#### Effect-TS

現行 lock `28822c9e...` から公式 [`2309e6f2`](https://github.com/Effect-TS/skills/commit/2309e6f27d9955b434c0e3f394b945c136e89fd2) は、Effect v4 が RC に入ったことを理由に install guidance の `effect@beta` を `effect@rc` へ変更した。repo の Effect v4 migration と一致する更新候補だが、実プロジェクトが stable v3 または beta を要求する場合は install guidance が変わる。APM refresh で取得し、ユーザーの package policy と skill discovery を追加確認する。

#### Vercel React View Transitions

現行 floating entry の accepted commit は `dd089a8c752c966dee8bf0f27cb625ba193ffd9e`。公式 selected subtree は [`0c04547b`](https://github.com/vercel-labs/agent-skills/commit/0c04547b953d49d5e91f512a7c4a6ecfcb3a7055) まで11 commit進み、SKILL.md と reference群に実体差分がある。Next.js の obsolete `experimental.viewTransition` 設定記述を除き、`transitionTypes` guidanceへ整理し、nested View Transition limitation と troubleshooting reference を追加した。CSS recipes をそのままコピーする指示を「適用対象に合わせて adapt」に緩和した。API/config guidance の変更を含むため、通常 payload の候補ではあるが、React/Next.js version compatibility と discovery を追加検証してから採用する。

### Orca skills（通常 payload、契約非変更）

Orca の現行 selected payload は `orca-cli` exact `5ca747dad0d0583f4a1ac91c2655b345ba6c07eb`、`orchestration` / `computer-use` floating が lockで `026389a3bc03da03ca2d65295e805493712b0774`。公式 [`b44ef1e5`](https://github.com/stablyai/orca/commit/b44ef1e59db4399cbd3a0615d29345de601885e7)（2026-08-31 22:57:52 UTC）は3 selected SKILL.mdを同時に変更した。

- `orca-cli` は Computer Use を external browser の OS/window-level 操作に限定し、Orca embedded pages は `orca-cli`、external page automation は Playwright/CDP と明示した。
- `orchestration` は terminal/embedded browser と external browser OS/window 操作の routing 境界を同じ wording へ揃えた。
- `computer-use` は native app / external browser window の OS-level surface に限定し、Orca embedded browser と page-only automation を除外した。

current pin → `b44ef1e5` の SKILL.md SHA-256 は次の通りである。これは b44 commit の実体差分を raw source から確認した値で、APM content hash ではない。

| skill           | 現行 SKILL.md SHA-256                                              | b44/main SHA-256                                                   |
| --------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------ |
| `orca-cli`      | `cdd5d9c8a95837a6cc24d68b150a117684afe9bbb2d763de2cc7fba1da1ed163` | `6dcbd69045c74787be3385198750c67223709c5fa63a2ba3cfbbe0403e1219f5` |
| `orchestration` | `9ca228137b9a442b98c761aa07adecc2265708132ab175ad7e22b163fdc0bd7f` | `a7e3350f037698ebbce36b2818d8383ec6e96c2a4825537caab39a83b4fb4b7f` |
| `computer-use`  | `c4a11596b7c0338f4c991b24ba7ba453d93fb8dc045c642c517e7ae6d3c88467` | `a3fcca06875e354a470e7daef5619172a3615fbbf82900ff3e0a65636fc694c6` |

これはブラウザ責務の routing 文言を狭める更新であり、PR #202 / ADR-0046 の Orca native worktree ownership、Agent Picker、permission mode、`codex-orca` / `codex-worktree` 非使用を変更しない（confirmed: b44 の3 SKILL.md diffと ADR、inferred: 契約への非影響、unconfirmed: live Orca binary の実行時 discovery）。`orca-cli` は exact pinを `b44ef1e5` へ更新し、他2件は既存 floating 方針のまま同一 APM generationで再解決する候補とする。

### 据え置き / 独立 gate

#### Impeccable

現行 exact tag は `skill-v4.1.2` / [`63b04e25`](https://github.com/pbakaus/impeccable/releases/tag/skill-v4.1.2)。公式 main [`40b51512`](https://github.com/pbakaus/impeccable/commit/40b51512377019202e28e534e2316017b84671b1) は 2026-09-01 時点で118 commit相当の selected subtree差分を持ち、新しい `build-phase.mjs`、composition diff/spec、font fingerprint/index、hero checks、detector、hook/live server等を含む。これは Design Hook、runtime scripts、detector、provider output を横断するため、通常 payload refreshへ混ぜない。新しい skill tag が出てから [ADR-0029](../adr/0029-impeccable-pin-advance-with-stop-hook.md) / [ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md) の独立 Design Hook gateで扱う。

#### Matt Pocock full set

現行 exact revision [`6654f6b6`](https://github.com/mattpocock/skills/commit/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76) は公式 main と一致し、selected full setに upstream差分がない。membership 25 skill、frontier separator、explicit Skill tool invocation、setup未済時の user pointer は現行 payloadを維持する。更新する場合も [ADR-0042](../adr/0042-mattpocock-managed-set-update-gate.md) の ordered gateを単独で通し、通常 APM refreshへ混ぜない。

#### 変更なしの selected subtree

次の依存は現行 `resolved_commit` から公式 default branch を比較して selected subtree に実体差分がなかったため据え置く。

| dependency                                             | 現行 resolved commit | 公式比較結果             |
| ------------------------------------------------------ | -------------------- | ------------------------ |
| `anthropics/skills/pdf`                                | `3b3fad96`           | main と同一              |
| `anthropics/skills/skill-creator`                      | `3b3fad96`           | main と同一              |
| `supabase/agent-skills`                                | `8331f910`           | main と同一              |
| `mizchi/skills/empirical-prompt-tuning`                | `7a0d7286`           | main と同一              |
| `vercel-labs/skills/find-skills`                       | `435076e7`           | main と同一              |
| Vercel web-design / React best practices / composition | `dd089a8c`           | selected subtree差分なし |

floating dependency の revision-only movement は、payload content hashが不変なら pin追加の理由にしない。新しい APM native lock生成時に revision と content hash を記録し、hashが変わったものだけ通常 payload gateへ送る。

## 実装時の更新単位と検証境界

1. `llm-agents.nix` は [ADR-0033](../adr/0033-update-llm-agents-snapshot-and-claude-baseline.md) に従い、stable/default branch の exact revisionを実装入口で一度だけ再確認して `flake.nix` と `flake.lock` を同じ単位で更新する。Claude floor と Codex floor は package metadata の収録 version と整合させる。Codex が0.152.0まで進んでいても`update_plan`をopt-inせず、planning toolなしのskill flowをsmokeする。進んでいなければ0.151.0を採用して特定 releaseを待たない。
2. APM 通常 payload は、現行 manifestの exact/floating 方針を保ちつつ、更新候補を隔離 cwd/HOME で `apm install --target claude,codex --https` に渡す。lockを手書きせず、生成された selected `resolved_commit` / content hash / deployment ledgerを現行 lockと比較する。
3. 同じ隔離 runtime で `apm install --frozen --target claude,codex --https` 前後の lock SHA-256 が不変であること、`apm audit --ci` が driftなしであること、`.agents/skills` と `.claude/skills` の target discovery が一致することを確認する。APM 0.29 の plugin registration が target layoutへ余計な書込みをしないことも確認する。
4. Orca 3 skill は b44 payload の routing wording と discoveryを確認するが、Orca native worktree creation、Agent Picker、permission ownership の契約を APM skill側から再導入しない。live Orca appへの in-app updater や `npx skills update` は実行しない。
5. Impeccable は Design Hookの Codex Stop native output、Claude Stop output、fail-open、detector、hook migrationを独立 gateで評価する。Matt は full set / cleanup / workflow contractを [ADR-0042](../adr/0042-mattpocock-managed-set-update-gate.md) の ordered gateで単独評価する。
6. source adoption後にのみ `nix flake check --no-build --all-systems`、x86_64-linux build/startup smoke、`tests/`、`lefthook`、`cog verify`、`git diff --check` を行う。`chezmoi apply` と live HOMEへの反映はこの調査には含めず、source→liveの別境界で扱う。

PR #202 と既存 ADR の責務を満たす実装は、(a) llm snapshot（Claude、Codex、Copilot、Antigravity、APMを一体で検証）、(b)通常 APM payload（Modern Web、Remotion、shadcn、Orca、Effect-TS、React View Transitions）の2更新単位・2PRへ分ける。(b)のEffect-TS / React View Transitionsにはcandidate-specific gateを追加する。実装入口でsnapshotがCodex 0.152.0まで進んでいる場合は、planning toolなしで既存skill flowが成立することを(a)で確認する。Impeccable と Matt をこれらへ混ぜない。

## 検証コマンドと結果

本調査で実行した read-only コマンドは次の通り。Nix build、APM install/lock、`chezmoi apply` は実行していない。Nix evalは試行したが、この runtimeからNix daemonのUnix socketを作成できず `Operation not permitted` で失敗したため、version比較にはpin済みrevisionと候補revisionの公式 package metadataを用いた。

```sh
git status --short --branch
git rev-parse --git-dir
git rev-parse --git-common-dir
git branch --show-current
git merge-base --is-ancestor a800002b9a77e9112532c707cf8acfd38ee225ae HEAD
sed -n '1,260p' flake.nix
sed -n '1,300p' private_dot_config/nix-devshell/flake.nix
sed -n '1,280p' private_dot_config/nix-devshell/modules/ai.nix
sed -n '1,260p' private_dot_config/nix-devshell/packages/code-review-graph.nix
sed -n '1,90p' apm.yml
rg -n 'repo_url:|name:|resolved_commit:|resolved_ref:|version:' apm.lock.yaml
```

結果は linked worktree（`git-dir` は主 repo の `.git/worktrees/main-fork-2`、`git-common-dir` は主 repo `.git`）で、ancestor check は成功した。作業開始時点の既存変更は `.env.example`、`.envrc`、`templates/*/.envrc` のみで、これらと lock/source は編集していない。本ノートがこの調査で作成した唯一の repo file である。

外部の read-only 確認には `gh api` の GitHub REST endpoint（repo metadata、commit、compare、release、raw contents）を使い、公式リポジトリ・公式 release・公式 artifact metadataだけを根拠にした。`npm view` は sandbox の read-only npm cache (`EROFS`) により失敗したため、registry結果を根拠にしていない。

## 残る不確定事項

- `llm-agents.nix` main `ea1dc213` は調査時点で Codex 0.151.0までであり、既に公開された stable 0.152.0の Nix package metadata/hashが未収録である。実装入口の一度だけの再確認で候補revisionと収録versionを固定し、0.152.0が収録済みならplanning tool互換性を追加検証する。
- Nix `flake.lock`の再生成後に、3 system全ての evaluation/buildが通るか、特に APM 0.29 の Python `websockets` / plugin dependencies が閉包へ入るかは未確認である。
- APM candidate native lockの selected content hash、frozen no-rewrite、audit、Claude/Codex両target discoveryは未実行である。
- Anthropic Claude 2.1.252、Codex 0.151.0/0.152.0、Antigravity 1.1.22 の interactive session挙動はこの調査で再現していない。Codex `update_plan` default変更とcurrent model/runtimeでのtool提供状況は要確認である。
- Impeccable mainの未タグ差分は実体が大きいが、次の official skill tag、Design Hook compatibility、live binary discoveryは未確認である。
- Orca b44 の SKILL.md差分は確認済みだが、Orca 1.4.193等の live binary discoveryと、PR #202 native Agent Picker経路での挙動は未確認である。
- `aarch64-linux` / `aarch64-darwin` 実機の build/version smoke、APM organization policy enforcement、`chezmoi apply` は未実行である。

## Issue #204 実装結果

実装入口の一度だけの再確認ではdefault branch HEADは調査候補と同じ`ea1dc2132fb2669899dc8b3cbe6fe82ed10d23d6`で、Codex 0.152.0は未収録だった。このrevisionをsource/lockへ固定し、Claude Code 2.1.252、Codex 0.151.0、Copilot CLI 1.0.82、Antigravity CLI 1.1.22、RTK 0.46.0、APM 0.29.0を採用した。Claude floorは2.1.252、Codex floorは0.151.0へ引き上げた。OpenCodeは配備せず、repositoryの`update_plan` opt-in、APM manifest/lock変更、live `chezmoi apply`は行っていない。

検証中に、shared overlay の Codexがconsumer側のstable nixpkgsで別derivationになり、設定済みのNumtide cacheをhitせず大規模なRust source / release LTO buildになることを確認した。上流READMEとoverlay自身も、shared overlayのcacheはconsumerと上流のnixpkgs revisionが一致する場合だけhitすると明記している。実測したrevisionはconsumer `fca2dbd4c00c3063235e56bb91758e24fc67b7b8`、上流 `174eb786fb68e3a13e4e535a3deea479a0c07a6a`で、Codex derivationも異なった。

共有nixpkgs全体を動かさず、Codexだけを同じimmutable `llm-agents` inputのdirect packageへ切り替えた。direct outputはx86_64-linux / aarch64-linux / aarch64-darwinの3 systemともNumtide cacheに存在する。切替後のx86_64-linux WSL devShell dry-runはCodex derivationをbuild対象に含めず、実buildはshell derivation 1件だけを2.00秒で完了した。隔離HOMEでのstartupと6 CLIのversion/help、3-system flake check/metadata eval、専用Bats 32/32、workflow contract 14/14、full Bats suite 404/404（runtime mount条件の1件はskip）が成功した。さらにcandidate Codex 0.151.0を一時`CODEX_HOME`・read-only sandboxで実行し、`update_plan`なしで`tdd` skill flowを開始して同じsessionを`resume --last`で継続した。aarch64実機実行、candidate Codexのinteractive UI、fresh hostのcache download時間は未確認である。

## Issue #205 実装結果

PR #207を含む`origin/main`と同じcommit `c66c0312f09da62bd19dcc0be79219a69d625445`から新しいOrca native worktreeを開始した。`nix develop ./private_dot_config/nix-devshell#wsl --command apm --version`で採用済みAPM 0.29.0を確認し、manifestの3 exact candidateを更新してから、隔離cwd/HOMEで`apm install --target claude,codex --https`を一度だけ実行した。lockの手編集、`apm lock`、別updater、live HOMEへのapplyは行っていない。

生成した通常payloadは次のとおりである。

| Skill                  | 解決revision                               | `content_hash`                                                     | 採否・境界                                                                 |
| ---------------------- | ------------------------------------------ | ------------------------------------------------------------------ | -------------------------------------------------------------------------- |
| Modern Web Guidance    | `56c61c9ee79a8df1a98822309c04847a57f56000` | `cc46430506cf1b6fe0facf191ac30e6cacaa2e0ee4237361bb445ed17c5b9908` | exact pinをv0.0.186へ更新。IME-safe submit guideとretrieval guidanceを確認 |
| Remotion               | `357a270803b23e16b32bec65df07c41a62e94bd9` | `3ebdb1c3e503732103a92bba9611685e9e15812adb9b25c3a734ee8d3c228aeb` | exact pinを4.0.519 markerへ更新                                            |
| shadcn                 | `63c1308d112b6b1205d86244a156cca1abef5087` | `b82236022a12b00cfc80621d5de272e62ce597fb38f496d0a4a586ff954e6ae7` | floating解決。chat SSR scroll/CSP guidanceを確認                           |
| Effect-TS              | `2309e6f27d9955b434c0e3f394b945c136e89fd2` | `6bdb9b95aa83071eca2f67ae947b7d398a22e9e6e08f6cfa35de9516b03efa6e` | floating解決。setupは`effect@rc`、beta記述なし、setup時だけのtriggerを確認 |
| React View Transitions | `063bee94c3f4df8453406c830b0a7df0f2860278` | `0d0012537fe7619026f0a844fe505958beb2d525afb8f854ac7217798a2785e2` | floating解決。候補`0c04547b`以後selected subtree不変                       |
| Orca `orca-cli`        | `b44ef1e59db4399cbd3a0615d29345de601885e7` | `83ece910d035d0684195095bb9df5911a028002b2efba1ebbeb4ae66de5e0903` | selected payload変更をexact pinへ反映                                      |
| Orca `computer-use`    | `41ef1ddd80d69795749451116fe70568a3779ca9` | `eaa770000cf2e806485dc142c815580de3c6df4dfdd0afc792c79498aa93cfec` | floating解決。`b44ef1e5`以後selected subtree不変                           |
| Orca `orchestration`   | `41ef1ddd80d69795749451116fe70568a3779ca9` | `e611e8065f08f308823d063bb3cd8d4e283242202456b8a3e80058b2f59f0c3a` | floating解決。`b44ef1e5`以後selected subtree不変                           |

Orcaの3 `SKILL.md`は同じ`b44ef1e5` changesetで変更され、その後の`41ef1ddd`までselected subtreeに差分がない。3件ともOrca embedded pageは`orca-cli`、external page automationはPlaywright/CDP、external browser/native appのOS/window-level操作はComputer Useへroutingする。PR #202のOrca native worktree、Agent Picker、permission ownership、非Orca runtimeの`to-worktree`、Orca native Codexでwrapperを使わない契約は変更していない。

Effect-TS候補はClaude/Codex双方の`SKILL.md` SHA-256が`509ed4e10def32dc3f6b20854c9ae50a56b7dc525a14a02ab9871eef53a2052e`で一致し、`effect@rc` setup、`effect@beta`不在、setup repositoryだけに限定したfrontmatter triggerを確認した。React View Transitions候補は両targetの`SKILL.md` SHA-256が`1520343c8814c972fee001cac6d6185976d6eb3f4edcac33afe95c10f3b3228b`で一致した。React一次資料が示すCanary限定の`ViewTransition` / `addTransitionType`、Transition/Suspense trigger、type mapと、Next.js一次資料が示すApp RouterのReact Canary、`Link` / `useRouter`の`transitionTypes`に整合する。Next.jsの`experimental.viewTransition`はdeeper framework integration用で、候補が扱う直接APIと明示的`transitionTypes`には必須でないため、候補の「旧flagを追加しない」境界を採用した。

Impeccableはmanifest pinとlock blockが完全に不変である。Matt Pocockはexact revision `6654f6b60cd9d5be8b54c6fafe44346dabeb3b76`、25 skill membership、全deployed file/hashが不変だった。APM 0.29が生成したpackage aggregate `content_hash`だけは`30aaf153…`から`22de78eb0eca8ad3f1830f955999ff588650e1f6bbb1f436236eff4fb0296eda`へ変わったが、比較対象のpayload byteとmembershipには差分がない。Vercelのcomposition / React best practices / web-designは`063bee94`へrevision-onlyで進みcontent hash不変、内容不変のdependencyへ新しいexact pinは追加していない。OpenCode、新規skill、追加runtime target、`tools.update_plan.enabled`も追加していない。

同じ隔離runtimeの`apm install --frozen --target claude,codex --https`前後でlock SHA-256は`d343147e73c22f76eb0ccbb4a22838987fa29cd6857cd51c8d4002f3fc0e4369`から変わらず、`apm audit --ci`は10/10でdriftなしとなった。隔離cwdはGit remoteを持たないためorganization policy enforcementだけはwarning付きskipである。対象8 skillを含む42 skillすべてが`.agents/skills`と`.claude/skills`にmaterializeされ、対象8 skillの`SKILL.md`はtarget間でbyte一致した。`.codex`への追加配備とplugin registrationはなく、APM-only ownershipを維持した。

planning toolなしの開始・継続は、今回の隔離runtimeと一時`CODEX_HOME`、read-only sandboxでCodex 0.151.0を実行して再確認した。開始turnはmaterialize済み`.agents/skills/tdd/SKILL.md`を読み、`apm install --frozen`を公開seamとして選んで`STARTED_NO_PLAN`を返した。続いて明示した同一thread `01a05bf5-7519-76b2-8b7d-97f75e0c7d68`をresumeし、追加commandやfile変更なしで`CONTINUED_SAME_SESSION_NO_PLAN`を返した。両turnのJSON eventにplanning tool callはなく、repositoryにも`tools.update_plan.enabled`を追加していない。

### Verification Matrix

| Acceptance criterion                           | 検証                                                                                    | 結果 / 未確認理由                                                                                            |
| ---------------------------------------------- | --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| #204 merge後のmain起点                         | `HEAD` / `origin/main` / merge-baseを`c66c0312`で照合                                   | 成功                                                                                                         |
| APM 0.29・一度の隔離標準install                | candidate manifestを隔離cwd/HOMEへコピーし、non-frozen installを一度だけ実行            | 成功                                                                                                         |
| 対象8 skillのfile list/hash                    | native lockの`deployed_files` / `deployed_file_hashes` / `content_hash`と隔離実体を照合 | 成功                                                                                                         |
| exact/floating方針                             | manifest exact refとlock `resolved_ref`の集合一致、floatingへのpin追加なし              | 成功                                                                                                         |
| Orca 3 skill changeset/routing                 | `b44ef1e5..41ef1ddd`のselected diffなしと3 materialized `SKILL.md`を確認                | 成功                                                                                                         |
| PR #202 worktree ownership                     | 既存workflow contract regression seam                                                   | 成功（focused 14/14、full suiteにも収録）                                                                    |
| Effect-TS compatibility                        | `effect@rc`、beta不在、setup trigger、両target SHA/discovery                            | 成功                                                                                                         |
| React View Transitions compatibility           | React/Next.js一次資料、trigger、Canary/API境界、両target SHA/discovery                  | 成功                                                                                                         |
| frozen no-rewrite / audit                      | lock SHA前後一致、audit 10/10                                                           | 成功。org policy enforcementのみ隔離cwdにremoteがなくskip                                                    |
| Claude/Codex discovery                         | 42/42 directory、対象8 `SKILL.md`のtarget間byte一致                                     | 成功                                                                                                         |
| planning toolなしworkflow                      | 今回の隔離payloadをCodex 0.151.0で開始し、同一threadを明示resume                        | 成功（`STARTED_NO_PLAN` / `CONTINUED_SAME_SESSION_NO_PLAN`、planning call・file変更なし）                    |
| Impeccable/Matt/OpenCode/target非回帰          | Impeccable block一致、Matt file/hash集合一致、manifest target/dependency比較            | 成功                                                                                                         |
| repository full suite / lint / commit contract | Bats、Nix eval、lefthook、cog、diff check                                               | 成功（Bats 406/406、repo/user flake 3-system eval、pre-commit、diff check。commit-msg hookはcommit時に実行） |
| live HOME非変更                                | `chezmoi apply`とlive APM installを未実行                                               | 成功。live discoveryはmerge後の別運用境界                                                                    |

## 2026-09-05 skill payload 再確認

`apm outdated` は7 dependencyを候補として返した。採用済み revisionと公式 upstreamのGit tree / compare APIをselected pathに限定して照合した結果は次のとおりである。

| Dependency                        | 採用済み → upstream                             | selected payload                                                    | 判断                                          |
| --------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------- | --------------------------------------------- |
| Anthropic `pdf` / `skill-creator` | `53048666` → `41bbe19d`                         | 各directoryのGit tree SHAとcontent hashが同一                       | revision-onlyとしてfloating lockへ反映        |
| shadcn                            | `71e50952` → `7c9eaba1`                         | `rules/styling.md`の`cn` importが`@/lib/utils`から独立packageへ変更 | upstream migrationとして採用                  |
| Orca `computer-use`               | `40d9927f` → `af821260`（224 commits）          | content hash不変                                                    | revision-onlyとしてfloating lockへ反映        |
| Orca `orchestration`              | `40d9927f` → `af821260`（224 commits）          | delegationとembedded browserのrouting説明を明確化                   | payload変更として採用                         |
| Orca CLI                          | `b44ef1e5` → v1.4.197 `5ee4ace5`（339 commits） | selected pathの変更0件                                              | exact pinを維持                               |
| Matt Pocock                       | `6654f6b6` → main `3cca18b3`                    | `skills/` tree SHAが同一                                            | managed-set pinを維持                         |
| Impeccable                        | `63b04e25` → main `8dac6ae7`（170 commits）     | `SKILL.md`、agents、reference、runtime scriptsを含む大幅変更        | 通常refreshへ混ぜず専用Design Hook gateへ保留 |

`apm.yml` のexact pinは変更せず、APM 0.29.0のnative updateでfloating依存を`apm.lock.yaml`へ反映した。最初のfrozen installではdeployment ledgerの正規化によりlockが一度更新されたため、その生成物を入力に2回目の `apm install --frozen --target claude,codex --https` を実行した。2回目の前後でlock SHA-256は`1d833fb947eb39a0e8a5a817530ca43e7c6d996b5ec0a65fdd45f5e5f53da010`のまま不変、`apm audit --ci`は10/10、`.agents/skills`と`.claude/skills`は各42件で一致した。organization policy enforcementだけは隔離cwdにremoteがなくwarning付きskipである。live HOME、live skill directory、`chezmoi apply`は変更していない。
