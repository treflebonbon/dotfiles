{ pkgs, ... }:

{
  packages = with pkgs; [
    # Documentation tools
    marp-cli
  ];
}
