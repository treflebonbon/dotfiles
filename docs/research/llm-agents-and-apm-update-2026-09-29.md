# ツールとスキル更新（2026-09-29）

## 要件と採用境界

Anthropic が 2026-09-28 に Claude Sonnet 5.5（`claude-sonnet-5-5`、Opus 5.5 に次ぐ Claude 5.5 ファミリー第2弾、Sonnet 5 と同一課金・1M context）を発表したことを受け、ユーザーの `/ask-matt claude sonnet 5.5 に対応したバージョンに更新` から `/implement` へ合流し、既存 AI tool snapshot を Sonnet 5.5 対応版へ更新する。ADR-0045 に従い、この更新単位は llm-agents snapshot のみを対象とし、通常 APM payload・Impeccable・Matt Pocock managed set は対象外とする（今回の動機と無関係な upstream 進捗を確認する必要がない）。task worktree は main `acb6df4` から作成した。

受入条件は exact snapshot と lock の整合、3 system の評価、Linux build・CLI起動、関連テスト・型チェック・full suite、二軸レビューとコミット。品質 floor は根拠がある場合のみ変更する。モデル・権限設定、配布経路、新規ツール追加、private skill 改稿、通常 APM payload は対象外。live apply・push・PR は行わない。

## Tool snapshot

Claude Sonnet 5.5 の存在を WebSearch で確認した後、Claude Code 公式 CHANGELOG（`anthropics/claude-code` の `CHANGELOG.md` を直接 `curl` して逐語確認、AI 要約ではなく原文）で、バージョン **2.1.284** が "Added Claude Sonnet 5.5 (`claude-sonnet-5-5`), now the default Sonnet model on the Anthropic API — 1M context, $2/$10 per Mtok with $0.20/Mtok cache reads" を追加したことを確認した。

`numtide/llm-agents.nix` の commit 検索（`gh api search/commits`）で claude-code 2.1.283→2.1.284 の bump commit `fe037ebd459c2eb90b143efb52806f5213a59052`（merge `b1e1d3eb028514ec804534939d545b7f3d5168a5`、2026-09-28T23:06:01Z）を特定し、`gh api compare` で旧 pin `e28ea84e78517e5d05ae0c399da00e848e207261` から upstream default branch HEAD `ee7041016e9b6de43f7ba4cce04272518f7cfaa9`（2026-09-28T23:41:53Z、62 commit 先行、0 commit 遅れ）までの範囲にこの bump commit が含まれる（HEAD から50 commit 先行・0 commit 遅れ）ことを確認した。

| ツール            | 旧版    | 候補    |
| ----------------- | ------- | ------- |
| Claude Code       | 2.1.283 | 2.1.284 |
| Codex             | 0.157.1 | 0.158.0 |
| Copilot CLI       | 1.0.88  | 1.0.89  |
| Antigravity CLI   | 1.2.12  | 1.2.12  |
| RTK               | 0.50.0  | 0.50.0  |
| APM               | 0.32.0  | 0.32.0  |
| Herdr             | 0.9.1   | 0.9.1   |
| code-review-graph | 2.3.9   | 2.3.9   |

Claude Code 2.1.284 の公式 CHANGELOG から、この repo の quality floor 判断基準に合致する項目として以下を確認した:

- **Sonnet 5.5 の追加**（今回の直接動機）: "Added Claude Sonnet 5.5 (`claude-sonnet-5-5`), now the default Sonnet model on the Anthropic API"

他に、symlink 経由の `.claude` external-imports approval bypass 修正、`allowManagedPermissionRulesOnly` 下でのプラグインツール事前承認 bypass 修正、auto-memory 読み込み時の markup injection 無害化改善、Linux での write-denied+read-denied ディレクトリを含む sandboxed Bash 起動失敗の修正を確認したが、いずれも既存の `minClaudeCode` 判断基準（多 agent ワークフロー・worktree 隔離・permission/trust boundary の信頼性）の枠内で Sonnet 5.5 追加ほど直接的ではないため、床上げの主根拠には含めない（Sonnet 5.5 追加自体が単独で十分な根拠）。よって `minClaudeCode` を `2.1.283` → `2.1.284` へ引き上げ、pin も `2.1.284`（最新）を採用する。

