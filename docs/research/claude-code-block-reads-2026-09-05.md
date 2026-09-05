---
type: research
title: Claude Code の blockReadsOutsideWorkingDirectories と tool / skill snapshot（2026-09-05）
description: Anthropic 公式 docs・CHANGELOG と numtide/llm-agents.nix の upstream metadata を一次情報として、外部読み取り境界とこの dotfiles での導入候補を調査したノート。
tags: [research, claude-code, permissions, worktree, llm-agents, skills]
timestamp: 2026-09-05
---

# Claude Code の `blockReadsOutsideWorkingDirectories` と tool / skill snapshot（2026-09-05）

このノートの時刻は JST（Asia/Tokyo）、Anthropic / `llm-agents.nix` の公開時刻は UTC で記録する。外部の二次記事は使わず、Anthropic 公式 docs / 公式 CHANGELOG / 公式 GitHub release と `numtide/llm-agents.nix` の source metadata だけを根拠にした。

## 結論

### Claude Code

`permissions.blockReadsOutsideWorkingDirectories` は、**session の primary working directory と `permissions.additionalDirectories` に含まれるディレクトリの外側を、Claude の file tools が読むことを全 permission mode で拒否する**設定である。設定リファレンスの default は `unset`（未設定）であり、`true` が既定ではない。[公式 settings reference](https://code.claude.com/docs/en/settings-reference#permissions-blockreadsoutsideworkingdirectories)、[公式 permissions docs](https://code.claude.com/docs/en/permissions#working-directories)

この repo は `defaultMode: "auto"` で background agent / worktree / skill の読み取りを多用する。機密ファイルを `deny` する既存ルールに加えて外部ファイルの accidental read を境界化する目的には `true` が適している。ただし、想定された `~/runtime` の読み取りを保つため、導入するなら `additionalDirectories` に `~/runtime` を追加することを推奨する。現行の `~/.claude/jobs` は既に追加済みなので残す。

調査phaseで得た推奨候補は次のとおりである（後段の実装結果は末尾に追記する）。

```json
{
  "permissions": {
    "defaultMode": "auto",
    "additionalDirectories": ["~/.claude/jobs", "~/runtime"],
    "blockReadsOutsideWorkingDirectories": true
  }
}
```

`~/.agents/skills` は Codex / Antigravity が読む共有 skill hub であり、Claude Code の user-level skill discovery は `~/.claude/skills` が担当する。このため Claude の file-tool read を許可するために `~/.agents/skills` を追加する根拠は現時点ではない。`~/.gitconfig`、共有 `.git` metadata、親 checkout も追加しない。Git worktree が共有する metadata は Claude Code の git / worktree runtime が扱うべき境界であり、2.1.260 でこの設定に起因する git config / subagent checkout の不具合が修正されているため、明示的に home 全体を許可するより実動作で確認する。

### version と更新単位

調査開始時に実行した `claude --version` は `2.1.258`。同時点の source checkout は `llm-agents.nix` を revision [`775405507404a6c28246aec9a848e091d3d8478c`](https://github.com/numtide/llm-agents.nix/commit/775405507404a6c28246aec9a848e091d3d8478c) に pin し、upstream package metadata の Claude Code は 2.1.258 だった。[local flake input](../../private_dot_config/nix-devshell/flake.nix#L15-L18)、[local flake lock](../../private_dot_config/nix-devshell/flake.lock#L58-L80)

2026-09-04 19:58:10 UTC に公開された Anthropic の最新 stable release は [v2.1.261](https://github.com/anthropics/claude-code/releases/tag/v2.1.261)。同日 11:30:43 UTC 時点の `numtide/llm-agents.nix` default branch は [`896d09ccef580902e01e716e6f4646421087c252`](https://github.com/numtide/llm-agents.nix/commit/896d09ccef580902e01e716e6f4646421087c252) で、[その revision の Claude package metadata](https://raw.githubusercontent.com/numtide/llm-agents.nix/896d09ccef580902e01e716e6f4646421087c252/packages/claude-code/hashes.json) は `version: 2.1.261` を収録している。したがって tool snapshot 更新の候補は、現行 2.1.258 から upstream default branch の 2.1.261 を含む exact revision への更新である。`apm` の skill payload 更新とは別の互換性・rollback 単位として扱う（[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md)）。

## `blockReadsOutsideWorkingDirectories` の semantics

### working directory の定義

Claude Code は、起動したディレクトリを session の primary working directory とする。`--add-dir <path>`、`/add-dir`、または settings の `permissions.additionalDirectories` で追加したディレクトリも working directories になる。追加ディレクトリ内の file read は prompt なしで扱われ、file edit は現在の permission mode に従う。[公式 permissions docs — Working directories](https://code.claude.com/docs/en/permissions#working-directories)、[公式 CLI reference — `--add-dir`](https://code.claude.com/docs/en/cli-usage#cli-flags)

`additionalDirectories` は file access の拡張であり、完全な configuration root ではない。追加ディレクトリの `.claude/skills/` は live reload される例外だが、その他の `.claude` configuration（subagents、commands、output styles、hooks など）は原則として追加ディレクトリから discovery されない。`CLAUDE.md` / `.claude/rules/` / `CLAUDE.local.md` を追加ディレクトリから読むには `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` が必要である。[公式 permissions docs — Additional directories grant file access, not configuration](https://code.claude.com/docs/en/permissions#additional-directories-grant-file-access-not-configuration)、[公式 memory docs](https://code.claude.com/docs/en/memory#load-from-additional-directories)

`/cd <path>` は追加ではなく primary working directory を移動し、移動先の project configuration / skills / plugins 等を読み込む。main session の `cd` は primary または追加 directory 内に留まる限り後続 Bash に保持され、それ以外へ出ると project directory に戻される。subagent の working-directory 変更は親 session へ継承されない。[公式 permissions docs](https://code.claude.com/docs/en/permissions#move-the-session-to-another-directory)、[公式 tools reference](https://code.claude.com/docs/en/tools-reference#bash)

### 設定値と permission mode

- **default**: settings reference 上の default は `unset`。`false` または未設定では、auto mode の最初の Read / Grep / Glob に対して working directories 外の read を今後も許可するか尋ねる one-time prompt が出る（非対話 `-p` / background ではその prompt は出ず、従来の動作）。[公式 permission modes docs](https://code.claude.com/docs/en/permission-modes#auto-mode)
- **`true`**: file tools は working directories 外の path を全 permission mode で拒否する。`default`、`acceptEdits`、`plan`、`auto`、`dontAsk`、`bypassPermissions` のモード選択で、この path fence 自体を bypass できない。[公式 settings reference](https://code.claude.com/docs/en/settings-reference#permissions-blockreadsoutsideworkingdirectories)、[公式 permission modes docs](https://code.claude.com/docs/en/permission-modes#available-permission-modes)
- **built-in read-only Bash**: Claude Code は `ls`、`cat`、`echo`、`pwd`、`head`、`tail`、`grep`、`find`、`wc`、`which`、`diff`、`stat`、`du`、`cd` と read-only な `git` を permission prompt なしで扱う。ただし `blockReadsOutsideWorkingDirectories` が fence する path は例外で、read path の permission check に入る。[公式 permissions docs — Read-only commands](https://code.claude.com/docs/en/permissions#read-only-commands)
- **Bash の redirect**: `< file` の入力 redirect は `Read` rule と working-directory boundary の対象になり、v2.1.257 以降は外部 path も評価される。`> file` / `>> file` は Edit rule、protected path、working-directory boundary の対象である。[公式 permissions docs — Redirections](https://code.claude.com/docs/en/permissions#redirections)
- **auto mode の classifier との違い**: `auto` は通常 classifier が safety check を行うが、working-directory 外の read fence は classifier の判断で許可される一般的な allowlist ではない。公式 docs は、設定有効時の recognized file-reading Bash と sandbox 外 retry を `auto` / `bypassPermissions` でも prompt 対象としているため、direct file tools の拒否と Bash read の permission prompt を分けて検証する。[公式 permission modes docs](https://code.claude.com/docs/en/permission-modes#auto-mode)

### 対象 version と bugfix

設定が追加されたのは [公式 CHANGELOG v2.1.257](https://github.com/anthropics/claude-code/blob/v2.1.257/CHANGELOG.md#21257) である。同じ release で、auto mode の Containment Escape rule、compound command / subshell の `permissions.ask` bypass 修正、reader command / input redirect に `Read` / `Edit` deny rule を適用する修正、plugin path の symlink traversal 修正、worktree-isolated Bash の false positive 修正も入った。

その後の関連 version は次のとおりである。

| release | 公式に確認できる変更                                                                                                                                                                                                              | この repo への意味                                                                                           |
| ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| 2.1.258 | macOS 12 の launch regression、再送された permission approval の content 欠落を修正。[CHANGELOG](https://github.com/anthropics/claude-code/blob/v2.1.258/CHANGELOG.md#21258)                                                      | floor の安定性には寄与するが、外部 read 境界固有の floor 根拠とはしにくい                                    |
| 2.1.259 | hook-created worktree の検出、worktree-isolated session の Bash loop / xargs pipeline / launcher-wrapped command の false refusal を修正。[CHANGELOG](https://github.com/anthropics/claude-code/blob/v2.1.259/CHANGELOG.md#21259) | worktree + Bash read matrix を 2.1.259 でも再確認する根拠                                                    |
| 2.1.260 | `blockReadsOutsideWorkingDirectories` が macOS の git config と worktree-isolated subagent 自身の checkout を隠す不具合を修正。[CHANGELOG](https://github.com/anthropics/claude-code/blob/v2.1.260/CHANGELOG.md#21260)            | この repo の linked worktree / subagent 運用に直撃。採用 floor は少なくとも 2.1.260、snapshot 候補は 2.1.261 |
| 2.1.261 | `/add-dir` の `/net` automount false error、background agent resume の high CPU、Stop / Remote Control 等を修正。[CHANGELOG](https://github.com/anthropics/claude-code/blob/v2.1.261/CHANGELOG.md#21261)                          | 2.1.260 fix の後続候補。外部 read setting の新しい semantics 変更は CHANGELOG にない                         |

`2.1.253`–`2.1.256` は公式 CHANGELOG の version section として確認できないため、更新候補の版飛びを release と誤認しない。現行 upstream package が 2.1.261 を収録していることは、Claude Code stable release と `llm-agents.nix` metadata の双方で確認済みである。

## この dotfiles の現状と採否

調査時点で確認した local source は次の状態である。

| 対象                                                                                                               | 現状                                                                                                               | 判断                                                                                                                                                                                |
| ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`private_dot_claude/settings.json.tmpl`](../../private_dot_claude/settings.json.tmpl#L8-L12)                      | `defaultMode: "auto"`、`additionalDirectories: ["~/.claude/jobs"]`。`blockReadsOutsideWorkingDirectories` は未設定 | `true` を追加候補にする。ただし `~/runtime` を追加してから導入する                                                                                                                  |
| [`private_dot_config/nix-devshell/modules/ai.nix`](../../private_dot_config/nix-devshell/modules/ai.nix#L101-L140) | `minClaudeCode = "2.1.257"`、snapshot package は 2.1.258                                                           | 2.1.260 fix を floor 根拠にできるかを release gate で決め、少なくとも 2.1.260 を候補にする。snapshot を 2.1.261 へ追従する場合は `minClaudeCode` も同じ compatibility gate で決める |
| [`private_dot_config/nix-devshell/flake.lock`](../../private_dot_config/nix-devshell/flake.lock#L58-L80)           | `llm-agents.nix` exact revision `7754055…`                                                                         | upstream [`896d09c…`](https://github.com/numtide/llm-agents.nix/commit/896d09ccef580902e01e716e6f4646421087c252) への tool snapshot 更新候補                                        |
| `~/.claude/jobs`                                                                                                   | 実在し、`state.json` / `timeline.jsonl` 等を持つ。現行 settings で追加済み                                         | 維持。job read を block 設定で壊さないため必要                                                                                                                                      |
| `~/runtime`                                                                                                        | 実在し、`index.md` / `ai-runtimes.md` / `skill-harness.md` 等を持つ。global `CLAUDE.md` が参照を要求               | `additionalDirectories` へ追加推奨。読み取りだけでなく mode に応じた edit scope も広がるので実動作 gate が必要                                                                      |
| `~/.agents/skills`                                                                                                 | 実在する共有 hub。Codex / Antigravity 向け。Claude 用 `~/.claude/skills` は別に配備済み                            | Claude の additional directory には追加しない。`Skill` discovery と file-tool read を混同しない                                                                                     |
| `~/.gitconfig` / linked worktree の共通 `.git`                                                                     | 実在。worktree Git dir は共通 git dir を参照                                                                       | path を追加して境界を広げない。2.1.260 の git-config / subagent checkout fix を含む candidate で git smoke を行う                                                                   |

### 採用を進める条件

1. `llm-agents.nix` snapshot と APM payload を同じ lock / rollback 単位にしない。tool snapshot は upstream exact revision と Claude version assert の変更、skill payload は APM の selected subtree / lock hash を独立して review する。
2. `blockReadsOutsideWorkingDirectories: true` を設定する前に、`~/runtime` を追加した candidate settings を隔離した `CODEX_HOME` / Claude config で検証する。live `~/.claude/jobs`、live `~/.agents/skills`、live deployment はテスト fixture にしない。
3. v2.1.260 の修正対象である global git config、linked worktree common `.git`、worktree-isolated subagent 自身の checkout を必須 smoke にする。
4. direct `Read` / `Grep` / `Glob`、recognized Bash reader、input redirect、symlink、非対話 `-p`、background session の結果を分けて記録する。docs から推測して一つの「外部 read は全部拒否」というテスト結果にまとめない。

## 実動作 verification matrix

### 共通準備

テストは候補 Claude binary（最低 2.1.260、推奨 2.1.261）を使い、各 case の一時設定で `permissions.additionalDirectories` と `permissions.blockReadsOutsideWorkingDirectories` だけを切り替える。現在の dotfiles source、live `~/runtime`、live skill directory、実際の jobs state を変更しない。各 fixture は次の構成にする。

```text
fixture/
  repo/                 # primary linked worktree
  repo/.claude/         # isolated test settings only
  extra/                # explicit additionalDirectories candidate
  outside/              # not in any working directory
  symlink-to-outside
```

機密情報は fixture に置かない。期待結果は exit code だけでなく、tool result に `permission denied` / prompt / success のどれが出たか、settings が user scope に書き戻されたか、対象 path が変化していないかで判定する。

### matrix

| axis                   | cases                                                                                       | 確認すること                                                                                                                                                                  |
| ---------------------- | ------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| setting                | unset、`false`、`true`                                                                      | unset / false の auto one-time prompt と、true の persistent fence を区別する。user settings への自動書き戻しも確認                                                           |
| permission mode        | `default`、`acceptEdits`、`plan`、`auto`、`dontAsk`、`bypassPermissions`                    | true で direct file read が全 mode で拒否されるか。`bypassPermissions` は candidate の隔離環境だけで試す                                                                      |
| direct tools           | `Read`、`Grep`、`Glob`                                                                      | primary worktree は成功、`outside/` は true で拒否、`extra/` は追加 directory 設定時だけ成功、symlink は target 境界として評価されるか                                        |
| Bash readers           | `cat`、`grep`、`find`、`head`、read-only `git`、`pwd` / `cd`                                | working-directory 内外で built-in read-only 扱いが変わるか。true の外部 path は prompt / deny の実際の結果を記録                                                              |
| redirects              | `cat < outside/file`、`grep x < outside/file`、`cat > outside/file`                         | v2.1.257 の input redirect read check と output redirect edit checkを別々に確認。glob、`cd dir && cat file`、heredocも含める                                                  |
| additional directories | `~/.claude/jobs`、`~/runtime`、fixture `extra/`                                             | settings の追加 path は direct tools / Bash / edit それぞれに効くか。追加 path の `.claude/skills` discovery と `CLAUDE.md` discovery（env var あり / なし）も別確認          |
| user config            | `git config --global --get user.name`、read-only git from linked worktree                   | 2.1.260 で修正された global git config の hidden failure が再発しないか。credential value は出力しない                                                                        |
| linked worktree        | current linked worktree、main checkout の common `.git`、`.git` pointer                     | current worktree 内の edit / read は成功し、main checkout file を直接読む操作は境界外として扱われるか。git commit 等の common metadata access が壊れないか                    |
| subagent               | `Agent(isolation: "worktree")` の own checkout、親 worktree、main checkout                  | 2.1.260 fix のとおり own checkout が hidden にならず、親 / main checkout の file edit・read isolation が維持されるか                                                          |
| jobs / background      | scheduled job の state read、background session、`-p`                                       | `~/.claude/jobs` は追加 path として継続利用できるか。background / noninteractive に interactive one-time prompt を期待しない                                                  |
| skills                 | Claude の `~/.claude/skills`、shared `~/.agents/skills`、追加 directory 内 `.claude/skills` | `Skill` tool discovery が block 設定に不必要に依存しないことを確認。Claude が shared hub を直接 file-tool read する構成なら、それを別途明示して additional directory を再判断 |
| version regression     | 2.1.258、2.1.259、2.1.260、2.1.261（可能なら）                                              | 2.1.257 setting introduction、2.1.259 worktree false refusal、2.1.260 git config / own checkout fix、2.1.261 current candidate を比較                                         |

### 判定基準

- **採用**: true の direct file-tool fence、追加 directory の必要な read、linked worktree / git config / isolated subagent の smoke、background / `-p` の non-prompt behavior が全て期待どおりで、既存の secret deny ルールと skill discovery に回帰がない。
- **保留**: direct tools は正しいが、Bash reader / redirect / subagent の結果が version・permission mode により不明確、または `~/runtime` を追加しないと global contract が読めない。
- **不採用**: own worktree または共通 `.git` が読めず、Claude が自分の skill / runtime contract / job state を安定して読めない。home 全体や `~/.agents/skills` を追加して回避するのではなく、失敗した path の責務を再設計する。

## 確認済み / 推論 / 未確認

### 確認済み

- 公式 settings reference の `blockReadsOutsideWorkingDirectories` default は unset で、説明は「全 permission mode で working directories 外の file-tool read を拒否」。
- 設定の導入は v2.1.257、2.1.260 に macOS git config と worktree-isolated subagent own checkout の修正がある。
- 調査開始時の Claude Code は 2.1.258、local `llm-agents.nix` package metadata も 2.1.258。
- 2026-09-05 時点の Anthropic stable と upstream `llm-agents.nix` default-branch package はともに 2.1.261。upstream main revision は `896d09ccef580902e01e716e6f4646421087c252`。
- 調査開始時の checkout の settings は `auto`、`~/.claude/jobs` のみ additional、block 設定なし。`~/runtime` / `~/.agents/skills` / `~/.claude/jobs` は実在する。

### 推論

- この repo の global `CLAUDE.md` が `~/runtime/index.md` を参照させるため、true を採るなら `~/runtime` を additional directory にするのが最小の明示的許可である。
- Claude の `~/.claude/skills` は user-level discovery であり、Codex / Antigravity 用 `~/.agents/skills` を Claude の additional directory にする必要はない。
- tool snapshot と APM skill payload は ADR-0045 の compatibility / rollback boundary に従い分けるべきである。

### 未確認

- `Grep` / `Glob` / LSP、全 permission mode の個別比較、scheduled job / background session、明示 `permissions.allow` との細かい優先順位は未確認とする。
- `LSP` や plugin 内部の file read が direct `Read` / `Grep` / `Glob` と同じ fence に入るかは、公式 current docs の一般的な「file tools」という説明だけではこの repo の enabled plugins に対して確定できない。LSP plugin を使う fixture を matrix に追加し、結果を別記する。

## 実装結果（2026-09-05）

tool snapshotを`896d09ccef580902e01e716e6f4646421087c252`へ固定し、Claude Code floorを2.1.261へ上げた。managed settingsには`blockReadsOutsideWorkingDirectories: true`を追加し、`additionalDirectories`は`~/.claude/jobs`と`~/runtime`だけにした。`~/.agents/skills`、user git config、共有`.git`、親checkoutは許可directoryへ追加していない。

候補Claude Code 2.1.261を一時fixtureと明示settingsで`--print --no-session-persistence`実行し、stream JSONのtool event / denial reasonまで確認した。

| case                                             | 結果                                                                                              |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| primary directoryのdirect `Read`                 | `PRIMARY_OK`を取得                                                                                |
| 明示`additionalDirectories`のdirect `Read`       | `EXTRA_OK`を取得                                                                                  |
| outside fileのdirect `Read`                      | `permissions.blockReadsOutsideWorkingDirectories`を理由に拒否                                     |
| primary内symlinkからoutside targetへの`Read`     | 同じread fenceを理由に拒否                                                                        |
| outside fileへのBash `cat` / input redirect      | `bypassPermissions` modeでも両方ともread fenceを理由に実行前拒否                                  |
| global git configとlinked worktreeの`git status` | config値を出力せず`GIT_RUNTIME_OK`                                                                |
| `Agent(isolation: "worktree")`のown checkout     | own checkoutで`pwd`と`Read AGENTS.md`が成功し`OWN_WORKTREE_OK`。一時worktreeは終了時に自動cleanup |

これにより2.1.260の修正対象だったglobal git configとworktree-isolated subagent own checkoutを含む必須smokeは通過した。`nix flake check --no-build --all-systems`と3 systemのpackage metadata evaluationも成功している。task worktreeからlive HOMEへの`chezmoi apply`は行っていない。

## 一次情報

- [Anthropic: Configure permissions](https://code.claude.com/docs/en/permissions)
- [Anthropic: Choose a permission mode](https://code.claude.com/docs/en/permission-modes)
- [Anthropic: Settings reference](https://code.claude.com/docs/en/settings-reference#permissions-blockreadsoutsideworkingdirectories)
- [Anthropic: Tools reference](https://code.claude.com/docs/en/tools-reference)
- [Anthropic: Run parallel sessions with worktrees](https://code.claude.com/docs/en/worktrees)
- [Anthropic: Run agents in parallel](https://code.claude.com/docs/en/agents)
- [Anthropic Claude Code v2.1.257 CHANGELOG](https://github.com/anthropics/claude-code/blob/v2.1.257/CHANGELOG.md#21257)
- [Anthropic Claude Code v2.1.260 CHANGELOG](https://github.com/anthropics/claude-code/blob/v2.1.260/CHANGELOG.md#21260)
- [Anthropic Claude Code v2.1.261 release](https://github.com/anthropics/claude-code/releases/tag/v2.1.261)
- [numtide/llm-agents.nix current default-branch commit](https://github.com/numtide/llm-agents.nix/commit/896d09ccef580902e01e716e6f4646421087c252)
- [`llm-agents.nix` Claude Code metadata at that revision](https://raw.githubusercontent.com/numtide/llm-agents.nix/896d09ccef580902e01e716e6f4646421087c252/packages/claude-code/hashes.json)
