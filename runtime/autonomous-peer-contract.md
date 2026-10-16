---
type: concept
title: 元のアーキテクチャ候補を改善する peer 協働契約
description: 明示依頼から native peer と設計・実装・独立レビューを進め、元候補に対応する PR を届ける規範
tags: [autonomy, peer, herdr, orca, skills]
---

# 元の候補を改善する peer 協働契約

`herdr-peer-refactor` / `orca-peer-refactor` の規範。実行手順は同 skill、環境共通の worktree・公開手順は [skill-harness](skill-harness.md) が持つ。決定は [ADR-0075](../docs/adr/0075-adopt-peer-refactor-skills.md)。permission 設定そのものは変更しない。

## 開始と承認

- 人が候補改善と peer 協働を明示依頼したら、通常 session でも進める。deny 設定がないことは、この明示依頼を拒否する条件ではない。専用 auto session を選んだ場合の追加保護は skill 同梱の `local-skills/herdr-peer-refactor/references/auto-session.md` に従う。適用が未確認の設定を有効と報告しない。
- Run Scope は現在の依頼から対象候補・所有範囲・並行数・予算・承認済みの外部操作を記録したもの。承認済みの外部操作には topic branch の公開（`git-push-topic`）、Contract 付き issue の作成、draft PR の公開を明記して記録する。ready 化・merge・close・force push・secret は承認に含めない。既存の明示承認を引き継ぎ、可逆な手段は合理的に決める。権限拡大や承認していない外部書込みは推測しない。最大数 M と並行数 N を事前入力させる必須ゲートは設けない。
- 人の選んだ候補を保持し、選択を委任されたときだけ peer が選ぶ。正常経路の探索は上流の 1 回。候補の棄却を理由に探索し直さない。
- PR の作成・topic push・本文更新・ready 化・Review Round の返信と resolve は、依頼された結果と内容が確定していれば routine collaboration writes として二重確認しない。issue 作成や報告 comment も依頼範囲にある場合だけ行う。skill 自体は外部操作を承認しない。
- merge と issue の直接 close は実行しない。破壊的操作、共有環境、想定外の課金は、明示承認がある同じ対象・範囲を除き保留する。

## 元の候補と受入条件

元 artifact の内容・共通 Git dir による repo identity・提示時の source SHA を固定し、候補 ID／元名称／受入条件／非目標／所有範囲を保存する。pin の repo identity は提示元の記録を必須入力とし、実行先の cwd だけから出所を推測しない。同じ commit を持つ clone／fork も提示元と共通 Git dir が異なれば拒否する。record の fingerprint はファイル外の会話の実行記録に保持し、再確認時に必ず照合する。source SHA は後続 HEAD の ancestor であることを検査し、main 更新の取り込み後も現在 HEAD で出所を作り直さない。artifact が消失・変更、別 repo、候補の差し替えなら公開を止める。

候補の改善意図は最後まで同じものを使う。helper の共有やファイル分割が進んでも、それだけで元候補の完了とはしない。Spec レビューに固定 record を渡し、元の振舞いと AC が実装されたことを検証する。要件変更が明示承認された場合は旧 record と理由を残し、新しい run で固定する。

## 担当と並行

native worktree ごとに writer は一人。親は選定・調整・検証・報告を担い、peer は read-only。指定された Herdr / Orca の native pane / worker を使い、別 runtime の subagent をその環境での協働と呼ばない。

ファイル・行範囲の所有を宣言する。同じファイルでも別 hunk かつ挙動が独立なら並行可能。読取り依存や意味的な競合は直列にする。公開前に実差分と所有範囲を照合し、Git 結合確認と挙動の検証を区別する。新しい子は親停止後に起動しない。他者の未 commit 変更を commit・stash・破棄しない。

## 判断の分類

