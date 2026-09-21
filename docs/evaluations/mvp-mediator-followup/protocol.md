# 検証記録の適用再評価（dispatch前固定）

Baseline e7b3d5a。対象はlocal-skills/mvp-mediator-architecture。E/O/Fの課題・基準は前回定義をそのまま使い、前回の採点を変更しない。full=1、partial=.5、absent=0、critical全fullのみbinary○。通常経路の独立実行、状態の用途・所有者・本実装での取得元、説明と実装の整合は、対象skillの適用確認として別に記録する。全基準fullかつ適用漏れ・新たな不明点0の組をclearとし、高重要度のため3連続後に未使用Lを実行する。Eは既存52ケースcheckerを変更せず使用する。

毎回gpt-5.6-terra/highの新規executor、forkなし、担当節だけを渡し、過去成果物と親checkerを非公開にする。完成後のみ採点する。自己報告TraceはUnderstanding/Planning/Execution/Formattingを展開して指定する。tool_uses/duration_msはcanonical metadataがなければ取得不能とし、strict convergenceに数えない。qualitative plateau; quantitative convergence unverifiedまたは根拠付きresource cutoffで判定する。親は評価出力の意味を修正して救済しない。

## E — exclusive device (executable)

A React/Effect app has recording and calibration that cannot own a device concurrently; a profile editor is independent. The parent owns exclusion; child flows own local UI. Product policy: latest start request wins during acquisition, stop and release, including returning to an earlier requested target. In-flight work continues with its identity unchanged. After acquisition, keep that owner if it matches latest intent, otherwise stop then release before acquiring the latest target. Stop/release failure blocks new acquisition until explicit retry of the failed stage. Repeated starts in blocked state update intent but do not retry automatically. Acquisition failure returns idle without auto-retrying. Same-owner start in active state is a no-op. Stale completions are ignored.

Deliver a minimal executable **abstract decision model**, plus a short responsibility/verification memo. This is not a replacement Effect runtime: output commands for the existing execution boundary; do not perform I/O. Use only JavaScript and Node built-ins. Export:

- `initial()` -> fresh opaque state.
- `transition(state, event)` -> `{ state, effects }`, without mutating input.
- `observe(state)` -> `{ phase, owner, desired, operationId }`. Phases: `idle`, `acquiring`, `active`, `stopping`, `releasing`, `blocked`. owner/desired are `recording`, `calibration` or null; operationId is the pending execution ID or null. IDs must not be reused within a run.
- Events: `{type:'start', target}`, `{type:'ok', id}`, `{type:'fail', id}`, `{type:'retry'}`, `{type:'profile'}`. Completion applies to the current stage. Unknown/stale events leave state/effects unchanged.
- Effects: `{type:'acquire'|'stop'|'release', target, id}`. Acquisition owns nothing until successful; stopping/releasing/blocked reserve the old owner until successful release. State internals are your choice.

1. [critical] Executable transitions implement latest intent consistently in every waiting phase, including target changes back to the in-flight target, without duplicate I/O.
2. [critical] Stop and release success are required before the next acquire; failure blocks acquisition and explicit retry repeats only the failed stage.
3. Execution IDs survive intent changes, are fresh for new stages/retries, and stale success/failure cannot advance state.
4. Common UI parent owns policy; Effect owns execution, typed errors/defects/interruption/lifetime. The pure model only emits commands and does not invent a scheduler or runtime.
5. Child local flows and the profile editor remain independent; profile events leave device state/effects unchanged.
6. Model, memo and concrete checks agree; run at least one meaningful assertion-based check and report its actual result, separating executed checks from proposed checks.

## O — 実行時の業務判定（dispatch前固定）

既存React/Effect注文画面でキャンセル操作を扱う。画面が購読する注文のcached statusと、ユースケースが実行時に取得する最新statusは別で、画面がcancelableを表示した後でも発送され得る。発送済み注文はユースケースが実行時に拒否し、typed business errorを返す。Mediatorはその判定を再実装せず、pending中の二重送信を拒否し、完了後の新しい試行を区別する。古い試行の成功・失敗は現在の試行を完了させない。通常のpending/resultは既存bindingから共用し、独立したtooltipは局所状態。純粋Node抽象モデル（API自由）と実行したassertion・責務メモを作る。実Effect runtimeの実装は不要。

