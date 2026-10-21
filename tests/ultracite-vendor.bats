@test "vendored Ultracite presets load and are excluded from project lint/format" {
  cd "$BATS_TEST_DIRNAME/.."
  run bun -e '
    const [oxlint, oxfmt] = await Promise.all([
      import("./oxlint.config.ts"),
      import("./oxfmt.config.ts"),
    ]);
    const vendor = "scripts/vendor/ultracite/config/**";
    if (
      !oxlint.default.ignorePatterns.includes(vendor) ||
      !oxfmt.default.ignorePatterns.includes(vendor)
    ) {
      throw new Error("vendored presets must stay outside project lint/format");
    }
  '
  [ "$status" -eq 0 ]
}
