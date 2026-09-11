---
type: concept
title: Skill harness
description: apm 経由の外部 skill 群、mattpocock 設計→実装ワークフロー、chezmoi 配布のローカル skill（to-pr）、playwright-cli、Claude Code plugin の多層管理
tags: [skills, apm, mattpocock, playwright, claude-code, antigravity]
---

# Skill harness

軽量化のため superpowers を外し、workflow 層は mattpocock skills に置換した（→ [ADR-0002](../docs/adr/0002-mattpocock-over-superpowers.md)）。

## apm 管理の外部 skill

`apm.yml` / `apm.lock.yaml` が外部 skill を `~/.claude/skills/` へ展開する。lockfile の再生成は下記「apm lock は runtime layout を再現した隔離ディレクトリで再生成する」の手順に従う（`apm lock` 単体では不十分）。配備は `apm install --frozen` が `run_onchange_after_apm-install.sh.tmpl` から冪等に走る。

**mattpocock 設計→実装ワークフロー** (`mattpocock/skills/skills/engineering/`)。上流 v1.2.3 plugin collection の25 skill（User-invoked / Model-invoked の公式分類）を、検証済み default-branch revision `6654f6b60cd9d5be8b54c6fafe44346dabeb3b76` から APM で配備する。workflow semantics は repo の local contract と照合して採用する。

_User-invoked_（明示起動のみ、orchestration 層。メインフロー1本 + on-ramp 2つで構成する — 詳細は [ADR-0014](../docs/adr/0014-triage-not-after-to-issues.md)、上流 `ask-matt` の main-flow/on-ramp 構造に整合）:

- メインフロー: native worktree での作業開始→ `grill-with-docs` → `to-spec` → `to-tickets` → `implement` → `to-pr`。要件確定済みの小さな作業は `grill-with-docs`/`to-spec`/`to-tickets` を省略して `implement` から直接入ってよい。`to-tickets` までを **Planner**、`implement`（内部で `tdd`/`code-review` を使う）を **Builder-Evaluator** と呼ぶ（[CONTEXT.md](../CONTEXT.md)）。Builder-Evaluator は `to-tickets` が生成した ticket をまたいで、同一 worktree/branch 内であれば止まらずループしてよい（issue #28・#29 が単一 worktree・単一 PR #30 として実践した前例を明文化したもの。単一セッション単位ではなく、phase boundary の選択は下記の v1.2.3 semantics に従う）: `tdd` の green slice commit・`code-review` 後の修正 commit は確認なしで行う（根拠は [ADR-0019](../docs/adr/0019-builder-evaluator-cross-issue-autonomy.md) / [ADR-0022](../docs/adr/0022-align-mattpocock-v1-1-workflow.md)）。`code-review` は `git diff <fixed-point>...HEAD` の三点差分——commit 済みの履歴のみを見る——を review 対象にし、empty diff は明示的に fail するため、commit が無いと `code-review` 自体が動かない。対象 worktree/branch の全 ticket が完了したら `to-pr` を一度だけ実行する（AFK 運用時は自律呼出し可、通常運用は完了報告のうえユーザーの `/to-pr` 呼出しを待つ）。`/to-pr` 呼出しまたは AFK/自律完了の明示許可は、topic branch push・PR create/edit・証跡添付・整合済み `Fixes`・本文で宣言済みの missing native edge 追加への事前承認とする。commit は運用者＝エージェント自身の責務（詳細は [ADR-0015](../docs/adr/0015-add-tdd-commit-confirmation.md) / [ADR-0019](../docs/adr/0019-builder-evaluator-cross-issue-autonomy.md) / [ADR-0022](../docs/adr/0022-align-mattpocock-v1-1-workflow.md)）
- on-ramp（raw issue: `to-tickets` の産出物には使わない）: `triage` → ready-for-agent 化 → `implement` へ合流
- on-ramp（ハードなバグ）: `diagnosing-bugs` → `code-review` → `to-pr`。raw な報告ならまず `triage` を通す

外部 skill は APM 配布物を fork せず、repo の指示層で必要な差分だけを **ローカル skill 上書き**として定義する（[ADR-0023](../docs/adr/0023-resolve-external-skill-contracts-locally.md)）。現行の上書きは次の4点:

- `triage` は推薦根拠を得る read-only 検証を推薦前に実行してよい。推薦・適用内容の判断点は維持するが、内容確定後の非破壊な GitHub 定型書込みは二重確認しない。close/reopen/delete は引き続き確認する。
- Builder-Evaluator 内の `code-review` は branch の既知の base（通常 `origin/main`）を fixed point として自動採用してよい。standalone で fixed point が不明な場合だけ質問する。
- `gh-address-comments` は GitHub plugin の flat な comment read と `gh api graphql` を併用せず、thread-aware な取得・返信・resolve を専用 CLI `gh-review-thread` に統一する。review 対応依頼は選択 thread 群の Review Round（修正・検証・`fix: address PR review feedback` commit・`git-push-topic`・日本語返信・resolve）を承認する。コード修正は commit が現在の PR 履歴に含まれた後だけ短縮 SHA・修正要約・検証結果を返信して resolve する。説明のみは `--explanation-only` を明示し、根拠を返信して空 commit を作らない。同一本文の自分の返信は再投稿せず未完了の resolve から再開し、thread 単位の失敗は open のまま理由を記録して残りを続行する（[ADR-0032](../docs/adr/0032-automate-review-round.md)）。
- `empirical-prompt-tuning` は `tool_uses` または `duration_ms` を取得できない round を strict convergence の判定に含めない。`qualitative plateau; quantitative convergence unverified` と報告して metadata を提供する runtime で再評価するか、明示的な `resource cutoff` として終了する。

### Managed workflow semantics と local safety boundary

上流 v1.2.3 の semantics と、その後の検証済み workflow 本文は、skill を fork せず APM payload とこの指示層の組み合わせで採用する。

- **Explicit invocation**: cross-skill 呼出しは `Call the Skill tool with "<name>"` 相当として Skill tool と skill 名を明示する。setup 情報がなければ、依存する skill は user-invoked の `setup-matt-pocock-skills` を自動実行せず、ユーザーへ明示起動を案内する。
- **Frontier grilling**: `grilling` は依存関係が解決済みの全 decision を frontier round でまとめて提示し、各質問へ推奨を添え、複数質問の間を horizontal rule (`---`) で区切る。各 round の人間の回答を待ち、事実は環境探索で埋め、未回答の decision を推測して先へ進まない。`ui-grill-with-docs` は同じ frontier round の全質問をラウンド質問シートにまとめ、visual comparison が必要な質問には同じHTML内で disposable mockup を添える。回答はMarkdownでコピーしてチャットへ渡す。
- **Phase boundary**: 公式の選択肢は `Continue → /clear → /handoff → Subagent → /compact`。phase の途中では判断せず、boundary でこの順に評価する。次 phase が現 phase を primary source として必要、または smart zone（目安 ~150k tokens）に収まるなら `Continue`。context が次 phase と無関係なら `/clear`。新しい harness / directory / repo / colleague へ portability が必要な場合だけ `/handoff`。AFK で独立して実行できる scoped task は `Subagent`。同じ harness / directory の relevant context を保ったまま要約する場合は `/compact` を使う。
- **Builder-Evaluator**: 同一 worktree/branch では ticket をまたいで `implement` を続けてよい。ticket 境界で relevant context が同じ harness / directory にあるなら `/compact`、移植性が必要な場合だけ `/handoff` とする。`tdd` の red-green、commit、`code-review`、full verification の境界は既存 Contract と Verification Matrix を維持し、`to-pr` は worktree/branch 単位で一度だけ実行する。
- **Model-invoked safety**: model-invoked discipline は current repository の実装契約内で動くが、外部書込み（Issue / PR / shared service など）は親の Contract または明示的に起動された user-invoked skill の承認範囲に限る。機密情報・credential・CI secret は読み出し、出力、commit、無断変更をしない。権限拡大や permission bypass は推測せず、現在の runtime profile と project instructions に従い、必要ならユーザーへ戻す。
- **Prototype lifecycle**: state model を検証する `prototype` の logic path は single self-contained HTML とし、build / server 不要、inline の pure logic、free-play と guided walkthroughs、各操作後の全 state 表示を持つ。決定を本実装へ反映した後も prototype 全体は throwaway branch に primary source として残し、implementation issue から参照する。main branch には検証済み decision だけを残す。
- **Instruction ownership**: `AGENTS.md` は Codex / OpenCode / Zed / Cursor、`CLAUDE.md` は Claude Code 向けに別管理する。共有すべき workflow / safety contract は双方で整合させ、runtime-specific な browser / tool 差分は各ファイルに残す。
- **Worktree ownership**: 作成・選択は native 機構へ委ね、開始時の検証と参照不能時の復旧は下記「Worktree の開始と復旧」に従う。

