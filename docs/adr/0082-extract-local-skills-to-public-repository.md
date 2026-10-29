---
type: decision
title: ローカル skill を独立した公開配布元へ分離する
description: 公開 skills リポジトリへの分離方針、固定版の公式導入、安全な旧配備移行と依存の所有権を定める
tags: [adr, skills, plugins, distribution]
timestamp: 2026-10-29
status: accepted
---

# ローカル skill を独立した公開配布元へ分離する

現在の `local-skills/` は、dotfiles 自身がソースと配布を所有する private skill の集合である。[ADR-0047](0047-local-skill-membership-and-explicit-retirement.md) の配備契約は chezmoi source 内の配置を前提とし、一部の skill は dotfiles が配備する文書や CLI にも依存する。単なる保管先の変更では、dotfiles のない環境で利用できる配布元にはならない。

## 合意済みの方向

- `local-skills` を、dotfiles を導入していない環境でも公式の導入手順で利用できる「独立 skill 配布元」へ分離する。
- Claude Code、Codex、Antigravity の対応を維持する。
- 新リポジトリは公開し、第三者向けの説明と依存関係の整理を設計対象に含める。
- 現在の全11件を移行対象とし、初期は1リポジトリ・1 plugin にまとめる。導入・バージョン・リリースを1単位にし、用途別や skill ごとの plugin 分割は行わない。
- Antigravity は現在 dotfiles が供給している CLI を必須の動作確認対象とし、App／IDE は公式の配置・導入手順を案内する範囲とする。
- ライセンスは現在の dotfiles と同じ MIT とする。既存の著作権表示と、同梱資源の第三者ライセンス表示を引き継ぐ。
- 対象 skill が必要とする独自の補助 CLI と規範契約も、新リポジトリから単独で導入・参照できる形に整理して同梱する。Python、Node.js、GitHub CLI、Herdr、Orca など一般配布されるツールは導入条件として案内する。
- `grilling`、`domain-modeling`、`tdd` など第三者の skill はコピーせず、公式配布元から別途導入する。依存 skill・対応版・導入方法を明示し、不足する手順は開始前に案内する。
- dotfiles による対象11件の導入も各 runtime の公式 plugin 管理へ切り替える。現行の実体コピーは移行時に停止し、旧配備の撤去手順を設計する。他の APM 管理 skill の配布方式は今回の対象外とする。
- 名前は repository を `treflebonbon/skills`、plugin を `treflebonbon-skills`、marketplace を `treflebonbon` とする。呼び出しは各 runtime の公式 namespace に従い、Claude Code では `/treflebonbon-skills:rop` の形式に移行する。
- dotfiles 側は検証済みの commit SHA に固定して導入し、検証後に明示的に更新する。公開側はバージョンを付けて配布する。catalogue と plugin 本体の両方が意図した版を参照することを確認する。
- 初期の対応 OS は現在の dotfiles に合わせて Linux、macOS、WSL2 とする。現在の CPU 対応範囲は Linux の x86_64／aarch64、macOS の aarch64 を基準とする。
- plugin の導入と汎用 skill の利用に Nix は必須にしない。必要な一般ツールをそれぞれの公式手順で導入すれば利用できる形とし、dotfiles の Nix 環境からの利用も維持する。
- 専用機能は従来の OS・依存条件を維持する。raw Codex の隔離起動は Linux／WSL2＋Nix＋対象 repo の flake、WSL2 専用のブラウザ経路は WSL2 を条件とし、機能ごとの対応表に明記する。条件外では保護を弱めた代替処理へ進まず、対象機能を開始する前に理由を案内する。Nix が配布だけを担う補助 CLI は Nix なしで導入できる形へ切り出す。
- 外部依存は skill ごとに実行前に確認する。必要なツールや第三者 skill がない場合は対象手順を開始せず導入方法を案内し、無関係な skill の利用は妨げない。
- skill 本体は Agent Skills、配布と導入は各 runtime の公式 plugin 仕様に準拠する。

