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

- `scripts/test.sh` は `bats --jobs "$(nproc)" --no-parallelize-within-files` で、テストファイルを並列に、ファイル内のテストを直列に実行する。bats の並列実行に必要な GNU parallel は repo の devShell（`./flake.nix`）に入れる。テスト入口は `parallel` が Nix store から解決されることを install 前に確認する。
- 全件再実行の規約（`docs/conventions.md` のテスト節）は変えない。

実測（16コアの WSL2、同じ worktree。上2行の並列実行は旧 devShell の PATH へ pinned nixpkgs の GNU parallel を追加、最終行は `parallel` を含む新しい devShell の `lefthook run test`）:

| 実行方法 | 所要時間 | 結果 |
| --- | --- | --- |
| 直列（従来） | 約30分（issue #448 の retro の報告値、この比較では未計測） | — |
| `--jobs 16`（ファイル内も並列） | 約8.9分 | 3件失敗 |
| `--jobs 16 --no-parallelize-within-files` | 約8.1分（うち後片付け約1分） | 1061件中 skip 24件（既定 opt-in のみ）、失敗0件 |
| 同上（新しい devShell、採用した入口） | 約8.3分 | 1062件中 skip 24件（既定 opt-in のみ）、失敗0件 |

ファイル内も並列にすると、bats は各テストを非対話 bash の background job として起動するため、テストは SIGINT と SIGQUIT を無視した状態（`/proc/self/status` の `SigIgn: 0x2006`）で始まる。SIGINT の扱いを検証する3件（`test-entry.bats`、`gateway-lifecycle.bats`、`playwright-cli-wsl.bats`）はこのために失敗した。ファイル間だけの並列ではこの継承は起きない（`SigIgn: 0x2000`、SIGALRM のみ）。所要時間の差は小さいため、テスト側に回避を入れずにファイル内の並列化を使わない。

共有状態の確認（issue #448 の前提条件）:

- confirmed: `/tmp/codex` を使う `codex-tmp.bats`・`run-evidence.bats`・`raw-codex-integration.bats` は、その下にテストごとの `mktemp -d` を作る。ただし共有 root `/tmp/codex` の作成は「存在確認 → `mkdir`」で、`/tmp/codex` がない環境では並列のファイル同士が競合した（PR #460 のレビューで指摘、3並列の再現で600回中400回失敗）。EEXIST を許容する `mkdir` と、その後の種類・所有者の確認に変えた。`tmp/` を使う `test-status.bats`・`verify-canonical.bats` は `BATS_TEST_TMPDIR` 内の複製で動く。`managed-chrome-owner.bats`・`browser-attachments.bats` の port は fixture の文字列で、待受けはしない。ファイル間並列の2回の全件実行と、新しい devShell での INT 中断（終了コード130、bats・parallel の残存プロセスなし）を確認した。
- inferred: grep と全件実行の成功に基づくもので、全テストの共有資源を網羅的に監査したものではない。共有資源がすでに存在するホストでの成功は、初回作成時の競合を検出できない。

## Considered Options

- 変更範囲に応じたテストの選択を規約として認める: 全件再実行の保証を弱める。並列化で待ち時間が許容範囲に下がるため不要。
- 現状を維持する: 待ち時間の問題が残る。
- ファイル内も並列にし、SIGINT 系テストで既定の handler を戻す: 短縮効果は約1分にとどまり、テストごとの回避が増える。

## Consequences

- 並列実行は bats の結果順を保つため、TAP の計画・連番の検査（`scripts/test.sh`）と `scripts/test-status.sh` の集計は変わらない。
- ファイルをまたいで共有資源（固定 port、HOME 直下、`tmp/` の固定名など）を使うテストは競合しうる。bats にはファイル単位で並列を外す指定がなく、違反を自動で検知する仕組みもないため、テストは `BATS_TEST_TMPDIR` などのテストごとの領域を使うことを規約とし、レビューで確認する。
- 所要時間は最も遅いテストファイルとコア数に依存する。
- ファイル間並列でもテストは SIGALRM を無視した状態で始まるため、bash の `trap … ALRM` は効かない（bash は起動時に無視されたシグナルの trap を設定できない）。
