-- Internal mutable state of the package.
-- Modules don't directly request each other for primitives and data,
-- but request this instead so that user overrides work as regular "options".

local str = require("intim.strings")

---@alias lang string

return {
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
        "Missing tmux.spawn function "
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
  -- Can also be a function, evaluated on invocation.
  invoke = {
    lua = "lua",
    python = "python",
    julia = "julia --project=. --threads=auto",
    r = "R --no-save",
  },
  -- Lang-specific settings.
  lua = {
    -- Raise if persistent locals are supported within the interpreter.
    use_locals = false,
  },

  --- Transformations to be applied prior to sending lines to intim.
  --- @alias LinePreProcess fun(input:string):string
  --- @type table<string, LinePreProcess?>
  line_preprocess = {
    _before = str.dedent,
    _after = str.dedent,
  },

  --- Determine current session name.
  ---@type fun(): string
  session = nil,

  --- Determine current intim language.
  ---@type fun():lang
  current_lang = nil,
}
