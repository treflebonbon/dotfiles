---
type: decision
title: 通常の調査コマンドを hooks で安全な実行経路へつなぐ
description: 通常の gcloud の単独呼出しを hook で gcloud-inspect へ接続し、既存の調査許可と機密項目の除外を維持する
tags: [adr, codex, claude-code, permissions, gcloud, github, hooks]
timestamp: 2026-10-19
status: accepted
---

# 通常の調査コマンドを hooks で安全な実行経路へつなぐ

通常の Claude Code と Codex が `gcloud-inspect` を認識せず、許可済みの調査にも進めない可能性が指摘された。現行の共通指示には入口の案内があるが、認識不足による失敗の再現は未確認である。`gcloud` / `gh` を使おうとした場面で hooks により検査・案内する方式を採用する。

## 合意済みの目標と境界

2026-10-19 の `grill-with-docs` 第1ラウンドで、ユーザーは次の2点の推奨案を採用した。

- エージェントが専用コマンドを知らなくても、通常の `gcloud` / `gh` で許可済みの調査を完了できることを目標にする。拒否後の案内だけで完了とせず、安全な実行経路への接続方法を設計する。
- 変更対象は案内と実行経路とし、調査操作の許可範囲、秘密値取得の禁止、既知の機密項目の除外、既存の書込み承認ルールを維持する。`gh` の依頼済み定型書込みも維持し、`gh api` などの要確認操作は引き続き確認する。

[ADR-0073](0073-allow-investigation-commands.md) の権限境界を引き継ぐ。通常の Claude Code と Codex の共通設定を対象とし、raw 隔離版の認証・通信境界は変更しない。ADR-0073 の実行手順は置き換えず、通常の `gcloud` から `gcloud-inspect` への接続を追加する。

第2ラウンドで、初回に対応するコマンド形式についても推奨案を採用した。

- 初回は `gcloud` / `gh` を直接1回呼ぶ単独コマンドを確実に扱う。対象 CLI を含む複合 shell（`cd repo && gh pr view 42`、`gcloud logging read ... | jq ...`、コマンド置換を含む呼出しなど）は、単独の呼出しへ分けるよう案内する。複合形式の解析は、実際に必要な例が出た時点で追加を検討する。

第3ラウンドで、書換え方針について推奨案を採用した。Codex への設計相談（読み取りのみ、helper のスタブ検証9件を含む）の指摘を取り込んでいる。第2ラウンドの複合形式への案内は、このラウンドで `gcloud` のみに変更した（`gh` の項を参照）。

- 設計判断として、許可リスト・引数検証・出力の機密項目の除外は `gcloud-inspect` に集約し、書換え先は `gcloud-inspect <args>` だけにする。hook に許可リストを複製せず、`--reviewed` も付けない。
- 判定順は次のとおり固定する。
  1. 実行位置と、対応するリテラル構文かを判定する。
  2. 引用符・エスケープを解釈して引数列を確定する。
  3. 確定した第1引数が `--reviewed` なら deny する。
  4. 残った入力は、操作の自動許可可否を判定せず `gcloud-inspect <args>` へ書換える。許可の可否は helper に任せる。
- 「判定しない」は、操作の許可可否を判定しないという意味に限る。単引用符内の文字列は展開として扱わないが、引数の確定後の検査は免除しない。文字列中に `gcloud` があるだけの入力（`echo gcloud` など）は、実行位置にないため対象外とする。
- `gcloud` の実行と認識できても安全に書換えられない入力は、素通しにせず deny する。対象は複合 shell、`"$(...)"`・`$ARGS`・バッククォート・`<(...)` などの展開、先頭の `NAME=value` 代入、リダイレクト、入力由来の先頭 `--reviewed` である。理由は入力の種類に合わせる。
  - 複合 shell: 単独の呼出しへ分ける案内。
  - 展開・代入・リダイレクト: リテラル引数だけの単独呼出しにする案内。
  - 先頭 `--reviewed`: 人への確認後に、既存の明示的な `gcloud-inspect --reviewed …` を使う案内。
