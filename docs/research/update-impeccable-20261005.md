# Impeccable skill／engine の独立更新（2026-10-05）

## 更新境界と採用物

ユーザーの「マージした」により、通常APMの [PR #379](https://github.com/treflebonbon/dotfiles/pull/379) が main `c045ab337eba30672c5ec402e9b3fbe300f39540` へ2026-10-05に merge済みと確認した。同じ native task worktree の Git 所属とclean statusを検証し、このmainをbaseとする `chore/update-impeccable-20261005` で独立した更新を続ける。[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md) と [ADR-0053](../adr/0053-separate-impeccable-skill-and-engine.md) に従い、skill／launcherとengineを同じ Design Hook互換性ゲート・採用・rollback境界で扱う。Tool Snapshot、通常APM、Matt Pocock managed set、native Ponytailはこの単位では変更しない。

| 対象 | 採用済み | 候補 |
| --- | --- | --- |
| skill／launcher | 4.4.0 `dc78b325e753a6971800e3bddc9089bf5954f608` | 4.5.0 `6b9d0ffa3a9a884fc95928d2d2d896b0befa5d3e` |
| Nix engine | 0.1.8 | 0.1.11 |

[調査済みのskill差分](https://github.com/pbakaus/impeccable/compare/dc78b325e753a6971800e3bddc9089bf5954f608...6b9d0ffa3a9a884fc95928d2d2d896b0befa5d3e)は用途別mode、responsive review、live browser UIとcontext抽出を改善する。[engine 0.1.11の公式release](https://github.com/pbakaus/impeccable/releases/tag/engine-v0.1.11)の3環境のasset digestと、Nix packageの固定SRI hashが一致することを再確認した。Linux成果物は同じNix出力を再利用し、ARM Linux／Darwinは評価のみで実機起動は未検証。engineの `--version` は上流の静的ラベルであり、releaseはasset／hash、skill版は `scripts/VERSION` の4.5.0で確認する。

## APMのnative更新と不変条件

APM 0.33.0で、空の隔離runtimeに採用済みmanifest／lockを複製し、実manifestのImpeccable exact pinだけを変更して `apm install --target claude,codex --https` を実行した。APMのnative lock再利用により、変更したrefだけを解決し、floating dependencyのmanifestに一時pinは追加しない。古い一括候補のlockもsourceへ流用しない。19非Impeccable依存のlock項目全体と、非Impeccableのdeployment ledger全項目がbaseと同じであることを確認した。

native生成 → frozen install → auditは全て終了コード0。frozen前後およびsource採用後のlock SHA-256は `ae0de6daa840f19de28263ccbec01e3309ee7e00a8e18e8baad6c9402d01a117` で不変。20依存・1,310配布ファイルのSHA-256と、Claude／Codex各46スキルの一致を確認した。audit baselineは10/10成功し、組織ポリシーenforcementはGit remoteのない隔離環境でwarning付きskipとなるため、その適合は未検証。

## 本単位の検証

- 対応3環境のroot／user devShell評価、Linux engine出力の実現、型検査 `bunx tsc --noEmit` が成功した。
- candidate launcherとengineを使う `tests/design-hook.bats` は13/13成功。quiet、両providerのper-edit／Stop出力、global有効化、silent convergence、project設定・cache、dedupe・編集閾値を維持する。
- `tests/apm-runtime.bats`／`tests/impeccable-engine.bats` は16/16成功。隔離chezmoi dry-runは成功し、実行前後の一時HOMEは不変。
- 初回の検証helperはPathを文字列へ置換したため `AttributeError` でテスト起動前に終了した。helperのPath構築を修正し、初回と再実行のログを分けて保持した。テスト本体への例外化や変更は行わない。
- 標準全件テストと二軸レビューは本単位の最終sourceで実施する。旧一括候補の成功を本単位の成功として扱わない。
- live sourceはmerge済みmainへfast-forwardで同期した。HOME配備は全更新単位の受入・merge後にlive sourceから行う。
