# dotfiles ワークフロー

この repo のドメインは chezmoi 管理下の設計→実装ワークフロー（skill harness）そのもの。プロダクトコードではなく、エージェントが辿る手続きと、手続き間で受け渡す成果物の語彙を定義する。

## Language

**導入済み AI ツールセット**:
ユーザー環境が共通の immutable upstream revision から公開する AI 関連 CLI の集合。upstream の全ツール一覧ではなく、実際に環境へ組み込まれたものだけを指す。
_Avoid_: llm-agents ツール, 全 AI ツール, upstream catalog

**導入済み Agent Skill セット**:
ユーザー環境が外部 package から取得・公開する Agent Skill の集合。dotfiles が所有するローカル skill は含まない。
_Avoid_: スキル, 全 skill, ローカル skill

**検証済み Skill Pin**:
自動 hook やワークフロー契約との互換性を確認した Agent Skill の immutable revision。floating dependency の定期更新とは分け、契約を再検証したときだけ前進させる。
_Avoid_: 最新版, lock revision, floating pin

**Design Hook 互換性ゲート**:
Impeccable の更新候補が、Claude Code / Codex の quiet・fail-soft・per-edit / deep-pass 契約を維持できるかを判定する更新境界。契約変更へ追従できない候補は採用せず、最新の互換 revision に戻す。
_Avoid_: hook test, latest pin, smoke check

**品質 floor**:
導入済み AI ツールについて、運用上不可欠な挙動を保証する最低 release。snapshot の実際の version とは独立し、具体的な品質根拠がある場合だけ引き上げる。
_Avoid_: 最新版, pin version, minimum version

**更新単位**:
同じ互換性ゲート、検証結果、配備境界、rollback 境界を共有して一緒に採用する導入済み AI ツールセットまたは Agent Skill セットの変更群。payload や workflow 契約が大きく異なる変更は、同じ upstream 更新でも別の更新単位に分ける。
_Avoid_: 一括更新, 全部入り update, upstream の更新

**Managed Playwright Chrome**:
WSL2 上の Playwright 操作専用に管理され、通常利用の Chrome と完全に分離された Windows 側の browser identity。専用 profile の手動認証状態を、排他的な CLI session と Dashboard が再利用する。
_Avoid_: Windows Chrome, Playwright 専用 Chrome, WSL Chrome

**Managed Chrome モード**:
Managed Playwright Chrome の同一 identity が、排他的に取る headless または headed の実行形態。別の browser identity や別 profile を意味しない。
_Avoid_: headless Chrome, headed Chrome, 別ブラウザー

**Managed Playwright Dashboard**:
Managed Playwright Chrome の headed モードを表示面として使う、CLI session とは独立した Playwright の操作画面。annotation は排他 lease を所有する session にだけ結び付く。
_Avoid_: Dashboard tab, show 画面, headless Dashboard

**Managed Dogfood Chrome**:
WSL2 上の dogfood evidence 収集専用に管理され、隔離 profile と CDP endpoint、任意の unpacked extension を所有する Windows 側の browser identity。通常利用の既定ブラウザおよび Managed Playwright Chrome とは状態を共有しない。
_Avoid_: Dogfood browser, extension Chrome, Managed Playwright Chrome

**WSL2 browser boundary**:
WSL2 が browser identity を所有せず、人間向け URL 表示は Windows の通常の既定ブラウザ、自動操作は用途別の Managed Playwright Chrome または Managed Dogfood Chrome へ分離して委譲する環境境界。
_Avoid_: WSL Chrome, WSL browser, Windows Chrome only

**Contract**:
issue/PRD が定める「目的・AC・非目標・検証方法・関連ファイル/入口・判断済みtradeoff」の6項目。`ready-for-agent` 化の入口契約であり、`to-pr` が PR body へ埋め込む出口契約でもある。
_Avoid_: 仕様, spec, 要件定義

**Verification Matrix**:
`to-pr` が PR body に載せる AC ごとの検証記録表（列: AC / 種別 / 実行コマンドまたは理由 / 結果 / 未確認理由）。UI・CLI・API・infra 全ての AC を1つの表に統合する。
_Avoid_: evidence table, 検証エビデンス, verdict

**Environment Contract File**:
Repository に追跡され、workspace が必要とする環境変数名と導出規則を秘密値なしで共有するファイル。実値を保持する credential や secret file とは区別する。
_Avoid_: env file, dotenv, secret file

