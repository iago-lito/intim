local B = {} -- (base, internal, root module)

B.str = require("intim.strings")
B.err = require("intim.errors")
B.setup = require("intim.setup")
B.session = require("intim.session")
B.pass = require("intim.pass")
B.chunk = require("intim.chunk")
B.ts = require("intim.treesitter")
B.statement = require("intim.statement")
B.loop = require("intim.loop")
B.hotkeys = require("intim.hotkeys")
B.colors = require("intim.colors")

-- The exposed, configurable "Intim" state.
local I = require("intim.state")
I.setup = B.setup.setup
I.spawn = B.session.spawn
I.kill = B.session.kill

I.send = {
  invoke = B.session.invoke,
  revoke = B.session.revoke,
  enter = B.pass.send_enter,
  interrupt = B.pass.send_interrupt,
  eof = B.pass.send_eof,
  line = B.pass.send_line,
  selected = B.pass.send_selected,
  statement = B.statement.send,
  chunk = B.chunk.send,
}

I.loop = {
  infiltrate = B.loop.infiltrate,
  step = B.loop.step,
}

I.hotkeys = B.hotkeys

-- Extra utils.
I.current_lang = B.ts.current_lang
I.on_lang_change = B.ts.on_lang_change
I.on_lang = B.ts.on_lang

-- Expose internals to ease debugging.
I.internals = B

return I
