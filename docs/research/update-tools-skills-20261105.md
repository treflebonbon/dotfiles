# ツール・管理スキル更新（2026-11-05）

## 依頼と作業境界

今回の依頼原文は「`$implement ツールとスキルの更新`」。ユーザーが選択した「AI ツール＋全管理スキル＋個別 CLI」を調査対象とし、既存の配布経路と検証ゲートで採否を判断する。言語ランタイム・テンプレート・root 開発依存の一括更新は対象に含めない。過去の更新記録は参考資料であり、今回の追加要件とは扱わない。

開始点は HEAD / `origin/main` `c3b8ac2b2a995eaf4bd3539bab24224bb7790951`。Orca native task worktree `/home/ubuntu/orca/workspaces/dotfiles/eelpout`、branch `test/eelpout` は fetch 後に physical root・Git dir・common dir・clean status を確認した。実装・検証・独立レビュー・コミットを完了範囲とし、PR 公開・merge・live 配備は含めない。

## 更新単位と予定変更

| 更新単位 | 適用する判断 | 予定する変更・判定 |
| --- | --- | --- |
| AI snapshot | ADR-0045 の更新単位分離と2026-10-31 amendment、ADR-0047 の品質 floor | default branch HEAD を固定し、6ツール×3 system の version・output・cache と Linux 起動を確認する。新しい独自 patch・source build は追加せず、APM は修正済み既存 output を維持する。 |
| 通常 APM payload | ADR-0045、runtime/skill-harness.md の隔離 lock 生成・配備比較 | 全 dependency の selected subtree を比較し、実体差分を採否判断する。native install・frozen 不変・audit・両 target・ownership ledger を照合する。 |
| Impeccable skill / engine | ADR-0053 の一体検証 | 安定 release に差分があれば Design Hook gate で検証する。 |
| Matt Pocock managed set | ADR-0042 の ordered gate | 公式 full set に差分がある場合に専用 gate を使う。 |
| 公開 skills plugin | ADR-0082 の complete pin record・公式導入・current payload 照合 | 前回却下候補の原因と新しい release を再確認し、受入条件を満たす候補だけ採用する。 |
| 個別 CLI | 現行の公式 binary / Nix 配布方式、Cloudflare CLI の満7日条件 | Playwright CLI、waza、design.md、文書変換 CLI、Cloudflare CLI を調べ、配布経路を変更せず検証できる候補を採用する。 |

pin 更新に伴うテスト期待値と現行 runtime 文書の訂正を含む。候補の採用・却下・保留と理由、分割時に外した変更の対応先・検証状態を追記する。

## 証跡

調査と候補 runtime は `/tmp/codex/update-tools-skills-20261105.Jaf41M/` に保存する。検証は `scripts/verification_env.py` / `scripts/verify-ai-tools.py` から開始し、通常 HOME を書込み対象にしない。

## 調査結果と採否

