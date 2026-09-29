# CLAUDE.md レビュー判定基準

このファイルは skills/md-claude-review が利用する判定基準。出典は末尾参照。

レビューは 2 つの直交した層を持つ: **内容キュレーション層**（§1〜§6: 何を残す/削る/外出しするか = Keep / Trim / Move-to / Delete）と **文言品質層**（§7: 残す内容を対象モデルが正確に追従できる言い回しにするか = Reword。対象は実行中セッションのモデルで、固定しない）。

## 0. レビュー単位（何に判定を付けるか）

判定を付ける単位は次の両方。どちらも飛ばさない:

1. **前文（preamble）ブロック** — `# タイトル` 直下から最初の `## ` 見出しの前までの本文。実際の CLAUDE.md は編集ルール・各ファイルの役割・最重要の注意書きといった load-bearing な指示を前文に置くことが多い。`## ` 見出しが無いという理由で前文を skip すると、最も効く指示が成果物から脱落する。前文も 1 つの判定単位として Keep / Trim / Reword / Move-to / Delete のいずれかを付与する。
2. **各 `## ` セクション** — 見出し単位で 1 判定。

前文が複数の話題を含む場合は、話題ごとに判定を分けてよい（例: 編集ルールは Keep、自明な概要文は Delete）。分割するのは**話題が異なる verb を受けるときだけ**でよい。全話題が同じ決定になるなら 1 ユニットとして扱う。空でない前文は必ず 1 つ以上の判定を受ける。

## 1. Length

- humanlayer 推奨: **< 60 行**（HumanLayer 自身は 60 行未満）
- 公式ベストプラクティス: 自明な上限なしだが「短く人間が読める状態に保つ」
- 300 行を実用上の上限とみなす（それ以上は確実にスリム化対象）

## 2. WHY / WHAT / HOW フレームワーク（humanlayer）

各セクションは下記いずれかに分類できるべき:

- **WHAT**: tech stack, アーキテクチャ, ファイル構成
- **WHY**: プロジェクトの目的・コンポーネントの役割
- **HOW**: ワークフロー（ビルド、テスト、検証）

3 つのいずれにも当てはまらないセクションは削除候補。

## 3. ✅ 含めるべきもの（公式ベストプラクティス）

| 項目                                   | 例                          |
| -------------------------------------- | --------------------------- |
| Claude が推測できない Bash コマンド    | `task test`, 独自スクリプト |
| デフォルトと異なるコードスタイルルール | 言語標準と違う規約のみ      |
| テスト指示と推奨テストランナー         | 単一テスト推奨など          |
| リポジトリのエチケット                 | ブランチ命名, PR 規約       |
| プロジェクト固有のアーキテクチャ決定   | モノレポ構造, レイヤ分割    |
| 開発者環境の癖                         | 必須環境変数                |
| 一般的な落とし穴・明白でない動作       | edge case                   |

## 4. ❌ 除外すべきもの（公式 + humanlayer）

| 項目 | 理由 |
| --- | --- |
| Claude がコードを読むことで理解できるもの | 推測可能 → 削除 |
| 標準言語規約 | Claude が既知 → 削除 |
| 詳細な API ドキュメント | リンクで十分 → Move-to or Delete |
| 頻繁に変わる情報 | メンテコスト |
| 長い説明・チュートリアル | 別ファイル → Move-to |
| ファイルごとのコードベース説明 | コードを読めば分かる → Delete |
| 自明なベストプラクティス | "クリーンなコードを書く" 等 → Delete |
| **auto-generation で書かれた行**（humanlayer） | 高レバレッジな手書きにすべき |
| **lint ルールの自然言語化**（humanlayer） | hook で決定論的に |
| **コードスタイル例**（humanlayer） | in-context learning に任せる |

## 5. 「削除すると Claude が間違うか?」テスト（公式）

各セクション・各行について次を問う:

> _「この記述を削除すると、Claude が（このプロジェクト固有のことで）間違いを犯すか?」_

- **Yes** → Keep または Trim（残す）
- **No** → Delete または Move-to（削除/外出し）
- **判断つかず** → Trim（短縮して残す）

## 6. Move-to 候補

本リポジトリ前提の外出し先:

