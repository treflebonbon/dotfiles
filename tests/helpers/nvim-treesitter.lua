if vim.env.NVIM_TREESITTER_RUNTIME then
  vim.opt.runtimepath:prepend(vim.env.NVIM_TREESITTER_RUNTIME)
else
  -- 外部 plugin の公開 API だけを代用し、parser と選択は実 Neovim で検証する。
  package.preload["nvim-treesitter"] = function()
    return {
      setup = function() end,
      install = function()
        return {
          await = function(_, callback)
            callback(nil, true)
          end,
        }
      end,
      indentexpr = function()
        return -1
      end,
    }
  end
end

local plugins = dofile(vim.env.NVIM_CONFIG_SOURCE .. "/lua/plugins/lsp.lua")
local spec
for _, plugin in ipairs(plugins) do
  if plugin[1] == "nvim-treesitter/nvim-treesitter" then
    spec = plugin
    break
  end
end
assert(spec and spec.lazy == false, "Treesitter は起動時に読み込む必要があります")
if vim.env.NVIM_TREESITTER_RUNTIME then
  local revision = vim.system({ "git", "rev-parse", "HEAD" }, {
    cwd = vim.env.NVIM_TREESITTER_RUNTIME,
    text = true,
  }):wait()
  assert(revision.code == 0 and vim.trim(revision.stdout) == spec.commit, "実 plugin が固定 commit と一致しません")
  local available = require("nvim-treesitter").get_available()
  for _, language in ipairs(spec.opts.ensure_installed) do
    assert(vim.list_contains(available, language), "固定版に parser がありません: " .. language)
  end
end
spec.opts.ensure_installed = {} -- ネットワークを使わず、同梱済み Lua parser を使う。
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local value = 1 + 2" })
vim.cmd("setfiletype lua")
spec.config(nil, spec.opts)
assert(vim.wait(10000, function()
  return vim.fn.maparg("<C-Space>", "n", false, true).callback ~= nil
end), "非同期導入後に既存 buffer の選択キーが有効になりません")
assert(vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], "ハイライトが有効ではありません")
assert(vim.bo.indentexpr == "v:lua.require'nvim-treesitter'.indentexpr()")
vim.api.nvim_win_set_cursor(0, { 1, 14 })
local function press(key)
  vim.api.nvim_feedkeys(vim.keycode(key), "xt", false)
  return table.concat(vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = "v" }), "\n")
end
local first = press("<C-Space>")
assert(first == "1", "最初の構文要素を選択できません: " .. vim.inspect(first))
assert(press("<C-Space>") == "1 + 2", "親の構文要素へ拡大できません")
assert(press("<BS>") == "1", "子の構文要素へ縮小できません")
vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "xt", false)

local original = vim.api.nvim_get_current_buf()
vim.cmd("enew")
vim.cmd("setfiletype audit_unknown_language")
assert(not vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()])
vim.cmd("enew")
vim.cmd("setfiletype lua")
local other = vim.api.nvim_get_current_buf()
assert(vim.treesitter.highlighter.active[other], "新しい buffer のハイライトが有効ではありません")
vim.api.nvim_set_current_buf(original)
-- 他の FileType handler による停止に頼らず、この設定自身の解除を検証する。
vim.cmd("noautocmd setlocal filetype=audit_unknown_language")
assert(vim.treesitter.highlighter.active[original])
vim.api.nvim_exec_autocmds("FileType", { group = "Treesitter", buffer = original })
assert(not vim.treesitter.highlighter.active[original], "filetype 変更後に古いハイライトが残っています")
assert(vim.bo.indentexpr == "", "filetype 変更後に古いインデント設定が残っています")
assert(vim.fn.maparg("<C-Space>", "n") == "", "通常モードの選択キーが残っています")
assert(vim.fn.maparg("<C-Space>", "x") == "", "選択拡大キーが残っています")
assert(vim.fn.maparg("<BS>", "x") == "", "選択縮小キーが残っています")
assert(vim.treesitter.highlighter.active[other], "別 buffer のハイライトが解除されました")

vim.bo.filetype = "lua"
assert(vim.treesitter.highlighter.active[original], "対応 filetype に戻しても有効になりません")
local user_mapping = function() end
vim.keymap.set("n", "<C-Space>", user_mapping, { buffer = original })
vim.bo.filetype = "audit_unknown_language"
assert(not vim.treesitter.highlighter.active[original])
assert(vim.fn.maparg("<C-Space>", "n", false, true).callback == user_mapping, "利用者の mapping が削除されました")
assert(vim.fn.maparg("<C-Space>", "x") == "")
assert(vim.fn.maparg("<BS>", "x") == "")
vim.bo.indentexpr = "0"
vim.api.nvim_exec_autocmds("FileType", { group = "Treesitter", buffer = original })
assert(vim.bo.indentexpr == "0", "利用者のインデント設定が削除されました")
vim.cmd("qa!")
