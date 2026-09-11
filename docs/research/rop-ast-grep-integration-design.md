# ROP visualizerへのTypeScript構文補助の導入設計

状態: 実装・検証・コードレビュー完了。PR #306 の比較実験を受けた別の変更。live環境への反映は受入後。

## 目的と前提

TypeScript EffectのROPフロー図を作る際に、ast-grepが返す構文とソース位置を読解の補助として利用する。元ソースから失敗伝播・回復スコープを判断する責任は引き続きモデル生成側にある。構文の包含やメソッド名を、型・参照解決の確定情報として扱わない。

[比較実験](rop-visualizer-analysis-comparison.md)ではTypeScriptのast-grepを次の導入候補とし、Rustは現行維持とした。差は小さく、型解析の優位性や網羅的な正しさは証明していない。本変更でもRustの手順は維持する。

## 合意済み

- Q1: TypeScript Effectの可視化ではast-grepを標準で試行する。
- Q2: 未導入・抽出失敗時は、その理由を成果物に記録して従来のソース読解で続行する。

出典: ユーザーの「Q1:推奨案 Q2:推奨案」。

## 第2ラウンドの合意

- Q3: ast-grepをdotfilesの共通ツール環境へ追加する。
- Q4: 初回の対象は.tsと.tsx。指定した入口と関連ファイルに限定し、repo全体の一括走査はしない。

出典: 第2ラウンドの推奨案に対するユーザーの「ok」。Q1〜Q4の合意をもとに実装する。

## 導入前の構成

- `local-skills/rop-visualizer/SKILL.md` はソース読解、flow.json作成、既存rendererによるHTML生成、表示検査の順。構文抽出工程はまだない。
- `local-skills/rop-visualizer/` 内の同梱ファイルは既存のlocal skill配布経路で配備できる。
- ast-grepはroot flakeおよび共通ツール環境の管理対象に含まれていない。
- 他repoで使う共通CLIの配布先は `private_dot_config/nix-devshell/`。root flakeはdotfiles編集用である。

## 実装

スキルにTypeScript用の小さな抽出ヘルパーと利用手順を同梱する。対象はユーザーが指定した入口と、既存の読解手順で必要と判断した関連ファイルに限定する。出力した構文証拠を元ソースと照合してflow.jsonを作り、rendererの形式と画面操作は維持する。

抽出の成功・未導入・失敗を区別して記録する。失敗理由は成果物のlimitations等の既存説明欄で示し、正常終了した空の抽出結果と混同しない。対象プログラムは実行しない。

検証は、抽出対象のソース範囲、通常メソッドとEffect操作の混同防止、未導入・異常終了・空結果、選択した拡張子を対象とする。既存の意味・表示契約も維持する。実装時に必要なテストを具体化し、75回の比較生成を自動的に繰り返すものとはしない。

配布sourceへの変更はこのtask branchで行い、live環境へのapplyは受入後に行う。可逆な機能追加なのでADRは作らず、設計の合意をこのメモに記録する。

### 実装した入口と動作

- `local-skills/rop-visualizer/scripts/extract-typescript.py` が明示した.ts/.tsxを読み、標準入力経由でast-grepへ渡す。対象repoのast-grep設定を拾わないよう、一時ディレクトリで走査する。
- `status` は `ok` / `unavailable` / `failed`。抽出失敗は部分的なnodesを返さず、原因を記録する。正常な空結果は `ok` として扱い、失敗と区別する。
- 原文とbyte範囲を照合し、元ファイルの行範囲・ハッシュ・構文の包含を返す。型・呼び先・回復スコープの解決は行わない。
- `references/typescript-evidence.md` にコマンドと解釈・継続手順をまとめ、SKILL.mdのTypeScript分岐から必ず読むようにした。renderer・report schema・Rust手順は維持する。
- 共通devShellに `pkgs.ast-grep` を追加。既存lockの0.42.1を使い、lock更新や実行時インストールは行わない。

### 検証

- 抽出器contract: 11テスト成功。固定済み0.42.1を使った.ts/.tsx・Unicode範囲・構文エラー・CLI出力を含み、nativeテストのskipなし。
- 既存renderer contract: 8テスト成功。
- Linuxのdefault/wsl devShellを評価し、ast-grep 0.42.1がnativeBuildInputsに含まれることを確認。バイナリも同じ固定済みNix入力から取得して検証した。
- 配布検証: 隔離したHOMEでlocal skill配布hookを実行し、抽出ヘルパーとreferenceが `.agents` / `.claude` に同梱されることを確認。`tests/rop-visualizer.bats` 全3件成功。live環境は変更していない。
- コードレビュー: 実装commit `54f9a4c` を規約・仕様の2軸で独立レビューし、修正を要する指摘なし。明示ファイル限定、失敗時の継続、構文情報の解釈、配布先が合意と一致することを確認した。
- PR #309レビュー対応: `ERROR` がない欠落トークンでも部分的な構文証拠が成功扱いになる問題を再現し、program配下のゼロ幅ノードを検出してバッチ全体を失敗とするルールを追加した。TS/TSXの閉じ括弧・波括弧欠落を回帰テストで確認し、空ファイル・コメント・空文字列・空配列・空関数・JSXは成功することも確認した。
