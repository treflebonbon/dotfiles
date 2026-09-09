---
type: decision
title: additionalDirectories を Edit-deny read-only パターンで拡張する
description: ADR-0045 の「最小限に保つ」方針を実測データに基づき部分的に見直し、~/ghq/github.com・~/.claude/projects・/nix/store を additionalDirectories に加える。書込みが不要な対象は Edit-deny で read-only にする。
tags: [adr, claude-code, permissions, working-directories]
timestamp: 2026-09-07
status: accepted
---

# additionalDirectories を Edit-deny read-only パターンで拡張する

ADR-0045（2026-09-05）は Working-Directory Read Fence（[CONTEXT.md](../../CONTEXT.md)）を有効化する際、`additionalDirectories` を `~/.claude/jobs` と `~/runtime` だけに絞り、「home 全体や `~/.agents/skills` を追加して回避するのではなく、失敗した path の責務を再設計する」と明記した。この方針を、2026-09-07 に実施した実際の session transcript の実測分析と、本セッションでのライブ実測に基づき部分的に見直す。

## Decision

`private_dot_claude/settings.json.tmpl` の `additionalDirectories` に `~/ghq/github.com`、`~/.claude/projects`、`/nix/store` を追加する。`~/ghq/github.com` は `deny` に `Edit(~/ghq/github.com/**)` を加えて read-only にする（`~/runtime` に対する既存の `Edit(~/runtime/**)` deny と同じパターン）。`~/.claude/projects` は memory システムの読み書きに必要なため Edit-deny を付けない。`/nix/store` は OS レベルで immutable なため Edit-deny は不要とする。

`/tmp`、`~/orca/workspaces`、`/mnt/nfs` は追加しない。必要になった session でその都度 `/add-dir` を使う。

## Considered Options

- **`~/.claude/skills` を追加する**: transcript 上の実測では deny 実績が記録されていたが、本セッションでライブ実測したところ `~/.claude/skills/**` は `SKILL.md` と script ファイルのどちらも Read tool の fence 対象外だった（同じ Read tool で `~/.bashrc`、`~/.claude/history.jsonl`、他プロジェクトの transcript は明確に block されることを対比確認した）。既に fence 対象外のため追加不要と判断した。
- **`/tmp` を全体追加する**: 実測で Bash 経由の `/tmp` 読み書き（`cat`、working directory 外への出力 redirect）は現状 fence の対象外と判明した。fence が効くのは direct file tool 呼び出しのみのため、恒久追加の効用は限定的と判断して見送った。root cause（`to-pr` 等が `/tmp` ではなく session scratchpad を使うようにする）は別 issue とする。
- **`~/orca/workspaces` / `/mnt/nfs` を chezmoi の環境フラグで条件分岐する**: [ADR-0046](0046-separate-orca-native-worktree-entry.md) が Orca セッション識別用の環境変数 discriminator を意図的に不採用としており、この repo には `is_orca` 相当のフラグが存在しないため見送った。

## Consequences

**Working-Directory Read Fence は Bash コマンドを保護しない。** 本セッションでの実測（`cat ~/.bashrc`、working directory 外への出力 redirect）はいずれも block されず成功した。公式ドキュメントと 2026-09-05 調査ノートの検証表（bypassPermissions でも Bash `cat`/redirect は拒否される）と食い違う。この fence は direct file tool（Read/Grep/Glob、および追加済みディレクトリでの Edit/Write）だけを保護し、Bash 経由のファイルアクセスは別レイヤーの Technical Sandbox Boundary の範囲になる。この repo は `sandbox.filesystem` を設定していないため、現状 Bash からの working directory 外ファイルアクセスに事実上の境界はない。この食い違いの原因調査（version 差分か未文書化の仕様か）は本 ADR のスコープ外とし、別途フォローアップとする。

`~/ghq/github.com` を read-only で追加したことで、worktree セッションから親 checkout を direct file tool で読める一方、誤って親 checkout や他 repo を Edit ツールで書き換えることは防ぐ。ただし上記の通り Bash 経由の書込みはこの deny の対象外であり、read-only 化は Edit ツール経由のリスクだけを閉じる点に注意する。

