" File: bufferline.vim
" Author: romgrk
" Description: Buffer line
" Date: Fri 22 May 2020 02:22:36 AM EDT
" !::exe [So]

set showtabline=2

function! bufferline#enable()
   augroup bufferline
      au!
      au BufReadPost  * call <SID>on_buffer_open(expand('<abuf>'))
      au BufNewFile   * call <SID>on_buffer_open(expand('<abuf>'))
      au BufDelete    * call <SID>on_buffer_close(expand('<abuf>'))
      au BufWritePost * call <SID>check_modified()
      au TextChanged  * call <SID>check_modified()
      au ColorScheme  * call bufferline#highlight#setup()
   augroup END

   function! s:did_load (...)
      augroup bufferline_update
         au!
         au BufNew                 * call bufferline#update()
         au BufEnter               * call bufferline#update()
         au BufWipeout             * call bufferline#update()
         au BufWinEnter            * call bufferline#update()
         au BufWinLeave            * call bufferline#update()
         au BufWritePost           * call bufferline#update()
         au SessionLoadPost        * call bufferline#update()
         au WinEnter               * call bufferline#update()
         au WinLeave               * call bufferline#update()
         au WinClosed              * call bufferline#update_async()
      augroup END

      call bufferline#update()
   endfunc
   call timer_start(25, function('s:did_load'))

   call bufferline#highlight#setup()
endfunc

function! bufferline#disable()
   augroup bufferline | au! | augroup END
   augroup bufferline_update | au! | augroup END
   let &tabline = ''
endfunc

call bufferline#enable()

"=================
" Section: Commands
"=================

command!                BarbarEnable           call bufferline#enable()
command!                BarbarDisable          call bufferline#disable()

command!          -bang BufferNext             call s:goto_buffer_relative(+1)
command!          -bang BufferPrevious         call s:goto_buffer_relative(-1)

command! -nargs=1 -bang BufferGoto             call s:goto_buffer(<f-args>)
command!          -bang BufferLast             call s:goto_buffer(-1)

command!          -bang BufferMoveNext         call s:move_current_buffer(+1)
command!          -bang BufferMovePrevious     call s:move_current_buffer(-1)

command!          -bang BufferPick             call bufferline#pick_buffer()

command!          -bang BufferOrderByDirectory call bufferline#order_by_directory()
command!          -bang BufferOrderByLanguage  call bufferline#order_by_language()

command! -bang -complete=buffer -nargs=?
                      \ BufferClose            call bufferline#bbye#delete('bdelete', <q-bang>, <q-args>)
command! -bang -complete=buffer -nargs=?
                      \ BufferDelete           call bufferline#bbye#delete('bdelete', <q-bang>, <q-args>)
command! -bang -complete=buffer -nargs=?
                      \ BufferWipeout          call bufferline#bbye#delete('bwipeout', <q-bang>, <q-args>)

"=================
" Section: Options
"=================

let bufferline = extend({
\ 'shadow': v:true,
\ 'animation': v:true,
\ 'icons': v:true,
\ 'closable': v:true,
\ 'semantic_letters': v:true,
\ 'clickable': v:true,
\ 'maximum_padding': 4,
\ 'tabpages': v:true,
\ 'letters': 'asdfjkl;ghnmxcbziowerutyqpASDFJKLGHNMXCBZIOWERUTYQP',
\}, get(g:, 'bufferline', {}))

" Default icons
let icons = extend({
\ 'bufferline_default_file': '',
\ 'bufferline_separator_active':   '▎',
\ 'bufferline_separator_inactive': '▎',
\ 'bufferline_close_tab': '',
\ 'bufferline_close_tab_modified': '●',
\}, get(g:, 'icons', {})) " 

"==========================
" Section: Bufferline state
"==========================

" Hl groups used for coloring
let s:hl_status = ['Inactive', 'Visible', 'Current']

" Last value for tabline
let s:last_tabline = ''

" Current buffers in tabline (ordered)
let s:buffers = []
let s:buffers_by_id = {} " Map<String, [nameWidth: Number, restOfWidth: Number]> 

" Last current buffer number
let s:last_current_buffer = v:null

" If the user is in buffer-picking mode
let s:is_picking_buffer = v:false

" Debugging
" let g:events = []

"========================
" Section: Main functions
"========================

function! bufferline#update()
   let new_value = bufferline#render()
   if new_value == s:last_tabline
      return
   end
   let &tabline = new_value
   let s:last_tabline = new_value
endfu

