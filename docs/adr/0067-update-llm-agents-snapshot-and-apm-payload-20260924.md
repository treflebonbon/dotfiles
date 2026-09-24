---
type: decision
title: llm-agents snapshot と通常 APM payload を更新する（2026-09-24）
description: Claude Code / Codex の permission bypass・sandbox isolation 修正を根拠に quality floor を引き上げ、herdr / orca-cli / remotion-best-practices / modern-web-guidance の4 exact pin を実差分に基づいて進める
tags: [adr, nix, llm-agents, apm, skills, quality-floor]
timestamp: 2026-09-24
status: accepted
---

# llm-agents snapshot と通常 APM payload を更新する（2026-09-24）

ユーザーの `/implement ツールとスキル更新` に基づき、既存 AI tool snapshot と APM 全19依存の更新候補を確認する。ADR-0045 に従い、tool snapshot と通常 APM payload の2更新単位を同じ task worktree・同一 commit で採否する（Impeccable、Matt Pocock managed set は対象外。両単位とも小規模なため commit は分割しない）。task worktree は main `8ed3db4` から作成した。

受入条件は exact snapshot と lock の整合、3 system の評価、Linux build・CLI起動、関連テスト・型チェック・full suite、二軸レビューとコミット。品質 floor は根拠がある場合のみ変更する。モデル・権限設定、配布経路、新規ツール追加、private skill 改稿は対象外。live apply・push・PR は行わない。

## Decision

### llm-agents snapshot

- `private_dot_config/nix-devshell/flake.nix` の `llm-agents.url` を immutable revision `8011aaf2e65e9222b2121c2fbb622912d7469bd6` から upstream default branch HEAD `8bec0ce1cbb0a39f8f08dc97a7635af847779f99`（2026-09-24）へ更新する。共有 nixpkgs（`nixpkgs-26.05-darwin`）と x86_64-linux / aarch64-linux / aarch64-darwin の3-system境界は維持する。3 system の package metadata は claude-code 2.1.281、codex 0.156.1、copilot-cli 1.0.88、antigravity-cli(`agy`) 1.2.10、rtk 0.49.0（変化なし）、apm 0.31.0（変化なし）、herdr 0.9.1（変化なし）、code-review-graph 2.3.9（変化なし）で一致する。
- Claude Code の quality floor を `2.1.280` から `2.1.281` へ引き上げる。根拠は 2.1.281 の公式 CHANGELOG から確認した次の内容: auto mode / `--dangerously-skip-permissions` で、削除対象がコマンド置換結果のみの再帰 `rm`（例: `rm -rf "$(pwd)"`）が Bash allow ルールに関わらず無承認実行されていた permission bypass の修正（この repo は `defaultMode: auto`）、NUL byte を含む permission rule がワイルドカード一致へ展開されていた不具合の修正、sandbox `excludedCommands` が `git rev-parse --git-dir` 等の正当な呼び出しに一致しなかった不具合の修正。pin 自体も 2.1.281 が最新のため、床と pin を同じ `2.1.281` に揃える。
- Codex の quality floor を `0.155.0` から `0.156.0` へ引き上げる。前回（2026-09-23、ADR-0065）は 0.156.1 の release note（0.156.0→0.156.1 の hotfix 差分のみ）だけを確認して `minCodex` を据え置いたが、実際に snapshot が進んだ差分は `0.155.1`→`0.156.1` であり、その途中の `0.156.0` 自体の公式 release note を確認していなかった。今回確認した 0.156.0 の GitHub Releases 本文には "Close sandbox isolation gaps involving inbound Windows connections, privileged Linux/macOS sockets, and writes through read-only macOS file handles" とあり、この repo の Codex floor 判断基準（[ADR-0047](0047-test-quality-floors-through-package-outputs.md) の sandbox・trust boundary の信頼性）に合致する。pin は snapshot 内の 0.156.1（GPT-6 モデルカタログ追加のみで追加の床上げ根拠なし）を採用する。
- Copilot CLI 1.0.87→1.0.88、Antigravity CLI 1.2.9→1.2.10 は非公開 changelog のため package metadata の追従のみ確認し、quality floor 対象外のまま据え置く。RTK・APM・Herdr（バイナリ）・code-review-graph は snapshot 内でも変化なし。
- 実装の正本は Nix flake / lock、`modules/ai.nix` とし、配備先を直接編集しない。

### 通常 APM payload

`apm outdated` が示した6件（herdr、mattpocock/skills、orca `orchestration`/`computer-use`/`orca-cli`、supabase）を起点に、floating `(default)` 依存は selected subtree の content hash 比較、exact pin 依存は実際の upstream diff を確認して個別に採否した。

