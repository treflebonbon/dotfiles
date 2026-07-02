{
  description = "treflebonbon/dotfiles user devShell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
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
            config.allowUnfree = true;
          };
          lib = pkgs.lib;

          gwq = pkgs.callPackage ./packages/gwq.nix { };
          gws = pkgs.callPackage ./packages/gws.nix { };

          moduleArgs = {
            inherit
              pkgs
              inputs
              lib
              system
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
