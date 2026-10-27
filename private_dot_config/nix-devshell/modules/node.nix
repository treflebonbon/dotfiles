{
  pkgs,
  inputs,
  system,
  ...
}:

{
  packages = with pkgs; [
    # Toolchain
    (import inputs.nixpkgs-node-sources { inherit system; }).nodejs_24

    # LSP
    typescript-language-server
    typescript
  ];
}