一次情報と実動作の詳細は [2026-09-07 追記](../research/claude-code-block-reads-2026-09-05.md#2026-09-07-追記) を正本とする。

(2026-09-08 追記) root cause として繰延べた「`to-pr` 等が `/tmp` ではなく session scratchpad を使うようにする」対応は [ADR-0052](0052-resolve-to-pr-temp-artifacts-via-session-scratchpad.md) で決着した。

(2026-09-08 追記、issue #248) 上記の「Working-Directory Read Fence は Bash コマンドを保護しない」という結論は、`cat` や `< file` / `> file` のような認識済み read-only reader・redirect に限って正しい。静的解析できない script（heredoc 経由の interpreter、`$(...)` / command substitution、裸の `$VAR`（simple expansion）、`sed`/`awk`/`python3 -c` 等の programmable reader、safe list 外の環境変数プレフィックス）は、working directory の内外を問わず同じ `permissions.blockReadsOutsideWorkingDirectories` を理由に一律で human confirmation を要求する。本 ADR が採用した実測 verification matrix はこの経路を一度もテストしておらず（outside file への Bash アクセスとして `cat` / input redirect のみを検証）、「Bash は保護されない」は認識済み reader についてのみ正しい結論だった。`permissions.allow` の Bash ルールもこの確認を回避しない（実測確認済み）。詳細な taxonomy と実測結果は [2026-09-05 調査ノートの 2026-09-08 追記](../research/claude-code-block-reads-2026-09-05.md#2026-09-08-追記issue-248) を参照する。TMPDIR carve-out gap への対応は [ADR-0054](0054-stabilize-nix-shell-tmpdir-base.md) を参照する。

(2026-09-08 追記、issue #250) `~/ghq/github.com` に対する `Edit(~/ghq/github.com/**)` deny を撤回した。deny ルールは session の working directory に関わらずマッチするため、`~/ghq/github.com` を read-only にする本 ADR の判断は「実装対象の repository 自身もこのディレクトリ配下に置かれる」という前提を見落としていた。`~/runtime` はデプロイ物の置き場でしかなく実装対象になり得ないため read-only 化が成立するが、`~/ghq/github.com` は `EnterWorktree` が作る worktree を含め実装対象そのものの置き場であり、同じ Edit-deny-readonly パターンを適用すると repository の編集そのものが拒否される。実際に `~/ghq/github.com/<owner>/<repo>` 配下のファイルへ Edit/Write ツールを使うと "File is in a directory that is denied by your permission settings." で拒否されることを issue #250 の triage で実測した。`~/ghq/github.com` は `additionalDirectories` に残し、書込み抑止は validated task worktree を経由してしか実装しないという既存の運用契約（`CLAUDE.md` の Worktree Entry Point 契約）に委ねる。「deny を自リポジトリ以外に限定する」案は、`additionalDirectories`/`deny` のどちらにも session の working directory を動的に除外する構文がないため技術的に不可能と判断した。「`~/ghq/github.com` を `additionalDirectories` から外し都度 `--add-dir` する」案は、cross-repo 参照のたびに確認コストが発生し issue #248 のコストと重なるため見送った。**この撤回により、`~/ghq/github.com` 配下の兄弟 repository（実装対象ではない、参照目的で開いた他 repo）への `Edit`/`Write` を実行時に拒否する技術的な制御は存在しなくなる。** 誤書込みの抑止は validated task worktree 経由の運用契約という運用レベルの対策のみに委ねることを、この cross-repository write risk として明示的に受容する（issue #250 実装 PR #251 のレビューで指摘）。`~/runtime` に対する `Edit(~/runtime/**)` deny は本追記の対象外で、そのまま維持する。

(2026-09-09 追記) 本 ADR が拡張してきた `permissions.blockReadsOutsideWorkingDirectories`（Working-Directory Read Fence）自体は [ADR-0055](0055-disable-block-reads-outside-working-directories.md) により無効化された。`additionalDirectories` と `Edit(...)` deny の記述は fence とは独立した意味を持つため（[CONTEXT.md](../../CONTEXT.md) の定義参照）そのまま有効だが、本 ADR 内で fence の挙動として記述した部分は fence が有効だった期間の実測記録として読む。

関連: [ADR-0045](0045-separate-llm-agents-and-apm-update-units.md) / [ADR-0046](0046-separate-orca-native-worktree-entry.md) / [ADR-0052](0052-resolve-to-pr-temp-artifacts-via-session-scratchpad.md) / [ADR-0054](0054-stabilize-nix-shell-tmpdir-base.md) / [ADR-0055](0055-disable-block-reads-outside-working-directories.md)
