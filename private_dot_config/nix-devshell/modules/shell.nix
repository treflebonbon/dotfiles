{
  pkgs,
  lib,
  flyline,
  ...
}:

{
  packages =
    (with pkgs; [
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
      zsh
      zsh-autosuggestions
      zsh-syntax-highlighting

      # Note-taking
      nb
    ])
    ++ lib.optionals pkgs.stdenv.isLinux [
      flyline
    ];

  # zsh-autosuggestions / zsh-syntax-highlighting は blesh の `blesh-share` の
  # ような discovery 用コマンドを持たないため（NixOS/home-manager の
  # `programs.zsh.*` オプション経由の利用を前提としたパッケージのため）、
  # dot_zshrc.tmpl（macOS 向け、ADR-0020）から直接 source できるよう
  # ファイルパスを env で供給する。
  env = {
    ZSH_AUTOSUGGESTIONS_SHARE = "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh";
    ZSH_SYNTAX_HIGHLIGHTING_SHARE = "${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh";
  }
  // lib.optionalAttrs pkgs.stdenv.isLinux {
    FLYLINE_BASH_LOADABLE = "${flyline}/lib/libflyline.so";
  };
}
