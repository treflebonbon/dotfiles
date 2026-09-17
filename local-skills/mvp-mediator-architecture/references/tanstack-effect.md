# React / TanStack / Effect-TS への当てはめ

`SKILL.md` の4点を、この技術スタックでどう実装するかの具体例。ROP(bind/map/tee)の書き方自体は `rop` skill の `references/effect-ts.md` を読む。ここでは「Mediator が Effect を呼ぶ場所」だけを扱う。

データ取得・非同期処理の層には TanStack Query ではなく `@effect/atom-react`(Effect v4 の公式 React バインディング)を使う。Effect をそのまま `Atom` にすると `AsyncResult`(Initial/Success/Failure、それぞれ再検証中を示す `waiting` フラグ付き)として公開され、Promise への変換を挟まない。Effect v4 は執筆時点で RC のため、`Atom` の import path は安定化前に変わり得る — 実装時は現在の `effect` / `@effect/atom-react` のドキュメントで確認する。

## Root

TanStack Router の Root Route (`createRootRoute`) が Root の実体になる。`@effect/atom-react` の `RegistryProvider` でその配下を包み、Atom の状態をこのサブツリーに閉じる。Route ごとに Provider を作り直さない — Atom はレジストリ単位で状態を持ち、Route 遷移をまたいで保持され得る。

```tsx
// routes/__root.tsx
import { RegistryProvider } from "@effect/atom-react";

export const Route = createRootRoute({
  component: () => (
    <RegistryProvider>
      <Outlet />
    </RegistryProvider>
  ),
});
```

## Passive View

コンポーネントは props と、その props から導出できる表示専用の local state しか持たない。`useAtomValue` / `useAtomSet` を Passive View の中で直接呼ばない — どの Atom を読むか・いつ書き込むかは「データ取得・更新」という判断であり、Mediator(connector)の責務。

```tsx
// 良い例: 受け取ったデータをそのまま描画する
type OrderRowProps = {
  order: { id: string; total: number; status: OrderStatus };
  onCancelRequested: (orderId: string) => void;
};

function OrderRow({ order, onCancelRequested }: OrderRowProps) {
  return (
    <tr>
      <td>{order.id}</td>
      <td>{order.total}</td>
      <td>{order.status}</td>
      <button onClick={() => onCancelRequested(order.id)}>Cancel</button>
    </tr>
  );
}
```

`useAtomValue` でこのコンポーネント自身が注文一覧を取りに行く実装は Passive View 違反。一覧取得は Mediator(または Mediator が委譲する Model 層)の仕事で、`OrderRow` は結果を props で受け取るだけにする。

## Chain of Responsibility

`onCancelRequested` はこの階層で処理を完結させない。呼び出し元へそのまま bubble させる。中間コンポーネントは意味を解釈せず転送するだけ。

```tsx
// 中間コンポーネントは pass-through — イベントの意味を知らない
function OrderTable({ orders, onCancelRequested }: OrderTableProps) {
  return (
    <table>
      <tbody>
        {orders.map((o) => (
          <OrderRow
            key={o.id}
            order={o}
            onCancelRequested={onCancelRequested}
          />
        ))}
      </tbody>
    </table>
  );
}
```

`OrderTable` が `onCancelRequested` の中身を書き換えたり、ここで確認ダイアログを出したりし始めたら、それは判断であり Mediator に属する。

## Mediator = state machine

`Atom.make` は Effect / Stream をそのまま `AsyncResult` の Atom にする。`Atom.fn` は引数を書き込むと Effect を実行し、その結果を `AsyncResult` として公開する書き込み可能な Atom を作る — 「トリガー」と「状態更新」が1回の書き込みに結合されているため、SKILL.md rule 4 が警戒する「dispatch する側に reduce と同じ許可条件を重複させる」失敗が構造的に起きにくい。呼び出し箇所が実質1つ(その Atom への書き込み)しかないため、唯一の裁定者が2箇所に分裂しようがない。

```tsx
import { Atom, AsyncResult } from "effect/unstable/reactivity";

// 一覧取得: Effect をそのまま Atom にすると AsyncResult<Order[], FetchError> になる。
const ordersAtom = Atom.make(fetchOrders);

// キャンセル: 引数(orderId)を書き込むと Effect を実行する Atom。既定では
// 新しい呼び出しが前の in-flight 呼び出しを interrupt する(concurrent: true を渡さない限り)。
// 連打で新しいキャンセルが発火しても、古い呼び出しの結果が後から状態を上書きすることはない。
const cancelOrderAtom = Atom.fn((orderId: string) => cancelOrder(orderId));

// 「今どの注文をキャンセル中か」という domain 固有の表示状態だけは通常の書き込み可能 Atom で持つ。
// AsyncResult 自体は「今どの引数で呼ばれたか」までは持たないため、行の isCancelling 判定に要る。
const cancellingOrderIdAtom = Atom.make<string | null>(null);
```

