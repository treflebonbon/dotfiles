---
type: decision
title: 外部 skill の契約差は fork せず実効契約で解決する
description: 外部 skill の一般手順と repo の実運用が異なる場合、upstream 変更や local fork ではなく指示層の狭い上書きで解決し、harness-feedback は実効契約と適用 scope に基づいて逸脱を判定する
tags: [adr, skills, harness, observability, apm]
timestamp: 2026-07-13
status: accepted
---

# 外部 skill の契約差は fork せず実効契約で解決する

## Context

`harness-feedback` が DAP の transcript を分析したところ、外部 `triage` / `code-review` skill の一般手順と実運用の差、および DAP 固有 `dap-packages` skill の適用 scope 外の規則を、いずれも critical な実行逸脱として報告した。しかし、前二者は検証不足や承認回避を起こしておらず、後者は Service/UI tier 限定の規則を Apps tier の runtime adapter に誤適用した false positive だった。また Auto mode は現在の project に過去 transcript がない場合、無関係な別 project の直前 transcript へフォールバックしていた。

外部 skill 本文を fork すれば直接修正できるが、APM で pin した upstream との差分を継続保守する必要が生じる。upstream へ変更を提案する選択肢も採らない。一方、差を黙って無視すると、実行時の優先規則と harness の評価基準が分離する。

## Decision

1. 外部 skill は fork も upstream 変更もせず、実運用に必要な差分だけを home / project の指示層で **ローカル skill 上書き**として定義する。
2. `triage` は推薦根拠を得る read-only 検証を推薦前に実行してよい。`code-review` は Builder-Evaluator 内では既知の branch base（通常 `origin/main`）を fixed point として自動採用してよく、standalone で fixed point が不明な場合だけ質問する。
3. `harness-feedback` は system/developer 指示、runtime に対応する project 指示（Codex系は `AGENTS.md`、Claude Codeは `CLAUDE.md`）、呼び出された skill の順に **実効契約**を解決してから逸脱を判定する。下位 skill の規則が上位指示で置き換えられた場合は finding にせず、必要なときだけ **Contract Warning** として報告する。
4. finding の前提として **Scope Matching**を行い、制約の主語、対象層、関数種別、実行文脈が観測対象と一致しない規則は根拠に使わない。
5. **Critical Deviation** は承認・安全境界の回避、必須検証やレビューの欠落、虚偽の完了主張、または成果物の正しさを損なう逸脱に限定する。無害な順序差や追加検証は critical にしない。
6. Auto mode は **Project-scoped Auto Selection**とし、現在の project に一致する過去 transcript がなければ、別 project へフォールバックせず「分析対象なし」で正常終了する。別 project は direct path または project filter でのみ選ぶ。
7. scope mismatch、上位指示による上書き、critical なレビュー欠落、同一 project transcript 不在、Direct path での明示 transcript 優先の5ケースを normative examples として固定する。自動 eval の導入は本決定の範囲外とする。

## Consequences

- APM で取得する外部 skill は改変せず、upstream 更新を継続して取り込める。
- repo 固有の実運用差は指示層に明示され、executor と `harness-feedback` が同じ契約を参照できる。
- `harness-feedback` の finding 数と critical severity は減るが、残る critical は利用者が即時対応すべき実害を表す。
- Auto mode で分析対象が見つからないケースは増える。cross-project 分析には明示的な引数が必要になる。

関連: [ADR-0022](0022-align-mattpocock-v1-1-workflow.md) / [skill-harness](../../runtime/skill-harness.md) / [CONTEXT.md](../../CONTEXT.md)
