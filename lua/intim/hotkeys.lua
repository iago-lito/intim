-- Prepare hotkeys behaviour and configuration.
--- Constant hotkey produce only their value regardless of input.

--- A hotkey combines the key value and user-collected input
--- into an expression that is either passed to intim or inserted in source.
---@alias Hotkey fun(input: string):string
---@alias Keys table<string, Hotkey>
---@type table<lang, Keys>
local hotkeys = {}

--- The strategy to set local lua functions to the operator option.
--- https://github.com/neovim/neovim/issues/18132#issuecomment-1723577603
local set_opfunc = vim.fn[vim.api.nvim_exec2(
  [[
  func s:set_opfunc(val)
    let &opfunc = a:val
  endfunc
  echon get(function('s:set_opfunc'), 'name')
  ]],
  { output = true }
).output]

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
  --- Impl.

  function M.hotkey_send_word(key) P.send_hotkey(key, P.extract_word) end
  function M.hotkey_send_WORD(key) P.send_hotkey(key, P.extract_WORD) end
  function M.hotkey_send_selected(key) P.send_hotkey(key, P.extract_selected) end

  ---@type fun(key: string, extract: fun():string)
  function P.send_hotkey(key, extract)
    local hk = P.hotkey(key)
    if not hk then return end
    local input = extract()
    local cmd = hk(input)
    M.send_command(cmd)
  end

  --- Use `:h map-operator` to edit sources with hotkeys.
  function M.transform_hotkey(key)
    local hk = P.hotkey(key)
    if not hk then return end
    set_opfunc(function(_)
      local srow, scol = unpack(vim.api.nvim_buf_get_mark(0, "["))
      local erow, ecol = unpack(vim.api.nvim_buf_get_mark(0, "]"))
      srow = srow - 1
      erow = erow - 1
      ecol = ecol + 1
      local input = vim.api.nvim_buf_get_text(0, srow, scol, erow, ecol, {})
      local res = hk(P.join(input, "\n"))
      local lines = P.split(res, "\n")
      vim.api.nvim_buf_set_text(0, srow, scol, erow, ecol, lines)
    end)
    vim.api.nvim_feedkeys("g@", "n", false)
  end

  ---@type fun(key: string):Hotkey?
  function P.hotkey(key)
    local lang = P.get_current_lang()
    local hks = M.state.hotkeys[lang]
    if not hks then
      P.err("No Intim hotkey recorded for lang " .. vim.inspect(lang) .. ".")
      return
    end
    local hk = hks[key]
    if not hk then
      P.err(
        "No Intim hotkey recorded as "
          .. vim.inspect(key)
          .. " for lang "
          .. vim.inspect(lang)
          .. "."
      )
      return
    end
    return hk
  end
end
