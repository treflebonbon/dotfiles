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
- 型検査 `bunx tsc --noEmit` と、native採用後のAPM／更新gate／workflow契約43テストは成功。採用後のsourceで標準 `lefthook run test` も成功し、全735件中713成功・22skip・失敗0、終了コード0。以下のレビュー後の追加変更は検証結果の文書記録のみ。

HOME配備は全更新単位の受入・merge後、merge済みlive sourceから行う。ARM実機起動、Claude／Codexの対話的skill loader、実セッションの初回hook trustはこの隔離ゲートで確認しない。

## 二軸レビュー

機能変更commit `c5108b2` を、fixed point `c735bef` から読み取り専用でレビューした。レビュー時点では採用後の標準全件テストを実行中だった。

### 規約軸レビュー

規約違反は **0件**、報告対象の Fowler smell も **ありません**。

`apm.yml` と native lock の pin・hash 更新、runtime の revision 記載、関連テストの期待値、調査記録を確認しました。ADR-0042 がこれらの一体更新とゲート順序を定め、ADR-0045 が Matt Pocock set を独立した更新単位としているため、差分は規約に適合しています。調査記録も標準全件テストと二軸レビューを未完了としており、親共有の状況と一致します。

読み取り専用で確認し、テストは実行していません。

### 要件軸レビュー

指摘なし。差分は Matt Pocock のみを独立更新単位とする範囲に収まり、依頼された「`$implement` ツールとスキルの更新」と後続の PR 統合に沿っています。

- 欠落・部分実装：なし。ADR-0042 の「候補 revision を一つの exact commit」とする条件に対し、manifest と lock は `24fe0ef…` で一致しています。検証記録には ordered gate、native lock、frozen install、audit、discovery の実施結果があります。ADR-0071 の「公式 managed full set」は、上流 manifest の27 skillを維持しています。
- 未依頼 scope 増大：なし。ADR-0045 の「四つの更新単位」を分離する方針どおり、他の更新単位は差分に含まれていません。
- 実装誤り：なし。上流比較では配布本文の変更が `ask-matt/SKILL.md` のみで、runtime の案内更新と整合しています。`marketplace_plugin` は生成された lock metadata であり、別配布経路を追加した形跡はありません。

レビュー中にテストは実行していません。

規約軸・要件軸とも指摘0件。
