---
name: pr-screenshots
description: "修正箇所を撮影するか既存画像を使い、既存 PR のコメントへスクリーンショットを添付する。"
disable-model-invocation: true
---

# pr-screenshots

必要なときだけ明示的に呼ぶ、画像添付の補助スキル。PR 本文作成は上流 `pr` に任せ、このスキルは短い説明と画像を PR コメントにまとめる。実装・push・PR 作成・本文更新は行わない。

## 対象と画像を決める

1. 指定された PR の URL・番号と repository を解決する。指定がなければ現在のブランチの PR を `gh pr view --json number,url` で調べ、URL から repository を確認する。複数の候補があり曖昧な場合だけ質問する。対象の `OWNER/REPO#NUMBER` と URL を表示する。PR がなければ、取得画像を残して PR 作成後の再実行を案内する。
2. セッション所有の一時ディレクトリに画像・コメント原稿・再実行コマンドを残す。既存画像が指定されていれば内容を確認して使う。撮影が必要なら Skill tool で `playwright-cli` を呼び、修正した要素と判断に必要な周辺が分かる範囲を撮る。native app や Orca 内蔵 page は、その操作面に対応する既存のブラウザ操作規則に従う。
3. 変更前には既存の比較 URL・環境・画像を使い、比較可能なら同じ表示幅・画面状態で変更前後を撮る。変更前がなければ変更後と未比較理由を残す。比較のためだけに別 worktree や起動環境を構築しない。機密値の写り込みを確認し、その画像は添付せず理由を残す。

## 1つのコメントに添付する

新しい添付依頼ごとに一意な `request-id` を作り、ディレクトリ内へ保存する。同じ依頼の再実行では、その ID・画像・原稿を再利用する。画像や説明を意図的に変更した場合は新しい依頼として扱い、過去のコメントを残す。

日本語の短い修正説明と画像のラベルを `comment.md` に書く。各画像の位置には、コマンドへ渡す順に `<!-- screenshot-1 -->`、`<!-- screenshot-2 -->` をそれぞれ1回置く。変更前がなければ「変更後」と未比較理由だけにする。

```markdown
## 修正箇所のスクリーンショット

設定パネルの保存ボタンが狭い画面でも操作できることを確認した。

**変更前**
<!-- screenshot-1 -->

**変更後**
<!-- screenshot-2 -->
```

```bash
browser-attachments comment \
  --repo OWNER/REPO --pr NUMBER \
  --image /absolute/path/before.png --image /absolute/path/after.png \
  --body-file /absolute/path/comment.md \
  --request-id SAVED_REQUEST_ID
```

CLI は全画像をアップロードしてから1コメントを投稿する。投稿済みの同じ依頼は GitHub 側で照会し、二重投稿を避ける。返されたコメント URL を確認し、画像と説明が揃ったことを報告する。画像を Git に commit しない。

## 失敗した場合

コメントを部分的に投稿せず、画像・原稿・取得済み添付 URL・失敗理由・同じ ID の再実行コマンドを残す。送信結果不明の `upload-unconfirmed` / `post-unconfirmed` は状態を調べ、ID を変えて再送しない。`request-conflict` は同じ ID の入力変更を意味するので、既存の依頼内容を確認する。

`post-unconfirmed` は API の照会で対応するコメントを確認できない状態。PR のコメント一覧と保存された receipt を調べ、投稿があれば URL を報告する。判定できなければ画像・原稿・取得済み URL と理由を人間へ引き継ぎ、投稿がないと確認できるまで手動投稿も行わない。`upload-unconfirmed` も receipt の取得済み URL と不明な画像を区別して引き継ぐ。認証不足・接続前の競合・`upload-not-started` は、原因を解消して同じ依頼を再実行できる。

添付専用ブラウザの認証は、検証ブラウザと別に手動確立されたものを使う。未認証なら手動添付へ引き継ぎ、自動ログインや認証情報のコピーはしない。ユーザーが認証準備を希望した場合の手順は `browser-attachments auth` → 専用ウィンドウで手動ログイン → `browser-attachments close`。

完了報告には対象 PR、コメント URL または失敗理由、変更前後の有無、残したファイルの絶対パスを含める。失敗した添付を完了扱いにしない。
