#!/usr/bin/env bats

@test "pinned skills package exposes the Domain Modeling Studio TypeScript consumer assets" {
  local skills_root="$(cd "${TREFLEBONBON_SKILLS_LIB:?run tests in the pinned skills-plugin devShell}/../.." && pwd)"
  local skill="$skills_root/skills/domain-modeling-studio"
  local file

  for file in \
    scripts/extract-typescript.py \
    references/typescript-evidence.md \
    references/rop-semantics.md \
    references/effect-ts.md \
    references/rust.md; do
    [ -f "$skill/$file" ]
  done
  run python3 "$skill/scripts/extract-typescript.py" --help
  [ "$status" -eq 0 ]
}
