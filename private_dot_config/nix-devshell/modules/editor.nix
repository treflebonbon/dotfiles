{ pkgs, ... }:

{
  packages = with pkgs; [
    # Editors
    neovim
    tmux
    tree-sitter

    # LSP (for neovim)
    lua-language-server
  ];
}
