#!/usr/bin/env bats

load 'test_helper'

readonly KEYBINDS="$BATS_TEST_DIRNAME/../private_dot_config/wezterm/keybinds.lua"

@test "WezTerm leader-g clears the buffer before running gcd" {
  grep -q '{ key = "g", mods = "LEADER", action = act.Multiple' "$KEYBINDS"
  grep -q 'act.SendKey({ key = "u", mods = "CTRL" })' "$KEYBINDS"
  grep -q 'act.SendString("gcd\\r")' "$KEYBINDS"
}

@test "tmux prefix-g clears the buffer before running gcd" {
  grep -q "bind g send-keys C-u 'gcd' Enter" "$BATS_TEST_DIRNAME/../dot_tmux.conf"
}
