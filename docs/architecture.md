---
type: concept
title: Architecture
description: chezmoi dotfiles のレイアウトと 2 種類の flake devShell、per-repo 言語テンプレート
tags: [chezmoi, nix, flake, devshell]
---

# Architecture

chezmoi 管理の dotfiles。DevPod / VS Code Dev Containers で自動デプロイ。テーマは Dracula 統一。

**編集・配備ルール**: engineering change は validated task worktree 内の source で行う。`chezmoi source-path` が示す live source は配備元の確認に使い、未 merge の task worktree から `chezmoi apply` しない。受入後に live source で `chezmoi diff` を確認し、変更した対象を `chezmoi apply <配備先パス>` で `~/` へ反映する。パス指定の apply は `run_after_*` と `run_onchange_*` を実行しないため、`private_dot_config/nix-devshell/` を変えた場合は続けて `. ~/.config/nix-devshell/lib/refresh-cache.sh && NIX_DEVSHELL_CACHE_REQUIRED=1 refresh_nix_devshell_cache` で devShell のキャッシュを更新する。`private_dot_config/codex/` を変えた場合は続けて `sync-codex-managed-config` を実行する。Codex は同期先の `~/.codex` などを読むので、apply だけでは届かない。task worktree に隔離されたセッションは live source の `git pull` とこの更新を実行できないため、`git pull --ff-only`・`chezmoi diff`・apply・キャッシュ更新・Codex 同期のうち必要なものを、ユーザーが別ターミナルで実行する1つのコマンドとして渡す。無関係な差分は反映せずユーザーへ報告する。配備先がローカルで変更されていると、apply は TTY での上書き確認を求めて失敗する。差分をユーザーへ示して了承を得てから、そのパスだけ `chezmoi apply --force <配備先パス>` で上書きする。デプロイ先を直接編集した場合は `chezmoi re-add <file>` で source へ戻す。live source は init 時の `--source` が chezmoi.toml の `sourceDir` に永続化される。

受入後の公開 skill 移行・撤去も対象限定配備を守る。live source だけを使い、初回の `chezmoi diff` より前に旧 CLI snapshot の保存だけを実行する。`diff` も新しい shim を render するため、切替 preflight に必要な backup を先に用意する。その後の `chezmoi diff` で意図した配備差分を確認し、未知または無関係な差分があれば保留して報告する。移行で5つの CLI shim を差し替える前に、before hook を live source から render して実行し、その後に変更対象の配備先 path だけ `chezmoi apply <配備先パス>` する。全対象の apply 後は after hook を同様に明示実行する。path 指定 apply は onchange hook を起動しないため、after hook の実行が旧 copy の撤去まで完了させる。after hook 自身が mutating な `sync-codex-managed-config` を実行し、続けて `sync-codex-managed-config --verify-only`、`sync-skills-plugin --verify-only` の current state が両方成功した場合だけ `legacy_skills retire-known-skills` を呼ぶ。単独の同期コマンドでは撤去 gate を実行しない。

hook は chezmoi 自動実行外で明示実行する場合も live source から取得する。以下は移行処理を手動で再現する手順であり、新しい CLI を追加しない。

```bash
set -euo pipefail
live_source="$(chezmoi source-path)"
tmpdir="$(mktemp -d /tmp/codex/skills-retire.XXXXXX)"
# 初回 diff の render に必要な旧 CLI backup だけを保存する。
chezmoi --source "$live_source" execute-template \
  '{{ includeTemplate "local-skills.sh.tmpl" . }}{{ "\n" }}legacy_skills prepare' > "$tmpdir/prepare"
bash "$tmpdir/prepare"
chezmoi --source "$live_source" diff
# 差分が意図した内容だけであることを確認し、未知差分があれば保留する。
# 確認後に before hook を実行し、変更対象だけを apply する。
chezmoi --source "$live_source" execute-template --file "$live_source/run_onchange_before_remove-orphan-claude-skills.sh.tmpl" > "$tmpdir/before"
CHEZMOI_SOURCE_DIR="$live_source" bash "$tmpdir/before"
# 変更対象の配備先 path ごとに apply する。これは対象の一例。
chezmoi --source "$live_source" apply "$HOME/.local/bin/git-push-topic"
# 他の変更対象も、意図した配備先 path だけ apply する。
chezmoi --source "$live_source" execute-template --file "$live_source/run_onchange_after_codex-managed-sync.sh.tmpl" > "$tmpdir/after"
CHEZMOI_SOURCE_DIR="$live_source" bash "$tmpdir/after"
```

