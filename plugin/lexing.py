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
b.plainMethod(arguments, andeven, more=arguments[say.even, complex])
b.met.a.long.navigation()
b. met
    .
    a
    .weird . navigation
then.a.subsequent.one
"charstring"
\"\"\"and a
multilined
one with a \" trap
\"\"\"
def wops(irregular)
    code.. still tokenized? yeah!
"""

class Node(object):
    """Identifier and references to its parents and kids. It may have no
    parent, it is a root then.
    """

    def __init__(self, id, parent=None):
        self.id = id
        self.parent = parent
        self._kids = {} # {id: Node}

    @property
    def leaf(self):
        """True if has no kids
        """
        return not bool(self._kids)

    def add_node(self, node):
        """basic procedure to add a node as a kid
        """
        node.parent = self
        self._kids[node.id] = node

    def add_id(self, id):
        """Create a new kid from a string id
        if it already exists, do not erase the existing one
        return the newly created node
        """
        node = self._kids.get(id)
        if node:
            return node
        node = Node(id=id, parent=self)
        self._kids[id] = node
        return node

    @property
    def kids(self):
        """iterate over kids
        """
        for kid in self._kids.values():
            yield kid

    @property
    def leaves(self):
        """Iterate over all leaf kids
        """
        if self.leaf:
            yield self
        else:
            for kid in self.kids:
                yield from kid.leaves

    def __iter__(self):
        """Iterate over all nodes, top-down
        """
        yield self
        for kid in self.kids:
            yield from kid

    def _repr(self, prefix):
        """Iterate over all nodes and print full paths
        """
        res = prefix + self.id + '\n'
        for kid in self.kids:
            res += kid._repr(prefix + self.id + '.')
        return res

    def __repr__(self):
        return self._repr('')

class Forest(Node):
    """A Forest is a special Node with no parent, no id, and containing
    only root nodes.
    """

    def __init__(self):
        self._kids = {}

    def __repr__(self):
        if self.leaf:
            return "empty Forest."
        res = ""
        for kid in self.kids:
            res += repr(kid)
        return res

# informal tests:
a = Node('abc')
d = Node('de')
f = Node('f')
a.add_node(d)
a.add_node(f)
f.add_id('gh')
f.add_id('i')
forest = Forest()
forest.add_node(a)
A = Node('A')
A.add_id('B')
A.add_id('C')
forest.add_node(A)
forest.add_id('B')
print(forest)

# dear lexer
lx = pylex.Python3Lexer()
g = lx.get_tokens(source)
# gather names to color as a forest of '.' operators:
# iterate over type_of_token, string
forest = Forest()
current = forest
# flag to keep track of whether to add in depth or go back to the root
last_was_a_name = True
# Also gather misc:
keywords = set()
litterals = set()
operators = set()
for t, i in g:
    if is_token_subtype(t, Token.Name):
        node = forest if last_was_a_name else current
        current = node.add_id(i)
        last_was_a_name = True
    if is_token_subtype(t, Token.Operator):
        operators.add(i)
        if i == '.':
            last_was_a_name = False
    if is_token_subtype(t, Token.Keyword):
        keywords.add(i)
    if is_token_subtype(t, Token.Literal):
        litterals.add(i)
print(forest)


