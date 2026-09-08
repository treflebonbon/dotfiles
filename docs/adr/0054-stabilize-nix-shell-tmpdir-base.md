---
type: decision
title: nix devShell の TMPDIR を静的 base 配下に安定化する
description: nix-shell が生成する `/tmp/nix-shell.XXXXXX` のランダムサフィックスにより additionalDirectories に静的パスで書けなかった TMPDIR carve-out gap（background task output 等）を、direnvrc の既存 Chrome 向け正規化を汎用の静的 base（`~/.cache/nix-devshell-tmp`）へ retarget して解消する。
tags: [adr, nix, direnv, claude-code, permissions, tmp]
timestamp: 2026-09-08
status: accepted
---

# nix devShell の TMPDIR を静的 base 配下に安定化する

[Issue #248](https://github.com/treflebonbon/dotfiles/issues/248) は、nix devShell が発行する `TMPDIR=/tmp/nix-shell.XXXXXX` のランダムサフィックスにより、session scratchpad carve-out に一致しない兄弟パス（特に background task の `<TMPDIR>/claude-<uid>/<project>/<session>/tasks/*.output`）が `additionalDirectories` に静的パスとして書けないと報告した。issue はこの carve-out gap を「Claude Code 自身が生成し自身が読めないパスで dotfiles 側では解消不能」とした。implement セッションで検証したところ、`tasks/` は Session Scratchpad（`.../scratchpad`）と同じ `<TMPDIR>/claude-<uid>/<project>/<session>/` の兄弟ディレクトリであり、TMPDIR 自体の base を静的パスへ安定化すればこの gap も解消できることを確認した。issue #248 の out-of-scope 判断はこの ADR で修正する。

## Decision

`private_dot_config/direnv/direnvrc` の既存 Chrome 向け TMPDIR 正規化（`_df_normalize_tmpdir_for_chrome`、`/tmp/nix-shell.*` を検出して plain `/tmp` へ収束させていた）を、汎用の静的 base `~/.cache/nix-devshell-tmp` へ収束させるよう retarget し、`_df_stabilize_nix_shell_tmpdir` へ改称する。`use_flake` / `use_nix` の既存ラッパーが `nix develop` / `nix-shell` 呼出し成功後にこの関数を呼ぶ配線は変えない。

`private_dot_claude/settings.json.tmpl` の `additionalDirectories` に `~/.cache/nix-devshell-tmp` を追加する。background task output や `to-pr` の `${TMPDIR:-/tmp}` fallback など書込みが必要な用途があるため `Edit(...)` deny は付けない。

## Considered Options

- **`/tmp` 配下の固定サブディレクトリ（例 `/tmp/dotfiles-nix-tmp`）にする**: ADR-0048 は「`/tmp` 全体を additionalDirectories に加えると無関係な他ファイルへの read も許可してしまう」という理由で `/tmp` の恒久追加を見送っている。`/tmp` 配下の固定サブディレクトリでも同じ `/tmp` 上の境界の曖昧さが残るため、user-scoped であることが明確な `~/.cache` 配下を採用した。
- **direnvrc の変更を見送り、settings.json.tmpl 側だけで対応する**: `additionalDirectories` はディレクトリの静的パス列挙であり、ランダムサフィックスを含むパスパターンをサポートする根拠が公式ドキュメントにない。direnvrc 側で TMPDIR の base 自体を静的化する以外に確実な手段がない。

## Mechanism（実測で訂正）

草案段階では「direnvrc の既存 Chrome 正規化は post-hoc collapse で、収束先を静的 base に変えるだけで十分」と考えたが、これは誤りだった。実際には次の2層になっている:

1. リポジトリ直下の `direnv exec . env` は `TMPDIR=/tmp` を返す — `_df_stabilize_nix_shell_tmpdir`（旧 `_df_normalize_tmpdir_for_chrome`）による post-hoc collapse はここで確定して発生する。
2. その後段で、ユーザー環境 devShell（`private_dot_config/nix-devshell/flake.nix`）自身の `nix develop` 呼出しが、その時点で継承した TMPDIR（step 1 の結果）を base として `mktemp -d "$TMPDIR/nix-shell.XXXXXX"` を実行し、ランダムサフィックス付きの leaf を生成する。

したがって static base（`~/.cache/nix-devshell-tmp`）は additionalDirectories の grant anchor であり、session ごとの isolation は Claude Code 自身のディレクトリ構造にではなく、この step 2 の `mktemp -d` が生成するランダム leaf に由来する。実測で、同じ static base を共有する2つの `nix develop` 呼出しを並行実行したところ、異なるランダム leaf（例 `nix-shell.helIHi` / `nix-shell.eY7h1q`）を得て衝突しないことを確認した。`additionalDirectories` はディレクトリの再帰的な静的パス grant のため、static base 1エントリで両方の leaf（とその配下の `tasks/*.output` を含む全 session）をカバーする。

## Consequences

`~/.cache/nix-devshell-tmp` は tmpfs（`/tmp`）ではなく home filesystem 上に置かれる。WSL2 環境では実害はないが、`/tmp` の「再起動で自動的に空になる」特性は失われるため、長期的にはこのディレクトリの手動クリーンアップが必要になり得る。自動クリーンアップの仕組みは本 ADR のスコープ外とする。

`_df_stabilize_nix_shell_tmpdir` の `mkdir -p "$_DF_NIX_TMPDIR_BASE" 2>/dev/null || return 0` は base directory を作成できない場合（権限不足等）に TMPDIR を無言で変更せず raw な `/tmp/nix-shell.*` のまま返す。この場合 `additionalDirectories` の当該エントリは実質何もカバーしない状態に静かに退行する。エラー通知は行わないため、原因調査時はまずこの mkdir 失敗を疑う。

`managed-chrome-owner`（[ADR-0047](0047-centralize-managed-chrome-ownership.md)）の `BROWSER_OWNERSHIP_DIR` 既定解決は `XDG_RUNTIME_DIR || TMPDIR || "/tmp"` の順で、`XDG_RUNTIME_DIR` が未設定な環境では TMPDIR の収束先が `/tmp` から `~/.cache/nix-devshell-tmp` へ変わる。保存内容は所有権 lock ファイルのみで機密性・サイズとも無関係なため実害はないが、意図した変更として記録する。

TMPDIR carve-out gap のうち、issue #248 が「dotfiles 側では解消不能」としていた background task の `tasks/*.output` は、本 ADR の static base 安定化によって同じ `additionalDirectories` エントリでカバーされる。

関連: [ADR-0048](0048-extend-additional-directories-with-edit-deny-readonly.md) / [ADR-0052](0052-resolve-to-pr-temp-artifacts-via-session-scratchpad.md) / [ADR-0047](0047-centralize-managed-chrome-ownership.md)
