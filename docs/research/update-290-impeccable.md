# Issue #290 — Impeccable skill 4.3.1 / engine 0.1.5

2026-09-10。親 [#283](https://github.com/treflebonbon/dotfiles/issues/283) の更新単位として、通常 APM 更新 `f423852` を baseline に、Impeccable の skill・launcher・固定 engine を一組で source へ採用した。配布経路は [ADR-0053](../adr/0053-separate-impeccable-skill-and-engine.md) のまま。検証済み候補の採用を coordinator が承認し、worker が source に反映した。commit は coordinator が直列で行い、live 配備は受入・merge 後に残す。

## 採用物

| 対象 | 更新前 | 採用値 | 判断 |
| --- | --- | --- | --- |
| APM | 0.30.0 | 0.30.0 | #288 で確定した実 binary を維持 |
| skill / launcher | 4.2.2、`f64da20b07271b760e4e3133eef3b87942860f11` | 4.3.1、`cd12f8660e2dde57b9615c8a6b8ea674101f9cfc` | 全 selected payload 比較、APM と実 hook ゲートを通過 |
| engine | 0.1.3 | 0.1.5、release commit `112703d5bf2469574758e0ddc5baf8e03c958f58` | 3 system asset/hash・Nix 評価、host build・起動を通過 |
| 管理 hook | Claude / Codex global PostToolUse / Stop | command・matcher・timeout 不変 | 既存配線で候補実体を検証 |
| 非 Impeccable 依存 | 通常17依存と Matt25 | 18 dependency block 全体が不変 | revision-only の進行もなく、baseline を維持 |

[skill-v4.3.1](https://github.com/pbakaus/impeccable/releases/tag/skill-v4.3.1) と [engine-v0.1.5](https://github.com/pbakaus/impeccable/releases/tag/engine-v0.1.5) は、入口で各1回 `gh api repos/pbakaus/impeccable/releases/tags/<tag>` と `gh api repos/pbakaus/impeccable/commits/<tag>` を照会して固定した。両 release は draft=false / prerelease=false。以後 tag / HEAD を追い直していない。skill の選択 path は `.agents/skills/impeccable`、engine は既存 Nix package の固定 release asset のままで、universal installer・新規 override・hook 実行時の自動取得を採用していない。

APM は `/nix/store/r08b589k4w0zap14lf556mq52fmmpwbd-apm-0.30.0/bin/apm` を使用した。採用 engine の host 出力は `/nix/store/y9pk751z9njx5pq50j4niwn0hf5n9w61-impeccable-0.1.5/bin/impeccable`。実 `engine-probe` は `impeccable-engine 0.1.5` を返した。

## Selected payload と互換性

現行・候補の全56ファイルを、隔離 APM materialization と exact Git tree の blob ID で照合した。tree は `5d1803e02461e06ea26361bd642104924da158c8` → `06efff78a5233850e8477632d577e700c9bd7994`。追加・削除なし、変更12ファイルである。

- selected content hash（更新前）: `sha256:f825ecc6c155ff5db1bb20f18449e4ba45f413af74a2d42adeb348b7cc72204e`
- selected content hash（採用）: `sha256:851788575191830d96380cc96260f17ccd491feb608ed59c04d298093b544beb`

[固定 commit 間の比較](https://github.com/pbakaus/impeccable/compare/f64da20b07271b760e4e3133eef3b87942860f11...cd12f8660e2dde57b9615c8a6b8ea674101f9cfc) を読み、次の内容を確認した。

- `scripts/VERSION` と POSIX / Windows launcher: engine 0.1.5 に整合し、cache 作成・書込みや download 失敗の診断を追加する。`IMPECCABLE_BIN` の優先経路は不変。
- `SKILL.md` と `reference/new-work.md`: launcher 不可時の説明と許可された直接 context 読取り、craft-floor の読取り、新しい surface の目的確認を明確化する。承認済みの作業・確認や権限は上位の user / AGENTS 契約を優先する。
- asset producer の agent / degraded reference と `reference/visualize.md` / `new-work.md`: crop・prompt-file・明示出力を使う実コマンドへ整合し、透明素材の native PNG alpha と画像確認を要求する。
- documenter の agent / degraded reference と `new-work.md`: 通常の拡張では既存 system を保持し、既存 drift を無断修復しない。新しい world / 承認済み system 変更では DESIGN.md と sidecar を揃える。
- `reference/live.md` / `live-setup.md`: local development の範囲を明確化し、production CSP や browser security の緩和を禁止する。

同梱4 agent の TOML は `developer_instructions` 以外すべて不変。Claude / Codex 管理モデル・権限設定、project opt-in、理由付き `ignore-value` と file / rule 全体の明示承認境界を変更していない。管理 hook は engine と launcher の存在を確認してから実行するため、launcher の自動取得には進まない。

engine の任意 `generate-image` コマンドには、上流で既定モデルを `gpt-image-2` から `gpt-image-2.5-flare` へ変える変更が含まれる（[採用 engine source](https://github.com/pbakaus/impeccable/blob/112703d5bf2469574758e0ddc5baf8e03c958f58/crates/context/src/generate_image.rs)）。これは管理モデル設定と区別する。今回その API は呼ばず、画像生成の品質・課金 API・native transparency の実サービス動作は未検証である。画像 API fallback の利用方針や credential は変更していない。

## 3 system の固定 asset

公式 release から binary と隣接 `.sha256` を取得し、実 bytes、checksum 本文、GitHub release metadata の digest / size が全件一致した。Nix は `https://github.com/pbakaus/impeccable/releases/download/engine-v0.1.5/<asset>` を既存の `fetchurl` で取得する。

| system | asset / ID | 更新前 Nix hash | 採用 Nix hash |
| --- | --- | --- | --- |
| x86_64-linux | `impeccable-linux-x64` / 551511146 | `sha256-r8ekJOC9bGBre+THc8cOhyhK+9tB10jrmjT4pEeOV9o=` | `sha256-z1IxpLGuZplshbAzgAsdrQeX5ZDq4vIe8leUMK8Yfxk=` |
| aarch64-linux | `impeccable-linux-arm64` / 551511130 | `sha256-UjwKIjrAwVIkiXWan1bcywtFi0LWpcZudOb+IlWvYM4=` | `sha256-vE+ii8jMuwGHlamaTs6VraiYpvGIXxQoE4nQ5u8qL5g=` |
| aarch64-darwin | `impeccable-darwin-arm64` / 551511126 | `sha256-I4IRNdTGLxQo/RXduekdaVQCcn9DsTpus+nzH8AbQHI=` | `sha256-DUi24WqpdmT9vmB9XamuMg44mhhD4P8TKPjCUwUwMg0=` |

3 system × default / wsl の実 package 出力と `IMPECCABLE_BIN` path は既存 Nix 統合テストで確認した。実機起動は x86_64-linux host で確認し、ARM の評価や asset 一致を実機起動の成功とは扱わない。

## Native lock と配布の検証

`tmp/update-290/runtime/` を cwd と HOME にし、XDG cache/config/data/state/runtime、CODEX_HOME、APM_CACHE_DIR も専用配置にした。採用済み lock を seed として byte コピーし、実 manifest の Impeccable exact pin だけ変更して次を実行した。他依存の一時 pin や lock の手編集・再整形は使っていない。

```sh
apm install --target claude,codex --https
apm install --frozen --target claude,codex --https
apm audit --ci
```

3コマンドとも exit0。native install / frozen / audit 後の lock SHA-256 はすべて `144bf375db3942b1185fc5d73ebcb4965121b27e52bed1ef40b717849fd93c53`。source はこの native bytes を採用した。manifest SHA-256 は `9b3af697ddea6273b6c7f77d57710e970bde08fbd30e62063e3297e2f156a9d5`。更新前 lock は `c15f6e15b89ef11c9e3c43ce149088239a2db44f31f8a833daa728f47e5a340a`。

hub / Claude 各43スキル、全602ファイル対が一致し、dependency hash と deployment ledger hash をそれぞれ1,204件、実 bytes と照合した。全1,290 ledger record の membership / owners / active_owner / scope / runtime は不変。変更は Impeccable 12ファイル × 2 target の24 hash だけで、非 Impeccable 18依存は revision を含む全ブロックが不変だった。実 manifest の exact 6件だけ `resolved_ref` を持ち、floating 13件は未固定のままである。

audit は10/10、drift なし。organization enforcement は隔離 cwd に Git remote がなく適用外で、baseline と同じ制限。includes-consent は local include がなく対象外。required target や drift 検証の skip はない。

## 実 engine ゲートと source 検証

現 engine 0.1.3 の baseline は coordinator の `tmp/update-283/t2-current-hook-gate.log` で14/14 PASS。候補は coordinator が `bash tmp/update-290/run-engine-gate.sh` を既存権限で実行し、exit0 を確認した。専用 `engine-home/` で候補 user flake の host package を `nix build --impure --no-link --no-write-lock-file --json --expr ...` により build した。worker の Nix / Unix socket 制限を回避する操作は行っていない。

検証では、実 store binary を `IMPECCABLE_BIN`、隔離 APM の実 `scripts/impeccable` を `IMPECCABLE_HOOK_RUNTIME` に明示した。既存の挙動テストは無変更で、package 出力テストの期待版だけ0.1.5に整合した。

| 検証 / 実行コマンド | 結果 | 証跡（`tmp/update-290/`） |
| --- | --- | --- |
| 全 selected tree / asset 照合 | PASS、56ファイルと3 asset | `selected-tree-verification.json`、`asset-verification.json` |
| native install / frozen / audit | PASS、exit0、lock 不変、audit 10/10 | 各 `.log` / `-result.json` |
| discovery / 配布 hash / 非対象 drift | PASS、43/43、非対象18依存不変 | `payload-verification.json` |
| Nix host build / 実 launcher `engine-probe` | PASS、0.1.5 | `engine-build.json`、`engine-build.log`、`engine-probe.log` |
| `bats <candidate-source>/tests/design-hook.bats <candidate-source>/tests/impeccable-engine.bats` | PASS、14/14、skip 0 | `engine-hook-gate.log` |
| `bats --filter 'managed Design Hook commands discard failed runtime output and fail open' tests/codex-config.bats` | PASS、1/1、skip 0 | `managed-failure-gate.log` |
| `bats tests/apm-runtime.bats tests/apm-cache-refresh.bats tests/workflow-contract.bats` | exit0、40実行 PASS / 1 skip | `source-related.log` / `source-related-result.json` |
| 親の full Bats / 必要な隔離 source dry-run | #295 の最終検証に残す | 必須 runtime 設定付きで coordinator が実行 |
| live 配備 / ARM 実機起動 | 未実施 | live は受入・merge後。ARM 実機なし |

実 hook では per-edit / Stop、両 provider の正常出力、quiet、dedupe・編集閾値・再入、both-tier の無言への収束、symlink を含む monorepo、project 設定/cache の所有権、理由付き抑制と policy footer を確認した。管理側では4 command の失敗 stdout 破棄、非0を fail-open、engine 不在時の launcher 非到達、正常出力の透過を既存の障害注入テストで確認した。timeout は既存の5秒 / 30秒を使い、hook を無効化したり期待動作を緩めたりしていない。

source 反映後の関連41テストは専用 HOME / XDG / CODEX_HOME で実行した。skip 1件は `repo-local Agent skill deploy target is absent` で、worker runtime が source の `.agents` を mount する場合の既存分岐である。候補の隔離 discovery / 配布照合や実 engine ゲートを skip したものではない。runtime mount のない環境での同チェックと full Bats は coordinator の最終検証に残す。

coordinator の artifact hash と、採用する実体の bytes を worker が再照合した。engine SHA-256 は `cf5231a4b1ae66996c85b033800b1dad0797e590eae2f21ef2579430af187f19`、launcher は `39d9600489073e227e4f4d55c451ce4252a6632ed7ae37923efbbcbc91f16d07`、package 式は `fde039bf1569fdcf9a13990ceace4ad26c5cb507b34c977f51311213d6517c65`。検証時の user flake.lock は `0e1b06a2ecfebfa6e03c29ba91844c19a7265aad65e6053b49418b52ab3c2c72` だった。生ログと全コマンドは同 scratch に保持し、一時成果物がなくても採用値と確認範囲は本記録から判断できる。

今回の変更は manifest / native lock、固定 engine package、既存2テストの pin/hash/版期待値、runtime の現行記述と本記録である。次の Matt 単位はこの確定 pair を non-Matt baseline とし、coordinator の atomic commit を参照する。既存 #243 の履歴は変更せず、最終 full suite、commit、受入後の live 配備はそれぞれ後続の境界で管理する。
