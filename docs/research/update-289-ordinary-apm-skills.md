# 通常APM 17依存の採用記録（Issue #289）

2026-09-10。#288で確定した APM 0.30.0 (`/nix/store/r08b589k4w0zap14lf556mq52fmmpwbd-apm-0.30.0/bin/apm`) を使用。隔離した候補のmaterializationとpayloadを確認し、manifest/native lockをsourceへ採用した（coordinator commit `f423852`）。この単位ではImpeccableとMattの組み合わせを維持し、live配備は行っていない。親仕様は [#283](https://github.com/treflebonbon/dotfiles/issues/283)、担当は [#289](https://github.com/treflebonbon/dotfiles/issues/289)。

## 候補の固定と全件比較

未凍結の9 repositoryは、この入口で `gh api repos/<owner>/<repo>/commits/HEAD` を各1回実行して固定した。完全なrevision・時刻・コマンドは `tmp/update-289/candidates.json` と `metadata/*.json` に保存。Orca `a067cccd38e38487772741ebf9d0ea4a8fed8644` とHerdr `b99002ac99b09e00b4ca692436cb15a6b0d676f1` の候補確認は繰り返していない。

全selected subtreeを固定Git objectのtree SHAで比較した。結果はpayload変更1件、revision-only 5件（exactのOrca CLIを含む）、revisionもpayloadも不変11件。Orca CLIのexact pinは維持するため、準備したlockの変更はRemotionとfloating 4件である。

| 依存 | 方針 | 現行revision | 凍結候補revision | native lockの採用値 | 判定 |
| --- | --- | --- | --- | --- | --- |
| pdf | floating | `41bbe19d1a1a7eaab5e7bb9050a417e5c6cffc8f` | `41bbe19d1a1a7eaab5e7bb9050a417e5c6cffc8f` | `41bbe19d1a1a7eaab5e7bb9050a417e5c6cffc8f` | 不変、維持 |
| skill-creator | floating | `41bbe19d1a1a7eaab5e7bb9050a417e5c6cffc8f` | `41bbe19d1a1a7eaab5e7bb9050a417e5c6cffc8f` | `41bbe19d1a1a7eaab5e7bb9050a417e5c6cffc8f` | 不変、維持 |
| effect-ts | floating | `2309e6f27d9955b434c0e3f394b945c136e89fd2` | `2309e6f27d9955b434c0e3f394b945c136e89fd2` | `2309e6f27d9955b434c0e3f394b945c136e89fd2` | 不変、維持 |
| modern-web-guidance | exact | `bfd8c8dded770f3ba07a518e28991a32df40f902` | `bfd8c8dded770f3ba07a518e28991a32df40f902` | `bfd8c8dded770f3ba07a518e28991a32df40f902` | payload不変、exact維持 |
| herdr | exact | `b99002ac99b09e00b4ca692436cb15a6b0d676f1` | `b99002ac99b09e00b4ca692436cb15a6b0d676f1` | `b99002ac99b09e00b4ca692436cb15a6b0d676f1` | payload不変、exact維持 |
| empirical-prompt-tuning | floating | `7a0d72866a0bb3e9ac3e2768c328b09ba2bc40c4` | `7a0d72866a0bb3e9ac3e2768c328b09ba2bc40c4` | `7a0d72866a0bb3e9ac3e2768c328b09ba2bc40c4` | 不変、維持 |
| remotion-best-practices | exact | `11986e44eeb672b083354e68967f2b194df73b7c` | `9ae8048a84690098b1059f7f5d30e6d05833b824` | `9ae8048a84690098b1059f7f5d30e6d05833b824` | 本文変更を採用 |
| shadcn | floating | `5c7072da672b0048bc6771e3204063a2537df91a` | `3ba91b1cc83e1bbe4ab35a422ff2a694849c5048` | `3ba91b1cc83e1bbe4ab35a422ff2a694849c5048` | floating revision-only |
| computer-use | floating | `1a8640adb6e86abb342a8025892300b2835f3e8e` | `a067cccd38e38487772741ebf9d0ea4a8fed8644` | `2bf298d1dc1a41c03a270e89eca08834c36f13e0` | floating revision-only |
| orca-cli | exact | `de0a91b99fc845c9510340786f807ea1c988859b` | `a067cccd38e38487772741ebf9d0ea4a8fed8644` | `de0a91b99fc845c9510340786f807ea1c988859b` | payload不変、exact維持 |
| orchestration | floating | `1a8640adb6e86abb342a8025892300b2835f3e8e` | `a067cccd38e38487772741ebf9d0ea4a8fed8644` | `2bf298d1dc1a41c03a270e89eca08834c36f13e0` | floating revision-only |
| supabase-postgres-best-practices | floating | `8331f910845103c08d51f6ca1d86ebb7d1f745e3` | `8331f910845103c08d51f6ca1d86ebb7d1f745e3` | `8331f910845103c08d51f6ca1d86ebb7d1f745e3` | 不変、維持 |
| vercel-composition-patterns | floating | `063bee94c3f4df8453406c830b0a7df0f2860278` | `063bee94c3f4df8453406c830b0a7df0f2860278` | `063bee94c3f4df8453406c830b0a7df0f2860278` | 不変、維持 |
| vercel-react-best-practices | floating | `063bee94c3f4df8453406c830b0a7df0f2860278` | `063bee94c3f4df8453406c830b0a7df0f2860278` | `063bee94c3f4df8453406c830b0a7df0f2860278` | 不変、維持 |
| vercel-react-view-transitions | floating | `063bee94c3f4df8453406c830b0a7df0f2860278` | `063bee94c3f4df8453406c830b0a7df0f2860278` | `063bee94c3f4df8453406c830b0a7df0f2860278` | 不変、維持 |
| web-design-guidelines | floating | `063bee94c3f4df8453406c830b0a7df0f2860278` | `063bee94c3f4df8453406c830b0a7df0f2860278` | `063bee94c3f4df8453406c830b0a7df0f2860278` | 不変、維持 |
| find-skills | floating | `1682051d48c34f5eb135e6475c1a965dce05e820` | `80feb48868972d518436f26711509bc78595b5cb` | `80feb48868972d518436f26711509bc78595b5cb` | floating revision-only |

