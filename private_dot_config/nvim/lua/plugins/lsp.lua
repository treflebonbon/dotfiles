-- LSP 設定
-- 方針: flake devShell で LSP サーバーを一元管理し、neovim はそれを利用する
-- mason.nvim は補助ツール（DAP アダプタ等）のみに使用
return {
  -- LSP 設定（システムの LSP サーバーを使用）
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      -- 診断表示設定
      vim.diagnostic.config({
        virtual_text = { prefix = "●" },
        signs = true,
        underline = true,
        update_in_insert = false,
        severity_sort = true,
        float = {
          border = "rounded",
          source = "always",
        },
      })

      -- 診断アイコン
      local signs = { Error = " ", Warn = " ", Hint = "󰌵 ", Info = " " }
      for type, icon in pairs(signs) do
        local hl = "DiagnosticSign" .. type
        vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
      end

      -- LSP サーバー設定（Nvim 0.11+ 新 API）
      -- カスタム設定があるサーバーのみ vim.lsp.config で設定
      vim.lsp.config("gopls", {
        settings = {
          gopls = {
            analyses = {
              unusedparams = true,
              shadow = true,
            },
            staticcheck = true,
            gofumpt = true,
          },
        },
      })

      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            workspace = { checkThirdParty = false },
            telemetry = { enable = false },
            diagnostics = { globals = { "vim" } },
          },
        },
      })

      -- 全サーバーを有効化（lsp/*.lua のデフォルト設定とマージされる）
      vim.lsp.enable({
        "gopls",
        "ts_ls",
        "ty",
        "ruff",
        "lua_ls",
        "rust_analyzer",
        "expert",
        "gleam",
        "perlnavigator",
      })
    end,
  },

  -- Mason（補助ツール用: DAP アダプタ、追加 Linter 等）
  -- LSP サーバーは flake devShell で管理するため、ensure_installed は空
  {
    "williamboman/mason.nvim",
    cmd = "Mason",
    build = ":MasonUpdate",
    opts = {
      ui = {
        border = "rounded",
        icons = {
          package_installed = "✓",
          package_pending = "➜",
          package_uninstalled = "✗",
        },
      },
    },
  },

  -- Mason と lspconfig の連携（自動インストール無効）
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "mason.nvim" },
    opts = {
      -- LSP サーバーは flake devShell で管理するため自動インストールしない
      ensure_installed = {},
      automatic_installation = false,
    },
  },

  -- 補完
  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
      "rafamadriz/friendly-snippets",
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      require("luasnip.loaders.from_vscode").lazy_load()

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        window = {
          completion = cmp.config.window.bordered(),
          documentation = cmp.config.window.bordered(),
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "path" },
        }, {
          { name = "buffer" },
        }),
      })
    end,
  },

  -- Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    commit = "0195cd62fa89950f34c0e0d648ea7897ab85d4d3",
    lazy = false,
    build = ":TSUpdate",
    opts = {
      ensure_installed = {
        "bash",
        "elixir",
        "gleam",
        "go",
        "gomod",
        "gosum",
        "json",
        "lua",
        "markdown",
        "markdown_inline",
        "perl",
        "python",
        "rust",
        "toml",
        "typescript",
        "vim",
        "vimdoc",
        "yaml",
      },
    },
    config = function(_, opts)
      local treesitter = require("nvim-treesitter")
      treesitter.setup()
      local indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      local function expand_selection()
        -- 初回はカーソル上の最小要素を選び、選択中は親へ拡大する。
        vim.treesitter.select(vim.fn.mode() == "n" and "child" or "parent")
      end
      local function shrink_selection()
        vim.treesitter.select("child")
      end
      local function enable(buf)
        if not pcall(vim.treesitter.start, buf) then
          vim.treesitter.stop(buf)
          for _, mode in ipairs({ "n", "x" }) do
            for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
              if mapping.callback == expand_selection or mapping.callback == shrink_selection then
                vim.keymap.del(mode, mapping.lhs, { buffer = buf })
              end
            end
          end
          if vim.bo[buf].indentexpr == indentexpr then
            vim.bo[buf].indentexpr = ""
          end
          return
        end
        vim.bo[buf].indentexpr = indentexpr
        vim.keymap.set({ "n", "x" }, "<C-space>", expand_selection, { buffer = buf, desc = "構文要素の選択を拡大" })
        vim.keymap.set("x", "<bs>", shrink_selection, { buffer = buf, desc = "構文要素の選択を縮小" })
      end
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("Treesitter", { clear = true }),
        callback = function(event)
          enable(event.buf)
        end,
      })
      treesitter.install(opts.ensure_installed):await(function()
        vim.schedule(function()
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(buf) then
              enable(buf)
            end
          end
        end)
      end)
    end,
  },
}
