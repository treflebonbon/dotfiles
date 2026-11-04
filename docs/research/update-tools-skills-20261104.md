# ツール・管理スキル更新（2026-11-04）

## 依頼と作業境界

今回の依頼原文は「`$implement ツールとスキルの更新`」。ユーザーが選択した「AI ツール＋全管理スキル」を範囲とし、既存の配布経路と検証ゲートを使い、APM 本体の修正版を維持する。過去の更新記録の追加指示を今回の要件とは扱わない。開始点は `origin/main` / HEAD `0b7ce88e0e60b3614d0e0fff38fb285ea1af7d72`、Codex native task worktree は `/home/ubuntu/.codex/worktrees/7a94/dotfiles`、branch は `chore/update-tools-skills-20261104`。実装・検証・レビュー・コミットを行い、PR 公開・merge・live 配備はこの依頼の範囲に含めない。

## 更新単位と予定変更

| 更新単位 | 適用する判断 | 予定する変更・判定 |
| --- | --- | --- |
| AI ツールの snapshot | ADR-0045 の更新単位分離と最新 amendment、ADR-0047 の品質 floor、Architecture の upstream direct package 方針 | default branch HEAD を一度固定し、導入済み6ツールの版・3 system の cache・Linux 起動を照合する。独自 patch と自前ビルドを追加しない。APM は修正済みの既存 output を維持する。 |
| 通常 APM payload | ADR-0045 と runtime/skill-harness.md の lock 生成・配備比較 | 全 dependency の selected subtree を確認する。実体差分だけを採否判断し、native lock 生成・frozen 不変・audit・両 target と所有権 ledger の比較後に採用する。 |
| Impeccable skill / engine | ADR-0053 の skill / engine 一体検証 | 安定 release の差分があれば独立した Design Hook gate で検証する。 |
| Matt Pocock managed set | ADR-0042 の ordered gate | full set に実体差分がある場合だけ専用 gate と native lock 採用を行う。 |
| 公開 skills plugin | ADR-0082 の完全な pin record と current payload 照合 | upstream source と現行 pin を比較し、必要な runtime 受入を満たした場合だけ pin record 全体を更新する。 |
| 個別 CLI | 現行の公式 binary / Nix 配布方式 | waza、design.md、Playwright CLI と文書変換 CLI の安定版を調査し、配布経路を変えず検証できる候補を採用する。 |

テストと runtime に残る旧版の期待値、現行運用を説明する文書も変更対象に含める。変更不要・却下・保留と、その根拠は調査結果へ追記する。公開・merge・配備の未実施を source 検証の成功と混同しない。

## 証跡

調査・候補 runtime は `/tmp/codex/update-tools-skills-20261104.019RxR/` に保存する。検証は task worktree の `scripts/verification_env.py` / `scripts/verify-ai-tools.py` から開始し、通常 HOME への書込みを防ぐ。

## 調査結果と採否

