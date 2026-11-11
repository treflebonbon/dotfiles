# Fable 5.2 対応と公開 skills 0.2.8（2026-11-11）

依頼原文は「`$implement ツールとスキル更新。fable 5.2、treflebonbon/skills 0.2.8`」。`test/beluga` の PR #586 がマージ済みで、fetch 後の `origin/main` と tree が一致していることを確認した。同じ Orca worktree で `origin/main` の `24f0b59856ccbec4dc94a0697eed9bce9748c128` から `chore/update-tools-skills-20261111` を作成した。

## 更新単位

- **AI ツール**は `llm-agents` の URL と lock を upstream `main` の `2b6455a7711d6dc90e42e555c1ddb504481268f4` に進める。Claude Code 2.1.319 → 2.1.322、Copilot CLI 1.0.107 → 1.0.109、Antigravity CLI 1.5.3 → 1.5.5 を取り込む。Fable 5.2 は Claude Code 2.1.321 から対応し、管理設定の `sonnet` は既定モデルとして維持する。対応する接続先では `/model claude-fable-5-2` で明示選択できる。共有 nixpkgs、独立した APM、Claude Code と Codex の品質 floor は従来どおりとする。 [ADR-0045 の 2026-10-31 amendment](../adr/0045-separate-llm-agents-and-apm-update-units.md#2026-10-31-amendment-apmを除いてllm-agentsの出力を更新する)、[Claude Code のモデル設定](https://code.claude.com/docs/en/model-config)、[2.1.321 のリリース](https://github.com/anthropics/claude-code/releases/tag/v2.1.321)
- **公開 skills plugin** は `skills-plugin.json` の単一 pin と ADR の現行版を v0.2.8 に進める。PR 証跡アップロードとブラウザーの実行環境確認の修正が、同じ pin を読む Nix の Playwright パッケージにも反映される。 [ADR-0082 の runtime 導入・更新の運用契約](../adr/0082-extract-local-skills-to-public-repository.md#runtime-導入更新の運用契約)、[skills v0.2.8](https://github.com/treflebonbon/skills/releases/tag/v0.2.8)

今回は指定された二つの更新単位を同じブランチで扱う。第三者 APM payload と個別 CLI の一括更新は対象外とした。

## 個別検証

- 両 flake の `nix flake check --no-build --all-systems` と TypeScript の型検査が成功した。対応3環境で6ツールの出力を評価し、Numtide cache の18出力を確認した。Codex 0.167.0 と code-review-graph 2.3.9 は出力のみ更新され、Herdr と独立 APM は derivation と出力が一致した。
- v0.2.8 のタグ、配布 manifest の版、tree、283 ファイル、NAR hash を照合した。公開版の WSL2 ブラウザーパッケージで Node 18 件と添付・PR 証跡の Bats 18 件がすべて成功した。
- 0.2.8 の資産を組み込んだ Nix Playwright パッケージで関連 Bats 3 件が成功した。実装コミット `8f26e26` の独立レビューは Standards、Spec ともに指摘0件だった。
- Linux では候補 devShell の6 CLI の実体パスと版表示を照合した。Claude Code、Codex、Antigravity CLI の公式 CLI で 0.2.8 を隔離環境に導入した。Claude Code 2.1.322 で2回再同期し、管理設定と283ファイルが一致した。記録は `/tmp/codex/claude-plugin-native.2hsk7ljt/result.json` に保存した。
- Nix の取得停滞後は同じ署名付き Numtide 配布物を取得し直した。検証時の一時 flake registry は、`nix develop --file` が参照する `nixpkgs` を、その時点の `nixpkgs-unstable` と同じ `4fe25e12eb9f` の Nix store source に解決する。
- Fable 5.2 の実モデル呼出しと、ADR-0082 が求める新規モデルセッションでの全 33 件のスキル呼出しは未確認。0.2.7 での省略承認は引き継がない。ローカル検証のログは `/tmp/codex/update-tools-skills-20261111.ihDtTo/` に保存する。
