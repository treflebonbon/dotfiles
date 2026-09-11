---
type: research
title: WSL の一時送信ポート範囲と Windows Chrome の CDP 復旧
---

# WSL の一時送信ポート範囲と Windows Chrome の CDP 復旧

2026-09-11、#307 のマージ・配備後の確認で、task worktree に割り当てた47858番へ CDP 接続できなかった。Chrome は指定 profile / headless / port 引数で稼働していたが、Windows / WSL のどちらからも `/json/version` に接続できなかった。

## 観測

- Linux の `/proc/sys/net/ipv4/ip_local_port_range` は44620–48715。
- Windows の loopback TCP bind は44619・48716で成功、44620・45000・47858・47860・48715で `AddressAlreadyInUse`。境界が Linux の一時送信ポート範囲と一致する。
- Windows の Get-NetTCPConnection / netstat に47858の listener はなく、IPv4 / IPv6 の明示 excluded port range にも含まれなかった。通常の listener 一覧だけではこの利用不能状態を検出できない。
- この実機結果は WSL mirrored networking による範囲の利用制約と整合する。Windows 内部で予約を管理する具体的なコンポーネントは特定していない。

## 修正と復旧契約

新しい worktree 割当は、現在の Linux 一時送信ポート範囲と CDP / Dashboard の両方が重ならない候補を選ぶ。既存割当を自動変更しない。

既存割当には `managed-chrome-owner relocate --role playwright --workspace <physical-root> --identity <exact-identity>` を追加した。登録 lock 内で、正確な既存 identity・所有権記録なし・旧 profile / port に Chrome なしを確認してから、その identity の port pair だけを更新する。profile と他 identity は保持する。残存予約、稼働 Chrome、照会失敗は拒否する。

47858番の今回の Chrome は CDP による終了ができず、照合した対象 PID への `CloseMainWindow` も false。ブラウザ強制終了は #301 の承認対象外のため、自動終了や所有権の強制削除は実行していない。この専用プロセスの終了について個別承認後、正規 recover → relocate →実機再検証を行う必要がある。既存の Dogfood starting 記録は別件であり変更しない。

## 検証

- 新規回帰2件は修正前に失敗、修正後に成功。所有権21件、Dogfood10件、添付2件、to-pr27件の計60件成功。
- lint と Nix package build 成功。実機で使った package は `/nix/store/ksb8z3lg505ban33wq7pd2sqg5c47iqb-playwright-cli-0.1.19`。
- 隔離 Git fixture の旧候補48020は利用不能範囲内。修正版で CDP48716 / Dashboard48717へ割り当てられることを確認。
- その fixture で headless open、証跡ディレクトリ A での title 設定、B での title 照合・撮影・close がすべて成功。終了後の当該 ownership は null。
- Session Scratchpad が提示されていないため `${TMPDIR:-/tmp}` fallback を使用。実機ログ・画像は `/tmp/nix-shell.2VWWVm/nix-shell.5ocIC6/nix-shell.Cr560r/browser-port-recovery.ezribsdv/`。一時資料の永続保存は保証しない。
- ここでの成功は隔離 fixture の結果。元の worktree の復旧完了や OS フォーカスの再測定を主張しない。未マージ source から chezmoi apply は実行していない。
