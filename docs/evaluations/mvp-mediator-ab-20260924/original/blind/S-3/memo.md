# 検索バインディングの結果採用 — 責務/イベント/検証メモ

対象: 既存の React/Query 検索画面。1リクエストごとに pending/result を公開する search binding があり、Query 自体（キー単位の重複排除・キャッシュ・実行）はそのまま維持する。Effect は導入しない。

対象実装ファイルは今回のタスクで指定されていないため、既存 binding の具体的なコードは未読。「search binding exposing pending/result for each request」という task 文はそのまま前提として受け取る（per-request で個別に pending/result を公開しており、どれを表示に採用するかは binding 自身が選ばない）。その上で「Only the newest request's success/failure may update displayed results」は満たすべき要件であり、可能性ではない。この採用判断のために `latestId` を1個追加するのが本メモの設計。実コードで未確認なのは、リクエスト識別の実体（§5 `nextId` の情報源）と、binding 側に転用できる「最新マーカー」がすでに存在するか（あれば `latestId` はそれへ委譲できる。§11 に非ブロッキングの確認対象として記載）の2点のみ。

## 1. 既存の所有者の確認

- **実行・寿命（Query の実行facility）**: リクエストの発行・重複排除・best-effort cancel・per-request の pending/result の公開は既存の Query バインディングが持つ。ここは温存する。
- **不足している保証（追加が必要）**: per-request の pending/result はそれぞれ独立して公開されるため、「どのリクエストが最新か」を選ぶ採用判断は binding の外に置く必要がある。既存機構がこの選別まで保証しているという記述はタスク文にはないので、Mediator 相当の関数に `latestId` という1個の追加状態を置く。
- **tooltip**: 業務フロー・検索の可否・表示採用に影響しない独立した View 状態。既存のローカル state のままでよい。

## 2. 操作間の制約

- 検索イベントは連打・再入力で重複しうる。新しい検索が発行されても、進行中の古いリクエストへの cancel は best effort であり、サーバー側停止を保証しない（＝古いリクエストの成功/失敗通知は、新しいリクエストの完了より後に届くこともありうる）。
- 表示に採用してよいのは、直近に発行したリクエストの成功/失敗だけ。それ以外の解決は「結果は採用しないが、解決自体は処理する（後始末のため）」。
- tooltip の開閉はこの制約と独立。検索の許可・進行・表示に一切影響しない。

## 3. 必要な判断の所在

- 「どのリクエストの結果を採用するか」という一つの判断だけを Mediator 相当の純粋関数へ集約する（`latestId` という1個の追加状態）。
- tooltip は View ローカルのまま独立に保つ。共通の親へは委ねない（競合するフローではないため）。

## 4. 責務の所有者（本シナリオへの当てはめ）

| 役割 | 本シナリオでの担当 |
| --- | --- |
| Model／ユースケース | 検索結果の成功/失敗という業務的な結果そのもの（本メモの対象外、既存のAPI/ユースケースが返す） |
| Mediator | どのリクエストIDが「最新」で表示採用対象かを決める。古いIDの解決は採用しない。 |
| 実行層 | Query 自体（発行・best-effort cancel・購読解除・解決通知）。温存し、新設しない。 |
| UI binding | Query が公開する pending/result（per request）。そのまま使う。 |
| View | 検索欄の表示・tooltip の開閉。表示は Mediator の採用結果から導出するだけで、採用判断そのものは持たない。 |

## 5. 状態の説明

抽象モデルを作成したため5列表を使う。

| 状態 | 判断に使う目的・所有者 | 抽象モデルでの区分 | 抽象モデルでの表現 | 本実装での情報源 |
| --- | --- | --- | --- | --- |
| `nextId` | リクエストとその解決通知を照合するID発行。既存 binding／実行層 | 既存binding／実行層の模擬 | モデル内の連番 | 未確認。確認対象: 使用中の Query クライアントがリクエスト単位で公開する識別子・AbortController の紐付け方 |
| `bindingState[id]`（`status`/`query`/`data`/`error`） | 各リクエストの pending/result 表現。既存 binding | 既存binding／実行層の模擬 | id をキーとするモデル内 map | 既存の search binding が公開する per-request の pending/result（task 文で明言されている部分） |
| `latestId` | 表示へ採用する最新リクエストの選択。per-request で公開される pending/result からの採用判断は既存 binding が持たない前提のため、追加の裁定として置く | 追加の裁定 | モデル内で保持する最新リクエストID | 検索実行時に呼ばれる Mediator 相当の関数が保持する1個の状態。未確認（非ブロッキング）: 既存 binding 側にすでに転用できる「最新マーカー」があれば、`latestId` を新設せずそれへ委譲できる |
| `tooltipOpen` | 当該 View 内の開閉。View | View の局所状態 | モデル内の真偽値 | 当該 tooltip コンポーネントの既存ローカル state |
| （self-check内の）`before`/`firstBefore`/`results[]` | assertion・検査結果の集計だけに使用。検査側 | 検証専用の補助 | 検査側のローカル値 | 本実装には不要 |

