local TS = {}
local I = require("intim.state")
local on_setup = require("intim.setup").on_setup

--- Obtain current node text.
---@type fun(node: TSNode):string
function TS.nodetext(node) return vim.treesitter.get_node_text(node, 0, {}) end

--- Obtain language under cursor.
--- https://github.com/nvim-treesitter/nvim-treesitter/discussions/6643#discussioncomment-9892537
--- Or fallback to filetype, or nothing.
---@type fun():lang
function TS.current_lang()
  local curline = vim.fn.line(".")
  local parser = vim.treesitter.get_parser()
  if not parser then return vim.o.ft end
  return parser:language_for_range({ curline, 0, curline, 0 }):lang()
end

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

--------------------------------------------------------------------------------
--- Fire an event on every language change.
TS.lang = "" -- State.

---@alias LangChangeCallback fun(now: string, before: string)

---@type LangChangeCallback[]
TS.lang_change_callbacks = {}

on_setup(function()
  local aug = vim.api.nvim_create_augroup("intim-tracklang", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "CursorMoved" }, {
    group = aug,
    callback = function()
      local before = TS.lang
      local now = I.current_lang()
      if before ~= now then
        for _, callback in ipairs(TS.lang_change_callbacks) do
          callback(now, before)
        end
      end
      TS.lang = now
    end,
    desc = "Keep track of cursor changing position.",
  })
end)

--- Register to the language change event.
---@type fun(callback: LangChangeCallback)
function TS.on_lang_change(callback)
  table.insert(TS.lang_change_callbacks, callback)
end

--- Register callbacks when entering/leaving a language.
---@type fun(lang: string, on_enter: fun(), on_leave: fun())
function TS.on_lang(lang, on_enter, on_leave)
  TS.on_lang_change(function(now, _)
    if now == lang then on_enter() end
  end)
  TS.on_lang_change(function(_, before)
    if before == lang then on_leave() end
  end)
end

return TS
