# Vim global plugin for interactive interface with interpreters: intim
# Last Change:	2016-03-20
# Maintainer:   Iago-lito <iago.bonnici@gmail.com>
# License:      This file is placed under the GNU PublicLicense 3.

"""
This python script is supposed to perform introspection into a
particular python session and produce a vim syntax file gathering each
declared word and an associated group depending on its type.

Building a huge tree of every declared identifiers and various
(potentially circular) ways to access them is difficult, non-trivial and
slow. Let's try another approach and only consider the accessors that
are.. actually used in the file to color ;)

Idea: `intim_introspection` will be called with a reference to a python
script file. This file will be parsed to gather every `access.paths` to
color. Once done, they will be analysed for type etc. so that a color
will be defined for each. The resulting vim syntax file will then be
completely ad-hoc, dedicated to the parsed script.

Let's go, try it :)

"""

def intim_introspection():

    # Starting point of the exploration:
    root = globals().copy()

    # options
    # TODO: mak'em user-definable..
    max_module = 2
    verbose = True
    # .. like this one:
    syntax_file = INTIMSYNTAXFILE # sed by vimscript
    script_file = "plugin/syntax.py"

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
                type = RootDefault if parent is None else UnsupportedType
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
    RootDefault     = 1 # unsupported root type
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
            , RootDefault     : 'IntimPyRootDefault'
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
    # file = open(syntax_file, 'w')
    # for item in forest:
        # plot_item(item, '')
    # file.close()

    # Now use the forest to build the syntax file:
    if verbose:
        print("writing syntax file..")
    file = open(syntax_file, 'w')
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
        elif depth > 0:
            suffix += " contains=NONE"
        # flesh the prefix: insert as many white space as you wish provived
        # here is the full command:
        command = "syntax match " + groups[item.type] + prefix + suffix
        # recursive call:
        for i, subitem in enumerate(item.sub):
            print("{}: {}".format(depth, i), end='\r')
            # there is a clean dot to subname:
            recursive(subitem, prefix +
                    r"[ \s\t\n]*\.[ \t\s\n]*" + subitem.name, depth + 1)
        # write to the file
        print(command, file=file)
    # the root name starts without being a subname of something else:
    root_prefix = r" '\(\.[\s\n]*\)\@<!\<"
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