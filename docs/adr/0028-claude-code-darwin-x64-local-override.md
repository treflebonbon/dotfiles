---
type: decision
title: AI エージェント CLI の x86_64-darwin を local override で復旧する
description: numtide/llm-agents.nix が claude-code / codex / copilot-cli / antigravity-cli の darwin-x64 packaging を打ち切った後も、各配布元本家のバイナリを直接参照する override で Intel Mac サポートを継続する
tags:
  [
    adr,
    nix,
    claude-code,
    codex,
    copilot-cli,
    antigravity-cli,
    darwin,
    llm-agents,
  ]
timestamp: 2026-07-25
status: accepted
---

# AI エージェント CLI の x86_64-darwin を local override で復旧する

## Context

Issue #112（Claude Opus 5 対応）で `minClaudeCode` を 2.1.219 へ床上げする必要が生じた。`numtide/llm-agents.nix` は commit `718f56b955bb`（2026-07-21、「Drop x86_64-darwin support」）で claude-code の darwin-x64 hash 追跡を停止しており、2.1.217 以降のどの commit にも darwin-x64 の packaging は存在しない。素直に pin を進めると `llm.claude-code` は x86_64-darwin 上で `Unsupported system` を throw する。

`flake.nix` は元々 `nixpkgs-26.05-darwin`（Intel Darwin サポート終了は 2026-12-31）を pin し、`allowBroken = system == "x86_64-darwin"` などの互換対応も維持しており、この repo は Intel Mac を積極的にサポートする方針を既に持っている。一方、Anthropic 本家の配布バケット（`storage.googleapis.com/claude-code-dist-...`）を直接検証したところ、2.1.219 時点でも `darwin-x64` バイナリは配布されている（HTTP 200、hash 実測済み）。つまり今回の断絶は upstream nix packaging 側の追跡停止であり、Anthropic 自体の Intel Mac 打ち切りではない。

claude-code の修正パッチを適用したレビューで、`v = llm.claude-code.version or null;` が version チェックの前に `llm.claude-code` へアクセスしてしまい、x86_64-darwin では条件分岐に到達する前に throw することが指摘された。この検証の過程で devShell 全体を x86_64-darwin 向けに深く評価（`drvPath` まで強制評価）したところ、同じ pin bump（`533b02e` → `0858b21`）で **codex・copilot-cli・antigravity-cli の3パッケージも同様に x86_64-darwin サポートを失っていた**ことが判明した。いずれも直前の pin では x86_64-darwin 向けの hash / URL / `platforms` 定義が存在しており、配布元（denoland の rusty_v8 バイナリ、npm registry の `@github/copilot-darwin-x64`、Google Cloud Storage の antigravity-cli darwin-x64 tarball）を実際にダウンロードして hash を実測した結果、いずれも該当バージョンのバイナリが今も配布されていることを確認した。つまり4パッケージとも同一原因（llm-agents.nix 側の packaging 追跡漏れ）であり、配布元自体の Intel Mac 打ち切りではない。

## Decision

各パッケージを `pkgs.stdenv.hostPlatform.system == "x86_64-darwin"` のときだけ次の override へ差し替える。他の3 system では `llm.*` をそのまま使う。

- **claude-code**: `private_dot_config/nix-devshell/packages/claude-code-darwin-x64.nix` に Anthropic の配布 URL を直接参照する自前の `stdenv.mkDerivation` を追加。`claudeCode` の let 内で version チェックの前にプラットフォーム選択を行う（`selected` 経由）ことで、`llm.claude-code` への属性アクセス自体が throw する問題を回避する。
- **codex**: `llm.codex.override { librusty_v8 = llm.codex.mkRustyV8Archive { ... }; }` で、欠落した rusty_v8 の x86_64-darwin ハッシュだけをローカルで補う。codex 本体の再パッケージは不要。
- **copilot-cli** / **antigravity-cli**: `llm.copilot-cli.overrideAttrs` / `llm.antigravity-cli.overrideAttrs` で `src`（darwin-x64 バイナリの `fetchurl`）と `meta.platforms` を直接差し替える。両パッケージとも `hashes.json` やその他の内部データが `callPackage` の引数として公開されていないため、`override` ではなく `overrideAttrs` を使う。

トレードオフとして、flake pin 上でこれら4パッケージのいずれかの version が動くたびに、該当する override の `version` / `hash` / URL を手動更新する保守コストをこの repo 側が負う（更新手順は `modules/ai.nix` の各コメントおよび `claude-code-darwin-x64.nix` 冒頭コメントに記載）。numtide 側が packaging を再開すれば、該当する override を削除して `llm.*` に戻せる。

## 補足（2026-07-28）

初版はこの保守コストの発生条件を「`minClaudeCode` / `minCodex` を上げるたび」と書いていたが、これは誤りだった。床は根拠のある release でしか上げない運用のため、**床を据え置いたまま pin だけ進む回**がある。その回に override を放置すると次の2通りに壊れる。

- **claude-code**: `claude-code-darwin-x64.nix` は `version` をハードコードしており、`llm.claude-code` とは独立に固定される。pin が claude-code を上げても x86_64-darwin だけ旧版のまま残り、assert は満たされてしまうため**黙って**プラットフォーム間の version skew が生じる。
- **antigravity-cli**: override の `src` は `old.version` を埋め込む一方で URL 内の内部ビルド ID はハードコードのため、pin が version を上げると存在しない組み合わせの URL になり x86_64-darwin だけ fetch に失敗する。評価は通るのでビルドまで進まないと気付けない。

したがって override を見直す条件は床の変化ではなく「flake pin 上の当該パッケージの version が動いたとき」である。実例として 2026-07-28 の pin 更新（`0858b21` → `64b24c81`）では床を据え置いたまま claude-code 2.1.219 → 2.1.220、antigravity-cli 1.1.6 → 1.1.8 が動き、override 2 件の更新が必要になった（codex / copilot-cli は version 据え置きのため不要）。`flake.nix` / `modules/ai.nix` / `claude-code-darwin-x64.nix` のコメントもこの条件へ揃えた。

この誤りは、x86_64-darwin を実ビルドできない環境では検出が難しい。`nix flake check --all-systems` に加えて devShell を `drvPath` まで強制評価し、生成された derivation が参照するパッケージの version を直接確認することで skew を検出できる。

## 補足（2026-07-31）

pin 更新（`64b24c81` → `a6dcbf72`）で codex 0.145.0 → 0.146.0、copilot-cli 1.0.75 → 1.0.77、antigravity-cli 1.1.8 → 1.1.9 が動いた。配布元の darwin-x64 artifact を直接取得し、copilot-cli は npm tarball の sha256、antigravity-cli は build ID `6572839516635136` の tarball の sha512 を実測して override を更新した。

codex は version が動いたため upstream の package definition も再確認したが、要求する librusty_v8 は 149.2.0 のままだったのでローカル artifact 値は変更していない。claude-code も 2.1.220 のままなので変更なし。これにより、床の上下ではなく pin 上の各 package version をトリガーに個別確認する補足方針をもう一度実証した。
