# Intim

*interactively interface vim with interpreters*

---

This plugin makes you open an interactive interpreter in another terminal from
Vim, like a shell, `python` or `R`. You will feed input to this terminal via
predefined or custom Vim mappings: sending commands, interrupting, restarting,
analyzing variables *etc.*

It is mostly inspired from [vim-R
plugin](https://github.com/jcfaria/Vim-R-plugin), a great plugin able do this
with R.  
Its plain intent is to extend to any interpreter and to be more customizable.

- send lines, words, visual selections, chunks and whole files to your
  interpreter
- dynamically update your syntax file to get your script variables colored as
  they get declared in your interpreter
- use custom hotkeys to send very specific expressions build from the variables
  you are pointing to
- use bonus hotkeys to actually edit your script with these specific expressions
- access and read the interpreter help from within a vim buffer

## Installation

Just like vim-R, Intim uses [tmux](https://github.com/tmux/tmux/wiki) to open a
multiplexed interactive shell session, then uses it to launch and communicate
with the interpreter. Tmux is typically installed on debian-based systems with:

    sudo apt-get install tmux

Once done, install Intim using
[pathogen](https://github.com/tpope/vim-pathogen): typically

    cd ~/.vim/bundle
    git clone https://github.com/iago-lito/intim
    
and this should be it :)

If you are using [Vundle](https://github.com/VundleVim/Vundle.vim), you have
just to add the following line to your `.vimrc`:

    Plugin 'iago-lito/intim'

Do not forget to run `:PluginInstall` after. It should be as simple as this =)


## First steps

Once you know how to launch and close an Intim session with these default
mappings

    nmap <F10> <Plug>IntimLaunchSession " or any mapping you like since..
    nmap <F2> <Plug>IntimEndSession     " these defaults will not override yours

use for instance:

- `<space>` to send the current line to your interpreter
- `,<space>` to send the word under cursor
- `,uc` to update syntax coloring as your variables and function get declared
- `,sm` hotkey to send the `summary()` of your variable to `R`
    - `;sm` edition hotkey to actually wrap your variable in the `summary()`
  expression
- `,mx` hotkey to send the `max()` of your variable in `python`
    - `;mx` edition hotkey to actually wrap your variable in the `max()`
      expression
- `<F1>` to get interpreter help about the function you are currently pointing
  to

## Configure

Remap anything you want.

Enjoy hooks to manipulate, tile, bring focus to your terminal, play sounds or
anything you like, for instance:

    call IntimLaunchCommand('python', ['cd ~'])     " first commands to tmux
    call IntimInvokeCommand('python', 'python3 -B') " invoke your interpreter

Create any new hotkey you like, for instance:

    call Intim_headedExpression('R', 'ac', 'as.character')
    call Intim_prefixedExpression('python', 'sf', 'self = ')
    call Intim_hotkeys('R', 'ii', '* <- * + 1')

See `:help intim<cr>` for more information.

## Contribute

Intim code is open. It comes with no guarantees, but also with extension points,
complete documentation, git versionning and extensive comments to encourage nice
developers to bring any new feature to it.  
Feel free to contribute of course: share, comment, report bugs, ask for
features, provide help in development, anything is good :)

## License

This package is licensed under the [GPL v3
license](http://www.gnu.org/copyleft/gpl.html). &copy; 2017 Intim contributors

