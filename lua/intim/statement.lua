--- Passing statements to intim, semantic approach.

return function(M, P)
  ------------------------------------------------------------------------------
  --- Public.

  --- Send statement under cursor (semantic, using treesitter).
  ---@type fun(session: string?)
  function M.send_statement(session)
    local lang = P.get_current_lang()
    local find_statement = M.state.ts_statement[lang]
    if not find_statement then
      P.err(
        "No function provided to find TS statement for lang "
          .. vim.inspect(lang)
          .. "."
      )
      return
    end
    local node = find_statement()
    if not node then return end -- Assume the funtion has already explained why.
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
  end

  --- Finding 'statement' nodes work the same for lua or python:
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
    M["find_" .. lang .. "_statement"] = function()
      -- Any node directly descending from 'block' or 'chunk'.
      vim.treesitter.get_parser(0):parse()
      local node = vim.treesitter.get_node()
      if not node then
        P.err("No TSNode found at given location.")
        return
      end
      while true do
        local parent = node:parent()
        if not parent then
          P.err("Root reached without finding a statement.")
          return
        end
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
  end
end
