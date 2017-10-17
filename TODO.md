Find work here

Bugs:
--

- Here, `np` seems not lexed:

        """docstring
        """
        import numpy as np # for scientific calculation
        EOF

- Known weird bug with successive object members.. investigate:

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
--

### Easy ones

- add an explicit predefined `restart` mapping?
- provide utilities to get into loops: for `python` (easy) and `R` (trickier)
- add another placeholder like `%f` in hotkeys expressions to insert filenames.
    - this will help making a neater implementation of default LaTeX commands.

### Bigger ones

- add explicit utilities for `bash` interpreter, does anyone know bash well?
- disable simple sending for compiled language (LaTeX, Rust, ..), which make no
  sense.
- ssh option? sending commands *via* is not difficult, but sending
  chunk/help/color files could be something :)

.. feel bored? grep 'TODO' anywhere in the project ;)

