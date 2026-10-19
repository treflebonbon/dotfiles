{
  description = "Gleam project devShell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nixpkgs-language-sources = {
      url = "github:NixOS/nixpkgs/fe13242281a67641c0102cdb1087f0ebe586c7df";
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
      pkgsFor = forAllSystems (system: import nixpkgs { inherit system; });
    in
    {
      apps = forAllSystems (system: {
        with-env = dotfiles.apps.${system}.with-env;
      });

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor.${system};
          languagePkgs = import nixpkgs-language-sources { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              dotfiles.packages.${system}.with-env
              languagePkgs.gleam
              # Standalone repo: gleam の erlang target 実行に erlang が要る
              # (旧グローバル env では elixir module の beam が供給していた)。
              beam29Packages.erlang
            ];
          };
        }
      );

      formatter = forAllSystems (system: pkgsFor.${system}.nixfmt);
    };
}
