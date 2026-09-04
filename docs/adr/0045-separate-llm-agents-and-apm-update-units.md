---
type: decision
title: llm-agents と APM skill の更新を四つの更新単位に分ける
description: snapshot、通常の skill payload、Design Hook、Matt Pocock workflow を個別の互換性ゲートと rollback 境界で更新する
tags: [adr, nix, llm-agents, apm, skills, impeccable, matt-pocock]
timestamp: 2026-08-27
status: accepted
---

# llm-agents と APM skill の更新を四つの更新単位に分ける

2026-08-27 の更新では、導入済み AI ツールセットと導入済み Agent Skill セットの全 dependency を調査対象にする。ただし、互換性ゲートと rollback 境界が異なる変更を一括採用せず、次の四つの更新単位へ分ける。

## Decision

1. **llm-agents snapshot**: 実装 phase の入口で upstream stable/default branch HEAD を一度だけ再確認し、pre-release を除外した exact revision に固定する。特定 release の収録を待ち続けない。調査時点の候補は `4a9441120caf6c6aff273af68995267a35c20fcd` で、code-review-graph 2.3.8 に合わせて local package override も同じ単位で更新する。Claude Code の品質 floor は `2.1.247`、Codex の品質 floor は `0.150.0` へ引き上げる。
2. **通常の APM payload refresh**: 全 dependency の selected subtree を比較し、実体差分のある Modern Web Guidance と Remotion を候補にする。floating dependency は隔離 lock 生成時に再解決し、revision だけが進んで payload が同じ変更は個別の採用理由にしない。selected subtree が同一の exact pin は動かさない。
3. **Impeccable**: 4.1.2 payload を独立した検証済み Skill Pin の候補とし、Codex Stop protocol、finding cache、monorepo/symlink root、fail-soft の挙動を含む Design Hook 互換性ゲートが通った場合だけ採用する。候補は Codex Stop を top-level の `decision` / `reason` で返すため、旧 `hookSpecificOutput.additionalContext` adapter を除去して fail-open pass-through にする配線変更と、Stop characterization test / runtime docs の更新を同じ単位に含める。Claude Stop の出力契約は変更しない。
4. **Matt Pocock managed set**: 同じ initiative 内の独立した workflow migration として、25 skill の full set を exact revision へ進める。membership は変更せず、明示的な skill 呼出し、frontier question separator、setup 未済時の案内方法を取り込む。既存のローカル skill 上書きは維持し、先に確定した non-Matt lock を baseline として ADR-0042 の ordered gate が全て通った場合だけ採用する。

各更新単位は、候補の一部だけを採用しない。互換性ゲートに失敗した単位は旧 snapshot、旧 pin、または旧 manifest/lock pair を維持し、他の更新単位の採否とは分離する。

## 2026-09-01 amendment

PR #202 が Orca native の Worktree Entry Point を確立した後の更新は、Tool Snapshot と通常の APM payload refresh の直列2 PRへ分ける。Tool Snapshot の実装入口で upstream default branch を一度だけ確認し、immutable revision `ea1dc2132fb2669899dc8b3cbe6fe82ed10d23d6` に固定した。この snapshot は Claude Code 2.1.252、Codex 0.151.0、Copilot CLI 1.0.82、Antigravity CLI 1.1.22、RTK 0.46.0、APM 0.29.0 を含む。Codex 0.152.0 は未収録のため待機せず、`tools.update_plan.enabled` も opt-in しない。

通常の APM payload refresh は Tool Snapshot の main への merge を blocker とする別の更新単位で、採用済み APM 0.29.0 を使う。両更新単位とも PR #202 の worktree ownership contract を変更しない。Impeccable と Matt Pocock managed set は今回の2更新単位に含めない。

## Implementation status

### llm-agents snapshot（Issue #204）

Issue #204 の実装入口で `numtide/llm-agents.nix` の default branch HEAD を一度だけ再確認し、調査時点候補と同じ immutable revision `ea1dc2132fb2669899dc8b3cbe6fe82ed10d23d6` を採用した。source URL と lock の `original.rev` / `locked.rev` は同じ revision を指す。3 system の package metadata は Claude Code 2.1.252、Codex 0.151.0、Copilot CLI 1.0.82、Antigravity CLI 1.1.22、RTK 0.46.0、APM 0.29.0 で一致した。Codex 0.152.0 は未収録のため待機せず、repository に `tools.update_plan.enabled` を追加していない。OpenCode 1.18.25 は snapshot に存在するが user devShell へ配備していない。

最初の x86_64-linux devShell build では、shared overlay の Codex derivationがconsumer側のstable nixpkgsで再計算され、Numtide cacheと一致せずRust source / release LTO buildになった。上流のdirect packageは上流自身のpin済みnixpkgsでCI buildされるため、Codexだけを同じimmutable inputの`inputs.llm-agents.packages.${system}.codex`へ切り替えた。direct Codex outputはx86_64-linux / aarch64-linux / aarch64-darwinの3 systemすべてでNumtide cacheに存在する。切替後のx86_64-linux WSL devShell dry-runはCodexをbuild対象に含めず、実buildはshell derivation 1件だけを2.00秒で完了した。snapshot/version/floorは変えず、他のAI packageはshared overlayを維持する。

