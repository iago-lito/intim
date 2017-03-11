"""Playaround: prepare gathering only relevant tokens to color
IDEA: lex script with `pygments` module in order to collect tokens, then
evaluate their types in order to choose which color to associate them
with :)
Big advantage: the lexing process may not be broken by a misformed
script!
"""

from pygments.token import Token, is_token_subtype
from pygments.lexers import python as pylex
from enum import Enum # for analysing enum types
import os # for module type

# Use this very file as a test :P

with open('./lexing.py', 'r') as file:
    source = file.read()

class Type(object):
    """Type class for typing nodes of the token forest
    Can iterate over its instances for convenience
    """

    _instances = set()

    def __init__(self, id, color, python_type):
        self.id = id
        self._instances.add(self)
        self.color = color
        self.type = python_type

    @classmethod
    def instances(cls):
        """Iterate over all instances
        """
        return iter(cls._instances)

Instance   = Type("instance"   , 'blue'   , None)
Unexistent = Type("unexistent" , 'grey'   , None)
Class      = Type("class"      , 'gold'   , type(object))
Function   = Type("function"   , 'purple' , type(lambda a: a))
BuiltIn    = Type("builtin"    , 'orange' , type(dir))
Module     = Type("module"     , 'pink'   , type(os))
Int        = Type("int"        , 'green'  , type(1))
Float      = Type("float"      , 'green'  , type(1.))
String     = Type("string"     , 'green'  , type('a'))
Bool       = Type("bool"       , 'green'  , type(True))
NoneType   = Type("nonetype"   , 'grey'   , type(None))

# Store them so that they can easily be found from actual python types
types_map = {}
for cls in Type.instances():
    types_map[cls.type] = cls


class Node(object):
    """Identifier and references to its parents and kids. It may have no
    parent, it is a root then.
    """

    def __init__(self, id, parent=None, type=Unexistent):
        """
        id: string the node's identifier: i.e. how it is written in the
            code.
        parent: Node its parent node in the graph, root node if None
        type: Type associated type with coloration etc
        """
        self.id = id
        self.parent = parent
        self._kids = {} # {id: Node}
        self.type = type

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
    def parents(self):
        """iterate backwards until a root parent is found
        """
        yield self
        if self.parent:
            yield from self.parent.parents
        else:
            raise StopIteration()

    @property
    def path(self):
        """Use backward iteration to build the full path to this node
        """
        res = [parent.id for parent in self.parents]
        return '.'.join(reversed(res))

    @property
    def kids(self):
        """iterate over kids
        """
        return iter(self._kids.values())

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
        res = "{}{}: {}\n".format(prefix, self.id, self.type.id)
        for kid in self.kids:
            res += kid._repr(prefix + self.id + '.')
        return res

    def __repr__(self):
        return self._repr('')

    def __len__(self):
        """Number of nodes: ourselves as a node + the weight of our kids
        """
        return 1 + sum(len(kid) for kid in self.kids)

    def type_nodes(self, prefix=''):
        """Ultimate use of this forest: evaluate our id in this context
        to retrieve information on the current state of this access path
        prefix: string previous path (context) of this node
        called by the parents
        """
        path = prefix + self.id
        # analyse type of this node:
        try:
            t = eval("type({})".format(path), globals())
        except (AttributeError, NameError) as e:
            # then all subsequent nodes are unexistent
            for node in self:
                node.type = Unexistent
            return
        # is the type available, special?
        node_type = types_map.get(t)
        if node_type:
            self.type = node_type
        else:
            # then it is just a plain valid, known node, probably
            # instance of a custom class
            self.type = Instance
        for kid in self.kids:
            kid.type_nodes(path + '.')


class Forest(Node):
    """A Forest is a special Node with no parent, no id, and containing
    only root nodes.
    """

    def __init__(self):
        self._kids = {}

    @property
    def parents(self):
        """A forest has no parents
        """
        raise StopIteration()

    def __repr__(self):
        if self.leaf:
            return "empty Forest."
        res = ""
        for kid in self.kids:
            res += repr(kid)
        return res

    def __len__(self):
        """Total number of nodes in the forest:
        """
        return sum(len(kid) for kid in self.kids)

    def __iter__(self):
        """Iterate over all trees, not ourselves
        """
        for kid in self.kids:
            yield from kid

    def type_nodes(self):
        """Ask each tree to type itself
        """
        for kid in self.kids:
            kid.type_nodes()


# informal tests:
a = Node('abc')
d = Node('de')
f = Node('f')
a.add_node(d)
a.add_node(f)
gh = f.add_id('gh')
f.add_id('i')
forest = Forest()
forest.add_node(a)
A = Node('A')
A.add_id('B')
A.add_id('C')
forest.add_node(A)
forest.add_id('B')
print(forest)
gh.path

# dear lexer
lx = pylex.Python3Lexer()
g = lx.get_tokens(source)
# gather names to color as a forest of '.' operators:
forest = Forest()
current = forest
# flag to keep track of whether to add in depth or go back to the root
last_was_a_name = True
# Also gather misc immediate tokens.. just for fun and extensibility
misc = {}
for i in [Token.Name.Decorator,
          Token.Name.Namespace,
          Token.Name.Operator,
          Token.Name.Keyword,
          Token.Name.Literal,
          Token.Comment,
          ]:
    misc[i] = set()
# iterate over type_of_token, string
for t, i in g:
    in_misc = False
    for subtype, harvest in misc.items():
        if is_token_subtype(t, subtype):
            in_misc = True
            harvest.add(i)
            break
    if in_misc:
        # no need to go further since this token does not belong to the forest
        continue
    if is_token_subtype(t, Token.Name):
        if i == '.':
            raise Exception()
        node = forest if last_was_a_name else current
        current = node.add_id(i)
        last_was_a_name = True
    elif is_token_subtype(t, Token.Operator):
        if i == '.':
            last_was_a_name = False

forest.type_nodes()

