# B: 表示専用の負の対照メモ

## Deliverable

既存の React/TanStack Query と compound components の共有 Context を維持し、既存 formatter で total を整形して表示する。送信や他操作に影響しないローカル state の help tooltip を追加する想定。アプリコードと状態モデルは不要。

## 判定

| 基準 | 判定 | 根拠 |
| --- | --- | --- |
| 1. Query/プロジェクト構成を維持し、Effect/Atom/MVP 移行をしない | ○ | 指定は既存 React/TanStack Query の表示変更であり、新たな採用・移行を含まない。 |
| 2. 表示変更を局所化し、Mediator/reducer/global state/実行可能な遷移モデルを作らない | ○ | total 整形と送信等へ影響しない tooltip は表示専用の局所状態で足りる。 |
| 3. 複数の Context consumer を維持し、単一 connector/転送を要求しない | ○ | 接続方式は既存の共有 Context のままで、裁定を増やさない。 |
| 4. 既存 formatter とローカル tooltip state を再利用する | ○ | total は既存 formatter、tooltip の開閉はその View 内の local state を使う。 |
| 5. 無関係な業務・送信ロジックの所有者を維持する | ○ | tooltip は送信や他操作を変えないため、既存所有者に変更はない。 |
| 6. 比例した表示/tooltip 確認を示し、未実行のアプリテストを成功としない | ○ | formatter 済み total の表示、tooltip の開閉、送信への無影響を確認対象とする。アプリテストは実行していない。 |

critical はすべて ○ のため **success**。

## Trace

Understanding ○ / Planning ○ / Execution ○（本メモを作成）/ Formatting ○

## Unclear points

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| 既存 formatter と tooltip の具体名・既存テスト有無 | シナリオに実装詳細がない | 実装時は現在の formatter と View 内の state を確認して再利用し、未実行の確認を成功扱いしない。 |

## 任意補足

追加の Mediator、reducer、Context connector、Effect/Atom は不要。

## Retry

やり直した判断: 0