`minClaudeCode`は2.1.252、`minCodex`は0.151.0へ引き上げた。`nix flake check --no-build --all-systems`、3-system metadata eval、x86_64-linux WSL devShell build/startup、隔離HOMEでの6 CLI version/help、`tests/nix-devshell.bats` 32/32、`tests/workflow-contract.bats` 14/14、full Bats suite 404/404（runtime mount条件の1件はskip）が成功した。candidate Codex 0.151.0 は一時`CODEX_HOME`とread-only sandboxで`tdd` skill flowを開始し、同じsessionを`resume --last`で継続できた。両turnとも`update_plan`は使っていない。APM manifest/lockはHEADから不変で、`chezmoi source-path`がprimary checkoutを指すためlive applyは行っていない。

#### Verification Matrix（Issue #204）

| AC                                            | 種別              | 検証                                                                                                    | 結果      | 未確認理由                                     |
| --------------------------------------------- | ----------------- | ------------------------------------------------------------------------------------------------------- | --------- | ---------------------------------------------- |
| stable/default HEADを一度だけ固定             | infra             | 実装入口でdefault branchを一度だけ再確認し`ea1dc2132fb2669899dc8b3cbe6fe82ed10d23d6`を固定              | 確認済み  | —                                              |
| source / lock / metadataの整合                | infra             | `flake.nix`とlockの`original.rev` / `locked.rev`、3-system metadata evalを照合                          | 確認済み  | —                                              |
| 導入済み5 CLIとAPMを更新                      | CLI / infra       | Claude 2.1.252、Codex 0.151.0、Copilot 1.0.82、`agy` 1.1.22、APM 0.29.0。RTK 0.46.0も同じsnapshotで確認 | 確認済み  | version固有機能のinteractive再現は未実施       |
| Codex 0.152の収録待ちをしない                 | policy            | 一度の再確認で未収録を確認し0.151.0を採用                                                               | 確認済み  | —                                              |
| `update_plan`を強制opt-inしない               | config / workflow | repository configに設定なし、workflow contract 14/14、candidate Codexで`tdd`の開始と`resume --last`継続 | 確認済み  | —                                              |
| OpenCodeを新規配備しない                      | config            | `modules/ai.nix`に`llm.opencode`なし                                                                    | 確認済み  | —                                              |
| supported systemsのNix evaluation             | infra             | `nix flake check --no-build --all-systems`と3-system metadata eval                                      | 確認済み  | aarch64-linux / aarch64-darwin実機実行は未実施 |
| Linux devShell build/startupとCLI smoke/floor | CLI / infra       | cacheable direct Codex、2.00秒build、隔離HOME startup、6 CLI version/help、floor tests                  | 確認済み  | fresh hostでのdownload時間は未計測             |
| PR #202 workflow regression                   | workflow          | `tests/workflow-contract.bats` 14/14                                                                    | 確認済み  | —                                              |
| APM payload不変・live applyなし               | safety            | `git diff --quiet -- apm.yml apm.lock.yaml`、`chezmoi source-path`を確認                                | 確認済み  | —                                              |
| Verification Matrix                           | docs              | source側の本表を作成                                                                                    | 後続phase | PR本文への転記は`/to-pr`で行う                 |

### llm-agents snapshot（2026-09-02 follow-up、v2.1.257 release note トリガー）

Claude Code v2.1.257 の公式 release note を更新トリガーとして、実装入口で upstream default branch HEAD を一度だけ再確認し、`llm-agents.nix` の immutable revision を `ea1dc2132fb2669899dc8b3cbe6fe82ed10d23d6` から `775405507404a6c28246aec9a848e091d3d8478c` へ更新した。ユーザー devShell が共有する nixpkgs（`fca2dbd4c00c3063235e56bb91758e24fc67b7b8`）と対応3 system は変更していない。

3 system の package metadata は Claude Code 2.1.258、Codex 0.152.0、Copilot CLI 1.0.82（変化なし）、Antigravity CLI 1.1.23、RTK 0.46.0（変化なし）、APM 0.29.0（変化なし）、code-review-graph 2.3.8（local override、変化なし）で一致した。

Claude Code の公式 CHANGELOG（2.1.257）を確認した結果、auto mode への Containment Escape rule 追加、working directory 外読み取りの one-time prompt、compound command / subshell 内での `permissions.ask` 迂回の修正、`Read()`/`Edit()` deny ルールの redirect / reader コマンド適用漏れの修正、plugin コンポーネント path の symlink traversal 修正、linked worktree での sandboxed git 書込み権限喪失の修正、worktree 隔離 session の git 非関与コマンドに対する false-positive 拒否の修正、teammate mailbox 二重応答の修正、background daemon の複数安定化が見つかった。worktree 隔離・auto mode の trust boundary・`teammateMode: auto` の信頼性に直結するため `minClaudeCode` を `2.1.252` から `2.1.257` へ引き上げた。pin 自体は 2.1.258 まで進むが、その2件の修正（macOS 12 起動regression、再送 permission approval のcontent欠落）には床上げ根拠となる記述がないため、床は 2.1.257 に留めた。

Codex の公式 release note（0.152.0）を確認した結果、信頼できない backend URL を拒否し redirect を無効化して保存済み credential を保護する修正、MCP tool のキャッシュ更新・remote plugin 変更をまたいだ可用性維持と認証再試行時の refreshed header 使用が見つかった。credential/trust boundary に直結するため `minCodex` を `0.151.0` から `0.152.0` へ引き上げた。同版で `tools.update_plan.enabled` が既定 disabled の opt-in 設定へ変わったが、この repo は元々同 flag を設定しておらず、Issue #204 時点の判断（opt-in しない）を継続するだけで挙動への影響はない。

