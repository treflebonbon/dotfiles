# Issue #243: 通常 APM payload 更新

## Contract と baseline

[Issue #243](https://github.com/treflebonbon/dotfiles/issues/243) の第2単位。第1単位の [PR #244](https://github.com/treflebonbon/dotfiles/pull/244) が2026-09-08に merge された `c94ecc8c86efda32198e74000c32b8ab613cdac8` から、validated linked worktree の同じ checkout で branch `chore-ai-apm-payloads` を開始した。

本単位は通常スキルの選定・配備・再現性を扱う。Tool Snapshot、品質 floor、モデル設定、Impeccable 4.1.2、Matt Pocock の pin / selected payload を維持する。Impeccable 4.2.2 / engine 0.1.3 は本単位の merge 後に第3単位として実装する。Issue 全体の完了や live 配備は本単位の完了条件に含めない。

検証境界は Issue の Testing Decisions で合意済みの「APM の隔離配備」。既存 APM テストの期待 pin を先に更新した red は、旧 Modern Web Guidance pin に対して失敗した。

## 選定した payload

| 依存                              | baseline revision | 採用 revision                              | 配備対象の差分                                                |
| --------------------------------- | ----------------- | ------------------------------------------ | ------------------------------------------------------------- |
| Modern Web Guidance               | `56c61c9e`        | `bfd8c8dded770f3ba07a518e28991a32df40f902` | 本文・資料を更新。exact pin                                   |
| Remotion                          | `357a2708`        | `11986e44eeb672b083354e68967f2b194df73b7c` | 配備対象13ファイルの版参照のみ。exact pin                     |
| Orca CLI                          | `b44ef1e5`        | `de0a91b99fc845c9510340786f807ea1c988859b` | discovery stub / fallback guidance を更新。exact pin          |
| Orca computer-use / orchestration | `af821260`        | `1a8640adb6e86abb342a8025892300b2835f3e8e` | 候補 `de0a91b9` と同じ selected subtree。既存の floating 解決 |
| Shadcn                            | `7c9eaba1`        | `5c7072da672b0048bc6771e3204063a2537df91a` | content / 全配備 hash 不変。floating の revision-only         |
| find-skills                       | `435076e7`        | `1682051d48c34f5eb135e6475c1a965dce05e820` | content / 全配備 hash 不変。floating の revision-only         |

[Modern Web Guidance の公式差分](https://github.com/GoogleChrome/modern-web-guidance/compare/56c61c9ee79a8df1a98822309c04847a57f56000...bfd8c8dded770f3ba07a518e28991a32df40f902) は progress ring / scrollspy / spinner の3資料、layout の overflow による問題隠蔽を避ける説明、cache directive の説明を追加する。SKILL.md は `--skill-version` と、network approval が必要な環境・npm cache が書込み不能な環境への条件付き guidance を更新する。

このセッションは filesystem 制限なし・network 有効・approval policy `never` であり、条件付き guidance だけを理由に承認フローを増やさない。外部 skill は system / developer 指示と repository の Worktree Entry Point・公開権限を上書きしない。配布物やローカル指示への追加 patch は不要である。

[Remotion の公式比較](https://github.com/remotion-dev/skills/compare/357a270803b23e16b32bec65df07c41a62e94bd9...11986e44eeb672b083354e68967f2b194df73b7c) には他の standalone skill の本文変更もあるが、配備する `skills/remotion-best-practices/` は `version: 4.0.519` → `4.0.522` だけ。13ファイルすべてについて、この置換を除けば baseline と byte 一致することを確認した。配備しない sibling skill の改善を本更新の効果とは扱わない。

[Orca 候補](https://github.com/stablyai/orca/tree/de0a91b99fc845c9510340786f807ea1c988859b/skills) は3スキルの stub を簡潔にし、未記載の command を `--help` から調べる手順と、古い CLI の fallback を整理する。orchestration は追加資料の個別取得と、`--reference` 非対応時の `--full` を案内する。GitHub compare は300ファイルで打ち切られるため、selected path が表示されないことを差分なしの根拠にしていない。native install の Git cache に対する `git ls-tree` で、候補 `de0a91b9` と自然解決 `1a8640ad` の3 subtree hash が完全一致することを確認した。

全18依存を比較し、上記以外の revision / selected payload は不変。Impeccable は dependency block と全配備 ledger が完全不変。Matt は exact revision `6654f6b60cd9d5be8b54c6fafe44346dabeb3b76`、content hash `sha256:22de78eb0eca8ad3f1830f955999ff588650e1f6bbb1f436236eff4fb0296eda`、25スキル、全配備ファイル・hash・owner が不変である。APM 0.30.0 が生成する Matt の `package_type` だけが `marketplace_plugin` → `apm_package` になった。native metadata の再分類であり、workflow migration や native plugin installer への経路変更ではない。既存テストは分類文字列に代えて、維持すべき pin / selected content hash と25スキルを確認する。

## Native materialization と discovery

Nix の採用済み APM `/nix/store/hshrxdwp5vwjh13kyljg25z1kpzzaaia-apm-0.30.0/bin/apm` を使用した。既存シェルの `PYTHONPATH` には APM 0.29.0 が含まれ、binary の絶対 path だけでは旧 module が優先された。検証プロセスの `PYTHONPATH` / `PYTHONHOME` を除去し、専用 HOME / XDG / CODEX_HOME を設定して `apm --version` が実際に0.30.0となることを先に確認した。live の環境変数や設定は変更していない。

`tmp/issue-243-apm/runtime/` を cwd と HOME にして、最終 `apm.yml` だけをコピーした新規 layout で次を実行した。一時 pin や既存 lock を生成入力にしていない。

```sh
apm install --target claude,codex --https
apm install --frozen --target claude,codex --https
apm audit --ci
```

3コマンドとも終了0。native install 後・frozen 後・audit 後の lock SHA-256 はすべて `1b39cba0a658527f7068dc4a48d0c9a296de6ed1114edefe6e549d681ae81c6c`。この生成物をそのまま source にコピーした。APM 0.30.0 の native 出力では旧 `generated_at` がなくなるが、配備 ledger / hash は含まれる。lock の手編集・formatter 処理は行っていない。

Audit は10/10、driftなし。organization policy は `treflebonbon/.github-private` が見つからないため enforcement を skip したという warning があり、組織 policy 取得成功・適合とは扱わない。13件の unpinned 警告は既存 floating 宣言の結果であり、manifest の exact pin と lock の `resolved_ref` が一致することを別途テストした。

`.agents/skills/` と `.claude/skills/` の42/42 directory を baseline と照合し、各 `SKILL.md` の name / description と全ファイルの target 間 byte 一致を確認した。全18依存の1,396ファイルを SHA-256 計算し、dependency hash と1,480件の配備 ledger の該当 hash に照合した。Matt25、specialist skill、現 Impeccable launcher、Modern Web Guidance の追加3資料、Remotion の参照資料も両 target に揃う。これは隔離した discovery location / payload の検証であり、live agent session への再読込の確認ではない。

## Orca の実行時ガイド

セッション指定の executable `orca-ide` を固定し、`status --json` が app version `1.4.197` / runtime `ready` を返すことを確認した。`skills get orca-cli`、`skills get computer-use`、`skills get orchestration` はすべて成功した。新しい stub に書かれた `--references` はこの CLI では unknown flag となるが、案内された互換経路の `skills get orchestration --full` は成功し、実行中版の全ガイドを返す。新しい参考資料名をこの旧版に推測で渡さない。

Orca が返す worktree 操作例は command surface の説明として扱い、Orca native worktree / Agent Picker が所有する入口契約を維持する。新しい worktree 作成・worker dispatch・desktop 操作・外部送信を、この read-only なガイド検証のために実行していない。

## Verification Matrix

証跡は同じ worktree の `tmp/issue-243-apm/`。恒久的なログ保管先ではなく、ここには採用結果と限界を記録する。第1単位の結果は [Tool Snapshot 記録](ai-tool-snapshot-243.md) を参照する。

| AC                    | 確認方法・証跡                                                            | 本単位の結果                            | 未確認・後続                                |
| --------------------- | ------------------------------------------------------------------------- | --------------------------------------- | ------------------------------------------- |
| AC1 更新単位          | PR #244 の merge commit と branch base                                    | 第2単位を merge 済み baseline から開始  | 第3単位は本単位の merge 後                  |
| AC2 snapshot          | Nix source / lock 不変、第1単位記録                                       | 第1単位の採用値を維持                   | 再選定しない                                |
| AC3 対応環境          | 第1単位の3 system / 両 shell 評価・host build                             | 第1単位の検証を継承                     | ARM 実機起動の未確認も継承                  |
| AC4 floor / 設定      | floor / モデル設定不変、full suite                                        | 維持                                    | —                                           |
| AC5 Herdr             | package / 設定不変、第1単位記録                                           | 第1単位の検証を継承                     | 画像の実描画等の未確認も継承                |
| AC6 スキル選定        | `comparison.json`、公式比較、実体差分、Orca tree hash                     | 成功。本文・版参照・revision-onlyを区別 | 配備外の sibling 本文変更は含めない         |
| AC7 再現性            | `materialization.json`、install / frozen / audit logs、source `sha256sum` | 成功。native lock不変、audit 10/10      | organization policy enforcement は skip     |
| AC8 可視性            | `payload-verification.json`、1,396 hash / 全 target 照合                  | 成功。42/42、Matt25、Impeccable維持     | live session discovery は最終配備時         |
| AC9 Orca              | 3 `skills get`、`status --json`、`--full`、実効契約の照合                 | 成功                                    | 新 `--references` は実行中1.4.197では非対応 |
| AC10 Impeccable 配布  | 現 pin / launcher / 管理設定を維持                                        | 第3単位                                 | skill4.2.2 / engine0.1.3 は未導入           |
| AC11 global hook      | 現 global PostToolUse / Stop を維持                                       | 第3単位                                 | 新 engine による確認は後続                  |
| AC12 hook 動作        | 現4.1.2 materialized runtimeで既存テスト                                  | 現構成の回帰確認                        | 新 engine の互換性を意味しない              |
| AC13 fail-open / 所有 | 管理 hook / timeout / 所有境界を維持                                      | 現構成の回帰確認                        | 新 engine の障害検証は後続                  |
| AC14 実 engine        | 現4.1.2実体をfull suiteへ指定                                             | 第3単位                                 | Rust engine移行の成功とは扱わない           |
| AC15 回帰             | 関連Bats、full suite、型検査、format、code-review                         | 検証中                                  | 完了時に結果を追記                          |
| AC16 配備境界         | linked checkout確認、live source非変更                                    | source側を遵守                          | live apply / 最終起動は受入後               |
