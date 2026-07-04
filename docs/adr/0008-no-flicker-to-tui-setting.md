---
type: decision
title: CLAUDE_CODE_NO_FLICKER は維持、矢印キーバグの原因究明は保留
description: Windows Terminal + WSL2 でのフォーカス/矢印キー問題を機に CLAUDE_CODE_NO_FLICKER の実体をバイナリ解析。tui:fullscreen への移行を試みたが、tmux -CC/Windows-over-SSH では判定順序の違いにより挙動が変わる(PRレビューで指摘)と判明し撤回。バグ自体の根治は設定変更では困難なため保留する
tags: [adr, claude-code, tui, windows-terminal]
timestamp: 2026-07-04
---

# CLAUDE_CODE_NO_FLICKER は維持、矢印キーバグの原因究明は保留

## Status

Accepted (2026-07-04)。2026-07-04 に PR #9 のレビュー（Codex）指摘を受け、当初の Decision（`tui: fullscreen` への移行）を撤回し訂正。

## Context

[ADR-0005](0005-advisor-tool-default-enable.md) は `CLAUDE_CODE_NO_FLICKER` を含む undocumented env var 3 種を「ADR も rationale コメントも無い」まま挙げていた。Windows Terminal + WSL2 環境で発生している「AskUserQuestion 系の選択メニューが、ウィンドウのフォーカスアウト→イン直後に矢印キーで選択不能になる（Enter は効く）」という不具合をきっかけに、この env var を外すべきかを検証した。

claude-code 2.1.200 バイナリ（`.claude-wrapped`）の `strings` 解析と実行環境の実測により、以下が判明した。

- `CLAUDE_CODE_NO_FLICKER=1` は fullscreen（alt-screen + virtualized scrollback）レンダラーを強制 ON にするフラグ。同じ機能が settings スキーマ上に `"tui": "fullscreen" | "default"` として既にドキュメント化されており、"fullscreen" は "equivalent to CLAUDE_CODE_NO_FLICKER=1" と明記されている。
- fullscreen の ON/OFF 判定順序: スクリーンリーダー検出 → 明示的 OFF（`NO_FLICKER=0` or `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN`） → `NO_FLICKER=1`（強制 ON、以降の自動判定を全てバイパス） → tmux -CC（iTerm2 統合モード）検出で自動 OFF → Windows ネイティブ + SSH 接続（ConPTY）検出で自動 OFF → `tui` 設定 → 未設定ならデフォルト ON。
- `WT_SESSION` は `WSLENV=WT_SESSION:WT_PROFILE_ID:` により Windows Terminal から WSL2 側へ伝播することを実測で確認した。この環境は上記の自動 OFF 条件（tmux -CC／Windows ネイティブ+SSH）のいずれにも該当しないため、`NO_FLICKER` を外しても fullscreen はデフォルトで ON のまま変わらない。すなわち現状このフラグはほぼ no-op。
- fullscreen（alt-screen）への遷移時は DECSET 1004（フォーカスイベント通知）を明示的に無効化 (`\x1B[?1004l`) し、default（classic）への遷移時は逆に有効化 (`\x1B[?1004h`) する。今回のバグがフォーカスイベント絡みだとすると、`NO_FLICKER` を外して default へ切り替える対処は根治どころか、無効化されていたフォーカスイベント通知を有効化し別の不具合を誘発しうる。
- `WT_SESSION` 検出時は `NO_FLICKER` の値に関わらず `CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT=1` が自動設定され、カーソル描画がターミナルのネイティブカーソルではなく合成カーソルに切り替わる（ConPTY の部分再描画バグへの既知の回避策と見られる）。

以上より、当初の問い「`CLAUDE_CODE_NO_FLICKER` を外すべきか」への答えは、少なくとも今回報告されたバグに対しては **No**（外しても挙動は変わらない可能性が高い）である。

**訂正（PR #9 の Codex レビューで指摘）**: 上記の判定順序が示す通り、`CLAUDE_CODE_NO_FLICKER=1` は `Gno()`（Windows ネイティブ+SSH 検出）と `Jre()`（tmux -CC 検出）の**手前**で評価され真なら即座に fullscreen を強制するのに対し、`tui: "fullscreen"` は switch 文の中、すなわち `Gno()`/`Jre()` の**後**でしか参照されない。そのため tmux -CC や Windows ネイティブ+SSH 環境では、`NO_FLICKER=1` はそれらの自動 OFF を上書きして fullscreen を強制できるが、`tui: "fullscreen"` はできず classic レンダラーへ黙って fallback する。upstream の設定スキーマ説明文（"equivalent to CLAUDE_CODE_NO_FLICKER=1"）はこの評価順序の違いを説明しておらず、額面通り読むと誤誘導になる。`private_dot_claude/settings.json.tmpl` は chezmoi で home-wide に配備される共有設定であり、tmux -CC や Windows ネイティブ+SSH で使われる devcontainer が将来出てこないとは言い切れないため、「今回の WSL2 環境では no-op」という調査結果だけを根拠に全環境向け設定を書き換えるべきではなかった。

## Decision

- `private_dot_claude/settings.json.tmpl` の `env.CLAUDE_CODE_NO_FLICKER: "1"` は変更せず維持する。`tui: "fullscreen"` への置き換えは撤回した。
- 矢印キー/フォーカスの不具合自体の原因究明と対応は保留する。設定変更（`NO_FLICKER` の有無、`tui` の値）では直せない可能性が高いと判明したため。再検討する際は、本 ADR の調査結果を起点に、Ink 側の内部フォーカス管理（`useFocus` / `useHasFocus`）や ConPTY 側の focus-report ハンドリングを疑うこと。

## Consequences

- 挙動は変更前と一切変わらない。
- ADR-0005 が指摘した「undocumented env var の将来的な名前/挙動変更リスク」は本 ADR では解消されず残る。tmux -CC / Windows ネイティブ+SSH 環境を上書きする能力を保つには undocumented env var への依存が必要、という trade-off がある以上、documented 設定への安易な置き換えは避けるべきという教訓として記録する。
- 矢印キー/フォーカスのバグは未解決のまま残る。再発した場合は upstream（anthropics/claude-code）の GitHub issue を確認・報告することを検討する。
- 「一部の環境（自分の手元）で挙動が変わらない」ことと「全ての環境で挙動が変わらない」ことを混同しない。共有 infra の設定を扱う際は、コードが分岐する条件を全て列挙し、それぞれで比較すること。

関連: [ADR-0005](0005-advisor-tool-default-enable.md)
