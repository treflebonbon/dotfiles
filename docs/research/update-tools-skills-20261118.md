# ツール・管理スキルとモデル更新（2026-11-18）

## 依頼と作業境界

依頼原文は「`$implement ツールとスキルの更新。GPT-6.2 Astra Sol。codexのモデル変更。claudeのモデル変更 claude opus, adviser fable。`」。追加回答で Codex は親 `gpt-6.2-sol / xhigh`、subagent `gpt-6-luna / xhigh` 維持を選択した。Claude は実行 `opus`、advisor `fable` とする。

Orca task worktree `/home/ubuntu/orca/workspaces/dotfiles/barnacle`、branch `test/barnacle` の root・Git dir・common dir・clean status を接続済み実行環境で確認した。fetch 後の HEAD と `origin/main` は `cf87cd68f8fc691c7188ab0332bfaf7c8b584087` で一致し、同 branch の既存 PR はない。隔離 shell から Git metadata は参照できないため、検証に成功した接続済み実行環境で作業する。PR 公開・merge・live 配備は今回の実装範囲に含めない。

## 更新単位と予定変更

| 更新単位 | 根拠と予定 |
| --- | --- |
| AI snapshot | ADR-0045 の更新単位分離・2026-10-31 amendment と ADR-0047 の品質 floor に従い、upstream default branch を一度確認した `1bd66a577d1f975927ddfed1a30b2cb19dba1ddc` を候補に固定する。3 system の版・output と Linux 起動を確認する。共有 nixpkgs と修正済み独立 APM は維持する。 |
| Codex モデル | 追加回答に従い親だけ `gpt-6.2-sol / xhigh` に更新し、subagent の役割を維持する。管理 config・親指示・同期テスト・現行 runtime 文書を更新する。Astra は明示選択の案内と利用可否を確認する。 |
| Claude モデル | `model: opus`、`advisorModel: fable` に変更する。既存の experimental advisor 有効化設定・subagent の sonnet・effort は維持する。候補 CLI の設定対応と実行経路を確認する。 |
| 通常 APM payload | ADR-0045 と `runtime/skill-harness.md` の native lock 生成・frozen 不変・audit・両 target 配備比較に従って全 dependency を調査する。 |
| Impeccable / Matt Pocock | ADR-0053 / ADR-0042 の各専用ゲートに従う。実体差分がなければ pin を維持する。 |
| 公開 skills plugin | ADR-0082 の完全な pin record と公式導入契約を適用する。最新公開 tag は現行 0.2.10 と同じ `fd2a50c558288b3661e5066b94b1196453ef9269`。同じ版の未公開 payload は採用しない。 |
| 個別 CLI | 現行の配布経路と Cloudflare CLI の満7日条件で調査し、既存の検証方法で採否を決める。 |

新規の独自 patch・source build は追加しない。必要変更の保留、候補の却下、未検証事項を区別する。実装ロジックの追加がない変更には新しい TDD seam を設けず、既存の公開境界テストを更新・実行する。

証跡は `/tmp/codex/update-tools-skills-20261118.KEZzVN/` に保存する。Nix と検証は `scripts/verification_env.py` / `scripts/verify-ai-tools.py` / `scripts/run-canonical.py` の書込み境界を使う。

## 公式資料

