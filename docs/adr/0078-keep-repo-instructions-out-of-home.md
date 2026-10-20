---
type: decision
title: repo 直下の agent 指示を home へ配備しない
description: dotfiles repo 直下の CLAUDE.md / AGENTS.md を repo 編集用に限定し、全 repo 共通の指示はグローバル用ファイルだけが持つ
tags: [adr, chezmoi, claude-code, codex, instructions]
timestamp: 2026-10-20
status: accepted
---

# repo 直下の agent 指示を home へ配備しない

chezmoi は repo 直下の `CLAUDE.md` / `AGENTS.md` を `~/CLAUDE.md` / `~/AGENTS.md` として配備していた（ADR-0003 の「`~/CLAUDE.md` が知識バンドルを指す」モデル）。Claude Code は作業ディレクトリの祖先にある `CLAUDE.md` をすべて読むため、この repo では同じ指示を 2 回読み込み、`~` 配下の他の repo では dotfiles 専用の指示と repo 相対パスが context に入っていた（issue #447、PR #451 のレビュー）。グローバル指示の配備元は別に存在し、Claude Code は `~/.claude/CLAUDE.md`、Codex は `$CODEX_HOME/AGENTS.md` を読む。

## Decision

- repo 直下の `CLAUDE.md` / `AGENTS.md` は dotfiles repo を編集するための指示とし、`.chezmoiignore` で home への配備から外す。chezmoi の編集規則、flake 構成、この repo の検証コマンド、skill 配布経路、`docs/agents` の設定だけを持つ。
- 全 repo 共通の指示は `private_dot_claude/CLAUDE.md`（Claude Code）と `private_dot_config/codex/AGENTS.md`（Codex）だけが持つ。調査規則、設計→実装ワークフロー、Matt Pocock workflow contract（ADR-0023 の外部 skill のローカル上書きを含む）、ブラウザ操作の使い分けをこちらへ移し、参照先は `~/runtime/...` にする。
- ADR-0007 の「cross-repo 価値の有無で配備を分ける」基準を指示ファイルにも適用する。`runtime/` の home-wide 配備は変えない。

## Considered Options

- `.chezmoiroot` で source をサブディレクトリへ移す: chezmoi の正式な仕組みだが、source root の設定ごと移す必要があり変更範囲が広い。
- template で共通部分を `include` する: 本文の保守には効くが、読み込み範囲を分けられない。
- Claude Code の `claudeMdExcludes` で抑止する: Claude Code 側の設定で症状を抑えるだけで、配備構造は変わらない。

## Consequences

- dotfiles repo では repo 直下の指示とグローバル指示が 1 回ずつ読み込まれ、他の repo には dotfiles 専用の指示が入らない。
- `.chezmoiignore` に追加しても、既に配備された `~/CLAUDE.md` / `~/AGENTS.md` は消えない。merge 後に内容を照合・退避してから、人が一度だけ撤去する。`.chezmoiignore` にある対象は `.chezmoiremove` でも削除されないため、自動撤去の仕組みは追加しない。
- 指示ファイルの文言を検査するテストは、共通契約をグローバル用ファイルで、repo 編集規則を repo 直下のファイルで検査する。

関連: [ADR-0003](0003-okf-knowledge-bundle.md) / [ADR-0007](0007-split-okf-by-cross-repo-value.md) / [ADR-0023](0023-resolve-external-skill-contracts-locally.md)
