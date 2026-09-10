# ユーザー共通環境の更新記録（Issue #287）

親仕様: [#283](https://github.com/treflebonbon/dotfiles/issues/283)。担当Issue: [#287](https://github.com/treflebonbon/dotfiles/issues/287)。

## 候補と現在の検証状態

既存の `nixpkgs-26.05-darwin` channelを維持し、2026-09-10の実装入口で [104a7c61006cd22d11c0379663afee90c62273ab](https://github.com/NixOS/nixpkgs/commit/104a7c61006cd22d11c0379663afee90c62273ab) を候補として固定した。旧revisionは `fca2dbd4c00c3063235e56bb91758e24fc67b7b8`。この更新で変更したlock nodeはrootの `nixpkgs` inputが参照する `nixpkgs_2` だけで、AI snapshot・そのtransitive inputs・source-only inputは維持した。

候補の3 system × default/WSLの評価と、起動・キャッシュ・品質floor関連35テストは成功した。ホストWSLの実build、隔離HOMEでの起動、75 CLIの起動、28件のNix devShellテスト、現行APM payloadのfrozen no-rewrite・audit、実Design Hook 14件も成功した。全体回帰検証は進行中であり、この段階では全体の採用完了と扱わない。

## 実package出力による棚卸し

全80 nativeBuildInputsを旧・候補の実Nix出力から比較した。表中の「維持」は候補で版が不変という意味で、buildやCLI起動の検証成功とは区別する。他チケット担当のpackageも共存確認のため掲載する。

| パッケージ | 旧版 | 候補版 | このチケットでの扱い |
| --- | --- | --- | --- |
| nodejs | 24.18.0 | 24.19.0 | 更新候補 |
| typescript-language-server | 5.3.0 | 5.3.0 | channel収録版を維持 |
| typescript | 5.9.3 | 5.9.3 | channel収録版を維持 |
| python3 | 3.13.14 | 3.13.15 | 更新候補 |
| uv | 0.11.21 | 0.11.21 | channel収録版を維持 |
| ty | 0.0.38 | 0.0.38 | channel収録版を維持 |
| ruff | 0.15.14 | 0.15.14 | channel収録版を維持 |
| bun | 1.3.13 | 1.3.13 | channel収録版を維持 |
| oxfmt | 0.45.0 | 0.45.0 | channel収録版を維持 |
| shfmt | 3.13.1 | 3.13.1 | channel収録版を維持 |
| oxlint | 1.65.0 | 1.65.0 | channel収録版を維持 |
| tombi | 0.10.4 | 0.10.4 | channel収録版を維持 |
| markdownlint-cli2 | 0.21.0 | 0.21.0 | channel収録版を維持 |
| starship | 1.25.1 | 1.25.1 | channel収録版を維持 |
| zoxide | 0.9.9 | 0.9.9 | channel収録版を維持 |
| atuin | 18.15.2 | 18.15.2 | channel収録版を維持 |
| eza | 0.23.4 | 0.23.4 | channel収録版を維持 |
| bat | 0.26.1 | 0.26.1 | channel収録版を維持 |
| hexyl | 0.17.0 | 0.17.0 | channel収録版を維持 |
| fd | 10.4.2 | 10.4.2 | channel収録版を維持 |
| ripgrep | 15.1.0 | 15.1.0 | channel収録版を維持 |
| fzf | 0.72.0 | 0.72.0 | channel収録版を維持 |
| jq | 1.8.2 | 1.8.2 | channel収録版を維持 |
| sd | 1.1.0 | 1.1.0 | channel収録版を維持 |
| ShellCheck | 0.11.0 | 0.11.0 | channel収録版を維持 |
| bash-completion | 2.17.0 | 2.17.0 | channel収録版を維持 |
| direnv | 2.37.1 | 2.37.1 | channel収録版を維持 |
| zsh | 5.9.1 | 5.9.1 | channel収録版を維持 |
| zsh-autosuggestions | 0.7.1 | 0.7.1 | channel収録版を維持 |
| zsh-syntax-highlighting | 0.8.0 | 0.8.0 | channel収録版を維持 |
| nb | 7.25.4 | 7.25.4 | channel収録版を維持 |
| flyline | 1.3.0 | 1.3.0 | 現行との共存確認。版更新は #293 |
| wsl-xdg-open | 0.1.0 | 0.1.0 | 既存管理adapterを維持・起動確認 |
| neovim | 0.12.4 | 0.12.4 | channel収録版を維持 |
| tmux | 3.6a | 3.6a | channel収録版を維持 |
| lua-language-server | 3.18.1 | 3.18.1 | channel収録版を維持 |
| gh | 2.96.0 | 2.100.0 | 更新候補 |
| lazygit | 0.61.1 | 0.61.1 | channel収録版を維持 |
| gitleaks | 8.30.1 | 8.30.1 | channel収録版を維持 |
| kubectl | 1.36.2 | 1.36.3 | 更新候補 |
| kubernetes-helm | 3.20.2 | 3.20.2 | channel収録版を維持 |
| kustomize | 5.8.1 | 5.8.1 | channel収録版を維持 |
| skaffold | 2.19.0 | 2.19.0 | channel収録版を維持 |
| k9s | 0.50.18 | 0.50.18 | channel収録版を維持 |
| flyctl | 0.4.52 | 0.4.52 | channel収録版を維持 |
| devpod | 0.6.15 | 0.6.15 | channel収録版を維持 |
| hadolint | 2.14.0 | 2.14.0 | channel収録版を維持 |
| actionlint | 1.7.12 | 1.7.12 | channel収録版を維持 |
| ghalint | 1.5.6 | 1.5.6 | channel収録版を維持 |
| pinact | 3.9.2 | 3.9.2 | channel収録版を維持 |
| bats-with-libraries-1.12.0 | package名に付随 | package名に付随 | channel収録版を維持 |
| k6 | 2.0.0 | 2.0.0 | channel収録版を維持 |
| marp-cli | 4.4.0 | 4.4.0 | channel収録版を維持 |
| claude-code | 2.1.263 | 2.1.263 | 現行との共存確認。版更新は #288 |
| codex | 0.153.4 | 0.153.4 | 現行との共存確認。版更新は #288 |
| bubblewrap | 0.11.2 | 0.11.2 | channel収録版を維持 |
| copilot-cli | 1.0.83 | 1.0.83 | 現行との共存確認。版更新は #288 |
| antigravity-cli | 1.1.27 | 1.1.27 | 現行との共存確認。版更新は #288 |
| herdr | 0.9.0 | 0.9.0 | 現行との共存確認。版更新は #288 |
| rtk | 0.48.0 | 0.48.0 | 現行との共存確認。版更新は #288 |
| code-review-graph | 2.3.8 | 2.3.8 | 現行との共存確認。版更新は #288 |
| design-md | 0.3.0 | 0.3.0 | 現行との共存確認。版更新は #293 |
| impeccable | 0.1.3 | 0.1.3 | 現行との共存確認。版更新は #290 |
| playwright-cli | 0.1.17 | 0.1.17 | 現行との共存確認。版更新は #292 |
| defuddle | 0.19.1 | 0.19.1 | 現行との共存確認。版更新は #288 |
| markitdown | 0.1.6 | 0.1.6 | 現行との共存確認。版更新は #288 |
| waza | 0.38.3 | 0.38.3 | 現行との共存確認。版更新は #293 |
| apm | 0.30.0 | 0.30.0 | 現行との共存確認。版更新は #288 |
| act | 0.2.88 | 0.2.88 | channel収録版を維持 |
| cocogitto | 7.0.0 | 7.0.0 | channel収録版を維持 |
| lefthook | 2.1.5 | 2.1.5 | channel収録版を維持 |
| go-task | 3.48.0 | 3.48.0 | channel収録版を維持 |
| dive | 0.13.1 | 0.13.1 | channel収録版を維持 |
| atlas | 1.2.0 | 1.2.0 | channel収録版を維持 |
| tbls | 1.94.5 | 1.94.5 | channel収録版を維持 |
| ghq | 1.9.4 | 1.9.4 | channel収録版を維持 |
| overmind | 2.5.1 | 2.5.1 | channel収録版を維持 |
| graphviz | 12.2.1 | 12.2.1 | channel収録版を維持 |
| gws | 0.22.5 | 0.22.5 | 現行との共存確認。版更新は #293 |
| gwq | 0.0.5 | 0.0.5 | 現行との共存確認。版更新は #293 |

## 上流との差と配布経路

- Node.jsの候補出力は24.19.0。宣言は `nodejs_24` のままで、3 systemの両shellで一致した。[公式一覧](https://nodejs.org/en/about/previous-releases)の最新LTS 24.21.0との差は既存stable channelの収録差であり、26 Currentへ移行しない。
- Pythonの候補出力は既存 `python3` 属性の3.13.15。[公式一覧](https://www.python.org/downloads/)では同系列の最新修正版が3.13.15、最新安定系列が3.14.7である。共通 `python3` package集合と既存AI/Python依存の取得経路を維持する。
- Bunは既存channelの1.3.13を維持。[公式配布](https://bun.sh/)の1.4.2との差を記録し、独自overrideやinstallerを追加しない。

## 検証入口とテスト契約

- `nix flake check --no-build --all-systems path:./private_dot_config/nix-devshell`: 候補revisionで3 systemのdefault/WSLを評価し成功。さらに全6 shellのnativeBuildInputsを実出力として記録した。
- `bats tests/ai-quality-floor.bats tests/shell-flake-startup.bats tests/nix-devshell-global-reload.bats tests/refresh-cache.bats tests/refresh-cache-concurrency.bats tests/user-environment-startup.bats`: 35/35成功。
- 既存テストが旧stable revisionの完全固定を要求して失敗することを確認した。今回の合意はstable channel内での更新なので、検証対象をそのchannelの維持へ修正した。同じテストは修正後に成功した。AI snapshotのexact pin照合は維持する。
- CRGの既存実行テストはWSLでもdefault shellを選び、shellHookが通常HOMEを参照していた。検証実行が受入前のlive配備にならないよう、そのテストを隔離HOMEへ向け、WSLでは既存 `#wsl` 出力を選択する。

## 残る確認

- host buildは `/nix/store/nbnkm02w4c7d8qpwf7ymg7zhzydx9iy7-nix-shell.drv` → `/nix/store/7w50f8kqzjrnyah8xbkbyrl6nhikn2dc-nix-shell` で成功。隔離したHOMEにだけPlaywright skillをmaterializeし、管理adapter・zsh関連ファイルを確認した。
- flylineの実loadは同じstable集合のbashInteractiveで成功した。初回probeはreadlineを持たない非interactive Nix bashを誤って選び、symbol解決に失敗した。実際のbashrcはbind builtinの存在を確認してloadするため、probeを正しいinteractive Bashへ修正し、配布コードを変更せず成功した。
- 75 CLIの起動probeは `user-generic-cli-smoke.json` に実行パスと出力を記録した。markdownlint-cli2のhelpは仕様上exit2だったため、別の正常なMarkdownを検査させ、exit0 / 0 errorsを確認した。
- 現行APMの隔離frozen配備前後でlock SHA-256 `ef6e2065b6cec632780b4ceac55bd12472dbd4d8bbf69b6b15ab0b65da3a5f8b` は不変。auditは10/10、materializeした旧skill + 現行固定engineのDesign Hook/engine検証は14/14成功。engine releaseは0.1.3だが、binaryの `--version` 出力は4.0.0であり、release tagと内部表示を区別する。
- `bats tests/nix-devshell.bats` は28/28成功。full Bats suiteと最終採否記録を継続する。
- aarch64-linux / aarch64-darwinは評価対象であり、このWSL hostから実機起動済みとは扱わない。

作業ログと実出力はworktreeの `tmp/update-283/` に保持する。通常環境への反映は受入・merge後のlive sourceから行う。
