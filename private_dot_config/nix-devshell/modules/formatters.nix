{ pkgs, ... }:

{
  packages = with pkgs; [
    # Code formatters
    oxfmt
    shfmt

    # Linters (available globally for other projects)
    oxlint
    tombi
    markdownlint-cli2
  ];
}
