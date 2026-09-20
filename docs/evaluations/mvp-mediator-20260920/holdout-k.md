# Holdout K アーキテクチャメモ

## Deliverable

### 責務マップ

| 所有者 | 責務 |
| --- | --- |
| `document-editor` の VSA slice | 編集画面を組み立て、既存の保存バインディングと `EditorNavigationMediator` を接続する。React、TanStack、Effect は導入しない。 |
| `EditorNavigationMediator` | 保存中かどうかと現在の `SaveId` を既存バインディングから受け取る。保存中の遷移要求を最新の目的地だけに置換し、同じ `SaveId` の完了時に成功ならその目的地へ遷移、失敗ならキューを捨てる。保存の開始、取消、再実行はしない。 |
| 既存の save binding / 実行層 | 保存の実行、`pending` と結果、重複保存の拒否を担う。開始した保存の `SaveId` を完了結果にも対応付ける。 |
| hexagonal application use case | 文書の書込み権限を実行時に検証する。 |
| Filename View | ファイル名ドラフトと形式検証を局所状態として保持する。権限規則を disabled 表示のために再実装しない。 |
| ナビゲーション実行層 | Mediator が裁定した目的地へ実際に遷移する。 |

`EditorNavigationMediator` は editor slice 内の UI フロー所有者である。保存結果を別の View が直接使って遷移する経路は作らない。目的地を変更しても保存バインディングへの取消・再保存要求は送らない。

### イベント遷移

`SaveId` は開始済み保存を識別する値であり、目的地の置換では変更しない。完了通知は `SaveId` が現在保存中の値と一致するときだけ採用する。

| 前状態 | イベント | 後状態 | 資源所有者 | 実行効果 |
| --- | --- | --- | --- | --- |
| `Editing` | `Navigate(destination)` | `Editing` | なし | 直ちに `destination` へ遷移する。 |
| `Saving(saveId, queued = none)` | `Navigate(destination)` | `Saving(saveId, queued = destination)` | save binding | 保存は継続し、遷移は待機する。 |
| `Saving(saveId, queued = old)` | `Navigate(destination)` | `Saving(saveId, queued = destination)` | save binding | 待機先だけを最新値に置換する。保存の取消・再開はしない。 |
| `Saving(saveId, queued)` | `SaveSucceeded(saveId)` | `Editing` | なし | `queued` があればその最新目的地へ一度だけ遷移する。なければ遷移しない。 |
| `Saving(saveId, queued)` | `SaveFailed(saveId)` | `Editing` | なし | editor に残り、待機先を消去する。 |
| `Saving(currentId, queued)` または `Editing` | `SaveSucceeded/SaveFailed(otherId)` | 不変 | 既存の状態どおり | 遅延・重複した別保存の完了をナビゲーション判断へ採用しない。 |

### 具体的な確認

1. 保存 A が `pending` のときに `Navigate(/one)`、続けて `Navigate(/two)` を送る。保存開始回数は 1、取消回数は 0、保存中の `SaveId` は A のままで、待機先は `/two` になる。
2. 上記の保存 A を `SaveSucceeded(A)` で完了する。遷移は `/two` に一度だけ行われ、`/one` には遷移しない。
3. 保存 A 中に `/two` を待機させて `SaveFailed(A)` を送る。editor に残り、待機先は空になる。その後の保存 B 中に `/three` を待機させ、`SaveSucceeded(B)` を送る。遷移は `/three` だけであり、A の待機先は使われない。
4. `SaveSucceeded(A)` または `SaveFailed(A)` を A の処理後にもう一度送る。後続の状態と遷移先は変化しない。
5. 権限のない保存を要求する。use case が実行時に拒否し、Mediator と Filename View のどちらにも書込み権限の判定を追加しない。

## 六つの達成状況

1. ○ VSA slice と hexagonal use case を維持し、Svelte 以外の UI/非同期ライブラリや業務ロジックの集約を提案していない。
2. ○ 名前付きの `EditorNavigationMediator` が待機先を最新値に置換し、同じ保存を継続したまま成功・失敗を裁定する。
3. ○ 書込み権限は use case、ファイル名ドラフトと形式検証は View に残し、UI 用の権限規則を重複させていない。
4. ○ 既存 save binding の pending/result と重複保存拒否を前提にし、追加する状態は待機先と保存完了照合だけに限定した。
5. ○ 遷移表、説明、確認項目で `SaveId` を保存期間中に不変とし、一致する完了通知だけを採用している。
6. ○ 連続遷移、最新目的地への成功遷移、失敗後の次回保存で古い待機先が使われないことを具体的に確認している。

## Trace

| 観点 | 内容 |
| --- | --- |
| Understanding | 保存の重複拒否と pending/result は既存機能であり、追加要件は「保存中の遷移待機と最新目的地の裁定」であると捉えた。 |
| Planning | 保存・権限・入力検証を移さず、editor slice に一つの Mediator を置く責務境界を選んだ。 |
| Execution | 責務マップ、`SaveId` を含む遷移表、通常・失敗・遅延完了を含む確認項目を作成した。アプリ実装は変更していない。 |
| Formatting | 指定された Deliverable、六項目の判定、Trace、課題、裁量補完、再試行を日本語で記録した。 |

## 不明確な点

| Issue | Cause | General Fix Rule |
| --- | --- | --- |
| 既存 save binding の result が開始保存と対応付けられるかは未提示である。 | `pending/result` の存在だけでは、遅延または重複した完了通知を安全に照合できない。 | 反復・遅延完了を扱う UI フローでは、実行開始時の操作 ID を完了通知まで保持し、Mediator は一致する ID の結果だけを採用する。 |

## 裁量による補完

- 保存中ではない遷移は、保存フローと競合しないため直ちにナビゲーション実行層へ渡す。
- 待機先がない保存成功は、表示結果の更新だけを既存 binding に任せ、Mediator は遷移を起こさない。

## 再試行

再試行は不要。要件内の保存再開禁止、最新目的地の採用、失敗時の待機先消去を一つの遷移表と確認項目で満たしている。