### Worktree の開始と復旧

Worktree Entry Point は、対象 task worktree を確認して作業を始める契約。独立スキルの呼出しは不要。作成・選択には実行環境の native 機構を使い、既存の task worktree は同じ依頼への所属を確認して再利用する。変更前に physical root、ブランチ、HEAD、status、worktree 固有 Git dir と common dir を read-only に確認し、全 phase を同じ checkout で続ける。親の未コミット変更を移動・上書きしない。説明・読み取り調査は primary checkout や Git 検証不能の環境でも継続できる。

- **Herdr**: 明示依頼時に `herdr` スキルを使い、`HERDR_ENV=1` を確認して native worktree・pane を管理する。Codex の隔離起動は、対象 pane の shell prompt から `codex-worktree` を実行する。既存 linked worktree を受け取る adapter なので `--worktree` は渡さない。pane の cwd と返却された ID を確認し、background 起動は `--no-focus` を使う。agent 認識と入力可能状態を親が確認してから依頼を引き継ぐ。隔離内では Herdr socket を公開せず、Herdr の制御は親が担当する。
- **Orca**: native worktree と Agent Picker の built-in agent 起動を使い、permission mode は Orca に委ねる。自律 workflow は shipped Yolo、確認を残す場合は Manual と Orca Source Control を使う。Orca native Codex は `codex-orca` / `codex-worktree` を使わない。worktree は review / recovery の境界であり OS sandbox ではないため、Yolo は信頼できる repository / host に限る。runtime 自己認識で Orca を識別し、`ORCA_*` environment の汎用判定は導入しない。Orca primary checkout からの実装は native worktree の新しい agent session で開始する。
- **Claude Code / Codex**: Claude Code は `EnterWorktree`、Codex app は native worktree、Codex CLI の新規作成は導入版の `codex --help` に従い `--worktree` を使う。native 作成と隔離起動は別の責務。raw Codex の秘密隔離が必要な場合は、作成済み linked worktree で既存 `codex-worktree` を使い、その公開入力登録・trust・返却契約に従う。

Git 管理情報を解決できない場合は編集・Git 書込みを保留し、以下を区別する。

1. **owner 側でも検証不能**: pointer / back-pointer / common dir の不整合、参照先消失、別 repository への所属を読み取りで診断する。変更を始めず、確認できた原因と必要な修復を報告する。
2. **owner 側では有効、子から参照不能**: worktree の破損とは断定せず、実行環境の参照範囲を調べる。親は同じ worktree に正規経路の後継セッションを起動し、依頼・合意・対象 root / branch / HEAD・変更状況・実施済み検証・残作業を引き継ぐ。子が自分の環境で再検証に成功してから変更を再開する。親の検証だけで子の検証を省略しない。

依頼済みタスクの正規経路での復旧・引継ぎには二重確認を求めない。後継起動前に元担当が編集を停止していることを確認し、同じ worktree を同時編集しない。既存 pane の強制終了、worktree の削除・作り直し、権限拒否の迂回、共有設定の権限拡大は復旧に含めない。新しい根拠や正規経路がない同じ失敗は繰り返さず、最後の検証結果と再開に不足する条件を報告する。

Herdr 0.9.0 では adapter 内の対話 Codex が入力可能でも `agent list` に現れない事例を実測した（[ADR-0057](../docs/adr/0057-retire-to-worktree-for-native-entry.md)）。この場合は自動引継ぎ未完了として報告し、親自身が検証できる task worktree での作業は継続する。

起動しただけでは引継ぎ完了としない。対話 agent の認識・入力可能状態と、子からの checkout / Git 検証を別々に確認する。`codex-worktree sandbox` の成功は対話 agent 起動の代用にならない。配備済み公開入力・trust・接続前提が不足している場合も、通常環境の秘密値や権限を変更して代用しない。

`harness-feedback` は外部 skill 本文だけでなく system/developer 指示と runtime に対応する project 指示（Codex系は `AGENTS.md`、Claude Codeは `CLAUDE.md`）を含む **実効契約**を評価する。下位 skill との差がローカル上書きで解決される場合は finding ではなく、必要に応じて Contract Warning として報告する。

- wayfinding: 巨大で曖昧な作業は `wayfinder` で調査・決定 ticket の map を作り、frontier が明確になってから Planner / Builder-Evaluator へ合流する

`ready-for-agent` ラベルを付与する際は、`triage` 経由・`to-tickets` 経由のいずれでも次の6項目を最低条件とする: 目的 / AC / 非目標 / 検証方法 / 関連ファイル・入口 / 判断済み tradeoff（[CONTEXT.md](../CONTEXT.md) の Contract 参照）。`triage` / `to-tickets` はいずれも apm 経由の vendored skill であり、この最低条件を skill 自体に組み込んで機械的にゲートすることはできない——ラベルを付与する運用者（実行エージェント自身）が確認する doc-level discipline とする。2つの経路でチェックポイントの位置は異なる: `triage` は「Apply the outcome」というラベル付与前の明示的な判断点を持つため、そこで6項目の充足を確認してから `ready-for-agent` を付与する。`to-tickets` は ticket の生成とラベル付与を同一ステップ（Publish the tickets）で完結させ、付与前に立ち止まる地点が無いため、事前ゲートではなく**生成直後**に各 ticket 本文を確認し、6項目のうち ticket 本文から読み取れないものがあればその場で本文に追記する（[ADR-0015](../docs/adr/0015-add-tdd-commit-confirmation.md) の commit 確認ステップと同型のタイミング配慮。詳細は [ADR-0016](../docs/adr/0016-to-pr-shared-contract-vocabulary.md)）。

- `setup-matt-pocock-skills` — **必須エントリポイント**。per-repo で issue tracker（GitHub / GitLab / local markdown / その他）、triage label 語彙、domain doc レイアウト（`CONTEXT.md` + `docs/adr/`）を構成し `docs/agents/*.md` を生成
- `grill-with-docs` — 対話しつつ `CONTEXT.md` と ADR を更新（`domain-modeling` に委譲）
- `to-spec` — 会話を spec（旧称 PRD）にして issue tracker へ publish
- `to-tickets` — plan/spec を vertical slice の ticket に分解
- `implement` — spec/ticket に基づく実装入口。可能な範囲で `tdd` を使い、最後に `code-review` して current branch に commit
- `triage` — issue を state machine（needs-triage / needs-info / ready-for-agent / ready-for-human / wontfix）で捌く
- `ask-matt` — user-invoked skills の router（どのフローが合うか迷った時）
- `improve-codebase-architecture` — ball-of-mud レスキュー。deepening 機会を HTML レポートで提示
- `wayfinder` — 1セッションに収まらない巨大で曖昧な作業を、調査・決定 ticket の map と frontier に分解

_Model-invoked_（実装フェーズで自動発火する discipline 層。上流ルール: user-invoked は他の user-invoked を呼ばない）:

- `tdd` — red-green-refactor
- `code-review` — Standards 軸 + Spec 軸の 2 軸並列レビュー
- `resolving-merge-conflicts` — merge/rebase conflict 解決時に primary source を読んで両変更意図を保つ discipline
- `diagnosing-bugs` — ハードバグ / 性能回帰の診断ループ
- `domain-modeling` — `grill-with-docs` / `triage` が委譲する依存（`CONTEXT.md` + ADR 維持の実体）
- `codebase-design` — deep module 設計の共有語彙（interface / seam / testability）
- `prototype` — 設計質問に答える捨てプロトタイプ
- `research` — 一次情報リサーチを background agent で行い cited Markdown を残す

