---
type: concept
title: Shell environment
description: bash は flyline 中心、macOS zsh は atuin + zsh plugins 中心で構成するシェル環境と nix-devshell グローバル env キャッシュ
tags: [bash, zsh, shell, flyline, starship, atuin, ghq]
---

# Shell environment

Linux / Dev Container のログインシェルは **bash**（[ADR-0001](../docs/adr/0001-bash-over-zsh.md)）。macOS は zsh を維持する（[ADR-0020](../docs/adr/0020-macos-keeps-zsh-login-shell.md)）。

- `dot_bash_profile.tmpl` → `~/.bash_profile` — login shell。PATH / XDG_RUNTIME_DIR フォールバック / nix-daemon 読み込み / Codex Desktop 用 CODEX_HOME、末尾で `~/.bashrc` を source。
- `dot_bashrc.tmpl` → `~/.bashrc` — 対話 shell。ツール init と関数を定義。
- `dot_zshrc.tmpl` → `~/.zshrc` — macOS zsh 用の対話 shell。atuin と zsh-native plugins を初期化する。

## 所有権モデル

**履歴検索の所有者** は shell ごとに分ける。bash では flyline が `Ctrl-R` を所有し、zsh では atuin が `Ctrl-R` を所有する。

**主要機能セット** は同一実装ではなく、shell ごとの最適実装で満たす。bash は flyline、zsh は atuin + zsh-autosuggestions + zsh-syntax-highlighting を使い、starship / fzf / zoxide は両方で維持する（[ADR-0021](../docs/adr/0021-replace-blesh-with-flyline.md)）。

## bash ツール

sheldon などのプラグインマネージャは使わず、`.bashrc` で各ツールの init を直接 `eval` する（軽量化）:

- **flyline** — bash の line editor と履歴検索の所有者。Linux/glibc 版 loadable builtin を `enable -f` する。load 失敗時は1行警告を出して bash 標準入力編集へフォールバックする。mouse capture と AI agent integration は初期無効
- **bash-preexec** — precmd/preexec hook 基盤（`~/.config/bash/bash-preexec.sh` に vendored, rcaloras/bash-preexec 0.6.0）。starship 継続時の prompt hook 互換性のため維持
- **starship** — プロンプト（Dracula カラーパレット）。flyline prompt は directory / Git branch/status / time / command duration の既存表示を十分に置き換えないため、bash でも starship を維持する
- **fzf** — キーバインド + 補完。通常の `fzf --bash` を使う。Dracula カラー
- **zoxide** — スマート cd（`--cmd cd`）
- **eza** — `ls`/`ll`/`la`/`lt` エイリアス
- **direnv** — 既存 `.envrc` の明示利用用。標準の自動 hook は登録しない
- **bash-completion** — 補完。OS パッケージ優先、無ければ nix-devshell 供給の本体を `XDG_DATA_DIRS` から探索

## zsh ツール（macOS）

- **atuin** — zsh の履歴検索の所有者（`Ctrl-R`）。fzf より後に init し、zsh の後勝ち keybind で履歴検索を取る
- **zsh-autosuggestions / zsh-syntax-highlighting** — nixpkgs パッケージ由来の plugin file を直接 source する
- **starship / fzf / zoxide** — zsh native hook で初期化する

## プロジェクト開発シェルへの明示入場

bash／zsh は `cd` 時に direnv を自動実行しない。通常設定とツールは対象 repo の `flake.nix` と `flake.lock` に置き、人間は Git root で次のように入る。`nix develop` が起動する子シェルは bash で、`exit` すると起動元の bash／zsh に戻る（[Nix の公式仕様](https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-develop)）。

```bash
nix develop .#default
# プロジェクトのツールで作業
exit
```

dotfiles の WSL2 開発では `nix develop .#wsl` を使う。Nix 自体は `.wsl-browser-free` や `DEVSHELL_ENV_OUTPUT` を解釈しないので、人間は output を明示する。`with-env`、Claude hook、raw Codex adapter は現在の root・marker・WSL を共通規則で選択し、`DEVSHELL_ENV_OUTPUT=default` などの明示値を優先する。6言語テンプレートは browser を含まない `default` を使う。flake や import した設定を編集したら、人間は `exit` して入り直し、Claude は `devshell-env reload`、raw Codex は再起動する。

