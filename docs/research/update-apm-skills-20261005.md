# 通常 APM payload 更新（2026-10-05）

## 更新境界

ユーザーの「マージした」により、Tool Snapshot の [PR #378](https://github.com/treflebonbon/dotfiles/pull/378) が main `a76f19b1ba2f56d00b753103415e2298ae023bd4` へ2026-10-05に merge済みと確認した。同じ native task worktree の Git 所属と clean status を検証して、この main を base とする `chore/update-apm-skills-20261005` で通常 APM の独立更新を続ける。[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md) の直列 PR／rollback 境界を守り、Tool Snapshot、Impeccable skill／engine、Matt Pocock managed set、Ponytail native plugin は本単位に含めない。

APM 0.33.0 は merge済み snapshot の package を使う。旧一括候補の lock を流用せず、Remotion だけを変更した実 manifest を空の隔離 runtime へコピーし、native `apm install --target claude,codex --https` で lock を生成した。継承の `PYTHONPATH`／`PYTHONHOME` を除き、runtime は Git 管理外かつ cache 扱いされない `/var/tmp/dotfiles-update-tools-skills-20261005/` 内に置く。live source の main は fast-forwardで merge済み commit へ同期した。

## 全20依存の採否

全 dependency の lock項目と selected payload の content hash を base と比較した。実体差分は Remotion 4.0.531 → 4.0.532のみで、[上流の比較](https://github.com/remotion-dev/skills/compare/a9b199e165505267eda1ed3e0ef3dd3567c43411...0b5db9daae40f42c73544d1cc0a8c733bd530eaa)で調査済みの inline effects と timing props の参照ファイル分離を、exact revision `0b5db9daae40f42c73544d1cc0a8c733bd530eaa` で採用する。floating dependency の再解決6件は content hash が同一のため、revisionのみを native lockへ反映する。

| 対象 | revision | selected payload |
| --- | --- | --- |
| empirical-prompt-tuning | `f1dfda26` → `62f58081` | 内容不変、revisionのみ |
| remotion-best-practices | `a9b199e1` → `0b5db9da` | 内容変更 |
| shadcn | `b0fcb58a` → `6b600cf1` | 内容不変、revisionのみ |
| computer-use | `3ab3c923` → `8b5de392` | 内容不変、revisionのみ |
| orchestration | `3ab3c923` → `8b5de392` | 内容不変、revisionのみ |
| supabase-postgres-best-practices | `544bfc56` → `c9be0e93` | 内容不変、revisionのみ |
| find-skills | `36947403` → `18f96ea1` | 内容不変、revisionのみ |

残る13依存は lock項目全体が不変。Impeccable `dc78b325`、Matt Pocock `d81f3a18`、Herdr、Orca CLI、Modern Web Guidance、security-audit の exact pinは維持する。Impeccable engineは0.1.8、公式Matt27 skillの membershipとworkflow契約も維持する。

## 確認済み検証

- native生成 → frozen install → audit が全て終了コード0。frozen前後およびsource採用時の lock SHA-256 は `f96e452aadf6041ad1fbf5301a9f88fdfc461c02a336f0ff0283ebf3bb0a6832` で不変。
- 空runtimeの20依存・1,304ファイルのSHA-256と、Claude／Codex各46スキルの一致を確認した。
- audit baselineは10/10成功。Git remoteのない隔離環境で organization policy enforcementはwarning付きskipとなり、その適合は未検証。
- 関連 `tests/apm-runtime.bats`／`tests/nix-devshell.bats` は43/43成功。型検査 `bunx tsc --noEmit` と隔離chezmoi dry-runも成功し、dry-run前後の一時HOMEは不変。非Remotionのdeployment ledgerは全項目不変。
- 本単位の最終sourceで標準 `lefthook run test` が735件中713成功・22 skip・失敗0、終了コード0で完了した。過去の一括候補の結果とは別の実行ログに記録した。
- HOMEへの配備は受入・merge後のlive sourceで行う。

## 規約軸レビュー

実装 commit `6786197` の差分を merge済み base `a76f19b` から確認し、指摘0件。隔離 native lock生成・frozen no-rewrite と Tool Snapshot merge後の独立した通常APM更新境界を守り、採否・未検証事項・配備時期を記録している。Fowler smellの指摘もなし。pin／hashの反復は成果物の整合と独立した期待値の確認に必要な重複と判断された。

## 要件軸レビュー

同じ差分の指摘0件。欠落・部分実装、未依頼のscope増大、誤った実装はなし。Remotionだけをpayload変更として固定し、内容不変のfloating6依存はrevisionのみ更新する。Impeccable／Mattなど別単位を維持し、manifest／native lock／期待値の更新範囲が一致する。

両担当はread-onlyでレビューし、標準全件が親で実行中である前提を維持した。標準全件の完了結果は親が上記へ追記し、後続コミットは検証記録のみとする。規約軸0件、要件軸0件。
