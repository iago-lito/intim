--- Passing text to intim, lexical approach.
return function(M, P)
  ------------------------------------------------------------------------------
  -- Public.

  --- Send text to the given (or current) tmux session.
  ---@type fun(input: string, session: string?)
  function M.send(input, session)
    local tm = M.state.tmux
    session = session or tm.session
    local cmd = { "tmux", "send", "-t", session, input }
    vim.system(cmd)
  end

  --- Paste text to the given (or current) tmux session.
  --- (better handle of line breaks with paste-brackets inserted)
  ---@type fun(input: string, session: string?, buffer: string?)
  function M.paste(input, session, buffer)
    local tm = M.state.tmux
    session = session or tm.session
    buffer = buffer or tm.buffer
    local cmd = { "tmux", "set-buffer", "-t", session, "-b", buffer, input }
    vim.system(cmd)
    cmd = { "tmux", "paste-buffer", "-t", session, "-b", buffer, "-dp" }
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
    M[fn_name] = function(session) M.send(code, session) end
  end

  --- Send then 'press enter'.
  ---@type fun(input: string, session: string?)
  function M.send_command(cmd, session)
    M.paste(cmd, session)
    M.send_enter(session)
  end

  --- Send line under cursor (lexical).
  ---@type fun(session: string?)
  function M.send_line(session)
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
    M.send_command(line, session)
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

  ------------------------------------------------------------------------------
  -- Private.

  --- Remove fixed prefix from string if present.
  ---@type fun(prefix: string, input: string): string
  function P.remove_prefix(expected, input)
    local n = #expected
    local actual = input:sub(1, n)
    return (actual == expected) and input:sub(n + 1, #input) or input
  end

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
end
