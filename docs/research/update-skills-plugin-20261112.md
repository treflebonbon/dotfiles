# 公開 skills plugin 0.2.10 の採用（2026-11-12）

## 要件と更新単位

ユーザーが skills の release PR #28 をマージしたことを受け、受入済みの公開版を dotfiles に採用する。変更範囲は `skills-plugin.json` の単一 pin、ADR-0082 の現行版、今回の採用記録、および新版の公開入口へ追従する既存 consumer テストとする。AI ツール・nixpkgs・APM の lock と第三者 skill は今回の更新対象外である。

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

pin の旧 record 全体は Git 履歴から復元できる。0.2.8 の更新時に残した [過去の記録](update-tools-skills-20261111.md) は、その版の検証として保持する。公開版との source 同一性に加えて、以下の個別検証が成功した。独立レビューは下記の結果を得た。最終 HEAD の全 Bats は公開前 gate として続けて行う。結果の正本は各実行が生成する JSON / TAP とし、最終 commit 後の canonical 結果は PR 本文に記録する。

## dotfiles 側の個別検証

- 両 flake の `nix flake check --no-build --all-systems` は成功した。
- 新 pin の資産を使う検証環境で6 CLI の実体と版表示を照合した。plugin の改ざん検出と Nix Playwright 配線の Bats は2件成功した。ビルド済み Playwright package を要求する2件は、この個別実行では未指定のため skip であり、後続の canonical で package を準備して確認する。
- Claude Code 2.1.322 の公式導入後、管理設定と固定 payload を保った2回の再同期が成功した。結果は `/tmp/codex/claude-plugin-native.88eqe081/result.json` に保存した。通常 HOME の導入内容と元 checkout は変更していない。

## 独立レビューと公開前 gate

実装 commit `485283ade043d54957100fb7ce15784b6cb6cfd9` を、固定点 `563758ae834c854f512938b816bd9658ebd46e17` から Standards / Spec の2軸で確認した。Standards は指摘0件。Spec は差分の不整合・scope creep の指摘はなく、最終 HEAD の全 Bats が未完了であることを公開前 gate として1件指摘した。

この記録を含む最終 commit を clean にした後、元の standalone Bun template の1件を通常の Bats 経路で確認し、同じ HEAD で `python3 scripts/run-canonical.py --shell wsl --no-codex-build` を実行する。生成された `result.json` の終了コード・失敗件数と前後記録を照合し、Spec の gate を完了してから公開する。canonical 後は結果の追記だけの source 変更を行わず、結果を PR 本文と共有 QA に記録する。

## 初回 canonical が検出した consumer テストの不整合

HEAD `6fa8fe35fca9ed890a9b5f536b3e8707e64ca64b` で元の standalone Bun template の1件は通常経路で成功した。同じ HEAD の初回 canonical は214.43秒、835 pass / 25 skip / 1 fail、終了コード1だった。失敗は `pinned skills package exposes the Domain Modeling Studio TypeScript consumer assets` の1件で、旧 `scripts/extract-typescript.py` の存在確認だった。分離した stderr と初回 JSON / TAP は `/tmp/codex/adopt-skills-0210.WODFpJ/canonical-initial` と `bun-single` に保持している。

失敗した1件を同じ Nix 環境の単独 Bats で2回再現した。Nix が実際に使う source の全288ファイルは公開版と一致し、旧 Python 入口は存在せず、TypeScript 入口と参照文書が一致していた。公開版が案内する `bun run --config=/dev/null --no-env-file .../extract-typescript.ts --help` は終了コード0だった。これにより、古い期待値を原因と確認し、別 source の参照と公開 package の資産欠損を除外した。

既存テストの資産名を `.ts` にし、呼出しを上の公式 Bun 手順へ変更した。修正後の同じ単独 Bats は1件成功・skipなし・終了コード0を確認した。資産の存在確認と正常終了の assertion は維持し、互換用の旧入口や skip は追加しない。この修正の独立レビューを行い、記録を含む clean な最終 HEAD で元の Bun 1件・全 canonical を改めて実行する。初回の失敗は成功記録へ置き換えず、最終結果とは分ける。

修正 commit `b563b8957a6b8bbee8c7902a8cf79d1e9469d719` を含む4ファイルの差分も独立に再レビューした。Standards は指摘0件、Spec は機能上の要件漏れ・scope creep・実装誤りを認めず、同じ「最終 clean HEAD の全 canonical 完了」の公開前 gate 1件だけが残ると確認した。この結果を含む記録を commit してから最終検証へ進む。

## 後続の配備

PR merge 後に live source から対象限定の diff / apply、Nix cache の更新、必要な Codex 同期、両 current-state verifier を実行する。今回の記録時点では通常環境の pin は0.2.8で、live 配備・受入専用ログイン領域・worktree の削除は行っていない。旧配備の撤去は既存 gate と明示承認の範囲に従う。
