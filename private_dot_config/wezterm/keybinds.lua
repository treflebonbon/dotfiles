-- WezTerm keybindings
-- Leader key: Ctrl+Q (tmux-like)

local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

M.keys = {
  -- ghq + fzf: 未送信の入力を破棄してから picker を開く。
  { key = "g", mods = "LEADER", action = act.Multiple({ act.SendKey({ key = "u", mods = "CTRL" }), act.SendString("gcd\r") }) },

  -- ===========================================================================
  -- タブ操作
  -- ===========================================================================
  { key = "t", mods = "CTRL|SHIFT", action = act.SpawnTab("CurrentPaneDomain") },
  { key = "w", mods = "CTRL|SHIFT", action = act.CloseCurrentTab({ confirm = true }) },
  { key = "Tab", mods = "CTRL", action = act.ActivateTabRelative(1) },
  { key = "Tab", mods = "SHIFT|CTRL", action = act.ActivateTabRelative(-1) },

  -- ===========================================================================
  -- ペイン分割
  -- ===========================================================================
  { key = "r", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
  { key = "d", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
  { key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },
  { key = "z", mods = "LEADER", action = act.TogglePaneZoomState },

  -- ===========================================================================
  -- ペイン移動 (Vim 風)
  -- ===========================================================================
  { key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
  { key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
  { key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
  { key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },

  -- ===========================================================================
  -- ペインリサイズ (key_table)
  -- ===========================================================================
  {
    key = "s",
    mods = "LEADER",
    action = act.ActivateKeyTable({
      name = "resize_pane",
      one_shot = false,
    }),
  },

  -- ===========================================================================
  -- ワークスペース
  -- ===========================================================================
  { key = "w", mods = "LEADER", action = act.ShowLauncherArgs({ flags = "WORKSPACES" }) },
  {
    key = "$",
    mods = "LEADER",
    action = act.PromptInputLine({
      description = "Rename workspace:",
      action = wezterm.action_callback(function(window, pane, line)
        if line then
          wezterm.mux.rename_workspace(wezterm.mux.get_active_workspace(), line)
        end
      end),
    }),
  },
  {
    key = "W",
    mods = "LEADER",
    action = act.PromptInputLine({
      description = "New workspace name:",
      action = wezterm.action_callback(function(window, pane, line)
        if line then
          window:perform_action(
            act.SwitchToWorkspace({
              name = line,
            }),
            pane
          )
        end
      end),
    }),
  },

  -- ===========================================================================
  -- コピーモード
  -- ===========================================================================
  { key = "[", mods = "LEADER", action = act.ActivateCopyMode },

  -- ===========================================================================
  -- クリップボード
  -- ===========================================================================
  { key = "c", mods = "CTRL|SHIFT", action = act.CopyTo("Clipboard") },
  { key = "v", mods = "CTRL|SHIFT", action = act.PasteFrom("Clipboard") },

  -- ===========================================================================
  -- フォントサイズ
  -- ===========================================================================
  { key = "+", mods = "CTRL", action = act.IncreaseFontSize },
  { key = "-", mods = "CTRL", action = act.DecreaseFontSize },
  { key = "0", mods = "CTRL", action = act.ResetFontSize },

  -- ===========================================================================
  -- その他
  -- ===========================================================================
  { key = "p", mods = "CTRL|SHIFT", action = act.ActivateCommandPalette },
  { key = "F11", mods = "NONE", action = act.ToggleFullScreen },
}

-- タブ番号切り替え (Ctrl+1〜9)
for i = 1, 9 do
  table.insert(M.keys, {
    key = tostring(i),
    mods = "CTRL",
    action = act.ActivateTab(i - 1),
  })
end

M.key_tables = {
  -- ===========================================================================
  -- ペインリサイズモード
  -- ===========================================================================
  resize_pane = {
    { key = "h", action = act.AdjustPaneSize({ "Left", 1 }) },
    { key = "j", action = act.AdjustPaneSize({ "Down", 1 }) },
    { key = "k", action = act.AdjustPaneSize({ "Up", 1 }) },
    { key = "l", action = act.AdjustPaneSize({ "Right", 1 }) },
    { key = "Enter", action = "PopKeyTable" },
    { key = "Escape", action = "PopKeyTable" },
  },

  -- ===========================================================================
  -- コピーモード (Vim 風)
  -- ===========================================================================
  copy_mode = {
    -- 移動
    { key = "h", mods = "NONE", action = act.CopyMode("MoveLeft") },
    { key = "j", mods = "NONE", action = act.CopyMode("MoveDown") },
    { key = "k", mods = "NONE", action = act.CopyMode("MoveUp") },
    { key = "l", mods = "NONE", action = act.CopyMode("MoveRight") },

    -- 行頭・行末
    { key = "^", mods = "NONE", action = act.CopyMode("MoveToStartOfLineContent") },
    { key = "$", mods = "NONE", action = act.CopyMode("MoveToEndOfLineContent") },
    { key = "0", mods = "NONE", action = act.CopyMode("MoveToStartOfLine") },

    -- 単語移動
    { key = "w", mods = "NONE", action = act.CopyMode("MoveForwardWord") },
    { key = "b", mods = "NONE", action = act.CopyMode("MoveBackwardWord") },
    { key = "e", mods = "NONE", action = act.CopyMode("MoveForwardWordEnd") },

    -- ジャンプ
    { key = "f", mods = "NONE", action = act.CopyMode({ JumpForward = { prev_char = false } }) },
    { key = "F", mods = "NONE", action = act.CopyMode({ JumpBackward = { prev_char = false } }) },
    { key = "t", mods = "NONE", action = act.CopyMode({ JumpForward = { prev_char = true } }) },
    { key = "T", mods = "NONE", action = act.CopyMode({ JumpBackward = { prev_char = true } }) },

    -- スクロール
    { key = "b", mods = "CTRL", action = act.CopyMode("PageUp") },
    { key = "f", mods = "CTRL", action = act.CopyMode("PageDown") },
    { key = "u", mods = "CTRL", action = act.CopyMode({ MoveByPage = -0.5 }) },
    { key = "d", mods = "CTRL", action = act.CopyMode({ MoveByPage = 0.5 }) },

    -- ファイル先頭・末尾
    { key = "g", mods = "NONE", action = act.CopyMode("MoveToScrollbackTop") },
    { key = "G", mods = "NONE", action = act.CopyMode("MoveToScrollbackBottom") },

    -- 選択モード
    { key = "v", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Cell" }) },
    { key = "V", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Line" }) },

    -- コピー・終了
    { key = "y", mods = "NONE", action = act.Multiple({ { CopyTo = "ClipboardAndPrimarySelection" }, { CopyMode = "Close" } }) },
    {
      key = "Enter",
      mods = "NONE",
      action = act.Multiple({ { CopyTo = "ClipboardAndPrimarySelection" }, { CopyMode = "Close" } }),
    },
    { key = "Escape", mods = "NONE", action = act.CopyMode("Close") },
    { key = "q", mods = "NONE", action = act.CopyMode("Close") },
  },
}

return M
