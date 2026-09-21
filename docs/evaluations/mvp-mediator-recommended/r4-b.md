# B — Effect未導入の表示変更

## Deliverable

既存の React/TanStack Query 画面で、現在の compound Context の各 consumer を維持したまま、合計値には既存 formatter を適用する。help tooltip は合計値を表示する View の局所状態として追加し、開閉は表示だけを変える。Query、送信、業務規則、既存の状態所有者は変更しない。

提案する最小変更は次のとおり。

- 合計値の表示箇所で既存 formatter を呼ぶ。
- 同じ View に既存の tooltip 実装を使い、開閉状態を局所的に保持する。
- 既存 Context consumer と TanStack Query の取得・キャッシュ接続はそのままにする。

確認メモ（未実行）:

- 合計値が formatter を通した表記になることを、既知の合計値で確認する。
- tooltip を開閉しても合計値、Query の状態、送信 UI、他 consumer の表示が変わらないことを確認する。
- 送信の可否・実行・取消に関する既存の操作を一度実行し、今回の表示変更が既存フローを変えないことを確認する。

アプリの検査は未実行であり、上記は確認すべき内容であって成功結果の主張ではない。

## Criteria

| # | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | TanStack Query と既存構成を維持する。Effect、Atom、MVP への移行は提案しない。 |
| 2 | ○ | 変更は数値整形と View 内の tooltip 開閉だけである。Mediator、reducer、global state、実行モデルは不要である。 |
| 3 | ○ | compound Context の複数 consumer をそのまま使う。単一 connector や中継専用層を設けない。 |
| 4 | ○ | 合計値は既存 formatter、tooltip は既存の局所実装を再利用する。 |
| 5 | ○ | 業務規則、送信制御、Query の所有者を変更しない。tooltip の開閉は他操作に影響しない。 |
| 6 | ○ | 整形表示、tooltip の局所性、既存送信フローの非干渉という具体的な確認を示し、アプリ検査は未実行と明記した。 |

## YOUR Trace

### Understanding

Effect 未導入で既存構成の維持が規約である。要求は他操作へ影響しない表示と局所 tooltip の追加なので、操作間の制約や非同期結果の裁定は生じない。

### Planning

既存 formatter と tooltip を利用し、表示 View だけを変更対象にする。既存の compound Context、TanStack Query、送信フローは接続も所有者も変えない。

### Execution

設計メモのみを作成した。アプリコード、Model、API、状態機械、実行モデルは作成していない。

### Formatting

本ファイルは Markdown として `oxfmt --check` で確認する。

## Unclear Issue / Cause / General Fix Rule

該当なし。シナリオの制約と最小変更の範囲は明確であり、追加の一般化や修正規則は不要である。

## Optional fill-ins

なし。

## YOUR Retries

0

## INPUT

- 対象 SKILL.md の SHA-256: `050c87041aecc5bf04e24f425f56e01d0e10dc4c9d46ecc9d9f50dcf98eec0fb`
- 読了したスキル: `local-skills/mvp-mediator-architecture/SKILL.md`
- 実際に読んだ適用参照: `local-skills/mvp-mediator-architecture/references/tanstack-effect.md`
