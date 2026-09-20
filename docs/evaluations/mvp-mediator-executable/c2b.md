# B メモ

スキル: `/home/ubuntu/.codex/worktrees/90ae/dotfiles/local-skills/mvp-mediator-architecture/SKILL.md`  
SHA-256: `25cc12b199514b6876f499469814f5a14421ef5d8a7f1362a39d6e5947032fb6`

| 基準 | 判定 | 根拠 |
| --- | --- | --- |
| 1. Query／既存構成を維持 | ○ | B は既存 React/TanStack Query とプロジェクト規約を維持し、Effect/Atom/MVP 移行を禁じる。 |
| 2. 表示変更を局所化 | ○ | 合計表示と他操作に影響しない tooltip のみ。Mediator/reducer/global state/遷移モデルは不要。 |
| 3. Context 消費者を維持 | ○ | compound components の複数 Context consumer を維持し、単一 connector/転送を要求しない。 |
| 4. formatter と局所 tooltip を再利用 | ○ | 既存 formatter と local tooltip state を使う。 |
| 5. 業務・送信ロジックの所有者を維持 | ○ | 無関係な business/submission logic は既存 owner のまま。 |
| 6. 比例した具体確認 | ○ | formatter の合計表示と、tooltip の開閉が送信・他操作を変えないことを確認対象とする。アプリ試験の実行・成功は主張しない。 |

採点: 6.0/6.0（critical 2 件はいずれも full、成功）。

Trace: Understanding OK / Planning OK / Execution OK（本メモ作成） / Formatting OK。

Unclear: 実アプリの formatter 名・tooltip 実装・確認手段は未提示。Cause: B は負の対照の方針だけを与える。General Fix Rule: 実装時は既存の formatter と局所 state を確認して最小変更にする。

裁量: コード・状態モデル・アプリ試験は追加しない。再試行: 0。
