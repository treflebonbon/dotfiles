---
type: decision
title: worktree-gc をホーム全体横断 fan-out に拡張する（明示オプトイン、既存 engine を再利用）
description: ~/.herdr/worktrees/・~/orca/workspaces/・~/ghq/ を対象に、単一repo前提の worktree-gc.sh の保護判定を再利用し、別ラッパーで横断GCを追加する。許可リスト・稼働中プロセス検出・集約承認・全体上限キャップを伴う明示オプトインモードとする。年齢閾値の既定は単体・横断とも3日。
tags: [adr, skills, worktree-gc, worktree, gc, safety]
timestamp: 2026-09-10
status: accepted
---

# worktree-gc をホーム全体横断 fan-out に拡張する（明示オプトイン、既存 engine を再利用）

`local-skills/worktree-gc/scripts/worktree-gc.sh` は `--repo` 必須の単一リポジトリ前提で、`--roots`（既定 `.claude/worktrees` / `.worktrees` / `tmp/implement-issue/worktrees`）配下の repo-local worktree のみを緊急時に手動GCする設計だった（[ADR-0004](0004-fill-mattpocock-gaps.md) で旧基盤から `local-skills/` へ移植、SessionStart自動GC hookは持ち込まない方針）。`$REPO` 外（out-of-root）のパスは診断表示のみで自動削除対象外という明示的なガードレールがある。

`grill-with-docs` セッションでの調査により、worktree の実体は repo-local だけでなく `~/.herdr/worktrees/<repo>/<worktree>` と `~/orca/workspaces/<repo>/<workspace>` にも多数存在し、いずれも `~/ghq/<host>/<org>/<repo>` 側の `.git/worktrees/` に登録された正規の git worktree であることを確認した。さらに `~/orca/workspaces/project/claude-env-preflight-le2xmoem` のように、親リポジトリ自体（`/tmp/...` 配下）が消滅した dangling worktree も1件確認され、`--repo` 前提の現行ロジックでは原理的に検出不能だった。fd/inotify 枯渇という worktree-gc 本来の課題は home 配下のこれらの worktree も含めて累積するため、GC のスコープを `~/.herdr/worktrees/`・`~/orca/workspaces/`・`~/ghq/` へ拡張する。

## Decision

