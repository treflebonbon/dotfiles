{
  description = "treflebonbon/dotfiles user devShell";

  inputs = {
    # Keep the shared package set fixed while AI tools advance through pinned sources.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    nixpkgs-brotli-sources = {
      url = "github:NixOS/nixpkgs/04b65f5f819c8f0d0592a4b34fb3ee57ac92b1ad";
      flake = false;
    };

    # 共有チャンネルに未収録の安定版言語パッケージの取得元。
    nixpkgs-language-sources = {
      url = "github:NixOS/nixpkgs/0d765791b09356dd5b356559c1b67c1600ca3c5b";
      flake = false;
    };

    # Source only: backport selected package definitions onto 26.05 without
    # moving the shared package set (document converters and FastMCP for CRG).
    nixpkgs-ai-sources = {
      url = "github:NixOS/nixpkgs/d6524aaca2ff07876657ae2b323f24be4874944b";
      flake = false;
    };

    llm-agents = {
      # Immutable installed AI toolset snapshot; modules/ai.nix enforces safety floors.
      url = "github:numtide/llm-agents.nix/959a6e37234ae40e3ae6d4c9a564ec1a8803ccf9";
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
            overlays = [
              (import ./overlays/runtime-security.nix)
              inputs.llm-agents.overlays.shared-nixpkgs
            ];
          };
          lib = pkgs.lib;

          gwq = pkgs.callPackage ./packages/gwq.nix { };
          gws = pkgs.callPackage ./packages/gws.nix { };
          flyline = pkgs.callPackage ./packages/flyline.nix { };
          wslXdgOpen = pkgs.callPackage ./packages/wsl-xdg-open.nix { };

          makeShell =
            browserless:
            let
              moduleArgs = {
                inherit
                  pkgs
                  inputs
                  lib
                  system
                  flyline
                  wslXdgOpen
                  browserless
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
            pkgs.mkShell (
              {
                packages = mergedPackages ++ cicdPackages;
                shellHook = mergedShellHook;
              }
              // mergedEnv
            );
        in
        {
          default = makeShell false;
          wsl = makeShell true;
        }
      );

      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixfmt);
    };
}
