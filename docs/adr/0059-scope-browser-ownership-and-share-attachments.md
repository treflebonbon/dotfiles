---
type: decision
title: ブラウザ所有権を identity ごとに管理し PR 添付を共有する
status: accepted
---

# ブラウザ所有権を identity ごとに管理し PR 添付を共有する

#301 の Agent Brief に基づく。ADR-0058 の先行検証で、独立 Windows profile の分離・保持と、既存専用認証を使う並列添付が成立した。全体排他のままでは worktree の並列作業を支えられない。

## Decision

- 所有権は同じ root と短時間の登録 lock を共有し、identity ごとの record に分ける。予約時に profile / CDP endpoint の重複を拒否する。世代 token、未確定起動の保持、停止確認後の解放を継続する。
- 通常の検証は物理 worktree root から identity を作り、profile を永続保持する。profile、CDP、Dashboard port、lease と終了処理を同じ identity に結び付ける。別 worktree と Dogfood 試行は独立する。
- 同じ identity の headless / headed 競合は既存 consumer を保持して拒否する。Dashboard はその検証ブラウザの headed 表示面であり、別 identity を追加しない。背景処理から可視画面を自動起動しない。
- 旧専用 GitHub profile は添付専用 identity で利用する。要求ごとの Page と receipt を扱う CLI を公開し、汎用 browser 操作を要求へ公開しない。異なる PR の upload は並列、同じ repository / PR 本文更新は flock 内で fresh read →置換→write を行う。排他に参加しない外部編集者との分散原子性は保証しない。
- 同じ request ID は asset を再利用し、本文更新を再開できる。送信の成否が不明なら新しい upload を自動再送しない。ログインが必要な場合は to-pr 外の人間の操作とする。
- 旧 consumer を旧 package で終了してから新 package と Dogfood skill を揃える。旧 owner / acquire.lock / runtime lease が残っていれば拒否する。旧 profile や認証をコピー・初期化しない。
- ADR-0031 の単一 identity・固定 Dashboard port、ADR-0047 の全体排他を置き換える。WSL browser-free、同一 identity の排他、認証境界、慎重な復旧の判断は維持する。

## Consequences

共有添付には独立した lifecycle と request receipt が必要になる。receipt は認証情報を含まないが、PR と asset の対応を含むためユーザー専用の runtime directory に保持する。通常の検証 profile と添付認証は独立してリセットする。

新構成の Dogfood / Dashboard 共存、可視操作と背景作業の非干渉は本実装の必須実機受入試験。試験未実施を合格にしない。portless は標準配布・必須依存に採用せず、実アプリごとの任意導入条件を維持する。
