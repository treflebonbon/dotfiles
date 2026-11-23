# Codex 公式配布版の `.env` symlink 保護（2026-11-23）

`dotfiles` の既定化に必要な機密保護を満たしうる公式 Codex 版があるか、Linux／WSL の実装を確認した。比較した最新の安定版とプレビューには、`.env` の deny glob で子 symlink を保護する処理が見つからなかった。既定化の受入は対応版を待つ。 [ADR-0091 の既定化の受入条件](../adr/0091-base-default-codex-permissions-on-workspace.md#既定化の受入条件) · [PR #620 のレビュー](https://github.com/treflebonbon/dotfiles/pull/620#pullrequestreview-6004816208)

## 確認した公式配布

| 公式配布 | タグ | 公開日 |
| --- | --- | --- |
| 最新安定版 | [`rust-v0.171.0`](https://github.com/openai/codex/releases/tag/rust-v0.171.0) | 2026-11-20 |
| 最新プレビュー | [`rust-v0.173.0-alpha.4`](https://github.com/openai/codex/releases/tag/rust-v0.173.0-alpha.4) | 2026-11-21 |

GitHub Releases の `Latest` 表示と配布一覧を照合した。コード比較の範囲は導入版の `rust-v0.170.0` と表の 2 タグ。Desktop が実際に使う実行側の版と CLI タグの対応は未確認。公式ガイドは WSL2 で Linux sandbox を使うことを説明している。 [公式 Releases](https://github.com/openai/codex/releases) · [OpenAI の WSL ガイド](https://learn.chatgpt.com/docs/windows/wsl)

## `.env` symlink と別 checkout の走査

3 タグの `bwrap.rs` は、deny glob の列挙結果を通常ファイルに限定し、子 symlink を除外する。安定版とプレビューでは同ファイルの Git blob が `f822a6daec315aef18fe58e662b2ab3c22cf600d` で一致した。0.170.0 で ADR-0091 に記録した `.env` symlink 保護の不足を解消できる根拠は、比較したソースから得られなかった。 [0.170.0](https://github.com/openai/codex/blob/rust-v0.170.0/codex-rs/linux-sandbox/src/bwrap.rs#L929-L1012) · [0.171.0](https://github.com/openai/codex/blob/rust-v0.171.0/codex-rs/linux-sandbox/src/bwrap.rs#L962-L1012) · [0.173.0-alpha.4](https://github.com/openai/codex/blob/rust-v0.173.0-alpha.4/codex-rs/linux-sandbox/src/bwrap.rs#L962-L1012)

同じ列挙処理は読み取りエラーを `Fatal` として返す。現行設定の走査範囲内に読めないディレクトリがある場合、正常な checkout でも sandbox の準備段階で停止し得る。深さ 6 の範囲内での停止は 0.170.0 の実測で確認済み。最新 2 タグでの結論はソース比較に基づく。 [0.173.0-alpha.4 の列挙処理](https://github.com/openai/codex/blob/rust-v0.173.0-alpha.4/codex-rs/linux-sandbox/src/bwrap.rs#L975-L1012) · [ADR-0091 の実測](../adr/0091-base-default-codex-permissions-on-workspace.md#codex-01700-の-linux-sandbox-で確認した制約)

## 承認後の sandbox 起動と公開依存の取得

比較した 3 タグは、読み取り拒否を含むポリシーでコマンドを承認した後も、制限を適用する sandbox を必要とする。マウントの準備が失敗するとコマンド起動前に停止するため、認証不要の依存取得も影響を受け得る。 [0.170.0 の承認処理](https://github.com/openai/codex/blob/rust-v0.170.0/codex-rs/core/src/tools/sandboxing.rs#L240-L281) · [0.171.0 の承認処理](https://github.com/openai/codex/blob/rust-v0.171.0/codex-rs/core/src/tools/sandboxing.rs) · [0.173.0-alpha.4 の承認処理](https://github.com/openai/codex/blob/rust-v0.173.0-alpha.4/codex-rs/core/src/tools/sandboxing.rs) · [OpenAI の承認と sandbox の説明](https://learn.chatgpt.com/docs/agent-approvals-security)

0.170.0 の旧設定を使った Desktop では、承認後に共有領域の `.env` を隠すマウントの作成で失敗した。日常用の `/tmp` を標準に委ねた候補では、承認後のファイルシステム規則を再現した隔離試験で、コマンドが起動し、共有領域のダミー `.env` は読み取れなかった。候補を使った Desktop の実承認と、承認後の公開依存取得は未確認。 [ADR-0091 の一時領域の再評価](../adr/0091-base-default-codex-permissions-on-workspace.md#2026-11-23-の一時領域の再評価)

## 調査時点の PR と既定化の条件

調査時点の PR #620 は `edffdb7` で OPEN。`.env` symlink、別 checkout の走査、承認後の起動・依存取得の 3 スレッドが未解決。カスタム `CODEX_HOME` の認証ファイル保護は解決済み。 [PR #620 のレビュー](https://github.com/treflebonbon/dotfiles/pull/620#pullrequestreview-6004816208)

対応を含む公式候補版が見つかった段階で、CLI と Desktop の Linux／WSL セッションごとに実行側の版を記録し、`.env` symlink がある状態で通常コマンドの起動と機密保護を確認する。別 checkout の走査、承認後の sandbox 起動、承認後の公開依存取得は、それぞれ独立した試験結果を使って判断する。 [ADR-0091 の再検証手順](../adr/0091-base-default-codex-permissions-on-workspace.md#候補版の再検証)
