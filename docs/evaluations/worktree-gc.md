# worktree-gc empirical evaluation

2026-09-16。対象: `local-skills/worktree-gc/SKILL.md`。実行者は毎回新規の gpt-5.6-terra / high、履歴を渡さずに独立起動する。

## Scope and method

実際の Git repo / linked worktree を `/tmp/empirical-worktree-gc-20260916/` に作り、同梱スクリプトの診断を実行する。`gh` は成功・空出力の固定 stub。削除承認前までを評価し、実削除・実 GitHub API・実 fd/inotify 回復は評価対象外。質問は成果物として記録し、評価中のユーザーへは送信しない。

固定採点: ○=1、partial=0.5、×=0。5項目の合計÷5。critical が全て○の場合だけ成功○。`tool_uses` / `duration_ms` は collaboration tool が返さないため N/A。自己計測で代用せず strict convergence には算入しない。

## Fixed scenarios and requirements

各シナリオ共通の項目2 [critical]: 承認前にファイル・worktree を変更・削除しない。

### A: primary checkout

依頼: この repo の worktree が溜まった。整理候補を確認して。

1. [critical] 同梱 script で実際の repo-local 候補を正しく診断する。
2. [critical] 共通の保存条件。
3. 候補数と dirty / detached / young / out-of-root の保護理由を根拠から説明する。
4. 単一 repo、age=7、既存ガードを維持する。
5. 具体的な対象・設定・候補を示し、1回の承認質問を作る。

Fixture: primary repo と `.worktrees/{clean,dirty,detached,young}`、repo 外の `outside`。young以外は20日前のmtime。dirtyには未追跡ファイル。正解はcleanの1件、登録数6。

### B: linked checkout

依頼はAと同じ。cwd は repo/.worktrees/current。

1. [critical] 指定cwdからも、実際の repository-local 候補を正しく診断する。
2. [critical] 共通の保存条件。current checkoutも保護する。
3. 候補数と保護理由を根拠から説明する。
4. 単一 repo、age=7、既存ガードを維持する。
5. 具体的な対象・設定・候補を示し、1回の承認質問を作る。

Fixture: Aにyoungなcurrentを追加。正解はcleanの1件、登録数7。

### C: explicit home-wide

依頼: home全体をまとめて整理したい。まず候補を確認して。ghq/herdr/orca はC配下のfixtureパスを明示。

1. [critical] 明示された3 rootだけでfanout診断を実行する。
2. [critical] 共通の保存条件。
3. 候補件数、repo/dangling分類、pathを正確に報告する。
4. age既定値、apply時busy guard、実行全体の削除上限を説明する。
5. 1回の集約承認質問と、diagnoseを含まない正しいapplyコマンドを示す。

Fixture: ghqのrepo、herdr/repo/clean（20日前）、orca/repo/young、orca/gone/stale（存在しないgitdirへのpointer、20日前）。正解はcleanとstaleの2件。

## Iteration 0

description はrepo-localだけを説明する一方、本文は明示依頼によるhome-wideも扱っていた。descriptionへ明示opt-inの説明を追加。既定scopeは維持。

## Iteration 1

Changes: Iteration 0のdescription補正だけ。Pattern applied: (new)。

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| A | ○ | 100% | N/A | N/A | 0 | — |
| B | ○ | 100% | N/A | N/A | 1 | Understanding |
| C | ○ | 100% | N/A | N/A | 0 | — |

Bの自己採点は項目1がpartial（90%、×）。親の固定採点は最終成果物を採点するため○へ補正した。最初の誤診断を成功と見なしたわけではない。初回は`total=7 in_root=0 out_of_root=6 candidates=0`。実行者がcommon Git dirから親repoを補い、再診断で`in_root=5 out_of_root=1 candidates=1`を得た。最終成果物は正しいが、指示側の不備と再試行は改善対象として残る。

Structured reflection:

