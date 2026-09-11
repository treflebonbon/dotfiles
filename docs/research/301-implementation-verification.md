---
type: research
title: Issue 301 ブラウザ並行利用の実装検証
---

# Issue 301 ブラウザ並行利用の実装検証

2026-09-11。対象は `implement/301-parallel-browser`、比較基準は `90b9c5947ee32ffb0d4473ac02424c6df1b4ae64`。[Agent Brief](https://github.com/treflebonbon/dotfiles/issues/301#issuecomment-5627472175) の AC を検証する。ユーザーの可視 Chrome 開始指示を受けて、Dashboard / annotation の必須実機受入を完了した。実機で見つかった registry / socket 共有と Dogfood port 衝突も修正し、変更範囲を再検証した。 先行 prototype の成功を今回の成功へ転記しない。

Session Scratchpad は context から特定できなかったため、許容された fallback `/tmp/triage-301-probe/` に生ログ・試験コード・画像を保存した。これらは一時資料であり永続保存を保証しない。認証情報、signed upload URL、前面 window ID、cursor の生座標はこの文書へ含めない。

## 実装と配布確認

- `3ded6f1`: Dogfood の自動 port を予約と同じ排他区間で割り当て、未確定の予約や同時予約を避ける。明示 port と外部 listener の競合拒否は維持。
- `cc898be`: 可視試験で発見した上流 CLI registry / Dashboard singleton socket の共有を修正。物理 worktree ごとに分離し、同名 session を許容。Windows 確認の競合を待てるよう登録 lock の上限を30秒へ変更。
- `785729f`: browser identity ごとの予約・世代・実資源競合と worktree 割当。
- `bd1430d`: worktree wrapper / Dashboard / Dogfood と共有添付 CLI、運用手順。
- `a478f60`: 添付 CLI の所有権競合・CDP 障害時の非変更を検証。
- `d572cfe`: Dashboard 開始 session の停止権限、明示 profile reset、添付再開と診断・文書のレビュー修正。
- Nix package を source からビルドし、store 内の CLI を直接検証した。可視 Dashboard / 共存試験は `/nix/store/c8j7r9hpjz5b3zlirf3c42isag6irwlh-playwright-cli-0.1.19`。自動 port 割当の実機試験は `h47jkr2c51s5y5b73hrkrdwrqwcsqk3h-playwright-cli-0.1.19`、整形・helper 抽出・PowerShell 変数名修正後の最終ビルドは `/nix/store/n8r1ga32j6w1yhb4i0h8z8f1xqlvr7yi-playwright-cli-0.1.19`。
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
| AC7 | 成功 | A headed / Dashboard、B headless を同じ `acceptance` session 名で利用。A だけを一覧表示し、A への矩形注釈・feedback・画像・snapshot が CLI に返ることを確認。共有添付と Dogfood を同時利用し、それぞれ終了後も A / B を操作。`annotation-scoped-result.json`、`dashboard-coexistence.json`。終了順の確認は `dashboard-stop-check.json` |
| AC8 | 成功（回帰試験） | 同一 identity の mode 競合、他 session の annotation / Dashboard 停止、profile / endpoint 衝突を拒否。既存 consumer の継続、旧 runtime 拒否を確認。可視 Dashboard も A のみを表示し、同名 B の URL 操作は B に届くことを実機確認 |
| AC9 | 成功（観測範囲内） | 01:05:43.379–01:06:18.016 UTC の約34.6秒、200ms間隔・167 sample。headless の終了・起動・接続・状態読取り・撮影・実添付・終了を覆い、foreground / cursor は各1種類、cursor read は全成功。`implementation-focus.json`。さらに Dashboard 表示中の01:46:37.026–01:47:35.227 UTC、約58.2秒・279 sample で別 identity の Dogfood / 添付 / B 操作を覆い、foreground / cursor は各1種類。`dashboard-coexistence.json`。標本間の短い変化と任意の人間操作を保証しない |
| AC10 | 成功 | 修正後の wrapper / ownership 84件成功。前回の Dogfood / evidence / attachment CLI の成功に加え、最終全体 suite を実行。型検査、関連 skill 文書検査、Nix build、pre-commit を通過。全体実行で発見した3失敗は修正後の変更範囲再実行で解消。結果の内訳は下記 |
| AC11 | 成功（回帰試験・文書） | 旧 global owner / runtime lease で移行を拒否。不明・live 状態を強制解放しない。旧版で終了→package と Dogfood skill を更新→devShell 再読込みを明記。旧 devShell の ownership CLI との混在が実際に失敗することも確認 |
| AC12 | 成功（文書照合） | ADR-0058 / 0059 と先行調査に標準非採用を記録。PORT と公開 URL、proxy Host、callback allowlist、Windows 名前解決 / TLS、名称衝突は任意導入の条件として維持 |

## 実 PR 証跡

- [PR #302](https://github.com/treflebonbon/dotfiles/pull/302): alpha 画像 SHA-256 `07372765bf5594c312e594dc9b46ec5c5d4f3ed556e8b2dc44db04e983333dbd`。
- [PR #303](https://github.com/treflebonbon/dotfiles/pull/303): beta 画像 SHA-256 `361a06359f23951385e980fbc75cf5c2f7cdcc53a181c9ddc720e26b6e697744`。

両者は承認済みの Draft fixture PR。本文の先行証拠を保持して追記した。close / merge / branch 削除は実行していない。同じ request ID の再実行は元の asset・時刻を返し、新しい upload を行わないことも確認した。

## 全体テストと再検証

`bun run test` は695件を実行し、初回は662成功・12失敗・21 skip（TAP の `ok` 683件には skip が含まれる）。ログは `full-suite.log`。全成功とは扱わない。

- Dogfood の9失敗は、既存 devShell が旧 `managed-chrome-owner` を参照し `--identity` を受け付けないことを単独再現した。新 package の owner と同梱 Windows helper に揃えると、headless の既存 report path 試験は成功。人間の開始指示後、annotation を含むファイル全14件が成功した。registry / socket 修正後の全体 suite では、残った未確定予約との port 衝突を検出し、自動割当修正後にファイル全14件を再実行して成功した。
- WSL skill の1失敗は mode 選択の説明不足を補い、対象検査が成功した。
- delete-data の1失敗は明示 reset の対象と案内を修正し、wrapper 65件の再実行ですべて成功した。
- `human-validation.bats` の1失敗は、実行環境に `with-env` が見つからず、Nix store 内の実体を要求する既存 precondition に失敗した。該当 test / helper は比較基準から変更していない。正式な `nix build .#with-env` の出力を PATH に追加し、単独再実行で成功した。テストや条件を緩めていない。

Standards / Spec の並列 code-review 後、指摘を修正して再レビューした。両軸ともコード上の未解消指摘は0件。可視受入試験や全体 suite の不足を、このコードレビュー結果だけで合格扱いにはしない。`cc898be` と `3ded6f1` の追加修正も両軸で再レビューし、コード上の指摘は0件。

## 可視受入で見つかった問題と修正

上流 CLI は `.playwright` marker がない場合に session registry を共有し、Dashboard singleton socket も共有する。このため最初の実画面では A に B の一覧が見えた。ブラウザ所有権の分離だけでは不十分だったため、全 upstream コマンドの session registry・browser discovery・socket を物理 worktree root の hash に結び付けた。別 worktree の同名 session と同じ worktree の subdirectory を回帰試験と実機の両方で確認した。

Windows の lifecycle 確認が重なると共有 lock の旧5秒上限を超えることも観測した。上限を30秒へ変更し、6秒保持される lock を待って成功する回帰試験を追加した。取得失敗時の所有権保持は変更していない。

最初の旧5秒上限で失敗した Dogfood fixture `dogfood-0c132f79083b5968` は `starting` 記録を保持している。Windows helper の対象 Inspect は `absent` だったが、起動結果の確定を記録できなかったため正規 `recover` は拒否した。契約どおり記録を強制削除せず保持する。全体 suite の2件が同じ19379を PID 剰余から再選択し、正しく競合拒否された。失敗 report を `full-failure-197.md` / `full-failure-198.md` に保存した。自動 port を予約時に割り当てる修正後は、保持記録を避けて実機 Dogfood 全14件が成功した。所有権 / Dogfood 回帰29件も成功し、未確定記録を消さずに並行作業を続けられることを確認した。

全体 suite の再実行は **702件中678成功・3失敗・21 skip**（`full-suite-final.log`、exit 1）。skip は既存の明示 opt-in 試験で、Herdr / hosted model / 実サービス連携、Bash 3.2、6言語の実 Nix build など #301 の受入外の条件による。

検出した3失敗は次の修正・再検証で解消した。全体ログの失敗を成功へ書き換えず、最終 source の検証は変更範囲の再実行で補完する。

- annotation 失敗経路2件: 上記の保持中19379との衝突。自動割当修正後に Dogfood 実機ファイル全14件成功（`dogfood-auto-port-final.log`）、ownership / Dogfood 回帰29件成功（`auto-port-regression.log`）。この回帰には保持記録と並行2予約を扱う新規1件も含む。
- Nix package 静的検査1件: wrapper に固定9222 / 9323があることを要求する旧仕様の検査を、割当結果から endpoint / Dashboard port を受け取る現在契約へ更新して成功。PowerShell 自動変数 `$Profile` を再利用しない既存検査は維持し、reset のローカル変数名を修正した。

修正前後の wrapper / ownership 84件、正式な `with-env` package を使う `human-validation.bats`、型検査、lint、Nix build、commit hook も成功。最終コードの Standards / Spec 再レビューはいずれも指摘0件。

A の注釈は01:44:42 UTCに、`acceptance / Implementation 301 @ http://127.0.0.1:19433/alpha`、矩形 `{ x: 10, y: 26, width: 144, height: 57 }`、文言 `AC7: this annotation belongs only to alpha` として画像・snapshot とともに返った。A Dashboard に B の URL は表示されず、B の同名 session の `eval document.URL` は `/beta` を返した。Dashboard 終了後、続いて A Chrome 終了後にも B を操作し、その後 B も正常終了した（`dashboard-stop-check.json`）。

今回の A / B、共有添付、Dogfood の稼働 browser と試験 HTTP server は個別に終了した。最終 ownership 記録は上記の未確定 fixture 1件のみで、正常終了した consumer の記録は残っていない。認証 profile、検証 profile、Draft fixture PR、prototype branch は保持した。配備・push・PR作成・merge は行っていない。
