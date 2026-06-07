--- Use treesitter + lang-specific tricks
--- to infiltrate `for` loops and step them.

---@type table<lang, boolean>
local supported = {}

---@alias loop_name string
---@alias loop_data any

--- Identify every open loop so as to keep track of them.
---@class Loops<L>
---  @field next_id integer
---  @field index table<loop_name, Loop<L>>
---@type fun(): Loops
local function new_loops() return { next_id = 0, index = {} } end

---@class Loop<L>
---  @field id integer
---  @field body [integer, integer] (start row/col)
---  @field data L extra data depending on the language.

-- Find loops by climbing up the tree until a special `for` node is reached.
---@alias LoopFind string (nodename)
---@type table<lang, LoopFind>
local find = {}

--- One query per lang to obtain the relevant loop parts from a loop node.
---@type table<lang, vim.treesitter.Query>
local query = {}

--- Given captures from the query above, return a name and loop data.
--- Return an identifier for the loop, the lang-specific data and the body node.
---@alias Parse<L> fun(node: fun():TSNode): loop_name, L, TSNode
---@type table<lang, Parse>
local parse = {}

--- Exposed actions for user.
---@alias Action<L> fun(loop: Loop<L>): string
---@alias Verb table<lang, Action<L>>

-- Generate a coroutine with this loop, ready to be stepped.
---@type Verb
local infiltrate = {}

--- Generate code to step the given loop.
---@type Verb
local step = {}

