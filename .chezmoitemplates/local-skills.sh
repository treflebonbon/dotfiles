#!/usr/bin/env bash
# Embedded in the chezmoi skill phases; inputs are emitted by local-skills.sh.tmpl.
shared_skills_dir="$HOME/.agents/skills"
claude_skills_dir="$HOME/.claude/skills"

is_preserved_local_skill() {
  local name="$1" skill
  # shellcheck disable=SC2154
  for skill in "${local_skills[@]}"; do
    [ "$name" = "$skill" ] && return 0
  done
  return 1
}

deploy_skill() {
  local name="$1"
  # shellcheck disable=SC2154
  local src="$src_root/$name"

  if [ ! -d "$src" ]; then
    echo "ERROR: local skill source missing: $src" >&2
    exit 1
  fi

  local target
  for target in \
    "$shared_skills_dir/$name" \
    "$claude_skills_dir/$name"; do

    mkdir -p "$(dirname "$target")"
    local tmp
    tmp="$(mktemp -d "${target}.tmp.XXXXXX")"

    # -L: symlink を実ファイル化 / --delete: 撤去分を反映 / .gitkeep は除外
    if ! rsync -a -L --delete --exclude '.gitkeep' "$src/" "$tmp/"; then
      rm -rf "$tmp"
      echo "ERROR: rsync failed for $name -> $target" >&2
      exit 1
    fi

    local old="${target}.old.$$"
    if [ -e "$target" ] || [ -L "$target" ]; then
      mv "$target" "$old"
    fi
    if mv "$tmp" "$target"; then
      rm -rf "$old"
    else
      rm -rf "$tmp"
      if [ -e "$old" ] || [ -L "$old" ]; then
        if ! mv "$old" "$target"; then
          echo "ERROR: restore failed; previous skill preserved at $old" >&2
          exit 1
        fi
      fi
      echo "ERROR: could not place $target" >&2
      exit 1
    fi
  done
}

local_skills_deploy() {
  local skill
  for skill in "${local_skills[@]}"; do
    deploy_skill "$skill"
  done
}

remove_named_skill_entries() {
  local dir="$1"
  local label="$2"
  shift 2
  [ -d "$dir" ] || return 0

  local removed=0
  local skill
  for skill in "$@"; do
    local entry="$dir/$skill"
    if [ -e "$entry" ] || [ -L "$entry" ]; then
      rm -rf -- "$entry"
      removed=$((removed + 1))
    fi
  done

  if [ "$removed" -gt 0 ]; then
    printf "orphan-claude-skills: removed %d retired %s skill entries from %s\n" \
      "$removed" "$label" "$dir" >&2
  fi
}

local_skills_cleanup() {
  local dir
  for dir in "$shared_skills_dir" "$claude_skills_dir"; do
    # shellcheck disable=SC2154
    remove_named_skill_entries "$dir" "local" "${retired_local_skills[@]}"
  done
  for dir in "$HOME/.codex/skills" "${extra_codex_home:+$extra_codex_home/skills}"; do
    [ -n "$dir" ] || continue
    remove_named_skill_entries "$dir" "codex local duplicate" "${local_skills[@]}" "${retired_local_skills[@]}"
  done
}
