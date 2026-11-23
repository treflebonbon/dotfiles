{ pkgs, inputs, ... }:

let
  bun = pkgs.callPackage (inputs.nixpkgs-language-sources + "/pkgs/by-name/bu/bun/package.nix") { };
in
{
  packages = [ bun ];
  env.NIX_DEVSHELL_BUN_BIN = "${bun}/bin/bun";
}
