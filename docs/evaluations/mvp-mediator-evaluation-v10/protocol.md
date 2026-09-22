# MVP Mediator 評価契約 v10

状態: 実装用契約。実LLM評価は実装完了後の明示的なempirical-prompt-tuning依頼で開始する。

[v9契約](../mvp-mediator-evaluation-v9/protocol.md)とv2〜v8を継承し、以下のE課題・親checkerに関する差分だけを優先する。[確定設計](../mvp-mediator-checker/design.md)のQ1〜Q3を根拠とする。

## 評価条件と比較の制限

スキル本文はv9のSHA-256 `6ef323f5126cdf0373baef52c3f0aedc0f1d7f55305138eb3072b5eeb6fa4fc6`、条件付き参照は `110b25b8ba320ac61ceb38c19142f5028aabfcc28a27cfd6b7a51b0eef288cca` を維持する。B/S/L課題、各6基準・critical指定・C1〜C4、共通配布テンプレート、runtime隔離、model/effort、直列監査、E/B/S各3組、再発停止・上限・L条件、canonical metadata規則も維持する。

E課題の配布元は本書のE節、固定checkerは同ディレクトリの `check-device.mjs` とする。公開CLIは新旧契約・新旧checkerのhashを固定し、親のE検査には新版checkerのhashを要求する。旧契約・checker・run・入力・成果物・採点は変更しない。旧runのstatus参照を保ち、新版での書込み再開・再採点は認めない。

この変更は評価用APIの状態表現を制限し、純粋性検査を追加する。旧版との単純な改善率比較やスキル自体の改善としては扱わない。形式遵守と内容精度の区別、正確な要約・重複の許容、事前整理は推奨というv9の条件も維持する。

## 親の検査記録

旧52機能ケースと `--known-bug` negative controlを維持する。初期状態と返却状態の形式を確認し、各呼出し後の全入力stateの不変性と同入力の2結果の一致を検査する。初回結果は再呼出し前に複製する。effectsの実行はせず、機能ケースの履歴には初回結果だけを採用する。

checkerのJSONは `status`、`passed`、`executed`（開始したケース数）、`notRun`、`total=52`、ケース別 `failures`、必要なら `error` を報告する。`passed` とfailuresが完了結果であり、準備失敗で開始していないケースを失敗へ算入しない。

- `pass`: 全52ケースが成功。exit0。
- `fail`: 実行したケースで非破壊・決定性・機能検査が不合格、またはモデル呼出しが例外。exit1。
- `contract-error`: モデルの状態形式・APIが契約外。具体的な箇所を示して後続を止める。初期状態で拒否された場合はexecuted0／notRun52／failures空。exit1。
- `model-error`: ケース開始前のモデル初期化が例外。機能検査未実行。exit1。
- `checker-error`: ファイルを読み込めないなど、checkerが検査を成立させられない。機能検査の結果とは分離し、理由を記録。exit1。JSON自体が出ないプロセス障害も親が検査未成立と記録する。

モデルの契約違反を配布入力invalidへ付け替えず、replacementの理由にしない。検査未成立を52件の機能不良としない。採点は従来の6項目・C1〜C4へ根拠別に行い、新しい一律減点は設けない。親の追加検査を実行者の自己検査実績へ加えない。状態外の隠れた判断状態はコード監査でも確認し、有限検査の成功だけで完全な純粋性を証明したとしない。

## 実装検証

公開checker入口で、通常／freeze状態の52件成功、非公開投影部分の入力破壊、同入力の非決定性、返却object再利用、許容外形式の分類、準備失敗の未実行数、negative controlを確認する。公開CLI fixtureで新版E配布・source固定・新版checker要求・旧run書込み拒否を確認する。これらは実LLMの行動改善の証拠ではない。

## E — exclusive device (executable)

A React/Effect app has recording and calibration that cannot own a device concurrently; a profile editor is independent. The parent owns exclusion; child flows own local UI. Product policy: latest start request wins during acquisition, stop and release, including returning to an earlier requested target. In-flight work continues with its identity unchanged. After acquisition, keep that owner if it matches latest intent, otherwise stop then release before acquiring the latest target. Stop/release failure blocks new acquisition until explicit retry of the failed stage. Repeated starts in blocked state update intent but do not retry automatically. Acquisition failure returns idle without auto-retrying. Same-owner start in active state is a no-op. Stale completions are ignored.

Deliver a minimal executable **abstract decision model**, plus a short responsibility/verification memo. This is not a replacement Effect runtime: output commands for the existing execution boundary; do not perform I/O. Use only JavaScript and Node built-ins. Export:

- `initial()` -> fresh explicit-data state (representation contract below).
- `transition(state, event)` -> `{ state, effects }`, without mutating input.
- `observe(state)` -> `{ phase, owner, desired, operationId }`. Phases: `idle`, `acquiring`, `active`, `stopping`, `releasing`, `blocked`. owner/desired are `recording`, `calibration` or null; operationId is the pending execution ID or null. IDs must not be reused within a run.
- Events: `{type:'start', target}`, `{type:'ok', id}`, `{type:'fail', id}`, `{type:'retry'}`, `{type:'profile'}`. Completion applies to the current stage. Unknown/stale events leave state/effects unchanged.
- Effects: `{type:'acquire'|'stop'|'release', target, id}`. Acquisition owns nothing until successful; stopping/releasing/blocked reserve the old owner until successful release. State field names and organization are your choice within the representation contract below.

State representation and purity contract (evaluation model only):

All decision state must be contained in state; do not hide mutable decision state in a WeakMap, closure or module-global variable. State is acyclic data composed only of ordinary objects (`Object.prototype`), ordinary dense arrays, null, booleans, strings and finite numbers. Object properties are own enumerable string-keyed data properties. Arrays have no holes, accessors or extra properties. Frozen data is allowed. Functions, undefined, symbols, bigint, getters/setters, custom classes/prototypes, null-prototype objects, Map/Set and other non-data values are outside this contract. This restriction does not prescribe production application state representation or internal field names.

For every checked transition, preserve the entire input state and return structurally equal state/effects for the same state/event. Compare input snapshots after both calls. Snapshot the first result before the second call so reusing and overwriting a result object cannot hide nondeterminism. The parent checks state representation and full-state purity; it still checks functional expectations through observe/effects, and audits the code for hidden decision state. These finite checks do not prove purity for every possible execution. No additional inspect API is required.

1. [critical] Executable transitions implement latest intent consistently in every waiting phase, including target changes back to the in-flight target, without duplicate I/O.
2. [critical] Stop and release success are required before the next acquire; failure blocks acquisition and explicit retry repeats only the failed stage.
3. Execution IDs survive intent changes, are fresh for new stages/retries, and stale success/failure cannot advance state.
4. Common UI parent owns policy; Effect owns execution, typed errors/defects/interruption/lifetime. The pure model only emits commands and does not invent a scheduler or runtime.
5. Child local flows and the profile editor remain independent; profile events leave device state/effects unchanged.
6. Model, memo and concrete checks agree; run at least one meaningful assertion-based check and report its actual result, separating executed checks from proposed checks.
