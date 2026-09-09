---
type: research
title: "#270 の通常 Linux VM 実測"
description: QEMU/KVM の別 Linux kernel と非 root ユーザーで Nix、Codex と worktree の隔離を検証する。
tags: [research, nix, nixos, qemu, kvm, secret-isolation]
timestamp: 2026-09-10
---

# 通常 Linux VM の実測

[#270](https://github.com/treflebonbon/dotfiles/issues/270) の通常 Linux 経路を、WSL2 上の QEMU/KVM が起動した Linux **6.18.33**、非 root の uid 1000 で検証した。WSL2 の kernel 名を差し替えた結果ではない。Nix 2.34.6、Codex 0.153.4、bubblewrap 0.11.2、Git 2.54.0、gh 2.96.0、Python 3.13.14、Bash 5.3.9、coreutils 9.11 を使用した。

[実行スクリプト](../../scripts/secret-isolation-linux-vm.py) は repo の lock が指定する Nixpkgs から [NixOS test driver](../../tests/fixtures/secret-isolation/linux-vm.nix) を build し、KVM を利用できる現在のユーザーで実行する。Nix daemon の権限・group・設定を変える必要はない。

```bash
python3 scripts/secret-isolation-linux-vm.py --output /tmp/secret-isolation-linux-vm-270-result
```

`--output` は新規の絶対パスを指定する。Nix store 由来の上記 8 ツールと Bats、利用者が read/write できる `/dev/kvm`、4 GiB の VM memory、少なくとも 10 GiB の空きディスクが必要になる。`qemu.forceAccel = true` により KVM が使えない場合は失敗する。通常の Nix build user が KVM に接続できない環境では、driver の build と VM の実行を分けるこの手順を使う。

VM の store は `useNixStoreImage = true` と `mountHostNixStore = false` で、選択した CLI と公開 fixture の有限 closure から image を作る。host store 全体を 9P 共有しない。guest 内の probe はさらに専用 local Nix store を準備し、その store だけを外側 bubblewrap へ渡す。root、HOME、PID、network namespace も別になる。[NixOS の store image 設定](https://github.com/NixOS/nixpkgs/blob/64c08a7ca051951c8eae34e3e3cb1e202fe36786/nixos/modules/virtualisation/qemu-vm.nix#L871-L910)

host の HOME、認証情報、worktree 全体は guest に渡さない。Nix expression が読み取る repo 入力は、ファイル名を列挙した検証スクリプト・fixture・Bats・Git metadata 検証用 helper だけである。`restrictNetwork = true` で guest の外部通信も止める。通常 Linux の実サービス認証試験をこの結果に含めない。

VM 起動用 state は指定した output 内に保存する。既定の `/run/user/<uid>` は tmpfs の容量不足を起こし得るため、task 専用の disk-backed `XDG_RUNTIME_DIR` を使う。guest disk は 8 GiB とする。

## 実測と失敗の切り分け

`/tmp/secret-isolation-linux-vm-270-unprivileged/evidence/report.json` は `fixture_result = "passed"`、kernel `6.18.33` を記録した。Nix 評価、shellHook、実 Codex、shell と子プロセス、編集・build・test・commit、合成 GitHub API、stdio MCP、秘密ファイル・親環境・host service の拒否、追加・差替え、ログの dummy sentinel 検査が成功した。`production_ready = false` は、この合成 fixture 単独の成功を本番入口全体の完成としない既存契約である。

最初の root 実行では、外側で capability を破棄した後に Codex が作る内側 user namespace の uid map が失敗した。通常の開発者と同じ非 root ユーザーで実行すると成功した。capability を戻したり Codex sandbox を迂回したりしていない。

証跡は `build.log`、`test.log`、`evidence/report.json`、`evidence/runtime.log`、`evidence/evidence/` に保存する。worktree の独立入力・commit 返却・stage/未 stage の保持試験は `evidence/worktree-tests.log` に保存する。失敗時も guest から証跡を回収してから assertion を返す。実行可能な Nix ファイルを正本とし、文書に別の recipe を複製しない。

NixOS test driver は公式の [外部 project からの test 呼出し](https://github.com/NixOS/nixpkgs/blob/64c08a7ca051951c8eae34e3e3cb1e202fe36786/nixos/doc/manual/development/writing-nixos-tests.section.md#L119-L135) と [guest command API](https://github.com/NixOS/nixpkgs/blob/64c08a7ca051951c8eae34e3e3cb1e202fe36786/nixos/doc/manual/development/writing-nixos-tests.section.md#L205-L223) を使う。

追加実測 `/tmp/secret-isolation-linux-vm-270-worktree` も exit 0 となった。同じ合成統合 probe に加えて、worktree Bats は 4 成功・3 opt-in skip。成功した 4 件は明示入力の独立コピー、変更済み/リンク入力の拒否、commit 返却と host 競合拒否、stage/未 stage の返却と再起動である。skip は実 GitHub・hosted model・外部依存取得で、通常 Linux の実認証接続を検証したことにはしていない。
