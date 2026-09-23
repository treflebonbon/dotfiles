# ツール更新（2026-09-23）

## 要件と採用境界

ユーザーの `/implement ツールの更新。opus 5.5 を利用したい` に基づき、Claude Code の `llm-agents.nix` snapshot を更新して Claude Opus 5.5 (`claude-opus-5-5`) を利用可能にする。2026-09-22 に Anthropic が Opus 5.5 をリリースし、Claude Code 2.1.280 がこれをデフォルト Opus モデルとして追加したことを公式 CHANGELOG で確認した。前回更新（2026-09-22、`9032892f`、[調査ノート](llm-agents-and-apm-update-2026-09-22.md) / [ADR-0063](../adr/0063-update-llm-agents-snapshot-and-worktree-trust-boundary.md)）から1日で、snapshot は claude-code のみ quality floor 対象の変更を含む。task worktree は main `26fe923` から作成した。

受入条件は exact snapshot と lock の整合、3 system の評価、Linux build・CLI起動、関連テスト・full suite、二軸レビューとコミット。ADR-0045 の更新単位方針に従い、APM payload（skills）・実行/advisor モデルの銘柄選択・配布経路は対象外にする（`"model": "sonnet"` / `"advisorModel": "opus"` は generic alias のままで、Opus 5.5 は floor 側の snapshot 更新だけで解決される）。実装途中でユーザーから `effortLevel は high` という追加指示を受け、同じ `private_dot_claude/settings.json.tmpl` 内の設定として本更新に含めた（詳細は「Claude effortLevel」節）。live apply・push・PR は行わない。

## Tool snapshot

実装入口で `git ls-remote https://github.com/numtide/llm-agents.nix HEAD` を確認し、default branch HEAD `8011aaf2e65e9222b2121c2fbb622912d7469bd6`（2026-09-22）に固定した。`private_dot_config/nix-devshell/flake.nix` の `llm-agents.url` は exact revision 文字列を直接埋め込む設計のため、URL 自体を書き換えてから `nix flake update llm-agents` で再ロックした。

| ツール            | 旧版    | 候補    |
| ----------------- | ------- | ------- |
| Claude Code       | 2.1.278 | 2.1.280 |
| Codex             | 0.155.1 | 0.155.1 |
| Copilot CLI       | 1.0.87  | 1.0.88  |
| Antigravity CLI   | 1.2.7   | 1.2.8   |
| RTK               | 0.49.0  | 0.49.0  |
| APM               | 0.31.0  | 0.31.0  |
| Herdr             | 0.9.1   | 0.9.1   |
| code-review-graph | 2.3.9   | 2.3.9   |

Claude Code の公式 CHANGELOG（v2.1.280、`raw.githubusercontent.com/anthropics/claude-code/v2.1.280/CHANGELOG.md`。2.1.279 は公開されていない）を確認した。この repo の quality floor 判断基準（多 agent ワークフロー・worktree 隔離・permission/trust boundary の信頼性、モデル品質・metadata の正確性）に合致する修正:

- **モデル品質・metadata の正確性**: Claude Opus 5.5 (`claude-opus-5-5`) を追加してデフォルト Opus モデルへ変更（今回の更新の直接動機。issue #112 の Opus 5 対応と同じ根拠区分）
- **permission bypass**: symlink 経由の書込みが in-tree spelling で判定され、`acceptEdits` / allow ルール / auto mode がそのファイルの実体が symlink 先の tree 外に着地する書込みを承認していた不具合の修正（この repo は `defaultMode: auto` を既定にしているため直撃）
- **auto mode の trust boundary**: safety check が拒否した操作を auto mode が延々と再試行する不具合、safety check が無回答のとき auto mode が一時停止なく拒否を繰り返す不具合の修正
- **多 agent の error 伝搬**: LSP plugin が有効な状態で background subagent が LSP tool を使えない不具合の修正（この repo は `enabledPlugins` に LSP を含むため直撃）、background subagent へ送ったメッセージが消失する不具合、compaction 後に完了済み subagent の report が失われる不具合の修正
- **skill discovery**: `~/.claude/skills/` 内の skill が、そのディレクトリの `manifest.json` に名前が載っているだけで `.trash/` へ誤って退避される不具合の修正（この repo の shellHook は `$HOME/.claude/skills` へ symlink するため直撃しうる）

pin 自体は 2.1.280 が最新（2.1.279 は未公開）で、他に床上げ根拠となる追加内容はない。よって `minClaudeCode` を `2.1.277` → `2.1.280` へ引き上げ、pin も `2.1.280` を採用する。

Codex は snapshot 内で 0.155.1 のまま変化がないため `minCodex` は `0.155.0` を維持する。Copilot CLI 1.0.87→1.0.88、Antigravity CLI 1.2.7→1.2.8 は package metadata の追従のみ確認し、version 固有の公式 changelog は未確認（quality floor 対象外）。RTK・APM・Herdr・code-review-graph は snapshot 内でも変化なし。

