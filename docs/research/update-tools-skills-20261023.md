# ツール・スキル更新（2026-10-23）

## 現在の依頼と更新境界

依頼は「`/implement` ツールとスキルの更新。独自パッチはあてない。upstreamにはなにもしない」。開始点は main `e1be40d2f51356cc3eaaaf6a985d65f130778c5e`。Claude Code native worktree `.claude/worktrees/update-tools-skills-20261023`、branch `chore/update-tools-skills-20261023`。

- 「独自パッチはあてない」は、ユーザーへの確認で「既存の独自 patch も撤去する」と決定した。Codex は upstream（Numtide cache）の出力をそのまま使う。
- 「upstreamにはなにもしない」は、issue・PR・comment等の書込みを一切行わない。release情報の読み取りのみ。
- 適用ADR: ADR-0045（更新単位の分離、Tool Snapshot）、ADR-0047（品質floor）、ADR-0053（Impeccable skillとengineの一体検証）。

## 更新単位と採否

| 更新単位 | 採否と根拠 |
| --- | --- |
| Tool Snapshot | `llm-agents.nix` を `998b9f26…` → `529ee8f9a886cb6f09d6f3d25f13b0de72c8a4c0`（2026-10-22 HEAD）へ。Claude Code 2.1.296→2.1.308、Codex 0.162.1→0.163.0、Copilot CLI 1.0.96→1.0.103、Antigravity CLI 1.3.3→1.4.5、Herdr 0.9.3→0.9.5、APM 0.33.0→0.34.0、RTK 0.51.0→1.0.1。品質floor（Claude 2.1.296／Codex 0.162.0）は満たすため変更しない。 |
| Codex独自patch撤去 | `codex-sandbox-cleanup.patch`、未使用の `codex-distinct-mask-fds.patch`、`tests/codex-sandbox-cleanup.bats`、対応する `docs/architecture.md` の記述、single-job build指定を削除。Codex 0.163.0 は `nix build --dry-run` で cache から取得され source build は発生しない。強制終了時に空 `.env` が残り得る既知の回帰は、ユーザー判断で許容する。 |
| root npm | bun-types 1.4.2→1.4.3、oxfmt 0.72.0→0.73.0、oxlint 1.87.0→1.88.0。bunfig の minimum-release-age（7日）の範囲で解決できる最新。latest（1.4.4／0.74.0／1.89.0）は7日未満のため採らない。 |
| studio npm | react／react-dom 19.3.0→19.3.1（公開から7日以上）。`dist` を再buildし、studioテスト21件が成功。 |
| 固定CLI | waza 0.38.10→0.39.0（3 asset のhashを取得、draft／prereleaseともfalse）。flyline・gwq・gws・Playwright CLI・design.md は最新と一致するため維持。 |
| Impeccable | 保留。候補はskill `490141501de5035d1d2fb975239ceb757f045bcb`（6file差分）とengine 0.1.15→0.1.16（ADR-0053の一体更新）。APM lock生成ゲートが通らないため採用しない（下記）。 |
| 通常APM | 保留。候補はRemotion `6c67adcd9cdbe6eb84d76342da89b225f9161cb2`、Modern Web Guidance `65e7edd67e77420eaf02c5df00fdc0521417d809`、Herdr skill `2ecf19a92fc3a7fff75b6ce3655ef04f4625ec01`（v0.9.5 tag）。同上の理由で採用しない。 |
| Matt Pocock | HEADは`5beb35b0…`だが差分は managed set 外の `in-progress/chief-of-staff` だけなので維持。 |
| shadcn／Orca／find-skills | floating の resolved_commit が進むだけで selected subtree は同一。個別の採用理由にしない。 |
| その他APM | anthropics／cloudflare／Effect-TS／mizchi／supabase／vercel-labs はHEADが現行と一致し維持。 |

## APM unit の保留

新snapshotのAPMはNix package上0.34.0だが、実行した`apm --version`は0.33.0を返す（confirmed、dist-infoは0.34.0）。`scripts/generate-apm-lock.sh`はCLI版とsnapshot版の一致を要求して中止するため、lock生成に進めない。ユーザー判断で、ゲートの迂回・APM単独の据え置き・上流への報告のいずれも行わず、APM関連の候補（上表のImpeccable skill+engine、Remotion、Modern Web Guidance、Herdr skill）を保留とした。`apm.yml`・`apm.lock.yaml`・`impeccable.nix`は変更していない。上流の版表示が直った後、同じ候補をこの記録から再評価する。更新全体は未完了。

## 検証結果

結果は最終commit前に追記する。
