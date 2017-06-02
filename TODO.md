
BUGS:

    > do not try opening a new session if one is already opened

    > Here, `np` seems not lexed:
        """docstring
        """
        import numpy as np # for scientific calculation
        EOF

    Known weird bug with successive object members:  
    > investigate:

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

    > compilation utilities for LaTeX.. predefined constant expressions
      depending on current filename?

FEATURE REQUESTS:

    > add explicit utilities for `bash` interpreter, does anyone know bash well?

