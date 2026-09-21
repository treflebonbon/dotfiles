# 推奨構成の適用評価

Baseline: `35c0a4af965027d4df7476b2e808388419516f76`。ユーザーはEffectを優先する推奨構成への変更と実証評価を依頼し、合わない要素は無理に取り入れない方針を明示した。過去の検証例追加とは別の設計変更として評価する。旧E/B/Sの基準・採点・成果物は変更しない。

変更テーマは「既存の実装基盤を優先し、必要な責務だけを追加する」。ドメイン／ユースケース、Effect実行、Atom接続、UI裁定を分け、各パターンを必須のクラス・層・ストアとして追加しない。既知ledgerの状態分類問題は、判断に必要な情報と検証補助の意味を区別する手順へ整理する。

以下の設計課題3種類を、1課題1新規executor（gpt-5.6-terra/high、履歴forkなし）で3組実行する。対象skillと条件付きreference、指定した課題・基準だけを渡す。過去評価、他executorの出力、親のcheckerを読ませない。各組は同じ候補を使い、失敗時はその根拠に対応する一テーマを修正して新規executorで再評価する。

各基準はfull=1、partial=0.5、absent=0。binary○はcriticalがすべてfullの場合だけ。親は成果物全文を読み自己申告とは別に採点する。新規の指示不明点・適用漏れがなく全基準fullの組をqualitative clearとし、3連続後に未使用holdoutを実行する。tool_uses/duration_msはruntime提供値だけを使い、欠ければstrict convergenceと呼ばない。数値が取得不能でも実行評価を続け、達成時はqualitative plateau; quantitative convergence unverifiedと報告する。

## A — Effect / Atom の新規構成

React / Effect / @effect/atom-reactで注文画面を設計する。ドメインモデリング、ヘキサゴナル、ROP、DAG、Passive View、CoR、Mediatorの採用を検討しているが、合わないものは不要。注文取消は発送後に不可であり、画面表示後に発送されることがある。操作は失敗後に再試行できる。複数Viewが同じ状態を購読する。別の画面フロー間には終了待ちを伴う共有資源の排他がある。採用条件と責務・依存方向・状態の所有者・具体的な検証案を短い日本語メモにまとめる。これは設計課題であり、実アプリ、抽象実行モデル、フレームワークAPIコードの作成は不要。

1. [critical] 業務上の取消可否と実行時検証をModel／ユースケースに置き、React・Atom依存やUI内での業務規則の再実装を避ける。
2. [critical] Effectの型付きエラー・依存供給・実行/寿命を利用し、Mediator独自のruntime/schedulerや同じpending/resultの複製を提案しない。
3. MediatorをUI判断の役割として説明し、既存機構で足りる場合は専用class/store/reducer不要。排他・終了待ちなど追加制約は必要な共通親が担当する。
4. DAGを依存関係に適用し、失敗→再試行など時間上の循環を許す。CoRは必要な担当外要求の委譲であり、業務処理/エラーの合成はEffectで行う。
5. 厳密なPassive Viewと購読・局所状態を許す緩和を区別し、複数購読を許容する。厳密さが必要な場合の接続部分と表示部分の境界を示す。
6. ROPをEffectの成功・型付き失敗の合成へ適用し、常時の二重Result化やdefect/中断の業務エラー化を避ける。
7. 実行時の発送競合、再試行の古い応答、排他の解放待ちを具体的な検証案に含め、未実行を明記する。中断がサーバー処理の巻戻しを保証するとは主張しない。

## F — 既存Atomだけで足りるフォーム

既存React / Effect / @effect/atom-reactフォームの送信中表示と独立したhelp tooltipを整える。既存bindingがpending/result/errorと操作識別を所有し、今回必要な二重送信抑止・古い結果の除外はすでに保証され、テスト済みとする。フォームは入力値と形式チェックを所有し、業務検証はユースケースにある。複数Context consumerが表示を読む。新しい排他・取消方針はない。最小変更案と具体的な確認項目を日本語メモにする。実アプリ・実行モデル・APIコードは不要。

1. [critical] 既存bindingからpending/result/errorを導出し、二重のisSubmitting/reducer/storeや独自runtimeを追加しない。
2. [critical] 新しいMediator class/CoRチェーン/Root再編/操作ID/状態機械を形式的に追加せず、既存の所有者を維持する。
3. tooltipの開閉を局所に保ち、複数Context consumerと既存フォームの入力・形式チェックを維持する。
4. 業務検証をユースケースに残し、表示条件のために再実装しない。Atom採用だけを保証とせず、課題に与えたbindingの確認済み保証を根拠にする。
5. 投稿中表示、完了/失敗表示、tooltip独立性の確認項目を示し、未実行アプリ検査を成功扱いしない。
6. 追加不要なパターンの理由を今回の制約に結び付け、strict Passive Viewのための一律の購読移動や中継専用層を要求しない。

## B — Effect未導入の表示変更

既存React/TanStack Query画面。compound Contextを複数consumerが読み、Effectは未導入。合計値を既存formatterで整形し、送信など他操作に影響しないhelp tooltipを追加する。プロジェクト規約は既存構成の維持を求める。最小の変更提案・確認メモのみを作る。アプリコード・実行モデルは不要。

1. [critical] Queryと既存設計を保ち、Effect/Atom導入やMVP移行を要求しない。
2. [critical] 表示と局所tooltipに限定し、Mediator/reducer/global state/実行モデルを追加しない。
3. 複数Context consumerを保ち、単一connectorや中継専用層を強制しない。
4. 既存formatterと局所tooltipを再利用する。
5. 無関係の業務規則・送信制御の所有者を変えない。
6. 整形とtooltipに釣り合う具体的な確認を示し、未実行アプリ検査の成功を主張しない。

## 未使用holdoutと回帰

3組clear後に、旧実験の[evidence.mdに固定済みのHoldout O](../mvp-mediator-executable/evidence.md)を初めて実行する。6基準と課題は変更しない。同時に旧[Scenario E](../mvp-mediator-executable/protocol.md)を新規executorで実行し、変更しない52ケースcheckerで回帰確認する。両者は抽象実行モデルの評価であり、上記の設計メモ課題とは別集計とする。完成していない中間ファイルは採点せず、親が評価fixtureを修正して点数を救済しない。
