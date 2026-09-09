{
  pkgs,
  inputs,
  lib,
  system,
  browserless ? false,
  ...
}:

let
  llm = pkgs.llm-agents;
  # Codex is a large Rust/LTO build. Use the immutable llm-agents input's direct
  # package so upstream versions match the Numtide cache even though this
  # devShell keeps its shared nixpkgs on the stable branch.
  codexPackage = inputs.llm-agents.packages.${system}.codex;

  # Evaluate only these newer package definitions against the shared package set.
  defuddle = pkgs.callPackage (
    inputs.nixpkgs-ai-sources + "/pkgs/by-name/de/defuddle/package.nix"
  ) { };
  markitdown = pkgs.python3Packages.callPackage (
    inputs.nixpkgs-ai-sources + "/pkgs/development/python-modules/markitdown/default.nix"
  ) { };

  # Snapshot versions and quality floors are independent; adoption history is in ADR-0047.
  minClaudeCode = "2.1.261";
  minCodex = "0.153.4";

  requireQualityFloor =
    {
      name,
      package,
      minimum,
      reason,
    }:
    let
      version = package.version or null;
      actual = if version == null then "不明" else version;
    in
    assert lib.assertMsg (version != null && lib.versionAtLeast version minimum) ''
      ${name} ${actual} は品質 floor ${minimum} を満たしていません。
      採用理由: ${reason}
      判断経緯: dotfiles の docs/adr/0047-test-quality-floors-through-package-outputs.md
      修復手順:
        validated task worktree で private_dot_config/nix-devshell/flake.nix の llm-agents revision を確認・更新し、
        nix flake lock ./private_dot_config/nix-devshell を実行してください。
        検証・受入後に live source から chezmoi apply してください。
    '';
    package;

  claudeCode = requireQualityFloor {
    name = "claude-code";
    package = llm.claude-code;
    minimum = minClaudeCode;
    reason = "read fence の worktree 対応、background resume・teammate 通知と危険コマンド検出の修正。";
  };

  codex = requireQualityFloor {
    name = "codex";
    package = codexPackage;
    minimum = minCodex;
    reason = "Astra の bundled model picker 表示と、model 未指定時の既定モデルの修正。";
  };

  markitdown-cli = pkgs.python3Packages.toPythonApplication markitdown;
  codeReviewGraph = pkgs.callPackage ../packages/code-review-graph.nix { inherit inputs; };
  design-md-cli = pkgs.callPackage ../packages/design-md-cli.nix { };
  impeccable = pkgs.callPackage ../packages/impeccable.nix { };
  playwright-cli = pkgs.callPackage ../packages/playwright-cli.nix {
    playwright-driver = if browserless then null else pkgs.playwright-driver;
  };
  waza = pkgs.callPackage ../packages/waza.nix { };
in
{
  env = {
    DISABLE_TELEMETRY = "1";
    CODEX_ISOLATION_CA_BUNDLE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    IMPECCABLE_BIN = "${impeccable}/bin/impeccable";
  };

  packages = [
    # --- AI Coding Agents ---
    claudeCode
    codex
  ]
  ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.bubblewrap ]
  ++ [
    llm.copilot-cli
    llm.antigravity-cli

    # --- Terminal Workspaces ---
    # Keep the derivation aligned with the pinned Numtide binary cache.
    inputs.llm-agents.packages.${system}.herdr

    # --- Token Optimization ---
    llm.rtk

    # --- Code Review Context ---
    # CLI only. Each repository decides whether to build a graph and add a
    # project-scoped MCP entry; never run the upstream global installer here.
    codeReviewGraph

    # --- Specification & Design ---
    design-md-cli
    impeccable

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
    export MANAGED_CHROME_OWNER="${playwright-cli}/bin/managed-chrome-owner"
    export DOGFOOD_WINDOWS_SCRIPT="${playwright-cli}/share/playwright-cli/dogfood-chrome-windows.ps1"
    mkdir -p "$HOME/.agents/skills" "$HOME/.claude/skills"
    ln -sfn "${playwright-cli}/share/playwright-cli/skills/playwright-cli" "$HOME/.agents/skills/playwright-cli"
    ln -sfn "../../.agents/skills/playwright-cli" "$HOME/.claude/skills/playwright-cli"
  '';
}
