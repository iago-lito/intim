" Vim global plugin for interactive interface with interpreters: intim
" Last Change:	2016-02-20
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

" Options:

" Convenience macro for guarding global options
function! s:declareOption(name, default) "{{{
    execute "if !exists('" . a:name . "')\n"
        \ . "    let " . a:name . " = " . a:default . "\n"
        \ . "endif"
endfunction
"}}}

" For now, everything is designed for only ONE tmux session at a time
" Tmux session name
call s:declareOption('g:intim_sessionName', "'IntimSession'")
" Which terminal to use?
call s:declareOption('g:intim_terminal', "'gnome-terminal'")
" Language of the interpreter (e.g. `python`)
" This string will be the key for choosing which methods to use (adapted to each
" supported language) and which options to read.
" Examples : 'default', 'python', 'R', 'LaTeX', 'bash' + user-defined
call s:declareOption('g:intim_language', "'default'")

" From now on, Each option is stored as a dictionnary entry whose key is the
" language.

" Convenience macro for declaring the default dictionnary options without
" overwriting user's choices:
function! s:declareDicoOption(name, default) "{{{
    execute "if !exists('" . a:name . "')\n"
        \ . "    let " . a:name . " = {'default': " . a:default . "}\n"
        \ . "else\n"
        \ . "    if !has_key(" . a:name . ", 'default')\n"
        \ . "        let " . a:name . "['default'] = " . a:default . "\n"
        \ . "    endif\n"
        \ . "endif\n"
endfunction
"}}}

" Shell command to execute right after having opened the new terminal. Intent:
" call a custom script (I use it for placing, (un)decorating, marking the
" terminal). One string. Silent if empty.
call s:declareDicoOption('g:intim_postLaunchCommand', '[]')

" First shell commands to execute in the session before invoking the
" interpreter. Intent: set the interpreter environment (I use it for cd-ing to
" my place, checking files). User's custom aliases should be available here.
" List of strings. One command per string. Silent if empty.
call s:declareDicoOption('g:intim_preInvokeCommands', '["cd ~"]')

" Interpreter to invoke (e.g. `bpython`)
call s:declareDicoOption('g:intim_invokeCommand', '[]')

" First shell commands to execute in the session before invoking the
" interpreter. Intent: set the interpreter environment (I use it for cd-ing to
" my place, checking files). User's custom aliases should be available here.
" List of strings. One command per string. Silent if empty.
call s:declareDicoOption('g:intim_postInvokeCommands', '[]')


" Read a particular option from a dictionnary or return the default one
function! s:readOption(dico) "{{{
    if has_key(a:dico, g:intim_language)
        return a:dico[g:intim_language]
    else
        return a:dico['default']
    endif
endfunction
"}}}

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
    let query = "tmux ls 2> /dev/null | grep '^" . g:intim_sessionName . ":' -q;echo $?"
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
        let launchCommand = g:intim_terminal
                    \ . " -e 'tmux new -s " . g:intim_sessionName . "' &"
        " send the command
        call system(launchCommand)
        " + send additionnal command if user needs it
        call s:System(s:readOption(g:intim_postLaunchCommand))
        " dirty wait for the session to be ready:
        let timeStep = 300 " miliseconds
        let maxWait = 3000
        let actualWait = 0
        while !s:isSessionOpen()
            execute "sleep " . timeStep . "m"
            let actualWait += timeStep
            if actualWait > maxWait
                echom "Too long for an Intim launching wait. Aborting."
                return
            endif
        endwhile
        " prepare invocation
        call s:Send(s:readOption(g:intim_preInvokeCommands))
        " invoke the interpreter
        call s:Send(s:readOption(g:intim_invokeCommand))
        " initiate the interpreter
        call s:Send(s:readOption(g:intim_postInvokeCommands))
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
        let launchCommand = "tmux kill-session -t " . g:intim_sessionName
        " send the command
        call s:System(launchCommand)
        " did everything go well?
        echom "Intim session ended"
    else
        echom "Intim session seems not launched"
    endif
endfunction
"}}}

" send plain text to the Tmuxed session unless it is empty
function! s:SendText(text) "{{{
    if !empty(a:text)
        " build the command: tmux send -t sname TEXT
        let c = "tmux send -t " . g:intim_sessionName . " " . a:text
        call system(c)
    endif
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
        let text = '"' . a:command . '" ENTER'
        call s:SendText(text)
    endif

endfunction
"}}}

" Now map these to something cool: "{{{
" Set the <Plug> specific maps
nnoremap <unique> <script> <Plug>IntimLaunchSession <SID>LaunchSession
nnoremap <unique> <script> <Plug>IntimEndSession <SID>EndSession
" Set the calls to the functions, local to this script
nnoremap <SID>LaunchSession :call <SID>LaunchSession()<cr>
nnoremap <SID>EndSession    :call <SID>EndSession()<cr>
" And set the default maps (without interfering with user's preferences)
if !hasmapto("<Plug>IntimLaunchSession")
    nmap <unique> <F10> <Plug>IntimLaunchSession
endif
if !hasmapto("<Plug>IntimEndSession")
    nmap <unique> <F2> <Plug>IntimEndSession
endif
"}}}

" Provide wrappers to methods:
if !exists('*IntimSend')
    function IntimSend(commands)
        call s:Send(a:commands)
    endfunction
endif

" lines for handling line continuation, according to :help write-plugin<CR> "{{{
let &cpo = s:save_cpo
unlet s:save_cpo
"}}}
