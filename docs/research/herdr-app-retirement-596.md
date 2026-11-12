# Herdr App 移行に伴う TUI 依存整理・復旧の検証（#596）

2026-11-12 時点の task source と隔離 fixture の検証記録。
2026-11-13 の受入前補足を末尾に追記した。
これは live 配備の完了報告ではない。

- root: `/home/ubuntu/orca/workspaces/dotfiles/herdr-app-596`
- branch: `test/herdr-app-596`
- base: `34fa46fdd7a7cd8e30b910b2d5c0be5bebf30e63`
- 実装 commit: `f9aa716ec1d2e21e902476cb9cb6928572bb0114`
- normal merge: `feat/herdr-app-migration` の
  `95a90ac21f60058da71c61c72d0c352514fd3d8a`
- 検証時の merge HEAD: `2f2142a5aa5465f3f3cd37980ec2455a0910e1db`

## 実装範囲

- 通常 devShell の Herdr TUI 供給、TUI 用 APM skill、copy-env plugin
  の source と apply 後登録、旧 `herdr-ask`、関連 permission を同じ
  source 変更で撤去した。旧 TUI データ、`~/.herdr/worktrees`、既存
  agent は削除・停止・移送していない。`.chezmoiignore` は旧データを
  home 配備の対象外として保持した。
- APM lock は `apm.yml` から公式生成し、frozen install と audit を通した。
  `herdr-peer-refactor` と公開 plugin 0.2.10 / revision `fd2a50c558288b3661e5066b94b1196453ef9269`、他 skill、旧配備撤去用
  baseline は維持した。TUI 専用公開 skill は App 対応済みとは案内しない。
- APM 配備計画・照合は、dependency 削除と旧配備 file の不在を明示
  できるよう拡張した。新 dependency、候補外更新、消し残しは拒否する。
- TUI 固有の隔離 VM 分岐、専用 test / helper、必須 runtime check の
  依存を削除した。raw Codex 隔離と reviewer の read-only Git metadata
  境界は残した。
- 拒否 fixture の read-only file、pre-push stub の開いた stdin、canonical test fixture
  の欠落を修正した。
- 利用手順、用語集、ADR-0088 とこの検証記録を更新した。live source での
  `chezmoi diff` / apply は行っていない。

## 受入条件ごとの結果

### AC 1 — 先行する worktree / Codex 協働の確認

**確認済み。** 先行 #595 の実機記録と親側の最終 runtime 証拠を照合した。
Issue #595 は親確認で 100/100 + 1/1、対象 4/4 pass / skip なし / exit 0、
clean HEAD。初回 99/100 の mount failure と後続成功は別の結果として
残し、原因解決済みとは扱わない。Ponytail hook warning は再発・原因未確定。

### AC 2 — TUI 依存の棚卸しと整理

**確認済み。** Nix 供給、APM dependency、hook、旧 command、permission、
指示、runtime guide、test と `runtime_test_checks.py` を整理した。

### AC 3 — TUI なしで配備が成功すること

**部分確認。** 旧 apply test は `.chezmoiignore` と dummy `dot_fixture` のみを
使っていたため、candidate 全体の配備根拠から外した。2026-11-13 の修正で
実 candidate source の `.chezmoiignore` と
`private_dot_config/nix-devshell/modules/ai.nix` を fixture に選び、実際の
`chezmoi apply` 後に配備先 `ai.nix` と source bytes が一致すること、TUI 用
`llm.herdr` entry がなく、旧 hook / plugin source が候補に含まれないこと、
旧登録・history が変わらないことを確認した。これは対象 source slice と
apply / hook 境界の検証であり、candidate 全体の配備証明ではない。詳細は
末尾の受入前補足と `/tmp/codex/ai-tools-w9_ncy0j/startup.log` を参照。

### AC 4 — APM の公式生成・frozen・audit・配備照合

**確認済み。** APM 公式 lock 生成、frozen install、`apm audit --ci` 10/10、
candidate/base 配備比較を確認した。未加工の baseline lock を比較元として、
Herdr dependency の削除1件と TUI skill の 4 file だけが削除対象になった。
Org policy は fixture remote から private `.github-private` を読めず、
強制評価が skip された。これは APM audit
の10検査とは別の状態として下記に記録した。

