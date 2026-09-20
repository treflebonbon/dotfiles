# Scenario D: 保存ポリシーの責務メモ

対象は既存の React/Query フォームである。ここではアプリ実装を増やさず、同じ責務を Node 組み込み `assert` で実行する抽象モデルだけを示す。

## 責務と状態対応

| 状態・境界 | 分類 | 所有者 | 用途 |
| --- | --- | --- | --- |
| `values`、`draftRevision` | existing mock | 既存フォーム binding | 入力と形式検証を保持する。表示整形も Form / Passive View に残す。 |
| `execute(command)`、Query の mutation 通知 | existing mock | 既存 Query 実行境界 | snapshot を既存ユースケースへ渡し、成功・失敗を Mediator へ通知する。 |
| 業務検証 | existing mock | 既存ユースケース | 実行時に業務規則を検証する。Mediator は重複検証しない。 |
| `activeOperationId`、`savedRevision`、操作 ID | production added | `SaveMediator` | UI の保存許可、単一実行、結果採用を一箇所で裁定する。 |
| `started`、`received`、assertion | test-only | セルフチェック | 境界に渡った snapshot と結果採用を観測する。 |

`SaveMediator` が名前を持つ唯一の UI 保存ポリシー所有者である。View は save 要求を通知し、入力の形式検証と表示用整形をフォーム / View に置く。業務検証、Effect 移行、取消、auto retry は追加しない。

## 遷移と検証記録

| 検査名 | 前状態 / イベント / 後状態 | 資源所有者 / 実行効果 | 期待結果 | 実測結果 |
| --- | --- | --- | --- | --- |
| 通常成功 | revision 0 / save, success(1) / savedRevision 0・idle | Mediator が操作 1 を所有し Query が snapshot を実行 | 初期 save が完了し dirty でない | ○ `node d.mjs` assertion 通過 |
| 保存中編集 | revision 1 / save, edit to revision 2, success(2) / savedRevision 1・dirty | Mediator が操作 2 を所有、フォームは編集を保持 | command は revision 1・値 A のまま、値 B は dirty のまま残る | ○ assertion 通過 |
| 同時 save | 操作 2 実行中 / save / 操作 2 継続 | Mediator が資源を保持、追加 Query 実行なし | 二重実行しない | ○ `started.length === 2` |
| 古い通知と失敗 | 操作 3 実行中 / success(2), failure(2), failure(3) / idle・savedRevision 1 | Mediator は操作 ID を照合 | 古い通知は操作 3 の進行を変えず、失敗は保存済み revision を進めない | ○ assertion 通過 |

実行コマンド: `node docs/evaluations/mvp-mediator-executable/d.mjs`。未検証の制約は、実際の React binding / TanStack Query の callback 配線、ユースケースの実業務規則、ネットワークの順序保証である。この抽象モデルは取消・自動再試行・Effect 移行を扱わない。

## 判定

| 基準 | 判定 | 理由 |
| --- | --- | --- |
| 1 | ○ | command を値と revision の clone として固定し、保存中編集後の成功が新しい下書きを saved にしないことを実行した。 |
| 2 | ○ | active 操作 ID 一致時だけ結果を採用し、失敗が `savedRevision` を変えず、同時 save を拒否することを実行した。 |
| 3 | ○ | フォーム binding と Query 実行境界を existing mock、Mediator 状態を production added、観測を test-only と明示した。 |
| 4 | ○ | 業務検証はユースケース、実行は Query 境界に残し、Effect・取消・auto retry を導入していない。 |
| 5 | ○ | 初期成功、保存中編集、失敗、古い成功・失敗通知を `assert` で実行し、未検証範囲も記録した。 |
| 6 | ○ | `SaveMediator` を唯一の保存ポリシー所有者とし、形式検証・表示整形の所有者をフォーム / View とした。 |

## 自己トレース

| 区分 | 状態 | 記録 |
| --- | --- | --- |
| Understanding | OK | 指定された保存順序、revision と古い通知の分離をモデル化した。 |
| Planning | OK | 既存 binding / Query を模擬し、Mediator へ必要最小限の裁定状態だけを置いた。 |
| Execution | OK | Node built-ins のセルフチェックを実行する。 |
| Formatting | OK | 指定された状態分類、遷移記録、基準判定を日本語で記載した。 |

## 不明点と一般則

| Unclear Issue | Cause | General Fix Rule |
| --- | --- | --- |
| 実アプリの Query callback が操作 ID をどこまで保持できるか | この成果物は framework 非依存の抽象モデルで、既存 binding の実装を読まない制約がある | 実行境界で操作 ID を保持して Mediator の通知へ戻し、active ID と一致する結果だけを進行状態に採用する。 |

裁量選択: snapshot は `structuredClone`、実行中の再要求は拒否、結果採用は operation ID 完全一致とした。今回の反復判断回数: 1（単一保存の拒否方針）。

SKILL.md: `/home/ubuntu/.codex/worktrees/90ae/dotfiles/local-skills/mvp-mediator-architecture/SKILL.md`  
SHA-256: `25cc12b199514b6876f499469814f5a14421ef5d8a7f1362a39d6e5947032fb6`
