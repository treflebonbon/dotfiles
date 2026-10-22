#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "runtime index alone states how to resolve ../ links from the chezmoi source, with an existing example" {
  local index="$PROJECT_ROOT/runtime/index.md" example
  grep -Fq '`../` で始まるリンクは' "$index"
  grep -Fq '`chezmoi source-path`' "$index"
  # ../ resolves from the source's runtime/ directory, not from the source root.
  grep -Fq '`runtime/` を起点' "$index"
  [ "$(grep -lF '`../` で始まるリンクは' "$PROJECT_ROOT"/runtime/*.md)" = "$index" ]

  example="$(grep -o -m1 -E '`\$\(chezmoi source-path\)/[^`]+`' "$index" | sed -E 's/^`\$\(chezmoi source-path\)\///; s/`$//')"
  [ -n "$example" ]
  [ -e "$PROJECT_ROOT/$example" ]
}
