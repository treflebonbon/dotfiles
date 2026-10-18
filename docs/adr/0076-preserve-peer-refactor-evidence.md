---
title: peer-refactor の公開証跡を Git common dir に保管する
status: accepted
date: 2026-10-18
---

# peer-refactor の公開証跡を Git common dir に保管する

gateway のリファクタを再開した際、task worktree と commit は残っていたが、`/tmp/codex` の元レポート・固定 record・peer 記録がなく、公開の照合を継続できなかった。元セッションの tool 入力からレポートと record を復元すると、会話の fingerprint と一致した。ファイルが消えた直接の原因は未確認である。

作業中の共有は ADR-0074 の `/tmp/codex` に保ち、復旧用 checkpoint は現在の repo の Git common dir 配下の `peer-refactor-evidence/` に保存する。既存 repo identity を使えて別 worktree から参照でき、task worktree の寿命にも依存しない。XDG 配下へ新しい共有 root や runtime の許可を追加する案は採らない。

checkpoint は公開ファイルを明示して作り、全体の hash と元 record fingerprint を会話に残す。元 artifact・候補・record の内容と絶対パス、全 peer の応答・待機予算・review round・失敗履歴、判断・検証結果を保持する。既存の記録が異なる場合は復元せず、受入・merge まで保管する。自動削除はしない。

再開時は checkpoint を復元し、元 fingerprint と source SHA を既存 checker で再照合する。checkpoint がない過去 run も、ユーザーへバックアップを尋ねる前に一次実行記録からの同内容復旧を確認する。ログの任意コマンドは実行せず、hidden reasoning・credential を抽出しない。復旧不能な台帳をゼロに戻したり、会話要約から候補を再定義したりしない。手順は [規範契約](../../runtime/autonomous-peer-contract.md#証跡の保存と復旧)に集約する。
