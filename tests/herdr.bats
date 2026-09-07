#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/nix-cache"
  cd "$PROJECT_ROOT" || return
}

@test "user devShell provides pinned llm-agents Herdr on all supported systems and shell variants" {
  # shellcheck disable=SC2016 # Nix expands ${system}.
  run nix eval --json --impure --no-write-lock-file --expr '
    let
      flake = builtins.getFlake (toString ./private_dot_config/nix-devshell);
    in builtins.mapAttrs (system: shells:
      let package = flake.inputs.llm-agents.packages.${system}.herdr;
      in {
        expected = { inherit (package) version; path = toString package; };
        shells = builtins.mapAttrs (_name: shell:
          map (package: { inherit (package) version; path = toString package; })
            (builtins.filter (package: (package.pname or null) == "herdr")
              shell.nativeBuildInputs)
        ) shells;
      }
    ) flake.devShells
  '
  [ "$status" -eq 0 ]
  echo "$output"
  jq -e '
    keys == ["aarch64-darwin", "aarch64-linux", "x86_64-linux"] and
    all(.[];
      .expected.version == "0.8.2" and
      .shells.default == [.expected] and
      .shells.wsl == [.expected]
    )
  ' <<<"$output"
}
