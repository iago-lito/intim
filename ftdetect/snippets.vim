" recognize interpreter files
if has("autocmd")

    " recognize R files
    autocmd BufNewFile,BufRead *.R setf r
    autocmd BufNewFile,BufRead *.r setf r
    autocmd BufNewFile,BufRead *Rprofile setf r

    " recognize python files
    autocmd BufNewFile,BufRead *.py setf python
    autocmd BufNewFile,BufRead *pythonrc setf python
    autocmd BufNewFile,BufRead *.sage setf python

    " recognize latex files
    autocmd BufNewFile,BufRead *.tex setf tex
    autocmd BufNewFile,BufRead *.bib setf tex
    autocmd BufNewFile,BufRead *.cls setf tex

    " recognize Rust files
    autocmd BufNewFile,BufRead *.rs setf rust

    " recognize shell files
    autocmd BufNewFile,BufRead *.sh setf sh
    autocmd BufNewFile,BufRead *.bash setf sh
    autocmd BufNewFile,BufRead *.zsh setf sh

endif
