--- Passing text to intim, lexical approach.

---@alias GetLinesSpan fun():string[], [integer, integer, integer, integer]

return function(M, P)
  --- Send text to the given (or current) tmux session.
  ---@type fun(input: string)
  function M.send(input)
    local sess = P.session()
    local cmd = { "tmux", "send", "-t", sess, input }
    vim.system(cmd)
  end

  --- Paste text to the given (or current) tmux session.
  --- (better handle of line breaks with paste-brackets inserted)
  ---@type fun(input: string, buffer: string?)
  function M.paste(input, buffer)
    local sess = P.session()
    buffer = buffer or M.state.tmux.buffer
    local cmd = { "tmux", "set-buffer", "-t", sess, "-b", buffer, input }
    vim.system(cmd)
    cmd = { "tmux", "paste-buffer", "-t", sess, "-b", buffer, "-dp" }
    vim.system(cmd)
  end

  --- Send special tmux codes.
  for verb, code in pairs({
    enter = "ENTER",
    space = "SPACE",
    interrupt = "c-c",
    eof = "c-d",
    clear = "c-u",
  }) do
    local fn_name = "send_" .. verb
    M[fn_name] = function() M.send(code) end
  end

  --- Send then 'press enter'.
  ---@type fun(input: string)
  function M.send_command(cmd)
    M.paste(cmd)
    M.send_enter()
  end

  --- Send line under cursor (lexical).
  function M.send_line()
    local line = vim.api.nvim_get_current_line()
    local lang = P.get_current_lang()
    local pr = M.state.line_preprocess
    for _, passes in ipairs({ pr._before, pr[lang], pr._after }) do
      if passes then
        for _, pass in ipairs(passes) do
          line = pass(line)
        end
      end
    end
    M.send_command(line)
  end

  --- Remove input leading whitespace.
  ---@type fun(input: string): string
  function M.dedent(input) return input:match("^%s+(.*)") or input end

  -- Helper functions to remove doctest prompts.
  for ft, prefix in pairs({
    python = { ">>>", "..." },
    julia = "julia>",
    r = "#'",
  }) do
    local fn_name = "strip_" .. ft .. "_doctest_prompt"
    if type(prefix) == "string" then
      M[fn_name] = function(line) return P.remove_prefix(prefix, line) end
    else
      -- With several possible prefixes, attempt to remove until one matches.
      M[fn_name] = function(line)
        for _, p in ipairs(prefix) do
          local stripped = P.remove_prefix(p, line)
          if stripped ~= line then return stripped end
        end
        return line
      end
    end
  end

  --- Extract visually selected text.
  ---@type GetLinesSpan
  function P.selected_text()
    local mode = vim.api.nvim_get_mode().mode
    local start = vim.fn.getpos("v")
    local stop = vim.fn.getpos(".")
    local _, srow, scol = unpack(start)
    local _, erow, ecol = unpack(stop)
    if erow < srow then
      erow, srow = srow, erow
    end
    if ecol < scol then
      ecol, scol = scol, ecol
    end
    local lines
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
    return lines, { srow, scol, erow, ecol }
  end

  ------------------------------------------------------------------------------
  --- Exposed mappings.

  function M.send_object()
    P.operator(function(_)
      local lines = P.object_text()
      local text = P.join(lines, "\n")
      M.send_command(text)
    end)
  end

  function M.send_selected()
    local lines = P.selected_text()
    if not lines then return end
    local text = (P.join(lines, "\n"))
    M.send_command(text)
  end

  ------------------------------------------------------------------------------
  -- Misc utils.

  --- Obtain languages under cursor.
  --- https://github.com/nvim-treesitter/nvim-treesitter/discussions/6643#discussioncomment-9892537
  --- Or fallback to filetype, or nothing.
  ---@type fun(): string
  function P.get_current_lang()
    local curline = vim.fn.line(".")
    local parser = vim.treesitter.get_parser()
    if not parser then return vim.o.ft end
    return parser:language_for_range({ curline, 0, curline, 0 }):lang()
  end

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
    srow = srow - 1
    erow = erow - 1
    ecol = ecol + 1
    local text = vim.api.nvim_buf_get_text(0, srow, scol, erow, ecol, {})
    return text, { srow, scol, erow, ecol }
  end

  --- Leverage the above to perform operator action immediately on user object.
  ---@type fun(f: fun(string))
  function P.operator(f)
    P.set_opfunc(f)
    vim.api.nvim_feedkeys("g@", "n", false)
  end
end
