---
type: research
title: code-review-graph 導入可否
description: code-review-graph v2.3.7 と numtide/llm-agents.nix の固定 snapshot を一次情報・ローカル実測で検証し、この dotfiles への採否と再評価条件を整理した調査ノート。
tags: [research, code-review, mcp, nix, codex, claude-code]
timestamp: 2026-08-06
---

# code-review-graph 導入可否

## 結論

**Issue #136 は「CLI は user devShell へ常設し、実利用はリポジトリ単位で opt-in」とする。MCP、graph build、hook、daemon は global に有効化しない。この dotfiles 自体は利用対象外とする。**

製品自体は、Tree-sitter で抽出した code graph を SQLite に永続化し、変更の blast radius、関連 test、execution flow を CLI / MCP から引ける、筋のよい local-first tool である。複数 repository で評価できるよう binary は共通環境へ置く一方、次の不一致があるこの repo には graph / MCP を導入しない。

1. この repo は tracked file 237 件で、上流自身が効果を「marginal」とする「数百 file 未満」に入る。実測でも graph が既存の Bats test を変更対象の test と結び付けられず、test gap を false positive で報告した。
2. chezmoi の重要な source である `*.tmpl` は v2.3.7 の language detection 対象外で、1つの `.tmpl` extension を Nix / shell / JSON など複数 grammar に割り当てることもできない。
3. 上流 installer は Codex の user-global config / hooks と repo の git hook を直接変更する。この repo はそれらを chezmoi source、managed hook、lefthook で宣言管理しており、installer の mutation は管理境界と衝突する。
4. pin 済みの `llm-agents.nix` package はそのままでは `x86_64-darwin` 非対応で、この repo の shared-nixpkgs 経路では upstream が要求する FastMCP floor も満たさない。CLI 配備では local package が FastMCP 3.3.1 と、Intel Darwinで欠ける platform bundleを必要としない `tree-sitter-language-pack` 0.13.0 の source build経路を CRG 専用環境へ入れてこの差を塞ぐ。
5. 公開版 v2.3.7 は HTTP transport の Host / Origin guard、Codex の `AGENTS.md` instruction integration、再測定後の benchmark 訂正より前の版である。既定の 30 MCP tools には source を変更できる tool も含まれ、常時接続には surface が広すぎる。

大規模 repo で multi-hop review を頻繁に行う場合だけ、後述の read-only / stdio 限定評価を行い、その repository の project config に MCP を追加する。CLI が存在すること自体を利用可の判定にはしない。

## 調査対象と確度

