-- Kept deliberately thin so startup cost stays near zero: everything else is
-- required lazily the first time the command runs.
if vim.g.loaded_vimdojo then
  return
end
vim.g.loaded_vimdojo = true

vim.api.nvim_create_user_command("VimDojo", function(cmd)
  require("vimdojo").command(cmd.fargs)
end, {
  nargs = "*",
  desc = "Open the vimdojo game",
  complete = function(arg_lead, cmd_line)
    return require("vimdojo").complete(arg_lead, cmd_line)
  end,
})
