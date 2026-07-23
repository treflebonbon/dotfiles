# dotfiles ワークフロー

この repo のドメインは chezmoi 管理下の設計→実装ワークフロー（skill harness）そのもの。プロダクトコードではなく、エージェントが辿る手続きと、手続き間で受け渡す成果物の語彙を定義する。

## Language

**Contract**:
issue/PRD が定める「目的・AC・非目標・検証方法・関連ファイル/入口・判断済みtradeoff」の6項目。`ready-for-agent` 化の入口契約であり、`to-pr` が PR body へ埋め込む出口契約でもある。
_Avoid_: 仕様, spec, 要件定義

**Verification Matrix**:
`to-pr` が PR body に載せる AC ごとの検証記録表（列: AC / 種別 / 実行コマンドまたは理由 / 結果 / 未確認理由）。UI・CLI・API・infra 全ての AC を1つの表に統合する。
_Avoid_: evidence table, 検証エビデンス, verdict

**Design Hook**:
UI コードの編集直後に決定論的なデザイン検査を行い、修正対象となる finding だけをエージェントの作業文脈へ返す advisory 型の自動フィードバック経路。変更を拒否する品質ゲートではなく、人間が画面を見て判断する要素指差しフィードバックや、実装後の Verification Matrix とも異なる。
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
設計協働フェーズ（`grill-with-docs`→`to-spec`→`to-tickets`）の呼称。人間が対話を通じて意思決定する主体であり、確認ポイントは削減しない（[ADR-0019](docs/adr/0019-builder-evaluator-cross-issue-autonomy.md), [ADR-0022](docs/adr/0022-align-mattpocock-v1-1-workflow.md)）。
_Avoid_: 計画フェーズ, 設計フェーズ

**Builder-Evaluator**:
実装検証フェーズ（`implement` を入口に、内部で `tdd`↔`code-review` を使う）の呼称。`to-tickets` が生成した ticket をまたいで自律的にループしてよい自動化された主体（[ADR-0019](docs/adr/0019-builder-evaluator-cross-issue-autonomy.md), [ADR-0022](docs/adr/0022-align-mattpocock-v1-1-workflow.md)）。
_Avoid_: 実装フェーズ, ビルドフェーズ

**親完了条件**:
親 issue の全 direct child ticket が既に close 済み、または同一の最終 PR の close 対象になっている状態。merge 前でも直接の親を安全に close できる見込みが立った状態を指し、未処理 ticket が残る状態と区別する。
_Avoid_: 全 ticket 完了, epic completion

**Ticket Hierarchy**:
親 issue と child ticket の関係。GitHub native subissues を正本とし、ticket 本文の `Parent` は人間向けの写しとして照合に使う。
_Avoid_: Parent link, body hierarchy

**Ticket Coverage**:
child ticket の全 AC が PR の Contract に含まれ、Verification Matrix の行へ対応付けられている状態。行の検証結果は coverage を左右せず、issue 番号の参照だけでも coverage とみなさない。
_Avoid_: issue reference, commit link

**最終 PR**:
対象 worktree/branch の実装をまとめて公開し、merge まで親 issue の Ticket Hierarchy を凍結する PR。作成後に見つかった追加 scope は同じ親へ child ticket を足さず、別の親 issue として扱う。
_Avoid_: last PR, final patch

**Parent Reconciliation**:
最終 PR が直接の child ticket と親 issue の close 対象を整合させる1階層の完了判定。Ticket Hierarchy または Ticket Coverage を証明できない場合は親の close を省いて理由を記録し、PR 作成自体は止めない。
_Avoid_: epic reconciliation, post-merge cleanup

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
