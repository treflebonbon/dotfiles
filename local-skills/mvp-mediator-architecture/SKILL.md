---
name: mvp-mediator-architecture
description: "Enforce a Passive View (MVP) + Mediator component architecture for React/TanStack/Effect-TS frontends: every component lives under one Root, is a pure Passive View limited to render parameters, and bubbles behavior as events via Chain of Responsibility up to a Mediator that arbitrates as an explicit state machine. Use whenever writing or reviewing React components, deciding where component logic/state/business rules belong, wiring event handlers or callbacks between parent and child components, or splitting up a growing component — even if the user never names MVP, Passive View, Mediator, or Chain of Responsibility explicitly, just describes a component getting hard to test or doing too much. Governs component/event architecture only; for Effect-TS Result/error-handling composition, see the `rop` skill instead."
allowed-tools: Read, Edit, Write
metadata:
  depends_on: [rop]
  topics:
    [
      react,
      tanstack,
      effect-ts,
      mvp,
      passive-view,
      mediator,
      chain-of-responsibility,
      state-machine,
      frontend-architecture,
    ]
  source: human
---

# MVP + Mediator Architecture

## The doctrine

React/TanStack/Effect-TS のコンポーネント構成は次の4点を1つの一貫したアーキテクチャとして適用する。個別の tips ではなく、互いに支え合う制約として扱う: Passive View がロジックを持たないから CoR で bubble させる必要があり、bubble させるから Mediator という唯一の裁定者が要る。

1. **Root 集約** — すべてのコンポーネントは単一の Root の配下に置く。Root の外にコンポーネントを作らない。CoR のイベントが必ずどこかへ終着するための、ツリーの単一の終端。
2. **Passive View (MVP)** — 各コンポーネントは描画パラメータ（props / 表示用ローカル state）だけを操作する。分岐条件・計算・API 呼び出し・状態遷移の判断はコンポーネント内に書かない。ローカルに持ってよいのは、何の判断にも使われない表示専用の状態(トグルの開閉、フォーカスなど)だけ。入力欄の値のように何らかの判断(バリデーション等)の材料になる値は、コンポーネントに保持せず生の値のまま Mediator へ bubble させ、確定した表示値を props として受け取り直す(controlled)。複数の値を組み合わせて `disabled` や表示文言を決めるのも計算であり、Mediator 側(state → props への変換)で確定させてから View に渡す。
3. **Chain of Responsibility** — 動作はコンポーネント内で完結させず、イベントとして親へ bubble させる。中間コンポーネントは pass-through に徹し、イベントの意味を解釈・改変しない。bubble の終着点(Mediator)で生の callback を tagged event に組み立て直すのは違反ではない — 違反になるのは途中の中間コンポーネントが意味を解釈・改変すること。
4. **Mediator = state machine** — bubble してきた全イベントの唯一の裁定者。UI 起因のイベントだけでなく、Model 層(TanStack Query のキャッシュ更新・再検証などの非同期通知)も同じ state machine のイベントとして扱い、進行中の遷移を無条件に上書きさせない。遷移関数 (`reduce`) 自体は同期・純粋にし、非同期I/Oは呼び出す側が行って結果を新しいイベントとして戻す — 遷移関数の中で非同期処理を完結させると、型で宣言した中間状態に実際には到達できなくなる。副作用(API 呼び出し等)は「その state に実際に入ったこと」自体から駆動し、dispatch する側に `reduce` と同じ許可条件を重複させない — 重複させると唯一の裁定者が2箇所に分裂する。典型的な事故は `useEffect` のクリーンアップに `let cancelled = false` を仕込んで古い応答を握りつぶすパターンで、これも隠れたもう一つの裁定者になる。古い応答を無視する判断は `reduce` 内のガード(domain の識別子で比較する)だけに一本化する。コンポーネント側は Mediator が決めた描画パラメータを受け取るだけ。

ROP（Railway Oriented Programming）準拠は `rop` skill（`references/effect-ts.md`）に従う。ここでは重複させない。

## Wiring

Mediator の Context を読むのは、機能ごとにちょうど1つの「connector」コンポーネントだけにする。それより下位はすべて props しか受け取らない Passive View。connector が `state._tag` を見てどの Passive View をマウントするか選ぶ分岐は rule 2 の違反ではない — Mediator が既に決めた状態を 1:1 でコンポーネント選択に写しているだけで、新しい判断をしていない。

## Applying it

新規コンポーネントを書く、または既存コンポーネントをレビューするときは確認する:

- このコンポーネントは Root からたどれる位置にあるか。Root の外に浮いていないか。
- props / 表示 state 以外に分岐条件・計算・API 呼び出しを持っていないか。持っていたら Mediator 側へ移す。
- `disabled` や表示文言のような複数値の合成を View 側で組み立てていないか。Mediator 側(state → props の変換)で確定済みか。
- イベントハンドラは `on〜` 形式で親へ bubble しているか。ハンドラ内で状態更新や API 呼び出しなど処理を完結させていないか。
- 状態遷移の判断が Mediator の外に漏れていないか。複数コンポーネントがそれぞれ独自に同じ判断をしていないか。
- Model 層からの背後通知(キャッシュ更新・再検証等)が UI 起因のイベントを経由せずに描画へ反映されていないか。Mediator の state machine を素通りしていたら、進行中の遷移を無条件に上書きするバグの元になる。
- 副作用の発火条件を dispatch する側で `reduce` と別に判定していないか。state に実際に入ったことから駆動しているか。

React/TanStack/Effect-TS への具体的な当てはめ(Root の置き場所、Mediator の実装パターン、TanStack Query との関係)は `references/tanstack-effect.md` を読む。
