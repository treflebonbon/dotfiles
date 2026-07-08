{ pkgs, ... }:

{
  packages = with pkgs; [
    # Prompt
    starship

    # Navigation
    zoxide
    atuin

    # File listing
    eza
    bat
    hexyl

    # Search
    fd
    ripgrep
    fzf

    # Text processing
    jq
    sd

    # Shell tools
    shellcheck
    bash-completion
    direnv
    blesh

    # Note-taking
    nb
  ];
}