## 移行する skill

`dogfood`、`domain-modeling-studio`、`herdr-peer-refactor`、`marp`、`md-agents-review`、`md-claude-review`、`orca-peer-refactor`、`pr-screenshots`、`rop`、`ui-grill-with-docs`、`worktree-gc` の11件を対象とする。

## 受入条件

2026-10-29 の設計対話で、以下の受入条件を含む設計全体についてユーザーの最終合意を得た。この ADR は実装前の設計を記録するもので、リポジトリの作成・公開、skill の移動、配備先の変更はまだ行っていない。

1. dotfiles と Nix がない環境で、公開リポジトリと記載された外部依存だけから plugin を導入し、汎用 skill を利用できる。必要な補助 CLI・契約・同梱資源を解決でき、dotfiles の checkout や `~/runtime/` の存在を必須にしない。専用機能は合意した OS・依存条件の下で利用できる。
2. Claude Code、Codex、Antigravity CLI の公式経路で導入し、新規セッションで全11件の検出と公式名による呼び出しを確認する。同梱 skill 間の相互参照、第三者 skill の実際の呼出し名、同梱資源・補助 CLI・子プロセスのパス解決を検証する。Antigravity App／IDE は公式手順の案内を用意する。
3. 既存機能と承認・検証・秘密保護の境界を維持する。依存不足は処理前に案内し、無関係な skill は利用できる。専用 auto は保護設定が欠損・不正・未有効の場合に起動を保留し、通常 session へ自動で切り替えない。認証・資格情報の準備など人間の操作が必要な確認と、自動検証した内容を区別する。
4. skill 本体と専用補助ツールのテストは新リポジトリへ移し、dotfiles には版の固定・公式 plugin 導入・更新・旧配備からの移行を検証する統合テストを残す。全11件の frontmatter を Agent Skills 仕様で検証し、契約の上限値・保護設定の投影・共通 script の同一性も正本と照合する。対応環境ごとの実行結果と未確認の範囲を記録し、validator の成功だけを実動作確認としない。
5. dotfiles の導入元と実際の plugin 本体が固定 SHA に対応し、公開 version と内容も一致する。実行後も配布物の内容は変わらず、依存準備・出力は別領域へ置く。再実行で二重導入や設定の継続的な差分を生まず、既知の旧版へ戻す手順を示す。
6. 全3 runtime の導入確認後に、今回の11件が旧方式で重複検出されない状態へ移行する。どれかの導入が失敗・未確認なら旧配備を維持する。撤去は明示した旧配備パスに限定し、既知の移行前内容との差分があれば表示して当該対象を残す。無関係な APM 配備や利用者の skill を削除しない。
7. MIT と既存の著作権・第三者ライセンス表示を保持し、README に導入、依存、機能ごとの対応環境、呼び出し、更新と移行の手順を記載する。

## 実装への引き継ぎ

新リポジトリ側の独立導入と検証を先に完成させ、その固定 SHA を dotfiles 側の移行に使う。受入前の task worktree から live の `chezmoi apply` は行わず、受入後に live source から対象を限定して配備する。[編集・配備ルール](../architecture.md)に従う。

ルートの `plugin.json` と `.claude-plugin/plugin.json` から、全 runtime 共通の `skills/<name>/SKILL.md` を配布する。manifest の独自 skill パス指定に依存しない。下記の Antigravity 形式確認に加え、実装した package を3 runtime で導入・呼び出して受入確認する。

### 検証済み SHA の公式導入

dotfiles が管理する版の正本は、検証済みの完全な commit SHA とする。SHA ごとの専用ローカル checkout を準備して HEAD を照合し、その同じ checkout を各 runtime の公式導入元にする。公開 version は配布物の識別に使い、同じ version に異なる payload を公開しない。

