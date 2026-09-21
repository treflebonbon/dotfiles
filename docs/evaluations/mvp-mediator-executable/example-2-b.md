# Scenario B: 合計表示の整形とヘルプ tooltip

## 入力

- 対象スキル: `local-skills/mvp-mediator-architecture/SKILL.md`
- INPUT target SHA256: `ce4554b1f544571257a0635657d7bc9e6eddb3435c59346e702792d4050f7c2f`
- 実際に読んだ参照: `local-skills/mvp-mediator-architecture/references/tanstack-effect.md`
- 前提: 既存の React/TanStack Query 画面には複数 consumer を持つ compound Context があり、Effect は導入されていない。

## 変更提案

合計値を表示する既存 View で、その画面が既に利用している formatter を合計値にも適用する。新しい金額整形 helper や状態管理は作らない。

同じ View にヘルプ tooltip を追加し、開閉が必要な API ならその View 内の局所状態で保持する。tooltip を閉じても合計の取得、TanStack Query のキャッシュ、送信可否、既存の業務処理には影響させない。既存 compound Context の各 consumer は維持し、Context を単一 connector や中継専用コンポーネントへ集約しない。

業務規則、送信制御、Query の無効化・再取得は現在の所有者のままとする。この変更では Mediator、reducer、global model、Atom、Effect を追加しない。

## 凍結基準の判定

| 基準 | 判定 | 理由 |
| --- | --- | --- |
| 1. 既存 stack を保持し、Effect/Atom/MVP へ移行しない | ○ | React/TanStack Query と既存 Context を維持し、Effect、Atom、MVP 移行を提案しない。 |
| 2. 表示変更と tooltip 局所状態に限定し、Mediator/reducer/global model を新設しない | ○ | 変更は formatter の適用と View 内 tooltip の開閉だけであり、操作許可や状態遷移を扱わない。 |
| 3. 複数 consumer を許し、単一 connector や中継専用層を強制しない | ○ | compound Context の既存 consumer をそのまま利用する。購読数を理由に構造を変えない。 |
| 4. 既存 formatter と View ローカル tooltip を利用 | ○ | 画面で既に使われる formatter を再利用し、tooltip の表示状態は該当 View に閉じる。 |
| 5. 業務規則/送信制御の既存所有者を変えない | ○ | 表示と説明だけを変え、既存のユースケース、mutation、Query 制御へ条件や判断を移さない。 |
| 6. 変更に釣り合う検証を挙げ、未実行のアプリテストを成功扱いしない | ○ | 下記の表示確認と静的確認を区別して記録する。アプリテストは未実行として扱う。 |

## 検証メモ

| 検査 | 期待結果 | 実測結果 |
| --- | --- | --- |
| 合計表示 | 既存 formatter と同じ表記で合計値が描画される | 未実行（アプリ実装なし） |
| tooltip の開閉 | 開く・閉じる操作はヘルプ表示だけを変え、合計値や送信操作を変えない | 未実行（アプリ実装なし） |
| compound Context の consumer | 既存の複数 consumer が残り、中継専用層が増えない | 未実行（アプリ実装なし） |
| `oxfmt` | このメモがリポジトリ設定に従って整形済みである | 実行済み・成功（`bunx oxfmt --check`） |
| `git diff --check` | このメモの差分に空白エラーがない | 実行済み・成功 |

実装時は、既存の formatter を使う画面上の値と合計値を並べて確認し、tooltip の開閉前後で送信ボタン、mutation 実行、Query の状態が変化しないことを確認する。非同期操作・取消・再試行の制約を追加しないため、新たな状態対応表や遷移検証は不要である。

## 不明点

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| formatter と tooltip の正確な import/API | このシナリオは実装対象のファイル名と既存コンポーネント API を与えていない | 実装前に当該 View と既存 formatter/tooltip の利用箇所を読み、既存 API をそのまま使う。新規 helper や状態共有は追加しない。 |
| 実行するアプリテスト | この提案にはアプリ実装がなく、画面用テストコマンドも指定されていない | 実装後に既存の最小の画面テストまたは手動確認を実行し、未実行なら成功として記録しない。 |

## 任意補完

tooltip コンポーネントが非制御の開閉を提供済みなら、その API を使い `useState` すら追加しない。制御が必要な場合だけ、状態を表示 View の中に置く。

## YOUR Trace

`allOK`

| 項目 | 判定 | 根拠 |
| --- | --- | --- |
| Understanding | OK | 既存 stack、compound Context、Effect 未導入、表示のみという前提を保持した。 |
| Planning | OK | 既存 formatter の再利用と View 局所 tooltip に限定した。 |
| Execution | OK | 実装は提案に留め、Mediator/reducer/global model やライブラリ移行を追加しなかった。 |
| Formatting | OK | 判定、検証、未実行事項、不明点を所定の形式で記録した。 |

## YOUR Retries

やり直し数: 0。凍結基準すべてに初回の提案で適合しており、追加の構造変更は不要と判断した。