実装フェーズの user-invoked entrypoint は `implement`。`tdd` / `code-review` / `resolving-merge-conflicts` / `diagnosing-bugs` などは model-invoked discipline として必要時に発火する。`grilling`（productivity/Model-invoked、`grill-with-docs`/`grill-me` の共通ループ）は frontier round semantics を採用する。公式 v1.2.3 full set の APM 配備により `grill-me` と `teach` も managed set に含め、旧除外判断と workflow semantics の migration は [ADR-0040](../docs/adr/0040-adopt-mattpocock-v1-2-3-full-set.md) / [ADR-0041](../docs/adr/0041-adopt-mattpocock-v1-2-3-workflow-semantics.md) で管理する。

このワークフローは per-repo で完結する。ラベル provisioning は dotfiles では持たず、各 repo で `gh label create` または skill のランタイム挙動に任せる。domain doc は mattpocock ネイティブの `CONTEXT.md`/`docs/adr` を使い、この `runtime/` バンドルとは混ぜない（`runtime/` は home-wide ambient 知識専用）。

**apm のマルチランタイム配布**: `apm.yml` の `targets` は `claude` / `codex`（apm の `install` は `antigravity` target を非対応）。apm は全 skill を APM-native の共有ハブ `~/.agents/skills/` に必ず materialize し（target とは独立）、Claude 向けには `~/.claude/skills/` にも配備する。**Codex と Antigravity はどちらも `~/.agents/skills/` を global skills location として直接読む**（Codex は `codex debug prompt-input` で skill 可視性を実機確認済み）ため、apm skill は追加配線なしで 3 ランタイムに可視。`~/.codex/skills/` は Codex の native location だが apm 0.23 は配備せず、過去に配備された real dir が残っていても discovery は `~/.agents/skills/` 側が担う。

**apm lock は runtime layout を再現した隔離ディレクトリで再生成する**: apm の target 解決はカレントディレクトリ基準なので、`apm.yml` を一時ディレクトリへコピーし、live onchange と同じ `apm install --target claude,codex --https` で生成した `apm.lock.yaml` を repo へ戻す。install が新規配備時に deployed_files / deployed_file_hashes を lock へ追記するため、`apm lock` だけの lock を採用すると materialization 情報が欠落する。更新後は同じ隔離環境で `apm install --frozen --target claude,codex --https` を実行し、lock の SHA-256 が変わらないことを確認する。非 candidate dependency を一時 pin する update gate の作業用 lock をそのまま source に採用せず、最終 source lock は実際の unpinned manifest から生成された native 形式（`resolved_ref` は manifest の exact pin だけ、single-quote）にする。`~/.agents/skills` / `~/.claude/skills` は直接変更せず、lock は oxfmt で再整形しない（`lefthook.yml` で除外済み。再整形すると apm が runtime で書き戻して chezmoi と永続 drift する）。

**Matt Pocock managed full set の update gate**: candidate revision は [ADR-0042](../docs/adr/0042-mattpocock-managed-set-update-gate.md) の順序で [実行可能な gate](../tests/mattpocock-update-gate.sh) に通す。隔離 runtime 内だけで accepted lock の非 candidate dependency を一時的に exact pin し、lock generation → `apm install --frozen`（SHA-256 no-rewrite）→ `apm audit --ci` → full-set discovery / workflow payload contract → related workflow contract tests → full `bats tests/` → `chezmoi --source "$SOURCE_DIR" apply --dry-run` を一つの検証境界とする。candidate package と Matt 単独所有の deployment ledger record だけを比較対象から外し、共有 owner を持つ record を含む非 Matt lock field の drift、candidate 外の manifest 差分、full-set / cleanup mismatch、native route、`@latest` / `main` / native Claude plugin / universal installer は reject する。全て通過した exact commit だけを採用し、失敗時は accepted manifest / lock pair を保持して partial adoption を commit しない。

2026-07-21 の上流更新では mattpocock workflow を commit `9603c1c` に統一し、各 skill の Codex metadata（`agents/openai.yaml`）と最新の grilling / ticket / wayfinding guidance を取り込んだ。repo 固有の main-flow と上書き契約は引き続き `AGENTS.md` / ADR を優先する。Impeccable は commit `4d849eb` に更新し、Design Hook の重複 finding 修正と検出精度改善を quiet hook テストで検証した。未固定の APM 依存も同時に再解決し、Remotion は上流の canonical path `remotion-best-practices` へ追従した。lock は APM 0.26.0 の隔離 runtime layout で再生成し、同じ環境の `apm install --frozen` が書き戻しなしになることを確認した。

2026-07-31 の更新では、Impeccable HEAD `32930818a109fafa87199babe92fa8e530cff5d3`（4.0.4）を候補に Design Hook 互換性ゲートを実行し、quiet / immediate tier / Stop deep pass / dedupe / edit threshold / sensitive・generated path filter / Stop re-entry の runtime 契約を 7/7 テストで維持した。未配備・内部失敗時の fail-soft は managed hook の fail-open テストで別途確認できたため、新しい検証済み Skill Pin として採用した。既知の both-tiers Stop 交互報告は未修正で、characterization test を維持する。floating dependency の再解決で payload が変わったのは Impeccable、Remotion（4.0.503。相対リンク、multi-scene、timing / transition 等）、Supabase（schema / migration / RLS / security を含む trigger description）の3件。Shadcn、Orca 3 skill、find-skills は repository revision だけが進み selected skill subtree の content hash は不変、Matt Pocock の選択済み skill 群は `ed37663cc5fbef691ddfecd080dff42f7e7e350d` を維持した。APM 0.26.0 の隔離 HOME で lock を生成し、同じ runtime layout の frozen install で再現性を確認した。

2026-08-06 の更新では、APM 0.28.0 の隔離 runtime layout で lock を再生成した。Impeccable HEAD `a075d89bdbe60b2b00220cb0527fb5091e84215e`（4.0.4）は同じ Design Hook 互換性ゲート 7/7 と managed hook の fail-open 契約を維持したため、新しい検証済み Skill Pin として採用した。既知の both-tiers Stop 交互報告は未修正で、characterization test を維持する。floating dependency の selected payload が変わったのは Impeccable、Modern Web Guidance（`684ab9d7`）、Remotion（`7809e793`）の3件。Shadcn、Orca 3 skill、find-skills は repository revision のみ進み selected subtree の content hash は不変、Matt Pocock の選択済み skill 群は `ed37663cc5fbef691ddfecd080dff42f7e7e350d` を維持した。同じ環境の `apm install --frozen` は lock を書き戻さず、ライブ skill directory と `chezmoi apply` には触れていない。

2026-08-15 の更新では、Impeccable `5a149f3fdb1b5793f10567233b1dcab98fc305fd`（4.1.1）を候補に、session初回の full policy footerと以後のshort footer、`ignore-file` / `ignore-rule`の承認境界、理由付き`ignore-value`の`detector.ignoreValues`限定保存を新しい契約へ加えた Design Hook gate 9/9、managed hook fail-openを通過したため採用した。確信のある false positive / 許容済み例外への `ignore-value` はagentが自己適用して根拠を開示できるが、`ignore-file` / `ignore-rule` はユーザーの明示承認を要する。既知の both-tiers Stop交互報告は未修正でcharacterization testを維持する。floating dependencyのselected payloadが変わったのはImpeccable、Remotion（`2a204c9b`）、Vercel React View Transitions（`b8caa260`）。Matt Pocockの20 skillはaliasなしrenameとworkflow差分のため`ed37663cc5fbef691ddfecd080dff42f7e7e350d`に据え置いた。APM 0.28.0の隔離runtime layoutで全37 dependencyを再生成し、`apm install --frozen --https`が書き戻しなしになることを確認した。

2026-08-18 の更新では、Impeccable `5c5553b1d7f9e89bb833f9179cea681742a17720`を候補に、APM 0.28.0の隔離runtimeで Design Hook gate 9/9とmanaged hook fail-open 1/1を再検証した。hook / footer / adminのcore blobは前pinと同一で、static HTML selectorのcompile cacheなどselected payloadの変更も既存契約を維持する。Remotionは`9f0faa50`（version markerのみ）、Orcaはlock生成時の`a1cd7eaa`までを候補lockとして評価した。既知のboth-tiers Stop交互報告と、理由付き`ignore-value`だけを自己適用できる境界は変更しない。Matt Pocockの20 skillは`writing-for-agents`へのrename、frontier interview、HTML prototype、handoff / compact / clearのphase boundaryをローカル契約へ調停できていないため`ed37663cc5fbef691ddfecd080dff42f7e7e350d`に据え置く。APM binaryも0.28.0を維持し、同じ隔離runtimeの`apm install --frozen --https`がlockを書き戻さないことを確認した。Claude interactive gateが未完了なので、配備sourceはacceptedなImpeccable `5a149f3fdb1b5793f10567233b1dcab98fc305fd`と対応lockを維持し、候補revisionはADRと調査ノートだけに置く。

