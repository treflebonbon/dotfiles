# ツールとスキル更新（2026-10-01）

## 要件と採用境界

`/implement ツールとスキル更新` に基づき、導入済み AI ツールと APM 20依存を確認する。登録済みでクリーンな更新用 task worktree を再利用し、main `8865369ca94ae7356d64d902c05b37fd8a93c29a` から `chore/update-tools-skills-20261001` を開始した。physical root、branch、HEAD、worktree 固有 Git dir と common dir を確認した。primary checkout の `.serena/project.yml` の変更は保持する。

[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md) の境界に沿い、tool snapshot、通常 APM payload、Impeccable をそれぞれの検証結果で採否する。Matt Pocock は採用済み revision が default HEAD と一致し、移行を要しない。受入条件は source／lock／独立したテスト期待値の整合、3 system 評価、Linux CLI 起動、APM の空の隔離 cwd／HOME での install・frozen no-rewrite・audit・両配布先の discovery、Design Hook gate、関連 Bats・型検査・全 Bats、二軸レビュー、コミット。新規ツール追加、共有 nixpkgs・言語テンプレートの変更、モデル・権限設定、ローカル skill の改稿、live apply・push・PR 作成は対象外。

## ツール

実装入口で [llm-agents default HEAD](https://github.com/numtide/llm-agents.nix/commit/84dbb5ce943e2830e622a37b52604798f9aa2be5) を一度だけ確認し、immutable snapshot `84dbb5ce943e2830e622a37b52604798f9aa2be5` に固定した。[旧 pin との比較](https://github.com/numtide/llm-agents.nix/compare/96f40e1e510d8cc7e895baae27f9cf37d2d94882...84dbb5ce943e2830e622a37b52604798f9aa2be5)は160 commit。共有 nixpkgs は維持し、llm-agents 内部の nixpkgs input だけ upstream pin に従う。

| ツール            | 旧版    | 採用版  |
| ----------------- | ------- | ------- |
| Claude Code       | 2.1.284 | 2.1.286 |
| Codex             | 0.159.1 | 0.159.2 |
| Copilot CLI       | 1.0.89  | 1.0.90  |
| Antigravity CLI   | 1.2.13  | 1.2.14  |
| Herdr             | 0.9.1   | 0.9.3   |
| RTK               | 0.50.0  | 0.50.0  |
| APM               | 0.32.0  | 0.32.0  |
| code-review-graph | 2.3.9   | 2.3.9   |

[Claude Code の公式 CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md#21286) は、MCP エラーやログ・transcript の秘密値の伏字漏れ修正を含む。この運用上の根拠から `minClaudeCode = "2.1.286"` へ上げ、[ADR-0047](../adr/0047-test-quality-floors-through-package-outputs.md) と独立したテスト期待値を更新した。[Codex 0.159.2 の公式 release](https://github.com/openai/codex/releases/tag/rust-v0.159.2) は Windows の console 表示修正のみで、`minCodex = "0.159.1"` を維持する。0.159.1→0.159.2 の source diff に Linux sandbox の修正がないため、[ADR-0070](../adr/0070-adopt-gpt-6-1-sol.md) の独立 FD パッチを維持する。この間は Linux Codex が source build となる。

## スキル

`apm outdated` に加え、各選択済み subtree の Git tree SHA を候補と照合した。GitHub compare の file list は大きな差分で省略され得るため、一覧に対象 file がないだけでは payload 不変と判断しない。

| 対象 | 採否と根拠 |
| --- | --- |
| Remotion | `a9b199e165505267eda1ed3e0ef3dd3567c43411`／4.0.531 へ更新。Studio preview を制作前に開く手順、明示依頼時の render、編集可能な timeline・composition 登録の説明を採用 |
| Herdr | binary 0.9.3 の release commit `7b116c05bfda646af39d2524c54e70c751f57ee8` と同じ skill に更新。remote session の選択、machine status、reconnect 時の人間による SSH 認証を説明 |
| Impeccable | `dc78b325e753a6971800e3bddc9089bf5954f608`／skill 4.4.0 と engine 0.1.8 を同じ更新単位で採用。generate routing と live browser の改良を含む。既存の Claude／Codex hook 配線を維持 |
| empirical-prompt-tuning、shadcn、Orca computer-use／orchestration | selected tree／content hash は不変。floating revision のみ lock に反映 |
| Orca CLI | selected tree が不変のため exact pin `aedb9305` を維持 |
| Matt Pocock | default HEAD が採用済み `d81f3a18` と一致。`apm outdated` の古い tag `v1.2.3` へ戻さない |
| その他 | selected payload は最新で維持 |

上流比較: [Remotion](https://github.com/remotion-dev/skills/compare/cf49eff5d4463b33966b6618c83f7295797dd028...a9b199e165505267eda1ed3e0ef3dd3567c43411)、[Herdr](https://github.com/herdrdev/herdr/compare/065ef9d6a531c49fb8bee7e818ef837065b21ee9...7b116c05bfda646af39d2524c54e70c751f57ee8)、[Impeccable](https://github.com/pbakaus/impeccable/compare/cb56ed6c19a07329a9fa0cd4e657bee040156593...dc78b325e753a6971800e3bddc9089bf5954f608)、[engine release](https://github.com/pbakaus/impeccable/releases/tag/engine-v0.1.8)。engine の3 systemの公式 asset digest を固定 hash に使う。Gemini 向けの新しい説明は上流 payload に含まれるが、この repo の管理 hook の配布先は変更しない。

## 検証

- 空の隔離 cwd／HOME で APM 0.32.0 の native lock を生成し、全20依存が deployed files と hashes を持つことを確認。frozen install 前後の SHA-256 は `22d8728d76bc905c70f8ed98f8e4c940ee5a2759ba4592032009821c64853944` のまま不変。audit は10/10成功。隔離 cwd に remote がないため organization policy は warning 付き skip。
- Claude／Codex 両配布先に46 skillを確認し、配布対象1,300ファイルの SHA-256 と source／隔離 native lock の一致を照合。payload が変わったのは Remotion、Herdr、Impeccable の3依存。
- Nix の3 systemで上表の package metadata が一致。Linux の Codex 以外の7 CLIは起動成功。ARM Linux／Darwin は評価のみで実機起動は未確認。
- engine 0.1.8 を固定 hash で Linux buildし、candidate launcher を通す Design Hook gate は13/13成功。quiet、per-edit／Stop、silent convergence、project 設定・cache、両 provider の正常出力を維持。
- 型検査、品質 floor の7テストは成功。
- ADR-0005 の floor bump 時の再確認として、Claude 2.1.286 の配布 binary に kill switch、experimental enable、`tengu_sage_compass2`、`advisorModel` が残ることを確認。取得した bundled code では kill switch を先に判定し、experimental enable が feature flag を迂回する順序を維持していた。advisor rank 判定には変更があるため、旧 binary との完全同一性は主張しない。モデル・env 設定は維持し、実モデルによる advisor 呼出しは未実施。
- パッチ付き Codex の build、関連テスト・全 Bats・レビューは実行中。
