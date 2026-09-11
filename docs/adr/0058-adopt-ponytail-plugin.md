---
type: decision
title: ponytail plugin を enabledPlugins で home-wide に導入する
description: dietrichgebert/ponytail を full mode・subagent スコープ限定なしで有効化し、既存の avoid_overengineering ディレクティブを運用的な ladder で補う
tags: [adr, claude-code, plugins, ponytail]
timestamp: 2026-09-11
status: accepted
---

# ponytail plugin を enabledPlugins で home-wide に導入する

## Context

グローバル `CLAUDE.md` の `<avoid_overengineering>` は YAGNI の規範を常時ロードされる短い箇条書きで示すが、7段階の ladder 強制、root-cause 修正、`ponytail:` マーカーによる意図的簡略化の追跡、非自明なロジックへの最小限テスト添付といった運用的な仕組みは持たない。Claude Code のコミュニティ plugin `ponytail`（dietrichgebert/ponytail, MIT, v4.9.0）はこれらを SessionStart/SubagentStart hook で毎ターン注入する。詳細は [Issue #304](https://github.com/treflebonbon/dotfiles/issues/304) のスペックを参照。

## Decision

`private_dot_claude/settings.json.tmpl` の `enabledPlugins` に `ponytail@ponytail` を、`extraKnownMarketplaces` に `ponytail`（`github:dietrichgebert/ponytail`）を追加し、既存の `codex@openai-codex` と同じ配備パターン（`chezmoi apply` のみで完結）で home-wide に有効化する。

- mode はアップストリーム既定の `full` のまま `PONYTAIL_DEFAULT_MODE` の override を追加しない。`lite` は「User picks」に倒れ `<default_to_action>`（常に実装し、止まらない）と衝突し、`ultra` は要求そのものへの挑戦を続けるため tdd / Verification Matrix / to-pr のような本リポジトリの多段階 skill 規約と衝突するリスクが高いと判断した。
- subagent への注入範囲も `PONYTAIL_SUBAGENT_MATCHER` を未設定のままとし、全 subagent（Explore・general-purpose・codex:codex-rescue 等）に一貫して ladder を注入する現行のアップストリーム既定を維持する。
- `enabledPlugins` にはバージョン pin 機構が無い（`apm.yml` のコミット pin と異なる）ことを既知の制約として受け入れる。
- `.chezmoiignore` は変更しない。chezmoi は `~/.claude` 配下で `CLAUDE.md` / `statusline.sh` / `settings.json` の3ファイルのみを管理しており、plugin がランタイムに書く `.ponytail-active` / `.ponytail-statusline-nudged` は管理対象外であり無視される。

## Consequences

ambient persona（`full` mode、毎応答、全リポジトリ、全 subagent）は、このリポジトリ自身が持つ多段階 skill ワークフローに原理的には干渉しうる。ponytail 自身が「明示的に要求されたものは削らない」「ユーザーが求めた説明はそのまま出す」と明記しており、skill 呼出しは明示的な要求に該当するため実害は限定的と判断してこれを受け入れる。実運用で支障が出た場合は `PONYTAIL_SUBAGENT_MATCHER` によるスコープ限定や mode 変更が低コストな follow-up として可能であり、今回の導入のブロッカーではない。

有効化の正しさは [tests/claude-plugins.bats](../../tests/claude-plugins.bats) で検証する。実際のランタイム有効化（`node` hook の実行成否）は `$CLAUDE_CONFIG_DIR/.ponytail-active` フラグファイルの存在で手動確認する。plugin の hook コードは `node`/PATH の失敗を静かに握りつぶすため、これが唯一の観測手段である。あわせて、既存の `~/.claude/statusline.sh` が引き続き機能し、ponytail の statusline セットアップ誘導（`settings.statusLine` が未設定の場合だけ発火する）が発火しないことも手動確認する。

関連: [skill-harness](../../runtime/skill-harness.md) / [Issue #304](https://github.com/treflebonbon/dotfiles/issues/304)