検証は `nix flake check --no-build --all-systems`（3 system で新 pin・新 floor が通過）、3 system の `nix build --dry-run` による7パッケージの version/store path 一致確認、x86_64-linux host での実 `nix develop` build と7 CLI (`claude` 2.1.258 / `codex` 0.152.0 / `copilot` 1.0.82 / `agy` 1.1.23 / `rtk` 0.46.0 / `apm` 0.29.0 / `code-review-graph` 2.3.8) の version 実測、`tests/nix-devshell.bats` 32/32、`tests/workflow-contract.bats` 16/16（Issue #204 時点の14/14から、後続の PR #209「fix: align agent guidance and APM lock tests」で2 testが増えた分で、regressionではない）、full Bats suite 407中399/407（既知の環境依存 pre-existing failure 8件のみを除き全通過。原因はいずれも本更新の差分と無関係であることを個別に確認済み、詳細は下記）まで行った。

full Bats suite で確認した2件の pre-existing failure はいずれも、このセッションのシェル環境に設定済みの `FORCE_COLOR=3` に起因し、原因を実験で確定させた（推測ではない）：

- `code-review-graph package meets its FastMCP floor on all supported systems` — `fastmcp call --json` の出力が rich の ANSI 装飾付きで返り、`"is_error": false` の厳密な部分文字列一致に失敗する。同じ呼び出しに `FORCE_COLOR=0` を前置しても装飾は消えず（rich は値を見ず環境変数の有無だけで force_terminal を有効化する挙動と推測される）、装飾を剥がした上での構造化出力自体は `is_error: false` / `total_nodes: 2` を含む正しい内容だった。`code-review-graph.nix` は本更新で変更しておらず、`nix build --dry-run` で `code-review-graph-2.3.8` が3 system とも再ビルド対象に含まれず前回検証済み derivation と同一であることも確認済み。
- `non-WSL dogfood leaves browser ownership untouched`（`tests/managed-dogfood-browser.bats`）— Node の `console.log(null)` が ANSI 装飾付き `null` を出力し、厳密一致 `[ "$output" = "null" ]` に失敗する。こちらは `FORCE_COLOR=0` を前置すると装飾なしの `null` に戻り、`bats tests/managed-dogfood-browser.bats` 7/7 全通過を確認した。対象の `.mjs` も本更新では変更していない。

このほか、full Bats suite 実行時には `tests/mattpocock-update-gate.bats` の6 testも一時的に failed だったが、こちらは `FORCE_COLOR` ではなく `LANG=en_US.UTF-8` によるロケール依存の GNU `sort` 収集順序差が原因であることを実験で確定させた：candidate/expected skill 一覧の diffが `code-review`/`codebase-design`、`grilling`/`grill-me` の並び順違いのみで要素集合自体は同一であることを確認し、`LC_ALL=C bats tests/mattpocock-update-gate.bats` を実行したところ13/13全通過した（通常実行では7/13、failしていた6 testが全て通過に転じた）。`code-review-graph.nix` 同様、Matt Pocock 関連ファイルも本更新では一切変更していない。

以上のとおり、mattpocock-update-gate の6件を含む計8件の failure は、本更新の差分（`flake.nix` / `flake.lock` / `modules/ai.nix` / `tests/nix-devshell.bats` / `runtime/ai-runtimes.md` / 本 ADR）とは無関係な、このセッション固有のシェル環境変数（`FORCE_COLOR=3`、`LANG=en_US.UTF-8`）に起因する事象であることを実行結果で確認済みである。修正（rich/Nodeの色制御差異の吸収、またはgateスクリプトへの`LC_ALL=C`固定）は本更新のスコープ外とする。

aarch64-linux / aarch64-darwin の実機実行、2.1.257 の床上げ根拠そのもの（Containment Escape rule 等）の interactive 機能的 smoke は未確認のまま。APM manifest/lock はこの更新単位では変更していない。

これにより llm-agents snapshot 更新単位（follow-up）も採用できる。

### Codex 0.153.2 local override（2026-09-04、GPT-6 Astra）

GPT-6 Astra を明示設定できる Codex 0.153.1 と Fast tier 表示を訂正した 0.153.2 の公式 release note を確認した。実装入口で `numtide/llm-agents.nix` の default branch HEAD を一度だけ再確認したところ、`10e3dca999e12a0d07f1e9e470707f4386dc3178` の Codex package は 0.153.0 だった。既存 snapshot を進めると他の CLI も同時に変わり得るため、この変更単位では flake pin と lock を維持し、既存 direct Codex package の `version`、source hash、`cargoHash` だけを 0.153.2 へ local override する。source hash は `sha256-R97lEHS2XfMQNbAc9k8v7EbcQCnwxND7zhnK3EBsI3Y=`、Cargo vendor hash は `sha256-GG6kOXmCdq+bZLU2ul0DIVL8lDuweayvZvXn6+bcUZw=` である。V8 は pin 側と同じ 150.4.0 のため、3 system の既存 artifact hash を再利用する。

