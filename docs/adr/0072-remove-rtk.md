---
type: decision
title: rtk を撤去する
description: rtk の PreToolUse hook・設定・devshell パッケージを撤去する。token 節約の金額効果が小さい一方、EnterWorktree 隔離との衝突で git 除外の設定を要したため、保守コストが利益を上回ると判断した。
tags: [adr, claude-code, rtk, hooks, nix]
timestamp: 2026-10-08
status: accepted
---

# rtk を撤去する

[ADR-0060](0060-rtk-exclude-git-from-hook.md) は、`rtk hook claude` が Bash コマンドを `rtk git ...` へ書き換えることで `EnterWorktree` の隔離境界チェックが git を検証不能として拒否する問題を、`exclude_commands = ["git"]` で回避した。rtk 自体は残した。

[調査](../research/rtk-removal-evaluation-2026-10-08.md)の結果、次を確認した。

- `rtk gain` では 6411 コマンドで 4.8M token（63.1%）を節約していたが、rtk 自身の `cc-economics` 試算では総支出 $5066 のうち節約は $18（0.4%）だった。
- hook は fail-open で、`rtk verify` は 151/151 PASS。現時点で出力破損は確認していない。
- 一方、hook による書き換えは Claude Code 本体の境界チェック・permission 評価と相互作用し、すでに ADR-0060 の回避設定を要した。同種の衝突は今後も起こりうる。

## Decision

rtk を撤去する。

- `private_dot_claude/settings.json.tmpl` から `rtk hook claude` の PreToolUse hook を削除する。
- `private_dot_config/rtk/config.toml` を削除する。
- `private_dot_config/nix-devshell/modules/ai.nix` から `llm.rtk` を削除する。
- `tests/codex-config.bats` は PreToolUse 全体が `devshell-env claude-hook` 1 件であることを検証する。
- 現行文書（`README.md`、`runtime/`）から rtk の記述を除く。

過去の ADR に残る RTK のバージョン記録は履歴として保持する。ADR-0060 は superseded とする。

## Consequences

- `find` / `grep` / `read` / `diff` / `git` の出力は標準のまま返り、token 圧縮は受けない。代替策は導入しない。
- `EnterWorktree` 隔離と rtk の衝突要因が無くなり、ADR-0060 の除外設定は不要になる。
- 配備後の手動掃除が必要（chezmoi は削除しない）:
  - 古い rtk hook が動くセッションを終了してから `chezmoi apply` する。
  - `~/.config/rtk` を削除する。
  - `~/.local/share/rtk`（履歴 DB）は退避してから削除する。
  - Git 管理外の `.claude/settings.local.json` にある `Bash(rtk git *)` / `Bash(rtk grep *)` を削除する。
