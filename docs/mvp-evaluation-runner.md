# MVP評価専用の実行入口

## v4接続（2026-09-22）

現行CLIは[v4契約](evaluations/mvp-mediator-evaluation-v4/protocol.md)へ接続する。対象本文の状態説明を、保持状態・目的/所有者・区分・本実装の取得元の欄へ具体化した。新規runは新本文とv2/v3/v4のpath/hashを固定する。配布テンプレート・課題・採点・停止条件はv3を維持し、実行者には新本文として変更を渡す。

公開CLIのinit/prepare fixtureで、v4登録前の失敗と、新版の固定・配布後の成功を確認する。旧runの記録は保持し、新版による再開は認めない。今回の実装では実LLM評価を開始しない。本文の適用効果は次のempirical評価で確認する。

この変更のcommitには、新本文の前提となる既存の未コミット本文改善も保持して含める。実装開始時の本文からの変更は状態説明段落のみ。v2契約と旧runは既存ローカル依存として保持し、一括でcommitしない。

### v4接続の検証結果

実装commit: `1098fa0`。`3e6ad30...1098fa0`をStandards／Specの独立した2軸でレビューした。

| AC | 検証 | 結果・限界 |
| --- | --- | --- |
| 状態説明の具体化 | 実装開始時の固定本文との差分と2軸レビュー | 状態説明段落だけを変更。保持フィールドの対応と未確認の取得元を明示。適用効果の実測は未実施 |
| 新本文・契約の固定と配布 | `bats tests/mvp-evaluation.bats` | 14/14成功。v4未登録でredを確認後、startの契約hashと配布本文hash・記入欄を確認してgreen |
| 既存ゲート・旧記録の保持 | 同じ14件、旧v3 runのprepare/status、437ファイルのSHA-256照合 | 隔離・承認・監査・再発停止・上限を維持。旧runの変更はimplementation changedで拒否、status成功、旧ファイルすべて不変 |
| 型・構文 | `bunx tsc --noEmit`、Python AST parse | 成功 |
| 全体回帰 | `PATH=/nix/store/m23g9jsxzhyph3xbwdim4v4xsslfqkxm-with-env/bin:$PATH bun run test` | 755件、732成功・23skip・失敗0、exit0。実行中にコード・テスト変更なし |

全体ログと保存照合の作業記録は `tmp/mvp-v4-implementation/`。opt-inの実モデル・プラットフォーム検査は既存のskip条件に従う。今回の新しい実LLM評価は0件。

#### Standards

規約違反0件、設計スメル0件。状態説明を一箇所へ集約し、既存の意味を保持したこと、固定hashとCLIの一致を確認。

#### Spec

未達・scope creep・誤実装0件。新本文/v2/v3/v4固定、Bのモデル不要条件、課題・採点・停止条件の維持を確認。既存未コミット本文改善と今回の差分を区別してレビューした。

## v3接続（2026-09-22）

v3接続時のCLIは[v3差分契約](evaluations/mvp-mediator-evaluation-v3/protocol.md)へ接続する。新規runの`start.json.sources`には基礎v2と差分v3の両path/hashを保存し、配布promptへv3のケース別実行出力要件を挿入する。Bにはその条件が適用されず、提案確認のままである。以下のv2初期実装・診断の記録は経緯として保持する。

親は監査確定時に残る未解決条件だけを`issues`・`failure_patterns`へ入れる。復帰済みの任意の探索エラーは、当該attempt内の`environment.md`等に失敗・代替手段のcall/resultと復帰根拠を記録し、監査の`references`と`reason`から参照する。CLIは参照先をhash固定し、次回操作でも照合する。新しい採点エンジンやエラーの自動分類は導入しない。

たとえば、必要な探索結果をrgで取得したfind不在は環境記録へ残し、未解決条件がなければ`issues: []`・`failure_patterns: []`とする。同じ復帰が2実行で発生しても停止せず、他のclear条件を満たせばLの投入判定を妨げない。禁止入力混入・承認境界違反や必須手順の省略は復帰済みへ分類しない。

監査JSONの`references`へ追加する例:

```json
{ "path": "environment.md", "locator": "失敗・代替実行のevent IDと復帰根拠" }
```

既存runは再開・再採点しない。旧runの実装hashは新CLIと一致しないため変更操作が拒否され、`status`で保存状態だけを確認できる。契約v3本文の「接続前」は契約固定時点の状態であり、接続状況は本節を参照する。

