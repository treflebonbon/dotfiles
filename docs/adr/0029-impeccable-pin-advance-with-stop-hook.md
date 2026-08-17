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
`ui-grill-with-docs` は impeccable を名前で 1 行参照しているだけでファイルパス依存はない。
削除・改名された `reference/{brand,codex,interaction-design}.md` / `product.md`→`operate.md` を参照している
repo 内のファイルは `apm.lock.yaml` だけで、これは現 pin の配備ファイル一覧という生成物なので lock 再生成で
解消する。手で保守しているドキュメント・設定側にこれらのパスへの依存は無い。

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

## 補足（2026-07-28、Issue #119 の実装時）

実際に配線して実機確認したところ、判定時には見えていなかった事実が 2 つ出た。

**1. deep pass は「1 度だけ」ではない。** 1 つのファイルが immediate と deferred の両方の finding を
持つ間、`Stop` はターン終端ごとに 2 つを**交互に**報告し続ける。`rememberFindings()` が記憶済みキーを
置換する実装である一方 `runStopHook` は fresh 分しか渡さないため、deferred を報告した時点で per-edit が
覚えていた immediate 側が追い出され、次の `Stop` で再び新規に見える。immediate 側を直せば層が 1 つに
なり収束する。上流のコード内コメント（"the next Stop fire is silent unless new issues appear"）とは逆の
挙動なので、上流側の不具合と判断した。

これを受けて **`tests/design-hook.bats` は上流の意図ではなく実挙動のほうを固定する**と決めた。意図を
書くとテストが「あるべき姿の願望」になり実際には落ちないが、実挙動を固定しておけば上流が eviction を
直した回にテストが落ちて気づける。テストにはその旨と直ったときの置き換え方をコメントで残す。この不具合を
理由に pin を戻すことはしない — 配線しなければ deferred 層が丸ごと届かないので、交互報告のほうが軽い。

**2. Codex の hook trust は entry 単位。** 上の Consequences では「`/hooks` 承認が要る可能性がある」と
書いたが、実機で確定した。`config.toml` の `[hooks.state]` に `"<hooks.json path>:<event>:<idx>:<idx>"` を
キーとした `trusted_hash` が積まれ、未登録の entry は "New hook - review required" になる。`hooks.json` に
event を足した回は Codex 側で一度承認するまでその hook は走らない。なお `Stop` は codex-cli 0.145.0 が
native に持つイベントで（`codex_hooks::schema::StopCommandOutputWire` が存在）、上流 impeccable 自身の
`.codex/hooks.json` も同じ形で `Stop` を出している。上流 README は hook を project-local に置く手順を
案内しているが、当 repo の user-global 配線も実際に読まれている（`~/.codex/config.toml` の
`[hooks.state]` に `"/home/ubuntu/.codex/hooks.json:post_tool_use:0:0"` の trust が積まれている）。

## 補足（2026-07-31、Issue #130 の更新時）

Impeccable の実装開始時点の HEAD `32930818a109fafa87199babe92fa8e530cff5d3`（4.0.4）を更新候補とし、
APM 0.26.0 が隔離 HOME に materialize した runtime を JSON event interface から直接検証した。per-edit の
immediate finding、clean / non-UI / sensitive / generated の無言成功、Stop での deferred finding、dedupe、
edit threshold、Stop re-entry を含む `tests/design-hook.bats` は 7/7 で通過した。未配備・内部失敗時の
fail-soft は `tests/codex-config.bats` の managed hook fail-open テストで別途確認した。したがってこの
revision を新しい検証済み Skill Pin として採用し、Claude Code / Codex の配線は変更しない。

テスト fixture には project marker として空の `package.json` を置くよう修正した。上流 runtime は marker が
ない場合に祖先の `.impeccable` を project root として選べるため、隔離テストの外にある `/tmp/.impeccable`
を拾って per-edit と Stop の cache root が分裂していた。これは hook 契約の変更ではなく、fixture が project
境界を決定論的に表していなかった問題の修正である。

`1cf7d7ab..32930818` の selected subtree は 67 files / +7323 -1639 で、主な変更は Live v2、framework
adapter、検出器、Impeccable 4.0.4 への更新である。hook entrypoint `scripts/hook.mjs` は不変で、
`hook-lib.mjs` の hook 関連差分は Google Fonts label の ignore 値抽出追加だけだった。既知の both-tiers Stop
交互報告 defect はこの revision にも残っているため、上流の意図へ書き換えず characterization test を維持する。
後続更新でも、pin の前進は同じ Design Hook 互換性ゲートを通過した場合に限る。

## 補足（2026-08-06 の更新時）

Impeccable HEAD `a075d89bdbe60b2b00220cb0527fb5091e84215e`（4.0.4）を APM 0.28.0 の隔離 runtime layout に materialize し、同じ JSON event interface で再検証した。quiet / immediate tier / Stop deep pass / dedupe / edit threshold / sensitive・generated path filter / Stop re-entry の 7/7 と managed hook の fail-open 契約を維持したため、新しい検証済み Skill Pin として採用した。

既知の both-tiers Stop 交互報告 defect はこの revision にも残っており、characterization test は変更しない。Claude Code / Codex の hook 配線にも変更はない。

## 補足（2026-08-15 の更新時）

Impeccable `5a149f3fdb1b5793f10567233b1dcab98fc305fd`（4.1.1）を APM 0.28.0 の隔離 runtime layout に materialize した。従来の二層 hook 契約に加え、finding policy の full footer を session 内の初回だけ表示し、2回目以降は short footer にする契約をテストへ追加した。`tests/design-hook.bats` は候補 runtime で 9/9、managed hook の fail-open test も通過した。既知の both-tiers Stop 交互報告 defect は残るため characterization test を維持し、hook 配線も変更しない。

4.1.1 の full footer は、確信のある false positive または明示的に許容された例外に限って agent 自身が `ignore-value` を実行できると案内する。この narrow suppression は可逆かつ finding 単位なので許容するが、根拠をユーザーへ開示する。test は `--reason` を持つ1 finding valueだけが `detector.ignoreValues` へ保存され、hook / file / rule 全体を抑制しないことまで確認する。file / rule 全体を隠す `ignore-file` / `ignore-rule` は従来どおりユーザーの明示承認を必要とする。採用判断は [ADR-0036](0036-update-llm-agents-and-validated-skill-pins.md) を参照する。

## 補足（2026-08-18 の更新時）

Impeccable `5c5553b1d7f9e89bb833f9179cea681742a17720`をAPM 0.28.0の隔離runtimeにmaterializeした。`hook.mjs` / `hook-lib.mjs`、footer policy、`hook-admin.mjs`のblobは前pinと同一で、変更されたstatic HTML selectorのcompile cacheも既存契約を変えない。候補runtimeに対して`tests/design-hook.bats` 9/9、managed hook fail-open 1/1が通過したため、新しい検証済みpinとして採用する。

Claude Code / CodexのPostToolUse + Stop配線、timeout、理由付き`ignore-value`と明示承認が必要な`ignore-file` / `ignore-rule`の境界は変更しない。既知のboth-tiers Stop交互報告も残るためcharacterization testを維持する。採用判断は [ADR-0037](0037-update-llm-agents-and-compatible-skill-pins.md) を参照する。

関連: [ai-runtimes](../../runtime/ai-runtimes.md) / [skill-harness](../../runtime/skill-harness.md) / [issue #117](https://github.com/treflebonbon/dotfiles/issues/117) / [issue #119](https://github.com/treflebonbon/dotfiles/issues/119) / [PR #118](https://github.com/treflebonbon/dotfiles/pull/118)