1. [critical] cached statusが未発送でも実行時statusが発送済みならユースケースが拒否するassertionがあり、Mediator/Viewに業務規則を重複しない。
2. [critical] pending中の重複送信を抑止し、同じ注文の別試行を識別して旧成功・旧失敗が現試行を完了させないことをassertionで示す。
3. pending/resultを既存bindingで共用し、ユースケース・bindingの模擬と追加裁定・検証専用状態を分類する。
4. Effectの実行境界とtyped business errorの役割を示し、defect/中断を業務拒否と混同せず、自作runtimeや強制的な新規依存を追加しない。
5. 通常のキャンセル成功と発送競合の拒否、反復要求を別に検査し、memoと実行したケース・結果を一致させ、未実行の実アプリ統合を明記する。
6. tooltipと表示整形は局所、同じ操作判断の所有者は一つとし、注文一覧の取得や他フローを一つのglobal FSMへ集約しない。

## F — 既存Atomだけで足りるフォーム

既存React / Effect / @effect/atom-reactフォームの送信中表示と独立したhelp tooltipを整える。既存bindingがpending/result/errorと操作識別を所有し、今回必要な二重送信抑止・古い結果の除外はすでに保証され、テスト済みとする。フォームは入力値と形式チェックを所有し、業務検証はユースケースにある。複数Context consumerが表示を読む。新しい排他・取消方針はない。最小変更案と具体的な確認項目を日本語メモにする。実アプリ・実行モデル・APIコードは不要。

1. [critical] 既存bindingからpending/result/errorを導出し、二重のisSubmitting/reducer/storeや独自runtimeを追加しない。
2. [critical] 新しいMediator class/CoRチェーン/Root再編/操作ID/状態機械を形式的に追加せず、既存の所有者を維持する。
3. tooltipの開閉を局所に保ち、複数Context consumerと既存フォームの入力・形式チェックを維持する。
4. 業務検証をユースケースに残し、表示条件のために再実装しない。Atom採用だけを保証とせず、課題に与えたbindingの確認済み保証を根拠にする。
5. 投稿中表示、完了/失敗表示、tooltip独立性の確認項目を示し、未実行アプリ検査を成功扱いしない。
6. 追加不要なパターンの理由を今回の制約に結び付け、strict Passive Viewのための一律の購読移動や中継専用層を要求しない。

## L — 文書の自動保存（未使用holdout）

React/Effect/Atomの文書編集。UIは最新の編集内容を表示し、既存bindingが各保存試行のpending/result/operation IDを所有する。同じ文書への保存中に新しい編集が来た場合は最新版だけを待機させる。現試行の成功・失敗を受けてから、新しい待機版がある場合だけ次の保存を開始する。同じ版の失敗を自動再試行せず明示retryで再開する。過去の完了は現試行を完了させない。古い版の成功を、最新編集が保存済みである表示に使わない。別文書・tooltipは独立。純粋Nodeの抽象モデル（API自由）とassertion、責務/検証メモを作り、実Effect runtimeやタイマーは実装しない。

1. [critical] 保存中の複数編集を最新版へ集約し、現試行が終わる前に次の保存を出さない。完了後は最新版だけを開始するassertionがある。
2. [critical] 同じ文書の各試行を区別し、旧成功・旧失敗が現試行を完了させず、旧版の成功だけで最新編集を保存済みにしないことをassertionで示す。
3. 新版がない失敗は自動再試行せず明示retryのみで新IDの試行を開始し、新版がある失敗後は待機した新版を開始する。
4. pending/result/操作IDは既存bindingの模擬として共用し、最新版待機や表示採用の裁定、検証補助との用途・所有者・本実装での取得元を説明する。独自runtimeを作らない。
5. 割込みなしの通常保存成功、現在失敗とretry、編集中の集約、遅延結果を別にassertion実行し、メモが実装と実測に一致する。実アプリ統合は未実行と明記する。
6. UI裁定とEffectによる実行・型付きエラー/defect/中断・寿命を分け、tooltipと別文書を一つのglobal FSMに集約しない。
