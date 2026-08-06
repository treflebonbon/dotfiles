{
  pkgs,
  inputs,
  lib,
  ...
}:

let
  llm = pkgs.llm-agents;

  # Evaluate only these newer package definitions against the shared package set.
  defuddle = pkgs.callPackage (
    inputs.nixpkgs-ai-sources + "/pkgs/by-name/de/defuddle/package.nix"
  ) { };
  markitdown = pkgs.python3Packages.callPackage (
    inputs.nixpkgs-ai-sources + "/pkgs/development/python-modules/markitdown/default.nix"
  ) { };

  # AI ツールの baseline は llm-agents flake の pin (flake.lock) で固定する。
  # 判断軸: モデル品質床（Sonnet 5 default = 2.1.197）と subagent / teammate / workflow の
  #         error 伝搬・background daemon 安定化（2.1.199）、background session のクラッシュ修正
  #         （sleep/resume・stale daemon 乗っ取り防止、2.1.200）を保ちつつ、worktree 隔離の破れ
  #         （subagent が親 checkout でコマンド実行）・daemon auto-upgrade の session 巻き添え停止・
  #         subagent 再委譲による作業消失を修正する 2.1.203、ヘッドレスセッションで SessionStart hook
  #         のイベントがストリーミングされずリモートワーカーに idle-reap されるバグを修正する 2.1.204、
  #         session transcript 改ざん防止・background agent 表示/attach/PR linking/worktree removal の修正を
  #         含む 2.1.205 を新フロアに据える。
  # 注意: 2.1.200 で default permission mode が "default" → "Manual" へ変更。settings.json.tmpl は
  #       defaultMode を明示していないため影響を受ける（詳細は runtime/ai-runtimes.md）。
  # 2.1.201: harness reminder の system role 廃止のみで settings/workflow に影響なし。
  # 2.1.202-2.1.204: worktree 隔離破れ・background daemon 安定性・SessionStart hook のヘッドレス
  #                  ストリーミング不具合を修正。
  # 2.1.205: auto mode の transcript 改ざん防止、background agent 状態表示/attach/PR linking、
  #          Windows worktree removal、file watcher crash を修正。多 agent ワークフロー/worktree
  #          隔離の信頼性に直結するため 2.1.205 へ床上げ（詳細は runtime/ai-runtimes.md）。
  # 2.1.206-2.1.207: EnterWorktree が .claude/worktrees/ 外への進入時に確認を挟むよう変更、
  #                  background agent が update 直後にバックグラウンドで即時アップグレードされる
  #                  よう変更、agent teams で不正な teammate mailbox メッセージによる crash loop を
  #                  修正（teammateMode: auto を使うこの repo に直撃）、background session が
  #                  git worktree 内で cold reopen 後に空表示のまま resume するバグと
  #                  worktreeConfig が worktree 削除後も .git/config に残るバグを修正。
  #                  いずれも worktree 隔離・多 agent ワークフローの信頼性に関わるため 2.1.207 へ床上げ。
  # 2.1.208-2.1.211: background agent / daemon / MCP の安定性に加え、worktree 隔離された subagent が
  #                  main checkout へ git 操作できる不具合、PreToolUse の ask 判断が unsandboxed Bash で
  #                  auto mode に上書きされる不具合を修正。多 agent・worktree 運用の安全性に直結するため
  #                  2.1.211 へ床上げ。
  # 2.1.212-2.1.216: .claude/worktrees symlink 経由の隔離逸脱、worktree subagent が git -C / GIT_DIR
  #                  で共有 checkout を操作できる不具合、resume 時に別 project の残存 worktree へ入る
  #                  不具合を修正。worktree 隔離保証に直結するため 2.1.216 へ床上げ。
  # 2.1.217: background session isolation が symlink 済み working directory を正規化せず、
  #          session がワークスペース folder の外へ脱出できる不具合を修正。worktree 隔離保証に
  #          直結するため床上げ対象に含める。
  # 2.1.219: Claude Opus 5 (`claude-opus-5`) を追加しデフォルト Opus モデルに変更（Issue #112）。
  #          これを新フロアに据える。
  # 2.1.220: release note が "Bug fixes and reliability improvements" の一行のみで、床の根拠に
  #          できる具体記述がない。pin では追従するが床は 2.1.219 のまま据え置く（2.1.201 /
  #          codex 0.144.4 と同じ扱い）。
  # 2.1.221: zsh の [[ ]] regex 内に隠したコマンドが permission check を迂回できる問題を修正。
  #          background session が CLAUDE.md の git 指示に従い、依頼時だけ draft PR を開くようにも
  #          なった。auto mode と worktree workflow の安全性に直結するため床上げする。
  # 2.1.222: worktree 隔離 session / subagent が main checkout に対して destructive git command を
  #          実行できる問題と、background agent task で PreToolUse auto-allow hook が tool restriction を
  #          迂回できる問題を修正。隔離と permission の保証に直結するため床上げする。
  # 更新: flake.nix の llm-agents revision を更新し、nix flake lock 後に flake.lock を re-addする。
  minClaudeCode = "2.1.222";
  minCodex = "0.146.1";

  claudeCode =
    let
      v = llm.claude-code.version or null;
      ok = v != null && lib.versionAtLeast v minClaudeCode;
      msg = ''
        claude-code ${toString v} は最低バージョン ${minClaudeCode} を満たしていません。
        Claude Sonnet 5（claude-sonnet-5）を default モデルに昇格した 2.1.197、
        subagent / teammate / workflow の error 伝搬（rate-limit / API error を親へ正確に伝達）と
        background daemon の安定化（~50s ごとの自死・claude stop の respawn 敗け・partial 応答の破棄を修正）を強制する 2.1.199 に加え、
        background session のクラッシュ修正（sleep/resume 後や stale セッション再開時の途中終了、stale daemon による乗っ取り防止）を
        強制する 2.1.200、worktree 隔離済み subagent が親 checkout でコマンドを実行してしまうバグ・
        background daemon の auto-upgrade 失敗が実行中の全 background session を巻き添えに停止させるバグ・
        claude agents 復帰時に実行中の subagent を無言で停止し最初からやり直すバグを修正する 2.1.203、
        ヘッドレスセッションで SessionStart hook のイベントがストリーミングされずリモートワーカーに
        idle-reap されるバグを修正する 2.1.204、auto mode の session transcript 改ざん防止・
        background agent 状態表示/attach/PR linking・Windows worktree removal・file watcher crash を
        修正する 2.1.205、EnterWorktree の .claude/worktrees/ 外進入時確認・background agent の
        即時アップグレード化を含む 2.1.206、agent teams の teammate mailbox crash loop・
        git worktree 内 background session の cold reopen 後空表示・worktreeConfig 残留を修正する
        2.1.207、background agent の返信再送・更新後 attach 復旧・daemon の世代逆行防止・
        worktree 削除安全化・Remote Control の agent/workflow 可視化・長時間 session の資源リークを
        修正する 2.1.208 に加え、worktree 隔離済み subagent が main checkout で git を変更できる不具合を
        修正する 2.1.210、PreToolUse hook の ask 判断が unsandboxed Bash で auto mode に上書きされる不具合・
        background agent / plugin MCP 再接続の不具合を修正する 2.1.211、.claude/worktrees symlink 経由の
        隔離逸脱と git -C / GIT_DIR による共有 checkout 操作、別 project の残存 worktree への誤進入を
        修正する 2.1.212-2.1.216、background session isolation が symlink 済み working directory を
        正規化せずワークスペース脱出を許してしまう不具合を修正する 2.1.217、Claude Opus 5
        (`claude-opus-5`) を追加しデフォルト Opus モデルに変更する 2.1.219、zsh の [[ ]] regex 内に
        隠したコマンドによる permission check 迂回と background session の git 指示逸脱を修正する
        2.1.221、worktree 隔離 session / subagent の main checkout に対する destructive git command と
        background agent task の PreToolUse restriction 迂回を修正する 2.1.222 を経た現在の
        ${minClaudeCode} を品質ベースラインとして固定しています。
        この repo は多 agent ワークフロー・worktree 隔離・teammateMode: auto を主用するため床の根拠に据えます。
        2.1.200 は default permission mode を "default" から "Manual" へ変更しています（runtime/ai-runtimes.md 参照）。
        修復手順:
          cd ~/.config/nix-devshell
          flake.nix の llm-agents 互換revisionを更新して nix flake lock
          chezmoi re-add ~/.config/nix-devshell/flake.lock
      '';
    in
    assert lib.assertMsg ok msg;
    llm.claude-code;

  codex =
    let
      v = llm.codex.version or null;
      ok = v != null && lib.versionAtLeast v minCodex;
      msg = ''
        codex ${toString v} は最低バージョン ${minCodex} を満たしていません。
        GPT-5.6 対応を含む Codex 0.144.0、standalone installer / code-mode reliability fixes を含む
        0.144.1 に加え、0.144.0 で混入した auto-review（Guardian）prompting のリグレッションを
        revert して修正した 0.144.2 の内容を品質ベースラインとして要求しています。
        さらに、強制削除を含む危険コマンドの検出と拒否理由を改善した 0.144.5 を品質ベースラインとして要求します。
        GPT-5.6 Sol / Terra / Luna の bundled instructions と context window metadata を修正した
        0.144.6 を品質ベースラインとして要求します。
        executor が提供する skill の discover/read、context pressure 下での skill catalog 保持、
        MCP server の refresh/reconnect を含む 0.146.0 を品質ベースラインとして要求します。
        cyber-capable model の auto-review 既定値を安全側へ修正した 0.146.1 を
        品質ベースラインとして要求します。
        llm-agents.nix の flake pin は codex ${minCodex} 以上を含む commit へ更新されている必要があります。
        修復手順:
          cd ~/.config/nix-devshell
          flake.nix の llm-agents 互換revisionを更新して nix flake lock
          chezmoi re-add ~/.config/nix-devshell/flake.lock
      '';
    in
    assert lib.assertMsg ok msg;
    llm.codex;

  markitdown-cli = pkgs.python3Packages.toPythonApplication markitdown;
  codeReviewGraph = pkgs.callPackage ../packages/code-review-graph.nix { inherit inputs; };
  design-md-cli = pkgs.callPackage ../packages/design-md-cli.nix { };
  playwright-cli = pkgs.callPackage ../packages/playwright-cli.nix { };
  waza = pkgs.callPackage ../packages/waza.nix { };
in
{
  env.DISABLE_TELEMETRY = "1";

  packages = [
    # --- AI Coding Agents ---
    claudeCode
    codex
  ]
  ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.bubblewrap ]
  ++ [
    llm.copilot-cli
    llm.antigravity-cli

    # --- Token Optimization ---
    llm.rtk

    # --- Code Review Context ---
    # CLI only. Each repository decides whether to build a graph and add a
    # project-scoped MCP entry; never run the upstream global installer here.
    codeReviewGraph

    # --- Specification & Design ---
    design-md-cli

    # --- Browser Automation ---
    playwright-cli

    # --- Document Conversion ---
    defuddle
    markitdown-cli

    # --- Skill Quality Evaluation ---
    waza

    # --- Agent Package Manager ---
    llm.apm
  ];

  shellHook = ''
    mkdir -p "$HOME/.agents/skills" "$HOME/.claude/skills"
    ln -sfn "${playwright-cli}/share/playwright-cli/skills/playwright-cli" "$HOME/.agents/skills/playwright-cli"
    ln -sfn "../../.agents/skills/playwright-cli" "$HOME/.claude/skills/playwright-cli"
  '';
}
