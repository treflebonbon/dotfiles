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

vim.cmd("enew")
vim.cmd("setfiletype audit_unknown_language")
assert(not vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()])
vim.cmd("enew")
vim.cmd("setfiletype lua")
assert(vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], "新しい buffer のハイライトが有効ではありません")
vim.cmd("qa!")
