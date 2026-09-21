# A — Effect / Atom の新規構成：設計メモ

## Deliverable

注文取消は、`Order` の状態遷移として Model／ユースケースに置く。発送済みかを実行時に再確認し、`AlreadyShipped` を型付きエラーで返す。React View や Atom はこの規則を持たず、表示用の可否だけを受け取る。

依存は `View → UI Mediator → cancelOrder Effect → OrderService → Adapter` とし、Composition Root が Service の Layer と Atom Registry を供給する。Effect の実行、Fiber の中断、Scope による解放は既存のアプリケーション境界または Atom binding に委ねる。defect と中断は `AlreadyShipped` のような業務エラーに畳み込まない。中断してもサーバーの取消処理が巻き戻るとは扱わない。

注文フロー Mediator は、取消・再試行の UI 上の許可、採用する結果、取消方針を判断する役割である。通常の `pending`／`result` と古い結果の除外を Atom binding が提供するなら、その値を表示へ導出し、class・store・reducer・別の `isSubmitting` は作らない。除外を提供しない場合だけ、Mediator が「現在採用する操作 ID」を持ち、Atom binding の結果をその ID で採用する。これは検査専用の採番ではなく、再試行の結果採用を決める本番状態である。

音声入力と範囲選択のように共有資源を競合させるフローだけは、共通親 Mediator が `owner`、`releasing`、次の開始要求を所有する。子 Mediator は自分で完結する操作を処理し、開始・切替要求だけを親へ委譲する。親は停止要求後、Effect 実行層から終了・解放の通知を受けるまで次を開始しない。独立する注文取消と他の画面操作には、この親を通さない。

複数 View は同じ Atom の表示状態を購読してよい。緩和した Passive View では View が Atom を購読し、共通の Mediator 送信口へイベントを渡す。厳密な Passive View が要る箇所は、Atom を読む接続部分と props／イベントだけを持つ表示部分に分ける。tooltip の開閉など、他の操作の許可や進行を変えない局所状態は View に置ける。

DAG は import と Service／Layer の依存に適用し、上記の一方向依存を保つ。失敗から再試行への時間上の遷移は許容する。CoR は子から親への担当外の開始・切替要求だけに使い、業務処理と成功／型付き失敗の合成は Effect で行う。ROP も Effect の成功値と型付き失敗の合成に限り、常時 `Result<Result<…>>` を増やさない。

### 未実行の検証案

| ケース | 期待値 |
| --- | --- |
| 取消要求後に注文が発送済みになる | ユースケースが実行時に `AlreadyShipped` を返し、UI はその結果を表示する。 |
| 同じ注文を A で失敗後に B として再試行し、A の応答が遅着する | A の成功・失敗は B の `pending`／表示結果を変更しない。binding の保証、または Mediator の操作 ID 照合で確認する。 |
| 音声入力中に範囲選択を要求する | 親が音声入力を停止し、終了・解放通知の後にだけ範囲選択を開始する。 |
| 二つの View が注文状態を購読する | 両 View は同じ導出状態を表示し、どちらのイベントも同じ Mediator 判断へ届く。 |

これらは設計段階の確認案であり、未実行である。

## 基準

| 基準 | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | 発送後不可の規則と実行時検証を Model／ユースケースへ置き、UI は再実装しない。 |
| 2 | ○ | Effect の型付きエラー、Layer、Fiber／Scope を用い、独自 runtime・scheduler・pending/result 複製を提案しない。 |
| 3 | ○ | Mediator を判断の役割とし、既存 binding で足りる場合は専用構造を作らず、排他と解放待ちは必要な親だけが持つ。 |
| 4 | ○ | DAG を依存へ、時間上の再試行循環を状態遷移へ分け、CoR と Effect の責務も分離した。 |
| 5 | ○ | 緩和した購読可能な Passive View と、接続部／表示部を分ける厳密版を区別した。 |
| 6 | ○ | ROP を Effect の成功・型付き失敗の合成に限定し、defect・中断や二重 Result 化を避けた。 |
| 7 | ○ | 発送競合、古い応答、解放待ちを具体的な未実行の検証案に含めた。 |

## YOUR Trace

Understanding／Planning／Execution／Formatting: all OK。

## Unclear

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| 導入する Atom binding が古い応答の除外と中断完了通知をどこまで保証するか | 課題は API・バージョン・既存 binding を指定しない設計課題である。 | 実装前に導入版の Atom binding の並行実行・購読・終了通知を確認し、保証済みの状態は再保持しない。不足する結果採用と解放待ちだけを担当 Mediator に置く。 |

## 任意補完

注文取消の業務可否を初期表示で示しても、送信直前のユースケース検証は残す。画面表示後の発送をそこで検出できる。

## YOUR Retries

0

## INPUT

- 課題入力: `docs/evaluations/mvp-mediator-recommended/protocol.md` の「A — Effect / Atom の新規構成」節。
- スキル: `local-skills/mvp-mediator-architecture/SKILL.md`（SHA-256: `050c87041aecc5bf04e24f425f56e01d0e10dc4c9d46ecc9d9f50dcf98eec0fb`）。
- 実際に読んだ reference: `local-skills/mvp-mediator-architecture/references/tanstack-effect.md`。
