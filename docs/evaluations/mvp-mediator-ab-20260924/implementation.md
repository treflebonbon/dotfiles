# MVPスキル配布元の撤去実装

ユーザーが[対象範囲](decision.md)を承認したため、task worktree `/home/ubuntu/.codex/worktrees/90ae/dotfiles`、branch `prototype/evaluation-input-gate` で実装した。固定点は `36100e89e8a5f1a87a3484e0542c86e568635267`。

## 変更

- active sourceのSKILL.mdと参照1ファイルを撤去し、既存localSkills.retiredへ登録。新しい削除処理は追加していない。
- 評価CLI・本文例テストはoriginal/skillの同一hash入力へ参照変更。旧run statusと書込み再開拒否の境界を維持。
- 原資料72ファイル・採点・群対応・メトリクス・メタデータを保存。共通formatter/linterでoriginal/とこの評価直下の証拠JSONだけを除外し、固定記録の自動改変を防ぐ。
- ADRの原則を保持し、保存先リンクと配布終了を追記。v18の表調整は中止として記録。

## 検証

| 対象 | 結果 |
| --- | --- |
| 撤去・保存入力の公開境界 | 2検査は変更前に失敗。変更後は下記関連テストの一部として成功。 |
| 評価CLI・local skill配備・cleanup | `bats tests/mvp-evaluation.bats tests/local-skills.bats tests/run_onchange_before_remove-orphan-claude-skills.bats`、59/59成功。配備検査は一時HOME内のみ。 |
| 型・lint | `bunx tsc --noEmit`、変更したTS/MJSのoxlint成功。 |
| 記録保全 | 変更前1676ファイルのSHA-256一致、固定SOURCES、17旧runのverify_history/status成功。 |
| 全体テスト | `bun run test`（既存`with-env`をPATHへ追加）、761/761成功、exit 0。 |
| レビュー | Standardsは指摘なし。Specの配備懸念はHEADのarchiveから`chezmoi managed`を実行して対象外と確認。Claude再レビューも阻害事項なし。ADRのmain統合条件を明確化した。 |

秘密検査は群対応表のSHA-256をAPI keyと誤認したため、固定manifestの該当fingerprint 1件だけを`.gitleaksignore`で除外した。通常のcommit hook（format・lint・型検査・秘密検査）は成功し、commit後も原資料72ファイルのhashは一致した。`.gitleaksignore`自体がhomeの配備対象外であることをHEADのarchiveからread-onlyで確認した。

ログと保全manifestは `tmp/mvp-retirement/`。静的検査成功をスキルの効果検証とは扱わない。今回は追加LLM評価を行っていない。

## mainへの統合・配備の境界

Claudeからの指摘をread-onlyで確認した。mainの配備対象は旧版で、mainには本branchのADRと同番号の別ADR-0063が存在する。したがってprototype branch全体をmainへmergeする前提にしない。

mainへ反映する段階では、2ソースの撤去・retired登録・原則と証拠を参照する番号衝突のない判断文書という必要差分に絞って別途統合する。専用評価CLIと実験履歴をmainへ一括導入しない。このtask worktreeでの撤去完了は、mainや配備先から削除済みという意味ではない。

今回の作業は承認済みtask worktree内のみ。push・PR・merge・live sourceの変更・homeへのchezmoi applyは実施していない。home反映は受入・merge後の既存経路で行う。
