{
  description = "treflebonbon/dotfiles user devShell";

  inputs = {
    # 26.05 is the final Nixpkgs release supporting Intel Darwin (through 2026-12-31).
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    # Source only: backport the requested document-converter releases onto 26.05.
    nixpkgs-ai-sources = {
      url = "github:NixOS/nixpkgs/421eebfd0ec7bccd4abe826ce62d7e6e83129493";
      flake = false;
    };

    llm-agents = {
      # Pinned past 718f56b955bb (2026-07-21, "Drop x86_64-darwin support"), which is
      # where upstream stopped tracking darwin-x64 hashes for claude-code, copilot-cli
      # and antigravity-cli. ../packages/claude-code-darwin-x64.nix and the overrides in
      # modules/ai.nix restore x86_64-darwin locally from each vendor's own bucket.
      # Bumping this rev can change any of those versions, so re-check those overrides
      # whenever it moves — not only when minClaudeCode / minCodex move.
      url = "github:numtide/llm-agents.nix/a6dcbf72f6d61519cc12858176f0fdd189853b28";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }@inputs:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
              # MarkItDown pulls pandas -> arrow-cpp, which 26.05 marks broken on
              # Intel Darwin. Keep evaluation available only for this sunset path.
              allowBroken = system == "x86_64-darwin";
            };
            overlays = [ inputs.llm-agents.overlays.shared-nixpkgs ];
          };
          lib = pkgs.lib;

          gwq = pkgs.callPackage ./packages/gwq.nix { };
          gws = pkgs.callPackage ./packages/gws.nix { };
          flyline = pkgs.callPackage ./packages/flyline.nix { };

          moduleArgs = {
            inherit
              pkgs
              inputs
              lib
              system
              flyline
              ;
          };

          fragments = [
            (import ./modules/node.nix moduleArgs)
            (import ./modules/python.nix moduleArgs)
            (import ./modules/runtimes.nix moduleArgs)
            (import ./modules/formatters.nix moduleArgs)
            (import ./modules/shell.nix moduleArgs)
            (import ./modules/editor.nix moduleArgs)
            (import ./modules/git.nix moduleArgs)
            (import ./modules/k8s.nix moduleArgs)
            (import ./modules/security.nix moduleArgs)
            (import ./modules/testing.nix moduleArgs)
            (import ./modules/docs.nix moduleArgs)
            (import ./modules/ai.nix moduleArgs)
          ];

          cicdPackages =
            (with pkgs; [
              act
              cocogitto
              lefthook
              go-task
              dive
              atlas
              tbls
              ghq
              overmind
              graphviz
            ])
            ++ [
              gws
              gwq
            ];

          mergedPackages = builtins.concatLists (map (f: f.packages or [ ]) fragments);
          mergedEnv = lib.foldl' (a: b: a // b) { } (map (f: f.env or { }) fragments);
          mergedShellHook = lib.concatStringsSep "\n" (map (f: f.shellHook or "") fragments);
        in
        {
          default = pkgs.mkShell (
            {
              packages = mergedPackages ++ cicdPackages;
              shellHook = mergedShellHook;
            }
            // mergedEnv
          );
        }
      );

      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixfmt);
    };
}