| runtime | dotfiles からの導入元 |
| --- | --- |
| Claude Code | 固定 checkout 内の `.claude-plugin/marketplace.json` をローカル marketplace として登録し、`treflebonbon-skills@treflebonbon` を導入 |
| Codex | 固定 checkout 内の `.agents/plugins/marketplace.json` をローカル marketplace として登録し、`treflebonbon-skills@treflebonbon` を導入 |
| Antigravity CLI | 固定 checkout の plugin root を `agy plugin install <local-dir>` で導入 |

両 marketplace の plugin source は、それぞれの公式形式で同じ checkout 内を指す相対パスにする。リポジトリ内へ自己の commit SHA は埋め込まず、GitHub URL の ref 指定だけで全 runtime の catalogue・本体が固定されるとも仮定しない。一般利用者向けには公開リポジトリからの公式導入手順も記載する。

更新時は別の SHA の checkout を準備・検証してから登録先を切り替え、実際に導入された payload と version を照合する。payload が変わる採用候補は version 更新済みの commit に限り、同じ version の別内容を固定しない。利用中の checkout は書き換えず、旧 SHA を再指定する復旧手順を用意する。manifest・version の整合、旧キャッシュが残る場合、固定先がずれた場合の拒否をテストする。

### 契約・保護設定・補助 CLI の正本

移行する skill の規範契約、専用補助 CLI、`peer_deny` とそこから導出する保護設定の正本は skills リポジトリに置く。dotfiles は検証済み SHA の資産を取得・設定し、別の手編集コピーを保守しない。`~/runtime/` に残る環境案内からは固定版の正本を参照する。契約と script の上限値の照合、Claude deny 断片と Codex rules の投影の検証は新リポジトリへ移す。

専用 auto に必要な Claude の deny 断片、Codex の rules と `dotfiles-peer` 相当の profile 定義・導入手順も配布範囲に含める。現在は dotfiles のグローバル設定にある raw push 拒否も、専用 auto の必要な保護として明示する。実効の deny 層にこれを含む必要な拒否がなければ起動を保留し、設定の存在や引数だけで適用済みとはしない。利用者の既存設定は無断で上書きせず、実値の資格情報は同梱しない。read-only の資格情報や専用 home の準備、有効化は既存契約どおり人間が行う。未有効・確認不能なら専用 auto を開始せず、通常の明示協働と区別する。

補助 CLI は package 内に置き、各 skill と子プロセスから package 内の実体を絶対パスで解決して使う。`bin/` の存在だけで全 runtime の PATH へ追加されるとは仮定しない。子プロセスへ必要なパスを明示して渡し、dotfiles の Nix 層から同じ資産を使う場合も実装を複製しない。

dotfiles からも使われる CLI の所有権は次のとおり。移管時はグローバル指示・起動手順・Nix 配布の呼び出し元も同じ固定版へ接続する。dotfiles 側の従来のコマンド名は同じ資産への配布入口として維持し、skill は package 内の実体を直接参照する。

| 資産 | 移行後の正本と dotfiles 側の利用 |
| --- | --- |
| `git-push-topic` と同じ実装を使う `git-push-reviewed` | skills リポジトリが実装を所有。dotfiles は固定版を従来のコマンド名で配布し、default branch と topic の既存の拒否・承認境界を維持 |
| `gh-review-thread` | skills リポジトリが実装を所有。dotfiles の Review Round とグローバル指示も同じ固定版を利用 |
| `orca-send` | skills リポジトリが実装を所有。dotfiles の通常の Orca 操作手順も同じ固定版を利用 |
| `codex-reviewer` | skills リポジトリが実装と必要な Git 読取り module を所有。dotfiles は固定版を配布し、秘密隔離を提供しない read-only 起動の既存契約を維持 |
| devShell 準備・raw Codex 隔離に必要な共用 module と入口 | 必要な実行ロジックと Nix 専用入口は skills リポジトリが所有し、dotfiles は固定版への依存注入と端末固有設定を所有する。Git 読取り部分を独立させ、Nix 不要の CLI から Nix 機能を必須 import しない。専用経路も dotfiles checkout を必須にせず、Nix・flake 等の導入条件を package 内に明記 |

