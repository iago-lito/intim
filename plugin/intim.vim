" Vim global plugin for interactive interface with interpreters: intim
" Last Change:	2016-02-21
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
"       - Debian 8, Jessie
"       - Gnome 3.14
"       - Vim 7.4 in a gnome-terminal
"     Should it need liftings in order to adapt to other environments, I'll need
"     help from users in those environments and invoke social coding. Feel free
"     to contribute :)
" InstallationCorner: Stack here dependencies, maybe provide a way to check for
" them or get them automatically?
"   - tmux
"   - gnome-terminal (default)

" Here we go.

" For now, everything is designed for only ONE tmux session at a time

" Absolute path to this plugin: http://stackoverflow.com/a/18734557/3719101
let s:path = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let g:intim_path = s:path

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
call s:declareOption('g:intim_tempchunks', "s:path . '/tmp/chunk'", 's:chunk')
" temporary file to read help in
call s:declareOption('g:intim_temphelp', "s:path . '/tmp/help'", 's:help')
" temporary syntax file update script coloration
call s:declareOption('g:intim_tempsyntax', "s:path . '/tmp/syntax'", 's:vimsyntax')
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
" From now on, Each option is stored as a dictionnary entry whose key is the
" language.

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
    if exists('g:intim_hotkeys')
        if has_key(g:intim_hotkeys, s:language)
            for hotkey in g:intim_hotkeys[s:language]
                call s:DefineHotKey(hotkey[0], hotkey[1])
            endfor
        endif
    endif

endfunction
"}}}

" Convenience macro for declaring the default dictionnary options without
" overwriting user's choices:
function! s:declareDicoOption(name, default, shorter) "{{{
    if !exists(a:name)
        " then user has not defined any such option: full default
        execute "let " . a:name . " = " . string(a:default)
    else
        " then user has defined a dictionnary, do not to overwrite these options
        execute "let users = " . a:name
        for key in keys(a:default)
            if !has_key(users, key)
                let users[key] = a:default[key]
            endif
        endfor
        " the resulting option dictionnary is a merged from both default & users
        execute "let " . a:name . " = users"
    endif
    " convenience shortcut for this script:
    execute "function! " . a:shorter . "()\n"
        \ . "    return s:readOption(" . a:name . ")\n"
        \ . "endfunction"
endfunction
"}}}

" Shell command to execute right after having opened the new terminal. Intent:
" call a custom script (I use it for placing, (un)decorating, marking the
" terminal). One string. Silent if empty.
call s:declareDicoOption('g:intim_postLaunchCommand', {
            \ 'default': []
            \ }, 's:postLaunch')

" First shell commands to execute in the session before invoking the
" interpreter. Intent: set the interpreter environment (I use it for cd-ing to
" my place, checking files). User's custom aliases should be available here.
" List of strings. One command per string. Silent if empty.
call s:declareDicoOption('g:intim_preInvokeCommands', {
            \ 'default': "cd ~"
            \ }, 's:preInvoke')

" Interpreter to invoke (e.g. `bpython`)
call s:declareDicoOption('g:intim_invokeCommand', {
            \ 'default' : "",
            \ 'python'  : "python",
            \ 'R'       : "R",
            \ 'bash'    : "bash",
            \ 'LaTex'   : "",
            \ }, 's:invoke')

" First shell commands to execute in the session before invoking the
" interpreter. Intent: set the interpreter environment (I use it for cd-ing to
" my place, checking files). User's custom aliases should be available here.
" List of strings. One command per string. Silent if empty.
call s:declareDicoOption('g:intim_postInvokeCommands', {
            \ 'default': ""
            \ }, 's:postInvoke')

" Default script highlighting
" TODO: make sure those syntax file are neat and available
call s:declareDicoOption('g:intim_syntax', {
            \ 'default' : "",
            \ 'python'  : "python",
            \ 'R'       : "r",
            \ }, 's:syntax')

" Help highlighting
" TODO: make sure those syntax file are neat and available
call s:declareDicoOption('g:intim_helpSyntax', {
            \ 'default' : "",
            \ 'python'  : "pydoc",
            \ 'R'       : "rdoc",
            \ }, 's:helpSyntax')

