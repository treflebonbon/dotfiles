# Orca worker readiness

## 更新単位

ローカル変更につながる診断・実装を Git task worktree で監督するとき、実作業前に worker の割当 worktree を照合する変更。対象は既存 `orca-preflight.py`、その Bats、Orca readiness 手順、runtime の入口 pointer。

## 適用する判断

- [ADR-0046](../adr/0046-separate-orca-native-worktree-entry.md): worktree 作成・選択、built-in agent launch、permission mode は Orca native に委ねる。readiness は launch 後の read-only 検査とし、wrapper や permission override を加えない。
- [ADR-0075](../adr/0075-adopt-peer-refactor-skills.md): 既存 Orca preflight を再利用し、明示依頼の peer-refactor に閉じず一般の Orca supervision からも参照する。専用 auto の開始条件は追加しない。

## 予定変更

- worker が自分の cwd から Task / Dispatch / handle と checkout の六項目を別 JSON に記録し、親が native 割当時に固定した branch / HEAD と worktree path から独立検証する CLI を追加する。
- 別 worktree、primary checkout、割当値・Git metadata・JSON の欠落や不一致を拒否する。ambient `GIT_*` を metadata subprocess から除き、入力 JSON は変更しない。
- `runtime/skill-harness.md` に対象となる Orca supervision の入口 pointer を追加し、既存 Orca reference へ「準備確認のみのDispatch → 記録 → 親照合 → 実タスクのDispatch → 着手」の順を記す。同じ実行 host でのGit照合を前提とし、remote placement は実行host側の独立観測がなければ成功扱いしない。folder workspace と primary checkout の説明・状態確認・読み取り調査は対象外。
- 新しい ADR、外部 orchestration の fork、native launch / permission の変更、`chezmoi apply` は対象外。

## 実装と検証

現行 preflight は、primary checkout から別 worktree 担当の有効な worker receipt を受理した。追加した Bats も実装前に赤を確認してから、既存 CLI に record / verify を追加した。record は worker 自身の cwd から別 JSON を作り、verify は native 割当時に固定した Task / Dispatch / handle / path / branch / HEAD と照合する。metadata subprocess から ambient `GIT_*` を除き、primary checkout、別 worktree、field mismatch、malformed / empty / duplicate JSON、shell 風文字列を拒否し、入力 JSON は変更しない。Bats は一時領域内に独立 repo と primary / linked worktree を作り、他 checkout の存在には依存しない。

関連検証は `nix develop ./private_dot_config/nix-devshell#wsl --command nix develop .#wsl --command bats tests/orca-preflight.bats tests/workflow-contract.bats tests/autonomous-peer-contract.bats tests/local-skills.bats` で76件成功した。全 Bats の `lefthook run test` は初回実装commit `870dd484721847df12c04e07935a79e219a0b2f3` に対して `#default` devShell で終了コード0（1045成功、24 skip、失敗0、計1069）だった。WSL用 `#wsl` ではなく実行した点と、追補は文書・テストのみのため全 suite を再実行していない点を作業 report に記録する。

配備元 `chezmoi source-path` は primary checkout `/home/ubuntu/ghq/github.com/treflebonbon/dotfiles` を指し、local skill source は `.chezmoiignore` で直接配備対象から除外され、`run_onchange_after_deploy-local-skills.sh.tmpl` が各 skill directory へ materialize する。task worktree の source だけを編集し、`chezmoi apply` は行わない。
