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

**mattpocock 設計→実装ワークフロー** (`mattpocock/skills/skills/engineering/`)。上流 v1.1.0 の promoted セット（User-invoked / Model-invoked の公式分類）に整合させて導入している。

_User-invoked_（明示起動のみ、orchestration 層。メインフロー1本 + on-ramp 2つで構成する — 詳細は [ADR-0014](../docs/adr/0014-triage-not-after-to-issues.md)、上流 `ask-matt` の main-flow/on-ramp 構造に整合）:

- メインフロー: `to-worktree`（一度だけ）→ `grill-with-docs` → `to-spec` → `to-tickets` → `implement` → `to-pr`。要件確定済みの小さな作業は `grill-with-docs`/`to-spec`/`to-tickets` を省略して `implement` から直接入ってよい。`to-tickets` までを **Planner**、`implement`（内部で `tdd`/`code-review` を使う）を **Builder-Evaluator** と呼ぶ（[CONTEXT.md](../CONTEXT.md)）。Builder-Evaluator は `to-tickets` が生成した ticket をまたいで、同一 worktree/branch 内であれば止まらずループしてよい（issue #28・#29 が単一 worktree・単一 PR #30 として実践した前例を明文化したもの。単一セッション単位ではない — smart zone に達したら `/handoff` で別セッションへ）: `tdd` の green slice commit・`code-review` 後の修正 commit は確認なしで行う（根拠は [ADR-0019](../docs/adr/0019-builder-evaluator-cross-issue-autonomy.md) / [ADR-0022](../docs/adr/0022-align-mattpocock-v1-1-workflow.md)）。`code-review` は `git diff <fixed-point>...HEAD` の三点差分——commit 済みの履歴のみを見る——を review 対象にし、empty diff は明示的に fail するため、commit が無いと `code-review` 自体が動かない。対象 worktree/branch の全 ticket が完了したら `to-pr` を一度だけ実行する（AFK 運用時は自律呼出し可、通常運用は完了報告のうえユーザーの `/to-pr` 呼出しを待つ）。`/to-pr` 呼出しまたは AFK/自律完了の明示許可は、topic branch push・PR create/edit・証跡添付・整合済み `Fixes` への事前承認とする。commit は運用者＝エージェント自身の責務（詳細は [ADR-0015](../docs/adr/0015-add-tdd-commit-confirmation.md) / [ADR-0019](../docs/adr/0019-builder-evaluator-cross-issue-autonomy.md) / [ADR-0022](../docs/adr/0022-align-mattpocock-v1-1-workflow.md)）
- on-ramp（raw issue: `to-tickets` の産出物には使わない）: `triage` → ready-for-agent 化 → `implement` へ合流
- on-ramp（ハードなバグ）: `diagnosing-bugs` → `code-review` → `to-pr`。raw な報告ならまず `triage` を通す

外部 skill は APM 配布物を fork せず、repo の指示層で必要な差分だけを **ローカル skill 上書き**として定義する（[ADR-0023](../docs/adr/0023-resolve-external-skill-contracts-locally.md)）。現行の上書きは次の3点:

- `triage` は推薦根拠を得る read-only 検証を推薦前に実行してよい。推薦・適用内容の判断点は維持するが、内容確定後の非破壊な GitHub 定型書込みは二重確認しない。close/reopen/delete は引き続き確認する。
- Builder-Evaluator 内の `code-review` は branch の既知の base（通常 `origin/main`）を fixed point として自動採用してよい。standalone で fixed point が不明な場合だけ質問する。
- `gh-address-comments` は GitHub plugin の flat な comment read と `gh api graphql` を併用せず、thread-aware な取得・返信・resolve を専用 CLI `gh-review-thread` に統一する。review 対応依頼は選択 thread 群の Review Round（修正・検証・`fix: address PR review feedback` commit・`git-push-topic`・日本語返信・resolve）を承認する。コード修正は commit が現在の PR 履歴に含まれた後だけ短縮 SHA・修正要約・検証結果を返信して resolve する。説明のみは `--explanation-only` を明示し、根拠を返信して空 commit を作らない。同一本文の自分の返信は再投稿せず未完了の resolve から再開し、thread 単位の失敗は open のまま理由を記録して残りを続行する（[ADR-0032](../docs/adr/0032-automate-review-round.md)）。

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

