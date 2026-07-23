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
--- Fire an event on every language change and/or buffer change.
TS.lang = "" -- State.
TS.buf = 0

---@alias LangChangeCallback fun(now: string, before: string)
---@alias BufLangChangeCallback fun(lang_now: string, lang_before: string,
---                                 buf_now: integer, buf_before: integer)

---@type LangChangeCallback[]
TS.lang_change_callbacks = {}
---@type BufLangChangeCallback[]
TS.buflang_change_callbacks = {}

on_setup(function()
  local aug = vim.api.nvim_create_augroup("intim-tracklang", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "CursorMoved" }, {
    group = aug,
    callback = function()
      local lang_before = TS.lang
      local buf_before = TS.buf
      local lang_now = I.current_lang()
      local buf_now = vim.api.nvim_get_current_buf()
      local newlang = lang_before ~= lang_now
      local newbuf = buf_before ~= buf_now
      if newlang then
        for _, callback in ipairs(TS.lang_change_callbacks) do
          callback(lang_now, lang_before)
        end
      end
      if newlang or newbuf then
        for _, callback in ipairs(TS.buflang_change_callbacks) do
          callback(lang_now, lang_before, buf_now, buf_before)
        end
      end
      TS.lang = lang_now
      TS.buf = buf_now
    end,
    desc = "Keep track of cursor changing position.",
  })
end)

--- Register to the language change event.
---@type fun(callback: LangChangeCallback)
function TS.on_lang_change(callback)
  table.insert(TS.lang_change_callbacks, callback)
end
---@type fun(callback: BufLangChangeCallback)
function TS.on_buflang_change(callback)
  table.insert(TS.buflang_change_callbacks, callback)
end

--- Register callbacks when entering/leaving a language.
---@type fun(lang: string, on_enter: fun(), on_leave: fun())
function TS.on_lang(lang, on_enter, on_leave)
  TS.on_lang_change(function(now)
    if now == lang then
      on_enter()
    else
      on_leave()
    end
  end)
end

--- Register callbacks when entering/leaving a (buffer, language) pair.
---@param lang string
---@param on_enter fun(bufn: integer)
---@param on_leave fun(bufn: integer)
function TS.on_buflang(lang, on_enter, on_leave)
  TS.on_buflang_change(function(ln, lb, bn, bb)
    if lb == lang then on_leave(bb) end
    if ln == lang then on_enter(bn) end
  end)
end

return TS
