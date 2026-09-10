---
type: research
title: Issue 274 秘密なし開発と人間の実値検証の分離
description: 公開 with-env の回帰、固定コードと出力の分離、6言語テンプレートの移行
tags: [nix, codex, dotenv, verification]
---

# Issue #274 の検証記録

2026-09-10。[#274](https://github.com/treflebonbon/dotfiles/issues/274)、親 [#268](https://github.com/treflebonbon/dotfiles/issues/268)。開始点は `63e47ffc471ff5e01f58a8a268ea553b0c9ab976`。依存 [#271](raw-codex-isolation-271.md) の共通入口を変更せず、公開入口の回帰検証と利用手順・テンプレートの移行を行った。未 merge の source から利用者設定を配備していない。

## 変更と入力

README と runtime、6言語の独立した `DEVELOPMENT.md` に、秘密なしの AI 操作と人間の実値検証を記載した。人間はコード・依存・初期化処理・実行コマンドを確認して完全な SHA に固定し、Codex がアクセスできない別環境にコード・秘密・出力を置く。検証結果は人間が確認して必要な要約だけを手動共有する。正本は[人間による実値検証](../../runtime/shell-environment.md#人間による実値検証)。旧 #257／#258 記録には現行手順への案内を追加した。

6テンプレートの共通 dotfiles input を、旧 `002085017c4260e3044156ab474823dad3bd1378` から、#271 を含む merge 済みの開始点へ揃えた。言語用 nixpkgs の系統・follows・公開 app 名・devShell・任意の `.envrc` は維持する。利用者の既存 repo や lock を一括変更する処理は追加していない。

`tests/human-validation.bats` は実 Nix、公開 `with-env` package、`codex-worktree sandbox` を使う。Nix／Codex を mock しない。人間側も列挙した公開ツール環境から起動し、任意の host 変数は渡さない。専用 HOME の設定は管理 template からレンダリングし、公開のテストコード・Git 履歴・通常変数・JSON fixture だけを raw 入口へ登録する。プロジェクト秘密や外部サービスの認証は使用しない。

## 分離検証

1. 公開 commit を `git archive FULL_SHA` で独立した人間側ディレクトリに展開し、共有 object directory のない Git root を作る。
2. 人間側だけにダミーの `.env` と出力を置き、公開 `with-env` から固定版の検証コードを実行して待機させる。
3. 同時に共通 raw 入口から Codex の実 sandbox を起動する。通常変数と JSON fixture、明示したダミー変数を使ってテストし、コードを変更・compile・再テストする。
4. Codex の子が人間側コード・dotenv・出力と `/proc/<human-pid>/environ`、`/proc/<human-pid>/root` を、通常 command と `with-env --prepared` の両方から read／write open する。値が表示されないだけで成功とせず、OS の拒否を判定する。
5. 人間側の検証を再開し、固定したソースが変わっていないことと、ダミー値を含む出力の生成を確認する。Codex 側で完成後の出力も再び read／write できないことを確認して commit・返却する。返却した commit の内容と、人間側の固定ファイル・秘密・出力の保持を確認する。

この fixture の人間側は共通 raw namespace の外側にあり、検証 controller が両側のダミー結果を検査する。現在の任意の agent session や、別ディレクトリという配置自体への非開示保証ではない。本番では別マシン／独立 VM 等のアクセス条件を人間が確認する。実値、外部サービス、本番 CI、秘密の自動送信の検証は行わない。

## 実行記録

Session Scratchpad が提示されていないため、証跡は `/tmp` を明示 fallback として使用した。

- WSL2: `nix develop .#wsl -c bats tests/human-validation.bats` で分離ケース成功。kernel `6.18.33.2-microsoft-standard-WSL2`、Nix 2.34.6、Codex 0.153.4、bubblewrap 0.11.2、repo devShell の Python 3.13.13 を使用。
- 6言語: `nix develop .#wsl -c python3 tests/helpers/template-with-env.py`。証跡は `/tmp/template-with-env-258-kspy5vz4/`。
- Linux VM: `nix develop .#wsl -c python3 scripts/secret-isolation-linux-vm.py --human-validation --output /tmp/human-validation-274-linux-final`。分離ケース成功。最終 source の再確認は `/tmp/human-validation-274-linux-verified/` に記録する。VM は列挙した CLI closure と fixture だけの image を使い、host HOME／store を共有しない。通常ユーザー uid 1000、外部サービスへのネットワークは無効。
- 全 Bats: `WITH_ENV_REAL_NIX=1 SECRET_ISOLATION_REAL_RUNTIME=1` と公開 CA を指定し、全 Bats ファイルを重複なく4群に分けて各群内は逐次実行。`/tmp/human-validation-274-suite/manifest.json` と各 log を参照。

## 適用と未確認事項

受入・merge 後に live source から配備し、新しい端末で公開ファイル・到達可能履歴を確認して `trust`／`admit`、`codex-worktree` を起動する。flake・lock・import を変えたら確認・再登録・再起動する。初期化失敗は非0終了し、秘密なしの入力を修正して正式入口から再試行する。詳細な導入条件・専用 store の初回準備・保持された session の復旧は [raw 共通入口](../../runtime/shell-environment.md#raw-codex-のプロジェクト開発環境)を参照。

既存セッション、直接 Codex、Desktop、Orca／Herdr native 起動、macOS raw の非開示保証には拡張しない。6テンプレートの3 system の評価は実機での実行とは区別する。ARM Linux／macOS の実行、人間の実値サービス・CI、本番別環境の運用は未検証。Claude は既存の非秘密 devShell 起動を回帰確認し、dotenv 注入や新しい OS sandbox は追加しない。