" Leaders for hotkeys
call s:declareDicoOption('g:intim_hotkeys_nleader', {
            \ 'default': ','
            \ }, 's:nleader')
call s:declareDicoOption('g:intim_hotkeys_vleader', {
            \ 'default': ','
            \ }, 's:vleader')
call s:declareDicoOption('g:intim_hotkeys_edit_ileader', {
            \ 'default': ','
            \ }, 's:ieleader')
call s:declareDicoOption('g:intim_hotkeys_edit_nleader', {
            \ 'default': '-;'
            \ }, 's:neleader')
call s:declareDicoOption('g:intim_hotkeys_edit_vleader', {
            \ 'default': '-;'
            \ }, 's:veleader')

" Highlight groups for supported syntax groups, they depend on the language
" TODO: user must set all supported groups or the defaults will not apply.. that
" ain't no nice, eh?
call s:declareDicoOption('g:intim_highlightgroups', {
            \ 'default': {},
            \ 'R': {
                \   'IntimRIdentifier' : 'Identifier',
                \   'IntimRFunction'   : 'Function',
                \  }
            \ }, 's:higroups')

" Read a particular option from a dictionnary or return the default one
function! s:readOption(dico) "{{{
    if has_key(a:dico, s:language)
        return a:dico[s:language]
    else
        return a:dico['default']
    endif
endfunction
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

" Launch a new tmuxed session
function! s:LaunchSession() "{{{
    " Don't try to open it twice
    if s:isSessionOpen()
        echom "Intim session seems already opened"
    else
        " build the launching command: term -e 'tmux new -s sname' &
        let launchCommand = s:terminal()
                    \ . " -e 'tmux new -s " . s:sname() . "' &"
        " send the command
        call system(launchCommand)
        " + send additionnal command if user needs it
        call s:System(s:postLaunch())
        " dirty wait for the session to be ready:
        if s:Wait("!s:isSessionOpen()", 300, 3000)
            echom "Too long for an Intim launching wait. Aborting."
        endif
        " prepare invocation
        call s:Send(s:preInvoke())
        " invoke the interpreter
        call s:Send(s:invoke())
        " initiate the interpreter
        call s:Send(s:postInvoke())
        " did everything go well?
        echom "Intim session launched"
    endif
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
function! s:SendEmpty() "{{{
    call s:SendText('ENTER')
endfunction
"}}}
" Or a keyboard interrupt
function! s:SendInterrupt() "{{{
    call s:SendText('c-c')
endfunction
"}}}
" Sneaky little escape tricks
function! s:HandleEscapes(text) "{{{
    " escape the escape characters
    let res = substitute(a:text, '\\', '\\\\', 'g')
    " escape the quote
    let res = substitute(res, "\"", '\\\"', 'g')
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

    " main code for strings:
    " prepare the text for SendText: "command" ENTER
    if !empty(a:command)
        let text = '"' . s:HandleEscapes(a:command) . '" ENTER'
        call s:SendText(text)
    endif

endfunction
"}}}

" Senders:
" Send the current script line to the session
function! s:SendLine() "{{{
    let line = getline('.')
    " if the line is empty, send an empty command
    if empty(line)
        call s:SendEmpty()
    else
        call s:Send(line)
    endif
endfunction
"}}}
" Send the current word to the session
function! s:SendWord() "{{{
    call s:Send(expand('<cword>'))
endfunction
"}}}
" Send the current selection as multiple lines
function! s:SendSelection(raw) "{{{
    " (this is the `raw` content of the selection)
    " get each line of the selection in a different list item
    let selection = split(a:raw, '\n')
    " then send them all!
    for line in selection
        call s:Send(line)
    endfor
    " python-specific: if the last line was empty, better not to ignore it
    " because the interpreter might still be waiting for it
    if s:language == 'python'
        if match(selection[-1], '^\s*$') == 0
            call s:SendEmpty()
        endif
    endif