`OrderRow` / `OrderTable` はこの Atom 群から導出した props しか受け取らない。`AsyncResult.match` によるパターンマッチは Mediator(connector)の中だけにあり、View 側には現れない — 具体例は次節。

## Wiring: connector と selector

Mediator の Atom を読むのは機能ごとにちょうど1つの connector だけにする。`AsyncResult.match` / `matchWithWaiting` による状態ごとの view props の組み立て(selector)も connector 側の責務で、Passive View には確定済みの値だけを渡す。

```tsx
function OrdersPage() {
  const ordersResult = useAtomValue(ordersAtom);
  const [cancelResult, runCancel] = useAtom(cancelOrderAtom);
  const [cancellingOrderId, setCancellingOrderId] = useAtom(
    cancellingOrderIdAtom
  );
  const refreshOrders = useAtomRefresh(ordersAtom);

  // cancelResult が「今キャンセル対象にしている注文」の成功へ落ち着いたら、
  // キャンセル中表示を解除して一覧を再取得する。素の Atom.fn には他の Atom を
  // 自動で無効化する仕組みがないため、この明示的な refresh が必要。
  useEffect(() => {
    if (cancellingOrderId === null) return;
    if (
      AsyncResult.isSuccess(cancelResult) &&
      cancelResult.value.id === cancellingOrderId
    ) {
      setCancellingOrderId(null);
      refreshOrders();
    }
  }, [cancelResult, cancellingOrderId, refreshOrders, setCancellingOrderId]);

  const onCancelRequested = (orderId: string) => {
    setCancellingOrderId(orderId);
    runCancel(orderId);
  };

  // 「キャンセル中」表示は cancelResult.waiting から導く。cancellingOrderIdAtom は
  // 成功パスの useEffect でしかクリアしない — 対称性のために失敗パスでもクリアする
  // 必要はない。waiting が false になった時点で activeCancellingOrderId は自動的に
  // null になり、cancellingOrderId 自体は次にキャンセルするまで残っていて構わない。
  const activeCancellingOrderId =
    cancellingOrderId !== null && cancelResult.waiting
      ? cancellingOrderId
      : null;

  // cancelResult の失敗も、成功パスと対称に identity check をする。AsyncResult は
  // 次の呼び出し中も直前の outcome を waiting:true のまま保持するため、これを怠ると
  // 「別の注文への新しいキャンセル操作」に「前の注文の失敗メッセージ」が一瞬漏れる。
  // matchWithError は型付きドメインエラーをそのまま onError で受け取れるため、
  // Cause.squash によるキャストより安全。
  const cancelError = AsyncResult.matchWithError(cancelResult, {
    onInitial: () => null,
    onSuccess: () => null,
    onDefect: () => null,
    onError: (error) =>
      error.orderId === cancellingOrderId
        ? { orderId: error.orderId, message: describeCancelError(error) }
        : null,
  });

  // selector: AsyncResult のパターンマッチで view props を確定させる。
  return AsyncResult.match(ordersResult, {
    onInitial: () => <p>読み込み中…</p>,
    onFailure: (failure) => <p role="alert">{String(failure.cause)}</p>,
    onSuccess: (success) => (
      <OrderTable
        orders={success.value}
        cancellingOrderId={activeCancellingOrderId}
        cancelError={cancelError}
        onCancelRequested={onCancelRequested}
      />
    ),
  });
}
```

`AsyncResult.match` による画面切り替えは Mediator が既に決めた状態を 1:1 でコンポーネント選択に写しているだけで、rule 2 の違反ではない。

### 単一の Atom.fn が画面全体の状態を表すケース

一覧+行操作(上の例)と違い、フォーム送信のように「1つの `Atom.fn` の `AsyncResult` がそのまま画面全体の state machine」になる場合もある。この形では **`waiting` を `_tag`/`matchWithError` より先に見る** — 失敗後に再送信すると、直前の `Failure` を `waiting: true` のまま引き継ぐため、`_tag` 側から先に分岐すると「再送信中」を「失敗のまま」と誤判定する。

```tsx
type SubmissionState =
  | { _tag: "editing" }
  | { _tag: "submitting" }
  | { _tag: "succeeded"; user: RegisteredUser }
  | { _tag: "failed"; message: string };

const toSubmissionState = (
  result: AsyncResult.AsyncResult<RegisteredUser, RegisterError>
): SubmissionState => {
  if (result.waiting) return { _tag: "submitting" }; // waiting を先に見る — 再送信中を「失敗のまま」と誤判定しない
  return AsyncResult.matchWithError(result, {
    onInitial: () => ({ _tag: "editing" }),
    onSuccess: (s) => ({ _tag: "succeeded", user: s.value }),
    onError: (error) => ({
      _tag: "failed",
      message: describeRegisterError(error),
    }),
    onDefect: () => ({ _tag: "failed", message: "登録に失敗しました" }),
  });
};
```

