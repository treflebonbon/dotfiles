---
type: concept
title: 元のアーキテクチャ候補を改善する peer 協働契約
description: 固定 plugin にある共通契約の参照先
tags: [autonomy, peer, herdr, orca, skills]
---

# 元の候補を改善する peer 協働契約

このファイルは契約本文を複製しません。規範の正本は、固定 plugin source の `contracts/autonomous-peer-contract.md` と `contracts/auto-peer-protection.md` です。

固定版は `~/.config/nix-devshell/skills-plugin.json` の `rev` から次の場所で確認します。

```text
~/.cache/treflebonbon-skills/marketplaces/<rev>/contracts/autonomous-peer-contract.md
~/.cache/treflebonbon-skills/marketplaces/<rev>/contracts/auto-peer-protection.md
~/.cache/treflebonbon-skills/marketplaces/<rev>/skills/herdr-peer-refactor/references/auto-session.md
```

専用 auto peer の deny rule、runtime profile、preflight と起動 wrapper は同じ source の `skills/herdr-peer-refactor/assets/auto-peer/` と `skills/herdr-peer-refactor/scripts/` が正本です。通常の明示 peer 協働と専用 auto の条件を混同しません。source、設定、起動経路、実効 deny のいずれかを確認できない専用 auto は保留し、通常 session や別 profile へ自動で切り替えません。資格情報の登録や人間の有効化は行いません。

`sync-codex-managed-config --verify-only` で Codex の current cache grant と deny を照合し、続けて `sync-skills-plugin --verify-only` が `status: verified` を返すことを確認します。その JSON の `source` が current pin の検証済み source path です。`--verify-source-only` は plugin 導入状態を照合しないため、実行経路の準備確認には使いません。read-only 照合が失敗した場合は専用 auto を起動せず、未確認の場合も pin と配備状態を確認するまで保留します。公開手順・証跡・個別 skill の作業は、この固定 source にある規範文書を参照してください。

Repository 固有の判断は [ADR-0075](../docs/adr/0075-adopt-peer-refactor-skills.md) を参照します。
