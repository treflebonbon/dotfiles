copy_codex_skills_retirement_inputs() {
  local source="$1"
  mkdir -p \
    "$source/.chezmoitemplates" \
    "$source/.chezmoidata" \
    "$source/private_dot_local/bin"
  cp -a "$PROJECT_ROOT/.chezmoitemplates/." "$source/.chezmoitemplates/"
  cp -a "$PROJECT_ROOT/.chezmoidata/." "$source/.chezmoidata/"
  cp "$PROJECT_ROOT/apm.lock.yaml" "$PROJECT_ROOT/apm.yml" "$source/"
  cp "$PROJECT_ROOT"/private_dot_local/bin/executable_{git-push-topic,git-push-reviewed,gh-review-thread,orca-send,codex-reviewer}.tmpl \
    "$source/private_dot_local/bin/"
}

create_codex_skills_verifier_source() {
  local source="$1" name
  mkdir -p "$source/bin" "$source/lib/python/treflebonbon_skills"
  for name in git-push-topic git-push-reviewed gh-review-thread orca-send codex-reviewer; do
    printf '#!/usr/bin/env bash\nexit 0\n' >"$source/bin/$name"
    chmod 755 "$source/bin/$name"
  done
  printf 'fixture module\n' >"$source/lib/python/treflebonbon_skills/devshell_environment.py"
  chmod 644 "$source/lib/python/treflebonbon_skills/devshell_environment.py"
}
