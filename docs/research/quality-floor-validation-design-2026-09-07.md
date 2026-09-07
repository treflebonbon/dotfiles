---
type: research
title: 品質 floor 判定の検証設計
description: Claude Code と Codex の版の採否を Nix で実評価し、採用理由の重複を整理する設計
tags: [nix, quality-floor, testing, architecture]
timestamp: 2026-09-07
---

# 品質 floor 判定の検証設計

アーキテクチャ調査の候補03を `grill-with-docs` で深掘りした記録。2026-09-07 に Q1〜Q3 の方針と Q4 の設計全体への確認を得て、設計合意を確定した。設計時の調査と合意した契約を以下に残し、実装結果は末尾に記録する。

## 変更前に確認した現状

- [ai.nix](../../private_dot_config/nix-devshell/modules/ai.nix) は Claude Code と Codex の version を `lib.versionAtLeast` で比較し、品質 floor 未満または version 欠損を assert で拒否する。Claude Code は shared overlay、Codex は同じ immutable input の direct package を使い、両者を `packages` に公開する。
- [nix-devshell.bats](../../tests/nix-devshell.bats) の該当テストは、floor の固定値、説明文、変数名、package 参照などを文字列で確認する。floor 未満の入力を与える拒否テストはない。
- 同じテストファイルには Nix の実評価を行う既存例がある。`nix flake check --no-build --all-systems` は現在の devShell を評価するが、境界値を差し替える floor 専用テストではない。
- 過去の床上げ理由が ai.nix のコメントと拒否メッセージに重複する。現行値の採用理由は [ADR-0045 の2026-09-05更新](../adr/0045-separate-llm-agents-and-apm-update-units.md#llm-agents-snapshot2026-09-05claude-read-fence-と-codex-model-再評価)、以前の判断は同 ADR と関連 ADR に記録されている。

## 対話で合意した方針

1. **Q1 — 版の採否判定を検証する。** 品質 floor 未満・version 欠損を拒否し、同値・上位版を受け入れることを Nix の実評価で確かめる。採用根拠になった CLI 機能そのものの再現は、今回の成功条件に含めない。
2. **Q2 — 採用理由の重複も今回整理する。** 拒否時にはツール名、実際の版、必要な floor、現在の採用理由の要約、修復手順を示す。歴史的な判断経緯は ADR を参照し、まだ ADR にない根拠があれば移してから重複を取り除く。
3. **Q3 — floor 自体の意図しない変更も検出する。** テスト側に承認済み floor を独立した期待値として持つ。境界値を実装の floor から自動生成せず、正当な床上げ時には実装と期待値を更新する。この独立性は、実装の誤った値へテストの期待値が自動追従することを防ぐ。

## 実装方針

既存の ai.nix の引数と `packages` 出力を検証の入口にする。テストで対象 package の version metadata を差し替え、出力側の対象 package を実際に評価する。比較関数だけを呼ぶ検証にせず、判定を迂回して package を公開する変更も検出する。

現行 floor と短い採用理由、判定、拒否診断は ai.nix 内で扱い、共通処理が必要なら非公開の関数にまとめる。比較には既存の `lib.versionAtLeast` を使う。現在の2ツールについて、独立した公開 module や全ツール用 registry を増やす必要性は認めていない。

テストは既存の Bats から実行する。境界ケースでは実際の Nix 評価と比較処理を使い、通常の配備入口については対応3 system の devShell 評価で確認する。Nix の遅延評価により、リストの長さを調べるだけでは対象 package 内の assert の検証にならない点に注意する。対象 package の識別と採用を検証し、配備リスト内の並び順を契約にしない。

### 調査時の実評価

ローカルにキャッシュされた実際の flake input と package set を使い、`nix eval --offline --impure` で現行2ツールの `drvPath` を強制評価できた。続けて Claude Code の version だけを `2.1.260` に差し替え、`2.1.261` を要求する Nix assert エラーを観測した。後者は出力をパイプで要約し Nix 自体の終了コードを保存していないため、正式な拒否テストの成功記録にはしない。

この調査で fetch／build／lock 更新は行っていない。Codex の拒否、両ツールの各境界値・欠損ケースは未実行。`deepSeq` で全 derivation 属性を再帰的に評価する試行は stack overflow になったため、検証では必要な出力属性を強制評価する。

## 受入条件

以下の版はテスト入力であり、上位版の release が実在するという主張ではない。

| 入力・変更                            | Claude Code  | Codex        | 期待結果                                                      |
| ------------------------------------- | ------------ | ------------ | ------------------------------------------------------------- |
| 承認済み floor の直前                 | 2.1.260      | 0.153.3      | 評価失敗。対象ツール・実際の版・必要な floor と修復情報を示す |
| 承認済み floor と同値                 | 2.1.261      | 0.153.4      | 評価成功。入力の対象 package を採用する                       |
| floor より上位の版                    | 2.1.262      | 0.153.5      | 評価成功。入力の対象 package を採用する                       |
| version 属性なし／null                | 共通         | 共通         | 評価失敗。version が不明であることを示す                      |
| 実装の floor だけを引き下げる         | 共通         | 共通         | 拒否されるべき直前の版が通るため、テスト失敗                  |
| 対象 package の公開時に判定を迂回する | 共通         | 共通         | 拒否ケースのテスト失敗                                        |
| 現行 snapshot の通常の配備入口        | 対応3 system | 対応3 system | default / wsl の devShell 評価成功                            |

拒否診断は必要な情報を検証し、長い履歴文の全文や内部の変数名を固定しない。差し替えた対象ツール以外は有効な入力にし、片方の拒否がもう片方の検証を隠さないようにする。文字列中心の floor テストは、この振舞いの検証へ置き換える。

## 範囲と確認の限界

対象は現行の Claude Code／Codex の品質 floor 判定と、その診断・テスト・根拠の参照経路。snapshot、floor の値、package の取得経路、対応 system、APM／Skill の更新単位はこの変更の対象に含めない。

`--no-build` の評価は CLI 機能の動作や実ビルド成功を証明しない。未キャッシュの Nix input は取得が必要になるため、評価のみであることとネットワーク不要であることも区別する。今回の判定テストは、ツール更新時に要求する [既存の検証境界](../adr/0045-separate-llm-agents-and-apm-update-units.md#verification-boundary) を代替しない。

用語は [CONTEXT.md](../../CONTEXT.md) の「品質 floor」「品質 floor 判定」に従う。

## 実装結果（2026-09-07）

ai.nix 内の非公開関数が共通の判定と診断を持ち、Claude Code と Codex の採用理由をそれぞれ短く示す。version 欠損・null は「不明」と表示する。歴史的な根拠と既存 ADR への参照は [ADR-0047](../adr/0047-test-quality-floors-through-package-outputs.md)にまとめた。

`tests/ai-quality-floor.bats` は実際の flake input と nixpkgs の比較処理を使い、`packages` 出力を通して各条件を検証する。version metadata を変えた fixture は元と異なる derivation identity を持つため、入力の取り違えも検出する。旧 floor の値・変数名・履歴文に対する grep は置き換えた。

| 検証                                                                                                             | 結果                                                                                                   |
| ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `env -u FORCE_COLOR LC_ALL=C bats --print-output-on-failure tests/ai-quality-floor.bats tests/nix-devshell.bats` | 37/37 成功。floor 専用7テスト、対応3 system の default / wsl 評価、既存 code-review-graph smoke を含む |
| 一時コピーでの変更検出                                                                                           | Claude／Codex それぞれの floor 引き下げ・判定迂回の4件すべてで、拒否ケースのテスト失敗を確認           |
| `bunx --no-install tsc --noEmit`                                                                                 | 成功                                                                                                   |
| Nixfmt、ShellCheck、shfmt、Markdown 書式、差分・ローカルリンク                                                   | 成功                                                                                                   |
| `env -u FORCE_COLOR LC_ALL=C bun run test`                                                                       | 実行中                                                                                                 |

変更検出の試行は repository の実装を変更せず、一時コピーで既存テストを実行した。full suite のログは `/tmp/quality-floor-full-tests-alxj3_xj.log`、4件の変更検出ログは `/tmp/nix-shell.7yUKd9/quality-floor-mutations-kv92986d/` に保存した一時的な証跡である。
