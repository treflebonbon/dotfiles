---
type: decision
title: WSL2 の Playwright CLI を Managed Playwright Chrome に統一する
description: mirrored networking 上の loopback CDP と専用 profile を境界に、WSL2 の既定 Playwright 操作と Dashboard を Windows Chrome へ統一する
tags: [adr, playwright, wsl2, chrome, cdp, dashboard, to-pr]
timestamp: 2026-07-29
status: accepted
---

# WSL2 の Playwright CLI を Managed Playwright Chrome に統一する

## Context

WSL2 の `playwright-cli` は従来、Nix が配布する WSL 内 Chromium を session ごとに起動していた。この経路は通常の Windows Chrome と認証境界を分離できる一方、Dashboard を含む browser UI が WSL 側と Windows 側へ分かれ、手動で確立した GitHub 認証を `to-pr` の証跡添付へ安全に再利用できなかった。

通常利用の Windows Chrome profile を流用すると、個人の閲覧状態と agent の操作権限が混ざる。任意の CDP endpoint を再利用すると別用途の browser を操作し得る。また、upstream の session 名は CDP 接続先の browser context を分離しないため、同じ endpoint へ複数 session を接続すると agent 間でタブと認証状態が競合する。

## Decision

1. WSL2 の通常の `playwright-cli open [URL]` は **Managed Playwright Chrome** を使う。これは Windows 上の Chrome、`%LOCALAPPDATA%\aiakos\playwright-cli\chrome-profile` の専用 profile、`127.0.0.1:9222` の CDP endpoint を一体として管理する browser identity であり、通常利用の Chrome profile とは完全に分離する。
2. この経路は WSL2 mirrored networking を必須とする。mirrored networking、PowerShell、Windows Chrome、CDP endpoint のいずれかを利用できなければ、修復手順を示して失敗し、WSL 内 Chrome へ黙ってフォールバックしない。
3. 既存 process を再利用するのは、Chrome executable、loopback CDP、port、専用 profile の起動引数がすべて一致するときだけとする。port 競合や不一致 process は自動終了しない。
4. Managed Playwright Chrome を同時に所有できる CLI session は1つだけとする。session 名は保持するが browser context の分離とはみなさず、別 session の同時 `open` は所有者と解放手順を示して失敗する。
5. `--config` / `--browser` / `--profile` / `--persistent` / `--device` / `--mobile` / `--headed`、作業ディレクトリの Playwright CLI config、browser/context を変える環境変数、`attach` は managed 経路へ取り込まず upstream の挙動を維持する。非 WSL 環境も upstream へ透過する。
6. `playwright-cli show` は CLI session と独立した利用者として WSL2 の `127.0.0.1:9323` に Dashboard をバックグラウンド起動し、Managed Playwright Chrome で `http://localhost:9323/` を表示する。通常の `show` は session を要求せず、`show --annotate` だけが Dashboard 接続後に排他 lease を所有する対象 session の annotation flow を実行する。Dashboard server は tab や Chrome window の終了では止めず、`show --kill` まで再利用する。PID・state・log は `$XDG_RUNTIME_DIR` 配下、未設定時は mode 0700 のユーザー専用 `/tmp` directory に置き、stale PID を実 process と port の照合で回復する。明示的な `--host` / `--port` と `show --kill` の upstream 契約は維持する。
7. Managed Playwright Chrome は、排他 CLI session または managed Dashboard の少なくとも一方が利用中の間だけ稼働する。最後の利用者が終了したら Chrome を正常終了するが、専用 profile は保持して次回の session で再利用する。
8. 専用 profile の認証はユーザーが手動で確立した状態だけを再利用する。認証状態は操作許可とはみなさず、実課金・実データ変更・不可逆操作の承認境界は task scope に従う。自動ログイン、通常 Chrome profile の流用、認証情報の import は行わない。`to-pr` は専用 profile が事前に GitHub 認証済みの場合だけ PR 証跡の添付に利用し、未認証なら従来どおり手動添付へ移る。
9. managed session に対する `delete-data` は専用 profile を削除せず、手動リセット手順を示して失敗する。managed 経路外の upstream session に対する `delete-data` は従来どおり透過する。
10. `close-all` / `kill-all` は upstream の session 終了を実行した後で managed lease を整合する。managed session がなく、Dashboard も動作していなければ Chrome を正常終了するが、`kill-all` を Windows Chrome の強制終了へは拡張しない。
11. Managed Playwright Chrome が動作中なのに現在の WSL runtime に対応する lease または Dashboard state がなければ、別 distribution の所有または orphan とみなして再利用せず fail closed にする。distribution 横断の共有 lease は設けない。
12. CDP 接続した upstream は既存 context の先頭 tab を `open` の遷移先にするため、managed mode に限る package patch で `goto` を `tab-new [URL]` に置き換える。`browser.cdpEndpoint`、session 名、公開 `open` 契約は維持し、既存の Dashboard tab や認証用 tab を上書きしない。

## Consequences

- WSL2 の通常操作、Dashboard、annotation は同じ Windows browser identity に揃い、専用 profile の手動ログイン状態を session 間で再利用できる。
- 固定 port と単一 browser context を安全に扱うため、managed 経路は同時に1つの CLI sessionへ制限される。
- 明示 override は WSL 内 browser を使い得るが、それはユーザーが upstream 挙動を選んだ経路であり、managed 経路のフォールバックではない。
- 現在の WSL2 が NAT mode の場合、mirrored networking へ切り替えて WSL を再起動するまで managed 経路の実機検証は成功しない。

本 ADR は [ADR-0026](0026-attach-playwright-evidence-to-pr.md) の WSL2 browser 境界に関する Decision 4 と対応する consequence を置き換える。PR 添付方式、未認証時の手動添付、認証の自動確立を禁止する判断は維持する。

関連: [skill-harness](../../runtime/skill-harness.md) / [ADR-0017](0017-element-pointing-feedback-in-tdd.md) / [ADR-0026](0026-attach-playwright-evidence-to-pr.md)
