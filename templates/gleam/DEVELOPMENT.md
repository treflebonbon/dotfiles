# Gleam の開発環境

このテンプレートは言語ツール、devShell、`with-env` app を提供する。アプリやテスト自体は生成しない。Nix（flakes 有効）と Git があれば、dotfiles のローカル checkout や direnv なしで使える。

Gleam の Erlang target 用に Erlang/OTP 29 を同梱する。`gleam run` はこの実行環境でコンパイルしたプログラムを起動する。

## 初回の準備と明示起動

空のディレクトリで展開する（既に展開済みなら `git add` から）:

```bash
git init
nix flake init -t 'github:treflebonbon/dotfiles#gleam'
git add flake.nix .gitignore
nix flake lock
git add flake.lock
nix develop .#default
gleam --version
exit
nix run .#with-env -- gleam --version
```

`flake.nix` と生成した `flake.lock` をコミットする。言語用 nixpkgs は従来の `nixpkgs-26.05-darwin` 系統、共通 `with-env` は検証済み dotfiles revision に固定し、nixpkgs を共有する。対応 system は x86_64 Linux、ARM Linux、Apple Silicon macOS。

## コマンドごとの dotenv

任意の root `.env` は `nix run .#with-env -- <command> [args...]` で指定したコマンドと子だけへ渡す。人間の明示実行に trust 登録は不要。サブディレクトリでは `nix run ..#with-env -- ...` など root の app を指定し、作業ディレクトリはそのまま保つ。

`.envrc` は残せるが、`nix develop` と `with-env` は読み込まない。従来の `dotenv_if_exists .env` によるシェル全体への自動 export は新経路にない。明示的に direnv を併用すると従来の読込みが走るため、既に継承した値も含め、同名変数は起動元 → devShell → `.env` の順で優先する。

`.env` 不在は許容する。現在の Git root 直下だけを読み、親・main・別 worktree は探索しない。root 外への symlink、読取り・解析失敗、Nix / shellHook の準備失敗ではコマンドを起動せず非0終了する。失敗した正式入口を直接コマンドへ置き換えて迂回しない。引数と終了コードはそのまま渡す。

解析は python-dotenv。空値・引用符・複数行・`${NAME}` / `${NAME:-default}` を扱い、`$NAME` や `$(command)` は文字列のまま。`.env` は Git へ追加せず、flake の `builtins.readFile` や shellHook に読ませない。同梱 `.gitignore` は `.env` / `.env.*` を除外し、値を持たない `.env.example` を許可する。

## dev / test app への組込み例

gleam.toml とテスト、main 関数をプロジェクト側で用意してから、`apps` 定義を次のように拡張できる。これは例で、テンプレートには実在しない dev / test コマンドを定義していない。

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
    test = mkApp "test" "gleam test";
    dev = mkApp "dev" "gleam run";
  });
```

人間は `nix run .#test -- ...` / `nix run .#dev -- ...` で実行する。接続先など必須の変数はプロジェクトのコマンド内で検証する。

## AI の信頼登録と再読込み

dotfiles の管理 CLI / hook を導入済みの環境では `devshell-env trust .` で repo を登録し、`devshell-env status .` で確認、`devshell-env untrust .` で解除する。同じ repo の正当な linked worktree は信頼を引き継ぐ。別 clone は再登録する。

Claude は起動後の Bash に秘密を含まない devShell を読み込み、flake 変更後は `devshell-env reload` を実行して次の Bash に反映する。Linux／WSL2 の raw Codex は、linked worktree で公開ファイルと到達可能 Git 履歴を `devshell-env admit --git-head FULL_SHA -- FILES` に明示登録してから `codex-worktree` で起動する。host で flake / lock / import を変えた場合は確認・再登録後に再起動する。ホスト dotenv と任意の継承変数は隔離内へ渡さない。

各 devShell に `with-env` を含めてあるため、準備済み raw Codex の正式入口は `with-env --prepared -- gleam test` などとする。準備情報がない・異なる場合は失敗し、再起動が必要。sandbox 内で `nix run` を再実行しない。Claude への dotenv 注入、Orca native Codex の自動準備はこの仕組みの対象外。

## output 選択

このテンプレートは browser を含まない `default` devShell のみを提供し、WSL でもそのまま使える。`with-env` は `DEVSHELL_ENV_OUTPUT` を最優先し、未指定時は WSL かつ現在の root に `.wsl-browser-free` がある場合だけ `wsl`、それ以外は `default` を選ぶ。`DIRENV_ROOT` / `IN_NIX_SHELL` は選択に使わない。

`DEVSHELL_ENV_OUTPUT=default nix run .#with-env -- gleam --version` で明示できる。別名を指定するなら、その devShell を先に flake に定義する。`.wsl-browser-free` は `wsl` output と対で追加する。存在しない output は失敗する。`nix develop .#default` 自体はこの自動選択を行わないため、直接起動では output を明示する。
