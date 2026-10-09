# Matt Pocock managed set の独立更新（2026-10-09）

## 更新境界と採用物

Impeccable の [PR #393](https://github.com/treflebonbon/dotfiles/pull/393) が main へ merge 済みであることを確認し、その main から開始する。[ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md) の最後の更新単位として、Tool Snapshot・通常 APM・Impeccable は変更しない。親記録は [update-tools-skills-20261009.md](update-tools-skills-20261009.md)。

予定した変更: `apm.yml` の exact pin、native lock の Matt Pocock 項目、関連 test の独立期待値、`runtime/skill-harness.md` の revision 記載、本記録。文書訂正は不要と判断した。

公式27 skill の managed full set を `24fe0ef7737efae15c87225755e9f6f5965e4888`（上流 manifest 1.3.1）から、上流 default branch HEAD `b0618bc436ad893b3c5e84e55fba86586d34a404`（manifest は 1.3.1 のまま、44 commit が未 release）へ更新する。[上流比較](https://github.com/mattpocock/skills/compare/24fe0ef7737efae15c87225755e9f6f5965e4888...b0618bc436ad893b3c5e84e55fba86586d34a404)の主な配布 skill 変更は次のとおり。

- `implement`: ticket 参照の取得と title 確認、`tdd`／`code-review` を Skill tool 名で呼ぶ指示
- `to-tickets`: native blocking edge を設定した場合に `Blocked by` を省略（GitHub の sub-issue 追加手順を issue-tracker 雛形へ追加）
- `code-review`: standards file の探索、sub-agent の foreground 実行
- `grilling`: yes で推奨を受け入れる質問文、`wayfinder`／`teach`／`setup-matt-pocock-skills`／`handoff`／`ask-matt`／`wizard`／`diagnosing-bugs`／`tdd` の修正

公式27 skill の membership は不変。新規の `skills/in-progress/chief-of-staff` は plugin manifest に含まれず、導入しない。release は v1.3.1 が最新で、今回の HEAD は未 release の修正を含む。`apm.yml` の注記（「検証済み default-branch revision を pin し、APM の lock / frozen install で同期する」）と、`runtime/skill-harness.md` 2026-09 の更新が default branch HEAD を pin した先例に従い、release tag に限らず gate の結果で採否を決めた。manifest 版が 1.3.1 のまま HEAD が進むため、release tag を待つ利点は無いと判断した。

## 隔離ゲートとnative lock

[ADR-0042](../adr/0042-mattpocock-managed-set-update-gate.md) の `tests/mattpocock-update-gate.sh` を、採用前の source に対し `--candidate-manifest` で候補 manifest を渡して実行した。gate は終了コード0で、lock generation → frozen install → audit → skill discovery → workflow contract → chezmoi dry-run の順に完了し、全746件が成功した。

実行環境は `LC_ALL=C`、書き込み可能な `XDG_RUNTIME_DIR`、単一の Nix browser bundle の `PLAYWRIGHT_BROWSERS_PATH` を指定した。初回は source 側の manifest を先に変更していたため apm-runtime の2件が失敗し（手順の誤り）、環境を整えた再実行で全件成功した。

gate 成功後、別の空 runtime で実 manifest と accepted lock から native lock を生成した（Matt の ref だけを解決）。Matt 以外の19依存の lock 項目と、非 Matt の deployment ledger は base と同一。Matt の `package_type` は native 出力で `apm_package` → `marketplace_plugin` に変わった（上流 plugin manifest から27 skill を materialize する分類で、同じ native 出力が前回（2026-10-05）にも現れた）。採用 lock の SHA-256 は `1071b2fcfec2dabfe5ab409bdf5bf4f2eec07d101932227360c6eb809f2fd8f1`。別の空 runtime の `apm install --frozen` 前後で不変、`apm audit --ci` 10/10、Claude／Codex 各46 skill が一致。Matt の selected content hash は `sha256:10f083ac2b0207d326f52883a862e9d50c607a887932a906decfbd12e995b6ab`。組織ポリシー enforcement は Git remote のない隔離環境のため未検証。

## 検証

- 採用後の `tests/apm-runtime.bats`・`mattpocock-update-gate.bats`・`workflow-contract.bats`・`nix-devshell.bats` の81件が成功した（独立期待値を新しい revision／hash に更新）。
- 未検証: Claude／Codex の対話的 skill loader、実セッションでの upstream 変更後の挙動、live apply（受入後に live source から配備する）。
- 標準 `lefthook run test`（`LC_ALL=C`、書き込み可能な `XDG_RUNTIME_DIR`、単一 browser bundle を指定）は746件中 成功724・skip 22・失敗0。

## 先行 PR の失敗17件の訂正

#391／#392／#393 の記録にある標準全件テストの失敗17件（dogfood 9件、`local-skills` 1件、managed-set gate 7件）は、この agent 実行環境の条件で説明できた。gate 7件は `LC_ALL` 未指定のロケール依存 `sort`、`local-skills` 1件は `/run/user/1000` を作れない `XDG_RUNTIME_DIR`、dogfood 9件は複数 Chromium を含む `PLAYWRIGHT_BROWSERS_PATH`（Nix の単一 bundle を指定）が原因で、上の環境指定で全件成功した。リポジトリの回帰ではない。先行3件の「環境要因と推定、未確認」は、この再実行で確認済みに更新する。
