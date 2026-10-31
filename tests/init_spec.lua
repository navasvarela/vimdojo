describe("vimdojo", function()
  it("defines the :VimDojo command", function()
    assert.is_true(vim.fn.exists(":VimDojo") == 2)
  end)

  it("merges setup options over the defaults", function()
    local vimdojo = require("vimdojo")
    vimdojo.setup({ unlock_all = true })
    assert.is_true(vimdojo.config.unlock_all)
    assert.are.equal("float", vimdojo.config.window)
  end)
end)

describe("completing :VimDojo", function()
  local vimdojo = require("vimdojo")

  it("offers subcommands", function()
    assert.are.same({ "board" }, vimdojo.complete("bo", "VimDojo bo"))
  end)

  it("offers ranked levels after board, and not Setup ones", function()
    local levels = vimdojo.complete("", "VimDojo board ")
    assert.is_true(vim.tbl_contains(levels, "basic-motions-01"))
    assert.is_false(vim.tbl_contains(levels, "autocmds-01"))
    assert.are.same(
      { "basic-motions-01" },
      vimdojo.complete("basic-motions-01", "VimDojo board basic-motions-01")
    )
  end)
end)
