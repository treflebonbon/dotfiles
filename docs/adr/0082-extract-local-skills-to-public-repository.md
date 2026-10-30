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

## 現行の固定版と所有権（2026-10-30）

dotfiles が導入する正本は、[`skills-plugin.json`](../../private_dot_config/nix-devshell/skills-plugin.json) にある単一 pin である。現在の accepted record は `treflebonbon/skills` の commit `7428e0567c61ba888e0ed7e07a2c02b4a2edc1c2`、tree `e7735ed5a60c63929d3e6ce5d57bfefeae4bf6e7`、version `0.2.3`、NAR `sha256-Z7R7ZdSjxYcekJI3frBVZx6+9R8+3dmnKBFrOOmyPL8=`、267 files。owner / repo / full `rev` / tree / version / NAR hash / file count を一組として照合し、別の runtime 用 pin は作らない。

同じ公開 payload は Git checkout と `.git` を除いた plugin source snapshot の間で、全 tracked file の内容・mode・tree を一致させる。全3 runtime は同じ pin から導入する: Claude Code は `~/.claude/plugins` 配下、Codex は native `~/.codex`・存在する `~/.codex-app`・明示 `CODEX_HOME` の `plugins/cache/treflebonbon/treflebonbon-skills/<version>` を重複なく照合し、Antigravity CLI は `~/.gemini/config/plugins/treflebonbon-skills` と import inventory を照合する。過去の receipt だけではどの runtime の current install も証明しない。

skill 本体、専用補助 CLI、共用 Python module、規範契約、WSL2 browser helper は公開 repository が所有する。dotfiles は single pin、公式 runtime 導入、端末固有の config・Nix wrapper・dispatch、旧配備からの安全な移行を所有する。5つの共用 CLI は `git-push-topic`、`git-push-reviewed`、`gh-review-thread`、`orca-send`、`codex-reviewer`。Nix の browser package は同じ公開 pin の資産を取り込み、上流 Playwright CLI 0.1.22 とその lock・license を維持する。第三者 skill は APM で別途導入し、独自 dependency resolver や公開 payload の dotfiles 内コピーは作らない。

公開 repository 自体は別の受入で immutable な `0.2.3` を確定し、公開 quality は Python 70 pass / 4 skip、Node 31 pass、Bats 476 pass / 11 skip、fresh native 33、Nix 不要の導入、公開 archive と pin の一致を確認した。これらは公開 package の結果であり、dotfiles consumer 検証の代用ではない。Linux VM driver の build は成功したが検証 host に `/dev/kvm` がなく guest 実行は未確認である。Antigravity App／IDE、実 Windows Chrome、macOS と aarch64 の runtime 実機確認もこの受入記録では保証しない。

## 受入条件

以下は2026-10-29 の設計対話でユーザーが合意した受入条件である。実装・受入の根拠と、実機で未確認の範囲は本 ADR の「現行の固定版と所有権」および dotfiles 側の実装 report に追記する。

1. dotfiles と Nix がない環境で、公開リポジトリと記載された外部依存だけから plugin を導入し、汎用 skill を利用できる。必要な補助 CLI・契約・同梱資源を解決でき、dotfiles の checkout や `~/runtime/` の存在を必須にしない。専用機能は合意した OS・依存条件の下で利用できる。
2. Claude Code、Codex、Antigravity CLI の公式経路で導入し、新規セッションで全11件の検出と公式名による呼び出しを確認する。同梱 skill 間の相互参照、第三者 skill の実際の呼出し名、同梱資源・補助 CLI・子プロセスのパス解決を検証する。Antigravity App／IDE は公式手順の案内を用意する。
3. 既存機能と承認・検証・秘密保護の境界を維持する。依存不足は処理前に案内し、無関係な skill は利用できる。専用 auto は保護設定が欠損・不正・未有効の場合に起動を保留し、通常 session へ自動で切り替えない。認証・資格情報の準備など人間の操作が必要な確認と、自動検証した内容を区別する。
4. skill 本体と専用補助ツールのテストは新リポジトリへ移し、dotfiles には版の固定・公式 plugin 導入・更新・旧配備からの移行を検証する統合テストを残す。全11件の frontmatter を Agent Skills 仕様で検証し、契約の上限値・保護設定の投影・共通 script の同一性も正本と照合する。対応環境ごとの実行結果と未確認の範囲を記録し、validator の成功だけを実動作確認としない。
5. dotfiles の導入元と実際の plugin 本体が固定 SHA に対応し、公開 version と内容も一致する。実行後も配布物の内容は変わらず、依存準備・出力は別領域へ置く。再実行で二重導入や設定の継続的な差分を生まず、既知の旧版へ戻す手順を示す。
6. 全3 runtime の導入確認後に、今回の11件が旧方式で重複検出されない状態へ移行する。どれかの導入が失敗・未確認なら旧配備を維持する。撤去は明示した旧配備パスに限定し、既知の移行前内容との差分があれば表示して当該対象を残す。無関係な APM 配備や利用者の skill を削除しない。
7. MIT と既存の著作権・第三者ライセンス表示を保持し、README に導入、依存、機能ごとの対応環境、呼び出し、更新と移行の手順を記載する。

