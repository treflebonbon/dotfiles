# ツールとスキル更新（2026-09-26）

## 要件と採用境界

ユーザーの `/implement ツールとスキル更新` に基づき、既存 AI tool snapshot と APM 全19依存の更新候補を確認する。ADR-0045 に従い、tool snapshot と通常 APM payload の2更新単位を同じ task worktree・同一 commit で採否する（Impeccable、Matt Pocock managed set は対象外）。task worktree は main `203d47d` から作成した。

受入条件は exact snapshot と lock の整合、3 system の評価、Linux build・CLI起動、関連テスト・型チェック・full suite、二軸レビューとコミット。品質 floor は根拠がある場合のみ変更する。モデル・権限、配布経路、新規ツール追加、private skill 改稿は対象外。live apply・push・PR は行わない。

前回更新（PR #355、2026-09-24、ADR-0067）から2日しか経っていないため、まず upstream HEAD の再確認と selected subtree の content hash 比較を先に行い、実差分がある場合のみ nix build / APM lock 生成に進む方針とした。

## Tool snapshot

実装入口で `git ls-remote https://github.com/numtide/llm-agents.nix HEAD` を確認し、default branch HEAD `bbb0f9a24c3a5ce918f3d8103397ce08b20300e1`（2026-09-26）に固定した。旧 pin `8bec0ce1cbb0a39f8f08dc97a7635af847779f99`（2026-09-24）から195 commit進んでいた。GitHub Compare のファイル一覧で追跡対象8ツールのうち `claude-code`・`codex`・`antigravity-cli`・`rtk`・`apm` の hashes.json/package.nix が変更対象に含まれ、`copilot-cli`・`herdr`・`code-review-graph` は含まれなかった。

| ツール            | 旧版    | 候補    |
| ----------------- | ------- | ------- |
| Claude Code       | 2.1.281 | 2.1.283 |
| Codex             | 0.156.1 | 0.157.1 |
| Antigravity CLI   | 1.2.10  | 1.2.11  |
| RTK               | 0.49.0  | 0.50.0  |
| APM               | 0.31.0  | 0.32.0  |
| Copilot CLI       | 1.0.88  | 1.0.88  |
| Herdr             | 0.9.1   | 0.9.1   |
| code-review-graph | 2.3.9   | 2.3.9   |

Claude Code の公式 CHANGELOG（`anthropics/claude-code` の `CHANGELOG.md`、2.1.283 見出しに 2.1.282 分を含む）を確認した。この repo の quality floor 判断基準（permission/sandbox/trust boundary の信頼性）に合致する修正:

- **sandbox 設定の fail-open 修正**: "Fixed managed `sandbox` settings being ignored entirely when one nested value was invalid; the invalid value now fails closed and the rest of the block still applies." 従来は managed sandbox settings のネストされた値が1つでも不正だとブロック全体が無視される（fail-open）挙動だったが、不正な値だけを無効化し残りのブロックは引き続き適用される（fail-closed）よう修正された。

他は Windows PowerShell の drive-root 削除防止（この repo が supported systems に含まない）、sandboxed git の credential helper 警告抑制（無害化のみで bypass ではない）など trust boundary への直接影響が薄い項目のため床上げ根拠から除外した。よって `minClaudeCode` を `2.1.281` → `2.1.283` へ引き上げ、pin も `2.1.283`（最新）を採用する。

Codex は公式 GitHub Release Notes（`rust-v0.157.0`）から次を確認した:

