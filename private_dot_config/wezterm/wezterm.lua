-- WezTerm configuration
-- Theme: Dracula

local wezterm = require("wezterm")
local config = wezterm.config_builder()
local keybinds = require("keybinds")

-- =============================================================================
-- WSL ドメイン
-- =============================================================================
config.default_domain = "WSL:Ubuntu-24.04"

-- =============================================================================
-- Dracula カラースキーム
-- =============================================================================
config.color_scheme = "Dracula (Official)"

config.colors = {
  foreground = "#F8F8F2",
  background = "#282A36",
  cursor_bg = "#F8F8F2",
  cursor_fg = "#282A36",
  cursor_border = "#F8F8F2",
  selection_fg = "#F8F8F2",
  selection_bg = "#44475A",
  scrollbar_thumb = "#44475A",
  split = "#6272A4",
  ansi = {
    "#21222C", -- black
    "#FF5555", -- red
    "#50FA7B", -- green
    "#F1FA8C", -- yellow
    "#BD93F9", -- blue
    "#FF79C6", -- magenta
    "#8BE9FD", -- cyan
    "#F8F8F2", -- white
  },
  brights = {
    "#6272A4", -- bright black
    "#FF6E6E", -- bright red
    "#69FF94", -- bright green
    "#FFFFA5", -- bright yellow
    "#D6ACFF", -- bright blue
    "#FF92DF", -- bright magenta
    "#A4FFFF", -- bright cyan
    "#FFFFFF", -- bright white
  },
  tab_bar = {
    inactive_tab_edge = "none",
  },
}

-- =============================================================================
-- フォント設定
-- =============================================================================
config.font = wezterm.font_with_fallback({
  { family = "HackGen", weight = "Regular" },
  { family = "Hack Nerd Font" },
  { family = "Noto Sans CJK JP" },
})
config.font_size = 14.0
config.line_height = 1.2
config.use_ime = true

-- =============================================================================
-- ウィンドウ設定
-- =============================================================================
config.window_decorations = "RESIZE"
config.window_background_opacity = 0.85
config.win32_system_backdrop = "Acrylic"
config.window_padding = {
  left = 10,
  right = 10,
  top = 10,
  bottom = 10,
}
config.initial_cols = 120
config.initial_rows = 35

-- タイトルバー透過
config.window_frame = {
  inactive_titlebar_bg = "none",
  active_titlebar_bg = "none",
}
config.window_background_gradient = {
  colors = { "#000000" },
}

-- =============================================================================
-- タブバー設定
-- =============================================================================
config.enable_tab_bar = true
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = false
config.hide_tab_bar_if_only_one_tab = true
config.show_new_tab_button_in_tab_bar = false
config.tab_max_width = 32

-- =============================================================================
-- Fancy タブバー (Nerd Font 装飾 + Dracula カラー)
-- =============================================================================
local SOLID_LEFT_ARROW = wezterm.nerdfonts.ple_lower_right_triangle
local SOLID_RIGHT_ARROW = wezterm.nerdfonts.ple_upper_left_triangle

wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
  local background = "#6272A4" -- Dracula Comment (非アクティブ)
  local foreground = "#F8F8F2" -- Dracula Foreground
  local edge_background = "none"

  if tab.is_active then
    background = "#BD93F9" -- Dracula Purple (アクティブ)
    foreground = "#282A36" -- Dracula Background
  elseif hover then
    background = "#44475A" -- Dracula Current Line (ホバー)
  end

  local edge_foreground = background

  -- タブタイトル: 明示的に設定されていればそちらを優先、なければプロセス名
  local title = tab.tab_title
  if not title or #title == 0 then
    title = tab.active_pane.title
  end
  title = "  " .. wezterm.truncate_right(title, max_width - 4) .. "  "

  return {
    { Background = { Color = edge_background } },
    { Foreground = { Color = edge_foreground } },
    { Text = SOLID_LEFT_ARROW },
    { Background = { Color = background } },
    { Foreground = { Color = foreground } },
    { Text = title },
    { Background = { Color = edge_background } },
    { Foreground = { Color = edge_foreground } },
    { Text = SOLID_RIGHT_ARROW },
  }
end)

-- =============================================================================
-- ステータスバー (key_table 名表示)
-- =============================================================================
wezterm.on("update-right-status", function(window, pane)
  local name = window:active_key_table()
  if name then
    name = "TABLE: " .. name
  end
  window:set_right_status(name or "")
end)

-- =============================================================================
-- キーバインド
-- =============================================================================
config.disable_default_key_bindings = true
config.leader = { key = "q", mods = "CTRL", timeout_milliseconds = 2000 }
config.keys = keybinds.keys
config.key_tables = keybinds.key_tables

-- =============================================================================
-- マウスバインド
-- =============================================================================
config.mouse_bindings = {
  {
    event = { Up = { streak = 1, button = "Left" } },
    mods = "NONE",
    action = wezterm.action.CompleteSelectionOrOpenLinkAtMouseCursor("ClipboardAndPrimarySelection"),
  },
  {
    event = { Up = { streak = 1, button = "Right" } },
    mods = "NONE",
    action = wezterm.action.PasteFrom("Clipboard"),
  },
}

-- =============================================================================
-- その他設定
-- =============================================================================
config.scrollback_lines = 10000
config.enable_scroll_bar = false
config.default_cursor_style = "SteadyBar"
config.cursor_blink_rate = 500
config.audible_bell = "Disabled"
config.check_for_updates = true

return config
