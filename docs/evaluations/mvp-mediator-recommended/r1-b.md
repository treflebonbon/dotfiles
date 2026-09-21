# B — Effect未導入の表示変更: 変更メモ

## Deliverable

既存の合計表示 View に、現在使われている合計値と既存 formatter をそのまま渡した整形済みテキストを表示する。表示の近くに、既存の局所 tooltip の実装またはプロジェクトの既存 tooltip パターンで help tooltip を置く。開閉状態はその View 内だけに置き、tooltip の開閉は送信、Query、他 consumer、業務規則へ通知しない。

compound Context の各 consumer は現在のまま読み続ける。Query の取得・キャッシュ・送信制御、Context の構成、業務規則の所有者は変更しない。Effect、Atom、Mediator、reducer、global state、単一 connector、中継専用層、実行モデルは追加しない。

## 凍結基準

| 基準 | 判定 | 理由 |
| --- | --- | --- |
| 1. Query と既存設計を保ち、Effect/Atom 導入や MVP 移行を要求しない。 | ○ | 既存 TanStack Query と compound Context を変更せず、View の表示だけを追加する。 |
| 2. 表示と局所 tooltip に限定し、Mediator/reducer/global state/実行モデルを追加しない。 | ○ | tooltip の開閉は当該 View の局所状態だけで扱い、操作の裁定や非同期実行を増やさない。 |
| 3. 複数 Context consumer を保ち、単一 connector や中継専用層を強制しない。 | ○ | 既存 consumer を集約せず、そのまま Context を読む構成を維持する。 |
| 4. 既存 formatter と局所 tooltip を再利用する。 | ○ | 合計値の表示には既存 formatter を呼び、tooltip は既存の局所実装または既存パターンを使う。 |
| 5. 無関係の業務規則・送信制御の所有者を変えない。 | ○ | 送信可否、送信中状態、業務検証、Query 更新には触れない。 |
| 6. 整形と tooltip に釣り合う具体的な確認を示し、未実行アプリ検査の成功を主張しない。 | ○ | 下記の表示・開閉確認を示す。アプリ検査は未実行であり、成功は主張しない。 |

## 確認メモ（未実行）

1. 既存 Query が返す代表的な合計値を表示し、画面テキストが同じ値への既存 formatter の出力と一致することを確認する。
2. help tooltip が初期状態では閉じており、トリガー操作で開き、閉じる操作で閉じることを確認する。
3. tooltip の開閉前後で送信操作の可否・進行表示・Query の状態・他の Context consumer の表示が変化しないことを確認する。

## YOUR Trace

allOK。Understanding: B の対象を、既存 React/TanStack Query 画面における合計値整形と局所 help tooltip と特定した。Planning: スキルの既存構成維持、複数 consumer の許容、表示整形・tooltip 開閉の View 所有を適用した。Execution: コード、Effect、Atom、Mediator、実行モデルを追加しない変更メモに限定した。Formatting: Markdown を `oxfmt --check` で確認する。

## Unclear

該当なし。Issue: なし。Cause: 課題 B が変更範囲と凍結基準を定めている。General Fix Rule: 実装時に既存 formatter または tooltip パターンの場所が未特定なら、同じ画面で既に使われているものを探索して再利用し、新規の状態管理・接続層を導入しない。

## 任意補完

tooltip の文言は合計の意味だけを説明し、送信可否や業務上の判断を示す内容にしない。

## YOUR Retries

判断やり直し数: 0。

## INPUT

- 課題: `docs/evaluations/mvp-mediator-recommended/protocol.md` の `## B — Effect未導入の表示変更` 節のみを読んだ。
- スキル: `local-skills/mvp-mediator-architecture/SKILL.md`（SHA-256: `050c87041aecc5bf04e24f425f56e01d0e10dc4c9d46ecc9d9f50dcf98eec0fb`）を全文読んだ。
- 実読 reference: `local-skills/mvp-mediator-architecture/references/tanstack-effect.md` を全文読んだ。
