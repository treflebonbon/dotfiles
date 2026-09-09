#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SETTINGS="$PROJECT_ROOT/private_dot_claude/settings.json.tmpl"
}

@test "settings.json.tmpl is valid JSON" {
  run jq empty "$SETTINGS"
  [ "$status" -eq 0 ]
}

@test "blockReadsOutsideWorkingDirectories is disabled (ADR-0055)" {
  run jq -r '.permissions.blockReadsOutsideWorkingDirectories' "$SETTINGS"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "deny list protects the credential stores added by ADR-0055" {
  local pattern
  for pattern in \
    'Read(~/.kube/**)' \
    'Read(~/.docker/config.json)' \
    'Read(~/.git-credentials)' \
    'Read(~/.config/gh/hosts.yml)' \
    'Read(~/.gnupg/**)'; do
    run jq --arg p "$pattern" '.permissions.deny | index($p) != null' "$SETTINGS"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "npmrc is intentionally left out of the deny list (ADR-0055)" {
  run jq '.permissions.deny | any(test("npmrc"))' "$SETTINGS"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "existing credential deny patterns are unchanged" {
  local pattern
  for pattern in \
    'Read(~/.ssh/**)' \
    'Read(~/.aws/**)' \
    'Read(~/.config/gcloud/**)'; do
    run jq --arg p "$pattern" '.permissions.deny | index($p) != null' "$SETTINGS"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "additionalDirectories is unchanged" {
  run jq -c '.permissions.additionalDirectories' "$SETTINGS"
  [ "$status" -eq 0 ]
  [ "$output" = '["~/.claude/jobs","~/runtime","~/.claude/projects","/nix/store","~/ghq/github.com","~/.cache/nix-devshell-tmp"]' ]
}
