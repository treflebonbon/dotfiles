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

@test "Herdr TUI registration, skill, command and permission are absent from source" {
  local settings="$PROJECT_ROOT/private_dot_claude/settings.json.tmpl"
  [ ! -e "$PROJECT_ROOT/.herdr/herdr-plugin.toml" ]
  [ ! -e "$PROJECT_ROOT/run_after_setup-herdr.sh" ]
  [ ! -e "$PROJECT_ROOT/private_dot_local/bin/executable_herdr-ask" ]
  ! grep -Fq 'herdrdev/herdr/skills/herdr' "$PROJECT_ROOT/apm.yml"
  ! grep -Fq 'Bash(herdr worktree remove:*)' "$settings"
}

@test "Herdr TUI cutover requires explicit command retirement and preserves unrelated state" {
  local source="$BATS_TEST_TMPDIR/source" home="$BATS_TEST_TMPDIR/home"
  local baseline="34fa46fdd7a7cd8e30b910b2d5c0be5bebf30e63"
  local original="$BATS_TEST_TMPDIR/herdr-ask" backup="$BATS_TEST_TMPDIR/backup"
  local chezmoi
  chezmoi="$(command -v chezmoi)"
  mkdir -p "$source" "$home/.herdr/worktrees/legacy" "$home/.local/bin" "$backup"
  git -C "$PROJECT_ROOT" show "$baseline:private_dot_local/bin/executable_herdr-ask" >"$original"
  cp "$original" "$home/.local/bin/herdr-ask"
  chmod +x "$home/.local/bin/herdr-ask"
  printf 'unrelated command\n' >"$home/.local/bin/keep"
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
  cmp -s "$original" "$home/.local/bin/herdr-ask"

  # The documented, approved one-file move is separate from chezmoi apply.
  mv -- "$home/.local/bin/herdr-ask" "$backup/herdr-ask"
  [ ! -e "$home/.local/bin/herdr-ask" ]
  [ ! -L "$home/.local/bin/herdr-ask" ]
  cmp -s "$original" "$backup/herdr-ask"
  run env PATH="$home/.local/bin:/usr/bin:/bin" bash --noprofile --norc -c 'command -v herdr-ask'
  [ "$status" -eq 1 ]
  [ "$(cat "$home/.local/bin/keep")" = 'unrelated command' ]
  [ "$(cat "$home/.herdr/history")" = 'preserved TUI history' ]
  [ "$(cat "$home/.herdr/worktrees/legacy/marker")" = 'preserved worktree marker' ]
}

