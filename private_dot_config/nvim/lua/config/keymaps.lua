-- Neovim キーマップ設定

local map = vim.keymap.set

-- 一般
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "ハイライト解除" })
map("n", "<leader>w", "<cmd>w<CR>", { desc = "保存" })
map("n", "<leader>q", "<cmd>q<CR>", { desc = "終了" })

-- ウィンドウ移動
map("n", "<C-h>", "<C-w>h", { desc = "左のウィンドウへ" })
map("n", "<C-j>", "<C-w>j", { desc = "下のウィンドウへ" })
map("n", "<C-k>", "<C-w>k", { desc = "上のウィンドウへ" })
map("n", "<C-l>", "<C-w>l", { desc = "右のウィンドウへ" })

-- ウィンドウリサイズ
map("n", "<C-Up>", "<cmd>resize +2<CR>", { desc = "ウィンドウを高く" })
map("n", "<C-Down>", "<cmd>resize -2<CR>", { desc = "ウィンドウを低く" })
map("n", "<C-Left>", "<cmd>vertical resize -2<CR>", { desc = "ウィンドウを狭く" })
map("n", "<C-Right>", "<cmd>vertical resize +2<CR>", { desc = "ウィンドウを広く" })

-- バッファ
map("n", "<S-h>", "<cmd>bprevious<CR>", { desc = "前のバッファ" })
map("n", "<S-l>", "<cmd>bnext<CR>", { desc = "次のバッファ" })
map("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "バッファを閉じる" })

-- 行移動
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "行を下へ移動" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "行を上へ移動" })

-- インデント維持
map("v", "<", "<gv", { desc = "インデント減" })
map("v", ">", ">gv", { desc = "インデント増" })

-- ファイルエクスプローラー
map("n", "<leader>e", "<cmd>Neotree toggle<CR>", { desc = "ファイルエクスプローラー" })

-- Telescope
map("n", "<leader>ff", "<cmd>Telescope find_files<CR>", { desc = "ファイル検索" })
map("n", "<leader>fg", "<cmd>Telescope live_grep<CR>", { desc = "テキスト検索" })
map("n", "<leader>fb", "<cmd>Telescope buffers<CR>", { desc = "バッファ一覧" })
map("n", "<leader>fh", "<cmd>Telescope help_tags<CR>", { desc = "ヘルプ検索" })
map("n", "<leader>fr", "<cmd>Telescope oldfiles<CR>", { desc = "最近のファイル" })

-- LSP
map("n", "gd", vim.lsp.buf.definition, { desc = "定義へジャンプ" })
map("n", "gr", vim.lsp.buf.references, { desc = "参照一覧" })
map("n", "K", vim.lsp.buf.hover, { desc = "ホバー情報" })
map("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "コードアクション" })
map("n", "<leader>rn", vim.lsp.buf.rename, { desc = "リネーム" })
map("n", "<leader>d", vim.diagnostic.open_float, { desc = "診断を表示" })
map("n", "[d", vim.diagnostic.goto_prev, { desc = "前の診断" })
map("n", "]d", vim.diagnostic.goto_next, { desc = "次の診断" })
