---
type: decision
title: CLAUDE_CODE_NO_FLICKER を tui:fullscreen へ移行、矢印キーバグの原因究明は保留
description: Windows Terminal + WSL2 でのフォーカス/矢印キー問題を機に CLAUDE_CODE_NO_FLICKER の実体をバイナリ解析し、undocumented env var をドキュメント化済みの tui 設定へ移行する。バグ自体の根治は設定変更では困難と判明したため保留する
tags: [adr, claude-code, tui, windows-terminal]
timestamp: 2026-07-04
---

# CLAUDE_CODE_NO_FLICKER を tui:fullscreen へ移行、矢印キーバグの原因究明は保留

## Status

Accepted (2026-07-04)

## Context

[ADR-0005](0005-advisor-tool-default-enable.md) は `CLAUDE_CODE_NO_FLICKER` を含む undocumented env var 3 種を「ADR も rationale コメントも無い」まま挙げていた。Windows Terminal + WSL2 環境で発生している「AskUserQuestion 系の選択メニューが、ウィンドウのフォーカスアウト→イン直後に矢印キーで選択不能になる（Enter は効く）」という不具合をきっかけに、この env var を外すべきかを検証した。

claude-code 2.1.200 バイナリ（`.claude-wrapped`）の `strings` 解析と実行環境の実測により、以下が判明した。

- `CLAUDE_CODE_NO_FLICKER=1` は fullscreen（alt-screen + virtualized scrollback）レンダラーを強制 ON にするフラグ。同じ機能が settings スキーマ上に `"tui": "fullscreen" | "default"` として既にドキュメント化されており、"fullscreen" は "equivalent to CLAUDE_CODE_NO_FLICKER=1" と明記されている。
- fullscreen の ON/OFF 判定順序: スクリーンリーダー検出 → 明示的 OFF（`NO_FLICKER=0` or `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN`） → `NO_FLICKER=1`（強制 ON、以降の自動判定を全てバイパス） → tmux -CC（iTerm2 統合モード）検出で自動 OFF → Windows ネイティブ + SSH 接続（ConPTY）検出で自動 OFF → `tui` 設定 → 未設定ならデフォルト ON。
- `WT_SESSION` は `WSLENV=WT_SESSION:WT_PROFILE_ID:` により Windows Terminal から WSL2 側へ伝播することを実測で確認した。この環境は上記の自動 OFF 条件（tmux -CC／Windows ネイティブ+SSH）のいずれにも該当しないため、`NO_FLICKER` を外しても fullscreen はデフォルトで ON のまま変わらない。すなわち現状このフラグはほぼ no-op。
- fullscreen（alt-screen）への遷移時は DECSET 1004（フォーカスイベント通知）を明示的に無効化 (`\x1B[?1004l`) し、default（classic）への遷移時は逆に有効化 (`\x1B[?1004h`) する。今回のバグがフォーカスイベント絡みだとすると、`NO_FLICKER` を外して default へ切り替える対処は根治どころか、無効化されていたフォーカスイベント通知を有効化し別の不具合を誘発しうる。
- `WT_SESSION` 検出時は `NO_FLICKER` の値に関わらず `CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT=1` が自動設定され、カーソル描画がターミナルのネイティブカーソルではなく合成カーソルに切り替わる（ConPTY の部分再描画バグへの既知の回避策と見られる）。

以上より、当初の問い「`CLAUDE_CODE_NO_FLICKER` を外すべきか」への答えは、少なくとも今回報告されたバグに対しては **No**（外しても挙動は変わらない可能性が高い）である。一方 ADR-0005 が指摘していた「undocumented env var の将来的な名前/挙動変更リスク」は、機能的に同一でドキュメント化済みの `tui` 設定へ置き換えることで無条件に（挙動を変えずに）解消できる。

## Decision

- `private_dot_claude/settings.json.tmpl` の `env.CLAUDE_CODE_NO_FLICKER` を削除し、代わりにトップレベルの `"tui": "fullscreen"` を追加する。挙動は完全に同一であり、undocumented env var への依存を断つことのみが目的。
- 矢印キー/フォーカスの不具合自体の原因究明と対応は保留する。設定変更（`NO_FLICKER` の有無、`tui` の値）では直せない可能性が高いと判明したため。再検討する際は、本 ADR の調査結果を起点に、Ink 側の内部フォーカス管理（`useFocus` / `useHasFocus`）や ConPTY 側の focus-report ハンドリングを疑うこと。

## Consequences

- 実際の挙動は一切変わらないため regression リスクはゼロ。
- ADR-0005 が指摘した undocumented env var の将来リスクは、このフラグに関しては解消される。残る2種（`ENABLE_TOOL_SEARCH` / `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`）は本 ADR の対象外のまま。
- 矢印キー/フォーカスのバグは未解決のまま残る。再発した場合は upstream（anthropics/claude-code）の GitHub issue を確認・報告することを検討する。

関連: [ADR-0005](0005-advisor-tool-default-enable.md)