- `herdrdev/herdr/skills/herdr`: 同梱 Herdr バイナリが 0.9.1 になって以降 pin が 0.9.0 相当の `b99002ac99b09e00b4ca692436cb15a6b0d676f1` のまま据え置かれていた。`--machine` 経由のリモート SSH machine 操作手順の追加、`pane split` の暗黙ターゲット規則の明確化、alternate-screen scrollback 回復の説明変更という実差分を確認し、pin を `065ef9d6a531c49fb8bee7e818ef837065b21ee9`（release v0.9.1）へ進める。apm.yml のコメントも「Herdr 0.9.1 同梱」へ追従する。
- `stablyai/orca/skills/orca-cli`: discovery 文言の簡素化（"Use Computer Use only when a visible window needs GUI control that a CLI, filesystem, or API cannot do."）という実差分を確認した。tag `v1.4.210` の commit `0afcacccb238bbb288acd7a0e412d3979c635ec8` を最初の候補としたが、`apm install` が別の commit `4a5afd70a3db16f1cd546458e070681a4eb0da18` へ解決し（`git diff` で両者の tree 内容が同一であることを確認済み。upstream 側で同じ内容の commit object が2つ存在する）、`apm audit --ci` の ref-consistency check が manifest 記載commitとlockfile resolved_commitの一致を要求するため、`apm` 自身が解決した `4a5afd70` を pin として採用する。
- `remotion-dev/skills/skills/remotion-best-practices`: `4.0.525`→`4.0.528` で connected-compositions パターンの新設、multi-scene 構成の全面改稿、`Audio`/`Video` の `from` prop 移行、`render --frames` の追加という実差分を確認し、pin を `41b22eec767aa77eb31df62ccb3bacf52ed771fb` へ進める。
- `GoogleChrome/modern-web-guidance/skills/modern-web-guidance`: Anchor positioning・Grid lanes（masonry）の Baseline 状況更新を含む browser-support 記述の広範な更新という実差分を確認し、pin を `22ab18dfb50a5d7e3bdcf471c14076a5534eae4e`（release v0.0.190）へ進める。
- `stablyai/orca` の floating `(default)` 依存 `orchestration` / `computer-use` は、前回サイクル（2026-09-22）と異なり resolved_commit が `059ee59a48272854a2317cc267bdd03f23ec9aa6`→`122b8c25d7c16f76e395bf9a65887d7c4bc5003b` へ進み selected content hash も変化した。floating 依存のため apm.yml は変更せず、lock 再生成による自然反映のみとする。
- `mattpocock/skills` の pin `6654f6b60cd9d5be8b54c6fafe44346dabeb3b76` は `apm outdated` が最新 tag `v1.2.3`（`6acc160e`）を示すが、`gh api .../compare` で実測すると pin の方が39 commit 先行しており（既知の tag 専用比較に起因する false positive、2026-09-03 と同型）、pin を維持する。
- `supabase/agent-skills/skills/supabase-postgres-best-practices` は floating `(default)` 依存で `apm outdated` が resolved_commit の前進のみを示す。lock 再生成による自然反映のみとし、apm.yml は変更しない。
- Impeccable、Matt Pocock managed set、Effect-TS、shadcn、anthropics `pdf`/`skill-creator`、vercel-labs 各 skill は今回の候補にしていない（`apm outdated` で up-to-date、または別更新単位）。

## Verification boundary

- Nix source gate: `nix flake update llm-agents`（`flake.nix` の URL revision 書き換え後）と `nix flake check --no-build --all-systems` が3 system で成功した。3 system の overlay 経由 `pkgs.llm-agents.<pkg>.version` 実測が claude-code 2.1.281 / codex 0.156.1 / copilot-cli 1.0.88 / antigravity-cli 1.2.10 / rtk 0.49.0 / apm 0.31.0 / herdr 0.9.1 / code-review-graph 2.3.9 で一致することを確認した。Codex は3 system とも `inputs.llm-agents.packages.${system}.codex`（direct package）の dry-run で fetch 対象（cache hit）であり、build 対象に含まれないことを確認した（rustc OOM を伴う LTO source build の回避）。x86_64-linux (host) では `nix develop` で実ビルドし、claude / codex / copilot / agy / rtk / apm / herdr / code-review-graph の8 CLI を隔離 HOME で起動し、実測 version が snapshot と一致することを確認した。
- 品質 floor の判定テスト（`tests/ai-quality-floor.bats`）と snapshot revision の固定値テスト（`tests/nix-devshell.bats`）を新しい floor・pin 値へ追従させ、成功を確認した。
- APM source gate: 隔離 cwd/HOME での `apm install --target claude,codex --https`（non-frozen）でlockを再生成し、同一隔離環境の `apm install --frozen --target claude,codex --https` で SHA-256 が不変（`8ff486...` → 修正後 `e4e54c...` で前後一致）であることを確認した。`apm audit --ci` は `lockfile-exists` / `ref-consistency` / `deployment-ledger-owners` / `deployed-files-present` / `no-orphaned-packages` / `skill-subset-consistency` / `config-consistency` / `content-integrity` / `includes-consent` / `drift` の10/10 に成功した。`tests/apm-runtime.bats` の該当 lock entry 断定（herdr を除く4 exact pin + floating orca 2件）を新しい resolved_commit・content_hash へ追従させ、成功を確認した。lock は oxfmt で再整形していない。
- full bats suite・`bunx tsc --noEmit` の結果は research doc に記録する。

## Deliberately separate

- Impeccable skill pin、Matt Pocock managed set は upstream の進捗を確認済みだが、専用の互換性ゲート（Design Hook 契約差分、workflow migration の ordered gate）が本更新単位のスコープ外のため据え置く。
- モデル・権限設定（`"model"` / `"advisorModel"` / Codex managed model）、配布経路、新規ツール追加、private skill 改稿は対象外。

## Consequences

Claude Code / Codex とも permission bypass・sandbox isolation の修正を quality floor に反映し、herdr / orca-cli / remotion-best-practices / modern-web-guidance の4 skill が実差分に基づいて最新payloadへ進む。Codex の floor 判断が前回サイクルで一度見落とされたことを本 ADR で明示的に訂正し、次回以降は snapshot 内で進んだ全 patch version（`X.Y.0` を含む）の release note を確認する運用を徹底する。

関連: [調査ノート 2026-09-24](../research/llm-agents-and-apm-update-2026-09-24.md) / [ADR-0064](0064-update-llm-agents-snapshot-for-opus-5-5.md) / [ADR-0065](0065-adopt-gpt-6-sol-and-luna-as-managed-models.md) / [ADR-0045](0045-separate-llm-agents-and-apm-update-units.md) / [ADR-0047](0047-test-quality-floors-through-package-outputs.md) / [ai-runtimes](../../runtime/ai-runtimes.md)
