---
type: decision
title: Codex 0.159.1 と GPT-6.1 Sol を採用する
description: Codex の bundled catalog と managed model を GPT-6.1 Sol に揃える
tags: [adr, codex, nix, model]
timestamp: 2026-09-30
status: accepted
---

# Codex 0.159.1 と GPT-6.1 Sol を採用する

ユーザーの `/implement GPT-6.1 Sol を利用するために codex 更新` に基づく。OpenAI の[モデル資料](https://developers.openai.com/api/docs/models/gpt-6.1-sol)はモデル ID `gpt-6.1-sol` と `high` effort を明記し、[Codex 0.159.1 release](https://github.com/openai/codex/releases/tag/rust-v0.159.1) は同モデルを bundled catalog の既定へ追加した。

## Decision

- `llm-agents.nix` の immutable revision を `a621acfa43a25731694a8ef64fcbd5a00241e085` から `96f40e1e510d8cc7e895baae27f9cf37d2d94882` に進める。後者は [upstream PR #10071](https://github.com/numtide/llm-agents.nix/pull/10071) の Codex 0.159.1 更新コミット。2026-09-30 時点で PR は未 merge なので、main へ取り込まれた後に次回の snapshot 更新で upstream main の pin に戻す。
- Codex quality floor を `0.159.1` に上げ、managed main model と親 agent 指示を `gpt-6.1-sol` / `high` にする。subagent の `gpt-6-luna` / `xhigh` は従来どおり。
- parent の未コミット変更と live chezmoi source を保全し、task worktree の source だけを変更する。配備は受入後に live source から行う。

## Verification

`llm-agents.nix` の旧・新 revision を比較すると、devShell が選ぶ Claude Code 2.1.284、Copilot CLI 1.0.89、Antigravity CLI 1.2.13 は同じ版で、Codex のみ 0.158.0 から 0.159.1 へ変わる。Nix の 3 system 評価、Linux package 取得と CLI 起動、managed config の strict parse、Bats と型チェックを実行する。実アカウントで Codex 0.159.1 から `gpt-6.1-sol` / `high` を指定した短いリクエストは `GPT_61_HIGH_OK` を返した。

全 Bats 756 件は exit 1。確認した失敗は、既存の dotenv 権限テストで `bwrap` が `Bad file descriptor` を返す件と、テストが要求する Nix store 版 `with-env` が通常の `PATH` にない件。後者は正式な `.#with-env` 出力を `PATH` に加えた単独再実行で通過した。変更対象の quality floor、Codex managed config、Nix snapshot の関連テストと型チェックは通過した。

## 2026-09-30: Linux sandbox の FD 再利用を修正する

複数の denied file があると、Codex は同じ `/dev/null` の FD を複数の `--ro-bind-data` に渡す。bubblewrap は各 mount 後に FD を閉じるため、0.12.0 では2件目が `Bad file descriptor` で失敗する（[upstream issue #43929](https://github.com/openai/codex/issues/43929)）。0.158.0 と 0.159.1 の両方で再現し、公開ファイル1件と denied file 2件だけの fixture でも失敗を確認した。

Linux の Codex package に、共有 helper が各 mask に独立した FD を保持するパッチを適用する。snapshot、source、Cargo dependencies、version、quality floor は維持し、[sandbox escape 修正](https://github.com/containers/bubblewrap/security/advisories/GHSA-pxhw-h44j-8pfx)を含む bubblewrap 0.12.0 と既存の deny を使う。この間は Linux の Codex が source build となる。upstream の修正版で公開ファイルの read と複数 denied file の拒否を確認したら、ローカルパッチを削除して direct package の cache 経路へ戻す。

修正版の x86_64-linux package を実際に build し、CLI が `0.159.1` を返すこと、最小再現が3回とも成功することを確認した。追加した実 OS 回帰テストは修正前に2件目の mask で失敗し、修正後は公開ファイルの read と両 denied file の拒否に成功した。元の dotenv 権限テストも通過した。関連35テスト、3 system の Nix 評価、[ADR-0071 の更新ゲート](0071-adopt-mattpocock-standard-workflow.md)全体も成功した。ARM Linux／Darwin は評価のみで、実行検証は x86_64-linux で行った。
