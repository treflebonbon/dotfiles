{
  pkgs,
  inputs,
  lib,
  ...
}:

let
  llm = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  # AI ツールの baseline は llm-agents flake の pin (flake.lock) で固定する。
  # 判断軸: モデル品質床（Sonnet 5 default = 2.1.197）と subagent / teammate / workflow の
  #         error 伝搬・background daemon 安定化（2.1.199）を保ちつつ、background session の
  #         クラッシュ修正（sleep/resume・stale daemon 乗っ取り防止）を追加で強制する 2.1.200 を新フロアに据える。
  # 注意: 2.1.200 で default permission mode が "default" → "Manual" へ変更。settings.json.tmpl は
  #       defaultMode を明示していないため影響を受ける（詳細は runtime/ai-runtimes.md）。
  # 更新: cd ~/.config/nix-devshell && nix flake update llm-agents && chezmoi re-add flake.lock
  minClaudeCode = "2.1.200";

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
        強制する 2.1.200 を品質ベースラインとして固定しています。この repo は多 agent ワークフローを主用するため床の根拠に据えます。
        2.1.200 は default permission mode を "default" から "Manual" へ変更しています（runtime/ai-runtimes.md 参照）。
        修復手順:
          cd ~/.config/nix-devshell
          nix flake update llm-agents
          chezmoi re-add ~/.config/nix-devshell/flake.lock
      '';
    in
    assert lib.assertMsg ok msg;
    llm.claude-code;

  markitdown-cli = pkgs.python3Packages.toPythonApplication pkgs.python3Packages.markitdown;
  design-md-cli = pkgs.callPackage ../packages/design-md-cli.nix { };
  playwright-cli = pkgs.callPackage ../packages/playwright-cli.nix { };
  waza = pkgs.callPackage ../packages/waza.nix { };
in
{
  env.DISABLE_TELEMETRY = "1";

  packages = [
    # --- AI Coding Agents ---
    claudeCode
    llm.codex
    pkgs.bubblewrap
    llm.copilot-cli
    llm.antigravity-cli

    # --- Token Optimization ---
    llm.rtk

    # --- Specification & Design ---
    design-md-cli

    # --- Browser Automation ---
    playwright-cli

    # --- Document Conversion ---
    pkgs.defuddle
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
