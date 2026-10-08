# 通常 APM payload 更新の記録（2026-10-09）

## 更新単位と適用 ADR

[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md) の「通常の APM payload refresh」単位。Tool Snapshot（[#391](https://github.com/treflebonbon/dotfiles/pull/391)）は main へ merge 済みで、採用済みの APM 0.33.0 を使う。親記録は [update-tools-skills-20261009.md](update-tools-skills-20261009.md)。

予定した変更: selected subtree に実差分のある exact pin（`apm.yml`）と floating 依存の `apm.lock.yaml` の更新、関連 test の独立期待値と本記録。Impeccable と Matt Pocock は別の更新単位で、この PR では変更しない。

## 候補と採否

全20依存の selected subtree を Git tree SHA で比較した（exact pin は pin 済み revision と upstream HEAD を比較）。

| 対象 | 判断 |
| --- | --- |
| Remotion `0b5db9da` → `32b241b9` | 採用。tree `17ddb25e` → `4d1a20d0`。captions／markup／video-editing 等の参照文書が変わった（上流 2 commit） |
| Modern Web Guidance `84ae7251` → `a9728684` | 採用。tree `df633f7d` → `80a6164d`。accessibility／css 等の guide 追加・更新（上流 2 commit） |
| security-audit、Orca CLI、Herdr | selected subtree 不変のため exact pin を維持 |
| anthropics `pdf`・`skill-creator`、shadcn、Orca `computer-use`・`orchestration`、find-skills | floating。content hash 不変で revision のみ lock へ自然反映 |
| Effect-TS、empirical-prompt-tuning、Vercel 5 skill、supabase | revision・payload とも不変 |
| Impeccable（HEAD `778c8a7b`）、Matt Pocock（HEAD `b0618bc4`） | 保留。別更新単位で、対応先 PR は未定、未比較・未検証。本 PR では pin・selected payload・配備 ledger とも不変（`package_type` の native 出力のみ変化） |

lock の `deployments` の差分は Modern Web Guidance 240 件と Remotion 62 件のみで、他の owner は不変。

更新全体は Impeccable と Matt Pocock が残るため未完了。追跡は親記録 [update-tools-skills-20261009.md](update-tools-skills-20261009.md) に置く。

## 検証

- APM 0.33.0 を `PYTHONPATH`／`PYTHONHOME` なしの空の隔離 cwd／HOME で使い、`scripts/generate-apm-lock.sh` で全20依存を一度の標準 install から再生成した（Nix snapshot の版と CLI 版の照合は成功）。
- 同じ生成で Matt Pocock の `package_type` が `marketplace_plugin` → `apm_package` に変わった。他の field・deployed file は不変で、Matt の `package_type` だけは APM の native 出力に従い `apm_package` を採用する（`runtime/skill-harness.md` 2026-09-08 の前例と同じ）。pin・selected payload・配備 ledger は不変。
- 採用 lock の SHA-256 は `7058c17bbafc3ed65284bc4a674643497fd463547b3cd0b9d73d43ae423d20e6`。別の空 runtime で `apm install --frozen` した前後で不変。`apm audit --ci` は 10/10 成功。Claude／Codex 各46 skill の payload が一致。
- `tests/apm-runtime.bats`・`tests/nix-devshell.bats` の独立期待値を新しい pin／hash／revision に更新し、50件が成功。
- 未検証: organization policy enforcement は Git remote のない隔離環境のため判定対象外。live skill directory と `chezmoi apply` には触れていない（受入後に live source で配備する）。
- 標準 `lefthook run test` は746件中729成功・22 skip・17失敗。失敗の内訳と番号は Tool Snapshot PR（#391）と同一で、dogfood 9件、`local-skills` 1件、managed-set gate 7件。gate 7件と `local-skills` 1件は変更前の main でも失敗する。dogfood 9件は環境要因と推定するが未確認。この変更は `apm.yml`／lock と期待値のみで、テストの例外化・削除はしていない。
