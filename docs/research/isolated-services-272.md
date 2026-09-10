---
type: research
title: 隔離 Codex の管理 MCP と GitHub 連携
description: Issue 272 の選択入力、権限、実接続、拒否検証と未確認事項。
tags: [codex, mcp, github, isolation]
timestamp: 2026-09-10
---

# 隔離 Codex の管理 MCP と GitHub 連携

[#272](https://github.com/treflebonbon/dotfiles/issues/272) と親仕様 [#268](https://github.com/treflebonbon/dotfiles/issues/268) の検証記録。共通 raw 入口と、秘密なしの公開 snapshot・専用 Nix store・変更返却は #271 の実装を使う。

## 選択入力と認証の範囲

| 入力                           | 使用先と制限                                                                                                                                                                                    |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 管理 MCP の command/args       | `--mcp` で選んだ Context7・Serena の既存 managed stdio 契約だけ。一致しない env・URL・追加 command は登録を拒否する。未選択サーバーの認証値を含む設定もコピーしない。                           |
| bunx・Node・uvx の Nix closure | 個別にコピーし隔離内で起動する。bunx/uvx は argv[0] が意味を持つため最終 symlink の名前を保持する。ホストの package cache は使用しない。                                                        |
| GitHub policy JSON             | worktree 外で人間が所有。公開 repository、1 topic、default branch、確認した commit、CI/外部連携の条件と根拠を固定する。private repository は本実装の対象外。                                    |
| host gh の既存認証             | host gateway だけが使う。HOME・token・credential helper・制御 socket を隔離内へ渡さない。プロジェクトコードから送れる要求を metadata・対象 PR・検査済み topic push に制限する。                 |
| 公開 Git 履歴・bundle          | 新規 commit の全 `.github` tree を確認済み commit と比較する。専用 publisher は checkout や project hook を実行しない。既存 `git-push-topic` の default branch 拒否・非 force push を維持する。 |
| network                        | 既存 domain allowlist と公開 IP resolver を使い、明示 deny を優先する。GitHub は既存 proxy の内部 HTTP envelope だけを受け、host が実サービスへ HTTPS 接続する。                                |

追加 MCP・Codex plugin・クラウドの取得サービスを無検査で接続しない。`automation` の確認は人間が所有する宣言であり、自動スキャンによる外部サービス全体の安全証明ではない。管理者が後から変更する CI、GitHub App、runner の状態まではローカル snapshot で固定できない。実シークレットを使う連携は、人間が確認済みのコードを AI がアクセスできない別環境で実行する条件に合わせる。

この repo の追跡済み `.github/workflows/osv-scanner-{pr,full}.yml` は固定 revision の OSV reusable workflow を呼ぶ。プロジェクト secret の参照・`secrets: inherit`・environment 指定はない。GitHub 外の連携や他 repo の保証と区別する。

## 実装判断の根拠

Codex の stdio MCP は `command`・`args`・`env_vars` と required startup を提供する。[公式 MCP 設定](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)

Codex 0.153.4 の Linux proxy 用 seccomp は IP socket を許可し、AF_UNIX の新規接続を拒否する。実 gh の `http_unix_socket` はここで EPERM となったため採用しない。限定 CLI が既存 HTTP proxy を使い、host gateway の固定 GitHub 操作へ接続する。Unix socket の包括許可、host network 共有、TLS 検証無効化は使用していない。[固定版の実装](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/linux-sandbox/src/landlock.rs)

AI の変更を secret 付き CI へ渡す危険はローカルファイル拒否では解消しない。確認済み automation の固定と人間の実行条件を別に扱う。[GitHub の安全な workflow 利用](https://docs.github.com/en/actions/reference/security/secure-use)

## WSL2 の検証

Linux `6.18.33.2-microsoft-standard-WSL2`、Codex 0.153.4、Nix 2.34.6、gh 2.96.0、bubblewrap 0.11.2 で測定。Session Scratchpad は提示されていないため、一般の検証ログは `/tmp/codex-services-272/` を fallback に使用した。

| 検証                | 結果・証跡                                                                                                                                                                                                        |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 管理 MCP 選択       | 実 `codex-worktree mcp list --json` で両サーバーを確認。未選択設定の dummy credential は出力されない。`tests/raw-codex-services.bats`。                                                                           |
| 実 Context7・Serena | 共通入口 → Nix/shellHook → hosted model を使う Codex → 両 stdio MCP。Context7 の Python 文書参照と Serena による `greeting.py` の before→after 編集・ホスト返却が成功。`mcp-home-fixture.log`。                   |
| 実 GitHub 接続      | 共通入口の Codex command sandbox から公開 repo metadata と対象 topic の PR 一覧を取得。host の実 gh が認証を使用。Secrets・Actions ログ・`.env` contents・GraphQL・dispatch の試行は拒否。`real-github-cli.log`。 |
| topic push の境界   | 実 Git object/bundle を socket 経由で受信し、正常 commit は dummy publisher まで到達。`.github` 変更・不一致 HEAD は publisher 前に拒否。実 GitHub push とは区別する。                                            |
| PR の境界           | dummy upstream で選択 branch/base の PR 作成を許可。別 branch/base、state 変更、余分な field は拒否。実 GitHub PR 作成とは区別する。                                                                              |
| ネットワーク拒否    | 許可外 domain、private IP、明示 deny、他 port を拒否する既存 gateway 検証を維持。                                                                                                                                 |

`/tmp` 配下の MCP fixture では、Serena の編集に対する Codex の自動承認レビューが `.env` マスク作成時の read-only filesystem エラーで失敗した。実利用先と同じ home 配下の linked worktree では、同じ managed permission/approval 設定のまま成功した。拒否を bypass する設定は加えていない。secret deny の空マスクを `.env` として読める場合も、ホストの dummy 値が取得されないことと区別する。`/tmp` 配下の MCP 編集は対応済みとしない。

実 MCP の再現は、ホスト側の公開 fixture の置き場所を home 配下にする（namespace 内の HOME と TMPDIR は launcher が固定する）。

```bash
mkdir -p "$HOME/.local/state/codex-services-test"
TMPDIR="$HOME/.local/state/codex-services-test" \
  CODEX_ISOLATION_REAL_MCP=1 \
  CODEX_ISOLATION_CA_BUNDLE=/nix/store/SELECTED-cacert/etc/ssl/certs/ca-bundle.crt \
  bats --filter 'uses real managed' tests/raw-codex-services.bats

CODEX_ISOLATION_REAL_GITHUB=1 \
  CODEX_ISOLATION_CA_BUNDLE=/nix/store/SELECTED-cacert/etc/ssl/certs/ca-bundle.crt \
  bats --filter 'uses host gh' tests/raw-codex-services.bats
```

## 通常 Linux での再現

NixOS VM は有限の公開 source と Nix closure から作り、host Nix store をマウントしない。実サービス検証を明示した場合だけゲストの host gateway に外部接続を許可する。ゲスト内の `codex-worktree` は同じ外側の network namespace と domain allow/deny を維持する。

通常 Linux kernel `6.18.33` の回帰 VM は exit 0（`linux-vm-regression-rechecked/test.log`）。実 Nix/Codex の隔離 fixture、worktree 変更返却、raw 入口、MCP 選択、GitHub 限定 API と model gateway の拒否検証が成功した。opt-in の hosted model・実 MCP・実 GitHub 接続はこの回帰実行の成功件数と区別し、別の実サービス実行で確認する。

```bash
nix develop .#wsl --command python3 scripts/secret-isolation-linux-vm.py \
  --output /tmp/codex-services-linux

nix develop .#wsl --command python3 scripts/secret-isolation-linux-vm.py \
  --real-services --output /tmp/codex-services-linux-live
```

`--real-services` は実モデル利用を含む。選択した Codex の `auth.json` と gh の `hosts.yml` だけを image 構築後にゲスト host の `/run` tmpfs へ渡す。値を Nix store・argv・ログ・evidence・ゲスト disk に含めず、ゲストの限定 gateway だけで使用する。転送途中の失敗を含めて finally でコピーを空にし、強制終了時もメモリ上のコピーだけが消える。元の login file は変更しない。出力 directory は mode 700 とし、Bats の結果だけを実接続の evidence として返す。

最初の実接続では、管理 MCP の設定参照・実 GitHub の認証済み参照と拒否検証は成功した。Context7・Serena は依存取得時に gateway の最初の接続先 IP が timeout し、required startup が非0終了した（`linux-vm-live/evidence/live-services-tests.log`）。公開 CONNECT の focused test でこの動作を再現し、DNS 結果の全 IP を検査してから、同じ検査済み IP の列だけを順に試すよう修正した。再 DNS・domain allowlist 拡大・private IP 許可は行わない。WSL2 の実 Nix cache 取得と許可外接続拒否は修正後も成功した（`public-dependency-recheck.log`）。

再試行だけでは VM の MCP 起動は直らなかった。起動ログで、Serena の GitHub 取得は成功し、PyPI 接続で timeout、Context7 は npm 依存解決中に timeout すると確認した（`linux-vm-mcp-startup-diagnostic/evidence/live-services-tests.log`）。QEMU はゲストへ `fec0::/64` と IPv6 default route を通知する一方、この WSL ホストの公開 IPv6 接続は失敗し、同じ配布元の IPv4 接続は成功した。このため検証 VM は `networking.enableIPv6 = false` で実際に使える IPv4 uplink に合わせる。通常 Linux の実接続の保証範囲もこの IPv4 構成に限定し、dual-stack は未確認とする。

IPv4 VM は後続の回帰を含め exit 0（`linux-vm-ipv4-services/test.log`）。実サービスの3件もすべて成功した（`evidence/live-services-tests.log`）。管理 MCP の選択、実 gh による公開 repo/PR 参照と秘密・制御 API の拒否、hosted Codex から実 Context7 による文書参照・実 Serena による `greeting.py` の編集とホスト返却を確認した。最後のテストは両 MCP の実呼出し、返却ファイルの before→after、dummy 秘密値の非露出を検査している。VM 全体の Bats は46成功・7 opt-in skip、別途実行した Nix/Codex 隔離 fixture も成功した。

## レビューと未確認事項

`code-review` の Standards 軸は規約違反なし。Spec 軸は実 GitHub 書込みと通常 Linux の最終証跡を未達として指摘した。bundle の資源上限については、要求64 MiB・Git 検査120秒の既存制限と、展開後容量・object 数を制限しない残余リスクを運用文書へ明記した。秘密到達の防止と host 資源枯渇への耐性を同一視しない。

`SECRET_ISOLATION_REAL_RUNTIME=1 bun run test` は641件を実行し、629成功・10 opt-in skip・2失敗だった（`full-suite.log`）。継承した二重の nix-shell TMPDIR により、既存の漏えい・timeout probe の Unix socket パスが108 byte以上になり、境界検証の前に失敗していた。`TMPDIR=/tmp` で該当2件を再実行すると両方成功した（`failed-probes-short-tmp.log`）。テストの assertion や runtime の制限は変更していない。全 suite の同一実行が exit 0 だったという記録にはしない。

Linux では既存 model gateway の拒否応答が本文送信より早く返る競合も再現した。テスト client が送信時の BrokenPipe 後も403応答・空本文・upstream 未接続を検査するように修正した。追加した接続先再試行を含む gateway/GitHub の6件は成功。Python lint・型検査と通常の commit hook も成功した。追加修正の Standards・Spec 再レビューに実装上の未解決指摘はない。

実 GitHub topic push・PR の書込みは未確認。外部連携が実シークレットを使用するかはユーザー確認待ち。fixture・公開 GET だけで実 GitHub 書込みの受入条件を満たしたとは扱わない。

## PR #280 の Review Round

5スレッドの指摘とタイトル省略時の診断を修正した。GitHub 設定先はホスト側で選択し、MCP の実行パスは Nix store 内の起動名を保持する。不正な GitHub tree 応答は全要素を確認して502を返す。`gh api -F body=@-` は標準入力を読み、PR 作成の `--title` 省略は送信前に診断する。

- `tests/isolated-github.bats` と `tests/secret-isolation-gateway.bats`: 8件成功。設定先の3段階の優先順位、publisher への設定先引継ぎ、dummy token の非転送、不正な tree 応答、stdin/file/raw field、タイトル必須を確認した。ログは `/tmp/codex-services-272/review-green-github.log`。
- `CODEX_ISOLATION_REAL_GITHUB=1` の `tests/raw-codex-services.bats`: 2件成功・実 MCP 呼出し1件 skip。プロファイル経由で登録した `bunx`・`uvx` と Node が実 sandbox 内で起動した。実 gh の公開 repo/PR 参照は `GH_CONFIG_DIR` と `XDG_CONFIG_HOME` の両方で成功し、dummy token・設定先の非露出と制御 API 拒否も維持した。ログは `/tmp/codex-services-272/review-final-raw.log`。
- HEAD 不一致の拒否は、automation 変更と最初の正常 push より前に、実在する reviewed HEAD を使って検証する。広告 HEAD 検査だけを取り除いた一時コピーでは、この assertion が失敗した。`/tmp/codex-services-272/review-head-mutation/result.log`。
- Ruff lint/format は成功。追加で実行した `ty check` は13件の診断があり、変更前の `649cfab` でも同じ13件を確認した。既存の `Path(shutil.which(...))` や nullable subprocess stream 等の診断で、今回の変更による追加はない。型検査全体が成功したとは扱わない。

この round では全 suite・Linux VM・hosted model を使う両 MCP の実呼出しを再実行していない。前節の実 GitHub 書込み・人間が確認する外部連携の条件も未確認のまま。
