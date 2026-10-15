---
type: concept
title: Codexの取得・配布方針設計
description: 自前ビルドを避ける範囲、対象環境、既存の品質条件を確認する設計記録
tags: [codex, nix, distribution, design]
---

# Codexの取得・配布方針設計

## 目的と現在の段階

元の依頼「ツールとスキルの更新。codexは自前ビルドしない方法を検討」の取得経路に戻り、Codexを自前ビルドせず利用するための条件を詰める。canonical検証のPR #410はmerge済みで、ユーザーから配備済みと報告されている。本設計は別の更新単位として扱う。

2026-10-15の `$grill-with-docs` による検討は完了した。ユーザーの `Q1:A Q2:A Q3:A` により、既存配布だけを利用し、WSL2／x86_64 Linuxを先行対象とする条件で、「適合配布待ち・現行構成維持」を結論とした。今回の採用変更はない。未キャッシュLinuxでの自前ビルド不要は未達として残す。

## 文書確定時の変更範囲と適用判断

今回の `$implement` 開始時点の予定差分は、`GLOSSARY.md` への「自前ビルド不要」の定義追加と、本記録への合意・根拠・残制限・再開条件の確定の2文書である。

適用する判断は、[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md)の「llm-agents snapshot の更新（2026-10-13、PR分割）」にある、現行の品質floor・FD patch適用終了・cleanup patch継続・未キャッシュLinuxの制限を維持する部分と、[ADR-0047](../adr/0047-test-quality-floors-through-package-outputs.md)の、品質floorをpackage出力で判定し根拠機能の検証と区別する判断である。取得経路や版を変更する採用gateは今回の実施対象に含めない。

## 作業場所

- Orca native task worktree: `/home/ubuntu/orca/workspaces/dotfiles/codex-binary-distribution-20261015`
- branch: `dev/codex-binary-distribution-20261015`
- 開始時base: `5f15e5e3b6bc2d211a63ff3c3ba1d6a078127ea2`（main／PR #410採用後）
- 検証再開時base: `ee8a22017ebbb0089da1399b64929fa3a100d4aa`（main／gateway起動通知のPR #412採用後）
- worktree固有Git dirとcommon dirの分離、physical root、branch、HEAD、開始時cleanを確認した。live sourceは読み取りだけに使う。

## 今回確認した事実

### 現行sourceと受入条件

- sourceの `llm-agents` pinは `998b9f267c671917a0b9a88b01e287c3168f3c24`、採用するCodexは0.162.1、品質floorは0.162.0。floorと採用版は別の概念で、floor判定だけでは根拠機能の検証を代替しない（[ai.nix](../../private_dot_config/nix-devshell/modules/ai.nix)、[ADR-0047](../adr/0047-test-quality-floors-through-package-outputs.md)）。
- 汎用devShellの対応systemは `x86_64-linux`、`aarch64-linux`、`aarch64-darwin`。Linuxはcleanup patchを追加し、source build時の `NIX_BUILD_CORES=1` を設定する。Darwinは基底packageを使う（[flake](../../private_dot_config/nix-devshell/flake.nix)、[cleanup patch](../../private_dot_config/nix-devshell/packages/codex-sandbox-cleanup.patch)）。
- cleanup回帰は公開CLIの `codex sandbox` を使い、通常終了、SIGKILL、並行終了、SIGTERM無視、既存の空／非空 `.env` の保持、stdout／stderr・終了コード、TTY入力を検査する（[tests](../../tests/codex-sandbox-cleanup.bats)）。
- 複数denied fileと公開fileのreadを確かめるFD回帰も残っている。旧FD patchは現moduleから適用していない（[codex-config.bats](../../tests/codex-config.bats)、[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md)）。

### 配布物とローカル成果物

