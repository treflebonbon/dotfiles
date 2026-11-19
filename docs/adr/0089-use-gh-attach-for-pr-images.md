---
type: decision
title: PR の画像添付を GitHub CLI の --attach に移す
description: 添付専用ブラウザを廃止し、コメント添付の重複防止と結果照会を維持する
tags: [adr, github, pr-screenshots]
timestamp: 2026-11-17
status: accepted
---

# PR の画像添付を GitHub CLI の `--attach` に移す

PR へ既存画像を添付するだけでも、旧方式では GitHub CLI の認証に加えて添付専用ブラウザの認証・接続・所有権管理が必要だった。通常の GitHub CLI 認証と対象 repository の push 権限で使える公式の `--attach` へ移し、専用ブラウザと GitHub の画面構造に依存する処理を廃止する。2026-11-17 に合意した仕様と、CLI の挙動は以下を参照する。 [仕様 #601](https://github.com/treflebonbon/dotfiles/issues/601) · [GitHub CLI の公式手順](https://docs.github.com/en/github-cli/github-cli/attaching-files-with-github-cli)

- **コメント添付**は、明示的に呼び出した `pr-screenshots` が既存 PR に対して行う。通常の Markdown 画像参照で掲載位置と代替テキストを指定し、投稿とアップロードは `gh pr comment --body-file` と `--attach` に委ねる。依頼の識別、対象・入力・投稿者の照合、並行実行での重複防止、結果保存と照会は補助 CLI が担う。
- **部分投稿**を許容する。`gh` は一部の画像しかアップロードできなくてもコメントを投稿し、非0で終了することがある。説明と全画像の掲載を確認できた場合だけ完了とし、一部掲載・全画像失敗・送信結果不明・照会失敗を区別する。コメント URL が判明していれば記録し、画像・原稿・receipt・不足分・理由を保持する。不明な送信は照会し、不足分の補完は明示的な別依頼として扱う。
- **本文添付**は `gh pr edit --attach` による末尾追記を基本とする。位置指定では最新本文を基にした Markdown 原稿を `--body-file` で渡す。コメント添付の重複防止はコメント依頼に適用する。
- **移行**では旧 `browser-attachments upload` と独自 placeholder の互換性を廃止する。撮影・Dogfood の共通資産と、既存 profile・利用者の状態・証跡を保持する。旧依頼の結果は保存済みの証跡と対象 PR を照合し、自動再送しない。公開 `treflebonbon/skills` が skill・補助 CLI・専用検証を所有し、dotfiles が受入済み版の pin・配布・導入確認を担う。 [ADR-0082](0082-extract-local-skills-to-public-repository.md)

[ADR-0026](0026-attach-playwright-evidence-to-pr.md) のブラウザによる PR 添付と、[ADR-0059](0059-scope-browser-ownership-and-share-attachments.md) の添付専用 identity に関する判断を置き換える。現行の操作は [PR 画像添付](../../runtime/skill-harness.md#pr-画像添付) を参照する。

公開側の fixture・配布検証と、dotfiles 側の固定版採用・Bats の結果は各 PR に記録されている。実 GitHub への添付、Windows Chrome での撮影、dotfiles からの公式 runtime 3種の実導入は未確認。 [公開側の実装 PR](https://github.com/treflebonbon/skills/pull/98) · [dotfiles の採用 PR](https://github.com/treflebonbon/dotfiles/pull/606)
