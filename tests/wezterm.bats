#!/usr/bin/env bats

load 'test_helper'

readonly KEYBINDS="$BATS_TEST_DIRNAME/../private_dot_config/wezterm/keybinds.lua"

@test "WezTerm leader-g runs gcd only in Bash" {
  grep -q 'local function is_bash(pane)' "$KEYBINDS"
  grep -q 'pane:get_foreground_process_name()' "$KEYBINDS"
  grep -q 'if is_bash(pane) then' "$KEYBINDS"
  grep -q 'act.Multiple({' "$KEYBINDS"
  grep -q 'act.SendKey({ key = "u", mods = "CTRL" })' "$KEYBINDS"
  grep -q 'act.SendString("gcd\\r")' "$KEYBINDS"
}

@test "tmux prefix-g runs gcd only in Bash" {
  grep -q "bind g if-shell -F '#{==:#{pane_current_command},bash}' 'send-keys C-u gcd Enter'" "$BATS_TEST_DIRNAME/../dot_tmux.conf"
}
