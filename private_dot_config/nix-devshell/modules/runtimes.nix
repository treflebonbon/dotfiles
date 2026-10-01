{ pkgs, inputs, ... }:

{
  packages = [
    # Cross-language runtimes
    (pkgs.callPackage (inputs.nixpkgs-language-sources + "/pkgs/by-name/bu/bun/package.nix") { })
  ];
}
