--- Use treesitter + lang-specific tricks
--- to infiltrate `for` loops and step them.

local L = {}
local err = require("intim.errors").err
local pass = require("intim.pass")
local ts = require("intim.treesitter")
local I = require("intim.state")

---@type table<lang, boolean>
local supported = {}

---@alias loop_name string
---@alias loop_data any

--- Identify every open loop so as to keep track of them.
---@class Loops<L>
---  @field next_id integer
---  @field index table<loop_name, Loop<L>>
---@type fun(): Loops
function L.new_loops() return { next_id = 0, index = {} } end

---@class Loop<L>
---  @field id integer
---  @field body [integer, integer] (start row/col)
---  @field data L extra data depending on the language.

--- Find loops by climbing up the tree until a special `for` node is reached.
---@alias LoopFind string (nodename)
---@type table<lang, LoopFind>
I.find = {}

--- One query per lang to obtain the relevant loop parts from a loop node.
---@type table<lang, vim.treesitter.Query>
I.query = {}

--- Given captures from the query above, return a name and loop data.
--- Return an identifier for the loop, the lang-specific data and the body node.
---@alias NextCapture fun():TSNode
---@alias Parse<L> fun(node: NextCapture): loop_name, L, TSNode
---@type table<lang, Parse>
I.parse = {}

--- Exposed actions for user.
---@alias Action<L> fun(loop: Loop<L>): string
---@alias Verb table<lang, Action<L>>

-- Generate a coroutine with this loop, ready to be stepped.
---@type Verb
I.infiltrate = {}

--- Generate code to step the given loop.
---@type Verb
I.step = {}

-- Expose so it may be configured further by user.
---@type table<lang, Loops>
I.loops = {}

------------------------------------------------------------------------------
--- Lua loops.

supported.lua = true

---@type Loops<Lua>
I.loops.lua = L.new_loops()
I.find.lua = "for_statement"

---@class Lua
---  @field clause string
---  @field vars string

I.query.lua = vim.treesitter.query.parse(
  "lua",
  [[
      (for_statement clause: [
          (for_generic_clause (variable_list) @vars) @clause
          (for_numeric_clause name: (_) @vars) @clause
       ] body: (_) @body)
    ]]
)

---@type Parse<Lua>
function I.parse.lua(capt)
  local clause = ts.nodetext(capt())
  local vars = ts.nodetext(capt())
  local name = "for " .. clause .. " do"
  local body = capt()
  return name, {
    clause = clause,
    vars = vars,
  }, body
end

---@type Action<Lua>
function I.infiltrate.lua(l)
  return string.format(
    [[
%sintim_loop_%i = coroutine.create(function()
  for %s do coroutine.yield(%s) end
  error()
end)
      ]],
    I.lua.use_locals and "local " or "",
    l.id,
    l.data.clause,
    l.data.vars
  )
end

---@type Action<Lua>
function I.step.lua(l)
  return string.format(
    [[
%sintim_loop_status, %s = coroutine.resume(intim_loop_%i)
if not intim_loop_status then error("Intim iteration ended for loop %i.") end
    ]],
    I.lua.use_locals and "local " or "",
    l.data.vars,
    l.id,
    l.id
  )
end

------------------------------------------------------------------------------
--- Python loops.

supported.python = true

---@type Loops<Python>
I.loops.python = L.new_loops()
I.find.python = "for_statement"

---@class Python
---  @field vars string
---  @field iter string

