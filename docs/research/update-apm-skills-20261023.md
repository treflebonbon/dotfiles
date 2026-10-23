# 通常APM・Impeccable更新（2026-10-23）

[ツール・スキル更新（同日）](update-tools-skills-20261023.md) で保留した APM unit の再開。開始点は main `58eef8dded0073e9ae29a9611c913f4cae005dc1`（PR #507 merge 後）。branch `chore/update-apm-skills-20261023`。「独自パッチはあてない・upstreamにはなにもしない」を引き続き適用する。ADR-0045（更新単位の分離）、ADR-0053（Impeccable skillとengineの一体検証）に従う。

## 保留理由の訂正

前記録は「APM 0.34.0 の `apm --version` が 0.33.0 を返す上流の表示ずれ」としたが、これは誤りだった。原因は旧 devShell から継承された `PYTHONPATH` が旧 0.33.0 の `apm_cli` を先に読み込んでいたことで、`env -u PYTHONPATH` では同じ 0.34.0 の launcher が `0.34.0` を返す（confirmed、Codex 相談で特定し本セッションで再現）。ゲートは変更せず、`PYTHONPATH` を外した環境で既存の隔離 lock 生成手順を実行した。

## 更新単位

| 更新単位 | 内容 |
| --- | --- |
| 通常APM | Remotion `1441a11e…`→`6c67adcd9cdbe6eb84d76342da89b225f9161cb2`、Modern Web Guidance `b31dc0a4…`→`65e7edd67e77420eaf02c5df00fdc0521417d809`、Herdr skill `7b116c05…`→`2ecf19a92fc3a7fff75b6ce3655ef04f4625ec01`（v0.9.5 tag）。 |
| Impeccable | skill 4.6.0→4.7.0（`2f46b7a8…`→`490141501de5035d1d2fb975239ceb757f045bcb`）と engine 0.1.15→0.1.16 を一体で更新。 |

Matt Pocock は managed set 外の差分だけなので維持。floating の shadcn／Orca／find-skills は resolved_commit だけが前進し、selected payload の content_hash は不変。

## 検証結果

- 通常APM: 隔離 runtime（accepted lock をコピー、`PYTHONPATH` 除去、APM 0.34.0）で `generate-apm-lock.sh --update` が成功。frozen install 前後の lock SHA-256 不変、`apm audit --ci` 10/10、`verify-apm-deployment.mjs` が dependency 20・skill 各 target 46・追加16・削除4で成功。content_hash が変わったのは 3 dependency だけ。
- Impeccable: 通常APM採用 lock をbaselineに別 runtime で同じ手順が成功（audit 10/10）。実 launcher と source-selected engine 0.1.16 で `tests/design-hook.bats` 13/13・skipなし。
- 配備照合 helper の修正: 新 payload の `scripts/impeccable.cmd` が CRLF で、APM は LF 正規化の hash を lock に記録する一方、配備 file は CRLF のまま。helper は実 byte の hash だけを比較して不一致としたため、ユーザー承認の上で、生 byte と CRLF→LF 正規化の hash のどちらかが lock と一致すれば受理するよう変更した。改ざんした byte は引き続き拒否する（回帰テスト追加）。upstream payload と APM は無改変。
- 未確認: 実 browser での Impeccable live mode、APM 組織 policy の enforcement、ARM／Darwin 実機。
