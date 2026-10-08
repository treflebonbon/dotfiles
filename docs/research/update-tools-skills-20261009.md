# ツール更新とスキル候補の記録（2026-10-09）

## 更新単位と適用 ADR

予定した変更: llm-agents snapshot の pin／lock 更新、品質 floor の要否判断、snapshot 更新で生じる互換性修正、関連 test の期待値・runtime 文書・本記録の更新。文書訂正は不要と判断した。

[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md) に従い、更新を直列の単位に分ける。この PR は **Tool Snapshot のみ**を扱う。APM manifest／lock、Impeccable、Matt Pocock managed set は変更しない。

| 単位 | 状態 |
| --- | --- |
| Tool Snapshot（本 PR） | 実装・検証済み。live apply と merge は受入後 |
| 通常 APM payload | 採用（別 PR）。Remotion `32b241b9`・Modern Web Guidance `a9728684` を採用し、floating 6件を revision のみ反映。記録は [update-apm-skills-20261009.md](update-apm-skills-20261009.md)。merge・live apply は受入後 |
| Impeccable | 採用（別 PR）。skill 4.5.1 `9dad388a`・engine 0.1.12。記録は [update-impeccable-20261009.md](update-impeccable-20261009.md)。merge・live apply は受入後 |
| Matt Pocock managed set | 保留。同上（確認時点の upstream HEAD `b0618bc436ad893b3c5e84e55fba86586d34a404`、未比較） |

分割で外した変更は次の3件。通常 APM payload（[#392](https://github.com/treflebonbon/dotfiles/pull/392)）と Impeccable（別 PR）は実装済みで、Matt Pocock のみ対応先 PR が未定のため保留とし、反映・検証は未実施。

保留した単位の候補は未検証であり、採否は後続 PR で決める。今回の対象に採用しなかったものではなく、更新全体としては未完了。

## ツールの候補

実装入口で llm-agents default HEAD を一度確認し、immutable snapshot `2109db8971dc18137ff1ac9393627c761609600d` に固定した。共有 nixpkgs と言語ソースの pin は維持する。lock の差分は `llm-agents` とその推移的 input（`systems`、`treefmt-nix`）のみ。

| ツール          | 旧版    | 採用版  |
| --------------- | ------- | ------- |
| Claude Code     | 2.1.289 | 2.1.293 |
| Codex           | 0.160.0 | 0.161.0 |
| Copilot CLI     | 1.0.91  | 1.0.93  |
| Antigravity CLI | 1.2.16  | 1.3.1   |
| APM             | 0.33.0  | 0.33.0  |
| Herdr           | 0.9.3   | 0.9.3   |

品質 floor（Claude Code 2.1.289、Codex 0.159.1）は、この repo の根拠に当たる修正を release note で確認していないため上げない（[runtime/ai-runtimes.md](../../runtime/ai-runtimes.md) の「pin と床は別物」）。

## 互換性の修正

新 snapshot の upstream `apm` package は nixpkgs の `installAgentSkills` hook を必須引数に持つ。shared overlay は stable nixpkgs 上で package を再評価するため、devShell の評価が `Function called without required argument "installAgentSkills"` で失敗した。Codex・Herdr と同じく、同じ immutable input の direct package `inputs.llm-agents.packages.${system}.apm` を使う。APM 0.33.0 自体は不変。

## 検証

- x86_64-linux の user devShell は `--cores 1 --max-jobs 1` の source build が終了コード0で完了した。Codex 0.161.0 には既存2パッチが問題なく適用され、`tests/codex-sandbox-cleanup.bats` を含む `nix-devshell`／`ai-quality-floor`／`codex-sandbox-cleanup` の45件が成功した。
- `nix flake check --no-build --all-systems` は成功した（aarch64-linux／aarch64-darwin は評価のみで、実機起動は未検証）。
- 標準 `lefthook run test` は746件中729成功・22 skip・17失敗。失敗は dogfood 9件（Chromium 環境）、`local-skills` 1件（`/run/user/1000` への mkdir 拒否）、managed-set gate 7件（期待リストのソート順差）。このうち gate 7件と `local-skills` 1件は、変更のない main でも同じ8件が失敗することを確認した。dogfood 9件は main で未再実行で、前回記録の Chromium 環境要因と同種と推定する（未確認）。いずれも APM／skill に触れない本変更とは無関係の見込みだが、テストの例外化・削除はしていない。
