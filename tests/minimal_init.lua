local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local plenary = vim.env.PLENARY_DIR or (root .. "/.deps/plenary.nvim")

vim.opt.runtimepath:prepend(plenary)
vim.opt.runtimepath:prepend(root)
vim.o.swapfile = false
vim.o.shadafile = "NONE"

-- --noplugin skips plugin/ scripts, so load the ones the tests need explicitly.
vim.cmd("runtime plugin/plenary.vim")
vim.cmd("runtime plugin/vimdojo.lua")

-- Lets specs `require("helpers")`.
package.path = root .. "/tests/?.lua;" .. package.path
