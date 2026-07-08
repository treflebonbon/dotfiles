---
type: research
title: Human-out-of-the-loop coding agents — primary-source survey
description: 自律的（human out of the loop）なコーディングエージェント運用について、Anthropic 公式ガイダンス・業界の loop engineering パターン・upstream mattpocock/skills の3方向を一次情報で調べたもの。ワークフローの人間確認チェックポイント再設計に向けた grill-with-docs のインプット。
tags: [research, autonomy, claude-code, mattpocock, ralph, workflow]
timestamp: 2026-07-08
---

# Human-out-of-the-loop coding agents — primary-source survey

> **新しい規約についての注記**: この repo にはこれまで `docs/research/` ディレクトリが存在しなかった（`docs/adr/` と `docs/agents/` のみ）。本ファイルが `docs/research/` の最初のエントリであり、`research` skill の産出物（一次情報に基づく調査メモ）の置き場としてこのディレクトリを新設する。ADR ではない——意思決定記録ではなく、意思決定の前段の調査であるため。

## 調査の狙いと出典の信頼度

現行の設計→実装ワークフロー（`grill-with-docs` → `to-prd` → `to-issues` → `tdd` → `code-review` → `to-pr`、on-ramp は `triage` / `diagnosing-bugs`）を、**人間確認チェックポイントを最小化した自律運用（human out of the loop）** に寄せられるか検討するための一次情報を集めた。既存の [ADR-0015](../adr/0015-add-tdd-commit-confirmation.md) は逆方向——「各 green slice ごとに commit してよいか人間に確認する」という人間確認ステップを doc 層で**追加**する——を採ったが、その根拠を含めて一次情報で再接地する。

**出典の検証プロセス（透明性のため明記）**:

- **Q2（Ralph）・Q3（mattpocock）は本エージェントが直接検証した**。`gh` CLI で upstream repo のファイル・issue を取得し、Ralph は著者本人の blog / repo を WebFetch した。
- **Q1（Anthropic 公式）は `claude-code-guide` サブエージェントが公式ドメイン（`code.claude.com/docs`、`anthropic.com/engineering`）を読んで報告したものを転記した**。各 fact に URL を付す。本エージェントが各引用を逐語再確認したわけではない点に留意——ただしサブエージェントは URL を明示しており、内容は既知の Claude Code 機能と整合的である。逐語確認が必要な引用は付した URL を参照のこと。

すべて **2026-07-08 時点**。upstream の動的状態（issue の open/closed、ファイル内容）は変わり続けるため、Q3 は commit SHA を pin した（ADR-0015 の規約に従う）。

---

## Q1. Anthropic 公式の自律／無人運用ガイダンス

Anthropic は「無人でエージェントを回す」こと自体は**サポートしているが、必ず隔離環境で行うこと**を一貫して条件付けている。関連する機能は以下。

### 1a. Headless / print モード（`claude -p`）

`-p`（`--print`）を任意の `claude` コマンドに付けると非対話（スクリプト）実行になる [1]。`--continue`（会話継続）・`--allowedTools`（ツール自動承認）・`--output-format`（`text` / `json` / `stream-json`）等の CLI オプションが併用可能 [1]。`--bare` は hooks / skills / plugins / MCP / auto memory の読み込みをスキップし、CI・スクリプトの再現性のためのモード [1]。**非対話モードでは、承認を求める相手（人間）がいないため、`auto` モードで繰り返しブロックされるとセッションが abort する** [8]——つまり `-p` 単独では「人間確認の代わりに黙って止まる」挙動になりうる。

### 1b. Permission モード [2][3]

