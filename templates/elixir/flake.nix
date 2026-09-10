{
  description = "Elixir/Erlang project devShell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    dotfiles = {
      url = "github:treflebonbon/dotfiles/b4931c5e0d2152e8fb89eba01b3ac130597e55b3";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, dotfiles, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;
    in
    {
      apps = forAllSystems (system: {
        with-env = dotfiles.apps.${system}.with-env;
      });

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = [
              dotfiles.packages.${system}.with-env
              pkgs.beam29Packages.elixir_1_20
              pkgs.beam29Packages.erlang
              pkgs.beam29Packages.expert
            ];
          };
        }
      );

      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixfmt);
    };
}
