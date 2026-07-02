{ pkgs, ... }:

{
  packages = with pkgs; [
    # Toolchain
    nodejs_24

    # LSP
    typescript-language-server
    typescript
  ];
}