**Worktree Owner**:
task の worktree を作成・選択し、workflow の全 phase を同じ checkout に留める責務を持つ実行環境。Orca session、Codex native worktree、Claude Code では各 runtime がこの責務を持ち、raw CLI では host 側の起動境界が担う。
_Avoid_: worktree launcher, worktree tool, checkout owner

**Worktree Entry Point**:
workflow を validated task worktree から始めるための共通の入口契約。Orca では native worktree の作成・選択と built-in agent の起動がこの契約を満たし、非 Orca runtime では `/to-worktree` が Worktree Owner へ処理を振り分ける。
_Avoid_: Orca worktree command, worktree creator, runtime-specific entry

**Worktree Activation**:
作成済みの task worktree を agent session の working root と runtime-owned permission mode に結びつける phase boundary。worktree の作成や shell 内だけの `cd` とは区別する。
_Avoid_: worktree creation, directory change, session resume

**Active Git Metadata Boundary**:
現在の task worktree から解決した worktree 固有 Git dir と Git common dir だけを、その session の書込み対象へ加える権限範囲。別 repository の Git metadata や静的な repository 例外は含めない。
_Avoid_: `.git` write access, repository-wide permission, global Git exception

**Technical Sandbox Boundary**:
Git の checkout 隔離とは独立して、agent の filesystem・network access を runtime が強制する権限境界。full-autonomy permission mode では存在せず、worktree isolation 自体もこの境界には含めない。
_Avoid_: worktree sandbox, repository isolation, permission mode

**Runtime Adapter**:
raw agent runtime の実行 context を公式 permission・working-root interface へ変換する狭い接続層。Active Git Metadata Boundary を解決できない場合は権限を広げず停止し、workflow policy や Git 操作そのものは所有しない。Worktree Owner が直接提供する built-in agent integration とは区別する。
_Avoid_: custom launcher, wrapper, glue

**Design Hook**:
UI コードに対して決定論的なデザイン検査を行い、修正対象となる finding だけをエージェントの作業文脈へ返す advisory 型の自動フィードバック経路。二層で走る — 編集直後（per-edit）はその場で直すべき機械的な層だけ、残りはセッション終端の deep pass でまとめて返す。変更を拒否する品質ゲートではなく、人間が画面を見て判断する要素指差しフィードバックや、実装後の Verification Matrix とも異なる。
_Avoid_: visual lint, UI review, 見た目確認

**要素指差しフィードバック**:
`tdd` の実装サイクル中、人間が画面上の UI 要素を選択し、その場でエージェントへ変更を指示する対話チャネル（Codex app（in-app browser）: Annotation Mode / Orca IDE: Design Mode / Claude Code: `claude-in-chrome`）。実装完了後にエージェントが自律的に検証する Verification Matrix とは主体（人間 vs エージェント）とタイミング（実装中 vs 実装後）の両方が異なる。
_Avoid_: UI verification, ブラウザ検証

**履歴検索の所有者**:
対話シェルで `Ctrl-R` の履歴検索を担当するツール。所有者はシェル実装ごとに決め、bash では line editor が持つ場合も、zsh では atuin が持つ場合もある。
_Avoid_: history backend, Ctrl-R integration

**主要機能セット**:
bash と zsh の両方で揃える対話シェル体験の最小集合。完全同一の実装や同一の履歴検索所有者ではなく、starship、fzf、zoxide、syntax highlight、autosuggestion、履歴検索の体験が大きく乖離しないことを重視する。
_Avoid_: parity, 同一実装

**Planner**:
設計協働フェーズ（`grill-with-docs`→`to-spec`→`to-tickets`）の呼称。`grilling` の frontier round で依存関係が解決済みの質問をまとめて提示し、人間の回答を待って次の frontier を開く主体であり、確認ポイントは削減しない（[ADR-0019](docs/adr/0019-builder-evaluator-cross-issue-autonomy.md), [ADR-0022](docs/adr/0022-align-mattpocock-v1-1-workflow.md), [ADR-0041](docs/adr/0041-adopt-mattpocock-v1-2-3-workflow-semantics.md)）。
_Avoid_: 計画フェーズ, 設計フェーズ

**Builder-Evaluator**:
実装検証フェーズ（`implement` を入口に、内部で `tdd`↔`code-review` を使う）の呼称。`to-tickets` が生成した ticket を同一 worktree/branch でまたいで自律的にループしてよい自動化された主体。関連 context が同じ harness / directory に残るなら phase boundary で `/compact` を優先し、別 harness / directory への portability が必要な場合だけ `/handoff` を使う（[ADR-0019](docs/adr/0019-builder-evaluator-cross-issue-autonomy.md), [ADR-0022](docs/adr/0022-align-mattpocock-v1-1-workflow.md), [ADR-0041](docs/adr/0041-adopt-mattpocock-v1-2-3-workflow-semantics.md)）。
_Avoid_: 実装フェーズ, ビルドフェーズ

