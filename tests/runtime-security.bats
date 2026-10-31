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

# 更新対象6件は upstream の出力を使い、APMは別テストで更新前の修正済み出力を照合する。
@test "llm-agents tools use unmodified upstream outputs on all supported systems" {
  run --separate-stderr nix eval --impure --json --no-write-lock-file --option warn-dirty false --expr '
    let
      flake = builtins.getFlake ((builtins.getEnv "PROJECT_ROOT") + "/private_dot_config/nix-devshell");
      names = [ "claude-code" "codex" "copilot-cli" "antigravity-cli" "herdr" "code-review-graph" ];
    in builtins.mapAttrs (system: shells:
      map (name:
        let
          selected = builtins.filter (p: (p.pname or "") == name) shells.wsl.nativeBuildInputs;
          package = builtins.head selected;
          upstream = flake.inputs.llm-agents.packages.${system}.${name};
        in assert builtins.length selected == 1;
           assert package.drvPath == upstream.drvPath;
           assert toString package == toString upstream;
           { inherit name; version = package.version; }
      ) names
    ) flake.devShells
  '
  [ "$status" -eq 0 ]
  jq -e 'length == 3 and all(.[]; length == 6)' <<<"$output"
}

@test "APM retains the pre-update outputs and patched Brotli closure" {
  run --separate-stderr nix eval --impure --json --no-write-lock-file --option warn-dirty false --expr '
    let
      flake = builtins.getFlake ((builtins.getEnv "PROJECT_ROOT") + "/private_dot_config/nix-devshell");
    in {
      host = builtins.currentSystem;
      systems = builtins.mapAttrs (_: shells:
        let
          matches = builtins.filter (p: (p.pname or "") == "apm") shells.wsl.nativeBuildInputs;
          package = builtins.head matches;
        in assert builtins.length matches == 1; {
          output = toString package;
          derivation = package.drvPath;
        }
      ) flake.devShells;
    }
  '
  [ "$status" -eq 0 ]
  # 更新開始点 9782063 の3環境の出力。APMの依存再計算も検出する。
  jq -e '.systems == {
    "x86_64-linux": {
      "output": "/nix/store/b57d3rsdby4w5pf67hs20y5ddp3kkach-apm-0.35.0",
      "derivation": "/nix/store/fb0sjxmrbi9ava7f6knglrwsqppq0z9j-apm-0.35.0.drv"
    },
    "aarch64-linux": {
      "output": "/nix/store/mqcnr5qzkkfv405yzf8zwx1h5lfzzl9b-apm-0.35.0",
      "derivation": "/nix/store/qby915a132smkb5cr2qbccfhhvsvhl1m-apm-0.35.0.drv"
    },
    "aarch64-darwin": {
      "output": "/nix/store/54n5hgrpwg7x44k3qja84mkw5n4273hz-apm-0.35.0",
      "derivation": "/nix/store/0c1d98q808vffbw581rb9i0x368nvpji-apm-0.35.0.drv"
    }
  }' <<<"$output"
  local package
  package="$(jq -r '.systems[.host].output' <<<"$output")"
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

@test "managed Node.js uses hash-pinned official release binaries on all systems" {
  run --separate-stderr nix eval --impure --json --no-write-lock-file --option warn-dirty false --expr '
    let
      root = builtins.getEnv "PROJECT_ROOT";
      repo = builtins.getFlake root;
      user = builtins.getFlake (root + "/private_dot_config/nix-devshell");
      releases = {
        x86_64-linux = { platform = "linux-x64"; hash = "sha256-bBcqmrZxj3uAH7WnvUhq8u5eMnWAhqBLhPzOKqdwleY="; };
        aarch64-linux = { platform = "linux-arm64"; hash = "sha256-26v3ocv5R+YFn/rSwnuABB25feoeVTtir97n8T/KM24="; };
        aarch64-darwin = { platform = "darwin-arm64"; hash = "sha256-ZUunneYVVkfiIyGTK0Xyocy3BZdswzfJuOJ4vrCFpig="; };
      };
      describe = flake: builtins.mapAttrs (system: shells:
        let
          node = builtins.head (builtins.filter
            (package: (package.pname or "") == "nodejs") shells.wsl.nativeBuildInputs);
          release = releases.${system};
          url = "https://nodejs.org/dist/v24.22.1/node-v24.22.1-${release.platform}.tar.xz";
        in assert node.src.urls == [ url ];
        assert node.src.outputHash == release.hash;
        node.version
      ) flake.devShells;
    in { repo = describe repo; user = describe user; }
  '
  [ "$status" -eq 0 ]
  jq -e '[.[] | .[]] | length == 6' <<<"$output"
}

@test "locally packaged CLI runtime closures use patched Node.js and Brotli" {
  run --separate-stderr nix build --no-link --print-out-paths --impure --no-write-lock-file --option warn-dirty false --expr '
    let
      root = builtins.getEnv "PROJECT_ROOT";
      repo = builtins.getFlake root;
      user = builtins.getFlake (root + "/private_dot_config/nix-devshell");
      # APM は専用テストで既存 output を照会し、この検査ではビルドしない。
      separatelyChecked = [ "claude-code" "codex" "copilot-cli" "antigravity-cli" "apm" "herdr" "code-review-graph" ];
      packages = flake: builtins.filter
        (package: !(builtins.elem (package.pname or "") separatelyChecked))
        flake.devShells.${builtins.currentSystem}.wsl.nativeBuildInputs;
    in packages repo ++ packages user
  '
  [ "$status" -eq 0 ]
  local -a packages
  mapfile -t packages <<<"$output"
  run nix-store --query --requisites "${packages[@]}"
  [ "$status" -eq 0 ]
  local path version found=0
  local -a nodes=()
  while IFS= read -r path; do
    if [[ "$path" =~ -nodejs(-slim)?-([0-9]+\.[0-9]+\.[0-9]+)(-|$) ]]; then
      version="${BASH_REMATCH[2]}"
      [[ "$version" == 24.* ]]
      [ "$(printf '%s\n' 24.22.1 "$version" | sort -V | head -n 1)" = 24.22.1 ]
      nodes+=("$path")
      found=1
    fi
  done <<<"$output"
  [ "$found" -eq 1 ]

  run nix-store --query --requisites "${nodes[@]}"
  [ "$status" -eq 0 ]
  # 公式 binary の同梱 Brotli は修正を backport 済み。共有 library がある場合は別に検査する。
  while IFS= read -r path; do
    if [[ "$path" =~ -brotli-([0-9]+\.[0-9]+\.[0-9]+)(-|$) ]]; then
      version="${BASH_REMATCH[1]}"
      [ "$(printf '%s\n' 1.2.1 "$version" | sort -V | head -n 1)" = 1.2.1 ]
    fi
  done <<<"$output"
}
