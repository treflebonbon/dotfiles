{ pkgs, ... }:

let
  cloudflare = pkgs.callPackage ../packages/cloudflare-cli.nix {
    nodejs = pkgs.nodejs-bin;
    buildNpmPackage = pkgs.buildNpmPackage.override { nodejs = pkgs.nodejs-bin; };
  };
in
{
  packages = with pkgs; [
    # Toolchain
    nodejs-bin
    cloudflare

    # LSP
    typescript-language-server
    typescript
  ];
}
