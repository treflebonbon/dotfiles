{
  description = "treflebonbon/dotfiles repository devShell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;
      pkgsFor = forAllSystems (system: import nixpkgs { inherit system; });
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              chezmoi
              lefthook
              cocogitto
              shellcheck
              shfmt
              actionlint
              ghalint
              pinact
              oxfmt
              nixfmt
              gitleaks
              (bats.withLibraries (p: [
                p.bats-support
                p.bats-assert
              ]))
              nodejs_24
              playwright-driver
              bun
              git
            ];
            PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
            PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
          };
        }
      );

      formatter = forAllSystems (system: pkgsFor.${system}.nixfmt);

      templates = {
        go = {
          path = ./templates/go;
          description = "Go project devShell";
        };
        rust = {
          path = ./templates/rust;
          description = "Rust project devShell";
        };
        elixir = {
          path = ./templates/elixir;
          description = "Elixir/Erlang project devShell";
        };
        perl = {
          path = ./templates/perl;
          description = "Perl project devShell";
        };
        gleam = {
          path = ./templates/gleam;
          description = "Gleam project devShell";
        };
        bun = {
          path = ./templates/bun;
          description = "Bun project devShell";
        };
      };
    };
}
