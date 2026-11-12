# Herdr App 移行に伴う TUI 依存整理・復旧の検証（#596）

2026-11-12 時点の task source と隔離 fixture の検証記録。
これは live 配備の完了報告ではない。

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
- 拒否 fixture の read-only file、pre-push stub の開いた stdin、canonical test fixture の欠落を修正した。
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

**確認済み。** candidate source の chezmoi fixture apply が成功した。
Herdr command が呼ばれないこと、TUI binary / hook / skill / permission が
配備されないことを確認した。fixture の `.herdr/keep.txt` は保持した。

### AC 4 — APM の公式生成・frozen・audit・配備照合

**確認済み。** APM 公式 lock 生成、frozen install、`apm audit --ci` 10/10、candidate/base 配備比較を確認した。新 dependency はなく、TUI skill の 4 file だけが削除対象になった。

### AC 5 — raw 隔離・Git 境界と必須 check

**確認済み。** raw Codex と Git boundary の test を維持した。関連 suite 92/92 pass。削除 test を要求する runtime / pre-push 配線は残っていない。

### AC 6 — 公開 plugin、他 skill、baseline、未対応 skill

**確認済み。** 公開 plugin pin / revision、他 skill、baseline は不変。
`herdr-peer-refactor` と歴史資料を残し、未対応 TUI skill は通常の App
手順から区別した。

### AC 7 — 状態・履歴・worktree・agent の保持

**確認済み。** source と fixture 以外の `~/.herdr`、状態・履歴・worktree、
稼働中 agent は操作していない。App と共用する worktree root も削除して
いない。

### AC 8 — App / Windows local / WSL remote の更新と失敗対応

**一部確認。** 隔離 WSL core fixture で `hc update --from` の 0.1.19→ 0.1.20、無効 binary の拒否、古い 0.1.19 候補の no-op を確認した。
既定の latest release download、通信 / checksum failure、rollback、Windows App / local core updater の実行は未確認。

### AC 9 — 固定版 TUI への復旧

**確認済み。** base `34fa46f...` の TUI 0.9.5、APM skill revision `2ecf19a92fc3a7fff75b6ce3655ef04f4625ec01`、copy-env source / 登録、permission
を restore fixture に戻した。frozen install、audit、配備照合が通った。
無関係な tool / pin は巻き戻していない。

### AC 10 — 主境界と source / live の分離

**先行証拠と source 境界を確認。** Windows App → WSL2 core → worktree →
既存 Codex entry point → 親の依頼・応答は #595 親側実測で成立した。
今回の fixture 配備は live 配備と分け、task source から apply していない。

### AC 11 — check、共通構成、live 手順

**source check 済み、live / canonical 待ち。** 3 supported systems の
共通 Nix 構成評価と targeted check は成功した。full canonical / full Bats
と受入後の live source apply は task 側で実行せず、最終統合後に親が行う。
live 未実行を移行完了とは扱わない。

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
- lock SHA-256 は次の値。

  `73dc23164c19046d8286e40ec019dbd42eac3a72df08a82ad54991e3f0cb9415`

  隔離 runtime は dependency 20、`.agents` / `.claude` とも skill 46、
  APM audit 10/10。candidate deploy verifier は追加 0・削除 4 を確認した。
  log: `/tmp/codex/ai-tools-us3bwxjj/startup.log`。

- `tests/codex-config.bats`、`tests/secret-isolation.bats`、
  `tests/verify-ai-tools.bats` は 92/92 pass、exit 0。
  log: `/tmp/codex/ai-tools-5fs5v80_/startup.log`。
- `tests/pre-push.bats` と `tests/pre-push-wiring.bats` は 30/30 pass。
  log root: `/tmp/codex/verification-env.gj90zxry`。
- `tests/run-canonical.bats` は 13/13 pass。
  `tests/verify-canonical.bats` は 34/34 pass。どちらも protected `verify-ai-tools.py --shell wsl --no-codex-build` 経由。
  logs: `/tmp/codex/ai-tools-13zj7hil/startup.log`、
  `/tmp/codex/ai-tools-rs0uiifz/startup.log`。
