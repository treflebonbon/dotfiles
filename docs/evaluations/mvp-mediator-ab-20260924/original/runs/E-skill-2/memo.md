# 録画／キャリブレーション排他 Mediator — 責務・検証メモ

対象: `model.mjs`（抽象決定モデル）、`check.mjs`（self-check、`node check.mjs` で実行、exit=0・「71 purity-checked transitions executed, all assertions passed」を確認済み）。

## 責務の所有者

| 役割 | 所有する責務 | 本モデルでの扱い |
| --- | --- | --- |
| Model／ユースケース | 「録画とキャリブレーションは同時に device を所有できない」という業務規則そのもの | `transition` の分岐条件（同一 owner 判定・latest-intent 判定・stop→release→acquire の順序）に埋め込み。プロフィール編集は対象外の独立ユースケース |
| Mediator（親、本モデル） | 取得・停止・解放の許可、latest-intent の採用、失敗時の blocked 遷移と明示 retry のみの解除、stale completion の除外 | `model.mjs` の `transition`/`initial`/`observe` |
| 実行層（Effect Fiber／Scope 相当、既存の実行境界） | `acquire`/`stop`/`release` effect の実際の実行、通信中断、リソース解放、id を伴う `ok`/`fail` の報告 | モデル外。本モデルは commands（effects）を返すのみで I/O をしない |
| Child flows（recording UI／calibration UI） | 自身のローカル表示。開始要求は親（本モデル）へ委ねる | モデル外。`observe()` の `phase/owner/desired/operationId` から表示を導出する想定 |
| Profile editor | 完全に独立したフロー。device 排他に無関係 | `profile` イベントは検査した6 phase（idle/acquiring/active/stopping/releasing/blocked）すべてで no-op（状態・所有権に触れない）。`caseProfileIndependent` 参照 |

## 状態の説明

状態はグローバル変数や WeakMap を使わず、全フィールドを `state` オブジェクトに保持する（`model.mjs` を読めば確認できる。人為的な監査はコード読解によるもので、実行検査ではない）。

| 状態 | 判断に使う目的・所有者 | 抽象モデルでの区分 | 抽象モデルでの表現 | 本実装での情報源 |
| --- | --- | --- | --- | --- |
| `phase` | 現在の裁定段階（idle/acquiring/active/stopping/releasing/blocked）。Mediator 所有 | 追加の裁定 | 文字列 enum | 追加する所有者（既存機構に対応する状態がなければ Mediator 側で新設） |
| `owner` | 確保成功から解放成功まで「予約済みの所有者」を表す。Mediator 所有 | 追加の裁定 | `null \| 'recording' \| 'calibration'` | 追加する所有者 |
| `desired` | 直近の `start` が示す latest-intent。Mediator 所有 | 追加の裁定 | `null \| 'recording' \| 'calibration'` | 追加する所有者 |
| `operationId` | 進行中 effect の識別子。stale な `ok`/`fail` を除外するための照合キー | 既存 binding／実行層の模擬（要確認） | モデル内の数値 | **未確認**: 既存の Atom／Fiber binding が既に stale completion を除外する保証を持つか確認する。持つ場合、本実装で `operationId` を別途保持する必要はない |
| `opTarget` | 進行中 effect の target。`acquiring` 中は `desired` と食い違いうるため、完了時に「何を確保したか」を判定するのに必要 | 追加の裁定 | モデル内の保存値。`stopping`/`releasing`/`blocked` 中は常に `owner` と同値になる（コード読解で確認、`model.mjs` の該当分岐参照） | 追加する所有者。ただし stop/release/blocked 中は `owner` と同値なので、本実装では独立フィールドを持たず `owner` を再利用して省略できる |
| `blockedStage` | 失敗した段階（`'stop' \| 'release'`）を記録し、`retry` が再実行する対象を決める | 追加の裁定 | `null \| 'stop' \| 'release'` | 追加する所有者 |
| `nextId` | id 発行の連番（本モデル内でのみ使用） | 既存 binding／実行層の模擬 | モデル内の連番カウンタ | **未確認**: 既存の実行境界（Fiber 起動や Atom の実行 ID）が既に一意な操作 ID を発行しているか確認する。している場合、本実装ではその ID をそのまま使い、モデル固有の連番は不要 |
| `log`/`stepCount`（`check.mjs` 側） | 検査結果の記録・報告専用 | 検証専用の補助 | 検査側のローカル値 | 本実装には不要 |

