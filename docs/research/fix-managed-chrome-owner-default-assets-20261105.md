# managed-chrome-owner の既定 Windows 資産修正の取り込み（#574）

## 要件と変更範囲

依頼は「`$implement 574`」。[Issue #574](https://github.com/treflebonbon/dotfiles/issues/574) の受入条件に従い、Nix 配布の公開 `managed-chrome-owner` が、環境変数を設定しなくても同梱 Windows スクリプトを解決できるようにする。後続の「修正」指示には、取り込みを妨げていた上流 plugin の strict 検証エラーの修正を含める。

開始点は HEAD / `origin/main` `454e6815802a384229165b4fafb4122d5e18b4c3`。Orca native task worktree `nix-playwright-cli-managed-chrome-owner-windows-2`、branch `test/nix-playwright-cli-managed-chrome-owner-windows-2` の physical root・Git dir・common dir・clean status を fetch 後に照合した。dotfiles の実装・検証・レビュー・コミットを今回の範囲とし、dotfiles の PR 公開・merge・live 配備は含めない。

更新単位は公開 skills plugin の単一 pin と、それを利用する Nix browser package。ADR-0082 の「現行の固定版と所有権」「runtime 導入・更新の運用契約」に従い、owner / repo / rev / tree / version / NAR hash / file count を一組で更新する。予定する変更は `skills-plugin.json`、`tests/playwright-nix-package.bats`、ADR-0082 の現行版表記と本記録。既存の runtime 設定は同じ pin から版を導出し、別の pin や固定値を追加しない。

関連検証で必要と判明した追従として、`tests/helpers/playwright-runtime-distribution.py` の既存 PowerShell fixture も更新する。従来はすべての要求に `absent` を返していたため、新しい Windows 資産存在検査が失敗した。指定済みの仮想 `C:\mock.ps1` に対する `Test-Path` は `True`、同じスクリプトの `Inspect` は `absent` とし、それ以外の要求は拒否する。製品コードの検査を弱めず、既存の Dashboard・runtime lock 検証を維持する。

Windows 資産のコピー、暫定 `windows.ps1` alias、利用者の環境変数を恒久的な回避策にしない。所有権の状態機械、identity / port / profile 方針、自動復旧、実ユーザーの記録や profile の削除は変更しない。

## 上流の修正と公開

- 0.2.6 は browser の修正を含んでいたが、Antigravity CLI の strict validator が root `AGENTS.md` を未読の plugin 規則として警告し、採用を保留していた。以前の保留判断は[更新記録](update-tools-skills-20261105.md)に残す。
- [上流 PR #16](https://github.com/treflebonbon/skills/pull/16) は開発用指示を内容不変で `AGENTS.override.md` へ改名し、Claude Code の import と README を更新した。利用者向け `rules/` は追加していない。merge commit `5858e08be0cbf93c00e4eed0085e316729cd021c` と検証済み `21400e0` は同じ tree。
- [release PR #17](https://github.com/treflebonbon/skills/pull/17) の head `430b80174abcb838e70698c0d689ec6ac004d962` を検証した後、[v0.2.7](https://github.com/treflebonbon/skills/releases/tag/v0.2.7) が `126690ce21ef2e929236efbb3fa873686fed8131` として公開された。公開 commit と候補は tree・283 files・NAR hash が一致した。公開済みの同一 version の内容は書き換えていない。
- ユーザーは今回の 0.2.7 に限り、新規モデルセッションでの11 skill × 3 runtime の呼出し33件を省略する例外を明示的に受け入れた。この確認を実施済みとせず、今後の版へ例外を一般化しない。

| pin 項目 | 変更前 | 採用する公開版 |
| --- | --- | --- |
| owner / repo | `treflebonbon/skills` | 同じ |
| rev | `7428e0567c61ba888e0ed7e07a2c02b4a2edc1c2` | `126690ce21ef2e929236efbb3fa873686fed8131` |
| version | `0.2.3` | `0.2.7` |
| tree | `e7735ed5a60c63929d3e6ce5d57bfefeae4bf6e7` | `a7c72af1037291b9c3df46a0aabbd9ecdfb7b061` |
| NAR hash | `sha256-Z7R7ZdSjxYcekJI3frBVZx6+9R8+3dmnKBFrOOmyPL8=` | `sha256-RnKzL8lZagIldowvrDV14q7yC+RqpbaaCFvGlqIm+cM=` |
| file count | 267 | 283 |

0.2.3 からの上流差分は34ファイル。単一 pin の全体を採用し、公開 payload の一部だけを差し替えない。owner の既定資産名と資産存在検査に加え、次を同時に取り込む。

- 添付 helper が対象 identity の同梱 `status` / `recover` を案内し、`pr-screenshots` と利用文書も同じ復旧手順を示す。dotfiles 側に案内を再実装しない。
- `git-push-topic` が default branch の先に commit がない場合や merge 済み branch の続きの公開を拒否する。`gh` と origin の PR を読める認証が追加の実行時依存になる。通常の GitHub CLI 配布・認証経路は維持する。
- release-please、上流の hook・開発規約・検証 fixture と、開発用指示の配置が更新される。

今回は PR を分割しておらず、上記の必要変更を別案件へ保留していない。過去の更新記録の保留は当時の判断として保持し、この公開版の検証結果で再評価する。

## 検証

証跡は `/tmp/codex/fix-574-upstream.Qi0pxn/`、`/tmp/codex/release-027-acceptance.i1jdAq/`、`/tmp/codex/implement-574-consumer.sHpmjV/` に保存する。通常 HOME と配備済み plugin は変更せず、保護付き入口から検証した。

- **確認済み（上流）:** 0.2.7 候補の `npm test` は Python 71成功・4 skip、Node 39成功、Bats 494成功・11 skip・失敗0、終了コード0、実測759.735秒。HEAD と source が前後で不変だった。最初の通常 clone での試行は linked worktree を要求する既存検査で5件失敗し、Orca の linked task worktree で再実行した結果と区別する。
- **確認済み（公式 CLI）:** Antigravity CLI 1.5.0 の strict 検証は警告なし・11 skill・0 rules。format・lint と公式導入テスト4件が成功した。Claude Code の validator にある root `CLAUDE.md` と icon 不在の警告は残る。公式導入は Antigravity 1.5.0・Claude Code 2.1.317・Codex 0.166.0 を使い、一時 HOME 内で配布元の不変も照合した。
- **確認済み（Nix / red）:** 現行0.2.3の実配布物に対し、組み込んだ回帰テストが欠落した `libexec/windows.ps1` を `-File` に渡して失敗した。PowerShell fixture は渡された path と実ファイルの存在を検査する。
- **確認済み（Nix / 候補）:** 候補から実際に組み立てた Nix output では同じテストが成功した。3 role の既定資産と明示上書き、`activate` / `recover`、資産欠落・照会失敗・不明状態・Chrome 稼働中・起動未完了での記録保持、profile marker の不変、PowerShell を呼ばない `status` を確認した。
- **確認済み（公開 pin）:** 既存の `sync-skills-plugin` module で公開 commit の checkout と marketplace snapshot を検証し、全283ファイルの内容・mode・tree・version を照合した。候補と公開 archive の NAR hash も一致し、更新した pin から Nix package を実際にビルドした。
- **確認済み（dotfiles の関連検証）:** 初回120件中119成功・1失敗・skipなし。失敗は既存 PowerShell fixture が `Test-Path` にも `absent` を返す点であり、上記の追従後、配布物・runtime の対象5件はすべて成功・skipなし。既定パスの回帰テストも公開 pin の実 Nix output で成功した。全体検証では修正後の source を使用する。
- **確認済み（公式再同期）:** Claude Code 2.1.318 で公開 pin の公式導入と2回の再同期に成功した。両回とも管理設定6779 bytesと0.2.7の283 filesを保持した。記録は `/tmp/codex/claude-plugin-native.2io1tfuh/result.json`。
- **確認済み（Nix 評価・旧版検索）:** 両 flake の `nix flake check --no-build --all-systems` が成功した。旧版・旧 rev は現行設定と tests に残らず、`runtime/skill-harness.md` の2026-11-04の保留記録と ADR の初期受入実績は歴史として保持する。`git-push-topic` が新たに要求する `gh` は既存のユーザー devShell の Git module に含まれる。
- **未確認:** 実 Windows Chrome / PowerShell、GitHub 認証・添付、App / IDE、macOS / aarch64 の実機動作。新規モデルセッション33件は上記の今回限りの受入例外で未実施。各 suite の opt-in skip も成功件数に含めない。

dotfiles 側の最終全体検証は、独立レビューと修正後の clean な commit で `scripts/run-canonical.py --shell wsl --no-codex-build` から実行する。同じ実行の `tmp/canonical-run.*/result.json` と `tmp/test-run.*/tap.log` に、全件数・skip・失敗・終了コードと source / runtime の前後照合を残し、完了報告から具体的な記録へリンクする。検証後の結果追記で source を変えず、検証対象 commit と成果物の対応を保つ。live 配備は今回の完了範囲に含めない。