- 2026-10-15に許可済みの `gh repo view openai/codex --json nameWithOwner,latestRelease` で確認した `latestRelease` は、[0.162.1／rust-v0.162.1](https://github.com/openai/codex/releases/tag/rust-v0.162.1)、公開日時は2026-10-09 19:44:51 UTCだった。新しいstable修正版を確認できたわけではない。
- [OpenAI公式CLIガイド](https://learn.chatgpt.com/docs/codex/cli)はmacOS／Linux用standalone installerを案内する。配布経路があることと、このrepoのcleanup／FD受入条件を満たすことは区別する。installer自体は実行していない。
- ローカルにはパッチ付きoutput `/nix/store/lhczzl4166l2aps8bcl1zi9kbqbbqy3w-codex-0.162.1` がある。`nix path-info --json` で登録を確認した。narHashは `sha256-HO5l1OgY+g344/2jhcdILbCKgkoTnErQJkNz1JrOlFs=`、signaturesは空だった。これだけでは別端末で同じoutputを第三者cacheから取得できることを示さない。
- 調査コマンドのambient PATHはCodex 0.161.0を指していた。これをsource-selectedの採用版や検証済みoutputとは扱わない。

## 過去の参考証拠

[2026-10-13の取得経路調査](tool-snapshot-pr-20261013.md#codexの取得経路と残制限)では、公式0.162.1 musl packageとパッチなしcache outputはcleanup 8件中3件で失敗した。パッチ付き版を維持し、未キャッシュLinuxではsource buildが必要という制限を記録している。

これは過去の試験結果であり、今回の再実行結果ではない。同じ版名であっても、今回の公式配布物のbytes一致やcleanupの成否を再確認したことにはしない。今回確認した既存ローカルoutputの存在も、新規環境での取得可能性とは別に扱う。

## 第1ラウンド回答後の限定調査

### 過去の実物と原始ログ

統合branch `dev/update-tools-skills-codex-binary-20261013`（`864880c0498d9b274c506183a2087f0863d674f7`）と元branch `chore/update-tools-skills-20261011`（`38a4cac5fd55ece548a1778af6c40aa6f2cdfd34`）のworktreeが現存する。比較結果は統合branchの `docs/research/update-tools-skills-20261011.md` と `tmp/codex-binary-20261013/` に残っていることを読み取りで確認した。

| 確認した既存成果物 | 過去のcleanup検証 | FD回帰 | 今回の扱い |
| --- | --- | --- | --- |
| 公式0.162.1 x86_64 musl archive | 5/8成功、SIGKILL・並行終了・SIGTERM無視で失敗 | 成功 | 切替候補として採用しない |
| Numtideのパッチなし0.162.1 output | 同じ3ケースで失敗 | 成功 | cache案内があっても品質条件を代替しない |
| 現行パッチ付き0.162.1 output | cleanup 8件を含む既存49件が成功 | 成功 | 現端末にあるが、第三者から取得できる根拠ではない |

公式archiveのSHA-256は `a676f5722aae0d86cbe3764332f08eab1fdd89dc0a300b3ad4ffbf48611fa3e3`、現存する展開済み `official/bin/codex` のSHA-256は `628e35487d888a28f0427fc37501da529dd3d81fcbad7a2c3421c1e8670d92e1`。パッチなしNumtide outputは `/nix/store/8h77jlpnipnray5n0f8pkqsd9ajgm53x-codex-0.162.1`。この比較では新たなbuild・回帰試験を行わず、現存する成果物と過去の原始ログを照合した。

### 既存の第三者取得元

- [Numtideのbinary cache案内](https://github.com/numtide/llm-agents.nix#binary-cache)は、Codexをsource packageとして掲載し、CI成果物を `cache.numtide.com` へ公開すると説明する。確認した `packages/codex/hashes.json` は0.162.1だった。ただし、必要なcleanup修正を含むpackageと、そのoutputがcacheから取得できることは確認できていない。
- NixpkgsにもCodex packageとbinary cacheの案内があるが、今回の調査では現行packageの版・同等cleanup修正・該当outputの取得可能性を確定できなかった。
- 調査は公式配布と上記2取得元に限定した。GitHub code searchが途中でHTTP 403 rate limitとなり、追加検索を停止した。別名の同等実装や、他の第三者配布が存在しないと結論したものではない。

今回確認できた範囲では、Q1・Q2と現在の品質条件を満たす切替候補は成立していない。合意どおり切替を保留し、現行Nix構成には未キャッシュLinuxでsource buildが必要になる制限が残る。取得経路の保留と、ビルドを自動で抑止する実装は区別する。

## 第1ラウンド：合意済み

### Q1 — 「自前ビルドしない」の範囲

- 推奨案: 公式または既存の第三者配布を使い、利用端末と自分のCIの双方でビルドしない。品質条件に適合する配布物がなければ切替を保留する。
- 別案: 利用端末でのビルドだけを避け、自分のCIなどでパッチ付き成果物を事前ビルドして配布する運用を許容する。
- 別案: 現在の端末の既存cacheを使えればよく、新規環境でのビルドは許容する。
- 回答: **A（推奨案）**。利用端末・自分のCIの双方でビルドしない。適合する既存配布物がない場合は切替を保留する。

### Q2 — 対象環境

- 推奨案: WSL2／x86_64 Linuxを先行対象とし、現在の実環境で取得・起動・回帰を検証する。
- 別案: dotfilesの全対応systemで同時に成立させる。
- 別案: x86_64／ARMのLinuxを対象にする。
- 回答: **A（推奨案）**。WSL2／x86_64 Linuxを先行対象とする。ARM Linux／Darwinへの同時展開は今回の採用範囲に含めない。

## 第2ラウンド：合意済み

### Q3 — 保留中の扱いと今回の完了境界

- 推奨案: 「適合配布待ち・現行構成維持」を採否の結論として記録し、今回の検討を閉じる。未キャッシュLinuxでの自前ビルド不要は未達として残す。
- 別案: 未キャッシュ時の自動ビルドを抑止する設計も、追加要件として続ける。
- 回答: **A（推奨案）**。「適合配布待ち・現行構成維持」で今回の検討を閉じる。未キャッシュLinuxでのsource buildを抑止する実装は追加しない。

## 結論と再開条件

現行のCodex 0.162.1、Linux cleanup patch、品質floor 0.162.0、取得経路を維持する。利用端末・自分のCIでの新たなbuild、共有cacheの新設、品質条件の引下げは今回の対応へ追加しない。今回は採否の検討を完了したものであり、自前ビルド不要を実現したものではない。

公式または既存の第三者から、必要なcleanup修正を含む安定版の成果物が得られる根拠が確認できた時点で、取得経路の検討を再開する。候補の再評価では、WSL2／x86_64 Linuxで次を確認する。

1. 配布元、固定する版・成果物、検証可能なhashと取得経路を対応付ける。以前のローカルoutputを使えただけで、未キャッシュ環境での取得可能性を成立扱いにしない。
2. 自分の端末・CIでsource buildせず取得した同じ候補で、品質floor、cleanup全8件と複数denied fileのFD回帰を確認する。過去の成功件数を候補の結果へ転記しない。
3. 候補が成立した場合に、取得できないときの挙動、更新手順、関連callerと検証範囲を改めて詰める。

これは将来の再評価条件であり、自動監視・定期調査・実装の開始を意味しない。

Q1で意味が確定した「自前ビルド不要」を `GLOSSARY.md` へ記録した。取得経路を変更せず既存のADR-0045の判断を維持するため、新規ADRは追加しない。

## 取得経路調査の検証境界

取得経路の調査は、source・過去記録・公式資料・既存ローカルoutputの読み取りまで。調査中に新規build、installer、現行公式配布物の回帰試験、ARM／Darwin実機、別端末でのcache取得、秘密値・認証値の取得は実施していない。本文に記録した過去のテスト件数と、文書確定後のbranch検証は区別する。
