# React / TanStack / Effect-TS への当てはめ

`SKILL.md` の4点を、この技術スタックでどう実装するかの具体例。ROP(bind/map/tee)の書き方自体は `rop` skill の `references/effect-ts.md` を読む。ここでは「Mediator が Effect を呼ぶ場所」だけを扱う。

## Root

TanStack Router の Root Route (`createRootRoute`) がそのまま Root の実体になる。Mediator はここで一度だけ生成し、Context で配下全体に渡す。Route ごとに Mediator を作り直さない — Mediator は状態機械であり、Route 遷移をまたいで状態を持ち得る。

```tsx
// routes/__root.tsx
export const Route = createRootRoute({
  component: () => (
    <MediatorProvider>
      <Outlet />
    </MediatorProvider>
  ),
});
```

## Passive View

コンポーネントは props と、その props から導出できる表示専用の local state しか持たない。TanStack Query の `useQuery` / `useMutation` を Passive View の中で直接呼ばない — それは「データ取得」という判断であり、Mediator の責務。

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

`useQuery` でこのコンポーネント自身が注文一覧を取りに行く実装は Passive View 違反。一覧取得は Mediator (または Mediator が委譲する Query 層) の仕事で、`OrderRow` は結果を props で受け取るだけにする。

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

Mediator は bubble してきたイベントを受け取り、Effect-TS の tagged union で状態を持つ。**遷移関数 (`reduce`) は同期・純粋な関数にする** — 非同期I/Oを `reduce` の中で完結させると、型で宣言した中間状態(`Cancelling` 等)へ実際には遷移できなくなる(1ステップで結果まで確定してしまうため)。非同期I/Oは `reduce` を呼び出す側(Mediator の Provider)が行い、結果を新しいイベントとして `reduce` に戻す。

```tsx
type OrdersState =
  | { _tag: "Idle" }
  | { _tag: "Ready"; orders: Order[] }
  | { _tag: "Cancelling"; orderId: string; orders: Order[] }
  | { _tag: "Failed"; reason: string; orders: Order[] };

type OrdersEvent =
  | { _tag: "FetchSucceeded"; orders: Order[] }
  | { _tag: "CancelRequested"; orderId: string }
  | { _tag: "CancelSucceeded"; orderId: string }
  | { _tag: "CancelFailed"; reason: string };

// 同期・純粋 — 非同期I/Oを持たない。呼び出し側が結果をイベントとして戻す。
const reduce = (state: OrdersState, event: OrdersEvent): OrdersState => {
  switch (event._tag) {
    case "FetchSucceeded":
      // Model 層からの背後通知も同じ state machine を通す — 進行中の遷移を無条件に上書きしない。
      if (state._tag === "Cancelling") return state;
      return { _tag: "Ready", orders: event.orders };
    case "CancelRequested":
      if (state._tag !== "Ready") return state; // 不正な遷移は無視 — 状態機械が唯一の裁定者
      return {
        _tag: "Cancelling",
        orderId: event.orderId,
        orders: state.orders,
      };
    case "CancelSucceeded":
      if (state._tag !== "Cancelling") return state;
      return {
        _tag: "Ready",
        orders: withoutOrder(state.orders, event.orderId),
      };
    case "CancelFailed":
      if (state._tag !== "Cancelling") return state;
      return { _tag: "Failed", reason: event.reason, orders: state.orders };
    default:
      return state;
  }
};

// 呼び出し側 (Provider 内) — dispatch は素通しするだけで、reduce と同じ許可条件を重複させない。
const requestCancel = (orderId: string) =>
  dispatch({ _tag: "CancelRequested", orderId });

// 副作用は「Cancelling へ実際に入ったこと」自体から駆動する。dispatch する側で
// 「今 Ready か」を manually 確認する guard を重複させると、唯一の裁定者が2箇所に分裂する —
// reduce が Ready 以外からの CancelRequested を無視した結果として Cancelling に
// "実際に入った" ときだけ、この effect が動く。
useEffect(() => {
  if (state._tag !== "Cancelling") return;
  const orderId = state.orderId;
  Effect.runPromise(
    Effect.match(cancelOrder(orderId), {
      onSuccess: (): OrdersEvent => ({ _tag: "CancelSucceeded", orderId }),
      onFailure: (reason): OrdersEvent => ({
        _tag: "CancelFailed",
        reason: reason.message,
      }),
    })
  ).then(dispatch);
}, [state._tag, state._tag === "Cancelling" ? state.orderId : null]);
```

