{
  description = "Rust project devShell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    dotfiles = {
      url = "github:treflebonbon/dotfiles/63e47ffc471ff5e01f58a8a268ea553b0c9ab976";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      dotfiles,
      rust-overlay,
      ...
    }:
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
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ rust-overlay.overlays.default ];
          };
          rustStable = pkgs.rust-bin.stable."1.98.1".default;
        in
        {
          default = pkgs.mkShell {
            packages = [
              dotfiles.packages.${system}.with-env
              rustStable
            ]
            ++ (with pkgs; [
              rust-analyzer
              bacon
              cargo-nextest
              sqlx-cli
              cargo-audit
            ]);
          };
        }
      );

      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixfmt);
    };
}
