--- Setting up options and starting/killing intim.

return function(M, P)
  ------------------------------------------------------------------------------
  --- Public.

  function M.setup(o)
    M.state = P.merge_tables(M.state, o, function(key, default, user)
      if not default then error("Unexpected option: " .. vim.inspect(key)) end
      local value = user or default
      if key == "data" then P.validate_or_create_dir("data", value) end
      return value
    end)
  end

  for _, verb in ipairs({ "start", "kill" }) do
    M[verb] = function(session)
      local tm = M.state.tmux
      session = session or tm.session
      local cmd = tm[verb](session) ---@cast cmd Cmd
      vim.system(cmd)
    end
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
end
