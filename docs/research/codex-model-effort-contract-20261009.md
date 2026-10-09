# 隔離 Codex の model／effort 指定と有効値確認

2026-10-09。状態: task worktree で実装・検証済み、未配備。以下の現状・合意記録は設計時点のもの。実装結果は末尾を参照する。

`grill-with-docs` の `grilling`／`domain-modeling` を適用した。ユーザーの「質問は Herdr pane Codex と協働、human out the loop」という委任に従い、初回は Herdr workspace `w1Z` の pane `w1Z:p1` に起動した Codex と3ラウンドで合意した。その後の Claude レビューで出た入力解釈と引継ぎ手順の2点を、同じ pane の新しい隔離 Codex で readiness 確認後に2ラウンドで詰め、本書へ反映した。

## 問題と確認した現状

隔離起動の `--model gpt-6-luna` は通るが、effort を指定する `-c 'model_reasoning_effort="xhigh"'` は拒否される。前回の設計相談では指定を外して起動し、必要な `xhigh` に対し実際は `high` だった。引数を渡せたことと、その設定で動いたことを区別する必要がある。

- [共用 validator](../../private_dot_local/share/codex-isolation/codex-inner.py) は `--model`／`-m` を通し、`-c`／`--config` を一律拒否する。[outer launcher](../../private_dot_local/share/codex-isolation/secret-isolation-worktree.py) と inner の両方がこの関数を使う。
- inner は root、permission profile、隔離 provider、network 設定を固定してから caller の argv を追加する。任意の config を許すと、後続引数から管理設定を上書きできる。
- `codex-worktree` のほか、`codex-orca`、linked worktree の `codex-context`、bun wrapper が関連する。既存の model 転送テストはあるが、明示 effort を使う既存 caller は今回の検索では見つからなかった。
- 導入版 Codex CLI 0.161.0 の生成スキーマでは、`ReasoningEffort` は空でない文字列であり固定 enum ではない。モデルごとの対応値は `model/list` の `supportedReasoningEfforts` が示す。
- 公式 app-server は `thread/start` の model と config、`turn/start` の model／effort を受け取る。`thread/start` 応答には model／reasoningEffort があるが、`turn/start` 応答だけでは有効値を確認できない。
- 一時的な `CODEX_HOME` で `config/read` を実測すると、`model_reasoning_effort="xhigh"` と空白付きの裸キーは反映されるが、`"model_reasoning_effort"="xhigh"` は既定の `high` のままだった。TOML 文書としては同じキーに解決されるため、文書全体の意味だけで許可してはいけない。
- raw 起動は毎回新しい隔離用 directory と `CODEX_HOME` を作る。持ち込む設定は `config.toml` と任意の `AGENTS.md`／`rules/default.rules` で、過去の rollout は移送しない。別の raw 起動の `exec resume` による会話継続を前提にできない。

## 合意した契約

対象は raw [Runtime Adapter](../../GLOSSARY.md) の呼び出し単位の明示指定と、app-server 経路で親が行う引継ぎ前の確認。CLI の引数指定機能は実装対象に残し、CLI 自動引継ぎは未対応とする。既存の working root、Active Git Metadata Boundary、permission、provider/gateway、network、secret isolation の境界を維持する。

「指定値」は caller が要求した model／effort、「有効値」は対象 session/thread で Codex runtime が解決した値とする。新しい domain entity は設けず、一般語である両者を GLOSSARY に追加しない。可逆な局所変更なので新しい ADR も作らない。既存の [ADR-0044](../adr/0044-runtime-owned-worktree-entry-and-codex-activation.md) と [ADR-0057](../adr/0057-retire-to-worktree-for-native-entry.md) の境界に従う。

「隔離起動単位」は raw 起動一回で作る process と隔離用 directory、「Codex thread」は会話と runtime 設定を継続する単位として区別する。本書で引継ぎに必要な「同じ session」は、同じ隔離 process と Codex thread ID の継続を指す。同じ Git worktree／branch にいることだけでは満たさない。

### CLI 入力

既存の `--model`／`-m` を維持し、config のうち `model_reasoning_effort` 一つだけを狭域許可する。

```bash
# task worktree で実装する契約。live source への反映は受入後に行う。
codex-worktree --model gpt-6-luna -c 'model_reasoning_effort="xhigh"'
```

`-c VALUE`、`--config VALUE`、`--config=VALUE`、`-cVALUE` を対象にする。ここで VALUE は `key=value` 全体であり、右辺は最初の `=` より後の部分を指す。

