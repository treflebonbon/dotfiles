# Matt Pocock managed set の独立更新（2026-10-05）

## 更新境界と採用物

Impeccableの [PR #380](https://github.com/treflebonbon/dotfiles/pull/380) がmain `c735befaf8b41c4395c1d6b2a27977630a0ae00e` にmergeされたことを確認した。同じnative task worktreeのGit所属とclean statusを検証し、このmainから `chore/update-mattpocock-20261005` を開始した。[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md)の最後の更新単位として、Tool Snapshot・通常APM・Impeccableを維持する。

公式27 skillのmanaged full setを、`d81f3a183412e71a5b1e84ca21bc1a35eea03a60`（上流manifest 1.2.3）から `24fe0ef7737efae15c87225755e9f6f5965e4888`（1.3.1）へ更新する。[上流比較](https://github.com/mattpocock/skills/compare/d81f3a183412e71a5b1e84ca21bc1a35eea03a60...24fe0ef7737efae15c87225755e9f6f5965e4888)では、配布skill本文の差分は `ask-matt/SKILL.md` のみ。古い自動post-mortem handoffの案内を、バグ修正後にユーザーが `retro` または `improve-codebase-architecture` を起動する案内へ修正する。公式27 skillのmembership、cleanup ownership、cross-skill invocation、frontier、setup、phase／safety boundaryは維持する。上流本文はforkしない。

## 隔離ゲートとnative lock

[ADR-0042](../adr/0042-mattpocock-managed-set-update-gate.md)の `tests/mattpocock-update-gate.sh` を候補manifestで実行する。gate専用manifestだけで非Matt依存を一時pinし、検証用lockはsourceへ採用しない。実manifestからAPM 0.33.0でnative lockを別の空runtimeに生成し、frozen installとauditを再確認して採用する。

- 隔離ゲートは終了コード0で、lock generation → frozen install → audit → skill discovery → workflow contract tests → chezmoi dry-runの順に完了した。関連71テスト成功、全735件中713成功・22skip・失敗0。候補payloadはaudit／discoveryで評価し、後段のsource契約・回帰テストは採用前のsourceで実行した。dry-run前後の一時HOMEは不変。
- gate成功後、別の空runtimeで実manifestとaccepted lockを使い、native install → frozen install → auditを実行した。すべて終了コード0で、lock SHA-256は `c3e86e96f91a5a516963c96bfe363a6e20194a04b8e8e22899f5a442630217fd` のまま不変。19非Matt依存のlock項目全体と非Matt deployment ledgerはbaseから不変。Mattのselected content hashは `sha256:127ccf2bbbf1442907b12581be5aba13ed034344e290714172f0a4a1b72942f8`。
- 20依存・1,310ファイルのSHA-256、Claude／Codex各46スキル、両targetの公式Matt 27スキル構成を照合した。native lockはmanifestのexact pin以外に `resolved_ref` を持たない。audit baseline 10/10成功。Git remoteのない隔離runtimeでは組織ポリシーenforcementがwarning付きskipであり、その適合は未検証。
- native生成でMattの `package_type` は `marketplace_plugin` となった。APMが上流plugin manifestから27 skillをmaterializeする分類であり、Claudeの `enabledPlugins` や別installerは追加していない。両targetのpayload構成とAPM単独ownershipをgateで検証した。
- 型検査 `bunx tsc --noEmit` と、native採用後のAPM／更新gate／workflow契約43テストは成功。採用後の標準全件テストと二軸レビューを本単位で実施し、結果を追記する。

HOME配備は全更新単位の受入・merge後、merge済みlive sourceから行う。ARM実機起動、Claude／Codexの対話的skill loader、実セッションの初回hook trustはこの隔離ゲートで確認しない。