`OrderRow` / `OrderTable` はこの `OrdersState` から導出した props しか受け取らない。分岐 (`state._tag !== "Ready"` を見て無視する、など) は Mediator の中だけにあり、View 側には現れない。

## Wiring: connector と selector

Mediator の Context を読むのは機能ごとにちょうど1つの connector だけにする。`disabled` の算出や表示文言の選択のように複数の値を組み合わせる合成は connector 側の `select*` 関数が行い、Passive View には確定済みの値だけを渡す。

```tsx
const selectOrderRowProps = (state: OrdersState, order: Order) => ({
  order,
  isCancelling: state._tag === "Cancelling" && state.orderId === order.id,
});

function OrdersPage() {
  const { state, dispatch } = useOrdersMediator();
  // state tag によるマウント切り替えは Mediator が既に決めた状態を 1:1 で写しているだけ — 新しい判断ではない。
  if (state._tag !== "Ready" && state._tag !== "Cancelling") return null;
  return (
    <OrderTable
      rows={state.orders.map((o) => selectOrderRowProps(state, o))}
      onCancelRequested={(orderId) =>
        dispatch({ _tag: "CancelRequested", orderId })
      }
    />
  );
}
```

## TanStack Query との関係

TanStack Query の `queryFn` / `mutationFn` は Model 層の実装であって、Mediator が呼ぶ相手であり、Passive View が呼ぶ相手ではない。Effect-TS でラップした Model を Mediator から `Effect.tryPromise` 等で呼ぶか、TanStack Query の cache 自体を Model として Mediator に注入するかは実装判断だが、いずれの場合も **呼び出し元は Mediator 一箇所**にする。複数のコンポーネントがそれぞれ `useQuery` を呼んでいたら、それは Mediator が1つでなくなっているサイン。

`reduce` を純粋・同期にしておく利点はテスト容易性にも及ぶ。Model 層(fetch 関数)を Mediator へ注入可能にしておけば、実際の API を呼ばずに `reduce` 単体のテストと、レスポンスの到着順を制御した Mediator の統合テストの両方を書ける。

TanStack Query は `refetchOnWindowFocus` などで Mediator の関与なく背後から結果を通知してくる。これも UI 起因のイベントと同じく `reduce` を通す一つの `OrdersEvent` として扱い、進行中の遷移(`Cancelling` など)を黙って上書きさせない(上の `FetchSucceeded` のガードを参照)。「Model のライフサイクル通知だから state machine の外で処理してよい」という例外を作らない。

連打によるページ送りなどで古いレスポンスを無視する必要がある場合も、`useEffect` のクリーンアップに `let cancelled = false` を仕込んで判定しない — それ自体が `reduce` と競合するもう一つの裁定者になり、`reduce` 側のガードが到達しないデッドコードになる。リクエストしたページ番号のような domain の識別子を event に含め、`reduce` がその識別子を現在の state と突き合わせて判定する一箇所に一本化する。

**ドメイン規則の可否判定(例: 発送済みはキャンセル不可)は Model 層の応答を唯一の正とし、`reduce` の中で同じ規則を重複して持たない。** `reduce` が見るのは「今この state でこのイベントが意味を持つか」という state machine 自身の整合性だけで、業務規則そのものの成否ではない。View がボタンを disabled 表示するなど見た目のヒントを出す場合も、state に既にある注文データから導出するだけにとどめ、業務規則を新たに判定させない。