検証は`bats tests/mvp-evaluation.bats`の公開CLI fixtureで行う。v2/v3固定・配布要件、復帰証拠を残した3組clearとL投入、未解決失敗の再発停止、既存の隔離・監査・証拠・上限ゲートを対象とする。実LLM評価は開始していない。

### v3接続の検証結果

実装commit: `a314d8c`。`b9449a0...a314d8c`をStandards／Specの2軸でレビューし、未解消指摘は各0件。Bへの条件付き指示に関する初回指摘は、v3の適用条件と全文を再照合して撤回された。

- `bats tests/mvp-evaluation.bats`: 14/14成功。配布・契約固定の追加検査は修正前にv3未登録で失敗し、接続後に成功した。
- `./node_modules/.bin/tsc --noEmit`: 成功。変更Pythonの構文検査も成功。
- `PATH=/nix/store/m23g9jsxzhyph3xbwdim4v4xsslfqkxm-with-env/bin:$PATH bun run test`: 755件、732成功・23skip・失敗0、終了コード0。`with-env`はこのcheckoutの`nix build .#with-env --no-link --print-out-paths`で取得。全体実行中にコード・テストは変更していない。
- 対象本文・契約・既存評価・prototype・監査補足を含む既存352ファイルはhash不変。追加LLM評価は0件。

## Contract

目的は、固定した評価契約v2を、実証済みの隔離起動へ接続すること。本文・既存評価・prototypeは変更しない。本評価の開始は別の明示依頼で行う。

受入条件:

- E/B/Sを3組、条件成立時にLを1回。各実行へ担当課題・本文・条件付き参照・明示した実行指示だけを渡す。
- 永続する書込みは、その実行の `memo.md` と、B以外の `model.mjs` に限定する。
- 配布内容・hash、実行条件、tool call/resultを含むstdout、stderr、終了状態、成果物hashを親側へ保存する。
- 親が証拠を参照して入力監査と採点を確定するまで、次の実行を拒否する。監査は該当証拠のhashへ結び付ける。
- 入力invalid/unknownだけを明示置換でき、最大2件。機能・遵守failを置換理由にしない。同じ失敗パターンが独立した2実行で再発すれば停止する。全dispatchは12件以内、3組を超えて追加しない。
- Lは3組clearと親による未使用確認が必要。canonical metadataは取得できなければN/Aのまま保存する。
- 合成workerを使い、公開CLIを通して隔離・監査・停止を検証する。本評価もモデル通信もテストでは開始しない。

非目標は汎用agent基盤、採点・意味的入力監査の全自動化、全runtimeの別起動経路の禁止、既存成果物の再採点。

関連する一次資料は `docs/evaluations/mvp-mediator-evaluation-v2/protocol.md` と `docs/evaluations/prototype-input-isolation/llm-run/`。実装ではprototypeをimportしない。既存のmodel gatewayを再利用し、実行入口自身が評価用の起動前条件を検査する。

判断済みのtradeoff: 契約が許す組内並列は使わず直列実行する。監査の意味判断・失敗パターンの分類・採点は親が行う。ホストの同一ユーザーによる悪意あるstate改変は対象外だが、二重CLI起動と証拠の変更は拒否する。

## CLIと状態の境界

`init` で実行条件と入力を固定し、`prepare` で次の課題を隔離用に抽出する。親が `approve` で配布内容を確認した後にだけ `dispatch` できる。完了後は `audit` で入力有効性・6項目・C1〜C4・失敗パターン・証拠参照を確定するまで次の `prepare` を拒否する。`status` は状態と停止理由を読むだけで、モデルを起動しない。

入力不良の置換には `prepare --replace` を使う。同じ課題slotに新しい実行IDを割り当て、元実行の証拠を残す。監査レコードは上書きしない。Lの配布前には、親が履歴を確認した証拠を渡す。

通常runと合成fixture runは初期化時に区別し、途中で切り替えない。fixture runはgatewayを起動せず、Codexのnative sandboxを経由して合成workerを隔離内で動かす。通常runは明示した `dispatch` だけがモデルを起動する。

## 操作

入口は `python3 scripts/mvp-evaluation.py`。以下は操作例であり、この実装作業では通常runを作成・dispatchしない。

