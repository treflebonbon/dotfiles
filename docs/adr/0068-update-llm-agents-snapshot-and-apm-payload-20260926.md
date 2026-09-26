---
type: decision
title: llm-agents snapshot と通常 APM payload を更新する（2026-09-26）
description: Claude Code の sandbox fail-closed 修正・Codex のネットワーク制限強制修正を根拠に quality floor を引き上げ、remotion-best-practices の実差分を根拠に APM pin を進める
tags: [adr, nix, llm-agents, apm, skills, quality-floor]
timestamp: 2026-09-26
status: accepted
---

# llm-agents snapshot と通常 APM payload を更新する（2026-09-26）

ユーザーの `/implement ツールとスキル更新` に基づき、既存 AI tool snapshot と APM 全19依存の更新候補を確認する。ADR-0045 に従い、tool snapshot と通常 APM payload の2更新単位を同じ task worktree・同一 commit で採否する（Impeccable、Matt Pocock managed set は対象外。両単位とも小規模なため commit は分割しない）。task worktree は main `203d47d` から作成した。前回更新（PR #355、2026-09-24）から2日しか経っていないため、まず upstream の実差分を確認し、実差分がある候補だけを検証コストの大きい nix build / APM lock 生成に進めた。

受入条件は exact snapshot と lock の整合、3 system の評価、Linux build・CLI起動、関連テスト・型チェック・full suite、二軸レビューとコミット。品質 floor は根拠がある場合のみ変更する。モデル・権限設定、配布経路、新規ツール追加、private skill 改稿は対象外。live apply・push・PR は行わない。

## Decision

### llm-agents snapshot

- `private_dot_config/nix-devshell/flake.nix` の `llm-agents.url` を immutable revision `8bec0ce1cbb0a39f8f08dc97a7635af847779f99` から upstream default branch HEAD `bbb0f9a24c3a5ce918f3d8103397ce08b20300e1`（2026-09-26、195 commit 先行）へ更新する。共有 nixpkgs と x86_64-linux / aarch64-linux / aarch64-darwin の3-system境界は維持する。3 system の package metadata は claude-code 2.1.283、codex 0.157.1、antigravity-cli(`agy`) 1.2.11、rtk 0.50.0、apm 0.32.0 で一致し、copilot-cli 1.0.88・herdr 0.9.1・code-review-graph 2.3.9 は変化なし。
- Claude Code の quality floor を `2.1.281` から `2.1.283` へ引き上げる。根拠は公式 CHANGELOG から確認した次の内容: managed `sandbox` settings に不正なネストされた値が1件でもあると設定ブロック全体が無視されていた不具合を修正し、不正な値だけを fail closed（無効化）してブロックの残りは引き続き適用されるようにした。これは sandbox 設定の一部欠陥がサンドボックス全体を無効化していた fail-open な挙動を fail-closed に修正するもので、この repo の trust boundary 判断基準（[ADR-0047](0047-test-quality-floors-through-package-outputs.md)）に合致する。pin 自体も 2.1.283 が最新のため、床と pin を同じ `2.1.283` に揃える。
- Codex の quality floor を `0.156.0` から `0.157.0` へ引き上げる。根拠は 0.157.0 の公式 GitHub Release Notes から確認した "Enforced network restrictions across redirects and ongoing HTTP and WebSocket traffic, including cancellation when policy changes revoke access."（#47389, #47407）。redirect 追従中や実行中の HTTP/WebSocket 通信でネットワーク制限が徹底されておらず、ポリシー変更によるアクセス取消も反映されていなかった不具合の修正であり、Codex floor 判断基準（sandbox・trust boundary の信頼性）に合致する。pin は snapshot 内の 0.157.1（Windows daemon 起動まわりの修正のみで Linux/macOS の追加床上げ根拠なし）を採用する。
- Antigravity CLI 1.2.10→1.2.11、RTK 0.49.0→0.50.0、APM 0.31.0→0.32.0 は非公開 changelog または floor 対象外のツールのため package metadata の追従のみ確認する。Copilot CLI・Herdr（バイナリ）・code-review-graph は snapshot 内でも変化なし。
- 実装の正本は Nix flake / lock、`modules/ai.nix` とし、配備先を直接編集しない。

### 通常 APM payload

`apm outdated`（隔離 cwd/HOME）が示した2件（mattpocock/skills、stablyai/orca/skills/orca-cli）に加え、exact pin 依存（modern-web-guidance、remotion-best-practices）の upstream 進捗を個別に確認して採否した。

