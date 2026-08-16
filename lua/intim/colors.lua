local M = {}
local err = require("intim.errors")

-- Investigate tree-sitter query+highlight?

local lang = "lua"
local ns = vim.api.nvim_create_namespace("intim")
local function clear_all(buf) vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1) end

local q = vim.treesitter.query.parse(
  lang,
  [[;; extends
    ((identifier) @variable.builtin (#set! priority 190))
    ("." @lsp.type.function (#set! priority 190))
  ]]
)

local do_color = nil
local update = function(buf, tree)
  if not do_color then return end
  clear_all(buf)
  for id, node, metadata, match in q:iter_captures(tree:root()) do
    local srow, scol, erow, ecol = node:range()
    vim.api.nvim_buf_set_extmark(buf, ns, srow, scol, {
      end_row = erow,
      end_col = ecol,
      hl_group = "Error",
      priority = 5000,
    })
  end
end

---@alias LanguageTree vim.treesitter.LanguageTree
---@return integer, LanguageTree?
local function get_parser()
  local buf = vim.api.nvim_get_current_buf()
  local parser = vim.treesitter.get_parser(buf, lang)
  if not parser then err.err("no parser found for " .. vim.inspect(lang)) end
  return buf, parser
end

local function start_coloring()
  local buf, parser = get_parser()
  if not parser then return end
  local _, srow, scol, _ = unpack(vim.fn.getpos("w0"))
  local _, erow, ecol, _ = unpack(vim.fn.getpos("w$"))
  local range = { srow, scol, erow, ecol }
  local tree = parser:tree_for_range(range)
  if do_color == nil then -- First time: register callback.
    parser:register_cbs(
      { on_changedtree = function(_, tree) update(buf, tree) end },
      true
    )
  end
  do_color = true
  update(buf, tree)
end

local function end_coloring()
  local buf, parser = get_parser()
  if not parser then return end
  clear_all(buf)
  do_color = false
end

-- DEBUG.
vim.keymap.set({ "n" }, "TT", start_coloring)
vim.keymap.set({ "n" }, "tt", end_coloring)

return M
