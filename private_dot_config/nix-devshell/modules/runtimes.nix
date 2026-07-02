{ pkgs, ... }:

{
  packages = with pkgs; [
    # Cross-language runtimes
    bun
  ];
}
