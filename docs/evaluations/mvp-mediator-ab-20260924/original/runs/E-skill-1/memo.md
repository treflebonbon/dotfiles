# Recording/Calibration exclusion — responsibility & verification memo

## 責務の所有者

| 役割 | 所有する責務 | 本タスクでの担当 |
| --- | --- | --- |
| Model／ユースケース | 業務規則（同時に1つの資源しか保有できない、という排他制約自体） | `model.mjs` の外側、既存アプリのユースケース層。本モデルはこの制約が既にあることを前提に、調停の**方針**だけを持つ。 |
| Mediator（本モデル） | recording／calibration という競合する2フローの開始許可・状態遷移・取消（latest-intent）方針・stop/release失敗時のブロック・再試行方針・結果採用 | `model.mjs` の `transition` |
| 実行層 | 実際の acquire/stop/release の実行、ID発行、完了通知 | 既存の Effect 実行境界（本モデルは `effects` としてコマンドを出力するのみ、I/Oは行わない） |
| UI binding／View | recording・calibration それぞれの表示、profile editor | 本モデルの範囲外。`profile` イベントは Mediator の決定状態に一切触れないことでこれを示す（独立フローは独立のまま）。 |

Root は「唯一の裁定者」＝ recording と calibration という**競合する2フロー**だけを対象にする共通の親。profile editor は競合しないため、この親を経由しない独立フロー。

## 状態の説明

| 状態 | 判断に使う目的・所有者 | 抽象モデルでの区分 | 抽象モデルでの表現 | 本実装での情報源 |
| --- | --- | --- | --- | --- |
| `phase` | 現在の調停段階（idle/acquiring/active/stopping/releasing/blocked）。Mediator | 追加の裁定 | 列挙値 | Mediator が新規に持つ（既存 binding には排他調停の概念がないため） |
| `owner` | 現在資源を保有しているフロー。Mediator（実際の保有は実行層） | 既存 binding／実行層の模擬 | `'recording'\|'calibration'\|null` | 未確認: 実行層（Effect Scope／デバイスハンドル）が「今どちらが確保済みか」を返せるか確認する。返せるなら Mediator は別途保持不要。 |
| `desired` | 最新の意図（latest-intent-wins の対象）。Mediator | 追加の裁定 | `'recording'\|'calibration'\|null` | Mediator が新規に持つ。既存 binding は「今実行中の1件」は追えても「複数回の切替後の最新意図」は追えない想定（例3と同じ不足制約）。 |
| `operationId` | 進行中コマンドとの完了通知の照合、古い通知の除外 | 既存 binding／実行層の模擬 | モデル内の連番 (`nextId`) | 未確認: 既存の実行境界（Effect の Fiber ID や実行結果）が返す操作IDを使えるか確認する。使えるなら `nextId` 発行はモデル固有の模擬で置き換えられる。 |
| `nextId` | `operationId` 発行元。ID再利用を防ぐカウンタ | 既存 binding／実行層の模擬 | state内の単調増加する数値 | 同上（`operationId` と同じ情報源） |
| `pendingTarget` | 進行中コマンド（acquire/stop/release）の対象。`ok`/`fail` は `id` しか運ばないため、対象を Mediator 側で覚えておく必要がある | 追加の裁定 | `'recording'\|'calibration'\|null` | 未確認: 実行層の完了通知が対象（target）も一緒に返すなら不要。本モデルのイベント契約（`{type:'ok',id}` のみ）を前提にした裁定側の保持。 |
| `blockedStage` | `blocked` 時にどの段階（stopping/releasing）を `retry` で再開すべきか | 追加の裁定 | `'stopping'\|'releasing'\|null` | Mediator が新規に持つ（失敗時の再試行方針そのもの） |

`operationId`／`nextId` 以外はすべて「本モデルが新設する追加の裁定」であり、既存 binding に同等の保証がない前提（例3の「両フローが同時に動けない場合、共通の親 Mediator が現在の所有者と切替方針を管理する」に対応）。

## 決めた2つの解釈（仕様上あいまいな箇所）

1. **acquisition失敗後の `desired` はnullへリセットする。** 「idle に戻る」を owner/desired/operationId すべて null の単一の正準形とし、idle の意味を経路によらず一定に保った。次の `start` が新たな意図を与えるため、機能上は再試行時に上書きされ影響しない。
2. **`retry` は「失敗した段階そのもの」を厳密に再実行する。** blocked中に `desired` が元の owner に戻っても、`retry` は同じ stop/release を再送する（acquire へ短絡しない）。「latest-intentが勝つ」のは acquiring/stopping/releasing の**進行中**フローに対してであり、`retry` は「失敗した段階の明示的再試行」と仕様が明記しているため、これを文字通り扱った。

