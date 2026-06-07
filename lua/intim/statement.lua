--- Passing statements to intim, semantic approach.

-- Find statements by climbing up the tree
-- until a special node kind is reached,
-- or until it lies behind a special field name.
---@alias StatementFind {kinds: string[]?, fields: string[]?}
---@type table<lang, StatementFind>
local find = {}

return function(M, P)
  find.lua = { kinds = { "block", "source_file" } }
  find.lua = { kinds = { "block", "chunk" } }
  find.python = { kinds = { "block", "module" } }
  find.r = { kinds = { "program" }, fields = { "body" } }

  ---@type fun(lang: lang):boolean
  function P.supported(lang) return find[lang] ~= nil end

  --- Given a focal node, climb up to find a statement node if any.
  ---@type fun(lang: lang, start: TSNode):TSNode?
  local function do_find(lang, node)
    local kinds = find[lang].kinds or {}
    local fields = find[lang].fields or {}
    while true do
      local parent = node:parent()
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
      local sib = node:next_sibling()
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
  function M.send_statement()
    local start, lang = P.current_node_lang()
    if not P.supported(lang) then
      error(
        "No semanting statement implemented for lang "
          .. vim.inspect(lang)
          .. "."
      )
    end
    local node = do_find(lang, start)
    if not node then
      P.err("Root reached without finding a statement.")
      return
    end
    -- Careful: the node starts *after* possible indentation on its first line.
    -- Remove that indentation from successive lines.
    local srow, scol, erow, ecol = node:range()
    local prefix = vim.api.nvim_buf_get_text(0, srow, 0, srow, scol, {})[1]
    local _, _, indent = prefix:find("^(%s*)")
    local lines = vim.api.nvim_buf_get_text(0, srow, scol, erow, ecol, {})
    local text
    for _, line in ipairs(lines) do
      text = (text and text .. "\n" or "") .. P.remove_prefix(indent, line)
    end
    M.send_command(text)
    node = do_skip(lang, node)
    if not node then return end
    srow, scol, _, _ = node:range()
    vim.api.nvim_win_set_cursor(0, { srow + 1, scol })
  end

  ---@type fun(): TSNode, string
  function P.current_node_lang()
    local lang = P.get_current_lang()
    vim.treesitter.get_parser(0):parse()
    if vim.fn.col("$") <= vim.fn.col(".") then
      -- Return back to actual content if the cursor lies past EOL.
      vim.cmd.normal("$")
    end
    local node = vim.treesitter.get_node()
    if not node then error("No TSNode found at given location.") end
    return node, lang
  end

  -- https://stackoverflow.com/a/72921992/3719101
  function P.endswith(string, suffix) return string:sub(-#suffix) == suffix end
end
