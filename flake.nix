{
  description = "treflebonbon/dotfiles repository devShell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;
      pkgsFor = forAllSystems (system: import nixpkgs { inherit system; });
      pythonFor = forAllSystems (system: pkgsFor.${system}.python3.withPackages (p: [ p.python-dotenv ]));
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor.${system};
          python = pythonFor.${system};
          withEnvSource = pkgs.runCommand "with-env-source" { } ''
            install -D ${./private_dot_local/bin/executable_devshell-env} $out/bin/devshell-env
            install -D ${./private_dot_local/share/devshell-env/devshell_environment.py} $out/share/devshell-env/devshell_environment.py
          '';
        in
        {
          with-env = pkgs.writeShellApplication {
            name = "with-env";
            text = ''
              export PATH="$PATH:${
                pkgs.lib.makeBinPath [
                  pkgs.git
                  pkgs.nix
                  pkgs.bash
                ]
              }"
              exec ${python}/bin/python3 ${withEnvSource}/bin/devshell-env with-env "$@"
            '';
          };
        }
      );

      apps = forAllSystems (system: {
        with-env = {
          type = "app";
          program = "${self.packages.${system}.with-env}/bin/with-env";
        };
      });

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor.${system};
          basePackages = with pkgs; [
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
            bun
            pythonFor.${system}
            self.packages.${system}.with-env
            git
          ];
        in
        {
          default = pkgs.mkShell {
            packages = basePackages ++ [ pkgs.playwright-driver ];
            PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
            PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
          };
          wsl = pkgs.mkShell {
            packages = basePackages;
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
