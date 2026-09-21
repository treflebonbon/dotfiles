# PROTOTYPE: 指定入力の隔離と次のdispatchの停止

問い: 現在のruntimeで、評価実行者に指定入力だけを渡し、入力監査が未確定・無効なら次のdispatchを止められるか。

**判定: 専用bubblewrapプロセスと、その起動入口では実証できた。通常のCodex子エージェントに同じ保証はない。LLM評価を隔離して完走したという実証ではない。**

## 実証結果

| 対象 | 観測 | 判定 |
| --- | --- | --- |
| 通常の子エージェント、履歴継承なし | 指定入力外の無害なcanaryを読み、SHA-256が一致 | 入力隔離なし |
| bubblewrapのPython worker | 指定3ファイルのhash一致 | 指定したデータ入力を読める |
| 同workerの禁止読取り | canary、Git HEAD、元の本文、過去結果、symlink、proc root、親ディレクトリ経由の7経路すべてENOENT | 試した経路からホストの資料を読めない |
| 書込み・環境 | 入力への書込みはEROFS、親環境のcanary変数は不在 | 入力はreadonly、環境はクリア |
| ネットワーク | ホストと異なるnetwork namespace | namespace分離を確認。通信先への接続テストは未実施 |
| 起動ゲート | 10ケース、有効監査に対応する2回だけ実workerを起動 | 未確定・無効・古い監査・実行中・入力追加で起動なし |

[evidence.json](evidence.json) はコマンド、許可入力のhash、workerの出力、終了コード、ケースごとの実起動数を保存する。[native-control.json](native-control.json) は通常の子エージェントの実行イベント抜粋と元transcriptの位置・hashを保存する。canaryは合成した無害な文字列で、機密情報を使っていない。

## 再実行と操作

Linux、Nix、Node.js、Python、bubblewrapがあるこの環境で、repo rootから実行する。

```sh
node docs/evaluations/prototype-input-isolation/probe.mjs
```

新しいscratchに証拠JSONを出力する。既存証拠は上書きしない。10ケースの照合に失敗すると非ゼロ終了する。最初の境界診断1回と、ゲート経由のworker2回は別に記録される。通常の子エージェントのnegative controlはこのコマンドでは再実行しない。

[prototype.html](prototype.html) を単独で開くと、自由操作と4つのガイドで状態を確認できる。HTMLは実プロセスを起動しない。実行runnerはHTML内の同じ純粋なゲートロジックを読み込む。`node:vm` はその読込みに使うだけで、隔離機構ではない。

## 実装した境界

親は指定3ファイルをscratchへコピーし、正規ファイル・hash・入力集合を確認する。子に見せるのはreadonlyの入力、診断用worker、PythonのNix依存closure、空の作業領域と新しいproc/devである。repo、home、全Nix storeはmountしない。診断用stdinには期待hash、禁止path名、ホストnetwork namespace識別子を渡す。したがって「3ファイルだけ」は評価用データの範囲であり、実行コードやOSライブラリまで不可視という意味ではない。

親が境界診断の実行証拠を照合してから監査を有効化する。dispatch直前にも入力集合・hashを再確認する。有効な監査を消費すると監査は未確定に戻り、完了後の次の起動には新しい監査が必要になる。無効な試行は停止状態を維持する。無効・未確定という状態の注入と、実際の入力追加による無効化を区別してケース名に記録した。

## 保証の限界と次の判断

- workerは決定的な診断プログラムであり、LLM評価実行者ではない。モデルへの認証・通信・ツール実行をこの境界内に接続するアダプターは未実装。
- ゲートはこの起動入口を通る呼出しにだけ効く。親が直接 `collaboration.spawn_agent` を呼ぶことは、これでは禁止できない。通常の子エージェントの可視範囲も変わらない。
- 親とホストは信頼する。悪意あるホストによるhash確認後のsnapshot差替えや、カーネル突破への耐性は検証していない。並行起動ケースは状態をrunningのまま再dispatchした確認であり、複数の親プロセス間の競合制御ではない。
- 実評価への採用条件は、LLMのデータ入力・ツールを隔離境界へ接続し、全dispatchをこの入口に集約して同じ検証を通すこと。このprototypeだけを根拠に過去評価を有効化したり再評価を再開したりしない。

本文と既存評価は変更しない。結果は `prototype/evaluation-input-gate` のローカルcommitに記録する。対応する実装issueは今回指定されていないため作成していない。

## 検証

実probeは10/10ケースを通過。HTMLの4つのガイドをChromiumで全操作し、最終起動数が順に2・0・1・1であること、キーボードによるタブ切替、自由操作での未確定監査の拒否を確認した。ブラウザ側のfile URL制限のため検証時だけloopbackの静的サーバーを使った。consoleのエラーは未配置faviconの404のみ。

`oxlint` と `oxfmt` を実行。開始時に記録した本文・既存評価239ファイルのSHA-256はすべて不変（[preservation.json](preservation.json)）。初回のOS診断は入力のmode 0400によるEACCESを期待したEROFSと区別して失敗したため、scratch側を0600にし、readonly mount自体によるEROFSを再確認した。