- `remotion-dev/skills/skills/remotion-best-practices`: upstream default branch が `41b22eec767aa77eb31df62ccb3bacf52ed771fb` から `cf49eff5d4463b33966b6618c83f7295797dd028` へ1 commit 進み、`@remotion/motion-blur`（`<HtmlInCanvasMotionBlur>`、Remotion 4.0.529 で追加）の使用ガイダンス新設という実差分（`remotion-markup/REFERENCE.md` への Motion blur 節追加と新規 `motion-blur.md`）を確認し、pin を `cf49eff5d4463b33966b6618c83f7295797dd028` へ進める。
- `stablyai/orca/skills/orca-cli`: `apm outdated` は最新 tag `v1.4.212`（`d937d22f`）を示すが、`gh api .../compare` で実測すると pin（`4a5afd70`）は69 commit 先行・0 commit 遅れで、選択済み subtree（`skills/orca-cli`）に実差分がないことを確認した。pin を維持する。
- `GoogleChrome/modern-web-guidance/skills/modern-web-guidance`: upstream default branch HEAD が前回確認時点（`22ab18dfb50a5d7e3bdcf471c14076a5534eae4e`）から不変であることを確認した。pin を維持する。
- `mattpocock/skills` の pin `6654f6b60cd9d5be8b54c6fafe44346dabeb3b76` は `apm outdated` が最新 tag `v1.2.3`（`6acc160e`）を示すが、`gh api .../compare` で実測すると pin の方が39 commit 先行しており（既知の tag 専用比較に起因する false positive、2026-09-03/09-24 と同型）、pin を維持する。
- floating `(default)` 依存のうち `anthropics/skills`（pdf・skill-creator）、`stablyai/orca`（orchestration・computer-use）、`mizchi/skills`（empirical-prompt-tuning）は resolved_commit が前進したが、いずれも選択済み subtree の content hash は不変（revision-only）であることを `gh api .../compare` で確認した。apm.yml は変更せず、lock 再生成による自然反映のみとする。
- Effect-TS、shadcn、vercel-labs 各4 skill、find-skills、supabase-postgres-best-practices は floating で resolved_commit も content hash も不変。Impeccable、Matt Pocock managed set は別更新単位のため対象外。

## Verification boundary

- Nix source gate: `nix flake update llm-agents`（`flake.nix` の URL revision 書き換え後）と `nix flake check --no-build --all-systems` が3 system で成功した。3 system の `nix build --dry-run` で claude-code 2.1.283 / codex 0.157.1 / antigravity-cli 1.2.11 / rtk 0.50.0 / apm 0.32.0 の版が一致し、Codex は3 system とも fetch 対象（cache hit）で build 対象に含まれないことを確認した（rustc OOM を伴う LTO source build の回避）。x86_64-linux (host) では `nix develop` で実ビルドし、claude / codex / copilot / agy / rtk / apm / herdr / code-review-graph の8 CLI を隔離 HOME で起動し、実測 version が snapshot と一致することを確認した。
- 品質 floor の判定テスト（`tests/ai-quality-floor.bats`）と snapshot revision の固定値テスト（`tests/nix-devshell.bats`）を新しい floor・pin 値へ追従させ、成功を確認した。
- APM source gate: 隔離 cwd/HOME（apm 0.32.0 の nix devshell 経由）での `apm install --target claude,codex --https`（non-frozen、完全に空の隔離ディレクトリから）でlockを再生成し、同一隔離環境の `apm install --frozen --target claude,codex --https` で SHA-256 が不変であることを確認した。`apm audit --ci` は `lockfile-exists` / `ref-consistency` / `deployment-ledger-owners` / `deployed-files-present` / `no-orphaned-packages` / `skill-subset-consistency` / `config-consistency` / `content-integrity` / `includes-consent` / `drift` の10/10 に成功した。`tests/apm-runtime.bats` の該当 lock entry 断定（remotion-best-practices の pin・content hash、pdf/skill-creator/orchestration/computer-use の revision-only な resolved_commit、apm_version）を新しい値へ追従させ、成功を確認した。lock は oxfmt で再整形していない。
- full bats suite（`LC_ALL=C bats tests/*.bats`、752/752 成功、exit code 0）・`bunx tsc --noEmit`（エラーなし）は research doc に記録する。

## Deliberately separate

- Impeccable skill pin、Matt Pocock managed set は upstream の進捗確認自体を今回のスコープに含めない（専用の互換性ゲートが本更新単位のスコープ外）。
- モデル・権限設定（`"model"` / `"advisorModel"` / Codex managed model）、配布経路、新規ツール追加、private skill 改稿は対象外。

## Consequences

Claude Code は sandbox 設定の fail-open 挙動を fail-closed へ修正した版、Codex はネットワーク制限の適用漏れを修正した版へ quality floor を引き上げる。remotion-best-practices が `@remotion/motion-blur` ガイダンスを含む最新payloadへ進み、他の候補は実差分の欠如を確認した上で pin を据え置く。isolated APM install は空の隔離ディレクトリから実行しないと `deployed_file_hashes` を欠いた不完全な lock を生成する場合がある（既存の配備済みファイルが残っていると increment 的な再解決になり、変更のない依存の per-file hash 記録が省略される）ことを本更新で確認した。次回以降は隔離ディレクトリを毎回作り直す運用を徹底する。

関連: [調査ノート 2026-09-26](../research/llm-agents-and-apm-update-2026-09-26.md) / [ADR-0067](0067-update-llm-agents-snapshot-and-apm-payload-20260924.md) / [ADR-0045](0045-separate-llm-agents-and-apm-update-units.md) / [ADR-0047](0047-test-quality-floors-through-package-outputs.md) / [ai-runtimes](../../runtime/ai-runtimes.md)