### AC 5 — raw 隔離・Git 境界と必須 check

**確認済み。** raw Codex と Git boundary の test を維持した。関連 suite 92/92 pass。削除 test
を要求する runtime / pre-push 配線は残っていない。

### AC 6 — 公開 plugin、他 skill、baseline、未対応 skill

**確認済み。** 公開 plugin pin / revision、他 skill、baseline は不変。
`herdr-peer-refactor` と歴史資料を残し、未対応 TUI skill は通常の App
手順から区別した。

### AC 7 — 状態・履歴・worktree・agent の保持

**確認済み。** source と fixture 以外の `~/.herdr`、状態・履歴・worktree、
稼働中 agent は操作していない。App と共用する worktree root も削除して
いない。

### AC 8 — App / Windows local / WSL remote の更新と失敗対応

**部分確認。** 隔離 WSL core fixture で `hc update --from` の
0.1.19→0.1.20、無効候補の拒否、古い 0.1.19 候補の no-op を実測した。
導入済み Windows App 0.1.15 と local core 0.1.20 は読み取り専用の版確認で
`runtime/ai-runtimes.md` の導入経路・版に一致した。前回の App Updates 表示で
両方 latest と確認した記録は履歴証跡として残るが、この補足では current の
Updates 状態を画面から再取得できなかった。`app.settings --section updates`
は成功応答を返したものの、computer accessibility query は Updates の要素を
返さず、表示状態を確認できなかった。App / core の更新・再起動はしていない。
WSL 実測は下記 receipt を参照。すべての通信・checksum fault や rollback は
追加条件としない。

### AC 9 — 固定版 TUI への復旧

**部分確認。** `tests/herdr-retirement.bats` の復旧ケースは base `34fa46f...` から TUI 0.9.5、APM skill revision `2ecf19a92fc3a7fff75b6ce3655ef04f4625ec01`、copy-env source / 登録、permission
を選んで restore fixture に戻し、Nix source / APM pin・metadata / hook と
chezmoi の登録・無効設定保持を確認する。frozen install・audit・配備照合は
この Bats の実行内容ではなく、別の隔離 APM runtime の証跡として扱う。
source/apply Bats の補足 receipt は 2026-11-13 の targeted run 40/40。
無関係な tool / pin は巻き戻していない。

### AC 10 — 主境界と source / live の分離

**先行証拠と source 境界を確認。** Windows App → WSL2 core → worktree →
既存 Codex entry point → 親の依頼・応答は #595 親側実測で成立した。
今回の fixture 配備は live 配備と分け、task source から apply していない。

### AC 11 — check、共通構成、live 手順

**source check 済み、live / full suite 待ち。** 3 supported systems の
共通 Nix 構成評価、targeted check、`runtime_test_checks.py` の必須 Bash / Treesitter
検証3/3、canonical harness Bats 47/47 は成功した。full canonical runner / full Bats と受入後の
live source apply は task 側で
実行せず、最終統合後に親が行う。live 未実行を移行完了とは扱わない。

### AC 12 — ADR、用語集、利用手順

**確認済み。** ADR-0088 と用語集を更新し、接続、起動、更新、切替、復旧、
未対応 skill、歴史記録、未確認事項を手順に分けた。

## 検証結果

### Nix、APM、配備

- `tests/runtime-security.bats` は 6/6 pass。3 supported systems すべてで
  Herdr TUI を含まず、残る CLI output は upstream と一致した。
  log: `/tmp/codex/ai-tools-a39_e3ak/startup.log`。
- `tests/apm-runtime.bats`、`tests/plan-apm-deployment.bats`、
  `tests/verify-apm-deployment.bats` は 54/54 pass。
  log root: `/tmp/codex/verification-env.shvwoh3j`。
- task branch の公式生成候補 lock SHA-256 は次の値。

  `73dc23164c19046d8286e40ec019dbd42eac3a72df08a82ad54991e3f0cb9415`

  隔離 runtime は dependency 20、`.agents` / `.claude` とも skill 46、
  APM audit 10/10。candidate deploy verifier は追加 0・削除 4 を確認した。
  log: `/tmp/codex/ai-tools-us3bwxjj/startup.log`。

