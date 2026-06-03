--- Passing statements to intim, semantic approach.

-- HERE: import fresh logic from loops.

return function(M, P)
  ------------------------------------------------------------------------------
  --- Public.

  P.root_error = "Root reached without finding a statement."

  --- Send statement under cursor (semantic, using treesitter).
  ---@type fun(session: string?)
  function M.send_statement(session)
    local node, lang = P.current_node_lang()
    local find_statement = M.state.ts_statement.find[lang]
    if not find_statement then
      error(
        "No function provided to find TS statement for lang "
          .. vim.inspect(lang)
          .. "."
      )
    end
    node = find_statement(node)
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
    M.send_command(text, session)
    local next_statement = M.state.ts_statement.next[lang]
    if not next_statement then return end
    local st, res = pcall(next_statement, node)
    if not st then
      if P.endswith(res, P.root_error) then return end -- Discard root error.
      error(res)
    end
    node = res
    srow, scol, _, _ = node:range()
    vim.api.nvim_win_set_cursor(0, { srow + 1, scol })
  end

  --- Finding 'statement' nodes work the same for these languages:
  --- start from current node and climb up
  --- until a 'block' or toplevel node is reached,
  --- or until the node is field-named 'body:' etc.
  for lang, stop in pairs({
    julia = { { "block", "source_file" }, {} },
    lua = { { "block", "chunk" }, {} },
    python = { { "block", "module" }, {} },
    r = { { "program" }, { "body" } },
  }) do
    local types, fields = unpack(stop)

    --- Given a focal node, climb up to find a statement node.
    ---@type fun(node: TSNode): TSNode
    local function find(node)
      while true do
        local parent = node:parent()
        if not parent then error(P.root_error) end
        local type = parent:type()
        for _, body in ipairs(types) do
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
    -- find the next statement node.
    ---@type fun(node: TSNode): TSNode?
    local function next(node)
      while true do
        local sib = node:next_sibling()
        if sib then
          if sib:type() ~= "comment" then return sib end
          node = sib
        else
          -- Climb up, throwing back to caller.
          node = node:parent()
          if not node then error(P.root_error) end
          node = find(node)
        end
      end
    end

    M["find_" .. lang .. "_statement"] = find
    M["next_" .. lang .. "_statement"] = next
  end

  ------------------------------------------------------------------------------
  --- Private.
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
