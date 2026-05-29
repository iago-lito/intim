--- Setting up options and starting/killing intim.

return function(M, P)
  ------------------------------------------------------------------------------
  --- Public.

  --- Merge user parameters into state starting point.
  function M.setup(o)
    M.state = P.merge_tables(M.state, o, function(key, default, user)
      if not default then error("Unexpected option: " .. vim.inspect(key)) end
      local value = user or default
      if key == "data" then P.validate_or_create_dir("data", value) end
      return value
    end)
  end

  --- Start tmux session.
  ---@type fun(session: string?)
  function M.spawn(session)
    session = P.requested_session(session)
    if P.is_session_open(session) then
      P.err("Tmux session " .. vim.inspect(session) .. " already open.")
      return
    end
    -- Request tmux session.
    local spawn = M.state.tmux["spawn"](session)
    local p = vim.system(spawn)
    -- Wait until it's ready.
    local wait = 500 -- ms.
    local max = 5000 -- ms.
    local acc = 0
    while not P.is_session_open(session) do
      vim.wait(wait)
      acc = acc + wait
      if acc >= max then
        P.err(
          "Could not spawn tmux session "
            .. vim.inspect(session)
            .. " before "
            .. max
            .. "ms were elapsed?"
        )
        local r = p:wait()
        P.err(
          "retcode: "
            .. r.code
            .. "\nstdout: "
            .. r.stdout
            .. "\nstderr: "
            .. r.stderr
        )
        return
      end
    end
    M.invoke(session)
  end

  --- Spawn interpreter.
  ---@type fun(session: string?)
  function M.invoke(session)
    local lang = P.get_current_lang()
    if not lang then
      P.err("No lang set to pick interpreter?")
      return
    end
    local invoke = M.state.invoke[lang]
    invoke = type(invoke) == "function" and invoke() or invoke
    if not invoke then
      P.err(
        "No interpreter invocation command set for lang "
          .. vim.inspect(lang)
          .. "?"
      )
      return
    end
    M.send_command(invoke, session)
  end

  --- Exit interpreter.
  ---@type fun(session: string?)
  function M.revoke(session) M.send_eof(session) end

  --- Restart interpreter.
  ---@type fun(session: string?)
  function M.reinvoke(session)
    M.revoke(session)
    M.invoke(session)
  end

  --- Terminate tmux session.
  ---@type fun(session: string?)
  function M.kill(session)
    session = P.requested_session(session)
    local kill = M.state.tmux["kill"](session)
    vim.system(kill)
  end

  --- Restart intim.
  ---@type fun(session: string?)
  function M.respawn(session)
    M.kill(session)
    M.spawn(session)
  end

  ------------------------------------------------------------------------------
  --- Private.

  ---@type fun(name: string, path: string)
  function P.validate_or_create_dir(name, path)
    vim.validate(name, path, "string")
    if vim.fn.isdirectory(path) > 0 then return end
    if vim.uv.fs_stat(path) then
      error("Not a folder for " .. name .. ": " .. path)
    end
    local parent = vim.fs.dirname(path)
    if vim.fn.isdirectory(parent) == 0 then
      error("Not a valid path to create directory within: " .. parent)
    end
    vim.fn.mkdir(path)
  end

  --- Recursively merge 'dict' tables using the given function.
  --- The function receives the path to values to be fused
  --- along with corresponding left and right values.
  function P.merge_tables(lhs, rhs, merge, path)
    local res = {}
    -- Fill once from the left, checking for unexpected right values,
    for k, l in pairs(lhs) do
      local p = path and path .. "." .. k or k
      local r = rhs[k]
      local v = P.recursive_merge(k, l, r, merge, p)
      res[k] = v
    end
    -- Then once from the right, skipping keys already there,
    -- and checking for unexpected left values.
    for k, r in pairs(rhs) do
      local p = path and path .. "." .. k or k
      local l = lhs[k]
      if l == nil then res[k] = P.recursive_merge(k, nil, r, merge, p) end
    end
    return res
  end

  function P.recursive_merge(key, lhs, rhs, merge, path)
    path = path or key
    local ld = P.is_dict(lhs)
    local rd = P.is_dict(rhs)
    if ld ~= rd then
      if rhs == nil then
        rhs = {}
      elseif lhs == nil then
        lhs = {}
      else
        error(
          "At key "
            .. vim.inspect(path)
            .. ": received dict on the "
            .. (ld and "left" or "right")
            .. " but on the "
            .. (rd and "left" or "right")
            .. " received: "
            .. vim.inspect(ld and rhs or lhs)
        )
      end
    end
    if ld then
      return P.merge_tables(lhs, rhs, merge, path)
    else
      return merge(path, lhs, rhs)
    end
  end

  --- Naive attempt to characterize a `:help lua-dict` from other values.
  function P.is_dict(table)
    local t = type(table)
    if t ~= "table" then return false end
    local has_indices = false
    for _, _ in ipairs(table) do
      has_indices = true
      break
    end
    return not has_indices
  end

  ---@type fun(session: string?): string
  function P.requested_session(session)
    if session then
      return session
    else
      return M.state.tmux.session
    end
  end

  ---@param session string
  function P.is_session_open(session)
    return vim.system({ "tmux", "has-session", "-t", session }):wait().code == 0
  end
end