| モード              | 挙動                                                                   | 想定用途                        |
| ------------------- | ---------------------------------------------------------------------- | ------------------------------- |
| `default`           | すべての編集・コマンドで確認プロンプト                                 | センシティブな作業              |
| `acceptEdits`       | ファイル編集＋一般的な fs コマンドを自動承認                           | コードのイテレーション          |
| `plan`              | 読み取り専用で変更を提案                                               | 編集前の探索                    |
| `auto`              | バックグラウンドの安全分類器付きで自動承認                             | 長時間タスク・プロンプト削減    |
| `dontAsk`           | 事前承認済み以外は自動拒否                                             | ロックダウンした CI・スクリプト |
| `bypassPermissions` | 全プロンプトをスキップ（`ask` ルールと `rm -rf /`・`rm -rf ~` は除く） | **隔離コンテナ / VM のみ**      |

`--dangerously-skip-permissions` は `--permission-mode bypassPermissions` と等価 [2]。**Anthropic 公式の警告（逐語）**: 「Only use this mode in isolated environments like containers, VMs, or dev containers without internet access, where Claude Code cannot damage your host system.」[2] さらに Linux / macOS では root・`sudo` 実行時にこのモードでの起動を拒否する [7]。`.git` / `.claude` / `.devcontainer` / shell 設定 / git 設定 / パッケージマネージャ設定などの保護パスは、`bypassPermissions` 以外のどのモードでも自動承認されない [2]。

### 1c. Hooks によるゲーティング（機械的強制の可否）[4]

ADR-0015 は「commit を機械的に強制するゲートは導入しない」と決めたが、公式には **hook で機械的ゲートを作ることは可能**であることを一次情報で確認した。

- **PreToolUse hook はツール呼び出しをブロックできる**。方法は2つ: (1) exit code 2（stderr がブロック理由として Claude に渡る）、(2) JSON で `{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"..."}}`（値は `allow`/`deny`/`ask`/`defer`）[4]。
- **PostToolUse hook はブロックできない**（ツールは既に実行済み。stderr を Claude に見せるのみ）[4]。
- **Stop hook はエージェントの停止をブロックできる**（逐語: 「Prevents Claude from stopping, continues the conversation」）。`{"decision":"block","reason":"..."}` で継続を強制する [4]。← **これは「人間確認で止まる」の逆——止まらせず自律継続させる機構**であり、まさに upstream #399 のコメントが提案する「post-TDD hook で review/commit を機械的に強制」の実装手段にあたる。
- 重要な制約: 「Hook decisions don't bypass permission rules.」——deny / ask ルールは hook の戻り値と無関係に評価される [4]。

### 1d. スケジューリング / cron

**この repo のランタイムに見えていた `CronCreate` / `CronList` / `CronDelete` / `ScheduleWakeup` は公式機能として文書化されている** [5]（当初 ADR-0015 の文脈では正体不明だったが、一次情報で確認できた）。

- セッションスコープのツール群: `CronCreate`（5-field cron 式）/ `CronList` / `CronDelete`（8文字 ID 指定）/ `ScheduleWakeup`（`stop: true` で pending wakeup をキャンセル）[5]。1セッションで最大50タスク、recurring タスクは作成7日後に自動失効 [5]。
- 組み込み `/loop` コマンド（`/loop 5m <prompt>` 等）、`.claude/loop.md` でプロンプトを差し替え可能 [5]。
- **未確認**: 本エージェントにロードされたツールスキーマは `durable: true` で `.claude/scheduled_tasks.json` に永続化すると記述するが、サブエージェントは**この永続化挙動を Anthropic 公式ドキュメントで確認できなかった**（GitHub issue 上の言及のみ）[5]。ツールスキーマ（ランタイムが提示する一次的記述）には存在するが、公式ドキュメントページには載っていない、という食い違いがある。セッションをまたぐ真の永続スケジュールについては、公式は別機構（cloud の Routines、Desktop scheduled tasks、GitHub Actions）を案内している [5]。

### 1e. 無人運用のガードレール（公式推奨）

