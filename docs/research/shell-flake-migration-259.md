---
type: research
title: Issue 259 標準シェルの flake 移行と親仕様の検証対応
description: direnv 自動 hook の停止、公開入口の統合検証、AC01–AC20 の証拠と環境別の限界
tags: [shell, nix, direnv, verification]
---

# Issue #259 の検証記録

対象は [#259](https://github.com/treflebonbon/dotfiles/issues/259)、親は [Spec #254](https://github.com/treflebonbon/dotfiles/issues/254)。固定基点は `b0fdad817033a1c34ea132cf54b13f4153e7a7b1`。依存 #255・#256・#257・#258 はこの基点に取り込まれている。current linked worktree と Git metadata を確認し、live source `/home/ubuntu/ghq/github.com/treflebonbon/dotfiles` は配備元の確認だけに使った。

## 実装と監査

bash／zsh の標準 direnv hook と初回導入の `direnv allow` を外した。direnv・nix-direnv package と、dotfiles／6言語テンプレートの既存 `.envrc` は保持する。root と6テンプレートの `.envrc` は `use flake` と `dotenv_if_exists .env` だけで、通常設定を追加移植する必要はなかった。ユーザー環境の `.envrc` は Nix の存在と WSL 選択だけを持ち、その通常設定も flake にある。

`install.sh` はキャッシュと同じ既存の output 選択関数を使い、WSL2 の初回評価と再配備も `#wsl` に揃えた。従来はキャッシュ生成より前の2回の `nix develop` が output 未指定だった。キャッシュの形式・鮮度・必須更新・対話起動の背景更新は維持した。

Codex の管理 `environments/environment.toml` は既存の名前と setup 形式を維持し、script を空にした。同期処理そのもの、Desktop の home 初期化、Orca native worktree／built-in launch、Claude permission は変更していない。APM が見つからないときの復旧案内は選択済みユーザー devShell からの `chezmoi apply` に変更した。

README・architecture・shell-environment・Serena の入口メモを監査した。direnv の残存参照は、明示利用、継承環境との区別、キャッシュからの `.direnv` 除外、既存実装・履歴の説明である。過去の ADR と ticket 検証記録は当時の証拠として保持した。運用手順は [shell-environment](../../runtime/shell-environment.md) に統合している。

## 検証境界と再現

親仕様の Testing Decisions に従い、実シェル起動、公開 CLI・Nix app、子プロセスから見える環境を境界とした。新しい Bats は source を chezmoi で隔離先へ render し、実 bash／zsh が cache 専用ツールを見つけ、direnv を呼ばないことを確認する。旧実装では両シェルの hook 呼出しを検出して失敗し、変更後は成功した。install の自動承認と WSL output も変更前の失敗を確認してから修正した。

```bash
bats tests/shell-flake-startup.bats tests/dot_bashrc.bats tests/dot_zshrc.bats
bats tests/install.bats
bats tests/codex-config.bats tests/apm-cache-refresh.bats
bats tests/shell-flake-startup.bats tests/nix-devshell-global-reload.bats
python3 tests/helpers/claude-env-preflight.py --real-nix --standard-shell --shell bash
python3 tests/helpers/claude-env-preflight.py --real-nix --standard-shell --shell zsh
nix flake check --no-build --all-systems
bunx tsc --noEmit
ruff check tests/helpers/claude-env-preflight.py
ruff format --check tests/helpers/claude-env-preflight.py
shellcheck install.sh private_dot_config/nix-devshell/lib/ensure-env.sh tests/shell-flake-startup.bats
shfmt -d install.sh private_dot_config/nix-devshell/lib/ensure-env.sh
TMPDIR=/tmp bun run test
```

`--standard-shell` は既存の実 Claude lifecycle fixture を拡張する。source の bashrc／zshrc と cache を隔離 HOME に置き、標準シェルから実 Claude を起動する。モデル応答だけは既存の loopback fixture を使い、実 Nix・実 hook・実 Bash と、Claude の EnterWorktree を実行する。人間と raw adapter は、その EnterWorktree が残した同じ linked worktree を使う。人間の `nix develop` は擬似端末で起動し、通常変数・hello・共通ツール、`exit` による親シェル復帰、編集後の再入場を確認する。パイプ入力では bash が Nix の rcfile を読まず、devShell が有効にならないため、対話シェルの証拠には使わない。

raw adapter の統合部分は Codex のモデル process と設定照会応答だけを fixture に置き換え、実 adapter・Nix・公開 with-env package を通す。起動と再起動、実 `direnv exec` からの継承、dotenv のコマンド単位注入、正式入口の失敗による未起動と調査用 AI 起動を確認する。これは sandbox の証拠ではなく、その境界は下表の #257 の実 Codex 記録に対応する。dotenv・継承値・登録先・HOME はすべてダミーまたは隔離先で、live 設定と実 credential は使わない。

## 親 AC の Verification Matrix

詳細ケースは各 ticket の成立済み記録を参照する。今回変更していない parser・metadata・sandbox・テンプレートの全ケースを個別に再実行せず、標準入口の統合と最後の全 Bats で照合する。

| AC   | 実装・証拠                                                                                             | 種別と確認範囲                                                                                               |
| ---- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------ |
| AC01 | [#258](template-with-env-258.md) の6言語独立 repo、#259 の source render と実 Nix                      | `.envrc` 不在・存在の新経路、通常設定は flake。既存 `.envrc` は保持                                          |
| AC02 | [#255](devshell-env-255.md)、`devshell-env.bats`                                                       | 公開 trust／untrust／status、repo 外保存と解除後の非評価                                                     |
| AC03 | #255、`devshell-env.bats`・`codex-config.bats`                                                         | 正当な linked worktree、別 clone・不正 metadata の境界                                                       |
| AC04 | #255、#256、同 Bats                                                                                    | 未登録・flake 不在・対象外の非評価、raw primary／非 Git 拒否                                                 |
| AC05 | #259 の `--standard-shell`、[#256](devshell-env-256.md)                                                | 同じ devShell の通常変数と hello、Claude 後続 Bash と人間・raw の入口。Claude 本体／MCP は対象外             |
| AC06 | #256 の実 Claude／Orca 通常接続、#259 の実 Claude                                                      | 起動・EnterWorktree・別 root・同一 root の回数。Orca Auto mode は #256 の再確認記録を採用                    |
| AC07 | #256、#259 の実 Claude、`claude-devshell-env.bats`                                                     | 旧環境の解除、失敗時の復元、他 hook の保持                                                                   |
| AC08 | #259 の実 Claude reload・人間再入場・raw 再起動                                                        | import した環境定義の編集を明示更新で反映。監視・永続 project cache の追加なし                               |
| AC09 | #255・[#257](with-env-257.md)、`codex-config.bats`                                                     | argv、root／Git metadata、標準 permission と Active Git Metadata Boundary                                    |
| AC10 | #259 の実 Nix と公開 app／adapter、実 Claude                                                           | 正式入口は未起動で失敗、AI 調査用起動は環境を付加せず継続                                                    |
| AC11 | #257、#259 の公開 app／prepared package                                                                | 人間と raw のコマンド・子だけへ dotenv 注入。argv／終了コードの詳細は #257                                   |
| AC12 | #257、`with-env.bats`                                                                                  | root 限定、不在、symlink／解析／読取り失敗。main 等からの暗黙供給なし                                        |
| AC13 | #257、`with-env.bats`、#259 の競合値                                                                   | dotenv の構文・非実行・起動元優先。通常変数の devShell 反映と dotenv の同名競合を区別                        |
| AC14 | #257 の実 Codex sandbox と `with-env-preflight.py`                                                     | root read／write deny、他秘密・外側・network。今回の model fixture を sandbox 証拠にしない                   |
| AC15 | #255・#256・#257・#258 の実 Nix 非残留、#259 の Claude 環境ファイル走査                                | ダミー値の Nix／derivation／cache／Claude file への非保存。継承済み秘密の除去と agent 自身からの秘匿は保証外 |
| AC16 | #259 の startup Bats・実シェル・install Bats                                                           | 自動 hook／自動承認停止、cache ツール、明示 direnv の継続                                                    |
| AC17 | #255・#257・#258 の通常／WSL／明示 output、#259 の WSL install と direnv 継承                          | 人間は Nix の output を明示、共通 CLI は現在 root の規則。3 system の評価と実ホストを区別                    |
| AC18 | #258 の6言語 `DEVELOPMENT.md`、README・[移行手順](../../runtime/shell-environment.md#既存-repo-の移行) | trust／解除／status／更新、with-env と dev／test の実入口・組込み例                                          |
| AC19 | 変更差分・Codex／Claude 設定 Bats、#256 の Orca 記録                                                   | Claude permission、cache、Orca 所有権を保持。Claude dotenv／OS sandbox と native Codex 自動読込みは対象外    |
| AC20 | 本記録、各 ticket の環境表、最終全 Bats／品質確認                                                      | 未 merge の source を実配備しない。親 issue の state 操作なし                                                |

## 環境の区別

今回の host は WSL2 x86_64-linux、kernel `6.18.33.2-microsoft-standard-WSL2`。Nix 2.34.6、bash 5.3.9、zsh 5.9.1、Claude 2.1.263 を使った。

| 環境                             | 評価                                            | 実行                                                                                 |
| -------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------ |
| WSL2 x86_64-linux                | dotfiles default／wsl・with-env                 | 今回の標準 bash／zsh、実 Nix、実 Claude、raw adapter 統合                            |
| native x86_64-linux              | 同じ x86_64-linux output                        | #255・#257・#258 の記録。今回は独立した native host がない                           |
| aarch64-linux                    | 今回の root flake 全 output と #258 の6言語     | 対応 host がなく未実行                                                               |
| Apple Silicon macOS              | 今回の aarch64-darwin 全 output と #258 の6言語 | 対応 host がなく未実行。WSL 上の zsh を macOS 実行成功とはしない                     |
| Orca built-in Claude             | 対象 flake は #256 と同じ共通入口               | #256 の通常接続による後続 Bash／reload・Auto mode 成功を採用。今回は再起動していない |
| Codex Desktop／Orca native Codex | 管理 setup は空、既存同期 Bats                  | 新しい自動起動は追加せず、GUI の再確認は行っていない                                 |

Session Scratchpad の指定がなかったため、証跡は明示 fallback の `/tmp` に置く。標準シェルのログは `/tmp/devshell-259-bash.log` と `/tmp/devshell-259-zsh.log`、各ログ先頭の `Evidence:` が隔離 HOME・fixture・コマンドログの保存先である。Bats は `/tmp/devshell-259-{shell,config,full}.log`、Nix 評価は `/tmp/devshell-259-flake.log` に記録する。

## 最終結果

実装コミット `606e7de`。`TMPDIR=/tmp bun run test` は終了コード0、596件中592件成功・4件skip・失敗0件だった。skip は実 Nix の devshell-env、6言語独立展開、with-env の実 Nix、実 Codex sandbox で、いずれも既存の opt-in。未変更の詳細ケースは #255・#257・#258 の上記記録を採用し、今回の標準入口の実 Nix は別途実行した。新しい shell startup の2件を含め、最終 source の Bats が通っている。

`--real-nix --standard-shell` は bash／zsh の両方で終了コード0。両ログ末尾に実 Claude lifecycle と標準入口の2つの PASS を記録した。成功時の fixture は bash が `/tmp/claude-env-preflight-oyz3zoq_/`、zsh が `/tmp/claude-env-preflight-7s_2_hxj/`。`commands.log`、`human-project.log`、`human-updated.log`、`claude-state/` に詳細を残している。

3 system の `nix flake check --no-build --all-systems`、型チェック、ruff check／format、ShellCheck、shfmt、差分の空白検査が成功した。コミット時の lefthook（shfmt・oxfmt・ShellCheck・gitleaks）と Conventional Commits 検証も成功。Serena CLI はこの PATH にないため、メモの既存 `mem:` 参照先6件をファイル一覧で照合した。参照の追加・削除はない。

`606e7de` を固定基点から独立した2エージェントでレビューした。Standards は規約違反0件・判断上の smell 0件、Spec は未充足・範囲逸脱・実装誤りの指摘0件。レビュー後の変更は本記録への最終結果追記だけで、実装とテストコードの追加変更はない。全テストの不要な再実行はせず、記録の整形・差分検査とコミット hook を通した。