2026-08-20 の更新では、`llm-agents.nix` を snapshot `20766586959e0dcc2f9e7cff6d49b0c710de30d6` へ進め、Claude Code 2.1.237 / Codex 0.148.0 / Antigravity CLI 1.1.16 を採用した。Copilot CLI 1.0.80、RTK 0.45.0、APM 0.28.0 は変わらない。APM は selected payload が変わった Modern Web Guidance `460e5536`、Remotion `21320596`、Orca `orca-cli` `5ca747da`だけを lock 更新し、revision-only の PDF、Shadcn、find-skills、Orca `computer-use` / `orchestration`、Impeccable、Matt Pocock は現行 pin / payload を維持した。候補 lock は隔離 runtime の `apm install --frozen --https` と `apm audit --ci` を通過し、Design Hook gate 9/9 と managed fail-open 1/1、3 system の Nix check / deep evaluation、Linux host smoke、Claude/Codex smoke も完了した。managed session の home filesystem が read-only のため `chezmoi apply` と live `apm install --frozen` は完遂できず、実環境への反映は後段に残す。

2026-08-21 の更新単位では、`llm-agents.nix` snapshot `d205793bf7c7f4cb41ce73ba0983c5f7a5e2c6da`、Claude Code quality floor `2.1.238`、Codex quality floor `0.149.0`、Antigravity CLI `1.1.17` を採用候補とする。APM は stable `0.28.0` のまま、selected payload が変わる Remotion だけを `7fc6dea333869e23f58bf9e9861010e9ba589e5e` へ進め、revision-only dependency は維持する。source gate は3 system Nix evaluation、CLI version / startup smoke、既存の Claude/Codex trust・config、隔離 APM frozen install / audit / lock no-rewrite / Remotion discovery とする。Impeccable の Design Hook compatibility、Matt Pocock workflow migration、APM main の trust-bin 変更は別更新単位であり、この更新では配備しない。core source gate が実際に失敗した場合は旧 source pin を fallback とし、partial adoption は認めない。managed session の実行制約による未確認は source gate の失敗と区別して verification record に残し、未確認の live behavior は保証しない。`chezmoi apply` と live discovery は source gate 後に試み、managed session の read-only 制約があれば未確認として記録する（→ [ADR-0040](../docs/adr/0040-update-llm-agents-and-remotion-update-unit.md)）。

2026-08-27 の通常 APM payload更新単位では、APM 0.28.0の隔離cwd/HOMEで全18 dependencyを比較し、selected payloadが変わったModern Web Guidance `457c381def89ce6213a171238f92eea63e9eaeb2`とRemotion `7a3d0ca45d2f6a00bf35cb3c525734a36d55a834`だけをexact pin候補として採用した。Shadcn `683a5a9b`とOrca `computer-use` / `orchestration` `9c01e09e`はcontent hash不変のrevision-only進行としてfloating解決をlockへ自然反映し、Impeccable、Matt Pocock、Orca CLIの既存exact pinは維持した。隔離materialization後のfrozen install前後でlock SHA-256は`d43138a744099027b61ad50150b4a36246f747214d23761c9f970b3a38d03720`から変わらず、audit 10/10とClaude/Codex両targetのdiscoveryを通過した。live skill directoryと`chezmoi apply`は後続の最終配備単位に残す（→ [ADR-0045](../docs/adr/0045-separate-llm-agents-and-apm-update-units.md)）。

同日の Matt Pocock workflow 更新単位では、上流 default branch `main` の HEAD `6654f6b60cd9d5be8b54c6fafe44346dabeb3b76` を実装入口で一度だけ固定した。plugin version `1.2.3` と25-skill membershipを維持し、plugin未収録の`implement-spec` / `retro`は導入していない。selected payloadのcontent hashは`sha256:30aaf1538e75a717db8608778e06e1c47ce38578f46fe88e53e599818cf30c9f`で、明示的なSkill tool呼出し、frontier question separator、setup未済時のuser pointerを含む。専用ordered gateはaudit 10/10、related contract 48/48、full Bats 396/396（Impeccable materialization 9件skip）、Claude/Codex両targetのfull-set discovery、isolated chezmoi dry-runを通過した。live applyは親initiativeの最終配備境界に残す（→ [ADR-0045](../docs/adr/0045-separate-llm-agents-and-apm-update-units.md)）。

同日の最終配備では chezmoi source を live HOME へ apply し、初回 smoke で Matt gate の一時 pin layout が source lock の unpinned dependency に `resolved_ref` を残していたことを検出した。live writebackは診断 evidence に限定し、実際のunpinned manifestを新しい隔離cwd/HOMEでnon-frozen installしてnative lockを再生成した。Orca `computer-use` / `orchestration` はrevision-onlyの `026389a3bc03da03ca2d65295e805493712b0774` へ自然再解決されたが、両 selected content hash は維持した。隔離環境のfrozen install前後でlock SHA-256 `29186c40a47bf6c25d9fbf73d15ebba4dc9575be7242f381ddaeac82ed24e6c4`は不変、auditは10/10となり、この生成物だけをsourceへ採用した。再apply後のsource/live checksum一致、live frozen no-rewrite、audit、Claude/Codexの通常payload・Impeccable・Matt 25 skill discovery、Design Hook 10/10とmanaged fail-open 3/3を通過した。Codex native hooks は配備済みだが新しいentryの実セッション実行には初回trust approvalが必要であり、permission bypassはせず未確認として残す（→ [ADR-0045](../docs/adr/0045-separate-llm-agents-and-apm-update-units.md)）。

2026-09-01の通常APM payload更新単位では、PR #207を含む`main`のcommit `c66c0312f09da62bd19dcc0be79219a69d625445`から新しいOrca native worktreeを開始し、採用済みAPM 0.29.0の隔離cwd/HOMEで全18 dependencyを一度の標準installから再生成した。Modern Web Guidance `56c61c9e`、Remotion `357a2708`、Orca CLI `b44ef1e5`はselected payloadの変更をexact pinへ反映し、shadcn `63c1308d`、Effect-TS `2309e6f2`、React View Transitions `063bee94`、Orca `computer-use` / `orchestration` `41ef1ddd`はfloating解決へ自然反映した。Orcaのfloating revisionは`b44ef1e5`以後selected subtree不変で、3 skillのroutingは同じchangesetに由来する。Effectは`effect@rc` setupとtrigger、React View TransitionsはReact/Next.js一次資料、Canary境界、`transitionTypes`、trigger、両target discoveryを通過した。Impeccable blockは完全不変で、Matt PocockはAPM 0.29のaggregate `content_hash`だけが`22de78eb`へ再計算されたが、exact revision・25 skill membership・全deployed file/hashは不変だった。frozen前後のlock SHA-256 `d343147e73c22f76eb0ccbb4a22838987fa29cd6857cd51c8d4002f3fc0e4369`は不変、audit 10/10、Claude/Codex 42/42 discoveryを通過し、live skill directoryと`chezmoi apply`には触れていない（→ [実装記録](../docs/research/llm-agents-and-apm-update-2026-09-01-after-pr-202.md)）。