実装フェーズの user-invoked entrypoint は `implement`。`tdd` / `code-review` / `resolving-merge-conflicts` / `diagnosing-bugs` などは model-invoked discipline として必要時に発火する。`grilling`（productivity/Model-invoked、`grill-with-docs`/`grill-me` の共通ループ）は [ADR-0009](../docs/adr/0009-add-grilling-skill.md) で導入済み。`grill-me`（productivity/User-invoked、no-codebase 向け）は [ADR-0002](../docs/adr/0002-mattpocock-over-superpowers.md) が軽量化のため意図的に除去したまま。`teach` は [ADR-0010](../docs/adr/0010-productivity-skill-audit.md) により「設計→実装ワークフロー」スコープ外として非導入。

このワークフローは per-repo で完結する。ラベル provisioning は dotfiles では持たず、各 repo で `gh label create` または skill のランタイム挙動に任せる。domain doc は mattpocock ネイティブの `CONTEXT.md`/`docs/adr` を使い、この `runtime/` バンドルとは混ぜない（`runtime/` は home-wide ambient 知識専用）。

**apm のマルチランタイム配布**: `apm.yml` の `targets` は `claude` / `codex`（apm の `install` は `antigravity` target を非対応）。apm は全 skill を APM-native の共有ハブ `~/.agents/skills/` に必ず materialize し（target とは独立）、Claude 向けには `~/.claude/skills/` にも配備する。**Codex と Antigravity はどちらも `~/.agents/skills/` を global skills location として直接読む**（Codex は `codex debug prompt-input` で skill 可視性を実機確認済み）ため、apm skill は追加配線なしで 3 ランタイムに可視。`~/.codex/skills/` は Codex の native location だが apm 0.23 は配備せず、過去に配備された real dir が残っていても discovery は `~/.agents/skills/` 側が担う。

**apm lock は runtime layout を再現した隔離ディレクトリで再生成する**: apm の target 解決はカレントディレクトリ基準なので、`apm.yml` を一時ディレクトリへコピーして `apm install` し、生成された `apm.lock.yaml` を repo へ戻す。install が新規配備時に deployed_files / deployed_file_hashes を lock へ追記するため、`apm lock` だけの lock を採用すると materialization 情報が欠落する。更新後は同じ隔離環境で `apm install --frozen` を検証し、`~/.agents/skills` / `~/.claude/skills` は直接変更しない。lock は apm native 形式（single-quote）のまま保存し oxfmt で再整形しない（`lefthook.yml` で除外済み。再整形すると apm が runtime で書き戻して chezmoi と永続 drift する）。

2026-07-21 の上流更新では mattpocock workflow を commit `9603c1c` に統一し、各 skill の Codex metadata（`agents/openai.yaml`）と最新の grilling / ticket / wayfinding guidance を取り込んだ。repo 固有の main-flow と上書き契約は引き続き `AGENTS.md` / ADR を優先する。Impeccable は commit `4d849eb` に更新し、Design Hook の重複 finding 修正と検出精度改善を quiet hook テストで検証した。未固定の APM 依存も同時に再解決し、Remotion は上流の canonical path `remotion-best-practices` へ追従した。lock は APM 0.26.0 の隔離 runtime layout で再生成し、同じ環境の `apm install --frozen` が書き戻しなしになることを確認した。

2026-07-31 の更新では、Impeccable HEAD `32930818a109fafa87199babe92fa8e530cff5d3`（4.0.4）を候補に Design Hook 互換性ゲートを実行し、quiet / immediate tier / Stop deep pass / dedupe / edit threshold / sensitive・generated path filter / Stop re-entry の runtime 契約を 7/7 テストで維持した。未配備・内部失敗時の fail-soft は managed hook の fail-open テストで別途確認できたため、新しい検証済み Skill Pin として採用した。既知の both-tiers Stop 交互報告は未修正で、characterization test を維持する。floating dependency の再解決で payload が変わったのは Impeccable、Remotion（4.0.503。相対リンク、multi-scene、timing / transition 等）、Supabase（schema / migration / RLS / security を含む trigger description）の3件。Shadcn、Orca 3 skill、find-skills は repository revision だけが進み selected skill subtree の content hash は不変、Matt Pocock の選択済み skill 群は `ed37663cc5fbef691ddfecd080dff42f7e7e350d` を維持した。APM 0.26.0 の隔離 HOME で lock を生成し、同じ runtime layout の frozen install で再現性を確認した。