`minCodex` を 0.153.2 へ上げ、管理 config の既定モデルを `gpt-6-astra` にする。モデル catalog が対応する `xhigh` は維持し、役割とコストが異なる subagent は `gpt-5.6-luna` / `high` のままにする。0.153.0 で追加された `features.context_management.experimental_mode` は disabled-by-default の experimental 機能であり、今回の目的には不要なので設定しない。upstream snapshot が 0.153.2 以上を収録した次回更新で local override を削除する。

Codex 管理設定 63/63、nix-devshell 32/32、`nix flake check --no-build --all-systems`、3 system の devShell closure における `codex-0.153.2` derivation、x86_64-linux host の実 devShell buildと `codex-cli 0.153.2`、`gpt-6-astra` / `xhigh` override の strict-config 読み込みを確認した。aarch64-linux / aarch64-darwin は derivation 評価のみで実機実行は未確認、GPT-6 Astra の実リクエストは段階的 rollout と利用資格に依存するため未確認である。task worktree から live HOME への `chezmoi apply` は行わない。この境界で Codex 0.153.2 local override 更新単位を採用する。

### llm-agents snapshot（Issue #184）

Issue #184 の実装入口では、upstream stable/default branch HEAD を一度だけ再確認し、調査候補と同じ `4a9441120caf6c6aff273af68995267a35c20fcd` を採用 revision として固定した。source URL と lock の `original.rev` / `locked.rev` は同じ exact revision を指し、pre-release は導入していない。ユーザー devShell が共有する nixpkgs `fca2dbd4c00c3063235e56bb91758e24fc67b7b8`、対応3 system、Copilot CLI 1.0.80、APM 0.28.0 は変更していない。

採用した package metadata は3 systemで claude-code 2.1.247、codex 0.150.0、copilot-cli 1.0.80、antigravity-cli 1.1.21、rtk 0.46.0、apm 0.28.0、code-review-graph 2.3.8 に一致する。`minClaudeCode` は2.1.247、`minCodex` は0.150.0へ上げた。CRG 2.3.8 の package sourceは parser probe を `[sys.executable, "-c", code, grammar]` へ変更したため、local overrideもこの新しい probe形を固定Python環境へ差し替えるよう更新した。

`nix flake check --no-build --all-systems`、3 systemの7 package metadata eval、x86_64-linux hostのdevShell buildと7 CLI version/startup、CRGの一時repository graph build、read-only allowlistに限定したstdio MCP `list_graph_stats_tool`、full Bats suite 389/389（runtime mount条件の1件はskip）を通過した。scoped `chezmoi apply` 後のlive devShellでも7 CLI versionは一致した。aarch64-linux / aarch64-darwinの実機実行、Claude 2.1.247 / Codex 0.150.0の根拠機能をinteractive agent sessionで再現する機能的smoke、Antigravity CLI 1.1.21のversion固有changelogは未確認である。

これにより llm-agents snapshot 更新単位は採用できる。

### 通常の APM payload refresh（Issue #185）

APM 0.28.0 の隔離 cwd / HOME で全18 dependencyを再materializeし、accepted lockとcandidateのselected subtreeを`resolved_commit` / `content_hash`で比較した。payloadが変わるのはModern Web GuidanceとRemotionの2件、revision-onlyはShadcnとOrcaの`computer-use` / `orchestration`の3件、残り13件はcommit/hashとも不変だった。

| selected dependency                               | accepted → candidate    | content hash            | 分類・採否                    |
| ------------------------------------------------- | ----------------------- | ----------------------- | ----------------------------- |
| `anthropics/skills/pdf`                           | `3b3fad96` → `3b3fad96` | `69e2ac9e` → same       | 不変                          |
| `anthropics/skills/skill-creator`                 | `3b3fad96` → `3b3fad96` | `b2bfe91d` → same       | 不変                          |
| `Effect-TS/skills/effect-ts`                      | `28822c9e` → `28822c9e` | `261b9f3f` → same       | 不変                          |
| `GoogleChrome/modern-web-guidance`                | `460e5536` → `457c381d` | `8951bdfc` → `07775fbf` | payload変更、exact pin採用    |
| `mattpocock/skills`                               | `6acc160e` → `6acc160e` | `7c5f630f` → same       | 不変、別更新単位のpin維持     |
| `mizchi/skills/empirical-prompt-tuning`           | `7a0d7286` → `7a0d7286` | `20e7fba9` → same       | 不変                          |
| `pbakaus/impeccable`                              | `c39b6425` → `c39b6425` | `d79bd3df` → same       | 不変、別更新単位のpin維持     |
| `remotion-dev/skills/remotion-best-practices`     | `7fc6dea3` → `7a3d0ca4` | `7e361522` → `2493dc60` | payload変更、exact pin採用    |
| `shadcn-ui/ui/shadcn`                             | `ac60ef5c` → `683a5a9b` | `8b8c1296` → same       | revision-only、floating再解決 |
| `stablyai/orca/computer-use`                      | `5bcbafff` → `9c01e09e` | `afe48be6` → same       | revision-only、floating再解決 |
| `stablyai/orca/orca-cli`                          | `5ca747da` → `5ca747da` | `cca6a909` → same       | 不変、exact pin維持           |
| `stablyai/orca/orchestration`                     | `5bcbafff` → `9c01e09e` | `b5c36487` → same       | revision-only、floating再解決 |
| `supabase/agent-skills`                           | `8331f910` → `8331f910` | `5766a8e9` → same       | 不変                          |
| `vercel-labs/agent-skills/composition-patterns`   | `dd089a8c` → `dd089a8c` | `5b3564ca` → same       | 不変                          |
| `vercel-labs/agent-skills/react-best-practices`   | `dd089a8c` → `dd089a8c` | `74f142d2` → same       | 不変                          |
| `vercel-labs/agent-skills/react-view-transitions` | `dd089a8c` → `dd089a8c` | `aa4cf8be` → same       | 不変                          |
| `vercel-labs/agent-skills/web-design-guidelines`  | `dd089a8c` → `dd089a8c` | `a6a44d54` → same       | 不変                          |
| `vercel-labs/skills/find-skills`                  | `435076e7` → `435076e7` | `913b9d37` → same       | 不変                          |

