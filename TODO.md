Find work here

Improvements:
-------------

- [ ] make doc tags more fleshed (all function names *etc.*) and their layout
  more consistent (tags bunches: where, how, why? lining up).
- [ ] make function names more consistent `IntimInvokeCommand` *vs.*
`IntimGetInvokeCommand` for instance.. or `IntimSetInvokeCommand`.
- [ ] guard: do not send python/R command if the interpreter has not been invoked
or has been exited()
- [ ] enable syntax coloring in pdb debug mode


Bugs:
-----

- [ ] This dot seems to be considered a navigation dot, so `identifier` is not
colored:

    # comment.
    identifier

- [ ] bunch of remapping errors when opening a new LaTeX file from a LaTeX file!

- [ ] Here, `np` seems not lexed:

        """docstring
        """
        import numpy as np # for scientific calculation
        EOF

- [ ] Known weird bug with successive object members.. investigate:

        class Test():
            def __init__(self, member):
                self.member = member

        test = Test(Test(Test(Test(Test(45)))))
        test.member
        test.member.member
        test.member.member.member
        test.member.member.member.member # here it starts
        test.member.member.member.member.member
        test.member.member.member.member.member.member # undefined, okay.


Feature requests:
-----------------

### Easy ones

- [ ] add utility to send line *with* indentation if desired, see #11
- [ ] explicit that `nmap` command could be set in `.vimrc` for "noobs like me",
    cheers to Vincent
- [ ] provide utilities to get into loops: for `python` (done) and `R` (trickier)
- [ ] add another placeholder like `%f` in hotkeys expressions to insert filenames
    - [ ] this will help making a neater implementation of default LaTeX commands.
- [ ] tex constant expression hotkeys behaviour should be less word-based
- [ ] keep "last change" fields up to date with a git hook
- [ ] style consistency
 - [ ] Comments with capitals and dots.
 - [ ] indentation 2 spaces.. hm but I'm still unsure..
- [ ] Rewrite `plugin/intim.vim` introduction

### Bigger ones

- [ ] add explicit utilities for `bash` interpreter, does anyone know bash well?
- [ ] disable simple sending for compiled language (LaTeX, Rust, ..), which make
  no sense.
- [ ] ssh option? sending commands *via* is not difficult, but sending
  chunk/help/color files could be something.. maybe easy with sshfs?
- [ ] Yeaah! check out new features at
  [Vim-R](https://github.com/jalvesaq/Nvim-R) :) TCP connections would feel
  great! ^ ^ Try'em out!
- [ ] rewrite `syntax.R` with new `syntax.py` logic
    - parse `R` script and only query `R` for used tokens
    - accordingly, color `list$name` constructs iif they are defined, just like
      `object.attribute` in `python`
- [ ] provide full syntax files instead of working around already defined groups.
    grep `pythonFunction` to see the problem, which may occurs because of other
    plugins or vim80-dependents stuff or anything ugly like that.
- [ ] python debugger facilities? R debugger facilities?

Misc:
-----

.. feel bored? grep 'TODO' anywhere in the project ;)

