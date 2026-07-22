-- Prepare hotkeys behaviour and configuration.
--- Constant hotkey produce only their value regardless of input.

local HK = {}
local str = require("intim.strings")
local pass = require("intim.pass")
local err = require("intim.errors")

--- A hotkey combines the key value and user-collected input
--- into an expression that is either passed to intim or inserted in source.
---@class Hotkey
---@field name string
---@field call HotKeyCall
---@field proof any
---@alias HotKeyCall fun(input: string):string

local hotkey, _, check_hotkey = err.stamp("hotkey")

-- Convenience 'make hotkey'.
---@type fun(name: string, call: HotKeyCall):Hotkey
local function mkhk(name, call)
  return { name = name, call = call, proof = hotkey }
end

------------------------------------------------------------------------------
--- Convenience hotkey creation for user.

--- Constant hotkeys just send the same text regardless of input.
---@type fun(constant: string):Hotkey
HK.constant = function(c)
  return mkhk("constant", function(_) return c end)
end

--- Prefix hotkeys send the input with a given prefix.
---@type fun(prefix: string):Hotkey
HK.prefix = function(p)
  return mkhk("prefix", function(i) return p .. i end)
end

--- Suffix hotkeys send the input with a given suffix.
---@type fun(suffix: string):Hotkey
HK.suffix = function(s)
  return mkhk("suffix", function(i) return i .. s end)
end

--- Call hotkeys send input under the form `head(input)`, `head[input]` *etc.*
---@type fun(head: string, wrap:[string,string]):Hotkey
HK.call = function(head, wrap)
  local open, close = unpack(wrap or { "(", ")" })
  return mkhk(
    "call" .. open .. close,
    function(i) return head .. open .. i .. close end
  )
end

--- LaTeX hotkeys send input under the form `\name{input}`.
---@type fun(name: string):Hotkey
HK.latex_macro = function(name)
  return mkhk(
    "latex macro",
    function(i) return "\\" .. name .. "{" .. i .. "}" end
  )
end

--- Generic hotkeys send input under the form given by their value
--- interpreted as a transformation template like `%I = %I.%K()`
--- where (configurable) placeholders `%I` will be replaced by input
--- and `%K` replaced by the key payload.
---@type fun(value: string, key_placeholder: string?, input_placeholder: string?):Hotkey
HK.generic = function(value, kp, ip)
  local key_placeholder = kp or "%K"
  local input_placeholder = ip or "%I"
  return mkhk("generic " .. vim.inspect(value), function(input)
    local res =
      input:gsub(key_placeholder, value):gsub(input_placeholder, input)
    return res
  end)
end

------------------------------------------------------------------------------

--- Given a mean to retrieve lines, execute the hotkey action.
---@class HotkeyVerb
---@field name string
---@field call HotkeyVerbCall
---@field proof table
---@alias HotkeyVerbCall fun(hk: Hotkey, get_lines: GetLinesSpan)

local verb_proof, _, check_verb = err.stamp("verb")
---@type fun(name: string, call: HotkeyVerbCall):HotkeyVerb
local function mkverb(name, call)
  return { name = name, call = call, proof = verb_proof }
end

--- Given a verb, execute from the correct input source.
---@class HotkeySource
---@field name string
---@field call HotkeySourceCall
---@field proof table
---@alias HotkeySourceCall fun(hk: Hotkey, v: HotkeyVerb)

local source_proof, _, check_source = err.stamp("source")
---@type fun(name:string, call: HotkeySourceCall):HotkeySource
local function mksource(name, call)
  return { name = name, call = call, proof = source_proof }
end

--- Transform and send result.
---@type HotkeyVerb
HK.send = mkverb("send", function(hk, get_lines)
  local lines = get_lines()
  local input = str.join(lines, "\n")
  local cmd = hk.call(input)
  pass.send_command(cmd)
end)

--- Transform in-place within current buffer.
---@type HotkeyVerb
HK.transform = mkverb("transform", function(hk, get_lines)
  local lines, span = get_lines()
  local srow, scol, erow, ecol = unpack(span)
  local input = str.join(lines, "\n")
  local res = hk.call(input)
  local rep = str.split(res, "\n")
  vim.api.nvim_buf_set_text(0, srow, scol, erow, ecol, rep)
end)

--- Input is the selected text.
---@type HotkeySource
HK.selected = mksource("selected", function(hk, verb)
  verb.call(hk, pass.selected_text)
  -- Then exit visual mode and navigate to the start of result.
  vim.cmd.normal({ vim.keycode("<esc>`<"), bang = true })
end)

--- Input is the user next textobject.
---@type HotkeySource
HK.object = mksource("object", function(hk, verb)
  pass.operator(function(_) verb.call(hk, pass.object_text) end)
end)

-- Input is the word under cursor.
---@type HotkeySource
HK.word = mksource("word", function(hk, verb)
  HK.object(hk, verb)
  vim.api.nvim_feedkeys("iw", "n", false) -- Don't remap
end)

--- Construct a source for an arbitrary given custom object.
---@type fun(object: string):HotkeySource
function HK.thisobject(object)
  return mksource("object " .. vim.inspect(object), function(hk, verb)
    HK.object(hk, verb)
    vim.api.nvim_feedkeys(object, "m", true) -- Remap because input by user.
  end)
end

-- Combine into a mapping.
---@param verb HotkeyVerb
---@param source HotkeySource
---@param hk Hotkey
---@return fun() -- Ready to be mapped.
function HK.action(verb, source, hk)
  check_verb(verb)
  check_source(source)
  check_hotkey(hk)
  return function() source.call(hk, verb) end
end

--------------------------------------------------------------------------------
-- Assuming hotkeys will be handled the same, convenience bulk mapping.

--- Define mappings for the actions given as prefixes.
---@param prefixes [string, HotkeyVerb, HotkeySource][]
---@param hotkeys table<string, Hotkey>
---@param loc boolean? -- Lower to get global mappings instead.
function HK.prefixed(prefixes, hotkeys, loc)
  if loc == nil then loc = true end
  for _, p in ipairs(prefixes) do
    local prefix, verb, source = unpack(p)
    check_verb(verb)
    check_source(source)
    for key, hk in pairs(hotkeys) do
      err.check_string(key)
      check_hotkey(hk)
      local map = prefix .. key
      local mode = source == HK.selected and "v" or "n"
      local opt = { desc = "intim: " .. verb.name .. " " .. source.name }
      if loc then opt.buf = 0 end
      vim.keymap.set(mode, map, function() source.call(hk, verb) end, opt)
    end
  end
end

return HK
