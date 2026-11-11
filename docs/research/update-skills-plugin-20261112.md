# 公開 skills plugin 0.2.10 の採用（2026-11-12）

## 要件と更新単位

ユーザーが skills の release PR #28 をマージしたことを受け、受入済みの公開版を dotfiles に採用する。変更範囲は `skills-plugin.json` の単一 pin、ADR-0082 の現行版、今回の採用記録とする。AI ツール・nixpkgs・APM の lock と第三者 skill は今回の更新対象外である。

適用する契約は [ADR-0082 の現行の固定版と所有権・runtime 導入更新の運用契約](../adr/0082-extract-local-skills-to-public-repository.md) と、[検証・追跡手順](../conventions.md) である。同じ immutable source の owner / repo / rev / tree / version / NAR hash / file count を揃え、全 Bats を clean な最終 HEAD で実行する。未 merge の task source は live 配備に使わない。

## 公開版と受入の同一性

- [release PR #28](https://github.com/treflebonbon/skills/pull/28) の受入対象 HEAD は `0fdd02cc82740c45686e730ad85ef514a23a7422`。ユーザーが merge した公開 commit と [v0.2.10](https://github.com/treflebonbon/skills/releases/tag/v0.2.10) の指す commit は `fd2a50c558288b3661e5066b94b1196453ef9269` である。
- 受入 HEAD と公開 commit の Git tree はともに `f3f3431db98cdca1a6132accef176ef288920365` で、差分はない。公開 archive の全288ファイルの内容と33ファイルの実行権限を Git blob / mode と照合した。
- GitHub archive を保護付き検証入口で取得し、展開済み source の NAR は `sha256-wCLbOs2NNdGJhGq2IlNr+NI4g1CcU+Cr8pXM9+vCtVw=`。相対 path と SHA-256 の map を canonical JSON にした SHA-256 は `0e7a99b98ebda52d48f5d451e35657c007b10a47318eb1b71d0284a377e45a3c` で、受入記録の値と一致した。
- [共有 QA 記録](https://github.com/treflebonbon/dotfiles/issues/540#issuecomment-6803126132) は3 CLI の公式導入、各11 skill の新規セッション33件と保存済み証跡の再判定33件、Python 109 pass / 4 skip、Node 41 pass、Bats 523 pass / 11 skip / 0 fail を記録している。成功は skill と同梱資源の読込に限る。依存 skill・補助 CLI の実行・業務 workflow・App/IDE・browser 実機・別 host/architecture は未確認である。
- release PR の GitHub CI は受入時に `action_required`・ジョブ0件、CodeRabbit は `SKIPPED` だった。ローカル検査と区別して記録しており、CI の成功とは扱わない。
- 前回の `/tmp/codex/accept-skills-0210.fHH9XQ` は再開時に見つからなかった。共有 QA 記録を回収し、今回の同一性確認と consumer 検証の証跡は `/tmp/codex/adopt-skills-0210.WODFpJ` に保存する。

## 採用内容と確認計画

0.2.8 → 0.2.10 で、native session 証跡の検査、PR check の参照と docstring 診断、Codex inventory の marketplace 指定を取り込む。0.2.9 から 0.2.10 への変更は Codex inventory の修正であり、公開版の [CHANGELOG](https://github.com/treflebonbon/skills/blob/fd2a50c558288b3661e5066b94b1196453ef9269/CHANGELOG.md) に対応する。

pin の旧 record 全体は Git 履歴から復元できる。0.2.8 の更新時に残した [過去の記録](update-tools-skills-20261111.md) は、その版の検証として保持する。公開版との source 同一性に加えて、以下の個別検証が成功した。独立レビューと最終 HEAD の全 Bats は続けて行う。結果の正本は各実行が生成する JSON / TAP とし、最終 commit 後の canonical 結果は PR 本文に記録する。

## dotfiles 側の個別検証

- 両 flake の `nix flake check --no-build --all-systems` は成功した。
- 新 pin の資産を使う検証環境で6 CLI の実体と版表示を照合した。plugin の改ざん検出と Nix Playwright 配線の Bats は2件成功した。ビルド済み Playwright package を要求する2件は、この個別実行では未指定のため skip であり、後続の canonical で package を準備して確認する。
- Claude Code 2.1.322 の公式導入後、管理設定と固定 payload を保った2回の再同期が成功した。結果は `/tmp/codex/claude-plugin-native.88eqe081/result.json` に保存した。通常 HOME の導入内容と元 checkout は変更していない。

## 後続の配備

PR merge 後に live source から対象限定の diff / apply、Nix cache の更新、必要な Codex 同期、両 current-state verifier を実行する。今回の記録時点では通常環境の pin は0.2.8で、live 配備・受入専用ログイン領域・worktree の削除は行っていない。旧配備の撤去は既存 gate と明示承認の範囲に従う。
