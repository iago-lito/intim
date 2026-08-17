local M = {}
local str = require("intim.strings")
local err = require("intim.errors")

local lang = "lua"

-- Implement using this.. weird trick?
-- https://github.com/neovim/neovim/issues/41354
local intim_patterns ---@type integer[]
local toggle_counter = 0

---@alias Query vim.treesitter.Query
---@type fun(_: lang):Query?
local function get_query(lang)
  local q = vim.treesitter.query.get(lang, "highlights")
  if not q then
    err.err("No query file found for " .. vim.inspect(lang) .. ".")
  end
  return q
end

local function start_coloring()
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
  local q = get_query(lang)
  if not q then return end
  for _, pat in ipairs(intim_patterns) do
    q.query:disable_pattern(pat)
  end
  vim.treesitter.stop(0)
  vim.treesitter.start(0, lang)
end

-- DEBUG.
vim.keymap.set({ "n" }, "TT", start_coloring)
vim.keymap.set({ "n" }, "tt", end_coloring)

return M
