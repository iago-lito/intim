# Vim global plugin for interactive interface with interpreters: intim
# Last Change:	2016-03-20
# Maintainer:   Iago-lito <iago.bonnici@gmail.com>
# License:      This file is placed under the GNU PublicLicense 3.

# This python script is supposed to perform introspection into a particular
# python session and produce a vim syntax file gathering each declared word and
# an associated group depending on its type.

# It seems non-trivial (http://queueoverflow.com/questions/35563092/). Before
# anyone helps me find a neat way to do it, we shall just satisfy ourselves with
# this crummy recursive procedure. Try at least not to make it loop endlessly.

# Basic principle: build a tree of python access identifiers or "names" called
#   `Item`s. The tree corresponds to *one* way of refering to the items by
#   sending, for instance, `name.subname` to the interpreter.
#   It is built by exploring `globals` then recursively calling `dir` on it.
#
#   In order for the circular references not to be a problem, each item will be
#   stored as a reference in `already_expanded` so that they will only be
#   expanded once.
#       Consequence: if `name` can be accessed both by `first.second.name` and
#                    by `third.fourth.name`, then only one of them will be
#                    highlighted. Shame, uh?
#
#   In order not to fill up the RAM, basic types which cannot be referenced
#   without being copied (int, float, strings) are not expanded. They are
#   listed in `noref_types`.
#       Consequence: `format` in `str.format()` will not be highlighted. Too
#       bad.
#
#   In order for the exploration not to be too long, we shall not explore python
#   reserved names.
#       Consequence: `__these__` and `__names__` won't be highlighted. Also
#       tricky names like `exit` and `quit`. Too bad.
#
#   In order for the exploration not to be too long, we shall only restrict
#   ourselves to `max_module` expansion steps down modules.
#       Consequence: `third` in `numpy.first.second.third` will not be
#       highlighted or user would have to wait a very long time. Shame, uh?