### 配布物のパスと実行時の書込み

同梱資源は、実際に読み込まれた `SKILL.md` の directory を起点に解決する。旧 `~/.agents/skills/`、`~/.claude/skills/`、dotfiles checkout、`~/runtime/` を必須にする参照を置き換える。CLI 固有の環境変数がなければ `.` を使うフォールバックも廃し、起点を特定できない場合は実行前に案内する。同梱 skill 間の参照と第三者 skill の名前は、各 runtime の公式 discovery に従って解決する。

dotfiles の ADR・GLOSSARY への相対リンクは、必要な契約・用語を package へ移し、履歴資料は出所が分かる固定版の参照へ置き換える。dogfood の `npm ci` などの依存準備は、lockfile を使って専用の作業・キャッシュ領域で行う。インストール済み plugin や固定 checkout へ `node_modules`・実行結果を書き込まない。`metadata` の配列値や runtime 固有の `allowed-tools` も移行時に仕様適合させ、`metadata` の値は文字列とする。

### 旧配備からの移行

この移行では [ADR-0047](0047-local-skill-membership-and-explicit-retirement.md) の対象11件について、source 内の配置による配備所有権と cleanup の順序を置き換える。`local-skills/` 必須のテンプレート・hash トリガー・テストも更新し、ソース移動後の render が失敗しないようにする。APM 自身の配布所有権と更新ゲートは維持する。

1. 移行前の管理対象11件について、旧配備パスと既知の旧内容を固定する。比較基準は移行前の source revision から得た配備内容とし、パス等を変更した新 plugin の内容とは比較しない。共用 CLI の既存入口と復旧可能な旧実装も保持する。
2. 全3 runtime へ固定版 plugin を導入し、導入内容・資源解決を確認する。共用 CLI は固定版の実体・必要 module・配布入口を副作用のない照合と mock 検証で確認するまで、既存の `~/.local/bin` の実装を置き換えない。確認後に入口を切り替え、失敗・checkout 欠損時は旧実装へ復旧できるようにする。実際の push や外部書込みを確認コマンドには使わない。全体の確認までは旧 skill 配備を保持し、共有ハブを読む runtime が一つでも未確認なら共有ハブ側も残す。
3. 確認後の `after` 段階で、明示した旧配備パスの現在内容を旧内容と比較する。一致する管理対象だけを撤去し、不明・差分ありの対象は理由と差分を示して残す。失敗後の再実行では確認済みの導入と残存対象を照合する。

移行する11件を既存の `retired` に加えるだけの方法や、名前が保持一覧にない実ディレクトリを一括削除する方法は使わない。既存 `before` cleanup の該当処理も置き換える。導入失敗、片側だけの導入、旧内容の変更、対象外 skill の存在、空になった source、再実行に加え、`git-push-topic`／`git-push-reviewed`／`gh-review-thread`／`orca-send`／`codex-reviewer` の入口切替失敗・checkout 欠損・旧実装への復旧を統合テストに含める。

[ADR-0075](0075-adopt-peer-refactor-skills.md) の peer 協働・元候補固定・専用 auto の保護は維持し、正本の所在と配布経路を変更する。共通 script・節の同一性を検証する既存の契約も新リポジトリへ移す。新しい配備方式を実装・受入するまでは、現行の live 配備と正本を継続する。

## 独立導入のために整理する依存

外部依存の版・供給元・必要になる実行経路を、全11件の入口と子プロセスから棚卸しして README に記載する。以下はレビューで確認した移管対象であり、optional な手順の依存を plugin 全体の導入条件にはしない。

