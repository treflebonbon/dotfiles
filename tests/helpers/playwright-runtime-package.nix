# nix build --impure --no-link --print-out-paths --file tests/helpers/playwright-runtime-package.nix
let
  flake = builtins.getFlake (toString ../../private_dot_config/nix-devshell);
  pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
in
pkgs.callPackage ../../private_dot_config/nix-devshell/packages/playwright-cli.nix {
  nodejs = pkgs.nodejs_24;
  playwright-driver = null;
}