2026-09-03の通常APM payload更新単位（Issue #212）では、`apm outdated`が提示した7候補を実コミット比較で個別に検証した。`mattpocock/skills`は`apm outdated`が示す最新tag `v1.2.3`（`6acc160e`）よりpin済みcommit `6654f6b6`の方が39コミット先行しており（`gh api .../compare`で実測）、`apm outdated`のtag専用比較に起因するfalse positiveと判明したため対象外にした。`stablyai/orca/skills/orca-cli`は最新tag `v1.4.196`（`aad4ae42`）まで121コミット進んでいたが、そのexact pinへ候補materializeしてもselected subtreeのcontent hashは既存pinと同じ`sha256:83ece910d035d0684195095bb9df5911a028002b2efba1ebbeb4ae66de5e0903`のまま不変だったため、revisionの新しさだけでは進めずexact pinを維持した。残る5件（anthropics/skillsの`pdf` `53048666`・`skill-creator` `53048666`、shadcn `71e50952`、Orca `computer-use` / `orchestration` `40d9927f`）はfloating `(default)`依存で、いずれもcontent hashが不変のrevision-only進行と確認できたため、apm.ymlへの新規exact pin追加はせずlockのfloating解決だけを自然反映した。`pbakaus/impeccable`、`GoogleChrome/modern-web-guidance`、`remotion-dev/skills`は別更新単位のexact pinまたはapm側の"unknown"判定のため今回の候補にしていない。隔離rootでの`apm install --target claude,codex --https`によるnon-frozen materializationと、同一環境の`apm install --frozen`前後でlock SHA-256 `4ff82f45d441efd837b993c761a74894575015581d3d82c7276b3141d0ccff81`が不変であることを確認した。Review Roundでは同じmanifest / lockをGit remoteのない隔離cwdへ複製してfrozen install後も同SHAが不変であることを確認し、`apm audit --ci`を再実行した。organization policy enforcementはGit remoteを判定できないためwarning付きskip、baseline 10/10はdriftなしで成功した。`.agents/skills/` / `.claude/skills/`の両targetのdeployed_filesとcontent hashは変更対象5件を含め候補実体と一致した。apm.ymlは無変更、live skill directoryと`chezmoi apply`は後続の最終配備単位に残す（→ [ADR-0045](../docs/adr/0045-separate-llm-agents-and-apm-update-units.md)）。

2026-09-05の通常APM payload更新単位では、`apm outdated`が再提示した7件を公式 upstream と比較した。shadcnは`rules/styling.md`の`cn` importを独立packageへ移す変更、Orca `orchestration`はdelegationとembedded browserのrouting説明を明確にする変更がselected payloadにあるため採用した。Anthropicの`pdf` / `skill-creator`とOrca `computer-use`はcontent hash不変のrevision-only進行をfloating lockへ自然反映した。Orca CLI v1.4.197はselected path不変、Matt Pocockはpinとmainの`skills/` treeが同一なのでexact pinを維持し、170 commit分の大幅なpayload変更があるImpeccable mainは専用Design Hook gateへ保留した。`apm.yml`は変更せずAPM 0.29.0のnative lockだけを更新し、隔離cwd/HOMEで2回目のfrozen install前後のSHA-256 `1d833fb947eb39a0e8a5a817530ca43e7c6d996b5ec0a65fdd45f5e5f53da010`が不変、audit 10/10、Claude/Codex 42/42 discoveryを通過した。live skill directoryと`chezmoi apply`には触れていない（→ [ADR-0045](../docs/adr/0045-separate-llm-agents-and-apm-update-units.md)）。

2026-09-08の通常APM payload更新単位（Issue #243 第2単位）では、Tool SnapshotのPR #244がmergeされた`c94ecc8`から開始し、APM 0.30.0で最終manifestのnative lockを生成した。Modern Web Guidance `bfd8c8dd`とOrca3スキルの本文変更、Remotion `11986e44`の配備対象13ファイルの版参照更新を採用した。Orca CLIは候補`de0a91b9`へexact pinし、floatingのcomputer-use / orchestrationは候補と同じsubtreeの`1a8640ad`へ自然解決した。Shadcnとfind-skillsはhash不変のrevision-onlyで、ImpeccableとMatt25のpin / selected payload / 配備ledgerを維持した。Mattのpackage_typeだけはAPMのnative出力に従い`apm_package`となる。隔離cwd/HOMEでfrozen前後のlock SHA-256 `1b39cba0a658527f7068dc4a48d0c9a296de6ed1114edefe6e549d681ae81c6c`が不変、audit 10/10、Claude/Codex 42/42と全配備hashの照合を通過した。実行中Orca 1.4.197の3ガイド取得と`--full`の互換経路も確認した。live配備とImpeccable移行は後続境界に残す（→ [実装記録](../docs/research/apm-payload-243.md)）。

2026-09-08のImpeccable移行単位（Issue #243 第3単位）は、第2単位のmerge `b6d0030`をbaselineとする。skill 4.2.2 `f64da20b07271b760e4e3133eef3b87942860f11`とlauncherはAPM、engine 0.1.3は3 systemの公式assetを固定hashで取得するNix packageが供給する。native APM 0.30.0のfrozen前後のlock SHA-256 `0ed5562ed58323349baa0245557320667e8297fbca7b4b0b7bd35648a955de98`は不変で、audit 10/10、両target42 discoveryと全配備hash照合を通過した。他17依存とMatt25は不変。実engineでglobalの即時検査とStopを確認し、project opt-inは追加しない。採用物と制限は[ADR-0053](../docs/adr/0053-separate-impeccable-skill-and-engine.md)と[検証記録](../docs/research/impeccable-engine-243.md)を参照する。

2026-09-10の通常APM更新単位（Issue #289）では、17依存の全selected payloadを比較し、Remotion `9ae8048a84690098b1059f7f5d30e6d05833b824`（4.0.523）の15ファイルの変更をsourceへ採用した。Shadcn・find-skills・Orcaのfloating 2スキルは本文不変のrevision-onlyをnative lockへ反映し、Orca CLI・Herdr・Modern Web Guidanceのexact pin、ImpeccableとMatt25を維持した。APM 0.30.0の隔離native生成・frozen・audit後のlock SHA-256は `c15f6e15b89ef11c9e3c43ce149088239a2db44f31f8a833daa728f47e5a340a` で不変、43/43 discovery、全配備hashとownershipが一致した。関連テストは40実行PASS・1 runtime mount skip、隔離source dry-runは成功し、live配備は受入・merge後に残す（[全17依存の採否と検証](../docs/research/update-289-ordinary-apm-skills.md)）。

2026-09-10のImpeccable更新単位（Issue #290）は、通常APMの採用 commit `f423852` をbaselineとし、skill / launcher 4.3.1 `cd12f8660e2dde57b9615c8a6b8ea674101f9cfc` と固定engine 0.1.5を一組でsourceへ採用した。3 systemの公式asset/hashと両devShellのpackage出力、host build、実engineによる既存14テストとmanaged failureテストを通過した。APM 0.30.0のnative install・frozen・audit後のlock SHA-256は `144bf375db3942b1185fc5d73ebcb4965121b27e52bed1ef40b717849fd93c53` で不変、43/43 discoveryと全配布hash・ownershipが一致し、非Impeccable 18依存はrevisionを含め不変だった。管理hook・モデル・権限設定は変更せず、最終full suiteと統合検証は [#295](../docs/research/update-295-integrated-acceptance.md) に記録した。live配備は受入・merge後に残す（[採用物と検証記録](../docs/research/update-290-impeccable.md)）。

**Impeccable**: UI の設計・評価・改善を担う user-invoked / model-invoked skill。検証済み commit に pin し、共有ハブ経由で Codex / Antigravity、Claude skill dir 経由で Claude Code へ配布する。新規 UI の create / shape flow は `PRODUCT.md` / `DESIGN.md` の context setup へ誘導し、既存 UI の scoped 改善は context 文書がなくてもブロックしない。直接の前身である `frontend-design` は責務の重複を避けるため撤去した。

**Design Hook**: user-global に **2 イベント**を配線する。per-edit は Claude Code の `Edit|Write|MultiEdit` / Codex の `Edit|Write|apply_patch` に対する `PostToolUse`（timeout 5s）、deep pass はセッション終端の `Stop`（`matcher` なし・timeout 30s。上流 manifest に合わせた値）。Claude は `~/.claude/skills/impeccable/`、Codex は共有ハブ `~/.agents/skills/impeccable/` の `scripts/impeccable hook` を `IMPECCABLE_HOOK_QUIET=1` で呼ぶ。Nix が `IMPECCABLE_BIN` に固定 engine の絶対 path を渡し、管理 command は実行可能な engine と launcher の存在を確認してから呼ぶ。engine がなければ launcher の自動取得へ進まず無言で終了する。runtime 側は stdin の `hook_event_name` でイベントを、`turn_id` で Codex を判別する。Claude Stop は従来の `hookSpecificOutput.additionalContext`、Codex Stop は native の top-level `decision` / `reason` を返し、managed command は両方を fail-open でそのまま通す。