## runtime 導入・更新の運用契約

独立公開 package は上記 accepted pin を正本とする。dotfiles の pin を更新するときは、新 version に対応する immutable commit の全 pin metadata を一度に選び、同じ source から3 runtime と共用資産を導入する。source checkout を利用中に書き換えない。新 pin と config の通常同期が成功した後、`sync-codex-managed-config --verify-only` で各 current Codex config の exact version cache grant / deny を読み取り照合し、続けて `sync-skills-plugin --verify-only` で current source・receipt・全 runtime の現在の plugin inventory / payload を読み取り照合する。両方が同じ current state で成功するまで、旧配備の撤去へ進まない。receipt の過去成功は現在の runtime state の証明に使わない。

この作業の全体受入前は live 配備に触れない。受入後は merge 済み live source の `chezmoi diff` を確認し、無関係な差分がないことを確かめて通常の `chezmoi apply` を実行する。移行時の撤去 gate は `run_onchange_after_codex-managed-sync.sh.tmpl` に接続され、path 指定 apply では hook が対象にならず旧配備を保持する。通常 apply に不要な差分が混在する場合は実行せず、先に差分の解消を報告する。[編集・配備ルール](../architecture.md)に従う。

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

### 旧配備の撤去と再開

[ADR-0047](0047-local-skill-membership-and-explicit-retirement.md) が定めた「source 内の配置から配備対象を導出し、名前で撤去する」契約は、対象11件の旧 runtime copy に対して本節へ置き換える。他の APM-managed skill と Matt managed set の所有権・更新 gate は維持する。

比較基準は移行前 revision `6d5b73dd8b9c88531a74e724ca9d83fa34b44b35` から固定した11 skill、113 files、39 directories の payload と各 file / directory の mode である。新しい公開 plugin の内容とは比較しない。撤去範囲は明示した11名と既知の runtime 配備 path の積に限る。ユーザーが変更した内容、未知の追加・欠損、読取不能、symlink、special file、検査中の消失・競合は理由と path を報告して保持する。各 file の最終撤去直前にも一致を再確認し、検査できない残りがあれば parent directory を消さない。部分失敗後の再実行は、現行 plugin の full current verification と残存 path の baseline 比較をやり直す。過去の successful receipt は許可に使わない。

通常の `run_onchange_after_codex-managed-sync.sh.tmpl` は mutating な `sync-codex-managed-config` が成功した後、`sync-codex-managed-config --verify-only`、`sync-skills-plugin --verify-only` の順に current state を確認し、両方が成功したときだけ `legacy_skills retire-known-skills` を呼ぶ。撤去 helper は current pin、移行前 baseline、5つの live CLI shim と pinned CLI / module / APM lock の所有権を照合し、11名の既知の旧 copy を file ごとに最終再確認してから unlink する。directory は空の場合だけ rmdir する。どの gate も失敗・未確認なら撤去を行わず、残す対象の理由と path を記録する。`sync-codex-managed-config --verify-only` は current config を読み取るだけで、cache directory や file を作成・更新しない。

この移行では対象11件を既存の APM `retired` 一覧へ加えて通常 cleanup へ任せたり、保持一覧にない directory を一括削除したりしない。APM が所有する他 skill、無関係な user skill、unknown asset は保持する。旧 source が空の場合も不在の場合も、公開 pin からの render・導入・同期・再実行は成立させる。対象は task source の旧 tracked copy と test fixture に限り、利用者 HOME の実データはこの作業で削除しない。

新 SHA が不調なら既知の旧 pin record 全体（owner / repo / rev / tree / version / NAR hash / file count）を戻し、公式同期後に両 read-only verifier で再確認する。CLI 復旧は `sync-skills-plugin --run-cli <name> -- <arguments>` が current public CLI を検証して優先し、固定 manifest の hash / mode と一致する旧5 CLI snapshot だけに fallback する。snapshot は `$XDG_STATE_HOME/treflebonbon-skills/legacy/6d5b73dd8b9c88531a74e724ca9d83fa34b44b35/` に保存し、未指定時は `~/.local/state/` を使う。欠損・不正な snapshot を無検証でコピーしない。

