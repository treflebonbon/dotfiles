# 公開 skills plugin 0.3.0 の採用（2026-11-19）

## 要件と更新単位

[treflebonbon/skills#95](https://github.com/treflebonbon/skills/issues/95)（親 #89、判断は skills の ADR-0004）に従い、`skills-plugin.json` の pin を 0.3.0 へ上げ、同じ変更で `runtime/skill-harness.md` の参照を移す。peer 規範（`autonomous-peer-contract.md` など）の撤去は #96 で行い、この変更に含めない。

## 公開版

- tag v0.3.0 の commit は `c34ef55bc8600493431ea0161d1eaaced4b89aff`、tree は `0c8aa3e1cb960e6ea6100ab6364f1e75b0999476`、345 files。
- GitHub archive を展開した source の NAR は `sha256-Zf7mVKovX/YJ45BkeoRoX0LYxSqDkD5u2f1REv+oVFk=`、ファイル数は tag の tree と一致した。

## 参照の移動

- Orca worktree の準備確認: `orca-peer-refactor/references/orca.md#worktree-readiness` への参照をやめ、要点を `runtime/skill-harness.md` に置き、共用 CLI `orca-worker-readiness` を指す。
- `orca-send` の本文サイズと argv 露出の制約: `#literal-message-body` への参照をやめ、`runtime/skill-harness.md` に移す。
- `improve-codebase-architecture` の HTML report: 構造検査 script をやめ、実ブラウザでの描画確認だけにする。
