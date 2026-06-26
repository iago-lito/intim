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

-- The exposed, configurable "Intim" state.
local I = require("intim.state")
I.setup = B.setup.setup
I.spawn = B.session.spawn
I.kill = B.session.kill

I.send = {}
I.send.invoke = B.session.invoke
I.send.revoke = B.session.revoke
I.send.enter = B.pass.send_enter
I.send.interrupt = B.pass.send_interrupt
I.send.eof = B.pass.send_eof
I.send.line = B.pass.send_line
I.send.selected = B.pass.send_selected
I.send.statement = B.statement.send
I.send.hotkey = {
  object = B.hotkeys.send_object,
  selected = B.hotkeys.send_selected,
}

I.loop = {}
I.loop.infiltrate = B.loop.infiltrate
I.loop.step = B.loop.step

-- Expose internals to ease debugging.
I.internals = B

return I
