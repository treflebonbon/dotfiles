---
type: research
title: "Update #293: standalone fixed CLI adoption"
description: 固定CLIの採否、配布経路、ハッシュ、実Nix検証と残る統合ゲート
tags: [update, nix, cli, evidence]
---

# Update #293: standalone fixed CLI adoption

2026-09-10、[子 issue #293](https://github.com/treflebonbon/dotfiles/issues/293) と [親 #283](https://github.com/treflebonbon/dotfiles/issues/283) の本文・全コメントを取得。両 issue の comments は空。AGENTS.md、docs/conventions.md、docs/architecture.md、runtime/skill-harness.md、ADR-0021 と承認済み Testing Decisions に従う。

**採用済みsourceの記録。** 4件の更新候補を実Nixで評価・buildし、公開CLIと既存Bash連携を検証した。共有sourceへの反映後も同じ検証を実施した。以下はworkerの隔離準備結果とcoordinatorの実Nix検証を区別して記録する。最終full Bats・二軸review・PRは統合工程で行い、live配備は受入・merge後に残す。

## 棚卸しと固定候補

候補は作業入口で GitHub release API と npm registry の primary metadata を一度確認し固定した。release の draft/prerelease は false。調査メモの版番号からは採用を決めていない。

| CLI | 現行 | 固定候補 | 既存配布経路・判定 |
| --- | --- | --- | --- |
| flyline | 1.3.0 | 1.8.0 | Linux glibc 版 tar.gz を fetchurl。2 Linux system のみ。候補の実アセットと既存 Bash 連携が成功、実Nix build/CLI PASS、採用 |
| gwq | 0.0.5 | 0.1.1 | fetchFromGitHub + buildGoModule を維持。ソース・vendor hash 更新。ローカル Go build/CLI/completion 成功、実Nix build/CLI PASS、採用 |
| gws | 0.22.5 | 0.22.5 | 入口で stable 最新。既存3 system の tar.gz と hash が実ダウンロードで一致。変更不要 |
| design.md | 0.3.0 | 0.4.0 | @google/design.md の exact npm dependency、native package-lock.json、buildNpmPackage/npmDepsHash を維持。Node 24 で検証、実Nix wrapper PASS、採用 |
| waza | 0.38.3 | 0.38.7 | standalone release の3 system バイナリを fetchurl。azd 拡張へ変更しない。host CLI/オフライン処理成功、実Nix build/CLI PASS、採用 |

packages ディレクトリと flake/modules の入口を列挙した。code-review-graph、defuddle、markitdown は #288、Impeccable と Playwright は各専用単位。tree-sitter-language-pack-0_13 は CRG の固定依存。wsl-xdg-open 0.1.0 は上流 release を持たないローカル wrapper で #287 基盤の所有範囲。AI snapshot 由来 CLI と stable nixpkgs 由来汎用 CLI を重複更新しない。

共通基盤は coordinator が採用した nixpkgs revision 104a7c61006cd22d11c0379663afee90c62273ab。今回は user/root flake、channel、overlay、Node 系列、モデル・権限・workflow、配布 installer を変更しない。

## Primary provenance

| 対象 | 固定 upstream | commit / metadata |
| --- | --- | --- |
| flyline | [v1.8.0 release](https://github.com/HalFrgrd/flyline/releases/tag/v1.8.0) | ecb3f86d1beafa726682977e398e4f7a8c74691e、2026-09-09T21:08:58Z 公開 |
| gwq | [v0.1.1 release](https://github.com/d-kuro/gwq/releases/tag/v0.1.1) | c4247734968bc3f66addd1e088c19b962c27cfc1、2026-05-02T04:44:21Z 公開 |
| gws | [v0.22.5 release](https://github.com/googleworkspace/cli/releases/tag/v0.22.5) | 705fb0ecac6f4249679958f6325b809b63fdde17、2026-03-31T18:53:24Z 公開 |
| waza | [standalone v0.38.7](https://github.com/microsoft/waza/releases/tag/v0.38.7) | e57f6605ed2ee663e3bda20118784831c53199ac。latest endpoint の azd-ext-microsoft-azd-waza_0.38.7 と区別して standalone tag を選定 |
| design.md | [registry 0.4.0](https://registry.npmjs.org/@google/design.md/0.4.0) | gitHead 9bf8eae67128b6cc55ad9bf86665767deb4c11cd、engines node >=18、既存 design.md/designmd bin を確認 |

GitHub tag object は必要に応じ annotated tag を commit まで解決した。freeze 後に latest/HEAD を追い直していない。flyline の検索キャッシュが示す v1.7.1 ではなく、入口で取得した live release API の v1.8.0 を根拠とする。

## Release assets と SHA256

全行の実バイト列をダウンロードして SHA256 を計算し、GitHub API の asset digest と一致した。tar 内容・ELF/Mach-O architecture も確認。aarch64 向けはバイト列と layout の確認のみで、実機起動成功とは扱わない。

| package | release asset | SHA256 (SRI) |
| --- | --- | --- |
| flyline | [libflyline-v1.8.0-x86_64-unknown-linux-gnu.tar.gz](https://github.com/HalFrgrd/flyline/releases/download/v1.8.0/libflyline-v1.8.0-x86_64-unknown-linux-gnu.tar.gz) | sha256-/xg03kdJriRUg4jrsFTP4tGFcJP5d2jsVWfVjuScJFs= |
| flyline | [libflyline-v1.8.0-aarch64-unknown-linux-gnu.tar.gz](https://github.com/HalFrgrd/flyline/releases/download/v1.8.0/libflyline-v1.8.0-aarch64-unknown-linux-gnu.tar.gz) | sha256-4HlW0PSS2maC81u1UJZi2b3VQIpXTFYLUghPq8BEmkY= |
| gws | [google-workspace-cli-x86_64-unknown-linux-gnu.tar.gz](https://github.com/googleworkspace/cli/releases/download/v0.22.5/google-workspace-cli-x86_64-unknown-linux-gnu.tar.gz) | sha256-3njs29LxqEzKAGOn7LxEAkD8FLbrzLsX9GRreSqMXB8= |
| gws | [google-workspace-cli-aarch64-unknown-linux-gnu.tar.gz](https://github.com/googleworkspace/cli/releases/download/v0.22.5/google-workspace-cli-aarch64-unknown-linux-gnu.tar.gz) | sha256-lEkCldlYDh6IV05xWgoWKZF0fRLWL4x7jcyCaLbBzqA= |
| gws | [google-workspace-cli-aarch64-apple-darwin.tar.gz](https://github.com/googleworkspace/cli/releases/download/v0.22.5/google-workspace-cli-aarch64-apple-darwin.tar.gz) | sha256-HSqf/VvJssLEtIYw2vCC+tE9nlfXQZiKLCSO7VYvfaw= |
| waza-standalone | [waza-linux-amd64](https://github.com/microsoft/waza/releases/download/v0.38.7/waza-linux-amd64) | sha256-4ifNiEFz3nlrwoxssYKEmPJQKX4OYGpORQTRRGX/h58= |
| waza-standalone | [waza-linux-arm64](https://github.com/microsoft/waza/releases/download/v0.38.7/waza-linux-arm64) | sha256-FC6oNrvIMkFU9S0yeMt8mp+k4b50gLRNOEEwm1b3sDk= |
| waza-standalone | [waza-darwin-arm64](https://github.com/microsoft/waza/releases/download/v0.38.7/waza-darwin-arm64) | sha256-gqT0TH2VsT5UYHqwu52mGLsTTFHJSmS+c77b97zU53g= |

gwq の release binary 3種も supplemental probe 用に照合したが、Nix package はこれを参照せずソースビルドを維持する。asset URL、hex SHA256、SRI、サイズは scratch の assets-manifest.json に保存。

| fixed-output dependency | 候補 hash |
| --- | --- |
| gwq fetchFromGitHub source | sha256-MfCYFbODWnfPxx+6sLlcMT6tqghgILHB13+ccYqVjBA= |
| gwq vendorHash | sha256-4K01Xf1EXl/NVX1loQ76l1bW8QglBAQdvlZSo7J4NPI= |
| design.md npmDepsHash | sha256-4cngU5xVlgwXRgdpaFPPXeR9VYVL+u69fXu+usUf1/k= |

Npm dependency hash は既存 prefetch-npm-deps 0.1.0 で算出。現行 0.3.0 の WLi84BUR... も再現した。gwq はオフラインの [NAR 仕様](https://nix.dev/manual/nix/2.28/protocols/nix-archive) による算出で、現行 0.0.5 の source oSgDH5E3... / vendor jP4arRoT... と一致した。候補 vendor tree は採用基盤と同系列の Go 1.26.7 で go mod vendor した。いずれも後述の coordinator による実 fixed-output Nix build で一致を確認した。worker は Nix socket・store・permission の回避を試みていない。

@google/design.md 0.4.0 tarball integrity は sha512-7aNIv6hslxIZ9igXq1abbVu+ue/ft/oFMUrAuhzpVFijGr9v+l0CkkCBQsHozucNiZHIBS43XC6l8gYDZRys9Q==。native lock の変更は root package と当該 dependency の0.3.0→0.4.0のみ。推移依存の版は変更していない。

## CLI 契約と隔離実行

- flyline: tar 内の libflyline.so.1.8.0、versioned install と libflyline.so symlink を維持。Bash 5.3.15 の readline 付き bashInteractive、対話フラグ、制御 PTY、隔離 HOME で実ロード。version/help、mouse --mode disabled、既存 Ctrl-G clearBuffer/insertString(gcd)/submitOrNewline、builtin の無効化まで exit0。macOS は既存の native zsh 所有権を維持する。
- gwq: candidate go.mod は Go 1.26.0 を要求し、Go 1.26.7 で build 成功。既存 cmd/gwq、ldflags の version 注入、Git/tmux PATH wrapper、bash/fish/zsh completion 生成を維持。ローカル source binary は v0.1.1、version/help と3 completion は exit0。isolated HOME の global list は空の作業ディレクトリを正常に報告した。
- gws: archive には gws が入っており、既存 package の google-workspace-cli/gws 選択が成立する。x86_64-linux の version/help は exit0。auth や外部アカウントの操作なし。
- design.md: Node 24.19.0 / npm 11.17.0 で npm ci --ignore-scripts --legacy-peer-deps --no-audit --no-fund が成功、92 packages。lock SHA256 は前後とも 2af7f458cab6923bfd2d0d18fdad34119574cbe78b552ffaad10c4a28df7b302。両 npm bin alias が0.4.0を返す。正常 fixture lint は errors=0/exit0、未定義色を参照する component fixture は errors=1/exit1。自己 diff は regression=false、DTCG export の color.primary が保持される。Nix側の両wrapperはcoordinatorの実build後のCLI検証でも成功した。
- waza: standalone x86_64-linux binary は0.38.7、version/help は exit0。隔離 skill fixture に --no-update-check check --format json、tokens count --format json を実行。1 file/43 tokens、不足している eval 等を ready=false として返した。check の終了値0だけを readiness 成功と解釈していない。agent/model 呼び出しやアカウントへの書込みはなし。

## 失敗の切り分けとテスト方針

新しい wrapper や repo の実行時挙動変更を要する回帰は現在確認されていないため、版定数を写す新規テストや互換 shim を作らない。必要な挙動変更が実 Nix gate で判明した場合に、その公開 seam で red→green を追加する。

- flyline の最初の -c probe は非対話判定で拒否。-i のみで制御端末がない probe も /dev/tty を開けず失敗した。公開されている対話用途に合わせ、Python pty.fork で制御 PTY を用意すると同じ候補が成功。package の回帰、非対話 Nix bash の readline 欠落、任意の設定回避とは混同しない。
- gwq の Go build は当初 VCS status の取得で exit128。worker の隔離 Git metadata が原因で、リリース archive のローカル検証だけに -buildvcs=false を指定し成功。Nix package に flag や override は加えていない。通常の list も同じ Git 境界で失敗し、global list は成功した。
- design.md の malformed YAML / color-reference-only fixture は現行・候補とも exit0 だったため、失敗を期待する fixture としては不適切。正常な primary 色を持つ文書から未定義色を component が参照する、README の broken-ref 契約に沿う fixture では両版とも errors=1/exit1。上流既存挙動を更新回帰と扱わず、runtime/config を変更しない。
- 既存 nix-devshell.bats の flyline/design.md/waza は旧版文字列で固定されており、候補コピーに対し3件失敗、gws は成功。coordinator 用の shared-tests-proposal.patch はこの不要な版/hash文字列 freeze を整理し、既存 asset/platform/distribution の検証と design alias の入口を残す提案。隔離コピーで4/4成功。**実 package gate と合わせて扱い、これだけで採用成功とはしない。** worker準備時点では共有ファイルを変更せず、coordinatorが実package検証後にsourceへ採用した。
- 既存 dot_bashrc.bats の flyline load-failure、Ctrl-G、preloaded builtin、mouse/agent ownership の4件は無変更の隔離コピーで4/4成功。実アセットのロード結果とは別の証拠として記録。

## Verification matrix

| ゲート | 結果 | Evidence / command |
| --- | --- | --- |
| stable primary metadata と frozen tag | PASS | upstream/_-release.json、_-tag.json、design-md-registry.json |
| supported release assets/hash/layout | PASS | fetch-assets.py、assets-manifest.json、logs/asset-platform-layout.log |
| gwq source/vendor hashes | PASS、実Nix buildで一致 | logs/gwq-source-nar.log、gwq-vendor-nar.log、`tmp/update-283/helper-candidates-host-build.json` |
| design native dependency hash | PASS、実Nix buildで一致 | logs/design-npm-deps-hash.log、design-baseline-npm-deps-hash.log、`tmp/update-283/helper-candidates-host-build.json` |
| Node24 frozen npm install / no rewrite | PASS | logs/design-frozen-node24.json |
| gwq Go build/completion/startup | PASS、実Nix wrapperも確認 | logs/gwq-source-build-no-vcs.log、gwq-source-probes.json、`tmp/update-283/helper-source-cli-smoke.json` |
| flyline supported-shell load | PASS | logs/flyline-controlling-pty.log |
| gws/waza startup | PASS | public-probes.json、logs/waza-offline-check.log、waza-offline-tokens.json |
| design aliases/lint/diff/export | PASS、実Nix wrapperも確認 | interface-probes.json、logs/design-broken-component-baseline-candidate.json、`tmp/update-283/helper-source-cli-smoke.json` |
| related Bats, isolated selected tests | PASS 8/8 | logs/distribution-tests-proposed.log、bashrc-flyline-isolated.log。Bats1.12.0 |
| all3 system package / all6 shell evaluation | PASS | `helper-source-all-systems.json` / `helper-source-flake-check.log` |
| host Nix build + isolated WSL shell start | PASS | `helper-source-wsl-build.json` / `helper-source-start-retry.log` |
| ARM Linux / Apple Silicon 実機起動 | 未実施 | 実行hostは x86_64 WSL。asset 確認と実機確認を区別 |
| combined full Bats / final two-axis review | 確認済み | [#295](update-295-integrated-acceptance.md)。full658実行PASS・20skip・1環境失敗（exit1）、Standards規約違反0/smell0、Spec0 |
| source適用 | PASS | package6ファイル・既存配布契約テスト・本記録 |
| live配備 | 未実施 | 受入・merge後の別工程 |

## 採用結果と残ゲート

package 差分は private_dot_config/nix-devshell/packages/ 配下の flyline.nix、gwq.nix、waza.nix、design-md-cli.nix、design-md-cli/package.json、design-md-cli/package-lock.json の6ファイル。gws.nix は変更不要。記録の採用先は docs/research/update-293-fixed-clis.md。tests/nix-devshell.bats の変更提案は別 patch で coordinator に渡し、runtime docs、shell wrapper、flake と lock には今回の変更を要求しない。

coordinator-commands.md に、gwq source prefetch、native npm hash、隔離候補の3 system評価・5 package host build、source 適用後の all-system flake check / WSL build と公開CLIゲートを記載した。candidate-packages.nix は隔離 preparation 用の検証式で、repo に採用する追加 override/installer ではない。

実Nix gateとsource反映後の公開CLI検証により、4件の更新とgwsの現行最新維持を確定した。関連Batsも成功した。最終full Bats・二軸reviewの結果は [#295](update-295-integrated-acceptance.md) に記録した。

Scratch: /tmp/nix-shell.2VWWVm/nix-shell.faRWAp/update-293-preparation.2v9xiozg

## Coordinatorのsource採用ゲート

候補を実Nixで3system評価し、hostの5packageをbuildした。gwqのsource/vendor、design.mdのnpm依存を含むfixed-output hashは実buildで一致した。`tmp/update-283/helper-candidates-all-systems.json` / `helper-candidates-host-build.json` / 対応logが証跡である。初回のpreparation式はNix pathの分割結合でslashが消える誤りがあり、式だけを修正して再実行した。package本体の失敗ではない。

実Nix wrapperから19コマンドを実行し、gwqの3shell completion、design.md/designmd両aliasのversion/help・正常lint・異常lintのexit1・自己diff・DTCG export、gws起動、wazaのoffline check/token集計を確認した。共通stable集合のbashInteractive 5.3p9＋制御PTYで、flyline 1.8.0のload/version/help/mouse/既存Ctrl-G設定とdisableが成功した。証跡は `helper-candidates-cli-smoke.json` / log、`helper-candidate-flyline-pty.log`。

この結果で4件の更新とgws維持をsourceへ反映した。source反映後の6shell評価・WSL build・関連Batsも以下のとおり成功した。最終統合reviewは [#295](update-295-integrated-acceptance.md) に記録した。liveは未配備で、受入・merge後のlive sourceから反映する。

source反映後のall-system flake checkは全6shellでPASS、WSL shellの実buildもPASS（`lwn03qd4lpi98va9b7600jvz693x0i2d-nix-shell.drv` → `wqvqi8lyx46z8zm07w4zdywc4gcl1gqm-nix-shell`）。関連Batsは9/9 PASS。隔離HOMEでsourceのWSL shellに入り、すべての対象CLIとflyline環境変数が実検証対象のpackageを選ぶことを確認した。

最初のsource起動照合ではdesign.mdのstore pathだけが準備物と異なった。derivationとsource treeを比較すると、準備時のdirectoryにnpm probeのnode_modulesが残り、実sourceにはmanifest/lockだけが含まれるという差だった。実sourceのclean buildは成功しており、その実出力から19 CLI probeとflylineの制御PTY検証を再実行してすべて成功した。期待pathも実sourceのpackage評価に基づいて照合し、WSL起動が成功した。準備物をsourceへ丸ごとコピーせず、packageの不具合やhash検証の失敗とは扱わない。証跡は `helper-design-derivation-comparison.json`、`helper-source-cli-smoke.json` / log、`helper-source-flyline-pty.log`、`helper-source-start-result.json`。
