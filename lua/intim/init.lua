local M = {}
local P = {}
M.P = P -- Expose internals to ease debugging.

--------------------------------------------------------------------------------
-- Internal mutable state, whose initialization is configurable as "options".

---@alias Cmd string[]

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

--- Escape and send text to the given (or current) tmux session.
---@type fun(input: string, session: string?)
function M.send(input, session)
  local tm = M.state.tmux
  session = session or tm.session
  local cmd = { "tmux", "send", "-t", session, input }
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
  M.send(cmd, session)
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
  local srow, scol, erow, ecol = node:range()
  -- Extract anything before the node on the same line.
  local prefix = vim.api.nvim_buf_get_text(0, srow, 0, srow, scol, {})[1]
  local text
  if prefix:match("^%s+$") then
    -- If the prefix is indentation, dedent subsequent lines by the same amount.
    local lines = vim.api.nvim_buf_get_text(0, srow, scol, erow, ecol, {})
    for _, line in ipairs(lines) do
      text = (text and text .. "\n" or "") .. P.remove_prefix(prefix, line)
    end
  else
    -- Otherwise just use the node text as-is.
    text = vim.treesitter.get_node_text(node, 0)
  end
  M.send_command(text, session)
end

--- Implement for lua.
---@type fun():TSNode?
function M.lua_statement()
  -- Any node directly descending from 'block' or 'chunk'.
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
    local t = parent:type()
    if t == "block" or t == "chunk" then return node end
    node = parent
  end
end

--------------------------------------------------------------------------------
--- Init/default state.

M.state = {
  -- Where to store the data.
  data = vim.fs.joinpath(vim.fn.stdpath("data"), "intim"),
  tmux = {
    -- The tmux session name to communicate within it.
    session = "Intim",
    --- The system command to run tmux with the session name.
    ---@type fun(session_name: string): Cmd
    start = function(name)
      error(
        "Missing tmux.cmd function "
          .. "to explain how to obtain a tmux session with name "
          .. vim.inspect(name)
          .. "."
      )
    end,
    --- The system command to kill the given tmux session.
    ---@type fun(session_name: string): Cmd
    kill = function(name) return { "tmux", "kill-session", "-t", name } end,
  },
  --- Functions applied to lines under cursor prior to them being sent by intim.
  --- Grouped by filetype. Applied in order.
  line_preprocess = {
    _before = { M.dedent },
    python = { M.strip_python_doctest_prompt },
    julia = { M.strip_julia_doctest_prompt },
    r = { M.strip_r_doctest_prompt },
    _after = { M.dedent },
  },
  --- Use to find tree-sitter statements/instructions to be passed to intim.
  ts_statement = {
    lua = M.lua_statement,
  },
}

--------------------------------------------------------------------------------
-- Private utils.

---@param name string
---@param path string
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
  local path = path or key
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

--- Remove fixed prefix from string if present.
---@type fun(prefix: string, input: string): string
function P.remove_prefix(expected, input)
  local n = #expected
  local actual = input:sub(1, n)
  return (actual == expected) and input:sub(n + 1, #input) or input
end

--- Obtain languages under cursor.
-- https://github.com/nvim-treesitter/nvim-treesitter/discussions/6643#discussioncomment-9892537
function P.get_current_lang()
  local curline = vim.fn.line(".")
  return vim.treesitter
    .get_parser()
    :language_for_range({ curline, 0, curline, 0 })
    :lang()
end

-- Display error message, usually prior to early returning.
function P.err(mess) vim.api.nvim_echo({ { mess } }, false, { err = true }) end

return M
