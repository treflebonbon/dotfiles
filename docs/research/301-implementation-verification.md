---
type: research
title: Issue 301 ブラウザ並行利用の実装検証
---

# Issue 301 ブラウザ並行利用の実装検証

2026-09-11。対象は `implement/301-parallel-browser`、比較基準は `90b9c5947ee32ffb0d4473ac02424c6df1b4ae64`。[Agent Brief](https://github.com/treflebonbon/dotfiles/issues/301#issuecomment-5627472175) の AC を検証する。**可視 Dashboard の必須受入試験が未実施のため、実装全体は未完了。** 先行 prototype の成功を今回の成功へ転記しない。

Session Scratchpad は context から特定できなかったため、許容された fallback `/tmp/triage-301-probe/` に生ログ・試験コード・画像を保存した。これらは一時資料であり永続保存を保証しない。認証情報、signed upload URL、前面 window ID、cursor の生座標はこの文書へ含めない。

## 実装と配布確認

- `785729f`: browser identity ごとの予約・世代・実資源競合と worktree 割当。
- `bd1430d`: worktree wrapper / Dashboard / Dogfood と共有添付 CLI、運用手順。
- `a478f60`: 添付 CLI の所有権競合・CDP 障害時の非変更を検証。
- `d572cfe`: Dashboard 開始 session の停止権限、明示 profile reset、添付再開と診断・文書のレビュー修正。
- Nix package を source からビルドし、store 内の CLI を直接検証した。最終ビルドは `/nix/store/x1phcq8gpmf0i8vb8gg66vl5hmzzqwmx-playwright-cli-0.1.19`。実機操作の直前版 `qdyh4450xb6lkjhdb4grs1dymac28s97-playwright-cli-0.1.19` との差は skill 文書と JavaScript の整形のみ。
- 未 merge worktree から `chezmoi apply` は実行していない。WSL browser binary の導入は行っていない。

## Verification Matrix

| AC | 結果 | 今回の証拠・制限 |
| --- | --- | --- |
| AC1 | 成功 | 隔離した alpha / beta の2つの git worktree から Windows headless Chrome を同時起動。異なる profile / CDP、同一 origin の別 cookie / localStorage、URL と撮影画像を照合。`implementation-isolation.json` |
| AC2 | 成功 | A の終了・再起動で cookie / storage を保持、B は継続。さらに停止した synthetic A を exact identity で reset し、A だけ cookie / storage が消え、B は保持。`implementation-restart.json`、`implementation-reset.json`。誤 identity・active reset 拒否は wrapper 回帰試験 |
| AC3 | 成功 | 既存の専用認証で実 PR #302 / #303 へ別 process から添付。S3 POST の request→requestfinished 区間が **962ms 重複**。本文の asset URL と、認証済み download の画像 SHA-256 が各原画像に一致。`implementation-network.json`、`implementation-network-assets.json` |
| AC4 | 成功 | 同じ実 PR #302 の異なる placeholder を2 process から更新し、両画像と既存本文を保持。`implementation-same-pr.json`。既存 asset の再利用でも新 placeholder を置換する回帰試験を追加。保証は同じ flock に参加する caller 間に限定 |
| AC5 | 成功 | 実 CDP client を exit 17 で異常終了させ、B へ再接続して状態保持を確認。`implementation-crash.json`。正常停止、世代違い release、起動中 recover、不明状態保持は ownership / wrapper 回帰試験 |
| AC6 | 成功（故障注入） | 公開 CLI で mode 競合を `ownership-conflict`、到達不能 CDP を `cdp-unavailable` と区別し、owner と upload receipt の非変更を確認。実 Page の upload policy 通信を1件 abort して `upload-failed`、所有タブの終了、別タブの継続を確認。Page の遷移先に local HTTP 302 fixture を代入して `authentication-required` を確認。実認証を失効させず、未認証と期限切れの原因は断定しない。`implementation-upload-fault.json` |
| AC7 | 一部成功・必須残件 | 検証 A / B・共有添付・別 identity の Dogfood の実並行利用と、Dogfood 終了後の A / B 継続を確認。`implementation-dogfood.json`。**A Dashboard / B headless の表示・annotation は人間の明示開始待ちで未実施** |
| AC8 | 成功（回帰試験） | 同一 identity の mode 競合、他 session の annotation / Dashboard 停止、profile / endpoint 衝突を拒否。既存 consumer の継続、旧 runtime 拒否を確認。実機可視 Dashboard の確認は AC7 に残す |
| AC9 | 成功（観測範囲内） | 01:05:43.379–01:06:18.016 UTC の約34.6秒、200ms間隔・167 sample。headless の終了・起動・接続・状態読取り・撮影・実添付・終了を覆い、foreground / cursor は各1種類、cursor read は全成功。`implementation-focus.json`。標本間の短い変化と可視 Dashboard を保証しない |
| AC10 | 一部成功 | wrapper 65、ownership / Dogfood / evidence 30、attachment CLI 2 の計97件成功。型検査、関連 skill 文書検査、Nix build、pre-commit を通過。全体 suite の未解消条件は下記 |
| AC11 | 成功（回帰試験・文書） | 旧 global owner / runtime lease で移行を拒否。不明・live 状態を強制解放しない。旧版で終了→package と Dogfood skill を更新→devShell 再読込みを明記。旧 devShell の ownership CLI との混在が実際に失敗することも確認 |
| AC12 | 成功（文書照合） | ADR-0058 / 0059 と先行調査に標準非採用を記録。PORT と公開 URL、proxy Host、callback allowlist、Windows 名前解決 / TLS、名称衝突は任意導入の条件として維持 |

## 実 PR 証跡

- [PR #302](https://github.com/treflebonbon/dotfiles/pull/302): alpha 画像 SHA-256 `07372765bf5594c312e594dc9b46ec5c5d4f3ed556e8b2dc44db04e983333dbd`。
- [PR #303](https://github.com/treflebonbon/dotfiles/pull/303): beta 画像 SHA-256 `361a06359f23951385e980fbc75cf5c2f7cdcc53a181c9ddc720e26b6e697744`。

両者は承認済みの Draft fixture PR。本文の先行証拠を保持して追記した。close / merge / branch 削除は実行していない。同じ request ID の再実行は元の asset・時刻を返し、新しい upload を行わないことも確認した。

## 全体テストと残件

`bun run test` は695件を実行し、初回は683成功・12失敗。ログは `full-suite.log`。全成功とは扱わない。

- Dogfood の9失敗は、既存 devShell が旧 `managed-chrome-owner` を参照し `--identity` を受け付けないことを単独再現した。新 package の owner と同梱 Windows helper に揃えると、headless の既存 report path 試験は成功。残る annotation 関連8件は headed 起動を含むため、人間の明示開始後に再実行する。
- WSL skill の1失敗は mode 選択の説明不足を補い、対象検査が成功した。
- delete-data の1失敗は明示 reset の対象と案内を修正し、wrapper 65件の再実行ですべて成功した。
- `human-validation.bats` の1失敗は、実行環境に `with-env` が見つからず、Nix store 内の実体を要求する既存 precondition に失敗した。該当 test / helper は比較基準から変更していない。必要な runtime がある環境で再検証が必要。

Standards / Spec の並列 code-review 後、指摘を修正して再レビューした。両軸ともコード上の未解消指摘は0件。可視受入試験や全体 suite の不足を、このコードレビュー結果で合格扱いにはしない。

## 終了状態と再開

今回の synthetic A / B、共有添付 Chrome、試験用 HTTP server は個別に終了した。最後の ownership `status` は `null`。検証 profile と共有添付認証は保持している。テスト用 fixture PR と prototype branch も保持した。

再開時は最終 package の `MANAGED_CHROME_OWNER` と `DOGFOOD_WINDOWS_SCRIPT` を同梱版へ揃える。人間が開始を明示した後に、A を headed / Dashboard、B を headless で起動し、表示・annotation、別 identity の添付 / Dogfood、各終了後の他方の継続を確認する。annotation 関連8件をその環境で再実行する。`with-env` の既存 runtime 条件も整え、残った `human-validation.bats` を再検証してから完了判定する。