2026-08-06 の更新では、APM 0.28.0 の隔離 runtime layout で lock を再生成した。Impeccable HEAD `a075d89bdbe60b2b00220cb0527fb5091e84215e`（4.0.4）は同じ Design Hook 互換性ゲート 7/7 と managed hook の fail-open 契約を維持したため、新しい検証済み Skill Pin として採用した。既知の both-tiers Stop 交互報告は未修正で、characterization test を維持する。floating dependency の selected payload が変わったのは Impeccable、Modern Web Guidance（`684ab9d7`）、Remotion（`7809e793`）の3件。Shadcn、Orca 3 skill、find-skills は repository revision のみ進み selected subtree の content hash は不変、Matt Pocock の選択済み skill 群は `ed37663cc5fbef691ddfecd080dff42f7e7e350d` を維持した。同じ環境の `apm install --frozen` は lock を書き戻さず、ライブ skill directory と `chezmoi apply` には触れていない。

2026-08-15 の更新では、Impeccable `5a149f3fdb1b5793f10567233b1dcab98fc305fd`（4.1.1）を候補に、session初回の full policy footerと以後のshort footer、`ignore-file` / `ignore-rule`の承認境界、理由付き`ignore-value`の`detector.ignoreValues`限定保存を新しい契約へ加えた Design Hook gate 9/9、managed hook fail-openを通過したため採用した。確信のある false positive / 許容済み例外への `ignore-value` はagentが自己適用して根拠を開示できるが、`ignore-file` / `ignore-rule` はユーザーの明示承認を要する。既知の both-tiers Stop交互報告は未修正でcharacterization testを維持する。floating dependencyのselected payloadが変わったのはImpeccable、Remotion（`2a204c9b`）、Vercel React View Transitions（`b8caa260`）。Matt Pocockの20 skillはaliasなしrenameとworkflow差分のため`ed37663cc5fbef691ddfecd080dff42f7e7e350d`に据え置いた。APM 0.28.0の隔離runtime layoutで全37 dependencyを再生成し、`apm install --frozen --https`が書き戻しなしになることを確認した。

2026-08-18 の更新では、Impeccable `5c5553b1d7f9e89bb833f9179cea681742a17720`を候補に、APM 0.28.0の隔離runtimeで Design Hook gate 9/9とmanaged hook fail-open 1/1を再検証した。hook / footer / adminのcore blobは前pinと同一で、static HTML selectorのcompile cacheなどselected payloadの変更も既存契約を維持する。Remotionは`9f0faa50`（version markerのみ）、Orcaはlock生成時の`a1cd7eaa`までを候補lockとして評価した。既知のboth-tiers Stop交互報告と、理由付き`ignore-value`だけを自己適用できる境界は変更しない。Matt Pocockの20 skillは`writing-for-agents`へのrename、frontier interview、HTML prototype、handoff / compact / clearのphase boundaryをローカル契約へ調停できていないため`ed37663cc5fbef691ddfecd080dff42f7e7e350d`に据え置く。APM binaryも0.28.0を維持し、同じ隔離runtimeの`apm install --frozen --https`がlockを書き戻さないことを確認した。Claude interactive gateが未完了なので、配備sourceはacceptedなImpeccable `5a149f3fdb1b5793f10567233b1dcab98fc305fd`と対応lockを維持し、候補revisionはADRと調査ノートだけに置く。

2026-08-20 の更新では、`llm-agents.nix` を snapshot `20766586959e0dcc2f9e7cff6d49b0c710de30d6` へ進め、Claude Code 2.1.237 / Codex 0.148.0 / Antigravity CLI 1.1.16 を採用した。Copilot CLI 1.0.80、RTK 0.45.0、APM 0.28.0 は変わらない。APM は selected payload が変わった Modern Web Guidance `460e5536`、Remotion `21320596`、Orca `orca-cli` `5ca747da`だけを lock 更新し、revision-only の PDF、Shadcn、find-skills、Orca `computer-use` / `orchestration`、Impeccable、Matt Pocock は現行 pin / payload を維持した。候補 lock は隔離 runtime の `apm install --frozen --https` と `apm audit --ci` を通過し、Design Hook gate 9/9 と managed fail-open 1/1、3 system の Nix check / deep evaluation、Linux host smoke、Claude/Codex smoke も完了した。managed session の home filesystem が read-only のため `chezmoi apply` と live `apm install --frozen` は完遂できず、実環境への反映は後段に残す。

