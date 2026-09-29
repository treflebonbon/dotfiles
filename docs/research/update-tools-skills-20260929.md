# ツールとスキル更新（2026-09-29）

`/implement ツールとスキルの更新` に基づき、main `b3f9c27` から task worktree を作成した。[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md) の更新境界に従い、導入済み tool snapshot と通常の APM payload を確認した。Impeccable と Matt Pocock managed set は専用ゲートを要するため pin を維持した。モデル・権限設定と品質 floor は変更しない。

## 採用内容

- `llm-agents.nix` の default branch HEAD [`a621acfa43a25731694a8ef64fcbd5a00241e085`](https://github.com/numtide/llm-agents.nix/commit/a621acfa43a25731694a8ef64fcbd5a00241e085) を snapshot に固定した。[旧 pin との差分](https://github.com/numtide/llm-agents.nix/compare/ee7041016e9b6de43f7ba4cce04272518f7cfaa9...a621acfa43a25731694a8ef64fcbd5a00241e085)は38 commitで、導入済み package の定義では Antigravity CLI の hashes が 1.2.12→1.2.13 に進んだ。Claude Code 2.1.284、Codex 0.158.0、Copilot CLI 1.0.89、RTK 0.50.0、APM 0.32.0、Herdr 0.9.1 は不変。共有 nixpkgs input と `minClaudeCode` / `minCodex` は維持した。
- [Modern Web Guidance の選択済み subtree](https://github.com/GoogleChrome/modern-web-guidance/compare/22ab18dfb50a5d7e3bdcf471c14076a5534eae4e...84ae7251ee919239d5ea85aef25897983f26601e) にフォーム、Web Components、性能、セキュリティなどの実差分があるため exact pin を `84ae7251ee919239d5ea85aef25897983f26601e` へ進めた。Remotion と Cloudflare security-audit の pin は default HEAD と一致しており維持した。Orca CLI は pin 後の選択済み subtree に差分がないため維持した。
- Anthropic の `pdf` / `skill-creator`、Orca の `computer-use` / `orchestration`、Vercel の `find-skills` は、選択済み subtree の内容が不変で revision のみ進んだ。floating 依存のまま隔離環境で lock を再生成した。20依存のうち content hash が変わったのは Modern Web Guidance のみ。

## 検証

- `nix flake check --no-build --all-systems`: 6 devShell と3 formatterの評価に成功。3 system の package metadata は上記の版で一致。
- x86_64-linux の `nix develop .#wsl` を隔離 HOME で実行し、Claude Code 2.1.284、Codex 0.158.0、Copilot CLI 1.0.89、Antigravity CLI 1.2.13、RTK 0.50.0、APM 0.32.0、Herdr 0.9.1、code-review-graph 2.3.9 の8 CLI が起動した。aarch64-linux / aarch64-darwin の実機起動は未確認。
- 空の隔離 cwd/HOME で `apm install --target claude,codex --https` を実行。`apm install --frozen --target claude,codex --https` の前後で lock SHA-256 は `9d70202302358d5165298b84bfc4871ff5d9f1e22378ecfff4127935010fcf1f` のまま。`apm audit --ci` は10/10成功。隔離 cwd に Git remote がないため organization policy enforcement は warning 付き skip。
- 関連 Bats（`tests/nix-devshell.bats`、`tests/apm-runtime.bats`、`tests/apm-cache-refresh.bats`、`tests/ai-quality-floor.bats`）は58/58成功。`bun install --frozen-lockfile` 後の `bunx tsc --noEmit` も成功。
- `LC_ALL=C FORCE_COLOR=0 bun run test` は756件中754件成功、2件失敗（exit 1）。失敗した `Codex config migration keeps dotenv denied and public examples readable without a raw read grant` と `raw Codex edits and tests with public fixtures while a human runs a fixed revision outside its namespace` は、今回の差分を含まない現行 `main` `b3f9c27` でも個別に再実行して同じ失敗を確認した。前者は fixture の終了 status が0にならず、後者は `with-env` の実体が `/nix/store` 内にあるという assertion に失敗する。

## 追加依頼: Bash 許可ルール

`private_dot_claude/settings.json.tmpl` の `permissions.allow` に `Bash(git worktree remove:*)`、`Bash(herdr worktree remove:*)`、`Bash(orca worktree rm:*)` を追加した。`tests/codex-config.bats` の既存設定テストは1/1成功。Claude Code の[公式 permission rule 構文](https://code.claude.com/docs/en/permissions#wildcard-patterns)で `:*` は末尾ワイルドカードとして扱われる。Herdr と Git のサブコマンドは CLI help で確認した。Orca CLI はこの shell に存在しないため、実コマンド起動は未確認。実際の worktree 削除は実行していない。

live source への `chezmoi apply`、push、PR作成は行っていない。