- normal merge 後の最終 lock は current integration branch が採用していた
  native lock `4b93ce2ed94771780a6d3ebcd512342569b155db0eeb320390a1350aa770cc64`
  を選んだ。`73dc...` に含まれた4件の floating `resolved_commit` 更新を
  持ち込まず、base `34fa46f...` と比べ Herdr dependency と4配備 file
  だけを削除する。最終 lock でも frozen install 前後の SHA は不変、APM audit は10/10、配備 helper は
  dependency 20、各 target 46 skills、追加0・
  削除4を確認した。log: `/tmp/codex/ai-tools-uxglq2mk/startup.log`。
  同じ隔離 runtime で `apm audit --ci` を再実行した結果は
  `/tmp/codex/ai-tools-4laa20bf/startup.log`。org policy は private `.github-private` の読取り権がなく強制評価されなかった。

- `tests/codex-config.bats`、`tests/secret-isolation.bats`、
  `tests/verify-ai-tools.bats` は 92/92 pass、exit 0。
  log: `/tmp/codex/ai-tools-5fs5v80_/startup.log`。
- `tests/pre-push.bats` と `tests/pre-push-wiring.bats` は 30/30 pass。
  log root: `/tmp/codex/verification-env.gj90zxry`。
- `tests/run-canonical.bats` は 13/13 pass。
  `tests/verify-canonical.bats` は 34/34 pass。どちらも protected `verify-ai-tools.py --shell wsl --no-codex-build` 経由。
  logs: `/tmp/codex/ai-tools-13zj7hil/startup.log`、
  `/tmp/codex/ai-tools-rs0uiifz/startup.log`。
- merge 後の APM / retirement / Nix runtime security suite は 63/63 pass。
  内訳は APM 54、`tests/herdr-retirement.bats` 3、runtime security 6。
  log: `/tmp/codex/ai-tools-_0np2okv/startup.log`。
- merge 後の canonical harness Bats は 47/47 pass。log: `/tmp/codex/ai-tools-d3g9ne26/startup.log`。
- merge 後の Codex config / secret isolation / AI tool verification suite は
  92/92 pass。log: `/tmp/codex/ai-tools-iwqjg7jx/startup.log`。
- merge 後の pre-push / wiring tests は 30/30 pass。log root: `/tmp/codex/verification-env.bc5ks4mu`。
- `scripts/runtime_test_checks.py` は Bash 3.2 と固定 Treesitter checkout を
  渡して実行し、Codex repo state と Treesitter の3件すべてが pass、skip
  なし。Treesitter checkout は commit `0195cd62fa89950f34c0e0d648ea7897ab85d4d3`。log: `/tmp/codex/ai-tools-mh6__i93/startup.log`。
- merge commit の pre-commit hook は protected Nix entry 経由で pass。
  log: `/tmp/codex/ai-tools-f_1qzd99c/startup.log`。
- `git diff --check` と `git diff --cached --check` は pass。
  merge 前に実行した。

### chezmoi candidate / 復旧 fixture

- TUI なし candidate apply は Herdr command の呼出しなしで成功した。
  fixture の旧 user data は残った。
  `.chezmoiignore` を旧 `.herdr` state の保持に合わせた後も exit 0。
  result: `/tmp/codex/verification-env.yq38w9gr/exit-code`。
- integration branch の `tests/herdr-retirement.bats` でも history と既存
  worktree marker を保持した apply を確認した。
- 復旧 fixture は base source の `git show` 内容を使った。0.9.5 TUI package、
  同梱 APM skill、登録 hook、旧 command、permission を戻した。APM lock SHA
  は不変、audit 10/10、配備照合は dependency 21 / `.agents` 47 / `.claude` 47。TUI skill
  は指定 revision で両 target に戻った。
  log: `/tmp/codex/verification-env.fdyv4xho`。
- 検証は scratch HOME / XDG 内であり、live source、実 user の `.herdr`、
  App / Core を変更していない。

### WSL core 更新 fixture

