---
type: concept
title: 秘密なしの開発と人間の実値検証
description: raw Codex のダミー値テストから、確認済みの固定版を別環境で検証し、確認した結果だけを戻す手順
tags: [codex, with-env, secrets, validation]
---

# 秘密なしの開発と人間の実値検証

Linux／WSL2 の `codex-worktree` では、公開入力だけで開発・テストする。実際のプロジェクト用シークレットが必要になったら、人間が確認した固定版を、Codex からアクセスできない別環境で実行する。`with-env` は対象コマンドへ値を渡す入口であり、そのコマンドやコードを書いた AI から値を隠す機能ではない。

## Codex に渡す入力とダミー値

[raw Codex の導入手順](shell-environment.md#raw-codex-のプロジェクト開発環境)に従い、必要な CLI・公開 CA・managed 設定を導入する。linked worktree で `devshell-env trust` と `devshell-env admit --git-head FULL_SHA -- FILES` を実行してから `codex-worktree` を起動する。`FILES` は確認済みの公開ファイルを個別に列挙し、到達可能な Git 履歴全体にも秘密がないことを確認する。

通常変数は秘密を含まない devShell に定義し、テストデータは通常名の公開 fixture として登録する。root `.env` やホストの環境変数からテスト値を継承させる必要はない。たとえばプロジェクトが用意した `scripts/check.py` を実行するなら、隔離内で次のようにダミー値を明示する。

```bash
with-env --prepared -- env TEST_TOKEN=dummy-local-only python3 scripts/check.py
```

同じ環境の通常コマンドや `with-env` から、非公開のホストファイル・プロセス環境へは到達できない。ネットワークに秘密取得サービスを追加したり、実値入り `.env` を公開入力に登録したりしない。`.env.example` には空値または明白なダミー値だけを置く。prepared 入口は Nix を再初期化しないため、flake・lock・import の変更後は再起動する。ホストで変更した公開入力は人間が再確認して `admit` し直す。raw セッション実行中の同じホスト worktree の並行編集は、結果返却時に競合となる。

## 人間が確認する固定版

1. 秘密なしのテストを完了し、対象の完全な commit SHA、検証コマンド、期待する結果を記録する。人間はその版のコード、flake・lock・shellHook、依存や install/build script、実行コマンドを確認する。実値を外部へ送る処理や、実行時に未確認コードを取得する処理がないことも確認する。
2. 人間が管理する別 VM または別マシンへ、その SHA の公開コードと固定した依存を渡す。Git bundle なら秘密のない履歴だけを含め、独立 clone で `git checkout --detach FULL_SHA` する。共有 object store、作業中の worktree の bind mount、同期フォルダ、動く branch の再取得を使わない。
3. 受取先でも `git rev-parse HEAD` とコードの差分を照合する。固定版・lock・コマンドが変わったら検証を止め、人間の確認からやり直す。実行に必要な公開依存の準備は秘密投入前に済ませる。

履歴を渡さない場合は、人間側で `git archive --format=tar --output=reviewed.tar FULL_SHA` を作り、別環境へ渡して展開する。`with-env` は Git root を必要とするため、展開先で `git init`、公開ファイルを `git add` する。この方法では元の SHA を検証記録に残し、展開内容を照合する。submodule・Git LFS の実体は archive だけでは揃わないため、必要な固定版も確認して別途渡す。

別ターミナルや別 worktree だけではアクセス境界にならない。実行中の Codex とその子、MCP、接続済みツールから、検証環境のコード・秘密・出力を読取り／書込みできないことが条件になる。共有 HOME・ディスク・キャッシュ・ログ・プロセス環境、SSH／VM 制御ソケット、到達可能な管理 API、秘密取得サービスを渡さない。Codex のツール認証にも、この検証環境を操作したりログを取得したりできる権限を与えない。実値を使う CI も同じ条件を満たし、未確認の AI 変更を自動実行しない。

## 別環境で実行し、確認した結果だけを共有する

人間はコードの固定とアクセス境界を確認した後、その別環境の root `.env` または既存の秘密管理手段で値を用意する。配備済みの秘密を AI に読ませて転送しない。秘密・ログ・成果物は人間だけが扱える保存先に置く。

root `.env` は Git に追加せず、所有者だけにアクセスを許可する。秘密取得を Nix 評価や shellHook に書かない。

人間向けの公開入口は従来どおり `nix run .#with-env -- <確認済みコマンド> [args...]`。root `.env` の解析、起動元 → devShell → dotenv の優先順位、引数・終了コードの保持、不正 dotenv や Nix／shellHook 失敗時の停止は維持する。詳細は [with-env の契約](shell-environment.md#指定コマンドへの-dotenv-注入)を参照する。実行コードとその子には実値が見えるため、固定・確認済みコードに限る。

最初はこの別環境でもダミー値で手順を確認する。自動回帰テストはここまでで、実値の投入や実サービス呼出しは含めない。確認後、実値を使うかと実行時期は人間が決める。

終了後は、人間が非公開のログと成果物を確認し、必要な結果だけを新しく要約して共有する。共有内容は「完全な SHA、実行したコマンド、成否、公開してよいエラー分類」などとし、未確認の stdout／stderr、デバッグ dump、接続 URL、スクリーンショット、成果物を AI や Issue／PR に自動送信しない。機械的な文字列マスクだけで共有可と判定しない。再検証が必要なら新しい版を再確認して同じ手順を繰り返す。

## 移行・適用範囲・検証

既存 repo は個別に確認し、通常設定を flake へ、テスト値を公開 fixture へ移す。`.envrc` は必須にせず、`nix develop`／`with-env`／raw 入口は既存 `.envrc` を自動実行しない。明示した direnv は従来の dotenv を読み得るため、新しい端末で移行を確認する。既存 repo の一括変更や秘密ファイルの収集・コピーは行わない。

dotfiles と6言語テンプレートは同じ公開 devShell／`with-env` 入口を使う。新規テンプレートの input は #271 の受入済み revision に固定する。既存 repo で更新する場合は `DEVELOPMENT.md` と input の変更を個別に確認し、lock を再生成して秘密なしで検証する。テンプレートの `default` は Linux／WSL2 と macOS の人間向け環境に使える。dotfiles の WSL2 は `nix develop .#wsl`、6テンプレートは `nix develop .#default` を使う。

隔離は Linux／WSL2 の共通 `codex-worktree` 入口から新規起動したセッションに適用する。既存セッション、直接 `codex`、Desktop、Orca／Herdr native 起動、Claude にこの非開示保証を広げない。Herdr 作成済み worktree でも共通入口を明示して起動する。macOS raw は未対応。Claude は既存の非秘密 devShell 起動と permission を維持し、実値検証は上記の人間側で行う。

導入は受入・merge 後に live source から配備し、新しい端末・セッションで行う。隔離や初期化に失敗したら停止し、秘密のない診断と入力を確認して再登録・再起動する。無保護起動へ fallback せず、返却に失敗した結果は復旧前に破棄しない。

[#274 の検証記録](../docs/research/human-validation-274.md)は、Linux と WSL2 の結果、実際の公開 CLI、6言語の独立 repo、人間側をダミー値で再現した fixture の証拠と未確認事項を区別する。