- **Peer Decision**: 現在の受入条件と既存 ADR・仕様の範囲内で、元に戻せる判断を peer の反例または検証で決めたもの。担当、既存 helper の再利用、挙動不変の性能改善、レビュー指摘修正を含む。モデル同一性を判断の権限にしない。
- **Held Candidate**: 新たな ADR・仕様・schema、破壊的操作、課金、共有環境について未承認の判断が必要な候補。提案と理由を報告し、実装しない。保留条件は広い許可より優先する。他の候補は進める。
- 事実の不一致を絞り、再現・型・テスト・ADR で確かめ、AC を満たす最小案を選ぶ。解けなければ保留。根拠が同意だけなら不一致扱い。無応答は同意にしない。
- Peer Decision には問い・選択肢・採用理由・peer の根拠・手段・peer の kind・対象 SHA を残す。既に明示承認された同じ判断を再質問しない。

## peer 相談と応答

peer は新しい context から始め、推奨を先に見せない。元候補・関連 ADR・コード・差分を直接読み、反例か実行した検証結果を答える。人の回答を待つ `grilling` を呼ばない別手順とし、その上流 skill の人間の回答を待つ条項は変えない。

各依頼に依頼 ID と対象 SHA を付け、応答に両方と根拠があることを検査する。idle・送信成功・古い turn の完了は今回の完了ではない。待機後も一致する成果物を読む。返信先と要件資料は親と peer の両方がアクセスできる共有 scratch に置き、原本をコピーした場合は内容を照合して元の record を保持する。peer の sandbox が返信先に書けない場合、peer は端末に `DONE <ID> <SHA> <nonce>` 行・本文・`END <ID> <nonce>` 行で答え、親が依頼 ID・対象 SHA・試行ごとの nonce・非空本文・`END` までの完全性を検査して保存する（peer の権限は広げない。途中で切れた応答、前の試行の応答、依頼文の echo は完了にしない。端末を読めない、または保存できない場合は保留する）。Claude の background session は同じ session に attach し、dashboard を完了扱いしない。状態不明の agent に依頼を再送しない。

| 上限             | 値     |
| ---------------- | ------ |
| peer 1 回の待機  | 20 分  |
| 1 候補の累積待機 | 2 時間 |
| Review Round     | 3 回   |

`blocked` は再試行せず保留。同一の失敗は 2 回で保留。個別 timeout だけでは編集停止を断定せず、停止と差分の安定を確認してから後継を起動する。確認不能や累積予算超過は保留し、pane・worktree・成果物を保持する。人への設計質問を待つ代わりに、可逆な判断は peer に、未承認の影響が広い判断は保留に送る。

## 実装・レビュー・公開

- issue は任意。必要で承認済みなら 目的／AC／非目標／検証方法／関連ファイル・入口／判断済み tradeoff の 6 項目を載せる。単一 session の小さな候補は固定記録から直接実装し、複数 session の設計だけ仕様・ticket を作る。
- `tdd` と repo の必要チェックを行い、エラー・確定・冪等性を含む振舞いを保持する。最新 base を取り込んだ後は再検証する。
- 最終 SHA に Standards と Spec の独立レビューを行う。レビュー環境の Git object 可視性を先に確かめ、失敗時は primary repo の read-only pane で同じ SHA を読む。権限拡大はしない。新しい head に古い SHA のレビュー結果を流用しない。
- PR 本文に元候補・受入条件と結果・非目標・Decisions・保留を含め、対象 issue がある場合だけ `Closes #N` を書く。topic push は `git-push-topic`。修正の公開後に Review Round の返信・resolve を行う。
- 外部書込みの失敗後は再送前に成果物を照会し、issue と報告 comment は `gh-once.sh` の run ID で重複を避ける。存在が確認不能なら再送しない。
- 最後に PR の state・head・draft を読み直し、元候補 → PR、Peer Decision、Held Candidate と理由、未実行・未確認を一件の報告にまとめる。保留の記録だけのために issue／PR を作らない。未 merge の task source から配備しない。

## 成功判定

開始後の人の操作が merge だけで、元候補の AC を満たす PR と検証結果が届けば成功。候補ゼロ・全件保留は無操作の終了として報告し、改善 PR の納品成功とは区別する。内部 agent 評価・mock CLI・Git 結合確認を、実環境の完走や同時実行の挙動検証と混同しない。
