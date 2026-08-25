---
type: research
title: Codex / Orca worktree の Git metadata 書込み境界
description: Orca の linked worktree 内で to-pr が .git read-only により失敗する原因と、vendor 既定・最小権限・repo-local workflow の選択肢を一次資料で整理する。
tags: [research, codex, orca, git, worktree, sandbox, pull-request]
timestamp: 2026-08-25
---

# Codex / Orca worktree の Git metadata 書込み境界

> **後続判断（2026-08-25）**: 本ノートは調査時点の選択肢と推奨を記録したものである。同日採択した [ADR-0044](../adr/0044-runtime-owned-worktree-entry-and-codex-activation.md) は、その後の設計判断として runtime-owned Worktree Entry Point と exact Git metadata permission を使う repo-local hybrid を採用した。現在の実装・運用判断は ADR-0044 を正本とし、本ノートの結論と異なる箇所を supersede / 補足する。

## 結論

**「PR 作成だけ人間がシェルで行う」を定常運用にはしない。** それは直ちに作業を進めるための安全な fallback だが、この repo の `to-pr` が持つ「明示呼出しから topic branch の push と PR 作成まで完了する」という contract を途中で切る。

vendor が公開している推奨経路は、実質的に次の二択である。

1. **Orca worktree を継続するなら、Orca の shipped default を使う。** Orca は Codex を `--dangerously-bypass-approvals-and-sandbox` 付きで起動し、「worktree itself is the sandbox」とするのを既定としている。Settings → Agents の Codex launch arguments を **Reset** し、新しい session を起動するのが Orca 公式の経路である。[Orca: Agents & sessions](https://www.onorca.dev/docs/model/agents-sessions) [Orca: Supported agents](https://www.onorca.dev/docs/agents/supported)
2. **Codex 自身の隔離を vendor 管理のまま保ちたいなら、Codex-managed worktree を使う。** OpenAI は managed worktree を branch 化した後、その場で commit、push、GitHub PR 作成まで行える product flow として文書化している。[OpenAI: Worktrees](https://learn.chatgpt.com/docs/environments/git-worktrees)

この二択には security posture の差がある。Git worktree は checkout と branch を分ける Git の機能であり、OS の filesystem / network sandbox ではない。Orca の full-bypass は Git 上の差分を worktree に隔離する運用モデルで、Codex の技術的 sandbox 境界は外す。OpenAI も `--dangerously-bypass-approvals-and-sandbox` を最広権限として注意を求めている。[Git: git-worktree](https://git-scm.com/docs/git-worktree) [OpenAI: Agent approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security#run-without-approval-prompts)

一方、**「Orca が作った任意 repo の linked worktree」「Codex の narrow sandbox」「その repo の外にある Git common dir の自動発見」の三つを同時に満たす vendor 組み込み機能は、確認した Orca / OpenAI 文書には見つからなかった。** この hybrid を選ぶ場合は、exact Git common dir を許可する permission profile、launcher、または sandbox 外で一つの安全な push wrapper だけを実行する rule / escalation といった repo-local glue が必要になる。これは vendor 既定ではなく、この repo が最小権限を優先するときの独自設計である。

したがって推奨は次の順になる。

- **Codex / Orca の推奨どおりに直すことを優先:** Orca の Codex launch arguments を Reset し、既存 session ではなく新規 session / Restart から `to-pr` を実行する。
- **full-bypass を許容しないことを優先:** Orca worktree ではなく Codex-managed worktree へ寄せる。
- **Orca + narrow Codex sandbox をどうしても維持:** 手動 shell ではなく、`git-push-topic` だけを sandbox 外で実行する既存 allow rule / escalation を publication boundary とし、`gh pr create` は push 済み branch に対して実行する。実装中の `git add` / `git commit` まで自動化する場合だけ、linked worktree の `$GIT_DIR` と `$GIT_COMMON_DIR` に限定した custom permission profile を使う。

## 判定ラベルと調査範囲

- **確認済み:** 公式 documentation / source、immutable な repo commit、またはこの環境の read-only inspection / isolated test で直接確認した事実。
- **推論:** 複数の確認済み事実から導いた運用判断。一次資料が実装の内部境界まで説明していないものを含む。
- **未確認:** 現在動いている Orca process の実 launch argv など、この session から一次確認できなかった事実。

参照された Qiita 記事は Codex CLI 0.147.0 で `workspace-write`、`/tmp`、`.git`、network を実測しており、問題提起の入口としては有用である。ただし本ノートの仕様判断は OpenAI、Orca、Git、GitHub CLI の一次資料に置く。[Qiita: Codex CLI の workspace-write は /tmp も書けた実測5例](https://qiita.com/kai_kou/items/f251fc123976a482dda1)

## linked worktree の `.git` は作業ディレクトリ内で完結しない

### 確認済み

linked worktree の top-level `.git` は directory ではなく、実体を指す `gitdir: <path>` の text file である。worktree 固有の `$GIT_DIR` は main repository の `$GIT_COMMON_DIR/worktrees/<id>` にあり、object、通常の refs、repository config などは `$GIT_COMMON_DIR` を共有する。Git は `git rev-parse --git-dir`、`--git-common-dir`、`--git-path` で最終 path を解決するよう求めている。[Git: git-worktree DETAILS](https://git-scm.com/docs/git-worktree#_details) [Git: repository layout](https://git-scm.com/docs/gitrepository-layout)

この環境の既存 Orca worktree でも次を確認した。

```text
<orca-worktree>/.git
  -> gitdir: <source-repo>/.git/worktrees/<id>

$GIT_DIR
  -> <source-repo>/.git/worktrees/<id>
     ├── HEAD
     └── index

$GIT_COMMON_DIR
  -> <source-repo>/.git
     ├── objects/
     ├── refs/
     ├── logs/
     └── config
```

つまり、worktree directory だけを writable root にしても Git metadata write は完結しない。少なくとも per-worktree index / HEAD を持つ `$GIT_DIR` と、objects / shared refs / config を持つ `$GIT_COMMON_DIR` の双方が操作に応じて必要になる。worktree の `.git` pointer file を解決した先も保護する Codex の挙動は、この構造に対応している。[OpenAI: protected paths in writable roots](https://learn.chatgpt.com/docs/agent-approvals-security#protected-paths-in-writable-roots)

## `commit` / `push` / `gh pr create` は何を書くか

### 確認済み

| 操作                      | 主な local Git metadata write                                                                                                                 | `.git` read-only での影響                                                                                                                                                                                                                                                                             |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `git add`                 | worktree 固有の `index` と lock file                                                                                                          | `$GIT_DIR` が必要。実装中の stage が失敗する。                                                                                                                                                                                                                                                        |
| `git commit`              | new object、current branch ref、reflog、commit message / lock 類                                                                              | object / shared ref は `$GIT_COMMON_DIR`、worktree state は `$GIT_DIR` にまたがる。Git 公式は index から commit を作り、current branch tip を更新すると明記する。[Git: git-commit](https://git-scm.com/docs/git-commit)                                                                               |
| `git push -u origin HEAD` | remote ref の更新に加え、local upstream 設定を common `config` に保存する。成功した push が local remote-tracking ref を更新する経路もある    | network だけの操作ではない。`-u` を固定した `git-push-topic` は local `.git/config` への write を必要とする。[Git: git-push, UPSTREAM BRANCHES](https://git-scm.com/docs/git-push#_upstream_branches) [Git source: transport tracking-ref update](https://github.com/git/git/blob/master/transport.c) |
| `gh pr create`            | local Git stateを読み、GitHub API へ PR を作成する。current branch が remote へ fully pushed でなければ、push / fork を行う prompt へ進み得る | 「PR API 呼出しだけ」とは限らない。`--head` は forking / pushing behavior を明示的に skip する。[GitHub CLI: gh pr create](https://cli.github.com/manual/gh_pr_create) [GitHub CLI source](https://github.com/cli/cli/blob/trunk/pkg/cmd/pr/create/create.go)                                         |

### 推論

この repo の `to-pr` は先に `git-push-topic`、次に `gh pr create` を実行するため、通常の failure point は PR の GraphQL create より前の push である。push が完了した後の `gh pr create` は主に Git read + network write になるが、GitHub CLI の文書は「local `.git` へ一切 write しない」ことまでは保証していない。厳密に push と PR create を分離するなら、branch 名を引数として固定する専用 wrapper から `gh pr create --head <branch>` を使う余地がある。ただし、現状の問題を直すためにそこまで追加する必要はない。

## Codex が `.git` を read-only にする根拠

### 確認済み

OpenAI は default `workspace-write` について、writable root 内でも次を read-only と明記している。

- `<writable_root>/.git` は directory / file のどちらでも read-only。
- `.git` が `gitdir: ...` pointer file なら、解決先の Git directory も read-only。
- 保護は再帰的。[OpenAI: Agent approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security#protected-paths-in-writable-roots)

また spawned `git` command も built-in edit と同じ sandbox 境界を継承する。approval と sandbox は別であり、approval policy や auto-review を有効にしただけでは `.git` の write boundary は変わらない。[OpenAI: Sandboxing](https://learn.chatgpt.com/docs/sandboxing)

current `openai/codex` source も `.git`、`.agents`、`.codex` を protected workspace metadata として扱い、restricted profile では explicit write entry がない限り metadata write を拒否する。逆に current main には、より具体的な explicit `write` entry で保護 path を開き直す処理もある。[OpenAI Codex source: permissions.rs](https://github.com/openai/codex/blob/main/codex-rs/protocol/src/permissions.rs)

### `writable_roots` だけでは足りない

legacy `sandbox_workspace_write.writable_roots` や workspace root の追加は「通常の書込み可能 root」を増やす機能であり、公式 security docs が定める `.git` / resolved `gitdir` の carve-out を自動解除しない。したがって、Qiita の例のように parent directory を writable root へ追加できても、それだけを linked-worktree Git write の解決策とみなしてはいけない。[OpenAI: Agent approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security#protected-paths-in-writable-roots) [OpenAI: Config reference](https://learn.chatgpt.com/docs/config-file/config-reference)

新しい permission profiles は `read` / `write` / `deny` の exact path と precedence を持ち、より具体的な entry が広い entry を上書きできる。custom profile で `.git` と absolute `$GIT_COMMON_DIR` を明示する経路は current docs / source に存在するが、permission profiles は legacy `sandbox_mode` と混用しない。OpenAI は「task を完了できる最も narrow な profile」を選ぶよう求めている。[OpenAI: Permissions](https://learn.chatgpt.com/docs/permissions)

profile を repo 単位に置く場合、OpenAI は trusted project の `.codex/config.toml` を project override として公式にサポートしている。ただし linked worktree の common dir は checkout の外にあるため、static repo config には machine-specific absolute path が必要になる。任意 repo を扱う Orca launcherでは、current cwd から動的解決する glue なしに portable な設定にはならない。[OpenAI: Config basics](https://learn.chatgpt.com/docs/config-file/config-basic)

## 選択肢の比較

| 経路                                                               | vendor 上の位置づけ                                                                | Git write                                    | 権限範囲                   | 判定                                                                                                                                                                  |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------- | -------------------------------------------- | -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Orca Settings → Agents → Codex → **Reset**、新 session             | Orca shipped default。Codex を `--dangerously-bypass-approvals-and-sandbox` で起動 | 通る                                         | 最広。Codex sandbox は無効 | **vendor 推奨を優先する場合の第一候補**。[Orca docs](https://www.onorca.dev/docs/model/agents-sessions)                                                               |
| Codex-managed worktree                                             | OpenAI が提供する worktree product flow                                            | Create branch 後に commit / push / PR が可能 | Codex product が管理       | **OpenAI の技術的隔離を優先する場合の第一候補**。[OpenAI docs](https://learn.chatgpt.com/docs/environments/git-worktrees)                                             |
| 人間の shell / Orca UI で push してから agent が PR create         | Git / Orca の通常操作。Orca は UI からの commit / push も案内する                  | 通る                                         | agent 外                   | **緊急 fallback**。定常の `to-pr` contract にはしない。[Orca: First session](https://www.onorca.dev/docs/first-session)                                               |
| `git-push-topic` だけ sandbox 外へ escalation、execpolicy `allow`  | OpenAI 公式の rules / approval 機構を使う repo-local policy                        | push のみ通る                                | command 単位               | **hybrid の publication に対する最小権限推奨**。rule は outside-sandbox request にだけ効く。[OpenAI: Rules](https://learn.chatgpt.com/docs/agent-configuration/rules) |
| custom permission profile で `.git` と exact common dir を `write` | OpenAI 公式 permission 機構を使う repo-local profile                               | add / commit / push が通る                   | common Git dir 全体        | 実装中の Git 操作も自律化する場合。shared refs / objects / config / hooks まで authority が広がる。[OpenAI: Permissions](https://learn.chatgpt.com/docs/permissions)  |
| plain `writable_roots` / `--add-dir` だけ                          | 通常 writable root の追加                                                          | protected Git dir は保証されない             | root 単位                  | **単独解決として非推奨**。resolved gitdir protection を test せず採用しない。                                                                                         |
| raw `danger-full-access` を手で常用                                | OpenAI が caution 付きで提供                                                       | 通る                                         | 最広                       | Orca shipped default を選ぶなら launch policy として一元化し、場当たり的に混ぜない。                                                                                  |

rules は sandbox 内の write permission を増やす設定ではない。OpenAI docs の定義は「Codex が sandbox 外で実行を request した command」に対する `allow` / `prompt` / `forbidden` である。したがって `git-push-topic = allow` があっても、通常の sandboxed command として実行すれば `.git` read-only のまま失敗し得る。`to-pr` 側または runtime がこの wrapper を明示的に escalation する配線までが一組である。[OpenAI: Rules](https://learn.chatgpt.com/docs/agent-configuration/rules)

## `to-worktree` も raw Codex では同じ問題を持つ

### 確認済み

current [`to-worktree`](https://github.com/treflebonbon/dotfiles/blob/b05a6171a0eabfdb3450def13c1d0ee7b90afb94/local-skills/to-worktree/SKILL.md) は Claude Code の `EnterWorktree` tool と、それ以外の runtime 用の次の manual path を分けている。

```bash
git worktree add .worktrees/<topic> -b feat/<topic>
cd .worktrees/<topic>
```

この manual path は shell / Git の手順としては正しいが、raw Codex `workspace-write` の end-to-end setup としては未完備である。

1. `git worktree add` 自体が source repository の branch ref と `$GIT_COMMON_DIR/worktrees/<id>` を作るため、開始時点で protected `.git` write を必要とする。[Git: git-worktree](https://git-scm.com/docs/git-worktree)
2. 作成後の linked worktree に対して `$GIT_DIR` / `$GIT_COMMON_DIR` を writable にする処理がないため、後続の `git add` / `git commit` / `git-push-topic` で同じ failure が再発する。
3. `cd` はその shell process の current directory を変えるだけで、Codex session の primary workspace root を恒久的に切り替える contract ではない。Codex CLI は `-C` / `--cd` を「agent の working root」として session 起動 option に持つため、後続 phase の tool `workdir`、config resolution、permission root を保証するには worktree を root とした session launch / handoff が必要である。[OpenAI Codex source: shared CLI options](https://github.com/openai/codex/blob/main/codex-rs/utils/cli/src/shared_options.rs)

### runtime 別判定

| runtime     | 判定                    | 理由                                                                                                                                                                                                                        |
| ----------- | ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Claude Code | **概ね成立**            | skill が harness-native `EnterWorktree` を優先し、作成と session-side entry を tool に委ねる。                                                                                                                              |
| Orca        | **上位 routing で回避** | この repo の project instruction は Orca session では既存 Orca worktree を優先するため、通常は worktree 内からさらに `to-worktree` manual path を実行しない。[Orca: Worktrees](https://www.onorca.dev/docs/model/worktrees) |
| raw Codex   | **未完備**              | worktree 作成前の Git metadata escalation、作成後の common dir permission、session working root の再設定が contract にない。                                                                                                |

したがって `to-worktree` を raw Codex でも対応させる将来変更は、単に `git worktree add` を shell 側で代行するだけでは足りない。少なくとも「安全な worktree-create wrapper の sandbox 外実行 → 新 worktree path と common dir の解決 → その path を `-C` とした新 Codex session / handoff → selected permission policy の再適用」を一つの transaction として設計する必要がある。これは今回の `to-pr` failure の修正範囲を超えるため、本ノートでは実装しない。

## この repo の contract と現在の配線

### 確認済み

この repo の [`to-pr`](https://github.com/treflebonbon/dotfiles/blob/b05a6171a0eabfdb3450def13c1d0ee7b90afb94/local-skills/to-pr/SKILL.md) は、呼出し自体を routine publication の承認とし、次を順に実行する。

```bash
git-push-topic
gh pr create --title "<conventional title>" --body-file <tmp>
```

[`git-push-topic`](https://github.com/treflebonbon/dotfiles/blob/b05a6171a0eabfdb3450def13c1d0ee7b90afb94/private_dot_local/bin/executable_git-push-topic) は引数を拒否し、detached HEAD / default branch を fail closed にしたうえで `git push -u origin HEAD` のみを実行する。[`ADR-0030`](https://github.com/treflebonbon/dotfiles/blob/b05a6171a0eabfdb3450def13c1d0ee7b90afb94/docs/adr/0030-preauthorize-routine-github-writes.md) と [`runtime/skill-harness.md`](https://github.com/treflebonbon/dotfiles/blob/b05a6171a0eabfdb3450def13c1d0ee7b90afb94/runtime/skill-harness.md) も、`to-pr` を push / PR create の事前承認と定義する。

Codex rules は raw `git push` と代表的な bypass を `forbidden`、`git-push-topic` と列挙した `gh pr create` 等を `allow` にしている。[`default.rules`](https://github.com/treflebonbon/dotfiles/blob/b05a6171a0eabfdb3450def13c1d0ee7b90afb94/private_dot_config/codex/rules/default.rules) これは「push を人間 shell へ移す」より、「既に絞った wrapper だけを sandbox 外で動かす」設計と整合する。

repo はすでに二段階で hybrid 対応を実装している。

- [PR #141 / commit `a855fc2`](https://github.com/treflebonbon/dotfiles/commit/a855fc2) は `dotfiles-secure` profile に workspace `.git` と source repository の absolute common dir write を追加した。
- [PR #179 / commit `b05a617`](https://github.com/treflebonbon/dotfiles/commit/b05a6171a0eabfdb3450def13c1d0ee7b90afb94) は [`codex-orca`](https://github.com/treflebonbon/dotfiles/blob/b05a6171a0eabfdb3450def13c1d0ee7b90afb94/private_dot_local/bin/executable_codex-orca) が current cwd から `git rev-parse --git-common-dir` を動的解決し、exact path の `write` override を渡すようにした。ambient `GIT_DIR` / `GIT_COMMON_DIR` を除去し、nested sandbox の temp path collision を避けるため `TMPDIR=/tmp` へ固定する。

[`tests/codex-config.bats`](https://github.com/treflebonbon/dotfiles/blob/b05a6171a0eabfdb3450def13c1d0ee7b90afb94/tests/codex-config.bats) の linked-worktree test は、別 repo を source とする worktree で raw profile の `git add` が失敗し、`codex-orca` 経由なら成功し、`.env` は deny のままという境界を確認する。2026-08-25 にこの test 一件を outer sandbox 外で再実行し、pass を確認した。

### 現在の failure をどう読むか

active `$CODEX_HOME/config.toml` と [`source template`](https://github.com/treflebonbon/dotfiles/blob/b05a6171a0eabfdb3450def13c1d0ee7b90afb94/private_dot_config/codex/config.toml.tmpl) は `default_permissions = "dotfiles-secure"`、workspace `.git = "write"`、dotfiles common dir の absolute `write` を持つ。一方、この会話へ渡された実効 filesystem profile は workspace root write でも `.git` は明示的に read-only である。**設定ファイルの意図と、この session に materialize された権限が一致していないことは確認済み**である。

有力な説明は、現在の Orca session が raw `codex` / 別 launch arguments で始まった、設定変更前から継続している、または上位 runtime が profile を上書きしている、のいずれかである。Codex rules は startup に読み込まれ変更後は restart が必要で、Orca の launch argument override も subsequent launch に適用される。[OpenAI: Rules](https://learn.chatgpt.com/docs/agent-configuration/rules) [Orca: Agents & sessions](https://www.onorca.dev/docs/model/agents-sessions)

ただし current Orca agent の実 command / argv は **未確認**である。Orca skill guide の local CLI 取得は `UtilBindVsockAnyPort: socket failed 1` で失敗したため、履歴に `codex-orca` / `-P dotfiles-secure` を設定した記録があっても、現在実行中の process の一次証拠としては扱わない。Orca 公式 docs から確認できるのは、built-in Codex picker の shipped default が raw `codex` + full-bypass flag であることまでである。[Orca: Codex](https://www.onorca.dev/docs/agents/codex) [Orca: Supported agents](https://www.onorca.dev/docs/agents/supported)

また、すでに sandbox 内にいる session から `codex sandbox` を起動すると、nested bubblewrap が `/tmp/codex-bwrap.../lock: Read-only file system` で失敗することがある。同じ linked-worktree test は outer sandbox 内では red、outer sandbox 外では green だった。この red は `codex-orca` の Git permission regression の証拠ではなく、nested sandbox の検証環境汚染である。sandbox regression test は outer sandbox 外、または Codex が公式に想定する host 環境で実行する。[OpenAI: Linux sandbox implementation](https://learn.chatgpt.com/docs/permissions#how-enforcement-works)

## 実行判断

### vendor 既定へ戻す場合（推奨）

1. Orca Settings → Agents で Codex launch arguments を確認する。
2. 独自 override を使わない方針なら **Reset** し、shipped `--dangerously-bypass-approvals-and-sandbox` に戻す。
3. running session へ hot-apply したとみなさず、新規 session または Restart から `to-pr` を実行する。
4. full-bypass が threat model に合わないなら、その場で個別 writable root を足し続けず、Codex-managed worktree へ切り替える。

### hybrid narrow sandbox を維持する場合（repo-local recommendation）

1. PR publication だけの問題なら、common dir 全体を常時 writable にせず、既存 `git-push-topic` を sandbox 外で実行する escalation と `allow` rule を一組にする。push 後に `gh pr create` を続行する。
2. `git add` / `git commit` も session 内で必要なら、`codex-orca` から current `$GIT_COMMON_DIR` を exact path として custom profile へ追加する。source repo 固定 path だけでは、別 repo の Orca worktree を処理できない。
3. launch command / selected profile / effective `/status` を新 session で確認する。設定ファイルに entry が存在するだけで成功扱いにしない。
4. `codex sandbox` の linked-worktree test は outer sandbox 外で行う。common dir write と `.env` deny の双方が pass 条件である。

## 未確認事項

- Orca built-in launcherが full-bypass を渡すことは確認済みだが、「worktree itself is the sandbox」を OS security boundary として実装する追加 isolation は公式 docs から確認できない。Git worktree 自体にはその機能がないため、運用上の isolation という理解が安全である。
- OpenAI の Codex-managed worktree で commit / push / PR が可能なことは確認済みだが、product が protected Git metadata write をどの privileged component へ分離しているかは公開ページに記載がない。
- current Orca terminal が `codex`、`codex-orca`、どの `-P` / `-c` / full-bypass flag で起動されたかは未確認。新 session の process argv / `/status` で確認する必要がある。
- current `openai/codex` main source は exact path permission override を実装しているが、すべての platform / managed runtime が同じ profile を受け入れることまではこの調査で保証しない。実配備 version と `codex sandbox` test を正本にする。
