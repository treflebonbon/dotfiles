{
  tool,
  metadata ? null,
}:

let
  flake = builtins.getFlake (toString ../../private_dot_config/nix-devshell);
  system = builtins.currentSystem;
  pkgs = import flake.inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [ flake.inputs.llm-agents.overlays.shared-nixpkgs ];
  };
  original =
    if tool == "claude-code" then
      pkgs.llm-agents.claude-code
    else
      flake.inputs.llm-agents.packages.${system}.${tool};
  # Keep a valid derivation with a distinct identity while replacing only metadata.
  candidate =
    if metadata == null then
      original
    else
      builtins.removeAttrs (original.overrideAttrs (_: {
        name = "quality-floor-${tool}-fixture";
      })) [ "version" ]
      // metadata;
  module = import ../../private_dot_config/nix-devshell/modules/ai.nix {
    inherit system;
    lib = pkgs.lib;
    pkgs = pkgs // {
      llm-agents =
        pkgs.llm-agents
        // pkgs.lib.optionalAttrs (tool == "claude-code") {
          claude-code = candidate;
        };
    };
    inputs = flake.inputs // {
      llm-agents = flake.inputs.llm-agents // {
        packages = flake.inputs.llm-agents.packages // {
          ${system} =
            flake.inputs.llm-agents.packages.${system}
            // pkgs.lib.optionalAttrs (tool == "codex") { codex = candidate; };
        };
      };
    };
  };
  selected = builtins.filter (package: (package.pname or null) == tool) module.packages;
  package = builtins.head selected;
in
assert builtins.length selected == 1;
{
  version = package.version;
  matchesInput = package.drvPath == candidate.drvPath;
}
