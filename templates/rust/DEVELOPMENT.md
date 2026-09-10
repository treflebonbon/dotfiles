# Rust の開発環境

このテンプレートは言語ツール、devShell、`with-env` app を提供する。アプリやテスト自体は生成しない。Nix（flakes 有効）と Git があれば、dotfiles のローカル checkout や direnv なしで使える。

## 初回の準備と明示起動

空のディレクトリで展開する（既に展開済みなら `git add` から）:

```bash
git init
nix flake init -t 'github:treflebonbon/dotfiles#rust'
git add flake.nix .gitignore
nix flake lock
git add flake.lock
nix develop .#default
rustc --version
exit
nix run .#with-env -- rustc --version
```

`flake.nix` と生成した `flake.lock` をコミットする。言語用 nixpkgs は従来の `nixpkgs-26.05-darwin` 系統、共通 `with-env` は検証済み dotfiles revision に固定し、nixpkgs を共有する。対応 system は x86_64 Linux、ARM Linux、Apple Silicon macOS。

## 人間向けコマンドごとの dotenv

実値を使う場合は後述の別環境で固定コードを確認してから実行する。任意の root `.env` は `nix run .#with-env -- <command> [args...]` で指定したコマンドと子だけへ渡す。人間の明示実行に trust 登録は不要。サブディレクトリでは `nix run ..#with-env -- ...` など root の app を指定し、作業ディレクトリはそのまま保つ。

`.envrc` は残せるが、`nix develop` と `with-env` は読み込まない。従来の `dotenv_if_exists .env` によるシェル全体への自動 export は新経路にない。明示的に direnv を併用すると従来の読込みが走るため、既に継承した値も含め、同名変数は起動元 → devShell → `.env` の順で優先する。

`.env` 不在は許容する。現在の Git root 直下だけを読み、親・main・別 worktree は探索しない。root 外への symlink、読取り・解析失敗、Nix / shellHook の準備失敗ではコマンドを起動せず非0終了する。失敗した正式入口を直接コマンドへ置き換えて迂回しない。引数と終了コードはそのまま渡す。

解析は python-dotenv。空値・引用符・複数行・`${NAME}` / `${NAME:-default}` を扱い、`$NAME` や `$(command)` は文字列のまま。`.env` は Git へ追加せず、flake の `builtins.readFile` や shellHook に読ませない。同梱 `.gitignore` は `.env` / `.env.*` を除外し、値を持たない `.env.example` を許可する。

## dev / test app への組込み例

Cargo.toml とテスト、binary targetをプロジェクト側で用意してから、`apps` 定義を次のように拡張できる。これは例で、テンプレートには実在しない dev / test コマンドを定義していない。

```nix
apps = forAllSystems (system:
  let
    pkgs = import nixpkgs { inherit system; };
    withEnv = dotfiles.packages.${system}.with-env;
    mkApp = name: command: {
      type = "app";
      program = "${pkgs.writeShellScriptBin "${name}-with-env" ''
        exec ${withEnv}/bin/with-env -- ${command} "$@"
      ''}/bin/${name}-with-env";
    };
  in {
    with-env = dotfiles.apps.${system}.with-env;
    test = mkApp "test" "cargo test";
    dev = mkApp "dev" "cargo run";
  });
```

人間は `nix run .#test -- ...` / `nix run .#dev -- ...` で実行する。接続先など必須の変数はプロジェクトのコマンド内で検証する。

## AI の信頼登録と再読込み

dotfiles の管理 CLI / hook を導入済みの環境では `devshell-env trust .` で repo を登録し、`devshell-env status .` で確認、`devshell-env untrust .` で解除する。同じ repo の正当な linked worktree は信頼を引き継ぐ。別 clone は再登録する。

Claude は起動後の Bash に秘密を含まない devShell を読み込み、flake 変更後は `devshell-env reload` を実行して次の Bash に反映する。Linux／WSL2 の raw Codex は、linked worktree で公開ファイルと到達可能 Git 履歴を `devshell-env admit --git-head FULL_SHA -- FILES` に明示登録してから `codex-worktree` で起動する。host で flake / lock / import を変えた場合は確認・再登録後に再起動する。ホスト dotenv と任意の継承変数は隔離内へ渡さない。