- 公式 installer で checksum を確認した 0.1.20 binary を使い、隔離 fixture
  の 0.1.19 から `hc update --from` で更新した。private runtime socket 上の
  core restart 後も live terminal `t1` が継続した。
  log: `/tmp/codex/verification-env.8f5ylnnp`。
- 無効 fixture binary は `not a working hc` と拒否され、fixture の
  0.1.20 core と live terminal は保たれた。
  log: `/tmp/codex/verification-env._vysercg`。
- 0.1.20 に古い 0.1.19 binary を渡すと `now == was == hc 0.1.20` の
  no-op として報告され、terminal は継続した。
  log: `/tmp/codex/verification-env.d_a4kbvm`。
- Windows App 0.1.15 / local core 0.1.20 は読み取り専用で導入版を照合した。
  独立した Windows updater fixture は成立していないため、通常 App / shared core の更新実行はしない。現行 Updates 表示の再取得も未確認である。
  導入版の手順は [runtime guide](../../runtime/ai-runtimes.md) を参照。

## 失敗した試行と是正

- 初回 Codex config suite は read-only 拒否 fixture が次ケースへ残り失敗した。
  各固定 fixture path を内容確認後に書込み可能へ戻して再作成する処理を
  追加した。Nix store の `chezmoi` がない wrapper からも実行していたため、
  最終 suite は保護付き Nix gate で再実行した。
- 92件 suite の中間実行では、別の同時 suite が `/tmp/codex` の scratch を
  削除する race が sandbox の glob scan に出た。競合 suite の終了後に再実行し、
  92/92 pass を確認した。初期 log: `/tmp/codex/ai-tools-6r39g250/startup.log`。
- pre-push wiring 初回確認は test stub が `record` 時にも open stdin を
  `cat` し続けて停止した。record 時は stdin を読まない stub に直し、対象
  30 tests を再実行した。
- canonical test の初回 `verification_env.py` 実行は `with-env` 不在で拒否
  された。保護付き Nix gate へ切替えた後、fixture source に
  `tests/codex-repo-state.bats` がなく test 20 が失敗した。setup で実 source file
  をコピーする修正を加え、最後に両 canonical Bats を再確認した。
- touched Markdown 全体の lint では複数の既存 ADR・runtime doc・template に
  MD013 long line と MD025 heading が残った。今回の report は単体の
  `markdownlint-cli2` で通過した。log: `/tmp/codex/ai-tools-m3zlfy0n/startup.log`。
- `scripts/test-docs.sh` は `.chezmoiignore` が docs-only exception 外のため
  exit 2 を返し、doc-only test を実行しなかった。full suite は未実行。
- 最初の commit hook は未導入の `oxlint` / `oxfmt` package 解決で失敗した。
  protected Nix entry で frozen Bun dependencies を準備後に再実行したが、
  verifier complexity 28 の lint error で停止したため helper に処理を分割し、
  APM 54件と pre-commit を再確認して commit した。
- integration merge の既定 message は Conventional Commits の形式でなく
  `commit-msg` hook が拒否した。`chore: merge Herdr App integration` にして
  normal merge commit を作成した。
- 最終 APM install の初回 fixture は install 出力先と helper の runtime
  引数を分けており、配備 file の不在で失敗した。隔離 runtime を cwd にして
  frozen install / audit / helper をやり直し、最終 lock を確認した。

## 残作業と反映境界

- Integration tip `feat/herdr-app-migration` は normal merge commit `2f2142a5aa5465f3f3cd37980ec2455a0910e1db` で取り込んだ。
- merge 後、変更対象だけを live source の `chezmoi diff` で確認し、受入・
  merge 後に `chezmoi apply <対象の配備先パス>`、環境再読込、配備結果を
  照合する。task source から live へ apply しない。
- Windows App / local core の実更新と current Updates 表示、full canonical runner / full suite、受入後の live source 配備は親へ渡す。既定 latest download の fault 群、通信 / checksum failure、downgrade / rollback は
  この受入の追加条件にしない。

## 変更一覧と理由

