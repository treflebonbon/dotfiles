---
type: decision
title: Codex の共有一時領域を /tmp/codex に限定する
description: 既存のビルド済み Codex を再利用し、専用一時領域の共有と機密ファイル名の拒否を両立する
tags: [adr, codex, permissions, temporary-files]
timestamp: 2026-10-15
status: accepted
---

# Codex の共有一時領域を /tmp/codex に限定する

Herdr の通常起動で Codex 0.162.1 を検証すると、管理 profile の `":slash_tmp" = "deny"` により、ホストに存在する `/tmp` の通常ファイルが sandbox 内では見えなかった。worktree 内と、そのセッションの `$TMPDIR` 配下の通常ファイルは読み取れた。

当初はスキルが使う任意の `/tmp/...` をそのまま共有し、既存の機密ファイル名の拒否を追加する方針に合意した。しかし、Linux の Codex 0.162.1 では `/tmp/systemd-private-*` などの読めないディレクトリで ripgrep が終了コード 2 を返し、sandbox 全体の起動が失敗した。深さを限定したパターンでも再現し、本体パッチの追加案は新しい source build を必要とした。

その後、ユーザーは「今回の新規パッチをやめ、既存のビルド済み Codex を使う」「専用の `/tmp/codex` 配下を共有し、機密名の拒否を維持する」を選択した。本決定は、任意の `/tmp` を共有する当初の方針を置き換える。

## 決定

- 通常の Codex がセッション間で共有する一時領域は `/tmp/codex` とする。スキルの一時作業は `mktemp -d /tmp/codex/<task>.XXXXXX` で分ける。
- `dotfiles-secure` の `:slash_tmp` は `deny` を維持し、明示的な `/tmp/codex` の table に読み書きと共通の機密ファイル名の拒否を設定する。各セッションの `$TMPDIR` は従来どおり利用できる。
- 共通管理設定を利用する Herdr の通常起動・通常の Codex CLI・アプリで方針を揃える。同期時は明示的に管理する `/tmp/codex` を古い worktree の展開結果と区別し、追加された利用者の拒否ルールを保持する。
- raw `codex-worktree` の外側の隔離を維持する。raw は隔離内の一時領域を使い、ホストの `/tmp/codex` を共有しない。[ADR-0044](0044-runtime-owned-worktree-entry-and-codex-activation.md) の秘密分離の境界を維持する。
- 今回の Codex 本体パッチは採用しない。Nix の package 定義と lock を変更せず、既存の cleanup パッチ付き Codex 0.162.1 のビルド済み出力を再利用する。既存 cleanup パッチと未キャッシュ環境の制限は[採用記録](../research/tool-snapshot-pr-20261013.md#codexの取得経路と残制限)に従う。

## 起動時の準備と保護範囲

Linux の sandbox は存在しない writable root を無視するため、既存の `SessionStart` hook で `/tmp/codex` を用意する。シンボリックリンクを拒否し、所有者を確認して mode 700 に揃える。通常ファイル・他人所有の領域などを安全に準備できなければ、hook の `continue:false` で停止する。既存の中身は削除しない。

共有領域にも dotenv・鍵・credential などの共通拒否規則を適用する。`.envrc` と `.env.example` は利用可能とし、それらの派生秘密ファイル名は拒否する。`/tmp/codex` の `.env` は、存在しないファイルに mount target を作らない glob にする。

ファイル名の拒否は内容による機密判定ではない。Linux では既存の `glob_scan_max_depth = 4` を使用するため、起動時に見つかった深さ 4 までの名前が対象であり、将来作られるファイルや別名の秘密は保証しない。専用領域内に読めないディレクトリがある場合は、現行版の走査エラーによる起動失敗を維持し、拒否規則を省略しない。

## 設定だけの比較

既存のビルド済み Codex 0.162.1 と公開ダミーファイルで比較した。

| 設定 | 通常操作 | 機密名の拒否 |
| --- | --- | --- |
| `/tmp` 全体を許可、追加の拒否なし | 読書き・作成・後片付けに成功 | ダミーの `private.key` も読めたため不採用 |
| `/tmp` 全体を許可、機密名拒否あり | 読めないシステム用ディレクトリの走査で起動失敗 | 操作自体を開始できない |
| 専用の `/tmp` 子ディレクトリを許可、機密名拒否あり | 読書き・作成・後片付けに成功 | ダミーの `private.key` を拒否したため採用 |

## 検証と配備

管理設定と同期の回帰、実 sandbox での共有領域の読書き・後片付け、共有領域外の `/tmp` の拒否、機密名の拒否と公開サンプルの許可、起動 hook の作成・再実行・不正な種類の拒否を検証する。Herdr の通常起動で実効権限と操作結果を照合し、raw の実隔離でホストの共有領域が見えないことを確認する。秘密値は使わない。

未 merge の task worktree から `chezmoi apply` は実行せず、受入後に live source から配備する。起動済みセッションへの反映は未検証で、新しい Codex セッションでの確認を前提にする。
