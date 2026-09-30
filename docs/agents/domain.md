# Domain 文書

コード探索前に repo root の `GLOSSARY.md` と、対象領域に関係する `docs/adr/` を読む。存在しなければそのまま進める。用語が確定したときに `domain-modeling` が用語集へ記録し、採用基準を満たす判断だけを ADR に残す。

この repo は single-context。用語集は `GLOSSARY.md`、意思決定記録は `docs/adr/` に置く。ドメイン概念を issue、コード、仮説、テストへ記述するときは用語集の語彙を使い、ADR と矛盾する提案は対象の判断を明示する。

`runtime/` は chezmoi が `~/runtime/` へ配備する、全 repo に共通する環境知識。dotfiles 固有の構造・規約は `docs/architecture.md`／`docs/conventions.md`、全領域の判断は `docs/adr/` に置き、`runtime/` とは分ける（ADR-0006／ADR-0007）。
