# Issue #291 — Matt Pocock managed set の exact pin 維持

2026-09-10。[#291](https://github.com/treflebonbon/dotfiles/issues/291) と親 [#283](https://github.com/treflebonbon/dotfiles/issues/283) の AC10 / AC13 に従い、導入済み Matt Pocock 25スキルの exact pin `6654f6b60cd9d5be8b54c6fafe44346dabeb3b76` を維持する。入口で固定された上流候補 `3cca18b368ae95cdbdebbff572ccafa662551015` は、選択 payload と plugin membership が現 pin と同一であり、revision の新しさだけを理由に更新しない。

この単位の変更は本判断記録だけである。APM manifest / lock、skill membership、配布 ownership、workflow・cleanup・モデル・権限の契約は変更しない。最終の二軸 review と [#295](https://github.com/treflebonbon/dotfiles/issues/295) の統合検証は未済であり、維持判断の確定を combined branch 全体の検証完了とは扱わない。commit と最終採用の取りまとめは coordinator が行う。

## 現行・候補・採否

| 対象 | 現行 | 入口で固定した候補 | 判断 |
| --- | --- | --- | --- |
| Matt repository revision | `6654f6b60cd9d5be8b54c6fafe44346dabeb3b76` | `3cca18b368ae95cdbdebbff572ccafa662551015` | 現行 exact pin を維持 |
| plugin version / membership | 1.2.3 / 25スキル | 同一 | full set を維持 |
| 選択 payload | 74ファイル | 同一 | 配備実体の更新なし |
| 配布経路 | APM の plugin collection、共有 hub と Claude target | 同じ既存経路で比較 | native plugin、別 installer、per-skill pin は追加しない |

coordinator が入口で取得した一次資料 `tmp/update-283/matt-candidate-entry.json` と比較結果 `tmp/update-283/matt-selected-payload-decision.json` を使用した。本単位では上流 HEAD / tag / latest を再解決していない。候補は [固定 commit](https://github.com/mattpocock/skills/commit/3cca18b368ae95cdbdebbff572ccafa662551015) であり、[現 pin との比較](https://github.com/mattpocock/skills/compare/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76...3cca18b368ae95cdbdebbff572ccafa662551015) を根拠とする。

## 選択 payload 不変の根拠

| 比較対象 | 現行・候補に共通する Git object ID | 結果 |
| --- | --- | --- |
| `skills/` tree 全体 | `fa7abc9c6000d0e276c2b5d2e7ce8e3983101b35` | 同一 |
| `.claude-plugin/plugin.json` blob | `0a2e3088d2bcaaabcc02ff1c691c5e6c0f81d01d` | 同一 |

選択元の tree 全体と選択する plugin manifest がともに同じ Git object なので、選択した25スキル・74ファイルの内容と membership は変わらない。候補 commit で変更されるのは repository 直下の `CLAUDE.md` と `scripts/link-skills.sh` だけで、上流のローカル symlink 作成時に `misc/` を除外する変更である。この repo が APM collection から配備する選択 payload には含まれず、その installer も実行していない。

25スキルは次の full set である。

```text
ask-matt, code-review, codebase-design, diagnosing-bugs, domain-modeling,
grill-me, grill-with-docs, grilling, handoff, implement,
improve-codebase-architecture, prototype, research, resolving-merge-conflicts,
setup-matt-pocock-skills, tdd, teach, to-questionnaire, to-spec, to-tickets,
triage, wait-what, wayfinder, wizard, writing-for-agents
```

plugin に含まれない skill の追加や一部だけの採用はしない。ローカルの workflow 上書きは [runtime/skill-harness.md](../../runtime/skill-harness.md) と [ADR-0041](../adr/0041-adopt-mattpocock-v1-2-3-workflow-semantics.md)、更新境界は [ADR-0042](../adr/0042-mattpocock-managed-set-update-gate.md) を維持する。

## #290 native runtime での再確認

入口の比較記録が参照する runtime は `tmp/update-289/runtime` である。本判断では後続 #290 の `tmp/update-290/runtime` を read-only で再確認し、通常 APM / Impeccable 更新後にも Matt full set が保持されていることを確認した。

| read-only 照合 | 結果 |
| --- | --- |
| source と runtime の manifest、lock、materialized `.apm-pin` | Matt の exact revision はすべて `6654f6b60cd9d5be8b54c6fafe44346dabeb3b76` |
| runtime の plugin manifest | Git blob を再計算し、上記 `0a2e3088…` と一致。version 1.2.3、25 membership 一致 |
| materialized selected files と両 target | 各74ファイルの実 bytes が一致し、lock の deployed hash 計148件とも一致 |
| discovery | `.agents/skills` / `.claude/skills` は各43スキル。名前の集合が一致し、全 `SKILL.md` の先頭 frontmatter に name / description が存在。両方に Matt25を含む |
| Matt dependency block と ownership | #290 baseline から block 全体と ledger 198件が不変。owners / active_owner は `mattpocock/skills` |
| source lock と #290 native lock | bytes 全体が一致。Matt のための再生成・手編集は実施していない |

APM 0.30.0 が記録する Matt の aggregate content hash は `sha256:22de78eb0eca8ad3f1830f955999ff588650e1f6bbb1f436236eff4fb0296eda` で不変。Git tree / blob ID、APM content hash、配備ファイルの SHA256 はそれぞれ別の照合として扱う。

#290 で既に実施したコマンドは次のとおり。本単位で再実行したり、Matt 候補の ordered gate として数えたりしていない。

```sh
apm install --target claude,codex --https
apm install --frozen --target claude,codex --https
apm audit --ci
```

実 binary は `/nix/store/r08b589k4w0zap14lf556mq52fmmpwbd-apm-0.30.0/bin/apm`、cwd / HOME は `tmp/update-290/runtime`。各 exit0、audit 10/10。native install / frozen / audit 後の lock SHA256 は `144bf375db3942b1185fc5d73ebcb4965121b27e52bed1ef40b717849fd93c53` で一致する。organization enforcement は Git remote のない隔離 cwd のため適用外、includes-consent は local include がなく対象外である。両 target の discovery は管理された layout / payload の確認であり、対話的な Claude / Codex loader や live 配備の確認ではない。

#289 / #290 の関連Batsは各40実行PASS・1skipであり、41/41ではない。`repo-local Agent skill deploy target is absent` はsource `.agents` をmountする場合の既存skipで、現在のcoordinator runtimeにも適用される。Mattの両target・全payload照合や実hookの未実施をこのskipで代替しない。

## Verification Matrix と未済事項

| #291 / 親 AC の確認対象 | 状態 | 根拠・限界 |
| --- | --- | --- |
| 現 pin / 固定候補 / 選択 payload / membership 比較（AC1, AC4, AC10） | PASS | whole skills tree と plugin blob が同一、selected25 / 74ファイル |
| unchanged 時の keep 条件（AC13, AC17） | 確定 | payload 不変なので accepted exact pin を維持。実行制約や互換性失敗を理由にした保留ではない |
| 両 target の full-set 整合（AC11, AC13） | PASS | #290 runtime の実 bytes、148 hash、discovery43/43、Matt ledger198件を read-only 照合 |
| 実体変更時の候補 ordered gate | 適用外・未実施 | 新 Matt candidate を採用しないため。isolated materialization から native lock adoption までの ordered gate を実施 PASS とは記録しない |
| 候補採用時の non-Matt drift 判定 / 作業用 lock の排除 | 候補採用条件は適用外 | 本単位は manifest / lock 無変更。採用済み #290 native lock と source の一致は別に確認 |
| TDD の red / green と追加挙動テスト | 適用外 | 動作変更なし。版や pin の文字列を写すだけのテストは追加しない |
| 最終 Standards / Spec review（AC16, AC19） | 未済 | coordinator の combined branch review に残す |
| full Bats / 必要な隔離 dry-run / 最終横断検証（AC16, AC19） | 未済 | #295 の統合 gate に残す。他単位の scoped PASS を最終 PASS に置き換えない |
| live 配備と通常環境での確認（AC18） | 未実施 | 受入・merge後の live source から行う。本単位では live skills に触れない |

この keep 判断による `runtime/skill-harness.md` や共有テストの必須修正はない。#290 の同文書編集は担当 worker が所有し、本単位では編集しない。将来 selected payload や membership を更新する場合は、[ADR-0042](../adr/0042-mattpocock-managed-set-update-gate.md) の full-set ordered gate が改めて必要になる。

## Evidence

- 入口の固定候補・比較: `tmp/update-283/matt-candidate-entry.json`、`tmp/update-283/matt-selected-payload-decision.json`。
- #290 の native install / frozen / audit: `tmp/update-290/install-result.json`、`frozen-result.json`、`audit-result.json` と対応ログ。
- #290 の全配布・ownership 照合: `tmp/update-290/payload-verification.json`。非 Impeccable 18 dependency block 不変、全体43/43 discovery の記録を含む。
- 本単位の再確認: `python3` の read-only probe で上記 JSON、source / runtime / #290 baseline の YAML、materialized plugin と選択ファイルを読み、hash と membership を照合。結果は前掲表の25 / 74 / 148 / 43 / 198。runtime への書込み、APM の再実行、Git 操作はない。
- 関連する採用記録: [#289 通常 APM](update-289-ordinary-apm-skills.md)、[#290 Impeccable](update-290-impeccable.md)。これらの検証結果と、未実施の Matt 候補 gate / 最終統合 gate を区別する。