`nix flake update llm-agents`（`flake.nix` の URL 書き換え後）で lock を更新し、`nix flake check --no-build --all-systems` は全6 devShell と formatter の評価に成功した。3 system の overlay 経由 `pkgs.llm-agents.<pkg>.version` 実測は claude-code 2.1.280 / codex 0.155.1 / copilot-cli 1.0.88 / antigravity-cli 1.2.8 / rtk 0.49.0 / apm 0.31.0 / herdr 0.9.1 / code-review-graph 2.3.9 で3 system一致した。x86_64-linux の実 `nix develop` build と8 CLI 起動（`claude` 2.1.280 / `codex-cli` 0.155.1 / `copilot` 1.0.88 / `agy` 1.2.8 / `rtk` 0.49.0 / `apm` 0.31.0 / `herdr` 0.9.1 / `code-review-graph` 2.3.9）も成功した。

Opus 5.5 の到達経路は `private_dot_claude/settings.json.tmpl` の `"advisorModel": "opus"` という generic alias を経由する。`claude` バイナリ自体は薄い wrapper script（`bin/.claude-wrapped` を起動するだけ）だが、`bin/.claude-wrapped` を `strings` で再検証したところ、`runtime/ai-runtimes.md` の Advisor tool 節が要求する「pin 上の claude-code version が変わった回の再検証」に相当する周辺コードの直接取得に成功した（2026-07-13 以降の複数回は auto mode 分類器にブロックされ件数のみだった）。`advisorModel` の候補セット `NB() = ["fable","opus","sonnet"]` に `"opus"` が含まれ、rank 比較（`hne()`、閾値 `zH=2`）を通る generic alias であることをコード上で確認した。これと Anthropic 公式 CHANGELOG の記述（"Added Claude Opus 5.5 (`claude-opus-5-5`), now the default Opus model"）を合わせて一次情報とし、2.1.280 の snapshot 更新だけで advisor が Opus 5.5 を使うようになると判断した。詳細は `runtime/ai-runtimes.md` の Advisor tool 節の 2026-09-23 エントリを参照。`"model": "sonnet"`（実行 model）は今回のスコープ外（2026-09-22 の調査ノートと同じ判断）のため変更していない。

## Claude effortLevel

実装途中でユーザーから `effort は high` という追加指示を受けた。`private_dot_claude/settings.json.tmpl` の唯一の effort 関連設定は `effortLevel`（旧値 `xhigh`）で、これを `high` へ変更した。`tests/*.bats` に `effortLevel` を直接検証するケースはなく、settings.json.tmpl の JSON 構文以外に追加のテスト追従は不要だった。`runtime/ai-runtimes.md` の Claude 設定要約（現在値の記述）と advisor tool のコスト説明、`README.md` の Claude Code 節（現在値の記述）も同じ値へ追従させた。この変更は snapshot 更新とは因果関係のない独立した決定のため、[docs/agents/domain.md](../agents/domain.md) の「決定記録は `docs/adr/` に一元化する」規約に従い [ADR-0064](../adr/0064-update-llm-agents-snapshot-for-opus-5-5.md) の Decision に記録した（本節はその調査ログ）。ADR-0005 / ADR-0045 内の `effortLevel: xhigh` への言及はその時点の判断記録であり変更していない。

## APM payload

今回はツール snapshot のみが対象で、rtk/apm/herdr/code-review-graph を含め APM 経由で配布する19 skill 依存に変化はない（upstream 側の変化を確認していない）。ADR-0045 の更新単位方針により、この更新には含めない。

## 検証

- `nix flake update llm-agents`（`flake.nix` の URL revision 書き換え後）、`nix flake check --no-build --all-systems`: 成功。
- 3 system の overlay 経由 `pkgs.llm-agents.<pkg>.version` 実測（8パッケージ）: 一致。
- x86_64-linux の実 `nix develop` build と8 CLI version 起動: 成功。
- `tests/ai-quality-floor.bats`: quality floor 値（`2.1.280`）と診断メッセージの固定値を更新し、7/7 成功。
- `tests/nix-devshell.bats`: snapshot revision の固定値を更新し、28/28 成功。
- `bunx tsc --noEmit`: エラーなし。
- `bats tests/*.bats`（全スイート）: `LC_ALL=C bats tests/*.bats` で740/741成功。失敗した `tests/codex-config.bats` の「Codex config migration keeps dotenv denied and public examples readable without a raw read grant」は `codex sandbox` を起動する統合テストで、`main`（`26fe923`）を一時 worktree にチェックアウトして単体実行しても同じく失敗することを確認した。この diff（`codex` 関連ファイルを一切変更していない）とは無関係な既存の環境依存フレークであり、regression ではない。

## 二軸レビュー

`/code-review`（base: `main`）を実行した。結果は後述。

## 最終結果

`nix flake update`・3 system 評価・x86_64-linux 実 build・関連 bats が成功した。live apply、push・PR は未実施。aarch64-linux / aarch64-darwin の実機実行、2.1.280 の permission bypass / auto mode trust boundary / skill discovery 各修正を実際の agent session で機能的に再現する smoke、Copilot CLI / Antigravity CLI の version固有 changelog、Opus 5.5 が実際に advisor 呼び出しで選択されることのランタイム smoke は未確認のまま。
