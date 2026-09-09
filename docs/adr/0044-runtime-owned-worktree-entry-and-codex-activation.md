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
- raw Codex CLI だけは、caller `HEAD` を起点とし、repository の absolute physical top level を `git -C` と absolute destination の両方に使う `git worktree add` 一回へ scoped approval を求める。parent の tracked / staged / untracked change は全て残し、fetch は行わない。作成後は current session で作業を続けず、new worktree を root とする fresh session のため停止する。

raw Codex / Orca の **Worktree Activation** には canonical **Runtime Adapter** `codex-worktree` を使う。adapter は inherited `GIT_*` environment を除去してから current physical worktree root、absolute worktree Git dir、absolute Git common dir を解決し、次を全て満たす linked worktree だけを受理する。

- current context が Git worktree として解決できる。
- top-level `.git` が linked-worktree pointer file である。
- worktree Git dir と Git common dir が存在し、異なる absolute physical path に解決できる。
- `.git` pointer が worktree Git dir、worktree Git dir の `commondir` が Git common dir、worktree Git dir が common dir 直下の `worktrees/<entry>`、worktree Git dir の `gitdir` back-pointer が top-level `.git` を指す同一の ownership chain である。各 metadata file からの relative target は受理し、全 target を physical path に解決して比較する。

受理後は Codex 公式 CLI の `-C` で worktree root を固定し、`-c 'default_permissions="dotfiles-secure"'` で profile 選択を session flag に固定してから、別の `-c` でその Git dir と common dir の exact absolute path だけを filesystem write に加える。ambient `CODEX_PERMISSION_PROFILE` は enforcement の根拠にせず除去する。Codex CLI 0.149.0 の top-level agent launch は `-P` を受理せず、`-P dotfiles-secure` は `codex sandbox` subcommand の直接検証に使う interface なので、agent launch では同じ profile を選択する公式 `default_permissions` config override を使う。`codex-orca` は引数を変更せず `codex-worktree` へ転送する thin compatibility entry とする。

managed `dotfiles-secure` profile は workspace write、protected-path deny、network policy を保持するが、workspace-relative `.git` write と dotfiles common dir の static write exception は持たない。Active Git Metadata Boundary は session 起動時にだけ materialize する。

配備時の `sync-codex-managed-config` は、既存の managed profile に残る旧 absolute `…/.git = "write"` と `:workspace_roots` 内の `".git" = "write"` を managed migration として除去する。Codex が自己展開した concrete map は、absolute root と managed `:workspace_roots` の `"."` mode が一致するものだけを除去する。managed profile 内の独立した nested deny、`:minimal` など他の scalar baseline、dotfiles が所有しない user-defined profile の path rule は保持する。この migration は native Codex home と明示された `CODEX_HOME` の双方へ適用する。

## Boundaries

- Runtime Adapter は metadata の read-only discovery と Codex process launch だけを所有する。worktree create、branch naming、fetch、add、commit、push、PR、workflow policy は所有しない。
- Runtime Adapter が固定する working root / permission profile を置換・拡張する argument と、sandbox / hook trust を迂回する dangerous argument は起動前に拒否する。`codex-orca` は argv を欠落させず adapter へ渡すが、adapter の technical boundary validation は迂回しない。
- primary checkout、non-Git directory、unresolved metadata は Codex を起動せず fail closed にする。full sandbox bypass、parent/common directory の包括許可、routine manual-shell Git へ fallback しない。
- Worktree Activation 後の `git add`、`git commit`、`git-push-topic`、`to-pr` は同じ narrow sandbox 内で実行する。common dir は repository 内の objects / refs / config を共有する Git の構造上必要だが、別 repository の Git metadata は許可しない。

## 2026-09-09 amendment: 信頼済み devShell の準備

