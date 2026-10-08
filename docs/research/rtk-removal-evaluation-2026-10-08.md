---
type: research
title: rtk 撤去の評価
description: rtk 0.51.0（Claude Code PreToolUse hook）の実効果・過去の問題・撤去手順を調べ、撤去 / 維持を判断する。
tags: [research, rtk, claude-code, hooks]
timestamp: 2026-10-08
---

# rtk 撤去の評価

問い: 「効果がないなら問題を起こすだけ」として rtk を撤去すべきか。凡例: **[確認]** = この session で実測・実読、**[推測]** = 部分証拠からの推論、**[未確認]** = 調べていない。

## 結論

**撤去を推奨する（確度: 中）。** 前提「効果がない」は誤りで、context 上の削減は実在する。ただし (a) 金額換算の効果は rtk 自身の試算で 0.4%、(b) 過去に実害（ADR-0060）が出ており、(c) 維持コスト（config・ADR・bats・更新 ADR での言及）が恒常的に発生する。節約が context 窓の余裕にしか効かず、その価値を repo が測っていない以上、複雑さを減らす側に倒す。context 削減を重視するなら「維持（現状のまま）」も合理的で、その場合に必要な変更は無い。

## 1. rtk の実体と主張される利点

- upstream: `https://github.com/rtk-ai/rtk`（バイナリ内文字列に `github.com/rtk-ai/rtk` を確認 [確認]。`rtk telemetry status` の data controller は RTK AI Labs）。nix 経路は `numtide/llm-agents.nix` の `llm.rtk`（`private_dot_config/nix-devshell/modules/ai.nix:113`）。実機は `/nix/store/7wnhcq87vc7z6k4n2v8hrqkwgyy114nz-rtk-0.51.0` [確認]。
- 自己説明（`rtk --help`）: "A high-performance CLI proxy designed to filter and summarize system outputs before they reach your LLM context." [確認]
- README（WebFetch 要約、https://github.com/rtk-ai/rtk）: 「一般的な dev コマンドで LLM の token 消費を 60-90% 削減」。ただし README 自身が「削減は bash 出力量であり請求額の削減ではない。input 以外に output token もあり、段階ごとに希釈される」と述べ、token 数は bytes÷4 の近似。Claude Code の組込み Read / Grep / Glob は Bash hook を通らないため書き換え対象外、と明記。撤去は `rtk init -g --uninstall`。[確認: 要約経由。原文逐語ではない]
- 仕組み: PreToolUse hook `rtk hook claude` が Bash tool の command を `rtk <subcmd> ...` へ `updatedInput` で書き換え、出力を圧縮する（ADR-0060:17 に stdin 模擬での実測あり）。

## 2. この repo での配線

全 `\brtk\b` 参照（`docs/research/` と更新履歴 ADR を除く）:

| 場所 | 内容 |
| --- | --- |
| `private_dot_claude/settings.json.tmpl:125-131` | `PreToolUse` の 2 つ目 entry（matcher `Bash`、`rtk hook claude`）。初期 commit `4c91e11` から存在 |
| `private_dot_config/rtk/config.toml` | `[hooks] exclude_commands = ["git"]`（ADR-0060 の回避策） |
| `private_dot_config/nix-devshell/modules/ai.nix:112-113` | `# --- Token Optimization ---` / `llm.rtk` |
| `tests/codex-config.bats:954-957` | `data["hooks"]["PreToolUse"][1:] == [ ...rtk hook claude... ]` を assert |
| `README.md:33` | AI 行に `rtk` |
| `runtime/ai-runtimes.md:15, 177` | 「ワークフロー: rtk, herdr」「claude-code / codex / copilot-cli / rtk 等」 |
| `runtime/ai-runtimes.md` 200 行目以降の日付付き更新記録、ADR-0033/0035/0036/0043/0045/0063/0064/0067-0069、`docs/research/llm-agents-and-apm-update-*.md` | rtk の version 追従の歴史記録。編集不要（履歴） |
| `docs/adr/0060-rtk-exclude-git-from-hook.md` | 過去の決定（status: accepted） |

`runtime/shell-environment.md`、`runtime/skill-harness.md`、`flake.lock`、`docs/architecture.md` には rtk の記述は無い [確認: grep]。

### 過去の問題（ADR-0060、2026-09-15、PR #321）

