{
  description = "Elixir/Erlang project devShell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # OTP 29 first lands in nixpkgs >= 26.05; pin stable to source the BEAM toolchain.
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";

    expert.url = "github:elixir-lang/expert";
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-stable,
      expert,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          stablePkgs = import nixpkgs-stable { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = [
              stablePkgs.beam29Packages.elixir_1_20
              stablePkgs.beam29Packages.erlang
              expert.packages.${system}.default
            ];
          };
        }
      );

      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixfmt);
    };
}
