let
  flake = builtins.getFlake (toString ../../private_dot_config/nix-devshell);
  system = builtins.currentSystem;
  pkgs = import flake.inputs.nixpkgs { inherit system; };
  graph = builtins.head (
    builtins.filter (
      package: (package.pname or "") == "code-review-graph"
    ) flake.devShells.${system}.wsl.nativeBuildInputs
  );
  fastmcp = builtins.head (
    builtins.filter (package: (package.pname or "") == "fastmcp") graph.propagatedBuildInputs
  );
in
pkgs.mkShell {
  packages = [
    graph
    fastmcp
  ];
}
