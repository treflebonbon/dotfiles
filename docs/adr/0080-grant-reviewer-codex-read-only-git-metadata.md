---
type: decision
title: レビュー役 Codex に linked worktree の Git metadata を read だけで渡す
description: 読み取り専用レビュー役は codex-reviewer で起動し、exact Git dir と common dir を read で足す
tags: [adr, codex, herdr, git, worktree, sandbox]
timestamp: 2026-10-21
status: accepted
---

# レビュー役 Codex に linked worktree の Git metadata を read だけで渡す

Herdr pane で起動したレビュー役の Codex は、task worktree で `git status` / `git diff` を実行すると `fatal: not a git repository: (null)` で失敗した（issue #457）。managed profile（`dotfiles-secure` / `dotfiles-peer`）は `":root" = "deny"` で workspace root の外を読ませない。linked worktree の Git dir と common dir は checkout の外にある。実装役の `codex-worktree` は起動時にこの 2 つを write で足すが（[ADR-0044](0044-runtime-owned-worktree-entry-and-codex-activation.md)）、レビュー役の起動経路（`herdr agent start --kind codex`、auto peer の素の `codex`）は足していなかった。

## Decision

- 読み取り専用レビュー役は `codex-reviewer` で起動する。`codex-reviewer` は `codex-worktree` と同じ `Repository.discover(linked_only=True)` で ownership chain を検証する。そのうえで `-C <root>`、`default_permissions`、`permissions.<profile>.filesystem={"<git dir>"="read","<common dir>"="read"}` を付けて Codex を起動する。
- 既定の profile は `dotfiles-secure`。auto peer は `--peer` で `dotfiles-peer` を選び、gh 資格情報の隔離を保つ。
- root・profile・filesystem・sandbox・rules を置き換える引数を受け取ったら、Codex を起動しない。対象は `codex-inner.py` の `validate_codex_arguments` と同じフラグ群。`-c` は `model`、`model_reasoning_effort`、`model_reasoning_summary`、`model_verbosity` の 1 行の値だけを許可する。`mcp_servers` や `notify` のように sandbox の外でコマンドを起動できるキーがあり、拒否するキーを列挙する方式では漏れるため。`--disable` は通す。auto peer の `--disable apps` を使うためで、adapter の validator を共用しない理由もここにある。
- Codex CLI の `-c` は key を「.」ごとに分割し、quoted key を TOML として解釈しない。そのため、`github.com` を含む path は key に書けない。path は inline table の値として渡す。Codex 0.162.1 では、この inline table は profile の既存の filesystem table にマージされた（`:workspace_roots` 配下の `.env` deny が残ることを実測）。

## Considered Options

- **レビュー役も `codex-worktree` で起動する**: 不採用。Git dir への write まで渡すうえ、adapter が `dotfiles-secure` に固定されていて `dotfiles-peer` の gh 隔離と両立しない。
- **権限は変えず、差分をファイルで渡す手順を文書化する**: 不採用。毎回の手作業が残る。

## Consequences

- レビュー役は対象 worktree の Git 履歴と状態を読める。commit などの Git 書込み、別 worktree、checkout 外の他の path は sandbox が拒否する（Codex 0.162.1 の `codex sandbox` で実測）。
- common dir には同じ repository の他の worktree の Git dir（metadata）も含まれる。common dir を読めないと objects / refs を扱えないため、この範囲は受け入れる。
- `codex-reviewer` は `codex-worktree` の秘密隔離を提供しない。非開示保証が必要な作業には使わない。