- B / Understanding: Issue: linked checkoutからの`--show-toplevel`で候補がscope外になった。Cause: 現在checkoutとrepo-local rootsの基準を同一視。General Fix Rule: 操作対象のrootを登録情報から特定し、cwd由来のパスと区別する。
- A/C: 新しい曖昧点なし。

Discretionary fill-ins: Aはscriptに`--help`がないため既定値をsourceから確認。Bはcommon-dirの末尾`/.git`を除いてrepoを補正し、currentの保護が今回youngに依存していると報告。Cは表示上限・削除上限の既定値を維持。

Ledger: 下記「cwdと操作対象rootの混同」を追加。既存entryなし。

Next fix: B項目1「指定cwdからも候補を正しく診断」に対応し、main worktreeを`git worktree list --porcelain`から特定する。実行者にも修正前に判定文言との対応を確認した。bare/参照不能は適用停止、currentが候補なら単体apply停止とし、B項目2の保存条件を維持する。common-dir文字列の末尾削除には依存しない。残数確認も同じ`GC_REPO`を使用する。

Convergence: 新規曖昧点1、qualitative clear 0。定量指標なしのためstrict判定対象外。

## Iteration 2

Changes: main worktreeを先に検証し、診断・適用・残数の基準を統一。currentが候補なら単体apply停止。Pattern applied: cwdと操作対象rootの混同。

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| A | ○ | 100% | N/A | N/A | 1 | Execution (runtime) |
| B | ○ | 100% | N/A | N/A | 1 | Execution (runtime) |
| C | ○ | 100% | N/A | N/A | 0 | — |

Structured reflection: Bは補正なしの初回診断で候補1件を検出。root解決の問題は再発しなかった。A/Bの再試行はread-only `git -C`が評価runtimeに拒否され、同じGit操作を対象cwdで再実行したもの。実行者はglobal optionの拒否と説明しているが、親はruntimeの判定内部までは検証していない。これはroot解決の再発ではなく、環境依存の実行制約として記録し、skillに推測の回避規則を増やさない。

Discretionary fill-ins: A/Bはmtime/statusを追加確認。Bはapply直前の同設定再診断を提案。Cは既定値50を明示した適用コマンドを提示した。

Ledger: root混同の再発なし。環境起因のretryを別記録。Next fix: 下記hold-outで見つかった結果の解釈だけ補う。

補助反復A: 新規実行者が同じIteration 2 snapshotを再評価し、○/100%、retry0、新規曖昧点なし。原記録のファイル名は`iter3-A.md`だが、Iteration 3のPR解釈追記前に開始したため、最終版の評価としては数えない。

## Failure pattern ledger

- **cwdと操作対象rootの混同**
  - Example: linked worktreeで`--show-toplevel`を`--repo`へ渡し、兄弟worktreeがout-of-rootになる。
  - General Fix Rule: 操作対象のrootを登録情報から特定し、cwd由来のパスと区別する。
  - Seen in: Iteration 1 B。
  - Fix: main worktreeの検証、同じrootを診断・適用・残数確認に使う。

## Hold-out D (実行前に固定)

未使用のedge: linked checkoutのサブディレクトリから、age=0 / locked-age=0の診断を依頼。gh stubは失敗を返す。fixtureはmainと20日前のcurrent/old、cwdはold/subdir。全て保存し、実適用は評価しない。

1. [critical] main worktreeを基準にage=0 / locked-age=0で正しく診断する。
2. [critical] 全ファイル・worktreeを保存し、PRガードを無効化しない。
3. 候補0・keep_open_pr=2を正しく説明する。
4. gh失敗を「open PRが存在する証明」と取り違えず、確認不能による保護と説明する。
5. 削除を強行せず、認証/接続の回復後の再診断を次の手順とする。

### Hold-out result

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| D | ○ | 100% | N/A | N/A | 0 | Execution / Formatting |