Codex の managed 設定だけを変更する場合は、通常の設定同期に `sync-codex-managed-config` を使う。公開 skill 移行では上記 after hook が同期・検証・撤去を一続きで行うため、単独の同期コマンドで置き換えない。`private_dot_config/nix-devshell/` の変更は、path apply 後に上記の Nix cache 更新を続ける。

`runtime/` バンドルは chezmoi が `~/runtime/` へ配備する（agent 向け知識バンドル）。グローバル指示の実体は `private_dot_claude/CLAUDE.md`（→ `~/.claude/CLAUDE.md`）と `private_dot_config/codex/AGENTS.md`（→ `$CODEX_HOME/AGENTS.md`）で、repo 直下の `CLAUDE.md` / `AGENTS.md` は dotfiles repo 編集用として `.chezmoiignore` で非配備にする（[ADR-0078](adr/0078-keep-repo-instructions-out-of-home.md)）。この `docs/architecture.md` 自体は repo ローカル専用（`.chezmoiignore` で `~/docs/` へは非配備）— dotfiles repo 自身の構造説明は他 repo で作業中の agent には価値が無いため。

## 2 種類の flake devShell

混同しないこと:

- **リポジトリ自体** (`./flake.nix`) — chezmoi 編集用の devShell（chezmoi / lefthook / cocogitto / shellcheck / shfmt / oxfmt / bats / parallel / bun / playwright-driver など lint・format・test 一式）。validated task worktree の root で `nix develop .#default`、WSL2 では `nix develop .#wsl`（browser binary なし）へ明示的に入る。Claude hook・raw Codex adapter・`with-env` は marker `.wsl-browser-free` と WSL を見て `#wsl` を選択する。加えて per-repo flake の `templates` output（go/rust/elixir/perl/gleam/bun）を公開する。
- **ユーザー環境** (`private_dot_config/nix-devshell/flake.nix` → `~/.config/nix-devshell/flake.nix`) — 汎用ランタイム（node / python3 / bun）+ 横断ツール + AI ツール。`.#default` は従来のローカル browser 互換経路、`.#wsl` は Playwright browser を closure に含めず Managed Windows CDP adapter だけを配布する。初回セットアップとユーザー環境キャッシュは WSL2 で `.#wsl` を選択する。bash／zsh はこのキャッシュで共通ツールを利用し、direnv 自動 hook は登録しない。direnv と nix-direnv は既存 `.envrc` の明示利用用に維持する。プロジェクト言語（go/rust/elixir/perl/gleam）の toolchain は持たない。

## 公開 Agent Skills plugin

11件の Agent Skill、共用 CLI、規範契約、WSL2 browser 資産の正本は公開 `treflebonbon/skills` repository である。dotfiles は `private_dot_config/nix-devshell/skills-plugin.json` の単一 pin を使い、Claude Code、Codex、Antigravity CLI の公式 plugin 導入と、端末固有の Nix / config / dispatch 配線を所有する。dotfiles に skill payload の source copy や独自 dependency resolver を置かない。第三者 skill は従来どおり APM から別途導入する。

pin の完全な識別情報と、更新・旧配備撤去・復旧条件は [ADR-0082](adr/0082-extract-local-skills-to-public-repository.md) を正本とする。現在の導入状態は `sync-codex-managed-config --verify-only` の current cache path / grant / deny 照合後に `sync-skills-plugin --verify-only` で全 runtime の plugin payload を確認する。成功 receipt のみで現在の導入状態や旧配備撤去を許可しない。旧配備の撤去は両 verifier の成功を同じ hook 実行内で確かめた後だけ行う。

`flake.nix` は `modules/*.nix`（node, python, runtimes, shell, editor, git, k8s, security, formatters, testing, docs, ai）を plain fragment として import し、`pkgs.mkShell` に packages / env / shellHook を fold する。ユーザー環境と per-repo template はともに `nixpkgs-26.05-darwin` を使い、x86_64-linux / aarch64-linux / aarch64-darwin の3 system に対応する。Claude Code、Codex、Copilot CLI、Antigravity CLI、Herdr、code-review-graph の6件は同じ immutable `llm-agents` input の `packages.${system}` を直接使う。consumer 側の package set による再計算や独自 patch を加えず、Numtide の binary cache と derivation を一致させる。更新時は対応3 systemのcacheを確認し、取得できない候補を自前ビルドで補わない。Claude / Codex の品質 floor と code-review-graph の FastMCP floor は維持する。CRGのparser依存はllm-agents側の制約緩和に従って1.4.1を使い、以前の`tree-sitter-language-pack<1`検査を終了した。APMは更新対象から外し、独立した`llm-agents-apm` pinで更新前の修正済みoutputを維持する。同梱Node runtimeの版と他言語のgrammar互換性の未確認範囲は[更新記録](research/update-tools-skills-20261031.md)に残す（[ADR-0045](adr/0045-separate-llm-agents-and-apm-update-units.md)）。x86_64-darwin は2026-08-06にサポートを終了した（[ADR-0034](adr/0034-update-ai-toolset-safety-baselines.md)）。