- `git diff --check` と `git diff --cached --check` は pass。
  commit 前に再実行する。

### chezmoi candidate / 復旧 fixture

- TUI なし candidate apply は Herdr command の呼出しなしで成功した。
  fixture の旧 user data は残った。
  `.chezmoiignore` を旧 `.herdr` state の保持に合わせた後も exit 0。
  result: `/tmp/codex/verification-env.yq38w9gr/exit-code`。
- 復旧 fixture は base source の `git show` 内容を使った。0.9.5 TUI package、
  同梱 APM skill、登録 hook、旧 command、permission を戻した。APM lock SHA
  は不変、audit 10/10、配備照合は dependency 21 / `.agents` 47 / `.claude` 47。TUI skill は指定 revision で両 target に戻った。
  log: `/tmp/codex/verification-env.fdyv4xho`。
- 検証は scratch HOME / XDG 内であり、live source、実 user の `.herdr`、
  App / Core を変更していない。

### WSL core 更新 fixture

- 公式 installer で checksum を確認した 0.1.20 binary を使い、隔離 fixture
  の 0.1.19 から `hc update --from` で更新した。private runtime socket 上の
  core restart 後も live terminal `t1` が継続した。
  log: `/tmp/codex/verification-env.8f5ylnnp`。
- 無効 fixture binary は `not a working hc` と拒否され、fixture の 0.1.20 core と live terminal は保たれた。
  log: `/tmp/codex/verification-env._vysercg`。
- 0.1.20 に古い 0.1.19 binary を渡すと `now == was == hc 0.1.20` の
  no-op として報告され、terminal は継続した。
  log: `/tmp/codex/verification-env.d_a4kbvm`。
- Windows App 0.1.15 / local core 0.1.20 は親の現在値確認のみ。独立した
  Windows fixture がなく更新実行はしていない。既定の latest download、
  通信 / checksum failure、rollback も未確認。導入版の CLI reference と
  更新手順は [runtime guide](../../runtime/ai-runtimes.md) を参照。

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
  `tests/codex-repo-state.bats` がなく test 20 が失敗した。setup で実 source file をコピーする修正を加え、最後に両 canonical Bats を再確認した。
- touched Markdown 全体の lint では複数の既存 ADR・runtime doc・template に
  MD013 long line と MD025 heading が残った。今回の report は修正後、単体の
  `markdownlint-cli2` で通過した。report lint log: `/tmp/codex/ai-tools-zefvg1ru/startup.log`。
- `scripts/test-docs.sh` は `.chezmoiignore` が docs-only exception 外のため
  exit 2 を返し、doc-only test を実行しなかった。full suite は未実行。

## 残作業と反映境界

- Integration tip `feat/herdr-app-migration` は task base より先へ進んでいた。
  task commit 後に通常 merge し、clean 状態を確認する。
- merge 後、変更対象だけを live source の `chezmoi diff` で確認し、受入・
  merge 後に `chezmoi apply <対象の配備先パス>`、環境再読込、配備結果を
  照合する。task source から live へ apply しない。
- App / Windows local core の更新、WSL の既定 latest update と通信 / checksum failure、rollback、full canonical / full suite は未実行のまま
  親へ渡す。

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

## 参照証跡

- worker readiness: `/tmp/codex/herdr-596-readiness.w65vTc/worker-readiness.json`
  （model / effort は観測 JSON に含まれず、切替なし）。
- #595 worker: `/tmp/codex/herdr-595-worker-evidence.4hkPsv/report.md`。
- #595 parent runtime: directory `/tmp/codex/herdr-implement-resume.dEJfG7/`, file `595-parent-final-runtime-evidence.md`。
- #595 merge / protected check: `/tmp/codex/herdr-merge-595.dFEn3H/report.md`。
