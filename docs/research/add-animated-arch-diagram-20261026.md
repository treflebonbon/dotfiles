# animated-arch-diagram の APM 導入

## 要件と変更範囲

ユーザーの依頼は、[musoukun/skills の animated-arch-diagram](https://github.com/musoukun/skills/blob/main/animated-arch-diagram/SKILL.md) を APM に導入すること。

[ADR-0045 の Decision 2](../adr/0045-separate-llm-agents-and-apm-update-units.md#decision) と [Skill harness の隔離 lock 生成手順](../../runtime/skill-harness.md#apm-管理の外部-skill) に従い、通常 APM payload の追加として扱う。`apm.yml` に skill 単位の依存を追加し、採用済み lock を引き継いだ新しい隔離 cwd／HOME／XDG 環境で `scripts/generate-apm-lock.sh` を実行する。APM の版は source の Nix snapshot に合わせる。

予定する変更は manifest、native lock、本記録のみ。既存 dependency、ツール snapshot、Impeccable、Matt Pocock の pin は更新しない。PR 分割による保留変更はない。未 merge の worktree から live HOME へ配備しない。

## 採用内容

`musoukun/skills/animated-arch-diagram` を追加した。manifest は既存の一般 skill と同じ floating dependency とし、native lock は解決済み commit `7b1c4d514cb387cf160cd1ae1b6f8f62c3b92aa4`、content hash `sha256:2c1b78ecb18a4f452f725ebd59dc061ca90a7fce00621677a83fc944594e145e` を記録する。

## 確認済みの検証

- Source の Nix snapshot と実行 CLI、生成 lock はいずれも APM `0.35.0`。
- 隔離環境の `apm install --frozen --target claude,codex --https` 前後で lock の SHA-256 は `94f4a178135301c9eb14b7d025bba56438ae4441918f28ea5ffd5f6f8d94d602` のまま不変。`apm audit --ci` は10項目成功、drift なし。隔離 cwd には Git remote がないため organization policy enforcement は warning 付きで省略された。
- 既存20 dependency の全 field、既存 deployment ledger、root metadata は更新前と一致。追加は1 dependency と24 deployment record（11ファイルと skill directory を両 target に配置）。
- `SKILL.md`、`references/`、`assets/template/` 内の全11ファイルが `.agents/skills/animated-arch-diagram/` と `.claude/skills/animated-arch-diagram/` に元と同じ bytes で配備され、台帳の owner／target／hash が一致した。
- `scripts/verify-apm-deployment.mjs` に候補 lock 自身を baseline として渡し、全21 dependency の実ファイル／hash／frontmatter と、両 target での47 skill の discovery を検証した。既存 lock からの追加差分と台帳不変の比較は、dependency 構成を固定する同 helper の対象外なので、別の assertion で照合した。
- 関連 Bats（`apm-runtime.bats`、`local-skills.bats`、`run_onchange_before_remove-orphan-claude-skills.bats`）は69件成功。
- 両 devShell 内の `lefthook run test` は361.35秒で終了。計画1,120件のうち成功1,083件、失敗1件、skip 36件、exit 1。ログは task worktree の `tmp/test-run.CdGR0o/` に保持した。失敗は `tests/nix-devshell.bats:262` の既存テスト `code-review-graph package meets its FastMCP floor on all supported systems` で、MCP 応答待ちが10秒で timeout したもの。今回、そのテストと code-review-graph の package／Nix snapshot は変更していない。
- 同じ source・devShell で上記テストだけを `bats --tap --print-output-on-failure --filter 'code-review-graph package meets its FastMCP floor' tests/nix-devshell.bats` により再実行し、1件成功、exit 0。並列実行中の負荷による一時的な timeout の可能性はあるが、原因は未確定。全 suite の初回失敗と単独再実行の成功を区別し、全 suite 成功とは扱わない。
- `code-review` は base `2e07d8dbe23bb8ad595a0954c7b477c16f47e26e` から実装 commit `c7ed02e` までを独立した2 agent が読み取り専用でレビューし、Standards／Spec とも指摘0件。

隔離 runtime とログは `/tmp/codex/add-animated-arch-diagram.Qcb7Ay/` に保持した。MP4／GIF の書き出しと実セッションでの呼出しは未検証。live HOME への反映は受入・merge 後の配備境界に残す。
