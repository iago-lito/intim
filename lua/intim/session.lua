local S = {}
local pass = require("intim.pass")
local err = require("intim.errors").err
local I = require("intim.state")

--- Start tmux session.
function S.spawn()
  local sess = I.session()
  if S.is_session_open() then
    err("Tmux session " .. vim.inspect(sess) .. " already open.")
    return
  end
  -- Request tmux session.
  local spawn = I.tmux.spawn(sess)
  local p = vim.system(spawn)
  -- Wait until it's ready.
  local wait = 500 -- ms.
  local max = 5000 -- ms.
  local acc = 0
  while not S.is_session_open() do
    vim.wait(wait)
    acc = acc + wait
    if acc >= max then
      err(
        "Could not spawn tmux session "
          .. vim.inspect(sess)
          .. " before "
          .. max
          .. "ms were elapsed?"
      )
      local r = p:wait()
      err(
        "retcode: "
          .. r.code
          .. "\nstdout: "
          .. r.stdout
          .. "\nstderr: "
          .. r.stderr
      )
      return
    end
  end
  S.invoke()
end

--- Spawn interpreter.
---@type fun()
function S.invoke()
  local lang = I.current_lang()
  if not lang then
    err("No lang set to pick interpreter?")
    return
  end
  local invoke = I.invoke[lang]
  invoke = type(invoke) == "function" and invoke() or invoke
  if not invoke then
    err(
      "No interpreter invocation command set for lang "
        .. vim.inspect(lang)
        .. "?"
    )
    return
  end
  pass.send_command(invoke)
end

--- Exit interpreter.
function S.revoke() pass.send_eof() end

--- Restart interpreter.
function S.reinvoke()
  S.revoke()
  S.invoke()
end

--- Terminate tmux session.
function S.kill()
  local kill = I.tmux["kill"](I.session())
  vim.system(kill)
end

--- Restart intim.
function S.respawn()
  S.kill()
  S.spawn()
end

--- Obtain current session name.
---@type fun(): string
function I.session() return I.tmux.session end

---@type fun():boolean
function S.is_session_open()
  return vim.system({ "tmux", "has-session", "-t", I.session() }):wait().code
    == 0
end

return S