**Impeccable**: UI の設計・評価・改善を担う user-invoked / model-invoked skill。検証済み commit に pin し、共有ハブ経由で Codex / Antigravity、Claude skill dir 経由で Claude Code へ配布する。新規 UI の create / shape flow は `PRODUCT.md` / `DESIGN.md` の context setup へ誘導し、既存 UI の scoped 改善は context 文書がなくてもブロックしない。直接の前身である `frontend-design` は責務の重複を避けるため撤去した。

**Design Hook**: user-global に **2 イベント**を配線する。per-edit は Claude Code の `Edit|Write|MultiEdit` / Codex の `Edit|Write|apply_patch` に対する `PostToolUse`（timeout 5s）、deep pass はセッション終端の `Stop`（`matcher` なし・timeout 30s。上流 manifest に合わせた値）。Claude は `~/.claude/skills/impeccable/`、Codex は共有ハブ `~/.agents/skills/impeccable/` の固定 runtime を、存在確認後に `IMPECCABLE_HOOK_QUIET=1` で呼ぶ。runtime 側は stdin の `hook_event_name` で振り分ける。

検出ルールは二層で、**両方を配線して初めて全ルールが届く**（[ADR-0029](../docs/adr/0029-impeccable-pin-advance-with-stop-hook.md)）。per-edit は immediate tier だけ — 壊れた出力・contrast・design-system drift など、その場で直すべき機械的な指摘を編集箇所へ返す。コピーの調子・パレットや字組みの趣味・レイアウトの律動は `Stop` へ先送りされ、セッション中に触れた全 UI ファイルを full rule set で再走査して fresh finding をまとめて返す（per-edit が既に出した分は dedupe。何も残っていなければ無言）。`Stop` は `stop_hook_active` を見て再入時は即座に抜けるため、ターンが延命ループに入ることはない。

**既知の上流不具合（採用pin `5a149f3f` 時点、実測）**: 1 つのファイルが immediate と deferred の両方の finding を持つ間、`Stop` はターン終端ごとに 2 つを**交互に**報告し続ける。`rememberFindings()` が記憶済みキーを置換する一方で `Stop` は fresh 分しか渡さないため、deferred を報告した時点で per-edit が覚えていた immediate 側が追い出され、次の `Stop` で再び新規に見える。immediate 側を直せば層が 1 つになり収束する。`tests/design-hook.bats` はこの**実挙動のほう**を固定してあるので、上流が直すとそのテストが落ちて気づける。候補`5c5553b1`でも同じ挙動を確認済みである。

finding footerはsession内の初回だけfull policyを出し、以後はshort footerにする。full policyが許容する自己修復の境界はfinding単位の`ignore-value`までで、agentは確信のあるfalse positiveまたはユーザーが許容済みの例外に限って使い、理由をユーザーへ示す。file / rule全体を抑制する`ignore-file` / `ignore-rule`はユーザーの明示承認が必要である。

いずれの層も、clean UI、非 UI、機密・生成物、重複 finding、同一ファイルの編集閾値超過は無言にする。runtime の未配備・内部エラー・非0終了はすべて成功扱いにする advisory feedback であり、編集を拒否する gate ではない。実装中に人間が画面上の対象を選ぶ要素指差しフィードバック、実装後に AC を検証する Verification Matrix とも役割・主体・タイミングが異なる。Antigravity / Cursor / GitHub Copilot には自動 hook を配線しない。

**UI specialist skill（保持）**: `web-design-guidelines` は Web 実装規則、`modern-web-guidance` は最新 Web API、React 系 skill は React の構成・性能・View Transition、`shadcn` は shadcn/ui、`remotion-best-practices` は動画 UI を担当する。Impeccable はこれらを置き換えず、UI 全体の設計品質を扱う。

**その他 apm skill（保持）**: find-skills, skill-creator, pdf, supabase-postgres-best-practices, empirical-prompt-tuning, effect-ts。

## chezmoi 配布のローカル skill

apm 外の user-scoped private skill は chezmoi で配布する。ソースは `local-skills/<name>/`（`.chezmoiignore` で `~/` へ直接 deploy せず SoT のみ）、`run_onchange_after_deploy-local-skills.sh.tmpl` が各ランタイムの skill dir へ `rsync` で materialize する:

- `~/.agents/skills/<name>/` — 共有ハブ。Antigravity / Codex はここを直接読む
- `~/.claude/skills/<name>/` — Claude

Codex native location（`${CODEX_HOME:-~/.codex}/skills`）へは配備しない。Codex は `~/.agents/skills/` で同じ skill を既に発見でき、native location にも置くと `to-pr` などのローカル skill が二重表示されるため。