endfunction
"}}}
" Send a chunk by sinking it to a temporary file
function! s:SendChunk(raw) "{{{

    " guard: if language is not set, we cannot source a chunk
    if s:language == 'default'
        echom "Intim: No sourcing chunk without a language. "
                    \ . "Fall back on line-by-line."
        call s:SendSelection(raw)
        return
    endif

    " security
    let file = s:chunk()
    call s:CheckFile(file)

    " retrieve current selected lines:
    " python-specific: keep a minimal indent not to make the interpreter grumble
    if s:language == 'python'
        let selection = s:MinimalIndent(a:raw)
    else
        let selection = split(a:raw, '\n')
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
    if lang == 'python'
        return "exec(open('". a:file ."').read())"
    elseif lang == 'R'
        return "base::source('" . a:file . "')"
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
    let raw = join(all, "\n")
    call s:SendChunk(raw)
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
    if s:Wait("s:IsEmpty(file)", 300, 3000)
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
    execute "setlocal syntax=" . s:helpSyntax()
    " there usually are snippets in man pages, which it would be a shame not to
    " be able to use as yet another script:
    call s:SetLanguage(s:language)

endfunction
"}}}

" Write a man page to a file
function! s:SinkHelp(topic, file) "{{{
    let help = a:file
    let chunk = s:chunk()
    call s:CheckFile(chunk)
    " build a small script to write help to a file
    if s:language == 'python'
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
function! s:UpdateColor() "{{{
    " The introspection script is part of this plugin
    if s:language == 'python'
        let script = s:path . "/plugin/syntax.py"
    elseif s:language == 'R'
        let script = s:path . "/plugin/syntax.R"
    elseif s:language == 'default'
        echoerr "There is no default Intim color updating."
        return
    else
        echoerr "Intim does not support " . s:language . " color updating yet."
        return
    endif
    " copy the script to chunk file, fill the missing field
    let chunk = s:chunk()
    call s:CheckFile(chunk)
    let path = substitute(s:vimsyntax(), '/', '\\/', 'g')
    call system("sed 's/INTIMSYNTAXFILE/\"" . path . "\"/' " . script
                \ . "> " . chunk)
    " produce the syntaxfile
    call s:Send(s:sourceCommand(chunk))
    " dirty wait for it to finish
    function! s:isSyntaxWriten(syntax) "{{{
        let lastLine = systemlist("cat " . a:syntax . " | tail -n 1")[0]
        return lastLine == "\" end"
    endfunction
    "}}}
    if s:Wait("!s:isSyntaxWriten(s:vimsyntax())", 300, 3000)
        echom "Intim: syntax is too long to be written. Aborting."
        call s:SendInterrupt()
        return
    endif
    " reset current syntax
    syntax clear
    syntax on
    " set the syntax group meaning
    let higroups = s:higroups()
    for group in keys(higroups)
        execute "highlight link " . group . " " . higroups[group]
    endfor
    " and add the 'metasyntax' produced
    execute "source " . s:vimsyntax()
endfunction
"}}}

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
let s:regexNextLine = {'default': "^.+$",
                    \  'python': "^\\(\\s*#\\)\\@!.",
                    \  'R':      "^\\(\\s*#\\)\\@!."}
"}}}

" wrap a selection into an expression (not to depend on vim-surround)
function! s:Wrap(head) "{{{
    " get the last selected area
    let [start, end] = [getpos("'<"), getpos("'>")]
    " to the `end` first before it gets invalid
    call setpos('.', end)
    execute "normal! a)"
    " then add the head
    call setpos('.', start)
    execute "normal! i" . a:head . "("
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
" Send keyboard interrupt to the session
call s:declareMap('n', 'Interrupt',
            \ ":call <SID>SendInterrupt()<cr>",
            \ "<c-c>")
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
            \ "<esc>:call <SID>SendSelection(@*)<cr>gv",
            \ "c<space>")
" (for an obscure reason, the function is called twice from visual mode, hence
" the <esc> and gv)
" Send selection as multiple lines then jump to next
call s:declareMap('v', 'SendSelection',
            \ "<esc>:call <SID>SendSelection(@*)<cr>"
            \ . ":call <SID>NextScriptLine()<cr>",
            \ "")