- `.chezmoiignore` は `.herdr` を home 配備対象外のまま維持した。
  `apm.yml`、`apm.lock.yaml`、`private_dot_config/nix-devshell/modules/ai.nix`、
  `.herdr/herdr-plugin.toml`、`run_after_setup-herdr.sh` — TUI source 供給と
  自動登録を同じ変更で除去する。
- `private_dot_claude/settings.json.tmpl`、
  `private_dot_local/bin/executable_herdr-ask`、
  `scripts/herdr-codex-isolation.py`、関連 `tests/herdr*` / helper — 旧 command、
  専用 permission、TUI 固有隔離・copy-env test を撤去する。
- `scripts/runtime_test_checks.py`、`scripts/verify-ai-tools.py`、
  `scripts/secret-isolation-linux-vm.py`、
  `scripts/secret-isolation-probe.py`、
  `tests/fixtures/secret-isolation/linux-vm.nix` — 削除 test の必須配線と
  TUI 専用 VM branch を外し、raw Codex と人手 VM 検証を残す。
- `scripts/plan-apm-deployment.mjs`、`scripts/verify-apm-deployment.mjs`、
  `tests/apm-runtime.bats`、`tests/plan-apm-deployment.bats`、
  `tests/verify-apm-deployment.bats` — dependency 全削除を配備照合へ追加し、
  新規 dependency と旧 file の残存を拒否する。
- `tests/runtime-security.bats`、`tests/skills-plugin-verify.py`、
  `tests/verify-ai-tools.bats`、`tests/run-canonical.bats`、
  `tests/verify-canonical.bats`、`tests/pre-push.bats`、
  `tests/pre-push-wiring.bats`、`tests/codex-config.bats` — TUI 削除後の期待値と
  必須 test fixture を揃え、fixture 後片付けと stdin 境界を修正する。
- `GLOSSARY.md`、`README.md`、`docs/architecture.md`、
  `docs/conventions.md`、
  `docs/adr/0080-grant-reviewer-codex-read-only-git-metadata.md`、
  `docs/adr/0088-migrate-herdr-tui-to-app.md`、`runtime/*.md`、
  `templates/{bun,elixir,gleam,go,perl,rust}/DEVELOPMENT.md` — 現行 App 利用、
  未対応 TUI skill、歴史資料、更新・復旧・未確認範囲を区別する。
- current integration の `tests/herdr-retirement.bats` と、追加された ADR / research
  の歴史記録を通常 merge で保持した。ADR-0088 の復旧 baseline には
  Nix 0.9.5、APM skill revision、copy-env source / hook の旧固定値を記録する。
- ADR-0057 / 0063 と Herdr / AI tool の research 記録は、旧検証の歴史を残し
  現行 App の運用案内と混同しないよう通常 merge で更新した。

## 参照証跡

- worker readiness: `/tmp/codex/herdr-596-readiness.w65vTc/worker-readiness.json`
  （model / effort は観測 JSON に含まれず、切替なし）。
- #595 worker: `/tmp/codex/herdr-595-worker-evidence.4hkPsv/report.md`。
- #595 parent runtime: directory `/tmp/codex/herdr-implement-resume.dEJfG7/`, file `595-parent-final-runtime-evidence.md`。
- #595 merge / protected check: `/tmp/codex/herdr-merge-595.dFEn3H/report.md`。

## 2026-11-13 受入前補足

### `95a90ac` の作成経路

Git object と integration worktree の reflog では、
`95a90ac21f60058da71c61c72d0c352514fd3d8a` は
`feat/herdr-app-migration` 上で 2026-11-12 15:28:16 JST に
`refactor: retire Herdr TUI integration` として記録され、author / committer はともに `test <test@example.com>` だった。作成元を Git identity
以上に確かめる公開操作記録は、次の Codex session の public tool call にある。

```text
session root: /home/ubuntu/.codex/sessions
session date: 2026/11/12
session file:
rollout-2026-11-12T13-23-53-01a1cdff-6f5f-77b0-b48e-19118bb9ac0e.jsonl
item id: ctc_0aad2762e0956e88016af55c7c222087d0abd3a9131871b2d7
time: 2026-11-12 15:28:13.345 JST
cwd: /home/ubuntu/orca/workspaces/dotfiles/lancetfish
command: nix develop .#wsl --command \
  git commit -m 'refactor: retire Herdr TUI integration'
```