- **検証ゲートが最重要（逐語）**: 「Give Claude a check it can run: tests, a build, a screenshot to compare. It's the difference between a session you watch and one you walk away from.」[6] 手段として tests / build exit code / linter / screenshot / `/goal` 条件 / **Stop hook を決定的ゲートとして** / サブエージェント検証を挙げる [6]。
- **隔離技術の公式比較** [7]: Sandbox runtime（低オーバーヘッド・安全なデフォルト）／ Docker コンテナ ／ gVisor ／ Firecracker VM。コンテナ hardening 例として `--cap-drop ALL --security-opt no-new-privileges --read-only --network none --memory 2g --user 1000:1000` 等を提示 [7]。
- **クレデンシャル**: proxy パターン推奨——認証情報をエージェントの境界の外に置き、proxy が注入する（エージェントは認証情報を一切見ない）[7]。
- **git worktree 隔離（逐語）**: 「Run separate CLI sessions in isolated git checkouts so edits don't collide.」[6] ← この repo の `/to-worktree` / Orca worktree 方針と整合。
- **ネットワーク隔離**: `--network none` + host 上の proxy への Unix socket のみ、というゼロトラスト構成 [7]。
- **`auto` モードの正直な限界（Research preview、逐語）**: 「Auto mode is a research preview. It reduces permission prompts but does not guarantee safety.」実際の overeager アクションに対する**false-negative 率17%**（危険コマンドがすり抜ける）[8]。デフォルトでブロックするもの: `curl | bash`、機微データの外部送信、本番 deploy / migration、`main` への force push / push、`git reset --hard`、`git checkout -- .`、`git clean -fd`、`terraform destroy` 等 [8]。「not a drop-in replacement for careful human review on high-stakes infrastructure」[8]。

**Q1 の要点**: Anthropic は「人間確認を減らす」機能（`auto` / `bypassPermissions` / headless / Stop hook での継続強制）を明確に提供する一方、**そのすべてに「隔離環境で」という条件と「検証ゲートを必ず持たせろ」という対の推奨を付けている**。permission プロンプトを外すことと、安全性を保証することは別だ、と公式自身が明言している [8]。

---

## Q2. 業界の無人ループ運用パターン（loop engineering / Ralph Wiggum）

Geoffrey Huntley の "Ralph Wiggum" 技法。**最重要の注意点として、出典によってガードレールの記述が大きく異なる**ため、2つの一次情報を分けて記録する。

### 2a. 原典 blog（ghuntley.com/ralph/、2025-07-14）[9]

- 核となるコマンド（逐語）: `while :; do cat PROMPT.md | claude-code ; done`
- **ガードレールはほぼ記述されていない**。WebFetch で原文を確認した限り: サンドボックス／コンテナ／VM の言及なし、branch 保護・PR レビュー・staging の言及なし、ロールバック戦略なし、クレデンシャル露出リスクの言及なし [9]。
- 人間チェックポイントは**予防ゲートとしては提示されず、失敗からの復旧としてのみ**登場する。著者は「full hands-off vibe coding」と表現し、「you'll wake up to a broken code base... and you'll have situations where Ralph can't fix it himself」と破綻を認めつつ手動復旧のみを示す [9]。
- **重要**: 原典 blog はガードレールを積極的には示していない。上に列挙した「なし」は、本エージェントが原文に対して個別に確認した「言及の不在」であって、著者が「不要」と積極的に述べたわけではない。

### 2b. 後発の playbook repo（github.com/ghuntley/how-to-ralph-wiggum）[10]

同じ著者による詳細版 playbook では、原典と対照的に**サンドボックスを唯一のセキュリティ境界として必須化している**。

