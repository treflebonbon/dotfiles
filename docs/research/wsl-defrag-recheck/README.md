# defrag_mode=1 の起動後再検証（完了）

ユーザーが `.wslconfig` に `kernelCommandLine=sysctl.vm.defrag_mode=1` を追加して WSL を再起動した。agent は新 boot ID、起動引数、実値1を確認して検証した。agent による追加の共有設定変更、compaction、再起動はない。

全テストは700成功・22スキップ・失敗0、終了コード0。Rust・Elixir・Perl は各3システム評価、devShell、with-env、環境変数の隔離、実 raw entry 内の実行・テスト・コミット・再起動まで成功、終了コード0。テンプレートの固定入力は前回と一致。

Node / Python は PowerShell の起動元であり、いずれも実行対象は `powershell.exe`。以下の5試行、合計1,256回すべて成功。元の vsock タイムアウト・別エラーとも0件。全テストと言語テンプレート終了後の実 Dogfood は直列10回・4並列40回、計50回すべて成功。起動・CDP 接続・終了処理を含む。

| summary の probe ID | 起動元・負荷条件 | PowerShell 成功回数 | 並列数 | 終了コード |
| --- | --- | --: | --: | --: |
| `node-idle` | Node、無負荷 | 64 | 64 | 0 |
| `interop-loaded-1000` | Node、全テスト・テンプレートの負荷中 | 1,000 | 32 | 0 |
| `node-loaded-64` | Node、負荷中 | 64 | 64 | 0 |
| `python-loaded-64` | Python、負荷中 | 64 | 64 | 0 |
| `node-loaded-late-64` | Node、空きメモリが減った段階 | 64 | 64 | 0 |

各試行の `vsock110` と `other` は0。合計は `64 + 1,000 + 64 + 64 + 64 = 1,256`。Dogfood の直列10回・並列40回は別集計で、この合計には含めない。

kernel order-7 allocation warning は開始前0件・終了後0件。共有 VM の activity counter 差分は summary.json に保存。これらは回数であり、待機時間や設定変更の効果量ではない。mode0 の fresh-boot 対照は今回取得していないため、再起動の効果と設定の効果、性能への影響は分離できない。設定後の再検証は成功したが、恒久修正の証明とは扱わない。

このディレクトリの [summary.json](summary.json) は再検証時の集計を変更せず保存したもの。各試行の成功・失敗数と終了コード、全テスト・テンプレートの終了結果、kernel warning 数と VM counter 差分を収録する。生の .log / .exit、kernel / memory 記録、Dogfood 50試行の evidence は元の `tmp/wsl-defrag-recheck/` に保存しており、Git 管理対象外で別の clone には含まれない。

Nix は起動直後の systemd 初期化待ちで一度接続不能だったが、サービスを変更せず初期化完了後に接続できた。最初の Node 試行は起動時に消えた /tmp harness の不足で実行できず、node-idle-invalid-harness.* に保存した。保存済み harness を復元して有効な検証を開始し、これらの準備時の失敗は product failure の集計に含めていない。

対象 HEAD は c2c638de10219967a08e2591f2b888c18249ec0b。boot ID は df0a6e66-e109-4fd8-bdf1-d6dab73e9d48。WSL 3.0.1.0 / kernel 6.18.40.1-microsoft-standard-WSL2、Nix の Node 24.21.0 / Bun 1.4.2 / gh を確認済み。検証はすべて終了した。この証跡追加のための共有設定変更、追加再起動、再検証は行っていない。
