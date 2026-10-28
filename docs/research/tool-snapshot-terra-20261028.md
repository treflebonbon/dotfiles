# GPT-6.1 Terra 対応の Tool Snapshot 更新（2026-10-28）

## 現在の要件と更新単位

- ユーザーの `$implement ツール更新 GPT-6.1 Terra` に基づく。追加回答により、既定の `gpt-6.1-sol` / `xhigh` と subagent の `gpt-6-luna` / `xhigh` を維持し、Terra を選択可能にする。
- 対応する Issue は存在せず、この依頼と追加回答を要件の正本とする。
- ADR-0045 の Decision §1 と 2026-10-23 amendment に従い、導入済み AI ツールセットを一つの immutable snapshot で更新し、Codex は upstream direct package を使う。独自 patch や新規の source build は追加しない。
- ADR-0070 の親モデルと effort、ADR-0051 の管理設定同期は維持する。live source への配備は受入・merge 後に行う。
- 予定変更は user devShell の source/lock、snapshot の既存テスト、Terra の起動方法と今回の採否・検証記録。一般ツール、APM payload、Impeccable、Matt Pocock は別の更新単位として今回は更新しない。分割で外した実装差分はない。

## 固定した候補

実装入口の `nix flake metadata github:numtide/llm-agents.nix/main --json` で一度だけ upstream main を解決し、`959a6e37234ae40e3ae6d4c9a564ec1a8803ccf9` に固定した（confirmed）。旧 snapshot は `a5500f41321b0a6b68407500f26dd55dbeb5793f`。

| 導入済み CLI    | 旧版    | 候補    |
| --------------- | ------- | ------- |
| Claude Code     | 2.1.310 | 2.1.312 |
| Codex           | 0.164.0 | 0.165.0 |
| Copilot CLI     | 1.0.103 | 1.0.104 |
| Antigravity CLI | 1.4.7   | 1.4.8   |
| Herdr           | 0.9.5   | 0.9.5   |
| APM             | 0.35.0  | 0.35.0  |

[Codex upstream PR #57293](https://github.com/openai/codex/pull/57293) は bundled catalog へ `gpt-6.1-terra` を追加する。[snapshot PR #11489](https://github.com/numtide/llm-agents.nix/pull/11489) は Codex 0.165.0 の採用で、上記 snapshot はこの merge commit と一致する。[OpenAI のモデル資料](https://learn.chatgpt.com/docs/models)は `codex -m gpt-6.1-terra` を案内し、[API モデル資料](https://developers.openai.com/api/docs/models/gpt-6.1-terra)は `xhigh` を対応 effort に含める。CLI の bundled catalog とアカウントでの利用可否は別に検証する。

品質 floor は現行の Claude Code 2.1.296 / Codex 0.162.0 を維持する。snapshot の更新と最低版の根拠は区別し、今回確認した catalog 追加を CLI 接続の最低版とは扱わない。

## 検証

- user / repo 両 flake の `nix flake check --no-build --all-systems --offline` が成功。対応3 system の6 CLI metadata は上表の候補と一致（confirmed）。ARM Linux / Darwin は評価のみ、実行検証は x86_64-linux。
- `--no-codex-build` により Codex 0.165.0 の direct output を Numtide cache から取得。Rust source build は発生していない（confirmed）。
- 認証を持たない隔離 HOME の候補 Codex app-server に `initialize` / `model/list` を送り、`gpt-6.1-terra` が1件あり、`xhigh` を公開することを確認（confirmed）。証拠: `/tmp/codex/terra-catalog.23izq9xi/terra.json`。実モデルへの接続は未確認で、この結果をアカウントの利用権限の確認とは扱わない。
- `tests/nix-devshell.bats` は26/26、`tests/ai-quality-floor.bats` は7/7。型チェックは frozen install 後に成功（confirmed）。初回の snapshot テストは lock 再生成との実行順の誤りで失敗し、lock 確定後に再実行した。初回型チェックは依存関係の未導入で失敗した。失敗を最終成功の試行と混同しない。
- 最初のオンライン lock 再生成は Nix daemon の接続拒否で停止した。既存キャッシュを使った native の offline 再生成は成功し、その後 service と socket の稼働を確認した。権限変更は行っていない。
- `scripts/verify-ai-tools.py --shell default --no-codex-build` は exit 0。6 CLI の候補 output と実際の `--version` が一致した（confirmed）。証拠: `tmp/ai-tools-hsrtz11v/`。
- 候補 Codex を使う `tests/codex-config.bats` は61/61、exit 0。strict parse、管理設定の同期、実 sandbox の denied-file / dotenv / network 境界を含む（confirmed）。
- 最初の全 Bats は1,158件中1,134成功、1失敗、23 skip、exit 1。失敗は `tests/test-entry.bats` の INT 停止待ちが3秒を超過した1件。証拠: `tmp/test-run.Fn6q8B/`。6 CLI の起動不一致ではなく、後続テストの失敗として記録する。
- `0b5a6711dc4630b90336f75e8d3d28a2b00ea960...d5d14e0` の code-review は Standards / Spec とも指摘0。追加の待機時間変更は再レビューする。
- live 配備は受入・merge 後とする。

## 検証中に追加した変更

全 Bats の停止検証の失敗を受け、`tests/test-entry.bats` のシグナル送信後の待機上限を3秒から10秒へ変更する。既存の fixture 起動待ちと同じ猶予であり、`docs/conventions.md` の並列実行時のタイムアウト規則と ADR-0079 に従う実装判断である。停止処理本体は変更せず、終了コード130 / 143、子孫プロセスの消滅、INT handler の実行 marker を引き続き検査する。

3秒の上限超過は confirmed。並列負荷の関与は、全体実行のみの失敗、同じ正式 devShell での単独成功、待機中の I/O wait の観測に基づく inferred であり、Codex の回帰とは断定しない。全体の負荷を小さい fixture に固定した再現の最小化は行っていない。今回の修正はテスト補助の時間上限だけに限定し、停止処理の不具合は既存の意味的な検査と次の検証で引き続き検出する。

- 変更後の `tests/test-entry.bats` は20/20、exit 0。
- 一時コピーの `scripts/test.sh` で Python の SIGINT handler を無効にすると、対象テストは10秒の上限で失敗した。待機時間を延ばしても停止しない実装を拒否できる（confirmed）。証拠: `/tmp/codex/terra-int-mutation.y02qzqzf/tap.log`。本体にはこの変更を適用していない。
- 変更後の `lefthook run test` は1,158件中1,135成功、23 skip、失敗0、exit 0（confirmed）。証拠: `tmp/test-run.DO2tKj/`。`scripts/verify-ai-tools.py --shell default --no-codex-build -- lefthook run test` 自体も exit 0。証拠: `tmp/ai-tools-6ubdfmoy/`。初回失敗とは別の試行であり、実モデル・認証等の既定 opt-in は実行していない。
- `0b5a6711dc4630b90336f75e8d3d28a2b00ea960...51b933b` の追加差分レビューも Standards / Spec とも指摘0。停止検査を維持した待機時間変更と、初回失敗／局所検証／再実行の区別を確認した。

## 最終状態

Tool Snapshot、Terra の利用手順、並列負荷を見込む停止検証の待機時間を task worktree に実装し、検証した。APM payload / Impeccable / Matt Pocock / 一般ツールは今回の対象外として維持し、分割で外した未反映の実装差分はない。実モデルの応答、ARM / Darwin の実機、live 配備は未確認。受入・merge・live source への配備はこの実装完了とは区別する。
