---
type: decision
title: llm-agents と APM skill の更新を四つの更新単位に分ける
description: snapshot、通常の skill payload、Design Hook、Matt Pocock workflow を個別の互換性ゲートと rollback 境界で更新する
tags: [adr, nix, llm-agents, apm, skills, impeccable, matt-pocock]
timestamp: 2026-08-27
status: proposed
---

# llm-agents と APM skill の更新を四つの更新単位に分ける

2026-08-27 の更新では、導入済み AI ツールセットと導入済み Agent Skill セットの全 dependency を調査対象にする。ただし、互換性ゲートと rollback 境界が異なる変更を一括採用せず、次の四つの更新単位へ分ける。

## Decision

1. **llm-agents snapshot**: 実装 phase の入口で upstream stable/default branch HEAD を一度だけ再確認し、pre-release を除外した exact revision に固定する。特定 release の収録を待ち続けない。調査時点の候補は `4a9441120caf6c6aff273af68995267a35c20fcd` で、code-review-graph 2.3.8 に合わせて local package override も同じ単位で更新する。Claude Code の品質 floor は `2.1.247`、Codex の品質 floor は `0.150.0` へ引き上げる。
2. **通常の APM payload refresh**: 全 dependency の selected subtree を比較し、実体差分のある Modern Web Guidance と Remotion を候補にする。floating dependency は隔離 lock 生成時に再解決し、revision だけが進んで payload が同じ変更は個別の採用理由にしない。selected subtree が同一の exact pin は動かさない。
3. **Impeccable**: 4.1.2 payload を独立した検証済み Skill Pin の候補とし、Codex Stop protocol、finding cache、monorepo/symlink root、fail-soft の挙動を含む Design Hook 互換性ゲートが通った場合だけ採用する。候補は Codex Stop を top-level の `decision` / `reason` で返すため、旧 `hookSpecificOutput.additionalContext` adapter を除去して fail-open pass-through にする配線変更と、Stop characterization test / runtime docs の更新を同じ単位に含める。Claude Stop の出力契約は変更しない。
4. **Matt Pocock managed set**: 同じ initiative 内の独立した workflow migration として、25 skill の full set を exact revision へ進める。membership は変更せず、明示的な skill 呼出し、frontier question separator、setup 未済時の案内方法を取り込む。既存のローカル skill 上書きは維持し、先に確定した non-Matt lock を baseline として ADR-0042 の ordered gate が全て通った場合だけ採用する。

各更新単位は、候補の一部だけを採用しない。互換性ゲートに失敗した単位は旧 snapshot、旧 pin、または旧 manifest/lock pair を維持し、他の更新単位の採否とは分離する。

## Implementation status

### llm-agents snapshot（Issue #184）

Issue #184 の実装入口では、upstream stable/default branch HEAD を一度だけ再確認し、調査候補と同じ `4a9441120caf6c6aff273af68995267a35c20fcd` を採用 revision として固定した。source URL と lock の `original.rev` / `locked.rev` は同じ exact revision を指し、pre-release は導入していない。ユーザー devShell が共有する nixpkgs `fca2dbd4c00c3063235e56bb91758e24fc67b7b8`、対応3 system、Copilot CLI 1.0.80、APM 0.28.0 は変更していない。

採用した package metadata は3 systemで claude-code 2.1.247、codex 0.150.0、copilot-cli 1.0.80、antigravity-cli 1.1.21、rtk 0.46.0、apm 0.28.0、code-review-graph 2.3.8 に一致する。`minClaudeCode` は2.1.247、`minCodex` は0.150.0へ上げた。CRG 2.3.8 の package sourceは parser probe を `[sys.executable, "-c", code, grammar]` へ変更したため、local overrideもこの新しい probe形を固定Python環境へ差し替えるよう更新した。

