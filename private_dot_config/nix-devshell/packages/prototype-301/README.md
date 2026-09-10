# #301 ownership prototype

Throwaway branch: `prototype/301-browser-ownership`。このディレクトリは main へ取り込まず、chezmoi apply しない。

`ownership.html` をファイルとして開くだけで操作できる。インストール・サーバー・認証は不要。自由操作と4つのガイドで、worktree ごとの状態保持、古い終了要求の拒否、PR ごとの更新待ち、切断後の再接続、再認証後の待機要求の再開を確認する。状態はメモリ内だけに置く。

暫定判断: クライアント切断とブラウザ終了を別状態にし、終了確認と所有者世代の照合を要求するモデルを採用候補とする。同じ PR の更新だけを直列化する。認証待ちからの復帰も明示する。実機との適合性が未確認のため、本実装への反映は保留。

検証済み: inline JavaScript と実機 probe の構文、pure transition による4シナリオの実行結果、実機 probe の lint。A の状態を保持した世代2への再起動、B の継続、全添付要求の完了、再接続を確認。正式なテストスイートは追加していない。

画面の確認は未完了。通常の managed Chrome は別 worktree の `rop-analysis` が所有しており、CLI が起動を拒否した。既存セッションには接続・終了・変更していない。

## Windows 実機 probe（実行未承認・未実行）

`windows-probe.mjs` は Windows 側の一時 profile 2つ、headless Chrome、CDP 19431 / 19432、WSL のダミー HTTP origin 19433 を使う。独立 profile にダミー cookie と localStorage を保存し、同一 origin で分離されること、A の正常終了・再起動後にも状態が残り B が使えることを確認する。

既存 `../dogfood-chrome-windows.ps1` の Resolve / Inspect / Start のみを使用する。Cleanup は呼ばない。終了はこの probe が起動して CDP 接続を保持する対象への Browser.close と、その profile の停止確認による。未確定の起動は記録を残す。profile は削除しない。既存の認証 profile・所有権 record は変更しない。

`focus-observer.ps1` は90秒間、200ms間隔で前面 window handle とカーソル座標のみを読み取る。OS の入力・前面化 API は使用しない。出力先は実行ごとの `/tmp/prototype-301-<timestamp>/`。短時間の変化は見逃す可能性があり、人間の入力と区別できない。観測範囲が operations-start から operations-end までを覆っているか結果の時刻で照合する。変化がないという結果だけで一般的な無干渉保証とはしない。

この probe は独立 Chrome の分離と再起動を対象とし、Dogfood / Dashboard の共存と実 OAuth callback は検証しない。

実行は上記2つの PowerShell スクリプトに限って `-ExecutionPolicy Bypass` をプロセス単位で指定することへの承認後に行う。永続的な ExecutionPolicy 設定は変更しない。根拠: `runtime/skill-harness.md` の Model-invoked safety にある「権限拡大や permission bypass は推測せず」。現環境の Restricted による拒否を受けているため、別の呼出し方で迂回せず保留している。

承認後、Playwright core の導入済み module path を指定する:

```bash
PROTOTYPE_PLAYWRIGHT_CORE=/absolute/path/to/playwright-core/index.mjs \
  node private_dot_config/nix-devshell/packages/prototype-301/windows-probe.mjs --allow-process-policy
```

操作中はフォーカス観測の解釈を助けるため、可能なら約90秒、普段の画面をそのままにする。これは安全条件ではなく観測条件であり、操作した場合は結果を未確定として扱う。
