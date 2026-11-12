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

**部分確認。** 復旧 Bats は base `34fa46f...` の TUI 0.9.5 を選ぶ。

- APM skill revision は `2ecf19a92fc3a7fff75b6ce3655ef04f4625ec01`。
- source として copy-env、登録 hook、permission を復元する。
- Nix / APM pin・metadata、hook と登録、無効設定保持を確認する。
- frozen install / audit / 配備照合は別の隔離 APM runtime で確認した。
- 2026-11-13 の source/apply Bats は 40/40 pass。
- 無関係な tool / pin は巻き戻していない。

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
- 独立 Windows updater fixture は成立していないため、App / shared core は
  更新しない。current Updates 表示は未確認。
- 導入版の手順は [runtime guide](../../runtime/ai-runtimes.md) を参照。

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
  照合する。task source から live へ apply しない。source から消した
  `herdr-ask` は apply だけでは配備先から消えないため、[旧 TUI 配備物の
  残存確認・承認付き撤去・完了確認](../../runtime/ai-runtimes.md#切替後の旧-tui-配備物)
  も行う。旧 APM skill の残存も確認し、未確認・保留なら移行完了としない。
- Windows App / local core の実更新と current Updates 表示は親へ渡す。
- full canonical runner / full suite と受入後の live source 配備も親の後続。
- 既定 latest download の fault 群や通信 / checksum failure、
  downgrade / rollback は追加条件にしない。

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

- commit: `95a90ac21f60058da71c61c72d0c352514fd3d8a`
- branch / time: `feat/herdr-app-migration`, 2026-11-12 15:28:16 JST
- subject: `refactor: retire Herdr TUI integration`
- Git author / committer: `test <test@example.com>`
- 作成操作は次の public Codex tool call で確認した。

```text
session: /home/ubuntu/.codex/sessions/2026/11/12/
  rollout-2026-11-12T13-23-53-01a1cdff-6f5f-77b0-b48e-19118bb9ac0e.jsonl
item id: ctc_0aad2762e0956e88016af55c7c222087d0abd3a9131871b2d7
time: 2026-11-12 15:28:13.345 JST
cwd: /home/ubuntu/orca/workspaces/dotfiles/lancetfish
command: nix develop .#wsl --command \
  git commit -m 'refactor: retire Herdr TUI integration'
```

- 作成操作は integration worktree 上で行われた。
- session と Git identity から実行者の agent / 利用者名は分からない。
- 対象 Bats は `tests/herdr-retirement.bats`。
- fixture は `git archive HEAD` で source を一時 directory へ取り出し、
  local repo に `git init` する。
- `git diff` / `git show` は読み取りのみで、test 自体に commit はない。
- `scripts/test.sh` と `tests/setup_suite.bash` は Git local env を解除する。
- `tests/suite-git-env.bats` はこの fixture 境界を検査する。
- 15:28 の commit は apply fixture の Git ではない。
- fixture が integration branch に向いた証拠はなく、原因は断定しない。
- integration tip: `d5fb373fe7ab441a74ff0eefb1dc6e2c58b637c6`
- task worktree merge: `5b8ee23cbb98656eefdc63d047ddf514d69cf66c`
- この補足中に integration branch は変更していない。

### AC3 / AC9 の fixture 境界と receipt

修正した `tests/herdr-retirement.bats` の復旧 case は candidate `HEAD` から
実 source を `git archive` して隔離 chezmoi source を作る。

- `.chezmoiignore`
- `private_dot_config/nix-devshell/modules/ai.nix`

- candidate slice に旧 hook と plugin manifest がないことを確認する。
- candidate `ai.nix` に `llm.herdr` entry がないことを確認する。
- apply target は `BATS_TEST_TMPDIR` 配下の隔離 HOME。
- apply 後の `ai.nix` が candidate source と byte 一致することを確認する。
- 既存 copy-env 登録と `.herdr/history` が残ることを確認する。
- 復旧 source は base `34fa46f...` の限定差分と旧 hook から組み立てる。
- baseline source を apply 後、candidate slice を apply して登録保持を確認する。
- 最後に復旧 source と利用者の無効化設定保持を確認する。

保護付きコマンドと receipt は次の通り。TAP は 40/40 pass、skip なし。

```bash
python3 scripts/verify-ai-tools.py "$PWD" --shell wsl --no-codex-build -- \
  bats tests/herdr-retirement.bats tests/plan-apm-deployment.bats \
  tests/verify-apm-deployment.bats
```

receipt: `/tmp/codex/ai-tools-w9_ncy0j/startup.log`。

- 旧 synthetic `dot_fixture` test は user-data 境界だけを確認する。
- その test を candidate 全体の配備証明には数えない。
- 新 fixture は実 source slice と apply / hook 境界を確認する。
- AC9 Bats は固定版 source の復旧と apply / 登録動作を確認する。
- APM `install --frozen` と audit は別 APM fixture の証跡とする。

### APM base 比較と drift 拒否

隔離 APM run の script は baseline commit から元 lock を直接取得する。
script: `/tmp/codex/herdr-596-final-apm.Krj0kE/verify.sh`

```bash
git -C "$source_root" show \
  34fa46fdd7a7cd8e30b910b2d5c0be5bebf30e63:apm.lock.yaml \
  >"$work_root/base.lock.yaml"
```

- `cmp` は元 base と同一 commit の `git show` との byte 一致を返した。
- frozen install の前後で candidate lock の hash が不変だった。
- 続けて `apm audit --ci`、plan 作成、verifier を実行した。
- plan は `herdrdev/herdr` / `skills/herdr` の削除1件。
- `added` は空で、`removed` は次の4 path。

- `.agents/skills/herdr`
- `.agents/skills/herdr/SKILL.md`
- `.claude/skills/herdr`
- `.claude/skills/herdr/SKILL.md`

- final lock SHA:

  ```text
  4b93ce2ed94771780a6d3ebcd512342569b155db0eeb320390a1350aa770cc64
  ```

- Startup receipt: `/tmp/codex/ai-tools-uxglq2mk/startup.log`。
- APM audit は 10/10。
- verifier: dependency 20、`.agents` / `.claude` は各46、追加0・削除4。
- Bats は未宣言削除と削除 dependency の配備残りを拒否する。
- Bats は候補外 hash drift と exact pin / ref / version drift を拒否する。
- 以上は未加工 base と削除予定集合で比較した証拠。
- ADR-0088 の旧「base を加工した」説明を実測方式へ修正した。
- source、pin、payload は変更していない。

### AC8 の導入版照合と未確認境界

今回の読み取り専用確認で得た導入版:

- App executable: `%LOCALAPPDATA%\Programs\herdr-app\herdr-app.exe`
- App ProductVersion / FileVersion はともに `0.1.15`。
- Local core executable: `%LOCALAPPDATA%\Programs\herdr-core\hc.exe`
- `hc.exe --version`: `hc 0.1.20`。
- Herdr App process は稼働中。

- 版の手順は [runtime/ai-runtimes.md](../../runtime/ai-runtimes.md) に記録済み。
- 版確認には Settings → Updates、Help → About、`hc.exe --version` を使う。
- `app.settings --section updates` は `{"ok":true}` を返した。
- read-only accessibility query は Updates 要素を返さなかった。
- 可視画面も Updates pane でなく、current latest / pending は未確認。
- App と shared local core は更新・再起動していない。
- current status は App の Settings → Updates / Help → About で読める。
- app command 後の画面をこの session では取得できなかった。
- 公式 source は `HERDR_APP_HOME` と `HERDR_RELEASES_URL` を示す。
- scratch 専用 core の選択と更新先隔離は未検証。
- updater source directory: `/tmp/codex/herdr-implement-resume.dEJfG7/`
- updater source file: `596-updater-primary-source-options.md`

この補足で使った WSL 実測 receipt:

- `/tmp/codex/verification-env.8f5ylnnp`: `hc update --from` で0.1.19→0.1.20。
- `/tmp/codex/verification-env._vysercg`: 無効候補を拒否し、fixture coreを保持。
- `/tmp/codex/verification-env.d_a4kbvm`: 古い候補は no-op になった。
- 前日の App Updates は App / core を latest と表示した。
- その値は前回記録であり current state の再確認ではない。
- App / shared core では `app.check_updates` / update / restart をしていない。
- 独立 Windows updater fixture の成功は未確認のまま親へ渡す。
- 通信 / checksum fault と core downgrade / rollback は追加条件にしない。

### この補足の check と残る境界

- 保護付き Bats run は 40/40 pass、skip なし。
  receipt: `/tmp/codex/ai-tools-w9_ncy0j/startup.log`。
  対象は retirement fixture、APM plan、APM verifier。
- `git diff --check` は pass。
- Markdownlint は exit 1、既存 MD013 / MD025 が計50件。
- lint error はすべて未変更行。今回変更した行との重なりは0件。
- Lint receipt: `/tmp/codex/ai-tools-xblb6mfm/startup.log`。
- full canonical runner、full Bats、live source apply、App / core update は
  今回実行していない。前者と受入後 live source 手順は親の後続工程であり、
  この checkout から live source は変更していない。
- task worktree の source / report を commit した後も
  `feat/herdr-app-migration` と live 配備状態は変更しない。

## 2026-11-13 Claude Opus レビュー後の修正

規約・仕様を別々の fresh Claude Opus でレビューし、規約 P3×3、仕様 P2×1・P3×3 の報告を確認した。仕様の verifier 説明は曖昧さ、復旧 fixture は将来の保守懸念として扱い、現在の実機不良とは区別した。

- source から旧 `herdr-ask` を消しても apply は配備先から消さず、diff が空でも残ることを、保護付きの使い捨て source／配備先で再現した。live の旧コマンドや skill は変更していない。
- [切替手順](../../runtime/ai-runtimes.md#切替後の旧-tui-配備物)へ旧コマンド・両 runtime の旧 APM skill の残存確認、固定 baseline との照合、対象を示した撤去承認、完了判定を追加した。未知・変更済み・symlink は保持し、残存や保留があれば未完了とする。APM の prune は実結果で確認し、live verifier の PASS だけでは撤去完了としない。
- TUI 専用 peer の入口に App 非対応を明記し、計画済み dependency 削除を許す verifier の範囲と5 CLIの説明、ADR の TUI 表記を整合した。
- 公開 plugin pin の重複した固定値検査を二つのテストから外した。pin 自体と公開 payload は変更していない。
- `tests/fixtures/herdr/restore-tui.patch` に受入時の TUI 撤去差分だけを固定した。復旧テストは現在 HEAD と昔の baseline の4ファイル全差分を生成せず、この差分だけを一時 source に戻す。別 skill の revision を更新した fixture を用意し、APM の候補外 metadata・配備 ledger、Nix・permission の他設定、現行 flake lock の不変を照合する。固定した復旧 patch が将来の source に適用できない場合は失敗し、全ファイルを古い版へ戻す代替はしない。
- 保護付き `verify-ai-tools.py --shell wsl --no-codex-build` から retirement・APM runtime・autonomous peer contract の関連 Bats を実行し、29/29 成功、skip0、exit0を確認した。実ログは `/tmp/codex/ai-tools-koyj2q1y/startup.log` と `exit-code`。

修正後の独立再レビューと clean commit の最終 canonical 結果は後続の生成記録・PR 本文へ保存する。merge、live 配備、実環境の旧配備物撤去は未実施。