調査日は 2026-08-06。製品判断の基準版は、現在の最新公開 release [`v2.3.7`](https://github.com/tirth8205/code-review-graph/releases/tag/v2.3.7)（commit [`6a1ee1c7`](https://github.com/tirth8205/code-review-graph/commit/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad)、2026-07-18 公開）とした。現在の `main` は確認時点で [`1a010dee`](https://github.com/tirth8205/code-review-graph/commit/1a010deed6c283d4aa1e7e949e78fe3a7bcdfbb3)（2026-08-02）まで進んでいるため、公開版との差は分けて記す。

この repo の Nix 経路は [`private_dot_config/nix-devshell/flake.nix`](../../private_dot_config/nix-devshell/flake.nix) が pin する `numtide/llm-agents.nix` commit [`71c0eafc`](https://github.com/numtide/llm-agents.nix/commit/71c0eafcae20331346e60154ca843d4791ba1245) を対象にした。ローカル構造の判断は [Architecture](../architecture.md)、[Skill harness](../../runtime/skill-harness.md)、[`modules/ai.nix`](../../private_dot_config/nix-devshell/modules/ai.nix)、[`tests/nix-devshell.bats`](../../tests/nix-devshell.bats) を正本とした。

以下では、source / package metadata / 実コマンドで確かめた内容を「確認済み」、そこから導く採否を「判断」、実環境でまだ測っていないものを「未確認」とする。

## 製品の機能と動作方式（確認済み）

`code-review-graph` は repository を Tree-sitter で解析し、function、class、import、call、inheritance、test relationship を `.code-review-graph/graph.db` の SQLite graph に保存する。変更時は file hash と VCS diff を使って incrementally update し、MCP / CLI から blast radius、review context、graph query、full-text / semantic search、flow、community、risk、test gap 等を返す（[v2.3.7 README](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/README.md#L101-L157)、[architecture](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/docs/architecture.md)）。

v2.3.7 の主な surface は次のとおり。

- `build` / `update` / `detect-changes` / `query` / `impact` / `watch` / `daemon` / `visualize` / `wiki` 等の CLI。
- 変更影響、review context、test、flow、community、refactor、multi-repo search を含む 30 MCP tools と 5 MCP prompts（[tool list](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/README.md#L445-L485)）。
- MCP transport は既定が stdio。Streamable HTTP は opt-in で、既定 bind は `127.0.0.1:5555`（[server source](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/code_review_graph/main.py#L1071-L1138)）。
- Git repository では `git ls-files` の tracked files を収集するため、通常の gitignored file は index されない。追加除外は `.code-review-graphignore` で指定できる（[file collection source](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/code_review_graph/incremental.py#L750-L792)）。
- 各 worktree は別 root / 別 database として扱われる。異なる commit の worktree 間で database を共有しないよう上流も明記する（[FAQ](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/docs/FAQ.md#L217-L243)）。

LSP と異なり、compiler-backed の型解決ではなく AST-level heuristic である。上流自身も dynamic dispatch、metaprogramming、duck typing では inferred / ambiguous edge が生じると説明している（[FAQ](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/docs/FAQ.md#L18-L49)）。既存の Serena は LSP-backed symbol retrieval / editing を担うため、CRG が追加できる固有価値は symbol lookup ではなく multi-hop の review impact に限られる。

## 対応言語と chezmoi source への適合（確認済み）

v2.3.7 は `.nix` を Nix grammar、`.sh` / `.bash` / `.zsh` / `.ksh` を bash grammar として扱う。Nix の binding、flake input URL、`import`、`callPackage`、shell の function、command、`source` 等を graph 化する（[parser extension map](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/code_review_graph/parser.py#L550-L612)）。

一方、language detection は既知 extension を調べた後、suffix が空の file だけ shebang fallback を行う。したがって `*.sh.tmpl`、`*.nix.tmpl`、`*.json.tmpl` は suffix `.tmpl` の未対応 file になり、元言語として解析されない（[language detection source](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/code_review_graph/parser.py#L2131-L2158)）。custom language config は extension と grammar の一対一 mapping なので、同じ `.tmpl` を複数の元言語へ振り分ける解決策にはならない（[custom language schema](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/docs/CUSTOM_LANGUAGES.md#L37-L68)）。既定 ignore には `*.lock` もあり、`flake.lock` は graph 外となる（[default ignores](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/code_review_graph/incremental.py#L162-L177)）。

これは、chezmoi template を source of truth とするこの repo では重要な欠落である。deploy 後の生成 file を直接 index すれば一部を補えるが、編集対象は chezmoi source であるという [Architecture](../architecture.md) の境界を逆転させるため採用しない。

## 公式導入手順と変更範囲（確認済み）

上流の基本手順は Python 3.10+ で次のとおり（[Quick Start](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/README.md#L47-L74)、[package metadata](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/pyproject.toml#L5-L38)）。

```bash
pip install code-review-graph
code-review-graph install --platform codex
code-review-graph build
```

しかし `install --platform codex` は binary の配置だけではない。

- `~/.codex/config.toml` に `[mcp_servers.code-review-graph]` を追記し、MCP process の `cwd` を install 時の repository path に固定する（[Codex platform definition](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/code_review_graph/skills.py#L44-L52)、[server entry](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/code_review_graph/skills.py#L209-L266)）。
- `~/.codex/hooks.json` に `PostToolUse` update と `SessionStart` status check を merge する（[Codex hooks](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/code_review_graph/skills.py#L775-L816)）。
- repository の git pre-commit hook に graph update / change detection を追記する。失敗は `|| true` で commit 自体を止めない（[git hook source](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/code_review_graph/skills.py#L819-L886)）。
- `.gitignore` へ `.code-review-graph/` を追加する（[install source](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/code_review_graph/cli.py#L197-L244)）。

Claude Code では project `.mcp.json`、`.claude/settings.json`、`.claude/skills/`、`CLAUDE.md` にも作用する。なお v2.3.7 の Codex path は `AGENTS.md` instruction injection の owner に含まれない。この追加は release 後の commit [`33b039e7`](https://github.com/tirth8205/code-review-graph/commit/33b039e7) で入り、v2.3.7 の package にはない。

この repo は [`private_dot_config/codex/config.toml`](../../private_dot_config/codex/config.toml) と [`private_dot_config/codex/hooks.json`](../../private_dot_config/codex/hooks.json) を chezmoi から `$CODEX_HOME` へ merge 配備し、hook trust state も管理する（[AI runtimes](../../runtime/ai-runtimes.md)）。Git hook は lefthook が commit contract を担う。したがって上流 installer を実行すると、source of truth を介さない deploy 先の直接変更、managed hook との merge / trust drift、git hook の二重実行を招く。

**判断:** `code-review-graph install` は使わない。binary は Nix package、MCP entry と tool allowlist は採用した各 repository の project config で宣言する。global Codex / Claude config と managed hook は変更しない。

## Nix package と対応 system（確認済み）

この repo の `llm-agents.nix` pin には `code-review-graph` v2.3.7 package が既にあるため、Linux / Apple Silicon だけなら新しい flake input は不要である（[fixed package definition](https://github.com/numtide/llm-agents.nix/blob/71c0eafcae20331346e60154ca843d4791ba1245/packages/code-review-graph/package.nix)）。

ただし固定 package の `meta.platforms` は次の3 systemだけである。

- `x86_64-linux`
- `aarch64-linux`
- `aarch64-darwin`

この repo と同じ `nixpkgs-26.05-darwin` + `inputs.llm-agents.overlays.shared-nixpkgs` で derivation を評価したところ、この3 system は成功したが、`x86_64-darwin` は `package.meta.platforms` 不一致で評価を拒否された。上流 `llm-agents.nix` 自体も 2026-07-21 に x86_64-darwin output を削除している（[upstream commit](https://github.com/numtide/llm-agents.nix/commit/718f56b955bb074b458c644472e03264e378169d)）。この repo は [Architecture](../architecture.md) に従って 2026-12-31 まで4 systemを維持するため、`modules/ai.nix` の共通 package listへそのまま足すと契約違反になる。

依存についても注意が要る。upstream v2.3.7 は `fastmcp>=3.2.4,<4`、`tree-sitter-language-pack<1`、`watchdog<7` 等を要求する（[pyproject](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/pyproject.toml#L27-L38)）。一方、固定 Nix package は FastMCP tests を `doCheck = false` にし、dependency check を skip して複数 bounds を relax する（[package definition](https://github.com/numtide/llm-agents.nix/blob/71c0eafcae20331346e60154ca843d4791ba1245/packages/code-review-graph/package.nix#L8-L58)）。

`llm-agents.nix` 単体の package set と、この repo の shared-nixpkgs integration では依存 version が異なる。採用時に実際に使う後者を評価・build した結果は次のとおり。

| 項目                      |    実測 |
| ------------------------- | ------: |
| code-review-graph         |   2.3.7 |
| Python                    | 3.13.14 |
| FastMCP                   |   3.2.3 |
| MCP                       |  1.26.0 |
| tree-sitter-language-pack |   1.4.1 |

clean environment で `code-review-graph --version` は成功し、core graph build も動いたため「起動不能」ではない。しかし FastMCP 3.2.3 は upstream CRG が明記する 3.2.4 floor 未満であり、dependency check の緩和がその差を隠している。FastMCP v3.2.4 自体も security hardening を含む release である（[official FastMCP v3.2.4 release](https://github.com/PrefectHQ/fastmcp/releases/tag/v3.2.4)）。標準 stdio / local-only CRG path に各修正が exploit 可能かは未確認なので「既知の直接脆弱性」とは断定しないが、少なくとも upstream runtime contract を満たしていない。

**実装:** [`packages/code-review-graph.nix`](../../private_dot_config/nix-devshell/packages/code-review-graph.nix) は、同じ flake に source-only で pin 済みの Nixpkgs package 定義から FastMCP 3.3.1 を CRG 専用 Python 環境へ backport する。CRG 2.3.7 の package source / hash は `llm-agents.nix` pin を再利用し、FastMCP 3.2.4 floor を assert する。さらに CRG 自身の `>=0.9,<1` 制約内で、universal2 wheelも公開された `tree-sitter-language-pack` 0.13.0 の source distributionを buildする（[PyPI files](https://pypi.org/project/tree-sitter-language-pack/0.13.0/)、[Nixpkgs package definition](https://github.com/NixOS/nixpkgs/blob/cc53eadbdb10015c09c2bd48c6e82877b2f777ee/pkgs/development/python-modules/tree-sitter-language-pack/default.nix)）。1.4.1 の parser releaseには Intel Mac bundleがないため、metadataだけを拡張する方法は採っていない。4 system の derivation 評価と Linux build / CLI run を導入時の検証対象とし、Intel Darwin の実機 runtime は未確認として残す。

## 認証、外部通信、privacy、security（確認済み）

core の build / review / search / stdio MCP は API key 不要で local 実行され、telemetry はなく、graph data は repository 内の SQLite に保存される（[LEGAL](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/docs/LEGAL.md#L1-L16)、[SECURITY](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/SECURITY.md#L26-L53)）。外部通信は主に次の opt-in / ancillary path で発生する。

- local embeddings は初回に Hugging Face から sentence-transformers model を取得する。
- cloud embeddings は明示選択した provider へ identifier、signature、structural context、bounded docstring / comment 等の source-derived text を送る。`CRG_ACCEPT_CLOUD_EMBEDDINGS=1` は egress warning の acknowledgement であり、通信停止 flag ではない（[embedding configuration](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/README.md#L516-L575)）。
- v2.3.7 の visualization HTML は D3.js を `d3js.org` CDN から取得する（[v2.3.7 SECURITY](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/SECURITY.md#L49-L53)）。vendored D3 への変更は release 後である。
- `uvx` を MCP command に選ぶ上流 installer 経路では package cache miss / update 時に registry 通信が起こり得る。Nix package の固定 store pathを使えばこの経路は不要である。

v2.3.7 の HTTP mode は localhost bind が既定だが、Host / Origin validation はない。DNS rebinding guard は release 後の [`e6d508d7`](https://github.com/tirth8205/code-review-graph/commit/e6d508d7) と [`e13a8c0d`](https://github.com/tirth8205/code-review-graph/commit/e13a8c0d) で追加された。したがって v2.3.7 PoC で HTTP transport を有効にしない。

さらに、MCP は既定で全30 toolsを公開する。その中の `apply_refactor_tool` は `dry_run=false` が既定で、source を変更し得る（[command reference](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/docs/COMMANDS.md#L212-L241)）。上流 source は全 tool schema の公開コストを LLM turn あたり約8,000 description tokens と見積もっており、graph queryで減らす contextと別に固定 overheadが生じる（[tool filtering source](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/code_review_graph/main.py#L1014-L1033)）。`--tools` / `CRG_TOOLS` で allowlist にできるため、PoC では read-only tool だけに限定する（[tool filtering](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/README.md#L577-L600)）。

## 保守状況と効果の根拠（確認済み）

project は MIT License、Python package classifier は Beta である（[metadata](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/pyproject.toml#L5-L25)、[LICENSE](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/LICENSE)）。v2.3.7 release は package / daemon / parser / security fixes を多数含み、release 後も main の更新が続いているため、放置 project ではない。一方、公開後2週間で Codex integration、HTTP security、parser、benchmark、packaging に大きな差分が積まれており、設定と品質評価はまだ安定期とは言いにくい。

効果の数値は慎重に扱う必要がある。

- v2.3.7 は whole-corpus baseline 比で約82倍の token reduction を掲げるが、上流自身が「有能な agent は whole corpus を読まず grep するため、この baseline は上限」と明記する（[v2.3.7 FAQ](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/docs/FAQ.md#L76-L106)）。
- current main の再測定では中央値は約65倍へ下がった。impact F1 0.693 の ground truth は同じ graph 由来で循環的であり、より独立した co-change mode は全 graded commit で prediction 0 となって測定として未完成である（[current benchmark](https://github.com/tirth8205/code-review-graph/blob/1a010deed6c283d4aa1e7e949e78fe3a7bcdfbb3/README.md#L210-L263)）。
- keyword search MRR 0.35、flow detection recall 33%、小さい single-file diff では graph response が raw content より大きくなる場合がある（[current limitations](https://github.com/tirth8205/code-review-graph/blob/1a010deed6c283d4aa1e7e949e78fe3a7bcdfbb3/README.md#L281-L287)）。
- 上流 FAQ は「数百 file 未満」「trivial single-file change」「一度しか質問しない repo」を非推奨条件として挙げる（[FAQ](https://github.com/tirth8205/code-review-graph/blob/6a1ee1c7063cc35cfa5ff12b8198c29360f3e4ad/docs/FAQ.md#L128-L144)）。

よって、上流 benchmark は「大きな graph-aware context reduction の可能性」を示すが、この dotfiles で既存の `rg` / Serena / `code-review` skill より優れることは示していない。

## この dotfiles での実測（確認済み）

既存 worktree の未コミット変更を汚さない隔離 clone で、pin 済み Nix packageを使って測定した。

| 項目                          |                                                          結果 |
| ----------------------------- | ------------------------------------------------------------: |
| tracked files                 |                                                           237 |
| 主な内訳                      | Markdown 87 / Nix 27 / Bats 23 / tmpl 14 / shell 13 / JSON 13 |
| build console の parsed files |                                                            70 |
| `status` の indexed files     |                                                            63 |
| nodes / edges                 |                                                   477 / 1,829 |
| indexed languages             |    Nix, bash, JavaScript, TypeScript, PowerShell, Lua, Python |
| graph DB                      |                                                      約2.3 MB |

build は約3秒で完了した。速度と容量は問題ではないが、tracked 237 filesのうち `status` で index されたのは63 filesで、Markdown、template、lock 等の大部分は graph の構造分析対象外だった。

`modules/ai.nix` へ一行の comment probe を加えて `detect-changes --brief` を実行すると、変更された `llm` binding、risk 0.30、1件の test gap、推定96% token savingsを報告した。しかし実際には [`tests/nix-devshell.bats`](../../tests/nix-devshell.bats) が `modules/ai.nix` と `llm` package contractを直接 grep 検証しており、報告された test gap は false positive だった。推定96%は CRG 自身の heuristic estimateであり、既存 review flowとの独立比較ではない。

この結果は「Nix parser が動く」ことは確認する一方、この repo で最も欲しい test impact mapping の精度が採用基準を満たさないことを示す。

## 既存ワークフローとの位置づけ（判断）

この repo の [`code-review` skill](../../runtime/skill-harness.md) は固定 base に対する commit 済み diff を Standards / Spec の2軸で評価する。CRG は review verdict を代替するものではなく、変更の周辺 context 候補を graph で絞る substrate である。

既存 Codex configには Serena MCPがあり、通常の symbol search / edit は既に coverage がある。CRGを追加する唯一の合理的な位置は、Builder-Evaluator の `code-review` 前に大規模 repo の blast radius / related testsを補助する read-only context provider である。しかしこの dotfiles の実測では、まさにその related-test edgeが false positiveになった。標準 flowへ追加する根拠はない。

## 比較した導入案

| 案                                               | 判断     | 理由                                                                                               |
| ------------------------------------------------ | -------- | -------------------------------------------------------------------------------------------------- |
| CLI と上流 `install` を global 実行              | 不採用   | managed config / hooks / lefthook と衝突し、全 repository に広すぎる MCP surface を公開する        |
| 3 system だけ CLI を配備                         | 不採用   | home-wide tool availability が platform 依存になり、Intel Darwin sunset 前の architecture と不整合 |
| 修正済み local package で CLI だけ4 systemへ配備 | 採用     | 評価対象を増やしつつ、graph / MCP / hook を勝手に有効化しない                                      |
| 各 repository で read-only stdio MCP を有効化    | 条件付き | CLI 評価で既存手段より有効だった repository だけ project config に宣言する                         |

## リポジトリ単位の利用可否判定

候補 repository ごとに次を確認する。詳細なコマンドと project config 例は [AI runtimes](../../runtime/ai-runtimes.md) を正本とする。

1. 数百〜数千 filesで、複数言語または multi-hop impact reviewを反復する repoを選ぶ。dotfiles 自体を PoC対象にしない。
2. 共通 devShell の fixed version / hash packageを使い、FastMCPの upstream floorを満たす。
3. `code-review-graph install`、Codex / Claude hooks、git hook、daemon、HTTP transportを使わない。stdio MCPだけを declarative configで登録する。
4. embeddingは local / cloudとも無効から開始する。cloud embeddingはPoC対象外とする。
5. `CRG_TOOLS` を `list_graph_stats_tool,query_graph_tool,get_impact_radius_tool,detect_changes_tool,get_review_context_tool` 程度の read-only allowlistへ限定し、`apply_refactor_tool`を公開しない。
6. 同じ実review task群を既存 `rg` / Serena / `code-review` flowと比較し、wall time、agent input tokens、正しい impacted files/tests の precision / recall、false positive、stalenessを記録する。
7. 少なくとも related-test mappingが既存手段より改善し、tool schema / maintenance cost込みで再現性ある削減を示した場合だけ、その repository の project config へ MCP entry を追加する。

## 未確認事項

- x86_64-darwin 向け local package closure の実機 runtime。derivation 評価は対象に含めるが、Intel Mac での起動確認は別途必要。
- 大規模な実務 repositoryで、既存 agentic grep / Serenaと比べた独立した token、latency、finding精度。
- current main の HTTP guard、Codex instruction integration、benchmark修正を含む次回 releaseのversionと互換性。

これらは CLI の共通配備を妨げないが、個別 repository の利用可判定を自動的に「可」にする材料でもない。採用判定は repository ごとの実測を正本とする。
