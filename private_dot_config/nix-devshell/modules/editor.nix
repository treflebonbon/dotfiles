{ pkgs, ... }:

{
  packages = with pkgs; [
    # Editors
    neovim
    tmux

    # LSP (for neovim)
    lua-language-server
  ];
}
