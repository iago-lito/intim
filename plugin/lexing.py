"""Playaround: prepare gathering only relevant tokens to color
IDEA: lex script with `pygments` module in order to collect tokens, then
evaluate their types in order to choose which color to associate them
with :)
Big advantage: the lexing process may not be broken by a misformed
script!
"""

from pygments.token import Token, is_token_subtype
from pygments.lexers import python as pylex

source = \
"""
a = 5
b = a + 1
b.plainMember = 'wops'
b.plainMethod(arguments)
b.met.a.long.navigation()
b. met
    .
    a
    .weird . navigation
"charstring"
\"\"\"and a
multilined
one with a \" trap
\"\"\"
def wops(irregular)
    code.. still tokenized? yeah!
"""

lx = pylex.Python3Lexer()
g = lx.get_tokens(source)
for t, i in g:
    if is_token_subtype(t, Token.Name):
        print("name    : {}".format(i))
    if is_token_subtype(t, Token.Keyword):
        print("keyword : {}".format(i))
    if is_token_subtype(t, Token.Literal):
        print("literal : {}".format(i))
    if is_token_subtype(t, Token.Operator):
        print("operator: {}".format(i))

