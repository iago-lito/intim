-- Prepare hotkeys behaviour and configuration.
--- Constant hotkey produce only their value regardless of input.

--- A hotkey combines the key value and user-collected input
--- into an expression that is either passed to intim or inserted in source.
---@alias Hotkey fun(input: string):string
---@alias Keys table<string, Hotkey>
---@type table<lang, Keys>
local hotkeys = {}

return function(M, P)
  -- Expose so it may be configured further by user.
  M.state.hotkeys = hotkeys

  ------------------------------------------------------------------------------
  --- Convenience hotkey creation for user.

  --- Constant hotkeys just send the same text regardless of input.
  ---@type fun(constant: string):Hotkey
  hotkeys.constant = function(c)
    return function(_) return c end
  end

  --- Prefix hotkeys send the input with a given prefix.
  ---@type fun(prefix: string):Hotkey
  hotkeys.prefix = function(p)
    return function(i) return p .. i end
  end

  --- Suffix hotkeys send the input with a given suffix.
  ---@type fun(suffix: string):Hotkey
  hotkeys.suffix = function(s)
    return function(i) return i .. s end
  end

  --- Call hotkeys send input under the form `head(input)`, `head[input]` *etc.*
  ---@type fun(head: string, wrap:[string,string]):Hotkey
  hotkeys.call = function(head, wrap)
    local open, close = unpack(wrap or { "(", ")" })
    return function(i) return head .. open .. i .. close end
  end

  --- LaTeX hotkeys send input under the form `\name{input}`.
  ---@type fun(name: string):Hotkey
  hotkeys.latex_macro = function(name)
    return function(i) return "\\" .. name .. "{" .. i .. "}" end
  end

  --- Generic hotkeys send input under the form given by their value
  --- interpreted as a transformation template like `%I = %I.%K()`
  --- where (configurable) placeholders `%I` will be replaced by input
  --- and `%K` replaced by the key payload.
  ---@type fun(value: string, key_placeholder: string?, input_placeholder: string?):Hotkey
  hotkeys.generic = function(value, kp, ip)
    local key_placeholder = kp or "%K"
    local input_placeholder = ip or "%I"
    return function(input)
      return input:gsub(key_placeholder, value):gsub(input_placeholder, input)
    end
  end

  ------------------------------------------------------------------------------

  -- Query hotkey within current lang.
  ---@type fun(key: string):Hotkey
  function P.hotkey(key)
    -- HERE: Investigate why this results in "",
    -- but having LuaLS understand the connections among modules
    -- and recognize this function.
    local lang = P.get_current_lang()
    local hks = M.state.hotkeys[lang]
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
  function P.hotkey_send(hk, get_lines)
    local lines = get_lines()
    local input = P.join(lines, "\n")
    local res = hk(input)
    local cmd = P.split(res, "\n")
    M.send_command(cmd)
  end

  --- Transform in-place within current buffer.
  ---@type HotkeyVerb
  function M.hotkey_transform(hk, get_lines)
    local lines, span = get_lines()
    local srow, scol, erow, ecol = unpack(span)
    local input = P.join(lines, "\n")
    local res = hk(input)
    local rep = P.split(res, "\n")
    vim.api.nvim_buf_set_text(0, srow, scol, erow, ecol, rep)
  end

  --- Input is the selected text.
  ---@type HotkeySource
  function M.hotkey_selected(hk, verb) verb(hk, P.selected_text) end

  --- Input is the user object.
  ---@type HotkeySource
  function M.hotkey_object(hk, verb)
    P.operator(function(_) verb(hk, P.object_text) end)
  end

  -- Combine.
  ---@type [string, HotkeyVerb][]
  local verbs = {
    { "send", M.hotkey_send },
    { "transform", M.hotkey_transform },
  }
  ---@type [string, HotkeySource][]
  local sources = {
    { "object", M.hotkey_object },
    { "selected", M.hotkey_selected },
  }
  for _, i in ipairs(verbs) do
    local vname, verb = unpack(i)
    for _, j in ipairs(sources) do
      local sname, source = unpack(j)
      local fn_name = P.join({ "hotkey", vname, sname }, "_")
      M[fn_name] = P.guard(function(key)
        local hk = P.hotkey(key)
        source(hk, verb)
      end)
    end
  end
end
