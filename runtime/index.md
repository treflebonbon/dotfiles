---
type: index
title: treflebonbon/dotfiles knowledge bundle
description: home 配下のどの repo でも共通する、ambient なシェル環境・skill 配備・AI ランタイム知識を OKF (Open Knowledge Format) で表現した agent 向けバンドル
tags: [dotfiles, chezmoi, runtime]
---

# treflebonbon/dotfiles — knowledge bundle

このディレクトリは [Open Knowledge Format](https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing) (OKF v0.1) に沿った知識バンドルです。各 concept は 1 ファイルの markdown で、`type` frontmatter を必須とし、markdown リンクで相互参照します。

chezmoi が `~/runtime/` へ配備するため、home 配下のどの repo で作業している agent もここを読める。**このディレクトリに置くのは、home 配下のどの repo でも同じ意味を持つ ambient な知識だけ**（シェル環境・skill 配備の仕組み・AI ランタイム設定）。ディレクトリ名は「runtime」— OKF は書式（markdown + frontmatter）の名前であり、内容を表す名前ではないため使わない。dotfiles repo 自身の内部構造（chezmoi source レイアウト、commit/lint 規約など）は、他 repo で作業中の agent には価値が無いため `docs/`（repo ローカル、`.chezmoiignore` で home 非配備）に置く（[ADR-0007](../docs/adr/0007-split-okf-by-cross-repo-value.md) 参照）。

このディレクトリの `../` で始まるリンクは、配備元の source（`chezmoi source-path` が返す directory）にある `runtime/` を起点にした相対パスとして辿る。`docs/` などは source 側にだけある。例: `../docs/adr/0007-split-okf-by-cross-repo-value.md` は `$(chezmoi source-path)/docs/adr/0007-split-okf-by-cross-repo-value.md` を読む。

## Concepts

- [shell-environment](shell-environment.md) — bash + starship/atuin/fzf/zoxide/ghq のシェル環境
- [human-validation](human-validation.md) — 秘密なしの AI 開発と、人間による固定版の別環境検証
- [skill-harness](skill-harness.md) — apm 経由の skill 群、mattpocock ワークフロー、playwright-cli
- [autonomous-peer-contract](autonomous-peer-contract.md) — 元候補を保持する native peer 協働、承認範囲、独立レビュー、保留と報告
- [ai-runtimes](ai-runtimes.md) — nix-devshell の AI ツールと Claude/Codex マルチランタイム、更新経路
- [investigation](investigation.md) — Google Cloud / GitHub の調査コマンド、機密項目の除外、未対応操作の実行前確認

別ディレクトリの git は `cd <dir> && git …` で実行する。worktree に隔離された Claude Code セッションは、自分の worktree の外（共有 checkout など）へ `cd` した git を拒否される。その worktree で完結させ、別 checkout の操作が要るときはユーザーへ戻す。`git -C` などの global option は push を承認規則から隠せるため、Claude の deny（dotfiles の `private_dot_claude/settings.json.tmpl` の `Bash(git -C:*)`）と Codex の forbidden rule（`private_dot_config/codex/rules/default.rules`）で拒否される。`W=<dir>; git -C $W …` のような変数代入つきの複合コマンドも `git -C` を含むため拒否された。変数代入そのものが拒否されるかは未確認。git を含まない `herdr pane layout --pane "$HERDR_PANE_ID"` は、変数の展開を理由に拒否された（confirmed、2026-10-23、Claude Code 2.1.296）。`echo "$HERDR_PANE_ID"` 単体は通った。他の変数展開の形に一般化できるかは unconfirmed。#458 の隔離 session（Claude Code 2.1.296）では、git を含まないコマンドも、実行内容を検証できない形だと拒否された。例は本文を引数に渡す `herdr agent prompt`、`bash <script>`、`printf … > file`。実行権限を付けたスクリプトを絶対パスで呼ぶと通った。#468 の隔離 session（同じ 2.1.296、2026-10-23）でも、scratchpad のスクリプトを `bash` で呼ぶと「git を検証できない形」として拒否された（confirmed）。scratchpad のパスに含まれる `-github-com-` が理由かは inferred。本文を `--body "…"` で渡す `gh issue comment` も拒否され、worktree 内に置いた一時ファイルを `--body-file <相対パス>` で渡すと通った（confirmed）。Herdr agent への本文の送信には `herdr-ask`（[Herdr からの agent 起動](ai-runtimes.md#herdr-からの-agent-起動)）を使う。

隔離 session で Windows 側の dogfood Chrome を確認するには、実行権限つきの `~/.local/bin/dogfood-chrome-inspect` を絶対パスで呼ぶ（読み取り専用。CDP port 19330〜19393 の待ち受けの port・PID・起動時刻・command line を表示する）。`powershell.exe` の直接実行は `!` 経由でも拒否された（confirmed、#490）。

dotfiles repo 自身の構造・規約は [docs/architecture.md](../docs/architecture.md) / [docs/conventions.md](../docs/conventions.md)（repo ローカル）を参照。

## Decisions

意思決定記録（ADR）は mattpocock skills 標準に合わせて `docs/adr/`（repo root、repo ローカル）に一本化した。`runtime/` 配下には置かない（[ADR-0006](../docs/adr/0006-consolidate-decisions-into-docs-adr.md) 参照）。
