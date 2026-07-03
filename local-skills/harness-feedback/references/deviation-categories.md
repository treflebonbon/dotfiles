# Deviation Categories

逸脱分析で使用する finding_type と execution_state の定義。

## finding_type（逸脱カテゴリ）

| finding_type     | 定義                                                     | 判定基準                                                           | 具体例                                            |
| ---------------- | -------------------------------------------------------- | ------------------------------------------------------------------ | ------------------------------------------------- |
| ステップスキップ | SKILL.md に定義されたステップを実行しなかった            | Step N に対応する tool_use が transcript に存在しない              | Step 3 の human gate を飛ばした                   |
| 順序違反         | SKILL.md のステップ順序と異なる順で実行した              | Step N+1 の tool_use が Step N より前に出現                        | Step 2 のレビューを Step 1 の実装より先に実行     |
| 指示無視         | SKILL.md の禁止事項・必須事項に違反した                  | 禁止キーワード（「してはならない」「禁止」等）に該当する動作を実行 | 「git push --force 禁止」なのに force push した   |
| ツール逸脱       | allowed-tools 外のツールを使用、または非効率なツール選択 | frontmatter の allowed-tools リストと実際の tool_use を比較        | allowed-tools に Bash がないのに Bash を使用      |
| 出力形式違反     | 指定されたフォーマットと異なる出力を生成した             | Output Format セクションの仕様と実際の出力を比較                   | Markdown テーブル指定なのにプレーンテキストで出力 |
| 過剰動作         | スキルのスコープ外の作業を実施した                       | SKILL.md に記載のない tool_use が存在                              | レビュースキルなのにコードを修正した              |

## execution_state（実行状態）

finding_type と直交する軸。逸脱が発生した時点の実行状態を示す。

| execution_state | 定義                                             | 判定基準                                                     |
| --------------- | ------------------------------------------------ | ------------------------------------------------------------ |
| completed       | 正常に実行された上での逸脱                       | tool_use に対応する tool_result が成功ステータスで存在       |
| blocked         | 環境制約（ファイル不在、ネットワーク等）で未実行 | tool_result にエラー（file not found, timeout 等）が含まれる |
| denied          | 権限拒否（ユーザーがツール実行を拒否）で未実行   | tool_result に permission denied / user denied が含まれる    |
| unknown         | 判定不能（transcript の情報不足）                | 上記いずれにも該当しない、または tool_result が欠落          |

## Severity ルール

Severity は **critical** と **minor** の 2 段階。

- **critical**: 機能的な問題を引き起こす逸脱（completed 状態でのステップスキップ、指示無視等）
- **minor**: 軽微な逸脱、または環境要因による逸脱

### blocked の細分類

blocked 状態は原因に応じて以下の 2 種類に分類し、Evidence に記録する:

- **environment-error**: ファイル不在、ネットワークタイムアウト、外部サービス障害など、スキル定義に起因しない環境要因
- **implementation-error**: スキル定義のパス誤り、コマンド構文エラーなど、スキル定義の修正で解決可能な問題

まず blocked を分類し、environment-error は finding 対象外として除外する。implementation-error のみ finding として記録する。

### 自動降格ルール

execution_state が **denied** の場合、または **blocked** かつ **implementation-error** として記録された finding の場合、finding_type に関わらず severity を自動的に **minor** に降格する。environment-error は除外済みのため降格対象にしない。

**例外**: blocked / denied で未実行となった動作について transcript が虚偽の完了主張（false completion claim）をしている場合は、この降格を適用せず **critical** とする（SKILL.md の severity ルールが優先）。

## False Positive 防止ルール

逸脱分析における false positive を抑制するためのルール。

### Finding 化の条件

- SKILL.md 内の **明示的な must / forbidden 制約**（「必須」「してはならない」「禁止」等）に紐づく逸脱のみ finding として記録する
- **Open-ended guidance**（「推奨」「可能であれば」「望ましい」等の柔軟な記述）は finding 対象外とする

### 判定フロー

1. 逸脱候補を検出
2. 対応する SKILL.md の記述が must/forbidden か open-ended か判定
3. must/forbidden → finding として記録
4. open-ended → finding 対象外（スキップ）

## Artifact-driven enrichment 例

以下は SKILL.md の Artifact-driven enrichment セクションの具体例。

### 例 1: ステップスキップ (contract / active-eval 件数不一致)

- contract.json の `verifiable_acs.length` が 3
- active-eval.json の `results.length` が 1
- 一部の verifiable AC が active-evaluator で評価されていない (= 必須評価ステップが未実行)
- → 「ステップスキップ」finding として、Evidence に `contract.json: /tmp/handoff-123-abc/contract.json` と `active-eval.json: /tmp/handoff-123-abc/active-eval.json` を追記
- Severity は既存判定 (transcript ベース) を維持

### 例 2: 指示無視 (review NEEDS_CHANGES 無視)

- review.json の `spec_review.verdict` が `NEEDS_CHANGES`
- transcript で coordinator が「LGTM」と返答
- → 「指示無視」finding の Severity を `critical` に上書き
- Evidence に `review.json: /tmp/handoff-123-abc/review.json` を追記

### 例 3: ステップスキップ (verifiable AC があるのに SKIPPED)

- contract.json の `verifiable_acs.length` が 2
- active-eval.json の `status` が `SKIPPED`
- 必須の active-evaluator ステップが実行されていない (verifiable AC があるのに評価をスキップ)
- → 「ステップスキップ」finding の Severity を `critical` に上書き
- Evidence に `contract.json` と `active-eval.json` の両方を追記
