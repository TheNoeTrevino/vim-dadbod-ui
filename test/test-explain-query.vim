let s:suite = themis#suite('Explain query')
let s:expect = themis#helper('expect')

function! s:suite.before() abort
  call SetupTestDbs()
  " Sleep 1 sec to avoid overlapping temp names
  sleep 1
endfunction

function! s:suite.after() abort
  call Cleanup()
endfunction

function! s:suite.should_explain_query_and_open_results() abort
  :DBUI
  norm ojo
  call s:expect(&filetype).to_equal('sql')
  call setline(1, 'SELECT * FROM contacts')
  execute "normal \<Plug>(DBUI_ExplainQuery)"
  call s:expect(bufname('.dbout')).not.to_be_empty()
  " Query execution may be async, so wait for the results buffer to populate.
  let dbout = bufnr('.dbout')
  let tries = 0
  while tries < 50 && len(getbufline(dbout, 1, '$')) <= 1
    sleep 100m
    let tries += 1
  endwhile
  let output = join(getbufline(dbout, 1, '$'))
  call s:expect(output).to_match('opcode')
  " The original query buffer must remain untouched (query not rewritten).
  call s:expect(getline(1)).to_equal('SELECT * FROM contacts')
  pclose
endfunction

function! s:suite.should_expose_postgres_explain_prefixes() abort
  let pg = db_ui#schemas#get('postgresql')
  call s:expect(pg.explain_prefix).to_equal('EXPLAIN')
  call s:expect(pg.explain_analyze_prefix).to_match('ANALYZE')
endfunction
