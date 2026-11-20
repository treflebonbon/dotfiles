#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "global gitignore excludes per-directory .sprite files" {
  local repo="$BATS_TEST_TMPDIR/repo"
  git init -q "$repo"
  git -C "$repo" config core.excludesFile "$PROJECT_ROOT/dot_gitignore_global"
  mkdir "$repo/subdir"
  touch "$repo/.sprite" "$repo/subdir/.sprite" "$repo/subdir/sprite"

  run git -C "$repo" check-ignore .sprite subdir/.sprite subdir/sprite
  [ "$status" -eq 0 ]
  [ "$output" = $'.sprite\nsubdir/.sprite' ]
}

@test "both user devShell outputs select the pinned Sprites CLI for each supported system" {
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/nix-cache"
  local flake="path:$PROJECT_ROOT/private_dot_config/nix-devshell"
  local select_sprite='shells: builtins.mapAttrs (_: outputs:
    builtins.mapAttrs (_: shell:
      map (sprite: { inherit (sprite) version; inherit (sprite.src) urls outputHash; })
        (builtins.filter (p: (p.pname or "") == "sprite") shell.nativeBuildInputs)
    ) { inherit (outputs) default wsl; }
  ) shells'

  run nix eval --json --no-write-lock-file --option use-xdg-base-directories true \
    "$flake#devShells" --apply "$select_sprite"
  [ "$status" -eq 0 ]
  jq -e '
    def pinned($asset; $hash):
      {version: "0.0.1-rc48", outputHash: $hash,
       urls: ["https://sprites-binaries.t3.storage.dev/client/v0.0.1-rc48/sprite-\($asset).tar.gz"]} as $sprite
      | . == {default: [$sprite], wsl: [$sprite]};
    (."x86_64-linux" | pinned("linux-amd64"; "sha256-UlgRQoNfiFTSIgaj67qcNriXEcorM0XPJC1Doy3HnP4="))
    and (."aarch64-linux" | pinned("linux-arm64"; "sha256-taj5QskS1bRgv0QFh9nu/IXUvzJCXGxiDP6lYPaL5tU="))
    and (."aarch64-darwin" | pinned("darwin-arm64"; "sha256-HoYKvupDS4Lak5ce07yZ8VkgafzxlSI0YNb6pg+xRTg="))
  ' <<<"$output"
}