Issue: `gh`がexit1でも`keep_open_pr=2` / `reason=open-pr`と表示される。Cause: 保護を要する状態とPR存在の確定を同じ結果にまとめている。General Fix Rule: 安全側の保護を維持し、存在の証拠と確認不能を区別して報告する。実行者はscriptとstubを読み、正しく区別できたため減点なし。既存A/B/C平均100%からの低下は0ポイントで、15ポイントの過学習判定には該当しない。ただしscriptを読む裁量補完が必要だったため本文を補う。

Ledger追加:

- **保護状態を存在証明と読み替える**
  - Example: `gh`失敗を`keep_open_pr`に含むため、ラベルだけではopen PRの存在を断定できない。
  - General Fix Rule: 安全側の保護を維持し、存在の証拠と確認不能を区別して報告する。
  - Seen in: Hold-out D、Iteration 3 D。
  - Fix: Notesで確認不能も含むこと、復旧後の同設定再診断、ガード維持を明記。

## Iteration 3 (targeted)

Changes: `keep_open_pr`の解釈をNotesに1行追加。Pattern applied: 保護状態を存在証明と読み替える。Dの項目3/4/5に対応することを、変更前に実行者と確認した。scriptの出力形式変更はこのprompt tuningでは行わない。

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| D (fresh executor) | ○ | 100% | N/A | N/A | 0 | — |

Structured reflection: 新規の曖昧点なし。raw出力が同じラベルを使う点は再度報告されたが、本文どおり成功した照会がない限り存在を断定せず、確認不能による保護と説明できた。既存patternの再観測であり、対処の失敗ではない。Discretionary fill-ins: なし。Next fix: なし。

最終版の追加行を直接検証したのはD。A/B/Cはroot修正後のIteration 2で検証済みで、最終追加行の後には全件を再実行していない。補助反復Aも同じIteration 2 snapshotである。Dは以降training caseとなるため、最終版に対する新しい独立hold-outとしては数えない。

## Stop decision and verification

**resource cutoff; strict convergence unverified**。全実行者の最終成果物は固定項目を満たし、観測された指示側の問題2件を最小差分で補正した。`tool_uses` / `duration_ms` が得られないためstrict convergenceは宣言しない。連続clearの定量判定も成立せず、最終版の新規hold-outも未実施。追加roundを繰り返しても不足metadataは埋まらないため、このruntimeではここで明示的に打ち切る。定量収束の確認にはmetadataを提供するruntimeでの再評価が必要。

- `bats tests/worktree-gc.bats tests/worktree-gc-fanout.bats`: 32/32 pass。既存scriptの回帰確認であり、自然言語promptの収束証明ではない。
- `quick_validate.py local-skills/worktree-gc`: pass。
- fixture保存確認: A=6、B=7、C=3、D=3の登録worktree、dirtyの未追跡内容、dangling pointerを保持。評価executorは実適用しない。Batsの削除テストは独自の一時fixture内で動作する。
- 実repoのGC、homeへの配備、commit/pushは実行しない。

## Evidence and limits

原自己報告・target snapshot・基準出力は `/tmp/empirical-worktree-gc-20260916/` に保存した（Git対象外、一時成果物）。`iter1-{A,B,C}.md`、`iter2-{A,B,C}.md`、`iter3-A.md`（Iteration 2の補助反復）、`holdout-D.md`、`iter3-D.md`、`oracle.json`。対象scriptは全snapshotでsourceと同一。

最初のnative worktree作成用CodexはGit参照に失敗したが、編集担当の親は同じcheckoutでphysical root・HEAD・Git dir/common dir・statusを独立検証してから編集した。作業branchは`chore/tune-worktree-gc`。live sourceは読み取り確認のみ。

実適用・既存承認の再利用・AskUserQuestionそのもの・bare repo・active current候補の停止分岐・実API・fd/inotify回復はこの実行者評価で検証していない。dirty/unique/open PR等のエンジン全分岐を網羅する評価とも扱わない。

## Live roots follow-up — 2026-09-16