| 更新単位 | 採否と根拠 |
| --- | --- |
| AI snapshot | `2cae3bb5…` → [`78f777ba4f6141fca604a5cee3f6ff8dfab09f48`](https://github.com/numtide/llm-agents.nix/tree/78f777ba4f6141fca604a5cee3f6ff8dfab09f48) を採用候補とする。Claude Code は 2.1.314 → 2.1.317。他5件は version・derivation・output が3 system とも不変。upstream の flake-parts 更新も native lock に反映し、共有 nixpkgs と独立した APM input は維持する。 |
| 通常 APM | Modern Web Guidance を [`34126856…`](https://github.com/GoogleChrome/modern-web-guidance/tree/341268561baaff256927c931ec8215dbd30e3cee/skills/modern-web-guidance)、Remotion を [`c7cb2fdc…`](https://github.com/remotion-dev/skills/tree/c7cb2fdcacd134fb2ccb9b7a44f9ffa44e467271/skills/remotion-best-practices) へ更新する。Web guide の整理・noise reduction ガイド追加、Remotion 4.0.540 のライセンス案内・同梱 browser 利用案内が主な差分。 |
| Orca computer-use | 調査時 HEAD `68ba160c…` では selected subtree が削除されていた。削除・配布機能の廃止を採用せず、既存の解決済み revision `1bd67185489c66a9e0d841e0134727f171a33764` へ exact pin を追加する。本文と hash は維持する。 |
| Matt Pocock | 現行 `a496f551…` / 1.3.2 を維持する。HEAD `4ae2317d…` の変更は管理対象外の in-progress skill で、公式27件の engineering / productivity subtree と plugin manifest は不変。専用 ordered gate を必要とする payload 更新は採用しない。通常 lock 再生成で `package_type` だけが `marketplace_plugin` → `apm_package` に変わる。runtime/skill-harness.md の native 出力方針に従い、そのまま採用する。 |
| Impeccable | [Skill 4.8.0](https://github.com/pbakaus/impeccable/releases/tag/skill-v4.8.0) / [engine 0.1.18](https://github.com/pbakaus/impeccable/releases/tag/engine-v0.1.18) が最新の安定 release であり維持する。未リリース HEAD の変更は却下する。 |
| 公開 skills plugin | [v0.2.5](https://github.com/treflebonbon/skills/releases/tag/v0.2.5) `6f8a02f3…` を検証したが、strict validator が失敗したため却下し、既存0.2.3の pin record 全体を維持する。候補は282 files、tree `b381bdf0ac8cdc407348c3acafbb537c7f077c2b`、NAR `sha256-a9dpV/dyRuGlhY0UsjovnWCrmrZaPB6Mc3UB5gqLmjw=`。11 skill と contracts / lib / packages / share は現行と同一で、CLI の merged PR 検査とリリース運用等に差分がある。 |
| Playwright CLI | [0.1.23](https://github.com/microsoft/playwright-cli/releases/tag/v0.1.23) を候補に採用する。npm native lock と依存 hash を再生成し、既存の公開 browser 資産・patch・配布方式を維持する。依存する Playwright / playwright-core は上流 CLI が指定する `1.65.0-alpha-2026-10-30`。 |
| その他の CLI / plugin | waza 0.39.1、design.md 0.4.0、Ponytail 5.3.3 は公開安定版と一致し維持する。runtime が自動管理する plugin の導入状態や chrome plugin の配布元は今回の source 更新に含めない。 |
| 文書変換 CLI | 公開候補は Defuddle 0.19.6 / MarkItDown 0.1.9。現行 source-only Nix 定義の更新・新規 source build なしで配布できることを今回検証していないため候補を採用せず、既存0.19.3 / 0.1.7と pin を維持する。新しい独自 override や配布経路は追加しない。 |

通常 APM の他依存は selected payload 不変。shadcn、find-skills、orchestration は floating revision だけが前進し、他は解決済み revision も維持する。orchestration は native install 時に `a905a311c5adcdf23d05ffb8a60e3d7fcf25b567` に解決された。調査開始時 HEAD と異なるが、既存 content hash・配備 bytes の不変を検証している。Herdr の subtree は HEAD と0.9.5 tag で同一のため tag 相当の pin を維持する。

今回の変更は一つの topic branch に集約し、PR 分割は行っていない。公開 plugin の候補 pin は source から外し、却下済みとして上表で追跡する。汎用ランタイム・言語テンプレート・root 開発依存の更新は合意した範囲外である。

## 個別検証

- **確認済み（x86_64-linux / source 評価）:** `llm-matrix.json` で旧・候補の6件×3 system の version / derivation / output を照合した。`nix-cache.json` と `curl-cache.json` で18 output の Numtide cache を確認し、`cache-only.exit-code` / `outputs.exit-code` はともに0。`--max-jobs 0 --builders ''` でLinuxの6 outputを取得し、自前ビルドへ fallback していない。初回の Python HTTP client は403となったが、これはcache不在の根拠にはせず、後続のNix照会・curl照会・Nix取得の成功と区別する。
- **確認済み（通常 APM）:** 保持する修正済みAPM 0.35.0を使い、`ordinary/` で共通スクリプトによる native lock 生成、frozen 前後 SHA-256 `5a6fb05e5f8665f133257e1852f46f1ae606f08384e5e9c7b427a30a50304f4d` 不変、audit 10/10 が成功した。`deployment-result.json` は21 dependency、両target各47 skill、追加8・削除0。`ledger-result.json` はroot metadata、全1508件の既存owner / active_ownerと共有recordの維持を確認した。Matt の変更は package_type だけで、revision・content hash・全配備file / hashは完全不変。
- **確認済み（公開 plugin 候補）:** package static は17/17成功。公式CLIの4テストは3成功・1失敗で、Antigravity 1.4.12のstrict validatorが、候補に新設されたroot `AGENTS.md` はpluginの規則として読み込まれないというwarningを返しexit1となった（`plugin-agy-validation.json`、`plugin-cli.log`）。Codex / Claude / Antigravityの公式installは成功し、Codex導入物のCLIテストも成功したが、strict失敗を覆す根拠にはしない。上流のテスト・payload・validatorの判定を変更せず候補を却下した。新規モデルsessionは呼んでいない。最初のstatic検証は実在しないclass名を指定して起動に失敗したため、正しいclass名での再実行と記録を分けた（`plugin-static.log` / `plugin-static-2.log`）。
- **確認済み（Playwright候補）:** npm native lock の生成・frozen install、CLIの0.1.23表示、既存socket patchのdry-runが成功。npm依存は既存配布済み`prefetch-npm-deps`で取得し、hash `sha256-qclb2w06hyqJ9hMerj1WbtuQYLn45z+eHcW524PWCGw=` を採用した。後続のNix package組立ても成功している。本体のsource buildや新しいpatchの追加は行っていない。

ARM / Darwin は metadata と cache の評価範囲であり、実機起動は未確認。モデル呼出し、実Windows Chrome、通常HOMEへの配備、公開・mergeは検証に含めない。全体回帰と独立レビューの結果は実施後に追記する。