deploy は `run_onchange_after_apm-install`（alphabetical 先行）の後に走り apm 配備を上書きしない。`run_onchange_before_remove-orphan-claude-skills.sh.tmpl` は `~/.claude/skills/` の real dir を wipe するため、ローカル skill 名を同スクリプトの `preserve_local_skills` allowlist に登録して除外する（両者の skill 名リストは一致させること）。

構造は **flat な `local-skills/<name>/`**（SKILL.md + references/ + 必要なら scripts/ 同梱で完結）。hooks / agents / marketplace 登録を要するメガパッケージ型の 3層 plugin 構造（`plugins/<ns>/{claude,codex,common}` 型）は不採用: あの構造の必然性は hooks + agents + bin + marketplace 登録というメガパッケージ要件にあり、skill-only なら不要。将来分離したくなったら `local-skills/` ごと新 repo に切り出して apm pin 化すればよい。

現行のローカル skill:

- `to-worktree` — ワークフローチェーンの入口。機能作業を始める前に隔離 worktree を用意する（Claude Code は `EnterWorktree` ツール優先、他ランタイムは `git worktree add .worktrees/<topic>`）。`.worktrees/` 配下に作るため放置分は `worktree-gc` が回収する
- `ui-grill-with-docs` — UI/UX 比重が高い Planner 向けの `grill-with-docs` 派生。レイアウト・コンポーネント配置・画面遷移が争点になる質問だけ `tmp/wireframe-<screen>.html` の静的 HTML/CSS モックアップで補助し、通常の質問はチャットの一問一答、確定事項は `CONTEXT.md` / ADR に残す
- `to-pr` — 実装完了後（user-invoked チェーンの最後尾）に、issue/ticket/会話から抽出した contract（目的/AC/非目標/検証方法/関連ファイル・入口/判断済みtradeoff）を PR body へ埋め込み、全 AC（UI/CLI/API/infra）を対象にした単一の verification matrix で検証記録を残す。呼出し自体を topic branch push・PR create/edit・証跡添付・整合済み `Fixes` への事前承認とし、外部操作を理由に二重確認しない。push は実際の remote default branch を拒否し、内部で`git push -u origin HEAD`だけを実行する`git-push-topic`を使う。force-pushは方針として禁止し、直接の生の`git push`と代表的なwrapper/global option経由はruntime ruleで遮断する。default branchへの直接pushだけは明示承認後に`git-push-reviewed`を使う。UI は `playwright-cli` で検証し、代表画像と `playwright-report.md` を一時ディレクトリへ生成する。PR 本文の `Playwright Evidence` に操作・観測結果・URL・console/network エラー要約を載せ、認証済みブラウザが利用できる場合は画像を GitHub の PR 添付としてアップロードし、匿名化 URL を埋め込む。WSL2 では Managed Playwright Chrome の専用 profile が既に GitHub 認証済みの場合だけこの添付へ利用する。認証は PR 証跡添付以外の操作許可を拡張せず、自動ログイン、通常 Chrome profile の流用、認証情報 import は行わない。ブラウザ未認証・操作不可・アップロード失敗時はログインや画像 commit に切り替えず、`手動添付待ち` と証跡の絶対パス・ファイル一覧を引き継ぐ。非UIは既存証拠（`implement` / `tdd` のテスト・commit・lefthook実行）を引用するのみで新規実行はしない。code-review 実施状況も記録する（未実施でも PR 作成はブロックしない）。最終 PR では GitHub native subissues を Ticket Hierarchy の正本とし、ticket 本文の `Parent` と照合する。直接の全 child が close 済みまたは Contract / Verification Matrix で covered なら、open な covered child と直接の親へ `Fixes` を付け、`Parent Reconciliation` に判定・理由・close 対象を記録する。hierarchy または coverage を証明できない場合は親の `Fixes` を省略しても PR 作成は継続する。reconciliation は直接の親1階層に限り、state label cleanup や post-merge automation は行わない。重量級の evidence schema / verdict gate / hero 選定は持ち込まない。
- `dogfood-to-issues` — 同梱の Playwright dogfood runner で web アプリ / Chrome MV3 拡張を隔離 worktree で dogfood し、承認された finding だけを GitHub Issue 化。`--annotate` 指定時は自動検査後、runner 所有 Chromium に Playwright CLI で CDP attach し、矩形注釈と全体 feedback を同じ候補・承認フローへ加える（`--resume` とは併用不可）。issue 作成で完了し、実装へは続かない（triage → model-invoked フローへ）。`scripts/runtime-preflight.sh` 同梱
- `harness-feedback` — Codex / Claude の transcript JSONL を分析し、skill/agent 指示と実際の実行の乖離パターンを検出して小さな指示修正を提案
- `marp` — markdown を Marp CLI で PDF スライド化（marp-cli は nix devshell 配備済み）
- `md-agents-review` — AGENTS.md / Codex rules の対話式レビュー（trim / progressive disclosure）
- `md-claude-review` — プロジェクト CLAUDE.md の対話式レビュー（humanlayer ベストプラクティス基準）
- `rop` — Railway Oriented Programming の two-track パターン強制（Elixir / Gleam / Rust / Effect-TS の言語別 references 同梱）
- `worktree-gc` — 緊急時（fd/inotify 枯渇）の repo-local worktree 手動 GC。`scripts/worktree-gc.sh` 同梱。SessionStart 自動 GC hook は持ち込まない（手動起動のみ）

