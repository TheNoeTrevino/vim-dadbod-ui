let s:suite = themis#suite('Connection groups')
let s:expect = themis#helper('expect')

function! s:db_url() abort
  return 'sqlite:'.fnamemodify('test/dadbod_ui_test.db', ':p')
endfunction

function! s:suite.before_each() abort
  let g:dbs = [
        \ { 'name': 'first', 'url': s:db_url(), 'group': 'Group A' },
        \ { 'name': 'second', 'url': s:db_url(), 'group': 'Group A' },
        \ { 'name': 'loose', 'url': s:db_url() },
        \ ]
endfunction

function! s:suite.after_each() abort
  call Cleanup()
endfunction

function! s:suite.should_render_group_headers_with_indented_members() abort
  :DBUI
  call s:expect(&filetype).to_equal('dbui')
  call s:expect(getline(1, '$')).to_equal([
        \ '▾ Group A',
        \ '  ▸ first',
        \ '  ▸ second',
        \ '▸ loose',
        \ ])
endfunction

function! s:suite.should_collapse_group_to_hide_members() abort
  :DBUI
  call cursor(1, 1)
  normal o
  call s:expect(getline(1, '$')).to_equal([
        \ '▸ Group A',
        \ '▸ loose',
        \ ])
endfunction

function! s:suite.should_allow_duplicate_names_across_groups() abort
  let g:dbs = [
        \ { 'name': 'shared', 'url': s:db_url(), 'group': 'Group A' },
        \ { 'name': 'shared', 'url': s:db_url(), 'group': 'Group B' },
        \ ]
  :DBUI
  call s:expect(getline(1, '$')).to_equal([
        \ '▾ Group A',
        \ '  ▸ shared',
        \ '▾ Group B',
        \ '  ▸ shared',
        \ ])
endfunction
