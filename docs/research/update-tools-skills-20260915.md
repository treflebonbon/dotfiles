# ツール・スキル更新（2026-09-15）

## 要件と採用境界

ユーザーの `/implement ツール、スキル更新` に基づき、既存 AI tool snapshot と APM 全19依存の更新候補を確認する。ADR-0045 に従い、tool snapshot・通常スキル・Impeccable・Matt managed set を別々に採否する。前回更新の native worktree の Git 所属と clean status を検証し、main `28eb3810c1dc416349adbfbee618e60c6e313848` から今回用の topic branch を作成した。

受入条件は exact snapshot と lock の整合、3 system の評価、Linux build・CLI 起動、関連テスト・型チェック・full suite、二軸レビューとコミット。APM に配布差分があれば隔離 install/frozen/audit と更新単位固有のゲートを追加する。品質 floor、モデル・権限、配布経路、新規ツール追加、private skill 改稿は対象外。live apply・push・PR は行わない。

## Tool snapshot

入口で確認した [llm-agents default branch snapshot](https://github.com/numtide/llm-agents.nix/tree/1dedf84794052aa7569df5b8335de60aee97af35) `1dedf84794052aa7569df5b8335de60aee97af35` に固定。旧 snapshot は `e320800dd9dc2b156bfa77fbeeb00e9e7295f3a9`。前回保留の原因だった Nix daemon は今回は接続に成功した。

| ツール          | 旧版    | 候補    |
| --------------- | ------- | ------- |
| Claude Code     | 2.1.267 | 2.1.270 |
| Antigravity CLI | 1.2.0   | 1.2.2   |
| RTK             | 0.48.0  | 0.49.0  |
| Codex           | 0.154.0 | 0.154.0 |
| Copilot CLI     | 1.0.83  | 1.0.83  |
| Herdr           | 0.9.0   | 0.9.0   |
| APM             | 0.30.0  | 0.30.0  |

`nix flake lock` が llm-agents 自身の nixpkgs input も追従更新する。ユーザー共通 nixpkgs と source-only input は維持し、Codex / Herdr の direct package と他ツールの shared overlay の分担を変えない。snapshot に含まれる未導入の prerelease ツールは追加しない。

## スキル候補の比較

全19依存の配布対象は不変のため、manifest と lock を維持する。GitHub compare のファイル一覧で選択 subtree を照合し、300ファイル上限に達した比較は contents API の直下 name / tree・blob SHA を照合した。Matt の差分は repo の `CLAUDE.md` と `scripts/link-skills.sh` だけで、配布する skills と plugin metadata は不変。revision だけの進行を更新理由にしない。

| 依存 | 確認した upstream HEAD | 採否 |
| --- | --- | --- |
| pdf | [`34040c9c56`](https://github.com/anthropics/skills/tree/34040c9c568585f6929bedeaad110ad08f079624) | 配布差分なし・維持 |
| skill-creator | [`34040c9c56`](https://github.com/anthropics/skills/tree/34040c9c568585f6929bedeaad110ad08f079624) | 配布差分なし・維持 |
| effect-ts | [`2309e6f27d`](https://github.com/effect-ts/skills/tree/2309e6f27d9955b434c0e3f394b945c136e89fd2) | 配布差分なし・維持 |
| modern-web-guidance | [`16ed22b43f`](https://github.com/googlechrome/modern-web-guidance/tree/16ed22b43fa56157adadfb25f18a354197d497b9) | 配布差分なし・維持 |
| herdr | [`32503f81f7`](https://github.com/herdrdev/herdr/tree/32503f81f7f22552d86f048afb3de179f44e049a) | 配布差分なし・維持 |
| mattpocock-skills | [`3cca18b368`](https://github.com/mattpocock/skills/tree/3cca18b368ae95cdbdebbff572ccafa662551015) | 配布差分なし・維持 |
| empirical-prompt-tuning | [`66dadd9613`](https://github.com/mizchi/skills/tree/66dadd9613719251c1501ba482c08cbd7f55ffee) | 配布差分なし・維持 |
| impeccable | [`2149fcce39`](https://github.com/pbakaus/impeccable/tree/2149fcce39a90bb409df5f16515f316a76dc6199) | 配布差分なし・維持 |
| remotion-best-practices | [`bd566b65d5`](https://github.com/remotion-dev/skills/tree/bd566b65d521b40fe92e1f26766e82de9e291693) | 配布差分なし・維持 |
| shadcn | [`2b3e6d4f8d`](https://github.com/shadcn-ui/ui/tree/2b3e6d4f8d9161fe5c19340dc383aade392012dd) | 配布差分なし・維持 |
| computer-use | [`ffc331212c`](https://github.com/stablyai/orca/tree/ffc331212c38e9d94af09df74f03afa6e63a0717) | 配布差分なし・維持 |
| orca-cli | [`ffc331212c`](https://github.com/stablyai/orca/tree/ffc331212c38e9d94af09df74f03afa6e63a0717) | 配布差分なし・維持 |
| orchestration | [`ffc331212c`](https://github.com/stablyai/orca/tree/ffc331212c38e9d94af09df74f03afa6e63a0717) | 配布差分なし・維持 |
| supabase-postgres-best-practices | [`8331f91084`](https://github.com/supabase/agent-skills/tree/8331f910845103c08d51f6ca1d86ebb7d1f745e3) | 配布差分なし・維持 |
| vercel-composition-patterns | [`063bee94c3`](https://github.com/vercel-labs/agent-skills/tree/063bee94c3f4df8453406c830b0a7df0f2860278) | 配布差分なし・維持 |
| vercel-react-best-practices | [`063bee94c3`](https://github.com/vercel-labs/agent-skills/tree/063bee94c3f4df8453406c830b0a7df0f2860278) | 配布差分なし・維持 |
| vercel-react-view-transitions | [`063bee94c3`](https://github.com/vercel-labs/agent-skills/tree/063bee94c3f4df8453406c830b0a7df0f2860278) | 配布差分なし・維持 |
| web-design-guidelines | [`063bee94c3`](https://github.com/vercel-labs/agent-skills/tree/063bee94c3f4df8453406c830b0a7df0f2860278) | 配布差分なし・維持 |
| find-skills | [`d6b37f62ae`](https://github.com/vercel-labs/skills/tree/d6b37f62ae23c3825b0ed16c73e123eee0a41fdc) | 配布差分なし・維持 |

## 検証

証跡は同 worktree の `tmp/update-20260915/`。

- `nix flake check --no-build --all-systems`: 全6 devShell と formatter の評価成功。
- 3 system の実 package metadata: 上表の7 CLI の版が一致。
- `nix develop .#wsl --command true` と `bunx tsc --noEmit`: 成功。
- 関連テストの初回実行で snapshot の旧固定値2件が失敗。期待値を今回の revision と本記録へ更新し、該当2件の再実行は2/2成功。初回関連49件はこの2件だけ失敗した。
- Linux user devShell build と隔離 HOME の shell 起動: 成功。full suite は終了0（全732件、710 PASS・22 skip・0 FAIL）。
- 7 CLI は候補 package の絶対パスを使い、隔離 HOME で version/help 計14 probe が終了0。RTK の Git status と Claude PreToolUse hook も成功し、rewrite が permissionDecision=allow を付与しないことを確認。

[Claude 2.1.270](https://github.com/anthropics/claude-code/releases/tag/v2.1.270) と [RTK 0.49.0](https://github.com/rtk-ai/rtk/releases/tag/v0.49.0) は非 prerelease。Claude は長時間セッションの read-only Git 操作で不要な承認が発生する回帰を修正する。RTK は recall・rewrite の変更を含むため、候補の CLI 起動に加え、隔離 HOME で既存の Git コマンド経路を検証する。

RTK rewrite probe は当初終了0を期待して失敗したが、[v0.49.0 の実装](https://github.com/rtk-ai/rtk/blob/v0.49.0/src/hooks/rewrite_cmd.rs) では明示 allow がない場合の終了3は承認を保持する正しい応答だった。CLI help の簡略説明だけで判断せず、仕様どおりの終了値と hook の JSON 出力を照合した。実装や権限を変更して検証を通していない。

## 二軸レビュー

Standards / Spec 各1件: cross-repo の runtime 文書が旧 snapshot だけを案内していたため、`runtime/ai-runtimes.md` に今回の採用版と検証記録へのリンクを追記した。それ以外の指摘なし。

## 最終結果

`nix develop .#wsl --command bun run test` は終了0、全732件（710 PASS・22 skip・0 FAIL）。skip は実機・認証・runtime の opt-in 条件によるもので、実施済みとは扱わない。full suite の再実行は行っていない。型チェック・3 system 評価・Linux build/startup・7 CLI 起動・RTK hook 検証も完了した。aarch64 実機、認証を伴う対話 agent session、live 配備後の動作は未確認。Antigravity の版固有 changelog と advisor 非公開内部構造も保証しない。

二軸レビューの各1指摘は `b005919` で解消し、両 reviewer の再確認で追加指摘なし。コミット hook の format・gitleaks・Conventional Commits 検証も成功。APM manifest/lock は基準コミットから byte 不変。live apply、push・PR は未実施。

主要証跡: `nix-check.log`、`package-metadata.json`、`comparison.json`、`build.log`、`startup.log`、`smoke.json`、`related.log`、`pin-tests.log`、`full-suite.log`。
