---
type: decision
title: blockReadsOutsideWorkingDirectories を無効化し、機密パスの deny を拡充する
description: ADR-0045 が有効化した Working-Directory Read Fence を無効化する。承認プロンプト頻発による開発効率低下を優先し、credential 系 deny パターンの拡充で埋め合わせる。
tags: [adr, claude-code, permissions, working-directories]
timestamp: 2026-09-09
status: accepted
---

# blockReadsOutsideWorkingDirectories を無効化し、機密パスの deny を拡充する

[ADR-0045](0045-separate-llm-agents-and-apm-update-units.md)（2026-09-05〜06）は Working-Directory Read Fence（[CONTEXT.md](../../CONTEXT.md)）を意図的に有効化した。その理由は「機密ファイルを `deny` する既存ルールに加えて、外部ファイルの accidental read を境界化する」ことであり、credential 保護に留まらない広いスコープの防御だった。[ADR-0048](0048-extend-additional-directories-with-edit-deny-readonly.md) の 2026-09-08 追記（issue #248）はこの fence が、静的解析できない Bash コマンド（`$VAR` のような simple expansion、command substitution、heredoc 経由 interpreter、`sed`/`awk`/`python3 -c` 等の programmable reader）に対しても working directory の内外を問わず human confirmation を要求することを実測済みだった。

2026-09-09 の `grill-with-docs` セッションで、この既知の挙動が実際の開発体験として承認プロンプトの頻発を引き起こしていることを確認した。`additionalDirectories`（[ADR-0048](0048-extend-additional-directories-with-edit-deny-readonly.md)）による部分的な緩和は既に実施済みだったが、trigger がパス非依存（unanalyzable なシェル構文そのもの）であるため効果がなかった。本セッションで `~/runtime` 配下（`additionalDirectories` に含まれる既知パス）への `simple_expansion` を含む単純なコマンド（`D=$HOME/runtime; ls "$D"`）が繰り返しプロンプトを発生させることをライブで再現し、project-local `blockReadsOutsideWorkingDirectories: false` に切り替えると同じコマンドが無音で成功することを実機検証した。

## Decision

`private_dot_claude/settings.json.tmpl` の `permissions.blockReadsOutsideWorkingDirectories` を `false` にする。あわせて `permissions.deny` に以下を追加し、credential 系ファイルの保護を明示的に拡充する:

- `Read(~/.kube/**)`
- `Read(~/.docker/config.json)`
- `Read(~/.git-credentials)`
- `Read(~/.config/gh/hosts.yml)`
- `Read(~/.gnupg/**)`

`~/.npmrc` は追加しない。レジストリ設定確認など、トークン行以外の正当な読み取り用途があり、`.npmrc` 自体を読む以外に確認する手段がないため。

`additionalDirectories` の内容、`defaultMode: "auto"`、既存の `~/.ssh/**`・`~/.aws/**`・`~/.config/gcloud/**`・`**/.env*`・`*.pem`・`*.key`・`credentials*.json` 等の deny パターンは変更しない。

## Considered Options

- **Claude Code のバージョンアップ**: `claude --version` は 2.1.263（調査時点の最新は 2.1.266）。公式 CHANGELOG を確認したところ、`blockReadsOutsideWorkingDirectories` の導入（2.1.257）とバグ修正（2.1.260）はいずれも現行バージョンより古く、2.1.263〜2.1.266 間に関連する変更は見つからなかった。バージョンアップでは解決しないと判断した。
- **`additionalDirectories` のさらなる拡張のみで対処する**: [ADR-0048](0048-extend-additional-directories-with-edit-deny-readonly.md) 時点で既に実施済みだが、issue #248 の実測どおり trigger はパスの内外に依存しないため、追加拡張では unanalyzable なシェル構文由来のプロンプトを減らせない。見送った。
- **fence を維持し、静的解析可能なシェル構文だけを使う運用ルールを徹底する**: 変数展開・パイプ・command substitution は日常的なシェル操作の基本要素であり、これを避ける運用は非現実的と判断し見送った。
- **試験的に一定期間だけ無効化し、様子を見てから恒久化するか判断する**: 恒久的な決定ではなく段階導入も検討したが、`deny` リストの拡充で credential 系のリスクは独立して塞げているため、試験導入を挟む必要はないと判断した。

## Consequences

**ADR-0045 が意図した「credential 以外も含む偶発的な外部ファイル読み取り防止」という広いスコープの保護を失う。** `~/.ssh`・`~/.aws` 等の credential 系ファイルは本 ADR で拡充した `deny` パターンにより `blockReadsOutsideWorkingDirectories` と独立して引き続きブロックされるが、それ以外の任意の外部ファイル（他リポジトリの非公開コード、個人的なメモ、業務文書など、`deny` パターンに載っていないもの）への accidental read を防ぐ仕組みは無くなる。この dotfiles は個人開発機での利用を前提とし、全リポジトリで同様の摩擦が発生していたことから、開発効率の回復をこのリスクより優先した。

`~/.npmrc` は意図的に deny 対象から外したため、`_authToken` を含む場合はその行が読み取り可能になる。

Working-Directory Read Fence（[CONTEXT.md](../../CONTEXT.md)）は本 ADR により無効化され、現在この dotfiles では機能しない。[ADR-0045](0045-separate-llm-agents-and-apm-update-units.md) と [ADR-0048](0048-extend-additional-directories-with-edit-deny-readonly.md) の記述は、fence が有効だった期間の設計判断・実測記録として残す。

関連: [ADR-0045](0045-separate-llm-agents-and-apm-update-units.md) / [ADR-0048](0048-extend-additional-directories-with-edit-deny-readonly.md)
