---
type: decision
title: 全 Bats をファイル単位で並列実行する
description: テスト入口は bats --jobs をファイル間だけに使い、全件再実行の規約は維持する
tags: [adr, testing, bats]
timestamp: 2026-10-20
status: accepted
---

# 全 Bats をファイル単位で並列実行する

全 Bats（約1060件）の直列実行には約30分かかり、検証後にソースを変更するたびに全件を再実行する規約と合わせて、PR #442 のレビュー対応で数時間の待ちが発生した（issue #448）。

## Decision

- `scripts/test.sh` は `bats --jobs "$(nproc)" --no-parallelize-within-files` で、テストファイルを並列に、ファイル内のテストを直列に実行する。bats の並列実行に必要な GNU parallel は repo の devShell（`./flake.nix`）に入れる。
- 全件再実行の規約（`docs/conventions.md` のテスト節）は変えない。

実測（16コアの WSL2、同じ worktree・devShell、confirmed）:

| 実行方法 | 所要時間 | 結果 |
| --- | --- | --- |
| 直列（従来） | 約30分（issue #448 の retro の報告値、この比較では未計測） | — |
| `--jobs 16`（ファイル内も並列） | 約8.9分 | 3件失敗 |
| `--jobs 16 --no-parallelize-within-files` | 約8.1分（うち後片付け約1分） | 1061件中 skip 24件（既定 opt-in のみ）、失敗0件 |

ファイル内も並列にすると、bats は各テストを非対話 bash の background job として起動するため、テストは SIGINT と SIGQUIT を無視した状態（`/proc/self/status` の `SigIgn: 0x2006`）で始まる。SIGINT の扱いを検証する3件（`test-entry.bats`、`gateway-lifecycle.bats`、`playwright-cli-wsl.bats`）はこのために失敗した。ファイル間だけの並列ではこの継承は起きない（`SigIgn: 0x2000`、SIGALRM のみ）。所要時間の差は小さいため、テスト側に回避を入れずにファイル内の並列化を使わない。

## Considered Options

- 変更範囲に応じたテストの選択を規約として認める: 全件再実行の保証を弱める。並列化で待ち時間が許容範囲に下がるため不要。
- 現状を維持する: 待ち時間の問題が残る。
- ファイル内も並列にし、SIGINT 系テストで既定の handler を戻す: 短縮効果は約1分にとどまり、テストごとの回避が増える。

## Consequences

- 並列実行は bats の結果順を保つため、TAP の計画・連番の検査（`scripts/test.sh`）と `scripts/test-status.sh` の集計は変わらない。
- ファイルをまたいで共有資源（固定 port、HOME 直下、`tmp/` の固定名など）を使うテストは競合しうる。bats にはファイル単位で並列を外す指定がないため、新しいテストは `BATS_TEST_TMPDIR` などのテストごとの領域を使う。
- 所要時間は最も遅いテストファイルとコア数に依存する。
