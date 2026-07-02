{ pkgs, ... }:

{
  packages = with pkgs; [
    # Toolchain
    python3
    uv

    # LSP / Linter
    ty # Astral's Python type checker (fast alternative to mypy)
    ruff
  ];
}
