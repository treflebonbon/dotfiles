---
type: decision
title: Google Cloud と GitHub の調査操作を自動許可する
description: 通常の Codex と Claude Code で必要な読み取りを許可し、秘密値の取得と設定出力の既知の機密項目を制限する。ログへの偶発的な秘密値の混入リスクは受容する。
tags: [adr, codex, claude-code, permissions, gcloud, github]
timestamp: 2026-10-15
status: accepted
---

# Google Cloud と GitHub の調査操作を自動許可する

現行設定は `gcloud` を一括禁止しており、Logging・Monitoring や非機密の設定確認も実行できない。`gh` も調査用コマンドの明示許可が不足している。CLI 全体の許可では変更操作や秘密値の取得まで含まれるため、調査に必要な操作と出力を限定して自動許可する。

## 合意済みの権限境界

2026-10-15 の `grill-with-docs` で次を合意した。

| 対象 | 自動許可する調査 |
| --- | --- |
| Google Cloud | Logging の検索・閲覧、Monitoring の参照、機密情報を除く設定内容の参照 |
| GitHub | PR・Issue・コードの参照、Actions の実行結果と失敗ログの参照 |

通常の Codex と Claude Code を対象とし、`codex-worktree` の raw 隔離版は今回の対象に含めない。既存の認証でアクセスできる Google Cloud プロジェクトと GitHub repo を対象とし、private repo も含む。新しいアクセス権の付与や認証設定の変更は、この調査許可には含まれない。

Secret Manager の秘密値や認証トークンをエージェントへ表示する取得操作は禁止し、設定の既知の機密項目はエージェントが受け取る出力から除外する。CLI 内部で既存の認証を利用することと、認証値自体を調査結果として取得することは区別する。[ADR-0055](0055-disable-block-reads-outside-working-directories.md) の credential ファイルの直接参照に対する保護は維持する。

通常ログは閲覧できる。ログ本文や想定外の設定項目に誤って含まれた秘密値を完全に自動判別する保証は求めず、その混入リスクを受容する。これは秘密値の意図的な取得や、既知の機密項目をそのまま表示することの許可ではない。

## 採用した許可方針

- 非機密の一覧・設定・IAM 参照は、Logging・Monitoring、Cloud Run、GKE、Compute Engine などサービス横断で扱う。初期の自動許可対象は、操作と出力の安全性を確認できたものを明示的に列挙する。
- 初期の自動許可対象にない調査操作は、ユーザーへ内容を示して実行前に確認する。今回の変更で、既存の書込み操作に対する許可範囲は広げない。

## 実装時に守る条件

コマンド名の先頭だけで判定するルールでは、後続のオプションやレスポンスの機密項目を制限できない。Cloud Run の `services describe` は環境変数も返すため、設定参照に必要な出力制限を、任意オプションで解除できる形にしない。既存の許可機構を利用できる操作はそれを使い、追加の実行入口が必要な場合は対応する調査操作だけを扱う。

実装は `gcloud-inspect` を限定入口とし、操作・引数の検証、設定の機密項目の除外、Monitoring 時系列 API の固定 GET を担当させる。初期対応外の読み取りはユーザーの確認後に `gcloud-inspect --reviewed` を使い、CLI の help で正式な読み取りコマンドか検証する。対応する `gh` の参照コマンドは各 runtime の許可ルールを使う。`gh api`（既存の `rate_limit` を含む）は個別確認に回す。使い方と初期対応範囲は [runtime/investigation.md](../../runtime/investigation.md) に記載する。

Monitoring の時系列データは、導入版 CLI の対応を確認したうえで必要なら公式の `projects.timeSeries.list` を利用する。認証値をエージェントへ表示する手順は採用しない。任意の `gh api` や GraphQL は初期の自動許可対象に加えず、必要な GitHub 調査は専用の参照コマンドで提供する。

通常の `gcloud` は一括禁止を維持する。グローバルオプションを先に置くと秘密取得を狭い prefix ルールで識別できないため、単に個別確認へ緩和する設計は採用しない。別名の限定入口を許可し、Codex の command rules と Claude Code の共通設定・repo 設定を揃える。Codex の allow で限定入口を既存の承認経路から実行し、秘密ファイルや network domain の許可範囲は広げない。raw 隔離版の独立した認証・通信境界は変更しない。

Claude Code の auto 判定だけでは、未対応の調査操作について人間への確認を保証しない。対象外の操作を自動実行せず、実行前にユーザーへ確認する経路も検証する。

検証は、許可する参照操作、拒否・確認する操作、秘密値取得、出力制限を変えるオプション、ダミーの機密項目の除外を含める。実 credential や実サービスを使わない検証と、受入後の接続確認は区別する。配備は受入後に live source から行い、未 merge の task worktree から `chezmoi apply` しない。

## 根拠

- [Codex rules](https://learn.chatgpt.com/docs/agent-configuration/rules): 複数ルールでは `forbidden`、`prompt`、`allow` の順に厳しい判断を採用する。
- [Claude Code permissions](https://code.claude.com/docs/en/permissions): deny の優先とコマンドパターンの判定方式。
- [Cloud Run の環境変数確認](https://docs.cloud.google.com/run/docs/configuring/services/environment-variables#view-environment-variables-settings): `services describe` の返却設定に環境変数を含む。
- [Monitoring 時系列 API](https://docs.cloud.google.com/monitoring/api/ref_v3/rest/v3/projects.timeSeries/list): 時間範囲と filter を指定する時系列の読み取り。
- [GitHub Actions の安全な利用](https://docs.github.com/en/actions/reference/security/secure-use): ログの秘密値のマスキングには限界がある。
- [gh api](https://cli.github.com/manual/gh_api): 任意 endpoint と HTTP method を扱い、field の指定で既定 method が POST になる。
