# MVPスキルの配布終了判断

2026-09-24。ユーザーの「常に相談しつつ削除するか決めて」に対して、CodexとClaudeがHerdr経由で反証・再検討を行った判断記録。ユーザーが対象範囲を承認し、task worktreeの配布元撤去と参照更新を実施。検証結果は[実装記録](implementation.md)に残す。homeへの配備は未実施。

## 決定

現行mvp-mediator-architectureスキルは配布終了を選ぶ。v18の表調整は中止し、1KB版や明示呼出し専用版は今は作らない。責務分離・既存実行機構の再利用などの原則をADRに残し、評価資料と現行本文の固定コピーを保持する。将来、実プロジェクトで具体的な不足が見つかった時に、短縮版を別案として評価する。

「スキルなしが全フロントエンド開発で優れる」という一般的結論ではなく、確認できた利益と負担から現行版への追加投資を止める判断である。

## 確認した根拠

- [原資料72ファイル](original/)をscratchpadからコピーし、[SHA-256一覧](source-manifest.json)と照合。skill/referenceはv17と一致。旧版を比較したという懸念は解消。
- [元採点](original/blind/grades.md)と[群対応表](original/blind-key.txt)を照合。S/F合計は各群23.5/24。ただしEは固定52件だけの元評価であり、E4〜6を含むメモの全面採点を行った結果ではない。
- [親の隔離再実行](parent-checks.json): E4成果物は各52/52、S4成果物は自己検査exit0。known-bug対照はexit1。Fは提案のみで実アプリ検査なし。Sの2000試行fuzzは元採点者の記録であり、今回Codexは再実行していない。
- [metrics](original/metrics.txt)を再集計: skill群は平均106530.17 tokens / 457661.83 ms、noskill群は82193 tokens / 284860.33 ms。比率は約1.296 / 1.607。元データはClaude Code完了usageの転記で、tokens内訳は未確認。Codex v17 runのcanonical N/Aとは接続しない。
- [transcriptメタデータ抜粋](transcript-metadata.json)で12実行者と採点者のmessage.model=claude-sonnet-5、記録上のeffort=high、advisorModel=claude-opus-5-5を確認。APIへ適用されたeffortの直接証明ではない。原transcriptはpath/hashのみ保存し、全文コピーはしていない。

## 残す側の根拠も検討した

Claudeは初めの削除推奨を再検討し、一度は1KB化を提案した。Eのskill群には既存Effect/Atomの操作ID・保証を再利用できるか具体的に確認する説明があり、S-skill-1には抽象モデルの限界を丁寧に開示する利益がある。この質的利益を否定しない。

一方、Eのnoskill群も既存Effect実行境界と親の方針分離を明記しており、skill群にもtyped errors/defectsの明示が揃っていない。固定rubric E4を完全充足して明確に上回ったとは判定できない。再利用確認の質的利益とE4全体の優越を混同せず、元採点は変更しない。1KB版がその利益を保つという仮説も未評価である。

Codexが「現行配布版を退役、原則と資料を保存、短縮版は実需要時の別案」と提案し、Claudeが同意して1KB化の即時実施案を取り下げた。[対話記録](claude-consultation.txt)。合意の有無そのものを実験的証明とは扱わない。

## 最初の報告から訂正した点

1. v17のdescriptionは既に新規設計・MVP変更・競合UIへ限定されている。「React全般で起動する」は今回版の撤去理由にしない。
2. 過剰設計6対1には文書・表の重複や検査手続きの重さが混在する。実装上の指摘はskill側F-skill-2の新規共通selector、noskill側S-noskill-2のshouldCancel（採点者は妥当な追加として許容）。件数だけで実装品質の優越を断定しない。
3. Fのselector提案は本文のselectDisplay例と形が似ているが、それだけで因果を証明しない。本文から誘導された可能性として扱う。
4. 群間の「交絡なし」は撤回。advisor回数はClaude報告で8対7だが助言内容の影響は未分離。各群2回、方針を含む課題文、抽象モデル中心、同系列採点者・群推測可能性、並列実行時間という制限を残す。
5. このA/BはCodexモデルでの有無比較ではない。v17以前のCodex評価は指示遵守を測る別実験であり、A/Bの効果推定へ混ぜない。

## 実削除時の対象と保持範囲

| 対象 | 必要な処理 |
| --- | --- |
| local-skills/mvp-mediator-architecture/SKILL.md と references/tanstack-effect.md | アクティブな配布元から撤去。固定コピーは本資料original/skill以下に保持。 |
| .chezmoidata/local-skills.yaml | 既存のretiredへ名前を登録。既存配布処理を使い、新しい削除スクリプトは作らない。 |
| scripts/mvp-evaluation.py、tests/mvp-evaluation.bats、tests/mvp-reporting-example.mjs、tests/mvp-purity-example.mjs | 現行配布元への参照を評価用の固定保存先へ整合。過去run statusの読取りを保持。旧runを書き換えて新版へ再開させない。 |
| docs/mvp-evaluation-runner.md、ADR-0063 | 配布終了と保存先を説明。ADRの原則を保持し、現役スキルへのリンクを残したままにしない。 |
| 過去の評価・入力・成果物・audit・protocol | 保持。旧採点を変更せず、履歴を一括削除しない。 |
| 配備済みhome以下のスキル | task worktreeから直接変更しない。受入・merge後、live sourceの既存chezmoi配布経路で反映する。 |

現時点のread-only調査では、他のlocal skillから本スキルへの直接参照は見つからず、主要な参照元はADRと専用評価CLI・テストだった。実装時にはhidden設定を含む参照検索と既存配布テストで再確認する。

ユーザーの「承認」により、指定2ソースファイルの削除を含む上記範囲を実施する。配備済みhome以下は承認範囲どおり受入・merge後の反映に残す。固定A/B資料のhashを保つため、共通formatter/linter設定ではoriginal/以下だけを除外する。

## mainへの反映

本prototype branch全体はmainへmergeしない。mainの配布元はv17とは異なる旧版であり、ADR-0063にも番号衝突がある。mainへは2ソースの撤去・retired登録・番号衝突のない原則と根拠の説明を別の最小差分で統合する。詳しくは[実装記録](implementation.md)を参照。