## 6. イベントと採用方針

- `search(query)`: 新規リクエストを発行する。直前の `latestId` がまだ pending なら、その id へ best-effort な `cancelRequest` を発する（**停止の証明にはならない**）。すでに settled の場合は cancel を送らない。新しい id を `bindingState` に `pending` で追加し、`latestId` をその id に更新する。
- `resolve(id, outcome)`: 指定 id の pending/result を成功/失敗で更新する。未知の id（モデルが発行していない id）は no-op（状態・効果とも変化なし）。`latestId` と一致するかどうかに関わらず必ず `bindingState[id]` を更新し、`requestSettled` 効果を出す（後始末は採用可否と無関係に必要）。
- `toggleTooltip()`: `tooltipOpen` を反転する。`bindingState` にも `latestId` にも触れない。

表示は `selectDisplay(bindingState, coordination)`（`coordination` は `latestId` を持つ値。self-check では `state` そのものを渡している）から導出する読み取り専用関数で得る。`resolve` は `bindingState` だけを更新し、`display` という別の場所は持たない。

**コード読解による主張と、実行検査で照合した主張の区別**:
- 「`selectDisplay` は `latestId` のエントリしか読まないので、他 id への `resolve` は表示を変え得ない」という一般則は、コード読解（`selectDisplay` の実装を読めば成り立つ）による主張である。実行検査では、この一般則の複数のインスタンス（`staleResolution`／`newestFirstThenStaleFailure`／`repeatedTextReentry`／`bestEffortCancelStillArrives` の各ケースでの具体的な id・タイミングの組）を個別に照合しており、一般則そのものを網羅的に検査したわけではない。
- 「settled 済みの id へは cancel を送らない」は §7 `noCancelWhenPreviousAlreadySettled` で実行検査済み（コード読解だけの主張ではない）。

## 7. 検証ケースと期待値

純粋性の検査は、個別の `purityCheck` ケースを設けず、共有ヘルパー `step(state, event)` を経由してすべてのケースの全 `transition` 呼び出しに適用した（下記ヘルパー本体を1回引用し、各行から参照する）。これにより「search（cancel あり／なし）」「resolve（最新 id／stale id／未知 id）」「toggleTooltip」の全分岐が、少なくとも1回は純粋性チェック付きで実行されている。

```js
function step(state, event) {
  const before = snapshot(state);
  const first = transition(state, event);
  assertEqual(state, before, 'input state must stay unchanged after 1st call');
  const firstBefore = snapshot(first);
  const second = transition(state, event);
  assertEqual(state, before, 'input state must stay unchanged after 2nd call');
  assertEqual(first, firstBefore, 'first result must not have been mutated since');
  assertEqual(second, firstBefore, 'same input must produce the same output');
  return first;
}
```

| ケース | 操作列 | 期待値 |
| --- | --- | --- |
| `normalPath` | 初期状態→`search("cat")`→`resolve(id0, success)` | id0 の成功が表示に採用される（`latestId===0`） |
| `staleResolution` | `search("cat")`[id0]→`search("dog")`[id1]→`resolve(id0, success)`→`resolve(id1, success)` | id0 の遅延成功は無視（表示は pending のまま）。id1 の成功のみ採用される |
| `newestFirstThenStaleFailure` | `search("cat")`[id0]→`search("dog")`[id1]→`resolve(id1, success)`→`resolve(id0, failure)` | 最新が先に成功した後で旧idの失敗が届いても、表示は成功のまま失敗へ上書きされない |
| `repeatedTextReentry` | `search("cat")`[id0]→`search("dog")`[id1]→`search("cat")`[id2, 同一テキスト]→`resolve(id0)`→`resolve(id2)` | id0（過去の同一テキスト）の結果は無視。id2（最新）の結果のみ採用 |
| `bestEffortCancelStillArrives` | `search("cat")`[id0]→`search("dog")`[id1, id0へcancelRequest]→`resolve(id0, failure)` | cancel 送信後でも id0 の解決は届き得る。表示には反映されない（id1 は pending のまま） |
| `noCancelWhenPreviousAlreadySettled` | `search("cat")`[id0]→`resolve(id0, success)`→`search("dog")`[id1] | 直前の id0 はすでに settled なので、2回目の `search` は `cancelRequest` を出さない |
| `resolveUnknownId` | 初期状態→`resolve(999, success)` | 未発行の id への解決は no-op（状態・効果とも不変） |
| `tooltipIndependence` | `search("cat")`→`toggleTooltip()`→`resolve(id0, success)` | tooltip の開閉は bindingState/latestId に影響しない。逆に検索イベントは tooltipOpen に影響しない |