revision-onlyのfloating解決はShadcn `683a5a9b370acdb7785a0529434e6a3b8c7e0441`、Orca `computer-use` / `orchestration` `9c01e09ecc9d3c1203968ace9945d16edfb35dd2`である。selected content hashはそれぞれaccepted lockの`sha256:8b8c1296ad947a237b32c21857837357f29197c53722131758777c80d26ed1ad`、`sha256:afe48be623c1f6190ade7dacc4c1d334d4150b503ed00b28dda23a499e5bdc30`、`sha256:b5c364878fb07d21a369f091f2e96b823da94308b15b39636f2585d8b5621b51`と一致するためmanifestへpinを追加していない。

Modern Web Guidanceはexact revision `457c381def89ce6213a171238f92eea63e9eaeb2`、content hash `sha256:07775fbfaed98fcf50795256434f646da296311bc10dd54f2de29075eca9095b`を採用した。公式差分はglobal `Translator` interface、4状態のavailabilityとdownload時のuser gesture、CSS sibling functionsのBaseline更新である。Remotionはexact revision `7a3d0ca45d2f6a00bf35cb3c525734a36d55a834`、content hash `sha256:2493dc60c3917d2e1153cd60d9e4df771b2775f64f3e17cbb1c2f1d011f888f3`を採用した。4.0.518 payloadにはcaptionの`pageBreakAfter`、重複timestampでも安定するtoken key、Mediabunnyの`UrlSource`例の更新が含まれる。

更新済みmanifestを隔離cwdへコピーし、隔離HOMEで`apm install --target claude,codex --https`を実行してdeployed files/hashを含むlockを生成した。同じ環境の`apm install --frozen --target claude,codex --https`前後でlock SHA-256は`d43138a744099027b61ad50150b4a36246f747214d23761c9f970b3a38d03720`のまま、`apm audit --ci`はdriftなしで10/10 checksを通過した。`.agents/skills` / `.claude/skills`の両targetでModern Web Guidance 141 files、Remotion 137 filesと上記guidanceを発見した。隔離cwdはGit remoteを持たないため、auditのorganization policy enforcementはwarning付きskipとなったが、manifest/lock/deployment/contentの10 checksはすべて成功した。live skill directoryと`chezmoi apply`には触れていない。

これにより通常の APM payload refresh更新単位も採用できる。

### 通常の APM payload refresh（2026-09-03 follow-up、Issue #212）

Issue #212 の実装入口で `apm outdated` が提示した7候補を実コミット比較で個別に検証した。`mattpocock/skills` は `apm outdated` が示す最新タグ `v1.2.3`（`6acc160e`）よりpin済みcommit `6654f6b6`の方が39コミット先行しており（`gh api repos/mattpocock/skills/compare/6acc160e...6654f6b6` で実測、`ahead_by: 39, behind_by: 0`）、`apm outdated` のタグ専用比較に起因するfalse positiveと判明したため対象外にした。`stablyai/orca/skills/orca-cli` は最新タグ `v1.4.196`（`aad4ae42`）まで121コミット進んでいた（同様の`compare`で`ahead_by: 0, behind_by: 121`を実測）が、apm.ymlの当該pinを一時的にそのcommitへ進めて隔離rootでcandidate materializeしたところ、selected subtreeのcontent hashは既存pinと同じ`sha256:83ece910d035d0684195095bb9df5911a028002b2efba1ebbeb4ae66de5e0903`のまま不変だったため、Issue #185で確立した「selected payloadが同一のexact pinをrevisionの新しさだけで進めない」原則に従いpinを維持した。残る5件（anthropics/skillsの`pdf`・`skill-creator`、shadcn、Orcaの`computer-use`・`orchestration`）はfloating `(default)` 依存で、いずれもcontent hashが不変のrevision-only進行と確認できたため、apm.ymlへの新規exact pin追加はせずlockのfloating解決だけを自然反映した。`pbakaus/impeccable`、`GoogleChrome/modern-web-guidance`、`remotion-dev/skills`は別更新単位のexact pinまたはapm側の"unknown"判定のため今回の候補にしていない。

