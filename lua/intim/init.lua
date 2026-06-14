local M = {} -- Public interface module.
local P = {} -- Private.
M.P = P -- Expose internals to ease debugging.

---@alias lang string
---@alias Cmd string[]

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
--- Private, yet reusable in other modules.

--- Obtain current session name.
---@type fun(): string
function P.session() return M.state.tmux.session end

-- Display error message, usually prior to early returning,
-- to avoid polluting user with a whole stacktrace.
function P.err(mess) vim.api.nvim_echo({ { mess } }, true, { err = true }) end

-- Decorate a function so it gracefully wraps the above.
function P.guard(...)
  local status, res = pcall(...)
  if not status then
    P.err(res)
    return
  end
  return res
end

--- Collapse array into a single string with the given separator.
---@type fun(input: string[], sep:string):string
function P.join(input, sep)
  local res
  for _, elt in ipairs(input) do
    res = res and (res .. sep .. elt) or elt
  end
  return res
end

--- Separate string into `sep`arated chunks.
---@type fun(input:string, sep:string):string[]
function P.split(input, sep)
  local res = {}
  for chunk, s in input:gmatch("([^" .. sep .. "]*)(" .. sep .. "?)") do
    table.insert(res, chunk)
    if s == "" then break end
  end
  return res
end

--- Remove fixed prefix from string if present.
---@type fun(prefix: string, input: string): string
function P.remove_prefix(expected, input)
  local n = #expected
  local actual = input:sub(1, n)
  return (actual == expected) and input:sub(n + 1, #input) or input
end

-- More 'state' may be added in subsequent modules adding functionality.
for _, mod in ipairs({
  "setup",
  "pass",
  "chunk",
  "statement",
  "loop",
  "hotkeys",
}) do
  require("intim." .. mod)(M, P)
end

return M