各dependencyの現行／候補content hash、selected path、tree SHAは `tmp/update-289/comparison.json` にある。

### Orca floatingのnative解決

最終形のfloating宣言を維持した新規 `apm install` は、computer-use / orchestrationを `2bf298d1dc1a41c03a270e89eca08834c36f13e0` に自然解決した。これを新しい調査候補へ差し替えていない。native cache中のこのexact objectを読み、凍結候補 `a067cccd...`、現行 `1a8640ad...` との全selected tree一致を確認した。computer-useは `fab1436f0d73889492279544eadebc9bcc2694b6`、orchestrationは `ebd864919dd8cab9d7049fc624c9afeebce2767c`。両content hash、全配備file/hash、ownerも不変で、native lockのrevision-onlyとして記録する。Orca CLIのexact pin `de0a91b99fc845c9510340786f807ea1c988859b` は維持。

## Remotionの内容評価

候補は `9ae8048a84690098b1059f7f5d30e6d05833b824`、SKILL versionは4.0.522→4.0.523。選択対象137ファイルのうち15ファイルが変わり、10件はversion表記だけ、5件には本文差分がある。`tmp/update-289/remotion-best-practices.diff` と `tmp/update-289/remotion-changes.json` を保存した。

- create: 空の作業場所なら現在のディレクトリ、意味のあるファイルがある場合は子ディレクトリへscaffoldするよう分岐。`.git`や環境設定ファイルを不要なhidden fileとして扱わない。削除操作の承認は引き続きユーザー指示とAGENTSの契約に従う。
- MapLibre（同じ説明を持つ2資料）: namespace importと、実際のpackage versionに揃えたES-module worker URLを設定する。[MapLibre公式v6移行資料](https://maplibre.org/maplibre-gl-js/docs/guides/v5-to-v6-migration-guide/)のESM import・bundlerのworker設定と整合する。CDNとBlob workerを使う例であり、制限されたCSPやofflineレンダリングの動作までは本検証では確認していない。
- markup / upgrade: 補助packageをtarget Remotionのstudio依存に合わせる説明へ変更。[4.0.523のregistry metadata](https://registry.npmjs.org/@remotion%2fstudio/4.0.523)でzod 4.5.4、mediabunny 1.55.5を確認した。`@huggingface/transformers`はこの版のstudio依存にないため、その版が指定されているとは扱わない。Remotion各packageを同版へ揃える方針は[公式のversion mismatch説明](https://www.remotion.dev/docs/version-mismatch)と一致する。

APM選択path、skill名、参照先membership、Node24方針、モデル・権限・workflow利用方針の変更は不要。既存upgrade資料の `npx skills update` は今回追加された経路ではなく、当dotfilesでは引き続きAPM正本を優先する。動画projectの作成、独自skill installer、ブラウザ描画は実行していない。採否の必須seamは親Testing Decisionsの隔離APM materializationとpayload一致である。

## Native materializationと検証

`runtime/`を専用cwdとHOMEにし、XDG cache/config/data/state/runtime、CODEX_HOME、APM_CACHE_DIRもその配下へ隔離した。`PYTHONPATH` / `PYTHONHOME`をchild環境から除去して実binaryの0.30.0を確認。新規runtimeへ、sourceと同じexact/floating方針のmanifest（変更はRemotion exact pinだけ）を置き、seed lockや一時pin manifestなしでnative生成した。生成lockの手編集・formatter処理は行っていない。

```sh
apm install --target claude,codex --https
apm install --frozen --target claude,codex --https
apm audit --ci
```

3コマンドとも終了0。install後・frozen後・audit後のlock SHA-256はすべて `c15f6e15b89ef11c9e3c43ce149088239a2db44f31f8a833daa728f47e5a340a`。manifestとnative lockの `resolved_ref` はexact宣言6件だけで一致し、floating13件はunpinnedのままである。

| 検証 | 結果 | 証跡 |
| --- | --- | --- |
| 17依存の全selected tree比較 | PASS | comparison.json、Git cacheのexact object、Remotionの固定blob比較 |
| 新規native install | PASS、19依存 | install.log / install-result.json |
| 同layout・target・HTTPSのfrozen no-rewrite | PASS、lock不変 | frozen.log / frozen-result.json |
| audit | PASS、10/10、driftなし | audit.log / audit-result.json |
| hub / Claude discovery | PASS、43/43、baselineと同一membership | payload-verification.json |
| 両targetの全ファイル一致 | PASS、602組 | payload-verification.json |
| dependency / deployment ledger hash | PASS、それぞれ1,204ファイル。ledger全1,290件の所有権も不変 | payload-verification.json |
| Impeccable / Matt | PASS、dependency block全体と配備ownership・hash維持 | payload-verification.json |
| worker準備中のsource manifest / lock、#294 helper | 変更なし | baselineコピーとのbyte照合、helper SHA-256 |
| 既存APM runtime・cache refresh・workflow契約テスト | 40実行PASS・1mount skip、exit0 | `tmp/update-283/apm-source-related.log`。root runtimeにも存在する `.agents` mount条件 |
| 隔離chezmoi dry-run | PASS、HOME不変 | `tmp/update-283/source-dry-run-result.json` |
| sourceの統合full Bats | #295で657実行PASS・19skip、exit0 | 必須実hook・テンプレートは別途実行してskipと区別する |

auditのorganization enforcementは、隔離cwdでGit remoteからorgを判定できずskip。baselineでもorganization policyの適用はskipだった。ローカルincludeがないためincludes-consentの実処理も対象外。inactive experimental targetのskipと13件のunpinned warningは既存target / manifest方針に由来し、Claude/Codexの必須配備をskipしたものではない。

## 採用した成果物と後続baseline

- 採用したmanifest: `tmp/update-289/runtime/apm.yml`。変更はRemotion exact pinだけ。
- 採用したnative lock: `tmp/update-289/runtime/apm.lock.yaml`。sourceへbyteコピーし、再整形していない。
- Remotionの新content hash: `sha256:bc5aa6227bce213acbe534be0c35d7454e5c2b20cee5ae17005b2ae640cd423c`。
- #289更新前のsource lock SHA-256: `ef6e2065b6cec632780b4ceac55bd12472dbd4d8bbf69b6b15ab0b65da3a5f8b`。#289採用値は上記 `c15f6e15...`。
- #294 helperの固定SHA-256: `4bd2a84a55acec995fc9c4e39ebbe16db2fad1594f820542382172eed685e6f2`。

rootのbaseline full suiteと#288 source確定後に、coordinatorがmanifest/native lock、既存pin/hash契約の期待値、今回の採用記録を反映した。関連契約と隔離dry-runを確認したpairを #290 のbaselineとした。後続 [#290](update-290-impeccable.md) はImpeccableだけを更新したnative pairを採用し、[#291](update-291-matt-pocock.md) はそれを維持する。最終統合full suiteは [#295](update-295-integrated-acceptance.md) に記録した。

Git cacheに候補treeはあったがRemotionの一部blobが未取得で、lazy fetch禁止のread-only diffは失敗した。baseline cacheを書き換えず、固定tree/blobのGitHub APIから取得して比較を完了した。APM自身は通常のHTTPS native installを使用した。scratchはこのworktreeの `tmp/update-289/` に保存しており、恒久保管先ではない。

## Source採用

rootが全17依存の比較結果・Remotionの本文変更とnative生成結果を確認し、上記manifest / lockをbyteコピーした。pinとcontent hashの既存契約テストは旧sourceでREDを確認し、新しい検証済み値へ追従した。lockは手編集・再整形していない。source反映後のAPM/cache/workflow契約テストと隔離dry-runの確認後、#290へこの採用pairを引き継いだ。

source採用後の関連テストは40実行PASS・1mount skip、exit0。以前の41/41報告を現存ログに合わせて訂正した。`tmp/update-283/apm-source-related.log` と #290 の別実行ログは同じ結果であり、上書きの証拠はない。skip対象は `repo-local Agent skill deploy target is absent` で、現在のroot runtimeもsource `.agents` をmountするため適用される条件である。`chezmoi --source <task worktree> init --no-tty --guess-repo-url=false` と隔離HOMEへの `apply --dry-run --no-tty` は `source-dry-run-result.json` で成功し、dry-run前後でHOMEの全パス・内容が不変だった。#289時点のsource lockも上記 `c15f6e15...` と一致していた。最終統合full Bats・二軸reviewの成功は [#295](update-295-integrated-acceptance.md) に記録した。