この操作は integration worktree の commit である。記録からこの Codex session の利用者・agent 名は特定できず、Git の `test` identity も実行主体の
氏名を示さないため、個人名は未確認とする。

対象 Bats は `tests/herdr-retirement.bats`。source は `git archive HEAD`
または `git archive HEAD <path>` で候補を一時 directory へ取り出し、そこに
`git init` する。Git baseline の `git diff` / `git show` は読み取りのみで、
テスト自体に `git commit` はない。`scripts/test.sh` と Bats `tests/setup_suite.bash` は継承した Git local environment variables を外し、
Bats suite はその設定を `tests/suite-git-env.bats` でも検査する。よって、
確認した 15:28 の commit 操作はこの apply fixture の Git ではなく、fixture
が integration branch へ向いたことを示す証跡も見つからなかった。原因を
fixture とする推測は未確認であり、記録上の実 commit 操作と区別する。

この補足中に `feat/herdr-app-migration` を変更していない。確認時の
integration tip は `d5fb373fe7ab441a74ff0eefb1dc6e2c58b637c6` で、この task worktree には通常 merge commit `5b8ee23cbb98656eefdc63d047ddf514d69cf66c` として
取り込まれている。

### AC3 / AC9 の fixture 境界と receipt

修正した `tests/herdr-retirement.bats` の復旧ケースは `PROJECT_ROOT` の
candidate `HEAD` から次の実 source だけを `git archive` し、隔離した
chezmoi source として使う。

- `.chezmoiignore`
- `private_dot_config/nix-devshell/modules/ai.nix`

この候補 slice に `run_after_setup-herdr.sh` と
`.herdr/herdr-plugin.toml` がないこと、`ai.nix` に `llm.herdr` がないことを
確認する。apply 先も `BATS_TEST_TMPDIR` 配下の HOME で、配備後 `ai.nix` と
選択した candidate source の bytes が一致し、以前作った copy-env 登録と
`.herdr/history` が残ることを確認する。比較用の復旧 source は base `34fa46f...` から限定した `git diff` (`ai.nix`, `apm.yml`, `apm.lock.yaml`, Claude permission) と `git show` した plugin manifest / after hook を組み立てる。
旧 hook の供給・登録を baseline 側で動かした後、candidate slice を apply
して source hook の不在・既存登録保持を確認し、最後に復旧 source と無効化
設定保持も確認する。

保護付きコマンドと receipt は次の通り。TAP は 40/40 pass、skip なし。

```bash
python3 scripts/verify-ai-tools.py "$PWD" --shell wsl --no-codex-build -- \
  bats tests/herdr-retirement.bats tests/plan-apm-deployment.bats \
  tests/verify-apm-deployment.bats
```

receipt: `/tmp/codex/ai-tools-w9_ncy0j/startup.log`。AC3 の旧 synthetic `dot_fixture` test は補助的な user-data 境界 test として残し、candidate
全体の配備証明には数えない。実 source slice と hook / 供給の連動を確認した
範囲は上記に限る。AC9 の Bats が確認するのは候補からの固定版復旧 source と
apply / 登録のふるまいであり、APM `install --frozen`・audit は別の APM fixture の証跡である。

### APM base 比較と drift 拒否

隔離 APM run の `/tmp/codex/herdr-596-final-apm.Krj0kE/verify.sh` は、
次のように baseline commit から元の lock を直接取得する。

```bash
git -C "$source_root" show \
  34fa46fdd7a7cd8e30b910b2d5c0be5bebf30e63:apm.lock.yaml \
  >"$work_root/base.lock.yaml"
```

`cmp` はこの file と同じ commit の `git show ...:apm.lock.yaml` の byte 一致を
返した。続けて candidate lock を frozen install 前後で比較し、
`apm audit --ci` の後、元 base file と candidate lock から `plan.json` を作り
verifier へ渡した。plan の候補は `herdrdev/herdr` / `skills/herdr` の1件のみで、
`added: []`、`removed` は次の4 path。

