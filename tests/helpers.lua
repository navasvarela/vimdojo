local M = {}

M.root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

--- Fixtures are shared with the web port's tests, so both implementations are
--- checked against identical cases.
---@param name string File name under tests/fixtures/, without extension.
---@return table
function M.fixture(name)
  local path = ("%s/tests/fixtures/%s.json"):format(M.root, name)
  local text = table.concat(vim.fn.readfile(path), "\n")
  return vim.json.decode(text, { luanil = { object = true, array = true } })
end

---@return string
function M.temp_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

return M