各 devShell に `with-env` を含めてあるため、準備済み raw Codex の正式入口は `with-env --prepared -- cargo test` などとする。準備情報がない・異なる場合は失敗し、再起動が必要。sandbox 内で `nix run` を再実行しない。Claude への dotenv 注入、Orca native Codex の自動準備はこの仕組みの対象外。

## Codex のダミー値と人間の実値検証

Codex では、公開してよい `tests/fixtures/config.json` などの fixture と、`with-env --prepared -- env APP_MODE=test command` のようなダミー値を使う。管理 helper は dotenv を読み込まず、公開 package を直接実行しても隠したホストの値には到達できない。実値を input 登録したり、root dotenv の read 例外を戻したりしない。公開ファイルと到達可能な Git 履歴を確認し、初回の index を HEAD と揃えて `trust` と `admit` を行う。host 側で flake・lock・import を変更したら確認・再登録後に再起動する。初期化に失敗した場合は秘密なしの入力を修正し、正式入口から再起動する。

実値検証は次の順で人間が行う。

1. コード・依存 lock・flake／import・shellHook・テスト・実行コマンドを確認し、完全な commit SHA に固定する。AI が編集中の worktree や可変 branch を実行対象にしない。
2. 固定版を Codex からアクセスできない別マシン／独立 VM へ渡す。共有フォルダ、Git object directory、同期・watcher、SSH／VM 制御、secret manager、サービス endpoint を通じて Codex がコード・秘密・出力を取得・変更できないことを確認する。単なる別ディレクトリへのコピーではこの条件を満たさない。`git archive FULL_SHA` を使う場合は別環境で展開して `git init`、公開ファイルを `git add` し、Git root を用意する。必要な submodule／Git LFS の固定版も別途確認する。
3. 別環境で devShell を準備し、まずダミー値で手順を確認する。実値を用意するかは人間が決め、 `nix run .#with-env -- command` または確認済み app を実行する。root `.env` は Git に追加せず所有者だけに許可する。ログ・成果物も同じ別環境に置き、実行中のコードを AI 側から更新しない。
4. 人間がログ・成果物を確認し、SHA・コマンド・成功／失敗・必要なエラー要約だけを手動共有する。未確認ログや成果物を AI／Issue／PR／共有 cache へ自動送信しない。CI でも AI が変更した任意コードを実シークレット付きで無審査実行できる構成は使わない。

導入は受入済み dotfiles の live source で配備して新しい端末・`codex-worktree` セッションから行う。既存 repo の一括変更や秘密のコピーはしない。Linux／WSL2 の共通入口が対象で、既存セッション、直接 Codex、Desktop、Orca／Herdr native 起動、macOS raw には非開示保証を広げない。Claude の既存の非秘密 devShell 起動は維持するが、dotenv 注入・OS sandbox の追加は対象外。[導入・復旧と検証記録](https://github.com/treflebonbon/dotfiles/blob/63e47ffc471ff5e01f58a8a268ea553b0c9ab976/docs/research/raw-codex-isolation-271.md)には Linux と WSL2 の実測範囲を記録している。

固定版を独立 clone へ渡す場合は `git checkout --detach FULL_SHA` と内容の照合を行う。公開コードだけの Git bundle を使い、共有 object store を作らない。詳しいアクセス条件と共有手順は [dotfiles の人間検証手順](https://github.com/treflebonbon/dotfiles/blob/main/runtime/human-validation.md)を参照する。

## output 選択

このテンプレートは browser を含まない `default` devShell のみを提供し、WSL でもそのまま使える。`with-env` は `DEVSHELL_ENV_OUTPUT` を最優先し、未指定時は WSL かつ現在の root に `.wsl-browser-free` がある場合だけ `wsl`、それ以外は `default` を選ぶ。`DIRENV_ROOT` / `IN_NIX_SHELL` は選択に使わない。

`DEVSHELL_ENV_OUTPUT=default nix run .#with-env -- rustc --version` で明示できる。別名を指定するなら、その devShell を先に flake に定義する。`.wsl-browser-free` は `wsl` output と対で追加する。存在しない output は失敗する。`nix develop .#default` 自体はこの自動選択を行わないため、直接起動では output を明示する。
