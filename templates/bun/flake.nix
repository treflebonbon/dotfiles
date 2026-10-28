{
  description = "Bun project devShell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nixpkgs-language-sources = {
      url = "github:NixOS/nixpkgs/0d765791b09356dd5b356559c1b67c1600ca3c5b";
      flake = false;
    };
    dotfiles = {
      url = "github:treflebonbon/dotfiles/63e47ffc471ff5e01f58a8a268ea553b0c9ab976";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-language-sources,
      dotfiles,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;
      pkgsFor = forAllSystems (
        system:
        import nixpkgs {
          inherit system;
          overlays = [
            (
              final: prev:
              let
                nodejs = prev.callPackage ./nodejs-bin.nix { };
              in
              {
                typescript = prev.typescript.override {
                  buildNpmPackage = prev.buildNpmPackage.override { inherit nodejs; };
                };
                typescript-language-server = prev.typescript-language-server.override {
                  inherit nodejs;
                  typescript = final.typescript;
                };
              }
            )
          ];
        }
      );
    in
    {
      apps = forAllSystems (system: {
        with-env = dotfiles.apps.${system}.with-env;
      });

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              dotfiles.packages.${system}.with-env
              (callPackage (nixpkgs-language-sources + "/pkgs/by-name/bu/bun/package.nix") { })
              # bun が TS を内包するため typescript 本体は同梱せず、LSP のみ置く。
              typescript-language-server
            ];
          };
        }
      );

      formatter = forAllSystems (system: pkgsFor.${system}.nixfmt);
    };
}
