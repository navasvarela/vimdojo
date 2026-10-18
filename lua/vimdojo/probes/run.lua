-- The sandbox's `nvim -l` script: `nvim ... -u shim.lua -l run.lua job.json`.
-- The shim has already put vimdojo on package.path and loaded the config.
-- A missing job argument is a bug in sandbox.lua, so asserting (which leaves
-- no report behind) is the right failure.

-- `nvim -l` passes script arguments only through the global `arg` table.
-- selene: allow(global_usage)
local job = assert(_G.arg[1], "usage: run.lua job.json")
require("vimdojo.probes.runner").main(job)
