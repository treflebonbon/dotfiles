# ponytail 監査指摘の修正（2026-11-04）

## 合意した範囲

ユーザーの「推奨案で進めて」に基づき、main `72db541476daeca4e82c1051cd9e1ab774658baa` の監査で提示した7件を修正する。実装は Codex native worktree の `fix/ponytail-audit-7-findings` で行い、公開・merge・live 配備は含めない。

| 指摘 | 修正と検証境界 |
| --- | --- |
| Herdr のコピー先所属検証 | 継承した Git 環境変数を除去する。別 repository の worktree を指すイベントを拒否し、コピーしないことを検証する。 |
| 空の `.codex` 修復 | Git index の読取りに失敗した場合は保持して失敗する。継承 Git 環境によって追跡判定が別 repository へ向かないことも検証する。 |
| Treesitter の API 不整合 | Neovim 0.12.4 を維持し、新 API の固定 commit へ移行する。ハイライト・インデント・選択キーと非同期導入完了後の有効化を実 Neovim で検証する。 |
| Claude の独自キャッシュ先 | 可変の root 名を固定 suffix の条件から外す。独自 root への同期後、現在状態の検証が成功し receipt を変更しないことを検証する。 |
| APM 台帳外のファイル | 管理 skill 内を再帰列挙して、台帳外の補助 script を拒否する。 |
| 旧 plugin 検証の重複 | Codex も既存の共通 payload 検証を使用する。既存の更新失敗・復旧・改変拒否テストで確認する。 |
| 未使用の hash helper | 現行呼出しがテストだけの helper と、その自己検証を削除する。旧 source の有無で配備結果が変わらない検証は残す。 |

公開 plugin の pin と payload、APM manifest／lock は変更しない。ADR-0082 の所有権・current-state 検証・旧配備撤去条件を維持する。Treesitter は他の tool／skill 更新とは分けて扱い、ADR-0045 の更新単位の原則に従って候補・検証・未確認範囲を記録する。

## Treesitter の追加確認