- 「リテラル引数」は、単引用符・二重引用符（展開を含まないもの）・バックスラッシュのエスケープだけで構成され、空引数や引用部分と非引用部分の連結を含んでよい引数を指す。glob、tilde（引用符なしの `~` は位置を問わない）、brace expansion、算術展開、変数展開、コマンド置換、改行、コメントを含む引数は展開または未対応の構文として扱う。末尾の空白・改行は無視する。受理例・拒否例は単体テストで固定する。初回から対応範囲は広げない。
- `gcloud` と認識した後に未対応の引数構文へ遭遇した場合は、hook の異常終了ではなく deny とする。
- 書換え後も、確定した引数列を空引数・空白・メタ文字を含めて保存し、引数の内容をシェル構文として再解釈させない。例えば `gcloud projects list '--filter=$(printf PROBE)'` は、書換え後も `$(printf PROBE)` が文字列のまま helper に渡る。
- 初回の「認識できた」の対象は、`gcloud` を実行名とする単独の単純コマンドと、上記の deny 対象とする。コマンド位置は、先頭、演算子（`&&`・`;`・`|` など）の直後、`if`・`then`・`else`・`elif`・`do`・`while`・`until`・`time`・`!`・`{` の直後、コマンド置換の中身（二重引用符内を含む）とする。行コメントと heredoc の本文は読み飛ばし、その後の行は走査を続ける。二重引用符内の置換にある heredoc だけは、本文の終わりを決められないため、そこで走査を止める。環境変数の代入は、値に引用符を使うもの（`NAME='v'`）も代入として扱う。`'gcloud'`・`gcl"oud"`・エスケープされた実行名、`command` / `env` / 絶対パス wrapper、別名、interpreter 経由は、初回は認識対象に広げない。
- backstop の保証範囲は次のとおり。
  - hook の失敗・timeout・未信頼などで、既存の `gcloud` deny / forbidden ルールに一致する元 command が残る場合は、そのルールが拒否する。ルールは変更しない。
  - 認識できない別名・interpreter 経由の完全な遮断は保証せず、ADR-0073 の既存の限界と行動契約を引き継ぐ。
- 書換えに成功した場合、元の command の deny は効かない。守るのは helper の検証と、書換え後の command に一致するルールである。元の deny が担うのは、書換えが行われなかった場合だけである。
- `gh` は初回は書換えず、hook は何もしない。単独の参照は既存の allow ルールで通り、`gh api` などは既存どおり ask / prompt が確認する。複合形が実際に詰まった例が出た時点で追加を検討する。このため、複合 shell の案内は初回は `gcloud` に限る。
- helper が対応外と判断した操作は、helper の案内どおり人への確認へ戻す。Codex の hook は `ask` を出せないため、対応外を承認済みの状態へ自動変換しない。

第4ラウンドで、安全条件と受入条件について推奨案を採用した。

安全条件（設計判断として固定する。実装方法は実装時に調べる）:

- 書換え対象は command のみとする。cwd・sandbox などの他の属性と既定動作は維持し、権限を広げない。
- helper が存在しない・実行に失敗した場合は、エラーで終了する。元の `gcloud` や別経路へ自動で再試行しない。
- 現行の `devshell-env claude-hook` との共存は、hook の適用順に依存しないことを条件にする。command や権限判断を変更する hook を将来追加するときは再検証する。
- 対象外の入力は、command も権限判断も変更しない。

受入条件:

- hook の検証（単体テスト）: 呼出しを記録する helper スタブで、書換え先・引数・最終権限判断を確認する。次を分類として含め、表記違いを網羅する。
  - 受理するリテラル引数（空引数・空白・メタ文字を含む文字列が、書換え後も保存される）。
  - deny する入力: 先頭 `--reviewed`、展開、代入、リダイレクト、複合 shell。
  - 変更しない入力: `gh`（参照・`gh api`・定型書込み）、`echo gcloud`、認識対象外の入力。command も権限判断も変更されない。
- helper の検証: 実 helper のコードを使い、その先の `gcloud` と通信をスタブ化する。既知の機密項目を含む固定データで `redact()` を確認する。既存テストで満たせる部分は再利用する。
- 両 runtime（Claude Code と Codex）の実機ダミー検証で、次の期待結果を確認する。deny は終了コードや未実行だけでなく、runtime が受理した判断と理由を証跡に残す。

  | 場面 | 期待結果 |
  | --- | --- |
  | 書換え先が allow（元 command に対する既存の deny / forbidden を残した状態） | 書換えが成功し、helper スタブが実行される |
  | 書換え先が deny / forbidden | helper スタブは実行されない |
  | 書換え先が ask / prompt | 確認要求が実際に発生し、承認前は helper スタブが実行されない |
  | 先頭 `--reviewed`・展開・代入（各分類の代表例） | hook 自身の deny と理由が runtime に受理され、スタブも元 command も実行されない |
  | hook の失敗・timeout、Codex の未信頼 | 書換えず、元 command が既存ルールで拒否される |
  | 書換え後の最終入力 | cwd・sandbox などの属性と省略時の扱いが変わらない |
  | helper 不在・非ゼロ終了 | エラーになり、元 command や代替経路を実行しない |
  | `devshell-env claude-hook` を併用した設定 | 期待する書換えと権限判断が保たれる |