初期化には次のJSONを `conditions.json` として用意する。`instructions` だけが実行者への追加指示となる。過去評価や正解を含めない。`effective_context` には実効system/developer/AGENTS・Ponytail等のログ参照と、見えない部分のunknownを記録する。`runtime_notes` にはツールや隔離環境の条件を記録する。親側の2項目は実行者へ渡さない。

```json
{
  "instructions": "今回の実行者へ適用するAGENTS等の指示全文",
  "effective_context": "実効指示のログ参照。モデル基本指示の非公開部分はunknown",
  "runtime_notes": "Linux/Nix、専用bubblewrap境界、評価用ツールセット"
}
```

```sh
python3 scripts/mvp-evaluation.py init /absolute/new-run --conditions conditions.json
python3 scripts/mvp-evaluation.py prepare /absolute/new-run
python3 scripts/mvp-evaluation.py status /absolute/new-run
```

runは存在しないディレクトリを指定する。`init` は入力元・実装・ツール・Git情報を固定する。`prepare` は担当節を抽出し、Sのheld-out表記と投入時期の一文だけを除く。`attempts/01/inputs/` と `prompt.txt` の配布内容を親が確認する。承認JSONは、statusにある最新attemptの `bundle_sha256` と具体的な確認理由を持つ。

```json
{
  "bundle_sha256": "statusに表示されたhash",
  "reason": "担当節・6基準・指定版・追加指示を確認。他課題と親checkerは配布に含まれない"
}
```

```sh
python3 scripts/mvp-evaluation.py approve /absolute/new-run --record approval.json
python3 scripts/mvp-evaluation.py dispatch /absolute/new-run
```

dispatchは同期実行し、run単位のlockを終了まで保持する。stdout/stderrは逐次保存する。900秒でtimeoutし、証拠を残して監査待ちにする。再dispatchは禁止する。通常runだけが既存のChatGPT gatewayを起動し、空のHOMEで新規Codex `gpt-5.6-terra/high` を動かす。認証情報はgatewayから隔離側へ渡さない。

永続成果物は `artifacts/memo.md`、E/S/Lのみ `artifacts/model.mjs`。親が用意した既存ファイルへ直接上書きする。ディレクトリへの追加・削除・renameは許可しないため、実行者はatomic renameを使う編集方式を避ける。内部のHOMEと/tmpは使い捨て領域で、返却対象ではない。Codexの保護処理が参照する `.git`・`.codex`・`.agents` の空ディレクトリをreadonly側に事前作成し、内側sandboxがmount先を作成できず停止することを防ぐ。実行コードとツールのNix依存closureも隔離内から読めるが、repo・過去成果物・checkerはmountしない。

## 親の監査

親は `stdout.jsonl` の実読取りと返却内容、実行者の報告、成果物を照合する。通常のexecイベントに加え、子の終了後に使い捨てHOMEのnative sessionからtool call/resultを `runtime.tool_record` として同じstdoutへ出力する。各レコードはnative sessionの相対path・行番号・原レコードを持つ。system本文・推論記録は転記しない。`--ephemeral` は使わないが、セッション自体は隔離内だけに保存され終了時に失われる。強制終了や破損で必要なcall/resultが取れなければ親はunknownを維持する。契約の独立検査も親側で行い、そのログを当該attemptの `parent-checks/` 以下へ保存する。生成コードを無条件にホストで実行せず、別の隔離境界で検査する。親の検査結果は実行者の実績へ加えない。

監査JSONの例（数値は例示であり、実採点ではない）:

```json
{
  "evidence_sha256": "statusに表示された最新attemptの証拠hash",
  "input": "valid",
  "scores": [1, 1, 1, 1, 1, 1],
  "compliance": ["pass", "pass", "pass", "pass"],
  "issues": [],
  "failure_patterns": [],
  "reason": "各基準とC1〜C4の根拠、および自己報告との差を参照記録に記載",
  "parent_checks": "parent-checks/checks.json",
  "references": [
    { "path": "stdout.jsonl", "locator": "入力読取りと実行結果のevent ID" },
    { "path": "parent-checks/review.md", "locator": "採点根拠と親検査の節" }
  ],
  "decision_retry": "自己報告の回数・理由・出典。未報告ならunknown",
  "mechanical_retry": "親がログから集計した回数と対応イベント"
}
```

```sh
python3 scripts/mvp-evaluation.py audit /absolute/new-run --record audit.json
```

入力判定は `valid/invalid/unknown`、6項目は `0/0.5/1`、C1〜C4は `pass/fail/unknown`。clearでなければ再発照合用の `failure_patterns` を必須とする。同じ原因には同じ名称を使い、入力不良と機能・遵守失敗を区別する。CLIは意味判断を代行せず、証拠の存在・hash・値域と停止条件を検査する。unknown確定後の置換と、監査レコード自体が未提出の状態は異なる。

監査・証拠・返却成果物は上書きしない。既存ログ・成果物に加え、全attemptのbundle・入力・promptの変更があれば次操作を拒否する。入力invalid/unknownのときだけ `prepare --replace` を使う。3組clear後のLには `prepare --unused-evidence unused.json` を使い、JSONに `{"unused":true,"reason":"履歴照合の参照と理由"}` を記す。

入力validの監査には `parent_checks` を必須とする。E/S/Lは `self_check`、Eはさらに `fixed_checker` を含むJSONを用意する。各項目は `status`（executed/not-run）、`reason`、`artifact_sha256`（証拠のmodel.mjs hash）を持ち、executedなら `command`・`expected`・`exit_code`・`output` も保存する。固定checkerには `checker_sha256` を付け、契約の値と一致させる。未実行・失敗の検査ではclearを拒否する。Bは `proposal_review` に `status: "not-run"` と提案確認の `reason` を記し、未実行アプリ検査を成功と扱わない。これらの記録もhashで固定する。検査の意味的な十分性は親が判断する。

失敗再発・置換上限・3組終了・L終了後は `status` の `stop` に理由を残す。4組目や上限を超えた追加試行は作らない。モデル内部の複数HTTP応答は1セッションに含め、dispatch数とは分ける。起動失敗も予約したattemptを消費する。

## 検証と限界

```sh
bats tests/mvp-evaluation.bats
```

テストは `init --fixture` で固定し、同じmount境界の合成workerでCLIを検証する。fixture runをliveへ変更できない。モデル評価は開始しない。実LLMとgatewayの接続実証は既存prototypeを参照し、今回変更した書込み境界はfixtureで確認する。

親による監査が意味的に正しいか、指定されたログ位置が採点を実際に裏付けるかは親の責務。ホストの同一ユーザーは別の起動経路を使えるため、全runtime共通の強制とは呼ばない。親プロセスが強制終了した場合はrunningのままfail-closedとなる。自動再開・状態書換えによる救済はせず、残った証拠を調査する。

契約・対象本文の未コミット状態を勝手に取り込まないため、このcommitは既存のローカル評価文書を依存として参照する。別checkoutへ移す際は、固定hashに一致する契約・本文が揃っている必要がある。

## Verification Matrix（2026-09-21）

| AC | 検査 | 結果・限界 |
| --- | --- | --- |
| 課題別入力・承認・変更拒否 | `bats tests/mvp-evaluation.bats` | 指定課題抽出、承認前拒否、入力／承認／証拠変更拒否が成功 |
| 隔離・指定成果物 | 同上の実bubblewrap fixture | 入力外読取り、入力書込み、未指定ファイル作成を拒否。指定成果物への書込み成功 |
| 監査・停止・上限 | 同上 | 未監査停止、明示置換、2件上限、再発停止、3組終了、L条件、12件経路、13件目拒否が成功 |
| 親検査の必須化・metadata | 同上 | 親検査なしのclear拒否、固定checker hash、N/A記録を確認 |
| 型・構文 | `bunx tsc --noEmit`、Python AST parseとCLI実行 | 成功 |
| 既存成果物の保持 | 作業開始時255ファイルのSHA-256と終了時を照合 | 本文・既存評価・prototypeすべて不変 |
| 本評価を開始しない | テストは全てfixture mode | 新しい実LLM評価は0件。変更した実行入口での実LLM統合は未実行 |

最終コードを固定した専用テストは **11/11成功**。全体の `bun run test` は750件を実行し、723成功・23skip・4失敗（exit 1）だった。うち新規テスト3件は全体実行中にレビュー修正を並行したことで旧fixtureと新実装が混在したためで、固定後の11件で再確認した。残る既存 `human-validation.bats` 1件は起動シェルに `with-env` がなかったため。repoの `nix build .#with-env --no-link --print-out-paths` で提供するバイナリをPATHに加え、同ファイル1/1成功を確認した。全体の単一runがgreenだったとは扱わない。opt-inの実モデル／プラットフォーム検査は実行していない。