- **サンドボックス必須（逐語）**: 「To operate autonomously, Ralph requires `--dangerously-skip-permissions` - asking for approval on every tool call would break the loop. This bypasses Claude's permission system entirely - so a sandbox becomes your only security boundary.」[10]
- **クレデンシャル露出警告（逐語）**: 「Running without a sandbox exposes credentials, browser cookies, SSH keys, and access tokens on your machine」。哲学として「It's not if it gets popped, it's when. And what is the blast radius?」[10]
- **最小権限（逐語）**: 「Run in isolated environments with minimum viable access: Only the API keys and deploy keys needed for the task, No access to private data beyond requirements, Restrict network connectivity where possible」。手段: Docker sandbox（ローカル）/ Fly Sprites・E2B 等（リモート）[10]。
- **エスケープハッチ（逐語）**: 「Ctrl+C stops the loop; `git reset --hard` reverts uncommitted changes; regenerate plan if trajectory goes wrong」[10]。
- **git**: 各イテレーションで commit 後 `git push`（監査証跡になる）。ただし **merge 前の人間レビューゲート・PR 必須・throwaway branch 限定は記述されていない**（本エージェントが確認した不在）[10]。
- **コスト／レート／spend 上限**: 記述なし（本エージェントが確認した不在）[10]。

### 2c. Anthropic による製品化と著者自身の留保

Ralph は Anthropic が Claude Code のプラグインとして同梱するに至った（`/loop` 相当。CLI から一度起動し「done」の条件を指定、条件充足か手動停止まで同じ指示に戻され続ける）——Q1 [5] の組み込み `/loop` はこの系譜。ただし著者本人はプロダクト化に留保を示している（Dev Interrupted のインタビュー、**二次情報**）: 「I see LLMs as an amplifier of operator skill, and if you just set it off and run away, you're not going to get a great outcome. You really want to babysit this thing.」また automatic context compaction が長時間セッションの品質を損なう懸念を挙げている [インタビュー要約、二次]。

**Q2 の要点**: 「無人ループ」の実運用パターンで一次情報が一致して要求する唯一のガードレールは **`--dangerously-skip-permissions` + サンドボックス隔離**（Q1 [2][7] の Anthropic 公式条件と一致）。一方で**「merge 前の人間レビュー」を必須とする一次情報は Ralph 側には無い**——commit/push はするが PR ゲートは各自の運用に委ねられている。著者自身は「babysit しろ」と言っており、完全 hands-off を推奨しているわけではない。

---

## Q3. upstream mattpocock/skills の設計議論

