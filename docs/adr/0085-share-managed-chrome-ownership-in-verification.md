---
type: decision
title: 保護付き検証の明示モードで Managed Chrome 所有権記録だけを書込み可能にする
description: verification_env.py --managed-browser が共通所有権記録とホスト PID namespace を使う
tags: [adr, verification, browser, wsl2]
timestamp: 2026-11-06
status: accepted
---

# 保護付き検証の明示モードで Managed Chrome 所有権記録だけを書込み可能にする

`scripts/verification_env.py` は通常 HOME を read-only にしたまま、隔離前の共通 `BROWSER_OWNERSHIP_DIR` を引き継ぐ。一方で公開の `managed-chrome-owner` は `status` でも記録先の `chmod` と `ownership.lock` を使い、`reserve` / `release` は記録を書き換える。そのため記録先が HOME 配下（WSL2 の既定は `~/.local/run/browser-ownership`）にあると、保護付き検証から起動した実 Chrome の操作は Chrome 起動前に `EROFS` で停止する。別の空の記録先を使うと実際の CDP port の予約を参照できなくなるため、代替先は採らない（[ADR-0047](0047-centralize-managed-chrome-ownership.md)）。

`--managed-browser` を指定した場合だけ、この共通記録先を書込み可能にする。指定しない既定モードは、従来どおり記録を read-only で引き継ぎ、private PID namespace も維持する。

- 対象は呼出元から解決した記録先そのものに限る。絶対 path で指定された `browser-ownership` という名前の既存 directory で、本人所有・厳密に mode 700・symlink を含まないことを、作成や `chmod` の前に検査する。保護対象（通常 HOME・共有 scratch・検証ログ・task worktree・Git metadata）そのもの、またはそれを包含する directory も拒否する。これらの子孫は拒否しない。満たさない場合は起動せず、記録先を変更しない。
- 通常 HOME の他の path とホスト filesystem は read-only のまま維持する。
- 所有権記録の caller PID は、ホストの `/proc` の開始時刻と boot id で生存を照合する。private PID namespace では PID が別の主体を指し、ホスト側の予約を誤判定する。そのため明示モードは `--unshare-pid` と専用 `/proc` を使わず、ホストの PID namespace とホストの `/proc` を使う。
- 帰結として、明示モードのコマンドは同じ利用者のホスト process を参照でき、signal も送れる。filesystem の書込み境界は変わらないが、process の隔離は弱まる。実 Chrome を操作するなど必要な場合に限って指定する。
- 実行記録の `boundary.json` に `managed_browser_ownership`（既定モードは `null`）と `pid_namespace`（`host` または `private`）を残す。

`verify-ai-tools.py` は Nix 評価と dotfiles の Bats 用の入口で、実際の Managed Chrome を操作しないため、このモードを伝播しない。
