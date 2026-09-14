# ツール・スキル更新（2026-09-14）

## 要件と採用境界

ユーザーの `/implement ツール、スキルの更新` を受け、既存の AI tool snapshot と APM 全19依存を調査する。ADR-0045 に従って通常 payload、Impeccable、Matt managed set、tool snapshot を分離して採否する。validated native worktree の source を変更し、既存のモデル・権限・配布経路を維持する。新しいツール追加、private skill 改稿、live apply、push・PR は今回の範囲に含めない。

受入条件は、配布対象の差分に基づく exact pin の採否、隔離 APM install/frozen/audit、配布 hash・membership の照合、管理 hook 検証、関連テスト・full suite・型チェック、二軸レビュー、コミット。Nix の評価・build ができない更新単位は旧 snapshot を維持し、成功とは報告しない。

## 調査結果

| 依存 | 固定した候補 | 配布差分・判断 |
| --- | --- | --- |
| pdf | [`34040c9c`](https://github.com/anthropics/skills/tree/34040c9c568585f6929bedeaad110ad08f079624) | 配布対象は不変。exact pin は維持し、floating は native lock の解決に従う。 |
| skill-creator | [`34040c9c`](https://github.com/anthropics/skills/tree/34040c9c568585f6929bedeaad110ad08f079624) | 配布対象は不変。exact pin は維持し、floating は native lock の解決に従う。 |
| effect-ts | [`2309e6f2`](https://github.com/effect-ts/skills/tree/2309e6f27d9955b434c0e3f394b945c136e89fd2) | 配布対象は不変。exact pin は維持し、floating は native lock の解決に従う。 |
| modern-web-guidance | [`8dd06413`](https://github.com/googlechrome/modern-web-guidance/tree/8dd064139b76a47d960c8e4422b73755d33bf6a0) | 配布対象は不変。exact pin は維持し、floating は native lock の解決に従う。 |
| herdr | [`aa961df9`](https://github.com/herdrdev/herdr/tree/aa961df943b874730b23f78baf94af7332f7acfa) | 配布対象は不変。exact pin は維持し、floating は native lock の解決に従う。 |
| mattpocock-skills | [`3cca18b3`](https://github.com/mattpocock/skills/tree/3cca18b368ae95cdbdebbff572ccafa662551015) | 配布対象は不変。exact pin は維持し、floating は native lock の解決に従う。 |
| empirical-prompt-tuning | [`66dadd96`](https://github.com/mizchi/skills/tree/66dadd9613719251c1501ba482c08cbd7f55ffee) | 配布対象は不変。exact pin は維持し、floating は native lock の解決に従う。 |
| impeccable | [`cb56ed6c`](https://github.com/pbakaus/impeccable/tree/cb56ed6c19a07329a9fa0cd4e657bee040156593) | reference 3文書のタッチ操作・中断時検証を追加。既存 launcher / engine 0.1.5 を維持して互換性を検証。 |
| remotion-best-practices | [`bd566b65`](https://github.com/remotion-dev/skills/tree/bd566b65d521b40fe92e1f26766e82de9e291693) | 4.0.524 とアイコン PNG→SVG。52ファイル、本文は版表記のみ。 |
| shadcn | [`2b3e6d4f`](https://github.com/shadcn-ui/ui/tree/2b3e6d4f8d9161fe5c19340dc383aade392012dd) | 配布対象は不変。exact pin は維持し、floating は native lock の解決に従う。 |
| computer-use | [`241fb9ed`](https://github.com/stablyai/orca/tree/241fb9ed9d8308d64b4450725732d2ec0f273876) | 配布対象は不変。exact pin は維持し、floating は native lock の解決に従う。 |
| orca-cli | [`241fb9ed`](https://github.com/stablyai/orca/tree/241fb9ed9d8308d64b4450725732d2ec0f273876) | 配布対象は不変。exact pin は維持し、floating は native lock の解決に従う。 |
| orchestration | [`241fb9ed`](https://github.com/stablyai/orca/tree/241fb9ed9d8308d64b4450725732d2ec0f273876) | 配布対象は不変。exact pin は維持し、floating は native lock の解決に従う。 |
| supabase-postgres-best-practices | [`8331f910`](https://github.com/supabase/agent-skills/tree/8331f910845103c08d51f6ca1d86ebb7d1f745e3) | 配布対象は不変。exact pin は維持し、floating は native lock の解決に従う。 |
| vercel-composition-patterns | [`063bee94`](https://github.com/vercel-labs/agent-skills/tree/063bee94c3f4df8453406c830b0a7df0f2860278) | 配布対象は不変。exact pin は維持し、floating は native lock の解決に従う。 |
| vercel-react-best-practices | [`063bee94`](https://github.com/vercel-labs/agent-skills/tree/063bee94c3f4df8453406c830b0a7df0f2860278) | 配布対象は不変。exact pin は維持し、floating は native lock の解決に従う。 |
| vercel-react-view-transitions | [`063bee94`](https://github.com/vercel-labs/agent-skills/tree/063bee94c3f4df8453406c830b0a7df0f2860278) | 配布対象は不変。exact pin は維持し、floating は native lock の解決に従う。 |
| web-design-guidelines | [`063bee94`](https://github.com/vercel-labs/agent-skills/tree/063bee94c3f4df8453406c830b0a7df0f2860278) | 配布対象は不変。exact pin は維持し、floating は native lock の解決に従う。 |
| find-skills | [`d6672828`](https://github.com/vercel-labs/skills/tree/d667282815248da03a08a18272b5d2eef9caf77c) | 配布対象は不変。exact pin は維持し、floating は native lock の解決に従う。 |

比較の一次資料は GitHub の固定 commit 間 compare。300ファイル上限に達した Orca / Herdr は contents API で配布ディレクトリ直下の全 name / tree・blob SHA を比較して一致した。Matt は skills tree と plugin manifest を変更していない。Modern Web Guidance の上流版更新は選択 subtree の外なので pin を維持する。

## Tool snapshot の保留

候補は [`bcd2a60f193d93655a836d7a2e05fb5f7bd8bdc5`](https://github.com/numtide/llm-agents.nix/compare/e320800dd9dc2b156bfa77fbeeb00e9e7295f3a9...bcd2a60f193d93655a836d7a2e05fb5f7bd8bdc5)。Claude Code 2.1.267→2.1.270、Antigravity 1.2.0→1.2.2、RTK 0.48.0→0.49.0。Codex は0.154.0で不変。

`nix develop .#default --command true` が `cannot connect to socket ... Connection refused` で終了1。daemon の共有設定・権限は変更せず、source/lock の snapshot は `e320800dd9dc2b156bfa77fbeeb00e9e7295f3a9` を維持する。候補 build、3 system 評価、CLI smoke は未実施であり、ツール更新は未完了。

## 検証

証跡はこの worktree の `tmp/update-20260914/`。通常 APM 更新の native lock SHA-256 は `9f81bed18017518487014b4ac0f09af2286e6b8fb5a784e5513995edbb90d837`。install/frozen/audit が終了0、lock不変、1,204配布ファイルのhash一致、Impeccable/Matt dependency block不変を確認した。

Orca floating は入口候補より後の `5e70014da8ee6aa6635fe4f031baa7dbaca17231` に自然解決した。content_hash と全配布ファイルhashが現行と同じであり、revision-only として扱う。13 floating dependency の警告は既存方針。組織ポリシー取得の警告はログに残し、private policy 適合を確認したとは扱わない。

既存 APM pin 契約テストの期待値を先に進め、旧 manifest に対して該当テストが失敗することを確認した。新しいテストやテスト基盤は追加していない。

最終 Impeccable 更新後の native lock SHA-256 は `42a3b10c942ced8d76c1dda217278727ebe265eadf27404e0d0fa796ca3f10fa`。install/frozen/audit は終了0、audit 10/10、lock不変、1,204ファイルhash一致、両target43/43 discovery。非Impeccable18 dependency blockは通常更新後のbaselineと完全一致した。engine 0.1.5 の実行ファイルで候補 launcher を通す `tests/design-hook.bats` は13/13成功。既存管理hook、engine pin、品質floorは変更していない。

関連 `apm-runtime` / `apm-cache-refresh` / `workflow-contract` は37/37成功。`bunx tsc --noEmit` と隔離 HOME の chezmoi init / source apply --dry-run は終了0。full suite の終了結果は以下のとおり。

## 最終結果とレビュー対応

`bun run test` は726件を完走し、703 PASS・22 skip・1環境失敗で終了1。唯一の失敗は `tests/human-validation.bats` の Nix store 版 `with-env` が PATH に無いことによるもの。既存store内で、`devshell-env` と `devshell_environment.py` の双方が現在のsourceとbyte一致する `/nix/store/m23g9jsxzhyph3xbwdim4v4xsslfqkxm-with-env/bin/with-env` を確認し、そのbinをPATHに追加した同テストの再実行は1/1 PASS。テスト・実装・共有環境は変更せず、full suite自体は再実行していない。初回の非0終了を成功へ読み替えない。22 skipは既存の実機・認証・runtime opt-in境界で、実施済みとは扱わない。

全deployment ledger 1,290件の実体・hashを照合し、110件の差分はRemotion/Impeccableの配布物だけだった。非対象のownershipも不変。最終source pairと隔離検証pairはbyte一致。

Standards / Spec の独立した2 agentレビューで、通常APMとImpeccableのコミット分離、full suite終了結果の追記を指摘された。未公開履歴を整理し、通常APMのnative pairを先行コミット `3d2dff9`、そのpairをbaselineとするImpeccableだけの更新を後続コミットへ分離した。中間sourceでもAPM契約テスト15/15 PASS。最終sourceのmanifest/lock/testは全テスト時の内容を維持し、検証結果の文書だけ追記した。

証跡: `full-suite.log`、`human-validation-retry.log`、`with-env-matches.json`、`ledger-verification.json`、`ordinary-source-tests.log`。コミット時のgitleaks・format・Conventional Commits hookは成功。live source / home配布物へのapply、push・PR作成は実施していない。ツールsnapshotの更新はdaemon復旧後の検証待ちであり、スキル更新の完了と区別する。