1. VALUE を最初の `=` で分割する。左辺の前後空白を除いた文字列が、引用符のない `model_reasoning_effort` と完全一致することを先に検査する。
2. 右辺を固定の仮キーに束縛して TOML として解析する。結果のキー集合がその仮キー一つだけで、値が空でない文字列のときに許可する。仮キーは検証用であり、Codex へ渡す argv は変更しない。
3. 有効値との比較には、TOML から復号された文字列を使う。たとえば `"xh\u0069gh"` の指定値は `xhigh` である。

TOML の basic／literal string、通常の空白、escape、末尾コメント、複数行文字列は、解析結果が一つの文字列だけなら受理する。文字列内の改行と、文字列外に別キーを作る改行を区別し、後者は拒否する。値の文字集合を独自 regex で狭めない。

2トークン形式の `-c`／`--config` は次のトークンを値として検査する。次が `--` や別 flag の場合も、値欠落・不正な入力として拒否し、検査を飛ばす境界にはしない。末尾で値がない場合も拒否する。Codex 自体が受理する `-c=VALUE` は、今回の許可対象に含めず拒否する。

未引用の `model_reasoning_effort=xhigh` は TOML として不正なので拒否する。Codex 独自の raw-string fallback は取り込まない。固定 effort enum や model catalog 問い合わせを validator に追加しない。未知の quoted string が構文上受理されても、そのモデルが対応すると保証するものではない。

以下は outer の初期化前に拒否し、inner でも同じ validator によって再検証する。

- 値の欠落、空文字、文字列以外の型、不正な TOML。
- 引用符付きのキー、別キー、追加キー、dotted key／table による偽装、文字列外の改行で追加した権限設定。
- effort の複数 flag 指定。同じ値でも拒否する。既存の model 指定の重複仕様は変えない。
- 従来拒否していた root、permission、provider、network、trust、bypass の変更。

config の値を待っていない位置の `--` の後は、従来どおり prompt／子コマンドの引数として扱う。残りの argv、空引数、空白を含む引数を保存し、文字列の再結合や shell 評価を追加しない。effort 省略時は現行 managed config の挙動を維持する。

| 比較案 | 判断と理由 |
| --- | --- |
| 公式 CLI の effort config 一キーだけを許可 | 採用。共用 validator の局所変更で CLI caller に届く。 |
| app-server だけを使い、CLI は変更しない | 現在の相談には利用できるが、CLI exec／TUI caller の問題が残り、利用側に RPC client を要求する。 |
| adapter 独自の `--reasoning-effort` を追加 | 独自 flag の変換と二段階検証が増えるため採用しない。 |

### 引継ぎ前の有効値確認

これは親が行う workflow gate であり、adapter による有効値の自動強制ではない。app-server での確認手順を次の順序に固定する。

1. 対象 worktree の root／Git 所属を確認する。同じ隔離 process の `thread/start` で model と `config.model_reasoning_effort` を指定し、応答の thread ID、model、reasoningEffort、modelProvider、cwd を記録して照合する。起動 argv、config の宣言値、子の自己申告だけを証拠にしない。
2. 同じ thread に実タスクを含まない readiness turn を送り、読み取りで root／branch／HEAD／Git dir／common dir を確認させる。実応答と `turn/completed` の成功を確認する。必要なら `model/list` を診断に使う。
3. 起動 stderr に表示された隔離 session directory の `config/sessions/` 配下から、その thread ID に一致する rollout を選ぶ。`turn_context` の model／effort／cwd だけを抽出し、指定値と対象 root に一致することを確認する。
4. 設定の一致とモデル応答の成功を別の証拠として残してから、同じ process/thread に実タスクを送る。実タスクの `turn/start` では model／effort を省略するか、readiness と同じ値を指定する。不一致、観測不能、未対応の場合は渡さず、黙って `high` などに変更しない。

別 session の probe 成功は対象 session の証拠にならない。設定を変えた場合や thread／process を変更・resume した場合も、新しい readiness とメタデータで確認をやり直す。古い `thread/start` 応答だけを流用しない。

| 経路 | 本設計の対応範囲 |
| --- | --- |
| app-server の同じ process/thread | 設定確認・readiness・限定設計相談を実測済み。実装タスクを含む引継ぎ全体の検証は次段階の受入条件に残す。 |
| CLI の model／effort 引数指定 | 本設計の実装対象。引数を受理することだけで自動引継ぎ対応とはしない。 |
| CLI 自動引継ぎ | 未対応。同じ TUI process での有効値観測、readiness から実タスクへの継続、Herdr の agent 認識と入力可能状態を実測するまで対応済みにしない。 |
| 別 raw 起動の `exec resume` | 対応経路にしない。過去の rollout を共有・移送する機構は追加しない。 |

