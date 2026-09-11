# #301 ブラウザ並列化の先行検証

2026-09-11 JST、[Issue #301](https://github.com/treflebonbon/dotfiles/issues/301) の合意済み契約に従って検証した。**portless と Windows Chrome の HTTP 経路に加え、手動認証後の実 PR への並列添付も成立した。独立 profile・フォーカス保持・新構成の共存条件は未確認であり、本実装の ready-for-agent 化に必要な実機検証は未完了。**

## 合意と追加条件

- Windows の worktree 別ブラウザを第一候補とし、通常の UI 検証では worktree ごとにログイン状態を保持する。
- 専用ブラウザの既存 GitHub 認証による並列添付を先に実証する。共有タブを認証のセキュリティ分離とは扱わない。
- portless は検証用アプリで評価し、実アプリの OAuth は各アプリの導入条件として記録する。
- ユーザーの追加指示により、バックグラウンド処理がフォーカス・カーソルを奪わないことを必須条件とした。headless と CDP を基本とし、OS 入力・前面化・自動 headed 起動を行わない。

調査方針は [ADR-0058](../adr/0058-validate-parallel-browser-workflows-before-adoption.md)。現行 wrapper と所有権管理の配備は変更していない。

## 環境と方法

- 調査 checkout: `90b9c5947ee32ffb0d4473ac02424c6df1b4ae64`。
- WSL2 mirrored networking、Windows PowerShell 呼出し成功。既存の `playwright-cli` 0.1.19 の Managed Windows Chrome を headless で利用した。
- CDP 操作は既存 package の `playwright-core` `1.63.0-alpha-2026-08-31` で行った。実際の Chrome version はこの試行では記録していない。
- portless `0.15.6`、Vite `8.2.2` を一時ディレクトリだけへ導入。npm integrity は証跡の `manifest.json` に保存した。Vite `8.3.0` は環境の公開後待機期間により導入を拒否されたため、その制約を変更せず、公開済みの `8.2.2` を使用した。
- `/tmp/triage-301-probe/fixture` に秘密情報を持たない Git repository を作り、`alpha` / `beta` の2 linked worktree で検証用 Vite アプリを起動した。この repository 自体の task worktree は変更していない。
- portless の state は専用ディレクトリ。HTTP proxy は loopback の `18431`、名称衝突試験は `18433`。`PORTLESS_SYNC_HOSTS=0` とし、hosts・CA store・service 設定を変更していない。
- ブラウザ操作は CDP の Page 参照を使用。OS のマウス・キーボード操作、`bringToFront` は実行していない。

## 初回の検証結果

| 検証 | 結果 | 観測と限界 |
| --- | --- | --- |
| 2 worktree の URL / PORT 分離 | 成功 | `alpha.probe301.localhost:18431` → `4672`、`beta.probe301.localhost:18431` → `4123`。PORT は各試行で自動割当。 |
| Windows からの並列表示・撮影 | 成功 | 両 URL を同時に開き、タイトルと表示が alpha / beta に対応。画像2枚を保存。ただし共有ブラウザ内の別タブであり、独立 profile の証明ではない。 |
| Vite HMR | 成功 | alpha の module 更新が反映され、クリック済み counter は `1` のまま。beta の module は `initial` のまま。 |
| アプリ間 proxy | 成功 | alpha から beta の metadata を取得。数値 loopback 宛ての転送では、送信時の Host を beta の hostname に明示設定した。 |
| 検証用 callback | 成功 | `PORTLESS_URL` から構成した `/callback?state=alpha` へ戻った。外部 OAuth provider は使っていない。 |
| 所有タブの終了 | 成功 | 新規作成した一方のタブだけを閉じても、もう一方は beta のまま利用可能。GitHub のアップロード処理ではない。 |
| CDP client の異常終了・再接続 | 成功 | 検証用 client を exit code `17` で終了し、別タブの生存と再接続を確認。Chrome process の crash や profile の復旧は対象外。 |
| 片方の server 終了 | 成功 | alpha の終了後、その route は利用できなくなり、beta の metadata 取得は成功。 |
| worktree 名の衝突 | 安全に拒否 | `feature/auth` と `fix/auth` は同じ `auth.probe301.localhost` となり、後発は exit code `1`。既存 route を強制取得していない。 |
| TLS transport | 部分確認 | 専用 proxy `18443` に検証用証明書を指定。Node client がその証明書だけを明示信頼した接続は成功（route 未登録の HTTP 404）。Windows Chrome は `ERR_CERT_AUTHORITY_INVALID` で拒否。証明書検証を回避していない。 |
| 現行の所有権競合 | 確認 | 別 CLI session の open は所有中の session/workspace を示して exit code `1`。 |
| CDP 接続失敗の区別 | 確認 | 未接続 endpoint への接続は 1500ms timeout。認証画面への転送とは異なる失敗として記録。低水準の ECONNREFUSED までは観測していない。 |
| GitHub 認証 | 利用不可 | 専用 browser の `/settings/profile` は `/login?return_to=...` へ転送。未ログインと期限切れはこの観測では区別できない。 |
| 実 PR への並列添付・本文更新競合 | 未確認 | 既存認証を利用できないため未実行。検証用 PR は作成していない。 |
| 独立 Windows profile・再起動後の状態保持 | 未確認 | 独立 profile の起動より前に、同じ script 実行経路の前提となるフォーカス観測 script が Windows execution policy で拒否された。 |
| フォーカス・カーソル保持 | 未確認 | 観測用 `focus.ps1` が `UnauthorizedAccess` で拒否された。headless / CDP の利用だけで「フォーカスを奪わない」とは断定しない。 |
| Playwright / Dogfood / Dashboard の新構成での共存 | 未確認 | 新しい所有権管理を実装していない。既存の単一所有者による拒否だけを確認。 |

## 試行中に修正した検証コード

- 初回の route probe は Node fetch に渡した Host が期待どおりのルーティングを得られず 404。`node:http` で Host を明示する probe に変更して正常応答を確認した。portless の失敗とは扱わない。
- Vite proxy の最初の設定では転送 Host が意図どおりにならず HTML 応答を得た。`proxyReq` で宛先 hostname を明示した後に beta の JSON 応答を確認した。この設定上の条件は導入時にも必要になる。
- 接続失敗試験の最初の assertion は ECONNREFUSED を期待していたが、実際は Playwright の timeout。観測結果を timeout として記録し、下位の原因は断定しない。
- Windows script 拒否は実行ポリシーの変更や別構文で回避していない。その経路を必要とする試験は未確認として残した。

## 採否と次の条件

### 手動認証後の追加検証

ユーザーが wizard で専用 Chrome の手動認証を完了した後、headless で GitHub の `/settings/profile` に到達することを再確認した。認証情報の読出し・コピーは行っていない。

検証専用 checkout から1枚の fixture 文書だけを commit し、各 checkout の topic branch を `git-push-topic` で公開した。現在の実装用 task worktree の未コミット文書は含めず、[Draft PR #302（alpha）](https://github.com/treflebonbon/dotfiles/pull/302) と [Draft PR #303（beta）](https://github.com/treflebonbon/dotfiles/pull/303) を作成した。両 PR は検証専用であり、マージ対象ではない。

| 追加検証 | 結果 | 根拠と限界 |
| --- | --- | --- |
| 既存認証での headless 接続 | 成功 | 設定ページへの到達だけを固定文字列で判定。cookie・storage の内容は取得しない。 |
| 異なる実 PR への並列添付 | 成功 | 各 PR の本文 editor を専用 Page で開き、alpha / beta の PNG を同時送信。S3 への実送信 request の区間が 1201ms 重なった。 |
| 画像 URL の本文への反映 | 成功 | アップロードごとに本文を再取得し、対応 placeholder だけを置換して `gh pr edit --body-file`。ブラウザ editor の古い本文は送信していない。 |
| 添付画像の対応 | 成功 | 両 PR で画像を表示でき、専用 browser context の認証を使った取得では HTTP 200。元画像と取得画像の SHA-256 がそれぞれ一致した。 |
| 一方の editor 終了 | 成功 | 所有する一方の Page を閉じても、もう一方の PR editor は生存した。 |
| 同一 PR の更新競合 | 成功 | PR #302 に対し2つの別 process を同時起動し、PR ごとの `flock` 内で本文取得→追記→更新を実行。両 marker と画像 URL が残った。ロックに参加する同一 WSL host 上の caller の検証であり、外部の編集者との分散排他を保証しない。 |
| 添付通信の失敗 | 故障注入で確認 | 所有する1つの Page だけで upload policy request を abort。新しい画像 URL は増えず、保存済み PR 本文は不変、他方の PR の画像は利用可能。GitHub 自体の実障害を観測したものではない。 |

画像 URL は以下。公開される本文には GitHub が返した添付 URL だけを使用し、signed redirect URL や認証情報を記録しない。

- alpha: `https://github.com/user-attachments/assets/62196445-7843-4d71-8fa4-8e851674a93d`
- beta: `https://github.com/user-attachments/assets/737fa669-a8fa-41cb-918b-fc7d4fd4821d`

初回の画像再取得は認証なしの Node fetch で失敗した。アップロードと PR 本文更新はその時点で成功済みだったため再送せず、既存 browser context の認証で取得して表示・内容を確認した。添付 URL の匿名アクセスを保証する結果ではない。

故障注入の準備では、本文更新後に追加された `edited` 履歴を先頭の summary として選んでしまい、Edit の取得が timeout した。観測した DOM に基づき `summary.timeline-comment-action` を選ぶよう変更して試験を完了した。本実装では本文の所有タブだけでなく操作メニューも明示的に選ぶ必要がある。失敗試験の `errors` は非表示のエラーテンプレートも含む DOM text であり、各文言が画面表示された証拠とは扱わない。request の abort、画像 URL の非追加、保存済み本文と他方の画像の保持を検証結果とする。

Windows script 経路についても読み取り診断した。実効 ExecutionPolicy は `Restricted`、各 scope の設定は `Undefined`。既存 Managed Chrome wrapper は `powershell_action` で `-ExecutionPolicy Bypass` を指定している。既存 wrapper の利用と、新規検証 script に同じ指定を追加することは区別し、今回その指定を新規 script へ拡大していない。フォーカス観測・独立 profile の試験は引き続き未確認。

### 現時点の判断

portless は **任意導入の候補として継続評価、標準配布への採用は保留** とする。HTTP の URL 分離・HMR・proxy の適合性は確認できたが、branch の末尾名だけでは一意性が足りず、Windows の TLS 信頼セットアップも未完了。ブラウザ所有権・共有添付の問題を portless で解決したとは扱わない。

実アプリへの導入条件は、待受け PORT と公開 URL の使い分け、転送 Host、Windows の名前解決と TLS 信頼、provider の callback allowlist と公開 URL 設定の整合である。検証用 callback の成功を実 OAuth の保証にしない。

専用 GitHub profile の手動認証と並列添付は追加検証で確認できた。残る実機検証には、フォーカス観測・独立 profile 起動を実行できる承認済み Windows 経路が必要。バックグラウンド処理から手動認証用の画面を開かず、通常閲覧用 profile や認証情報のコピーで代用しない。OS の CA/hosts 等を変更する場合も、具体的なセットアップ内容を確定してから扱う。

#301 は `enhancement` / `needs-triage` を維持する。本実装の Agent Brief と `ready-for-agent` は、共有添付・独立 profile・フォーカス保持・共存条件の検証後に確定する。

## 証跡と終了処理

Session Scratchpad を特定できなかったため `/tmp/triage-301-probe` を明示 fallback として使用した。

- `manifest.json`: package integrity と主要 artifact の SHA-256。
- `portless-results.json`、`connection-results.json`、`extra-results.json`: 成功した最終試行の観測。
- `results-attempt1.json`、`results-attempt2.json`、`portless-results-attempt1.json`: route probe・Windows script・proxy 設定の失敗記録。
- `portless-probe.mjs`、`connection-probe.mjs`、`extra-probe.mjs`、`app.mjs`: 検証コード。環境固有の絶対パスを含む一時 probe であり、配布する実装ではない。
- `alpha.png`、`beta.png`: Windows headless Chrome で取得した検証用画面。
- `ownership-conflict.log`: 現行 CLI の所有権競合。
- `upload-results.json`、`upload-verification.json`、`same-pr-results.json`: 認証後の並列アップロード、画像照合、同一 PR 更新の観測。`upload-results.json` の失敗記録はアップロード後の匿名再取得失敗であり、後続の認証付き取得で補完した。
- `upload-probe.mjs`、`verify-upload.mjs`、`update-same-pr.sh`: 実 PR を使った検証コード。`rendered-alpha.png` / `rendered-beta.png` は PR 上の添付画像表示。
- `upload-failure-probe.mjs`、`upload-failure-results.json`: Page 単位の upload request 故障注入。認証や context 全体の通信設定は変更していない。

検証用 app/proxy/client process は終了した。Managed Chrome は所有した `triage-301-fixture` session を通常の close で終了し、所有者記録が `null` に戻ったことを確認した。proxy の3つのポートも待受けがない。検証用 repository と一時 artifact は残し、削除・ブラウザの強制終了・CA store 変更を終了処理に含めない。検証用 TLS private key は共有する証跡に含めない。

## 一次情報

- [portless README（調査時の固定 revision）](https://github.com/vercel-labs/portless/blob/1ad573bb95810daf6cd50c1718707015450f3f09/README.md)
- [portless OAuth ガイド（同 revision）](https://github.com/vercel-labs/portless/blob/1ad573bb95810daf6cd50c1718707015450f3f09/skills/oauth/SKILL.md)
- [Microsoft: Networking interop](https://learn.microsoft.com/en-us/windows/dev-environment/wsl-interop#networking-interop)

文書の revision と npm package の版は別に記録している。実機結果は固定した npm package `0.15.6` に対するもの。

## 2026-09-11 承認後の独立 profile / フォーカス観測

上記の Windows 経路未承認という記録は、この追加検証で更新する。ユーザーが新規 probe の2つの PowerShell script へのプロセス限定 Bypass 指定を承認し、prototype/301-browser-ownership の probe を実行した。実効ポリシーは実行後も Restricted。

独立 headless Chrome 2つで同一 origin の dummy cookie / localStorage 分離に成功。A の正常終了・再起動で状態が残り、B が利用可能であることも確認した。最後に両 profile の Chrome 停止を確認し、profile は保持した。

前面 window handle は約90秒の436 sample すべてで同じ。Chrome 操作区間約21.4秒の104 sample でも同じだった。一方、cursor は全体15種類、操作区間5種類の位置を記録した。読取り失敗は0。人間の操作の有無が未確認なのでカーソルへの影響は未確定。200ms間隔の標本であり、短い前面切替の見逃しを排除しない。

raw evidence: /tmp/prototype-301-1789084461708/。集計と検証コードは prototype branch の private_dot_config/nix-devshell/packages/prototype-301/ に保存。Dogfood / Dashboard 共存は未検証で、#301 の needs-triage を維持する。

### 再観測と共存範囲の合意

前回のマウス操作はユーザーも覚えていないため、操作を控える観測条件を案内して同じ承認済み probe を再実行した。436 sample のうち Chrome の操作区間約22.1秒・107 sample では前面 window と cursor 座標がともに不変、読取り失敗0。90秒全体の cursor 位置は14種類だったが変化は操作区間外。独立 profile・状態保持・両 Chrome の停止も再確認。証跡 /tmp/prototype-301-1789086142063/。今回の標本で干渉を観測しなかったという結論であり、無制限の保証ではない。

Q6 は別 browser identity の並列利用と同一 identity の headless / headed 競合拒否で合意した。既存の所有権管理15件、headless / Dashboard / Dogfood の競合3件のテストは成功。これらは現行の安全な拒否を確認するテストで、新構成の共存試験ではない。

新構成の共存には全体排他から identity ごとの管理への変更が必要。共存を本実装の必須受入条件に移すか、追加 prototype で先行実装するかは Q8 で確認中。

## Triage の確定（Q8）

ユーザーは共存試験を本実装の必須受入条件へ移す推奨案を選択した。先行検証と Q6 の共存範囲に基づき Agent Brief を確定し、#301 を ready-for-agent とする。過去節の needs-triage / Q8 未回答の記述は当時の経過を示す。新構成での共存試験を未実施のまま成功と扱うことは認めず、実装完了には全 AC の検証が必要。

portless は今回の標準配布・必須依存には採用しない。任意導入の候補と実アプリごとの適合条件は維持する。prototype branch は一次資料として保持し、main には試作 HTML や probe を取り込まない。
