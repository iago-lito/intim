"""Playaround: prepare gathering only relevant tokens to color
IDEA: lex script with `pygments` module in order to collect tokens, then
evaluate their types in order to choose which color to associate them
with :)
Big advantage: the lexing process may not be broken by a misformed
script!
"""

from pygments.token import Token, is_token_subtype
from pygments.lexers import python as pylex
from enum import Enum                    # for analysing enum types
import os                                # for module type
from sys import stdout                   # for default 'file'
from types import ModuleType, MethodType # to define particular types
from numpy import ufunc as UFuncType     # yet other particular types

# Use this very file as a test :P

with open('./lexing.py', 'r') as file:
    source = file.read()

class Type(object):
    """Type class for typing nodes of the token forest
    Can iterate over its instances for convenience
    """

    _instances = set()

    def __init__(self, id, python_type):
        self.id = 'IntimPy' + id
        self._instances.add(self)
        self.type = python_type

    @classmethod
    def instances(cls):
        """Iterate over all instances
        """
        return iter(cls._instances)

Bool       = Type("Bool"       , type(True))
BuiltIn    = Type("Builtin"    , type(dir))
Class      = Type("Class"      , type(object))
EnumType   = Type("EnumType"   , type(Enum))
Float      = Type("Float"      , type(1.))
Function   = Type("Function"   , type(lambda a: a))
Function   = Type("Method"     , type(lambda a: a))
Instance   = Type("Instance"   , None)
Int        = Type("Int"        , type(1))
Module     = Type("Module"     , type(os))
NoneType   = Type("NoneType"   , type(None))
String     = Type("String"     , type('a'))
Unexistent = Type("Unexistent" , None)

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

    @property
    def root(self):
        """True if parent is None or a Forest
        """
        return self.parent is None or isinstance(self.parent, Forest)

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

    def write(self, prefix, depth, file=stdout):
        """Build a vim syntax command to color this node, given
        information recursively given from above:
        prefix: string prefix to the command, build from above
        depth: int our depth within the forest, also build from above
        res: collect here the resulting commands: once on each node
        """
        # match expressions from the root, but only color the leaf:
        suffix = r"\>'hs=e-" + str(len(self.id) - 1)
        # allow any amount of whitespace around the '.' operator
        whitespace = r"[ \s\t\n]*\.[ \t\s\n]*"
        # for speed, provide Vim information about the items inclusions:
        if not self.root:
            suffix += " contained"
        if self.leaf:
            suffix += " contains=NONE"
        if not self.leaf:
            # watch out: here is an additional iteration on kids! **
            subgroups = {sub.type.id for sub in self.kids}
            suffix += " contains=" + ','.join(subgroups)
        # here is the full command:
        command = "syntax match " + self.type.id + prefix + suffix
        # throw it up
        print(command, file=file)
        # ask the kids to do so :)
        for kid in self.kids: # ** second iteration, could be the only one
            kid.write(prefix + whitespace + kid.id, depth + 1, file)


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

    def write(self, file=stdout):
        """Visit the forest to build an ad-hoc vim syntax file and color
        the nodes in the source file.
        """
        # the root name starts without being a subname of something else:
        root_prefix = r" '\(\.[\s\n]*\)\@<!\<"
        for kid in self.kids:
            kid.write(root_prefix + kid.id, 0, file=file)
        # signal to Intim: the syntax file may be read now!
        print('" end', file=file)

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

forest.write()