**Phase Boundary**:
phase 間だけで選ぶ公式5択。`Continue → /clear → /handoff → Subagent → /compact` の順に、同じ phase の途中では判断しない。`Continue` を最初に検討し、同じ harness / directory の relevant context は `/compact`、portability が必要な場合だけ `/handoff` とする。
_Avoid_: phase 中の compact, handoff の常用

**Prototype Primary Source**:
設計上の state model を検証する single self-contained HTML。build / server 不要で、検証した decision を本実装へ反映した後も、prototype 全体は throwaway branch に primary source として残し、implementation issue から参照する。main branch には決定だけを残す。
_Avoid_: prototype の本番化, モックを仕様の正本にすること

**親完了条件**:
親 issue の全 direct child ticket が既に close 済み、または同一の最終 PR の close 対象になっている状態。merge 前でも直接の親を安全に close できる見込みが立った状態を指し、未処理 ticket が残る状態と区別する。
_Avoid_: 全 ticket 完了, epic completion

**Ticket Hierarchy**:
親 issue と child ticket の関係。GitHub native subissues を正本とし、ticket 本文の `Parent` は人間向けの写しとして照合に使う。
_Avoid_: Parent link, body hierarchy

**Hierarchy Repair**:
本文で単一の親を宣言した direct child 群を検証し、欠けている native subissue 関係を Parent Reconciliation より前に復元する安全側の整合処理。
_Avoid_: hierarchy migration, automatic reparenting

**Ticket Coverage**:
child ticket の全 AC が PR の Contract に含まれ、Verification Matrix の行へ対応付けられている状態。行の検証結果は coverage を左右せず、issue 番号の参照だけでも coverage とみなさない。
_Avoid_: issue reference, commit link

**最終 PR**:
対象 worktree/branch の実装をまとめて公開し、merge まで親 issue の Ticket Hierarchy を凍結する PR。作成後に見つかった追加 scope は同じ親へ child ticket を足さず、別の親 issue として扱う。
_Avoid_: last PR, final patch

**Parent Reconciliation**:
最終 PR が直接の child ticket と親 issue の close 対象を整合させる1階層の完了判定。Ticket Hierarchy または Ticket Coverage を証明できない場合は親の close を省いて理由を記録し、PR 作成自体は止めない。
_Avoid_: epic reconciliation, post-merge cleanup

**Review Round**:
選択した unresolved review thread 群を、修正または説明の確認から、検証・1 commit・topic push・日本語返信・resolve まで一括処理する単位。説明のみなら空 commit を作らず、thread 単位の失敗は残りの処理を止めない。
_Avoid_: コメント対応, review fix

**ローカル skill 上書き**:
外部 skill を fork せず、その repo の指示層で実運用に必要な差分だけを優先規則として定義すること。外部 skill 本文の一般手順は維持し、上書き範囲を明示できる場合に限る。
_Avoid_: skill fork, upstream patch, vendored skill 改変

**Scope Matching**:
skill 逸脱を判定する前に、制約の主語・対象層・関数種別・実行文脈が観測対象と一致することを確認する工程。一致しない制約は finding の根拠に使わない。
_Avoid_: keyword matching, 部分一致判定

**Critical Deviation**:
承認・安全境界の回避、必須検証やレビューの欠落、虚偽の完了主張、または成果物の正しさを損なう実行逸脱。無害な順序差や追加検証は含まない。
_Avoid_: completed violation, 文面上の不一致

**実効契約**:
system/developer 指示、runtime に対応する project 指示（`AGENTS.md` または `CLAUDE.md`）、呼び出された skill を優先順位どおりに解決した、その実行でエージェントが従うべき契約。下位文書との不一致だけでは実行逸脱としない。
_Avoid_: skill contract, 単一指示ファイル

**Project-scoped Auto Selection**:
`harness-feedback` の Auto mode が、現在の project に一致する過去 transcript だけを分析対象にする選択規則。一致する過去 transcript がなければ、別 project へフォールバックせず正常終了する。
_Avoid_: runtime fallback, newest transcript

**Contract Warning**:
下位 skill の規則が上位指示で置き換えられ、実行逸脱から除外されたことを示す `harness-feedback` の非 finding 通知。finding 件数や severity には影響しない。
_Avoid_: deviation, minor finding