| セクション内容 | Move-to 推奨先 |
| --- | --- |
| アーキテクチャ詳細・hook 仕様・スキル frontmatter 仕様 | `docs/architecture.md` |
| 規約・設計判断（ADR） | `docs/conventions.md` / `docs/adr/` |
| Claude へのルール（trust posture, Bash 禁止事項等） | `.claude/rules/` |
| 推測可能・標準的な情報 | （Move-to ではなく Delete） |
| 長い tutorial / API 詳細 | 該当 lib の `docs/` 配下 |

`@import` を使って CLAUDE.md から参照する形にすると、Claude のコンテキストを汚さず必要時のみロードできる（Progressive Disclosure）。

## 7. 文言品質（残す指示の言い回し）

内容キュレーション（§3〜§6）とは直交する層。**残す**と判断したセクションについて、対象モデルが指示を正確に追従できる言い回しかを点検する。該当すれば **Reword**（内容は残し言い回しのみ修正。該当する一文だけの削除もここに含む）を提示する。対象モデルは、レビューを実行しているセッションのモデルとする。

### 最新化手順（§7 を適用する前に毎回実行）

モデル世代が上がると、古い世代向けの補正は不要になり、新しい世代向けの補正が必要になる。行の有効性を固定せず、次の手順で確認してから適用する。

1. 対象モデルを特定する（実行中セッションのモデル ID）。
2. WebFetch で <https://code.claude.com/docs/en/best-practices> を取得し、CLAUDE.md の書き方（含める/除外、強調、削除テスト、hook への置換）が §3〜§5 と §7a に矛盾しないか確認する。
3. 対象モデル世代の公式 prompting / migration ガイドを取得し（best-practices 末尾の関連リンク、または <https://code.claude.com/docs/llms.txt> から辿る）、§7b の各行が対象モデルで有効かを確認する。無効または逆転している行は適用せず、レポートに「基準の更新提案」として記す。
4. 取得できない場合は §7b を適用せず §7a のみで判定し、その旨をユーザーに伝える。
5. 基準そのものの更新は、ユーザーの確認後にこのファイルの該当行と「検証」行を編集して行う。

### 7a. 世代に依存しない行

| アンチパターン | 検出の目印 | Reword 方針 | 根拠 |
| --- | --- | --- | --- |
| 過剰強調語 | `CRITICAL` / `MUST` / `ALWAYS` / `NEVER` / 全大文字が複数行にある | 従われていない 1 行だけに強調を残し、真の invariant（安全・必須）でなければ通常語へ。強調が多いと全体が埋もれる | best-practices "Write an effective CLAUDE.md" |
| 否定指示 | "Do not 〜" / "〜しない" 中心の記述 | 望ましい行動を肯定形で記述（"Write in flowing prose"） | prompting best practices — Control the format of responses |
| WHY 欠落 | 非自明なルールに理由がない | なぜそうするかを 1 文添える。Claude は説明から一般化できる | prompting best practices — Add context to improve performance |
| 暗黙スコープ | 適用範囲を書かず全体適用を期待 | 範囲を明示（"apply to every section, not just the first"）。モデルは指示を文字通りに解釈し、暗黙の一般化をしない | prompting best practices — literal instruction following |
| 検証手段の欠落 | 完了前に実行するテスト・型検査・ビルドなどが書かれていない | 実際に実行するテスト・型検査・ビルドのコマンドを明記し、実行してから完了を報告するよう書く（プロジェクト固有の検証コマンドは §3 のとおり維持する） | best-practices "Give Claude a way to verify its work" |

### 7b. 世代別の再テスト候補

各行は、由来の世代で観測された挙動への補正。対象モデルが由来と異なる場合は、上の最新化手順 3 で有効性を確認するまで適用しない。

