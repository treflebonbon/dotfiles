---
type: research
title: 公開入力からの worktree 実行と変更返却
description: Issue 270 の実 worktree 選別、独立コピー、Git と通常ファイルの返却を検証する契約。
tags: [research, git, codex, secrets]
timestamp: 2026-09-10
---

# 公開 worktree 入力の契約

[検証 CLI](../../scripts/secret-isolation-worktree.py) は既存の linked worktree を選び、秘密を含まないと確認したファイルと Git 履歴だけを独立コピーへ渡す。ファイル名の deny list だけで秘密を分類しない。`codex-worktree` への統合前の検証用 CLI であり、日常利用者の設定へ配備しない。

## 入力

人間が対象 worktree、完全な HEAD SHA とそこから到達する Git 履歴、公開するファイル名を明示する。Git 履歴に既に秘密を含む repository はこの契約で公開できない。追跡ファイルであることや flake の信頼登録だけでは、公開入力と認定しない。

```bash
python3 scripts/secret-isolation-worktree.py approve \
  --root /absolute/linked-worktree --policy /private/state/public-input.json \
  --git-head FULL_HEAD_SHA -- flake.nix flake.lock src/main.py

python3 scripts/secret-isolation-worktree.py run \
  --root /absolute/linked-worktree --policy /private/state/public-input.json \
  --output /private/state/session-1 -- bash public-task.sh

python3 scripts/secret-isolation-worktree.py return \
  --root /absolute/linked-worktree --session /private/state/session-1
```

例の command が読む `public-task.sh` も公開リストに含める必要がある。初回承認は index が HEAD と一致する状態で行う。policy は worktree と Git metadata の外に保存し、対象 root、Git common dir の所有同一性、HEAD、index tree、各ファイルの SHA-256 と executable bit を記録する。起動時に一致を確認してからコピーする。

入力ファイルと全親ディレクトリの symlink を拒否し、ファイルは regular file・link count 1 に限定する。読取り前後の変更も検査する。コピー後に host 側へファイルを追加したり、元ファイルを秘密に差し替えたりしても隔離内の inode は変わらない。リンクや変更を受け付けて処理を続ける fallback はない。

Git の既存 metadata directory 全体は共有しない。承認した HEAD/history と index の到達オブジェクトを pack し、Git common dir、branch ref、linked metadata pointer と index を独立領域に再構成する。隔離内では元の絶対 root と metadata path に mount する。host の hooks、credential helper、Git config、別 branch の履歴、reflog、別 worktree はコピーしない。

## 実行と返却

空の root/HOME、専用 local Nix store、独立した PID/network namespace の中で実行する。親の任意環境変数と control socket は渡さない。選択した gateway の private socket ディレクトリだけを read-only で公開できる。

終了時は HEAD、index tree、通常ファイルの一覧と Git bundle を保存する。command の非0終了でも export が成功すれば終了コードを保持する。返却を失敗した場合も session を保存し、隔離を解除して再実行しない。

返却側は bundle を隔離用 Git repository で検査し、元 HEAD からの fast-forward、regular file の tree、host の branch/index/入力ファイルが変わっていないことを検査する。unapproved な host ファイルを上書きしない。host の ref transaction と index lock を使い、HEAD・stage 済み内容・未 stage の編集・非 ignored の新規通常ファイルを戻す。返した公開データで policy を更新するため、次の起動も同じ state を使用できる。host 側で変更がある場合は自動再承認せず拒否する。

Git hooks と checkout filter は host の返却処理では実行しない。通常の task commit の hooks・identity・既存設定との接続は #271 で扱う。返却処理の複数ファイル更新全体は filesystem transaction ではなく、途中の I/O 失敗では部分変更が残り得る。その場合は保存した session を基に人間が状態を照合して復旧する。ホスト側で並行編集しながら返却する用途の保証はない。

## 実測

[Bats](../../tests/secret-isolation-worktree.bats) で、入力の独立性、起動前の差替え/symlink/hardlink/親 symlink の拒否、実 Git commit の同一 SHA 返却、host の並行編集拒否、stage/未 stage/新規ファイルの返却と再起動を確認した。WSL2 と [通常 Linux VM](secret-isolation-linux-vm-270.md) の両方で成功した。

WSL2 ではさらに実 Nix、hosted model を使う実 Codex、子プロセス、実 gh の公開 GET、stdio MCP を一つの起動に通した。secret probe はダミー値のみで、モデルと GitHub の既存ログイン値は host gateway の外へ出さない。[通信境界と結果](codex-isolation-connectivity-271.md)を参照。

この成果は入力と結果返却の最小成立確認である。標準 permission/network policy、trust、output 選択、通常の commit hooks、起動ポリシーの配備と公開 raw CLI の回帰は #271 で検証する。Herdr のイベント連動と GitHub/MCP の利用者設定統合はこの probe の成功に含めない。