- `EnterWorktree` 隔離中、`git status` まで "this command runs rtk with a git command among its operands ... cannot be shown not to be git" で一律拒否された。原因は hook が `git ...` を `rtk git ...` に書き換え、Claude Code の隔離境界チェックが launcher `rtk` を透過できず fail-closed したこと（ADR-0060:12-19）。
- 対処は `exclude_commands = ["git"]`。ADR-0060 は「hook 自体を撤去」を「find/grep/diff の節約を失う」ため見送り、「Claude Code の対応を待つ」も見送った（:31-32）。
- 副次: 隔離していない時の `git status` が圧縮形式（`* branch` / `clean —`）になる＝出力が標準と変わることを同 ADR が直接証拠として記録している（:19）。

## 3. この機械での実測（read-only、すべて [確認]）

`rtk gain`（Global）: 6411 commands、入力 7.6M → 出力 2.8M、**4.8M token 節約（63.1%）**。期間 2026-07〜10（月別: 07 は 39.5%、09 は 76.0%）。

| コマンド                         | 回数 | 節約 | 率    |
| -------------------------------- | ---- | ---- | ----- |
| `rtk read`（`cat` 系の書き換え） | 643  | 2.6M | 84.9% |
| `rtk grep`                       | 1847 | 1.3M | 59.6% |
| `rtk find`                       | 415  | 414K | 93.8% |
| `rtk diff`                       | 22   | 174K | 96.4% |

節約の大半は 4 コマンドに集中。git の節約は除外後は 0 件に近い（旧 `git diff`/`git branch` が履歴に残る）。

**金額換算**: `rtk cc-economics` は ccusage の総支出 $5066.30（cache read 8676M token）に対し、**推定節約 $18.28（0.4%）**と自己申告している。cache read が 0.1 倍課金のため、input 圧縮は請求にほとんど効かない [確認: rtk 自身の試算。方法論は推測を含む]。効果は主に context 窓の占有削減であり、その価値（長 session の compaction 回数など）は未計測 [未確認]。

**問題の兆候**:

- `rtk gain -F`: parse failure 192 件、recovery rate 100%（raw 実行へ fallback。出力は壊れていない）。多くは `shellcheck`、`mix`、`jq`、`ps aux`。fallback は「rtk が効かない」だけで害ではない [確認]。
- `rtk gain --recalls`: elision（出力を省略した件数）が `ls-hidden` 81、`grep` 65、`find-hidden` 41、`find` 17 に対し、agent が `rtk recall` で取りに戻った件数は全 filter で 0 [確認]。「agent が省略に困って再取得した」兆候は無い。ただし 0 件は「困らなかった」ことを保証せず、省略に気づかず誤判断した可能性は検出できない [推測]。
- `rtk verify`: hook 登録 PASS、151/151 tests PASS。壊れた hook は無い [確認]。
- `rtk discover`（30 日）: 3716 Bash commands のうち rtk 経由 855（23.0%）。git 除外の影響で `git diff` 407 件（~178K token）が取りこぼし扱い。
- telemetry: 未同意・無効、「this build has no telemetry endpoint」 [確認]。
- 副作用: `~/.local/share/rtk/{history.db 8.5M, recall.db, tee/}` にコマンド履歴を蓄積する（`~/.config/rtk/` は config のみ 8K）。コマンド文字列に secret が混ざれば history.db に残り得る [推測]。

## 4. Claude Code の hook 意味論（https://code.claude.com/docs/en/hooks、WebFetch 要約）

- `hookSpecificOutput.updatedInput` で tool 入力が置換され、その後に通常の permission flow が走る。permission rule（`Bash(git push-topic:*)` 等の allow/deny）は**書き換え後**の command に対して評価される。したがって `rtk <cmd>` へ書き換えられると allow 規則の前方一致が変わる危険がある。この repo は多数の `Bash(...)` allow/deny を持つ（`tests/codex-config.bats` 960 行以降）。rtk が実際にどの許可を取りこぼした/通したかは未検証 [未確認]。
- 同一 event・同一 matcher の hook は**並列実行**で、各 hook は元の入力を受け取り、`updatedInput` が衝突すると 1 つだけ勝つ（順序は未規定）。この repo には `devshell-env claude-hook` と `rtk hook claude` の 2 つが `Bash` に付いているが、`private_dot_local` 内に `updatedInput` は存在せず [確認: grep]、現状衝突はしない。devshell-env が将来 command を書き換えると rtk と競合する構造的リスクはある [推測]。
- 失敗時: exit 0 かつ不正 JSON、または JSON 無しの非 2 終了は「非 blocking error、元の command で続行」。timeout も続行。つまり rtk が壊れても fail-open で、tool が止まることは無い。止まったのは rtk の失敗ではなく ADR-0060 の隔離境界チェック側（fail-closed）だった。
- 要約経由のため細部（timeout 既定値の記述など）は不正確な可能性があり、厳密に使う前に原文確認が要る [未確認]。

## 5. 完全撤去に必要な変更