- 配備後の確認: Claude Code と Codex それぞれで、通常の `gcloud` 名による読み取りを1件通し、書換え記録などで helper 経由と分かる証跡を取る。Codex は hook の trust 済みであることも確認する。この1件は配線と接続の確認であり、実際の秘密値による除外の確認は行わない。実サービスへの接続確認は配備後の別工程とする。
- 配備前の自動検証と実機ダミー検証では、実サービスを使わない。自動化する検証は既存の `tests/*.bats` に追加する。

## 検証済みの事実

補助エージェントが、実サービスを呼ばないダミー hook（`probe-orig` を `echo` へ書換える）で、導入版の Claude Code 2.1.296 と Codex 0.162.1 を実行して確認した。親は再実行していない。

- 両 runtime とも、権限ルールは書換え後の command に対して評価される。元の command だけに掛けた deny / forbidden ルールは、書換えで回避される。
- hook の `allow` は、書換え後の command に一致する deny / ask / forbidden ルールを飛ばさない。一致するルールがなければ確認を省略する。
- Codex の PreToolUse は `ask` を扱えない。確認を出せるのはルールの `prompt` だけである。Claude は hook から `ask` を出せる。
- hook の異常終了・timeout・失敗は、両 runtime とも fail-open で元の command に進む。Codex は未信頼の hook をスキップし、これも元の command に進む。
- 既存の `devshell-env claude-hook` は command を変更せず、許可判断も出さない。第2の Bash hook は並列に動く追加として共存できる。Codex の `hooks.json` に PreToolUse はない。
- `gcloud-inspect` は、許可リストと引数検証を実行前に、`--format=json` の固定を実行時の指定として、`redact()` による機密項目の除外を出力後に行う。出力側の処理は hook では再現できない。
- helper は先頭引数が `--reviewed` なら追加読み取り用の経路へ入る。実プロセスと通信を禁止したスタブで確認した。
- `gh` の単独の参照コマンドは、既存の allow ルールで通る。`gh api` は ask / prompt のままである。

## 実装で確認した結果

実装は `private_dot_local/bin/executable_gcloud-inspect-hook`（hook 本体）、`private_dot_claude/settings.json.tmpl` と `private_dot_config/codex/hooks.json`（`Bash` の PreToolUse に timeout 5秒で登録）、`tests/gcloud-inspect-hook.bats`（単体テスト）に置いた。実機ダミー検証は、実サービスを呼ばないよう `gcloud` と `gcloud-inspect` を呼出し記録つきのスタブにし、本番の権限設定（Claude は `.claude/settings.json` の permissions、Codex は `default.rules`）と本物の hook 本体で、Claude Code 2.1.296 と Codex 0.162.1 に実行した。

- 入力形式: どちらも `tool_name` が `Bash`、`tool_input.command` が文字列で届く。Claude は `tool_input` に `description` も含む。
- 応答形式: どちらも `hookSpecificOutput`（`hookEventName: PreToolUse`）で、書換えは `permissionDecision: allow` と `updatedInput`、拒否は `permissionDecision: deny` と `permissionDecisionReason` を返す。拒否の理由はどちらもモデルへ届く。`updatedInput` は `tool_input` 全体を保って `command` だけを置換する。
- 属性の保持: Claude は `description` が書換え後も残る。Codex は書換え後の command が元と同じ cwd で実行される。
- 受入表の各場面は、両 runtime で期待どおりだった（書換え先の allow・deny / forbidden・ask / prompt、先頭 `--reviewed`・展開・代入・複合 shell の deny、hook の失敗・未登録のときに元 command が既存ルールで拒否されること）。ask / prompt は、headless 実行では承認待ちとして実行が止まる。Codex は `approval required by policy` で、Claude は未承認の権限要求として拒否される。
- 既存 hook との共存: 本物の `devshell-env claude-hook` と並べても、書換えと権限判断は保たれる。
- helper 不在: 書換え後の `gcloud-inspect` が `command not found`（終了コード127）で失敗し、元の `gcloud` は実行されない。hook は再試行しない。
- 経路の通し確認: hook から本物の `gcloud-inspect`、スタブの `gcloud` まで通すと、helper が引数を `--project=p --limit=100 --format=json --quiet` に組み直した。
- hook 本体の追加確認として、`gcloud` で始まるランダムな入力 36万件を分類器へ通し、例外が出ないことと、書換え後の引数が元の command を bash が単語分割した結果と一致することを確かめた。この確認で `name=~` の `~` が bash では展開されることが分かり、引用符なしの `~` を位置を問わず展開として扱うことにした。確認用のスクリプトは repo に含めない。
- hook が並列に動くときの応答の統合は、現行の `devshell-env claude-hook` が command も権限判断も変更しないため、検証していない。command や権限判断を変更する hook を追加するときに再検証する。

配備は受入後に live source から `chezmoi apply` で行い、未 merge の task worktree からは行わない。配備後は、Codex の hook trust を確認し、通常の `gcloud` 名による読み取り1件を通して helper 経由の証跡を取る。
