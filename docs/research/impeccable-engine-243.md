# Issue #243 — Impeccable skill 4.2.2 / engine 0.1.3

2026-09-08 JST。第1単位の [PR #244](https://github.com/treflebonbon/dotfiles/pull/244)、第2単位の [PR #245](https://github.com/treflebonbon/dotfiles/pull/245) が merge された `b6d0030ca493f526927bb27b24ad66af9b428bc1` を baseline とし、同じ validated linked worktree の `chore-impeccable-engine` で第3単位を実装した。判断は [ADR-0053](../adr/0053-separate-impeccable-skill-and-engine.md)。過去2単位の証拠は [Tool Snapshot](ai-tool-snapshot-243.md) / [通常 APM](apm-payload-243.md) に残す。

## 採用物と配布

- APM skill / launcher: [公式4.2.2](https://github.com/pbakaus/impeccable/releases/tag/skill-v4.2.2)、exact commit `f64da20b07271b760e4e3133eef3b87942860f11`。selected content hash は `sha256:f825ecc6c155ff5db1bb20f18449e4ba45f413af74a2d42adeb348b7cc72204e`。
- Nix engine: [公式0.1.3](https://github.com/pbakaus/impeccable/releases/tag/engine-v0.1.3) の非 prerelease asset を固定取得する。Linux x64 は static PIE で、host では互換 wrapper / patch なしで build・起動した。ARM の実機起動は未確認。
- `modules/ai.nix` が package を両 devShell へ加え、`IMPECCABLE_BIN` に `/nix/store/.../bin/impeccable` を渡す。管理 hook は APM launcher の `hook` コマンドを呼び、launcher が設定する skill directory / self command を engine に引き継ぐ。
- engine 未配備・非実行可能、launcher 未配備は無言の成功終了とする。launcher に入る前の engine 確認により、自動ダウンロード経路へ進まない。内部エラー・非0終了では stdout と stderr を捨て、正常な JSON は pass-through する。

| system         | 公式 asset                | SHA-256                                                            |
| -------------- | ------------------------- | ------------------------------------------------------------------ |
| x86_64-linux   | `impeccable-linux-x64`    | `afc7a424e0bd6c606b7be4c773c70e87284afbdb41d748eb9a34f8a4478e57da` |
| aarch64-linux  | `impeccable-linux-arm64`  | `523c0a223ac0c1522489759a9f56dccb0b458b42d6a5c66e74e6fe2255af60ce` |
| aarch64-darwin | `impeccable-darwin-arm64` | `23821135d4c62f1428fd15ddb9e91d695402727f43b13a6eb3e9f31fc01b4072` |

## APM の再現性と discovery

APM 0.30.0 を隔離 cwd = HOME、専用 XDG directory / CODEX_HOME で起動し、最終 `apm.yml` に対して `apm install --target claude,codex --https` → 同じ引数の `--frozen` → `apm audit --ci` を実行した。旧 APM が混在する ambient `PYTHONPATH` / `PYTHONHOME` はこのプロセスから除いた。native lock をそのまま source へコピーし、手編集・整形はしていない。

frozen install 前後・audit 後の lock SHA-256 は `0ed5562ed58323349baa0245557320667e8297fbca7b4b0b7bd35648a955de98` で不変。audit は10/10成功。organization policy は隔離環境で適用できず warning / skip となる既存の限定がある。18依存のうち変更は Impeccable だけで、他17依存の解決 commit、selected hash、配備 ledger は baseline と一致した。

Claude / Codex 各42スキルの `SKILL.md`、本文、launcher、参照資料を確認した。両 target の全実体は一致し、1,202ファイルの hash と1,286配備 record を照合した。Matt25 membership は不変。Node 実装が除かれて launcher / data が入ったため、lock の行数差分は大きいが、他スキルの payload 更新は含まない。

## 実 engine の動作と上流との互換性

`tests/design-hook.bats` は repository の実際の管理 command → APM が配備した launcher → Nix engine を通す。試験用 HOME に global manifest と skill link を置き、project の有効化設定を作らず検査する。明示された runtime が欠ける場合は失敗し、未配備 skip を移行の成功には使わない。各呼出しを管理設定の5秒 / 30秒で制限し、時間内の正常終了を確認する。

- 即時の `gradient-text`、Stop へ遅延する `side-tab`、provider 別 JSON、重複抑制、編集閾値、Stop 再入、両 tier の収束を確認した。旧 `overused-font` は新版の advisory 分類により標準 hook の対象外になるため、deferred fixture を実分類に合わせた。
- clean、非 UI、機密・生成物、未編集 session は無言。Codex の `tool_input.command` を持つ `apply_patch` と、monorepo 内の symlink 経由の対象も検査できる。同じ symlink path の再編集と2回目の Stop は無言となる。symlink と実 path を別名で渡した場合の cache key 統合は確認項目に含めない。
- `hooks ignore-value ... --reason ...` は理由と日時を project の `detector.ignoreValues` に記録する。hook 設定や file / rule 全体の抑制へ拡大しない。初回 footer と短縮 footer、file / rule 全体に必要なユーザーの明示承認も維持した。
- project の明示的な `hook.enabled: false` は尊重する。設定は `.impeccable/config*.json`、既定 cache は project の `.impeccable/hook.cache.json` のまま。dotfiles に project ごとの設定は追加しない。
- `tests/codex-config.bats` は4管理 command の timeout / matcher と、障害注入時の失敗出力破棄・launcher 未配備・engine 未配備／非実行可能・正常 JSON の透過を確認する。stub はこの障害注入と配線だけに使う。

上流 `context` の active-hook 検出は launcher を呼ぶ新 command を Claude / Codex の project manifest 内で認識した。一方、user-global manifest だけでは旧4.1.2・新4.2.2とも `MANUAL_DETECTOR_REQUIRED` が残ることを実行で確認した。新版は project root から親を探索するが HOME 自体は探索しないためである。これは実際の global hook 起動とは別の検出上の制限で、今回の移行では維持される。検証のために project manifest を置いたのは隔離 probe だけであり、実配備や新規 project の自動チェックはそれに依存しない。

Codex の PostToolUse / Stop 出力は[公式 hook reference](https://learn.chatgpt.com/docs/hooks) と照合した。PostToolUse は `hookSpecificOutput.additionalContext`、Codex Stop は top-level `decision: block` / `reason` となり、runtime の出力を変換しない。Claude Stop は既存の `hookSpecificOutput.additionalContext` を維持する。

## 検証記録

再実行時は、隔離 APM 配備先の `scripts/impeccable` を `IMPECCABLE_HOOK_RUNTIME`、Nix engine の実行可能ファイルを `IMPECCABLE_BIN` に明示する。

| 実行                                                                                                                                                               | 結果                                                                                                |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| `bats tests/impeccable-engine.bats`                                                                                                                                | 3 system × default / wsl の実 package version・env path が一致、1/1成功。追加前は engine がなく失敗 |
| `nix build --impure --no-link --json --expr '<host shell の impeccable package>'`                                                                                  | Linux x64 engine 0.1.3を固定 asset から build 成功                                                  |
| `nix develop ./private_dot_config/nix-devshell#{default,wsl} --command bash -c 'test -x "$IMPECCABLE_BIN" && "$IMPECCABLE_BIN" engine-probe && impeccable --help'` | 両 shell の engine-probe / help 成功                                                                |
| 実体指定の `bats tests/design-hook.bats tests/apm-runtime.bats tests/impeccable-engine.bats`                                                                       | 29/29、skip 0。旧管理配線では即時 finding が失われる RED を確認後、launcher 配線で GREEN            |
| managed hook の関連3項目                                                                                                                                           | 3/3成功                                                                                             |
| `bunx tsc --noEmit`                                                                                                                                                | 成功                                                                                                |
| 実体指定の `bun run test`                                                                                                                                          | 実行中                                                                                              |
| 対象 lint / format、pre-commit / commit-msg                                                                                                                        | 実行前                                                                                              |

生ログは検証時の worktree 内 `tmp/issue-243-impeccable/` に保持する（Git 非追跡）。`materialization.json`、`payload-verification.json`、`engine-build.json`、`context-probe-verified/results.json`、`related.log`、`managed-hooks.log`、`full-suite.log` が対応する。将来この一時ディレクトリがなくても、採用 hash・検証方法・結果は本記録から確認できる。

## Verification Matrix

| AC                  | 種別        | 実行コマンドまたは理由                                                          | 結果     | 未確認理由                                                  |
| ------------------- | ----------- | ------------------------------------------------------------------------------- | -------- | ----------------------------------------------------------- |
| AC1 更新単位        | infra       | #244 → #245 の merge 後、`b6d0030` から第3単位を開始                            | 確認済み | 第3単位の受入はPR merge待ち                                 |
| AC2 snapshot        | infra       | 第1単位の Tool Snapshot 記録、今回 snapshot / lock は不変                       | 確認済み | —                                                           |
| AC3 対応環境        | CLI / infra | 3 system × 2 shell の engine 公開評価、Linux両 shell の起動                     | 確認済み | ARMの実機起動は環境なし。評価成功と区別                     |
| AC4 floor / 設定    | infra       | 第1単位の採用記録、今回floor / model / reasoning不変                            | 確認済み | —                                                           |
| AC5 Herdr           | CLI         | 第1単位の隔離起動・再接続・再起動・状態検出fixture                              | 確認済み | 実端末の画像描画は第1単位の記録どおり未確認                 |
| AC6 通常スキル      | infra       | 第2単位の配備対象差分記録、今回他17依存不変                                     | 確認済み | —                                                           |
| AC7 APM             | CLI / infra | native install → frozen hash不変 → audit 10/10                                  | 確認済み | organization policyは隔離環境で適用外                       |
| AC8 discovery       | CLI / infra | 両target42、Matt25、1,202 hash / 1,286 ledger照合                               | 確認済み | live配備はAC16                                              |
| AC9 Orca / 契約     | CLI         | 第2単位の3 guide取得、本単位でもsessionのguide取得                              | 確認済み | 契約変更なし                                                |
| AC10 Impeccable配布 | CLI / infra | 公式skill4.2.2 / engine0.1.3、Nix評価・host build、launcher前のengine存在確認   | 確認済み | ARM実機はなし                                               |
| AC11 global自動検査 | CLI         | 両providerの新規project、設定なしでPostToolUse / Stopに実 finding               | 確認済み | 上流contextのglobal設定探索は上記の既存制限あり             |
| AC12 検出動作       | CLI         | 実engineのimmediate / deep / dedupe / reentry / both-tier / quiet               | 確認済み | —                                                           |
| AC13 障害・運用     | CLI         | 実engine正常出力、4commandの障害注入、5秒 / 30秒、理由付き抑制・設定とcache所有 | 確認済み | —                                                           |
| AC14 実体           | CLI         | native APM launcherとNix engineを明示、関連29項目skip 0                         | 確認済み | —                                                           |
| AC15 回帰・説明     | CLI         | 関連Bats、型検査、full suiteとformatは進行中                                    | 未確認   | full suite完了後に更新                                      |
| AC16 配備境界       | infra       | validated linked worktreeだけを編集、taskからlive applyなし                     | 未確認   | 第3単位受入・merge後、live source同期・配備・通常起動を実施 |