実装は task worktree で行い、live source から `chezmoi apply` は受入後（`CLAUDE.md`）。

編集:

1. `private_dot_claude/settings.json.tmpl`: 125-131 行の rtk entry（`{"matcher": "Bash", "hooks": [{"command": "rtk hook claude"}]}`）を削除し、直前の entry の末尾カンマを整える。`PreToolUse` は `devshell-env claude-hook` の 1 件だけになる。
2. `tests/codex-config.bats:954-957`: `assert data["hooks"]["PreToolUse"][1:] == [...]` を `assert len(data["hooks"]["PreToolUse"]) == 1` 等へ置換（または 4 行削除し、1 件目の既存 assert があるか確認）。影響する bats はこの 1 件のみ [確認: `rtk` を tests 配下で grep、他は無し]。`tests/ai-quality-floor.bats` と `ai.nix` の quality floor は rtk 非対象（ADR-0035:31）。
3. `private_dot_config/nix-devshell/modules/ai.nix:112-113`: コメントと `llm.rtk` を削除（`llm` 変数の他用途は残る）。
4. `git rm private_dot_config/rtk/config.toml`（`chezmoi` の `private_dot_config/rtk/` ディレクトリごと消える）。
5. `README.md:33`: AI 行から `rtk` を削除。
6. `runtime/ai-runtimes.md:15`（「ワークフロー: rtk, herdr」→「herdr」）と `:177`（「rtk 等」から rtk を除く）。200 行目以降の日付付き記録は履歴なので触らない。
7. 検証: `nix flake check --no-build --all-systems`（3 system）、`bats tests/codex-config.bats`、`python3 -m json.tool` で settings.json.tmpl 相当の JSON を確認、`grep -rnw rtk` で残存確認（履歴 ADR / research / ai-runtimes の日付記録のみ残るのが正）。

ADR（`docs/adr/` は決定記録、`docs/adr/0028` と `0003` の前例どおり、古い ADR は status と冒頭注記だけ最小限で更新し本文は保持する）:

- 新規 ADR（次番号は **0072**。現最大は 0071 [確認]）: 「rtk を撤去する」。内容は、ADR-0060 が選ばなかった「hook 自体の撤去」を、実測（0.4% の金額効果、recall 0 件、git 除外後の追加回避策の必要性）を根拠に採る決定。Consequences に context 削減（Bash 出力で約 63%）を失う点を明記。
- `docs/adr/0060-rtk-exclude-git-from-hook.md`: frontmatter を `status: superseded` にし、ADR-0028 と同形式の注記「ADR-0072 により撤去、以下は当時の判断記録として保持」を 1 行追加。それ以外は不変。
- 規約の根拠は `docs/conventions.md`（tool 追加先の判断は `docs/architecture.md` の devShell 節）。`docs/architecture.md` に rtk 記述は無く変更不要。

配備後の掃除（chezmoi apply 後。いずれも破壊的なので承認を取ってから実行）:

- `chezmoi apply` は source から消えた `~/.config/rtk/config.toml` を**自動では削除しない**ため、`rm -r ~/.config/rtk`（8K）が必要 [推測: chezmoi の既定動作。`.chezmoiremove` を使えば宣言的に消せる]。
- `~/.local/share/rtk/`（9.1M、command 履歴 DB と tee ログ）は chezmoi 管理外。履歴を捨ててよければ削除（不可逆）。
- `~/.claude/settings.json` は apply で再生成される。`~/.claude/RTK.md` は存在しない [確認]。他 repo の project-level `.claude/settings.json` に rtk hook が無いかは未確認 [未確認]。
- 実行中の Claude Code session は settings 再読込のため再起動が要る。nix devshell から rtk が外れるのは次回の devShell 再評価後。

## 判断

- 維持の根拠: context 占有を約 63% 圧縮（4.8M token）、hook は fail-open、現在の既知の実害は ADR-0060 の 1 件で回避済み、recall 0 件。
- 撤去の根拠: 金額効果 0.4%（rtk 自身の試算）、Claude 組込み Read / Grep は対象外で効果範囲が狭い、既に 1 回 fail-closed の事故と回避 config・ADR・bats の複雑さを生んだ、Claude Code の安全境界は今後 launcher 書き換えと衝突し得る（hook は `updatedInput` 後の command を検査するため）、出力改変（elision）は気づかれない誤判断の余地を残す、全 llm-agents 更新で version 追従の記録コストが発生する。
- 推奨: **撤去**。理由は「測れる利益が小さく、測れない（検出不能な）リスクと維持コストが残る」非対称性。もし context 窓の節約を主目的として維持するなら、現状（git 除外済み）のままで十分で、追加変更は不要。
