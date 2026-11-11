#!/usr/bin/env bats

@test "pinned skills package exposes the Domain Modeling Studio TypeScript consumer assets" {
  local skills_root="$(cd "${TREFLEBONBON_SKILLS_LIB:?run tests in the pinned skills-plugin devShell}/../.." && pwd)"
  local skill="$skills_root/skills/domain-modeling-studio"
  local file

  for file in \
    scripts/extract-typescript.ts \
    references/typescript-evidence.md \
    references/rop-semantics.md \
    references/effect-ts.md \
    references/rust.md; do
    [ -f "$skill/$file" ]
  done
  run bun run --config=/dev/null --no-env-file "$skill/scripts/extract-typescript.ts" --help
  [ "$status" -eq 0 ]
}