隔離root（`apm install --root`でsourceの`apm.yml`はcwdから解決しつつ生成物だけを分離し、HOMEは変更しない）での`apm install --target claude,codex --https`によるnon-frozen materializationと、同一環境の`apm install --frozen --target claude,codex --https`前後でlock SHA-256`4ff82f45d441efd837b993c761a74894575015581d3d82c7276b3141d0ccff81`が不変であることを確認した。Review Roundでは同じmanifest / lockをGit remoteのない隔離cwdへ複製してfrozen install後も同SHAが不変であることを確認し、`apm audit --ci`を再実行した。organization policy enforcementはGit remoteを判定できないためwarning付きskipとなったが、baseline 10/10はdriftなしで成功した。両target（`.agents/skills/` / `.claude/skills/`）のdeployed_filesとcontent hashは、変更対象5件を含め候補実体と一致した。`apm.yml`は無変更、`tests/apm-runtime.bats`の該当assertionを新しいresolved_commitへ更新し15/15成功、full Bats suiteは407中399/407通過（既知の環境依存 pre-existing failure 8件は2026-09-02 follow-upで確認済みの原因（`FORCE_COLOR`/`LANG`）と一致し、本diffとは無関係と再確認した）。live skill directoryと`chezmoi apply`はこの更新単位では行わず、後続の最終配備単位に残す。

これにより通常の APM payload refresh更新単位（2026-09-03 follow-up）も採用できる。

### Impeccable 4.1.2（Issue #186）

通常のAPM payload refreshで確定したlockをbaselineに、Impeccableだけを4.1.2 tagのexact revision `63b04e2530f5c7b41ea83c133daab24f34912456`へ進めた。selected content hashは`sha256:eaf9d73a3348cbda6774b1a8268645c17f4d8cf5b5231743d2c44d71212cd755`で、non-Impeccable entryはIssue #185 baselineから変更していない。

4.1.2 runtimeは`turn_id`を持つeventをCodexと判別し、Stop findingをtop-level `decision` / `reason`で返す。このためCodex managed Stop commandの旧`hookSpecificOutput.additionalContext` transformを除去し、runtime stdoutをfail-openでpass-throughする配線へ更新した。Claude Stopは既存の`hookSpecificOutput.additionalContext`、両runtimeのPostToolUse immediate tier / Stop deep pass、quiet、dedupe、edit threshold、sensitive/generated path filter、Stop re-entry、runtime error時のfail-openを維持する。

候補runtimeを公開JSON event seamから実行したDesign Hook testは10/10で、`turn_id`付きCodex Stopがdeep-pass findingをnative schemaで返し、次のStopがsilentになることを確認した。旧both-tiers交互再報告characterizationもsilent convergenceへ更新した。managed hook testsは3/3、隔離APMのfrozen install前後でlock SHA-256は`fed402d5e258b8a7347b8995d0396d5be72da39856157a16f8554ea5feb1d451`のまま、auditはdriftなしで10/10 checksを通過した。

これによりImpeccable更新単位も採用できる。

### Matt Pocock managed set（Issue #187）

実装入口で `mattpocock/skills` の default branch が `main`、HEAD が `6654f6b60cd9d5be8b54c6fafe44346dabeb3b76` であることを一度だけ再確認し、この revision を immutable candidate として固定した。plugin version は `1.2.3`、公式 membership は既存と同じ25 skillである。`implement-spec` と `retro` は in-progress bucket にのみ存在し plugin manifest 外であるため、APM collectionには追加していない。

candidate payload の content hash は `sha256:30aaf1538e75a717db8608778e06e1c47ce38578f46fe88e53e599818cf30c9f` で、明示的な Skill tool 呼出し、frontier round の horizontal rule、setup 未済時に `setup-matt-pocock-skills` を自動実行せずユーザーへ案内する文面を含む。Builder-Evaluator、standalone code review、triage write、model-invoked safety、Review Round のローカル上書きは `AGENTS.md` / `CLAUDE.md` / runtime contract の既存 authority を維持した。

実候補で ordered gate を走らせた際、Matt package block 外の deployment ledger hash まで non-Matt drift と誤認する既存 normalizer の欠陥が初めて露出した。normalizer は owner が `mattpocock/skills` だけの record のみ candidate-owned として除外し、複数 owner と真の non-Matt drift は比較対象に残すよう修正した。deterministic gate tests でこの許容と拒否を両方固定している。

APM frozen install は lock を書き換えず、audit は10/10、関連 contract tests は48/48、full Bats suite は396/396（candidate runtimeを明示しないImpeccable materialization 9件はskip）、Claude/Codex両targetの25-skill discoveryとworkflow payload contract、isolated chezmoi dry-runが成功した。過去の4 test failureは再現せず、例外にしていない。live skill directoryへのapplyはこのsource gateでは行わず、親initiativeの最終配備境界に残す。

### Final live deployment（Issue #188）

最終配備の初回 `chezmoi apply` では、更新前のlive Impeccableに対するDesign Hook smokeがCodex native Stopとsilent convergenceの2件でredになることを確認し、その後sourceからAPM payload、managed hooks、workflow contractをlive HOMEへ反映した。Design Hookは同じ公開event seamで10/10 greenとなり、Codex/Claudeのmanaged wiringとfail-open fixtureも3/3成功した。

