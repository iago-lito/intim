" Vim global plugin for interactive interface with interpreters: intim
" Last Change:	2018-01-29
" Maintainer:   Iago-lito <iago.bonnici@gmail.com>
" License:      This file is placed under the GNU PublicLicense 3.

" lines for handling line continuation, according to :help write-plugin<CR> "{{{
let s:save_cpo = &cpo
set cpo&vim
" make it possible for the user not to load the plugin, same source
if exists("g:loaded_intim")
    finish
endif
let g:loaded_intim = 1
"}}}

" In this script, I'll start gathering every bizarre, convenient stuff I use to
" interface Vim with command-line interpreters.
" Mostly inspired from vim-R plugin: https://github.com/jcfaria/Vim-R-plugin,
" started because I couldn't find such a thing for Python, continued because I
" could also use it for bash and LaTeX.. then R again.
" The main idea is to use Tmux: https://tmux.github.io/ from Vim's terminal to
" launch any interpreter within an interactive multiplexed session. Convenient
" utility functions will then help the user passing script from Vim to the
" interpreter, or retrieving information from it.
" MainFeatures: I expect to offer:
"   - easy passing of pieces of script to the interpreter without leaving Vim
"   - convenient wrapping of passed script into custom functions: delete a
"     variable, get lenght of a structure, analyse and plot a vector, open and
"     close graphical windows without leaving Vim
"   - a few convenience edition trick consistent with the latter ones, refered
"     to as `EditBonus` in this script
"   - if possible and implemented (R, Python), use interpreter's introspection
"     for dynamic syntax highlighting within Vim (change variable colors
"     depending on whether they are declared or not, depending on their type..)
"   - if possible and implemented (R, Python), easy access to help pages within
"     Vim
"   - if possible and implemented (R, Python), easy entering loops for debugging
"   - send all term signals supported by Tmux, in particular <c-c> and <c-d>
"   - quit and restart vim without terminating the session
" Difficulties:
"   - everything is mixed up for now because I also use a lot of custom scripts
"     to handle my windows, integrate my own vim tricks, etc. I'll try to sort
"     that out. Of course, I'll also try to keep enough flexibility for this
"     intimate coupling with my odd habits always to remain possible. In this
"     way, I expect that users will easily adapt intim into their own weird
"     fetishes.
"   - I only know one environment well (mine), so it might be difficult to adapt
"     to others in a first time.
"     Make it explicit: this plugin will be first elaborated within:
"       - Debian 9, Stretch
"       - Gnome 3.22.1
"       - Vim 8.0 in a gnome-terminal
"     Should it need liftings in order to adapt to other environments, I'll need
"     help from users in those environments and invoke social coding. Feel free
"     to contribute :)
" InstallationCorner: Stack here dependencies, maybe provide a way to check for
" them or get them automatically?
"   - tmux
"   - perl
"   - cat, sed, well, ok
"   - gnome-terminal (default)
"   for python coloring: modules
"       pygments, enum, os, sys, types, numpy

" TODO:
" > safety: replace ALL `system` by `systemlist`, check their outputs and warn
"   if anything went wrong.

" Here we go.

" For now, everything is designed for only ONE tmux session at a time

" Absolute path to this plugin: http://stackoverflow.com/a/18734557/3719101
let s:path = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let g:intim_path = s:path

" Methods:
" Provide user function call opportunities "{{{
" Note: some other function calls are provided in this script during options
" definitions. There are also guarded in their own way.

" Macro declaring and guarding user wrappers to methods:
function! s:functionExport(internalname, name, nargs) "{{{
    if !exists('*' . a:name)
        if a:nargs == 0
            execute "function " . a:name . "()\n"
                \ . "    return s:" . a:internalname . "()\n"
                \ . "endfunction"
        elseif a:nargs == 1
            execute "function " . a:name . "(arg)\n"
                \ . "    return s:" . a:internalname . "(a:arg)\n"
                \ . "endfunction"
        elseif a:nargs == -1 " variable number of arguments
            execute "function " . a:name . "(...)\n"
                \ . "    return s:" . a:internalname . "(a:000)\n"
                \ . "endfunction"
        else
            echoerr "Cannot export functions with more than 1 arguments yet."
        endif
    else
        echom a:name . "already declared, Intim won't overwrite it."
    endif
endfunction
"}}}

" Prefix them all with Intim-
call s:functionExport('Send'          , 'IntimSend', 1)
call s:functionExport('SendEnter'     , 'IntimSendEnter', 0)
call s:functionExport('SendInterrupt' , 'IntimSendInterrupt', 0)
call s:functionExport('SendEOF'       , 'IntimSendEOF', 0)
call s:functionExport('SetLanguage'   , 'IntimSetLanguage', 1)
call s:functionExport('GetLanguage'   , 'IntimGetLanguage', 0)
call s:functionExport('CompileTex'    , 'IntimCompileTex', -1)

" Some "languages" actually the same, right?
let s:python_like = ['python',
                   \ 'python3',
                   \ 'ipython',
                   \ 'ipython3',
                   \ 'bpython',
                   \ 'bpython3',
                   \ 'django',
                   \ 'sage',
                   \ ]
function! s:pythonBased(language)
    return index(s:python_like, a:language) > -1
endfunction

"}}}

" Options:
" Define here user's options "{{{

" Very global options: "{{{
" Convenience macro for guarding global options
function! s:declareOption(name, default, shorter) "{{{
    execute "if !exists('" . a:name . "')\n"
        \ . "    let " . a:name . " = " . a:default . "\n"
        \ . "endif"
    " convenience shortcut for this script
    execute "function! " . a:shorter . "()\n"
        \ . "    return " . a:name . "\n"
        \ . "endfunction"
endfunction
"}}}

" Tmux session name
call s:declareOption('g:intim_sessionName', "'IntimSession'", 's:sname')

" Which terminal to use?
call s:declareOption('g:intim_terminal', "'gnome-terminal'", 's:terminal')

" temporary file to write chunks to and source them from
call s:declareOption('g:intim_tempChunks', "s:path . '/tmp/chunk'", 's:chunk')
" temporary file to read help in
call s:declareOption('g:intim_tempHelp', "s:path . '/tmp/help'", 's:help')
" temporary syntax file update script coloration
call s:declareOption('g:intim_tempSyntax', "s:path . '/tmp/syntax'", 's:vimsyntax')
call s:declareOption('g:intim_openPdf_command', "'evince * &> /dev/null &'",
                   \ 's:openPdfCommand')
" Check if tempfiles can be written to or create'em
function! s:CheckFile(file) "{{{
    if !filewritable(a:file)
        call system("mkdir -p $(dirname " . a:file . ")")
        call system("touch " . a:file)
    endif
    if !filewritable(a:file)
        echoerr "Intim: can't access " . a:file
    endif
endfunction
"}}}
"}}}

" Options per language:  "{{{
" Following options are stored as a dictionnary entries whose keys are the
" language being used.
" In order for user not to have to deal with messy dictionary options, let's
" store them in s:variables and provide an interface to define them: functions
" callable from .vimrc or later, that should create and/or override default
" options.

" Language of the interpreter (e.g. `python`)
" This string will be the key for choosing which methods to use (adapted to each
" supported language) and which options to read.
" Examples : 'default', 'python', 'R', 'LaTeX', 'bash' + user-defined
let s:language = 'default'

" Here is a method for switching language: `should be called or no hotkeys
function! s:SetLanguage(language) "{{{

    " update the information
    let s:language = a:language

    " HotKeys:
    " Declare all hotkeys relative to that language
    let dicts = [
                \ [s:hotkeys, 's:DefineHotKey'],
                \ [s:headedExpression, 's:DefineHeadedExpression'],
                \ [s:latexExpression, 's:DefineLaTeXExpression'],
                \ [s:prefixedExpression, 's:DefinePrefixedExpression'],
                \ [s:constantExpression, 's:DefineConstantExpression'],
                \ ]
    for i in dicts
        let mappings = s:readOption(i[0])
        let MapperFunction = function(i[1])
        for [shortcut, expression] in items(mappings)
            call MapperFunction(shortcut, expression)
        endfor
    endfor

endfunction
"}}}

" Read access for user:
function! s:GetLanguage()
    return s:language
endfunction

" Read a particular option from a dictionnary or return the default one
function! s:readOption(dico) "{{{
    if has_key(a:dico, s:language)
        return a:dico[s:language]
    else
        return a:dico['default']
    endif
endfunction
"}}}

" define the s:dictionnaryOption_variable if not defined yet
function! s:defineLanguageOption(name) "{{{
    let name = 's:' . a:name
    if !exists(name)
        execute "let " . name . " = {}"
    endif
endfunction
"}}}

" utility macro for defining a new option dictionnary in this script
function! s:createLanguageOption(name) "{{{
    call s:defineLanguageOption(a:name)
    " function to define default option from this script, without overriding
    " user input
    execute ""
     \ . "function! s:setDefaultOption_" . a:name . "(language, option)\n"
     \ . "    if !has_key(s:" . a:name . ", a:language)\n"
     \ . "        let s:" . a:name . "[a:language] = a:option\n"
     \ . "    endif\n"
     \ . "endfunction"
    " read the option
    execute ""
     \ . "function! s:get_" . a:name . "()\n"
     \ . "    return s:readOption(s:" . a:name . ")\n"
     \ . "endfunction"
    " export this access to user
    call s:functionExport("get_" . a:name,
                        \ "IntimGet".toupper(a:name[0]).a:name[1:], 0)
    " function to be exported to user: define your own option.. this may require
    " the variable to be defined then, because .vimrc is sourced before this
    " script.
    execute ""
     \ . "function! s:set_" . a:name . "(language, option)\n"
     \ . "   call s:defineLanguageOption('" . a:name . "')\n"
     \ . "   let s:" . a:name . "[a:language] = a:option\n"
     \ . "   call s:setHook_" . a:name . "(a:language, a:option)\n"
     \ . "endfunction\n"
    " New: also provide a hook so other options may be automagically set when
    " user sets basic options. Override if actually needed.
    execute ""
     \ . "function! s:setHook_" . a:name . "(language, option)\n"
     \ . "endfunction\n"
    " export one version to user
    let fname = "Intim_" . a:name
    if exists(fname)
        echom a:name . "already declared, I won't overwrite it."
        return
    endif
    execute ""
     \ . "function! " . fname . "(language, option)\n"
     \ . "   call s:set_" . a:name . "(a:language, a:option)\n"
     \ . "endfunction\n"
endfunction
"}}}

" Shell command to execute right after having opened the new terminal. Intent:
" call a custom script (I use it for tiling, (un)decorating, marking the
" terminal). One command per item in the list. Silent if empty.
call s:createLanguageOption('postLaunchCommands')
call s:setDefaultOption_postLaunchCommands('default', [''])

" First shell commands to execute in the session before invoking the
" interpreter. Intent: set the interpreter environment (I use it for cd-ing to
" my place, checking files). User's custom aliases should be available here.
" List of strings. One command per item in the list. Silent if empty.
call s:createLanguageOption('preInvokeCommands')
call s:setDefaultOption_preInvokeCommands('default', [''])

" Interpreter to invoke (e.g. `bpython`) One command (string) only.
call s:createLanguageOption('invokeCommand')
call s:setDefaultOption_invokeCommand('default', '')
" all python-likes :P
for pl in s:python_like
    call s:setDefaultOption_invokeCommand(pl, pl)
endfor
call s:setDefaultOption_invokeCommand('django', 'python manage.py shell')
call s:setDefaultOption_invokeCommand('R', 'R')
call s:setDefaultOption_invokeCommand('bash', 'bash')
call s:setDefaultOption_invokeCommand('LaTeX', '')
call s:setDefaultOption_invokeCommand('javascript', 'node')
call s:setDefaultOption_invokeCommand('psql', 'psql')

" First interpreter commands to execute after invoking the interpreter (I use it
" to load packages etc.). One command per item in the list. Silent if empty.
call s:createLanguageOption('postInvokeCommands')
call s:setDefaultOption_postInvokeCommands('default', [''])

" Leave the interpreter
" <c-D> if empty.
call s:createLanguageOption('exitCommand')
call s:setDefaultOption_exitCommand('default', '')
call s:setDefaultOption_exitCommand('python', 'exit()')
call s:setDefaultOption_exitCommand('R', "quit(save='no')")
call s:setDefaultOption_exitCommand('javascript', "process.exit()")
call s:setDefaultOption_exitCommand('psql', "exit")

" Pattern matching for gathering all opened files to be colored
" TODO: make this automatic reading &ft in all buffers?
" TODO: document this
call s:createLanguageOption('filePattern')
call s:setDefaultOption_filePattern('default', '.*')
call s:setDefaultOption_filePattern('python', '.*\.py') " TODO: .pythonrc etc.
call s:setDefaultOption_filePattern('R', '.*\.r') " TODO: .r,.R,.Rprofile etc.
call s:setDefaultOption_filePattern('psql', '.*\.sql') " TODO: .r,.R,.Rprofile etc.

" Syntax function to be ran after s:ReadColor update
call s:createLanguageOption('syntaxFunction')
call s:setDefaultOption_syntaxFunction('default', 's:Void')
call s:setDefaultOption_syntaxFunction('python', 's:DefaultPythonSyntaxFunction')

" How should we <Plug>IntimSendSelection?
call s:createLanguageOption('sendSelection')
call s:setDefaultOption_sendSelection('default', 'LineByLine')
call s:setDefaultOption_sendSelection('sage', 'MagicCpaste')
" Automagically set it to MagicCpaste if invoked interpreter is Sage or ipython
" :P
function! s:setHook_invokeCommand(language, option)
    if match(a:option, 'ipython') >= 0
    \ || match(a:option, 'sage') >= 0
        call s:set_sendSelection(a:language, 'MagicCpaste')
    endif
endfunction

function! s:Void()
    " does nothing
endfunction

function! s:DefaultPythonSyntaxFunction()
    " parenthesis etc.
    syntax match Special "[()\[\]{}\-\*+\/]"
endfunction

" Help highlighting
" TODO: make sure those syntax file are neat and available
call s:createLanguageOption('helpSyntax')
call s:setDefaultOption_helpSyntax('default', "")
call s:setDefaultOption_helpSyntax('python', "pydoc")
call s:setDefaultOption_helpSyntax('R', "rdoc")

" Leaders for hotkeys "{{{
" `,` for sending commands to interpreter, `;` to actually edit the script
" in the LaTeX case, reverse: `,` for edition since interaction with
" interpreter is less frequent and `;` for sending in normal mode
call s:createLanguageOption('hotkeys_nleader')
call s:setDefaultOption_hotkeys_nleader('default', ',')
call s:setDefaultOption_hotkeys_nleader('LaTeX', ';')
" for sending in visual mode
call s:createLanguageOption('hotkeys_vleader')
call s:setDefaultOption_hotkeys_vleader('default', ',')
call s:setDefaultOption_hotkeys_vleader('LaTeX', ';')
" for editing in insert mode
call s:createLanguageOption('hotkeys_edit_ileader')
call s:setDefaultOption_hotkeys_edit_ileader('default', ',')
" for editing in normal mode
call s:createLanguageOption('hotkeys_edit_nleader')
call s:setDefaultOption_hotkeys_edit_nleader('default', ';')
call s:setDefaultOption_hotkeys_edit_nleader('LaTeX', ',')
" for editin in visual mode
call s:createLanguageOption('hotkeys_edit_vleader')
call s:setDefaultOption_hotkeys_edit_vleader('default', ';')
call s:setDefaultOption_hotkeys_edit_vleader('LaTeX', ',')
"}}}

"}}}

" Options lists per language: "{{{
" From now on, each language option will be an actual dictionnary as well, and
" user should be able to edit it without having to redefine it entirely each
" time.

" define the s:dictionnaryOptionVariable['language'] if not defined yet
function! s:defineLanguageOptionKey(dico, key) "{{{
    " so 'key' is a *language* (level 1 in the dict)
    if !has_key(a:dico, a:key)
        let a:dico[a:key] = {}
    endif
    return a:dico
endfunction
"}}}

" Utility macro for defining a new option dictionnary.. dictionnary in
" this script
function! s:createLanguageDictionnaryOption(name) "{{{
    call s:defineLanguageOption(a:name)
    " add an empty default key
    exec "let s:".a:name." = s:defineLanguageOptionKey(s:".a:name.", 'default')"
    " function to define default option from this script, without overriding
    " user input
    execute ""
     \ . "function! s:setDefaultOption_" . a:name . "(language, key, option)\n"
     \ . "    let s:" . a:name
     \ . "          = s:defineLanguageOptionKey(s:" . a:name . ", a:language)\n"
     \ . "    if !has_key(s:" . a:name . "[a:language], a:key)\n"
     \ . "        let s:" . a:name . "[a:language][a:key] = a:option\n"
     \ . "    endif\n"
     \ . "endfunction"
    " read the option
    execute ""
     \ . "function! s:get_" . a:name . "()\n"
     \ . "    return s:readOption(s:" . a:name . ")\n"
     \ . "endfunction"
    " function to be exported to user: define your own option at level 2 in the
    " dict.. this may require the variable *and* the key to be defined then,
    " because .vimrc is sourced before this script.
    execute ""
     \ . "function! s:set_" . a:name . "(language, key, option)\n"
     \ . "   call s:defineLanguageOption('" . a:name . "')\n"
     \ . "   call s:defineLanguageOptionKey(s:" . a:name . ", a:language)\n"
     \ . "   let s:" . a:name . "[a:language][a:key] = a:option\n"
     \ . "endfunction\n"
    " export one version to user
    let fname = "Intim_" . a:name
    if exists(fname)
        echom a:name . "already declared, I won't overwrite it."
        return
    endif
    execute ""
     \ . "function! " . fname . "(language, key, option)\n"
     \ . "   call s:set_" . a:name . "(a:language, a:key, a:option)\n"
     \ . "endfunction\n"
endfunction
"}}}

" Highlight groups for supported syntax groups, they depend on the language
call s:createLanguageDictionnaryOption('highlightGroups') "{{{
" default for R
call s:setDefaultOption_highlightGroups('R', 'IntimRIdentifier', 'Identifier')
call s:setDefaultOption_highlightGroups('R', 'IntimRFunction', 'Function')
" default for python
" (temp list for for readability here only)
let groups = [
            \ ['IntimPyBool'      , 'Constant'],
            \ ['IntimPyBuiltin'   , 'Underlined'],
            \ ['IntimPyClass'     , 'Type'],
            \ ['IntimPyEnumType'  , 'Type'],
            \ ['IntimPyEnumValue'  , 'Constant'],
            \ ['IntimPyFloat'     , 'Constant'],
            \ ['IntimPyFunction'  , 'Underlined'],
            \ ['IntimPyInstance'  , 'Identifier'],
            \ ['IntimPyInt'       , 'Constant'],
            \ ['IntimPyMethod'    , 'Underlined'],
            \ ['IntimPyModule'    , 'helpNote'],
            \ ['IntimPyNoneType'  , 'Constant'],
            \ ['IntimPyString'    , 'Constant'],
            \ ['IntimPyStandard'  , 'Identifier'],
            \ ]
for [group, linked] in groups
    call s:setDefaultOption_highlightGroups('python', group, linked)
endfor
"}}}

" Generic Hotkeys
call s:createLanguageDictionnaryOption('hotkeys') "{{{
" no default provided, but here is an example to increment a counter
" call s:setDefaultOption_hotkeys('R', 'ii', '* <- * + 1')
" call s:setDefaultOption_hotkeys('python', 'ii', '* += 1')
"}}}

" Headed hotkeys.. provide a few common default ones
call s:createLanguageDictionnaryOption('headedExpression') "{{{
" R  "{{{
let mappings = [
            \ ['al', 'as.logical'],
            \ ['ac', 'as.character'],
            \ ['ai', 'as.integer'],
            \ ['an', 'as.numeric'],
            \ ['cl', 'class'],
            \ ['cn', 'colnames'],
            \ ['dm', 'dim'],
            \ ['hd', 'head'],
            \ ['ia', 'is.array'],
            \ ['id', 'is.data.frame'],
            \ ['il', 'is.list'],
            \ ['im', 'is.matrix'],
            \ ['in', 'is.numeric'],
            \ ['is', 'is.sorted'],
            \ ['iv', 'is.vector'],
            \ ['lg', 'length'],
            \ ['lv', 'levels'],
            \ ['me', 'mean'],
            \ ['mn', 'min'],
            \ ['mx', 'max'],
            \ ['nc', 'ncol'],
            \ ['nh', 'nchar'],
            \ ['nm', 'names'],
            \ ['nr', 'nrow'],
            \ ['pl', 'plot'],
            \ ['pr', 'print'],
            \ ['rg', 'range'],
            \ ['rn', 'rownames'],
            \ ['sm', 'summary'],
            \ ['sd', 'std'],
            \ ['sz', 'size'],
            \ ['tb', 'table'],
            \ ['tl', 'tail'],
            \ ['tr', 't'],
            \ ['un', 'unique'],
            \ ]
for [map, head] in mappings
    call s:setDefaultOption_headedExpression('R', map, head)
endfor
"}}}
" python  "{{{
let mappings = [
            \ ['dr' , 'dir'  ],
            \ ['id' , 'id'   ],
            \ ['ln' , 'len'  ],
            \ ['mn' , 'min'  ],
            \ ['mx' , 'max'  ],
            \ ['pr' , 'print'],
            \ ['ty' , 'type' ],
            \ ]
for [map, head] in mappings
    call s:setDefaultOption_headedExpression('python', map, head)
endfor
"}}}
"}}}

" Prefixed expressions.. provide a few common default ones
call s:createLanguageDictionnaryOption('prefixedExpression') "{{{
" Python
let mappings = [
            \ ['sf', 'self = '],
            \ ['cl', 'cls = '],
            \ ]
for [map, prefix] in mappings
    call s:setDefaultOption_prefixedExpression('python', map, prefix)
endfor
"}}}

" Latex-style expressions..
call s:createLanguageDictionnaryOption('latexExpression') "{{{
" provide a few common default ones
let mappings = [
            \ ['bb', 'subsubsection'   ],
            \ ['bf', 'textbf'          ],
            \ ['ch', 'chapter'         ],
            \ ['cp', 'caption'         ],
            \ ['ct', 'cite'            ],
            \ ['ep', 'emph'            ],
            \ ['in', 'includegraphics' ],
            \ ['it', 'textit'          ],
            \ ['lb', 'label'           ],
            \ ['mb', 'mbox'            ],
            \ ['nc', 'newcommand'      ],
            \ ['pr', 'pageref'         ],
            \ ['rf', 'ref'             ],
            \ ['sb', 'subsection'      ],
            \ ['sc', 'textsc'          ],
            \ ['se', 'section'         ],
            \ ['sf', 'textsf'          ],
            \ ['tb', 'textbf'          ],
            \ ['te', 'emph'            ],
            \ ['ti', 'textit'          ],
            \ ['tt', 'texttt'          ],
            \ ['tx', 'text'            ],
            \ ['up', 'usepackage'      ],
            \ ]
for [map, head] in mappings
    call s:setDefaultOption_latexExpression('LaTeX', map, head)
endfor
"}}}

" Constant expressions.. provide a few common default ones
call s:createLanguageDictionnaryOption('constantExpression') "{{{
let mappings = [
            \ ['LaTeX', 'ex', '\expandafter'],
            \ ['LaTeX', 'hf', '\hfill '],
            \ ['LaTeX', 'hr', '\hrule'],
            \ ['LaTeX', 'ne', '\noexpand'],
            \ ['LaTeX', 'ni', '\noindent'],
            \ ['LaTeX', 'nl', '\null'],
            \ ['LaTeX', 'vf', '\vfill'],
            \ ['LaTeX', 'vr', '\vrule'],
            \ ['Rust', 'cb', 'cargo build'],
            \ ['Rust', 'cr', 'cargo run'],
            \ ['Rust', 'ct', 'cargo test'],
            \ ['R', 'go', 'graphics.off()'],
            \ ['django', 'dr', 'python manage.py runserver'],
            \ ['django', 'dk', 'python manage.py makemigrations'],
            \ ['django', 'dm', 'python manage.py migrate'],
            \ ['django', 'dt', 'python manage.py test'],
            \ ['django', 'df', 'python manage.py flush'],
            \ ]
for [language, map, prefix] in mappings
    call s:setDefaultOption_constantExpression(language, map, prefix)
endfor
"}}}

"}}}

"}}}

" TmuxSession:
" Open and close the session "{{{

" send a command to the system unless it is empty:
function! s:System(command) "{{{
    if !empty(a:command)
        call system(a:command)
    endif
endfunction
"}}}

" Check whether the session is opened or not:
function! s:isSessionOpen() "{{{
    " build shell command to query tmux:
    let query = "tmux ls 2> /dev/null | grep '^" . s:sname() . ":' -q;echo $?"
    " ask the system
    let answer = systemlist(query)
    " interpret the answer
    return !answer[0]
endfunction
"}}}

" Build and execute the call to a new tmuxed terminal
function! s:LaunchTmux() "{{{
    " build the launching command
    let launchCommand = s:terminal()
    " xterm and gnome-terminal have different launching logics, as far as I
    " understand.
    let term = s:terminal()
    if term == "gnome-terminal"
        " this one is relatively easy
        " watch out, the `-e` argument is deprecated.
        let term = "gnome-terminal -- <tmux>"
    elseif term == "xterm"
        " this is more difficult because calls are blocking
        " the following solution is the best I have found so far :\
        " TODO: understand why this is necessary and/or simplify
        " TODO: this still hungs for ages (~30s here) before vim actually
        " responds. FIX.
        let term = 'eval "nohup xterm -e ''<tmux>'' &" > /dev/null 2>&1'
    endif
    " replace the <tmux> placeholder with actual tmux command
    " TODO: escape quotes correctly
    " TODO: document
    let launchCommand = substitute(term, "<tmux>", "tmux -2 new -s " . s:sname(), "g")
    " send the command
    call s:System(launchCommand)
endfunction
"}}}
" Launch a new tmuxed session
function! s:LaunchSession() "{{{
    " Don't try to open it twice
    if s:isSessionOpen()
        echom "Intim session seems already opened"
        return
    endif
    " Open tmux!
    call s:LaunchTmux()
    " + send additionnal command if user needs it
    for i in s:get_postLaunchCommands()
        call s:System(i)
    endfor
    " dirty wait for the session to be ready:
    if s:Wait("!s:isSessionOpen()", 300, 3000)
        echom "Too long for an Intim launching wait. Aborting."
    endif
    " prepare invocation
    for i in s:get_preInvokeCommands()
        call s:Send(i)
    endfor
    " invoke the interpreter
    call s:InvokeInterpreter()
    " remove bottom bar
    " TODO: make this optional
    call s:System("tmux set -g status off;")
    " did everything go well?
    echom "Intim session launched"
endfunction

function! s:InvokeInterpreter()
    call s:Send(s:get_invokeCommand())
    " initiate the interpreter
    for i in s:get_postInvokeCommands()
        call s:Send(i)
    endfor
endfunction

function! s:ExitInterpreter()
    let ec = s:get_exitCommand()
    " if we have no exit command, use EOF
    if ec == ''
        call s:SendEOF()
    else
        call s:Send(ec)
    endif
endfunction

function! s:RestartInterpreter()
    call s:ExitInterpreter()
    call s:InvokeInterpreter()
endfunction

"}}}

" End the tmuxed session
function! s:EndSession() "{{{
    " Don't try to end it twice
    if s:isSessionOpen()
        " build the end command: tmux kill-session -t sname
        let launchCommand = "tmux kill-session -t " . s:sname()
        " send the command
        call s:System(launchCommand)
        " did everything go well?
        echom "Intim session ended"
    else
        echom "Intim session seems not launched"
    endif
endfunction
"}}}

"}}}

" SendToSession:
" Pass text and commands and signals to the session "{{{

" BasicSending:
" send plain text to the Tmuxed session unless it is empty
function! s:SendText(text) "{{{
    if !s:isSessionOpen()
        echom "No Intim session open."
        return
    endif
    if !empty(a:text)
        " build the command: tmux send -t sname TEXT
        let c = "tmux send -t " . s:sname() . " " . a:text
        call system(c)
    endif
endfunction
"}}}
" Convenience for sending an empty line
function! s:SendEnter() "{{{
    call s:SendText('ENTER')
endfunction
"}}}
" Or a keyboard interrupt
function! s:SendInterrupt() "{{{
    call s:SendText('c-c')
endfunction
"}}}
" Or an end-of-file signal
function! s:SendEOF() "{{{
    call s:SendText('c-d')
endfunction
"}}}
" Sneaky little escape tricks
function! s:HandleEscapes(text) "{{{
    " escape the escape characters
    let res = substitute(a:text, '\\', '\\\\', 'g')
    " escape the quotes
    let res = substitute(res, '\"', '\\\"', 'g')
    let res = substitute(res, "\'", "\\\'", 'g')
    " escape ending semicolons
    let res = substitute(res, ';$', '\\\;', 'g')
    " escape dollar sign
    let res = substitute(res, '\$', '\\\$', 'g')
    return res
endfunction
"}}}
" send a neat command to the Tmuxed session. `command` is either:
"   - a string, sent as a command, silent if empty
"   - a list of strings, sent as successive commands, silent if empty
function! s:Send(command) "{{{

    " Recursive call for lists:
    if type(a:command) == type([])
        for c in a:command
            call s:Send(c)
        endfor
        return
    endif

    let text = a:command
    if s:language == 'R'
        " remove roxygen2 comment sign before doctests:
        " TODO: make this work together with python doctest prompt removal
        let commentSign = "^\\s*#\'"
        if match(a:command, commentSign) > -1
            let text = substitute(a:command, commentSign, '', '')
        endif
    endif

    " main code for strings:
    " prepare the text for SendText: "command" ENTER
    " " Update from https://unix.stackexchange.com/a/472112/87656 (cheers :)
    " " Send litteral text first, then actual 'ENTER' command, or we had random
    " " commands not working like `up`, `right` or `-3` (interpreted as keywords
    " " or options)
    if !empty(text)
        let text = '-l '''' "' . s:HandleEscapes(text) . '"'
        call s:SendText(text)
        " then "press ENTER"
        call s:SendEnter()
    endif

endfunction
"}}}

" Senders:
" Send the current script line to the session
function! s:SendLine() "{{{
    let line = getline('.')
    " if the line is empty, send an empty command
    if empty(line)
        call s:SendEnter()
    else
        " TODO: gather these preprocessing into one single procedure with
        " options etc.
        if s:pythonBased(s:language)
            let line = s:RemovePythonDoctestPrompt(line)
            " TODO: make it optional
            " remove indentation
            let line = s:RemoveIndentation(line)
        endif
        call s:Send(line)
    endif
endfunction
"}}}
" Small preprocessing:
function! s:RemoveIndentation(line) "{{{
    return substitute(a:line, '^\s*', '', '')
endfunction
"}}}
" A small special case to handle
function! s:RemovePythonDoctestPrompt(line) "{{{
    let line = substitute(a:line, '^\s*>>>','', '')
    let line = substitute(line, '^\s*\.\.\.','', '')
    return line
endfunction
"}}}
" Send the current word to the session
function! s:SendWord() "{{{
    call s:Send(expand('<cword>'))
endfunction
"}}}
" Retrieve current selection content
" https://stackoverflow.com/a/6271254/3719101
function! s:getVisualSelection() "{{{
    " Why is this not a built-in Vim script function?!
    let [line_start, column_start] = getpos("'<")[1:2]
    let [line_end, column_end] = getpos("'>")[1:2]
    let lines = getline(line_start, line_end)
    if len(lines) == 0
        return ''
    endif
    let lines[-1] = lines[-1][: column_end - (&selection == 'inclusive' ? 1 : 2)]
    let lines[0] = lines[0][column_start - 1:]
    return join(lines, "\n")
endfunction
"}}}
" Send the current selection as multiple lines
function! s:SendSelection() "{{{
    let raw = s:getVisualSelection()
    " The way we'll do this depends on our interpreter/language
    if s:get_sendSelection() == 'MagicCpaste'
        call s:SendMagicCpaste()
    else
        " default
        call s:SendLineByLine()
    endif
endfunction
"}}}
" Send the current selection as plain successive lines
function! s:SendLineByLine() "{{{
    let raw = s:getVisualSelection()
    " (this is the `raw` content of the selection)
    " get each line of the selection in a different list item
    let selection = split(raw, '\n')
    " then send them all..
    for line in selection
        " .. one by one ;)
        if s:pythonBased(s:language)
            let line = s:RemovePythonDoctestPrompt(line)
            let line = s:RemoveIndentation(line)
        endif
        call s:Send(line)
    endfor
    " python-specific: if the last line was empty, better not to ignore it
    " because the interpreter might still be waiting for it
    if s:pythonBased(s:language)
        if match(selection[-1], '^\s*$') == 0
            call s:SendEnter()
        endif
    endif
endfunction
"}}}
" Send a chunk by sinking it to a temporary file
function! s:SendChunk() "{{{

    let raw = s:getVisualSelection()

    " guard: if language is not set, we cannot source a chunk
    if s:language == 'default'
        echom "Intim: No sourcing chunk without a language. "
                    \ . "Fall back on sending selection."
        call s:SendSelection()
        return
    endif

    " security
    let file = s:chunk()
    call s:CheckFile(file)

    " retrieve current selected lines:
    " python-specific: keep a minimal indent not to make the interpreter grumble
    if s:pythonBased(s:language)
        let selection = s:MinimalIndent(raw)
    else
        let selection = split(raw, '\n')
    endif
    " write this to the file
    call writefile(selection, file)
    " source this file from the interpreter:
    call s:Send(s:sourceCommand(file))

endfunction

" the latter function depends on this data:
function! s:sourceCommand(file) "{{{
    " depending on the language, return a command to source a file:
    let lang = s:language
    if s:pythonBased(lang)
        return "exec(open('". a:file ."').read())"
    elseif lang == 'R'
        return "base::source('" . a:file . "')"
    elseif lang == 'psql'
        return "\\include '" . a:file . "';"
    endif
    echoerr "Intim chunking does not support " . lang . " language yet."
    return ""
endfunction
"}}}

" Unindent text at most without loosing relative indentation
" http://vi.stackexchange.com/questions/5549/
function! s:MinimalIndent(expr) "{{{
    " `expr` is a long multilined expression
    " this returns expr split into a list (one line per item).. in such a way
    " that the minimal indentation level is now 0, but the relative indentation
    " of the lines hasn't changed.
    let lines = split(a:expr, '\n')
    " First, if this is python and there are some, remove the doctest prompts!
    if s:pythonBased(s:language)
        let pattern = '^\s*\(>>>\|\.\.\.\)'
        " Check for doctest prompt presence
        let doctest = 0
        for line in lines
            if match(line, pattern) > -1
                let doctest = 1
                break
            endif
        endfor
        if doctest
            let processed = []
            for line in lines
                if match(line, pattern) > -1
                    " remove the doctest but remember the line
                    call add(processed, substitute(line, pattern, '', ''))
                else
                    " ignore the line, it should not be a command then :)
                endif
            endfor
            let lines = processed
        endif
    endif
    " search for the smallest indentation level and record it
    let smallestLevel = 1 / 0
    let smallest = ''
    for line in lines
        if line != ''
            let indent = matchstr(line, "^\\s*")
            let indentLevel = len(indent)
            if indentLevel < smallestLevel
                let smallestLevel = indentLevel
                let smallest = indent
            endif
        endif
    endfor
    if smallestLevel > 0
        " Remove the smallest indent to each line
        for i in range(len(lines))
            let lines[i] = substitute(lines[i], smallest, '', '')
        endfor
    endif
    return lines
endfun
"}}}

"}}}
" Send the whole script as saved on the disk
function! s:SendFile() "{{{
    let file = resolve(expand('%:p'))
    call s:Send(s:sourceCommand(file))
endfunction
"}}}
" Send all lines (file might not be saved):
function! s:SendAll() "{{{
    let all = getline(0, line('$'))
    for line in all
        call s:Send(line)
    endfor
endfunction
"}}}

" SpecialSenders:
" Send compilation command to latex
function! s:CompileTex(args) "{{{
    " variable number of arguments, passed as a list
    " option:
    "   'full'  pdflatex && biber && pdflatex
    "   'twice' pdflatex && pdflatex
    "   'fast'  pdflatex
    "   'lncs' pdflatex && bibtex && pdflatex && pdflatex
    "   'clean' remove all temporary tex files except produced pdf
    let option = a:args[0]
    " first optional argument: filename (no extension).
    " If not provided, pick current one.
    let filename = len(a:args) > 1? a:args[1] : expand('%:r')
    " retrieve filename and send full compilation command
    " TODO: make the compilation command more customizable, or use a third tool
    " that guesses the right command. I've heard this exists, right?
    let pdflatexcmd = "pdflatex -synctex=1 --shell-escape --halt-on-error "
    " echo colored result
    let output = " && echo '\\033[32m \ndone.\n\\033[0m' "
               \ " || echo '\\033[31m \nfailed.\n\\033[0m' "
    if option == 'full'
        let cmd = pdflatexcmd . filename . ".tex"
              \ . " && biber " . filename
              \ . " && " . pdflatexcmd . filename . ".tex"
              \ . output
    elseif option == 'twice'
        let cmd = pdflatexcmd . filename . ".tex"
              \ . " && " . pdflatexcmd . filename . ".tex"
              \ . output
    elseif option == 'lncs'
        let cmd = pdflatexcmd . filename . ".tex"
              \ . " && bibtex " . filename
              \ . " && " . pdflatexcmd . filename . ".tex"
              \ . " && " . pdflatexcmd . filename . ".tex"
              \ . output
    elseif option == 'fast'
        let cmd = pdflatexcmd . filename . ".tex"
              \ . output
    elseif option == 'clean'
        " every common latex garbage one may wish to get rid of
        let cmd = "rm -f " . filename . ".out && "
              \ . "rm -f " . filename . ".aux && "
              \ . "rm -f " . filename . ".blg && "
              \ . "rm -f " . filename . ".log && "
              \ . "rm -f " . filename . "-blx.bib && "
              \ . "rm -f " . filename . ".toc && "
              \ . "rm -f " . filename . ".xml && "
              \ . "rm -f " . filename . ".bcf && "
              \ . "rm -f " . filename . ".bbl && "
              \ . "rm -f " . filename . ".nav && "
              \ . "rm -f " . filename . ".snm && "
              \ . "rm -f " . filename . ".run.xml && "
              \ . "rm -rf figure"
    else
        echoe "Intim: CompileTex does not know option '" . option . "'!"
    endif
    " after the operation, list files to see what happened
    let cmd = cmd . " && ls -lah"
    call s:Send(cmd)
endfunction
"}}}
" Open the file produced with latex
function! s:OpenPdf(command) "{{{
    " the 'command' is a system command with user's favorite pdf viewer etc. It
    " also is a hook for her to trigger any command she likes after having
    " opened a .pdf file
    " The command will probably contain a star `*` which will be replaced by the
    " actual filename.
    let cmd = a:command
    if cmd =~ '*'
        " TODO: handle star escaping '\*' if needed
        let filename = expand('%:r') . '.pdf'
        if empty(glob(filename))
            echoe "no " . filename . " file found"
            return
        endif
        let cmd = substitute(a:command, '*', filename, 'g')
    endif
    call s:Send(cmd)
endfunction
"}}}
" Send the current selection as an ipython/sage `%cpaste`
function! s:SendMagicCpaste() "{{{
    let raw = s:getVisualSelection()
    " Workaround ipython/sage autoindent procedure
    " https://github.com/kassio/neoterm/issues/71
    " The solution is to:
    " - use the selection as whole plain text
    " - invoke ipython's magic `%cpaste` command
    " - append an explicit end-of-file command
    " - send it as-is
    " whole selection
    let selection = s:HandleEscapes(raw)
    " append end-of file to tmux command (+ one CR for inlined case)
    let text = '"' . selection . '" c-d'
    " invoke ipython's magic command
    call s:Send('%cpaste')
    " and send!
    call s:SendText(text)
endfunction
"}}}
"}}}

" ReadHelp:
" Access interpreter's man page from within Vim "{{{

function! s:GetHelp(topic) "{{{

    " guard: if language is not set, we cannot source get help
    if s:language == 'default'
        echom "Intim: No help without a language."
        return
    endif

    " security
    let file = s:help()
    call s:CheckFile(file)

    " sink interpreter help page to the help file.. somehow
    call writefile([], file)
    call s:SinkHelp(a:topic, file)
    " dirty wait for this to be done:
    function! s:IsEmpty(file)
        return systemlist("test -s " . a:file . "; echo $?")[0]
    endfunction
    if s:Wait("s:IsEmpty('" . file . "')", 300, 3000)
        echom "Intim: Too long to get help. Weird. Aborting."
    endif
    " there are weird ^H, take'em off
    " TODO: how'da do that in place without an intermediate file?
    let interm = fnamemodify(file, ':h') . '/tp'
    " (http://stackoverflow.com/a/1298970/3719101)
    call system("perl -0pe 's{([^\\x08]+)(\\x08+)}{substr$1,0,-length$2}eg' "
                \ . file . " > " . interm
                \ . "; mv " . interm . " " . file . "; rm " . interm)

    " open it in another tab
    if bufexists(file)
        execute "bdelete! " . file
    endif
    execute "tabnew " . file
    " decorate it
    set buftype=nofile
    set readonly
    execute "setlocal syntax=" . s:get_helpSyntax()
    " there usually are snippets in man pages, which it would be a shame not to
    " be able to use as yet another script:
    call s:SetLanguage(s:language)

endfunction
"}}}
function! s:GetHelpSelection() "{{{
    call s:GetHelp(s:getVisualSelection())
endfunction
"}}}

" Write a man page to a file
function! s:SinkHelp(topic, file) "{{{
    let help = a:file
    let chunk = s:chunk()
    call s:CheckFile(chunk)
    " build a small script to write help to a file
    if s:pythonBased(s:language)
        let script  = [
          \ "import pydoc",
          \ "with open('" . help . "', 'w') as file:",
          \ "    print(pydoc.render_doc(" . a:topic . "), file=file)",
          \ ""]
    elseif s:language == 'R'
        let script = [
          \ "help_file <- as.character(help(" . a:topic . "))",
          \ "sink('" . help . "')",
          \ "tools:::Rd2txt(utils:::.getHelpFile(as.character(help_file)))",
          \ "sink()",
          \ ""]
    else
        echoerr "Intim does not support " . s:language . " help yet."
    endif
    " write it to the chunk file
    call writefile(script, chunk)
    " source it from the interpreter
    call s:Send(s:sourceCommand(chunk))
endfunction
"}}}

"}}}

" Colors:
" Use interpreter's introspection to produces dynamic syntax files "{{{

function! s:MatchingFiles() "{{{
    " lists every opened buffer whose name matches the pattern
    let pattern = s:get_filePattern()
    let result = []
    for i in range(bufnr('$') + 1)
        if bufloaded(i)
            let fname = expand('#'.i.':p') " full path
            if match(fname, pattern) > -1
                " slack it between quotes
                call add(result, "\"".fname."\"")
            endif
        endif
    endfor
    return result
endfunction
"}}}

function! s:UpdateColor() "{{{
    " The introspection script is part of this plugin
    let lang = s:language
    if s:pythonBased(lang)
        let script = s:path . "/plugin/syntax.py"
    elseif lang == 'R'
        let script = s:path . "/plugin/syntax.R"
    elseif lang == 'default'
        echoerr "There is no default Intim color updating."
        return
    else
        echoerr "Intim does not support " . lang . " color updating yet."
        return
    endif
    " copy the script to chunk file, fill the missing fields
    let chunk = s:chunk()
    call s:CheckFile(chunk)
    let path = substitute(s:vimsyntax(), '/', '\\/', 'g')
    call system("sed 's/INTIMSYNTAXFILE/\"" . path . "\"/' " . script
                \ . "> " . chunk)
    let user_script = substitute(expand('%:p'), '/', '\\/', 'g')
    let files = s:MatchingFiles()
    " escape slashes for sed
    let files = substitute(join(files, ', '), '/', '\\/', 'g')
    call system("sed -i 's/USERSCRIPTFILES/" . files . "/' " . chunk)
    " produce the syntaxfile
    call s:Send(s:sourceCommand(chunk))
    " dirty wait for it to finish: the syntax program should end it by a special
    " line: a "finish" sign
    function! s:isSyntaxWriten(syntax) "{{{
        let lastLine = systemlist("cat " . a:syntax . " | tail -n 1")[0]
        let finished = lastLine == "\" end"
        if finished
            " if it is finished, erase the sign for next time or it will be
            " considered "finished" even if nothing has been updated.
            let cmd = 'echo "\" considered as finished by intim." >> '.a:syntax
            let out = system(cmd)
        endif
        return finished
    endfunction
    "}}}
    if s:Wait("!s:isSyntaxWriten(s:vimsyntax())", 300, 3000)
        echom "Intim: syntax is too long to be written. Aborting."
        call s:SendInterrupt()
        return
    endif
    call s:ReadColor()
endfunction
" }}}

function s:ReadColor() " {{{
    if !s:isSessionOpen()
        return
    endif
    " reset current syntax
    syntax clear
    syntax on
    " set the syntax group meaning
    let higroups = s:get_highlightGroups()
    for group in keys(higroups)
        execute "highlight link " . group . " " . higroups[group]
    endfor
    " and add the 'metasyntax' produced
    execute "source " . s:vimsyntax()
    " + hardcoded special cases:
    " standard `self` and `cls` identifiers:
    syntax keyword IntimPyStandard self cls
    " Hackish part: conflict between native python syntax coloring and Intim:
    " classes names are considered as `pythonFunction` in declarations, why?
    " regex taken from /usr/share/vim/vim80/syntax/python.vim by Zvezdan
    " Petkovic <zpetkovic@acm.org>:
    syntax match IntimPyClass
      \ "\%(\%(^\s*\)\%(\%(>>>\|\.\.\.\)\s\+\)\=\%(class\)\s\+\)\@<=\h\w*"
    " duplicated, sorry:
    syntax match IntimPyMethod
      \ "\%(\%(^\s*\)\%(\%(>>>\|\.\.\.\)\s\+\)\=\%(def\)\s\+\)\@<=\h\w*"
    " TODO: make this editable by user? Higlight groups in this list will be
    " cleared at this point, in order not to mask intim colors:
    let overriding_groups = ['pythonFunction'] " defined by EasyTags plugin
    for group in overriding_groups
        if hlexists(group)
            execute "syntax clear " . group
        endif
    endfor
    " in the end, execute custom user's syntax, provided as a function
    execute 'call ' . s:get_syntaxFunction() . '()'
endfunction
"}}}

" call it each time you enter a python buffer
" TODO: adapt it for R and for the `filePattern` logic
augroup Intim_syntax
    autocmd!

    autocmd BufEnter *.py call s:ReadColor()

augroup end

"}}}

" Misc:
" Not sorted yet "{{{

" Wait for something to finish
function! s:Wait(criterion, timeStep, maxWait) "{{{
    " `criterion` is a string expression to evaluate
    " return 0 when done, 1 if aborted
    function! s:eval(text)
        execute "return " . a:text
    endfunction
    let actualWait = 0
    while s:eval(a:criterion)
        execute "sleep " . a:timeStep . "m"
        let actualWait += a:timeStep
        if actualWait > a:maxWait
            return 1
        endif
    endwhile
    return 0
endfunction
"}}}

" go to the next line of script (skip comments and empty lines)
function! s:NextScriptLine() "{{{
    " plain regex search
    call search(s:readOption(s:regexNextLine), 'W')
endfunction

" The latter function depends on this data:
let s:regexNextLine = {'default': "^.\\+$",
                    \  'python': "^\\(\\s*#\\)\\@!.",
                    \  'R':      "^\\(\\s*#\\)\\@!."}
"}}}

" wrap a selection into an expression (not to depend on vim-surround
" https://github.com/tpope/vim-surround)
function! s:Wrap(head, delimiters) "{{{
    let starter = a:delimiters[0]
    let ender   = a:delimiters[1]
    " get the last selected area
    let [start, end] = [getpos("'<"), getpos("'>")]
    " to the `end` first before it gets invalid
    call setpos('.', end)
    execute "normal! a" . ender
    " then add the head
    call setpos('.', start)
    execute "normal! i" . a:head . starter
    " get back to the end if vim can do it
    execute "normal! %"
endfunction
"}}}

"}}}

" Maps:
" Provide user mapping opportunities "{{{

" BasicMaps:
" plain shortcuts to script functions "{{{

" Convenience macro for declaring and guarding default maps: "{{{
" Should be called only once per argument set
function! s:declareMap(type, name, effect, default)
    " Declare the <Plug> specific map prefixed with Intim-
    let plug = "<Plug>Intim" . a:name
    let sid  = "<SID>" . a:name
    execute a:type . "noremap <unique> <script> " . plug . " " . sid
    " Explicit its effect:
    execute a:type . "noremap " . sid . " " . a:effect
    " Guard and set the default map we are offering (if we intend offering any)
    if !empty(a:default)
        " Don't set the default if the user has already a map to this one
        execute "let userHas = hasmapto('" . plug . " ')"
        if !userHas
            " Don't set the default if it somehow overwrites another map
            execute "let overwrites = !empty(maparg('" . a:default
                        \ . "', '" . a:type . "'))"
            if !overwrites
                execute a:type . "map <unique> " . a:default . " " . plug
            else
                " TODO: this is better silent. But what if user doesn't
                " understand why a mapping is not there? There should be a
                " special case for hotkeys.
                " echom "Intim: won't " . a:type . "map " . a:default . " to "
                        " \ . plug . " because it would overwrite another map."
            endif
        endif
    endif
endfunction
"}}}

" Launch the tmuxed session
call s:declareMap('n', 'LaunchSession',
            \ ":call <SID>LaunchSession()<cr>",
            \ "<F10>")
" End the tmuxed session
call s:declareMap('n', 'EndSession',
            \ ":call <SID>EndSession()<cr>",
            \ "<F2>")
" Send keyboard enter to the session
call s:declareMap('n', 'SendEnter',
            \ ":call <SID>SendEnter()<cr>",
            \ "<cr>")
" Send keyboard interrupt to the session
call s:declareMap('n', 'SendInterrupt',
            \ ":call <SID>SendInterrupt()<cr>",
            \ "<c-c>")
" Send keyboard EOF to the session
call s:declareMap('n', 'SendEOF',
            \ ":call <SID>SendEOF()<cr>",
            \ "<c-e>")
" Send invoke command
call s:declareMap('n', 'InvokeInterpreter',
            \ ":call <SID>InvokeInterpreter()<cr>",
            \ ",ii")
" Send exit command
call s:declareMap('n', 'ExitInterpreter',
            \ ":call <SID>ExitInterpreter()<cr>",
            \ ",ex")
" Send restart commands
call s:declareMap('n', 'RestartInterpreter',
            \ ":call <SID>RestartInterpreter()<cr>",
            \ ",rs")
" Send line and jump to the next
call s:declareMap('n', 'SendLine',
            \ ":call <SID>SendLine()<cr>:call <SID>NextScriptLine()<cr>",
            \ "<space>")
" Send line static
call s:declareMap('n', 'StaticSendLine',
            \ ":call <SID>SendLine()<cr>",
            \ "c<space>")
" Send word under cursor
call s:declareMap('n', 'SendWord',
            \ ":call <SID>SendWord()<cr>",
            \ ",<space>")
" Send selection as multiple lines, without loosing it
call s:declareMap('v', 'StaticSendSelection',
            \ "<esc>:call <SID>SendSelection()<cr>gv",
            \ ",<space>")
" (for an obscure reason, the function is called twice from visual mode, hence
" the <esc> and gv)
" Send selection as multiple lines then jump to next
call s:declareMap('v', 'SendSelection',
            \ "<esc>:call <SID>SendSelection()<cr>"
            \ . ":call <SID>NextScriptLine()<cr>",
            \ "c<space>")
" Send chunk and keep it
call s:declareMap('v', 'StaticSendChunk',
            \ "<esc>:call <SID>SendChunk()<cr>gv",
            \ ",<space>")
" Send chunk and move on
call s:declareMap('v', 'SendChunk',
            \ "<esc>:call <SID>SendChunk()<cr>"
            \ . ":call <SID>NextScriptLine()<cr>",
            \ "<space>")
" Send the whole script as a chunk
call s:declareMap('n', 'SendFile',
            \ ":call <SID>SendFile()<cr>",
            \ "a<space><space>")
" Send all lines
call s:declareMap('n', 'SendAll',
            \ ":call <SID>SendAll()<cr>",
            \ "")

" Get help about the  word under cursor
call s:declareMap('n', 'GetHelpWord',
            \ ":call <SID>GetHelp(expand('<cword>'))<cr>",
            \ "<F1>")
" Get help about the selection
call s:declareMap('v', 'GetHelpSelection',
            \ "<esc>:call <SID>GetHelpSelection()<cr>",
            \ "<F1>")

" Update coloring
call s:declareMap('n', 'UpdateColor',
            \ ":call <SID>UpdateColor()<cr>",
            \ ",uc")

" Special LaTeX case: send compilation commands etc
augroup intimLaTeX
    autocmd!

    " "Latex Compile"
    autocmd FileType tex call s:declareMap('n', 'TexCompileFast',
                \ ":w<cr>:call <SID>CompileTex(['fast'])<cr>",
                \ ",lc")
    " big "Latex Compile"
    autocmd FileType tex call s:declareMap('n', 'TexCompileFull',
                \ ":w<cr>:call <SID>CompileTex(['full'])<cr>",
                \ ",Lc")
    " "Make clean"
    autocmd FileType tex call s:declareMap('n', 'TexClean',
                \ ":call <SID>CompileTex(['clean'])<cr>",
                \ ",mc")
    " "x" stop latex compilation when there is an error
    autocmd FileType tex call s:declareMap('n', 'TexInterrupt',
                \ ":call <SID>Send('x')<cr>",
                \ "<c-x>")
    " "TeX Open" Open produced files
    autocmd FileType tex call s:declareMap('n', 'OpenPdf',
                \ ":call <SID>OpenPdf(g:intim_openPdf_command)<cr>",
                \ ",to")

    " Only do this once
    autocmd FileType tex autocmd! intimLaTeX

augroup end
"}}}

" Hotkeys:
" Convenient shortcut to wrap pieces of script inside expressions "{{{

" Convenience macro guard before mapping anything
function! s:CheckAndDeclare(type, map, effect) "{{{
    " Compare the effect to the map already in place. If it is ours or empty,
    " okay, if not, do *not* overwrite it or we may break user's ones. In order
    " to check whether it is ours, <SID> will have to be expanded into <SNR>X_
    let already = maparg(a:map, a:type)
    " adapted from :help SID<cr>
    let snr = matchstr(expand('<sfile>'), '\zs<SNR>\d\+_\zeCheckAndDeclare$')
    let actualEffect = substitute(a:effect, '<SID>', snr, 'g')
    if empty(already)
        execute a:type . "noremap <unique> <buffer> " . a:map . ' ' . a:effect
    elseif already != actualEffect
        " TODO: think better about cases where such a message is wanted.
        " echom "Intim: "
            " \ . a:map . " already has a " . a:type . "map, hotkey aborted."
    endif
endfunction
"}}}

" all hotkeys expressions are stored here
let s:hotkeys_expressions = {}

" Define one hotkey map: send an expression containing either visually selected
" area or the word under cursor. The expression is written with `*` representing
" the variable part.
" TODO: handle actual `*` characters escaping
function! s:DefineHotKey(shortcut, expression) "{{{
    " called while reading user's :hotkeys:

    " fill up the dict
    let s:hotkeys_expressions[a:shortcut] = a:expression

    " final mapping for user
    let map = s:get_hotkeys_nleader() . a:shortcut

    for mode in ['n', 'v']
        call s:CheckAndDeclare(mode, map,
            \ ":call <SID>SendHotkey('" . a:shortcut . "', '" . mode . "')<cr>")
    endfor

endfunction

" Function actually called when using a hotkey
" Searches for the right expression to replace with the shortcut as a key
" Depending on the 'v' or 'n' mode, fill it up with '<cword>' or '@*'
function! s:SendHotkey(shortcut, mode)

    " retrieve expression
    let expression = s:hotkeys_expressions[a:shortcut]

    " replace placeholder `*` with either..
    if a:mode == 'v'
        " visually selected area
        let content = s:getVisualSelection()
    else
        " or word under cursor
        let content = expand('<cword>')
    endif
    " & needs to be escaped: see :help sub-replace-special
    let content = substitute(content, '&', '\\\&', 'g')
    let expression = substitute(expression, '*', content, 'g')

    " and send that :)
    call s:Send(expression)

endfunction

"}}}

" Here is a special, predefined case expression: headed expressions of the form
" `head(*)`. The interest is that comes with edition bonuses: these mappings do
" not send commands to the Intim session, but they allow editing script.
" TODO: make EditBonuses optional
function! s:DefineHeadedExpression(shortcut, head) "{{{
    " called while reading users headed-hotkeys

    " define actual sender mappings
    call s:DefineHotKey(a:shortcut, a:head . '(*)')

    " EditBonus: one insertion map working as a small snippet
    let map = s:get_hotkeys_edit_ileader() . a:shortcut
    let effect = a:head . "()<left>"
    call s:CheckAndDeclare('i', map, effect)

    " EditBonus: wrap a word in the script in normal mode
    let map = s:get_hotkeys_edit_nleader() . a:shortcut
    let effect = "viwv:call <SID>Wrap('" . a:head . "', '()')<cr>"
    call s:CheckAndDeclare('n', map, effect)

    " EditBonus: wrap a selection in the script in visual mode
    let map = s:get_hotkeys_edit_vleader() . a:shortcut
    let effect = "<esc>:call <SID>Wrap('" . a:head . "', '()')<cr>"
    call s:CheckAndDeclare('v', map, effect)

endfunction
"}}}

" Here is another special case for LaTeX-style headed expressions `\head{*}`
function! s:DefineLaTeXExpression(shortcut, head) "{{{
    " called while reading users headed-hotkeys

    " define actual sender mappings
    call s:DefineHotKey(a:shortcut, '\' . a:head . '{*}')

    " EditBonus: one insertion map working as a small snippet
    let map = s:get_hotkeys_edit_ileader() . a:shortcut
    let effect = '\' . a:head . "{}<left>"
    call s:CheckAndDeclare('i', map, effect)

    " EditBonus: wrap a word in the script in normal mode
    let map = s:get_hotkeys_edit_nleader() . a:shortcut
    let effect = "viwv:call <SID>Wrap('\\" . a:head . "', '{}')<cr>"
    call s:CheckAndDeclare('n', map, effect)

    " EditBonus: wrap a selection in the script in visual mode
    let map = s:get_hotkeys_edit_vleader() . a:shortcut
    let effect = "<esc>:call <SID>Wrap('\\" . a:head . "', '{}')<cr>"
    call s:CheckAndDeclare('v', map, effect)

endfunction
"}}}

" Here is another special case for simple prefixed expressions: `prefix*`
function! s:DefinePrefixedExpression(shortcut, prefix) "{{{
    " called while reading users headed-hotkeys

    " define actual sender mappings
    call s:DefineHotKey(a:shortcut, a:prefix . '*')

    " EditBonus: one insertion map working as a small snippet
    let map = s:get_hotkeys_edit_ileader() . a:shortcut
    let effect = a:prefix
    call s:CheckAndDeclare('i', map, effect)

    " EditBonus: prefix a word in the script in normal mode
    let map = s:get_hotkeys_edit_nleader() . a:shortcut
    let effect = "viwovi" . a:prefix . '<esc>'
    call s:CheckAndDeclare('n', map, effect)

    " EditBonus: prefix a selection in the script in visual mode
    let map = s:get_hotkeys_edit_vleader() . a:shortcut
    let effect = "<esc>:call setpos('.', getpos(\"'<\"))<cr>i"
                \ . a:prefix . '<esc>'
    call s:CheckAndDeclare('v', map, effect)

endfunction
"}}}

" Here is another special case for constant expression `constant`
function! s:DefineConstantExpression(shortcut, constant) "{{{
    " called while reading users headed-hotkeys

    " define actual sender mappings
    " TODO: this should escape '*'
    call s:DefineHotKey(a:shortcut, a:constant)

    " EditBonus: one insertion map working as a small snippet
    let map = s:get_hotkeys_edit_ileader() . a:shortcut
    let effect = a:constant
    call s:CheckAndDeclare('i', map, effect)

    " EditBonus: insert constant before a word in the script in normal mode
    let map = s:get_hotkeys_edit_nleader() . a:shortcut
    let effect = "viwovi" . a:constant . '<esc>'
    call s:CheckAndDeclare('n', map, effect)

    " EditBonus: insert constant before a selection in the script in visual mode
    let map = s:get_hotkeys_edit_vleader() . a:shortcut
    let effect = "<esc>:call setpos('.', getpos(\"'<\"))<cr>i"
                \ . a:constant . '<esc>'
    call s:CheckAndDeclare('v', map, effect)

endfunction
"}}}

"}}}

"}}}


" lines for handling line continuation, according to :help write-plugin<CR> "{{{
let &cpo = s:save_cpo
unlet s:save_cpo
"}}}