最初の単発 exec に本タスクを入れて終了後に有効値を調べる運用は gate を満たさない。CLI の未検証手順を、TUI status を読めばよいという説明だけで対応済みにしない。

確認できるのは Codex runtime の有効設定とモデル応答の成功までであり、バックエンドの推論計算量そのものは保証しない。session 記録を読む場合は必要なメタデータだけを抽出し、hidden reasoning や認証情報を読まない。

## 次の実装段階の範囲と受入条件

| 対象 | 変更・検証する内容 |
| --- | --- |
| `private_dot_local/share/codex-isolation/codex-inner.py` | 共用 validator に上述の effort 一キーの許可を追加。outer／inner の二重検証を維持する。 |
| `tests/codex-config.bats` | 正規4形式、裸キー・引用キー、TOML string の復号、値欠落・型違い・追加キー・改行注入・重複・`--` を検証。既存の危険引数拒否と model 転送を維持し、既存 caller 経由の effort 転送も確認する。 |
| `tests/raw-codex-integration.bats` | model と quoted effort が隔離側の実 Codex に届くこと、および固定 root/profile/provider/network、承認設定、秘密隔離が維持されることを確認する。app-server の同じ process/thread で確認後に本タスクを渡す順序を検証する。hosted model test は明示 opt-in のままにする。 |
| `runtime/skill-harness.md` | raw adapter の許可引数と同一 session の引継ぎ gate を、対象箇所に必要最小限で記録する。 |

構文上の許可／拒否をネットワーク不要のテストで確定し、隔離統合で有効設定を確認する。起動 stderr の隔離 session directory 表示と、その `config/sessions/` に対象 thread の記録があることも観測点として検証する。引継ぎ gate は一致・不一致・観測不能・古い session 証拠の各ケースで確認し、不一致では実タスクを投入しない。正常時の quoted effort 指定と既存の境界拒否が両立することを完了条件とする。

構文の境界ケースには、次を含める。

- `"model_reasoning_effort"="xhigh"` と `'model_reasoning_effort'="xhigh"` は拒否し、`model_reasoning_effort = "xhigh"` は許可する。
- `-c --`、末尾の `-c`、`-c=VALUE`、effort の後に置いた別キーの config は拒否する。effort を複数 flag で指定した場合は、同じ値でも異なる値でも拒否する。
- escape・末尾コメント・複数行文字列が単一の文字列へ解決する場合と、右辺の後に追加キーを作る場合を分け、後者を拒否する。
- 正規 effort の後に `exec -- '-c sandbox_mode="danger-full-access"'` がある場合、`--` の後の一引数は prompt として保存され、設定変更として再解釈されないことを確認する。

role に応じた自動 model 切替、managed config の恒久変更、Orca built-in の変更、新しい production RPC client、公開入力の自動登録は対象外。承認経路の修正 `e1d7051` は別 worktree の変更であり、本設計へ混ぜない。

## 今回の検証と合意記録

- host と子の双方で、root `/home/ubuntu/.herdr/worktrees/dotfiles/research-codex-model-effort-contract`、branch `research/codex-model-effort-contract`、開始 HEAD `05f78b1b3d814cfc06aba9eb12f4b25b4c3448af`、worktree Git dir と common dir の所属を確認した。
- Herdr pane の一時的な stdio client から `codex-worktree app-server --stdio` を起動した。公開入力は列挙して登録し、秘密や Herdr socket を隔離内へ渡していない。
- `thread/start` 応答で `model=gpt-6-luna`、`reasoningEffort=xhigh`、`modelProvider=isolated`、対象 cwd の一致を確認してから第1ラウンドを送った。同じ session の全3 turn の `turn_context` でも `model=gpt-6-luna`／`effort=xhigh` を確認した。3回とも実応答が成功し、隔離 Codex は exit 0 で終了した。
- 第1ラウンドで範囲・境界・成功条件・用語、第2ラウンドで CLI・確認手順・文書化、第3ラウンドで境界ケースと完了条件を確定した。Codex は最終回答で「共有理解に合意。未解決事項なし」と回答した。
- 一時 client・質問・回答・有効値の証拠は、この worktree の Git 管理外 `tmp/design-model-effort/` に保存した。これは調査用であり、配布する runtime component ではない。

Claude レビュー後の追補では、次を確認した。

