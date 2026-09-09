---
type: research
title: Issue 257 with-env の実装と sandbox の未成立条件
description: 公開 Nix app の dotenv 注入、実行時だけの値の受渡し、Codex 権限の検証範囲
tags: [nix, dotenv, codex, verification]
---

# Issue #257 の検証記録

対象は [#257](https://github.com/treflebonbon/dotfiles/issues/257)、親は [#254](https://github.com/treflebonbon/dotfiles/issues/254)。依存 #255 の merge commit `e025054` を現在の validated task worktree に fast-forward して実装した。**Issue 全体は未完了**。公開 with-env app と人間の実行経路を実装し、raw Codex の権限変更は下記の未成立条件を解消するまで保留している。

## 実装した境界

`nix run .#with-env -- command [args...]` は同梱した `python-dotenv` と既存 Runtime Adapter の環境準備処理を使う。明示実行は trust 登録を要求せず、raw Codex の自動準備は既存どおり登録を要求する。dotenv の読取りは Nix と shellHook の終了後。親プロセスや AI セッション全体には注入しない。値と環境はメモリ・pipe で受け渡し、追加の環境保存ファイルは作らない。

対象の root と Git metadata は準備前後で検証する。dotenv は root 直下の一つだけを選び、親・main・別 worktree を探索しない。symlink の物理 target が root 内にあることを確認し、解決後の各 path component を `O_NOFOLLOW` で開く。FIFO はブロックせず拒否し、解析エラーは行番号だけを表示する。空値・引用符・複数行・変数展開・値のない名前は [python-dotenv の構文](https://bbc2.github.io/python-dotenv/#file-format) に従う。

## Codex sandbox の未成立条件

2026-09-09、Codex 0.153.4 / x86_64 Linux で、隔離 HOME・管理設定のコピー・ダミー値を使って確認した。実行中の agent 自体は sandbox 無効なので、その成功を権限の証拠にはしていない。

| 試行                                                                              | 実測結果                                                              | 判断                                                                                     |
| --------------------------------------------------------------------------------- | --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| 管理 profile の `**/.env` deny に root の exact read を追加                       | #255 の先行検証では拒否                                               | 単純な allow 追加を採用しない                                                            |
| 隔離した候補 profile で `.env` と `*/**/.env` の規則を分離し、root を read に変更 | root の read 成功、write 拒否、下位 `.env` の read 拒否               | root の read/write 分離自体は成立。source の管理設定には未採用                           |
| 同じ候補 profile から worktree 外の別ディレクトリの `.env` を read                | **成功してしまう**。`/tmp` 外の隔離 HOME 配下でも再現                 | 既存 profile の workspace 内だけの deny では、Issue が求める他 repo の拒否を保証できない |
| `:root=deny` と `:minimal=read` を候補へ加える                                    | 外の `.env` は見えなくなるが、通常の PATH 上の Nix も起動できなくなる | 広い境界変更を黙って導入しない                                                           |
| 実 Runtime Adapter → 標準 sandbox → 公開 with-env app                             | Nix の Unix domain socket 作成を拒否し、exit=1、対象コマンド未起動    | #255 の制約を本実装でも再現。raw sandbox 内の実行は未完了                                |

候補 profile の root 規則を `:workspace_roots` 全体で read に変える方法は、profile-defined な追加 workspace root にも及び得る。そのため「信頼済みの対象 root だけ」という要件の完成実装としては採用していない。標準 profile、既存の引数制限・Active Git Metadata Boundary、network 設定、Claude の permission は変更していない。

[Codex の権限仕様](https://learn.chatgpt.com/docs/permissions#filesystem-permissions) は同じ path の deny が read より優先すること、workspace-relative な deny が各 workspace root 内に適用されることを説明する。上記の実測とは区別する。Nix の read-only local store も候補を調査したが、[公式の前提](https://nix.dev/manual/nix/2.34/store/types/local-store.html#store-local-store-read-only) は他プロセスを含めて database が変化しないことで、通常の共有 daemon 環境にはそのまま適用できない。

## 検証

`python3 tests/helpers/with-env-preflight.py` で上記の実 adapter / sandbox / app 経路と候補 profile を再現できる。2026-09-09 の証拠は `/tmp/with-env-257-preflight-mdqmnl88/` に記録した。候補の実測は root read=0、root write=1、nested read=1、other repo read=0。スクリプトの成功は未成立条件の再現成功を意味し、raw Codex 機能の受入成功を意味しない。

```bash
TMPDIR=/tmp WITH_ENV_REAL_NIX=1 bats tests/with-env.bats
bunx tsc --noEmit
ruff check private_dot_local/bin/executable_devshell-env
nixfmt --check flake.nix
TMPDIR=/tmp bun run test
```

with-env の8件は実 Nix test を含めて成功。実 Nix test は公開 `nix run ...#with-env` から hello・通常変数・shellHook・dotenv・子プロセス・終了コード23を確認した。ダミー値は実行時に UUID として生成し、Nix の `print-dev-env` 出力、derivation JSON、app 出力、store 内の Git source、隔離 HOME・cache に値がないことを検索した。Git source 内に `.env` がないことも確認した。通常の全 Bats ではこの実 Nix test を opt-in として skip し、上記で別途実行する。

| #257 本文順の条件                                 | 状態                                                |
| ------------------------------------------------- | --------------------------------------------------- |
| 1: devShell 準備後の注入、`.envrc` 非依存         | 人間の公開 app で確認。raw sandbox での実行は未完了 |
| 2: root 限定、探索なし、外部 symlink 拒否         | Bats で確認                                         |
| 3: 不在許容、読取り・解析・準備失敗時の未起動     | Bats で確認                                         |
| 4: 既存 parser、構文・変数優先・非実行            | Bats で確認                                         |
| 5: 引数・終了コード・子プロセス限定               | Bats と実 Nix で確認                                |
| 6: 信頼済み raw 起動の root read                  | 未完了。管理設定と adapter の permission は未変更   |
| 7: 実 sandbox で限定 read と他秘密の拒否          | 上記の未成立条件あり。完成後受入は未完了            |
| 8: ダミー秘密の非永続化                           | 実 Nix の生成結果・隔離 cache を検索し確認          |
| 9: 通常／WSL 選択、direnv 継承                    | Bats で選択と PATH、3 system で app 出力評価を確認  |
| 10: dev/test 組込み例、必要変数と失敗時停止の規約 | shell-environment に記載                            |
| 11: Claude 非変更、品質、OS と配備の記録          | 最終結果は下記に追記                                |

3対応 system（x86_64-linux・aarch64-linux・aarch64-darwin）の app 出力評価は成功した。実行確認は x86_64 Linux のみ。WSL host・ARM Linux・Apple Silicon macOS は未確認。未 merge の source は配備していない。Session Scratchpad の提示がなかったため、一時検証ファイルとログには `/tmp` を使った。

## レビューと品質確認

`code-review` の固定点は依存実装の `e025054`。Standards と Spec を独立した2 agent で実施した。Standards は Python 依存定義の重複を非ブロッキングな heuristic として指摘したため共有化した。Spec は実装済み範囲に新たな不適合・scope creep を指摘せず、raw Codex の既知の未完了条件を確認した。root 選択のテストは dotenv を先に継承させずサブディレクトリから直接実行する形へ強化した。

実 Nix を含む with-env は8/8、既存 Runtime Adapter の `DEVSHELL_ENV_REAL_NIX=1 bats tests/devshell-env.bats` は18/18成功。`bunx tsc --noEmit`、ruff check/format、nixfmt、diff whitespace 検査も成功した。pre-commit の gitleaks がテストのダミー文字列を検出したため、低エントロピーのダミーへ変更して該当テストを再実行し、hook を通過した。検査除外や `--no-verify` は使用していない。
