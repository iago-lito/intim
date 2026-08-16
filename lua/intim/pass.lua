--- Passing text to intim, lexical approach.

local P = {}
local str = require("intim.strings")
local I = require("intim.state")

---@alias Cmd string[]
---@alias GetLinesSpan fun():string[], [integer, integer, integer, integer]

--- No-op: get no lines.
---@type GetLinesSpan
function P.notext() return {}, { 0, -1, 0, -1 } end

--- Send text to the given (or current) tmux session.
---@type fun(input: string)
function P.send(input)
  local sess = I.session()
  local cmd = { "tmux", "send", "-t", sess, input }
  vim.system(cmd)
end

--- Paste text to the given (or current) tmux session.
--- (better handle of line breaks with paste-brackets inserted)
---@type fun(input: string, buffer: string?)
function P.paste(input, buffer)
  local sess = I.session()
  buffer = buffer or I.tmux.buffer
  local cmd = { "tmux", "set-buffer", "-t", sess, "-b", buffer, input }
  vim.system(cmd)
  cmd = { "tmux", "paste-buffer", "-t", sess, "-b", buffer, "-dp" }
  vim.system(cmd)
end

--- Send special tmux codes.
---@type fun(c: string):(fun())
local function code(c)
  return function() P.send(c) end
end
P.send_enter = code("ENTER")
P.send_space = code("SPACE")
P.send_interrupt = code("c-c")
P.send_eof = code("c-d")
P.send_clear = code("c-u")

--- Send then 'press enter'.
---@type fun(input: string)
function P.send_command(cmd)
  P.paste(cmd)
  P.send_enter()
end

--- Send line under cursor (lexical).
function P.send_line()
  local line = vim.api.nvim_get_current_line()
  local lang = I.current_lang()
  local pr = I.line_preprocess
  for _, pass in ipairs({ pr._before, pr[lang], pr._after }) do
    if pass then line = pass(line) end
  end
  P.send_command(line)
end

-- Helper functions to remove doctest prompts.
for lang, prefix in pairs({
  python = { ">>>", "..." },
  julia = "julia>",
  r = "#'",
}) do
  local fn ---@type fun(line: string):string
  if type(prefix) == "string" then
    fn = function(line) return str.remove_prefix(prefix, line) end
  else
    -- With several possible prefixes, attempt to remove until one matches.
    fn = function(line)
      for _, p in ipairs(prefix) do
        local stripped = str.remove_prefix(p, line)
        if stripped ~= line then return stripped end
      end
      return line
    end
  end
  I.line_preprocess[lang] = fn
end

--- Extract visually selected text.
---@type GetLinesSpan
function P.selected_text()
  local mode = vim.api.nvim_get_mode().mode
  local start = vim.fn.getpos("v")
  local stop = vim.fn.getpos(".")
  local _, arow, acol = unpack(start)
  local _, brow, bcol = unpack(stop)
  local function sort(a, b) ---@return integer, integer
    if a < b then
      return a, b
    else
      return b, a
    end
  end
  local srow, erow = sort(arow, brow)
  local scol, ecol = sort(acol, bcol)
  local lines ---@type string[]
  if mode == "v" then
    -- Simple visual mode: send selected text.
    lines = vim.fn.getregion(start, stop)
  else
    -- Full line visual mode: send all selected lines.
    lines = vim.api.nvim_buf_get_lines(0, srow - 1, erow, true)
    if mode == "V" then -- Not much to add.
    elseif mode == "\22" then
      -- Block visual mode: truncate selected lines.
      for i, line in ipairs(lines) do
        lines[i] = line:sub(scol, ecol)
      end
    else
      error(
        "Intim: This action should be performed in visual mode, not "
          .. vim.inspect(mode)
          .. "."
      )
    end
  end
  return lines, { srow - 1, scol - 1, erow - 1, ecol }
end

------------------------------------------------------------------------------
--- Exposed mappings.

function P.send_object()
  P.operator(function(_)
    local lines = P.object_text()
    local text = str.join(lines, "\n")
    P.send_command(text)
  end)
end

function P.send_selected()
  local lines = P.selected_text()
  if not lines then return end
  local text = (str.join(lines, "\n"))
  P.send_command(text)
end

------------------------------------------------------------------------------
-- Misc utils.

--- The strategy to set local lua functions to the operator option.
--- https://github.com/neovim/neovim/issues/18132#issuecomment-1723577603
---@type fun(f: fun(string)) -- See `:h 'opfunc'`.
P.set_opfunc = vim.fn[vim.api.nvim_exec2(
  [[
    func s:set_opfunc(val)
      let &opfunc = a:val
    endfunc
    echon get(function('s:set_opfunc'), 'name')
    ]],
  { output = true }
).output]

--- Call during `opfunc` callback to obtain the text spanned by user object.
---@type GetLinesSpan
function P.object_text()
  local srow, scol = unpack(vim.api.nvim_buf_get_mark(0, "["))
  local erow, ecol = unpack(vim.api.nvim_buf_get_mark(0, "]"))
  local text =
    vim.api.nvim_buf_get_text(0, srow - 1, scol, erow - 1, ecol + 1, {})
  return text, { srow - 1, scol, erow - 1, ecol + 1 }
end

--- Leverage the above to perform operator action immediately on user object.
---@type fun(f: fun(_: string))
function P.operator(f)
  P.set_opfunc(f)
  vim.api.nvim_feedkeys("g@", "n", false)
end

return P