pin: `main` = [`8515a080`](https://github.com/mattpocock/skills/commit/8515a080)（2026-07-07 15:37 UTC 時点）。ADR-0015 は `16a2a5cd`（2026-07-06）を pin していたので、その1日後のスナップショット。

### 3a. `implement` は依然として自律オーケストレーター、#399 は未修正 [11][13]

`skills/engineering/implement/SKILL.md`（pin した revision で確認）は5行のまま [11]:

```
Use /tdd where possible, at pre-agreed seams.
Run typechecking regularly, single test files regularly, and the full test suite once at the end.
Once done, use /code-review to review the work.
Commit your work to the current branch.
```

`disable-model-invocation: true`（user-invoked）。**ADR-0015 で指摘した #399（最終2ステップ = review + commit の省略）を防ぐ文言は、この新しい pin でも追加されていない**——「MUST proceed without silent truncation」等は未反映。よって ADR-0015 の「#399 は未修正」という判断は 2026-07-07 時点でも成立する [11][13]。

### 3b. #399 の設計的含意——「人間確認 = バグ」という upstream の立場 [13]

issue #399 は依然 **OPEN**。本文と AI triage brief を読むと、upstream 側は**「自律継続こそ意図された挙動、途中で人間に聞くのはバグ」**という立場を取っている。これは本 repo の ADR-0015（人間確認を意図的に追加）と真逆の設計思想である点が重要:

- 報告本文: `/implement` が tests pass 後に「Are we done?」と**ユーザーに不要に聞いて停止する**ことをバグとして報告 [13]。
- AI triage brief（LucasGHE）の Desired behavior（逐語）: 「Once implementation is complete, the workflow should continue through review and commit **unless the user explicitly interrupts it**.」Acceptance criteria に「the workflow no longer halts early with avoidable 'are we done?' prompts」[13]。→ **人間確認は「明示的な中断」時のみ、デフォルトは自律継続**、という設計方向。
- コメントで2つの実装アプローチが対立している:
  - **プロンプト強化派**（chievan）: SKILL.md に厳格ルールを追記したらローカルで解決した、と報告 [13]。
  - **機械的ゲート派**（xg-gh-25）: 「make the final verification mechanical so the agent can't truncate early even if it tries」——SwarmAI では pytest hook（coverage 閾値割れで全 suite fail）を入れ、「'should' を 'must' に変えた」。review + commit の truncation には同様の **post-TDD hook** を提案 [13]。← Q1 [4] の Stop hook / PreToolUse hook で機械的に実装可能な方向。ADR-0015 はこの機械的ゲートを**あえて採らなかった**。

### 3c. 自律運用を進める方向の関連 issue（すべて OPEN）

- **#329**「run triage and tdd agents automatically」[14]: orchestrator plugin で (1) `needs-triage` issue を polling して triage、(2) `ready-for-agent` issue を polling して `/tdd` を開始、を提案。注目すべきは **ralph-loop への言及と使い分け**: 「it should work through them one session/context per issue. This would be more token efficient than the traditional ralph-loop... because the traditional loop tends to try to do multiple in one session.」→ 「1 issue = 1 session/context」の orchestrator の方が ralph-loop より良い、という設計観。blocker 順序の理解、`/to-issues` 済みの PRD issue の除外にも触れる。
- **#451**「the spec, not the loop: a compile step between /triage and /implement」[14]: 「loop engineering」（loop をどう構造化し、いつ checkpoint するか）に対し、**spec が steering する**アプローチを提案。「the loop is the imperative half of a very old debate（DDIA の declarative vs imperative）」という枠組み。作者は Maestro（git worktree 横断で並列エージェントを orchestrate する desktop app、〜30 ADR）で engineering suite を運用中。
- **#197 / #252**「skill orchestrator / skill-router」[14]: ワークフローを即実行せず、ゴールと開始点（idea / bug / issue / PRD / codebase / UI / prototype）からスキルチェーンを推奨する meta-skill 提案。→ 本 repo の `ask-matt` router に相当する方向。
- **#124**「Add user confirmation checkpoint between Phase 4 and Phase 5」[14]: **逆方向の提案**——`diagnosing-bugs` で instrument（Phase 4）から fix（Phase 5、コードを書く）へ**確認なしで進むのをやめ、root cause を人間に報告して明示確認を待つ mandatory checkpoint を追加**すべき、と主張。「the stakes are higher since Phase 5 writes code」。→ upstream 内にも「コードを書く前には人間確認を挟むべき」という声が併存する。本 repo の ADR-0015 の思想（commit 前の人間確認）と同系。

**Q3 の要点**: upstream には**両方向の圧力が併存**する。主流の `implement` / #399 / #329 は「自律継続がデフォルト、人間中断は例外」に寄る一方、#124 は「コードを書く前には人間確認を挟め」と逆を向く。#399 のコメントは「プロンプト強化 vs 機械的 hook ゲート」で割れており、**ADR-0015 が採った『doc 層の確認ステップ（プロンプト側、機械的ゲートなし）』は、この上流の対立軸の中では『プロンプト強化派に寄せつつ人間確認を残す』という第三の位置**にある。

---

## Open questions / 一次情報が決着させなかったこと

1. **`.claude/scheduled_tasks.json` の永続化の公式ステータスが不明**。ランタイムのツールスキーマ [5 の runtime 記述] は `durable: true` での永続化を明記するが、Anthropic 公式ドキュメントページでは確認できなかった（GitHub issue 上の言及のみ）。これに依存した設計をする場合、サポート保証のない挙動である可能性を織り込む必要がある。

2. **Ralph 系の一次情報は「merge 前の人間レビューゲート」を必須にしていない**。commit/push はするが PR レビューを required とする記述は原典 blog にも playbook にも無い。無人ループを PR ゲート付きで回すという構成は、本 repo の `to-pr`（ready-for-review PR を作る）と組み合わせた場合の**独自設計**になり、既存の一次情報からそのまま借用できるパターンではない。

3. **「自律継続がデフォルト、人間中断は例外」への反転を本 repo が採るべきか**は一次情報では決着しない。upstream #399/#329 はその方向を「意図」とするが、同じ upstream の #124 は逆を向き、Anthropic 公式 [8] は「permission プロンプト削減 ≠ 安全保証」「high-stakes には人間レビューを」と釘を刺す。ADR-0015 の「Claude Code は明示依頼なしに commit しない基本方針を持つ」という前提自体、`auto` モード [8] や `bypassPermissions` [2] を使うと崩れる——**どの permission モードで運用するかで、doc 層の確認ステップが実効的ガードになるか無効化されるかが変わる**。ここは grill で詰めるべき核心。

4. **機械的ゲート（Stop hook / PreToolUse hook）を「導入しない」という ADR-0015 の判断の再検討余地**。Q1 [4] で hook による commit/review 強制は技術的に可能と確認できた。#399 のコメント（xg-gh-25）も機械的ゲートを推す。ADR-0015 は over-engineering を理由に見送ったが、他ランタイム（Codex / Antigravity）や `bypassPermissions` 運用では doc 層の確認が効かない可能性があり、機械的ゲートの費用対効果は運用モード次第で変わる。

5. **`auto` モードの17% false-negative [8] を本 repo のリスク許容度でどう評価するか**は一次情報の外。Anthropic は数値と「research preview / not a safety guarantee」を正直に開示しているが、dotfiles/インフラ変更を含みうる本 repo の作業で許容できる誤り率かは判断が要る。

---

## 出典

**Q1（Anthropic 公式、`claude-code-guide` サブエージェント経由で取得、2026-07-08）**

- [1] Claude Code — Headless / print mode: https://code.claude.com/docs/en/headless.md
- [2] Claude Code — Permission modes: https://code.claude.com/docs/en/permission-modes.md
- [3] Claude Code — Permissions: https://code.claude.com/docs/en/permissions.md
- [4] Claude Code — Hooks reference: https://code.claude.com/docs/en/hooks.md
- [5] Claude Code — Scheduled tasks (`/loop`, Cron\* tools, ScheduleWakeup): https://code.claude.com/docs/en/scheduled-tasks.md
- [6] Claude Code — Best practices: https://code.claude.com/docs/en/best-practices
- [7] Claude Code — Agent SDK secure deployment: https://code.claude.com/docs/en/agent-sdk/secure-deployment.md
- [8] Anthropic Engineering — Claude Code auto mode: https://www.anthropic.com/engineering/claude-code-auto-mode

**Q2（Ralph、本エージェントが直接取得、2026-07-08）**

- [9] Geoffrey Huntley — "Ralph Wiggum as a software engineer"（2025-07-14）: https://ghuntley.com/ralph/
- [10] ghuntley/how-to-ralph-wiggum（playbook repo）: https://github.com/ghuntley/how-to-ralph-wiggum
- （二次）Dev Interrupted — "Inventing the Ralph Wiggum Loop"（著者インタビュー要約）: https://linearb.io/dev-interrupted/podcast/inventing-the-ralph-wiggum-loop

**Q3（mattpocock/skills、本エージェントが `gh` で直接取得、pin `8515a080` / 2026-07-07）**

- [11] `skills/engineering/implement/SKILL.md`（@ 8515a080）: https://github.com/mattpocock/skills/blob/8515a080/skills/engineering/implement/SKILL.md
- [12] `skills/engineering/README.md`（@ 8515a080）: https://github.com/mattpocock/skills/blob/8515a080/skills/engineering/README.md
- [13] issue #399 — implement が最終 review/commit を省略（OPEN）: https://github.com/mattpocock/skills/issues/399
- [14] 関連 issue: [#329](https://github.com/mattpocock/skills/issues/329) / [#451](https://github.com/mattpocock/skills/issues/451) / [#197](https://github.com/mattpocock/skills/issues/197) / [#124](https://github.com/mattpocock/skills/issues/124)