[Issue #255](https://github.com/treflebonbon/dotfiles/issues/255) の決定に従い、raw Codex の Runtime Adapter は上記の read-only discovery と process launch に加えて、検証済み root の信頼済み devShell を起動前に準備する。これは「metadata の read-only discovery と Codex process launch だけを所有する」という境界の限定的な拡張である。Orca native Codex の所有権は [ADR-0046](0046-separate-orca-native-worktree-entry.md) のまま維持する。

repo の信頼登録・解除による永続書込みは、利用者が明示実行する `devshell-env trust/untrust` が所有する。adapter の自動経路は登録を読み、同じ Git common directory に所属することを確認した worktree の flake だけを評価する。信頼にはその repo の worktree と将来の flake／shellHook 変更が含まれるが、agent の filesystem・network permission を広げるものではない。

未登録、flake 不在、Nix／shellHook の準備失敗は理由を通知し、プロジェクト環境を加えず調査用に起動する。不正な起動要求、metadata 不一致、準備後の所属・identity 変更は引き続き Codex 未起動で fail closed にする。起動元から選んだ Codex の実行ファイル、検証済み root と Active Git Metadata Boundary、標準 profile を準備後にも固定する。

新経路は `.envrc`、dotenv、秘密取得と独自の永続プロジェクト環境キャッシュを追加しない。環境準備は Codex sandbox 起動前に行い、flake 更新はセッション再起動で反映する。Git 操作・worktree 作成・workflow policy は引き続き adapter の責務に含めない。実装と検証の正本は [検証記録](../research/devshell-env-255.md) と [利用方法](../../runtime/shell-environment.md#raw-codex-のプロジェクト開発環境) を参照。

## 2026-09-09 amendment: 指定コマンドの dotenv と外側の読取り境界

[Issue #257](https://github.com/treflebonbon/dotfiles/issues/257) の root `.env` 読取りを成立させるため、利用者の承認を受けて worktree 外の読取りを含む標準 profile を見直した。workspace 内だけの秘密拒否では外の repo を保護できず、sandbox 内の Nix daemon 接続も成立しなかったため、`dotfiles-secure` は `:workspace` 継承を保って外側を既定で拒否し、最小ランタイム・Nix store・Git 用の限定した読取りと専用一時領域を許可する。home の個別 deny は外側の拒否へ統合する。重複した外側 deny は Linux の mount 構築を失敗させるため残さない。

raw adapter は devShell 内に含めた公開 `with-env` package を起動前に準備する。コマンド実行時には root・repo identity・output・flake/lock hash のみの照合情報を使って環境を再利用し、Nix daemon へ接続せず `.env` を子へ注入する。この照合情報は秘密や環境の永続キャッシュではなく、agent に対する認証境界でもない。Nix input の変更はセッション再起動で反映する。

信頼済み準備が成功し root `.env` が通常ファイルのときだけ、その root の読取りを追加する。root と下位 dotenv の拒否規則を分離し、実効 Codex config の profile 継承を解決して追加 workspace root を無効化する。設定読取り失敗は起動を拒否する。Git metadata と dotenv の動的規則は単一 filesystem override として渡し、片方の設定で他方を消さない。移行では管理 profile の旧 `**/.env` と旧 home deny を除去し、user-defined profile は保持する。

root dotenv の書込み、別名・下位・別 repo の秘密、home 保護対象は引き続き拒否する。agent 自身による対象 `.env` の読取りは許可するが、値を AI セッション全体へ自動注入しない。network と引数制限は維持する。実 Nix と実 sandbox による証拠は [#257 検証記録](../research/with-env-257.md)、正式入口と OS 制限は [利用方法](../../runtime/shell-environment.md#指定コマンドへの-dotenv-注入) を参照する。

## Verification Matrix

| Contract                                                        | Public seam                                                                                                      |
| --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| linked worktree の working root と Active Git Metadata Boundary | `codex-worktree` が Codex へ渡す fixed profile / `-C` / exact `-c`、ambient profile 除去、sandboxed Git write    |
| invalid context の fail-closed                                  | primary checkout / non-Git / unresolved・foreign-owned metadata で Codex stub が未起動、relative metadata は起動 |
| Orca compatibility                                              | `codex-orca` の全 argv forwarding                                                                                |
| managed profile の静的例外撤去と deny 維持                      | chezmoi rendered config と native / explicit `CODEX_HOME` の merge migration                                     |
| runtime routing                                                 | `to-worktree`、`AGENTS.md`、`CLAUDE.md` の workflow contract tests                                               |

## Consequences

worktree isolation と technical sandbox を同一視せず、各 runtime の native ownership を維持したまま raw Codex / Orca だけに portable な narrow activation を与えられる。新規 raw CLI worktree は fresh session を一回必要とするが、session 中の権限拡大や primary checkout の変更を workflow の通常経路にしない。

関連: [CONTEXT.md](../../CONTEXT.md) / [skill-harness](../../runtime/skill-harness.md) / [to-worktree](../../local-skills/to-worktree/SKILL.md) / [OpenAI Permissions](https://learn.chatgpt.com/docs/permissions) / [OpenAI Developer commands](https://learn.chatgpt.com/docs/developer-commands?surface=cli)
