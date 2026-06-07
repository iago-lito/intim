local M = {} -- Public interface module.
local P = {} -- Private.
M.P = P -- Expose internals to ease debugging.

---@alias lang string
---@alias Cmd string[]

-- Every file fills these modules up.
for _, mod in ipairs({ "setup", "pass", "statement", "loop" }) do
  require("intim." .. mod)(M, P)
end

--------------------------------------------------------------------------------
-- Internal mutable state, whose initialization is configurable as "options".

M.state = {
  --- Where to store intim's data.
  data = vim.fs.joinpath(vim.fn.stdpath("data"), "intim"),
  tmux = {
    --- The tmux session name to communicate within it.
    session = "Intim",
    --- The buffer used to pass/paste text.
    buffer = "Intim",
    --- The system command to run tmux with the session name.
    ---@type fun(session_name: string): Cmd
    spawn = function(name)
      error(
        "Missing tmux.cmd function "
          .. "to explain how to obtain a tmux session with name "
          .. vim.inspect(name)
          .. "."
      )
    end,
    --- The system command to kill the given tmux session.
    ---@type fun(session_name: string): Cmd
    kill = function(name) return { "tmux", "kill-session", "-t", name } end,
  },
  -- Command to invoke the interpreter right after the tmux session is launched.
  -- Can also be a function, evaluated on invokation.
  invoke = {
    lua = "lua",
    python = "python",
    julia = "julia --project=.",
    r = "R --no-save",
  },
  -- Lang-specific settings.
  lua = {
    -- Raise if persistent locals are supported within the interpreter.
    use_locals = false,
  },
  --- Functions applied to lines under cursor prior to them being sent by intim.
  --- Grouped by filetype. Applied in order.
  line_preprocess = {
    _before = { M.dedent },
    python = { M.strip_python_doctest_prompt },
    julia = { M.strip_julia_doctest_prompt },
    r = { M.strip_r_doctest_prompt },
    _after = { M.dedent },
  },
  loops = M.loops,
}

--------------------------------------------------------------------------------
---Private.

--- Obtain current session name.
---@type fun(): string
function P.session() return M.state.tmux.session end

-- Display error message, usually prior to early returning,
-- to avoid polluting user with a whole stacktrace.
function P.err(mess) vim.api.nvim_echo({ { mess } }, true, { err = true }) end

return M