初回live APM frozen installではsource lockの書き戻しを検出した。Issue #187のordered gateはnon-Matt baselineを一時的にexact pinして検証するため、作業用lockの`resolved_ref`がunpinned dependencyにも残っていた。このlive書き戻しは診断 evidence に限定し、source採用物にはしていない。実際のunpinned manifestを新しい隔離cwd/HOMEへコピーし、`apm install --target claude,codex --https`からnative lockを再生成した。Orca `computer-use` / `orchestration`は旧lockの`9c01e09ecc9d3c1203968ace9945d16edfb35dd2`からdefault-branch revision `026389a3bc03da03ca2d65295e805493712b0774`へ自然再解決された。両entryのcontent hashは`sha256:afe48be623c1f6190ade7dacc4c1d334d4150b503ed00b28dda23a499e5bdc30` / `sha256:b5c364878fb07d21a369f091f2e96b823da94308b15b39636f2585d8b5621b51`のままでpayload変更はない。このrevision-only driftを記録して隔離生成物をsourceへ採用し、live onchangeもlock生成と同じ`apm install --frozen --target claude,codex --https`へ統一した。regression testはmanifestのexact dependency path / revisionとlockの`resolved_ref` entryが一致することを固定する。

隔離生成lockのSHA-256は`29186c40a47bf6c25d9fbf73d15ebba4dc9575be7242f381ddaeac82ed24e6c4`で、同じ隔離cwd/HOMEのfrozen install前後で不変、`apm audit --ci`はdriftなしで10/10となった。sourceへ採用して再applyした後はsource/live lockも同じSHA-256となり、live frozen installは書き戻しなし、live auditは10/10、scoped `chezmoi status --exclude=scripts`はemptyとなった。Modern Web Guidance / Remotion / ImpeccableとMatt Pocock 25 skillは`~/.agents/skills` / `~/.claude/skills`の両方で発見でき、Matt payloadには明示的Skill tool呼出し、frontier separator、setup未済時のuser pointerが含まれる。

live CLIはClaude Code 2.1.247、Codex 0.150.0、Copilot CLI 1.0.80、Antigravity CLI（`agy`）1.1.21、RTK 0.46.0、APM 0.28.0、code-review-graph 2.3.8で、全てversion/help startupが成功した。`nix flake check --no-build --all-systems`とLinux hostのCRG graph build・read-only MCP `list_graph_stats_tool`も再実行して成功した。repository full suiteは396/396で既知例外なしに成功した。

Codex native hooksは配備済みで、materialized runtimeへのJSON eventではtop-level `decision` / `reason`とfail-openを確認した。ただし新しいhook entryは実Codex sessionで初回trust approvalが必要で、現時点の`~/.codex/config.toml`に`[hooks.state]`はない。permission bypassは行わず、actual sessionからのhook発火は未確認とする。再確認は新規Codex sessionで各entryをreview・approveし、UI fixtureの編集後にStopする。aarch64-linux / aarch64-darwinの実機実行、Claude/Codexの品質floor根拠機能をinteractive sessionで再現する機能的smoke、Antigravity 1.1.21のversion固有changelogも未確認のままである。APM auditの10 checksは成功したが、HOMEはGit remoteを持たないためorganization policy enforcementだけはwarning付きskipとなった。

#### Final Verification Matrix（親Issue #183）

| AC                                                | 種別              | 実行コマンドまたは理由                                                                                                                                                                                                                                                                  | 結果     | 未確認理由                                                                  |
| ------------------------------------------------- | ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | --------------------------------------------------------------------------- |
| #183-1 stable/default HEADを一度だけ固定          | infra             | Issue #184で`4a9441120caf6c6aff273af68995267a35c20fcd`を固定し、flake source / lockの`original.rev` / `locked.rev`を照合                                                                                                                                                                | 確認済み | —                                                                           |
| #183-2 snapshot metadataと品質floor               | CLI / infra       | 3-system metadata evalとlive version smoke。Claude 2.1.247、Codex 0.150.0、Copilot 1.0.80、`agy` 1.1.21、RTK 0.46.0、APM 0.28.0、CRG 2.3.8                                                                                                                                              | 確認済み | version根拠機能のinteractive再現とAntigravityのversion固有changelogは未確認 |
| #183-3 CRG 2.3.8 adaptation / build / MCP         | CLI / API / infra | 3-system Nix check、Linux graph build、read-only allowlistの`fastmcp call ... list_graph_stats_tool`                                                                                                                                                                                    | 確認済み | aarch64実機実行は未確認                                                     |
| #183-4 selected subtree比較とexact pin境界        | infra             | Issue #185の18 dependency比較。payload pinはModern Web Guidance `457c381def89ce6213a171238f92eea63e9eaeb2` / Remotion `7a3d0ca45d2f6a00bf35cb3c525734a36d55a834`、Orca `9c01e09ecc9d3c1203968ace9945d16edfb35dd2` → `026389a3bc03da03ca2d65295e805493712b0774`はhash不変のrevision-only | 確認済み | —                                                                           |
| #183-5 native lock / frozen no-rewrite / audit    | CLI / infra       | 新しい隔離cwd/HOMEでnon-frozen生成し、同じ環境のfrozen前後SHA-256 `29186c40a47bf6c25d9fbf73d15ebba4dc9575be7242f381ddaeac82ed24e6c4`、audit 10/10を確認してsourceへ採用                                                                                                                 | 確認済み | organization policy enforcementは隔離cwdにGit remoteがなくwarning付きskip   |
| #183-6 Modern Web Guidance / Remotion discovery   | CLI               | 両targetの`SKILL.md` checksum一致、global `Translator` guidanceとcaption `pageBreakAfter`をlive payloadで確認                                                                                                                                                                           | 確認済み | —                                                                           |
| #183-7 Impeccable 4.1.2とCodex native Stop        | API / infra       | exact pin `63b04e2530f5c7b41ea83c133daab24f34912456`、managed pass-through wiring、materialized runtimeへの`turn_id`付きStop event                                                                                                                                                      | 確認済み | 実Codex sessionからのhook発火は初回trust approval待ち                       |
| #183-8 Design Hook behavior / fail-open           | API               | live Design Hook 10/10、managed wiring / output / runtime failure fixture 3/3                                                                                                                                                                                                           | 確認済み | 実Codex sessionからのhook発火は初回trust approval待ち                       |
| #183-9 Matt 25-skill managed set                  | CLI / infra       | exact pin `6654f6b60cd9d5be8b54c6fafe44346dabeb3b76`、両target25/25、explicit invocation / separator / setup pointerをlive payloadで確認                                                                                                                                                | 確認済み | —                                                                           |
| #183-10 ordered gateと既知failure非例外化         | infra             | Issue #187のordered gate、関連contract 48/48、full suite 396/396、isolated dry-run。#188でnative lock regressionを追加                                                                                                                                                                  | 確認済み | —                                                                           |
| #183-11 repo固有workflow safety contract          | infra             | AGENTS / CLAUDE / runtimeと`tests/workflow-contract.bats`をfull suiteで検証                                                                                                                                                                                                             | 確認済み | —                                                                           |
| #183-12 atomic adoption / fallback                | infra             | 上記exact revisionの四単位を全て採用。下記fallback ledgerの旧sourceは全て未発動で、partial adoptionなし                                                                                                                                                                                 | 確認済み | —                                                                           |
| #183-13 full tests / 3-system Nix / Linux smoke   | CLI / infra       | `bun run test` 396/396、`nix flake check --no-build --all-systems`、live 7 CLI version/help、Linux CRG build/MCP                                                                                                                                                                        | 確認済み | aarch64実機実行は未確認                                                     |
| #183-14 source→live apply / discovery             | CLI / infra       | scoped `chezmoi apply`、source/live lock checksum一致、status empty、APM audit、両targetpayload discovery、managed hook discovery                                                                                                                                                       | 確認済み | Codex hookのactual session発火はtrust approval待ち                          |
| #183-15 正本文書 / decision / Verification Matrix | infra             | 本ADR、`runtime/ai-runtimes.md`、`runtime/skill-harness.md`をactual adoptionと未確認事項へ同期                                                                                                                                                                                          | 確認済み | —                                                                           |

