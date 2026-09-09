---
type: research
title: Issue 255 raw Codex の devShell 起動と先行検証
description: repo trust、Runtime Adapter、実 Nix・Claude hook・Codex sandbox の成立条件と検証範囲
tags: [nix, codex, claude-code, worktree, verification]
---

# Issue #255 の検証記録

対象は [#255](https://github.com/treflebonbon/dotfiles/issues/255)、親は [Spec #254](https://github.com/treflebonbon/dotfiles/issues/254)。base は `f0257af752718826b81f15736862b9ead9a452a0`。2026-09-09 に validated linked worktree で実装し、未 merge source の live apply は行っていない。利用方法は [shell-environment](../../runtime/shell-environment.md#raw-codex-のプロジェクト開発環境) を参照。

## 実装前の成立確認

隔離 HOME・設定・Git repo とダミー値だけを使った。実行環境は x86_64 Linux、Nix 2.34.6、Codex 0.153.4、Claude Code 2.1.263。現在の agent session は sandbox 無効なので、通常のコマンド成功を sandbox の証拠にせず、別プロセスの `codex sandbox -P dotfiles-secure` で確認した。

| 検証                                              | 実測結果                                                                                                                                           | 設計への反映                                                                                                |
| ------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| 実 Nix `print-dev-env` と daemon                  | host 側で mkShell、hello、通常変数、shellHook が動いた。継承ダミー値は Nix 出力に出なかった                                                        | raw adapter は sandbox 起動前に準備する                                                                     |
| 標準 Codex sandbox 内の Nix                       | `cannot create Unix domain socket: Operation not permitted` で非0終了                                                                              | 権限を緩めず記録。後続 with-env の sandbox 内 Nix 再評価は、この host で成立済みとは扱わない                |
| Claude SessionStart → Bash                        | `observed=initial envfile=unset`                                                                                                                   | hook の `CLAUDE_ENV_FILE` に session 用設定ファイルの source を追記する接続が成立                           |
| 同じ Claude session の明示 reload → 次の Bash     | 設定ファイルを更新すると `observed=reloaded`                                                                                                       | 通常 Bash へ `CLAUDE_ENV_FILE` が渡るという前提は使わない。#256 で session 状態・切替・旧環境解除を実装する |
| Codex root `.env` の exact read 追加              | 管理 profile の `**/.env` deny に exact read を重ねても読取り拒否                                                                                  | allow の追加だけでは成立しない                                                                              |
| root と下位 `.env` の規則を分離したダミー profile | `**/.env` を `*/**/.env` に絞り、検証対象 root の exact read を追加すると、root の read 成功・write 拒否、下位 `.env` と `.env.local` の read 拒否 | #257 向けの候補。管理設定には未導入であり、他 root・symlink・deny 全体の完成後受入は #257 が担当            |

Claude は実際の hook と Bash lifecycle を使用した。モデル応答だけを loopback HTTP fixture で固定し、実 API、実 credential、live Claude 設定を使わなかった。Orca 起動の Claude、CwdChanged、EnterWorktree、他 hook との共存を確認した結果ではない。

初回の詳細出力は `/home/ubuntu/.cache/nix-devshell-tmp/devshell-255-preflight-d_nzca7e/` に残した一時証跡。Claude の再現用 fixture は次で実行でき、別の `/tmp/claude-env-preflight-*` に出力を残す。

```bash
python3 tests/helpers/claude-env-preflight.py
```

公式の [Claude hook 環境反映](https://code.claude.com/docs/en/hooks#persist-environment-variables)、[Codex permission の優先順位](https://learn.chatgpt.com/docs/permissions)、[Nix print-dev-env](https://nix.dev/manual/nix/2.34/command-ref/new-cli/nix3-print-dev-env) を参照した。仕様の記述と上記の実測は区別する。

## 実装と検証境界

`devshell-env` に repo 所属検証を集約し、`codex-worktree` は argv をそのまま渡す。登録 CLI と adapter の両方が同じ物理 root／metadata の検証を使う。trust record は common directory の path・device・inode のみで、環境を保存しない。Nix の対象は URL encode した明示的な Git flake URL で固定し、他 root や `.envrc` を探索しない。

Nix と shellHook は最小環境で動かし、Nix 出力・子環境はメモリと pipe だけで受け渡す。元の任意変数は最終 Codex へ継承する。shellHook が継承秘密を別名へ加工して保存する経路も、ダミー値の不在を観測して検証した。これは任意の悪意ある flake の副作用を封じる sandbox ではない。秘密取得を shellHook に書かず、dotenv を Git に追跡させない。Nix が Git source として保存する追跡ファイルは、本処理の環境差分除外とは別の責務になる。

`nix print-dev-env` の Bash 出力が shellHook を実行することを実出力で確認し、別途の二重 eval は行わない。失敗時は準備中の環境全体を捨て、起動元の環境だけで調査を続行する。準備後に metadata の所属と identity を再検証し、異常があれば起動を拒否する。

## Verification Matrix

| #255 の条件（親 AC）              | 種別・検証入口                                        | 結果・範囲                                                                                                                                  |
| --------------------------------- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| 先行検証（AC20）                  | 上記の実 Nix・Claude lifecycle・実 Codex sandbox      | 成立条件と Nix socket の制約を記録済み                                                                                                      |
| trust/untrust/status（AC02）      | `tests/devshell-env.bats` の公開 CLI                  | 登録・worktree 継承・解除・repo 外保存、解除後に Nix 未実行                                                                                 |
| 物理パスと所属（AC03）            | 実 Git fixture と公開 CLI                             | 正当な alias、別 clone、common dir 再作成、偽装・symlink・未解決 metadata                                                                   |
| 未登録・flake 不在（AC04）        | CLI と launch sentinel、既存 Codex Bats               | Nix 未実行の調査起動と primary／非 Git の起動拒否                                                                                           |
| raw Codex の環境（AC01・AC05）    | adapter → 子コマンド、実 Nix opt-in test              | ツール・通常変数、`.envrc` 非実行、引数・終了コード                                                                                         |
| 起動境界（AC09）                  | 既存 Codex Bats、Nix 後の境界変更 fixture、実 sandbox | argv・引数制限・Git 変数除去・root/profile/Git metadata 固定。実 devShell 内の hello と sandboxed Git commit が成功し、`.env` は拒否        |
| 準備失敗と更新（AC08・AC10）      | Nix／hook 失敗・再起動 fixture                        | 部分環境を破棄、理由を表示、shellHook 1回、再起動で編集反映                                                                                 |
| WSL・明示 output・継承（AC17）    | WSL/direnv 環境を持つ fixture と既存 cache Bats       | 対象 root の marker、明示 output 優先、プロジェクトと起動元の PATH                                                                          |
| 秘密と runtime 境界（AC15・AC19） | ダミー値、Nix／hook snapshot、保存先検索、実 Nix      | Nix／hook／登録情報／隔離 cache に継承値と dotenv 値の残留なし。Codex への既存継承は保持。Orca native launch と管理 permission 設定は無変更 |
| 文書・品質・配備（AC20）          | 関連 Bats、型チェック、lint、全 Bats                  | 最終実行結果は下記に記録。live source と配備先は未変更                                                                                      |

再現コマンド:

```bash
DEVSHELL_ENV_REAL_NIX=1 bats tests/devshell-env.bats tests/codex-config.bats
bunx tsc --noEmit
ruff check private_dot_local/bin/executable_devshell-env tests/helpers/claude-env-preflight.py
shellcheck private_dot_local/bin/executable_codex-worktree
TMPDIR=/tmp bun run test
```

実 Nix test は host の Nix と repo の cached nixpkgs が必要。通常の全 Bats では opt-in test を skip し、上記コマンドで別途実行する。既存 Codex Bats は管理設定・network allowlist・Git 書込みと秘密ファイルの拒否を実 sandbox で検証する。

## 対応環境

`nix eval --offline --json .#devShells --apply 'shells: builtins.mapAttrs (_: outputs: builtins.mapAttrs (_: shell: shell.drvPath) outputs) shells'` は3 systemの default/wsl、計6出力で成功した。

| 環境           | Nix 出力評価                                              | 実行                                                       |
| -------------- | --------------------------------------------------------- | ---------------------------------------------------------- |
| x86_64-linux   | default/wsl 成功                                          | 実 Nix、raw adapter、Codex sandbox、Claude fixture 成功    |
| aarch64-linux  | default/wsl 成功                                          | 対応 host がないため未確認                                 |
| aarch64-darwin | default/wsl 成功                                          | Apple Silicon host がないため未確認                        |
| WSL2           | x86_64-linux の wsl 出力評価、marker/継承選択の Bats 成功 | Windows/WSL host がないため daemon・sandbox の実行は未確認 |

## 最終品質確認

新規 Bats は実 Nix opt-in を含む16件が成功した。既存 Codex Bats 48件、workflow contract Bats 18件、Claude lifecycle fixture、`bunx tsc --noEmit`、ruff check/format、adapter の ShellCheck も成功した。commit 時の oxfmt・gitleaks・Conventional Commit 検証を通過した。

初回の全 Bats は inherited `TMPDIR=/home/ubuntu/.cache/nix-devshell-tmp` で実行し、543件中、Design Hook 9件と dogfood browser 4件が失敗した。同じ未変更テストを `TMPDIR=/tmp` で単独比較すると、Design Hook の immediate finding と browser 4件はすべて成功した。一時領域の変更で解消する環境差として記録し、テストや実装の条件を弱めず、最終の全 Bats は `/tmp` を明示して再実行した。

`code-review` の Standards 軸は ADR-0044 の旧責務境界との文書不整合を指摘したため、#255 が承認する拡張を既存 ADR の amendment と skill-harness へ記録した。trust record の書込みは明示 CLI が所有し、自動 adapter は登録を読む。Spec 軸の指摘はなかった。追加確認で通常の XDG 検索パスを保持し、相対 PATH からの実行ファイル選択も固定した。両軸の再レビューは `b27d1d4` までを対象に未解決 finding 0件となった。

最終 `TMPDIR=/tmp bun run test` は終了コード0。545件中544件成功・1件skip・失敗0件だった。skip は opt-in の実 Nix test で、`TMPDIR=/tmp DEVSHELL_ENV_REAL_NIX=1 bats tests/devshell-env.bats` による16/16成功で別途確認した。全実行ログは `/tmp/devshell-255-full-bats-final.log`、初回の環境差を含むログは `/tmp/devshell-255-full-bats.log` に保存した。
