---
type: decision
title: Herdr App の標準機能を基準に TUI から移行する
description: Windows App と WSL2 内 core の公式配布を使い、独自連携を減らして TUI への依存を外す
tags: [adr, herdr, runtime, migration]
timestamp: 2026-11-11
status: accepted
---

# Herdr App の標準機能を基準に TUI から移行する

Herdr TUI から Herdr App へ日常利用を移す。既存の独自連携をそのまま移植する前提は置かず、App の標準機能を基準に必要性を見直す。必要な動作を App で確認した後、日常利用と dotfiles の管理対象から TUI への依存を外す。

## 合意した構成と所有範囲

- 操作には Windows 版 App を使う。App が使う Windows 側 local core に加え、WSL2 側の core を接続先として登録し、Nix・リポジトリ・エージェントは WSL2 を中心に置く。
- App と core は公式の完成済みバイナリと公式の導入・更新経路を使う。dotfiles に本体の独自 packaging や固定版同期を追加しない。App と Windows 側 local core、WSL2 側 remote core の更新を区別する。
- dotfiles は接続・安全な agent 起動・更新・切替の手順を管理する。レイアウト・テーマ・キー設定などは App 側で管理し、App の設定一式を chezmoi で固定・上書きしない。独自 mod や画面の作り込みは今回の範囲外とする。
- 実機での受入対象は Windows＋WSL2。通常 Linux・macOS の App 導入と実機検証は今回の範囲外とし、共通 Nix 設定など既存構成への影響は確認する。

## 既存連携の扱い

- 新規 worktree への `.env` 自動コピーは必須にしない。既存のコピー用 plugin は移植せず、必要なときに環境を準備する。秘密値を扱う既存の境界は維持する。
- エージェント同士の協働は App/core の標準連携へ移す。レビュー役の起動・依頼・結果受取りは確認するが、`herdr-ask` や `herdr-peer-refactor` と同じ呼び方の維持は求めない。
- Codex の既存の隔離と起動経路は維持する。実装役は `codex-worktree`、必要な読み取り専用レビュー役は `codex-reviewer` を使う。`hc` による agent の起動・制御は隔離の外にいる親が担当し、隔離内へ core の制御 socket やホストの権限を追加しない。
- 公開 skills 側の App 対応改修は今回の要件に含めない。公開 skill と dotfiles の所有範囲は [ADR-0082](0082-extract-local-skills-to-public-repository.md) に従う。公開 plugin 全体や無関係な同梱 skill を撤去対象に広げず、TUI 用 skill が App 対応済みであるかのように案内しない。
- TUI 用 Nix package の供給、copy-env plugin の登録、旧コマンド・APM skill・設定・手順・専用テストや検証 script への依存を棚卸しし、移行後に不要なものを整理する。Codex の隔離など引き続き必要な保証は、TUI 専用の検証を廃止するだけで失わず、新構成で確認する。

## 切替と復旧

検証中の併用を認め、必要な動作を App で確認するまで TUI の利用を止める前提にしない。TUI 内の作業は切替前に人が終えるか保存し、App では新規開始または必要な既存リポジトリ・worktree を開く。自動のセッション移送は作らず、稼働中の agent を自動停止しない。

TUI の状態・履歴・既存 worktree は保持する。導入や接続の検証が失敗したときは切替未完了として扱う。TUI 依存の整理前（検証・併用中）は TUI が残っているため、再導入せず旧状態で利用を再開する。

整理後に復旧が必要になった場合は、validated task worktree で復旧変更を作り、受入後に live source から対象を限定して配備する。整理前と同じ固定版の TUI 供給、同梱 skill の固定版、copy-env plugin の source と登録、関連する許可設定を整合した状態へ戻し、保持した旧状態を確認して利用を再開する。整理 commit の revert はこの結果を得る手段の一つで、Herdr 公式の手順ではない。無関係な AI ツールの版や設定を巻き戻さず、元の固定版を供給できない場合は別の版を無断で代用しない。データの削除、branch の破壊的な巻戻し、無関係な設定変更は含めない。

実装は validated task worktree で行う。未 merge の task source から `chezmoi apply` しない。受入後の live source から、変更対象に限定して配備・通常環境を再読み込みする既存の境界を維持する。

## 受入条件

以下を移行完了の条件として合意した。現時点で動作確認済みの一覧ではない。

1. 公式バイナリの Windows App／local core と WSL2 側 core を導入でき、`wsl.exe` の公式 transport で接続できる。SSH server の追加を前提にしない。
2. App から WSL2 内のリポジトリと既存 worktree を開き、新しい task worktree を作成できる。その terminal で Bash と既存の Nix ツールを使える。
3. Claude Code を起動でき、Codex は `--no-daemon` を指定した既存の実装役・レビュー役の起動経路で動く。公開のテスト入力で worktree／Git metadata の利用と必要な隔離を確認し、実際の秘密値を検証へ持ち込まない。
4. App の終了・再接続をまたいで core 内の terminal が継続する。OS 再起動や core 停止をまたいだ agent 実行の継続は要件にしない。
5. 隔離の外にいる親が標準の `hc run` で既存のレビュー役起動経路（`codex-reviewer`）を起動し、`hc wait` と `hc read` で依頼から応答の確認まで完了できる。子からの `hc send` や、隔離内からのホスト制御を必要条件にしない。待機の完了を回答の完了とは扱わず、今回の依頼への応答内容を確認する。
6. 接続・起動・App／local core／remote core の更新・切替・復旧手順が揃い、TUI を必須とする通常の設定・コマンド・skill 参照が残っていない。保持する旧データ・歴史資料・明示した未対応 skill は区別する。TUI 用の供給と copy-env の自動登録は同じ変更で整理し、途中の状態で `chezmoi apply` が失敗しないようにする。
7. dotfiles の変更に応じた必須チェックが通り、他 OS に共通する既存構成の検査を含める。実機未確認・opt-in 未実行の項目は成功扱いしない。

