{
  description = "Go project devShell";

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
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              dotfiles.packages.${system}.with-env
              go_1_26
              gopls
              air
              gotests
              gomodifytags
              delve
              golangci-lint
              ko
              wire
              goreleaser
              impl
              oapi-codegen
              sqlc
              gofumpt
            ];
          };
        }
      );

      formatter = forAllSystems (system: pkgsFor.${system}.nixfmt);
    };
}
