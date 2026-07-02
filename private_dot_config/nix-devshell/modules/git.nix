{ pkgs, ... }:

{
  packages = with pkgs; [
    # Git tools
    gh
    lazygit
    gitleaks
  ];
}