def intim_introspection():

    # Starting point of the exploration:
    root = globals().copy()

    # options
    # TODO: mak'em user-definable..
    max_module = 2
    verbose = True
    # .. like this one:
    filename = INTIMSYNTAXFILENAME

    class Item(object):
        """Wrap a node of the exploration tree.

            One item ~ one python object declared in the current session.

            parent: reference to a parent item, so that `parent.item` means
                    something to the interpreter.
            sub: set of children items, so that `item.sub*` means something to
                 the interpreter.
        """
        def __init__(self, name, type, ref, parent):
            """
                name: identifier string of the object
                type: type of the object
                ref: reference to the actual object wrapped by `Item`
                parent: none for objects in `globals()` or ref to a parent item
            """

            # Basic properties
            self.name = name
            self.parent = parent
            self.sub = {}
            # do not store heavy "references" which are actual copies
            self.ref = None if type in noref_types else ref
            # determine the syntax group
            if type not in groups:
                type = UnsupportedType
            self.type = type

            # Shall we expand this item?
            self.expand = True
            # Unhashable references cannot be put in `already_expanded`
            if not isinstance(ref, Hashable):
                self.expand = False # .. do not expand them
                return
            # Do not expand if the item has already been expanded
            if any([self.ref is item.ref for item in already_expanded]):
                self.expand = False
                return
            # Do not expand more if we are getting too far down a module
            grandparent = self
            root_reached = False
            # Is the `max_module`-grandparent a module?
            for i in range(max_module):
                if grandparent.parent is None:
                    # If we are stil close from the root, don't worry and expand
                    root_reached = True
                    break
                grandparent = grandparent.parent
            if __builtins__.type(grandparent.ref) is ModuleType:
                self.expand = root_reached
                return

        def __repr__(self):
            return "Item: '{}' {} {} {}".format(
                    self.name, self.type, self.ref, self.expand)

    # We'll need a few more modules to study objects types:
    from types import ModuleType, MethodType # to define particular types
    from numpy import ufunc as UFuncType     # yet other particular types
    from enum import Enum                    # yet others
    from collections import Hashable         # do not expand unhashable types

    # Supported syntax groups
    ClassType    = type(object)
    BuiltInType  = type(dir)
    FunctionType = type(lambda a: a)
    EnumType     = type(Enum)
    NoneType     = type(None)
    IntType      = type(1)
    FloatType    = type(1.)
    StringType   = type('a')
    BoolType     = type(True)
    UnsupportedType = 0
    groups = {BuiltInType     : 'IntimPyBuiltin'
            , ClassType       : 'IntimPyClass'
            , EnumType        : 'IntimPyEnumType'
            , FunctionType    : 'IntimPyFunction'
            , MethodType      : 'IntimPyMethod'
            , UFuncType       : 'IntimPyUFunc'
            , ModuleType      : 'IntimPyModule'
            , NoneType        : 'IntimPyNone'
            , IntType         : 'IntimPyInt'
            , FloatType       : 'IntimPyFloat'
            , StringType      : 'IntimPyString'
            , BoolType        : 'IntimPyBool'
            , UnsupportedType : 'IntimPyUnsupported'
            }

    # Don't ref these ones or they will be copied instead:
    noref_types = set([
        NoneType,
        IntType,
        FloatType,
        StringType,
        BoolType,
        ])

    # name filter: do not even itemize those identifiers:
    def is_item_name(name):
        # python internals
        # do not expand python reserved names:
        if name[:2] == '__' and name[-2:] == '__':
            return False
        if name in ['exit', 'quit', 'intim_introspection']:
            return False
        return True

    # Start the actual exploration
    if verbose:
        print("exploring session..")
    # No item has been expanded yet
    already_expanded = set()
    # here is the bunch of currently explored objects
    bunch = [Item(key,
                type(value),
                value,
                None) for key, value in root.items() if is_item_name(key)]
    # here is the result of our exploration: several rooted trees
    forest   = [item for item in bunch]
    # here are items that still need to be expanded
    queue = [item for item in bunch if item.expand]
    while len(queue) > 0:
        if verbose:
            print(len(queue), end="\r")
        # pick an item from the queue:
        current = queue.pop(0) # explore the highests first or the `max_module`
                               # trick may not work due to circular dependencies
        # explore it
        ref = current.ref
        subnames = dir(ref)
        # new bunch of items:
        bunch = [Item(name,
                     type(getattr(ref, name)),
                     getattr(ref, name),
                     current) for name in subnames if is_item_name(name)]
        # they are this item's subitems
        current.sub = bunch
        # some still need to be expanded
        queue += [item for item in bunch if item.expand]
        # mark this reference as already explored
        current.expand = False
        already_expanded.add(current)

    # # visualize the forest in a file (debugging):
    # def plot_item(item, level):
        # new = level + '.' + item.name
        # print(new[1:], file=file)
        # for subitem in item.sub:
            # plot_item(subitem, new)
    # file = open(filename, 'w')
    # for item in forest:
        # plot_item(item, '')
    # file.close()

    # Now use the forest to build the syntax file:
    if verbose:
        print("writing syntax file..")
    file = open(filename, 'w')
    # clear first
    for group in groups.values():
        print("syntax clear " + group, file=file)
    # then color. Recursive visiting of `forest` and generating dirty VimScript
    # syntax commands:
    def recursive(item, prefix, depth):
        # match expressions from the root, but only color the leaf:
        suffix = r"\>'hs=e-" + str(len(item.name) - 1)
        # for speed, provide Vim information about the items inclusions:
        if item.parent is not None:
            suffix += " contained"
        if len(item.sub) > 0:
            subgroups = {groups[sub.type] for sub in item.sub}
            suffix += " contains=" + ','.join(subgroups)
        else:
            suffix += " contains=NONE"
        # flesh the prefix: insert as many white space as you wish provived
        # there is a clean dot to subname:
        prefix += r"[\s\n]*\.[\s\n]*" + item.name
        # here is the full command:
        command = "syntax match " + groups[item.type] + prefix + suffix
        # recursive call:
        for i, subitem in enumerate(item.sub):
            print("{}: {}".format(depth, i), end='\r')
            recursive(subitem, prefix, depth + 1)
        # write to the file
        print(command, file=file)
    # the root name starts without being a subname of something else:
    root_prefix = r" '\(\.[ \n]*\)\@<!\<"
    for item in forest:
        recursive(item, root_prefix + item.name, 0)
    # signal to Intim: the syntax file may be read now!
    print('" end', file=file)
    file.close()
    if verbose:
        print("done.")

# run and forget about all this.
intim_introspection()
del intim_introspection