## ケースと操作列の対応

| ケース（`check.mjs`） | 対応する方針 |
| --- | --- |
| `normalPath` | 通常経路: start → 正常完了 → active |
| `acquisitionFailureIdle` | acquisition失敗はidleへ、自動再試行なし。意図変更後の失敗でも新owner確保なし |
| `sameOwnerNoOp` | active状態での同一owner start は no-op |
| `switchKeepsIdentityThenSwitches` | acquiring中の最新意図優先、in-flight操作のID不変、取得後に意図と不一致ならstop→release |
| `returningToEarlierTarget` | stopping/releasing中に意図が元へ戻っても進行中操作は不変、release完了後に最新意図（＝復帰後の対象）を再取得 |
| `stopFailureBlocks` | stop失敗→blocked、blocked中の再start（同一でない対象への変更も含む）は意図更新のみで自動再試行なし、blocked/retry境界をまたぐ古いIDは無視、`retry`は失敗段階を厳密再実行 |
| `releaseFailureBlocks` | release失敗→blocked、`retry`はrelease再実行 |
| `staleCompletionsIgnored` | 一致しないID・消費済みIDの完了通知は無視 |
| `unknownAndProfileEventsIgnored` | 未知イベント・`profile`イベントはMediatorの決定状態に無関係 |

各ケース内のすべての `transition` 呼び出しは共通ヘルパー `step()` を経由しており、`step()` は毎回：入力state不変・返却stateの表現契約（plain data）・1回目呼出後の入力保存・2回目呼出後も入力/1回目結果が不変・同一入力での2回目呼出結果が1回目のsnapshotと同値、を確認する（`check.mjs` 冒頭 `assertPlainData` と `step`）。

## 根拠表

実行コマンド: `node check.mjs`（`/tmp/.../scratchpad/ab/runs/E-skill-1/check.mjs`）。実行結果（実測、抜粋なしの全出力）:

```
normalPath: ok
acquisitionFailureIdle: ok
sameOwnerNoOp: ok
switchKeepsIdentityThenSwitches: ok
returningToEarlierTarget: ok
stopFailureBlocks: ok
releaseFailureBlocks: ok
staleCompletionsIgnored: ok
unknownAndProfileEventsIgnored: ok
ALL CHECKS PASSED
```

共通helper（全ケース・全呼出しで使用）:

```js
function step(state, event) {
  const before = structuredClone(state);
  const first = transition(state, event);
  assert.deepEqual(state, before, 'input mutated by 1st call');
  assertPlainData(first.state, 'first.state');
  assertPlainData(first.effects, 'first.effects');
  const firstBefore = structuredClone(first);
  const second = transition(state, event);
  assert.deepEqual(state, before, 'input mutated by 2nd call');
  assert.deepEqual(first, firstBefore, '1st result mutated by 2nd call');
  assert.deepEqual(second, firstBefore, 'same state+event produced a different result');
  return first;
}
```