標準 hook の対象ルールは二層で、**両方を配線して初めて両 tier が届く**（[ADR-0029](../docs/adr/0029-impeccable-pin-advance-with-stop-hook.md)）。per-edit は immediate tier を編集箇所へ返し、その他の対象ルールは `Stop` へ先送りする。Stop はセッション中に触れた UI ファイルを再走査して fresh finding をまとめて返す（per-edit が既に出した分は dedupe。何も残っていなければ無言）。4.3.1 / engine 0.1.5 は上流既定の advisory 除外を使い、従来の deferred fixture `overused-font` は対象外となるため、`side-tab` で遅延検出を検証する。`Stop` は `stop_hook_active` を見て再入時は即座に抜ける。

Impeccable 4.1.2 は Stop scan 後に fresh finding だけでなく live finding 全体を cache へ同期する。immediate / deferred の両 tier を持つファイルでも初回 deep pass 後の次回の `Stop` は無言になり、新しい finding が現れるまで再報告しない。4.1.1 までの交互再報告は解消済みで、4.3.1 / engine 0.1.5でもこの動作を維持し、`tests/design-hook.bats` は実際の管理 commandからこの silent convergence を検証する。

finding footerはsession内の初回だけfull policyを出し、以後はshort footerにする。full policyが許容する自己修復の境界はfinding単位の`ignore-value`までで、agentは確信のあるfalse positiveまたはユーザーが許容済みの例外に限って使い、理由をユーザーへ示す。file / rule全体を抑制する`ignore-file` / `ignore-rule`はユーザーの明示承認が必要である。

いずれの層も、clean UI、非 UI、機密・生成物、重複 finding、同一ファイルの編集閾値超過は無言にする。runtime の未配備・内部エラー・非0終了はすべて成功扱いにする advisory feedback であり、編集を拒否する gate ではない。実装中に人間が画面上の対象を選ぶ要素指差しフィードバック、実装後に AC を検証する Verification Matrix とも役割・主体・タイミングが異なる。Antigravity / Cursor / GitHub Copilot には自動 hook を配線しない。

**UI specialist skill（保持）**: `web-design-guidelines` は Web 実装規則、`modern-web-guidance` は最新 Web API、React 系 skill は React の構成・性能・View Transition、`shadcn` は shadcn/ui、`remotion-best-practices` は動画 UI を担当する。Impeccable はこれらを置き換えず、UI 全体の設計品質を扱う。

**その他 apm skill（保持）**: find-skills, skill-creator, pdf, supabase-postgres-best-practices, empirical-prompt-tuning, effect-ts。

