---
type: decision
title: impeccable の pin を前進させ、同時に Stop deep pass を両経路へ配線する
description: pbakaus/impeccable を 4d849eb7 から 1cf7d7ab へ進める。新 runtime は per-edit を immediate tier に縮小し残りを Stop イベントへ移すため、PostToolUse のみの現配線では検出カバレッジが落ちる。pin 前進と Stop 配線を分割せず一つの変更として扱う
tags: [adr, impeccable, hooks, apm, claude-code, codex, design-detector]
timestamp: 2026-07-28
status: accepted
---

# impeccable の pin を前進させ、同時に Stop deep pass を両経路へ配線する

## Context

2026-07-28 の定期メンテ（Issue #118）で APM 経路の skill を最新へ解決し直した際、`pbakaus/impeccable`
だけは `4d849eb75f216109ea7053ed21530a11fafcc786` に据え置いた。この repo は次の 2 経路から impeccable
の同梱 hook runtime を **自動実行** しており、pin を進めると自動実行される中身が丸ごと入れ替わるためである。

- `private_dot_claude/settings.json.tmpl` — user-global `PostToolUse` の quiet な Impeccable Design Hook
- `private_dot_config/codex/hooks.json` — managed hooks.json が共有ハブの runtime を quiet な `PostToolUse` で呼ぶ

Issue #117 としてこの影響判定を切り出した。以下はその結果である。

### 差分の規模

`4d849eb7..1cf7d7ab` は repo 全体で 324 commits。APM が実際に取得する `.agents/skills/impeccable/`
subtree に限ると 74 commits / 88 files / +13830 -3563。skill version は 3.9.1 → 4.0.3。
Issue #117 本文の「250 commits」は測り直した結果 324 が正しい。

### 現配線が依存している契約点

両経路とも同一形状の fail-open ラッパーである。依存しているのは次の 6 点で、すべて維持されていた。

| 契約点                                  | 1cf7d7ab での状態                                                                                                                                            |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `scripts/hook.mjs` が同じ相対パスに在る | 維持（改名・移動なし）                                                                                                                                       |
| stdin から JSON イベントを読む          | 維持。`hook.mjs` は依然 thin な stdin/stdout adapter                                                                                                         |
| 終了コードは常に 0                      | 維持。`hook-lib.mjs` 内の `exitCode` は全経路 0（`runStopHook` も同じ result 契約）、`hook.mjs` の docblock も "Contract: never break a turn. Always exit 0" |
| `IMPECCABLE_HOOK_QUIET=1` が効く        | 維持。`reference/hooks.md` が legacy env var 3 種を "still honored" と明記                                                                                   |
| stdout はそのまま呼び出し元へ渡される   | 維持。出力は `hookSpecificOutput.additionalContext` のみで、`decision` / `permissionDecision` などブロッキング用キーは存在しない                             |
| `timeout: 5` に収まる                   | 維持。per-edit は実測 59ms（旧 69ms）で、むしろ速い                                                                                                          |

Node の engine 要求も `>=22.12.0` で据え置き（devshell は 24.15.0）。hook 経路が import する
`context.mjs` の `loadContext` は同期関数のままで、更新チェックの `fetch` には両 pin とも到達しない。

### 唯一の実質的な挙動変更 — 検出ルールの二層化

新 runtime は検出ルールを二層に分けた。per-edit の `PostToolUse` は `IMMEDIATE_TIER_RULES`
（broken-image / low-contrast / gradient-text / design-system-\* など 13 ルール）だけを出し、
残り（コピーの調子、パレットや字組みの趣味、レイアウトの律動）は **`Stop` イベントの deep pass** へ
先送りする。既定は `perEditRules: 'immediate'`、かつ `perEditTieringActive()` は claude / codex に対して
真を返す。**当 repo の配線は 2 経路とも `PostToolUse` しか登録していないため、先送りされた層は誰にも
拾われず消える。**

隔離 HOME で両 pin を現配線のまま実行して実測した。