新経路は `.envrc` を読み込まず、dotenv も開発シェル全体へ自動 export しない。既存の direnv 環境から起動した場合は継承値が残るため、移行確認は新しいシェルから行う。既に走っているシェルの hook や継承した秘密を新しい設定が識別・除去する保証はない。

## nix-devshell グローバル env キャッシュ

`~/.config/nix-devshell` の共通ツールをプロジェクト開発シェルの外でも有効化するため、`nix print-dev-env` の出力を `~/.cache/nix-devshell-global-env.bash` にキャッシュし stale-while-revalidate で更新する。実体は `~/.config/nix-devshell/lib/{ensure-env,refresh-cache}.sh`（bash 関数）。`.bashrc` は起動時に現行キャッシュを source し、背景で次回向けに再生成、`PROMPT_COMMAND` で mtime 変化時にリロード（`chezmoi apply` 連携）。出力は bash として直接 source 可能なため zcompile は不要。

通常の `chezmoi apply`、APM 配備、初回導入は `NIX_DEVSHELL_CACHE_REQUIRED=1` で更新し、必要な更新や前提の確認に失敗したら停止する。途中まで出力した Nix の非0終了、空・bash 構文不正の出力、キャッシュ置換の失敗は旧キャッシュを保持する。対話シェルの背景更新は引き続き起動を止めない。鮮度は devShell 配下のソースの内容・追加・削除と WSL／通常環境の選択で判定し、入力が同じなら再評価しない。ルートの `.git`／`.direnv` と Nix の `result`／`result-*` symlink は実行時状態として除外する。対応する入力情報をキャッシュ本体に含め、検査後に一緒に置換する。旧形式はそのまま読め、次の更新で再生成へ移行する。初回を含む毎回の更新で、排他には PATH 上の system `perl`、鮮度判定には `sha256sum` または `shasum` を使う（[ADR-0050](../docs/adr/0050-user-environment-cache-freshness.md)）。

同じキャッシュの背景更新は競合時に待たず省略し、必須更新は先行更新を待って入力を再確認する。評価前後の照合で入力の変化を検出した場合は結果を採用せず1回だけ再試行し、再び検出すれば旧キャッシュを保持して必須更新を失敗させる。更新元の終了でロックは解放され、残った一時出力は次回の更新が回収する。`~/.cache/nix-devshell-global-env.bash.lock` は常設ファイルであり、存在自体は更新中の意味ではない。実行中のロックファイルを削除すると排他を壊すため、そのまま通常の更新を再実行する。