" Send chunk and keep it
call s:declareMap('v', 'StaticSendChunk',
            \ "<esc>:call <SID>SendChunk(@*)<cr>gv",
            \ ",<space>")
" Send chunk and move on
call s:declareMap('v', 'SendChunk',
            \ "<esc>:call <SID>SendChunk(@*)<cr>"
            \ . ":call <SID>NextScriptLine()<cr>",
            \ "<space>")
" Send the whole script
call s:declareMap('n', 'SendFile',
            \ ":call <SID>SendFile()<cr>",
            \ "")
" Send all lines as a chunk
call s:declareMap('n', 'SendAll',
            \ ":call <SID>SendAll()<cr>",
            \ "a<space><space>")

" Get help about the  word under cursor
call s:declareMap('n', 'GetHelpWord',
            \ ":call <SID>GetHelp(expand('<cword>'))<cr>",
            \ "<F1>")
" Get help about the selection
call s:declareMap('v', 'GetHelpSelection',
            \ "<esc>:call <SID>GetHelp(@*)<cr>",
            \ "<F1>")

" Update coloring
call s:declareMap('n', 'UpdateColor',
            \ ":call <SID>UpdateColor()<cr>",
            \ ",uc")

"}}}

" Hotkeys:
" Convenient shortcut to wrap pieces of script inside expressions "{{{

" Convenience macro guard before mapping anything
function! s:CheckAndDeclare(type, map, effect) "{{{
    " Compare the effect to the map already in place. If it is ours or empty,
    " okay, if not, do not overwrite it. In order to check whether it is ours,
    " <SID> will have to be expanded into <SNR>X_
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

" Define one hotkey map set: simple expression: head(selection)
" TODO: update these for supportig LaTeX, expressions are `\head{selection}`
function! s:DefineHotKey(shortcut, head) "{{{
    " This function is called only if user wants it and if the current language
    " is relevant. Yet one should check for mappings availability.

    " One normal map to send a wrapped word:
    let map = s:nleader() . a:shortcut
    let effect = ":call <SID>Send('"
                \ . a:head . "(' . expand(\'<cword>\') . ')')<cr>"
    call s:CheckAndDeclare('n', map, effect)

    " One visual map to send a wrapped selection:
    let map = s:vleader() . a:shortcut
    let effect = "<esc>:call <SID>SendSelection('"
                \ . a:head . "(' . @* . ')')<cr>gv"
    call s:CheckAndDeclare('v', map, effect)

    " EditBonus: one insertion map working as a small snippet
    let map = s:ieleader() . a:shortcut
    let effect = a:head . "()<left>"
    call s:CheckAndDeclare('i', map, effect)

    " EditBonus: wrap a word in the script in normal mode
    let map = s:neleader() . a:shortcut
    let effect = "viwv:call <SID>Wrap('" . a:head . "')<cr>"
    call s:CheckAndDeclare('n', map, effect)

    " EditBonus: wrap a selection in the script in visual mode
    let map = s:veleader() . a:shortcut
    let effect = "<esc>:call <SID>Wrap('" . a:head . "')<cr>"
    call s:CheckAndDeclare('v', map, effect)

endfunction
"}}}

"}}}

" TODO: add other kinds of hotkeys, not simple wrapped headed stuff

"}}}

" Methods:
" Provide user function call opportunities "{{{

" Macro declaring and guarding user wrappers to methods:
function! s:functionExport(internalname, name) "{{{
    if !exists('*' . a:name)
        " /!\ assumption: only one argument
        execute "function " . a:name . "(arg)\n"
            \ . "    call s:" . a:internalname . "(a:arg)\n"
            \ . "endfunction"
    else
        echom a:name . "already declared, I won't overwrite it."
    endif
endfunction
"}}}

" Prefix them all with Intim-
call s:functionExport('Send'        , 'IntimSend')
call s:functionExport('SetLanguage' , 'IntimLanguage')

"}}}


" lines for handling line continuation, according to :help write-plugin<CR> "{{{
let &cpo = s:save_cpo
unlet s:save_cpo
"}}}
