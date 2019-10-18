filetype plugin indent on    " required
filetype off                 " required
syntax on
set nocompatible             " be iMproved, required

set ai                          " Auto indent
set backspace=start,indent,eol
set si                          " Smart indent
set wrap                        " Wrap lines
set expandtab                   " Use spaces when tabbing
set shiftwidth=4
set tabstop=4
set number                      " Show number lines
set cursorline                  " Sets a line under the cursor
set showmatch                   " Matches [] {} and ()
set softtabstop=4
set ch=2                        " Make command line two lines high
set matchpairs+=<:>             " Show matching <> for html and xml

" Stops the annoying :W error and just writes file
:map :W :w
" " Stops the annoying :Q error and just exits
:map :Q :q
" " add command to sudo write file
:command Sudosave :w !sudo tee %

let python_highlight_all = 1

set pastetoggle=<F2>

" " Tell vim to remember certain things when we exit
" " "  '10  :  marks will be remembered for up to 10 previously edited files
" " "  "100 :  will save up to 100 lines for each register
" " "  :20  :  up to 20 lines of command-line history will be remembered
" " "  %    :  saves and restores the buffer list
" " "  n... :  where to save the viminfo files
set viminfo='10,\"100,:20,%,n~/.viminfo

cabbrev doc Pydocstring
