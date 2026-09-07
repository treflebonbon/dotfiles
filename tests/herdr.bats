#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/nix-cache"
  cd "$PROJECT_ROOT" || return
}

@test "user devShell provides Herdr 0.8.2 on all supported systems and shell variants" {
  run nix eval --json --impure --no-write-lock-file --expr '
    let
      flake = builtins.getFlake (toString ./private_dot_config/nix-devshell);
    in builtins.mapAttrs (_system: shells:
      builtins.mapAttrs (_name: shell:
        map (package: { inherit (package) version; path = toString package; })
          (builtins.filter (package: (package.pname or null) == "herdr")
            shell.nativeBuildInputs)
      ) shells
    ) flake.devShells
  '
  [ "$status" -eq 0 ]
  echo "$output"
  jq -e '
    keys == ["aarch64-darwin", "aarch64-linux", "x86_64-linux"] and
    all(.[];
      (.default | length) == 1 and
      .default == .wsl and
      .default[0].version == "0.8.2"
    )
  ' <<<"$output"
}