@test "the pinned TUI baseline can be restored on the retired source candidate" {
  local source="$BATS_TEST_TMPDIR/recovery-source"
  local deploy_source="$BATS_TEST_TMPDIR/recovery-deploy-source"
  local retired_source="$BATS_TEST_TMPDIR/retired-deploy-source"
  local reactivated_source="$BATS_TEST_TMPDIR/reactivated-deploy-source"
  local ai_source="private_dot_config/nix-devshell/modules/ai.nix"
  local baseline="34fa46fdd7a7cd8e30b910b2d5c0be5bebf30e63"
  local restore_patch="$PROJECT_ROOT/tests/fixtures/herdr/restore-tui.patch"
  local before="$BATS_TEST_TMPDIR/recovery-before"
  local home="$BATS_TEST_TMPDIR/recovery-home"
  local bin="$BATS_TEST_TMPDIR/recovery-bin"
  local state="$BATS_TEST_TMPDIR/herdr-state.json"
  local link_log="$BATS_TEST_TMPDIR/herdr-link.log"
  local chezmoi

  mkdir -p "$source"
  (cd "$PROJECT_ROOT" && git archive HEAD) | tar -x -C "$source"
  (cd "$source" && git init -q -b main)

  # Build the retired apply fixture from actual candidate source entries, not
  # a synthetic dotfile. The baseline copy below restores only the old TUI
  # integration needed to exercise its setup hook.
  mkdir -p "$retired_source"
  (cd "$PROJECT_ROOT" && git archive HEAD .chezmoiignore "$ai_source") | tar -x -C "$retired_source"
  (cd "$retired_source" && git init -q -b main)
  [ ! -e "$retired_source/run_after_setup-herdr.sh" ]
  [ ! -e "$retired_source/.herdr/herdr-plugin.toml" ]
  ! grep -Fq 'llm.herdr' "$retired_source/$ai_source"

  # A later unrelated skill update must survive the fixed TUI-only restoration.
  run bun --eval '
    import { readFileSync, writeFileSync } from "node:fs";
    const root = process.argv.at(-1);
    const manifest = readFileSync(`${root}/apm.yml`, "utf8");
    const revision = manifest.match(/mattpocock\/skills#([a-f0-9]{40})/)[1];
    for (const name of ["apm.yml", "apm.lock.yaml"]) {
      const file = `${root}/${name}`;
      writeFileSync(file, readFileSync(file, "utf8").replaceAll(revision, "1".repeat(40)));
    }
  ' "$source"
  [ "$status" -eq 0 ]
  mkdir -p "$before"
  (cd "$source" && tar -cf - apm.yml apm.lock.yaml "$ai_source" \
    private_dot_claude/settings.json.tmpl) | (cd "$before" && tar -xf -)

  # This fixture contains only the original TUI delta, never HEAD-to-baseline drift.
  (cd "$source" && git apply "$restore_patch")
  mkdir -p "$source/.herdr"
  (cd "$PROJECT_ROOT" && git show "$baseline:.herdr/herdr-plugin.toml") >"$source/.herdr/herdr-plugin.toml"
  (cd "$PROJECT_ROOT" && git show "$baseline:run_after_setup-herdr.sh") >"$source/run_after_setup-herdr.sh"
  chmod +x "$source/run_after_setup-herdr.sh"

  [ -f "$source/run_after_setup-herdr.sh" ]
  [ -f "$source/.herdr/herdr-plugin.toml" ]
  cmp -s "$PROJECT_ROOT/.chezmoiignore" "$source/.chezmoiignore"
  grep -Fq 'llm.herdr' "$source/private_dot_config/nix-devshell/modules/ai.nix"
  cmp -s "$PROJECT_ROOT/private_dot_config/nix-devshell/flake.lock" \
    "$source/private_dot_config/nix-devshell/flake.lock"
  grep -Fq 'herdrdev/herdr/skills/herdr#2ecf19a92fc3a7fff75b6ce3655ef04f4625ec01' "$source/apm.yml"
  grep -Fq 'content_hash: sha256:72177e911f55467de8737174072ec6bb08e30bbf62bceabcb69678e944398b18' \
    "$source/apm.lock.yaml"
  grep -Fq 'resolved_commit: 2ecf19a92fc3a7fff75b6ce3655ef04f4625ec01' "$source/apm.lock.yaml"
  grep -Fq 'Bash(herdr worktree remove:*)' "$source/private_dot_claude/settings.json.tmpl"
  grep -Fq 'Bash(git worktree remove:*)' "$source/private_dot_claude/settings.json.tmpl"

  run bun --eval '
    import assert from "node:assert/strict";
    import { readFileSync } from "node:fs";
    const [before, restored] = process.argv.slice(-2);
    const text = (root, name) => readFileSync(`${root}/${name}`, "utf8");
    const yaml = (root, name) => Bun.YAML.parse(text(root, name));
    const manifest = yaml(restored, "apm.yml");
    manifest.dependencies.apm = manifest.dependencies.apm.filter(entry => !entry.startsWith("herdrdev/herdr/skills/herdr#"));
    assert.deepStrictEqual(manifest, yaml(before, "apm.yml"));
    const lock = yaml(restored, "apm.lock.yaml");
    lock.dependencies = lock.dependencies.filter(entry => entry.repo_url !== "herdrdev/herdr");
    lock.deployments = lock.deployments.filter(entry => entry.active_owner !== "herdrdev/herdr/skills/herdr");
    assert.deepStrictEqual(lock, yaml(before, "apm.lock.yaml"));
    const nix = "private_dot_config/nix-devshell/modules/ai.nix";
    assert.equal(text(restored, nix).replace("    # --- Terminal Workspaces ---\n    llm.herdr\n\n", ""), text(before, nix));
    const settings = "private_dot_claude/settings.json.tmpl";
    assert.equal(text(restored, settings).replace("      \"Bash(herdr worktree remove:*)\",\n", ""), text(before, settings));
  ' "$before" "$source"
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3

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
  mkdir -p "$deploy_source/.herdr" "$deploy_source/private_dot_config/nix-devshell/modules"
  cp "$source/.chezmoiignore" "$deploy_source/.chezmoiignore"
  cp "$source/$ai_source" "$deploy_source/$ai_source"
  cp "$source/.herdr/herdr-plugin.toml" "$deploy_source/.herdr/herdr-plugin.toml"
  cp "$source/run_after_setup-herdr.sh" "$deploy_source/run_after_setup-herdr.sh"
  chmod +x "$deploy_source/run_after_setup-herdr.sh"
  grep -Fq 'llm.herdr' "$deploy_source/$ai_source"
  (cd "$deploy_source" && git init -q -b main)
  mkdir -p "$reactivated_source/.herdr"
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
  cmp -s "$deploy_source/$ai_source" "$home/.config/nix-devshell/modules/ai.nix"
  [ "$(jq -r '.result.plugins[0].plugin_root' "$state")" = "$deploy_source/.herdr" ]
  [ "$(jq -r '.result.plugins[0].enabled' "$state")" = true ]
  [ "$(wc -l <"$link_log")" -eq 3 ]

  # Applying the retired candidate removes the source setup but leaves the old
  # registration and user data untouched until a restoration is requested.
  run apply_source "$retired_source"
  [ "$status" -eq 0 ] || printf '%s\n' "$output" >&3
  cmp -s "$retired_source/$ai_source" "$home/.config/nix-devshell/modules/ai.nix"
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
