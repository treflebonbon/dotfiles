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

### 復旧 baseline

移行直前の dotfiles source baseline は `34fa46fdd7a7cd8e30b910b2d5c0be5bebf30e63`。復旧変更はこの commit から次の TUI 固定値と source を選び、現在の他の設定へ重ねる。

- Nix: `private_dot_config/nix-devshell/flake.lock` の `llm-agents` revision `2b6455a7711d6dc90e42e555c1ddb504481268f4` に含まれる `llm.herdr` 0.9.5。lock 全体は戻さず、現在の `ai.nix` の `llm.herdr` package entry だけを復元する。
- APM: `herdrdev/herdr/skills/herdr#2ecf19a92fc3a7fff75b6ce3655ef04f4625ec01`。移行直前 lock の skill `content_hash` は `sha256:72177e911f55467de8737174072ec6bb08e30bbf62bceabcb69678e944398b18`。現在の manifest にこの dependency だけを追加し、`runtime/skill-harness.md` の隔離生成・frozen install・audit 手順で lock を再生成する。旧 `apm.lock.yaml` 全体をコピーしない。
- Copy-env: `.herdr/herdr-plugin.toml` の `dotfiles.copy-env` 0.2.0 と `run_after_setup-herdr.sh`。この baseline の同名ファイルを復元し、chezmoi の設定反映後に登録状態を確認する。
- Claude permission: `private_dot_claude/settings.json.tmpl` の `Bash(herdr worktree remove:*)` 一件だけを戻す。`.chezmoiignore` の `.herdr` 除外は維持する。

テストする場合は移行後 source の一時 fixture に対して上記だけを戻し、Nix の版、APM の frozen/audit、plugin source と登録対象、permission、他の package / dependency の不変を確認する。fixture は専用の一時 HOME と APM 配備先を使う。ライブ HOME、稼働中の App/core、既存 `.herdr` データは復旧試験に使わない。実際の復旧では無関係なファイルを baseline から一括 checkout せず、復元対象の差分だけをレビューする。

実装は validated task worktree で行う。未 merge の task source から `chezmoi apply` しない。受入後の live source から、変更対象に限定して配備・通常環境を再読み込みする既存の境界を維持する。

## 受入条件

