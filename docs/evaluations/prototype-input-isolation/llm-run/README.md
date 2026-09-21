# PROTOTYPE: 実LLMを使った入力隔離と起動停止

**判定: この専用起動経路で、実LLMの1セッションを使った3条件を確認した。通常の子エージェント全体への強制や、評価プロトコルへの統合は行っていない。**

| 条件 | 実測と照合 | 結果 |
| --- | --- | --- |
| 指定入力で課題完了 | ツール出力に指定3ファイルの全文が含まれることを親で照合。最終回答はViewとMediatorの責務を正しく区別 | 確認 |
| ツール経由の入力外読取り拒否 | ホストに実在する合成canaryをLLMがshellツールから開き、`No such file or directory` と `READ=failure shell_status=1` | 確認したcanary経路で拒否 |
| 未確定・無効なら次回起動停止 | 初回前の未確定で0→0、終了後の未確定で1→1、無効で1→1。ゲートはそれぞれ拒否状態 | この入口で確認 |

Codex CLI 0.154.0 / `gpt-5.6-terra` / highを使用。**1セッション、モデル応答5回、shellツール呼出し4回**である。「1回」は評価実行者のセッション数であり、モデルへのHTTP要求1回ではない。

一次証拠は [evidence.json](evidence.json)。起動引数、prompt、許可入力hash、CodexのJSONLツールイベント、終了コード、gatewayの成功応答数とHTTP status、ゲート状態を記録する。[verdict.json](verdict.json) は親による照合結果。errnoの数値2はエラーメッセージからの推定であり、syscallが数値を直接出力した証拠ではない。

## 再利用したもの

- [既存HTML](../prototype.html) 内の純粋なゲートをそのまま読み込む。自由操作とガイドも既存HTMLを使う。
- 既存prototypeの本文・referenceを、新しいscratchのreadonly入力へコピー。今回の小課題だけ [task.txt](task.txt) に差し替えた。元ファイルには変更なし。
- repo既存の `private_dot_local/share/codex-isolation/secret-isolation-gateway.py` を利用。ChatGPT認証はホストの既存gatewayだけが扱い、隔離側へauthファイル・鍵・ホストHOMEを渡さない。gatewayはモデル用endpointだけを中継し、remote toolや既存conversation参照を拒否する実装。
- bubblewrapでfilesystem・PID・networkを分離。指定入力、Codex/Python/bash等のNix依存closure、起動コード、モデルgatewayのUnix socketだけを公開する。Codex自身のshell sandboxはread-only、承認方針はnever。権限を回避するオプションは使わない。

## 再実行

このLinux/Nix環境と既存のChatGPTログインで、repo rootから実行する。実行ごとに新しいモデルセッションが1つ発生する。

```sh
python3 docs/evaluations/prototype-input-isolation/llm-run/probe.py
```

新しいscratchへ証拠を保存し、既存証拠は上書きしない。認証・起動・通信が利用できなければ `runtime_unavailable` として終了する。正常終了の `requires_evidence_review` は課題の合格判定ではなく、親が実際のツール出力と回答を照合する段階を表す。

## 観測した制約

- 最小runtimeに `rg` / `sed` がなく、最初の2ツール呼出しはexit 127。3回目はshell builtinで3ファイルを読めたが、末尾の `compgen` がなくexit 127になった。親は終了コードだけでなく、出力が入力全文を含むことを照合した。4回目がcanaryの読取り拒否確認。課題は完了したが、通常評価用のツール集合として十分とは判定しない。
- 同一セッション内の5回のモデル応答は許可した。今回のゲートが制御するのは次の評価セッション開始であり、すべてのモデルHTTP要求を個別承認する仕組みではない。
- 監査未確定・無効は明示的に注入した状態である。前の評価の全transcriptから入力監査を自動確定する実装はまだない。起動数はcontrollerの計数と起動コード・Codexイベントによる照合であり、独立したOS全体のプロセス監視ではない。
- 親が別経路から起動することを禁止する全runtime共通の制御ではない。通常の `collaboration.spawn_agent` にこの保証を拡張しない。ホストは信頼し、悪意あるホストのsnapshot差替えやカーネル突破は対象外。
- 「指定入力だけ」は評価用データの範囲。モデル固有の基本指示、実行コード、OSライブラリ、今回明示した課題・canary pathは追加の実行用入力として存在する。

本文、過去評価、前回prototypeを含む既存249ファイルのSHA-256はすべて不変。前回の成果物は当時の結論として維持し、今回の結果だけをこのディレクトリへ追加した。`prototype/evaluation-input-gate` のローカルcommitを一次資料として残す。対応issueは指定されていない。

次に実評価へ採用する場合は、この起動経路へ評価dispatchを集約し、評価契約から指定入力manifestと課題を渡し、実行証拠に基づく監査結果を次回起動の前提へ接続する。今回の実証はMVPスキルの再評価・採点を含まない。