Codex は公式 GitHub Release Notes（`rust-v0.158.0`、`gh` ではなく WebFetch で該当ページを直接取得し原文を逐語確認）から次を確認した:

> Terminal input approval is enabled by default for commands running with elevated permissions; runtime-only grants no longer cause unnecessary reviews.
>
> Secure direct exec-server WebSocket connections with bearer tokens, including connections configured through app-server.

前者は昇格権限コマンドの承認フローのデフォルト強化、後者は exec-server の WebSocket 接続に対する認証強化であり、[ADR-0047](../adr/0047-test-quality-floors-through-package-outputs.md) の Codex floor 判断基準（sandbox・trust boundary の信頼性）に合致する。よって `minCodex` を `0.157.0` → `0.158.0` へ引き上げる。

Copilot CLI 1.0.88→1.0.89 は非公開 changelog のため package metadata の追従のみ確認した。Antigravity CLI・RTK・APM・Herdr・code-review-graph は snapshot 内でも変化なし。

`flake.nix` の `llm-agents.url` を直接書き換え（この設計では `nix flake update llm-agents` 単体では進まない）、`nix flake lock` で lock を再生成した。共有 nixpkgs（`nixpkgs-26.05-darwin`）は変化せず、llm-agents 自身の内部 nixpkgs input のみ upstream pin に従い更新された。`nix flake check --no-build --all-systems` は全6 devShell と3 formatterの評価に成功した。3 system の `nix eval` で claude-code 2.1.284 / codex 0.158.0 / copilot-cli 1.0.89 / antigravity-cli 1.2.12 / rtk 0.50.0 / apm 0.32.0 / herdr 0.9.1 の版が一致することを確認した。x86_64-linux (host) では `nix develop .#default` で実ビルドし、claude / codex / copilot / agy / rtk / apm / herdr / code-review-graph の8 CLI 実測 version が snapshot と一致することを確認した（`claude --version` → `2.1.284 (Claude Code)`、`codex --version` → `codex-cli 0.158.0`、`copilot --version` → `1.0.89`、`agy --version` → `1.2.12`、`rtk --version` → `0.50.0`、`apm --version` → `0.32.0`、`herdr --version` → `0.9.1`、`code-review-graph --version` → `2.3.9`）。

### Advisor tool 再検証（ADR-0005）

Claude Code の quality floor 引き上げ（2.1.283→2.1.284）を機に [ADR-0005](../adr/0005-advisor-tool-default-enable.md) の再検証トリガーを踏んだ。実ビルドした 2.1.284 バイナリ（`.claude-wrapped`、231.8MB、ELF 64-bit）を `strings -a` で再検証したところ、今回も auto mode 分類器にブロックされず取得に成功した。4トークンの出現回数は `CLAUDE_CODE_DISABLE_ADVISOR_TOOL` 4件・`CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL` 4件・`tengu_sage_compass2` 2件・`advisorModel` 39件で、2.1.283 時点から変化なし。

取得できたコードは minifier が振る識別子自体が変わっているが（`RK()`/`xat()`/`Rw()`/`ey()`）、構造として同一だった: kill switch（`function xat(){if(a.CLAUDE_CODE_DISABLE_ADVISOR_TOOL||RK())return!1;return Ie()==="firstParty"&&wg()}`）→ env var バイパス（`function Rw(){if(!xat())return!1;if(a.CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL)return!0;return x("tengu_sage_compass2",{}).enabled??!1}`）という順序、advisor モデル候補配列 `var AK=["fable","opus","sonnet"]`、rank 比較の閾値 `var vK=2`、"has no advisor rank in the model catalog. Switch to a public model alias (opus, sonnet, fable) or set CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL=1." という fallback メッセージ文言をいずれも確認した。

