# ツール・スキル更新（2026-10-26）

## 現在の依頼と更新境界

依頼は「`/implement` ツールとスキルの更新」。開始点は main `8d6b14c8e33e50ffb4a073530e622e9ea68f68c2`、Claude Code native worktree `.claude/worktrees/update-tools-skills-20261026`。前回（[20261023](update-tools-skills-20261023.md)）の「独自パッチはあてない・upstreamにはなにもしない」を引き続き適用し、release情報の読み取りだけを行う。適用ADR: ADR-0045（更新単位の分離）、ADR-0047（品質floor）、ADR-0053（Impeccable skillとengineの一体検証）。

## 更新単位と採否

| 更新単位 | 採否と根拠 |
| --- | --- |
| Tool Snapshot | `llm-agents.nix` を `529ee8f9…` → `a5500f41321b0a6b68407500f26dd55dbeb5793f`（2026-10-26 HEAD）へ。Claude Code 2.1.308→2.1.310、Codex 0.163.0→0.164.0、Antigravity CLI 1.4.5→1.4.7、APM 0.34.0→0.35.0。Copilot CLI 1.0.103・Herdr 0.9.5 は不変。品質floor（Claude 2.1.296／Codex 0.162.0）は満たすため変更しない。 |
| 通常APM | APM 0.35.0 に合わせて `apm.lock.yaml` を隔離runtimeで再生成する。payload（Remotion `6c67adcd…`、Modern Web Guidance `65e7edd6…`、Herdr skill `2ecf19a9…`）は上流HEADが前回の採用値と一致し不変。 |
| Impeccable | 保留。skill HEAD `3671d50f…` は新しい skill release を伴わない未リリースの差分（32 file）で、engine-v0.1.17 だけが新規。ADR-0053 は skill と engine の一体更新を要求するため、skill の新 release を待つ。 |
| Matt Pocock | HEAD `5beb35b0…` の差分は managed set 外のみ（前回と同じ）。維持。 |
| root npm | 保留。oxfmt 0.74.0／oxlint 1.89.0 は 2026-10-19 公開で、bunfig の minimumReleaseAge（7日）を本日は満たさない（2026-10-26 17:26 UTC 以降に満たす）。bun-types 1.4.4 も 2026-10-22 公開で未達。 |
| 固定CLI | waza 0.39.0 が最新のため維持。 |
