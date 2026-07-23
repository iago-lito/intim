-- Prepare hotkeys behaviour and configuration.
--- Constant hotkey produce only their value regardless of input.

local HK = {}
local str = require("intim.strings")
local pass = require("intim.pass")
local err = require("intim.errors")
local ts = require("intim.treesitter")

--- A hotkey combines the key value and user-collected input
--- into an expression that is either passed to intim or inserted in source.
---@alias HKCall fun(input: string):string

--- Given a mean to retrieve lines, execute the hotkey action.
---@alias HKVerbCall fun(hk: Hotkey, get_lines: GetLinesSpan)

--- Given a verb, execute from the correct input source.
---@alias HKSourceCall fun(hk: Hotkey, v: HKVerb)

-- Wrap into an object with identity and proof of kind.
---@class HK<Call>
---@field name string
---@field call Call
---@field proof table

---@class Hotkey : HK<HKCall>
---@class HKVerb : HK<HKVerbCall>
---@class HKSource : HK<HKSourceCall>

-- All share a common interface.
---@class HKMethods<Call>
---@field is fun(input: any):boolean -- Test kind.
---@field check fun(input:any) -- Enforce kind.
---@field make fun(name: string, call: Call):HK<Call>
---@type fun(kind: string):HKMethods
local function methods(kind)
  local proof, is, check = err.stamp(kind)
  return {
    is = is,
    check = check,
    make = function(name, call)
      return { name = name, call = call, proof = proof }
    end,
  }
end

---@type HKMethods<HKCall>
local hotkey = methods("hotkey")

---@type HKMethods<HKVerbCall>
local verb = methods("verb")

---@type HKMethods<HKSourceCall>
local source = methods("source")

--------------------------------------------------------------------------------
--- Expose hotkey constructors to user.

--- Constant hotkeys just send the same text regardless of input.
---@type fun(constant: string):Hotkey
HK.constant = function(c)
  return hotkey.make("constant", function(_) return c end)
end

--- Prefix hotkeys send the input with a given prefix.
---@type fun(prefix: string):Hotkey
HK.prefix = function(p)
  return hotkey.make("prefix", function(i) return p .. i end)
end

--- Suffix hotkeys send the input with a given suffix.
---@type fun(suffix: string):Hotkey
HK.suffix = function(s)
  return hotkey.make("suffix", function(i) return i .. s end)
end

--- Call hotkeys send input under the form `head(input)`, `head[input]` *etc.*
---@type fun(head: string, wrap:[string,string]):Hotkey
HK.call = function(head, wrap)
  local open, close = unpack(wrap or { "(", ")" })
  return hotkey.make(
    "call" .. open .. close,
    function(i) return head .. open .. i .. close end
  )
end

--- LaTeX hotkeys send input under the form `\name{input}`.
---@type fun(name: string):Hotkey
HK.latex_macro = function(name)
  return hotkey.make(
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
  return hotkey.make("generic " .. vim.inspect(value), function(input)
    local res =
      input:gsub(key_placeholder, value):gsub(input_placeholder, input)
    return res
  end)
end

--------------------------------------------------------------------------------
--- Expose predefined verbs.

--- Transform and send result.
---@type HKVerb
HK.send = verb.make("send", function(hk, get_lines)
  local lines = get_lines()
  local input = str.join(lines, "\n")
  local cmd = hk.call(input)
  pass.send_command(cmd)
end)

--- Transform in-place within current buffer.
---@type HKVerb
HK.transform = verb.make("transform", function(hk, get_lines)
  local lines, span = get_lines()
  local srow, scol, erow, ecol = unpack(span)
  local input = str.join(lines, "\n")
  local res = hk.call(input)
  local rep = str.split(res, "\n")
  vim.api.nvim_buf_set_text(0, srow, scol, erow, ecol, rep)
end)

--------------------------------------------------------------------------------
--- Expose predefined sources.

--- Input is the selected text.
---@type HKSource
HK.selected = source.make("selected", function(hk, vrb)
  vrb.call(hk, pass.selected_text)
  -- Then exit visual mode and navigate to the start of result.
  vim.cmd.normal({ vim.keycode("<esc>`<"), bang = true })
end)

--- Input is the user next textobject.
---@type HKSource
HK.object = source.make("object", function(hk, vrb)
  pass.operator(function(_) vrb.call(hk, pass.object_text) end)
end)

-- Input is the word under cursor.
---@type HKSource
HK.word = source.make("word", function(hk, vrb)
  HK.object.call(hk, vrb)
  vim.api.nvim_feedkeys("iw", "n", false) -- Don't remap
end)

--- Construct a source for an arbitrary given custom object.
---@type fun(object: string):HKSource
function HK.thisobject(object)
  return source.make("object " .. vim.inspect(object), function(hk, vrb)
    HK.object.call(hk, vrb)
    vim.api.nvim_feedkeys(object, "m", true) -- Remap because input by user.
  end)
end

--------------------------------------------------------------------------------
-- Combine into a single mapping.
---@param vrb HKVerb
---@param src HKSource
---@param hk Hotkey
---@return fun() -- Ready to be mapped.
function HK.action(vrb, src, hk)
  verb.check(vrb)
  source.check(src)
  hotkey.check(hk)
  return function() src.call(hk, vrb) end
end

--------------------------------------------------------------------------------
-- Assuming hotkeys will be handled the same, convenience bulk mapping.

--- Define mappings for the actions given as prefixes.
---@param lang lang
---@param prefixes [string, HKVerb, HKSource][]
---@param hotkeys table<string, Hotkey>
function HK.prefixed(lang, prefixes, hotkeys)
  -- Collect all mappings info a cached table to avoid on_lang churn.
  local collect = {} ---@type [string, string, fun(), table][]
  for _, p in ipairs(prefixes) do
    local prefix, vrb, src = unpack(p)
    verb.check(vrb)
    source.check(src)
    for key, hk in pairs(hotkeys) do
      err.check_string(key)
      hotkey.check(hk)
      local map = prefix .. key
      local mode = src == HK.selected and "v" or "n"
      local opt = { desc = "intim: " .. vrb.name .. " " .. src.name }
      local fn = function() src.call(hk, vrb) end
      table.insert(collect, { mode, map, fn, opt })
    end
  end
  --- Map/unmap depending on current lang.
  ts.on_buflang(lang, function(bufnr)
    for _, m in pairs(collect) do
      local mode, map, fn, opt = unpack(m)
      opt.buf = bufnr
      vim.keymap.set(mode, map, fn, opt)
    end
  end, function(bufnr)
    for _, m in pairs(collect) do
      local mode, map, _, opt = unpack(m)
      opt.buf = bufnr
      vim.keymap.del(mode, map, opt)
    end
  end)
end

return HK
