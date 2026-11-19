# ツール・管理スキル更新と Gemini 4 Neon（2026-11-20）

依頼原文は「`$implement ツールとスキルの更新 gemini 4 neon`」。導入済み AI ツールと管理スキルを点検し、Antigravity CLI で Gemini 4 Neon を選ぶ手順を確認する。Orca の `test/seanettle` で作業し、取得後の開始点 `b5f8989` は `origin/main` と一致した。

## 更新単位と予定

- AI ツールは [ADR-0045 の 2026-10-31 amendment](../adr/0045-separate-llm-agents-and-apm-update-units.md#2026-10-31-amendment-apmを除いてllm-agentsの出力を更新する) と [ADR-0047](../adr/0047-test-quality-floors-through-package-outputs.md) に従う。共通 snapshot の候補を対応3 system の binary cache と品質 floor で検証する。独立した APM 本体は現行の修正済み output を使う。
- 通常 APM は [native lock と配備比較](../../runtime/skill-harness.md#apm-lock-の生成) に従う。Matt Pocock と Impeccable は [ADR-0042](../adr/0042-mattpocock-managed-set-update-gate.md) と [ADR-0053](../adr/0053-separate-impeccable-skill-and-engine.md) の専用ゲート、公開 plugin は [ADR-0082](../adr/0082-extract-local-skills-to-public-repository.md) の固定版照合を適用する。
- Gemini 4 Neon の手順は Antigravity の [モデル選択](https://antigravity.google/docs/models) と [CLI の変更履歴](https://antigravity.google/docs/changelog?tab=cli) を根拠に runtime ガイドへ記録する。

## 採用した更新

| 更新単位 | 採用内容と確認 |
| --- | --- |
| AI snapshot | `60037f203e5f2dd1f318318c93e78a9a5e42646a`。Antigravity CLI 1.5.11 → 1.5.12、Claude Code 2.1.327 → 2.1.328、Codex 0.169.1 → 0.170.0。code-review-graph は 2.4.0 のまま依存先が変わる。Copilot CLI 1.0.114 と Herdr 0.9.5 は同じ output。Numtide cache で対応3 system × 6 package の登録を確認した。 |
| Gemini 4 Neon | `agy --model gemini-4-neon-xhigh` と対話中の `/model` を runtime ガイドに掲載した。1.5.12 では `GEMINI_API_KEY` で接続した場合にもモデルを選べる。利用可能な契約と手順は公式資料で確認した。1.5.12 の起動と `models --help` を Linux で確認した。 |
| 通常 APM | Orca CLI のスキルを `d840256c353f081efc4a1750a292b2dcee9daef3` に更新した。別のエージェントへのメッセージを扱う説明を含む。浮動依存3件は解決 revision だけが進み、選択 payload は同じ。 |
| Impeccable | 公開 skill 4.10.0 と同梱の版指定が要求する engine 0.1.27 を採用する。モーションレビューと分割された評価・新規制作ガイドを含む。対応3 system の公式 engine asset は同梱 checksum と一致した。 |
| 個別 CLI | Playwright CLI 0.1.25 は公開 plugin の既存パッチを適用できる。Cloudflare CLI 1.0.0-beta.31 は公開から満7日を過ぎた最新の `cf`。npm 公開日時は 2026-11-12 17:10:45 UTC で、既存7操作の schema は beta.29 と一致した。npm の lock は install script を無効にして生成し、`npm ci` を確認した。 |

Matt Pocock の公式配布対象に変更はなく、公開 `treflebonbon-skills` の最新 tag は現行の 0.4.1 と一致した。独立 APM 0.35.0、承認済み品質 floor、既存のモデル設定を使う。Waza の最新 standalone は現行 0.41.0 と一致した。Cloudflare CLI の beta.32 と RC は満7日未達のため今回の候補から除外した。

APM は native lock 生成、frozen install 前後の SHA-256 一致、audit 10/10 に成功した。両 target 各46スキルの配備を照合し、追加10・削除0を確認した。ledger は既存の所有権を保ち、更新した2スキルで所有する40件の hash が変わった。Linux では照合済み engine と候補 launcher で Design Hook 13件が成功した。Antigravity CLI 1.5.12 の一時 HOME で公開 plugin を公式 CLI から導入し、10スキルと全342ファイルを照合した。証跡は `/tmp/codex/update-tools-skills-20261120.CNPdKY/` に保存する。

実アカウントでの Gemini 4 Neon の選択と応答、ARM／Darwin での実行は未検証。依頼の実装範囲は task worktree の commit までとする。
