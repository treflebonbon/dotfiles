---
type: decision
title: runtime-owned Worktree Entry Point と Codex Worktree Activation を採用する
description: worktree の作成・選択を各 runtime に委ね、Codex は current linked worktree の Git metadata だけを動的に許可して起動する
tags: [adr, codex, orca, claude-code, git, worktree, sandbox, skills]
timestamp: 2026-08-25
status: accepted
---

# runtime-owned Worktree Entry Point と Codex Worktree Activation を採用する

## Context

linked worktree の worktree 固有 Git dir と Git common dir は checkout 外にあるため、Codex の通常 workspace permission だけでは `git add`、`git commit`、`git-push-topic` が完結しない。一方、従来の managed config は dotfiles source repository の common dir を静的に writable とし、`codex-orca` は non-Git directory でも Codex を起動していた。この配線は current task と無関係な Git metadata authority を常設し、worktree の作成、session entry、technical sandbox activation の責務も混同していた（[調査ノート](../research/codex-worktree-git-write-boundary-2026-08-25.md)）。

## Decision

`to-worktree` を全 runtime 共通の **Worktree Entry Point** とし、worktree の作成・選択は **Worktree Owner** に委ねる。

- current checkout が linked worktree なら冪等に検証してその場で再利用する。再利用できるのは current checkout だけで、same-topic worktree が別 path にあれば conflict として停止する。
- Orca は current Orca worktree を使う。新規作成時は `orca-cli` skill が実行時に取得する version-matched guide に従って native create / full handoff を行い、handoff 成功後に元セッションを停止する。具体 CLI は本 decision や `to-worktree` に固定しない。Codex Desktop は native worktree、Claude Code は `EnterWorktree` を使う。
- raw Codex CLI だけは、caller `HEAD` を起点とする `git worktree add` 一回へ scoped approval を求める。parent の tracked / staged / untracked change は全て残し、fetch は行わない。作成後は current session で作業を続けず、new worktree を root とする fresh session のため停止する。

raw Codex / Orca の **Worktree Activation** には canonical **Runtime Adapter** `codex-worktree` を使う。adapter は inherited `GIT_*` environment を除去してから current physical worktree root、absolute worktree Git dir、absolute Git common dir を解決し、次を全て満たす linked worktree だけを受理する。

- current context が Git worktree として解決できる。
- top-level `.git` が linked-worktree pointer file である。
- worktree Git dir と Git common dir が存在し、異なる absolute physical path に解決できる。

受理後は Codex 公式 CLI の `-C` で worktree root を固定し、`-c 'default_permissions="dotfiles-secure"'` で profile 選択を session flag に固定してから、別の `-c` でその Git dir と common dir の exact absolute path だけを filesystem write に加える。ambient `CODEX_PERMISSION_PROFILE` は enforcement の根拠にせず除去する。Codex CLI 0.149.0 の top-level agent launch は `-P` を受理せず、`-P dotfiles-secure` は `codex sandbox` subcommand の直接検証に使う interface なので、agent launch では同じ profile を選択する公式 `default_permissions` config override を使う。`codex-orca` は引数を変更せず `codex-worktree` へ転送する thin compatibility entry とする。

managed `dotfiles-secure` profile は workspace write、protected-path deny、network policy を保持するが、workspace-relative `.git` write と dotfiles common dir の static write exception は持たない。Active Git Metadata Boundary は session 起動時にだけ materialize する。

## Boundaries

- Runtime Adapter は metadata の read-only discovery と Codex process launch だけを所有する。worktree create、branch naming、fetch、add、commit、push、PR、workflow policy は所有しない。
- Runtime Adapter が固定する working root / permission profile を置換・拡張する argument と、sandbox / hook trust を迂回する dangerous argument は起動前に拒否する。`codex-orca` は argv を欠落させず adapter へ渡すが、adapter の technical boundary validation は迂回しない。
- primary checkout、non-Git directory、unresolved metadata は Codex を起動せず fail closed にする。full sandbox bypass、parent/common directory の包括許可、routine manual-shell Git へ fallback しない。
- Worktree Activation 後の `git add`、`git commit`、`git-push-topic`、`to-pr` は同じ narrow sandbox 内で実行する。common dir は repository 内の objects / refs / config を共有する Git の構造上必要だが、別 repository の Git metadata は許可しない。

## Verification Matrix

| Contract                                                        | Public seam                                                                                                   |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| linked worktree の working root と Active Git Metadata Boundary | `codex-worktree` が Codex へ渡す fixed profile / `-C` / exact `-c`、ambient profile 除去、sandboxed Git write |
| invalid context の fail-closed                                  | primary checkout / non-Git / unresolved metadata で Codex stub が未起動                                       |
| Orca compatibility                                              | `codex-orca` の全 argv forwarding                                                                             |
| managed profile の静的例外撤去と deny 維持                      | chezmoi rendered config                                                                                       |
| runtime routing                                                 | `to-worktree`、`AGENTS.md`、`CLAUDE.md` の workflow contract tests                                            |

## Consequences

worktree isolation と technical sandbox を同一視せず、各 runtime の native ownership を維持したまま raw Codex / Orca だけに portable な narrow activation を与えられる。新規 raw CLI worktree は fresh session を一回必要とするが、session 中の権限拡大や primary checkout の変更を workflow の通常経路にしない。

関連: [CONTEXT.md](../../CONTEXT.md) / [skill-harness](../../runtime/skill-harness.md) / [to-worktree](../../local-skills/to-worktree/SKILL.md) / [OpenAI Permissions](https://learn.chatgpt.com/docs/permissions) / [OpenAI Developer commands](https://learn.chatgpt.com/docs/developer-commands?surface=cli)
