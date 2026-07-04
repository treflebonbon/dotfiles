---
type: decision
title: ORCA Agent IDE の skill (stablyai/orca) を npx skills add ではなく apm 管理で導入する
description: ORCA Agent IDE をメイン利用するにあたり、公式手順の npx skills add で手動インストール済みだった orca-cli / orchestration / computer-use を apm.yml 管理へ移行する。npx skills 由来の配備は orphan-cleanup と衝突して次回 chezmoi apply で壊れる構造だった。upstream 8 skill のうち実際に使う 3 skill のみ導入する
tags: [adr, skills, orca, apm]
timestamp: 2026-07-04
---

# ORCA Agent IDE の skill (stablyai/orca) を npx skills add ではなく apm 管理で導入する

## Status

Accepted (2026-07-04)

## Context

ORCA Agent IDE をメイン IDE として利用するため、[公式ドキュメント](https://www.onorca.dev/docs/cli/skills)の手順（`npx skills add https://github.com/stablyai/orca --skill <name>`、Vercel skills CLI）で `orca-cli` / `orchestration` / `computer-use` を手動インストールした状態だった（2026-07-04 05:30 UTC、`~/.agents/.skill-lock.json` に記録）。しかしこの配備形態はこの dotfiles の skill 管理機構と 2 点で衝突する:

1. **orphan-cleanup による破壊**: skills CLI は `~/.agents/skills/` に real dir を置き `~/.claude/skills/` に `../../.agents/skills/<name>` 形式の symlink を張るが、`run_onchange_before_remove-orphan-claude-skills.sh.tmpl` の `cleanup_symlinks` はまさにこのパターンの symlink を除去対象としている（旧 ai.nix 残骸対策）。次に orphan-cleanup が発火する `chezmoi apply` で Claude Code から不可視になる。
2. **二重管理**: apm と skills CLI が同じ共有ハブ `~/.agents/skills/` に書き込むため、両方に管理させると `skills update` 等で apm 管理 dir が上書きされ drift する。

`stablyai/orca` は public repo で `skills/<name>/SKILL.md` 構造を持ち、既存依存と同じ `owner/repo/path` 形式で apm から直接解決できる。upstream には 8 skill が存在する: `orca-cli` / `orchestration` / `computer-use` / `orca-linear` / `linear-tickets` / `orca-emulator` (iOS) / `orca-emulator-android` / `orca-per-workspace-env`。

なお `orca` CLI バイナリ自体は Orca アプリが自身の terminal に注入する（production は `/usr/local/bin` の shim、dev build は `orca-dev`）ため、nix devshell 等 dotfiles 側での配線は不要かつ不可能。skill は CLI のドキュメント層のみを担う。

## Decision

- `apm.yml` に `stablyai/orca/skills/{orca-cli,orchestration,computer-use}` の 3 件を追加し、apm を唯一の管理元とする。skills CLI（`npx skills add`）は今後使わない。
- `~/.agents/.skill-lock.json` から該当 3 skill のエントリを除去し、npx 由来の配備実体（`~/.agents/skills/` の real dir と `~/.claude/skills/` の symlink）は撤去して apm の配備に置き換える。orphan-cleanup / apm.yml 側の特別扱い（preserve 追加等）は行わない — apm 管理化により既存機構がそのまま正しく働く。
- 導入は実際に使う 3 skill のみとする。`orca-linear` / `linear-tickets` は Linear 非利用、`orca-emulator` / `orca-emulator-android` はモバイル開発をこの環境で行わないため非導入。`orca-per-workspace-env` も現時点で用途がないため非導入。利用が始まった時点で追加を再検討する。
- skill docs と Orca アプリ（CLI）のバージョン同期は、Orca アプリ更新時に手動で `cd ~ && apm update`（または lock 再生成）して追従する。CI/renovate による自動更新は導入しない（既存 apm 依存と同じ運用）。
- worktree 運用の使い分けを明文化する: Orca セッション内（`orca` CLI、Linux では `orca-ide` が利用可能な時）は Orca worktree（`orca-cli` skill）を優先し、それ以外の環境では従来通り `/to-worktree` を使う（CLAUDE.md / AGENTS.md に追記）。

## Consequences

- `orca-cli` / `orchestration` / `computer-use` は apm 経由で `~/.agents/skills/`（共有ハブ）と `~/.claude/skills/` に real dir として配備され、chezmoi apply / orphan-cleanup と共存できる状態になった。
- Codex / Antigravity は共有ハブを直接読むため追加配線なしで同じ skill が可視。
- ORCA 公式手順（npx skills add）とは意図的に乖離する。将来 upstream の skill 追加・改名があった場合は `stablyai/orca` の skills/ 一覧と apm.yml を突き合わせて再棚卸しする（ADR-0010 の mattpocock 棚卸しと同型）。

関連: [ADR-0010](0010-productivity-skill-audit.md) / [skill-harness](../../runtime/skill-harness.md)