2026-09-16改訂（[PR #326](https://github.com/treflebonbon/dotfiles/pull/326)）: ユーザーの明示指定により、導入時の年齢閾値7日を3日へ変更する。「本体は無改修」はfan-out導入時の判断として残し、現行では単体・ラッパー双方の `AGE_DAYS` の変更を含む。既存の保護判定と、fan-outを明示オプトインにする構成は維持する。

- **既存 skill を拡張**する（新規 skill は作らない）。`worktree-gc.sh` の既存の保護判定を再利用し、別ラッパースクリプトで横断する。
- `~/ghq/` は削除対象ではなく、横断実行（fan-out）の**列挙起点**として使う。配下の実在リポジトリ（通常clone、非worktree）ごとに、ラッパーが `worktree-gc.sh --repo <repo> --roots 既存roots,~/.herdr/worktrees/<basename>,~/orca/workspaces/<basename>` を呼び出す。
- `~/.herdr/worktrees/<repo>` と `~/orca/workspaces/<repo>` は「信頼できる既知の外部ルート」として明示的に許可リスト化し、実削除対象にする。この2パス以外の out-of-root は引き続き診断のみという既存ガードレールを維持する（汎用的な out-of-root 解禁はしない）。
- 親リポジトリが消滅した dangling worktree もスコープに含める。`.git` の `gitdir:` 参照先が存在しないディレクトリを検出するが、即時削除候補にはせず`--age-days`（単体・fan-outとも既定3日）を適用し、`git worktree move` 中などの一時的参照不能による誤検知を避ける。検出はラッパー側の別パスが `~/.herdr/worktrees/**` / `~/orca/workspaces/**` を横断スキャンして行う（`--repo` を張れる相手が無いため `worktree-gc.sh` 本体では扱えない）。
- `--locked-age-days` 未指定時は `--age-days` に追随し、既定3日となる。両閾値はCLIで上書きできる。
- 横断GCで追加する安全策はラッパー側に実装し、単体engineの既存の保護判定は維持する:
  - 実削除前に `/proc/*/cwd` 等で稼働中プロセスを検出し、該当ディレクトリを削除候補から除外する。既存の `SELF_SESSION` は自分自身のworktreeのみ保護し他の同時稼働セッション（別のHerdr/Orcaセッションが使用中のworktree）は守らないため、これを補う。
  - 複数repo + dangling分の診断結果を1つの一覧に集約し、1回の承認（AskUserQuestion）でまとめて apply する。
  - repo単位の既存 `--max-removals`（既定50、`worktree-gc.sh` 内蔵）とは別に、実行全体での上限キャップをラッパーに追加し、誤判定が複数repoへ同時波及した場合の暴走を防ぐ。
- home幅広い fan-out はデフォルト動作にはせず、明示的に選ぶ別モードとする。実装上は `worktree-gc.sh` とは別の `worktree-gc-fanout.sh` を明示的に実行した場合にのみ発動し、フラグ1つで挙動が切り替わるわけではない。単一repo緊急GCの既定の探索範囲・トリガーフレーズ（「worktree cleanup」「fd 枯渇」「Too many open files」「worktree が溜まった」）は一切変更しない。

## Considered Options

- **worktree-gc.sh 自体を複数repo対応に書き換える**: `--repo-glob` 等の新フラグで内部完結させる案。1コマンドで完結するが、SELF_SESSION・MAX_REMOVALS 等の既存ロジックを複数repo文脈で再検証する必要がありテスト済みコアの差分が大きい。見送った。
- **プロセス検出ガードを worktree-gc.sh 本体（削除直前）に組み込む**: 既存の単一repo緊急GCにも遡及的に保護が効く利点はあるが、「単体engineの既存の保護判定を維持する」という方針と矛盾し、テスト済みコアロジックへの変更が必要になる。ラッパー側限定の実装を選んだ。
- **repoごとに個別承認ループ**: repo単位で diagnose→承認→apply を繰り返す案。粒度は細かいが、リポジトリ数分の確認プロンプトが発生し「緊急時にさっと一掃したい」という用途に合わない。集約承認を選んだ。
- **home幅広いfan-outを新デフォルトにする**: 今後何も指定しなければ常に home 全体を対象にする案。利便性は高いが、現在の単一repo前提の利用者・ドキュメントが想定していない広範囲削除が不意に発生し得るため見送った。

## Consequences

- merge判定・SELF_SESSION・MAX_REMOVALS等の既存の保護判定は維持する。一方、年齢閾値の短縮により3〜6日経過したworktreeも他の保護条件を満たせば削除候補になる。単体・fan-out・danglingで2日目は保持、3日目は候補となる既定値の境界を `tests/worktree-gc-fanout.bats` で検証する。
- 一方で `~/.herdr/worktrees/` と `~/orca/workspaces/` の basename が対応する ghq リポジトリ名と一致する、という命名規約に暗黙に依存する。異なる2つのリポジトリが home 配下で同じ basename を共有した場合（ghq 発見リポジトリ同士、または ghq 外の生きた親リポジトリと ghq 発見リポジトリの間でも起こり得る）、`worktree-gc.sh` の既存の孤児判定は「自リポジトリに未登録＝孤児」としか見ないため、素朴に実装すると他リポジトリの現存 worktree を dirty/unique-commit ガード無しで誤削除しかねない（code review、および PR #281 の GitHub 連携ボットレビューで指摘）。そのためラッパー側で (a) ghq 発見リポジトリ間の basename 衝突検出、(b) `git worktree list` に基づく実所有権検証（herdr/orca ディレクトリ配下の各エントリが対象リポジトリに登録済みか dangling かを確認し、それ以外＝他の生きたリポジトリ所有と判定）の二段構えで検出し、該当 basename については herdr/orca の外部ルート付与自体を無効化して repo-local roots のみにフォールバックし、警告を出す安全策を入れている。あわせて `--ghq-root`/`--herdr-root`/`--orca-root` は取得直後に `readlink -f` で正規化し、symlink 経由の root 指定で `git worktree list` の正規化済みパスと文字列不一致になり孤児と誤認識する事故も防いでいる（同PRレビューで指摘）。
- 既知の外部ルートを許可リスト化する設計のため、将来 Herdr/Orca 以外の新しいツールが別の home 配下ディレクトリに worktree を作るようになった場合、そのツール用のパスを都度この許可リストへ追加する必要がある（自動追従はしない）。
- `worktree-gc-fanout.sh` を明示的に実行しない限り、探索範囲は単一repoのままとする。年齢閾値の3日への変更は単体にも適用される。

関連: [ADR-0004](0004-fill-mattpocock-gaps.md)（worktree-gc の local-skills 移植、緊急時手動GCのみの方針）/ `runtime/skill-harness.md`