I.query.python = vim.treesitter.query.parse(
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
function I.parse.python(capt)
  local vars = ts.nodetext(capt())
  local iter = ts.nodetext(capt())
  local name = "for " .. vars .. " in " .. iter .. ":"
  local body = capt()
  return name, {
    vars = vars,
    iter = iter,
  }, body
end

---@type Action<Python>
function I.infiltrate.python(l)
  return string.format([[intim_loop_%i = iter(%s)]], l.id, l.data.iter)
end

---@type Action<Python>
function I.step.python(l)
  return string.format([[%s = next(intim_loop_%i)]], l.data.vars, l.id)
end

------------------------------------------------------------------------------
--- Julia.

supported.julia = true

---@type Loops<Julia>
I.loops.julia = L.new_loops()
I.find.julia = "for_statement"

---@class Julia Loops may be multiple (cartesian products).
---@field vars string[]
---@field iters string[]

I.query.julia = vim.treesitter.query.parse(
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
function I.parse.julia(capt)
  local vars = {} ---@type string[]
  local iters = {} ---@type string[]
  local name = "for "
  local n ---@type TSNode
  while true do
    n = capt()
    if n:type() ~= "block" then
      local v = ts.nodetext(n)
      local i = ts.nodetext(capt())
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
function I.infiltrate.julia(l)
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
function I.step.julia(l)
  local vars = ""
  for _, var in ipairs(l.data.vars) do
    vars = vars .. var .. ", "
  end
  return string.format([[%s = popfirst!(intim_loop_%i)]], vars, l.id)
end

------------------------------------------------------------------------------
--- R.

supported.r = true

---@type Loops<R>
I.loops.r = L.new_loops()
I.find.r = "for_statement"

---@class R
---@field var string
---@field iter string

I.query.r = vim.treesitter.query.parse(
  "r",
  [[
    (for_statement
      variable: (_) @var
      sequence: (_) @iter
      body: (_) @body
    )
    ]]
)

--- Need additional query to skip comments in braced loops.
I.query.r_braced_body =
  vim.treesitter.query.parse("r", [[ (braced_expression body: (_) @braced) ]])

---@type Parse<R>
function I.parse.r(capt)
  local var = ts.nodetext(capt())
  local iter = ts.nodetext(capt())
  local body = capt()
  -- Skip comments further in case the body is a braced expression.
  if body:type() == "braced_expression" then
    _, body, _ = I.query.r_braced_body:iter_captures(body, 0)()
  end
  local name = "for (" .. var .. " in " .. iter .. ")"
  return name, {
    var = var,
    iter = iter,
  }, body
end

---@type Action<R>
function I.infiltrate.r(l)
  return string.format(
    [=[
intim_loop_%s <- base::as.environment(base::list(coll = %s, i = 0, step = function() {
  e <- intim_loop_%s; if (e$i < base::length(e$coll)) { e$i <- e$i + 1; e$coll[[e$i]] }
  else { stop("Iteration ended.") }
}))
      ]=],
    l.id,
    l.data.iter,
    l.id
  )
end

---@type Action<R>
function I.step.r(l)
  return string.format([[%s <- intim_loop_%s$step()]], l.data.var, l.id)
end

------------------------------------------------------------------------------
--- Bring this all together.

---@type fun(lang: lang, node: TSNode):TSNode?
local function do_find(lang, node)
  local target = I.find[lang]
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
  local loops = I.loops[lang]
  local from_captures = I.parse[lang] ---@type Parse<any>
  local q = I.query[lang]
  local capts = q:iter_captures(node, 0)
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

---@type fun(verbs: Verb[])
function L.actions(verbs)
  local focal, lang = ts.current_node_lang() ---@type TSNode, string
  if not supported[lang] then
    err("Loop infiltration not supported for lang " .. vim.inspect(lang) .. ".")
    return
  end
  local node = do_find(lang, focal)
  if not node then
    err("Not within a loop?")
    return
  end
  local loop = do_parse(lang, node)
  for _, verb in ipairs(verbs) do
    local code = verb[lang](loop)
    if verb == I.infiltrate then
      local row, col = unpack(loop.body)
      vim.api.nvim_win_set_cursor(0, { row + 1, col })
    end
    pass.send_command(code)
  end
end

--- Exposed loop primitives.
function L.infiltrate() L.actions({ I.infiltrate, I.step }) end
function L.step() L.actions({ I.step }) end

return L
