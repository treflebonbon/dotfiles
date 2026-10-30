---
title: 元候補を固定して native peer 協働を明示依頼から進める peer-refactor skill を採用する
status: accepted
date: 2026-10-16
---

# 元候補を固定して native peer 協働を明示依頼から進める peer-refactor skill を採用する

2026-10-30 追記: [ADR-0082](0082-extract-local-skills-to-public-repository.md) と #544 の実装により、規範契約・専用補助 CLI・保護設定の正本と配布は固定版の skills repository が所有する。dotfiles は pin と terminal-specific な config・導入・起動配線を維持する。元候補固定、通常の明示協働、専用 auto の起動条件と未有効時の保留も維持し、専用 auto の有効化や資格情報を自動で変更しない。以下は設計時の配布配置・検証方法を含む歴史記録で、現在の source は [runtime の契約案内](../../runtime/autonomous-peer-contract.md) から解決する。

## 背景

`improve-codebase-architecture` は deepening 候補を HTML report で提示し、選んだ候補を `grilling` で人と詰める。人が提示済みの候補を、候補別 native workspace の writer と read-only peer で設計・実装・独立レビュー・PR まで進め、人の操作を merge に限定したいことがある。

実環境で試した結果、次が分かった。

- 専用 deny 付き session、事前の Run Scope、peer による候補選択、issue を開始条件にすると、通常の Codex と Claude の background process では起動 gate で止まる。これは設定の適用が確認できないという結果であり、deny が有効なのに誤判定した証拠ではない。
- 明示依頼に基づく native Herdr の Claude writer と Codex peer の実行では、提示済みの二候補それぞれの PR が作成され、各 branch の全チェックと最終 SHA の Standards／Spec 両軸レビューが完了した。main の更新後に再検証・再レビューし、外部向けの失敗分類の変化を修正した。Git 結合は確認したが、結合後の全 runtime テストと Orca での実行は確認していない。
- 環境固有の問題がある。Orca は supervised worker から peer を起動すると `nested_worker_depth_exceeded` になる。Herdr は dashboard 経由の background session が継承する `HERDR_PANE_ID` が他 workspace の pane を指し、`agent start` は分割直後の pane で `agent_pane_busy` になり、`pane run` で起動した agent には名前が付かない。

## 決定

実行環境別の二つの local skill を採用し、規範は `runtime/autonomous-peer-contract.md` に集中する。

- `herdr-peer-refactor`: Herdr の pane / agent を使う。専用 auto の追加保護（`references/auto-session.md`、`launch-child.sh`、`plan-parallel.sh`）と `peer-request.sh` を持つ。
- `orca-peer-refactor`: Orca の worker / terminal を使う。`orca-preflight.py` を持つ。
- 名前は中身から付ける。固有の特徴は人への設計質問を peer 協働に置き換えること（`peer`）、行う作業は提示済みのアーキテクチャ候補の改善（`refactor`）で、`<環境>-peer-refactor` とする。候補から PR までの範囲は description に書く。
- 共通の `candidate-record.py`、`check-owned.sh`、`gh-once.sh`、HTML report の検査 script は両方に同一のコピーを置く。共通の SKILL.md の節（1、3〜6）も同一に保つ。配備テンプレートが各 skill ディレクトリに SKILL.md を要求するため、共通置場は作らない。同一性は `tests/local-skills.bats` が検査する。

運用規則は次のとおり。

- 通常の明示依頼から native peer 協働を開始できる。専用 auto の deny gate を普通の session の開始条件にしない。専用 auto 起動を選んだ場合の適用確認と permission 設定は維持する。
- 人の候補選択を保持する。選択を委任された場合だけ peer が選ぶ。元 artifact と提示時の repo／SHA、候補 ID／元名称／AC／非目標／所有範囲を固定し、設計・再開・公開・Spec レビューで同じ記録を使う。
- 事前の最大数・並行数の入力や issue を必須にしない。現在の承認範囲と運用予算を記録し、小さな候補は直接 TDD に入る。多 session の設計だけ仕様・ticket を作る。
- 同じモデルか別モデルかを可逆な判断の権限にしない。独立 context、コードの直接確認、反例・検証、最終 SHA の照合を採用条件にする。
- 別 hunk で挙動が独立する場合は同じファイルでも並行改善できる。所有範囲、Git 結合、挙動の競合を個別に検査する。
- 未承認の不可逆・影響の広い判断、merge、権限拡大、共有環境への変更を自律で実行しない。上流の `grilling` を fork せず、人間の回答を待つ契約をそのまま保ち、この後段では peer 相談を使う。

専用 auto session は、deny 断片（`private_dot_claude/auto-peer-deny.json`）が自分のプロセスの `--settings` に適用されていることで識別する。環境変数は使わない。allow／deny は Claude と Codex の標準機能（`permissions.deny`、rules、permission profile）だけにし、独自の検証層は持たない。Codex の peer は並行実行の前提ではなく、後から加える強化とする。専用 home・rules・read-only 資格情報（`dotfiles-peer` profile）を人が用意し、有効化するまで使わない。

## 代替案と影響

- 旧 gate（専用 deny 付き session・事前 Run Scope・peer による候補選択・issue 必須）を維持すると、明示依頼された通常の協働も専用起動の準備で止まる。deny を一律に削除すると既存の追加保護を失うため採らない。
- 一つの SKILL.md が環境別の references を選ぶ構造にすると、description から選ぶ時点で環境が分からず、環境固有の注意が互いの手順に混ざる。
- 候補記録 CLI は、artifact の変更・別 repo・候補の差し替えを機械的に検出する。記録の意味と AC の正しさは Spec レビューが検証する。元 SHA が後続 HEAD の祖先でなくなる履歴への付け替えは拒否する。
- 環境固有の注意は片方の skill に閉じ込められる一方、共通部分の変更は両方へ反映する必要がある。乖離は Bats が検出する。
- 設定の存在や親 shell の process だけでは専用 auto の適用を主張しない。内部 agent 評価・mock CLI・Git 結合確認を、実環境の完走や同時実行の挙動検証と混同しない。
- chezmoi 配備は受入れ後の live source から行う。