[ADR-0075](0075-adopt-peer-refactor-skills.md) の元候補固定、通常の明示協働、専用 auto の追加保護は維持し、skill・契約・CLI の正本と配布だけを公開 repository へ移す。専用 auto の実効保護を確認できない場合は保留する。runtime の設定や資格情報を自動で有効化・生成しない。

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

- [`git-push-topic`](../../private_dot_local/bin/executable_git-push-topic.tmpl)、[`gh-review-thread`](../../private_dot_local/bin/executable_gh-review-thread.tmpl)、[`orca-send`](../../private_dot_local/bin/executable_orca-send.tmpl) は実装から Nix を呼ばない。[`codex-reviewer`](../../private_dot_local/bin/executable_codex-reviewer.tmpl) も Nix を直接要求しないが、dotfiles 内の共有 Python module の切り出しが必要である。
- ブラウザ機能の正本は [`skills-plugin.json`](../../private_dot_config/nix-devshell/skills-plugin.json) が固定する公開 `packages/wsl2-browser/` とする。[`playwright-cli.nix`](../../private_dot_config/nix-devshell/packages/playwright-cli.nix) は上流 `@playwright/cli` と browser driver の条件を保ち、公開 package の補助資産を Nix 用に包装する。`managed-chrome-owner.mjs` のプロセス識別は Linux の `/proc` を使う。
- [`codex-worktree`](../../private_dot_local/bin/executable_codex-worktree) は固定版 plugin の `bin/codex-worktree` と共通 `lib/python` module へ接続し、隔離実装の正本を公開側に置く。raw 経路は引き続き Nix と対象 repo の `flake.nix` を要求する。[既存の対応範囲](../../runtime/shell-environment.md)も Linux／WSL2 で、macOS の raw 隔離は未対応である。

このため、plugin の導入と汎用 skill を Nix 不要にし、既存の専用機能は機能ごとの OS・依存条件を維持する方針を採用した。Nix が配布だけを担う補助 CLI は独立配布へ切り出し、raw Codex の隔離起動などは必要条件を明示する。条件を満たさない場合は保護を弱めて代替せず、対象機能の処理前に案内する。専用機能も含めた全機能を Linux・macOS・WSL2 と Nix なしへ移植する案は、隔離機構などの再実装まで分離の範囲に加わるため採用しない。

## 公式仕様と形式確認

2026-10-29 時点の一次資料を配布形式の判断根拠として確認した。導入・呼び出しの受入結果は上記の固定版記録と公開側の受入 report に置き、この節の validator 結果だけを実機確認とは扱わない。

- [Agent Skills 仕様](https://agentskills.io/specification): skill 本体は `SKILL.md` と任意の同梱資源から構成する。
- [OpenAI の skill 作成ガイド](https://learn.chatgpt.com/docs/build-skills): 継続的な再利用・配布には plugin を推奨する。[plugin のパッケージ化ガイド](https://developers.openai.com/plugins/build/plugins) は新規パッケージにルートの `plugin.json` と Agent Plugins schema を推奨し、`.codex-plugin/plugin.json` を互換経路として説明している。
- [Claude Code の plugin manifest 仕様](https://code.claude.com/docs/en/plugins/manifest-reference): manifest は `.claude-plugin/plugin.json` に置き、component は plugin 名の namespace に属する。[marketplace 作成ガイド](https://code.claude.com/docs/en/plugin-marketplaces) は `.claude-plugin/marketplace.json` による配布を説明している。
- [Antigravity の skill ガイド](https://antigravity.google/docs/skills)、[plugin ガイド](https://antigravity.google/docs/plugins)、[marketplace ガイド](https://antigravity.google/docs/marketplace): App／CLI／IDE の skill・plugin 配置を区別し、CLI は GitHub URL またはローカル plugin を `agy plugin install` で導入できる。manifest の仕様と対応バージョンは実装前に照合する。

### Antigravity の形式確認

導入済みの Antigravity CLI 1.4.8 で、公開情報だけの使い捨て fixture を一時 HOME／XDG の下で `agy plugin validate <path> --strict --json` により確認した。ルートの Agent Plugins schema を宣言した `plugin.json` と skill 1件は exit 0 で受理され、同名の `.claude-plugin/plugin.json` を併設した場合も警告なしで同じ1件を検出した。

一方、同じルート manifest に `.antigravity-plugin/plugin.json` を併設した場合は後者が優先され、ルート manifest が無視される警告によって strict 検査は exit 1 となった。`.claude-plugin/plugin.json` のみでは Antigravity 用 manifest が見つからず exit 1 となった。記録は `/tmp/codex/plugin-format-probe.8KnK5N/validation-results.json` に保持している。

これはローカル validator による manifest 形式の確認である。実際の plugin install・CLI discovery・skill 呼び出しは固定版の受入 report で別に記録し、この fixture validator の結果と混同しない。live の plugin 設定は変更していない。
