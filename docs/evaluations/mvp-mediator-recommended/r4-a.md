# A — Effect / Atom の新規構成：設計メモ

## Deliverable

注文取消は、発送済みなら不可という業務規則を React・Atom 非依存の Model／ユースケースに置く。画面に表示した時点の可否はヒントとして表示できるが、取消 Effect の実行時にも必ず再検証する。発送は表示後にも起こり得るため、発送済みなら型付きの業務エラーとして返し、UI はその結果を表示する。

ユースケースは必要な Port を要求する Effect とし、Adapter は Port を実装し、組立箇所で Layer を供給する。Effect の型付き業務エラー、Fiber による中断、Scope による資源寿命を既存の実行境界と Atom Registry に接続する。Mediator のための独自 runtime／scheduler は作らない。既存 Atom binding が pending・result・操作識別・古い結果の除外を満たすならそれを表示へ導出し、別の `isSubmitting`、result、操作 ID を持たない。

Mediator は UI 操作を受けて許可・取消・再試行・結果採用を決める役割であり、純粋関数または既存 Atom の更新処理で足りる。通常の取消フローはその担当に留める。音声入力と範囲選択のように共有資源を競合させ、切替時に終了待ちが必要なときだけ、共通の親 Mediator が `所有者` と `終了待ちの操作識別` を所有する。親は停止を要求しただけで後続を開始せず、Effect 実行層から対象操作の終了・解放通知を受けてから開始する。

静的依存は `ユースケース → Port`、`Adapter → Port` とし、具体 Adapter／Layer は Root の組立箇所で選ぶ。View は props または Context の表示状態とイベント送信口を受け、兄弟 View を直接操作しない。親への通知口も props／Context で供給し、import の循環を作らない。失敗から再試行への時間上の循環は状態遷移として許容する。CoR は子が決められない共有資源の開始・切替要求だけを親へ委譲し、子が処理済みの取消や再試行を親で二重実行しない。業務処理とエラーの合成は Effect で行う。

この設計では緩和した Passive View を採用し、複数 View が同じ Atom を購読してよい。どの View からの要求も同じ Mediator の裁定へ届く。厳密な Passive View が必要な箇所だけは、Atom を読む接続コンポーネントと、props とイベントだけを扱う表示コンポーネントに分ける。数値整形や tooltip の開閉は View の局所状態に置けるが、取消可否、排他、取消・再試行の進行は置かない。

ROP は Effect の成功値と型付きの想定内業務エラーの合成に限って使う。常に別の Result を重ねず、defect と中断は業務エラーに潰さずに UI 実行境界で区別して通知・観測する。中断要求はサーバー側の取消処理や外部処理を巻き戻す保証にはならない。

## 検証案（未実行）

| ケース | 操作 | 期待値 |
| --- | --- | --- |
| 発送との競合 | 未発送表示の注文を取消要求した直後、サーバー側で発送済みにする | 実行時の Model／ユースケースが取消を型付き業務エラーで拒否し、UI は失敗を表示する。画面表示時の可否だけで実行を許可しない。 |
| 同一注文の再試行と古い応答 | 試行 A を中断または失敗後に試行 B を開始し、A の成功・失敗を遅れて返す | 既存 binding の結果除外、または必要時の操作 ID 照合により、A の結果が B の pending・result・表示を上書きしない。前回の失敗と B の進行中を区別する。 |
| 共有資源の切替 | 音声入力中に範囲選択を開始する | 親 Mediator が切替を裁定し、音声入力の停止、終了、資源解放を待ってから範囲選択を開始する。停止要求だけでは開始しない。 |
| 複数購読と局所表示 | 二つの View が同じ Atom を購読し、一方の tooltip を閉じる | 両 View は同じ裁定済み状態を表示でき、tooltip の変更は局所表示だけを変える。 |

## 基準評価

| 基準 | 評価 | 理由 |
| --- | --- | --- |
| 1 | ○ | 取消可否と発送競合の実行時検証を React・Atom 非依存の Model／ユースケースに置き、UI で業務規則を再実装していない。 |
| 2 | ○ | 型付きエラー、Service／Layer、既存実行境界、Fiber／Scope、Atom Registry を使う。独自 runtime／scheduler と pending・result の複製を提案していない。 |
| 3 | ○ | Mediator を判断の役割として純粋関数または Atom 更新に置き、排他と終了待ちだけを共通親が所有する。 |
| 4 | ○ | 静的 DAG と時間上の再試行循環を分け、CoR を担当外の共有資源要求だけに限定し、Effect を業務・エラー合成に使っている。 |
| 5 | ○ | 緩和した Passive View の複数購読と、厳密時の接続部分／表示部分の分離を明示した。 |
| 6 | ○ | ROP を Effect の成功・型付き業務エラーへ限定し、二重 Result 化と defect／中断の業務エラー化を避けている。 |
| 7 | ○ | 発送競合、再試行時の古い応答、共有資源の終了・解放待ちを具体例で検証対象にし、すべて未実行と明記した。中断によるサーバー処理の巻戻しも主張していない。 |

## YOUR Trace

### Understanding

画面上の表示状態と業務上の取消可否は別であり、発送状態が後から変わるため実行時検証が必要である。共有資源の競合だけが通常の Atom 実行状態を超える追加裁定である。

### Planning

既存 Effect／Atom の状態・寿命・結果採用を先に再利用し、不足する共有資源の所有者と終了待ちだけを親 Mediator に追加する方針とした。

### Execution

設計メモのみを作成した。実アプリ、抽象実行モデル、フレームワーク API コードは作成していない。検証案は未実行である。

### Formatting

日本語 Markdown とし、Deliverable、検証案、全基準の評価、Trace、未解決事項、補足、入力ハッシュ、再試行回数を記載する。

## Unclear Issue / Cause / General Fix Rule

なし。

## 任意補足

参照した適用ガイドは `references/tanstack-effect.md`。導入時は実際に導入された Effect 版の `node_modules/effect/AGENTS.md` と必要な参照を確認して API と並行実行の仕様を確定する。

## INPUT

対象 `local-skills/mvp-mediator-architecture/SKILL.md` の SHA-256 は `050c87041aecc5bf04e24f425f56e01d0e10dc4c9d46ecc9d9f50dcf98eec0fb`。同スキル本文および適用参照 `local-skills/mvp-mediator-architecture/references/tanstack-effect.md` を全文読了した。

## YOUR Retries

1 回（整形検査コマンドの呼出しを訂正）。
