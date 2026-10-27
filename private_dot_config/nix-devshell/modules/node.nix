{ pkgs, ... }:

{
  packages = with pkgs; [
    # Toolchain
    nodejs-bin

    # LSP
    typescript-language-server
    typescript
  ];
}
