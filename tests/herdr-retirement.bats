#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/nix-cache"
}

@test "user devShells no longer supply Herdr TUI on supported systems or shell variants" {
  cd "$PROJECT_ROOT" || return
  run --separate-stderr nix eval --json --impure --no-write-lock-file --expr '
    let
      flake = builtins.getFlake (toString ./private_dot_config/nix-devshell);
    in builtins.mapAttrs (_system: shells:
      builtins.mapAttrs (_name: shell:
        builtins.filter (package: (package.pname or null) == "herdr")
          shell.nativeBuildInputs
      ) shells
    ) flake.devShells
  '
  [ "$status" -eq 0 ]
  jq -e 'keys == ["aarch64-darwin", "aarch64-linux", "x86_64-linux"] and all(.[];
    .default == [] and .wsl == [])' <<<"$output"
}

@test "Herdr TUI registration, skill, command and permission are absent while the public plugin pin stays fixed" {
  local settings="$PROJECT_ROOT/private_dot_claude/settings.json.tmpl"
  local plugin_pin="$PROJECT_ROOT/private_dot_config/nix-devshell/skills-plugin.json"
  [ ! -e "$PROJECT_ROOT/.herdr/herdr-plugin.toml" ]
  [ ! -e "$PROJECT_ROOT/run_after_setup-herdr.sh" ]
  [ ! -e "$PROJECT_ROOT/private_dot_local/bin/executable_herdr-ask" ]
  ! grep -Fq 'herdrdev/herdr/skills/herdr' "$PROJECT_ROOT/apm.yml"
  ! grep -Fq 'Bash(herdr worktree remove:*)' "$settings"
  jq -e '.version == "0.2.10" and .rev == "fd2a50c558288b3661e5066b94b1196453ef9269"' "$plugin_pin"
}

@test "Herdr-free chezmoi apply preserves existing Herdr state in its deployment target" {
  local source="$BATS_TEST_TMPDIR/source" home="$BATS_TEST_TMPDIR/home"
  local chezmoi
  chezmoi="$(command -v chezmoi)"
  mkdir -p "$source" "$home/.herdr/worktrees/legacy"
  cp "$PROJECT_ROOT/.chezmoiignore" "$source/.chezmoiignore"
  printf 'managed fixture\n' >"$source/dot_fixture"
  printf 'preserved TUI history\n' >"$home/.herdr/history"
  printf 'preserved worktree marker\n' >"$home/.herdr/worktrees/legacy/marker"

  run env HOME="$home" PATH="$(dirname "$chezmoi"):/usr/bin:/bin" \
    "$chezmoi" --source "$source" --destination "$home" \
    --config /dev/null --config-format toml --cache "$BATS_TEST_TMPDIR/cache" \
    --persistent-state "$BATS_TEST_TMPDIR/chezmoi-state" apply

  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$(cat "$home/.herdr/history")" = 'preserved TUI history' ]
  [ "$(cat "$home/.herdr/worktrees/legacy/marker")" = 'preserved worktree marker' ]
  [ "$(cat "$home/.fixture")" = 'managed fixture' ]
}