- [GPT-6.2 のモデル ID と Codex での選択](https://learn.chatgpt.com/docs/models)
- [GPT-6.2 Sol](https://developers.openai.com/api/docs/models/gpt-6.2-sol)
- [Claude Code のモデル alias](https://code.claude.com/docs/en/model-config)

## 採否と検証

| 更新単位 | 採否と根拠 |
| --- | --- |
| AI snapshot | `1bd66a577d1f975927ddfed1a30b2cb19dba1ddc` を採用する。Claude Code 2.1.322 → 2.1.327、Codex 0.167.0 → 0.169.1、Copilot CLI 1.0.109 → 1.0.114、Antigravity CLI 1.5.5 → 1.5.11、code-review-graph 2.3.9 → 2.4.0。Herdr は0.9.5のまま output が変わる。upstream 内部の nixpkgs は更新され、共有 nixpkgs・独立 APM 0.35.0・品質 floor は維持する。Codex 0.170.0 は固定した snapshot に未収録なので待たず、独自の package override は追加しない。 |
| Codex モデル | 管理 source と親向け指示を `gpt-6.2-sol / xhigh` に変更する。子の `gpt-6-luna / xhigh` は維持する。候補 Codex 0.169.1 の同梱 catalog は Sol / Astra を `visibility: list` で含み、両方と Luna に `xhigh` がある。実アカウントの新モデル呼出しは未実施であり、同梱 catalog を利用資格の証明とは扱わない。 |
| Claude モデル | `model: opus` / `advisorModel: fable` を採用する。render した JSON で両設定と子の sonnet・既存 high effort を確認した。[公式 advisor 資料](https://code.claude.com/docs/en/advisor)は Opus 5.5 → Fable の組合せを認める。過去の undocumented な内部構造の記録を現行版の保証として扱わないよう runtime の説明も訂正した。Fable の利用資格・必要な初回の usage credits 同意・実際の advisor 呼出しは未確認であり、同意・課金設定は変更しない。 |
| 通常 APM | PDF、Modern Web Guidance、empirical-prompt-tuning、Remotion、Orca CLI / orchestration を更新する。PDF の参照ファイルが大文字へ修正されたため、runtime の小文字を読む上書きを撤去する。Modern Web Guidance は検索・参照案内を更新し16 guideを追加、Remotion 4.0.545 は動画 matting と OpenTimeline の案内を追加して重複する旧 maps 資産を整理する。Orca は version-matched guide への委譲を維持し、transient error で安易にウィンドウを起動しない案内と役割分担を取り込む。 |
| Impeccable | 最新公開 skill 4.9.1 の commit `acb4cfe14470b1fdf51e855431af618d936b7db8` と、それが指定する engine 0.1.24 を一体で採用する。未公開 HEAD の4.9.2は採用しない。launcher のプロセス起動削減・download error の説明と foundations の案内を含む。Claude / Codex の13件の Design Hook gate は全件成功・skipなし。 |
| Matt / その他の pin | Matt の公式27件は HEAD の selected subtree と同じなので現在の pin を維持する。security-audit、Effect-TS、Supabase、Vercel の4 skill は実体が同じ。computer-use の上流削除は採用せず既存 pin と payload を維持する。 |
| 公開 skills plugin | 最新公開版は現行0.2.10のまま。HEAD は version を更新せずに payload が変わっているため採用しない。complete pin record を維持する。 |
| Waza | [0.41.0](https://github.com/microsoft/waza/releases/tag/v0.41.0) を採用する。trial timeout 後の結果保持、JavaScript grader の標準入力、CLI 契約の修正を含む。3 system の公式 standalone binary を取得し、公開 digest と実 SHA-256 を照合した。Linux の raw binary は `waza version 0.41.0` を返した。 |
| Cloudflare CLI | 1.0.0-beta.29 を採用する。公開日時は2026-11-10T18:09:16.119Zで、調査時点で満7日を経過している。最新 rc.1 は満7日未達なので採用しない。native npm lock・install script 無効の frozen install・依存 hash 取得が成功した。許可済み7操作の schema を全体比較し、引数の flag / positional 情報・説明文・telemetry の preview field 追加を確認した。HTTP method・endpoint と既存フィールドは維持され、helper が受理する操作・引数を増やしていない。実サービスや実 credential は使わない。 |
| その他の CLI | Playwright CLI 0.1.24 を既存の public browser patch と Nix 配布経路で採用する。native npm lock・install script 無効の frozen install・依存 hash 取得と Nix package build が成功した。design.md 0.4.0 と Ponytail 5.3.3 は公開版と一致し維持する。Defuddle / MarkItDown の source-only backport と独立 APM 本体は、新しい source build を追加しない境界で維持する。 |

## 個別検証

- 両 flake の3 system評価と TypeScript 型検査が成功した。
- Waza / Impeccable の計6つの公式 binary は `assets/result.json` の全件が検証済み。ARM / Darwin の実機起動は未実施。
- native APM lock は `apm-commit.exit-code` が0、frozen 前後の SHA-256 不変、audit が成功した。20 dependency・両 target 各46 skill の全配備 file を照合した。予定した追加42・削除42、root ledger 各1512件、候補7件に属する368 hash record の変更を独立検証し、候補外は4件の floating revision のみの前進を除いて不変だった。`apm-ledger-result.json` に結果を保存した。
- 最初の Impeccable pin は annotated tag object の SHA だったため、native install の解決 commit と不一致になり frozen が拒否した。source を tag の実 commit `acb4cfe...` に直し、新しい隔離 runtime で native lock を再生成した。失敗 lock の手修正や採用は行っていない。
- Design Hook 13件と、render した Claude 設定の実行 opus・advisor fable・子 sonnet・high effort の確認が成功した。

- 候補5 CLI の絶対 path・版表示と source の output が一致した。6 package × 3 system の18 output は Numtide cache の照会が成功した。
- 関連 Bats の初回試行中に、旧 snapshot SHA を固定した期待値の失敗を確認した。source と lock が同じ完全 SHA を指す検査へ変更し、Playwright の版期待値も package.json から導出する形にした。修正対象2件の新しい標準検証は終了0だった。全体の網羅的な結果は最後の canonical で確認する。
- Claude Code 2.1.327 では、既存の公式同期 helper による管理 settings の2回再同期が終了0だった。別の新規隔離実行で、Codex 0.169.1 と Antigravity 1.5.11 による公式導入が、それぞれ plugin 0.2.10・288 file で成功した。対話・ログイン・モデル呼出しは行っていない。
- 独立レビューは実装 commit `20d395a07cc0c6d608e866fd0480bed82f6b0901` を固定し、既存 Codex 接続の GPT-6 Luna / xhigh を明示して Standards / Spec を並列に実行した。両者が root・branch・HEAD・Git metadata を照合した。Standards は D1 helper の旧 beta.26 期待値を1件指摘し、Spec は欠落・範囲拡大・誤実装の指摘0件だった。D1 の期待値は配布 package.json の pin から導出する形へ修正し、同 helper の19テストが全て成功した。実装ロジックの追加はない。
- 2.1.327 の advisor 内部構造も公開 binary で再検証した。kill switch → experimental env var → feature flag、候補 alias、rank 比較と追加の利用資格条件を確認し、runtime の現行説明と履歴を区別した。実 advisor 呼出しは未確認のままとする。
- 既存の `/tmp/codex` 公開ログの一部は、明示的な write 許可とユーザーの再承認後も自動審査に読み取りを拒否された。拒否された file を別経路で読まず、必要な現在の source の検証を新しい標準実行から確認した。通常 HOME の管理対象設定と live 配備は変更していない。
- canonical 用の Impeccable は、固定 commit を Nix store へ新規取得して準備した。native lock の64 file hash と照合し、`.cmd` だけは APM の LF 表現に正規化すると一致した。他63 file と Linux で使う Bash launcher は raw bytes が一致する。Windows での `.cmd` 実行は未確認であり、今回の Linux 検証とは区別する。

## canonical の初回試行と補正

`0a417c3` の初回 canonical は `tmp/canonical-run.hf4a67tb/`。834件の計画に対し、APM の旧 revision / content hash を固定した期待値3件の失敗を確認した。失敗確定後にこの task が開始した process group だけを終了し、途中結果の TAP を保持した。完了記録のない中断試行を成功とは扱わない。

`tests/apm-runtime.bats` の既存の承認済み payload の検査を維持し、native install・frozen・audit・全配布 file / ledger 照合を通過した今回の pin / content hash へ期待値を更新した。この file の新規検証は17件成功・1件 skip・失敗0件。skip は現在の agent runtime が source の `.agents` を mount している条件による既存のもの。Orca orchestration の floating 解決先は native install 中に `a22cdd66...` へ進んだが、調査時 `a1fda350...` と `SKILL.md` の Git blob `3dd0a7cf24740d6ff0fceaba1fc6301540a3f8b2` が同じことを GitHub の immutable ref で照合した。

この補正を含む最後の commit で全834件の canonical を新規実行する。結果は生成された `result.json`・前後記録・TAP を正本として最終報告に記載し、成功後に結果追記だけの変更は行わない。