`nix flake check --no-build --all-systems`、3 systemの7 package metadata eval、x86_64-linux hostのdevShell buildと7 CLI version/startup、CRGの一時repository graph build、read-only allowlistに限定したstdio MCP `list_graph_stats_tool`、full Bats suite 389/389（runtime mount条件の1件はskip）を通過した。scoped `chezmoi apply` 後のlive devShellでも7 CLI versionは一致した。aarch64-linux / aarch64-darwinの実機実行、Claude 2.1.247 / Codex 0.150.0の根拠機能をinteractive agent sessionで再現する機能的smoke、Antigravity CLI 1.1.21のversion固有changelogは未確認である。

これにより llm-agents snapshot 更新単位は採用できる。

### 通常の APM payload refresh（Issue #185）

APM 0.28.0 の隔離 cwd / HOME で全18 dependencyを再materializeし、accepted lockとcandidateのselected subtreeを`resolved_commit` / `content_hash`で比較した。payloadが変わるのはModern Web GuidanceとRemotionの2件、revision-onlyはShadcnとOrcaの`computer-use` / `orchestration`の3件、残り13件はcommit/hashとも不変だった。

| selected dependency                               | accepted → candidate    | content hash            | 分類・採否                    |
| ------------------------------------------------- | ----------------------- | ----------------------- | ----------------------------- |
| `anthropics/skills/pdf`                           | `3b3fad96` → `3b3fad96` | `69e2ac9e` → same       | 不変                          |
| `anthropics/skills/skill-creator`                 | `3b3fad96` → `3b3fad96` | `b2bfe91d` → same       | 不変                          |
| `Effect-TS/skills/effect-ts`                      | `28822c9e` → `28822c9e` | `261b9f3f` → same       | 不変                          |
| `GoogleChrome/modern-web-guidance`                | `460e5536` → `457c381d` | `8951bdfc` → `07775fbf` | payload変更、exact pin採用    |
| `mattpocock/skills`                               | `6acc160e` → `6acc160e` | `7c5f630f` → same       | 不変、別更新単位のpin維持     |
| `mizchi/skills/empirical-prompt-tuning`           | `7a0d7286` → `7a0d7286` | `20e7fba9` → same       | 不変                          |
| `pbakaus/impeccable`                              | `c39b6425` → `c39b6425` | `d79bd3df` → same       | 不変、別更新単位のpin維持     |
| `remotion-dev/skills/remotion-best-practices`     | `7fc6dea3` → `7a3d0ca4` | `7e361522` → `2493dc60` | payload変更、exact pin採用    |
| `shadcn-ui/ui/shadcn`                             | `ac60ef5c` → `683a5a9b` | `8b8c1296` → same       | revision-only、floating再解決 |
| `stablyai/orca/computer-use`                      | `5bcbafff` → `9c01e09e` | `afe48be6` → same       | revision-only、floating再解決 |
| `stablyai/orca/orca-cli`                          | `5ca747da` → `5ca747da` | `cca6a909` → same       | 不変、exact pin維持           |
| `stablyai/orca/orchestration`                     | `5bcbafff` → `9c01e09e` | `b5c36487` → same       | revision-only、floating再解決 |
| `supabase/agent-skills`                           | `8331f910` → `8331f910` | `5766a8e9` → same       | 不変                          |
| `vercel-labs/agent-skills/composition-patterns`   | `dd089a8c` → `dd089a8c` | `5b3564ca` → same       | 不変                          |
| `vercel-labs/agent-skills/react-best-practices`   | `dd089a8c` → `dd089a8c` | `74f142d2` → same       | 不変                          |
| `vercel-labs/agent-skills/react-view-transitions` | `dd089a8c` → `dd089a8c` | `aa4cf8be` → same       | 不変                          |
| `vercel-labs/agent-skills/web-design-guidelines`  | `dd089a8c` → `dd089a8c` | `a6a44d54` → same       | 不変                          |
| `vercel-labs/skills/find-skills`                  | `435076e7` → `435076e7` | `913b9d37` → same       | 不変                          |