- `.agents/skills/herdr`
- `.agents/skills/herdr/SKILL.md`
- `.claude/skills/herdr`
- `.claude/skills/herdr/SKILL.md`

`/tmp/codex/ai-tools-uxglq2mk/startup.log` は frozen lock SHA `4b93ce2ed94771780a6d3ebcd512342569b155db0eeb320390a1350aa770cc64`、
APM audit 10/10、および verifier の `dependency 20、skill .agents=46 .claude=46、追加0・削除4` を記録する。Bats は未宣言の配備削除、削除
dependency の file 残存、候補外 hash drift、候補外 exact pin / ref / version drift を拒否する。これが加工前 base と削除予定集合のみで照合した証拠である。
以前の ADR の「helper が dependency 構成変更を受け付けないため base を先に
加工した」という説明は誤りで、ADR-0088 の末尾を上記の実測方式へ合わせて
修正した。追加・削除以外の source、pin、payload は変更していない。

### AC8 の導入版照合と未確認境界

今回の読み取り専用確認では、次の導入版を得た。

- `%LOCALAPPDATA%\Programs\herdr-app\herdr-app.exe` の ProductVersion / FileVersion はともに `0.1.15`。
- `%LOCALAPPDATA%\Programs\herdr-core\hc.exe --version` は `hc 0.1.20`。
- Herdr App process は稼働中。

これらは [runtime/ai-runtimes.md](../../runtime/ai-runtimes.md) の v0.1.15 App install/update と v0.1.20 core guide、Settings → Updates / Help → About / `hc.exe --version` 手順に一致する。app CLI の
`app.settings --section updates` は `{"ok":true}` を返したが、その後の read-only computer accessibility query では Updates UI element が見つからず、可視画面も
Updates pane ではなかったため current latest / pending state は確認できなかった。
App を適用更新・再起動せず、shared local core も update / restart していない。

current status を読むには、稼働中 App で Settings → Updates と Help → About を
表示し、その表示を観測する必要がある。`app.settings --section updates` は
呼び出したが、computer accessibility query が表示要素を返さなかったため、
今回の session では画面内容を確認できなかった。独立 updater fixture について
公式 source は `HERDR_APP_HOME` と `HERDR_RELEASES_URL` の分離口を示すが、
コピーした App が scratch 内の専用 core を選び、そこだけを更新する境界は
未検証である。参照: `/tmp/codex/herdr-implement-resume.dEJfG7/596-updater-primary-source-options.md`。

この補足で使った WSL 実測 receipt は次の通り。

- `/tmp/codex/verification-env.8f5ylnnp`: `hc update --from` で
  0.1.19→0.1.20。
- `/tmp/codex/verification-env._vysercg`: 無効候補の拒否と現行 fixture core
  保持。
- `/tmp/codex/verification-env.d_a4kbvm`: 古い候補の no-op。

前日の記録では App Updates の Check now が App / core を latest と表示したが、
current の同じ表示を今回再確認したとは扱わない。実行済みなのは上記 WSL fixture と導入版の read-only 確認である。通常の App / shared core で
`app.check_updates` / update / restart を行わず、安全に完了できる独立 Windows updater fixture の成功は未確認のまま親へ渡す。全種類の通信・checksum fault
と core downgrade / rollback を追加要求とはしない。

### この補足の check と残る境界

- 保護付き Bats run は 40/40 pass、skip なし。
  receipt: `/tmp/codex/ai-tools-w9_ncy0j/startup.log`。
  対象は retirement fixture、APM plan、APM verifier。
- `git diff --check` は pass。
- 保護付き `markdownlint-cli2` は exit 1、2 file に既存 MD013 / MD025 が
  計50件あった。lint error はすべて未変更行で、今回変更した行との重なりは
  0件。receipt: `/tmp/codex/ai-tools-yapje7i0/startup.log`。
- full canonical runner、full Bats、live source apply、App / core update は
  今回実行していない。前者と受入後 live source 手順は親の後続工程であり、
  この checkout から live source は変更していない。
- task worktree の source / report を commit した後も
  `feat/herdr-app-migration` と live 配備状態は変更しない。
