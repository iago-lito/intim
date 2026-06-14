-- Pass input to intim an alternate way
-- by writing it to a file and then sending a sourcing command.

local C = {}
local err = require("intim.errors").err
local pass = require("intim.pass")
local I = require("intim.state")

--- Construct sourcing command for the given language.
---@alias Chunk fun(filepath: string): string
---@type table<lang, Chunk>
I.chunk = {}

-- https://stackoverflow.com/a/21650539/3719101
-- This is only supposed to work for the lua interpreter,
-- but make bet that it should also work good fair enough in alternate langs.
local function lua_str_repr(path) return ("%q"):format(path):gsub("\\\n", "\\n") end
local lsr = lua_str_repr

--------------------------------------------------------------------------------
--- Lang support.

function I.chunk.lua(p) return "dofile(" .. lsr(p) .. ")" end
function I.chunk.python(p) return "exec(open(" .. lsr(p) .. ").read())" end
function I.chunk.julia(p) return "include(" .. lsr(p) .. ")" end
function I.chunk.r(p) return "source(" .. lsr(p) .. ")" end

--------------------------------------------------------------------------------
--- Impl.

function C.file() return I.data .. "/chunk" end

function C.write(input)
  local name = C.file()
  local file = io.open(name, "w")
  if not file then
    error("Could not open file at " .. vim.inspect(name) .. ".")
  end
  file:write(input)
  file:close()
end

---@type fun():Chunk?
function C.get_fn()
  local lang = I.current_lang()
  local fn = I.chunk[lang]
  if not fn then
    err(
      "No intim support for sourcing chunks in lang "
        .. vim.inspect(lang)
        .. " yet."
    )
    return
  end
  return fn
end

--- Send selected text as a chunk.
function C.send()
  local fn = C.get_fn()
  if not fn then return end
  local chunkfile = C.file()
  local sel = C.selected_text()
  C.write(sel)
  local cmd = fn(chunkfile)
  pass.send_command(cmd)
end

-- Send whole file as a chunk.
function C.send_file()
  local fn = C.get_fn()
  if not fn then return end
  local path = vim.fn.expand("%s")
  local cmd = fn(path)
  pass.send_command(cmd)
end

return C
