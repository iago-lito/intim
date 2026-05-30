--- Use treesitter + lang-specific trick
--- to infiltrate `for` loops and step them.

---@alias lang string
---@alias loop_name string

---@class Loops<L>
---@field next_id integer
---@field index table<loop_name, L>

---@class Loop
---@field id integer
---@field body [integer, integer] (start row/col)

return function(M, P)
  --- Identify every open loop so as to keep track of them.
  ---@type table<lang, Loops>
  M.loops = {}

  ---@type fun(actions: string[], session: string?)
  function P.loop_actions(actions, session)
    local focal, lang = P.current_node_lang() ---@type TSNode, string
    local f = {} ---@type table<string, function>
    local verbs = { "find", "parse" }
    for _, act in ipairs(actions) do
      verbs[#verbs + 1] = act
    end
    for _, verb in ipairs(verbs) do
      local fn = M.state.ts_loop[verb][lang]
      if not fn then
        error(
          "No function provided to "
            .. verb
            .. " TS loop for lang "
            .. vim.inspect(lang)
            .. "."
        )
      end
      f[verb] = fn
    end
    local node = f.find(focal) ---@type TSNode?
    if not node then
      P.err("Not within a loop?")
      return
    end
    local loop = f.parse(node) ---@type Loop
    local code = ""
    for _, verb in ipairs(actions) do
      code = code .. f[verb](loop)
      if verb == "infiltrate" then
        local row, col = unpack(loop.body)
        vim.api.nvim_win_set_cursor(0, { row + 1, col })
      end
    end
    M.send_command(code, session)
  end

  function M.infiltrate_loop(session)
    P.loop_actions({ "infiltrate", "step" }, session)
  end
  function M.step_loop(session) P.loop_actions({ "step" }, session) end

  ------------------------------------------------------------------------------
  --- Lua loops.

  ---@type fun(node: TSNode):TSNode?
  function M.find_lua_loop(node)
    while true do
      if node:type() == "for_statement" then return node end
      local parent = node:parent()
      if not parent then return end
      node = parent
    end
  end

  M.loops["lua"] = { next_id = 0, index = {} }
  local lua_loop_vars = vim.treesitter.query.parse(
    "lua",
    [[
      (for_statement clause: [
          (for_generic_clause (variable_list) @vars) @clause
          (for_numeric_clause name: (_) @vars) @clause
       ] body: (_) @body)
    ]]
  )

  ---@class LuaLoop: Loop
  ---@field clause string
  ---@field vars string

  -- Assuming the input is a loop, parse it into the elements we need.
  ---@type fun(node: TSNode): LuaLoop
  function M.parse_lua_loop(node)
    local loops = M.loops["lua"] ---@type Loops<LuaLoop?>
    local capts = lua_loop_vars:iter_captures(node, 0)
    local function get_node()
      local _, n, _ = capts()
      return n
    end
    local function get_text()
      local n = get_node()
      return vim.treesitter.get_node_text(n, 0, {})
    end
    local clause = get_text()
    local vars = get_text()
    local body = get_node()
    local row, col, _ = body:start()
    local name = "for " .. clause .. " do"
    local loop = loops.index[name]
    if not loop then
      loop = {
        id = loops.next_id,
        clause = clause,
        vars = vars,
        body = { row, col },
      }
      loops.index[name] = loop
      loops.next_id = loops.next_id + 1
    else
      loop.body = { row, col } -- Update in case it has changed.
    end
    return loop
  end

  -- Generate a coroutine with this loop, ready to be stepped.
  ---@type fun(loop: LuaLoop): string
  function M.infiltrate_lua_loop(l)
    return string.format(
      [[
%sintim_loop_%i = coroutine.create(function()
  for %s do coroutine.yield(%s) end
  error()
end)
      ]],
      M.state.lua.use_locals and "local " or "",
      l.id,
      l.clause,
      l.vars
    )
  end

  --- Step the given loop.
  ---@type fun(loop: LuaLoop): string
  function M.step_lua_loop(l)
    return string.format(
      [[
%sintim_loop_status, %s = coroutine.resume(intim_loop_%i)
if not intim_loop_status then error("Intim iteration ended for loop %i.") end
    ]],
      M.state.lua.use_locals and "local " or "",
      l.vars,
      l.id,
      l.id
    )
  end
end