## 8. 根拠表（実行結果）

`node model.mjs; echo exit=$?` を実行。

```
[PASS] normalPath
[PASS] staleResolution
[PASS] newestFirstThenStaleFailure
[PASS] repeatedTextReentry
[PASS] bestEffortCancelStillArrives
[PASS] noCancelWhenPreviousAlreadySettled
[PASS] resolveUnknownId
[PASS] tooltipIndependence

8/8 cases passed
exit=0
```

各行の比較式は「純粋性（`step` 経由、上記ヘルパー本体を参照）」と「意味内容（`assertEqual`／`assert.ok`／`assert.notEqual` の個別呼び出し）」を分けて記す。

| ケース | 観測時点 | 照合値・比較相手 | 比較式の抜粋 | 検査結果 |
| --- | --- | --- | --- | --- |
| normalPath | `search("cat")`直後 | 発行効果／latestId | `assertEqual(res.effects, [{ type: 'startRequest', id: 0, query: 'cat' }])`、`assertEqual(state.latestId, 0)` | 成功（`[PASS] normalPath`）。純粋性は `step` 経由で同時に照合済み |
| normalPath | `resolve(id0, success)`直後 | 表示は成功データ | `assertEqual(selectDisplay(...), { status: 'success', query: 'cat', data: ['Cat'] })` | 成功（同上） |
| staleResolution | 2件目の`search`直後 | cancel効果+新規発行効果 | `assertEqual(searchRes.effects, [{ type: 'cancelRequest', id: 0 }, { type: 'startRequest', id: 1, query: 'dog' }])` | 成功（`[PASS] staleResolution`） |
| staleResolution | 旧id(id0)の遅延成功直後 | 表示はid1のpendingのまま／id0自体はsettled | `assertEqual(selectDisplay(state...), { status: 'pending', query: 'dog' })`、`assertEqual(state.bindingState[0].status, 'success')` | 成功（同上） |
| staleResolution | 現id(id1)の成功直後 | 表示はid1の成功データ | `assertEqual(selectDisplay(state...), { status: 'success', query: 'dog', data: ['Dog'] })` | 成功（同上） |
| newestFirstThenStaleFailure | id1(最新)の成功直後 | 表示は成功データ | `assertEqual(selectDisplay(state...), { status: 'success', query: 'dog', data: ['Dog'] })` | 成功（`[PASS] newestFirstThenStaleFailure`） |
| newestFirstThenStaleFailure | id0(旧)の遅延failure直後 | 表示は成功のまま変化なし／id0はsettled | `assertEqual(selectDisplay(state...), { status: 'success', query: 'dog', data: ['Dog'] })`、`assertEqual(state.bindingState[0].status, 'failure')` | 成功（同上） |
| repeatedTextReentry | 同一テキストの3回目`search`直後 | `latestId`はid2でありid0とは不一致 | `assertEqual(state.latestId, 2)`、`assert.notEqual(state.latestId, 0)` | 成功（`[PASS] repeatedTextReentry`） |
| repeatedTextReentry | id0（旧"cat"）の遅延成功直後 | 表示はid2のpendingのまま | `assertEqual(selectDisplay(state...), { status: 'pending', query: 'cat' })` | 成功（同上） |
| repeatedTextReentry | id2（新"cat"）の成功直後 | 表示はid2の成功データ | `assertEqual(selectDisplay(state...), { status: 'success', query: 'cat', data: ['FRESH cat'] })` | 成功（同上） |
| bestEffortCancelStillArrives | cancel送信直後 | cancelRequest効果にid0を含む | `assert.ok(cancelRes.effects.some(e => e.type === 'cancelRequest' && e.id === 0))` | 成功（`[PASS] bestEffortCancelStillArrives`） |
| bestEffortCancelStillArrives | id0の遅延failure直後 | 表示はid1のpendingのまま／id0はsettled | `assertEqual(selectDisplay(state...), { status: 'pending', query: 'dog' })`、`assertEqual(state.bindingState[0].status, 'failure')` | 成功（同上） |
| noCancelWhenPreviousAlreadySettled | settled後の2回目`search`直後 | 効果にcancelRequestを含まない | `assertEqual(res.effects, [{ type: 'startRequest', id: 1, query: 'dog' }])` | 成功（`[PASS] noCancelWhenPreviousAlreadySettled`） |
| resolveUnknownId | 未知id解決直後 | 状態・効果とも不変 | `assertEqual(res.state, state)`、`assertEqual(res.effects, [])` | 成功（`[PASS] resolveUnknownId`） |
| tooltipIndependence | `toggleTooltip`直後 | bindingState/latestIdは不変、tooltipOpenのみ変化 | `assertEqual(state.bindingState, beforeToggle.bindingState)`、`assertEqual(state.latestId, beforeToggle.latestId)`、`assertEqual(state.tooltipOpen, true)` | 成功（`[PASS] tooltipIndependence`） |
| tooltipIndependence | 検索の`resolve`直後 | tooltipOpenは検索イベントで不変 | `assertEqual(state.tooltipOpen, true)` | 成功（同上） |
| 全ケース共通 | 各 `step(state, event)` 呼び出し直後（1回目・2回目） | 入力state不変（×2）・初回結果保持・同入力結果一致 | ヘルパー本体（§7）内の4つの`assertEqual`（`state, before` を2回、`first, firstBefore`、`second, firstBefore`） | 成功（8ケース全て `[PASS]`。exit=0 の下で全 `step` 呼び出しが例外なく完了） |

