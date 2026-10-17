-- Minimal Neovim config for recording docs/demo.gif (see docs/demo.tape):
-- loads vimdojo from this checkout with a throwaway progress file.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.o.swapfile = false
vim.o.shadafile = "NONE"
vim.o.termguicolors = true
vim.opt.fillchars = { eob = " " }
vim.o.laststatus = 0
vim.o.ruler = false
vim.o.showcmd = false

vim.cmd("runtime plugin/vimdojo.lua")
require("vimdojo").setup({ progress_path = vim.fn.tempname() .. "/progress.json" })
