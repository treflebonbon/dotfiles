---
type: decision
title: rtk の PreToolUse hook から git を除外し、EnterWorktree 隔離中の git 封鎖を解消する
description: rtk hook claude が git コマンドを自動的に rtk 経由へ書き換えるため、Claude Code の worktree 隔離境界チェックが launcher (rtk) を透過できず git status のような read-only コマンドまで一律拒否していた。rtk config で git を書き換え対象から除外する。
tags: [adr, claude-code, rtk, worktree, git]
timestamp: 2026-09-15
status: accepted
---

# rtk の PreToolUse hook から git を除外し、EnterWorktree 隔離中の git 封鎖を解消する

`EnterWorktree`（Claude Code 2.1.270）で隔離した task worktree 内では、`git status` のような最も単純な read-only コマンドすら次のエラーで一律拒否されることを `diagnosing-bugs` で確認した:「this command runs rtk with a git command among its operands: ... so what it runs cannot be shown not to be git」。`dangerouslyDisableSandbox: true` の有無やコマンドの単純さに関わらず再現し、`EnterWorktree` を使わないセッションでは発生しなかった。

原因は次の連鎖として実機で確認済み:

1. `private_dot_claude/settings.json.tmpl`（初期セットアップ commit `4c91e11` から存在）が配備する `~/.claude/settings.json` の `PreToolUse` hook `rtk hook claude` は、Bash tool 呼び出し全件にマッチする。
2. `rtk hook claude` に Claude Code の PreToolUse payload（`{"tool_input":{"command":"git status"}}`）を模擬入力すると、`updatedInput.command` が `"rtk git status"` に自動書き換えされることを stdin シミュレーションで実測した。rtk はデフォルト設定で `git` サブコマンドを常時この書き換え対象にする（`rtk --help` の `git` サブコマンド: "Git commands with compact output"）。
3. Claude Code 本体の `EnterWorktree` 隔離境界チェックは、実行直前のコマンド文字列を静的解析して「git 操作が自分の worktree に収まっているか」を検証するが、`rtk` という launcher を透過できず、`git` が rtk のオペランドとして埋もれた形だと安全性を判定不能として fail-closed する。
4. 傍証: 隔離していない状態で `git status` を実行すると、標準の git 出力ではなく rtk の圧縮フォーマット（`* branch` / `clean — nothing to commit`）が返る（hook が常時書き換えている直接証拠）。git を絶対パス（`/nix/store/.../bin/git`）で実行すると rtk の書き換えパターンに一致せず素通りし、隔離中でも標準出力で成功する。

## Decision

`private_dot_config/rtk/config.toml` を新設し、`[hooks] exclude_commands = ["git"]` を設定する。これにより `rtk hook claude` は `git` コマンドを書き換えなくなり（`XDG_CONFIG_HOME` を差し替えた隔離環境での stdin シミュレーションで、この設定下では `updatedInput` が返らない＝無書き換えになることを確認済み）、`EnterWorktree` 隔離中も素の `git` コマンドとして Claude Code 本体の境界チェックを通過できる。

隔離状態を含む live home への反映後の最終的な動作確認（実際の `EnterWorktree` セッションで `git status` が通ること）は、この ADR の時点では未実施（validated task worktree からの source 変更であり、live source での `chezmoi apply` は受入後に行う運用のため）。次回 `chezmoi apply` 後に確認する。

## Considered Options

- **絶対パスで git を実行する回避策のみで済ませる**: 都度 `command -v git` 相当を書く運用は現実的でない上、`$(...)` を挟むと今度は「複雑すぎて検証不能」として別途拒否される（実測済み）。また絶対パス実行は隔離の境界チェック自体も一緒に回避してしまうため、安全側の回避策として恒常的に使うのは望ましくない。見送った。
- **rtk の `transparent_prefixes` 設定を使う**: `rtk config` のスキーマに存在するが、これは rtk 自身がユーザー入力コマンドの launcher prefix（`env`/`sudo` 等）を認識するためのものであり、Claude Code 側が rtk 自体を launcher として認識できない今回の問題には効かないと判断した（設定の説明からの推測であり、実機検証はしていない）。
- **`rtk hook claude` PreToolUse hook 自体を撤去する**: 根本原因を最も広く消せるが、find/grep/diff 等 git 以外のコマンドで得ている token 節約効果まで失う。今回の症状は git に限定されるため過剰な対応として見送った。
- **Claude Code のバージョンアップを待つ**: 境界チェックの launcher 認識に rtk のような外部 launcher を追加する変更が将来入る可能性はあるが、closed-source で見込みが立たず、現行バージョン（2.1.270）でも未対応と確認済みのため待たない。

## Consequences

`git` コマンドの出力は rtk による token 圧縮（`* branch` / `clean —` 形式の compact status など）を受けなくなり、常に標準の git 出力になる。`rtk gain` / `cc-economics` 等の節約計測から git 分の寄与が減る。find/grep/diff など git 以外のコマンドの rtk 書き換えは変更しない。

将来 Claude Code 側の隔離境界チェックが rtk のような launcher を透過できるようになれば、この除外設定は不要になる可能性がある。