- auth とモデルリクエストを使わない一時 `CODEX_HOME` の `config/read` で、引用キーが反映されない差と、値側の引用・空白・escape・コメント・複数行文字列が反映されることを実測した。追加キーを伴う入力は Codex が effort を使っても adapter 側で拒否する契約とした。
- `thread/start` の `config.model_reasoning_effort` で指定した隔離 Codex を起動し、最初に実タスクを含まない readiness turn を完了した。同じ thread の `turn_context` と起動応答で `gpt-6-luna/xhigh`、provider `isolated`、対象 cwd を確認してから設計質問を送った。
- 追補2ラウンドで入力解釈と引継ぎ範囲・ACに合意し、Codex は未解決の設計判断がないことを確認した。質問・回答・追試結果は `tmp/design-model-effort-followup/` に保存した。

設計段階ではこの文書だけを更新し、runtime 実装、commit、PR 公開、merge、`chezmoi apply` は行わなかった。

## 実装と検証

同じ task worktree で共用 validator に effort 一キーの許可を追加した。outer の初期化前と inner の再検証を維持し、caller の argv は変更しない。既存 caller の本体は変更不要で、`codex-orca` と bun → `codex-context` → adapter の転送を回帰テストで確認する。

通常の隔離試験ではダミー認証を gateway の起動条件だけに使い、実モデルへの要求を送らず `config/read` の復号値と `thread/start` 応答を確認する。app-server の model は `thread/start.model` に指定する。CLI の top-level `--model` の値だけを app-server の thread 選択の証拠にしない。

既存の hosted model opt-in 試験を、同じ process/thread の readiness と記録確認後に本タスクを送る手順へ更新した。試験用 stdio client は `tests/helpers/raw-codex-handoff.py` に置き、production runtime には配布しない。不一致、readiness 記録なし、別 thread の古い証拠では確認を通さず、本タスクの出力がまだ存在しないことを確かめる。正常時は実モデルが公開 `task.sh` を実行し、編集・テスト・commit・host への返却まで確認する。

運用の正本は [開始と復旧](../../runtime/skill-harness.md#worktree-の開始と復旧)。gate は親の手順であり、自動 enforcement や CLI 自動引継ぎを追加したものではない。承認設定の別修正、公開・merge・`chezmoi apply` は対象外のまま維持する。

### 検証結果

- 最初の受入試験は現行 validator の `-c` 拒否で失敗し、共用 validator の修正後に成功した。試験では認証を要求しない `--version` を先頭に置く。引数先頭から gateway の起動要否を判断する既存仕様は変更していない。
- 関連2ファイルは計画72件と全結果行が一致し、70成功・2 skip・失敗0、終了コード0。4形式、TOML string、危険入力拒否、caller 転送、実 Codex の設定・隔離境界を確認した。
- hosted model opt-in は `SECRET_ISOLATION_REAL_MODEL=1` で実行し、1件成功、終了コード0。Git 所属の全項目を照合した最終版も成功した。同じ thread の readiness と本タスク双方で `gpt-6-luna/xhigh` の記録を確認し、編集・テスト・commit の host 返却まで通った。
- 全体試験の `lefthook run test` は既存 zsh 試験の `fzf` ダミーが初期化時に TTY 入力を待つため中断した。`--no-tty` でも job の入出力が TTY となることを確認し、その試行も中断した。両試行は終了コード143であり、成功した全体試験として数えない。
- lefthook と同じ定義の `bun run test < /dev/null` を直接実行した全体試行は、TAP 計画748件と結果748行が一致。716成功・22 skip・10失敗、終了コード1。前述の zsh 試験は通過した。
- 全体試行の10失敗は、host PATH の `with-env` が Nix store の package でない1件と、選ばれた Python に `python-dotenv` がない9件。該当コード・試験は今回変更していない。`nix build .#with-env --no-link --print-out-paths` で得た package と、同じ flake が使う依存込み Python を PATH に加え、`human-validation.bats` は1成功、`with-env.bats` は18成功・2 skip、双方終了コード0。失敗10件を含む両ファイルの再検証で失敗は残らなかった。全体試行と再実行は別の結果として扱い、環境を整えた全748件の一括再実行は省略した。
- `tsc --noEmit`、変更 Python の構文検査、`git diff --check`、Markdown format、通常の commit hook が成功した。secret scan は検出0。`code-review` の独立した Standards／Spec 両軸は、基点 `05f78b1` から実装 commit `f2b1de2` までを確認して各0件だった。

試行ログは Git 管理外の `tmp/implement-model-effort/` に分離して保存した。opt-in の未実行項目は skip のままであり、実行済みとして数えていない。