| 更新単位 | 採否と根拠 |
| --- | --- |
| AI snapshot | [`499fb79f92064e92cdb968d12ffeb92d36243b50`](https://github.com/numtide/llm-agents.nix/tree/499fb79f92064e92cdb968d12ffeb92d36243b50) を採用する。Claude Code 2.1.317 → 2.1.318、Antigravity CLI 1.4.12 → 1.5.0。code-review-graph 2.3.9 は版据え置きで依存と output が変わり、FastMCP は3.4.7となる。Codex 0.166.0・Copilot CLI 1.0.105・Herdr 0.9.5 は3 system の derivation・output とも不変。upstream 内部の nixpkgs 更新だけを native lock に反映し、共有 nixpkgs と独立 APM input は維持する。 |
| 通常 APM | 全21 dependency の配備 bytes と metadata は、shadcn・find-skills・orchestration の floating `resolved_commit` だけを除き完全不変。native lock の3 revision 更新を採用し、manifest は維持する。orchestration は調査開始時の HEAD と異なる `dabdb606…` に native install で解決したが、既存 content hash と全配備 bytes の不変を確認した。 |
| Impeccable / Matt Pocock | 安定版 skill 4.8.0 / engine 0.1.18 と、公式27件の Matt 1.3.2 の現行 pin を維持する。Impeccable の未リリース HEAD は採用しない。Matt は engineering・productivity・plugin manifest が HEAD と同一であり、専用 ordered gate が必要な payload 更新はない。 |
| Orca computer-use / Herdr | computer-use の上流削除は採用せず既存 exact pin を維持する。Herdr の selected subtree は不変で、現行0.9.5相当の pin を維持する。 |
| 公開 skills plugin | [0.2.6](https://github.com/treflebonbon/skills/releases/tag/v0.2.6) `efa5ad0a…` は Windows browser 資産の解決・添付 browser の復旧案内等に差分があるが、Antigravity 1.5.0 でも strict validator が失敗するため却下する。root `AGENTS.md` が plugin の rules として読み込まれない warning が原因。validator・上流テスト・配布物を変更せず、0.2.3 の complete pin record 全体を維持する。 |
| waza | [0.40.0](https://github.com/microsoft/waza/releases/tag/v0.40.0) を採用する。既存の3 system の公式 standalone binary を取得して hash を更新する。task-level MCP mocks と before_run の実行順に挙動変更があるため release note を確認した。repo に waza の実行設定はなく、導入・CLI 検証だけを行う。モデル・有料 provider は呼ばない。 |
| Cloudflare CLI | [1.0.0-beta.25](https://github.com/cloudflare/cf/releases/tag/cf%401.0.0-beta.25) を採用する。npm 公開日時 2026-10-28T22:04:07.158Z は満7日条件を満たす。beta.26 / beta.27 は未達のため却下する。公式 npm 配布・install script 無効化・既存 helper と固定 endpoint を維持し、package lock・依存 hash・版照合・テスト・ADR の現行版を一緒に更新する。 |
| 他の個別 CLI / plugin | npm latest の Playwright CLI 0.1.23、design.md 0.4.0 と Ponytail の公開安定版5.3.3は現行と一致し維持する。調査時に誤った design.md の repository URL を試して失敗したが、npm metadata が示す公式 `google-labs-code/design.md` と区別する。runtime が自動管理する plugin の導入状態は source 更新に含めない。 |
| 文書変換 CLI / APM 本体 | Defuddle 0.19.6 / MarkItDown 0.1.9 は公開済みだが、現行 source-only Nix 定義の更新と新しい build 検証が必要になるため今回は候補を採用しない。既存0.19.3 / 0.1.7と取得経路を維持する。APM も ADR-0045 の独立単位どおり、修正済み0.35.0の既存 output を維持する。新規 patch や取得経路を追加しない。 |

今回の変更は一つの branch に集約し、PR 分割は行っていない。公開 plugin の新 pin と年齢条件未達の Cloudflare 候補、未リリース Impeccable、文書変換 CLI の切替を source 差分へ含めず、上表で却下として追跡する。実装ロジックは変更せず、既存の公開境界テストで version / pin と安全契約を検証するため、新たな TDD seam の設計は行わない。

## 個別検証

- **確認済み（metadata / cache）:** `llm-matrix.json` で6ツール×3 system の新旧 version・derivation・output を照合した。Nix の cache 照会は18件すべて成功し、`--max-jobs 0 --builders ''` で Linux の6 output を取得した（`nix-cache.exit-code` / `outputs.exit-code` とも0）。ビルドへの fallback はない。ARM / Darwin は評価と cache の確認であり、実機起動は未確認。
- **確認済み（APM）:** 共通生成スクリプト・frozen 前後 SHA-256 `02e7ede7e29eb477c74449de978082bc6190983860d7aa74835616b64c6ecf4d` 不変・audit 10/10 が成功。配備比較は21 dependency、両 target 各47 skill、追加0・削除0。`ledger-result.json` で root metadata・全 deployment ledger・owner・active_owner・共有 record の不変と、3件以外の全 dependency metadata 不変を独立に照合した。
- **確認済み（公開 plugin 候補）:** 0.2.6 の静的テストは17成功・公式 CLI の4件は opt-in skip。Antigravity の strict 検証は1.4.12 / 1.5.0で同じ warning を返し exit1（`plugin-agy-1.5-validation.json`）。採用を維持する0.2.3は1.5.0の strict 検証に成功した。最初の archive 展開には Git index がなく静的テスト1件が実行環境の不備でエラーになったため、scratch に index を用意して静的テストを再実行した。cache 取得中の1.5.0を先に起動した試行は `Text file busy` で終了しており、取得完了後の validator 結果と分ける。新しい model session は呼んでいない。
- **確認済み（waza / Cloudflare）:** 公式3 binary を取得し、`waza-assets.json` に SHA-256 を保存した。Linux 版の `--version` は0.40.0、`--help` も成功。Nix が組み立てた package でも waza 0.40.0 / cf 1.0.0-beta.25 の版表示が成功した（`package-smoke.log` と対応する `startup.log`）。Cloudflare の許可済み6操作は、新旧の schema JSON 全体が同一だった（`cf-schema-comparison.json`）。実 credential・実 API は呼んでいない。
- **確認済み（graph / 公式再同期）:** code-review-graph の Python fixture は build / status が成功し、1 file・3 nodes・3 edges を得た。CLI 起動・graph 処理の検証であり、MCP / モデル・他言語の実行は未確認。Claude Code 2.1.318 では維持する plugin 0.2.3 の公式導入と2回の再同期が成功し、両回とも設定 bytes と267 files を保持した（`/tmp/codex/claude-plugin-native.i8l28j_f/result.json`）。
- **確認済み（Nix 評価）:** 両 flake の `nix flake check --no-build --all-systems` が成功。root の app に `meta` がない既存 warning は残る。

通常 HOME の配備、PR 公開・merge、実 Windows Chrome、モデル呼出しは検証範囲に含めない。
