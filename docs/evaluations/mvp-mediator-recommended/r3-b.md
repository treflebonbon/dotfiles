# R3-B 実行メモ

## Deliverable

既存の合計値表示コンポーネントで、現在使われている formatter に合計値を渡して表示する。既存の compound Context の各 consumer はそのまま維持する。help tooltip は同じ表示コンポーネント内の局所開閉状態だけで実装し、送信・Query・業務規則には接続しない。

変更箇所は合計値を表示する既存コンポーネント一箇所を想定する。新規の Effect、Atom、Mediator、reducer、global state、connector、中継専用コンポーネント、実行モデルは作らない。

確認メモ:

- 合計値に既存 formatter を適用した表示が既存の期待書式になることを画面または既存のコンポーネント確認で見る。
- help を開閉しても tooltip の表示だけが変わり、送信ボタン、送信中表示、Query の取得状態、他 consumer の表示が変化しないことを確認する。
- アプリ検査は未実行。ここでは確認項目だけを提示する。

## 基準

| 基準 | 判定 | 理由 |
| --- | --- | --- |
| 1. Query と既存設計を保ち、Effect/Atom 導入や MVP 移行を要求しない | ○ | TanStack Query と compound Context を保持し、表示コンポーネントだけを変更する。 |
| 2. 表示と局所 tooltip に限定し、Mediator/reducer/global state/実行モデルを追加しない | ○ | tooltip の開閉は当該 View の局所状態に留め、操作フローの裁定や実行を追加しない。 |
| 3. 複数 Context consumer を保ち、単一 connector や中継専用層を強制しない | ○ | 各 consumer の購読と接続を変更しない。 |
| 4. 既存 formatter と局所 tooltip を再利用する | ○ | 合計値は既存 formatter で整形し、tooltip は表示コンポーネント内の既存の局所的な扱いを使う。 |
| 5. 無関係の業務規則・送信制御の所有者を変えない | ○ | 送信、業務規則、Query の所有者を触らず、tooltip からもそれらを操作しない。 |
| 6. 整形と tooltip に釣り合う具体的な確認を示し、未実行アプリ検査の成功を主張しない | ○ | 書式表示と tooltip 開閉時の局所性を確認対象にし、アプリ検査は未実行と明記した。 |

## YOUR Trace

allOK

## Unclear

| 項目 | 内容 |
| --- | --- |
| Issue | 既存 formatter と tooltip 実装の具体的なファイル名・API は課題から示されていない。 |
| Cause | この課題はアプリコードを調べず、最小の変更提案だけを作る前提である。 |
| General Fix Rule | 実装時はまず合計値表示の既存箇所と formatter/tooltip の利用例を探し、同じ API と構成を使う。利用例がなければ、コンポーネント内の最小の局所状態だけを追加する。 |

## 任意補完

tooltip を閉じる操作は説明表示だけを変えるため、Mediator に通知しない。これは View に許される局所表示状態であり、送信など別操作の進行へ影響しない。

## YOUR Retries

やり直し: 0 回。課題の要件と Skill の表示変更に関する指針が一致しており、設計判断を修正する必要はなかった。

## INPUT

- target SKILL.md SHA-256: `050c87041aecc5bf04e24f425f56e01d0e10dc4c9d46ecc9d9f50dcf98eec0fb`
- 実読 reference: `local-skills/mvp-mediator-architecture/references/tanstack-effect.md`
