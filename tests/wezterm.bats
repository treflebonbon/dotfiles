#!/usr/bin/env bats

load 'test_helper'

readonly KEYBINDS="$BATS_TEST_DIRNAME/../private_dot_config/wezterm/keybinds.lua"

@test "WezTerm leader-g sends gcd and Enter to the current pane" {
  grep -q '{ key = "g", mods = "LEADER", action = act.SendString("gcd\\r") }' "$KEYBINDS"
}

@test "tmux prefix-g sends gcd and Enter to the current pane" {
  grep -q "bind g send-keys 'gcd' Enter" "$BATS_TEST_DIRNAME/../dot_tmux.conf"
}