| skill | 外部依存と同梱する資産 |
| --- | --- |
| `herdr-peer-refactor` / `orca-peer-refactor` | Herdr／Orca と必要な `codebase-design`、`grilling`、`tdd`、`code-review`、`pr` 等の外部 skill。実行経路ごとの `jq`、Perl、OpenSSL、tmux も確認する。独自 CLI・契約・専用 auto の保護設定を同梱 |
| `dogfood` | Node.js・Playwright の固定依存と、必要時の `playwright-cli`／`triage`。WSL2 用のブラウザ補助資産を同梱し、依存準備先を配布物から分離 |
| `pr-screenshots` | 必要時の `playwright-cli`、GitHub CLI と認証準備。`browser-attachments`・所有権管理・Windows script を同梱 |
| `domain-modeling-studio` | 外部 `domain-modeling` と同梱 `ui-grill-with-docs`。生成時の Node.js、TypeScript 抽出時の Python・`ast-grep`。HTML／同梱資源と生成用の lockfile を移管 |
| `ui-grill-with-docs` | 外部 `grilling`、`domain-modeling`、`codebase-design`、必要時の `playwright-cli`。質問シートの資源を同梱 |
| `md-claude-review` / `md-agents-review` | 両者の役割分担と参照を維持。前者の `claude-api` 連携と既存の fallback 条件を明記し、後者へ不要な外部依存を追加しない |
| `marp` / `rop` | 前者は公式の Marp CLI と出力に必要な実行環境。後者は言語別 reference を同梱し、対象プロジェクトのツールを使う |
| `worktree-gc` | Bash、Git、必要経路の GitHub CLI・Python と実装が使う一般ツール。fan-out script と検査を同梱し、削除経路の OS 条件を事前確認 |

`playwright-cli` の上流 skill・CLI は第三者依存のままにする。一方、dotfiles が足しているソケットパッチ、WSL2 managed browser 用ラッパー、所有権管理、Windows script、skill 追記は独自資産として新リポジトリから供給する。上流の版・ライセンスを保持し、通常の外部 CLI 導入と WSL2 専用経路を区別する。

専用機能の最低限の対応条件は次のとおりで、対象外環境での機能拡張は今回の移行へ追加しない。

| 機能 | 条件と条件外での扱い |
| --- | --- |
| raw Codex の隔離起動 | Linux／WSL2＋Nix＋対象 repo の flake。条件外では起動を保留 |
| `pr-screenshots` の現行添付ブラウザ経路、WSL2 managed Chrome 経路 | WSL2 と Windows 側の準備が必要。未準備・未認証なら既存の引継ぎ手順を案内 |
| `worktree-gc` fan-out の `--apply` | Linux／WSL2 で必要な `/proc` 検査が可能な場合だけ。macOS 等では削除を実行せず、利用可能な preview と既存の repo 単位手順を案内 |
| 専用 auto peer | 対応する runtime の保護設定・実効性確認と、人間による資格情報準備・有効化が必要。未有効・確認不能なら保留 |

`domain-modeling-studio/dist/THIRD-PARTY-LICENSES.txt` は、生成 HTML に含める第三者コードのライセンス表示として移行後も保持する。

### 専用機能の対応条件を維持する理由

Nix なしという目標を全11件の全経路へ適用すると、既存の専用機能には移動以上の変更が必要になる。最終確認のためのソース調査で次を確認した。