以下を移行完了の条件として合意した。#594/#595 実機結果と #596 source checks の確認範囲は後段に記す。

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
- App 標準の worktree 機能は、接続先 machine の `~/.herdr/worktrees/<repo>/<branch>` に作成し、既存の checkout は Open worktree で開く（[App AGENTS.md](https://github.com/herdrdev/herdr-app/blob/v0.1.15/defaults/AGENTS.md)）。TUI の既定 root `~/.herdr/worktrees` と重なることを受け入れ、独自 mod・保存先の変更・自動削除は追加しない。同名 branch・path の衝突時の挙動、選択 checkout を基点とする作成、TUI が作成した checkout の再利用、worktree-gc（[ADR-0056](0056-worktree-gc-home-wide-fanout.md)）の所有権・保護条件は、2026-11-11 の #594 実機検証（WSL2、App 0.1.15、TUI 0.9.5）で確認した。手順は [runtime 利用案内](../../runtime/ai-runtimes.md#app-標準-worktree-の作成と再利用) に記録した。保持する worktree に Remove worktree を使わず、TUI 依存の整理で `~/.herdr` 配下のデータを削除しない。
- [Core Machines](https://github.com/herdrdev/herdr-core/blob/v0.1.20/docs/machines.md) の `wsl.exe` `--via` 経路は #594/#595 で Windows App 0.1.15 から WSL2 machine への接続に使った。App terminal で既存・新規 linked worktree を開き、Bash・Nix・Codex の起動と親側 `hc run` を確認した。
- [App の公式 updater](https://github.com/herdrdev/herdr-app/blob/v0.1.15/src/update.rs) は App と App 所有の local core を扱う。App update は download と SHA-256 を確認してから再起動で適用し、初回起動で同 generation の local core を更新する。package manager 所有の local core は App が更新しない。WSL 側 core は別 machine なので、App の更新だけで更新済みとは扱わず、公式の `hc machine update` 手順も運用に含める。
- 2026-11-11 の初期確認では WSL PATH 上に Nix 由来 Herdr TUI 0.9.5 があり、`hc` と `herdr-app` は未検出だった。翌日の #594/#595 では Windows App 0.1.15、Windows/WSL core 0.1.20、WSL Codex 0.167.0 を確認した。
- #595 では remote machine `wsl-ubuntu-24-04` に接続し、App terminal の `codex-worktree --no-daemon` と reviewer `codex-reviewer --no-daemon` を公開 fixture で実行した。raw wrapper の file/index/commit 返却と host HEAD 照合を確認し、reviewer の `git update-index --force-write-index` は read-only filesystem により拒否された。
- `codex-worktree` は既にホストの制御 socket を隔離内へ公開しない。[既存の隔離契約](../../runtime/shell-environment.md#raw-codex-のプロジェクト開発環境) と [ADR-0080](0080-grant-reviewer-codex-read-only-git-metadata.md) の保護は、新 App の通常起動だけで満たせるとは扱わない。
- [core のマニュアル](https://github.com/herdrdev/herdr-core/blob/v0.1.20/crates/herdr-core/src/SKILL.md) に従い、両起動経路で `--no-daemon` を使った。#595 では実起動と必要な隔離を確認した。親の `hc wait` は timeout/working の後に done へ進み、`hc read` の stitched 応答から今回の marker と公開 file の読取りを確認した。別の no-model fixture での `reason=message` は実 reviewer の回答と区別した。
- #595 の同じ reviewer process で `plugin contents changed; hook approval required` が再発した。承認後のモデル応答・Git boundary は確認したが、hook warning は解消済みと扱わず、正確な mismatch 原因は未確定である。
- 2026-11-12 の更新確認では Windows App `0.1.15`、Windows local core `0.1.20`、登録済み WSL machine `wsl-ubuntu-24-04` の remote core `0.1.20` を確認した。公式 release feed の latest も App `0.1.15` / Core `0.1.20` で、App の Settings → Updates から App と Core の「Check now」を実行すると双方が最新状態と表示された。`hc machine ls` は WSL machine を `connected`、`hc exec --on wsl-ubuntu-24-04 -- hc --version` は `hc 0.1.20` と返した。
- 失敗表示は、導入済み App binary を専用 `HERDR_APP_HOME` で起動し、`HERDR_RELEASES_URL=http://127.0.0.1:1` を与えて `app.check_updates` を実行する隔離試験で確認した。App / Core の両方に「更新確認に成功していません。接続状態を確認して再試行してください」という失敗表示が出て、実際の App `0.1.15`・local core `0.1.20`・remote core `0.1.20` は維持された。これは release feed 接続失敗の確認であり、download/checksum 不一致の注入は未実施。
- `hc.exe machine update` の不明 machine 名による拒否は `machine_unknown` / exit code 4 で確認した。実機は latest と同じ版で、local / remote core の各9 terminal が `live` だったため、remote core を再起動する実更新は行わず、転送失敗後の復旧も未検証である。更新がある場合の手順は [runtime 利用案内](../../runtime/ai-runtimes.md#app-と-core-の更新失敗時の復旧) に従い、App / Windows / WSL の再起動をまたぐ agent 継続は保証しない。
- 本 ADR の master 版資料は調査時点の参考である。導入時は、導入版の App home の `AGENTS.md` と `hc --skill` を正本として再確認する（[公式ガイド](https://herdr.dev/guide/)）。`wsl.exe` 経由の非 login shell と App menu の起動環境を区別し、menu と親の `hc run` の両方で Bash・Nix・`hc`・既存の Codex 起動経路を利用できることを実測する。

全機能の同等再実装は独自連携の保守を継続するため選ばず、TUI との恒久併用や試用だけでの完了も選ばなかった。2026-11-11 の `grill-with-docs` で設計全体の共有理解と受入条件を確認し、合意した。

## #596 実装・復旧 fixture の確認

- 変更前 source baseline `34fa46fdd7a7cd8e30b910b2d5c0be5bebf30e63` を一時 archive し、Herdr TUI package / copy-env / registration の旧 Bats 34件を実行した。32件成功、opt-in App integration と Bash 3.2 指定の2件は実行せず skip。Nix は 0.9.5 を全対応 system / shell で返した。
- 同じ baseline から隔離した APM fixture で 21 dependencies の `apm install --frozen --target claude,codex --https` と `apm audit --ci` が成功し、audit 10/10、lock SHA-256 は不変。Herdr TUI skill は revision `2ecf19a92fc3a7fff75b6ce3655ef04f4625ec01`、content hash `sha256:72177e911f55467de8737174072ec6bb08e30bbf62bceabcb69678e944398b18` で復旧可能なことを確認した。
- 現行 candidate lock は移行前 lock を初期値にした隔離 runtime で native
  生成し、frozen install 前後の SHA-256 不変、audit 10/10 を確認した。
  Herdr TUI dependency と両 target の4 ledger rowを除いた。
  残る 1,512 deployment entries は元 lock と一致した。
  - base は baseline commit `34fa46f...` の元 lockを直接取得する。
  - plan は Herdr TUI dependency の削除1件だけを追加0・削除4として列挙した。
  - verifier は元 base と candidate を比較し、削除4以外の drift を拒否する。
  - Bats は未宣言削除、削除 dependency の配備残り、候補外 hash drift、
    exact pin / ref / version drift を拒否する。
  - 照合結果は dependency 20、各 target 46 skill、追加0・削除4。
- `chezmoi apply` の回帰 fixture は Herdr TUI を含まない source から既存 `~/.herdr/history` と worktree marker を保持する。通常 HOME、App/core の live 更新・失敗注入、TUI state は変更していない。
- 2026-11-12 の復旧 fixture は retirement 候補を起点にし、baseline から Nix package・APM dependency/lock・Claude permission の差分だけを重ね、削除された copy-env source を復元した。Nix eval は 3 system / default・wsl の全 shell で Herdr TUI 0.9.5 を返し、`flake.lock` の `llm-agents` revision と現行 Matt / Orca dependency は維持された。APM lock の Herdr TUI revision/content hash と無関係な Matt revision を確認した。
- 同 fixture の `chezmoi apply` は登録済み copy-env を持つ旧 source → TUI なしの retirement source → 復旧 source の順で実行した。retirement 中は登録と `~/.herdr/history` を保持し、ユーザーが無効化した登録は復旧 source へ移動後も無効のまま、再 apply で重複 link されないことを確認した。
- 復旧 source の manifest / lock を隔離 APM runtime へ複製して公式の native lock 生成・`apm install --frozen --target claude,codex --https`・`apm audit --ci` を実行した。21 dependencies、生成／frozen 前後の lock SHA-256 `9fc12c9696dd1c0e3cb10116de24a732a47315630f873c70c9192fea1f8c037d` 不変、audit 10/10 成功を確認した。git remote のない fixture のため organization policy enforcement は warning 付き skip。生成 lock は復旧 source と byte 一致し、`verify-apm-deployment.mjs` の空候補照合で drift 0、各 target 47 skill、追加・削除 0 を確認した。