`refreshOrders()` 後、`ordersAtom` の `AsyncResult` は `_tag: "Success"` のまま `waiting: true`(前回の値を保持しつつ再検証中)を経由する。上の `match` はこれも通常の `onSuccess` として扱うため、再取得中は一覧が一瞬古いままになり得る — この間の区別(たとえば行を薄く表示する等)が必要なら `success.waiting` で分岐するか、`AsyncResult.matchWithWaiting` の `onWaiting` 分岐を使う。同じ staleness は `Failure` 側にも成立する — 「今どの引数を待っているか」の identity check は成功パスだけでなく失敗パスにも対称的に適用する。片方だけに適用すると、この skill が繰り返し警告してきた「同じ判断を一箇所に一本化する」という原則の非対称な適用漏れになる。

## Model 層(Atom)との関係

`Atom.make` / `Atom.fn` に渡す Effect が Model 層の実装であって、Mediator(connector)が呼ぶ相手であり、Passive View が呼ぶ相手ではない。**呼び出し元は Mediator 一箇所**にする — 複数のコンポーネントがそれぞれ `useAtomValue` で同じ Atom を読むのは構わないが(購読は何箇所からでもよい)、`useAtomSet` で書き込む(=判断してトリガーする)のは connector 一箇所にする。

Model 層(Effect)を Atom へ渡す前の関数として独立させておけば、実際の Atom/React を経由せず Effect 単体のテストと、`Atom.fn` を介した統合テストの両方を書ける。ROP の bind/map/tee で Model 層を組み立てる際の書き方は `rop` skill の `references/effect-ts.md` を参照する。

**ドメイン規則の可否判定(例: 発送済みはキャンセル不可)は Model 層の Effect の失敗として表現し、Atom の外や connector 側で同じ規則を重複して持たない。** `AsyncResult` の `Failure` はこの失敗をそのまま運ぶ。View がボタンを disabled 表示するなど見た目のヒントを出す場合も、Atom から得た注文データ(既にある `status` など)から導出するだけにとどめ、業務規則を新たに判定させない。失敗を型付きドメインエラーとして扱う場合は `Cause.squash` してキャストするより `AsyncResult.matchWithError`(`onError`/`onDefect` を分けて受け取れる)を使う方が安全。

素の `Atom.fn` は書き込み成功後に他の Atom を自動では無効化しない — 一覧を再取得したいなら上の例のように `useAtomRefresh` を明示的に呼ぶ。Effect の Layer をまたいだ自動 invalidation(`reactivityKeys`)が要る場合は Layer ベースの runtime 経由で Atom を作る(`Atom.runtime` 等)必要があり、素の `Atom.make`/`Atom.fn` の範囲外になる。Model 層の Effect が Service/Layer に依存し始めたら、この runtime 層の設計は effect-ts 側の知識であり、このスキルの範囲(コンポーネント構成)を超える。

## Router / Form / Table: 境界の原則

TanStack Router に加え TanStack Form・Table を使う場合、それぞれが自分の狭い関心事(ルーティング、フィールド単位の入力値と入力形式チェック、グリッドの並び替え・行モデル構築)を持つこと自体は rule 2 の違反ではない。native な `<input>` が自分のキー入力を保持するのと同じ扱いで、専用ライブラリに委ねてよい局所的な状態とみなす。

境界線は「そのライブラリが完結できる関心事か、フロー全体の判断か」で引く。TanStack Form の `form.Field` / `validators` はフィールドの入力形式チェックまでを担ってよいが、送信全体の状態遷移(編集中・送信中・成功・失敗)とドメイン規則の可否判定は引き続き Mediator が持つ — `form.handleSubmit` はバリデーション済みの値を1つのイベントとして Mediator へ bubble させるだけにする。TanStack Table の `useTable` はソート・フィルタ・行モデル構築を担ってよいが、どの行を表示するか(取得したデータそのもの)は Mediator から渡された Atom の状態に従う。どちらも API のバージョン差が大きいため、導入時は各ライブラリの現在のドキュメントで実装を確認する。

**注意**: TanStack Form 自身が持つ `form.state.isSubmitting` / `canSubmit` のような、Mediator の状態と名前・形が似た値を Mediator の代わりに使わない。今は見た目が一致していても(例: Mediator への送信を fire-and-forget にしている間はたまたま同期している)、送信を `await` する実装に変える等の変更で簡単に乖離する。「送信中」の唯一の正は Mediator の `AsyncResult`(上の `toSubmissionState`)であり、ライブラリが持つ同名・同形の値は使わない。