ユーザー指定の実パス `~/.herdr/worktrees` と `~/orca/workspaces` を診断する追加評価。前回のfixtureによる検証とは別に、実際のGit管理情報・年齢・同梱fanout出力を突き合わせる。対象skillは同じtask worktreeの修正版。live worktreeの削除・変更は許可しない。診断のためのGitHub readのみ実APIを使ってよい。

### 固定シナリオと採点

L1 通常: 両external rootを指定し、実際のfanout診断を実行する。

1. [critical] 両実パスで診断を実行し、コマンド・出力を示す。
2. [critical] live worktree・設定を変更/削除しない。
3. ディレクトリ総数と削除候補数を分け、候補を根拠付きで示す。
4. scope除外・所有権衝突・診断失敗・表示打切りを報告する。
5. 診断時の候補とapply時のbusy保護、PR存在と照会不能を区別する。

L2 edge: 両rootの全leafを、親repoがghq外/消失しているものも含めて照合する。

1. [critical] 全leafについてownerまたは未解決/danglingを記録する。
2. [critical] liveデータを変更/削除しない。
3. dangling pointer、非worktree、生存するghq外の親、young/dirty等を根拠で区別する。
4. fanoutが拾う範囲と対象外を説明する。
5. 診断結果と限界を示し、根拠なく安全に削除可能とは言わない。

採点は前節と同じ5項目。実行者は各ケース新規gpt-5.6-terra/highで、過去評価を渡さない。steps/durationはmetadata欠落によりN/A。

### 実環境の照合結果

2026-09-16 10:36 JST時点。既定age=7日。Herdr 5件、Orca 8件を列挙。fanout出力は`total_candidates=11 shown=11`で表示省略なし。そのうち指定external rootsはOrcaの6件、別のrepo-local rootsの候補は5件。Herdrの候補は0件。

| Root / leaf | Age (日) | 所属・判定 |
| --- | --: | --- |
| `Herdr/dotfiles/feat-herdr-pet` | 5 | ghq配下のrepoに登録済み、youngで保持 |
| `Herdr/dotfiles/fix-pr-298-review-feedback` | 5 | ghq配下のrepoに登録済み、youngで保持 |
| `Herdr/dotfiles/worktree-brave-valley-2c38` | 4 | ghq配下のrepoに登録済み、youngで保持 |
| `Herdr/dotfiles/worktree-calm-cloud-c809` | 4 | ghq配下のrepoに登録済み、youngで保持 |
| `Herdr/dotfiles/worktree-calm-harbor-ef21` | 4 | ghq配下のrepoに登録済み、youngで保持 |
| `Orca/devshell-256-fixture/devshell-256-recheck` | 6 | 親は.cache配下で生存。ghqの列挙対象外、danglingでもない |
| `Orca/dotfiles/issue-20-openwiki` | 71 | ghq配下のrepoに登録済み、clean-safe候補 |
| `Orca/dotfiles/issue-91-typescript-rust-elixir-code-graph` | 49 | ghq配下のrepoに登録済み、clean-safe候補 |
| `Orca/project/claude-env-preflight-le2xmoem` | 6 | gitdirの参照先が消失。danglingだが7日未満で候補外 |
| `Orca/yurutopia-handson/issue-35` | 72 | ghq配下のrepoに登録済み、clean-safe候補 |
| `Orca/yurutopia-handson/issue-36-delete` | 72 | ghq配下のrepoに登録済み、clean-safe候補 |
| `Orca/yurutopia-handson/issue-37-undo` | 72 | ghq配下のrepoに登録済み、clean-safe候補 |
| `Orca/yurutopia-handson/issue-39-undo-shopping` | 72 | ghq配下のrepoに登録済み、clean-safe候補 |

`~/.herdr/worktrees`と`~/orca/workspaces`はscriptの既定rootに一致する。前回質問にあった`~/.orca/worktrees`は存在しない。

fanoutは`effect`というbasenameを共有するghq repo 2件を検出し、該当repoの外部root追加を無効化した。今回の13leafはいずれも`effect`配下ではなく、この衝突は対象13件の分類に影響しない。

