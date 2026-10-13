# 通常APM PR分割（2026-10-13）

## 現在の要件と更新境界

現在の承認は「推奨案で進めて」に基づく通常APM保留差分の分割・検証・レビュー・commit・topic push・後続PR作成。native checkout `/home/ubuntu/orca/workspaces/dotfiles/refresh-ordinary-apm-20261013`、branch `dev/refresh-ordinary-apm-20261013`、開始HEAD `ef64dd3b6a2787a8b4b46d53d88649a9270dfa9f`、clean、common dir `/home/ubuntu/ghq/github.com/treflebonbon/dotfiles/.git` を自身で再検証した。同checkoutで全phaseを続け、raw isolation adapterは再起動しない。merge／chezmoi apply、他単位PR、upstream書込みは対象外。

Tool Snapshot PR [#397](https://github.com/treflebonbon/dotfiles/pull/397) は開始HEADへmerge済み。ユーザーは配備済みと報告し、親がlive source一致を確認済み。この担当はそのlive検証を自分の実行結果として転記しない。Snapshot `998b9f267c671917a0b9a88b01e287c3168f3c24`、APM 0.33.0、Nix source／品質floor／Codex cleanup patchを維持する。

適用する [ADR-0045](../adr/0045-separate-llm-agents-and-apm-update-units.md) はDecision 2の全selected subtree比較・floating再解決・同一payloadのexact pin維持、Decision 3／4のImpeccable／Matt独立性、2026-09-01 amendmentのSnapshot先行mergeである。`runtime/skill-harness.md` の隔離lock生成段落119–123、`docs/conventions.md` の更新追跡とcanonical全suite契約に従う。ADRの過去initiativeのlive配備完了境界を今回の承認範囲へ拡張しない。

読み取り参照は統合成果 `864880c0498d9b274c506183a2087f0863d674f7` と元branch `38a4cac5fd55ece548a1778af6c40aa6f2cdfd34`。統合記録 `docs/research/update-tools-skills-20261011.md` は過去の採用・検証・保留の履歴であり、今回の要件やこのbranchの検証結果とは区別する。参照checkoutは変更しない。

## 予定変更と採用候補

通常APMは20 dependencyからImpeccable／Mattを除いた18 dependency。Remotion `7ba4dcf8ebe1626b00baa41e1f2478113719b60b`（TransitionSeries／Interactive指針）、Modern Web Guidance `b31dc0a43ff5d19bcf386a3476a216f3b39a6f55`（追加guide／usage）のexact pinだけmanifestで更新する。Effect-TSの`effect@rc` → `effect@latest`、shadcnのDESIGN.md／coverage追加を候補とし、他floatingのnative revision-onlyを記録する。入口で生成した候補を固定し、検証中にupstreamを追い直さない。

Impeccable `9dad388a41944a0d2b8d1fb547c8556d2ecb49e7`／engine 0.1.12、Matt `b0618bc436ad893b3c5e84e55fba86586d34a404`／公式27 skillを維持する。package_typeのnative変化は手編集せず、pin／payload／ledger一致を別途検証する。候補外metadata driftは無視しない。新logic／上流skill fork／汎用検証helper配布は追加せず、既存テストの対象pin／hash／fixture期待値とこの追跡記録だけを整合させる。

## 統合成果から外した全変更と対応先

以下は開始HEADと統合成果の全file差分を照合した一覧。通常APMの一部分だけ採用するfileも、除外部分を明記する。保留の最新参照先は統合成果 `864880c`（元branch `38a4cac`も保持）。Tool Snapshotの既存分割記録の履歴は削除しない。

| file | 扱い・対応先 |
| --- | --- |
| `apm.lock.yaml` | 通常18依存を再解決。Impeccable／Mattのpin・payload・full set・owner ledgerは維持。 |
| `apm.yml` | 通常APMのRemotion／Modern Web Guidanceの2 pinのみ採用。Impeccable／Matt pin変更は保留。 |
| `bun.lock` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `docs/adr/0045-separate-llm-agents-and-apm-update-units.md` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `docs/architecture.md` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `docs/conventions.md` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `docs/research/braces-response-20261013.md` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `docs/research/tool-snapshot-pr-20261013.md` | 既存履歴を保持し、通常APM対応先への追跡だけ更新。 |
| `docs/research/update-tools-skills-20261011.md` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `flake.lock` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `local-skills/domain-modeling-studio/dist/THIRD-PARTY-LICENSES.txt` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `local-skills/domain-modeling-studio/dist/studio.html` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `local-skills/domain-modeling-studio/package-lock.json` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `local-skills/domain-modeling-studio/package.json` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `package.json` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `private_dot_config/nix-devshell/flake.lock` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `private_dot_config/nix-devshell/flake.nix` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `private_dot_config/nix-devshell/packages/flyline.nix` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `private_dot_config/nix-devshell/packages/gwq.nix` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `private_dot_config/nix-devshell/packages/impeccable.nix` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `private_dot_config/nix-devshell/packages/playwright-cli-agent/package-lock.json` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `private_dot_config/nix-devshell/packages/playwright-cli-agent/package.json` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `private_dot_config/nix-devshell/packages/playwright-cli.nix` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `private_dot_config/nix-devshell/packages/waza.nix` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `runtime/ai-runtimes.md` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `runtime/skill-harness.md` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `scripts/verify-ai-tools.py` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `scripts/verify-apm-deployment.mjs` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `templates/bun/flake.nix` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `templates/elixir/flake.nix` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `templates/gleam/flake.nix` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `templates/go/DEVELOPMENT.md` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `templates/go/flake.nix` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `templates/perl/flake.nix` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `templates/rust/DEVELOPMENT.md` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `templates/rust/flake.nix` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `tests/apm-runtime.bats` | 通常APMのrevision／hash期待値とEffect test名のみ採用。Impeccable／Matt期待値は維持。 |
| `tests/impeccable-engine.bats` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `tests/mattpocock-update-gate.bats` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `tests/nix-devshell.bats` | Remotion pin期待値のみ採用。Playwright期待値とSnapshot記録の参照先は維持。 |
| `tests/verify-ai-tools.bats` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `tests/verify-apm-deployment.bats` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |
| `tests/workflow-contract.bats` | この通常APM単位から除外。元branch／統合成果に保持し、後続PR未作成・保留。 |

同じfile内で除外する変更: `apm.yml`／lock／APMテストのImpeccableとMatt更新、nix-devshellテストのPlaywright 0.1.22と統合記録参照への変更。一般Nix／言語／npm／CLI／Impeccable／Matt／汎用helperの後続PRは未作成・保留。PR #397で採用したSnapshotの差分はこの単位へ再導入しない。

## このbranchの検証計画

source外の隔離cwd／HOME／全XDGでsource-selected APM 0.33.0を照合し、共通generatorのnative生成、同環境のfrozen前後SHA-256不変、auditを確認する。baseline 10 checksと組織policy enforcement skipを区別する。両target discovery、全deployed_filesの実bytes/hash、追加／削除、候補外全metadata／配布hash、Impeccable／Matt pin・payload・fullset・owner ledgerを比較する。参照helperはGit管理外tmpへ読み取り取得して補助に使い、配布しない。

候補bytesと一次資料を照合し、shadcn coverage構文・不足／充足fixture、Effect安定版案内、Remotion／Modern Web配布差分を確認する。関連Bats、root type／変更文書format／diff検査を通したcommit済み差分をfixed point `ef64dd3`からStandards／Specの2軸でレビューする。指摘修正後、このbranchのsource-selected隔離環境でcanonical `lefthook run test`を一度実行し、TAP plan／連続番号／pass・skip・fail／exitを保存する。実Design Hookの別gateを全suiteへ合算しない。結果追記のみでは全suiteを無用に再実行しない。

## このbranchのnative生成と実配布検証

入口でsource-selected APM `/nix/store/wq2wcjgmpcn370kmsszpyx8fyk1wz7x3-apm-0.33.0/bin/apm` とNix metadata 0.33.0の一致を確認し、source外の隔離cwd／HOME／全XDGで `scripts/generate-apm-lock.sh SOURCE_DIR --update` を実行した（exit 0）。生成に使ったmanifestはsourceの2 pinだけを更新した最終manifest。候補をこの生成結果で固定し、検証中に再解決していない。

同環境の `apm install --frozen --target claude,codex --https` はexit 0、前後SHA-256は `c97b972c23b2e45e396fe812cda7651be321c503e21259524eb71bfb4d3cec6c` で不変。`apm audit --ci` はbaseline 10/10・driftなし・exit 0。Git remoteのない隔離cwdのため組織policy enforcementはwarning付きskipで、実行済み検証とは扱わない。

全20 dependency（通常18＋Impeccable／Matt）のselected payloadは以下。実体変更4件のcontent hash・全deployed_files／file hashは参照統合版の選択実体と一致する。floating 5件はresolved_commitだけが変わり、残り11件は全field不変。Orca `1b9a408b8c0f7de5125f4bad8d89eb8419a29a88` とfind-skills `13e4063a1cf913f5606d57d42ab83a86f5001e04` は参照統合版からさらに進んだnative revision-onlyであり、manifestにpinを増やさず自然解決のまま採用した。

| selected dependency | revision | content hash | 採否 |
| --- | --- | --- | --- |
| `anthropics/skills/skills/pdf` | `683bc88e` → `dbd4588f` | `sha256:69e2ac9eb2bbe2881df26acc53b46b39a15cfda206f5357e5f9c83feb0fadcc7` | revision-only |
| `anthropics/skills/skills/skill-creator` | `683bc88e` → `dbd4588f` | `sha256:b2bfe91d69ca99994c0566baede889e7d2b9bb8791c6b6106c5d387392f717f6` | revision-only |
| `cloudflare/security-audit-skill/skills/security-audit` | `c1c8a8c1` → `c1c8a8c1` | `sha256:ac796659de231c3ab76f6ee012836072bdc82928fb019199925c9062800e16c1` | 全field不変 |
| `effect-ts/skills/skills/effect-ts` | `2309e6f2` → `155c50c9` | `sha256:cb225ba5dda169883dfee680fba6c570c89245ba19242a9bc5c3f2ac8218a55f` | payload採用 |
| `googlechrome/modern-web-guidance/skills/modern-web-guidance` | `a9728684` → `b31dc0a4` | `sha256:2bdf613c1efa013eb28bbc1ade3d6542f6864694cb344221b06d6754b183322c` | payload採用 |
| `herdrdev/herdr/skills/herdr` | `7b116c05` → `7b116c05` | `sha256:66715d76e5947497431ec0db32f2693b9c916ad799c3f32b99e6174b4b9c607f` | 全field不変 |
| `mattpocock/skills/` | `b0618bc4` → `b0618bc4` | `sha256:10f083ac2b0207d326f52883a862e9d50c607a887932a906decfbd12e995b6ab` | 全field不変 |
| `mizchi/skills/empirical-prompt-tuning` | `62f58081` → `62f58081` | `sha256:26042612e2d8b6ee1deebcdfc556da494640488e03471aaae74da587ae84fa2b` | 全field不変 |
| `pbakaus/impeccable/.agents/skills/impeccable` | `9dad388a` → `9dad388a` | `sha256:e4204e4067f404ec156a9d32e77a28850eebdafa1f5eb3e50181de6dd841243b` | 全field不変 |
| `remotion-dev/skills/skills/remotion-best-practices` | `32b241b9` → `7ba4dcf8` | `sha256:3b165350181cefb1c8459f1d615fe7230f4d20a62e56a2508dbebff8a071f6d8` | payload採用 |
| `shadcn-ui/ui/skills/shadcn` | `6ea09007` → `30a58d44` | `sha256:0598e176aa87bd0276b8972169d7b058ffeed643e75ca0abb59f10d97748db65` | payload採用 |
| `stablyai/orca/skills/computer-use` | `55eb48c1` → `1b9a408b` | `sha256:1130dcb48ca8c1cf00e1c15242e95f0141cad5299b9fc2ebbcd2779c8c2f3194` | revision-only |
| `stablyai/orca/skills/orca-cli` | `aedb9305` → `aedb9305` | `sha256:ccd717aed7b9866a059b0b31d9a009641a28f6db3201749943fbbb797af4a317` | 全field不変 |
| `stablyai/orca/skills/orchestration` | `55eb48c1` → `1b9a408b` | `sha256:0dc04a0a354974eed5c15115fc6cb7461d7423e95a5b19ee995796cf1383e7ed` | revision-only |
| `supabase/agent-skills/skills/supabase-postgres-best-practices` | `c9be0e93` → `c9be0e93` | `sha256:5766a8e9524c3c2a81041409be237c3baf515aa04a135871a21dd351682d173f` | 全field不変 |
| `vercel-labs/agent-skills/skills/composition-patterns` | `063bee94` → `063bee94` | `sha256:5b3564ca435f4714d5e65023351e1999e4744818603a9cfb6a6f6a61b7d84918` | 全field不変 |
| `vercel-labs/agent-skills/skills/react-best-practices` | `063bee94` → `063bee94` | `sha256:74f142d28d360d78e8bac4f239a84c87f0ced9015729bc72b5458d82ff45b015` | 全field不変 |
| `vercel-labs/agent-skills/skills/react-view-transitions` | `063bee94` → `063bee94` | `sha256:0d0012537fe7619026f0a844fe505958beb2d525afb8f854ac7217798a2785e2` | 全field不変 |
| `vercel-labs/agent-skills/skills/web-design-guidelines` | `063bee94` → `063bee94` | `sha256:a6a44d5498f7e8f68289902f3dedfc6f38ae0cee1e96527c80724cf27f727c2a` | 全field不変 |
| `vercel-labs/skills/skills/find-skills` | `05bf9387` → `13e4063a` | `sha256:913b9d37d0d54047dd65222bb8c67b2bf04e3cb87dcad1729068d7a8b2c8c396` | revision-only |

両target discoveryは各46 skill。全1,372 file hashを実bytesと照合し、SKILL frontmatter、runtime内の配布先、余剰／不足skillを確認した。追加はModern Webの9 guide×2 target＝18 fileとshadcnの6 file×2＝12 file、削除0。owner ledgerは1,464 record、追加30、candidateだけのhash更新112。既存owners／active_ownerは全て不変で、候補外全recordとfloatingのresolved_commitを除く全metadataは不変。ImpeccableとMattはpackage_typeを含む全dependency field、pin／payload／fullset／単独・共有owner ledgerが不変。native package_type変化は今回はなかった。比較に成功したnative lockだけをsourceへコピーし、手編集・oxfmtはしていない。

証拠はGit管理外の `/tmp/nix-shell.eQp2pY/ordinary-apm-20261013-unow0x9a/{generation.log,frozen.log,audit.log,deployment.log,comparison.json,ledger-result.json,plan.json,lock-sha256}`、このcheckoutの `tmp/ordinary-apm-comparison.log`。補助helperは `tmp/reference-verify-apm-deployment.mjs` へ読み取り取得した参照版で、PRへ追加しない。

## payloadの妥当性

変更fileは各targetでEffect 1、Modern Web 41、Remotion 20、shadcn 9。既存fileのaccepted実bytesが開始lockのhashと一致することを確認してcandidateとの差分を保存した。追加guideにはMarkdown見出しがあり、candidateのselected配布bytesは参照統合版と一致する。

- Effectは導入例2箇所だけが `effect@rc` → `effect@latest`。一次資料の [Effect公式commit](https://github.com/Effect-TS/skills/commit/155c50c911f9c99c294ef8a4461981c5bbe6453e) がv4 GAへの整合を示し、[公式installation](https://effect.website/docs/v3/getting-started/installation) でも通常packageの導入を確認した。dotfilesへEffect依存は追加しない。
- Remotionは4.0.535のversion markerとTransitionSeriesの連続clip、managed rootのInteractive指針。 [TransitionSeries公式docs](https://www.remotion.dev/docs/transitions/transitionseries) と [Interactive公式docs](https://www.remotion.dev/docs/interactive) のtiming／schema説明を照合した。動画projectの新設やrenderはしない。
- Modern Webは9 guideの追加、version marker `2026_10_12-dacb5911`、guide利用の開示手順。search／retrieveのCLI構文は既存と同じ。上流 [固定selected subtree](https://github.com/GoogleChrome/modern-web-guidance/tree/b31dc0a43ff5d19bcf386a3476a216f3b39a6f55/skills/modern-web-guidance) とAPM実体のhashで採用物を固定した。追加したUI実装はないため、guidanceが適用されたとするcreditは書かない。
- shadcnは [固定selected subtree](https://github.com/shadcn-ui/ui/tree/30a58d4498f270af1c1e981a7d78a15cf5740841/skills/shadcn) のDESIGN.md手順／showcase assets／coverageを採用。配布された `scripts/showcase-coverage.mjs` の `node --check` はexit 0、2 componentのfixtureで不足時は `1/2`・`Missing: card`・exit 1、充足時は `2/2`・exit 0。新しい検証helperの配布や上流skill forkはしない。

payload差分とcoverage証拠は同runtimeの `payload.diff`／`payload-files.json`／`coverage-result.json`。過去checkoutのテスト成功を転記していない。

## 個別検証と事前レビューの入口

このbranchのsource-selected user／repo devShellを隔離HOME／全XDGで組み合わせ、6 CLIの候補output・version／実起動を照合した。Claude 2.1.296、Codex 0.162.1（cleanup patch付きoutput）、Copilot 1.0.96、Antigravity 1.3.3、APM 0.33.0、Herdr 0.9.3で一致。関連APM／nix-devshell Batsは50件（50通過・skip 0・失敗0）、helper exit 0。TAP planと1から50の連続番号を照合した。証拠は `tmp/ai-tools-g6jn0o1f/{metadata.json,startup.log,exit-code}`。

source-selected Impeccable engine 0.1.12とこの候補runtimeの旧pin launcherを明示し、別gateの実Design Hookは13件（13通過・skip 0・失敗0・exit 0）。Codex native Stop、silent convergence、monorepo／symlink、理由付きignore-value、fail-openを含む既存fixtureを使い、全suiteのpassへ合算しない。証拠は同APM runtimeの `design-hook.tap`／`design-hook-exit-code`。

root `bun install --frozen-lockfile`／`bunx tsc --noEmit`、変更文書とmanifestのOXC format、`git diff --check`は成功。配布shadcnのshowcase TSX 2fileもBunの構文変換がexit 0（同APM runtimeの `showcase-syntax.log`）。source変更はmanifest／native lock／対象期待値／分割追跡の6fileだけで、元差分43fileの採否・保留を追跡している（`tmp/ordinary-apm-scope-check.log`）。新logicはないためTDD用の新seam／配布helperは追加していない。

この差分をcommitし、fixed point `ef64dd3b6a2787a8b4b46d53d88649a9270dfa9f` からStandards／Specをgpt-6-luna／xhighの2軸subagentでレビューする。現在の承認要件、適用ADRの箇所、予定変更と分割追跡、過去統合成果を区別して渡す。指摘修正後の同じsource-selected環境でcanonical `lefthook run test`を一度実行し、最終結果をここへ追記する。

## 事前レビューと最終全suite

実装commit `d8adb3a12125dd23f7186ff9a0dccb5e152c5211` をfixed point `ef64dd3b6a2787a8b4b46d53d88649a9270dfa9f`からStandards／Specの2軸subagent（gpt-6-luna／xhigh）で確認した。Standardsは規約違反0件・smell 0件、Specは欠落／部分実装0件・依頼外追加0件・誤実装0件。両軸へ現在の承認要件、ADR適用箇所、予定変更と元差分43fileの分割追跡、過去統合成果の参考扱いを渡し、指摘修正は不要だった。

同commitのsource・test・依存・検証環境を固定し、隔離HOME／全XDGのsource-selected user／repo devShellで6 CLI output／実起動を再照合した後、このbranch自身でcanonical `lefthook run test`を一度実行した。全769件（735通過・34 skip・失敗0）、runner／helperともexit 0。TAP planは1つで件数と一致し、1から769の全連続番号、bailoutなしを確認した。全tracked sourceのSHA-256も実行前後で不変だった。証拠は `tmp/test-run.vGNrq0/{tap.log,setup.log,environment,exit-code}`、`tmp/ai-tools-wk8mvus9/{metadata.json,startup.log,exit-code}`、集計は `tmp/ordinary-apm-full-result.json`。PythonはNix storeのpython3.14環境、`with-env`は `/nix/store/q3xwg3rk7s8l92a92rmaiqpmh3rmnp1m-with-env/bin/with-env` に解決されている。過去の統合成果の769／787件を代用していない。

34 skipはDesign Hook未materializeの12件、`TEST_PLAYWRIGHT_PACKAGE`未指定の実配布fixture 1件、実モデル／認証／Herdr／隔離runtime／全6言語生成／public Nix app等の既定opt-in 21件。Design Hookは上記別gateで13/13成功したが、全suiteの735通過へ合算しない。組織policy enforcement、ARM Linux／Darwin実機、変更していないPlaywright実配布fixtureと既定opt-inは未確認として残す。

追加の一次資料確認では、[RemotionのInteractive.withSchema公式docs](https://www.remotion.dev/docs/interactive-with-schema) の `layout: 'absolute-fill'`（4.0.535）とwrapperのstyle／dimension契約がcandidateと一致した。[npm公式dist-tags](https://registry.npmjs.org/-/package/effect/dist-tags) のEffect latestは4.0.4でpre-release表記なし（同APM runtimeの `effect-dist-tags.json`）。Modern Web新規security guideは [WICG仕様](https://wicg.github.io/webcrypto-modern-algos/) とalgorithm名／static support detectionを照合した。全ブラウザでの各新APIの実行を完了したとは扱わない。これらは候補の再解決やsourceの追加変更を伴わない。

## 最終記録と公開の境界

全suite後の変更は本記録の結果追記・metadata不変の表現の明確化、既存Snapshot記録への対応commitの追跡だけ。manifest／lock／tests／依存／Nix source／検証環境を変更せず、全suiteは繰り返さない。最終記録と日本語PR草稿を両軸で確認し、未解決指摘がなければ結果をcommitする。clean状態と成功full-suite、source-selected output不変を照合して `git-push-topic` でこのtopicを公開し、remote defaultを確認してPRを作成する。

通常APMの対応実装commitは `d8adb3a`、公開branchは `dev/refresh-ordinary-apm-20261013`。Impeccable／Matt／一般Nix／言語／npm／汎用helper等の後続PRは未作成・保留。通常APM後続PRの公開までが今回の完了境界であり、更新全体の完了とは区別する。merge／live apply／今回の通常APM live配備は行わない。

最終記録とPR草稿のStandards／Specレビューも指摘0件。追跡済み575fileのうち、結果追記対象2fileを除く573fileは全suite前と同じhashで、source-selected 6 CLI metadata／outputとcanonical `with-env` outputも不変と確認した（`tmp/ordinary-apm-final-output-check.log`）。検証条件は不変のため全suiteを繰り返さず、最終結果と追跡をcommitして公開する。

公開結果: [通常APM後続PR #398](https://github.com/treflebonbon/dotfiles/pull/398) を `main` 向けに作成した。`git-push-topic` の公開、作成時のlocal／upstream／PR HEAD `34b946c` の一致、日本語本文と英語Conventional titleを確認済み。今回の通常APM PR作業は公開まで完了し、merge／live配備と他の保留単位は未完了のまま。

## 後続Impeccableへの対応（2026-10-13）

公開時の履歴を保持する。現在はPR #398がmain `7af6a0a` へmerge済みとGitHubで確認し、配備済みのユーザー報告・親のlive source／lock一致確認を引き継いだ。保留Impeccableのmanifest／native lock／Nix package／関連tests／runtime版表記は `dev/update-impeccable-20261013` の [独立分割記録](impeccable-pr-20261013.md) で実装・隔離検証・レビュー・公開する。今回の通常18依存は不変として照合する。Matt／一般Nix／言語／npm／fixed CLI／helper等は統合成果 `864880c` に保持し、後続PR未作成・未配備。Impeccable公開を更新全体やlive配備の完了とは扱わない。

Impeccable対応実装commit `83a8f38` の非candidate19 dependencyと共有ownerを含むledgerは全field不変。candidate実Design Hookを含む同branchのcanonical全suiteは769件（747通過・22 skip・失敗0、exit 0）、事前Standards／Specレビューは指摘0件。最終記録／PR草稿の確認後にtopic／PR公開へ進む。今回のImpeccable live配備、Matt等の後続保留は残る。

Impeccableの対応先は [後続PR #399](https://github.com/treflebonbon/dotfiles/pull/399)。採用実装 `83a8f38`／検証記録 `e7b0d7b` を同topicから公開し、PR作成時のHEAD一致と日本語本文・英語Conventional titleを確認した。最終レビューの時制1文の指摘も修正・再確認済み。通常APMはmerge・配備済み、ImpeccableはPR公開済み・merge／配備未実施、Matt等は引き続き後続PR未作成・未配備と区別する。

## Matt Pocock後続単位（2026-10-13）

先行PR #397／#398／#399はmerge・配備済みという引継ぎを受け、sourceでは開始HEAD `e333f8a` と一致する。Matt候補 `49dd158d1076134a641b33efb035946536778336` は今回の独立branchで実ordered gate Decision 1–7と別runtimeのnative生成・frozen・audit・bytes／ledger比較を通過し、sourceへ採用した。19 non-Matt dependencyは全field不変。詳細と今回の実検証境界は [Matt後続記録](mattpocock-pr-20261013.md) を参照する。採用直後の計画では、採用後の個別検証・2軸レビュー・canonical全suite・PR公開を後続phaseとした。Mattは未merge・未配備、一般Nix／言語／npm／固定CLI／汎用helper等の残差分は引き続き保留で、更新全体は未完了。過去の検証結果を今回の成功へ転記しない。

Mattの対応実装commitは `4e6f129`。採用後個別53件は全通過、2軸レビューの未解決指摘0件、このbranch自身のcanonical全suiteは769件（747通過・22 skip・失敗0、exit 0）で、実Design Hook 13件も全suite内で通過した。最終記録／PR草稿を確認して公開へ進む。検証境界と残保留は [Matt後続記録](mattpocock-pr-20261013.md) に追跡し、Mattのmerge／live配備と更新全体は未完了のまま。

Mattの対応先は [後続PR #400](https://github.com/treflebonbon/dotfiles/pull/400)。実装 `4e6f129`／検証記録 `c6c2d7e` の同topicを `git-push-topic` で公開し、PR作成時のlocal／upstream／PR HEAD一致と英語Conventional title・日本語本文を確認した。Matt PR公開まで完了し、merge／live配備と一般Nix・言語・npm・固定CLI・汎用helper等の残保留は未完了である。