return function(M, P)
  ---@type table<lang, Loops>
  M.loops = {}

  ------------------------------------------------------------------------------
  --- Lua loops.

  supported.lua = true

  ---@type Loops<Lua>
  M.loops.lua = new_loops()
  find.lua = "for_statement"

  ---@class Lua
  ---  @field clause string
  ---  @field vars string

  query.lua = vim.treesitter.query.parse(
    "lua",
    [[
      (for_statement clause: [
          (for_generic_clause (variable_list) @vars) @clause
          (for_numeric_clause name: (_) @vars) @clause
       ] body: (_) @body)
    ]]
  )

  ---@type Parse<Lua>
  function parse.lua(capt)
    local clause = P.nodetext(capt())
    local vars = P.nodetext(capt())
    local name = "for " .. clause .. " do"
    return name, {
      clause = clause,
      vars = vars,
    }, capt()
  end

  ---@type Action<Lua>
  function infiltrate.lua(l)
    return string.format(
      [[
%sintim_loop_%i = coroutine.create(function()
  for %s do coroutine.yield(%s) end
  error()
end)
      ]],
      M.state.lua.use_locals and "local " or "",
      l.id,
      l.data.clause,
      l.data.vars
    )
  end

  ---@type Action<Lua>
  function step.lua(l)
    return string.format(
      [[
%sintim_loop_status, %s = coroutine.resume(intim_loop_%i)
if not intim_loop_status then error("Intim iteration ended for loop %i.") end
    ]],
      M.state.lua.use_locals and "local " or "",
      l.data.vars,
      l.id,
      l.id
    )
  end

  ------------------------------------------------------------------------------
  --- Python loops.

  supported.python = true

  ---@type Loops<Python>
  M.loops.python = new_loops()
  find.python = "for_statement"

  ---@class Python
  ---  @field vars string
  ---  @field iter string

  query.python = vim.treesitter.query.parse(
    "python",
    [[
    (for_statement
      left: (_) @vars
      right: (_) @iter
      body: (_) @body
    )
    ]]
  )

  ---@type Parse<Python>
  function parse.python(capt)
    local vars = P.nodetext(capt())
    local iter = P.nodetext(capt())
    local name = "for " .. vars .. " in " .. iter .. ":"
    return name, {
      vars = vars,
      iter = iter,
    }, capt()
  end

  ---@type Action<Python>
  function infiltrate.python(l)
    return string.format([[intim_loop_%i = iter(%s)]], l.id, l.data.iter)
  end

  ---@type Action<Python>
  function step.python(l)
    return string.format([[%s = next(intim_loop_%i)]], l.data.vars, l.id)
  end

  ------------------------------------------------------------------------------
  --- Julia.

  supported.julia = true

  ---@type Loops<Julia>
  M.loops.julia = new_loops()
  find.julia = "for_statement"

  ---@class Julia Loops may be multiple (cartesian products).
  ---@field vars string[]
  ---@field iters string[]

  query.julia = vim.treesitter.query.parse(
    "julia",
    [[
    (for_statement
      (for_binding
        (_) @vars
        (operator)
        (_) @iters
      )
      (block) @body
    )
    ]]
  )

  ---@type Parse<Julia>
  function parse.julia(capt)
    local vars = {}
    local iters = {}
    local name = "for "
    local n ---@type TSNode
    while true do
      n = capt()
      if n:type() ~= "block" then
        local v = P.nodetext(n)
        local i = P.nodetext(capt())
        name = name .. v .. " in " .. i .. ", "
        vars[#vars + 1] = v
        iters[#iters + 1] = i
      else
        break
      end
    end
    return name, {
      vars = vars,
      iters = iters,
    }, n
  end

  ---@type Action<Julia>
  function infiltrate.julia(l)
    local iters = ""
    for _, iter in ipairs(l.data.iters) do
      iters = iters .. iter .. ","
    end
    return string.format(
      [[intim_loop_%i = Iterators.Stateful(zip(%s))]],
      l.id,
      iters
    )
  end

  ---@type Action<Julia>
  function step.julia(l)
    local vars = ""
    for _, var in ipairs(l.data.vars) do
      vars = vars .. var .. ", "
    end
    return string.format([[%s = popfirst!(intim_loop_%i)]], vars, l.id)
  end

  ------------------------------------------------------------------------------
  --- Bring this all together.

  ---@type fun(lang: lang, node: TSNode):TSNode?
  local function do_find(lang, node)
    local target = find[lang]
    while true do
      if node:type() == target then return node end
      local parent = node:parent()
      if not parent then return end
      node = parent
    end
  end

  -- Assuming the input is a loop, parse it into the elements we need.
  ---@type fun(lang: lang, node: TSNode): Loop
  local function do_parse(lang, node)
    local loops = M.loops[lang]
    local from_captures = parse[lang]
    local capts = query[lang]:iter_captures(node, 0)
    local function get_node()
      local _, n, _ = capts()
      return n
    end
    local name, data, body = from_captures(get_node)
    local row, col, _ = body:start()
    local loop = loops.index[name]
    if not loop then
      loop = {
        id = loops.next_id,
        body = { row, col },
        data = data,
      }
      loops.index[name] = loop
      loops.next_id = loops.next_id + 1
    else
      loop.body = { row, col } -- Update in case it has changed.
    end
    return loop
  end

  --- Obtain current node text.
  ---@type fun(node: TSNode):string
  function P.nodetext(node) return vim.treesitter.get_node_text(node, 0, {}) end

  ---@type fun(verbs: Verb[])
  function P.loop_actions(verbs)
    local focal, lang = P.current_node_lang() ---@type TSNode, string
    if not supported[lang] then
      P.err(
        "Loop infiltration not supported for lang " .. vim.inspect(lang) .. "."
      )
      return
    end
    local node = do_find(lang, focal)
    if not node then
      P.err("Not within a loop?")
      return
    end
    local loop = do_parse(lang, node)
    for _, verb in ipairs(verbs) do
      local code = verb[lang](loop)
      if verb == infiltrate then
        local row, col = unpack(loop.body)
        vim.api.nvim_win_set_cursor(0, { row + 1, col })
      end
      M.send_command(code)
    end
  end

  --- Exposed loop primitives.
  function M.infiltrate_loop() P.loop_actions({ infiltrate, step }) end
  function M.step_loop() P.loop_actions({ step }) end
end
