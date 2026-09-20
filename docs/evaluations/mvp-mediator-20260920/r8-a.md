# Scenario A アーキテクチャメモ

## Concrete Deliverable

在庫予約ダイアログの裁定者を **予約ダイアログ Mediator** とする。Root は既存の画面構成と共有 Context を組み立てるだけでよく、このシナリオだけのために画面全体の Mediator や転送コンポーネントを増やさない。二つのパネルは既存 Context から表示状態と同じイベント送信口を購読できる。

| 所有者 | 責務 |
| --- | --- |
| 予約ユースケース（Model） | 利用可能在庫の業務ポリシーと、予約実行時の再検証。React/UI 状態に依存しない。 |
| 予約ダイアログ Mediator | submit・close/cancel・結果採用を裁定する。現在の attemptId、対象 itemId、`editing` / `submitting` / `cancelled` / `succeeded` / `failed` を所有し、表示用の操作可否と結果へ変換する。 |
| 既存 UI binding と Effect 実行境界 | Mediator が受理した予約を実行し、attemptId とともに結果を返す。取消方針に従う Fiber の中断、購読解除、資源解放を担う。想定内エラー、defect、中断を区別する。 |
| ダイアログ View | quantity の入力値と数値形式チェック、表示、submit/close の通知。在庫可否を再計算せず、兄弟 View を直接操作しない。 |
| 既存 operation state / stock refresh | 同等な pending/outcome の表示状態は再利用する。予約フローに必要な「close が取消」「試行の同一性」「古い結果の除外」だけを Mediator の協調状態として追加する。背景在庫更新はデータ表示を更新してよいが、active attempt の状態を遷移させない。 |

### イベントと遷移

| 前状態 | イベント | Mediator の裁定 / 実行効果 | 後状態 |
| --- | --- | --- | --- |
| `editing` | `submit(quantity)`（形式有効） | 新しい `attemptId` を採番し、既存 binding 経由でユースケース実行を開始する。 | `submitting(attemptId)` |
| `editing` | `submit(quantity)`（形式無効） | View の形式エラーを表示し、実行しない。 | `editing` |
| `submitting(A)` | `close` | A を取消要求として裁定し、実行境界へ中断/解放を依頼する。サーバー上の予約が巻き戻ったとは表示しない。 | `cancelled(A)` |
| `cancelled(A)` | `submit(quantity)` | B の `attemptId` を採番して実行する。 | `submitting(B)` |
| `submitting(X)` | `result(X, success)` | X が現在の attemptId と一致するときだけ成功を採用する。 | `succeeded(X)` |
| `submitting(X)` | `result(X, expectedError)` | X が現在の attemptId と一致するときだけ失敗を採用する。 | `failed(X)` |
| 任意 | `result(Y, success/error)`（`Y` が現行でない） | 表示状態を変えない。必要なら実行境界の解放完了だけを処理する。 | 不変 |
| `submitting(X)` | `stockRefreshed` | 在庫表示/キャッシュを更新してよいが、X の pending/outcome/attemptId を変更しない。 | `submitting(X)` |

`close` 後の B は A と同じ itemId でも別試行である。結果採用は itemId だけでなく attemptId を照合するため、遅れて届く A の成功・失敗は B を上書きしない。取消は UI が以後の結果を採用しない方針であり、通信中断や Scope の終了だけをサーバーのロールバックとみなさない。

### 確認項目

1. 在庫不足を表示しても、予約要求はユースケースが実行時に再検証して拒否できる。View/Mediator に第二の在庫ポリシーを置かない。
2. A を送信、close で取消、同一 item を B として送信した後に A の成功、A の失敗をそれぞれ遅延到着させる。どちらも B の pending/outcome を変えない。
3. B の想定内業務エラー、defect、中断を別経路として観測し、想定内エラーだけを通常の失敗表示に変換する。中断後にサーバー予約の取消済みとは断定しない。
4. 二つの Context consumer が同じ表示状態とイベント送信口を利用でき、quantity/数値形式エラーはダイアログに留まる。コンポーネント間の必須中継はない。
5. 既存 binding の pending/outcome を表示へ使い、追加状態は close-取消と attemptId の協調に限定される。別の fetch/pending state machine を複製しない。
6. B が `submitting` の間に background stock refresh を発行しても、B は `submitting(B)` のままで、結果受理は B の result イベントだけで行われる。

## 六つの達成判定

| # | 判定 | 根拠 |
| --- | --- | --- |
| 1 | ○ | 在庫ポリシーと実行時再検証を予約ユースケースへ明示し、表示側の再実装を排除した。 |
| 2 | ○ | 予約ダイアログ Mediator を submit/cancel/result の所有者として命名し、attemptId による成功・失敗双方の旧試行除外を遷移に入れた。 |
| 3 | ○ | Effect の実行・中断・資源寿命を実行境界へ委譲し、expected error / defect / interruption とサーバーロールバック非保証を区別した。 |
| 4 | ○ | 複数 Context consumer と View 内の quantity/形式処理を維持し、必須 forwarding component を要求していない。 |
| 5 | ○ | 既存 operation pending/outcome を再利用し、cancel と attempt 協調だけを追加状態として特定した。 |
| 6 | ○ | background refresh 中の `submitting` 維持をイベント表と確認項目に具体化した。 |

## Trace

| 区分 | 状態 | 記録 |
| --- | --- | --- |
| Understanding | OK | Scenario A の前提、六つの判定項目、MVP + Mediator スキル、React/Effect 条件付き参照を読み、Model/UI/実行境界を分離した。 |
| Planning | OK | 共有の在庫規則、取消、同一 item の再試行、遅延結果、refresh を一つの attemptId 遷移表で扱う計画にした。 |
| Execution | OK | フレームワーク実装やパッケージ選定を行わず、責務表・遷移表・振る舞い確認だけを作成した。 |
| Formatting | partial | 成果物の構造自体は指定どおりだが、プロトコル抽出コマンドの文脈指定が広すぎ、Scenario A の後続節も出力された。以後の内容は使用していない。 |

## 不明点・原因・一般修正規則

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| 既存 UI binding が attemptId を結果と結び付けられるかは未確認。 | シナリオは pending/outcome の公開だけを述べ、試行識別子の伝播方法を規定していない。 | 同一対象の取消後再試行で旧結果を除外する必要がある場合、既存 binding の相関機構を確認し、なければ Mediator が生成した operation ID を実行結果まで運ぶ。itemId 単独を相関キーにしない。 |
| close 後のダイアログ表示（閉じたままか、再編集可能か）は未指定。 | 要件は close の意味を cancel とだけ定めている。 | 操作可否・結果採用に影響する取消は Mediator が決める。純粋な表示の開閉は View に残し、表示方針が必要になった時だけ明示する。 |
| 実行境界での Fiber/Scope の具体 API は未指定。 | バージョン選定とフレームワークコードは禁止されている。 | 導入済み Effect の公式/ローカル API を実装時に確認し、Mediator の取消方針を既存 binding の実行・寿命管理へ接続する。別 scheduler や cancellation flag を重複実装しない。 |

## 裁量で補った前提

- `attemptId` は submit を受理するたびに一意で、取消済み試行も識別可能とした。
- 形式無効な quantity は View が送信要求を出さない局所エラーとした。業務上の在庫可否はこの形式チェックと別にユースケースが検証する。
- background refresh は在庫データを更新し得るが、予約の result イベントではないため active attempt の採否を変更しないとした。

## 再試行

実行の再試行は 0 回。プロトコルの抽出範囲が Scenario A を越えたため、以後の評価内容は判断材料に使わず、Scenario A の六項目だけで成果物を構成した。
