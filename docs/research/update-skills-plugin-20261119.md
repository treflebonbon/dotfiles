# 公開 skills plugin 0.4.1 の採用（2026-11-19）

## 要件と更新単位

[treflebonbon/skills#95](https://github.com/treflebonbon/skills/issues/95)（親 #89、判断は skills の ADR-0004）と [dotfiles#604](https://github.com/treflebonbon/dotfiles/issues/604)（親 #601）は同じ pin を更新するため、v0.4.1 の採用として1つの PR にまとめる。peer 規範（`autonomous-peer-contract.md` など）の撤去は #96、GLOSSARY と ADR-0089 は別担当で、この変更に含めない。

0.3.0 は配布 source に固定 Nix store path（`docs/bun-process-namespace-proof.md`）が含まれ、`fetchFromGitHub` が失敗したため採用できなかった（[skills#99](https://github.com/treflebonbon/skills/issues/99)）。0.4.1（[#101](https://github.com/treflebonbon/skills/pull/101)）で除去された。

## 公開版

- tag v0.4.1 の commit は `0f3ebdd87f32bff94c19f42d81f4721ac9b26ed8`、tree は `882353406e0361f33f15ef6822bd7710574ca6c2`、342 files。NAR は `sha256-OpYXJ0HLNqpZ5ctjOazd6gXhdAnAsf+k4t+MUpR73Wc=`。
- 公開側の受入（tag と release commit の tree・NAR の一致、store path 0 件、version 表記）は引き継ぎ時の報告による。dotfiles 側では固定 nixpkgs の `fetchFromGitHub` が成功することを bats で確認する。

## 0.3.0 → 0.4.1 の採用内容

- 0.3.0: peer-refactor skill と peer 専用基盤を撤去。`orca-worker-readiness` を共用 CLI へ切り出した。
- 0.4.0: `pr-screenshots` のブラウザ添付（`browser-attachments`・`pr-evidence`）を撤去し、`gh pr comment --attach` のコメント添付 `scripts/pr-screenshots-comment.mjs` へ移行した。
- 0.4.1: 配布 source から固定 store path を除去した。

## dotfiles 側の変更

- pin、ADR-0082 の現行版と `pr-screenshots` の行を 0.4.1 へ更新した。
- `playwright-cli.nix` から `browser-attachments` の entrypoint と wrapper を削除した。撮影・Dogfood が使う `playwright-cli`・`managed-chrome-owner`・Windows script は維持する。
- `runtime/skill-harness.md`: Orca worktree 準備確認を `~/runtime` の要点と共用 CLI へ、`orca-send` の本文制約を `~/runtime` へ移した。`improve-codebase-architecture` の HTML report は実ブラウザ確認だけにした。PR 添付は、本文を標準 `gh pr edit --attach`、コメントを `pr-screenshots` へ揃えた。request ID による重複防止はコメント用の責務とし、本文添付には適用しないと明記した。
- 旧版で保存した profile・所有権データ・画像・receipt は削除せず、dotfiles に公開 payload のコピーも作らない。

## 検証と未確認範囲

結果は PR 本文に記録する。実 GitHub への添付投稿、実機 WSL2 での撮影、公式 runtime（Claude Code・Codex・Antigravity CLI）の実導入は、この worktree では fixture・Bats の範囲でのみ確認し、実機は未確認として扱う。