監査時は旧 API を保てる `master` の固定を推奨した。しかし、実装前に[公式の master README](https://github.com/nvim-treesitter/nvim-treesitter/blob/master/README.md) を読むと、Neovim 0.12 は明示的に非対応だった。実行環境の Neovim は 0.12.4 である。

このため、単純な master 固定は採用しない。ユーザーは「現行 Neovim を維持し、新 API へ移行する」を選択した。選択の拡大・縮小は 0.12 の native `vim.treesitter.select('parent'|'child')` で維持する。

公式の現行 main を隔離された一時領域へ導入し、候補 commit を `0195cd62fa89950f34c0e0d648ea7897ab85d4d3` に固定した。[公式 README](https://github.com/nvim-treesitter/nvim-treesitter/blob/0195cd62fa89950f34c0e0d648ea7897ab85d4d3/README.md) と候補の実装に従い、起動時に plugin を読み込み、新 API で parser を導入する。FileType 時と非同期導入完了時に利用可能な parser のハイライト・インデント・選択キーを有効にする。

parser 導入が必要とする `tree-sitter` CLI はユーザー devShell へ追加する。既存 nixpkgs の 0.26.8 を binary cache から取得でき、新しい CLI 本体のソースビルドは行っていない。Nix が既に供給する C compiler を使い、独自 parser builder や追加の選択用 plugin は導入しない。

## 検証状況

Herdr の継承 Git context、壊れた Git index、独自 Claude cache、APM 台帳外 script の各回帰テストは、修正前の失敗を確認してから対応した。最終の関連テスト・全 Bats・独立レビュー結果は作業完了時に追記する。

関連7 suite は63件が成功した。APM のファイル列挙を lint の複雑度上限に合わせて分離した後も、同 suite の20件が成功した。Treesitter の最後の確認では固定 commit と全設定言語の対応も照合し、標準 API の代用・実 plugin の両方で2件が成功した。parser の新規ダウンロード・コンパイルは行わず、同梱済み Lua parser を使った検証である。

保護された両 devShell で6 AI CLI の出力・実起動が一致し、追加した tree-sitter CLI も0.26.8で起動した。6件だけを実装した時点の途中の全 Bats は、Treesitter 方針の確定後に SIGTERM で中断した（exit 143）。これは最終結果やテスト失敗として扱わない。

### 最終確認

実装 commit `4257ffc` の clean な worktree から `scripts/run-canonical.py --shell default --no-codex-build` を実行した。実 plugin の checkout は `NVIM_TREESITTER_RUNTIME` で指定した。

- 全746件: 成功732、既定 skip14、失敗0。コマンドと runner はともに exit 0、実測188.518秒。
- source／HEAD／runtime の前後照合は一致し、canonical の `errors` は空。
- 必須の Design Hook 13件・Playwright runtime 2件、Treesitter の2件はすべて skip なしで成功。
- TAP SHA-256: `e26cace2c3f2fa1d938cc872d1da5fee8cdd31bfaca486bced3bbfffe7d4734b`。
- 記録: `tmp/canonical-run.aj39yiw8/`、runner は `tmp/test-run.MeUYiC/`、準備記録は `/tmp/codex/canonical-env.26y93c9o/`。
- 追加 CLI は対応3 systemすべてで tree-sitter 0.26.8 を選択することを Nix 評価で確認。実起動確認は x86_64-linux のみ。

独立レビューは Standards の明示規約違反0件、Spec の指摘0件。Standards の助言は Git 環境除去4行の重複1件だった。Herdr イベントと単独の修復 CLI を共通 Python module へ接続すると、現在不要な Python・公開 plugin の起動依存を追加するため、既存 `codex-context` と同じ小さな Bash 処理を維持する。現在の誤動作を指摘するものではなく、両入口の継承 Git context は回帰テストで確認している。

14件の skip は実 CLI・実モデル・raw 隔離・独立した言語環境等の opt-in 検証である。macOS／Windows／aarch64 実機、新規 parser の取得・コンパイル、live 配備は未確認。本節は検証後の記録追記であり、コード・設定・テストは上記の実装 commit から変更していない。

## PR #567 のレビュー対応

- `GIT_*` が空の環境を追加し、Linux 用の配布済み Bash 3.2.39 で Herdr と `codex-repo-state` が `unbound variable` で終了することを再現した。空配列を安全に展開し、`nounset` は維持した。検証専用バイナリは Debian archive から `/tmp/codex` 配下へ展開したもので、通常のランタイムや配布依存には追加していない。
- Herdr は既存の共通 module と同じく継承 `GIT_*` を除去し、その後 `GIT_CONFIG_NOSYSTEM=1` と `GIT_CONFIG_GLOBAL=/dev/null` を明示する。コピーの許可判定は対象 repo の `.gitignore`・`.git/info/exclude` に限定する。`core.excludesFile` は設定がなくても [XDG 配下の既定ファイルを読む](https://git-scm.com/docs/git-config#Documentation/git-config.txt-coreexcludesFile)ため、判定コマンドで `/dev/null` を明示する。global config・既定 XDG ignore・local config の外部 ignore だけが `.env` を無視する場合は拒否し、`.git/info/exclude` による許可は維持する。
- Treesitter の開始失敗時は対象 buffer の highlighter と、この設定の callback に一致する mapping、同じ `indentexpr` だけを解除する。同じ buffer の Lua → 未対応 filetype → Lua、別 buffer の維持、利用者が上書きした mapping・indentexpr の維持を実 Neovim 0.12.4 で確認した。他の FileType handler に依存しない停止確認も含む。
- 対象テストは31件。うち Herdr の21件と `codex-repo-state` の空 Git 環境1件は Bash 3.2.39 でも検証する。Neovim は固定版 plugin の実 API を使う検証も含む。macOS 実機の検証ではない。全体テストと公開 commit の対応は PR のレビュー返信に記録する。
