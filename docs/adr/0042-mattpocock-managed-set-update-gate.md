---
type: decision
title: Matt Pocock managed full set の update gate を固定する
description: candidate revision を隔離 runtime で評価し、APM・配備・cleanup・workflow の契約を一つの検証境界で確認する
tags: [adr, apm, skills, mattpocock, verification]
timestamp: 2026-08-21
status: accepted
---

# Matt Pocock managed full set の update gate を固定する

## Context

[ADR-0040](0040-adopt-mattpocock-v1-2-3-full-set.md) で `mattpocock/skills` v1.2.3 の25 skillを一つの APM plugin collection として採用した。今後の revision 更新で、manifest だけを先に変える、lock を手書きする、APM と native plugin を併用する、といった partial adoption を許すと、Claude / Codex の discovery、orphan cleanup、local workflow contract が同時に drift する。

また、旧調査ノートにある20 skillの rename-only migration は、今回採用した25 skill full setの判断より前の候補である。候補 revision の評価手順と rollback 境界を、現行の accepted pair（manifest と lock）に対して明示する必要がある。

## Decision

Matt Pocock managed set の更新は、次の ordered gate を全て通過した候補だけを source に採用する。

1. **隔離 runtime**: candidate revision を一つの exact commit として一時ディレクトリへコピーした manifest から materialize する。live home、`~/.agents/skills`、`~/.claude/skills` は使わない。実行入口は `tests/mattpocock-update-gate.sh` とし、accepted lock も隔離 runtime にコピーする。
2. **lock generation**: gate は candidate 以外の依存を accepted lock の `resolved_commit` で一時 manifest 内だけ pin し、candidate manifest の Matt 行以外を変更していないことを先に比較する。その上で `apm install --update --target claude,codex --https` で生成された lock を正本とする。手書きの hash や `apm lock` 単体の結果は採用しない。生成後の lock から Matt collection の record を除外して accepted lock と比較し、候補以外の依存や deployment が変わった場合は、その候補を reject する。APM が pinned dependency に補う冗長な `resolved_ref` は `resolved_commit` と一致することを別検査した上で比較から除外する。つまり非 Matt dependency の再解決による drift は採用しない。
3. **frozen install**: 生成 lock の hash を保存して `apm install --frozen --target claude,codex --https` を再実行し、lock が書き戻されないことを確認する。
4. **audit**: 同じ隔離 runtime で `apm audit --ci` を実行し、source、lock、materialized payload の drift がないことを確認する。
5. **skill discovery**: `.agents/skills` と `.claude/skills` の full set が一致し、Codex / Claude の discovery が managed target を読むことを disposable runtime で確認する。
6. **workflow contract tests**: `tests/apm-runtime.bats`、`tests/run_onchange_before_remove-orphan-claude-skills.bats`、`tests/workflow-contract.bats` と全 `bats tests/` を実行する。full set、cleanup ownership、workflow safety の境界を同じ検証 matrix で追跡する。
7. **chezmoi dry-run**: isolated HOME 内で `chezmoi --source "$SOURCE_DIR" init --no-tty --guess-repo-url=false` により template data を生成し、続けて `chezmoi --source "$SOURCE_DIR" apply --dry-run` を実行する。dry-run 前後の isolated HOME の path snapshot が一致することも強制し、live apply や対象 HOME への書き込みをこの gate に含めない。

この順序は `tests/mattpocock-update-gate.bats` が実際に実行し、APM の呼び出し、isolated HOME、lock no-rewrite、full-set discovery、native / universal route の拒否を検証する。Bats は deterministic な fake runtime で gate の順序と失敗境界を検証し、採用候補の実 APM 評価では同じ入口を fake なしで実行する。テスト用の fake `bats` は gate が同じ Bats fileを再帰的に起動することだけを防ぎ、実 APM 評価の `bats tests/` は candidate runtime と分離した disposable test HOME / XDG directory で全テストを実行する。Playwright browser cache は既存の cache を read-only 参照し、live home/config はテスト対象にしない。

候補は次の条件を満たさない限り reject する。

- `@latest`、`main`、未固定の tag、per-skill の個別 pin は使わない。
- Claude native `enabledPlugins` や universal `npx skills` route を managed set の配布経路に追加しない。
- manifest、lock、runtime deployment、cleanup、instruction layer、tests の一部だけを更新しない。
- gate のどれか一つでも失敗した場合は accepted pair を変更せず、候補の partial materialization を commit しない。

rollback は直前の accepted manifest / lock pair を保持したまま、候補 commit を `git revert` で戻す。live home の削除や手書き lock の復元は rollback 手順にしない。

## Verification Matrix

| 契約                                           | 正本                                                                | 検証 seam                                                              |
| ---------------------------------------------- | ------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| exact revision と full set                     | `apm.yml` / `apm.lock.yaml`                                         | `tests/apm-runtime.bats`                                               |
| APM の配布 ownership と prune                  | `run_onchange_after_apm-install.sh.tmpl`                            | `tests/apm-runtime.bats`                                               |
| cleanup が full set を保持し orphan を削除する | `run_onchange_before_remove-orphan-claude-skills.sh.tmpl`           | `tests/run_onchange_before_remove-orphan-claude-skills.bats`           |
| discovery / workflow / safety boundary         | `AGENTS.md`、`CLAUDE.md`、`runtime/skill-harness.md`、ADR-0040/0041 | `tests/workflow-contract.bats` と disposable runtime                   |
| candidate update gate と rollback              | 本 ADR と `runtime/skill-harness.md`                                | `tests/mattpocock-update-gate.sh`、`tests/mattpocock-update-gate.bats` |

## Consequences

- accepted source は常に一つの exact commit と、その commit から生成された lock / deployment pair になる。
- upstream の更新速度より、隔離 materialization と cross-file contract の再現性を優先する。
- 旧20 skill rename-only 調査は候補選定の履歴として残るが、現在の採用条件や full-set の acceptance criterion ではない。
- discovery の実機挙動や live home への apply は、isolated gate の成功後に別途人間が確認する。未確認の live behavior を source gate の成功とは扱わない。

実 APM 評価は次のコマンドで行い、`apm install --update` が生成した lock の非 Matt 部分、`apm install --frozen` 前後の lock SHA-256、audit、discovery、workflow、chezmoi dry-run の全てを記録する。

```bash
tests/mattpocock-update-gate.sh \
  --source "$SOURCE_DIR" \
  --candidate-manifest "$CANDIDATE_MANIFEST"
```

関連: [Issue #172](https://github.com/treflebonbon/dotfiles/issues/172) / [Issue #168](https://github.com/treflebonbon/dotfiles/issues/168) / [ADR-0040](0040-adopt-mattpocock-v1-2-3-full-set.md) / [ADR-0041](0041-adopt-mattpocock-v1-2-3-workflow-semantics.md) / [skill-harness](../../runtime/skill-harness.md)