| ケース | 観測時点 | 照合値・比較相手 | 比較式の抜粋 | 検査結果 |
| --- | --- | --- | --- | --- |
| 純粋性・表現契約（全ケース共通） | 各 `step()` 呼出し直後 | 入力state不変、返却値がplain data、1回目/2回目呼出しの入出力が同値 | `assert.deepEqual(state, before)` / `assertPlainData(first.state, ...)` / `assert.deepEqual(second, firstBefore)` | 成功。実行結果は上記出力（全ケース `ok`、`ALL CHECKS PASSED`） |
| `normalPath` | start直後 | `effects` が `[{type:'acquire',target:'recording',id:1}]`、observeが `acquiring/null/recording/1` | `assert.deepEqual(r1.effects, [...])` / `assert.deepEqual(observe(r1.state), {...})` | 成功 |
| `normalPath` | ok(id=1)直後 | observeが `active/recording/recording/null` | `assert.deepEqual(observe(r2.state), {...})` | 成功 |
| `acquisitionFailureIdle` | 意図変更後のfail(id=1)直後 | idleへ復帰、effects空 | `assert.deepEqual(observe(r3.state), {phase:'idle',owner:null,desired:null,operationId:null})` | 成功 |
| `acquisitionFailureIdle` | 再startのid | 新規id=2（id=1は再利用されない） | `assert.deepEqual(r4.effects, [{type:'acquire',target:'calibration',id:2}])` | 成功 |
| `sameOwnerNoOp` | 同一owner start直後 | 返却stateが入力と同一参照、effects空 | `assert.equal(r.state, active)` | 成功 |
| `switchKeepsIdentityThenSwitches` | acquiring中の意図変更直後 | 進行中id(=1)不変、effects空 | `assert.deepEqual(observe(r2.state), {phase:'acquiring',owner:null,desired:'calibration',operationId:1})` | 成功 |
| `switchKeepsIdentityThenSwitches` | acquire ok後（意図不一致） | owner確保後ただちにstop発行 | `assert.deepEqual(r3.effects, [{type:'stop',target:'recording',id:2}])` | 成功 |
| `switchKeepsIdentityThenSwitches` | stop→release→acquire→ok の連鎖 | 最終的にactive/calibrationへ到達 | `assert.deepEqual(observe(r6.state), {phase:'active',owner:'calibration',desired:'calibration',operationId:null})` | 成功 |
| `returningToEarlierTarget` | stopping中に意図復帰 | 進行中stopの対象・idは不変 | `assert.deepEqual(observe(r2.state), {phase:'stopping',owner:'recording',desired:'recording',operationId:2})` | 成功 |
| `returningToEarlierTarget` | releasing中にも意図往復 | releasingの対象・idは不変 | `assert.deepEqual(observe(r3c.state), {phase:'releasing',owner:'recording',desired:'recording',operationId:3})` | 成功 |
| `returningToEarlierTarget` | release ok後 | 復帰後の最新意図(recording)を再取得 | `assert.deepEqual(r4.effects, [{type:'acquire',target:'recording',id:4}])` | 成功 |
| `stopFailureBlocks` | stop fail直後 | blocked、owner予約継続 | `assert.deepEqual(observe(r2.state), {phase:'blocked',owner:'recording',desired:'calibration',operationId:null})` | 成功 |
| `stopFailureBlocks` | blocked中の失敗id再通知 | 変化なし（同一参照） | `assert.equal(staleOk.state, r2.state)` | 成功 |
| `stopFailureBlocks` | blocked中の再start | 意図のみ更新、effects空 | `assert.deepEqual(observe(r3.state), {phase:'blocked',owner:'recording',desired:'recording',operationId:null})` | 成功 |
| `stopFailureBlocks` | retry直後 | 失敗段階(stop)を再実行、acquireへ短絡しない | `assert.deepEqual(r4.effects, [{type:'stop',target:'recording',id:3}])` | 成功 |
| `stopFailureBlocks` | retry後の旧id(=2)通知 | 無視（同一参照） | `assert.equal(staleAfterRetryOk.state, r4.state)` / `assert.equal(staleAfterRetryFail.state, r4.state)` | 成功 |
| `releaseFailureBlocks` | release fail直後 | blocked、blockedStage=releasing相当 | `assert.deepEqual(observe(r3.state), {phase:'blocked',owner:'recording',desired:'calibration',operationId:null})` | 成功 |
| `releaseFailureBlocks` | retry直後 | release再実行 | `assert.deepEqual(r4.effects, [{type:'release',target:'recording',id:4}])` | 成功 |
| `staleCompletionsIgnored` | 不一致id / 消費済みidの通知直後 | 変化なし（同一参照） | `assert.equal(staleOk.state, r1.state)` / `assert.equal(lateOk.state, r2.state)` | 成功 |
| `unknownAndProfileEventsIgnored` | `profile`/未知イベント直後 | 変化なし（同一参照） | `assert.equal(r1.state, active)` / `assert.equal(r2.state, active)` | 成功 |

実アプリ（Effect実行境界・Atom binding）との結線・実際のID発行機構が本モデルの契約を満たすかは未実行（本タスクはI/Oを行わない抽象モデル・自己検査のみが対象のため）。「状態の説明」表の「本実装での情報源」列に記載した未確認事項がその対象。

## 未実行の範囲

- 実アプリのEffect実行層・Atom bindingとの実結線（本モデルは `effects` を出力するのみ）。
- `operationId`／`pendingTarget` を既存の実行層の情報（Fiber IDや完了通知のtarget）で代替できるかどうかの確認。
