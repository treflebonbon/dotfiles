{
  pkgs,
  inputs,
  lib,
  ...
}:

let
  llm = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  # AI ツールの baseline は llm-agents flake の pin (flake.lock) で固定する。
  # 判断軸: モデル品質床（Sonnet 5 default = 2.1.197）を保ちつつ、この repo が多用する
  #         subagent / teammate / workflow の error 伝搬・background daemon 安定化を強制する 2.1.199 を新フロアに据える。
  # 更新: cd ~/.config/nix-devshell && nix flake update llm-agents && chezmoi re-add flake.lock
  minClaudeCode = "2.1.199";

  claudeCode =
    let
      v = llm.claude-code.version or null;
      ok = v != null && lib.versionAtLeast v minClaudeCode;
      msg = ''
        claude-code ${toString v} は最低バージョン ${minClaudeCode} を満たしていません。
        Claude Sonnet 5（claude-sonnet-5）を default モデルに昇格した 2.1.197 をモデル品質床として保持しつつ、
        subagent / teammate / workflow の error 伝搬（rate-limit / API error を親へ正確に伝達）と
        background daemon の安定化（~50s ごとの自死・claude stop の respawn 敗け・partial 応答の破棄を修正）を強制する
        2.1.199 を品質ベースラインとして固定しています。この repo は多 agent ワークフローを主用するため床の根拠に据えます。
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
