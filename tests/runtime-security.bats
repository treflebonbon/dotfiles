#!/usr/bin/env bats
# shellcheck disable=SC2016

setup() {
  bats_require_minimum_version 1.5.0
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export PROJECT_ROOT
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/nix-cache"
}

@test "standalone Bun template selects the patched Bun runtime" {
  run --separate-stderr nix eval --impure --json --no-write-lock-file --option warn-dirty false --expr '
    let
      template = builtins.getFlake ((builtins.getEnv "PROJECT_ROOT") + "/templates/bun");
      lib = template.inputs.nixpkgs.lib;
    in builtins.mapAttrs (_: shells:
      let
        bun = builtins.head (builtins.filter
          (package: (package.pname or "") == "bun") shells.default.nativeBuildInputs);
      in assert lib.assertMsg (lib.versionAtLeast bun.version "1.4.4")
        "Bun template selects ${bun.version}";
      bun.version
    ) template.devShells
  '
  [ "$status" -eq 0 ]
  jq -e 'length == 3' <<<"$output"
}

@test "repo and user devShells select runtimes with the Brotli security fixes" {
  run --separate-stderr nix eval --impure --json --no-write-lock-file --option warn-dirty false --expr '
    let
      root = builtins.getEnv "PROJECT_ROOT";
      repo = builtins.getFlake root;
      user = builtins.getFlake (root + "/private_dot_config/nix-devshell");
      lib = repo.inputs.nixpkgs.lib;
      describe = package:
        let
          minimum = if package.pname == "nodejs" then "24.22.1" else "1.4.4";
        in
        assert package.pname != "nodejs" || lib.versions.major package.version == "24";
        assert lib.assertMsg (lib.versionAtLeast package.version minimum)
          "${package.pname} ${package.version} is below ${minimum}";
        { inherit (package) pname version; };
      runtimes = flake: builtins.mapAttrs (_: shells:
        map describe (builtins.filter
          (package: builtins.elem (package.pname or "") [ "nodejs" "bun" ])
          shells.wsl.nativeBuildInputs)
      ) flake.devShells;
    in { repo = runtimes repo; user = runtimes user; }
  '
  [ "$status" -eq 0 ]
  jq -e '[.[] | .[] | .[]] | length == 12' <<<"$output"
}

@test "APM runtime closure uses the patched Brotli library" {
  run --separate-stderr nix eval --impure --raw --no-write-lock-file --option warn-dirty false --expr '
    let
      flake = builtins.getFlake ((builtins.getEnv "PROJECT_ROOT") + "/private_dot_config/nix-devshell");
      packages = flake.devShells.${builtins.currentSystem}.wsl.nativeBuildInputs;
    in (builtins.head (builtins.filter
      (package: (package.pname or "") == "apm") packages)).outPath
  '
  [ "$status" -eq 0 ]
  local package="$output"
  run nix-store --query --requisites "$package"
  [ "$status" -eq 0 ]
  local path version found=0
  while IFS= read -r path; do
    if [[ "$path" =~ -brotli-([0-9]+\.[0-9]+\.[0-9]+)(-|$) ]]; then
      version="${BASH_REMATCH[1]}"
      [ "$(printf '%s\n' 1.2.1 "$version" | sort -V | head -n 1)" = 1.2.1 ]
      found=1
    fi
  done <<<"$output"
  [ "$found" -eq 1 ]
}

@test "managed CLI runtime closures exclude unpatched Node.js" {
  run --separate-stderr nix eval --impure --json --no-write-lock-file --option warn-dirty false --expr '
    let
      root = builtins.getEnv "PROJECT_ROOT";
      repo = builtins.getFlake root;
      user = builtins.getFlake (root + "/private_dot_config/nix-devshell");
      packages = flake: flake.devShells.${builtins.currentSystem}.wsl.nativeBuildInputs;
    in map toString (packages repo ++ packages user)
  '
  [ "$status" -eq 0 ]
  local -a packages
  mapfile -t packages < <(jq -r '.[]' <<<"$output")
  run nix-store --query --requisites "${packages[@]}"
  [ "$status" -eq 0 ]
  local path version found=0
  while IFS= read -r path; do
    if [[ "$path" =~ -nodejs(-slim)?-([0-9]+\.[0-9]+\.[0-9]+)(-|$) ]]; then
      version="${BASH_REMATCH[2]}"
      [[ "$version" == 24.* ]]
      [ "$(printf '%s\n' 24.22.1 "$version" | sort -V | head -n 1)" = 24.22.1 ]
      found=1
    fi
  done <<<"$output"
  [ "$found" -eq 1 ]
}