Fallback ledger（AC12、全て未発動）:

- llm-agents snapshot: flake source / lock revision `3c16acbe5229040ee8f4d6f7b85de757e14b4bda`。
- 通常APM payload: Modern Web Guidance `460e5536b8e61034d83ff4af24bb0bf1112d2cb0` / Remotion `7fc6dea333869e23f58bf9e9861010e9ba589e5e`を持つ`eb66b43470114824ee4b657ddfe00793601e0373`のmanifestと、lock SHA-256 `37df89f9f3cacc70ad6658d7df5428bb84a4cd0a21cad892d2e48ff34d810a11`。
- Impeccable: pin `c39b6425fa54a093749b9a236adcd003818167c1`を持つ`5cdaf671d94593b3ba1af5c793aac2b072a31890`のmanifestと、lock SHA-256 `d43138a744099027b61ad50150b4a36246f747214d23761c9f970b3a38d03720`。
- Matt Pocock: pin `6acc160e4e0cd062dbbbd7a1b26ae92855edf07e`を持つ`0b4ec94aeaaa27ebcd4c24722bf216c5e7ad9f8e`のmanifestと、lock SHA-256 `fed402d5e258b8a7347b8995d0396d5be72da39856157a16f8554ea5feb1d451`。

四つの更新単位がそれぞれの互換性ゲートを通過したため、本ADRをacceptedとする。

## Verification boundary

- llm-agents は対応3 systemの evaluation、x86_64-linux host build、導入 CLI の version/startup smoke、code-review-graph の build/CLI/MCP smoke を行う。
- APM lock は runtime layout を再現した隔離 HOME で `apm install --https` により生成し、同じ環境で frozen no-rewrite と audit を確認する。
- Impeccable は `turn_id` を持つ Codex Stop の top-level `decision` / `reason`、初回 deep-pass 後の silent Stop、Claude Stop の既存出力、managed fail-open を candidate runtime で確認する。既知の交互再報告を期待する旧 characterization は、4.1.2 で不具合が修正された契約へ更新する。
- Matt Pocock managed set は `tests/mattpocock-update-gate.sh` の全工程を通す。ADR-0043 に記録した4 testの既知例外は現行 main で再現しないため、今回の例外にはしない。
- repository の full test、`chezmoi apply`、live 環境の version/discovery smoke までを完了境界とする。

## Consequences

候補ごとの失敗を他の更新へ波及させず、snapshot packaging、通常の skill payload、hook runtime、workflow semantics をそれぞれの根拠で採否できる。一方、単一の一括更新より検証回数と順序制約は増える。

関連: [ADR-0029](0029-impeccable-pin-advance-with-stop-hook.md) / [ADR-0041](0041-adopt-mattpocock-v1-2-3-workflow-semantics.md) / [ADR-0042](0042-mattpocock-managed-set-update-gate.md) / [ADR-0043](0043-update-llm-agents-and-impeccable-update-unit.md) / [skill-harness](../../runtime/skill-harness.md)
