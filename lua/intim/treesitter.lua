local TS = {}
local I = require("intim.state")

--- Obtain current node text.
---@type fun(node: TSNode):string
function TS.nodetext(node) return vim.treesitter.get_node_text(node, 0, {}) end

---@type fun(): TSNode, string
function TS.current_node_lang()
  local lang = I.current_lang()
  vim.treesitter.get_parser(0):parse()
  if vim.fn.col("$") <= vim.fn.col(".") then
    -- Return back to actual content if the cursor lies past EOL.
    vim.cmd.normal("$")
  end
  local node = vim.treesitter.get_node()
  if not node then error("No TSNode found at given location.") end
  return node, lang
end

return TS
