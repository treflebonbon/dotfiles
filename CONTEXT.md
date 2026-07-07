# dotfiles ワークフロー

この repo のドメインは chezmoi 管理下の設計→実装ワークフロー（skill harness）そのもの。プロダクトコードではなく、エージェントが辿る手続きと、手続き間で受け渡す成果物の語彙を定義する。

## Language

**Contract**:
issue/PRD が定める「目的・AC・非目標・検証方法・関連ファイル/入口・判断済みtradeoff」の6項目。`ready-for-agent` 化の入口契約であり、`to-pr` が PR body へ埋め込む出口契約でもある。
_Avoid_: 仕様, spec, 要件定義

**Verification Matrix**:
`to-pr` が PR body に載せる AC ごとの検証記録表（列: AC / 種別 / 実行コマンドまたは理由 / 結果 / 未確認理由）。UI・CLI・API・infra 全ての AC を1つの表に統合する。
_Avoid_: evidence table, 検証エビデンス, verdict

**要素指差しフィードバック**:
`tdd` の実装サイクル中、人間が画面上の UI 要素を選択し、その場でエージェントへ変更を指示する対話チャネル（Codex CLI: Annotation Mode / Orca IDE: Design Mode / Claude Code: `claude-in-chrome`）。実装完了後にエージェントが自律的に検証する Verification Matrix とは主体（人間 vs エージェント）とタイミング（実装中 vs 実装後）の両方が異なる。
_Avoid_: UI verification, ブラウザ検証
