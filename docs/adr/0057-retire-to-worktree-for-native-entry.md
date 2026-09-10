---
type: decision
title: native worktree を使い to-worktree スキルを廃止する
description: worktree 作成を native 機構へ委ね、開始条件と復旧を共通指示へ集約する
tags: [adr, worktree, herdr, codex, skills]
timestamp: 2026-09-10
status: accepted
---

# native worktree を使い to-worktree スキルを廃止する

## Context

PR #298 のマージ後レビュー対応で、Herdr が作成した linked worktree は親から Git 管理情報を解決できたが、plain Codex の子セッションからは参照できなかった。`to-worktree` は所有関係の破損と実行環境からの参照不能をまとめて停止し、復旧経路を持たなかった。同型の参照不能は [Issue #294 の検証記録](../research/update-294-language-templates.md) にもある。

worktree の作成・選択は各 runtime の native 機構が担える。導入済み Codex CLI 0.154.0 の `--help` にも `--worktree` があり、raw CLI 用の独自作成手順と必須スキル呼出しを保守する意味が薄れた。一方、native 作成だけでは子の Git アクセスや秘密隔離を保証しない。

## Decision

- `to-worktree` スキルを廃止し、既存の retired local skill 同期で配備物を除去する。代替スキルは新設しない。
- Worktree Entry Point は共通契約として残し、作業開始条件・runtime ごとの起動経路・復旧を `runtime/skill-harness.md` に集約する。AGENTS / CLAUDE はそこへ案内する。
- 作成・選択は native 機構、秘密隔離は既存 adapter の責務とする。Herdr は worktree と pane、`codex-worktree` は作成済み worktree での Codex 隔離起動を担う。adapter の内側で再作成する `--worktree` は拒否する。
- owner 側でも Git 所有関係が不正なら変更を保留する。owner 側だけで検証できる場合は読み取り診断を続け、同じ worktree の正規経路で後継セッションを起動する。子の再検証後に再開し、依頼済みタスクの復旧・引継ぎには二重確認を求めない。
- 親の成功を子の書込み許可の代用にしない。既存セッションの強制終了、worktree 再作成、権限拒否の迂回、共有権限の拡大は復旧に含めない。

## Consequences

独立スキルを覚える負担と runtime 手順の重複が減る。Git 検証不能による書込み保留は維持するが、読み取り診断や正規経路の復旧まで止めない。native 作成と adapter の起動を混同すると再発するため、Herdr の対話 agent 認識・引継ぎは sandbox コマンドの検証と区別する。

この decision は [ADR-0044](0044-runtime-owned-worktree-entry-and-codex-activation.md) のスキル routing と raw CLI の作成手順、および [ADR-0046](0046-separate-orca-native-worktree-entry.md) の非 Orca での必須スキル呼出しを置き換える。Orca の native 起動・permission mode と既存 adapter の秘密隔離・所有関係検証は維持する。

## Verification

- 廃止済み `to-worktree` を4つの managed skill homeに置いた隔離 chezmoi apply を2回実行し、旧配備物の除去・再配備されないこと・APM skill の保持を確認した。
- 契約・配備・Codex config の102件は初回101成功・1失敗。追加した引数拒否テストの呼出し区切りを修正し、失敗したテストを再実行して成功。契約14件も再実行して成功した。
- 実 Herdr / Nix / Codex の既存隔離テスト2件は成功。起動拒否・公開入力だけの開発・stage / commit・hostへの返却を含む。
- 新しい `scripts/herdr-codex-isolation.py --interactive --output <未作成path>` は既存ホストログインをgatewayだけで使い、独立したダミーrepositoryで対話起動を検証する。認証ファイルへのホスト側リンクは終了時に除去し、公開入力には含めない。通常テストは従来どおりhosted modelを使わない。
- 対話試験の初回は Nix store外のCA bundle指定で登録失敗。既存の公開CA指定へ戻した次の試行はCodexの信頼確認で停止した。ダミーrepositoryだけをfixture configで事前に信頼した試行では、Codex 0.154.0の入力画面まで到達したが、Herdr 0.9.0の`agent list`は空だった。agent APIによる引継ぎ・子での検証・commitは未確認であり、sandboxテストの成功で代用しない。

対話試験の証跡は `/tmp/herdr-native-interactive-3/interactive-terminal.txt`。現行Herdrでの自動引継ぎ完了は保証しない。親はagent認識に失敗した場合、同じ起動を繰り返さずこの制約を報告し、自身で検証できるtask worktreeの作業を継続する。Herdrのsocket公開やsandboxの解除による回避は行わない。
