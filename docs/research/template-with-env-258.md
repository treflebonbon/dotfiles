---
type: research
title: Issue 258 言語テンプレートの独立展開と with-env 検証
description: 6言語の公開 devShell と with-env、dotenv 分離、system 評価と実行環境の記録
tags: [nix, templates, dotenv, verification]
---

# Issue #258 の検証記録

対象は [#258](https://github.com/treflebonbon/dotfiles/issues/258)、親は [#254](https://github.com/treflebonbon/dotfiles/issues/254)。依存 [#257](https://github.com/treflebonbon/dotfiles/issues/257) の merge commit `002085017c4260e3044156ab474823dad3bd1378` を実装の基点・レビュー固定点とする。

## 実装

Go・Rust・Elixir・Perl・Gleam・Bun の flake に、上記 revision を指す dotfiles input を追加した。言語用 nixpkgs は従来の `nixpkgs-26.05-darwin` を維持し、dotfiles 側から `follows` する。公開 `apps.<system>.with-env` を再利用し、各 devShell に同じ `with-env` package を加えた。既存の言語 package、Rust 1.98.0、対応3 system は保持する。

実行時の parser と root 探索・環境準備は #257 の実装一つを使う。テンプレートに script をコピーせず、展開先から dotfiles のローカル checkout や配備済み helper を参照しない。Nix の取得元と依存は生成先の `flake.lock` に記録する。

各生成物の `DEVELOPMENT.md` に明示 devShell、dotenv 契約、言語別 dev / test app の例、信頼登録、Claude の reload、raw Codex の再起動と `--prepared`、WSL / 明示 output を記載した。実在しないアプリのコマンドは flake に定義せず、例としてだけ示す。既存 `.envrc` は保持し、`.gitignore` で `.env` / `.env.*` / `.direnv/` を除外する（値を含まない `.env.example` は許可）。

## 検証境界と再現

Issue の Verification に従い、境界は「公開テンプレートを展開した独立 Git repo の devShell / with-env」とする。[Nix の公式 template 定義・展開方法](https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-flake-init.html) に従って `nix flake init -t git+file://<task-root>#<language>` を実行する。生成後の依存取得は公開 GitHub input をそのまま使い、ローカル path override は行わない。

```bash
TMPDIR=/tmp TEMPLATE_WITH_ENV_REAL_NIX=1 bats tests/template-with-env.bats
TMPDIR=/tmp bats tests/with-env.bats tests/devshell-env.bats
bunx tsc --noEmit
ruff check tests/helpers/template-with-env.py
ruff format --check tests/helpers/template-with-env.py
nixfmt --check templates/{go,rust,elixir,perl,gleam,bun}/flake.nix
shellcheck tests/template-with-env.bats
TMPDIR=/tmp bun run test
```

実 Nix の6言語テストは依存取得と全 devShell の実現を伴うため opt-in。`python3 tests/helpers/template-with-env.py --language bun` のように言語単位でも再実行できる。隔離 repo・HOME・cache とコマンドログは `/tmp/template-with-env-258-*` に残す。詳細な dotenv parser ケースは既存 `tests/with-env.bats` を再利用する。

最初の Bun tracer は生成先の `apps.x86_64-linux.with-env` 不在で失敗し、配線後は3 system の評価と devShell / app の実行が成功した。追加テストで使う derivation 参照を、package 用の `.#default` から `.#devShells.<system>.default` に訂正した。これは検証コードの誤りで、言語テンプレートの output を変更して回避していない。

## Verification Matrix

| #258 本文順の条件                   | 検証内容                                                                                                                                                          | 結果 |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- |
| 1: 6種類の flake / lock と with-env | 独立 repo へ公開 template を展開・lock 作成、3 system の app 評価と flake check、実 devShell / app から言語 version 実行                                          | 成功 |
| 2: `.envrc` 任意・非読込み          | 不在と副作用・非0終了を含む `.envrc` の両方で devShell / app が成功し、副作用ファイルがない                                                                       | 成功 |
| 3: #257 と同じ dotenv 契約          | root 値と既存値の競合、空・空白・シェル文字を含む argv、終了23、子への継承、解析・読取り・外部 symlink の拒否、linked worktree / サブディレクトリからの root 限定 | 成功 |
| 4: 言語 / system 保持・Nix 非残留   | 3 system の全 output 評価、言語ツール起動、ダミー値が print-dev-env / derivation / Git source / HOME / cache にない                                               | 成功 |
| 5: WSL / 明示 output                | marker 不在の WSL は default、marker のみで未定義 wsl は停止、明示 default が優先、未定義 output は停止。継承した direnv 選択を使用しない                         | 成功 |
| 6: 言語別の組込みと移行手順         | 全6生成物に `DEVELOPMENT.md` を同梱                                                                                                                               | 完了 |
| 7: 独立利用・環境と品質の記録       | この記録と独立展開 helper、関連 Bats・full suite・品質チェック                                                                                                    | 成功 |

## 実行環境と結果

実行ホストは WSL2 x86_64（kernel `6.18.33.2-microsoft-standard-WSL2`）、Nix 2.34.6。native Linux、ARM Linux、Apple Silicon macOS の実行環境はこのセッションにない。3 system の Nix 評価と WSL2 の実行を区別し、他 OS の実行結果として扱わない。

全6言語の実 Nix テストは成功（1 Bats case 内で6言語を実行）。各言語の x86_64-linux / aarch64-linux / aarch64-darwin の app・devShell・formatter 出力評価、WSL2 の明示 devShell / with-env と dotenv 回帰が全て成功した。生成した lock は一連の実行で書き換わらなかった。

| 言語   | WSL2 で両入口から確認した version | 3 system 評価 |
| ------ | --------------------------------- | ------------- |
| Go     | 1.26.7                            | 成功          |
| Rust   | 1.98.0                            | 成功          |
| Elixir | 1.20.4 / Erlang OTP 29            | 成功          |
| Perl   | 5.42.0                            | 成功          |
| Gleam  | 1.18.1                            | 成功          |
| Bun    | 1.3.13                            | 成功          |

生成先の lock は6言語とも nixpkgs `555cb0f648dd138a7a3c250f4f4928767707c988`、dotfiles `002085017c4260e3044156ab474823dad3bd1378`。Rust の追加 input は rust-overlay `6ae57a71bcb0bebc7a66cc2bd76942c4cf649167`。これは今回生成した lock の記録で、テンプレートの言語用 channel を新たに exact pin したものではない。

関連 Bats は37件中34件成功・3件skip。全スイートは593件中589件成功・4件skip・失敗0件、終了コード0。追加した実テンプレートテストは別途 opt-in で成功した。残る3件は既存 #255 / #257 の実 Nix / Codex sandbox opt-in で、この変更では再実行していない。共通 parser / adapter のコードは変更しておらず、既存の詳細 parser 契約は34件の関連テストで通過した。

型検査・ruff check/format・nixfmt・shellcheck・shfmt・diff whitespace は成功。初回の型検査は checkout の `bun-types` 未導入で失敗したが、`bun install --frozen-lockfile` 後は成功した。6言語の Markdown 内の app 例も各 flake に組み合わせて `nix-instantiate --parse` で構文検証した。

証跡:

- `/tmp/template-with-env-258-oavz99cm/`: 独立6 repo と linked worktree、生成した lock、隔離 HOME / cache、`commands.log` と言語別 Nix 出力・derivation。サブディレクトリからのコマンドは各 `<language>-worktree/commands.log` に記録。
- `/tmp/template-with-env-258-real.log`: 実 Nix / 全6言語の結果。
- `/tmp/template-with-env-258-contract.log`: 関連37件。
- `/tmp/template-with-env-258-full.log`: 全593件。
- `/tmp/template-with-env-258-red.log` と `/tmp/template-with-env-258-green-bun.log`: app 不在の red と初回 green。
- `/tmp/template-app-examples-258-xih73_39/`: app 例を組み込んだ構文検証用 Nix file。

未 merge の task worktree から `chezmoi apply` は実行せず、live source へ実装を反映していない。
