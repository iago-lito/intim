local M = {}
local str = require("intim.strings")
local err = require("intim.errors")
local I = require("intim.state")

---@alias Query vim.treesitter.Query

--------------------------------------------------------------------------------
--- Retrieve (root) identifiers and paths like `a.b.c`.

---@alias Paths table<string, boolean> Store as unique "a.b.c" chains.
---@alias Identifiers table<string, boolean> The `a` in the above, or just `d`.

local queries = {
  ids = [[;query
    ((identifier) @id
    (#not-has-parent? @id dot_index_expression))
  ]],
  paths = [[;query
    ((dot_index_expression) @path
      (#not-has-parent? @path dot_index_expression))
  ]],
}
for k, p in pairs(queries) do
  ---@cast queries table<string, Query>
  queries[k] = vim.treesitter.query.parse("lua", p)
end

---@return Identifiers, Paths
function M.collect()
  local tree = vim.treesitter.get_parser():parse()[1]:root()
  ---@type fun(node:TSNode):string
  local function text(node) return vim.treesitter.get_node_text(node, 0, {}) end
  local roots = {} ---@type Identifiers
  local paths = {} ---@type Paths
  for _, node, _, _ in queries.ids:iter_captures(tree, 0) do
    local name = text(node)
    roots[name] = true
  end
  for _, node, _, _ in queries.paths:iter_captures(tree, 0) do
    -- Check path for identifier-purity:
    -- chains like a.b.c.method_call().d.e are truncated.
    -- The `a.b.c` path should have been independently captured.
    local full = text(node)
    local impure = false
    local root ---@type string
    while true do
      if node:type() == "identifier" then
        root = text(node)
        break
      end
      if node:type() ~= "dot_index_expression" then
        impure = true
        break
      end
      local child = node:child(0) ---@cast child -?
      node = child
    end
    if not impure then
      roots[root] = true
      paths[full] = true
    end
  end
  vim.print("roots: " .. vim.inspect(roots))
  vim.print("paths: " .. vim.inspect(paths))
  return roots, paths
end

--------------------------------------------------------------------------------
-- Color using this.. weird trick?
-- https://github.com/neovim/neovim/issues/41354

local intim_patterns ---@type integer[]
local toggle_counter = 0

---@type fun(_: lang):Query?
local function get_query()
  local lang = I.current_lang()
  local q = vim.treesitter.query.get(lang, "highlights")
  if not q then
    err.err("No query file found for " .. vim.inspect(lang) .. ".")
  end
  return q
end

local function start_coloring()
  local lang = I.current_lang()
  local current = get_query(lang)
  if not current then return end
  local pats = current.info.patterns
  local last_pattern = 0
  for k, _ in pairs(pats) do
    last_pattern = k
  end
  local q = [[;query
    ;; extends
    ((identifier) @variable.builtin (#set! priority 190))
    ("." @lsp.type.function (#set! priority 190))
  ]]
  -- https://github.com/neovim/neovim/issues/41352
  q = str.dedent(str.remove_prefix(";query\n", q))

  -- https://github.com/neovim/neovim/issues/41354
  if intim_patterns == nil then
    local n_intim_patterns = #vim.treesitter.query.parse(lang, q).info.patterns
    intim_patterns = {}
    for i = 1, n_intim_patterns do
      table.insert(intim_patterns, last_pattern + i)
    end
  else
    q = q .. "\n;toggle-" .. toggle_counter
    toggle_counter = toggle_counter + 1
  end

  vim.treesitter.query.set(lang, "highlights", q)
  vim.treesitter.stop(0)
  vim.treesitter.start(0, lang)
end

local function end_coloring()
  local lang = I.current_lang()
  local q = get_query(lang)
  if not q then return end
  for _, pat in ipairs(intim_patterns) do
    q.query:disable_pattern(pat)
  end
  vim.treesitter.stop(0)
  vim.treesitter.start(0, lang)
end

-- DEBUG.
vim.keymap.set({ "n" }, "UP", M.collect)
vim.keymap.set({ "n" }, "TT", start_coloring)
vim.keymap.set({ "n" }, "tt", end_coloring)

return M