**Herdr**: [公式スキル](https://herdr.dev/ja/docs/agent-skill/)を `herdrdev/herdr/skills/herdr` から APM で配布する。導入時の CLI 0.9.0 と同じ commit `b99002ac99b09e00b4ca692436cb15a6b0d676f1` に固定し、`~/.agents/skills/herdr/` と `~/.claude/skills/herdr/` へ展開する。Herdr の操作を明示的に依頼された場合に使い、制御コマンドの前に `HERDR_ENV=1` を確認する。CLI バイナリは nix devshell が供給する。

## chezmoi 配布のローカル skill

apm 外の user-scoped private skill は chezmoi で配布する。`local-skills/<name>/SKILL.md` の配置自体を配備対象の宣言とし、別の配備・保持一覧への登録は不要とする。ソースは `.chezmoiignore` で `~/` へ直接 deploy せず、`run_onchange_after_deploy-local-skills.sh.tmpl` が各ランタイムの skill dir へ `rsync` で materialize する:

- `~/.agents/skills/<name>/` — 共有ハブ。Antigravity / Codex はここを直接読む
- `~/.claude/skills/<name>/` — Claude

Codex native location（`${CODEX_HOME:-~/.codex}/skills`）へは配備しない。Codex は `~/.agents/skills/` で同じ skill を既に発見でき、native location にも置くと `to-pr` などのローカル skill が二重表示されるため。過去に native location へ materialize された Matt managed real directory も cleanup で撤去する。

cleanup → APM install / prune → ローカル配備の順序を維持する。cleanup と配備は `.chezmoitemplates/local-skills.sh.tmpl` / `local-skills.sh` の共通 module を実行用 script に展開し、同じ配備対象を保持する。HOME へ先に配備される helper には依存しない。APM の配備先にある Matt Pocock v1.2.3 の managed full set は従来の `managed_apm_skills` allowlist で保持し、APM lock と独立した採用ゲートで照合する。

撤去・改名時は `.chezmoidata/local-skills.yaml` の `localSkills.retired` に旧名を追加し、該当するソースを撤去・改名する。明示した旧名は共有ハブ・Claude と旧 Codex native location から除く。配備履歴は保存せず、過去の配備先にも適用できるよう撤去対象の名前を残す。共有ハブの未知のディレクトリを一括削除する処理は追加しない。既存の Claude orphan cleanup と、旧 `writing-great-skills` などの APM 撤去処理は維持する。ただし、現在は APM 所有でない旧名を有効なローカル skill が再使用する場合、共有ハブ・Claude の配備は保持する。

template 展開時に、ソースルート・各 skill の `SKILL.md`・名前の形式・配備対象と撤去対象の重複・APM の実配備先名との衝突を検査する。作業途中の skill は `local-skills/` の外に置き、APM 所有の名前をローカル配備で上書きしない。置換は配備先単位とし、途中失敗時は旧内容を保護するが、成功済みの更新は残る。修復後の再実行で両配備先を揃える。

APM の変更検知には展開後の cleanup script の hash を含めるため、共通 module・配備対象・撤去対象の変更も再実行へ連動する。skill の本文や参照ファイルだけの変更はローカル配備を再実行する。一時 HOME での配置・撤去・再実行・失敗時の挙動は `tests/local-skills.bats`、既存 cleanup 契約は `tests/run_onchange_before_remove-orphan-claude-skills.bats` で検証する（[ADR-0047](../docs/adr/0047-local-skill-membership-and-explicit-retirement.md)）。

構造は **flat な `local-skills/<name>/`**（SKILL.md + references/ + 必要なら scripts/ 同梱で完結）。hooks / agents / marketplace 登録を要するメガパッケージ型の 3層 plugin 構造（`plugins/<ns>/{claude,codex,common}` 型）は不採用: あの構造の必然性は hooks + agents + bin + marketplace 登録というメガパッケージ要件にあり、skill-only なら不要。将来分離したくなったら `local-skills/` ごと新 repo に切り出して apm pin 化すればよい。

現行のローカル skill:

- `ui-grill-with-docs` — UI/UX 比重が高い Planner 向けの `grill-with-docs` 派生。各 frontier round の全質問・推奨・必要な比較モック・回答欄を `tmp/ui-grill-<topic>.html` にまとめ、次の round で同じファイルを更新する。同梱テンプレートは選択肢と自由記述、未回答を明記するMarkdown一括コピー、同じ質問への入力復元を提供し、外部通信なしで動く。保存・コピーが使えない場合も手動コピーでき、貼り付けた回答を待って確定事項を `CONTEXT.md` / ADR に残す
- `to-pr` — 実装完了後（user-invoked チェーンの最後尾）に、issue/ticket/会話から抽出した contract（目的/AC/非目標/検証方法/関連ファイル・入口/判断済みtradeoff）を PR body へ埋め込み、全 AC（UI/CLI/API/infra）を対象にした単一の verification matrix で検証記録を残す。呼出し自体を topic branch push・PR create/edit・証跡添付・整合済み `Fixes`・本文で宣言済みの missing native edge の追加への事前承認とし、外部操作を理由に二重確認しない。push は実際の remote default branch を拒否し、内部で`git push -u origin HEAD`だけを実行する`git-push-topic`を使う。force-pushは方針として禁止し、直接の生の`git push`と代表的なwrapper/global option経由はruntime ruleで遮断する。default branchへの直接pushだけは明示承認後に`git-push-reviewed`を使う。UI は `playwright-cli` で検証し、代表画像と `playwright-report.md` を一時ディレクトリへ生成する。PR 本文の `Playwright Evidence` に操作・観測結果・URL・console/network エラー要約を載せ、認証済みブラウザが利用できる場合は画像を GitHub の PR 添付としてアップロードし、匿名化 URL を埋め込む。WSL2 では検証 identity と分離した共有添付ブラウザの専用 profile が既に GitHub 認証済みの場合だけ `browser-attachments upload` で添付する。認証は PR 証跡添付以外の操作許可を拡張せず、自動ログイン、通常 Chrome profile の流用、認証情報 import は行わない。ブラウザ未認証・操作不可・アップロード失敗時はログインや画像 commit に切り替えず、`手動添付待ち` と証跡の絶対パス・ファイル一覧を引き継ぐ。非UIは既存証拠（`implement` / `tdd` のテスト・commit・lefthook実行）を引用するのみで新規実行はしない。code-review 実施状況も記録する（未実施でも PR 作成はブロックしない）。最終 PR では GitHub native subissues を Ticket Hierarchy の正本とし、ticket 本文の `Parent` と照合する。native parent がなく本文が単一 parent を宣言する場合は **Hierarchy Repair** として、pagination 付きで同じ parent を宣言する全 direct child を列挙・preflight し、missing edge の追加だけを行って child / parent の両側から再検証する。repair failure は `未実施` として失敗 Issue・理由を記録し、親の `Fixes` を省略しても PR 作成は継続する。repair 後、直接の全 child が close 済みまたは Contract / Verification Matrix で covered なら、open な covered child と直接の親へ `Fixes` を付け、`Parent Reconciliation` に判定・理由・close 対象を記録する。reconciliation は直接の親1階層に限り、既存 relationship の削除・reparent、state label cleanup、post-merge automation は行わない。重量級の evidence schema / verdict gate / hero 選定は持ち込まない。
- `dogfood-to-issues` — 同梱の Playwright dogfood runner で web アプリ / Chrome MV3 拡張を隔離 worktree で dogfood し、承認された finding だけを GitHub Issue 化。`--annotate` 指定時は自動検査後、runner 所有 Chromium に Playwright CLI で CDP attach し、矩形注釈と全体 feedback を同じ候補・承認フローへ加える（`--resume` とは併用不可）。issue 作成で完了し、実装へは続かない（triage → model-invoked フローへ）。`scripts/runtime-preflight.sh` 同梱
- `harness-feedback` — Codex / Claude の transcript JSONL を分析し、skill/agent 指示と実際の実行の乖離パターンを検出して小さな指示修正を提案
- `marp` — markdown を Marp CLI で PDF スライド化（marp-cli は nix devshell 配備済み）
- `md-agents-review` — AGENTS.md / Codex rules の対話式レビュー（trim / progressive disclosure）
- `md-claude-review` — プロジェクト CLAUDE.md の対話式レビュー（humanlayer ベストプラクティス基準）
- `rop` — Railway Oriented Programming の two-track パターン強制（Elixir / Gleam / Rust / Effect-TS の言語別 references 同梱）
- `rop-visualizer` — 既存の Effect / Rust Result 実装を読み、成功・失敗・回復を Mermaid railway の単一 HTML にする。ノード選択・ソース抜粋・実現可能経路の強調で実装理解とレビューを支援する。生成時は Playwright CLI と Mermaid を使い、閲覧はオフラインで完結する
- `worktree-gc` — 緊急時（fd/inotify 枯渇）の repo-local worktree 手動 GC。`scripts/worktree-gc.sh` 同梱。SessionStart 自動 GC hook は持ち込まない（手動起動のみ）

### Session Scratchpad 解決

`to-pr` など working directory の外だが session をまたいで残ってよいとは限らない一時成果物（evidence bundle、PR body 下書き、Hierarchy Repair の結果など）を書く local skill は、**Session Scratchpad**（[CONTEXT.md](../CONTEXT.md)）を優先的な置き場にする。scratchpad path の特定は env var の自動検出に頼らない — 実測の結果、Claude Code では session scratchpad path が system prompt にテキストとしてのみ注入され env var には出ず、この injection が session 種別（interactive / `-p` / subagent / background job）を問わず一貫して行われるという公式ドキュメントの記載もない。Codex 側にも scratchpad 相当の概念は確認できていない。既存の `${CLAUDE_SKILL_DIR:-${CODEX_SKILL_DIR:-.}}`（`dogfood-to-issues` が使う）も実際には runtime が自動設定するのではなく、テストハーネスが明示 export しているだけである。

したがって、skill は agent が自分のセッション context を都度確認し、scratchpad path を認識できたらローカル変数（例: `TO_PR_SCRATCH_BASE`）へ明示代入してから使う。agent の Bash tool 呼出しは呼出しごとに独立した shell であり、ある呼出しで export した値は次の呼出しへ引き継がれない。同じ scratchpad path を複数の独立した temp artifact 生成箇所で使う skill は、各箇所（各コマンド／各 fenced block）でこの変数を都度再代入する手順を明記する。この判断は [ADR-0017](../docs/adr/0017-element-pointing-feedback-in-tdd.md) が採用した原則（ランタイム検出ロジックは導入しない — 実行中のエージェントは自身のランタイムの機能を把握している）と同じ考え方であり、session 種別ごとの injection 有無を前提にしない。scratchpad path を認識できない場合は空のままにし、`"${TO_PR_SCRATCH_BASE:-${TMPDIR:-/tmp}}"` のように `${TMPDIR:-/tmp}` を明示的な fallback として使う。fallback が発動した（scratchpad を認識できなかった）ことは完了報告や PR body などの出力に明記し、無言で `/tmp` へ落とさない（[ADR-0052](../docs/adr/0052-resolve-to-pr-temp-artifacts-via-session-scratchpad.md)）。

### 解析不能 Bash コマンドの確認（現在は不要）

[ADR-0055](../docs/adr/0055-disable-block-reads-outside-working-directories.md)（2026-09-09）により `permissions.blockReadsOutsideWorkingDirectories` は無効化された。静的解析できない Bash コマンド（heredoc 経由の interpreter、`$(...)` / command substitution、裸の `$VAR`、`sed`/`awk`/`python3 -c` 等）を理由に一律で human confirmation を要求していた仕組み（[2026-09-05 調査ノートの 2026-09-08 追記](../docs/research/claude-code-block-reads-2026-09-05.md#2026-09-08-追記issue-248)、issue #248）はもう働かない。heredoc・command substitution・裸の `$VAR` 展開を確認回避のために避ける必要はない。

ただし `permissions.deny` の `Read(...)` パターン（`~/.ssh/**`・`~/.aws/**` 等の credential 系を含む）は、`Read` tool と `cat`/`head`/`tail`/`grep` 等の認識済み read-only Bash コマンドには `blockReadsOutsideWorkingDirectories` と無関係に引き続き適用される（ADR-0055 で実機検証済み）。`python3 -c`・`node -e`・heredoc 経由の interpreter のようなプログラム経由の読み取りはこの `deny` をすり抜けるため、agent はこれを deny 回避の手段として使わない。`Read`/`Grep`/`Glob` tool が拒否したファイルは、拒否理由を尊重し別の経路で読み直さない。

**Orca native agent launch**: Orca は native worktree を agent の `cwd` にして Agent Picker から built-in agent を起動し、Settings の Agent Permissions で permission mode を所有する。自律 workflow は shipped Yolo、権限確認を残す場合は Manual と Orca Source Control による stage / commit / push を使う。Yolo の worktree isolation は disposable diff の review / recovery 境界であり、filesystem / network を強制する Technical Sandbox Boundary ではない。Orca native Codex の entry / activation に repository wrapper や Active Git Metadata Boundary を挟まない（[ADR-0046](../docs/adr/0046-separate-orca-native-worktree-entry.md)）。

**Codex Runtime Adapter（raw CLI only）**: `codex-worktree` は current linked worktree の physical root、absolute worktree Git dir、absolute Git common dir を inherited `GIT_*` なしで解決し、Codex の公式 `-C` / `-c` interface へ変換する。`.git` pointer → worktree Git dir → `commondir` → common dir と、common dir 直下の `worktrees/<entry>`、worktree Git dir の `gitdir` back-pointer → top-level `.git` を同じ physical ownership chain として検証する。metadata-file-relative target は受理し、不一致は Codex 未起動で fail closed にする。profile は ambient `CODEX_PERMISSION_PROFILE` や managed config の default に委ねず、top-level agent launch が受理する `-c 'default_permissions="dotfiles-secure"'` で固定する（`-P dotfiles-secure` は `codex sandbox` subcommand の直接検証で使う）。primary checkout、non-Git、unresolved metadata、working root / permission boundary を置換・拡張する caller argument、sandbox / hook trust を迂回する dangerous argument は fail closed とし、Git operation や workflow policy を持たない。`codex-orca` は既存 caller 向けに argv をそのまま転送する compatibility entry だが、Orca native session の entry / activation には使わない。managed `dotfiles-secure` config は secret-path deny と network policy を保持するが static repository Git write exception を持たず、Active Git Metadata Boundary は raw adapter が session ごとにだけ追加する（[ADR-0044](../docs/adr/0044-runtime-owned-worktree-entry-and-codex-activation.md)）。

raw adapter は Linux／WSL2 で `devshell-env trust` と worktree ごとの公開入力登録 `devshell-env admit --git-head FULL_SHA -- FILES` を要求する。登録した Git 履歴・ファイル・公開設定だけをコピーし、Nix／shellHook より前に専用 HOME・store・process・network の境界を作る。起動元の任意変数は復元せず、root dotenv の read 例外も追加しない。管理 permission と Active Git Metadata Boundary は読み取り専用の requirements に固定する。

終了時に commit・index・通常ファイルを元の worktree へ返す。実行中の host 並行編集、未登録入力との衝突、初期化／隔離の失敗では非0終了して結果を保持する。無保護な fallback は使わない。入力登録・導入条件・再起動・復旧は [利用方法](shell-environment.md#raw-codex-のプロジェクト開発環境) を読む。人間の明示 `with-env` は従来の dotenv 注入を保持し、raw の `with-env --prepared` は秘密なしの環境だけを再利用する。管理 Context7・Serena は明示選択して同じ隔離内で起動し、GitHub は人間が確認した公開 repo・topic・CI/外部連携の方針を登録して限定 gateway へ接続する。必要な認証は host に保持する。[対応 CLI と確認条件](shell-environment.md#隔離内の管理-mcp-と-github) を参照する。Orca／Herdr の native 起動、既存セッションには遡及適用しない。

`sync-codex-managed-config` は native Codex home と explicit `CODEX_HOME` の managed `dotfiles-secure` から、旧 absolute `…/.git = "write"` と `:workspace_roots` の `".git" = "write"` を除去する。Codex self-expanded concrete map は absolute root と managed workspace の `"."` mode が一致する場合だけ除去し、managed profile の独立 nested deny、`:minimal` など他の scalar baseline、user-defined profile の path rule は保持する。

移植元スキルの `eval.yaml` / `tasks/`（skill 評価ハーネス）は持ち込まない。

## playwright-cli

単発のブラウザ操作・スクレイピング・フォーム操作・スクリーンショットは `playwright-cli` skill を優先する。nix devshell のローカル package（`private_dot_config/nix-devshell/packages/playwright-cli.nix`、vendored `@playwright/cli`）を `modules/ai.nix` の shellHook が `~/.agents/skills/playwright-cli` へ symlink 配備する。agent-browser は削除した。`to-pr` の browser-observable 検証もこの skill を使う。

WSL2 の通常の `playwright-cli open [URL]` は Windows 側の worktree 別 browser identity を headless で使用する。物理 worktree root から profile・CDP endpoint・Dashboard port・lease を割り当て、同じ worktree の状態を保持する。別 worktree と Dogfood は独立して利用できる。同じ identity の headless / headed 競合は既存 consumer を保持して拒否する。WSL browser へフォールバックしない。

`show` / `show --annotate` は人間の明示開始による headed モードを要求し、その worktree の Dashboard を使う。annotation は lease 所有 session だけに結び付く。背景処理は自動 headed 起動・前面化・OS 入力をしない。終了は session 指定の `close` と対象 Dashboard の `show --kill` を使い、`close-all` / `kill-all` は拒否する。明示 remote CDP attach と WSL browser-free の override 制約は維持する。

profile を初期化する場合は、その worktree で `playwright-cli reset-profile --confirm-identity <identity>` を明示実行する。対象の session・Dashboard・所有権が終了し、Windows 側でも停止を確認できた場合だけ、その worktree profile を削除する。共有添付 profile は対象にできない。

PR 添付は `browser-attachments upload --repo OWNER/REPO --pr NUMBER --image PATH --placeholder TEXT --request-id ID` を使う。旧専用 profile の手動 GitHub 認証を添付専用 identity が引き継ぎ、検証 profile へコピーしない。異なる PR は並列、同じ PR の本文更新は直列にし、更新直前の本文を取得する。asset を保存済みなら同じ request ID で本文更新を再開できる。送信結果不明なら二重送信せず調査する。人間の初回認証・期限切れ対応は `to-pr` 外で `browser-attachments auth` → 手動ログイン → `browser-attachments close`。自動添付は headless のみ。

CLI session の保存先・Dashboard の session 一覧・制御 socket も物理 worktree root ごとに分離する。同じ session 名を別 worktree で使っても相互操作しない。切替前に旧 package で既存 CLI / Dashboard を終了する。Dogfood の自動 CDP port は所有権の予約と同じ lock 内で割り当て、保持中の予約を避ける。明示 port の競合は拒否する。Windows の状態確認が重なる場合、共有の登録 lock は最大30秒待機し、期限超過は状態を保持して失敗する。

### Managed Chrome 所有権の確認と復旧

WSL2 の Playwright と Dogfood は、Nix browser package に同梱する `managed-chrome-owner` を共有する。`MANAGED_CHROME_OWNER` は同梱 CLI の絶対パスを指す。所有権は共通の `BROWSER_OWNERSHIP_DIR`、未指定なら `$XDG_RUNTIME_DIR/browser-ownership`、さらに未設定なら `${TMPDIR:-/tmp}/browser-ownership` に置く。Dogfood 固有のディレクトリ指定がこの場所と異なる場合は拒否する。

`managed-chrome-owner status` で identity ごとの role・所有者・workspace・起動状態を確認する。`locate --role playwright --workspace <physical-root>` の先頭フィールドが対象 identity。終了に失敗した場合は記録された consumer を終了し、`managed-chrome-owner --identity <identity> recover` を実行する。Windows 側の照会が成功し、Chrome が停止済みで、未確定の起動処理もない場合だけ解放する。Chrome の終了要求や profile 削除は行わない。`starting` のまま起動監視 process が異常終了した場合は、後から Chrome を起動し得る処理の完了を証明できないため、記録を保持して調査を要する。

起動コマンドが戻った後の `settled` でも、呼出元が生存して CDP の準備を待っている間は `recover` による回収を拒否する。起動を一度も試みていない `reserved` の予約は、token が一致する caller の通常 `release` で取り消せる。この取消は起動処理と同じ lock 内で token を無効化するため、初期確認で Chrome 未インストールや port/profile 競合を検出した場合も、問題を解消してそのまま再試行できる。

移行は旧版で managed CLI session・Dashboard・Dogfood run を終了してから、Nix package とローカル Dogfood skill を対応する版へ揃え、devShell を再読込みして MANAGED_CHROME_OWNER / DOGFOOD_WINDOWS_SCRIPT 等の同梱ツール参照を更新する。旧 `owner` や `acquire.lock` が残っている場合は起動を拒否するため、切替前に旧版の終了処理と Windows 側の状態を調査する。記録の削除による起動制限の迂回は行わない。設計判断は [ADR-0047](../docs/adr/0047-centralize-managed-chrome-ownership.md) を参照する。

## Claude Code plugin の二層管理

プラグインは「配置（物流）」と「runtime 有効化」を別レイヤーで管理する:

- `apm.yml` — 外部 plugin / skill の取得（hook を持たない外部 skill-only は apm 経由）
- **chezmoi ローカル skill** — apm 外の user-scoped private skill（上記「chezmoi 配布のローカル skill」）。マルチランタイムへ materialize する自作 skill はこの経路
- `settings.json` `enabledPlugins` — runtime 有効化フラグ。hook を含む plugin（`security-guidance` / LSP 群 / `codex`）はここで有効化する
- `settings.json` `extraKnownMarketplaces` — 外部 marketplace 宣言（現状 `openai-codex` のみ）

`~/.claude/plugins/` 配下の `known_marketplaces.json` / `installed_plugins.json` / `cache/` は Claude Code の runtime state なので git/chezmoi では管理しない。

関連: [ai-runtimes](ai-runtimes.md) / [conventions](../docs/conventions.md)