revision-onlyのfloating解決はShadcn `683a5a9b370acdb7785a0529434e6a3b8c7e0441`、Orca `computer-use` / `orchestration` `9c01e09ecc9d3c1203968ace9945d16edfb35dd2`である。selected content hashはそれぞれaccepted lockの`sha256:8b8c1296ad947a237b32c21857837357f29197c53722131758777c80d26ed1ad`、`sha256:afe48be623c1f6190ade7dacc4c1d334d4150b503ed00b28dda23a499e5bdc30`、`sha256:b5c364878fb07d21a369f091f2e96b823da94308b15b39636f2585d8b5621b51`と一致するためmanifestへpinを追加していない。

Modern Web Guidanceはexact revision `457c381def89ce6213a171238f92eea63e9eaeb2`、content hash `sha256:07775fbfaed98fcf50795256434f646da296311bc10dd54f2de29075eca9095b`を採用した。公式差分はglobal `Translator` interface、4状態のavailabilityとdownload時のuser gesture、CSS sibling functionsのBaseline更新である。Remotionはexact revision `7a3d0ca45d2f6a00bf35cb3c525734a36d55a834`、content hash `sha256:2493dc60c3917d2e1153cd60d9e4df771b2775f64f3e17cbb1c2f1d011f888f3`を採用した。4.0.518 payloadにはcaptionの`pageBreakAfter`、重複timestampでも安定するtoken key、Mediabunnyの`UrlSource`例の更新が含まれる。

更新済みmanifestを隔離cwdへコピーし、隔離HOMEで`apm install --target claude,codex --https`を実行してdeployed files/hashを含むlockを生成した。同じ環境の`apm install --frozen --target claude,codex --https`前後でlock SHA-256は`d43138a744099027b61ad50150b4a36246f747214d23761c9f970b3a38d03720`のまま、`apm audit --ci`はdriftなしで10/10 checksを通過した。`.agents/skills` / `.claude/skills`の両targetでModern Web Guidance 141 files、Remotion 137 filesと上記guidanceを発見した。隔離cwdはGit remoteを持たないため、auditのorganization policy enforcementはwarning付きskipとなったが、manifest/lock/deployment/contentの10 checksはすべて成功した。live skill directoryと`chezmoi apply`には触れていない。

これにより通常の APM payload refresh更新単位も採用できる。ImpeccableとMatt Pocock managed setの2更新単位は後続issueの互換性ゲート待ちであるため、本ADR全体のstatusは`proposed`を維持する。

## Verification boundary

- llm-agents は対応3 systemの evaluation、x86_64-linux host build、導入 CLI の version/startup smoke、code-review-graph の build/CLI/MCP smoke を行う。
- APM lock は runtime layout を再現した隔離 HOME で `apm install --https` により生成し、同じ環境で frozen no-rewrite と audit を確認する。
- Impeccable は `turn_id` を持つ Codex Stop の top-level `decision` / `reason`、初回 deep-pass 後の silent Stop、Claude Stop の既存出力、managed fail-open を candidate runtime で確認する。既知の交互再報告を期待する旧 characterization は、4.1.2 で不具合が修正された契約へ更新する。
- Matt Pocock managed set は `tests/mattpocock-update-gate.sh` の全工程を通す。ADR-0043 に記録した4 testの既知例外は現行 main で再現しないため、今回の例外にはしない。
- repository の full test、`chezmoi apply`、live 環境の version/discovery smoke までを完了境界とする。

## Consequences

候補ごとの失敗を他の更新へ波及させず、snapshot packaging、通常の skill payload、hook runtime、workflow semantics をそれぞれの根拠で採否できる。一方、単一の一括更新より検証回数と順序制約は増える。

関連: [ADR-0029](0029-impeccable-pin-advance-with-stop-hook.md) / [ADR-0041](0041-adopt-mattpocock-v1-2-3-workflow-semantics.md) / [ADR-0042](0042-mattpocock-managed-set-update-gate.md) / [ADR-0043](0043-update-llm-agents-and-impeccable-update-unit.md) / [skill-harness](../../runtime/skill-harness.md)
