
Known weird bug with successive object members:  
- investigate:

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



