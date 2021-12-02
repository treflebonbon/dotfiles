call plug#begin()
Plug 'dracula/vim', { 'as': 'dracula' }
call plug#end()

if filereadable(expand("~/.vim/plugged/dracula/colors/dracula.vim"))
  colorscheme dracula
endif

set t_Co=256

set encoding=utf-8
scriptencoding utf-8
set fileencoding=utf-8
set fileencodings=ucs-boms,utf-8,euc-jp,cp932
set fileformats=unix,dos,mac
set ambiwidth=double

set laststatus=2
set showmode
set showcmd
set ruler

set wildmenu
set history=5000

set expandtab
set tabstop=2
set shiftwidth=2
set softtabstop=2
set autoindent
set smartindent

set incsearch
set ignorecase
set smartcase
set hlsearch
set wrapscan
nnoremap <silent><Esc><Esc> :<C-u>set nohlsearch!<CR>

set whichwrap=b,s,h,l,<,>,[,],~
set number
set cursorline

nnoremap j gj
nnoremap k gk
nnoremap <down> gj
nnoremap <up> gk

set backspace=indent,eol,start

set showmatch
source $VIMRUNTIME/macros/matchit.vim

set viminfo=
set noswapfile
set nobackup
set autoread
set hidden
set clipboard=unnamed,autoselect

set title
set nocompatible
set list
set listchars=tab:»-,trail:-,extends:»,precedes:«,nbsp:%
set paste