## Standards

規約違反・追加のsmell指摘なし。task worktree、既存prototype保持、専用CLIへの限定、fixtureからのモデル起動禁止を確認。固定hashの既存ローカル文書に依存する点は前記の配布上の制約である。

## Spec

初回指摘2件を修正し、仕様レビュー担当が解消を確認した。

- P1: 親の独立検査記録なしでもclear可能だった。課題別の構造化した親検査記録を必須化し、成果物・固定checkerのhash、実行状態、コマンド、期待値、終了値、出力へ結び付けた。
- P2: canonical metadataの取得不能をnullで記録していた。literal `N/A` とsource・reasonへ修正した。

未解消指摘はStandards 0件、Spec 0件。レビュー比較の起点は `94e283a346eaf12edece45bb7a5ca94295340faa`。

## Runtime障害の診断・修正（2026-09-21、b782437以後）

`run-20260921-02` の失敗とレビューP1の2件を対象にした。本文・評価契約・既存評価run・prototypeは変更していない。本評価は再開せず、`tmp/debug-mvp-runtime/live` に実LLM実行者1回の診断記録を保存した。

根因と修正:

- 外側readonly artifactsと、内側Codex sandboxの保護用mount先作成が衝突していた。`python3 tmp/debug-mvp-runtime/repro.py` で `bwrap: Can't mkdir /artifacts/.codex: Read-only file system` を再現。空の `.git`・`.codex`・`.agents` をreadonly側へ事前作成した比較だけで、同じ読取り・更新コマンドが成功した。ディレクトリ全体へのwrite権限は追加していない。実LLMの `apply_patch` も成功し、別の編集方式障害という仮説は今回の更新経路では棄却した。
- 通常の `codex exec --json` は一部のtool失敗を出さない。使い捨てHOMEのnative sessionからcall/resultを追加保存する。診断で `touch /artifacts/unlisted` の失敗がcompact側に欠け、native側のcall/result（session行50/52）には存在することを照合した。
- 過去attemptの入力は `verify_history` の照合対象外だった。全attemptへ `verify_bundle` を適用し、本文・prompt・bundleの改変を次のprepareより前に拒否する。

回帰検査は修正前の失敗を確認してから追加した。fixtureもCodex native sandboxを経由するようにし、モデル通信なしでmount衝突と指定ファイル更新を検査する。native tool記録の検査は `tests/mvp-evaluation-records.py` をBatsから実行する。

| 確認 | 結果 |
| --- | --- |
| `bats tests/mvp-evaluation.bats` | 13/13成功。履歴検査は本文・prompt・bundleの各変更を拒否 |
| 実LLM診断 | gpt-5.6-terra/high、新規1セッション。入力全文読取り、指定2成果物更新、self-check4ケース成功 |
| 親の隔離再実行 | self-check4ケース成功、固定checker52/52成功 |
| 入力と証拠 | native22レコード＝11call/result対を照合。入力valid、診断用Eの6項目とC1〜C4を親確認 |
| 起動ゲート | 診断実行の未監査時prepareをexit1で拒否。監査後も後続dispatchは実施しない |
| 書込み境界 | 実LLMの `touch /artifacts/unlisted` はreadonlyエラー。指定ファイルの既存更新は成功 |
| 読取り境界 | fixtureは実在するhost側bundleの読取りを拒否。実LLMのcanaryは不存在pathのENOENTだけで、単独の隔離証明とは扱わない |

診断の証拠: `tmp/debug-mvp-runtime/live/attempts/01/` の `evidence.json`、`stdout.jsonl`、`audit.json`、`parent-checks/`。model.mjs SHA-256は `9cf3dd6f66a9408717cd448f3ce7ba382093fbf5119c16e66eacc5bb181ad355`、stdout SHA-256は `d4ab946b7645f49a6e131e2e2f02289e42c54107db9954c9caa6b2a626f4c6b1`。native記録の件数は独自集計であり、canonical tool_uses/duration_msはN/Aを維持する。診断1回から評価の収束は主張しない。

限界: native sessionの回収は子終了後であり、強制終了時の未回収区間はunknown。fixtureはCodex native sandboxを通すが、実モデルの全tool選択を網羅しない。診断用ファイルは明示したdebugディレクトリに保持し、既存prototypeを削除・編集しない。
