#!/usr/bin/env bash
set -euo pipefail

command_log=${MATTPOCOCK_GATE_COMMAND_LOG:-$HOME/apm-command.log}
mkdir -p "$(dirname "$command_log")"
printf 'apm %s\n' "$*" >>"$command_log"

[[ "$PWD" != "$MATTPOCOCK_GATE_SOURCE_DIR" ]] || exit 20
[[ "$HOME" != "$MATTPOCOCK_GATE_SOURCE_DIR" ]] || exit 21

if [[ " $* " == *" --update "* ]]; then
  candidate_revision=$(sed -nE 's/^[[:space:]]*-[[:space:]]*mattpocock\/skills#([0-9a-f]{40})$/\1/p' apm.yml)
  [[ "$candidate_revision" =~ ^[0-9a-f]{40}$ ]] || exit 22
  awk -v candidate_revision="$candidate_revision" '
    /^- repo_url: mattpocock\/skills$/ { active = 1 }
    active && /^- repo_url:/ && $0 !~ /mattpocock\/skills$/ { active = 0 }
    active && /^  resolved_commit: / {
      print "  resolved_commit: " candidate_revision
      next
    }
    active && /^  resolved_ref: / {
      print "  resolved_ref: " candidate_revision
      next
    }
    { print }
  ' apm.lock.yaml >apm.lock.yaml.rewritten
  mv apm.lock.yaml.rewritten apm.lock.yaml

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
      /^- repo_url: / {
        non_matt = $0 !~ /mattpocock\/skills$/
      }
      non_matt && !replaced && /^  content_hash: / {
        print "  content_hash: sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        replaced = 1
        next
      }
      { print }
    ' apm.lock.yaml >apm.lock.yaml.rewritten
    mv apm.lock.yaml.rewritten apm.lock.yaml
  fi
  if [[ -n "${MATT_GATE_MUTATE_MATT_DEPLOYMENT:-}" ]]; then
    awk '
      /^deployments:$/ { deployments = 1 }
      deployments && !replaced && /^  active_owner: mattpocock\/skills$/ {
        matt_deployment = 1
      }
      matt_deployment && /^  content_hash: / {
        print "  content_hash: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        replaced = 1
        matt_deployment = 0
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
  for target in .agents/skills .claude/skills; do
    if [[ -n "${MATT_GATE_LEGACY_WORKFLOW:-}" ]]; then
      printf '%s\n' 'Run the grilling skill.' >>"$PWD/$target/grill-with-docs/SKILL.md"
      printf '%s\n' 'Call the Skill tool with "setup-matt-pocock-skills".' \
        >>"$PWD/$target/code-review/SKILL.md"
      continue
    fi

    printf '%s\n' 'Call the Skill tool twice, for "grilling" and "domain-modeling".' \
      >>"$PWD/$target/grill-with-docs/SKILL.md"
    printf '%s\n' 'Call the Skill tool with "grilling".' >>"$PWD/$target/grill-me/SKILL.md"
    printf '%s\n' '---' >>"$PWD/$target/grilling/SKILL.md"
    for skill in code-review to-spec to-tickets triage wayfinder; do
      printf '%s\n' 'If setup is missing, tell the user to run /setup-matt-pocock-skills.' \
        >>"$PWD/$target/$skill/SKILL.md"
    done
  done
  if [[ -n "${MATT_GATE_INVALID_FRONTMATTER:-}" ]]; then
    printf '%s\n' '---' 'name: ask-matt' '---' '# Body example' 'description: body-only' '---' \
      >"$PWD/.agents/skills/ask-matt/SKILL.md"
    printf '%s\n' '---' 'name: ask-matt' '---' '# Body example' 'description: body-only' '---' \
      >"$PWD/.claude/skills/ask-matt/SKILL.md"
  fi
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
