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
" For now, everything is designed for only ONE tmux session at a time
" Tmux session name
let g:intim_sessionName = "IntimSession"
" Which terminal to use?
let g:intim_terminal = "gnome-terminal"
" Shell command to execute after having opened the new terminal. Intent: call a
" custom script (I use it for placing, (un)decorating, marking the terminal).
" Silent if empty
let g:intim_postLaunchCommand = ""

" Utilities: "{{{
" send a command to the system unless it is empty:
function! s:System(command)
    if !empty(a:command)
        call system(a:command)
    endif
endfunction
"}}}

" Keep track of an existing opened session:
let g:intim_sessionOpen = 0

" Launch a new tmuxed session
function! s:LaunchSession()
    " Don't try to open it twice
    if g:intim_sessionOpen
        echom "Intim session seems already opened"
    else
        " build the launching command: term -e 'tmux new -s sname' &
        let launchCommand = g:intim_terminal
                    \ . " -e 'tmux new -s " . g:intim_sessionName . "' &"
        " send the command
        call s:System(launchCommand)
        " + send additionnal command if user needs it
        call s:System(g:intim_postLaunchCommand)
        " did everything go well?
        let g:intim_sessionOpen = 1
        echom "Intim session launched"
    endif
endfunction

" End the tmuxed session
function! s:EndSession()
    " Don't try to end it twice
    if g:intim_sessionOpen
        " build the end command: tmux kill-session -t sname
        let launchCommand = "tmux kill-session -t " . g:intim_sessionName
        " send the command
        call s:System(launchCommand)
        " did everything go well?
        let g:intim_sessionOpen = 0
        echom "Intim session ended"
    else
        echom "Intim session seems not launched"
    endif
endfunction

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

" lines for handling line continuation, according to :help write-plugin<CR> "{{{
let &cpo = s:save_cpo
unlet s:save_cpo
"}}}
