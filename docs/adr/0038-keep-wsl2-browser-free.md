---
type: decision
title: WSL2 を browser-free にして Windows 側の用途別 browser identity へ委譲する
description: WSL2 の managed devShell から browser binary を除外し、人間向け URL、通常の自動操作、dogfood を分離した Windows 側 browser identity へ委譲する
tags: [adr, wsl2, browser, xdg-open, playwright, dogfood, cdp]
timestamp: 2026-08-19
status: accepted
---

# WSL2 を browser-free にして Windows 側の用途別 browser identity へ委譲する

ADR-0031 は通常の Playwright 操作を Windows の Managed Playwright Chrome へ移した一方、非 WSL 互換と明示 override のため `playwright-driver` の browser 一式を WSL2 の devShell closure に残していた。これにより WSL2 は引き続き Chromium / Firefox / WebKit を所有でき、URL opener と自動操作の browser routing も別々に決まり得る。現在の環境では過去の `xdg-open` による二重起動自体は再現できず、Nix の Playwright Chromium に desktop handler も確認できなかったため旧 process の直接原因は断定しない。その代わり、WSL2 が browser identity を所有しない境界を設け、WSL browser と Windows browser が同時に起動し得る routing を構造的に除去する。

## Decision

1. managed dotfiles の標準経路では WSL2 の devShell closure に Chromium / Firefox / WebKit を含めず、Playwright の browser download も禁止する。非 WSL Linux と macOS は従来のローカル browser 経路を維持する。手動で別の Nix package や browser を導入する行為は対象外とする。
2. 通常 Linux と WSL2 を同じ Nix `system` から暗黙判定せず、browser-free な `.#wsl` devShell output を設ける。WSL2 の direnv と global environment cache はこの output を自動選択する。repo 側は opt-in marker があり、呼出側が output を明示していない場合だけ共通 `direnvrc` が選択を切り替える。
3. WSL2 の `xdg-open` は HTTP(S) URL だけを PowerShell 経由で Windows の通常の既定 handler へ渡し、`BROWSER=xdg-open` とする。その他の対象と非 WSL 環境は通常の Linux `xdg-open` へ透過する。Windows interop が利用できなければ修復案内付きで失敗し、WSL browser へ fallback しない。
4. 通常の自動操作は ADR-0031 の Managed Playwright Chrome + CDP を維持する。WSL2 では Managed CDP と任意の remote CDPへの明示 `attach` だけを browser 接続経路とし、ローカル browser 起動を要求する `--browser` / `--profile` / project config は拒否する。
5. `dogfood-to-issues` は Windows 側の **Managed Dogfood Chrome** へ CDP 接続する。各 run は通常利用の既定ブラウザおよび Managed Playwright Chromeと状態を共有しない隔離 profileを使い、screenshot、trace、video、console / network、storage stateのevidence contractを維持する。unpacked MV3 extensionはChrome起動時に渡し、service workerがheadlessで登録されない場合だけ、同じprofileをheadedで一度再試行する。
6. Managed Playwright ChromeとManaged Dogfood Chromeは同じ排他管理下に置き、同時起動しない。競合時はownerと終了手順を示して既存consumerを変更せず失敗する。dogfoodのannotationはdogfood側のheaded ChromeへDashboardを開き、最後のconsumer終了時にChromeを正常終了して一時profileを破棄する。
7. browser、CDP、extension、Dashboard、Windows interopのいずれかが利用できない場合も、別browserの起動、browser download、暗黙のcloseまたはmode/profile切替は行わない。
8. mock testに加え、WSL2実機でURL routing、通常Playwright、通常Web dogfood、MV3 dogfood、annotation、排他競合、WSL browser process非生成を確認する。実機確認を実行できなければ変更を完了扱いにしない。

## Considered Options

- WSL内browserを明示overrideとdogfood用に残す案は、browser-free境界を破り、URL openerとの二重起動経路を残すため採用しない。
- `xdg-open` をManaged Playwright Chromeへ接続する案は、人間の日常閲覧と自動操作のprofile・lease・権限を混ぜるため採用しない。通常のWindows browserと用途別Managed Chromeが同時に存在すること自体は許容する。
- WSL2の`dogfood-to-issues`を廃止する案は採用しない。2026-08-19の実機probeで、Windows Google Chrome 151へのCDP接続から通常Webのscreenshot / trace / videoを生成し、隔離profileへ渡したunpacked MV3 fixtureのservice workerも観測できた。
- Windows Playwright Chromiumを追加導入する案は、別browserの配布とlifecycleを増やすため今回は採用しない。PlaywrightがCDP接続を低fidelityとし、extension検証にbundled Chromiumを推奨している点は、Windows Chromeでservice worker登録を必須確認してfail closedにすることで監視する。

## Consequences

- WSL2ではFirefox / WebKitを含むローカルcross-browser testを実行できない。必要な検証は非WSL環境またはCIで行う。
- browser-free outputへの移行後も、既にrealize済みのbrowser pathは通常のNix GCまでstoreに残り得る。本変更は自動GCを行わず、managed closureが参照も起動もしないことを保証する。
- 本ADRは[ADR-0031](0031-managed-playwright-chrome-on-wsl2.md)のDecision 5にあるWSL明示override、WSL内browserを互換経路として配布するconsequence、dogfoodと競合する単一identity前提を置き換える。Managed Playwright Chromeのprofile分離、headless / headed mode、排他lease、認証境界、通常操作でのno-fallbackは維持する。

関連: [CONTEXT](../../CONTEXT.md) / [skill-harness](../../runtime/skill-harness.md) / [architecture](../architecture.md) / [ADR-0031](0031-managed-playwright-chrome-on-wsl2.md)