移植元スキルの `eval.yaml` / `tasks/`（skill 評価ハーネス）は持ち込まない。

## playwright-cli

単発のブラウザ操作・スクレイピング・フォーム操作・スクリーンショットは `playwright-cli` skill を優先する。nix devshell のローカル package（`private_dot_config/nix-devshell/packages/playwright-cli.nix`、vendored `@playwright/cli`）を `modules/ai.nix` の shellHook が `~/.agents/skills/playwright-cli` へ symlink 配備する。agent-browser は削除した。`to-pr` の browser-observable 検証もこの skill を使う。

WSL2 の通常の `playwright-cli open [URL]` は Managed Playwright Chrome の headless モードを既定経路とする。Windows Google Chrome、`%LOCALAPPDATA%\aiakos\playwright-cli\chrome-profile` の専用 profile、`127.0.0.1:9222` の CDP endpoint を一体として管理し、mirrored networking が利用できなければ WSL browser へフォールバックせず修復手順付きで失敗する。`open --headed` と `PLAYWRIGHT_MCP_HEADLESS=false|0` は同じ browser identity の headed モード、`PLAYWRIGHT_MCP_HEADLESS=true|1` は headless モードを選び、`--headed` を優先する。両モードは同時起動せず、不一致なら既存 consumer を変更せず明示的な cleanup を要求する。Managed Dogfood Chrome と共有する browser-ownership record に別 role がある場合も起動を拒否する。managed CLI session は1つだけが排他的に所有し、`open` は既存 tab を遷移せず新規 tab を作る。

`playwright-cli show` と `show --annotate` は headed モードを要求し、WSL2 の `127.0.0.1:9323` に Dashboard をバックグラウンド起動して `http://localhost:9323/` を開く。headless session が動作中なら、`close`、`open --headed`、`show` の順で開き直す。Dashboard は `show --kill` まで存続する。WSL2 では `--config` / `--browser` / `--profile` / `--persistent` / `--device` / `--mobile`、project config、browser/context shaping 環境変数を local browser escape として拒否し、明示 `playwright-cli attach --cdp=<remote-endpoint>` だけを remote CDP の互換経路とする。Dogfood の annotation は attach 後に外部 owner を明示して Dashboard コマンドを upstream へ渡す。詳細な境界と lifecycle は [ADR-0038](../docs/adr/0038-keep-wsl2-browser-free.md) と [ADR-0031](../docs/adr/0031-managed-playwright-chrome-on-wsl2.md) を正本とする。

## Claude Code plugin の二層管理

プラグインは「配置（物流）」と「runtime 有効化」を別レイヤーで管理する:

- `apm.yml` — 外部 plugin / skill の取得（hook を持たない外部 skill-only は apm 経由）
- **chezmoi ローカル skill** — apm 外の user-scoped private skill（上記「chezmoi 配布のローカル skill」）。マルチランタイムへ materialize する自作 skill はこの経路
- `settings.json` `enabledPlugins` — runtime 有効化フラグ。hook を含む plugin（`security-guidance` / LSP 群 / `codex`）はここで有効化する
- `settings.json` `extraKnownMarketplaces` — 外部 marketplace 宣言（現状 `openai-codex` のみ）

`~/.claude/plugins/` 配下の `known_marketplaces.json` / `installed_plugins.json` / `cache/` は Claude Code の runtime state なので git/chezmoi では管理しない。

関連: [ai-runtimes](ai-runtimes.md) / [conventions](../docs/conventions.md)