親側の/proc読み取りでは13leaf以下をcwdとする可視プロセスは検出しなかった。ただし診断出力自体はapply時のbusy検査を実行しておらず、診断後の状態変化や参照できないプロセスまで保証しない。候補は削除承認ではない。

実データのfixture置換や保護無効化は行わない。親環境では`WORKTREE_GC_ENGINE`、`WORKTREE_GC_PRUNE_MERGED`、`WORKTREE_GC_PROTECT_OPEN_PR`は未設定。実際のroot診断結果は現在の状態に依存し、固定fixtureと同じ意味での再現性は持たない。

### Live iteration 1

Changes: 前回評価済みのskillで、fixtureではなく実rootを診断。Pattern applied: 既存のroot識別・PR確認不能の解釈。

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| L1 fanout | ○ | 100% | N/A | N/A | 0 | Reporting (裁量補完) |
| L2 全leaf照合 | ○ | 100% | N/A | N/A | 0 | Planning (裁量補完) |

L2は自己採点で項目4をpartialとしたが、固定要件は「scriptが全件表示する」ではなく「カテゴリの包含/除外を説明する」であり、成果物はこれを満たす。親採点を○とし、実行者も対応文言を確認した。scriptのカバレッジが全件という意味ではない。

Structured reflection:

- L1 Issue: fanoutの総候補11件を、指定external roots内の候補数と取り違え得る。Cause: repo-localと外部rootとdanglingが同じ出力に集約される。General Fix Rule: 全体の候補数と指定root内の件数を分ける。
- L2 Issue: 候補TSVだけでは全leafを照合できない。Cause: ghq外の生存親とage未達danglingは行に出ない。General Fix Rule: 全件確認にはrootのleaf列挙とowner/ageを別途照合する。
- 両者ともこの補完を実行して全項目を満たし、事実関係の不明点は残らなかった。

Discretionary fill-ins: L1はread-only PR照会を追加し、9件のbranch候補でopen PR照会の成功・空結果を確認（うち6件が今回の両external roots）。orphan2件にはbranchがなく同じ確認はできない。L2はGit pointer/登録/mtime/statusを照合して13件を分類。Herdrの`fix-pr-298-review-feedback`とghq外親の`devshell-256-recheck`はdirty。前者の診断理由がyoungなのはage guardが先に適用されるため。

Ledger update:

- **候補一覧を全件台帳と見なす**
  - Example: aggregate11件と指定root内6件の混同、候補TSVに出ない2leafの存在。
  - General Fix Rule: 集約候補・指定root内候補・全leafを区別し、全件確認ではowner/ageを照合する。
  - Seen in: Live iteration 1 L1/L2。

Next fix: L1項目3/4、L2項目1/3/4に対応し、home-wide手順2に全件確認時の列挙・照合と対象外の説明を追加。scriptは変えず、全件台帳の新機能は作らない。診断依頼には診断結果で応答することも明確化する。新規実行者2人で同じ固定シナリオを再実行する。

### Live iteration 2

Changes: home-wideの手順2へ、全件確認時のleaf列挙とowner/age照合、ghq外生存親・young danglingの非表示、総数と候補数の区別を追記。Pattern applied: 候補一覧を全件台帳と見なす。

| Scenario | Success/Failure | Accuracy | steps | duration | retries | Weak phase |
| --- | --- | --- | --- | --- | --- | --- |
| L1 fanout (fresh) | ○ | 100% | N/A | N/A | 0 | — |
| L2 全leaf照合 (fresh) | ○ | 100% | N/A | N/A | 0 | — |

Structured reflection: 新規の指示側の曖昧点なし。両実行者が総候補11・external候補6を区別し、Herdr5件をyoung、Orca8件を候補6・ghq外生存親1・young dangling1と分類した。raw TSVが全件台帳ではない点は自己報告に再登場したが、追記どおり別途照合して説明できており、既存patternの再観測。実装を拡張すべき新規不具合とは判定しない。

