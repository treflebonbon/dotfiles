# Impeccable skill／engine の独立更新（2026-10-09）

## 更新境界と採用物

通常 APM の [PR #392](https://github.com/treflebonbon/dotfiles/pull/392) が main へ merge 済みであることを確認し、その main を base に独立して更新する。[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md) と [ADR-0053](../adr/0053-separate-impeccable-skill-and-engine.md) に従い、skill／launcher と engine を同じ Design Hook 互換性ゲート・採用・rollback 境界で扱う。親記録は [update-tools-skills-20261009.md](update-tools-skills-20261009.md)。

予定した変更: `apm.yml` の exact pin、`apm.lock.yaml` の Impeccable 項目、Nix engine package の版と3環境の SRI hash、関連 test の独立期待値、runtime 文書の版表記、本記録。Tool Snapshot、通常 APM、Matt Pocock managed set は変更しない。

| 対象 | 採用済み | 採用 |
| --- | --- | --- |
| skill／launcher | 4.5.0 `6b9d0ffa3a9a884fc95928d2d2d896b0befa5d3e` | 4.5.1 `9dad388a41944a0d2b8d1fb547c8556d2ecb49e7`（tag `skill-v4.5.1`） |
| Nix engine | 0.1.11 | 0.1.12 |

upstream HEAD `778c8a7b`（434 commit 先）は未 release の変更を含むため採らず、最新 release の `skill-v4.5.1` を pin した。この commit の `scripts/VERSION` と `SKILL.md` の `metadata.version` は 0.1.12／4.5.1 で、engine release `engine-v0.1.12` と対応する。engine の3環境の asset digest（linux-x64 `25282daf…`、linux-arm64 `2398adce…`、darwin-arm64 `13374ffa…`）を公式 release の値から SRI へ変換して固定し、Linux は fixed-output derivation の取得で hash の一致を確認した。ARM Linux／Darwin は評価のみで実機起動は未検証。

## 検証

- APM 0.33.0 で、空の隔離 runtime に採用済み manifest／lock を複製し、Impeccable の exact pin だけを変えて `scripts/generate-apm-lock.sh` を実行した（native lock 再利用）。19 非 Impeccable 依存の lock 項目と、非 Impeccable の `deployments` はすべて base と同一。
- 採用 lock の SHA-256 は `2aa26e72518f332b729d38cbee92e563e18fb62f706fd9ff37b3e76b363ccdd8`。別の空 runtime の `apm install --frozen` 前後で不変、`apm audit --ci` 10/10、Claude／Codex 各46 skill が一致。組織ポリシー enforcement は Git remote のない隔離環境のため未検証。
- `tests/apm-runtime.bats`・`tests/impeccable-engine.bats`・`tests/design-hook.bats` が candidate launcher／engine で成功した。
- 標準 `lefthook run test` は746件中707成功・22 skip・17失敗。失敗番号は #391／#392 と同一で、dogfood 9件、`local-skills` 1件、managed-set gate 7件。gate 7件と `local-skills` 1件は変更前の main でも失敗する。dogfood 9件は環境要因と推定するが未確認。テストの例外化・削除はしていない。
- 未完了: Matt Pocock managed set は別単位として残る（親記録で追跡）。live apply は受入後。
