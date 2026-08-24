---
type: research
title: llm-agents.nix と APM 管理 skill の更新差分（2026-08-24）
description: 2026-08-21 メモ以降に確認できる LLM エージェント、llm-agents.nix、APM 管理 skill/tool の公式リリース・タグ・コミット・ドキュメント差分を一次情報だけで整理した調査ノート。
tags:
  [research, llm-agents, apm, skills, claude-code, codex, remotion, impeccable]
timestamp: 2026-08-24
---

# llm-agents.nix と APM 管理 skill の更新差分（2026-08-24）

このノートの `timestamp` と日付だけの履歴表記は JST（Asia/Tokyo）を基準とする。

## 結論

調査基準時刻は **2026-08-24 09:00 JST / 2026-08-24 00:00 UTC**。比較基準は前回メモの **2026-08-21 08:50 JST / 2026-08-20 23:50 UTC 前後**とし、固定済みの source / lock は変更していない（本ノートは調査のみで `apm.yml` / `apm.lock.yaml` / `flake.lock` / `modules/ai.nix` は一切変更していない）。

前回以降、`numtide/llm-agents.nix` の公式 main は [`3c16acbe`](https://github.com/numtide/llm-agents.nix/commit/3c16acbe5229040ee8f4d6f7b85de757e14b4bda)（2026-08-23 21:57:04 UTC）まで進んだ。当 repo が直接消費する package のうち次が進んだ。

| package           | 現行 source / 前回確認値 | 今回確認した公式候補                                                                                                                                                                                                          | 判断                                                                                                                                                 |
| ----------------- | ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| claude-code       | `2.1.238`                | **`2.1.241`**（[`hashes.json`](https://raw.githubusercontent.com/numtide/llm-agents.nix/3c16acbe5229040ee8f4d6f7b85de757e14b4bda/packages/claude-code/hashes.json)）。途中版は `2.1.239`→`2.1.240`→`2.1.241`。                | 更新候補（pin）。床上げ根拠は `2.1.239` の worktree / teammate / 多 agent messaging 関連修正のみで、`2.1.240`/`2.1.241` は根拠なし。詳細は本文参照。 |
| codex             | `0.149.0`                | 変更なし（[`hashes.json`](https://raw.githubusercontent.com/numtide/llm-agents.nix/3c16acbe5229040ee8f4d6f7b85de757e14b4bda/packages/codex/hashes.json) は据え置き）。公式最新 tag は pre-release `rust-v0.149.0-alpha.4.3`。 | 変更なし。alpha tag は候補にしない。                                                                                                                 |
| antigravity-cli   | `1.1.17`                 | **`1.1.19`**（[`hashes.json`](https://raw.githubusercontent.com/numtide/llm-agents.nix/3c16acbe5229040ee8f4d6f7b85de757e14b4bda/packages/antigravity-cli/hashes.json)）。途中版は `1.1.18`→`1.1.19`。                         | package metadata の追従候補。version 固有 changelog は前回同様 **未確認**。                                                                          |
| copilot-cli       | `1.0.80`                 | `1.0.80`（npm registry 実測でも同値）                                                                                                                                                                                         | 変更なし。                                                                                                                                           |
| rtk               | `0.45.0`                 | `0.45.0`                                                                                                                                                                                                                      | 変更なし。                                                                                                                                           |
| apm               | `0.28.0`                 | `0.28.0`（公式最新 release も [`v0.28.0`](https://github.com/microsoft/apm/releases/tag/v0.28.0) のまま、2026-08-06 公開）                                                                                                    | 変更なし。                                                                                                                                           |
| code-review-graph | (llm-agents.nix 同梱)    | llm-agents.nix の compare 差分ファイルに `packages/code-review-graph/*` は含まれない                                                                                                                                          | 変更なし。                                                                                                                                           |

APM 管理 skill は、今回の確認範囲では Impeccable の selected subtree に実質的な差分がある。Remotion は前回ノートの候補（`7fc6dea3`）が既に `apm.yml` へ採用済みで、そこからさらに1 commit 進んだが version marker のみの機械的な更新だった。

- **Impeccable**（`pbakaus/impeccable`）: 現行 pin `5a149f3f`（4.1.1）から main HEAD [`c39b6425`](https://github.com/pbakaus/impeccable/commit/c39b6425fa54a093749b9a236adcd003818167c1)（2026-08-23 23:33:14 UTC）まで、selected path `.agents/skills/impeccable` を含む実質コミットが多数積まれている。live-server の symlink 脱出修正、agent-facing poller field の sanitize、Claude hook migration / home-scoped agent freshness の修正など、ADR-0029 が警戒する「hook 配線」領域に触れる変更を含むため、次回 pin 前進時は Design Hook 互換性ゲートを必ず通す。
- **Matt Pocock**（`mattpocock/skills`）: 現行 pin `6acc160e`（v1.2.3 full set）から main HEAD [`5b15a47f`](https://github.com/mattpocock/skills/commit/5b15a47f2d7150f545fbcacbfe381787fc0230dc)（2026-08-21 10:56:33 UTC）まで36 commit の差分があるが、前回ノート以降に main 自体は**進んでいない**（前回確認した `0ab1b63a4` の6 commit 後で main が止まっている）。ADR-0041 が調停済みの workflow migration 系列（grilling の HR 区切り、`writing-for-agents` 系のリネーム等）に加えて、新規 `implement-spec`（in-progress bucket）追加と code-review 手順の wording 修正が積まれているが、いずれも既存の「別 migration として保留」判断を変える材料ではない。
- **Remotion**（`remotion-dev/skills`）: 現行 pin `7fc6dea3`（4.0.514、前回ノートの候補として既に採用済み）から main HEAD [`baf0b919`](https://github.com/remotion-dev/skills/commit/baf0b919ff90bc980e8d2b73eb65a124cd262a64)（"Update template"、2026-08-21 11:38:39 UTC）まで進んだが、`SKILL.md` / `REFERENCE.md` の diff は `version: 4.0.514` → `4.0.515` の1行のみで、ガイダンス本文は無変更。
- **Orca**（`stablyai/orca`）: main は419 commit（`orca-cli` 基準）/多数 commit（`orchestration`/`computer-use` 基準）進んだが、`skills/orca-cli`、`skills/orchestration`、`skills/computer-use` の各 selected path 配下に file 差分はない。`skill-guides/orchestration.md` と `skill-guides/computer-use.md` は更新されたが、この2 skill の `SKILL.md` は「詳細は `orca` binary 自身が返す discovery stub」と明記しており、`skill-guides/*.md` を参照しない設計であることをソースで確認した。よって選択 skill の配備物には影響しない。
- `pbakaus/impeccable` 以外の floating skill（`anthropics/skills`、`vercel-labs/agent-skills`、`vercel-labs/skills`、`shadcn-ui/ui`）は upstream リポジトリ全体では commit があるが、selected subtree（`skills/pdf`、`skills/skill-creator`、各 vercel skill、`skills/shadcn`）配下には file 差分がなかった。`GoogleChrome/modern-web-guidance`、`Effect-TS/skills`、`supabase/agent-skills`、`mizchi/skills` は比較範囲に新しい commit が一切ない。

**調査結論（採否は判断していない、次の実装 round 向けの候補提示のみ）:** `llm-agents.nix@3c16acbe`、Claude pin `2.1.241`（床上げ候補は `2.1.239` 由来の根拠のみ）、Antigravity package metadata `1.1.19` が pin 追従候補。Impeccable `c39b6425` は Design Hook ゲート必須の更新候補。Remotion `baf0b919` は機械的更新のため優先度低い。Matt Pocock は引き続き別 migration として保留。

## 調査範囲と方法

repo の次の source / lock を対象にした。

- CLI: `private_dot_config/nix-devshell/flake.nix`、`private_dot_config/nix-devshell/flake.lock`、`private_dot_config/nix-devshell/modules/ai.nix`、`private_dot_config/nix-devshell/packages/code-review-graph.nix`
- APM manifest / lock: `apm.yml`、`apm.lock.yaml`
- 背景と前回との差分: `runtime/ai-runtimes.md`、`docs/research/llm-agents-and-apm-update-2026-08-21.md`、`docs/adr/0041-adopt-mattpocock-v1-2-3-workflow-semantics.md`

外部情報は、`gh api` 経由の GitHub REST API（`repos/<owner>/<repo>/compare`、`.../commits`、`.../releases`）、immutable commit の raw source、公式 release page、公式 CHANGELOG.md、npm registry のみを確認した。検索結果の二次記事、SNS、転載 changelog は根拠にしていない。

本ノートは調査専用であり、`apm.yml` / `apm.lock.yaml` / `flake.lock` / `modules/ai.nix` の変更、`nix flake update`、`apm install`/`apm lock` の実行は行っていない。

## llm-agents.nix と CLI の一次情報

### Snapshot と package metadata

前回 source の snapshot は `d205793bf7c7f4cb41ce73ba0983c5f7a5e2c6da`。[公式 compare](https://github.com/numtide/llm-agents.nix/compare/d205793bf7c7f4cb41ce73ba0983c5f7a5e2c6da...3c16acbe5229040ee8f4d6f7b85de757e14b4bda) で今回の package 差分は当 repo が直接消費する package のうち Claude Code と Antigravity CLI の2つだけだった（`ahead_by: 148`、他の変更は `aionui`、`amp`、`opencode`、`orca` など当 repo が配備しない package）。

- claude-code の `hashes.json` は3コミットで `2.1.238 -> 2.1.239 -> 2.1.240 -> 2.1.241` と進んだ（[`2.1.239`](https://github.com/numtide/llm-agents.nix/commit/3d22cc36e0ada9bcd8913fc127f93c1358acbc7c)、[`2.1.240`](https://github.com/numtide/llm-agents.nix/commit/69ee6f5d00edc1a2744e3d1a64dfbaae34f4c6db)、[`2.1.241`](https://github.com/numtide/llm-agents.nix/commit/23dfb67f055b8eaaf24ea5d2d9fda02858527309)）。
- antigravity-cli の `hashes.json` は2コミットで `1.1.17 -> 1.1.18 -> 1.1.19` と進んだ（[`1.1.18`](https://github.com/numtide/llm-agents.nix/commit/510af4858a14be0585e10959632c5c19dca65622)、[`1.1.19`](https://github.com/numtide/llm-agents.nix/commit/814bc6dcaab7934f582bebe715b822d9d65d8a1c)）。
- codex、copilot-cli、rtk、apm、code-review-graph の各 `package.nix`/`hashes.json` は compare のファイル一覧に含まれず、無変更を確認した。

### Claude Code 2.1.239–2.1.241

公式 [`v2.1.241` の `CHANGELOG.md`](https://raw.githubusercontent.com/anthropics/claude-code/v2.1.241/CHANGELOG.md) を確認した。

`2.1.240` と `2.1.241` はいずれも "Bug fixes and reliability improvements" の一行のみで、床上げの具体根拠を確認できない（過去の 2.1.201 / 2.1.226 / 2.1.228 の一部と同じ扱い）。

`2.1.239` はこの repo の床根拠（多 agent ワークフロー・worktree 隔離・permission/trust boundary の信頼性）に当たり得る項目を複数含む。

- **worktree 関連**: `extensions.worktreeConfig` が設定された repo で Linux sandbox が `.git/config.worktree`（存在しないファイル）を unreadable と誤判定し、sandbox 化されたあらゆる git コマンドを壊していた不具合を修正。過去に `2.1.207` で `extensions.worktreeConfig` 残留バグを踏んでいるのと同じ設定項目に関わる。
- **hook/working-directory 関連**: セッションの working directory が削除された後、hook が `posix_spawn ENOENT` で失敗していた不具合を修正し、project root または home directory から実行するよう変更。`worktree-gc` が対象とする「worktree を回収した後もそのディレクトリを前提にした処理が残る」状況と同種。
- **teammate/多 agent messaging 関連**（`teammateMode: auto` を使うこの repo に直結）: `ListAgents` が自分自身の名前を返すようになり、`SendMessage` で自分宛に送った場合も "no agent named…" ではなく正しく応答するよう修正。`ListAgents`/`/list-agents` が live teammate を一覧できるよう修正（従来は subagent と他 session しか見えず、到達可能な teammate が不在に見えていた）。
- その他: `2.1.232` regression だった background job 間のセッションタイトル同期の暴走を修正。組織ポリシーで拒否されたリクエストが拒否表示前に再送されていた不具合を修正。

上記を根拠とすれば `minClaudeCode` の `2.1.238` → `2.1.239` 以上への引き上げは前回までの判断基準と整合するが、この判定と実際の pin/floor 更新は次回の実装 round に委ねる（本ノートでは設定ファイルを変更していない）。

### Antigravity CLI 1.1.19

`llm-agents.nix` の package metadata から version `1.1.19`、Linux/Darwin artifact URL・hash は確認できたが、`1.1.18`/`1.1.19` 固有の公式 release note やアップストリームの changelog はこの調査範囲では **未確認**（前回ノートの `1.1.17` と同じ扱い）。

### Codex 0.149.0（変更なし）

公式 release 一覧の最新 tag は [`rust-v0.149.0-alpha.4.3`](https://github.com/openai/codex/releases) だが pre-release（alpha）であり、`llm-agents.nix` が追従する安定版は引き続き `0.149.0`。候補としては扱わない。

## APM skill / tool の一次情報

### Impeccable（`.agents/skills/impeccable`）

現行 pin `5a149f3fdb1b5793f10567233b1dcab98fc305fd`（SKILL.md 記載 version `4.1.1`）から公式 main HEAD [`c39b6425`](https://github.com/pbakaus/impeccable/commit/c39b6425fa54a093749b9a236adcd003818167c1)（2026-08-23 23:33:14 UTC）まで、selected path 直下の「Sync generated provider output」コミットが11件積まれている。これは複数 provider ディレクトリ（`.claude/skills/impeccable`、`.agents/skills/impeccable` 等）へ生成物を同期するコミットで、実体の変更は同じ期間の非 sync コミット側にある。[`compare (5a149f3f...main)`](https://github.com/pbakaus/impeccable/compare/5a149f3fdb1b5793f10567233b1dcab98fc305fd...main) で確認できた非 sync コミットのうち、この repo の hook 運用・安全境界に関係し得るものは次のとおり。

- [`Fix: stop live-server /source from following symlinks out of the workspace (#618)`](https://github.com/pbakaus/impeccable/commit/d008dd98) とその追加テスト [`#618`](https://github.com/pbakaus/impeccable/commit/869c8873) — live preview server の symlink 経由ワークスペース脱出を修正。
- [`Fix: strip page-controlled poller fields before they reach the agent (#488)`](https://github.com/pbakaus/impeccable/commit/bda7411a) — ページ側が制御可能な値が agent 入力へそのまま渡っていた経路を修正。
- [`Fix Claude agent installation`](https://github.com/pbakaus/impeccable/commit/7b945856)、[`Fix home-scoped agent freshness`](https://github.com/pbakaus/impeccable/commit/16a218e6)、[`Preserve inferred agent update scope`](https://github.com/pbakaus/impeccable/commit/d2a9efb9)、[`Sync marketplace Claude hook repair`](https://github.com/pbakaus/impeccable/commit/611147a3)、[`Fix Windows hook migration dedupe`](https://github.com/pbakaus/impeccable/commit/665c51b9) — いずれも Claude 側 hook/agent のインストール・更新スコープ・同期に関わる。ADR-0029 が要求する「どのルールがどのイベントで出るか」の再検証対象。
- 残りは detector（oklch parsing、コメント除去、grid-background 誤検知、color-mix 内 hex 判定など）の false positive/negative 修正で、Design Hook の検出精度には影響し得るが hook 配線そのものは変えない。

SKILL.md の `version:` フィールドは `4.1.1` のまま変わっていない（package.json 側は `3.6.0` を指しており、リポジトリ内の versioning 体系がスキル単位とルートパッケージ単位で分離している点に注意——直接の矛盾ではなく、比較対象を誤らないための記録）。次に pin を進める場合は、ADR-0029 の手順どおり `IMPECCABLE_HOOK_RUNTIME=c39b6425 bats tests/design-hook.bats` を隔離 HOME で実行し、上記 hook/agent 関連コミットが検出範囲や tier 分類にどう影響するかを確認する。

### Matt Pocock skills

現行 pin `6acc160e4e0cd062dbbbd7a1b26ae92855edf07e` から公式 main HEAD [`5b15a47f`](https://github.com/mattpocock/skills/commit/5b15a47f2d7150f545fbcacbfe381787fc0230dc)（2026-08-21 10:56:33 UTC）まで [36 commit](https://github.com/mattpocock/skills/compare/6acc160e4e0cd062dbbbd7a1b26ae92855edf07e...main) の差分がある。前回ノート（2026-08-21）が確認した main HEAD `0ab1b63a4` の時点からは、その後6 commit だけ進んで以降 main は動いていない（今回の調査時点でも `5b15a47f` が main HEAD）。

前回ノートで保留した workflow migration 系列（`grilling` の HR 区切り [`85f83d3f`](https://github.com/mattpocock/skills/commit/85f83d3fde1d3a90d5c9a657f6998c79a6c37308)/[`0ab1b63a`](https://github.com/mattpocock/skills/commit/0ab1b63a410a03d3627979a109c8695de27af954) と `writing-great-skills` → `writing-for-agents` のリネームを含む）に加え、前回ノート以降に次が積まれた。

- [`Add implement-spec skill (in-progress) with its bucket docs`](https://github.com/mattpocock/skills/commit/84b5ee5a) — `skills/in-progress/implement-spec` として追加された新規 skill（in-progress バケットのため即時配備対象ではない）。
- [`fix: clarify wording in implementation steps for code review process`](https://github.com/mattpocock/skills/commit/5b15a47f) — `code-review` 手順の wording 修正。

いずれも ADR-0041 が調停済みの「別 migration として保留」判断を変える材料ではない。現行 `6acc160e` の据え置きを継続する。

### Remotion

現行 pin `7fc6dea333869e23f58bf9e9861010e9ba589e5e`（前回ノートの候補として既に採用済み、version `4.0.514`）から main HEAD [`baf0b919`](https://github.com/remotion-dev/skills/commit/baf0b919ff90bc980e8d2b73eb65a124cd262a64)（コミットメッセージ "Update template"、2026-08-21 11:38:39 UTC）まで1 commit 進んだ。`skills/remotion-best-practices/SKILL.md` と `remotion-markup/REFERENCE.md`（前回ノートで挙動変更ありと指摘した `<HtmlInCanvas>` guidance を含むファイル）を実測 diff した結果、差分は `version: 4.0.514` → `4.0.515` の1行のみで、ガイダンス本文・`<HtmlInCanvas>` nesting 方針に変更はない。この repo の当時の判断（selected subtree を materialize して verification を通してから採用）は変わらない。

### Orca の selected skill（`orca-cli` / `orchestration` / `computer-use`）

`orca-cli` は base [`5ca747da`](https://github.com/stablyai/orca/commit/5ca747dad0d0583f4a1ac91c2655b345ba6c07eb) から main まで110 commit 進んだが、[`skills/orca-cli` 配下および `skill-guides/orca-cli.md` に差分はない](https://github.com/stablyai/orca/compare/5ca747dad0d0583f4a1ac91c2655b345ba6c07eb...main)。

`orchestration`/`computer-use` は base [`cb42b608`](https://github.com/stablyai/orca/commit/cb42b60849d81ff58976200baa6b89dc5df99fb7) から main まで進み、`skill-guides/orchestration.md` と `skill-guides/computer-use.md` は更新されている（例: `orchestration.md` に `dispatch --inject` の `unsupervised` 状態遷移に関する1段落が追加）。しかし `skills/orchestration/SKILL.md` と `skills/computer-use/SKILL.md` の本文をソースから直接確認したところ、いずれも「This file is a discovery stub, not the usage guide. The full, version-matched … reference is served by the `orca` binary itself」と明記されており、`skill-guides/*.md` を参照しない設計になっている。したがって `skill-guides/*.md` の更新は、この repo が APM 経由で配備する selected skill の内容には影響しない。

### その他の floating skill

| upstream                           | 現行 lock / 対象                        | 2026-08-21 メモ以降の公式確認                                                                                                                                                                                              | 判断       |
| ---------------------------------- | --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| `anthropics/skills`                | `f6656c12` / `pdf`, `skill-creator`     | main は [4 commit 進んだ](https://github.com/anthropics/skills/compare/f6656c1256d5a8adfa37db9110046ef20bac644c...main)が、変更は `academy-guide`/`claude-api`/`discernment-nudge` で `pdf`/`skill-creator` 配下に差分なし | 据え置き。 |
| `GoogleChrome/modern-web-guidance` | `460e5536`                              | 期間内の commit なし                                                                                                                                                                                                       | 据え置き。 |
| `shadcn-ui/ui`                     | `d4fc45b1` / `skills/shadcn`            | main は [21 commit 進んだ](https://github.com/shadcn-ui/ui/compare/d4fc45b1fbabfccb7a6a4333d8004cf19481caa9...main)（新規 registry style、`github-cli.ts` 追加等）が `skills/shadcn` 配下に差分なし                        | 据え置き。 |
| `vercel-labs/agent-skills`         | `b8caa260` / composition-patterns 他4件 | main は [4 commit 進んだ](https://github.com/vercel-labs/agent-skills/compare/b8caa260a420a73042e35521de4b5c8baf6446cc...main)（discovery workflow の追加）が `skills/*` 配下に差分なし                                    | 据え置き。 |
| `vercel-labs/skills`               | `c6f69c63` / `find-skills`              | main は [9 commit 進んだ](https://github.com/vercel-labs/skills/compare/c6f69c631292444cc541ac6d91e2226b0ff247da...main)（CLI 本体 `src/*` の変更）が selected skill path に差分なし                                       | 据え置き。 |
| `supabase/agent-skills`            | `8331f910`                              | 期間内の commit なし                                                                                                                                                                                                       | 据え置き。 |
| `Effect-TS/skills`                 | `28822c9e`                              | 期間内の commit なし                                                                                                                                                                                                       | 据え置き。 |
| `mizchi/skills`                    | `7a0d7286`                              | 期間内の commit なし                                                                                                                                                                                                       | 据え置き。 |

### APM CLI 0.28.0

公式 [`v0.28.0` release](https://github.com/microsoft/apm/releases/tag/v0.28.0)（2026-08-06 公開）が引き続き最新の release tag。新規 commit / release tag は今回の調査範囲では確認できなかった。

## 未確認事項と検証境界

- Claude Code `2.1.239`–`2.1.241` は CHANGELOG.md の記述のみを確認した。binary smoke、3-system Nix evaluation、worktree/teammate messaging の実地検証は本ノートでは実施していない（調査専用のため）。
- Antigravity CLI `1.1.18`/`1.1.19` の version 固有 changelog は前回同様 **未確認**。
- Impeccable `c39b6425` の Design Hook 互換性ゲート（`IMPECCABLE_HOOK_RUNTIME` 経由の bats 実行）は本ノートでは実施していない。live-server symlink 修正・hook migration 修正の実際の挙動差分は未検証。
- Matt Pocock の workflow migration 系列は、main が `5b15a47f` で停止していること以上の新しい動きは確認していない。
- upstream の「公式に変更がない」ことを網羅的に証明するものではない。GitHub の対象 repository、release、tag、commit と selected path の範囲で確認できなかったものは **未確認** と扱った。

## 次回の採用時ゲート

1. Claude Code floor 候補 `2.1.239`（pin は `2.1.241` まで追従可）を、3 system の Nix deep evaluation と worktree/teammate messaging の smoke で確認してから `minClaudeCode` を上げる。
2. Antigravity `1.1.19` は metadata/hash/evaluation と version smoke のみを確認し、未確認の upstream changelog を採用理由にしない。
3. Impeccable `c39b6425` は `IMPECCABLE_HOOK_RUNTIME=c39b6425 bats tests/design-hook.bats` を隔離 HOME で実行し、live-server symlink 修正・Claude hook migration 修正が既存の Design Hook 契約（tier 分類・fail-open・dedupe）を壊さないことを確認してから pin を進める。
4. Matt Pocock は今回も pin bump 対象に含めない。workflow migration の調停判断（ADR-0041）が変わらない限り、次回以降も定期確認のみとする。
5. Remotion は機械的な version marker 更新のみのため、他候補と一緒に処理する優先度は低い。

関連: [2026-08-21 調査ノート](llm-agents-and-apm-update-2026-08-21.md) / [ADR-0041](../adr/0041-adopt-mattpocock-v1-2-3-workflow-semantics.md) / [ai-runtimes](../../runtime/ai-runtimes.md) / [skill-harness](../../runtime/skill-harness.md)
