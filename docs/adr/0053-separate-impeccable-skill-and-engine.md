# Impeccable のスキルと launcher は APM、固定 engine は Nix が供給する

Impeccable 4.2.2 は Node hook から Rust engine へ移ったため、スキルの pin だけを更新すると既存の存在確認が無言で終了し、global Design Hook が失われる。スキルと launcher は APM の exact pin、engine 0.1.3 は対応3 system の公式 release asset と固定 hash で Nix が供給し、両者と Claude / Codex の管理 hook を同じ互換性検証・採用単位にする。Nix が `IMPECCABLE_BIN` に engine の絶対 path を渡し、管理 hook は実行可能な engine と launcher の存在を確認して呼ぶことで、通常の hook 実行を自動ダウンロードに依存させない。

新規プロジェクトでも user-global の `PostToolUse` / `Stop` を使い、project ごとの有効化は追加しない。quiet、5秒 / 30秒、失敗 stdout の破棄と fail-open、provider ごとの正常出力、project 設定・cache の所有先、理由付き `ignore-value` と file / rule 全体の明示承認境界を維持する。実 engine を通す検証が成功するまで片側だけを採用せず、live 配備は全単位の受入・merge 後に live source から行う。

[Issue #243](https://github.com/treflebonbon/dotfiles/issues/243) の設計時に予約された番号0052は、先行 merge で別の ADR が使用したため、本判断を0053に記録する。採用物、検証結果、上流 `context` の global 設定探索の制限は[実装記録](../research/impeccable-engine-243.md)を参照する。
