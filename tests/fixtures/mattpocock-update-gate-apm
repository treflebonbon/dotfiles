#!/usr/bin/env bash
set -euo pipefail

command_log=${MATTPOCOCK_GATE_COMMAND_LOG:-$HOME/apm-command.log}
mkdir -p -- "$(dirname -- "$command_log")"
printf 'apm %s\n' "$*" >>"$command_log"

[[ "$PWD" != "$MATTPOCOCK_GATE_SOURCE_DIR" ]] || exit 20
[[ "$HOME" != "$MATTPOCOCK_GATE_SOURCE_DIR" ]] || exit 21

if [[ " $* " == *" --update "* ]]; then
  if [[ -n "${MATT_GATE_MUTATE_NON_MATT:-}" ]]; then
    sed -i '0,/resolved_commit: /s//resolved_commit: 0000000000000000000000000000000000000000 #/' apm.lock.yaml
  fi
  while IFS= read -r skill; do
    mkdir -p "$PWD/.agents/skills/$skill" "$PWD/.claude/skills/$skill"
  done < <(
    awk '
      /^- repo_url: mattpocock\/skills$/ { active = 1; next }
      active && /^- repo_url:/ { exit }
      active && /^  - \.agents\/skills\/[^/]+$/ {
        sub(/^  - \.agents\/skills\//, "")
        print
      }
    ' apm.lock.yaml
  )
fi

if [[ " $* " == *" --frozen "* ]] && [[ -n "${MATT_GATE_MUTATE_FROZEN:-}" ]]; then
  printf '\n' >>apm.lock.yaml
fi