## per-repo 言語テンプレート

プロジェクト言語は per-repo `flake.nix` で供給する。新規 repo は `nix flake init -t 'github:treflebonbon/dotfiles#<lang>'`（go/rust/elixir/perl/gleam/bun）で展開する。テンプレ実体は `templates/<lang>/`、ルート `./flake.nix` の `templates` output で公開（`.chezmoiignore` で home には非配備）。

6テンプレートは共通 `with-env` の検証済み dotfiles revision を flake input に固定し、言語用 nixpkgs を `follows` で共有する。生成先の `nix flake lock` で依存を確定し、`nix develop .#default` と `nix run .#with-env -- command` を `.envrc` なしで使える。各 devShell に同じ package を含め、準備済み raw Codex の `with-env --prepared` にも対応する。 raw Codex は公開入力だけを専用 store・HOME へ渡すため、この入口ではホスト dotenv を注入しない。隔離実装と共有 module は [固定版 plugin](../private_dot_config/nix-devshell/skills-plugin.json) の source を正本とし、Nix 配布と launcher はそこから読み込む。独立 repo 向けの手順・言語別 app 組込み例は各テンプレートの `DEVELOPMENT.md`、生成先の dotenv 除外は `.gitignore` に同梱する。共通処理をテンプレートへコピーせず、更新時は6 input の revision と独立展開テストを揃える。

共有チャンネルより新しい Bun・Go・Perl・Gleam・Rust/Elixir の LSP は、汎用環境と対象テンプレートの `nixpkgs-language-sources` に同じ immutable revision を固定する。Bun はパッケージ定義だけを共有 nixpkgs へ取り込み、Go と Perl は compiler/interpreter と周辺ツールをその revision の package set からまとめて取得する。Gleam は compiler、Rust と Elixir は LSP だけをその package set から選ぶ。共通 `with-env` と formatter は既存チャンネルを使う。Node.js 24 は `packages/nodejs-bin.nix` で公式配布バイナリと OS／CPU ごとの hash を固定し、本体をコンパイルせずセキュリティ修正を届ける。`overlays/runtime-security.nix` は CLI の起動先と npm builder にも適用する。Bun テンプレートは独立展開のため同じ `nodejs-bin.nix` を持ち、版・hash を一緒に更新する。APMは`llm-agents-apm`の旧snapshotと`nixpkgs-brotli-sources`による既存の依存修正を維持する。今回の更新では3環境のderivation・outputが更新前と同一であることと、Linuxの既存outputを再利用できることを確認し、新しいAPMビルドは追加しない（[Brotli修正の採用記録](research/cve-2026-111497-brotli-20261027.md)）。

## プロジェクト環境準備

固定版 plugin の `lib/python/treflebonbon_skills/devshell_environment.py` が Repository・trust・環境準備を所有する。dotfiles は Nix shell と `with-env` app からこの module を供給し、generic CLI はそれを利用する。`prepare_environment` は準備前後の Git 所属と flake の対応を確認して環境を返し、`reuse_environment` は Nix を再評価せず準備済み環境を照合する。`.env` の読込み、Claude session、reload/hook、raw 起動 adapter は dotfiles 側に残す。

`devshell-env codex|admit` と `codex-worktree` は固定版の public entry を検証して起動する。public source と current installation の照合に失敗した raw 経路は保留し、旧ローカル実装へ無保護で fallback しない。共通化は raw の初期化場所を変えず、Nix の評価は隔離後に行う（[ADR-0044](adr/0044-runtime-owned-worktree-entry-and-codex-activation.md)）。

## ツール追加先の使い分け

- chezmoi リポジトリ編集向け（lefthook hooks 等）→ `./flake.nix`
- 横断ツール・汎用ランタイム → `private_dot_config/nix-devshell/flake.nix` と配下の `modules/*.nix`（[ai-runtimes](../runtime/ai-runtimes.md) 参照）
- プロジェクト言語ツール → per-repo flake / `templates/<lang>/`

関連: [shell-environment](../runtime/shell-environment.md) / [skill-harness](../runtime/skill-harness.md) / [adr/](adr/)