## 調査で確認した前提と未検証事項

2026-11-11 の確認結果。以下の公式資料の記載と、ローカルの観測を区別する。

- [公式 FAQ](https://herdr.dev/#questions) は、App が `herdr-core` を使う別プログラムで、TUI とエージェントを共有しないと説明している。既存の TUI セッションが App へそのまま表示される前提にはしない。
- App 標準の worktree 機能は、接続先 machine の `~/.herdr/worktrees/<repo>/<branch>` に作成し、既存の checkout は Open worktree で開く（[App AGENTS.md](https://github.com/herdrdev/herdr-app/blob/master/defaults/AGENTS.md)）。TUI の既定 root `~/.herdr/worktrees` と重なることを受け入れ、独自 mod・保存先の変更・自動削除は追加しない。同名 branch・path の衝突時の挙動、選択 checkout を基点とする作成、TUI が作成した checkout の再利用、worktree-gc（[ADR-0056](0056-worktree-gc-home-wide-fanout.md)）の所有権・保護条件は、2026-11-11 の #594 実機検証（WSL2、App 0.1.15、TUI 0.9.5）で確認した。手順は [runtime 利用案内](../../runtime/ai-runtimes.md#app-標準-worktree-の作成と再利用) に記録した。保持する worktree に Remove worktree を使わず、TUI 依存の整理で `~/.herdr` 配下のデータを削除しない。
- [Core Machines](https://github.com/herdrdev/herdr-core/blob/master/docs/machines.md) に、Windows から `wsl.exe` を `--via` に指定して WSL 内の core へ接続する経路がある。App がこの machine を利用することは [App の model](https://github.com/herdrdev/herdr-app/blob/master/defaults/AGENTS.md#the-model-spaces-tabs-terminals) と整合するが、この環境での一連の接続は未検証。
- [App の公式 updater](https://github.com/herdrdev/herdr-app/blob/master/src/update.rs) は App と local core を扱う。WSL 側 core は別 machine なので、App の更新だけで更新済みとは扱わず、公式の remote core 更新手順も運用に含める。
- 現ホストは WSL2。PATH 上には Nix 由来の Herdr TUI 0.9.5 があり、`hc` と `herdr-app` は見つからなかった。Windows 側の既知の標準インストール先にも App／core は見つからなかったが、任意の場所への導入までは確認していない。
- WSL の一覧には `Ubuntu-24.04` がある。対象ディストリビューションと current user の対応を実装時に再確認する。
- `codex-worktree` は既にホストの制御 socket を隔離内へ公開しない。[既存の隔離契約](../../runtime/ai-runtimes.md#新規-worktree-への-env-コピー) と [ADR-0080](0080-grant-reviewer-codex-read-only-git-metadata.md) の保護を、新 App の通常起動だけで満たせるとは扱わない。
- [core のマニュアル](https://github.com/herdrdev/herdr-core/blob/master/crates/herdr-core/src/SKILL.md) は、Codex に `--no-daemon` を指定しないとコマンドが hc の外で実行されると説明している。現行 CLI の help と固定版の両起動経路の引数検査では、この指定を使えることを確認した。App/core 経由の実起動、共有 daemon を経由しないこと、必要な隔離と OSC 7501 による状態報告は未検証である。
- 親の待機は `hc wait` を使い、message・timeout などの結果を区別する。起動時の依頼文が launch task として配送されるか、program の argv になるかと、`hc read` で応答を取得できる範囲を導入版で確認する。idle への遷移や待機の終了だけで回答完了とせず、子が `hc send` を使えない場合も親が今回の依頼への応答を確認する。実用に必要な状態報告や結果取得を満たせず公開 plugin の改修が必要になった場合は、合意範囲を広げず相談する。
- 本 ADR の master 版資料は調査時点の参考である。導入時は、導入版の App home の `AGENTS.md` と `hc --skill` を正本として再確認する（[公式ガイド](https://herdr.dev/guide/)）。`wsl.exe` 経由の非 login shell と App menu の起動環境を区別し、menu と親の `hc run` の両方で Bash・Nix・`hc`・既存の Codex 起動経路を利用できることを実測する。

全機能の同等再実装は独自連携の保守を継続するため選ばず、TUI との恒久併用や試用だけでの完了も選ばなかった。2026-11-11 の `grill-with-docs` で設計全体の共有理解と受入条件を確認し、合意した。導入・設定変更・既存資産の撤去は後続の実装フェーズで行う。