## 9. ケースと操作列の対応確認（最終編集後の照合）

- `normalPath` は単独の開始→自身の正常完了のみで構成し、失敗・反復要求・古い通知を含まない（分担どおり）。
- `staleResolution`／`newestFirstThenStaleFailure`／`repeatedTextReentry`／`bestEffortCancelStillArrives` は「古い通知」区分（順序違いを含む）に対応する別ケースとして分離されている。
- `noCancelWhenPreviousAlreadySettled`／`resolveUnknownId` は `transition` の分岐網羅のために追加した境界ケース。
- `tooltipIndependence` は tooltip が業務フローと無関係であることを、双方向（tooltip→検索に影響しない／検索→tooltipに影響しない）で確認する。
- 純粋性は個別ケースを設けず、全ケースの全 `transition` 呼び出しを `step()` 経由にすることで、実際に踏んだ分岐すべてに適用されている。

## 10. 状態表の照合

`initState()` が返す全フィールド（`nextId`／`bindingState`／`latestId`／`tooltipOpen`）は上記「状態の説明」表の行と一対一で対応済み。モデル外に隠れた保持フィールドはない。

## 11. 未実行・未確認の範囲

- （非ブロッキング）既存の search binding 側に、すでに転用できる「最新マーカー」（常に最新の呼び出しへ追従する仕組み）が存在するかは未確認。あれば `latestId` はそれへ委譲でき、新設は不要になる。対象実装ファイルを読んで確認する。
- 実際の Query クライアント（TanStack Query 本体）とこのモデルの `bindingState`／`nextId`／`cancelRequest` 効果との対応づけ（発行id・AbortController の実装）は未確認。
- **モデルが表現できていない再入力時のハザード**: 本モデルは `bindingState` をリクエスト id（`nextId` 採番）でキー管理しているため、同じテキストへの再入力（id0 と id2 がどちらも `"cat"`）でも常に別スロットに分かれ、self-check はここで green になる。しかし実際の Query ベースの binding が「クエリテキストをキーにしたキャッシュ」を持つ構成なら、id0 と id2 は同一スロットを共有し、id0 の遅延結果が id2 の表示を上書きする恐れがある。これは task 文の「re-entering the same text」がまさに指す危険であり、本モデルの green な self-check では検出できない。統合検証時の確認対象として残す: 実際の完了経路が「クエリキー一致」だけでなく「リクエスト識別（操作ID）一致」で採用可否を判定しているかを確認する（binding 未読のため条件付き）。
- `startRequest`／`cancelRequest`／`requestSettled` という効果を実行層（Query 呼び出し）へどう配線するかは、実アプリ結線の検証であり本モデルの self-check の範囲外（検査未実装）。
- ネットワーク遅延・実タイマーを使った実ブラウザでの人手確認は未実施。