| アンチパターン | 由来 | 検出の目印 | Reword 方針 |
| --- | --- | --- | --- |
| 応答の冗長化 | Opus 5 | 簡潔さの指示がなく、応答の長さを effort 設定だけで制御しようとしている | 簡潔さを定性的に指示する一文を追加する（"Keep responses focused, brief, and concise"）。語数などの数値上限は付けない |
| 過剰検証・スコープ逸脱 | Opus 5 | "回答前に必ず自己検証する" のように、モデル自身の出力を一般的に再チェックさせる指示 | その一文だけを削除する候補。§7a の実行可能な検証手順と §3 のプロジェクト固有の検証コマンドは対象外で、削除しない |
| subagent 委任過剰 | Opus 5 | 委任してよい場面・上限の基準が書かれていない | 委任が正当化される条件（大規模・独立・並列可能）を明示し、単純作業は自分で完結するよう指示する |
| 進捗ナレーション過剰 | Opus 5 | 更新の頻度・粒度の指示がなく、実況が冗長になりやすい | いつ・どの粒度で報告するかを明示する（開始前に一文、要点のみ短く、完了時は結論を先に） |
| ツール使用抑制 | Sonnet 5.5 | "only use tools when strictly necessary" / "minimize tool calls" | 削除する。対象モデルは文字通りに従い、必要なツールまで使わなくなる |
| 頑張らせる煽り | Sonnet 5.5 | "do not be lazy" / "be thorough" / "never give up" など、前世代の早期終了への補正 | 削除して再評価する。現行モデルは既定で積極的に取り組む |

## 8. Decision matrix

| Criterion                     | Keep | Trim | Reword | Move-to | Delete |
| ----------------------------- | ---- | ---- | ------ | ------- | ------ |
| 推測可能                      |      |      |        |         | ✓      |
| 標準的・自明                  |      |      |        |         | ✓      |
| プロジェクト固有 + 短い       | ✓    |      |        |         |        |
| プロジェクト固有 + 長い       |      | ✓    |        | ✓       |        |
| 詳細な手順 / API              |      |      |        | ✓       |        |
| auto-gen の痕跡               |      | ✓    |        |         |        |
| lint で代替可能               |      |      |        |         | ✓      |
| 重複している情報              |      |      |        |         | ✓      |
| 過剰強調語（§7a）             | ✓    |      | ✓      |         |        |
| 否定指示（§7a）               | ✓    |      | ✓      |         |        |
| WHY 欠落（§7a）               | ✓    |      | ✓      |         |        |
| 暗黙スコープ（§7a）           | ✓    |      | ✓      |         |        |
| 検証手段の欠落（§7a）         | ✓    |      | ✓      |         |        |
| 応答の冗長化（§7b）           | ✓    |      | ✓      |         |        |
| 過剰検証・スコープ逸脱（§7b） | ✓    |      | ✓      |         |        |
| subagent 委任過剰（§7b）      | ✓    |      | ✓      |         |        |
| 進捗ナレーション過剰（§7b）   | ✓    |      | ✓      |         |        |
| ツール使用抑制（§7b）         | ✓    |      | ✓      |         |        |
| 頑張らせる煽り（§7b）         | ✓    |      | ✓      |         |        |

**Tie-break（複数の決定が当てはまるとき）**: 1 ユニットには verb を 1 つに絞る。

- 短縮と外出しの両方が必要なら、CLAUDE.md に何か残るなら **Trim**（残す部分を短縮し詳細は Move-to 先へ）、何も残らないなら **Move-to**。
- §7 行が Keep ✓ と Reword ✓ の両方に印が付くのは「内容は残す（Keep）が言い回しは直す（Reword）」の意。headline の verb は **Reword** とする（Keep と並記しない）。
- 1 セクション内に真の invariant（安全・必須）と非 invariant の過剰強調語が混在する場合は **Reword** を選び、Reword 方針の中で真の invariant の強調は残しつつ非 invariant のみ通常語へ。

## 出典

- humanlayer (Dexter Horthy), "Writing a good CLAUDE.md"
- Claude Code best practices（§3〜§5、§7a の根拠）: https://code.claude.com/docs/en/best-practices
- Claude 公式 prompting best practices（複数世代共通）: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices
- Claude 公式 Prompting Claude Opus 5（§7b の Opus 5 由来行）: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5
- Claude API 公式 Migrating to Claude Sonnet 5.5 — Behavioral shifts（§7b の Sonnet 5.5 由来行、§7a の検証手段）

## 検証

最終検証: 2026-09-29。Sonnet 5.5 セッションで best-practices ページと §3〜§5・§7a を突合し、§7b の Sonnet 5.5 由来行を migration ガイドと突合した。Opus 5 由来の 4 行は Sonnet 5.5 では未検証（再テスト候補）。新しい世代が出たら最新化手順を実行し、この行を更新する。
