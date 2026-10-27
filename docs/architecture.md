---
type: concept
title: Architecture
description: chezmoi dotfiles のレイアウトと 2 種類の flake devShell、per-repo 言語テンプレート
tags: [chezmoi, nix, flake, devshell]
---

# Architecture

chezmoi 管理の dotfiles。DevPod / VS Code Dev Containers で自動デプロイ。テーマは Dracula 統一。

**編集・配備ルール**: engineering change は validated task worktree 内の source で行う。`chezmoi source-path` が示す live source は配備元の確認に使い、未 merge の task worktree から `chezmoi apply` しない。受入後に live source で `chezmoi diff` を確認し、変更した対象を `chezmoi apply <配備先パス>` で `~/` へ反映する。パス指定の apply は `run_after_*` と `run_onchange_*` を実行しないため、`private_dot_config/nix-devshell/` を変えた場合は続けて `. ~/.config/nix-devshell/lib/refresh-cache.sh && NIX_DEVSHELL_CACHE_REQUIRED=1 refresh_nix_devshell_cache` で devShell のキャッシュを更新する。`private_dot_config/codex/` を変えた場合は続けて `sync-codex-managed-config` を実行する。Codex は同期先の `~/.codex` などを読むので、apply だけでは届かない。task worktree に隔離されたセッションは live source の `git pull` とこの更新を実行できないため、`git pull --ff-only`・`chezmoi diff`・apply・キャッシュ更新・Codex 同期のうち必要なものを、ユーザーが別ターミナルで実行する1つのコマンドとして渡す。無関係な差分は反映せずユーザーへ報告する。配備先がローカルで変更されていると、apply は TTY での上書き確認を求めて失敗する。差分をユーザーへ示して了承を得てから、そのパスだけ `chezmoi apply --force <配備先パス>` で上書きする。デプロイ先を直接編集した場合は `chezmoi re-add <file>` で source へ戻す。live source は init 時の `--source` が chezmoi.toml の `sourceDir` に永続化される。

`runtime/` バンドルは chezmoi が `~/runtime/` へ配備する（agent 向け知識バンドル）。グローバル指示の実体は `private_dot_claude/CLAUDE.md`（→ `~/.claude/CLAUDE.md`）と `private_dot_config/codex/AGENTS.md`（→ `$CODEX_HOME/AGENTS.md`）で、repo 直下の `CLAUDE.md` / `AGENTS.md` は dotfiles repo 編集用として `.chezmoiignore` で非配備にする（[ADR-0078](adr/0078-keep-repo-instructions-out-of-home.md)）。この `docs/architecture.md` 自体は repo ローカル専用（`.chezmoiignore` で `~/docs/` へは非配備）— dotfiles repo 自身の構造説明は他 repo で作業中の agent には価値が無いため。

## 2 種類の flake devShell

混同しないこと:

- **リポジトリ自体** (`./flake.nix`) — chezmoi 編集用の devShell（chezmoi / lefthook / cocogitto / shellcheck / shfmt / oxfmt / bats / parallel / bun / playwright-driver など lint・format・test 一式）。validated task worktree の root で `nix develop .#default`、WSL2 では `nix develop .#wsl`（browser binary なし）へ明示的に入る。Claude hook・raw Codex adapter・`with-env` は marker `.wsl-browser-free` と WSL を見て `#wsl` を選択する。加えて per-repo flake の `templates` output（go/rust/elixir/perl/gleam/bun）を公開する。
- **ユーザー環境** (`private_dot_config/nix-devshell/flake.nix` → `~/.config/nix-devshell/flake.nix`) — 汎用ランタイム（node / python3 / bun）+ 横断ツール + AI ツール。`.#default` は従来のローカル browser 互換経路、`.#wsl` は Playwright browser を closure に含めず Managed Windows CDP adapter だけを配布する。初回セットアップとユーザー環境キャッシュは WSL2 で `.#wsl` を選択する。bash／zsh はこのキャッシュで共通ツールを利用し、direnv 自動 hook は登録しない。direnv と nix-direnv は既存 `.envrc` の明示利用用に維持する。プロジェクト言語（go/rust/elixir/perl/gleam）の toolchain は持たない。

`flake.nix` は `modules/*.nix`（node, python, runtimes, shell, editor, git, k8s, security, formatters, testing, docs, ai）を plain fragment として import し、`pkgs.mkShell` に packages / env / shellHook を fold する。ユーザー環境と per-repo template はともに `nixpkgs-26.05-darwin` を使い、x86_64-linux / aarch64-linux / aarch64-darwin の3 system に対応する。AI package は原則 `llm-agents` の shared overlay を使うが、ソースビルドの負担が大きい Codex と Herdr、および shared overlay では評価できない APM（上流が stable nixpkgs に無い `installAgentSkills` hook を要求する）は同じ immutable `llm-agents` input の direct package を使い、通常の upstream version では Numtide CI の binary cache と derivation を一致させる。これにより snapshot の一貫性を変えず、consumer 側の stable nixpkgs との差で毎回 source build になることを避ける。Codex の upstream 未収録版を一時的に local override する期間は source build となり、upstream 追従時に override を削除して cacheable な経路へ戻す（[ADR-0045](adr/0045-separate-llm-agents-and-apm-update-units.md)）。 Codex は repo 独自パッチを持たず upstream 版をそのまま使う（旧 sandbox cleanup patch は2026-10-23に撤去）。x86_64-darwin は upstream package の対応縮小と local override の継続コストを受け、2026-08-06 にサポートを終了した（[ADR-0034](adr/0034-update-ai-toolset-safety-baselines.md)）。

