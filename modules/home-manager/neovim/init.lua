vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

vim.o.hlsearch = true
vim.o.mouse = 'a'

vim.o.clipboard = 'unnamedplus'

vim.o.undofile = true

vim.wo.signcolumn = 'yes'

vim.o.updatetime = 250
vim.o.timeoutlen = 300

vim.o.completeopt = 'menuone,noselect'

vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })

vim.keymap.set("v", "p", '"_dP')

vim.keymap.set({ 'n', 'v' }, 'ä', ':', { silent = false })
vim.keymap.set('i', 'ä', '<C-[>:', { silent = false })

vim.keymap.set({ 'n', 'i' }, 'ö', '<Cmd>noh<CR><C-[>', { silent = false })
vim.keymap.set('v', 'ö', 'v<Cmd>noh<CR><C-[>', { silent = false })

vim.keymap.set({ 'n', 'i' }, '<Esc>', '<Cmd>noh<CR><C-[>', { silent = false })
vim.keymap.set('v', '<Esc>', 'v<Cmd>noh<CR><C-[>', { silent = false })

vim.keymap.set({ 'n', 'v', 'i' }, '<C-s>', '<Cmd>w<CR>', { silent = false })

vim.keymap.set('i', 'Å', require("copilot.suggestion").accept, { silent = false })
vim.keymap.set('i', 'å', require("copilot.suggestion").accept_word, { silent = false })

-- vim.keymap.set('i', '<C-å>', require("copilot.suggestion").accept_word, { silent = false })

-- Insert brakets and things around selected text
-- vim.keymap.set('v', '{', 'v<Cmd>noh<CR><C-[>', { silent = false })

-- vim.keymap.set({ 'n', 'v' }, 'å', '<Cmd>exit<CR>', { silent = true })

-- Remap for dealing with word wrap
vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

-- Diagnostic keymaps
vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Open floating diagnostic message' })
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostics list' })

-- [[ Highlight on yank ]]
-- See `:help vim.highlight.on_yank()`
local highlight_group = vim.api.nvim_create_augroup('YankHighlight', { clear = true })
vim.api.nvim_create_autocmd('TextYankPost', {
  callback = function()
    vim.highlight.on_yank()
  end,
  group = highlight_group,
  pattern = '*',
})
