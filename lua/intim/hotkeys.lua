-- Prepare hotkeys behaviour and configuration.
--- Constant hotkey produce only their value regardless of input.

local HK = {}
local I = require("intim.state")
local str = require("intim.strings")
local err = require("intim.errors")
local pass = require("intim.pass")

--- A hotkey combines the key value and user-collected input
--- into an expression that is either passed to intim or inserted in source.
---@alias Hotkey fun(input: string):string
---@alias Keys table<string, Hotkey>
---@type table<lang, Keys>
I.hotkeys = {}

------------------------------------------------------------------------------
--- Convenience hotkey creation for user.

--- Constant hotkeys just send the same text regardless of input.
---@type fun(constant: string):Hotkey
I.hotkeys.constant = function(c)
  return function(_) return c end
end

--- Prefix hotkeys send the input with a given prefix.
---@type fun(prefix: string):Hotkey
I.hotkeys.prefix = function(p)
  return function(i) return p .. i end
end

--- Suffix hotkeys send the input with a given suffix.
---@type fun(suffix: string):Hotkey
I.hotkeys.suffix = function(s)
  return function(i) return i .. s end
end

--- Call hotkeys send input under the form `head(input)`, `head[input]` *etc.*
---@type fun(head: string, wrap:[string,string]):Hotkey
I.hotkeys.call = function(head, wrap)
  local open, close = unpack(wrap or { "(", ")" })
  return function(i) return head .. open .. i .. close end
end

--- LaTeX hotkeys send input under the form `\name{input}`.
---@type fun(name: string):Hotkey
I.hotkeys.latex_macro = function(name)
  return function(i) return "\\" .. name .. "{" .. i .. "}" end
end

--- Generic hotkeys send input under the form given by their value
--- interpreted as a transformation template like `%I = %I.%K()`
--- where (configurable) placeholders `%I` will be replaced by input
--- and `%K` replaced by the key payload.
---@type fun(value: string, key_placeholder: string?, input_placeholder: string?):Hotkey
I.hotkeys.generic = function(value, kp, ip)
  local key_placeholder = kp or "%K"
  local input_placeholder = ip or "%I"
  return function(input)
    return input:gsub(key_placeholder, value):gsub(input_placeholder, input)
  end
end

------------------------------------------------------------------------------

-- Query hotkey within current lang.
---@type fun(key: string):Hotkey
function HK.hotkey(key)
  local lang = I.current_lang()
  local hks = I.hotkeys[lang]
  if not hks then
    error("No Intim hotkey recorded for lang " .. vim.inspect(lang) .. ".")
  end
  local hk = hks[key]
  if not hk then
    error(
      "No Intim hotkey recorded as "
        .. vim.inspect(key)
        .. " for lang "
        .. vim.inspect(lang)
        .. "."
    )
  end
  return hk
end

--- Given a mean to retrieve lines, execute the hotkey action.
---@alias HotkeyVerb fun(hk: Hotkey, get_lines: GetLinesSpan)

--- Given a verb, execute from the correct input source.
---@alias HotkeySource fun(hk: Hotkey, v: HotkeyVerb)

--- Transform and send result.
---@type HotkeyVerb
function HK.send(hk, get_lines)
  local lines = get_lines()
  local input = str.join(lines, "\n")
  local cmd = hk(input)
  pass.send_command(cmd)
end

--- Transform in-place within current buffer.
---@type HotkeyVerb
function HK.transform(hk, get_lines)
  local lines, span = get_lines()
  local srow, scol, erow, ecol = unpack(span)
  local input = str.join(lines, "\n")
  local res = hk(input)
  local rep = str.split(res, "\n")
  vim.api.nvim_buf_set_text(0, srow, scol, erow, ecol, rep)
end

--- Input is the selected text.
---@type HotkeySource
function HK.selected(hk, verb) verb(hk, pass.selected_text) end

--- Input is the user object.
---@type HotkeySource
function HK.object(hk, verb)
  pass.operator(function(_) verb(hk, pass.object_text) end)
end

-- Combine.
---@param source HotkeySource
---@param verb HotkeyVerb
---@return fun(hk: Hotkey)
local function combine(verb, source)
  return function(hk) source(hk, verb) end
end

HK.send_object = combine(HK.send, HK.object)
HK.send_selected = combine(HK.send, HK.selected)
HK.transform_object = combine(HK.transform, HK.object)
HK.transform_selected = combine(HK.transform, HK.selected)

return HK