## per-repo 言語テンプレート

プロジェクト言語は per-repo `flake.nix` で供給する。新規 repo は `nix flake init -t 'github:treflebonbon/dotfiles#<lang>'`（go/rust/elixir/perl/gleam/bun）で展開する。テンプレ実体は `templates/<lang>/`、ルート `./flake.nix` の `templates` output で公開（`.chezmoiignore` で home には非配備）。

6テンプレートは共通 `with-env` の検証済み dotfiles revision を flake input に固定し、言語用 nixpkgs を `follows` で共有する。生成先の `nix flake lock` で依存を確定し、`nix develop .#default` と `nix run .#with-env -- command` を `.envrc` なしで使える。各 devShell に同じ package を含め、準備済み raw Codex の `with-env --prepared` にも対応する。 raw Codex は公開入力だけを専用 store・HOME へ渡すため、この入口ではホスト dotenv を注入しない。共通の隔離実装は `private_dot_local/share/codex-isolation/` に置き、手動 probe と配備する launcher が共有する。独立 repo 向けの手順・言語別 app 組込み例は各テンプレートの `DEVELOPMENT.md`、生成先の dotenv 除外は `.gitignore` に同梱する。共通処理をテンプレートへコピーせず、更新時は6 input の revision と独立展開テストを揃える。

共有チャンネルより新しい Bun・Go・Perl・Gleam・Rust/Elixir の LSP は、汎用環境と対象テンプレートの `nixpkgs-language-sources` に同じ immutable revision を固定する。Bun はパッケージ定義だけを共有 nixpkgs へ取り込み、Go と Perl は compiler/interpreter と周辺ツールをその revision の package set からまとめて取得する。Gleam は compiler、Rust と Elixir は LSP だけをその package set から選ぶ。共通 `with-env` と formatter は既存チャンネルを使う。Node.js 24 は `packages/nodejs-bin.nix` で公式配布バイナリと OS／CPU ごとの hash を固定し、本体をコンパイルせずセキュリティ修正を届ける。`overlays/runtime-security.nix` は CLI の起動先と npm builder にも適用する。Bun テンプレートは独立展開のため同じ `nodejs-bin.nix` を持ち、版・hash を一緒に更新する。APM は `nixpkgs-brotli-sources` の修正版で既存 direct package の Python binding と Git / curl の Brotli 依存を再構築し、AI snapshot と APM payload の版は保つ。共有 package set 全体の Brotli は置換しない（[調査・検証記録](research/cve-2026-111497-brotli-20261027.md)）。

## raw Codex の gateway 実行資源

gateway 実行資源は `secret-isolation-gateway.py` の `gateway_scope` が所有する。呼び出し側には mount 用 directory を返し、部分起動・後続準備・隔離実行の失敗や Ctrl-C でも gateway と一時 directory の解放を試みる。一つの解放に失敗しても残りを試み、元の失敗を保持しながら解放失敗も診断に残す。解放だけが失敗した場合も非0終了し、復旧用 session は保持する。SIGTERM への追加対応と、処理中の通信の停止制御は含めない。資源所有の interface を通した回帰は `tests/gateway-lifecycle.bats` で検証する。

## プロジェクト環境準備

`private_dot_local/share/devshell-env/devshell_environment.py` が Repository・trust・環境準備を共有する。`prepare_environment` は準備前後の Git 所属と flake の対応を確認してから環境を返し、`reuse_environment` は Nix を再評価せず準備済み環境を照合する。CLI・Claude・raw Codex は同じ module を読み、CLI の再実行で内部定義を取得しない。dotenv、Claude session、Codex の隔離・固定設定・起動・結果返却は各 adapter に残す。

chezmoi 配備・公開 Nix `with-env`・raw の隔離コピーは `bin/` と `share/devshell-env/` の配置を揃える。Python `-I` でも配備先の絶対パスから同じ module を読み込み、プロジェクトの cwd や `PYTHONPATH` に依存しない。共通化は raw の初期化場所を変えず、Nix の評価は隔離後に行う（[ADR-0044](adr/0044-runtime-owned-worktree-entry-and-codex-activation.md)）。

## ツール追加先の使い分け

- chezmoi リポジトリ編集向け（lefthook hooks 等）→ `./flake.nix`
- 横断ツール・汎用ランタイム → `private_dot_config/nix-devshell/flake.nix` と配下の `modules/*.nix`（[ai-runtimes](../runtime/ai-runtimes.md) 参照）
- プロジェクト言語ツール → per-repo flake / `templates/<lang>/`

関連: [shell-environment](../runtime/shell-environment.md) / [skill-harness](../runtime/skill-harness.md) / [adr/](adr/)