`phase`/`owner`/`desired`/`operationId` の4つは `observe()` がそのまま返す。`opTarget`/`blockedStage`/`nextId` は内部裁定にのみ使う（`observe` の戻り値には含まれない）。

**解釈の明示**: 「Acquisition failure returns idle without auto-retrying」を、`desired` も `null` にリセットする実装として解釈した（`acqFail.fail`／`acqFailSwitch.fail` で検証）。取得失敗後は `idle` に「進行中の意図」が残らず、再開には利用者の明示的な `start` が必要という設計判断であり、根拠表の該当行を参照。

## ケースと操作列の対応

| 要件（タスク記述） | 対応ケース（`check.mjs`） |
| --- | --- |
| latest start が acquisition/stop/release 中に勝つ。以前の target への復帰を含む | `caseAcquireSwitch`, `caseAcquireReturn`, `caseStopReleaseSwitch`, `caseStopFailure_recovery` |
| in-flight の処理は identity 不変のまま継続する | `stopRelSwitch.flip_during_stop`, `stopRelSwitch.flip_during_release`（`operationId` 不変・`effects=[]`） |
| 確保成功後、latest intent と一致すれば維持、不一致なら stop→release→再確保 | `acqSwitch.ok_mismatch` 以降の連鎖、`acqReturn.ok`（不一致なし＝stop を出さない） |
| stop/release 失敗は明示 retry まで新規確保をブロックする | `caseStopFailure`, `caseReleaseFailure`, 各 `*.retry` |
| blocked 中の反復 start は意図更新のみ、自動再試行なし | `stopFail.repeated_start_1`, `stopFail.repeated_start_2_same_target` |
| acquisition 失敗は idle に戻り自動再試行しない | `caseAcquisitionFailure`, `caseAcquireFailAfterSwitch` |
| active 中の same-owner start は no-op | `caseSameOwnerNoOp` |
| stale completion は無視する | `caseStaleCompletion_neverIssuedId`, `stopFail.stale_*`（3種）, `relFail.stale_*`（4種、うち1件は次段階進行中に前段の完了が遅延到着するケース） |
| profile editor は独立（device 排他に無関係） | `caseProfileIndependent`（idle/acquiring/active/stopping/releasing/blocked の6 phase で確認） |
| 未知イベント・非 blocked 中の retry は無視 | `caseUnknownEvents` |
| 全遷移で入力不変・純粋性 | `check.mjs` の全 71 回の `transition` 呼び出しが `step()` 経由（後述） |

## 純粋な遷移の検査

`check.mjs` の `step(state, event, label)` が、`model.mjs` の**すべての** `transition` 呼び出し（71 回）に対して以下の順序で検査する（一部を除外していない）。

```js
const before = structuredClone(state);
const first = transition(state, event);
assert.deepStrictEqual(state, before, `${label}: state mutated by 1st transition() call`);
const firstBefore = structuredClone(first);
const second = transition(state, event);
assert.deepStrictEqual(state, before, `${label}: state mutated by 2nd transition() call`);
assert.deepStrictEqual(first, firstBefore, `${label}: 1st result changed after 2nd call`);
assert.deepStrictEqual(second, firstBefore, `${label}: 2nd call result != 1st call result`);
```

`structuredClone` を snapshot、`assert.deepStrictEqual` を等値比較として使用。71 回すべてが例外なしで完走し、`node check.mjs` の実行は `exit=0` で「71 purity-checked transitions executed, all assertions passed. / ALL CHECKS PASSED」を出力した（実行済み、下記コマンド・出力を参照）。

- 実行コマンド: `node check.mjs; echo "exit=$?"`
- 実際の出力（末尾3行）:
  ```
  71 purity-checked transitions executed, all assertions passed.
  ALL CHECKS PASSED
  exit=0
  ```

状態表現の契約（plain object／dense array／null／boolean／string／finite number のみ、`Object.prototype` 準拠、getter/setter・Map/Set・class なし）は `model.mjs` を読めば確認できる。`state` は `{phase, owner, desired, operationId, opTarget, blockedStage, nextId}` の7フィールドのみ、`effects` は `{type, target, id}` の dense array のみで構成されており、モジュールグローバルやクロージャに隠れた可変状態は存在しない。**この適合性はコード読解によるものであり、実行検査ではない**（有限回の検査が汎用の純粋性証明にならないのは前述の通り）。

## 根拠表

