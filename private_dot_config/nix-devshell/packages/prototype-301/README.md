# #301 ownership prototype

Throwaway branch: `prototype/301-browser-ownership`。このディレクトリは main へ取り込まず、chezmoi apply しない。

`ownership.html` をファイルとして開くだけで操作できる。インストール・サーバー・認証は不要。自由操作と4つのガイドで、worktree ごとの状態保持、古い終了要求の拒否、PR ごとの更新待ち、切断後の再接続、再認証後の待機要求の再開を確認する。状態はメモリ内だけに置く。

暫定判断: クライアント切断とブラウザ終了を別状態にし、終了確認と所有者世代の照合を要求するモデルを採用候補とする。同じ PR の更新だけを直列化する。認証待ちからの復帰も明示する。実機との適合性が未確認のため、本実装への反映は保留。

検証済み: inline JavaScript と実機 probe の構文、pure transition による4シナリオの実行結果、実機 probe の lint。A の状態を保持した世代2への再起動、B の継続、全添付要求の完了、再接続を確認。正式なテストスイートは追加していない。

画面の確認は未完了。通常の managed Chrome は別 worktree の `rop-analysis` が所有しており、CLI が起動を拒否した。既存セッションには接続・終了・変更していない。

## Windows 実機 probe（承認後に実行済み）

`windows-probe.mjs` は Windows 側の一時 profile 2つ、headless Chrome、CDP 19431 / 19432、WSL のダミー HTTP origin 19433 を使う。独立 profile にダミー cookie と localStorage を保存し、同一 origin で分離されること、A の正常終了・再起動後にも状態が残り B が使えることを確認する。

既存 `../dogfood-chrome-windows.ps1` の Resolve / Inspect / Start のみを使用する。Cleanup は呼ばない。終了はこの probe が起動して CDP 接続を保持する対象への Browser.close と、その profile の停止確認による。未確定の起動は記録を残す。profile は削除しない。既存の認証 profile・所有権 record は変更しない。

`focus-observer.ps1` は90秒間、200ms間隔で前面 window handle とカーソル座標のみを読み取る。OS の入力・前面化 API は使用しない。出力先は実行ごとの `/tmp/prototype-301-<timestamp>/`。短時間の変化は見逃す可能性があり、人間の入力と区別できない。観測範囲が operations-start から operations-end までを覆っているか結果の時刻で照合する。変化がないという結果だけで一般的な無干渉保証とはしない。

この probe は独立 Chrome の分離と再起動を対象とし、Dogfood / Dashboard の共存と実 OAuth callback は検証しない。

実行は上記2つの PowerShell スクリプトに限って `-ExecutionPolicy Bypass` をプロセス単位で指定することへの承認後に行う。永続的な ExecutionPolicy 設定は変更しない。根拠: `runtime/skill-harness.md` の Model-invoked safety にある「権限拡大や permission bypass は推測せず」。当初 Restricted による拒否を受けて保留し、その後ユーザーが対象と範囲を承認した。実行後も実効ポリシーは Restricted。

承認後、Playwright core の導入済み module path を指定する:

```bash
PROTOTYPE_PLAYWRIGHT_CORE=/absolute/path/to/playwright-core/index.mjs \
  node private_dot_config/nix-devshell/packages/prototype-301/windows-probe.mjs --allow-process-policy
```

操作中はフォーカス観測の解釈を助けるため、可能なら約90秒、普段の画面をそのままにする。これは安全条件ではなく観測条件であり、操作した場合は結果を未確定として扱う。

## 2026-09-11 実機結果

承認済みの2スクリプトへのプロセス限定指定で実行し、終了コード0。実行前のコード確認で、ブラウザへ渡す dummy 引数を cookie の値にも使用するよう修正した。lint だけでは page.evaluate 内の別実行環境への変数参照を検出できなかった。

- 同一 origin で独立した2つの profile の dummy cookie / localStorage が混ざらないことを確認。
- A の正常終了・再起動後に cookie / localStorage が残り、B が継続利用できることを確認。
- 2つの Chrome の終了を profile ごとの Inspect で確認。profile は保持。
- 約90秒、436 sample で前面 window handle は1種類。Chrome 操作区間約21.4秒の104 sample でも同一。今回の標本では前面の切替を観測しなかった。
- カーソル読取り失敗0。位置は全体15種類、操作区間5種類。人間の操作の有無が未確認のため、カーソルへの無干渉は未確定。短い前面切替の見逃しも排除できない。

集計は `windows-result-summary.json`。raw evidence は `/tmp/prototype-301-1789084461708/` の results.json / focus-samples.json。観測区間は Chrome 操作の開始前から終了後までを覆う。生の window handle / cursor 座標を GitHub へ公開せず、集計だけを保存する。

独立 profile と状態保持はこの環境で成立したため採用候補を支持する。Dogfood / Dashboard 共存とカーソルへの影響が未確定のため、#301 の ready-for-agent 化と本実装への反映は引き続き保留。

## 2026-09-11 再観測

Q7 の回答は「前回のマウス操作は覚えていない」。操作を控える観測条件を案内し、同じ承認範囲の probe を再実行した。profile 分離・再起動後の保持・両 Chrome の停止は再度成功。

436 sample 全体で前面 window handle は同一。Chrome 操作区間（00:22:23.499Z–00:22:45.634Z、約22.1秒）の107 sample では cursor 座標も同一で、読取り失敗は0。全90秒では14種類の cursor 位置があり、変化は操作区間外だった。今回の操作区間で干渉は観測されなかったが、200ms未満の変化や未試験の Dashboard 操作を保証しない。

集計は windows-result-repeat-summary.json、raw evidence は /tmp/prototype-301-1789086142063/。Q6 は「別 identity は並列、同一 identity のモード競合は既存 consumer を保持して拒否」で合意。新構成の共存試験を本実装の必須受入条件へ移すかは Q8 で確認中。

## Triage 確定

Q8 は推奨案で合意。新構成の Dogfood / Dashboard 共存を本実装の必須受入試験へ移し、#301 の Agent Brief を確定する。先行結果は実装の成立見込みを支えるが、本実装での AC 検証を代替しない。上の Q8 確認中・needs-triage は当時の記録。prototype 全体はこの branch に保持し、main へは検証済みの判断だけを取り込む。
