---
type: decision
title: worktree-gc をホーム全体横断 fan-out に拡張する（明示オプトイン、既存 script は不変）
description: ~/.herdr/worktrees/・~/orca/workspaces/・~/ghq/ を対象に、単一repo前提の worktree-gc.sh を無改修のまま別ラッパーで横断GCを追加する。許可リスト・稼働中プロセス検出・集約承認・全体上限キャップを伴う明示オプトインモードとし、既存の緊急GCの既定動作は変えない。
tags: [adr, skills, worktree-gc, worktree, gc, safety]
timestamp: 2026-09-10
status: accepted
---

# worktree-gc をホーム全体横断 fan-out に拡張する（明示オプトイン、既存 script は不変）

`local-skills/worktree-gc/scripts/worktree-gc.sh` は `--repo` 必須の単一リポジトリ前提で、`--roots`（既定 `.claude/worktrees` / `.worktrees` / `tmp/implement-issue/worktrees`）配下の repo-local worktree のみを緊急時に手動GCする設計だった（[ADR-0004](0004-fill-mattpocock-gaps.md) で旧基盤から `local-skills/` へ移植、SessionStart自動GC hookは持ち込まない方針）。`$REPO` 外（out-of-root）のパスは診断表示のみで自動削除対象外という明示的なガードレールがある。

`grill-with-docs` セッションでの調査により、worktree の実体は repo-local だけでなく `~/.herdr/worktrees/<repo>/<worktree>` と `~/orca/workspaces/<repo>/<workspace>` にも多数存在し、いずれも `~/ghq/<host>/<org>/<repo>` 側の `.git/worktrees/` に登録された正規の git worktree であることを確認した。さらに `~/orca/workspaces/project/claude-env-preflight-le2xmoem` のように、親リポジトリ自体（`/tmp/...` 配下）が消滅した dangling worktree も1件確認され、`--repo` 前提の現行ロジックでは原理的に検出不能だった。fd/inotify 枯渇という worktree-gc 本来の課題は home 配下のこれらの worktree も含めて累積するため、GC のスコープを `~/.herdr/worktrees/`・`~/orca/workspaces/`・`~/ghq/` へ拡張する。

## Decision

- **既存 skill を拡張**する（新規 skill は作らない）。`worktree-gc.sh` 本体は無改修のまま、別ラッパースクリプトを新設する。
- `~/ghq/` は削除対象ではなく、横断実行（fan-out）の**列挙起点**として使う。配下の実在リポジトリ（通常clone、非worktree）ごとに、ラッパーが `worktree-gc.sh --repo <repo> --roots 既存roots,~/.herdr/worktrees/<basename>,~/orca/workspaces/<basename>` を呼び出す。
- `~/.herdr/worktrees/<repo>` と `~/orca/workspaces/<repo>` は「信頼できる既知の外部ルート」として明示的に許可リスト化し、実削除対象にする。この2パス以外の out-of-root は引き続き診断のみという既存ガードレールを維持する（汎用的な out-of-root 解禁はしない）。
- 親リポジトリが消滅した dangling worktree もスコープに含める。`.git` の `gitdir:` 参照先が存在しないディレクトリを検出するが、即時削除候補にはせず既存の `--age-days`（既定7日）を適用し、`git worktree move` 中などの一時的参照不能による誤検知を避ける。検出はラッパー側の別パスが `~/.herdr/worktrees/**` / `~/orca/workspaces/**` を横断スキャンして行う（`--repo` を張れる相手が無いため `worktree-gc.sh` 本体では扱えない）。
- 安全策はすべてラッパー側にのみ実装し、`worktree-gc.sh` 本体・既存の単一repo緊急GCの挙動とリスクプロファイルは変えない:
  - 実削除前に `/proc/*/cwd` 等で稼働中プロセスを検出し、該当ディレクトリを削除候補から除外する。既存の `SELF_SESSION` は自分自身のworktreeのみ保護し他の同時稼働セッション（別のHerdr/Orcaセッションが使用中のworktree）は守らないため、これを補う。
  - 複数repo + dangling分の診断結果を1つの一覧に集約し、1回の承認（AskUserQuestion）でまとめて apply する。
  - repo単位の既存 `--max-removals`（既定50、`worktree-gc.sh` 内蔵）とは別に、実行全体での上限キャップをラッパーに追加し、誤判定が複数repoへ同時波及した場合の暴走を防ぐ。
- home幅広い fan-out はデフォルト動作にはせず、明示的に選ぶ別モードとする。実装上は `worktree-gc.sh` とは別の `worktree-gc-fanout.sh` を明示的に実行した場合にのみ発動し、フラグ1つで挙動が切り替わるわけではない。現行の単一repo緊急GCのデフォルト動作・トリガーフレーズ（「worktree cleanup」「fd 枯渇」「Too many open files」「worktree が溜まった」）は一切変更しない。

## Considered Options

- **worktree-gc.sh 自体を複数repo対応に書き換える**: `--repo-glob` 等の新フラグで内部完結させる案。1コマンドで完結するが、SELF_SESSION・MAX_REMOVALS 等の既存ロジックを複数repo文脈で再検証する必要がありテスト済みコアの差分が大きい。見送った。
- **プロセス検出ガードを worktree-gc.sh 本体（削除直前）に組み込む**: 既存の単一repo緊急GCにも遡及的に保護が効く利点はあるが、「既存scriptは不変」という方針と矛盾し、テスト済みコアロジックへの変更が必要になる。ラッパー側限定の実装を選んだ。
- **repoごとに個別承認ループ**: repo単位で diagnose→承認→apply を繰り返す案。粒度は細かいが、リポジトリ数分の確認プロンプトが発生し「緊急時にさっと一掃したい」という用途に合わない。集約承認を選んだ。
- **home幅広いfan-outを新デフォルトにする**: 今後何も指定しなければ常に home 全体を対象にする案。利便性は高いが、現在の単一repo前提の利用者・ドキュメントが想定していない広範囲削除が不意に発生し得るため見送った。

## Consequences

- `worktree-gc.sh` のテスト済みコアロジック（merge判定、SELF_SESSION、MAX_REMOVALS等）への差分がゼロのため、既存 bats テストへの影響がない。
- 一方で `~/.herdr/worktrees/` と `~/orca/workspaces/` の basename が対応する ghq リポジトリ名と一致する、という命名規約に暗黙に依存する。異なる2つの ghq リポジトリが home 配下で同じ basename を共有した場合、`worktree-gc.sh` 本体（無改修）の孤児判定は「自リポジトリに未登録＝孤児」としか見ないため、素朴に実装すると他リポジトリの現存 worktree を dirty/unique-commit ガード無しで誤削除しかねない（code review で指摘）。そのためラッパー側で basename 衝突を検出し、衝突した basename については herdr/orca の外部ルート付与自体を無効化して repo-local roots のみにフォールバックし、警告を出す安全策を入れている。
- 既知の外部ルートを許可リスト化する設計のため、将来 Herdr/Orca 以外の新しいツールが別の home 配下ディレクトリに worktree を作るようになった場合、そのツール用のパスを都度この許可リストへ追加する必要がある（自動追従はしない）。
- `worktree-gc-fanout.sh` を明示的に実行しない限り既存動作は変わらないため、本 ADR は単一repo緊急GCの既存利用フローには影響しない。

関連: [ADR-0004](0004-fill-mattpocock-gaps.md)（worktree-gc の local-skills 移植、緊急時手動GCのみの方針）/ `runtime/skill-harness.md`
