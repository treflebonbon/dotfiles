---
type: research
title: Issue 257 with-env の実装と sandbox 検証
description: 公開 Nix app の dotenv 注入、raw Codex の限定読取り、実行時だけの値の受渡し
tags: [nix, dotenv, codex, verification]
---

# Issue #257 の検証記録

対象は [#257](https://github.com/treflebonbon/dotfiles/issues/257)、親は [#254](https://github.com/treflebonbon/dotfiles/issues/254)。依存 #255 の merge commit `e025054` を validated task worktree に fast-forward して実装した。公開 with-env app に加え、利用者が承認した worktree 外の読取り境界の見直しを実装し、raw Codex の実 sandbox でも検証した。

## 実装した境界

人間は `nix run .#with-env -- command [args...]`、raw Codex は devShell 内に準備した同じ公開 package の `with-env --prepared -- command [args...]` を使う。dotenv は同梱の `python-dotenv` で Nix / shellHook 準備後に解析する。対象は現在地の Git root 直下の `.env` 一つで、親・main・別 worktree を探索しない。値は指定コマンドと子だけへ注入し、AI セッション全体には追加しない。独自の環境保存ファイルは作らない。

root と Git metadata は準備前後で検証する。明示実行は trust 登録を要求せず、raw 自動準備は既存の登録を要求する。通常の公開入口は継承した照合情報を無視して常に準備し、`--prepared` の明示時だけ再利用する。情報不在・不一致の prepared mode は未起動で失敗する。raw の再利用情報は root・repo identity・output・root の flake/lock hash だけを持ち、変更を検出したら正式入口を失敗させる。import した Nix file の変更も含め、devShell の更新後は常にセッションを再起動する。再利用情報は agent から改変できない認証情報ではない。

symlink の物理 target は root 内に限定し、解決後の各 path component を `O_NOFOLLOW` で開く。FIFO はブロックせず拒否する。raw の追加 read は通常ファイルの root `.env` に限定し、symlink には与えない。解析失敗は行番号だけを表示する。空値・引用符・複数行・変数展開・値のない名前は [python-dotenv の構文](https://bbc2.github.io/python-dotenv/#file-format) に従う。起動元、devShell、dotenv の順に同名の値を優先する。

## 権限設計と確認した制約

Codex 0.153.4 / x86_64 Linux、隔離 HOME・レンダリングした管理設定・ダミー値を使った実測である。この agent session 自体の sandbox 無効環境は権限の成功証拠に使っていない。

既存の workspace 内 `**/.env` deny と単純な root read の追加では root read が成立せず、workspace 内だけの拒否では外の repo を保護できなかった。Nix daemon 接続も標準 sandbox 内では失敗した。このため root と下位 dotenv の規則を分け、`:workspace` 継承を維持しながら外側を既定で拒否する方式へ変更した。実行に必要な最小ランタイム・Nix・Git 関連だけを読取り可能とし、専用 `TMPDIR` と Active Git Metadata Boundary を許可する。Nix は起動前に準備し、コマンド時は再利用する。

[公式 Permissions](https://learn.chatgpt.com/docs/permissions#filesystem-permissions) にある workspace-only 構成と path scope に従う。追加 workspace root も同じ root-relative read の対象になるため、実 Codex `app-server config/read` で継承元を含む profile を解決し、追加 root をこの起動では無効化する。設定読取り失敗時は Codex を起動しない。Git metadata と root dotenv の動的規則は一つの filesystem override にまとめる。

Linux の実測では、外側を拒否した後も home の個別 deny を残すと bubblewrap の mount 構築が失敗し、拒否した `/tmp` 下の read-only 例外は見えなくなる。旧 home deny は既定拒否へ統合し、インストールする home ツールは `/tmp` 外で検証する。専用一時領域は mode 0700 の `/tmp/codex-worktree-*`。環境保存先としては使わず、子の一時ファイル用途に限る。

## 検証方法と受入条件

```bash
TMPDIR=/tmp WITH_ENV_REAL_NIX=1 DEVSHELL_ENV_REAL_NIX=1 bats tests/with-env.bats tests/devshell-env.bats
python3 tests/helpers/with-env-preflight.py
TMPDIR=/tmp bats tests/codex-config.bats
bunx tsc --noEmit
ruff check private_dot_local/bin/executable_devshell-env tests/helpers/with-env-preflight.py tests/helpers/codex-config-reader.py
nixfmt --check flake.nix
shellcheck private_dot_local/bin/executable_sync-codex-managed-config
TMPDIR=/tmp bun run test
```

with-env と既存 Runtime Adapter の実 Nix opt-in は計32件。`with-env-preflight.py` は実 adapter と sandbox を通す受入スクリプトであり、以前の未成立条件を再現するだけのスクリプトから置き換えた。通常 Bats の実 Nix / sandbox 3件は opt-in とし、上記で別途実行する。

| #257 本文順の条件                             | 確認内容                                                                                                                                                                                                     |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1: devShell 準備後の注入、`.envrc` 非依存     | 公開 app の hello・通常変数・shellHook。raw で shellHook 1回、同じ devShell の Git 選択を保持                                                                                                                |
| 2: root 限定、探索なし、外部 symlink 拒否     | Bats の親/main/subdirectory、実 sandbox の別 repo・sibling・外部 symlink                                                                                                                                     |
| 3: 不在許容、読取り・解析・準備失敗時の未起動 | Bats の unreadable / FIFO / Nix / hook failure、実 sandbox の absent / malformed / symlink と未起動確認                                                                                                      |
| 4: 既存 parser、構文・変数優先・非実行        | 空値・quotes・multiline・展開・caller 優先・shell text 非実行                                                                                                                                                |
| 5: 引数・終了コード・子プロセス限定           | 空引数・空白付き引数・終了コード23・孫プロセス、raw 親環境の dotenv 不在                                                                                                                                     |
| 6: 信頼済み raw 起動の root read              | 未登録・解除・Nix 失敗では拒否、信頼済みは read のみ。実効 profile の直接・継承追加 root の無効化                                                                                                            |
| 7: 実 sandbox で限定 read と他秘密の拒否      | root write、下位・別名 dotenv、pem/key/pfx/p12、credentials/secret/service-account JSON、SSH/AWS/gcloud、外側 repo を拒否。Git add/commit と既存 push fixture、許可 registry / 非許可 example.com の network |
| 8: ダミー秘密の非永続化                       | 実行時 UUID を生成。人間の Nix 環境出力・derivation・app・Git source・cache を検索。raw は dotenv と継承値の両方について隔離 HOME・fixture・専用 TMPDIR を検索                                               |
| 9: 通常／WSL 選択、direnv 継承                | Bats の選択・PATH、3 system の app 出力評価                                                                                                                                                                  |
| 10: dev/test 組込み例、必要変数と失敗時停止   | [利用方法](../../runtime/shell-environment.md#指定コマンドへの-dotenv-注入) に人間と raw の正式入口・変数検証・再起動を記載                                                                                  |
| 11: Claude 非変更、品質、OS と配備の記録      | Claude の dotenv / permission は未変更。検証結果と制限は以下                                                                                                                                                 |

Git source 内の `.env` 不在も確認する。dotenv を Git や flake に含めない運用が前提で、起動元の秘密を識別・除去する機能ではない。root `.env` の読取りは agent にも許可しており、agent 自身から秘密を隠す保証はしない。

## 結果とレビュー

固定点 `e025054` から `c35733d` を Standards / Spec の独立した2 agent でレビューした。Standards は0件。Spec は通常の入口でも照合情報の継承により準備を省略する問題を1件指摘した。`843709c` で通常入口は必ず準備し、raw のみ明示的な `--prepared` を使う方式へ修正した。2件の回帰テストで修正前の失敗を確認し、修正後は実 Nix / 実 sandbox を含む with-env 13/13 が成功した。両 reviewer の再確認で未解消の指摘は0件。

実 Nix の既存 Runtime Adapter 19/19、Codex 設定・移行・実 sandbox 49/49、typecheck・ruff check/format・nixfmt・shellcheck・diff whitespace・commit hook は成功した。実受入スクリプトは `/tmp/with-env-257-preflight-a4iafybz/` と隔離 HOME `/home/ubuntu/with-env-257-home-g62ahjlx/` で成功。trusted / absent は exit=0、untrusted / revoked / external-symlink / malformed / preparation-failed / unprepared-entry は exit=1。未準備の `--prepared` は PATH lookup の失敗に頼らず、公開 app の絶対 store 実行ファイルまで到達して未起動で失敗する。

最終 `TMPDIR=/tmp bun run test` は終了コード0、577件中574件成功・3件skip・失敗0件。skip は実 Nix / sandbox の opt-in で、with-env 13/13 と既存 Runtime Adapter 19/19 の実行で全て別途成功した。最終コミット前の gitleaks と Conventional Commits 検証も通過し、検査除外や `--no-verify` は使っていない。再現ログは以下を参照する。

- `/tmp/with-env-257-full-verified.log`: 最終全 Bats
- `/tmp/with-env-257-mode-red.log`: 通常入口の準備省略を検出した回帰テスト
- `/tmp/with-env-257-mode-green.log`: 修正後の with-env 13/13（実 Nix / 実 sandbox を含む）
- `/tmp/with-env-257-real-final.log`: 既存 Runtime Adapter の実 Nix を含む19件
- `/tmp/with-env-257-prepared-acceptance.log`: 最終の実 adapter / 実 sandbox と非残留検証
- `/tmp/with-env-257-config-verified.log`: 管理設定と移行・sandbox の49件

3対応 system（x86_64-linux・aarch64-linux・aarch64-darwin）の app 出力評価は成功した。実行確認は x86_64 Linux のみ。WSL host・ARM Linux・Apple Silicon macOS は未確認。未 merge の source は配備せず、live source と runtime 設定は変更していない。レビュー固定点は依存実装 `e025054` とする。
