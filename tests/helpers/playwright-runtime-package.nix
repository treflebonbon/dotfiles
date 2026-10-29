# nix build --impure --no-link --print-out-paths --file tests/helpers/playwright-runtime-package.nix
let
  flake = builtins.getFlake (toString ../../private_dot_config/nix-devshell);
  pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
  pin = builtins.fromJSON (builtins.readFile (flake.outPath + "/skills-plugin.json"));
  skillsPluginSource = pkgs.fetchFromGitHub {
    inherit (pin) owner repo rev;
    hash = pin.nar_hash;
  };
in
pkgs.callPackage ../../private_dot_config/nix-devshell/packages/playwright-cli.nix {
  nodejs = pkgs.nodejs_24;
  inherit skillsPluginSource;
  playwright-driver = null;
}
