#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/nix-cache"
  cd "$PROJECT_ROOT" || return
}

@test "both user devShells supply the pinned Impeccable engine to the launcher on every supported system" {
  run --separate-stderr nix eval --json --impure --no-write-lock-file --expr '
    let flake = builtins.getFlake (toString ./private_dot_config/nix-devshell);
    in builtins.mapAttrs (_system: shells:
      builtins.mapAttrs (_name: shell: {
        engine = shell.IMPECCABLE_BIN or null;
        packages = map (package: {
          inherit (package) version;
          path = toString package;
        }) (builtins.filter (package: (package.pname or null) == "impeccable")
          shell.nativeBuildInputs);
      }) shells
    ) flake.devShells
  '
  [ "$status" -eq 0 ]
  echo "$output"
  jq -e '
    keys == ["aarch64-darwin", "aarch64-linux", "x86_64-linux"] and
    all(.[];
      keys == ["default", "wsl"] and
      .default == .wsl and
      all(.[];
        (.packages | length) == 1 and
        .packages[0].version == "0.1.5" and
        .engine == (.packages[0].path + "/bin/impeccable")
      )
    )
  ' <<<"$output"
}