- [`git-push-topic`](../../private_dot_local/bin/executable_git-push-topic)、[`gh-review-thread`](../../private_dot_local/bin/executable_gh-review-thread)、[`orca-send`](../../private_dot_local/bin/executable_orca-send) は実装から Nix を呼ばない。[`codex-reviewer`](../../private_dot_local/bin/executable_codex-reviewer) も Nix を直接要求しないが、dotfiles 内の共有 Python module の切り出しが必要である。
- [`playwright-cli.nix`](../../private_dot_config/nix-devshell/packages/playwright-cli.nix) はブラウザ関連の Node.js script、Playwright Core、補助ファイルなどの配布を担う。この配布方式は Nix なしへ移せるが、[`managed-chrome-owner.mjs`](../../private_dot_config/nix-devshell/packages/managed-chrome-owner.mjs) のプロセス識別は Linux の `/proc` を使う。
- [`codex-worktree`](../../private_dot_local/bin/executable_codex-worktree) が使う [`devshell_environment.py`](../../private_dot_local/share/devshell-env/devshell_environment.py) と [隔離実装](../../private_dot_local/share/codex-isolation/secret-isolation-worktree.py) は Nix と対象 repo の `flake.nix` を要求する。[既存の対応範囲](../../runtime/shell-environment.md)も Linux／WSL2 で、macOS の raw 隔離は未対応である。

このため、plugin の導入と汎用 skill を Nix 不要にし、既存の専用機能は機能ごとの OS・依存条件を維持する方針を採用した。Nix が配布だけを担う補助 CLI は独立配布へ切り出し、raw Codex の隔離起動などは必要条件を明示する。条件を満たさない場合は保護を弱めて代替せず、対象機能の処理前に案内する。専用機能も含めた全機能を Linux・macOS・WSL2 と Nix なしへ移植する案は、隔離機構などの再実装まで分離の範囲に加わるため採用しない。

## 公式仕様の確認

2026-10-29 時点の一次資料を確認した。以下は配布形式の判断材料であり、導入・呼び出しの実機検証結果ではない。

- [Agent Skills 仕様](https://agentskills.io/specification): skill 本体は `SKILL.md` と任意の同梱資源から構成する。
- [OpenAI の skill 作成ガイド](https://learn.chatgpt.com/docs/build-skills): 継続的な再利用・配布には plugin を推奨する。[plugin のパッケージ化ガイド](https://developers.openai.com/plugins/build/plugins) は新規パッケージにルートの `plugin.json` と Agent Plugins schema を推奨し、`.codex-plugin/plugin.json` を互換経路として説明している。
- [Claude Code の plugin manifest 仕様](https://code.claude.com/docs/en/plugins/manifest-reference): manifest は `.claude-plugin/plugin.json` に置き、component は plugin 名の namespace に属する。[marketplace 作成ガイド](https://code.claude.com/docs/en/plugin-marketplaces) は `.claude-plugin/marketplace.json` による配布を説明している。
- [Antigravity の skill ガイド](https://antigravity.google/docs/skills)、[plugin ガイド](https://antigravity.google/docs/plugins)、[marketplace ガイド](https://antigravity.google/docs/marketplace): App／CLI／IDE の skill・plugin 配置を区別し、CLI は GitHub URL またはローカル plugin を `agy plugin install` で導入できる。manifest の仕様と対応バージョンは実装前に照合する。

### Antigravity の形式確認

導入済みの Antigravity CLI 1.4.8 で、公開情報だけの使い捨て fixture を一時 HOME／XDG の下で `agy plugin validate <path> --strict --json` により確認した。ルートの Agent Plugins schema を宣言した `plugin.json` と skill 1件は exit 0 で受理され、同名の `.claude-plugin/plugin.json` を併設した場合も警告なしで同じ1件を検出した。

一方、同じルート manifest に `.antigravity-plugin/plugin.json` を併設した場合は後者が優先され、ルート manifest が無視される警告によって strict 検査は exit 1 となった。`.claude-plugin/plugin.json` のみでは Antigravity 用 manifest が見つからず exit 1 となった。記録は `/tmp/codex/plugin-format-probe.8KnK5N/validation-results.json` に保持している。

これはローカル validator による形式と静的な skill 検出件数の確認であり、インストール・実セッションでの discovery・skill 呼び出しの証明ではない。live の plugin 設定は変更していない。
