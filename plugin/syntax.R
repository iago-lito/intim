# Vim global plugin for interactive interface with interpreters: intim
# Last Change:	2016-02-21
# Maintainer:   Iago-lito <iago.bonnici@gmail.com>
# License:      This file is placed under the GNU PublicLicense 3.

# This R script is supposed to perform introspection into a particular R session
# and produce a vim syntax file gathering each declared word and an associated
# group depending on its type.

# this shall be filled before sourcing
syntaxFile <- INTIMSYNTAXFILE

# For now, only two R groups, functions and other declared variables
groups <- c(
  'id'  = 'IntimRIdentifier',
  'fun' = 'IntimRFunction'
  )

IntimIntrospection <- function(){
  # clean syntax file
  write("", syntaxFile)
  # Don't take basic names which are already handled by r.vim
  # TODO: make this more neat?
  basics <- c('function', 'in', 'for', 'do', 'while', 'if', 'else', 'return')
  basics <- c(basics, c('library', 'source', 'data.frame'))
  # iterate over packages:
  for (env in search()) {
    # retrieve all names within them
    names <- ls(env)
    # remove naughty names that would make vim syntax file fail
    dirties <- grep('[^a-zA-Z0-9\\._]', names)
    if (length(dirties) > 0)
      names <- names[-dirties]
    # remove basic names
    if (length(names) > 0)
      names <- names[!names %in% basics]
    if (length(names) > 0) {
      # stack here one line for each name:
      lines <- data.frame(
        prompt = 'syntax keyword', # vimscript command
        group  = '',               # highlighting group
        name   = names,            # identifier
        stringsAsFactors = FALSE
        )
      # fill the `group` field
      lines$group <- vapply(lines$name, function(name) # for each name
             if (any(class(get(name)) == 'function')) # get its group
               groups['fun']
             else
               groups['id'], 't')
      # collapse the whole structure into vimscript command lines
      commands <- do.call(paste, lines)
      # And write it to the file
      write(commands, syntaxFile, append=TRUE)
    }
  }
  write("\" end", syntaxFile, append=TRUE)
}

# run and forget
IntimIntrospection()
remove(IntimIntrospection)


