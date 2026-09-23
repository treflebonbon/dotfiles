---
type: decision
title: llm-agents snapshot を更新し Opus 5.5 を利用可能にする
description: Claude Code 2.1.280 が追加した Opus 5.5 とその permission bypass / auto mode trust boundary / skill discovery 修正を根拠に quality floor を引き上げ、同じ実装セッション中にユーザーが指示した effortLevel の変更も記録する
tags: [adr, nix, llm-agents, claude-code, opus, effort-level]
timestamp: 2026-09-23
status: accepted
---

# llm-agents snapshot を更新し Opus 5.5 を利用可能にする

ユーザーが `opus 5.5 を利用したい` と依頼した。2026-09-22 に Anthropic が Claude Opus 5.5 (`claude-opus-5-5`) をリリースし、Claude Code 2.1.280 がこれをデフォルト Opus モデルとして追加したことを公式 CHANGELOG で確認した。issue #112（Opus 5 対応）と同じ「モデル品質・metadata の正確性」を根拠区分として、ADR-0045 の更新単位方針に従いツール snapshot だけを一つの更新単位として採用する。実装途中でユーザーから `effort は high` という追加指示を受けた。これはツール snapshot とは因果関係のない独立した決定だが、同じ `private_dot_claude/settings.json.tmpl` を対象とし同じ実装セッション・commit で扱うため、この ADR の Decision に併記する（[docs/agents/domain.md](../agents/domain.md) が定める「決定記録は `docs/adr/` に一元化する」に従い、research doc（調査ノートであり決定記録ではない）だけに残さない）。

## Decision

- `llm-agents.nix` は `private_dot_config/nix-devshell/flake.nix` の immutable revision を `9032892fd4d89bdad79c858a81aae1268ad2d191` から upstream default branch HEAD `8011aaf2e65e9222b2121c2fbb622912d7469bd6`（2026-09-22）へ更新する。共有 nixpkgs（`nixpkgs-26.05-darwin`）と x86_64-linux / aarch64-linux / aarch64-darwin の3-system境界は維持する。3 system の package metadata は claude-code 2.1.280、codex 0.155.1（変化なし）、copilot-cli 1.0.88、antigravity-cli(`agy`) 1.2.8、rtk 0.49.0（変化なし）、apm 0.31.0（変化なし）、herdr 0.9.1（変化なし）、code-review-graph 2.3.9（変化なし）で一致する。
- Claude Code の quality floor を `2.1.277` から `2.1.280` へ引き上げる。根拠は 2.1.280 の公式 CHANGELOG から確認した次の内容: Opus 5.5 (`claude-opus-5-5`) の追加とデフォルト Opus モデルへの変更（今回の直接動機）、symlink 経由の書込みが in-tree spelling で誤判定され auto mode が越境書込みを承認していた permission bypass の修正（この repo は `defaultMode: auto`）、auto mode の safety-filter retry/deny ループの修正、LSP plugin 有効時に background subagent が LSP tool を使えない不具合の修正（この repo は `enabledPlugins` に LSP を含む）、background subagent へのメッセージ消失と compaction 後の report 消失の修正、`.claude/skills/` の skill が `manifest.json` 記載名と一致するだけで `.trash/` へ誤退避される不具合の修正（この repo の shellHook が symlink する対象と同じディレクトリ）。pin 自体も 2.1.280 が最新（2.1.279 は未公開）で他に床上げ根拠はないため、床と pin を同じ 2.1.280 に揃える。
- Codex は snapshot 内で 0.155.1 のまま変化がないため quality floor `0.155.0` は据え置く。Copilot CLI 1.0.87→1.0.88、Antigravity CLI 1.2.7→1.2.8 は package metadata の追従のみ確認し、新設の quality floor は設けない。RTK・APM・Herdr・code-review-graph は snapshot 内でも変化なし。
- Opus 5.5 の到達経路は `private_dot_claude/settings.json.tmpl` の `"advisorModel": "opus"` という generic alias を通す。model 名を直接指定する設定ではないため、今回の snapshot 更新だけで advisor が Opus 5.5 を使うようになる。`"model": "sonnet"`（実行 model）は対象外のまま変更しない。
- APM 経由で配布する skill 依存（`apm.yml` / `apm.lock.yaml`）は今回変更しない。upstream 側の変化を確認しておらず、ADR-0045 の更新単位方針によりツール snapshot と別更新単位のまま扱う。
- 実装の正本は Nix flake / lock、`modules/ai.nix` とし、配備先を直接編集しない。
- `private_dot_claude/settings.json.tmpl` の `effortLevel` を `xhigh` から `high` へ変更する。ADR-0005 / ADR-0045 時点の `xhigh` 既定（advisor tool のコスト・レイテンシ増と同方向に働くとされていた設定）をこの回のユーザー指示で置き換える。根拠は「ユーザーが `effort は high` と明示的に指示したこと」のみで、性能・コスト比較などの追加検証はこの ADR のスコープ外（ユーザー自身の判断による設定変更として受け入れる）。連動して `runtime/ai-runtimes.md`（Claude 設定要約、advisor tool のコスト説明）と `README.md`（Claude Code 節の設定要約）の現状値記述を同じ値へ追従させる。