model catalog に `{id:"claude-sonnet-5-5",family:"sonnet",display_name:"Sonnet 5.5",knowledge_cutoff:"June 2026",...,advisor_rank:3}` が追加され、`aliases.sonnet.default` と `latest_per_family.sonnet` が `claude-sonnet-5` から `claude-sonnet-5-5` に変わったことを確認した。`settings.json.tmpl` の `"model": "sonnet"`（実行モデル）と `advisorModel: "opus"`（advisor）はいずれも `AK`/alias 解決に含まれる generic alias のままであり、pin 更新だけで実行モデルが Sonnet 5.5 に追従し、advisor 経路（Opus 5.5 のまま）は変化しないことが構造面でも裏付けられた。あわせて、Sonnet モデルの safeguard 通知定数に `PREV_SONNET_ID` / `PREV_SONNET_NAME` が `SONNET_ID` / `SONNET_NAME` と対で新設されたことを確認した（CHANGELOG の "Changed the notice shown when a Sonnet model's safeguards flag a message to explain why it happened and to offer editing and retrying" に対応する構造変化）。詳細は `runtime/ai-runtimes.md` の該当節に転記した。

## APM payload

今回の更新単位に含めない（ADR-0045 の境界、動機が Sonnet 5.5 単発のため）。

## 検証

- `nix flake lock`（`flake.nix` の URL revision 書き換え後）、`nix flake check --no-build --all-systems`: 成功（6 devShell + 3 formatter）。
- 3 system の `nix eval`（`pkgs.llm-agents.<pkg>.version` / `inputs.llm-agents.packages.${system}.<pkg>.version`）: claude-code 2.1.284 / codex 0.158.0 / copilot-cli 1.0.89 / antigravity-cli 1.2.12 / rtk 0.50.0 / apm 0.32.0 / herdr 0.9.1 の版が3 system一致。
- x86_64-linux の実 `nix develop .#default` build と8 CLI version起動: 成功（上記実測値のとおり）。
- `tests/ai-quality-floor.bats`: floor 値（`2.1.284` / `0.158.0`）と診断メッセージの固定値を更新し、7/7 成功。
- `tests/nix-devshell.bats`: snapshot revision の固定値、AI toolset snapshot contract の参照先 research doc（本ファイル）を追従させ、35/35 成功。
- `bunx tsc --noEmit`: エラーなし。
- `LC_ALL=C bats tests/*.bats`（full suite）: 752/752 成功（exit code 0、既知の flaky 2件を含め今回は失敗なし）。

## 二軸レビュー

`/code-review`（base: `origin/main`）を実行した。Standards / Spec の両サブエージェントとも hard violation・scope creep・実装誤りの指摘はなかった。

Standards 側は、ADR-0045（更新単位分離）と ADR-0047（floor 根拠・テスト同時更新）への準拠を diff で直接確認し、`apm.yml`/`apm.lock.yaml` 無変更・`flake.lock` の共有 `nixpkgs` ノード不変（`llm-agents` 内部の nixpkgs のみ変化）を `jq` で確認した。ADR-0069 が ADR-0064/0068 と構造的に一致することも確認した。Claude Code の floor 根拠（Sonnet 5.5 追加）が trust boundary 系ではない点を指摘したが、これは ADR-0064 が確立した「モデル品質・metadata の正確性」区分の前例踏襲であり逸脱ではないと判断した。`runtime/ai-runtimes.md` の advisor tool 再検証記述が毎回ほぼ同型の反復になっている点を baseline smell として言及したが、これは ADR-0047 が求める既存の監査証跡慣習であり cut 対象ではないと判断した。

Spec 側は、研究ノートの「要件と採用境界」と ADR-0069 に対して rev・floor・reason 文字列・テスト期待値の実装一致を実測で確認し、未実装・部分実装の要件、依頼されていない挙動（APM payload・モデル/権限設定への波及）、実装誤り（version 不整合）のいずれも検出しなかった。

## 最終結果

`flake.nix` の revision 書き換え・`nix flake lock`・3 system 評価・x86_64-linux 実 build・関連 bats（7/7・35/35）・full suite（752/752）・`bunx tsc --noEmit`（エラーなし）・二軸レビュー（指摘0件）が完了した。live apply、push・PR は未実施。aarch64-linux / aarch64-darwin の実機実行、Copilot CLI / Antigravity CLI の version固有 changelog は未確認のまま。
