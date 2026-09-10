# AI snapshot・解析・文書変換ツールの更新（Issue #288）

親仕様: [#283](https://github.com/treflebonbon/dotfiles/issues/283)。担当: [#288](https://github.com/treflebonbon/dotfiles/issues/288)。共通基盤は #287 の `nixpkgs-26.05-darwin` revision `104a7c61006cd22d11c0379663afee90c62273ab`。

## 固定候補と配布経路

実装入口で確認した [llm-agents snapshot `e320800dd9dc2b156bfa77fbeeb00e9e7295f3a9`](https://github.com/numtide/llm-agents.nix/tree/e320800dd9dc2b156bfa77fbeeb00e9e7295f3a9) を使う。旧snapshotは `868527bc9eb4e8bee8610fa1d4027fbb37cfc012`。検証中に新しいHEADを追っていない。

文書変換とFastMCPの既存source-only inputは、`421eebfd0ec7bccd4abe826ce62d7e6e83129493` から、repo編集用inputと同じ既存unstableの [revision `d6524aaca2ff07876657ae2b323f24be4874944b`](https://github.com/NixOS/nixpkgs/tree/d6524aaca2ff07876657ae2b323f24be4874944b) を選ぶ。これらのpackage定義だけを共通stable package集合で評価する既存構成を維持する。

| package | 着手時 | 候補・ホスト実出力 | 経路 |
| --- | --- | --- | --- |
| Claude Code | 2.1.263 | 2.1.267 | shared overlay |
| Codex | 0.153.4 | 0.154.0 | immutable inputのdirect package |
| Copilot CLI | 1.0.83 | 1.0.83 | shared overlay、版維持 |
| Antigravity CLI | 1.1.27 | 1.2.0 | shared overlay |
| Herdr | 0.9.0 | 0.9.0 | direct package、版維持 |
| RTK | 0.48.0 | 0.48.0 | shared overlay、版維持 |
| APM | 0.30.0 | 0.30.0 | shared overlay、版維持 |
| code-review-graph | 2.3.8 | 2.3.8 | 同snapshotの定義＋既存Python依存補正 |
| FastMCP | 3.3.1 | 3.4.7 | 既存source-only定義をstable Pythonで評価 |
| tree-sitter-language-pack | 0.13.0 | 0.13.0 | 既存の固定parser package |
| defuddle | 0.19.1 | 0.19.3 | 既存source-only定義 |
| markitdown | 0.1.6 | 0.1.7 | 既存source-only定義 |

[Claude 2.1.267](https://github.com/anthropics/claude-code/releases/tag/v2.1.267) と [Codex 0.154.0](https://github.com/openai/codex/releases/tag/rust-v0.154.0) はstable releaseと確認した。設定や操作機能の追加・修正を含むが、本更新では既存運用の新しい最低版を要求しない。Claudeの品質floor 2.1.261、Codexのfloor 0.153.4は、実際の導入版から独立して維持する。モデル・権限・workflow設定は変更しない。

llm-agents内部のnixpkgsは上流lockに従って `0af3d1402dec3fc7e93635e511d1f7428c89cebf` から `5052d7ccbcfb7e4ae1586cb2ecf95a2e3707dce9` へ進む。共通stable inputの移動ではない。Codex/Herdr direct packageと、その他のshared overlayを切り替えない。

## Python依存と文書変換

CRGのFastMCP floor `>=3.2.4`、parserの `>=0.9.0,<1` を維持した。[PyPIのFastMCP](https://pypi.org/pypi/fastmcp/json) 最新安定版は4.0.3だが、選んだ既存source-only定義は3.4.7。[parser](https://pypi.org/pypi/tree-sitter-language-pack/json) の最新は1.17.0、`<1` を満たす最新は0.13.0だった。既存の依存制約と取得経路を維持し、新しいoverrideやinstallerは追加しない。[markitdown](https://pypi.org/pypi/markitdown/json) は上流0.1.7と一致した。固定時のmetadataは `ai-python-upstream.json` に保存した。

ホストの実CLIで、Pythonファイル1件からCRGのDBを構築し、read-only allowlistの `list_graph_stats_tool` をstdio MCPで呼んだ。CLI buildとMCPの結果はともに2 nodesで一致し、MCPの `is_error` はfalseだった。global install、常設MCP、hookやdaemonの追加は行わない。

同じHTML fixtureをdefuddleとmarkitdownへ渡して変換した。defuddleは記事の本文を抽出し、タイトルはJSON metadataへ分離する。最初のprobeはタイトルがHTML本文に残ると誤認して失敗したが、旧0.19.1も同じ出力であることを確認した。公開JSONのtitleとcontentを検証する形へ修正し、本文とタイトルの両方を確認した。単なる終了コード確認にはしていない。

## 実行結果

全証跡の保存先はtask worktreeの `tmp/update-283/`。通常HOMEへ配備しない隔離HOME/XDG/CODEX_HOMEから実行した。

| 検証 | 結果 | 証跡 |
| --- | --- | --- |
| 3 system × default/WSL、全nativeBuildInputs評価 | PASS | `ai-candidate-all-systems.json` |
| ホストWSLの実build | PASS | `ai-candidate-wsl-build.json`、`ai-candidate-wsl-build.log` |
| Codex/Herdr direct outputの3systemキャッシュ | 全6件PASS | `ai-direct-cache-check.json`、`nix path-info --store https://cache.numtide.com` |
| AI8 CLIのversion/help、Codex local features | PASS | `ai-candidate-cli-smoke.json` |
| CRG help/build/MCP、2文書変換の実処理 | PASS | 上記と `ai-candidate-cli-smoke.log`。合計25コマンド |
| 隔離Herdr起動・workspace取得・正常停止 | PASS | `ai-herdr-smoke.json`、専用HOME `/tmp/h283-59miyqf9` とsession |
| 既存APM payload frozen・audit | PASS | #287の同一APM出力による `apm-baseline-frozen-result.json`、`apm-baseline-audit-result.json` |
| 品質floor・source契約・関連Bats | 36/36 PASS | `ai-source-related-0.log`。採用前のpin契約REDも `ai-source-red.log` に保存 |
| 新Codexの管理config strict parser | 1/1 PASS | `ai-source-related-1.log`。候補0.154.0でrendered/merged設定を検証 |
| full Bats | PASS | [#295](update-295-integrated-acceptance.md)。657実行PASS・19skip、exit0 |

WSL buildは `/nix/store/q8zmpinc8misl7jn62rfqahaya5xr8cb-nix-shell.drv` → `/nix/store/91qwmjgha9j6aldj7bzk8491968cgb2f-nix-shell`。aarch64-linux / aarch64-darwinのcacheと評価の成功を、それらの実機起動成功とは扱わない。Claude/Codex/Antigravityのauthenticated conversation、全新機能の実動作、Herdrの全端末での描画はこの起動probeの対象ではない。

Herdrは稼働中の通常serverから独立したHOME・XDG・named sessionを作った。初回は長い一時パスがUnix socketの長さ制限で失敗したため短い専用パスへ修正し、`status --json` の明示と実出力schemaに合わせた検証で起動・停止を確認した。通常serverや既存paneは停止していない。Codexの初回features probeは未作成の隔離CODEX_HOMEを指定したため失敗した。ディレクトリを事前準備した同じ候補は正常に起動した。これらのprobe修正で配布設定を変更していない。

APMは旧・候補とも `/nix/store/r08b589k4w0zap14lf556mq52fmmpwbd-apm-0.30.0`。同一実体で現行manifest/lockをfrozen配備し、lock SHA-256 `ef6e2065b6cec632780b4ceac55bd12472dbd4d8bbf69b6b15ab0b65da3a5f8b` 不変とaudit 10/10を確認済み。共有hub／Claude targetは43スキル、配備ledgerの1,204ファイルのhashが一致した。organization policyの取得・enforcementはskipであり、適合を確認したとはしない。新しいskill payloadとnative lockの採否は #289 以降で行う。

source URLとnative lockを候補に揃え、lockの変更がsnapshot・そのtransitive nixpkgs・既存source-only inputだけであることを照合した。関連36件と新Codexでの設定parserが成功したため、この組み合わせをsourceへ採用する。統合full Batsと最終二軸reviewの成功は [#295](update-295-integrated-acceptance.md) に記録した。live反映は受入・merge後のlive sourceから行う。