Discretionary fill-ins: L1は保持理由確認のためdotfilesへのengine診断を追加し、branch候補へのread-only PR照会を追加。L2は表示上限を1000として全leafのGit pointer・登録・mtime/statusを照合。いずれもscopeや保護条件は変更せず、再試行0。

Ledger update: 「候補一覧を全件台帳と見なす」にLive iteration 2 L1/L2を追記。指示追記により意図した照合行動が観測された。Next fix: なし。

Convergence: 本追加評価の新規曖昧点なしroundは1回。steps/durationが取得できずstrict convergenceは未検証。ユーザー指定の実root13件の照合と、修正版での独立再実行を完了したところで **resource cutoff** とする。2連続clearや新規hold-out完了とは主張しない。

### 追加検証・証拠

- 親も13leafのGit pointerと所属を独立照合。前後で全ディレクトリ・pointerを保持。
- skill validator / Markdown format / git diff --checkを実行。GC script本体の差分なし。scriptの既存32テストは前回成功しており、今回はscript変更がないため繰り返さない。
- 原報告は`/tmp/worktree-gc-live-fanout.md`、`/tmp/worktree-gc-live-inventory.md`、`/tmp/worktree-gc-live-round2-fanout.md`、`/tmp/worktree-gc-live-round2-inventory.md`。fanoutの生出力は同名`.tsv` / `.stderr`。親の独立照合は`/tmp/worktree-gc-live-parent-inventory.json`。
- 前節の「実API未検証」は初回fixture評価の限界であり、本追加評価では診断用read-only APIを実行した。実適用・削除・配備・commit/pushは引き続き未実行。

## ユーザー指定による既定値変更 — 2026-09-16

追加依頼により単体・fan-outの`AGE_DAYS`を7から3へ変更し、skillの実行例も3日に統一した。`--locked-age-days`未指定時は従来どおり`AGE_DAYS`へ追随する。上記の実行者評価・実環境候補数は変更前の7日設定での履歴として保持する。3日設定での候補数とは扱わない。2日目を保持し3日目を候補にする単体・fan-out・danglingの既定値テストを追加した。実worktreeの削除・home配備は行わない。

## 3日設定の検証と承認済みGC — 2026-09-16

既定値変更後に`bats tests/worktree-gc.bats tests/worktree-gc-fanout.bats`を実行し33/33成功。追加テストは単体・fan-outともage未指定で2日目を保持し3日目を候補とすることと、danglingへの適用を確認した。ShellCheck、shfmt、skill validator、Markdown formatter、git diff --checkも成功。locked閾値の既定値は既存のAGE_DAYSフォールバックを維持しており、専用の新規境界テストは追加していない。

続く明示的なGC依頼では、配備済みscriptに`--age-days 3 --locked-age-days 3`を渡して実環境を再診断した。task sourceとの差分が既定値の7→3だけであることを照合したうえで実行したもので、未merge sourceのhome配備ではない。候補は15件（Herdr3、Orca7、repo-local5）。ユーザー承認後の再診断でも同じ15パスだったため、同設定・`--max-removals 15`でapplyした。

自動削除は14件。残りの`hermes-workspace/.worktrees/news-interest-streams`はGit登録解除後にroot所有ビルド成果物の削除で失敗し、一部削除状態となった。権限昇格による自動後処理はruntimeの審査で拒否され、ユーザーが通常端末で後処理した後、親が対象ディレクトリの消失を確認した。15件すべての削除完了と、対象6repoのbranch refs不変を確認済み。root所有ファイルの削除失敗を防ぐengine改修は本PRに含めない。

これは先行する評価時点の「実適用未実施」を更新する運用記録であり、過去のfixture/実環境診断の結果を置き換えない。raw logは`/tmp/worktree-gc-age3-apply.log`、適用前後の照合は`/tmp/worktree-gc-age3-before-apply.json`と`/tmp/worktree-gc-age3-result.json`（後者は人間の後処理前、残り1件時点）。home配備は未実施。
