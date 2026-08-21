#!/usr/bin/env bash
set -euo pipefail

command_log=${MATTPOCOCK_GATE_COMMAND_LOG:-$HOME/apm-command.log}
mkdir -p -- "$(dirname -- "$command_log")"
printf 'apm %s\n' "$*" >>"$command_log"

[[ "$PWD" != "$MATTPOCOCK_GATE_SOURCE_DIR" ]] || exit 20
[[ "$HOME" != "$MATTPOCOCK_GATE_SOURCE_DIR" ]] || exit 21

if [[ " $* " == *" --update "* ]]; then
  if [[ -n "${MATT_GATE_ALIAS_SKILL:-}" ]]; then
    awk '
      /^- repo_url: mattpocock\/skills$/ { active = 1 }
      active && /^- repo_url:/ && $0 !~ /mattpocock\/skills$/ { active = 0 }
      active && /^  - \.agents\/skills\/ask-matt$/ {
        print "  - .agents/skills/not-ask-matt"
        next
      }
      active && /^  - \.claude\/skills\/ask-matt$/ {
        print "  - .claude/skills/not-ask-matt"
        next
      }
      {
        print
      }
    ' apm.lock.yaml >apm.lock.yaml.rewritten
    mv apm.lock.yaml.rewritten apm.lock.yaml
  fi
  if [[ -n "${MATT_GATE_MUTATE_NON_MATT:-}" ]]; then
    awk '
      !replaced && /^  resolved_commit: / {
        print "  resolved_commit: 0000000000000000000000000000000000000000 #"
        replaced = 1
        next
      }
      { print }
    ' apm.lock.yaml >apm.lock.yaml.rewritten
    mv apm.lock.yaml.rewritten apm.lock.yaml
  fi
  while IFS= read -r skill; do
    mkdir -p "$PWD/.agents/skills/$skill" "$PWD/.claude/skills/$skill"
    printf '%s\n' '---' "name: $skill" 'description: fake skill payload' '---' \
      >"$PWD/.agents/skills/$skill/SKILL.md"
    printf '%s\n' '---' "name: $skill" 'description: fake skill payload' '---' \
      >"$PWD/.claude/skills/$skill/SKILL.md"
  done < <(
    awk '
      /^  - \.agents\/skills\/[^/]+$/ {
        sub(/^  - \.agents\/skills\//, "")
        print
      }
    ' apm.lock.yaml | sort -u
  )
  if [[ -n "${MATT_GATE_ADD_EXTRA:-}" ]]; then
    mkdir -p "$PWD/.agents/skills/unexpected-extra" "$PWD/.claude/skills/unexpected-extra"
    printf '%s\n' '---' 'name: unexpected-extra' 'description: fake extra payload' '---' \
      >"$PWD/.agents/skills/unexpected-extra/SKILL.md"
    printf '%s\n' '---' 'name: unexpected-extra' 'description: fake extra payload' '---' \
      >"$PWD/.claude/skills/unexpected-extra/SKILL.md"
  fi
fi

if [[ " $* " == *" --frozen "* ]] && [[ -n "${MATT_GATE_MUTATE_FROZEN:-}" ]]; then
  printf '\n' >>apm.lock.yaml
fi
