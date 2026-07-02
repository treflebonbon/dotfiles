{ pkgs, ... }:

{
  packages = with pkgs; [
    # Security scanners
    hadolint

    # GitHub Actions
    actionlint
    ghalint
    pinact
  ];
}
