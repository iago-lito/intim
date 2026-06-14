-- Pass input to intim an alternate way
-- by writing it to a file and then sending a sourcing command.

--- Construct sourcing command for the given language.
---@alias Chunk fun(filepath: string): string
---@type table<lang, Chunk>
local chunk = {}

-- https://stackoverflow.com/a/21650539/3719101
-- This is only supposed to work for the lua interpreter,
-- but make bet that it should also work good fair enough in alternate langs.
local function lua_str_repr(path) return ("%q"):format(path):gsub("\\\n", "\\n") end
local lsr = lua_str_repr

--------------------------------------------------------------------------------
--- Lang support.

function chunk.lua(p) return "dofile(" .. lsr(p) .. ")" end
function chunk.python(p) return "exec(open(" .. lsr(p) .. ").read())" end
function chunk.julia(p) return "include(" .. lsr(p) .. ")" end
function chunk.r(p) return "source(" .. lsr(p) .. ")" end

--------------------------------------------------------------------------------
--- Impl.
return function(M, P)
  -- Expose so it may be configured further by user.
  M.state.chunk = chunk

  function P.chunkfile() return M.state.data .. "/chunk" end

  function P.write_chunk(input)
    local name = P.chunkfile()
    local file = io.open(name, "w")
    if not file then
      error("Could not open file at " .. vim.inspect(name) .. ".")
    end
    file:write(input)
    file:close()
  end

  ---@type fun():Chunk?
  local function get_chunk_fn()
    local lang = P.get_current_lang()
    local fn = chunk[lang]
    if not fn then
      P.err(
        "No intim support for sourcing chunks in lang "
          .. vim.inspect(lang)
          .. " yet."
      )
      return
    end
    return fn
  end

  --- Send selected text as a chunk.
  function M.send_chunk()
    local fn = get_chunk_fn()
    if not fn then return end
    local chunkfile = P.chunkfile()
    local sel = P.selected_text()
    P.write_chunk(sel)
    local cmd = fn(chunkfile)
    M.send_command(cmd)
  end

  -- Send whole file as a chunk.
  function M.send_file()
    local fn = get_chunk_fn()
    if not fn then return end
    local path = vim.fn.expand("%s")
    local cmd = fn(path)
    M.send_command(cmd)
  end
end