> Enforced network restrictions across redirects and ongoing HTTP and WebSocket traffic, including cancellation when policy changes revoke access. (#47389, #47407)

redirect 追従中や実行中の HTTP/WebSocket 通信でネットワーク制限が徹底されておらず、ポリシー変更によるアクセス取消も反映されていなかった不具合の修正であり、[ADR-0047](../adr/0047-test-quality-floors-through-package-outputs.md) の Codex floor 判断基準（sandbox・trust boundary の信頼性）に合致する。よって `minCodex` を `0.156.0` → `0.157.0` へ引き上げる。`rust-v0.157.1`（`gh api .../compare/rust-v0.157.0...rust-v0.157.1`で実測）はコミット5件すべて Windows daemon 起動まわりの修正（コンソールウィンドウ抑制、Job Object membership、stdio 継承防止）のみで、Linux/macOS 環境に追加の床上げ根拠はない。pin は snapshot 内の 0.157.1 を採用する。

Antigravity CLI 1.2.10→1.2.11、RTK 0.49.0→0.50.0、APM 0.31.0→0.32.0 は非公開 changelog または floor 対象外のツールのため package metadata の追従のみ確認した。Copilot CLI・Herdr（バイナリ）・code-review-graph は snapshot 内でも変化なし。

`nix flake update llm-agents`（`flake.nix` の URL revision 書き換え後）で lock を更新し、`nix flake check --no-build --all-systems` は全6 devShell と formatter の評価に成功した。3 system の `nix build --dry-run` は claude-code 2.1.283、rtk 0.50.0、antigravity-cli 1.2.11、apm 0.32.0 の版が一致し、codex-0.157.1 はいずれも fetch 対象（cache hit）で build 対象に含まれないことを確認した（rustc OOM を伴う LTO source build の回避）。x86_64-linux の実 `nix develop .#wsl` build と、隔離 HOME での8 CLI version 起動（`claude` 2.1.283 / `codex` 0.157.1 / `copilot` 1.0.88 / `agy` 1.2.11 / `rtk` 0.50.0 / `apm` 0.32.0 / `herdr` 0.9.1 / `code-review-graph` 2.3.9）も成功した。

### Advisor tool 再検証（ADR-0005）

Claude Code の quality floor 引き上げ（2.1.281→2.1.283）を機に [ADR-0005](../adr/0005-advisor-tool-default-enable.md) の再検証トリガーを踏んだ。実ビルドした 2.1.283 バイナリ（`.claude-wrapped`）を `strings` で再検証したところ、auto mode 分類器にブロックされず取得に成功した。4トークンの出現回数は `CLAUDE_CODE_DISABLE_ADVISOR_TOOL` 4件・`CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL` 4件・`tengu_sage_compass2` 2件で 2.1.281 時点から変化なし（`advisorModel` は 38→39 件、モデルカタログへのエントリ追加分と見られ advisor 経路とは無関係）。

取得できたコードは minifier が振る変数名自体が変わっているが（`Zst()`/`mw()`/`Oj()`/`Pe()`/`cg()`）、構造として同一だった: kill switch（`if(a.CLAUDE_CODE_DISABLE_ADVISOR_TOOL||Oj())return!1`）→ 追加条件（`Pe()==="firstParty"&&cg()`）→ env var バイパス（`if(a.CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL)return!0`）→ `tengu_sage_compass2` フラグ判定（`x("tengu_sage_compass2",{}).enabled??!1`）という順序、advisor モデル候補配列 `["fable","opus","sonnet"]`、"has no advisor rank in the model catalog. Switch to a public model alias (opus, sonnet, fable) or set CLAUDE_CODE_ENABLE_EXPERIMENTAL_ADVISOR_TOOL=1." という fallback メッセージ文言、model catalog の `advisor_rank` フィールド（例: `claude-sonnet-5` は `advisor_rank:2`）をいずれも確認した。`settings.json.tmpl` の `advisorModel: "opus"` は引き続きこの候補配列に含まれる generic alias であり、pin 更新後も advisor 経路は変化しない。詳細は `runtime/ai-runtimes.md` の該当節に転記した。

## APM payload

`apm outdated`（隔離 cwd/HOME）が示した2件の outdated 依存（mattpocock/skills、stablyai/orca/skills/orca-cli）を起点に、floating `(default)` 依存は selected subtree の content hash 比較、exact pin 依存は実際の upstream diff を確認して個別に採否した。

| 依存 | 確認内容 | 採否 |
| --- | --- | --- |
| remotion-dev/skills/skills/remotion-best-practices（exact pin `41b22eec767a`） | upstream default branch が `cf49eff5d446` へ1 commit 進み、`skills/remotion-markup/REFERENCE.md` への Motion blur 節追加と新規 `motion-blur.md`（`@remotion/motion-blur`、`<HtmlInCanvasMotionBlur>`、Remotion 4.0.529 で追加）という実差分を確認 | pin を `cf49eff5d4463b33966b6618c83f7295797dd028` へ進める |
| stablyai/orca/skills/orca-cli（exact pin `4a5afd70a3db`） | `apm outdated` は最新 tag `v1.4.212`（`d937d22f`）を示すが、`gh api .../compare` で実測すると pin は69 commit 先行・0 commit 遅れ。選択済み subtree（`skills/orca-cli`）の差分ファイルは0件 | 配布差分なし・pin維持 |
| GoogleChrome/modern-web-guidance/skills/modern-web-guidance（exact pin `22ab18dfb50a`） | upstream default branch HEAD は前回確認時点から不変 | 配布差分なし・維持 |
| mattpocock/skills（exact pin `6654f6b60cd9`） | `apm outdated` は latest tag `v1.2.3`（`6acc160e`）を示すが、`gh api .../compare/6acc160e...6654f6b6` は `ahead_by: 39, behind_by: 0`。既知の tag 専用比較に起因する false positive（2026-09-03/09-24 と同型） | 配布差分なし・維持（別更新単位でもある） |
| anthropics/skills（pdf・skill-creator、floating） | 旧 resolved `34040c9c` → 新 resolved `33375500` まで selected subtree の差分ファイルは0件 | revision-only、floating解決を自然反映 |
| stablyai/orca `orchestration`/`computer-use`（floating） | 旧 resolved `122b8c25` → 新 resolved `f0a36109` まで selected subtree の差分ファイルは0件 | revision-only、floating解決を自然反映 |
| mizchi/skills/empirical-prompt-tuning（floating） | 旧 resolved `a3f2f1ba` → 新 resolved `0c7c1e60` まで selected subtree の差分ファイルは0件 | revision-only、floating解決を自然反映 |
| Effect-TS/skills、shadcn-ui/ui、vercel-labs 各4 skill、vercel-labs/skills/find-skills、supabase/agent-skills（floating、10件） | resolved_commit・content hash とも不変 | 配布差分なし・維持 |
| pbakaus/impeccable（exact pin `cb56ed6c`） | 別更新単位（ADR-0045）のため今回は upstream 進捗の確認自体を対象外とした | 対象外（別更新単位） |

Remotion の exact pin を `cf49eff5d4463b33966b6618c83f7295797dd028` へ更新し、隔離 cwd/HOME（apm 0.32.0 の nix devshell 経由）で `apm install --target claude,codex --https` を実行した。

初回の隔離環境確認では既存の配備済みファイル（`.agents/skills/`・`.claude/skills/`・APM キャッシュ）が残った状態で `apm install` を再実行したため、増分解決になり `deployed_file_hashes` が19依存中1件しか記録されない不完全な lock（14442行→2312行）が生成されることを確認した。隔離ディレクトリを完全に削除して作り直し、空の状態から `apm install --target claude,codex --https` を実行し直したところ、19依存すべてに `deployed_file_hashes` を含む完全な lock（14442行、`apm_version: 0.32.0`）が生成された。同一隔離環境の `apm install --frozen --target claude,codex --https` 前後で SHA-256（`9de64392c6acc9e4ef3268591b81a430b1e0c7b381a23fa8cd5c1a6ba2ba2331`）は不変、`apm audit --ci` は10/10全通過した。生成 lock を main の lock と diff すると、変更対象は remotion-best-practices の resolved_commit/content_hash、`apm_version`（0.31.0→0.32.0）、および pdf/skill-creator/orchestration/computer-use/empirical-prompt-tuning の revision-only な `resolved_commit` 更新のみで、他13依存の pin・content hash は無変化だった。両 target（`.agents/skills/` / `.claude/skills/`）に remotion-best-practices の新規ファイル（`remotion-markup/motion-blur.md`）を含む配備を確認した。

## 検証

- `nix flake update llm-agents`、`nix flake check --no-build --all-systems`: 成功。
- 3 system の `nix build --dry-run`: 5パッケージ（claude-code / codex / antigravity-cli / rtk / apm）の版が一致。Codex はいずれも fetch 対象（cache hit）で build 対象外を確認。
- x86_64-linux の実 `nix develop .#wsl` build と8 CLI version起動（隔離 HOME）: 成功。
- `tests/ai-quality-floor.bats`: floor 値（`2.1.283` / `0.157.0`）と診断メッセージの固定値を更新し、7/7 成功。
- `tests/nix-devshell.bats`: snapshot revision の固定値、AI toolset snapshot contract の参照先 research doc（本ファイル）を追従させ、28/28 成功。
- `tests/apm-runtime.bats`: remotion-best-practices の pin/content hash、pdf/skill-creator/orchestration/computer-use の revision-only な resolved_commit、`apm_version` の断定を追従・修正し、15/15 成功。
- `bunx tsc --noEmit`: エラーなし。
- `LC_ALL=C bats tests/*.bats`（full suite）: 752/752 成功（exit code 0）。既知だった flaky 2件（`codex-config.bats` の sandbox 統合テスト、本ファイル自体を参照する `nix-devshell.bats` の中間実行）も今回はすべて成功した。

## 二軸レビュー

`/code-review`（base: `main`）を実行した。Standards / Spec の両サブエージェントが独立に、本ドキュメントの受入条件の一文（旧稿）が「品質 floor…は対象外」と記載していた点を指摘した——同じドキュメントの本文および ADR-0068 で実際に `minClaudeCode`/`minCodex` を引き上げているため自己矛盾であり、前回（2026-09-24）稿にはない今回限りのコピーミスと確認した。当該一文を「品質 floor は根拠がある場合のみ変更する」へ修正して解消した。Spec 側はさらに、本節と「検証」節末尾の full suite 結果がプレースホルダーのまま（「結果は後述」「本節末尾に記録する」）だった点を指摘し、両方とも実測値の記入で解消した。ADR-0045 の update unit 分離（tool snapshot と通常 APM payload）を今回も1 commit にまとめている点は、前例（PR #355）と同型の判断として両サブエージェントとも hard violation ではなく判断済みの許容範囲と評価した。他に hard violation・scope creep・実装誤りの指摘はなかった。

## 最終結果

`nix flake update`・3 system 評価・x86_64-linux 実 build・APM 隔離 install/audit・関連 bats・full suite・二軸レビューが成功した。live apply、push・PR は未実施。aarch64-linux / aarch64-darwin の実機実行、Copilot CLI / Antigravity CLI / RTK / APM の version固有 changelog は未確認のまま。