- UI fixture 1 件: 旧 3 findings → 新 2 findings。`ai-color-palette` が脱落
- `tests/design-hook.bats` は **4 件中 2 件が fail**（`overused-font` が immediate tier 外のため、
  quiet モードでは出力が完全に空になり `hookEventName` すら出ない）

つまり pin だけを進めると、壊れはしないが検出範囲が静かに狭まり、この repo 自身の挙動テストが落ちる。

### Stop を配線した場合

同じ隔離環境で `Stop` イベントを流すと、先送りされた findings がちょうど回収された
（fixture の `ai-color-palette`、bats fixture の `overused-font` とも復元）。運用コストも小さい。

- `.impeccable/` を持たない repo での Stop: 53ms / 出力 0 byte（user-global 配線でも安い）
- 20 ファイル（`STOP_MAX_FILES` の上限）を触ったセッションの Stop: 69ms、20 ファイル全てを走査
- `stop_hook_active === true` のとき即座に無出力で抜けるガードがあり、Claude Code の Stop ループは起きない

上流が install する manifest は `matcher` を持たず、`timeout: 30`、`statusMessage: "Design deep pass"`。

### トリガー競合

`SKILL.md` の `description` frontmatter は両 pin で **byte 単位で同一**（sha256 一致）。skill の発火面は
まったく変わらないため、`ui-grill-with-docs` をはじめ他 skill との競合は新たに生じない。
`ui-grill-with-docs` は impeccable を名前で 1 行参照しているだけでファイルパス依存はなく、削除・改名された
`reference/{brand,codex,interaction-design}.md` / `product.md`→`operate.md` への参照も repo 内に存在しない。

### 副作用

キャッシュの永続化条件に `deferredTotal > 0` が加わり、opt-in していない repo でも UI ファイルを編集すると
`.impeccable/hook.cache.json` が作られるようになった。書き込み時に `.git/info/exclude` へ除外パターンが
入るため git は汚れないが、user-global 配線ゆえ「編集しただけの無関係な repo にディレクトリが増える」点は
上流の project-local install 前提とはずれる。Stop を配線すればこのキャッシュは実際に読まれるので、
配線とセットなら無駄ではなくなる。

## Decision

**pin を `1cf7d7ab` へ進める。ただし pin 前進と Stop deep pass の配線を分割せず、一つの変更として行う。**
実作業は Issue #119 に起票した。

- `apm.yml` の `pbakaus/impeccable` を `1cf7d7ab` へ更新し、lockfile を
  [skill-harness](../../runtime/skill-harness.md) の手順（隔離ディレクトリでの `apm install`）で再生成する
- `private_dot_claude/settings.json.tmpl` と `private_dot_config/codex/hooks.json` の両方に、既存の
  `PostToolUse` と同じ fail-open ラッパー形状で `Stop` エントリを足す。`Stop` に `matcher` は付けず、
  timeout は上流に合わせて 30 とする
- `tests/design-hook.bats` を二層化後の契約に合わせる。per-edit は immediate tier のルールで表明し、
  先送り層は Stop イベントで回収されることを表明する。`tests/apm-runtime.bats` と
  `tests/codex-config.bats` の該当箇所も追従させる

**pin だけを進めることは禁止する。** 上の実測どおり、それは検出カバレッジの純減であり、
この repo の挙動テストが落ちる状態を招く。

代替案として project の `.impeccable/config.json` に `hook.perEditRules: "all"` を置けば旧挙動へ戻せる
（実測で 3 findings に復元することを確認済み）が、この設定は project scope であり、当 repo の配線は
user-global である。全 repo に config を撒くことになるので採らない。

## Consequences

- 上流が二層化の閾値（`IMMEDIATE_TIER_RULES` の中身）を動かすと、per-edit で出る findings が変わる。
  `tests/design-hook.bats` はこの集合に依存するので、pin を動かすたびに同テストの結果を確認する
- Codex 側は `Stop` hook の初回に `/hooks` での承認が要る可能性がある（上流ドキュメントが PostToolUse に
  ついて同様の注意を書いている）。配線後に実機で承認フローを確認する
- `.impeccable/hook.cache.json` が今より多くの repo に作られる。git は `.git/info/exclude` で保護されるが、
  ディスク上には残る
