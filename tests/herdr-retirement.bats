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

@test "the pinned TUI baseline can be restored on the retired source candidate" {
  local source="$BATS_TEST_TMPDIR/recovery-source"
  local deploy_source="$BATS_TEST_TMPDIR/recovery-deploy-source"
  local retired_source="$BATS_TEST_TMPDIR/retired-deploy-source"
  local reactivated_source="$BATS_TEST_TMPDIR/reactivated-deploy-source"
  local baseline="34fa46fdd7a7cd8e30b910b2d5c0be5bebf30e63"
  local restore_patch="$BATS_TEST_TMPDIR/recovery.patch"
  local home="$BATS_TEST_TMPDIR/recovery-home"
  local bin="$BATS_TEST_TMPDIR/recovery-bin"
  local state="$BATS_TEST_TMPDIR/herdr-state.json"
  local link_log="$BATS_TEST_TMPDIR/herdr-link.log"
  local chezmoi

  mkdir -p "$source"
  (cd "$PROJECT_ROOT" && git archive HEAD) | tar -x -C "$source"
  (cd "$source" && git init -q -b main)

  # Restore only the tracked retirement delta that contains the Nix/APM entries
  # and Claude permission. Do not roll the rest of the candidate back to baseline.
  (
    cd "$PROJECT_ROOT" &&
      git diff --binary HEAD "$baseline" -- \
        private_dot_config/nix-devshell/modules/ai.nix \
        apm.yml apm.lock.yaml private_dot_claude/settings.json.tmpl
  ) >"$restore_patch"
  (cd "$source" && git apply "$restore_patch")
  mkdir -p "$source/.herdr"
  (cd "$PROJECT_ROOT" && git show "$baseline:.herdr/herdr-plugin.toml") >"$source/.herdr/herdr-plugin.toml"
  (cd "$PROJECT_ROOT" && git show "$baseline:run_after_setup-herdr.sh") >"$source/run_after_setup-herdr.sh"
  chmod +x "$source/run_after_setup-herdr.sh"

  [ -f "$source/run_after_setup-herdr.sh" ]
  [ -f "$source/.herdr/herdr-plugin.toml" ]
  cmp -s "$PROJECT_ROOT/.chezmoiignore" "$source/.chezmoiignore"
  grep -Fq 'llm.herdr' "$source/private_dot_config/nix-devshell/modules/ai.nix"
  [ "$(jq -r '.nodes["llm-agents"].locked.rev' "$source/private_dot_config/nix-devshell/flake.lock")" = \
    '2b6455a7711d6dc90e42e555c1ddb504481268f4' ]
  grep -Fq 'herdrdev/herdr/skills/herdr#2ecf19a92fc3a7fff75b6ce3655ef04f4625ec01' "$source/apm.yml"
  grep -Fq 'content_hash: sha256:72177e911f55467de8737174072ec6bb08e30bbf62bceabcb69678e944398b18' \
    "$source/apm.lock.yaml"
  grep -Fq 'resolved_commit: 2ecf19a92fc3a7fff75b6ce3655ef04f4625ec01' "$source/apm.lock.yaml"
  grep -Fq 'resolved_commit: a496f5513d4a4cf889bc48e189e579f4b0bdf6aa' "$source/apm.lock.yaml"
  grep -Fq 'mattpocock/skills#a496f5513d4a4cf889bc48e189e579f4b0bdf6aa' "$source/apm.yml"
  grep -Fq 'stablyai/orca/skills/computer-use#1bd67185489c66a9e0d841e0134727f171a33764' "$source/apm.yml"
  grep -Fq 'Bash(herdr worktree remove:*)' "$source/private_dot_claude/settings.json.tmpl"
  grep -Fq 'Bash(git worktree remove:*)' "$source/private_dot_claude/settings.json.tmpl"

  run nix eval --json --impure --no-write-lock-file --expr "
    let
      flake = builtins.getFlake (toString $source/private_dot_config/nix-devshell);
    in builtins.mapAttrs (_system: shells:
      builtins.mapAttrs (_name: shell:
        map (package: { inherit (package) pname version; })
          (builtins.filter (package: (package.pname or null) == \"herdr\") shell.nativeBuildInputs)
      ) shells
    ) flake.devShells
  "
  [ "$status" -eq 0 ]
  jq -e 'all(.[]; .default == [{"pname":"herdr","version":"0.9.5"}] and .wsl == [{"pname":"herdr","version":"0.9.5"}])' <<<"$output"

  mkdir -p "$home/.config/nix-devshell/lib" "$home/.herdr/worktrees/legacy" "$bin"
  mkdir -p "$deploy_source/.herdr"
  cp "$source/.chezmoiignore" "$deploy_source/.chezmoiignore"
  cp "$source/.herdr/herdr-plugin.toml" "$deploy_source/.herdr/herdr-plugin.toml"
  cp "$source/run_after_setup-herdr.sh" "$deploy_source/run_after_setup-herdr.sh"
  chmod +x "$deploy_source/run_after_setup-herdr.sh"
  (cd "$deploy_source" && git init -q -b main)
  mkdir -p "$retired_source" "$reactivated_source/.herdr"
  cp "$source/.chezmoiignore" "$retired_source/.chezmoiignore"
  printf 'retired candidate fixture\n' >"$retired_source/dot_fixture"
  (cd "$retired_source" && git init -q -b main)
  cp "$source/.chezmoiignore" "$reactivated_source/.chezmoiignore"
  cp "$source/.herdr/herdr-plugin.toml" "$reactivated_source/.herdr/herdr-plugin.toml"
  cp "$source/run_after_setup-herdr.sh" "$reactivated_source/run_after_setup-herdr.sh"
  chmod +x "$reactivated_source/run_after_setup-herdr.sh"
  (cd "$reactivated_source" && git init -q -b main)
  printf 'ensure_nix_devshell_env() { :; }\n' >"$home/.config/nix-devshell/lib/ensure-env.sh"
  printf 'retained history\n' >"$home/.herdr/history"
  cat >"$bin/herdr" <<'SH'
#!/usr/bin/env bash
set -eu
if [ "$2" = list ]; then
  cat "$HERDR_STATE"
else
  printf '%s\n' "$@" >>"$HERDR_LINK_LOG"
  enabled=true
  [ "${4:-}" != --disabled ] || enabled=false
  jq -n --arg root "$3" --argjson enabled "$enabled" \
    '{result:{plugins:[{plugin_id:"dotfiles.copy-env",plugin_root:$root,enabled:$enabled}]}}' >"$HERDR_STATE"
fi
SH
  chmod +x "$bin/herdr"
  printf '{"result":{"plugins":[]}}\n' >"$state"
  chezmoi="$(command -v chezmoi)"
  apply_source() {
    local fixture_source="$1"
    env -u CHEZMOI_SOURCE_DIR HOME="$home" PATH="$bin:$PATH" \
      HERDR_STATE="$state" HERDR_LINK_LOG="$link_log" \
      "$chezmoi" --source "$fixture_source" --destination "$home" \
      --config /dev/null --config-format toml --cache "$BATS_TEST_TMPDIR/recovery-cache" \
      --persistent-state "$BATS_TEST_TMPDIR/recovery-state" apply
  }

  run apply_source "$deploy_source"
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$(jq -r '.result.plugins[0].plugin_root' "$state")" = "$deploy_source/.herdr" ]
  [ "$(jq -r '.result.plugins[0].enabled' "$state")" = true ]
  [ "$(wc -l <"$link_log")" -eq 3 ]

  # Applying the retired candidate removes the source setup but leaves the old
  # registration and user data untouched until a restoration is requested.
  run apply_source "$retired_source"
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$(jq -r '.result.plugins[0].plugin_root' "$state")" = "$deploy_source/.herdr" ]
  [ "$(jq -r '.result.plugins[0].enabled' "$state")" = true ]
  [ "$(wc -l <"$link_log")" -eq 3 ]
  [ "$(cat "$home/.herdr/history")" = 'retained history' ]

  # A user disabled copy-env during retirement; restoring at a new source path
  # must move the registration without overriding that preference.
  jq '.result.plugins[0].enabled = false' "$state" >"$BATS_TEST_TMPDIR/disabled-state.json"
  mv "$BATS_TEST_TMPDIR/disabled-state.json" "$state"
  run apply_source "$reactivated_source"
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$(jq -r '.result.plugins[0].plugin_root' "$state")" = "$reactivated_source/.herdr" ]
  [ "$(sed -n '7p' "$link_log")" = --disabled ]
  [ "$(wc -l <"$link_log")" -eq 7 ]
  [ "$(jq -r '.result.plugins[0].enabled' "$state")" = false ]

  run apply_source "$reactivated_source"
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  [ "$(wc -l <"$link_log")" -eq 7 ]
  [ "$(jq -r '.result.plugins[0].enabled' "$state")" = false ]
}