ソースの書込み側はこのロックに参加しない。最後の入力照合後、採用直前にソースが変わると、その更新は変更前の入力のキャッシュを採用して成功することがある。この変更は次回更新の入力照合で検出する。配備中の並行編集まで含めた採用時点の最新性は保証しないため、編集が重なった場合は入力を安定させて必須更新を再実行する。保証範囲と判断理由は [ADR-0050の鮮度保証の境界](../docs/adr/0050-user-environment-cache-freshness.md#鮮度保証の境界) に従う。

## raw Codex のプロジェクト開発環境

Linux／WSL2 の `codex-worktree` は、Nix 評価・shellHook より前に専用の filesystem・user・PID・network namespace を作る。空の HOME、選択した Nix ツール closure のコピー、明示した公開ファイルと Git 履歴だけで初期化し、同じ physical root と Active Git Metadata Boundary を隔離内に再構成する。ホストの HOME、Nix daemon、任意の継承変数、未登録ファイルは渡さない。

人間は validated linked worktree で、公開してよいファイルと **現在の HEAD から到達可能な Git 履歴全体** を確認してから登録する。`trust` は repo の初期化許可、`admit` はファイルの内容と公開 runtime 設定の宣言であり、別々に必要になる。

```bash
devshell-env trust
# FULL_SHA は確認した現在の完全な commit SHA。FILES は公開ファイルを個別に列挙する。
devshell-env admit --git-head FULL_SHA -- flake.nix flake.lock package.json src/index.ts
codex-worktree
```

`admit` は現在の managed `CODEX_HOME/config.toml`、存在する AGENTS・default rules、Git の user.name/email と実行可能 hook も公開入力として記録する。これらにもプロジェクト秘密を含めない。署名鍵や署名 agent は提供しないため、隔離 repository は `commit.gpgsign=false` で起動する。以前登録した入力に署名設定が含まれていても同じ扱いとし、ホストの署名設定は変更しない。

初回の index は HEAD と一致させる。symlink・hardlink・特殊ファイルは列挙するファイル入力として受理しない。HEAD にある symlink・submodule の Git エントリは保持するが、ホストのリンク先や submodule の内容はコピーしない。変更のないエントリはそのまま返却でき、新規・変更された symlink・gitlink の結果は拒否する。ファイル名の denylist を公開可否の判定に使わないため、通常名に隠した秘密も列挙しなければ入らない。`.env`・鍵・認証ファイルを入力に加えて問題を回避しない。

`devshell-env status [directory]` と `untrust [directory]` は従来どおり。信頼は Git common directory の physical path と inode に結び付き、同じ repo の正当な linked worktree に継承する。公開入力の登録は worktree ごとに必要。primary checkout で信頼登録はできるが、raw 起動は linked worktree に限定する。

既定 output は `default`、WSL かつ現在の root に `.wsl-browser-free` があれば `wsl`。`DEVSHELL_ENV_OUTPUT=custom codex-worktree` で明示できる。devShell が生成する通常変数・PATH・shellHook の結果は Codex に渡すが、起動元の任意変数は復元しない。選択済みの Codex・Python・Git などの closure、launcher、管理ポリシーは読み取り専用にする。

Codex の対話画面で行うディレクトリの信頼や操作設定の保存は、session 専用の `config.toml` に限る。host の設定へは戻さない。AGENTS・rules と、標準 permission・当該 Git metadata の write を定義する requirements は読み取り専用のまま維持する。session config に同名 permission profile を追加しても、次の config 読込み時に競合として拒否する。

標準 `dotfiles-secure` を隔離内の `/etc/codex/requirements.toml` に固定し、当該 Git metadata だけ write に加える。追加 workspace root は無効にする。同名 profile を project config で再定義すると起動を拒否する。root dotenv の read 例外は追加しない。Codex が deny 対象に空の placeholder を作る場合はあるが、ホストの内容は入らず、その placeholder を作業結果として返さない。

終了時は commit SHA・index・未 commit の通常ファイルを元の worktree に返し、次回の入力登録を更新する。実行中は同じ host worktree を並行編集しない。host 側の HEAD・index・入力が変わった場合や、未登録ファイルと結果が衝突した場合は返却を止め、隔離結果を保持する。host で flake や公開ファイルを変更した場合は内容を再確認して `admit` し直し、再起動する。隔離内で変更して返却できたファイルは再登録済みとなる。

初回も再起動も専用 store を新規作成する。状態は `${XDG_STATE_HOME:-$HOME/.local/state}/devshell-env/` の `inputs/` と `sessions/<id>/` に保存し、開始時に session path を表示する。1 session あたり選択ツールだけでも約 700 MB、devShell の取得分は別途必要になる。復旧用に終了後も保持するため、受入済み結果を確認してから人間が不要な session directory を整理する。

未登録・信頼解除・flake 不在・不正 metadata／引数は初期化前に拒否する。入力の変更、隔離設定、Nix、shellHook、管理設定の失敗は非0終了し、無保護な調査用起動へ fallback しない。部分的な初期化結果を host へ返さず、表示された session の `store-copy.log`・公開 snapshot を確認し、原因を直して再登録・再起動する。返却途中の I/O 障害では全ファイルの原子的 rollback は保証しない。session の bundle と snapshot を保持して差分を確認し、失敗した返却を盲目的に繰り返さない。

必要条件は rootless user/network namespace を許可した Linux／WSL2、Nix store から選んだ Nix・bash・coreutils・Python 3.13 以上・Git・Codex 0.153.4 以上・gh・bubblewrap、managed `dotfiles-secure`、公開 CA bundle。汎用 devShell は `CODEX_ISOLATION_CA_BUNDLE` を設定する。モデル接続は host の既存 ChatGPT login を専用 gateway が使い、token は隔離内へ置かない。期限切れは host で login を更新して再起動する。API key provider は未統合。管理 MCP と GitHub は以下の明示登録で接続する。

Nix の取得と command network proxy は managed allowlist の HTTPS と公開 IP だけへ接続する。専用 resolver も同じ条件を使う。network namespace 内だけで低位 port を使用可能にし、DNS listener・初期化・Codex は capability を持たない。ホストの DNS・loopback・制御 socket は公開しない。

既存セッション、直接の `codex`、Codex Desktop、Orca／Herdr native 起動はこの保証の対象外。Herdr が作成した worktree でも、[ホスト側コピーの成功確認後、そのターミナルから `codex-worktree` を使う手順](ai-runtimes.md#新規-worktree-への-env-コピー)で共通の隔離入口を利用できる。macOS の raw 隔離起動は未対応で拒否する。受入・merge 後の live source から配備して新しい入口で起動する。未 merge の task source から `chezmoi apply` しない。検証範囲は [#271 の記録](../docs/research/raw-codex-isolation-271.md) を参照。

### 隔離内の管理 MCP と GitHub

Context7・Serena は入力登録時に `--mcp context7 --mcp serena` を追加して選択する。現在の管理済み stdio command/args と一致する設定だけを受理し、Nix の bunx・Node・uvx を個別にコピーする。パッケージ取得と MCP の起動・文書参照・コード操作は外側の隔離内で行う。ホストの MCP、cache、追加サーバーの設定や認証値は共有しない。起動失敗は required MCP のエラーとして報告し、API key や host 権限を自動追加しない。

GitHub は公開 repository の1 topic に限定する。人間がホスト上の worktree 外に次の JSON を置き、`--github-policy /absolute/path/policy.json` で登録する。`reviewed_commit` は現在の HEAD の祖先で、CI と外部連携を確認した完全な SHA。`review` に確認した対象と根拠を記録する。repo の trust 登録だけではこの確認を代替しない。

```json
{
  "repository": "OWNER/REPOSITORY",
  "branch": "feat/TOPIC",
  "default_branch": "main",
  "reviewed_commit": "REVIEWED_FULL_COMMIT_SHA",
  "automation": "no-project-secrets",
  "review": "push・PR・コメントで起動する CI と外部連携を確認した根拠"
}
```

`automation` は `no-project-secrets`（AI の変更を実行する連携へプロジェクト秘密を渡さない）か `human-reviewed-external`（実値検証は人間が確認済みコードを別環境で実行し、確認済み結果だけ共有する）。外部連携・環境変数・取得サービスも含めて確認する。不明な場合は GitHub を登録せず秘密なしのローカル作業を続ける。この repo の追跡済み workflow に秘密の受渡しがないことは、他 repo や GitHub 外の設定に対する保証ではない。

```bash
devshell-env admit --git-head FULL_SHA \
  --mcp context7 --mcp serena \
  --github-policy /absolute/path/policy.json \
  -- flake.nix flake.lock package.json src/index.ts
codex-worktree
```

GitHub 利用時は Nix の gawk・jq も必要。隔離内では `git-push-topic`、限定版 `gh api`、`gh pr create/list/view/edit/comment` を提供する。`gh pr create --title 'feat: example' --body-file pr.md --draft`、`gh pr edit NUMBER --body-file pr.md` のように使う。`gh api` は `--method/-X`・`--input`・`--jq/-q`・`--field/-F`・`--raw-field/-f` に対応する。対象 repo の metadata、topic の PR 一覧・参照・作成・title/body 更新・コメントだけを受理する。その他の gh コマンド・GraphQL・Secrets・Actions のログや artifact・workflow dispatch・merge・close は非対応として拒否する。ホストの gh alias、extension、credential helper、認証ファイルは渡さない。

ホストの認証設定先は `GH_CONFIG_DIR`、`XDG_CONFIG_HOME/gh`、`HOME/.config/gh` の順に選ぶ。設定先はホストの gateway・publisher だけが保持し、`GH_TOKEN`・`GITHUB_TOKEN` は転送しない。PR 作成には `--title` が必要。`gh api -F body=@-` は標準入力を本文として読み、`-f body=@-` は文字列 `@-` をそのまま送る。

`git-push-topic` は HEAD の bundle をホスト側の専用 Git repository へ渡し、履歴・fast-forward・全新規 commit の `.github` 不変を検査してから、登録時に固定した既存の `git-push-topic` helper で公開する。ホスト側でプロジェクトコード・hook・checkout を実行しない。認証は既存の host gh だけが利用する。remote の default branch と、PR 操作時の topic の `.github` が確認済み tree と異なる場合も停止する。CI 設定を変更したい場合は人間の確認・再登録を要する。

公開要求は base64 を含む JSON 全体で64 MiBまで、Git の検査は各 subprocess 120秒までに制限する。展開後の object 総容量・個数や host 全体の資源消費は制限していない。この境界の保証は秘密・認証・公開権限の分離であり、圧縮 bundle による host の資源枯渇まで防ぐものではない。

GitHub の要求は Codex の既存 HTTP proxy と外側の限定 gateway を通る。内部の `http://api.github.com` はこの通信経路内の宛先で、ホスト gateway が実 GitHub へ HTTPS で接続する。ホストのネットワーク、制御 socket、認証値を公開しない。直接の Unix socket 接続は Codex 0.153.4 の Linux proxy 用 seccomp に拒否されるため使用しない。標準の domain allow/deny はこの経路でも維持する。

認証不足・network 拒否・remote の変更は非0終了と原因カテゴリを返す。成功した外部 push/PR は後段のローカル返却失敗で取り消されない。公開 SHA・PR URL と保持された session を照合して復旧する。実接続の OS 別結果と制約は [#272 の検証記録](../docs/research/isolated-services-272.md) を参照。

### 指定コマンドへの dotenv 注入

dotfiles の `nix run .#with-env -- <command> [args...]` は、現在地の Git root にある devShell を準備し、その root の `.env` を対象コマンドと子プロセスにだけ渡す。人間による明示実行では trust 登録は不要。`DEVSHELL_ENV_OUTPUT` と WSL の `.wsl-browser-free` 判定は raw adapter と共通で、`.envrc` は読まない。サブディレクトリからも同じ root の `.env` を使い、コマンドの作業ディレクトリは現在地を保つ。

公開入口は通常の `.git` ディレクトリと linked worktree に加え、submodule や `git init --separate-git-dir` の有効な gitfile を受理する。gitfile の symlink・不正な参照・準備中の metadata 差替えは拒否する。起動元の `GIT_*` は対象コマンドへ継承するが、root 探索と Nix／shellHook の準備には渡さない。たとえば `GIT_AUTHOR_NAME`・`GIT_CONFIG_COUNT`・`GIT_SSH_COMMAND` は子の Git 操作で利用できる。gitfile の追加受理は公開入口に限り、trust 登録と自動起動の metadata 所属条件は従来どおりとする。

dotenv は任意で、不在なら準備済み環境だけで実行する。存在するファイルの読取り・解析失敗、worktree 外への symlink、通常ファイル以外は非0終了し、対象コマンドを起動しない。人間の明示実行では worktree 内のファイルへの symlink を受理する。raw Codex の隔離内にはホスト dotenv を渡さず、自動 read 許可も追加しない。解析は `python-dotenv` を使い、空値・引用符・複数行・`${NAME}` と `${NAME:-default}` を扱う。`$NAME` と `$(command)` は文字列のままになり、シェルとして実行しない。値のない `NAME` は無視し、同名の値は起動元、devShell、dotenv の順で優先する。

Nix／shellHook の準備失敗も正式入口の失敗として止める。**AI は失敗した正式入口を任意コマンドの直接実行へ置き換えて迂回しない。** 必要変数の有無・内容の検証は各コマンドが担当する。dotenv を Git に追加したり、flake の `builtins.readFile` や shellHook から取り込んだりしない。Nix の Git source には追跡ファイルが入るため、`.env` は追跡対象外のままにする。

raw Codex では `with-env --prepared -- <command> [args...]` が秘密なしの準備済み環境を再利用する。launcher の保護された helper も同じコマンド名で用意する。devShell の公開 `with-env` package を使う場合もホスト dotenv には到達できない。通常の入口は必ず Nix を準備し直すため、sandbox 内では `--prepared` を使う。準備成功の照合情報がない場合は失敗する。

準備完了の情報は `DEVSHELL_ENV_CONTEXT` に root・repo identity・output・root の `flake.nix` / `flake.lock` の hash だけを保持する。値を持つ環境キャッシュではない。別 root・output・この2ファイルの変更を検出したら正式入口を失敗させ、再起動を要求する。import した Nix file なども含め、devShell を変更したら常に再起動する。この情報は再利用対象の照合用であり、agent による環境変数改変を防ぐ認証情報ではない。

標準 profile の secret deny と network policy は維持する。raw の HOME と `TMPDIR` は専用 namespace 内にあり、ホストの認証ディレクトリはマウントしない。絶対 `/tmp` への依存は避け `TMPDIR` を使う。実際の秘密が必要な検証は人間の明示した `with-env` で行う。

名前付き dev / test app へ組み込む例（対象 flake で dotfiles を input に持ち、system ごとの output を定義する箇所）:

```nix
let
  withEnv = dotfiles.packages.${system}.with-env;
  mkApp = name: {
    type = "app";
    program = "${pkgs.writeShellScriptBin "${name}-with-env" ''
      exec ${withEnv}/bin/with-env bun run ${name} "$@"
    ''}/bin/${name}-with-env";
  };
in
{
  devShells.${system}.default = pkgs.mkShell {
    packages = [ pkgs.bun withEnv ];
  };
  apps.${system} = {
    dev = mkApp "dev";
    test = mkApp "test";
  };
}
```

たとえば `dev` が接続先を必須にするなら、そのコマンド内で `: "${DATABASE_URL:?DATABASE_URL is required}"` のように確認する。上記は組込み例で、dotfiles 自体に `dev` app や接続先を追加するものではない。Go・Rust・Elixir・Perl・Gleam・Bun のテンプレートにも共通の `with-env` app と devShell 内の同名コマンドを含めている。生成先で `nix flake lock` を実行して lock を Git に追加し、`nix develop .#default` / `nix run .#with-env -- command` を使う。言語別の dev / test 組込み例・信頼登録・明示再読込み・dotenv 移行は、生成物の `DEVELOPMENT.md` を参照する。テンプレートは browser を含まない `default` のみを持ち、WSL でも `.wsl-browser-free` なしで利用できる。別 output や marker を追加する場合は対応する devShell も定義する。

人間は `nix run .#dev` / `nix run .#test`、raw Codex は `with-env --prepared -- bun run dev` / `with-env --prepared -- bun run test` を正式入口にする。Claude への dotenv 注入と permission 変更は対象外。実行環境と証拠は [Issue #257 の検証記録](../docs/research/with-env-257.md) を参照。

## Claude のプロジェクト開発環境

同じ `devshell-env trust [directory]` の登録と output 選択を使う。登録済み repo で通常どおり `claude`、または Orca の built-in Claude を起動すると、その root の devShell のツール・通常変数を後続の Bash ツールで利用できる。primary checkout と正当な linked worktree が対象になる。Orca の worktree 作成・Agent Picker・permission mode は引き続き Orca が所有する。

`SessionStart` は初期環境を準備する。`SessionStart` と `CwdChanged` は Claude の `CLAUDE_ENV_FILE` へ session 用 script の source を追記し、他 hook の内容を保持する。Claude 2.1.263 の `CwdChanged` は非同期で、`EnterWorktree` では発火しないため、`PreToolUse(Bash)` が実際の cwd と信頼状態を同期確認して切替を確定する。同じ Git root・output・信頼状態・flake 有無なら Nix と shellHook を繰り返さない。遅れて到着した `CwdChanged` は環境を上書きしない。Bash ツールの backend が bash・zsh のどちらでも同じ差分を反映する。

flake を編集したら、Claude の Bash で `devshell-env reload` を実行する。その次の Bash から反映され、reload を呼んだ Bash 自身や、既に実行中のコマンドは変わらない。通常 Bash には `CLAUDE_ENV_FILE` が渡らないため、hook が設定する `DEVSHELL_ENV_SESSION` で接続する。この変数は手動設定せず、管理 hook のないセッションでは Claude を起動し直す。自動ファイル監視は行わない。

別 repo・worktree、未登録、flake 不在へ移動した場合は次の Bash の前に旧環境を解除する。Nix／shellHook の失敗も旧環境を解除して理由を表示し、調査を継続できる。`devshell-env status` で root と登録を確認し、必要な登録・flake 修正後に `devshell-env reload` で再試行する。失敗した reload は非0終了する。同じ対象の自動再試行は繰り返さず、明示 reload またはセッション再起動を使う。Nix と shellHook はそれぞれ50秒、managed hook は120秒が上限になる。

復元するのは環境変数と追加した PATH 要素であり、shellHook が作ったファイルなど外部副作用の巻戻しは保証しない。復元前に他 hook が同じ変数を別値へ変えていれば、その値を保持する。保存済みの他 hook の内容と、追加された PATH 要素も維持する。継承環境に元から含まれていた direnv の値は、この hook が追加した環境とは区別する。

session 状態は `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/.devshell-env/<session-id の hash>/` に置く。初期化結果だけを session 内で再利用し、`SessionStart` で再評価するため、session をまたいだプロジェクト環境キャッシュにはしない。Nix／shellHook へ渡すのは HOME と解決済み bootstrap ツールの PATH だけで、任意の継承値やその加工結果を新しい保存先へ残さない。元の変数値を復元するための情報は非exportの shell 変数に保持し、ファイルへ保存しない。dotenv と秘密取得は追加せず、shellHook 自身にも秘密取得を書かない。これは信頼した flake の外部副作用を封じる sandbox ではない。

Claude 本体と起動済み MCP の環境更新、Claude の dotenv 注入・OS sandbox 変更は対象外。既存 permission と RTK／Design Hook を維持する。未 merge の task source は実配備しない。[#256 の実 lifecycle・品質検証記録](../docs/research/devshell-env-256.md)を参照。

## 既存 repo の移行

1. `.envrc` にだけ置かれた通常変数・ツール・非秘密の初期化を `flake.nix` の devShell（またはそこから import するファイル）へ移す。dotenv や秘密取得は shellHook に置かない。既存 `.envrc` は明示利用のために残せる。dotfiles と6テンプレートの既存 `.envrc` は flake と dotenv を呼ぶだけで、通常設定の追加移植は不要。
2. flake と lock、必要な import ファイルを Git に追加する。`.env` と `.env.*` は追跡対象外に保ち、必要な値は作業する root に人間が用意する。`with-env` は main・親・別 worktree を探索・コピーしない。
3. 人間は上記の `nix develop` でツールと通常変数を確認する。AI 自動読込みを使う repo は `devshell-env trust` で一度登録し、`devshell-env status` で root・output・信頼を確認する。解除は `devshell-env untrust`。別 clone は別登録になる。
4. 指定コマンドに dotenv が必要なら、テンプレートの `DEVELOPMENT.md` または上記の組込み例に従い `with-env` を devShell と app に追加する。人間は `nix run .#with-env -- command`、準備済み raw Codex は秘密なしの `with-env --prepared -- command` を使い、初回に上記の公開入力登録も行う。Claude は非秘密の devShell だけを使い、dotenv が必要な処理は人間側の入口で実行する。
5. 旧 hook が動く端末は終了し、受入・merge 後に live source で `chezmoi apply` してから新しい端末を開く。未 merge の task source は配備しない。通常変数とツール、明示更新、正式入口の失敗を確認する。

従来の `.envrc` の `dotenv_if_exists .env` はシェル全体へ値を export していた。新しい注入は対象コマンドとその子に限定し、同名変数は起動元 → devShell → root `.env` の順で優先する。隔離された raw Codex はこの注入を行わず、起動元の秘密も継承しない。既存シェル・直接起動にはこの保証を適用しない。Claude の `.env` 注入・OS sandbox と Orca native Codex の自動読込みは対象外で、既存 permission は維持する。

既存 `.envrc` を明示的に使う場合は内容を確認して `direnv allow .`、続けて `direnv exec . command` を使う。この子には従来の dotenv 読込みも適用される（[direnv の公式コマンド仕様](https://direnv.net/man/direnv.1.html)）。セットアップや Codex 管理同期は自動承認しない。

共通ツールや APM の復旧は `nix develop ~/.config/nix-devshell#default --command chezmoi apply`（WSL2 は `#wsl`）を使う。ユーザー環境キャッシュの必須更新は通常配備と同じ入口で行い、`direnv reload` を前提にしない。ここでも配備は受入済み live source から行う。

## ghq + fzf リポジトリ管理

`.bashrc` の関数で提供:

| コマンド | 動作                                                                               |
| -------- | ---------------------------------------------------------------------------------- |
| `Ctrl-G` | flyline 有効時は入力を破棄して `gcd` を実行し fzf 選択 → cd、fallback 時は直接起動 |
| `gcd`    | リポジトリを選んで cd                                                              |
| `gclone` | 引数ありで `ghq get`、なしで `gh repo list`（ユーザー + 所属 Org）→ fzf → clone    |
| `gedit`  | リポジトリを `$EDITOR` で開く                                                      |
| `gweb`   | リポジトリを `gh browse` で表示                                                    |
| `ginit`  | `owner/repo` 形式で ghq 管理下にローカルリポジトリを作成                           |

## その他

- **tmux** — `Ctrl+a` プレフィックス
- **neovim (lazy.nvim)** — LSP は flake devShell 管理のものを PATH 経由で利用
- **wezterm** — ターミナル（Dracula テーマ、WSL 対応）

関連: [architecture](../docs/architecture.md) / [ai-runtimes](ai-runtimes.md)
