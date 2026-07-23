--- Passing statements to intim, semantic approach.

local S = {}
local str = require("intim.strings")
local err = require("intim.errors").err
local pass = require("intim.pass")
local ts = require("intim.treesitter")
local I = require("intim.state")

-- Find statements by climbing up the tree
-- until a special node kind is reached,
-- or until it lies behind a special field name.
---@alias StatementFind {kinds: string[]?, fields: string[]?}
---@type table<lang, StatementFind>
local find = {}

find.lua = { kinds = { "block", "chunk" } }
find.julia = { kinds = { "block", "source_file" } }
find.python = { kinds = { "block", "module" } }
find.r = { kinds = { "program" }, fields = { "body" } }

-- Expose so it may be configured further by user.
I.find_statement = find

---@type fun(lang: lang):boolean
function S.supported(lang) return find[lang] ~= nil end

--- Given a focal node, climb up to find a statement node if any.
---@type fun(lang: lang, start: TSNode):TSNode?
local function do_find(lang, node)
  local kinds = find[lang].kinds or {}
  local fields = find[lang].fields or {}
  while true do
    local parent = node:parent() ---@type TSNode? (not sure why inference fails)
    if not parent then return end
    local type = parent:type()
    for _, body in ipairs(kinds) do
      if type == body then return node end
    end
    for _, field in ipairs(fields) do
      for _, body in ipairs(parent:field(field)) do
        if body:equal(node) then return node end
      end
    end
    node = parent
  end
end

-- Given a statement node, skip to the next statement node,
-- skipping over 'comment' nodes and climbing up if necessary.
---@type fun(lang: lang, statement: TSNode): TSNode?
local function do_skip(lang, node)
  while true do
    local sib = node:next_sibling() ---@type TSNode? (inference failing?)
    if sib then
      if sib:type() ~= "comment" then return sib end
      node = sib
    else
      -- Climb up, throwing back to caller.
      -- If no next node is found, just reach to EOF.
      local function bottom() vim.cmd.normal("G$") end
      local p = node:parent()
      if not p then
        bottom()
        return
      end
      node = p
      p = do_find(lang, node)
      if not p then
        bottom()
        return
      end
      node = p
    end
  end
end

------------------------------------------------------------------------------
--- Public.

--- Send statement under cursor (semantic, using treesitter).
function S.send()
  local start, lang = ts.current_node_lang()
  if not S.supported(lang) then
    error(
      "No semantic statement implemented for lang " .. vim.inspect(lang) .. "."
    )
  end
  local node = do_find(lang, start)
  if not node then
    err("Root reached without finding a statement.")
    return
  end
  -- Careful: the node starts *after* possible indentation on its first line.
  -- Remove that indentation from successive lines.
  local srow, scol, erow, ecol = node:range()
  local prefix = vim.api.nvim_buf_get_text(0, srow, 0, srow, scol, {})[1]
  local _, _, indent = prefix:find("^(%s*)")
  local lines = vim.api.nvim_buf_get_text(0, srow, scol, erow, ecol, {})
  local text ---@type string?
  for _, line in ipairs(lines) do
    text = (text and text .. "\n" or "") .. str.remove_prefix(indent, line)
  end
  pass.send_command(text)
  node = do_skip(lang, node)
  if not node then return end
  srow, scol, _, _ = node:range()
  vim.api.nvim_win_set_cursor(0, { srow + 1, scol })
end

return S
