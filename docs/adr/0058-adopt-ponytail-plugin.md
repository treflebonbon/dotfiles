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

## 2026-09-11 amendment: Codex への拡張

[Issue #308](https://github.com/treflebonbon/dotfiles/issues/308) により、ponytail を Codex にも導入する。ponytail は Codex 向けにも `.codex-plugin/plugin.json` + 共有 `hooks/claude-codex-hooks.json` による正式な native plugin adapter を提供しており、apm ではなく Codex 自身の native plugin 機構（`codex plugin marketplace add` / `codex plugin add`）を使う。Claude Code 版と同じ「native plugin 機構で配線する」という判断を Codex にも一貫して適用する（apm を使わない正確な理由は後述の訂正 amendment を参照）。

- marketplace `dietrichgebert/ponytail` を `v4.9.0` に明示 pin して登録する（`--ref` は実際に該当タグへ確定 pin することを実機確認済み）。Claude Code 側の `enabledPlugins` にはこの pin 機構が無いため、Codex 側の方がより厳格な固定になる。
- `private_dot_config/codex/config.toml.tmpl` の `[plugins]` に `"ponytail@ponytail" = { enabled = true }` を追加し、既存の `github@openai-curated` / `chrome@openai-bundled` と同じ宣言パターンで有効化する。
- marketplace 登録・plugin install という命令的な新規ステップは、既存の `sync-codex-managed-config`（`codex_home` 列挙・`run_onchange` トリガーを既に持つ）を拡張して行う。新規スクリプトは作らない。
- marketplace 登録・install は `codex` バイナリが `PATH` に無い場合、および対象 `codex_home` の既存設定が `codex` 自身のロードに失敗する場合（無関係な理由によるものを含む）に fail-open とする。ファイルの静的マージ（既存の責務）を、この新規の命令的ステップの失敗で巻き込まないためである。
- mode（`full`、override なし）・subagent スコープ（`PONYTAIL_SUBAGENT_MATCHER` 未設定）・導入スキル（6つ全て）は Claude Code 版と同じ判断を踏襲する。

検証は `tests/codex-config.bats` を拡張して行う（新規ファイルは作らない）。ローカル git fixture を marketplace source として使い、実ネットワークで `dietrichgebert/ponytail` を毎回取得しない。

## 2026-09-11 amendment: apm を使わない理由の訂正

上記 Codex amendment は当初「apm.yml（hooks を持たない外部 skill-only の経路）ではなく」という理由づけで native plugin 機構を選んだと記していたが、apm CLI (v0.30.0) のソースと Codex CLI の実バイナリを調査した結果、この理由づけが不正確だったため訂正する（上記本文はすでに訂正済み）。Decision（apm ではなく `config.toml` の `[plugins]` を直接配線する）自体は変更しない。

- apm は一般論としては hooks を含む executable primitives（hooks/MCP/LSP/bin/canvas）を `apm approve`/`apm deny` で明示的に承認管理できる汎用機構を持ち、`apm_cli/integration/hook_integrator.py` には Claude（`.claude/settings.json`）・Codex（`.codex/hooks.json`）・Cursor（`.cursor/hooks.json`）向けの汎用 hook マージ実装が実在する。Codex 自身にも `.codex/hooks.json` を読む本物の hooks エンジンが存在し、本リポジトリの `private_dot_config/codex/hooks.json`（devshell-env / impeccable / rtk の hook、Claude の `settings.json.tmpl` の hooks 相当）が実際にこの経路で動いていることを `~/.codex/config.toml` の `[hooks.state]` の trusted_hash で確認した。つまり「apm = hooks を持たない経路」という一般化はそもそも誤りで、apm 自身の汎用マージ primitive を使ってフックの中身を Codex に流し込むこと自体は技術的には可能。
- 一方 ponytail の Codex 側 hooks は、この生 `.codex/hooks.json` 経路ではなく、plugin バンドル内の相対パス hooks（`hooks/claude-codex-hooks.json`）であり、`codex plugin marketplace add` / `codex plugin add` で登録した plugin としてのみロードされる別経路である。`codex plugin list --json` で `ponytail@ponytail` が marketplace `ponytail` から `installed, enabled` (v4.9.0) であること、`[hooks.state]` に `ponytail@ponytail:hooks/claude-codex-hooks.json:...` の trusted_hash が別途記録されていることを確認しており、この plugin 経由の hooks は実際に機能している。
- apm のソースを検索した範囲では、GitHub Copilot 向け native plugin marketplace registrar（`copilot_plugins/registrar.py`）に相当する Codex 版は見つからず、`codex plugin marketplace add` / `codex plugin add` を呼び出すコードも見つからなかった。つまり apm は ponytail が実際に使っている「plugin バンドルとして登録し、バンドル内 hooks をロードさせる」経路を再現できない。
- 正確な理由は「apm は hooks を扱えないから」ではなく「apm に Codex native plugin marketplace registrar が無く、ponytail 公式が提供する `.codex-plugin/plugin.json` 経由の配布・pin（v4.9.0）を再現できないから」である。apm 自身の汎用 `.codex/hooks.json` マージ primitive でフックの中身だけを生ファイルとして流し込む代替経路は技術的にはあり得るが、vendor 提供の pin 済み plugin bundle（v4.9.0）を使わない独自再実装になるため採用しない。