| ケース | 観測時点 | 照合値・比較相手 | 比較式の抜粋 | 検査結果 |
| --- | --- | --- | --- | --- |
| normalPath | `start(recording)`直後 | `observe(state)` が `{phase:'acquiring', owner:null, desired:'recording', operationId:1}`、effects が `acquire` 1件 | `assert.deepStrictEqual(observe(r.state), {phase:'acquiring', owner:null, desired:'recording', operationId:1})`、`assert.deepStrictEqual(r.effects, [{type:'acquire', target:'recording', id:1}])` | 成功（`node check.mjs` 実行済み、exit=0） |
| normalPath | `ok(1)`直後 | `observe(state)` が `active/recording`、`effects=[]` | `assert.deepStrictEqual(observe(r.state), {phase:'active', owner:'recording', desired:'recording', operationId:null})` | 成功 |
| caseAcquireSwitch（latest-start が acquisition 中に勝ち、不一致で stop→release→再確保） | `ok(op1)`直後（acquired=recording ≠ desired=calibration） | `effects` が `stop` target=recording | `assert.deepStrictEqual(r.effects, [{type:'stop', target:'recording', id:opStop}])` | 成功 |
| caseAcquireReturn（acquisition 中に離れた target へ戻る） | `start(rec)→start(cal)→start(rec)→ok(1)`直後 | `observe` が `active/recording`、`effects=[]`（stop を一切出さない） | `assert.deepStrictEqual(observe(r.state), {phase:'active', owner:'recording', desired:'recording', operationId:null})`、`assert.deepStrictEqual(r.effects, [], 'desired matches what was acquired again: no stop/release needed')` | 成功 |
| caseStopReleaseSwitch（stop/release 中の in-flight identity 不変） | stop 進行中に `start(recording)` を送った直後 | `operationId` が stop 発行時の id のまま、`effects=[]` | `assert.deepStrictEqual(observe(r.state), {phase:'stopping', owner:'recording', desired:'recording', operationId:opStop})` | 成功 |
| caseStopReleaseSwitch | release 進行中に `start(calibration)` を送った直後 | `operationId` が release 発行時の id のまま、`effects=[]` | 上記と同型の `assert.deepStrictEqual(observe(r.state), {..., operationId:opRelease})` | 成功 |
| caseStopFailure（stop 失敗で blocked、新規確保をブロック） | `fail(opStop)`直後 | `observe` が `blocked/owner=recording(予約継続)/desired=calibration/operationId=null`、`effects=[]` | `assert.deepStrictEqual(observe(r.state), {phase:'blocked', owner:'recording', desired:'calibration', operationId:null})` | 成功 |
| caseStopFailure_repeatedStart（blocked 中の反復 start は自動再試行しない） | blocked 中に `start(recording)` を2回送った直後 | 両方とも `effects=[]`。2回目は同じ target なので `observe` も1回目から不変（`desired` 変化なし） | 1回目: `assert.deepStrictEqual(observe(r.state), {phase:'blocked', owner:'recording', desired:'recording', operationId:null})`。2回目: `assert.deepStrictEqual(observe(r.state), {phase:'blocked', owner:'recording', desired:'recording', operationId:null})` かつ `assert.deepStrictEqual(r.effects, [])` | 成功（2回とも） |
| caseStopFailure_retry（明示 retry のみが失敗段階を再実行） | `retry`直後 | `effects` が `stop` target=recording, id=新規（失敗id ≠ 新id） | `assert.deepStrictEqual(r.effects, [{type:'stop', target:'recording', id:opStop2}])` かつ `assert.notEqual(opStop2, opStop)` | 成功 |
| caseStopFailure（stale: 失敗直後・retry後いずれも古い id は無視） | `ok(opStop)`をblocked中に送った直後／retry後に`ok(opStop)`・`fail(opStop)`を送った直後（計3回） | いずれも `effects=[]`、`observe` が直前の状態から不変 | `assert.deepStrictEqual(r.effects, [])`（各回） | 成功（3回とも） |
| caseReleaseFailure（release 失敗で blocked、retry で回復し新 target へ） | `fail(opRelease)`直後、`retry`直後、`ok(opRelease2)`直後 | `blocked`遷移／`release`再実行（新id）／`acquire(calibration)`発行 | `assert.deepStrictEqual(r.effects, [{type:'release', target:'recording', id:opRelease2}])`、`assert.deepStrictEqual(r.effects, [{type:'acquire', target:'calibration', id:opAcq}])` | 成功 |
| caseReleaseFailure（stale: 完了済み stop-id・失敗id・retry後の旧id・未発行idいずれも無視） | ①`ok_stop`直後、まだ releasing 進行中に完了済みの `opStop` を再送した直後（実運用で最も現実的な stale: 次段階が進行中に前段の遅延完了が届く） ②fail直後の`ok(opRelease)` ③retry後の`fail(opRelease)`（失敗id） ④無関係id`opRelease2+1000`での`ok`（releasing 中） | ①は `observe` が `releasing/owner=recording/desired=calibration/operationId=opRelease` のまま不変、②③④は `effects=[]` | ①`assert.deepStrictEqual(observe(r.state), {phase:'releasing', owner:'recording', desired:'calibration', operationId:opRelease})` ②③④`assert.deepStrictEqual(r.effects, [])`（各回） | 成功（4回とも） |
| caseAcquisitionFailure（acquisition 失敗は idle へ、自動再試行なし） | `fail(opAcq)`直後 | `observe` が `idle/owner=null/desired=null/operationId=null`、`effects=[]` | `assert.deepStrictEqual(observe(r.state), {phase:'idle', owner:null, desired:null, operationId:null})` | 成功 |
| caseAcquireFailAfterSwitch（intent 変更後の acquisition 失敗でも auto-retry なし） | `start(rec)→start(cal)→fail(1)`直後 | `effects=[]`（calibration の自動確保が発行されない） | `assert.deepStrictEqual(r.effects, [], 'no auto-acquire of the now-latest target (calibration)')` | 成功 |
| caseAcquisitionFailure_idUniqueness（id は使い回さない） | 失敗後の再 `start`直後 | 新しい id が失敗id+1 | `assert.equal(r.effects[0].id, opAcq + 1, ...)` | 成功 |
| caseSameOwnerNoOp（active 中の同一 owner start は no-op） | `start(recording)`（既に owner=recording）直後 | `state`が直前と完全一致、`effects=[]` | `assert.deepStrictEqual(out.state, activeState)` | 成功 |
| caseStaleCompletion_neverIssuedId（未発行 id の ok/fail は無視） | 未発行id での `ok`・`fail` 直後（各1回） | `state`が直前と完全一致、`effects=[]` | `assert.deepStrictEqual(r.state, acquiring)` | 成功（2回とも） |
| caseProfileIndependent（profile editor は独立、device 排他に無関係） | idle/acquiring/active/stopping/releasing/blocked の各 phase で `profile` 送信直後 | `state`が直前と完全一致、`effects=[]` | `assert.deepStrictEqual(out.state, st, ...)` | 成功（6 phase とも） |
| caseUnknownEvents（未知イベント／非blocked中のretryは無視） | `{type:'bogus'}`、`retry`（idle中）各直後 | 戻り値全体が `{state:s0, effects:[]}` | `assert.deepStrictEqual(r, {state:s0, effects:[]})` | 成功（2回とも） |
| 全71回のtransition呼び出し（純粋性） | 各呼び出し直後（`step()`内、上記4行のassertion） | 入力`state`の1回目・2回目呼出し後不変、1回目結果が2回目呼出しで変化しない、2回目結果が1回目結果と一致 | 前掲「純粋な遷移の検査」節の4行 | 成功（71回とも。`node check.mjs`のログ全文が各 `[step] ...` 行として出力済み） |

## 検査未実装・未実行の範囲

- **実アプリ統合**: 本モデルは実行境界（Effect Fiber／Scope、既存 Atom binding）と未接続。`effects` を実際に `acquire`/`stop`/`release` へ配線し、`ok`/`fail` を返す経路の検査は**未実行**。
- **`operationId`／`nextId` の重複可否**: 既存の実行境界が既に一意な操作IDや stale completion 除外を提供しているかは**未確認**。提供している場合、本実装ではモデル固有の `operationId`/`nextId` を重ねて持つ必要はない（上表の該当行を参照）。
- **`opTarget` の実装表現**: stop/release/blocked 中は `owner` と同値なため、本実装では独立フィールドとして持たず `owner` を読む設計で足りる可能性が高いが、その簡略化自体は未検証（モデル内では独立フィールドとして実装し、検査もそれに基づく）。
- 表内で「検査未実装」「未実行」と明記していない項目は、上表いずれかの行に対応する実行済みassertionで確認済み。