function! bufferline#update_async()
   call timer_start(1, {->bufferline#update()})
endfu

function! bufferline#render() abort
   return luaeval("require'bufferline.render'.render()")
endfu

function! bufferline#session (...)
   let name = ''

   if exists('g:xolox#session#current_session_name')
      let name = g:xolox#session#current_session_name
   end

   if empty(name)
      let name = substitute(getcwd(), $HOME, '~', '')
      if len(name) > 30
         let name = pathshorten(name)
      end
   end

   return '%#BufferPart#%( ' . name . ' %)'
endfunc

function! bufferline#pick_buffer()
   call luaeval("require'bufferline.jump_mode'.activate()")
endfunc

function! bufferline#order_by_directory()
   let new_buffers = copy(s:buffers)
   let new_buffers = map(new_buffers, {_, b -> bufname(b)})
   call sort(new_buffers, function('s:compare_directory'))
   let new_buffers = map(new_buffers, {_, b -> bufnr(b)})

   call remove(s:buffers, 0, -1)
   call extend(s:buffers, new_buffers)

   call bufferline#update()
endfunc

function! bufferline#order_by_language()
   let new_buffers = copy(s:buffers)
   let new_buffers = map(new_buffers, {_, b -> bufname(b)})
   call sort(new_buffers, function('s:compare_language'))
   let new_buffers = map(new_buffers, {_, b -> bufnr(b)})

   call remove(s:buffers, 0, -1)
   call extend(s:buffers, new_buffers)

   call bufferline#update()
endfunc

function! bufferline#close(abuf)
   call luaeval("require'bufferline.state'.close_buffer_animated(_A)", a:abuf)
endfunc

function! bufferline#close_direct(abuf)
   call luaeval("require'bufferline.state'.close_buffer(_A)", a:abuf)
endfunc

"========================
" Section: Event handlers
"========================

function! s:on_buffer_open(abuf)
   call luaeval("require'bufferline.jump_mode'.assign_next_letter(_A)", a:abuf)
endfunc

function! s:on_buffer_close(bufnr)
   call luaeval("require'bufferline.jump_mode'.unassign_letter_for(_A)", a:bufnr)
endfunc

function! s:check_modified()
   if (&modified != get(b:, 'checked'))
      let b:checked = &modified
      call bufferline#update()
   end
endfunc

" Needs to be global -_-
function! BufferlineMainClickHandler(minwid, clicks, btn, modifiers) abort
   if a:btn =~ 'm'
      call bufferline#bbye#delete('bdelete', '', a:minwid)
   else
      execute 'buffer ' . a:minwid
   end
endfunction

" Needs to be global -_-
function! BufferlineCloseClickHandler(minwid, clicks, btn, modifiers) abort
   call bufferline#bbye#delete('bdelete', '', a:minwid)
endfunction

" Buffer movement

function! s:move_current_buffer (direction)
   call luaeval("require'bufferline.state'.move_current_buffer(_A)", a:direction)
endfunc

function! s:goto_buffer (number)
   call luaeval("require'bufferline.state'.goto_buffer(_A)", a:number)
endfunc

function! s:goto_buffer_relative (direction)
   call luaeval("require'bufferline.state'.goto_buffer_relative(_A)", a:direction)
endfunc


" Helpers

function! s:close_buffer_animated(buffer_number)
   if g:bufferline.animation == v:false
      return s:close_buffer(a:buffer_number)
   end
   let buffer_data = s:get_buffer_data(a:buffer_number)
   let current_width =
            \ buffer_data.dimensions[0] +
            \ buffer_data.dimensions[1]

   let buffer_data.closing = v:true
   let buffer_data.width = current_width

   call bufferline#animate#start(150, current_width, 0, v:t_number,
            \ {new_width, state ->
            \   s:close_buffer_animated_tick(a:buffer_number, new_width, state)})
endfunc

function! s:close_buffer_animated_tick(buffer_number, new_width, state)
   if a:new_width > 0 && has_key(s:buffers_by_id, a:buffer_number)
      let buffer_data = s:get_buffer_data(a:buffer_number)
      let buffer_data.width = a:new_width
      call bufferline#update()
      return
   end
   call bufferline#animate#stop(a:state)
   call s:close_buffer(a:buffer_number)
endfunc

function! s:is_relative_path(path)
   return fnamemodify(a:path, ':p') != a:path
endfunc

function s:compare_directory(a, b)
   let ra = s:is_relative_path(a:a)
   let rb = s:is_relative_path(a:b)
   if ra && !rb
      return -1
   end
   if rb && !ra
      return +1
   end
   return a:a > a:b
endfunc

function s:compare_language(a, b)
   let ea = fnamemodify(a:a, ':e')
   let eb = fnamemodify(a:b, ':e')
   return ea > eb
endfunc


" Final setup

call luaeval("require'bufferline.state'.get_updated_buffers()")
" call s:update_buffer_letters()

let g:bufferline# = s:
