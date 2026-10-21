# OSV 依存関係修正の調査記録

## 依頼と確認済みの再現

2026-10-21、main の OSV Full Scan が報告した4件を最小限の依存関係変更で解消する。対象は `bun.lock` の `braces@3.0.3`（GHSA-vfj7-8cjw-p6xm）と `tests/experiments/rop-analysis/package-lock.json` の `brace-expansion@5.0.9`（GHSA-6j4f-fj2g-mc7p、GHSA-q2hr-2g5m-vwhr、GHSA-qhr7-859c-m2p7）。調査開始時点では、親が OSV Scanner v2.3.8 と v2.5.1、および lockfile ごとのスキャンで4件を再現・最小化済みで、証拠は `/tmp/codex/osv-diagnosis.dWWGPs/` にある。

## 更新単位と境界

今回の更新単位は、上記2 lockfile が固定する脆弱な依存解決の修正である。root の Ultracite/OXC は repo の開発ツールであり、その間接依存を変える作業には [`docs/conventions.md` の「ツール・スキル更新の追跡とレビュー`](../conventions.md#ツールスキル更新の追跡とレビュー)を適用する。experiment 側は既存の単一 `ts-morph` dependency の lockfile 更新である。root manifest の override を含め、依存元を追って再解決に必要と確認できたファイルだけを変更候補にする。広範な依存更新と OSV scanner の除外・ignore 設定は対象にしない。

ADR-0045 は llm-agents snapshot、通常の APM payload、Impeccable、Matt Pocock managed set の互換性・rollback 境界を独立させる判断であり、今回それらの payload、snapshot、manifest、lock を変更する根拠にはしない。過去の大規模なツール更新記録を今回の要件と混同せず、今回の OSV remediation を小さい独立単位として追跡する。

## 調査仮説

親が提示済みの仮説を順序どおり一つずつ検証する。

1. 互換範囲内の間接依存更新だけで4件が解消する。依存元 manifest の範囲内で再解決し、対象 lockfile だけの再スキャンが green になる。
2. 現行の依存元が脆弱版を必要とし、依存元の更新が必要である。脆弱な版の選択が現行制約で固定され、上流の更新候補なら safe release を許すことを確認する。
3. lockfile に不要な依存が残り、manifest からの再解決で除去できる。既存 caller / usage と install 契約を調べ、未使用の証拠がある場合に限って除去する。

## 予定変更と採否条件

- 最初に lockfile と各 dependency owner / caller / manifest / workflow を照合する。
- 採用する修正は OSV の対象4件を除去するための依存変更に限り、package manager で lockfile を生成する。OSV ignore、scanner の対象除外、無関係な tool / dependency 更新は却下する。
- manifest は、原因となる依存制約を解消する必要が証明された場合だけ変更する。root の `brace-expansion@5.0.9` override は base の lock に package entry も利用 dependency chain もない stale な no-op と確認されたため削除候補にし、direct package 版と minimum-release-age policy は維持する。
- root `braces` については、(1) preset 専用の公式 package / export distribution、(2) それがない場合に現在採用済みの preset だけを license と共に repo へ同梱して Ultracite dependency を外す案、(3) 現行構成を維持して upstream 修正を待つ案を比較し、必要ファイル・差分規模・同一挙動の検証方法・継続保守負担を記録する。比較・提案の完了前に独自 patch や新規 source build は行わない。
- 本記録は調査で根拠が変わった時点で更新し、最終的に採用・却下・未解決の候補、変更ファイル、生成方法、スキャンと関連検証結果を記す。

## 初期根拠

- 対象 CI: [OSV Full Scan run 39521608214](https://github.com/treflebonbon/dotfiles/actions/runs/39521608214)。
- 親の再現では両 lockfile を同時に指定した公式コンテナ `ghcr.io/google/osv-scanner:v2.5.1` の scan が exit 1、個別 scan は root `bun.lock` が1件、experiment `package-lock.json` が3件で exit 1。
- 親の初期依存鎖: `ultracite@7.12.4 -> fast-glob@3.3.3 -> micromatch@4.0.8 -> braces@3.0.3`、および `ts-morph@28 -> @ts-morph/common -> minimatch@10.2.6 -> brace-expansion^5.0.8`。
- これらは着手時点の観測であり、各 manifest / caller / lockfile と候補版の採用可能性を本調査で検証する。

## 2026-10-21 の実測・選択肢

### experiment lock

`tests/experiments/rop-analysis/package.json` は `ts-morph@28.0.0` を直接宣言し、`extract-ts.mjs` が実際に `Project` / `SyntaxKind` を使う。脆弱な `brace-expansion@5.0.9` は `minimatch@10.2.6` の `^5.0.8` 範囲内なので、manifest は変えず `npm update --package-lock-only --ignore-scripts --registry=https://registry.npmjs.org` で lock を生成し、5.0.12 を採用した。差分は package-lock の version / resolved / integrity の3値だけ。GitHub advisory の修正版は GHSA-6j4f が5.0.10、GHSA-qhr7 が5.0.11、GHSA-q2hr が5.0.12。5.0.12 は3件すべての修正版である ([6j4f](https://github.com/advisories/GHSA-6j4f-fj2g-mc7p), [qhr7](https://github.com/advisories/GHSA-qhr7-859c-m2p7), [q2hr](https://github.com/advisories/GHSA-q2hr-2g5m-vwhr))。

公式 registry を指定した `npm ci --ignore-scripts` は成功、audit は0件、実行前後の lock SHA-256 は `3de3307a893373e8d073f3a56729f6261bd59235ebc9866aad8bf27cda0f824b` で不変。親は同じ lock を CI 同 tag の公式 OSV Scanner v2.5.1 で独立スキャンし、exit 0 / 0件を確認済み。既存 unittest は24件中23件成功、1件が retired `local-skills/rop-visualizer/scripts/render.py` の不存在で失敗し、親も main `60116a1` で同じ失敗を確認した。今回の差分では直さない。現行 `extract-ts.mjs` を `/tmp/codex/task_10495ab5efbd-ts-morph.*/` の小さい TypeScript fixture で実行し、diagnostics 0 / AST node 2 を確認した。

### root braces の選択肢

現行 `braces` の latest は3.0.3で、advisory は affected `<=3.0.3`、patched version `None` ([GHSA-vfj7-8cjw-p6xm](https://github.com/advisories/GHSA-vfj7-8cjw-p6xm))。公式 npm metadata でも `ultracite@8.0.1` の latest 依存は `fast-glob@^3.3.3` / `find-workspaces@^0.3.1`、latest の `fast-glob@3.3.3` は `micromatch@^4.0.8`、latest の `micromatch@4.0.8` は `braces@^3.0.3` を維持する。互換範囲内の通常更新ではこの advisory は消えない。

1. **公式 export を維持**: npm 公開 package `ultracite@7.12.4` は `./oxlint/*` と `./oxfmt` を export するが、その同じ package が CLI と全 dependency tree を宣言する。npm registry search では公式 preset-only package を確認できなかったため、subpath export だけでは `braces` を外せない。
2. **現行 preset を同梱**: 固定済み tarball の `oxlint/core/index.mjs`（622行 / 26,139B）、`oxfmt/index.mjs`（29行 / 638B）、共有 `ignores.mjs`（78行 / 2,724B）で計729行 / 29,501B。型宣言3つも要り、npm package metadata は MIT を宣言する一方、tarball に root LICENSE は含まないため upstream notice を別途保つ必要がある。source 差分は root の2 config、`project-ignore-patterns.ts`、`lefthook.yml`、`package.json`（Ultracite と stale override を削除）、生成 `bun.lock`、同梱設定と license に限る。固定した upstream export と同梱設定の deep equality、`projectIgnorePatterns` の合成結果、同一対象に対する Oxlint / Oxfmt の出力を比較して挙動を検証した。Ultracite CLI caller は見つかっていないが、preset 設定の upstream 追随は以後手動保守となる。
3. **現行維持**: 追加の保守はないが、root の High advisory が残り、repo 全体の Full Scan は失敗する。

### 採用判断

親は Full Scan の全件解消を要件として option 2 を承認した。`scripts/vendor/ultracite/` に現行の2 preset と共有 ignore だけを固定し、Ultracite CLI dependency を外す。root の `brace-expansion@5.0.9` override は別 package に対する no-op で、root lock に package entry がなく、Ultracite 除去後も適用先がないため合わせて削除する。これは実依存の更新ではなく stale override の除去で、direct package 版と minimum-release-age policy は変更しない。公式 export 維持案は full CLI dependency tree を残すため却下し、現行維持案は High advisory と scan failure が残るため却下した。上流に preset-only package または `braces` の fixed dependency path が公開されたら再評価する。

## 最終検証

- `bun install --frozen-lockfile` は 66 packages を変更なく確認し、実行前後の `bun.lock` SHA-256 は `8b1a8a37f49ffdc9115dbea620bbea782bf7dc3f0c24bfad2d8e47d10dcfabf0` で不変。
- `bunx tsc --noEmit`、対象3ファイルの `bunx oxlint`、変更した設定・lock・文書の `bunx oxfmt --check` がすべて成功。
- `bats tests/ultracite-vendor.bats` は vendored presets の import と lint/format 除外を確認して成功。
- 保存済み root config と現在の config は、意図した `scripts/vendor/ultracite/config/**` ignore を除けば設定全体が一致。同じ3ファイルに対する baseline / candidate の Oxlint 診断は byte 一致し、Oxfmt 出力も実行時間の行以外は一致、両方 exit 0。
- 公式 OSV Scanner `v2.5.1` の最終 recursive scan は7 lockfile を走査し、0 findings / exit 0。
- 原因は、experiment の `package-lock.json` が互換範囲内で修正済みの `brace-expansion@5.0.12` ではなく旧 `5.0.9` を固定していたこと、および root が使用するものは Ultracite の2 preset と共有 ignore だけなのに、preset-only package がなく CLI 全体の依存鎖を導入していたこと。
- 親による二軸 review 後、次を一度実行した。Bats は 781.29 秒で完了し、plan 1,072 / pass 1,048 / skip 24 / fail 0 / exit 0。skip は hosted model、実 GitHub、Nix build、特定 runtime 等の opt-in 検証で、実行済みとしては数えない。

```bash
nix develop ./private_dot_config/nix-devshell#wsl --command nix develop .#wsl --command lefthook run test
```

実行時の TAP、setup log、exit code は `tmp/test-run.GKnH3w/` に保存。`git diff --check` は成功。