## Verification boundary

- Nix source gate: `nix flake check --no-build --all-systems` が3 system で成功。3 system の overlay 経由 `pkgs.llm-agents.<pkg>.version` 実測が claude-code 2.1.280 / codex 0.155.1 / copilot-cli 1.0.88 / antigravity-cli 1.2.8 / rtk 0.49.0 / apm 0.31.0 / herdr 0.9.1 / code-review-graph 2.3.9 で一致することを確認した。x86_64-linux (host) では `nix develop` で実ビルドし、claude / codex / copilot / agy / rtk / apm / herdr / code-review-graph の8 CLI 実測 version が snapshot と一致することを確認した。
- リポジトリ既存の bats full suite（741件）が `LC_ALL=C bats tests/*.bats` で740/741成功した。唯一の失敗（`tests/codex-config.bats` の Codex sandbox 統合テスト）は `main`（`26fe923`）でも同じく失敗することを一時 worktree で確認済みの既存フレークで、この diff とは無関係（regression ではない）。floor 引き上げに伴い `tests/ai-quality-floor.bats`（floor 値・診断メッセージの期待値）、`tests/nix-devshell.bats`（snapshot revision の固定値、AI toolset snapshot contract の参照先 research doc）を同じ更新単位で追従させた。`bunx tsc --noEmit` はエラーなし。
- `runtime/ai-runtimes.md` の Advisor tool 節が自ら課す再検証義務（pin 上の claude-code version が変わった回は kill switch → env var バイパス → `tengu_sage_compass2` フラグ → advisorModel rank check の構造を再確認する）に従い、pin `2.1.278→2.1.280` を機に `.claude-wrapped` バイナリを `strings` で再検証した。4トークン（`CLAUDE_CODE_DISABLE_ADVISOR_TOOL` 4件 / `CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL` 4件 / `tengu_sage_compass2` 2件 / `advisorModel` 38件）の存在に加え、今回は周辺コードの直接取得に成功し（過去回は auto mode 分類器にブロックされ件数のみだった）、`qb()`（kill switch → env var → `tengu_sage_compass2` フラグの順）・`hm()`（env var 直読み）・advisor モデル候補 `["fable","opus","sonnet"]`・rank 比較（`zH=2` 閾値、`hne()`）という構造が変化していないことをコード上で確認した。詳細は `runtime/ai-runtimes.md` の Advisor tool 節の 2026-09-23 エントリを参照。
- aarch64-linux / aarch64-darwin の実機実行、2.1.280 の permission bypass / auto mode trust boundary / skill discovery 各修正を実際の agent session で機能的に再現する smoke、Opus 5.5 が実際に advisor 呼び出しで選択されることのランタイム smoke、Copilot CLI / Antigravity CLI の version固有 changelog は未確認のまま。

## Deliberately separate

- APM payload（19 skill 依存の refresh）、Impeccable skill pin、Matt Pocock managed set は upstream の進捗有無を今回確認しておらず、この更新単位に含めない。
- `"model": "sonnet"` を `"opus"` 系へ切り替える判断（advisor ではなく実行 model 自体を Opus にする）は、2026-09-22 の調査ノートと同じくモデル・権限設定のスコープ外として対象外にする。ユーザーが実行 model の切替を意図している場合は別途依頼が必要。

## Consequences

この境界により、Opus 5.5 の利用可否という単一の動機と、それに付随する permission bypass / auto mode trust boundary / skill discovery の quality floor 引き上げを同じ verification / rollback 証跡で扱える。APM payload と model/権限設定は次回以降の専用更新単位に持ち越す。

関連: [調査ノート 2026-09-23](../research/llm-agents-and-apm-update-2026-09-23.md) / [ADR-0063](0063-update-llm-agents-snapshot-and-worktree-trust-boundary.md) / [ADR-0045](0045-separate-llm-agents-and-apm-update-units.md) / [ADR-0047](0047-test-quality-floors-through-package-outputs.md) / [ai-runtimes](../../runtime/ai-runtimes.md)
