# vim-dadbod-ui → Lua Port: Behavioral Specification

This is the **contract** the Lua reimplementation must satisfy. It is derived from
the existing VimScript source (`autoload/db_ui/*.vim`, `plugin/`, `ftplugin/`,
`syntax/`) and — most importantly — the 30+ themis tests in `test/`, which are the
executable specification. Where a value is "load-bearing" (an assertion depends on
it) it is quoted exactly.

The query engine (vim-dadbod) is **not** reimplemented. We call into it exactly as
the VimScript does. See §9 for the full external dependency surface.

---

## 0. Scope & non-goals

- **In scope:** the entire UI layer — drawer/tree, connection management, query
  buffer lifecycle, bind parameters, table helpers, schema introspection,
  output-buffer (`dbout`) interactions, notifications.
- **Out of scope:** anything vim-dadbod already does (connecting, dispatching SQL,
  adapter-specific CLI invocation, URL parsing). We delegate.
- **Platform:** Neovim only. We may use `vim.api`, `vim.system`/jobs, `vim.keymap`,
  `vim.notify`, Lua autocmds. Vim 8 is dropped.
- **Config model:** modernized — `require('dbui').setup({...})` — but commands,
  `<Plug>` mappings, on-disk file formats and save locations are preserved (see §1.x
  for the compatibility note on legacy `g:` vars).

---

## 1. User-facing surface

### 1.1 Commands

| Command | Action |
|---|---|
| `:DBUI` | Open the drawer. Honors command modifiers (`:tab DBUI`, `:vertical DBUI`). |
| `:DBUIToggle` | Open if closed, close if open. |
| `:DBUIClose` | Close the drawer. |
| `:DBUIAddConnection` | Prompt for URL + name, persist to `connections.json`. |
| `:DBUIFindBuffer` | Locate the current buffer in the drawer (assign to a db if external). |
| `:DBUIRenameBuffer` | Rename current query buffer / saved query. |
| `:DBUILastQueryInfo` | Echo last query text + execution time. |
| `:DBUIHideNotifications` | Dismiss floating notifications. |

### 1.2 `<Plug>` mappings & defaults

**Drawer (`filetype=dbui`)** — set in `ftplugin/dbui.vim` unless disabled:

| Keys | `<Plug>` | Action |
|---|---|---|
| `o` `<CR>` `<2-LeftMouse>` | `(DBUI_SelectLine)` | Toggle/open item under cursor |
| `S` | `(DBUI_SelectLineVsplit)` | Open in vertical split |
| `R` | `(DBUI_Redraw)` | Redraw / refresh tables |
| `d` | `(DBUI_DeleteLine)` | Delete buffer / saved query / connection |
| `A` | `(DBUI_AddConnection)` | Add connection |
| `H` | `(DBUI_ToggleDetails)` | Toggle `(scheme - source)` detail suffix |
| `r` | `(DBUI_RenameLine)` | Rename buffer / edit connection |
| `q` | `(DBUI_Quit)` | Close drawer |
| `<C-k>` / `<C-j>` | `(DBUI_GotoFirstSibling)` / `(DBUI_GotoLastSibling)` | First / last sibling |
| `K` / `J` | `(DBUI_GotoPrevSibling)` / `(DBUI_GotoNextSibling)` | Prev / next sibling |
| `<C-p>` / `<C-n>` | `(DBUI_GotoParentNode)` / `(DBUI_GotoChildNode)` | Parent / child node |
| `?` | (local) | Toggle help overlay |

**Output (`filetype=dbout`)** — `ftplugin/dbout.vim`:

| Keys | `<Plug>` | Action |
|---|---|---|
| `<C-]>` | `(DBUI_JumpToForeignKey)` | Jump to FK target row |
| `vic` / `ic` (omap) | `(DBUI_YankCellValue)` | Select/operate on cell value |
| `yh` | `(DBUI_YankHeader)` | Yank header row as CSV |
| `<Leader>R` | `(DBUI_ToggleResultLayout)` | Toggle expanded (vertical) layout |

**Query buffers (`sql`/`mysql`/`plsql`/`javascript`)** — `ftplugin/sql.vim`, `ftplugin/javascript.vim`:

| Keys | `<Plug>` | Action |
|---|---|---|
| `<Leader>S` (n & v) | `(DBUI_ExecuteQuery)` | Execute buffer (n) / selection (v) |
| `<Leader>W` | `(DBUI_SaveQuery)` | Persist a temp query |
| `<Leader>E` | `(DBUI_EditBindParameters)` | Edit bind params |
| `<Leader>X` (n & v) | `(DBUI_ExplainQuery)` | `EXPLAIN` the buffer (n) / selection (v); query not executed |
| _(unmapped)_ | `(DBUI_ExplainAnalyzeQuery)` | `EXPLAIN ANALYZE`; **executes** the query (write-query guard) |

JS mappings are applied **only** when the buffer was created by dbui
(`b:dbui_db_key_name` is set) — i.e. MongoDB query buffers.

**Disabling:** `disable_mappings` (all), plus per-filetype
`disable_mappings_dbui` / `_dbout` / `_sql` / `_javascript`. A disabled drawer
is `nomodifiable`, so `o`/`d`/etc. raise `E21` (test-disable-mappings asserts this).

### 1.3 Config (modernized) + legacy compatibility

The Lua API is `require('dbui').setup(opts)`. Every legacy `g:db_ui_*` variable maps
to a key under `opts`. **Decision (deferred to architecture doc):** whether to also
read legacy `g:` vars. The tests set `g:` vars directly, so the implementation MUST
honor `g:` vars at least as a fallback to keep the test suite as the contract — see
ARCHITECTURE §4.

Full config table with exact defaults:

| Legacy var | Default | Meaning |
|---|---|---|
| `db_ui_winwidth` | `40` | Drawer width |
| `db_ui_win_position` | `'left'` | `'left'` \| `'right'` |
| `db_ui_save_location` | `'~/.local/share/db_ui'` | Connections + saved queries dir |
| `db_ui_tmp_query_location` | `''` | Persisted temp query dir (else system temp) |
| `db_ui_drawer_sections` | `['new_query','buffers','saved_queries','schemas']` | Section order under a db |
| `db_ui_expand_groups` | `1` | Groups start expanded |
| `db_ui_dbout_list_sort` | `'asc'` | `'asc'` \| `'desc'` query-results ordering |
| `db_ui_show_help` | `1` | Show "Press ? for help" |
| `db_ui_use_nerd_fonts` | `0` | Nerd-font icon set |
| `db_ui_icons` | (see §7) | Icon dict |
| `db_ui_default_query` | `'SELECT * from "{table}" LIMIT 200;'` | Deprecated; prefer table_helpers |
| `db_ui_table_helpers` | `{}` | Per-scheme helper overrides |
| `db_ui_auto_execute_table_helpers` | `0` | Auto-run helper on open |
| `db_ui_execute_on_save` | `1` | Run query on `:w` |
| `db_ui_bind_param_pattern` | `':\w\+'` | Bind-param regex |
| `db_ui_hide_schemas` | `[]` | Regex patterns of schemas to hide |
| `db_ui_use_postgres_views` | `1` | Show PG (materialized) views |
| `db_ui_disable_progress_bar` | `0` | Async progress spinner off |
| `db_ui_force_echo_notifications` | `0` | Echo instead of float |
| `db_ui_disable_info_notifications` | `0` | Drop info-level |
| `db_ui_use_nvim_notify` | `0` | Route to `vim.notify` |
| `db_ui_notification_width` | `40` | Float width |
| `db_ui_debug` | `0` | Debug echo |
| `db_ui_is_oracle_legacy` | `0` | Oracle legacy mode |
| `db_ui_dotenv_variable_prefix` | `'DB_UI_'` | dotenv conn prefix |
| `db_ui_env_variable_url` | `'DBUI_URL'` | Single-conn URL env var |
| `db_ui_env_variable_name` | `'DBUI_NAME'` | Single-conn name env var |
| `db_ui_disable_mappings*` | `0` | See §1.2 |
| `Db_ui_buffer_name_generator` | `0`/nil | `fun(opts)->string`; `opts={label,table,schema,filetype}` |
| `Db_ui_table_name_sorter` | `0`/nil | `fun(list)->list` |

---

## 2. State model

A single lazily-created instance (`dbui`) holds:

- `dbs` — map `key_name → DatabaseObject`
- `dbs_list` — ordered list of `{name, url, source, group, key_name}`
- `save_path`, `connections_path`, `tmp_location`
- `drawer` — UI object
- `dbout_list` — map `file → preview` of executed result buffers

**`key_name` generation:** `group .. '_' .. name .. '_' .. source` when grouped, else
`name .. '_' .. source`. Sources: `'g:dbs'`, `'env'`, `'dotenv'`, `'file'`.

**DatabaseObject** (per connection):

```
name, key_name, db_name, group, source, url
conn, conn_error, conn_tried           -- vim-dadbod connection + status
scheme, schema_support, filetype, quote, default_scheme, table_helpers
schemas = { expanded, items, list }    -- multi-schema dbs
tables  = { expanded, items, list }    -- single-schema dbs
saved_queries = { expanded, list }
buffers = { expanded, list, tmp }
save_path
```

`expanded` flags are pure UI state. Connections are **lazy**: `conn` is populated on
first expand; `conn_tried` guards against re-attempts.

### 2.1 Connection population order

`dotenv → env → g:dbs/g:db → connections file`. For each:
- **dotenv:** env vars whose name starts with `dotenv_variable_prefix` (`DB_UI_`); conn
  name = lowercased remainder. Source `'dotenv'`.
- **env:** `$DBUI_URL` (+ optional `$DBUI_NAME`; else name from URL path). Source `'env'`.
- **g:dbs:** dict `{name=url|fn}` or list `[{name,url,group?}]`; url may be a function
  (resolved at init). Also legacy single `g:db`. Source `'g:dbs'`.
- **file:** JSON array at `connections.json`; preserves `group`. Source `'file'`.

**Dedup contract (test-duplicate-connections-from-same-source):** duplicate iff same
`(name, source, group)`. On dup → warning, first wins. Exact message:

```
Warning: Duplicate connection name "db-ui-database" in "g:dbs" source. First one added has precedence.
```

Same name across different groups or sources is allowed.

---

## 3. Connections persistence

- **File:** `{save_location}/connections.json`, JSON array of
  `{name, url, group?}`.
- **add:** prompt `"Enter connection url: "` → validate via `db#url#parse` +
  `db#resolve` → prompt `"Enter name: "` → reject empty/duplicate-name → append → write.
- **edit (`r` on a `source='file'` db):** prompt `"Edit connection url: "` /
  `"Edit connection name: "`, rewrite that entry. Only file-source connections are
  editable/deletable.
- **delete (`d`):** confirm → filter entry out → write.
- **Corrupted file (test-corrupted-connections-file):** must NOT crash; emit error,
  last message starts with `Error reading connections file.`

After any write, the drawer re-renders (`render({dbs=1})`).

---

## 4. Drawer / tree

### 4.1 Window

`buftype=nofile`, `bufhidden=wipe`, `nobuflisted`, `noswapfile`, `nowrap`, `nospell`,
`nonumber`, `norelativenumber`, `signcolumn=no`, `nomodifiable`, `winfixwidth`,
`filetype=dbui`. Side = `win_position`; width = `winwidth`. On open: set keymaps,
buffer-local `BufEnter → render` autocmd, then fire `User DBUIOpened`.

### 4.2 Content model

The tree is rendered as a **flat list** of content items (one per line). Each item:

```
label, action, type, icon, dbui_db_key_name, level
+ optional: expanded, file_path, saved, group, table, content, schema
```

Rendered line = `indent(level) .. icon .. ' ' .. label`, where indent uses
`shiftwidth() * level` spaces. `get_current_item()` = `content[line('.')]`.

`action ∈ {toggle, open, noaction, call_method}`.

### 4.3 Node types & layout

Under each **expanded db** the sections render in `drawer_sections` order:

- `new_query` → `+ New query` (action open, type `query`).
- `buffers` → `Buffers (N)` header (only if non-empty), children are buffer files;
  temp buffers get a trailing ` *`.
- `saved_queries` → `Saved queries (N)`, children from `save_path/*`.
- `schemas` → if `schema_support`: `Schemas (N)` → schema nodes `name (count)` →
  table nodes; else `Tables (N)` → table nodes. An expanded **table** lists its
  **table helpers** (open actions).

Group headers (type `group`) render at level 0; grouped dbs render at level 1 only
when the group is expanded. The query-results list (`Query results (N)`, type
`call_method`/`dbout`) renders below everything when `dbout_list` is non-empty,
ordered per `dbout_list_sort`.

Reference layout (test-db-navigation, exact):

```
▾ dadbod_ui_test ✓
  + New query
  ▸ Saved queries (0)
  ▸ Tables (2)
▸ dadbod_ui_testing
```

(`✓` = `icons.connection_ok`; the leading markers are
`icons.expanded.db` / `icons.collapsed.db`.)

### 4.4 Actions

- **toggle_line(edit_action):** dispatch on `action`/`type`:
  `noaction`→nop; `call_method`→call the method named in `type`; `dbout`→`pedit`
  the file in the query window; `open`→`query.open(item, edit_action)`;
  `group`→flip group expanded; else flip node `expanded` (and for `db`, run
  `toggle_db`: load saved queries, connect, populate tables/schemas), then re-render.
- **redraw:** full refresh at level 0, else refresh just the current db
  (`{db_key_name=…, queries=1}`).
- **goto_sibling(first|prev|next|last)** / **goto_node(parent|child)** — cursor moves
  bounded by tree level; child expands if needed. (test-goto-sibling-and-node).
- **delete_line / rename_line** — per §3 (connections) and §5 (buffers).
- **toggle_details** → `(scheme - source)` suffix on db nodes
  (test-toggle-details: `▸ dadbod_ui_test (sqlite - g:dbs)`).
- **toggle_help** (`?`) — overlay; exact help text is asserted by test-show-help (see
  §8). `db_ui_show_help` controls the persistent `" Press ? for help` line.

### 4.5 Schema population

- single-schema dbs: `db#adapter#call(conn,'tables',[conn],[])` (SQLite split on
  spaces; MySQL warning lines filtered).
- multi-schema dbs: `db_ui#schemas#query` runs the scheme's `schemes_query` +
  `schemes_tables_query`; schemas matching any `hide_schemas` regex are dropped.

---

## 5. Query buffer lifecycle

### 5.1 Open / create

`query.open(item, edit_action)`:
- Generate a buffer name: slug of `{db.name}-{suffix}` + timestamp, where suffix is
  `query` or `{table}-{label}`. If `Db_ui_buffer_name_generator` is set, call it with
  `opts={label,table,schema,filetype}` and use `{db.name}-{result}`.
- Location: `tmp_query_location/{name}` if set (persisted), else `tempname()` (and the
  path is tracked in `db.buffers.tmp`).
- Find/create target window (`focus_window`), open buffer with `edit_action`.
- Set buffer vars: `b:dbui_db_key_name`, `b:dbui_table_name`, `b:dbui_schema_name`,
  `b:db` (= `db.conn`). Set `filetype=db.filetype`. Register `<Plug>` query mappings
  and the `db_ui_query` autocmds (BufWritePost→execute if `execute_on_save` & sql;
  BufDelete/Wipeout→`remove_buffer`).
- If opened for a table/helper, fill the buffer from the helper template (or
  `default_query`) with substitutions: `{table}`, `{schema}`, `{optional_schema}`
  (schema + `.`, quoted if needed, empty for default schema), `{dbname}`,
  `{last_query}`. Then if `auto_execute_table_helpers`: `:write` (when
  `execute_on_save`) or call `execute_query` directly.

`b:dbui_table_name` contract (test-table-helpers): opening a table's List yields
buffer line `SELECT * FROM contacts` and `b:dbui_table_name == 'contacts'`.

### 5.2 Execute

`execute_query(is_visual)`:
- Get lines (whole buffer, or visual selection via `gvy`).
- If no bind params present: `%DB` (whole) — simplest path.
- Else `execute_lines`: single line→`DB {line}`; visual→`'<,'>DB`; multi-line→write a
  temp file (`tempname().<input_extension>`) and `DB < file`; inject bind values first.
- Async detection via `exists('*db#cancel')`; if async, notify `Executing query...`,
  else call `print_query_time` immediately. Timing via `User *DBExecutePre/Post`
  hooks (`Done after {n} sec.`). Results land in a `.dbout` preview buffer.

### 5.3 Bind parameters

- Regex: `\(^\|[[:blank:]]\|[^:]\)\(` + `bind_param_pattern` + `\)` — so a leading
  word char before the pattern disqualifies it (excludes `::text` casts).
- Excluded: matches inside quoted strings and JSON-ish literals (test-bind-parameters
  asserts casts and string contents are NOT treated as params).
- Prompt per new param `"...{var}..."`; cache in `b:dbui_bind_params`; substitute with
  `quote_query_value` (numbers / `true`/`false` / already-quoted unquoted; else single-
  quoted; empty/whitespace value → param skipped/raw).
- `edit_bind_parameters` (`<Leader>E`): list params with values (or `Not provided`),
  select → Edit/Delete/Cancel, update cache. (Default & custom `\$\d\+` patterns both
  tested.)

### 5.4 Save / rename / delete

- **save (`<Leader>W`, temp buffers only):** require `db.save_path`; prompt
  `"Save as: "`; reject empty/existing; `write {save_path}/{name}`; re-render
  (`{queries=1}`); reopen the saved file. Saved query appears under Saved queries as
  `icons.saved_query {name}` (test-save-query-to-file).
- **rename (`r` in drawer):** prompt new name; temp → track in `buffers.tmp` and show
  `{name} *`; saved → move file. Update buffer vars + `buffers.list`, re-render.
- **delete (`d`):** temp buffer → remove from list (not disk), drop Buffers section if
  now empty; saved query → delete file + entry.

---

### 5.5 Explain / Explain Analyze

`do_explain(is_visual, analyze)` — backs both `(DBUI_ExplainQuery)` (analyze=0) and
`(DBUI_ExplainAnalyzeQuery)` (analyze=1):

- Guard: require a valid dbui query buffer (`b:dbui_db_key_name` resolves to a known
  db) → else `error('Cannot explain - not a valid dadbod-ui query buffer.')`.
- Get lines (whole buffer or visual selection). Empty (after trim) → `error('Cannot
  explain an empty query.')`.
- **Write-query guard (analyze only):** if the first SQL word is one of
  `insert|update|delete|truncate|drop|alter|create|merge|replace|grant|revoke`,
  `confirm('EXPLAIN ANALYZE will execute this data-modifying query. Continue?', ...)`
  defaulting to **No**; on decline → `info('Canceled.')` and abort. (EXPLAIN ANALYZE
  actually runs the statement.)
- Inject bind params if present (same path as execute; errors surface via `error`).
- Resolve prefix from the scheme: `explain_analyze_prefix` / `explain_prefix`, falling
  back to `'EXPLAIN ANALYZE'` / `'EXPLAIN'`. PostgreSQL overrides analyze to
  `'EXPLAIN (ANALYZE, BUFFERS)'`.
- `prepend_explain`: prefix is prepended to the **first non-blank line only**; the
  rest of the buffer is untouched and **the source buffer is never rewritten** (the
  explained text goes through a temp file).
- Execute via temp file: `tempname().<input_extension>` → `writefile` → `DB < file`.
  Async → `info('Explaining query...')`, else `print_query_time`. Store as
  `last_query`. Results land in the `.dbout` preview buffer.

Contract (test-explain-query): after `(DBUI_ExplainQuery)` on `SELECT * FROM contacts`,
the `.dbout` buffer is populated and the source line `getline(1)` is still exactly
`SELECT * FROM contacts`. `schemas.get('postgresql').explain_prefix == 'EXPLAIN'` and
`.explain_analyze_prefix` matches `ANALYZE`.

## 6. Output buffer (`dbout`)

`*.dbout` files → `filetype=dbout`; `BufReadPost` → `db_ui#save_dbout`. Folding via
`foldexpr=db_ui#dbout#foldexpr`. Buffer-local `b:db` carries the connection.

- **jump_to_foreign_table (`<C-]>`):** parse `b:db.db_url` → scheme; find cell
  column/value from the rendered table using scheme `cell_line_number`/
  `cell_line_pattern`; run scheme `foreign_key_query` (`{col_name}`), parse to
  `[table, column, schema]`; run `select_foreign_key_query` (printf 4-arg) → `DB`.
- **get_cell_value (`vic`/operator `ic`):** compute cell range (normal or
  `has_virtual_results` virtual-col path) and visually select it.
- **yank_header (`yh`):** parse columns from the underline row, join CSV into the
  chosen register.
- **toggle_layout (`<Leader>R`):** require scheme `layout_flag` (`\x`/`\G`); rewrite
  query with the flag and replay (`normal! R`); toggle `b:db_ui_expanded_layout`.
- **Async progress spinner:** floating window animation driven by a 100ms timer on
  `User DBQueryPre/Post` and `*DBExecutePre/Post`, disabled by `disable_progress_bar`.

---

## 7. Icons & syntax

Default `db_ui_icons` (non-nerd-font):

```
expanded  = { db='▾', buffers='▾', saved_queries='▾', schemas='▾',
              schema='▾', tables='▾', table='▾', group='▾' }
collapsed = { …same keys… = '▸' }
saved_query='*', new_query='+', tables='~', buffers='»',
add_connection='[+]', connection_ok='✓', connection_error='✕'
```

The `group` key (connection-groups feature) is present in both sets; if the user does
not override it, it **falls back to the `db` icon**. `use_nerd_fonts=1` swaps in glyphs
for the expanded/collapsed sets (ok/error unchanged). Custom icons fully override
(test-custom-icons uses `[+]`/`[-]`).

Syntax (`syntax/dbui.vim`) generates `dbui_<group>` matches from the icon dict, all
linking to `Directory`, plus `dbui_saved_query→String`, `dbui_new_query→Operator`,
`dbui_buffers`/`dbui_tables→Constant`, `dbui_connection_source`/`dbui_help→Comment`,
`dbui_help_key→String`, and custom green/red `dbui_connection_ok`/`_error`.
Notification highlights: `NotificationInfo/Warning/Error`.

---

## 8. Help overlay (exact)

test-show-help asserts the full text. Line 1 (persistent): `" Press ? for help`.
After `?`, the body is exactly:

```
" o - Open/Toggle selected item
" S - Open/Toggle selected item in vertical split
" d - Delete selected item
" R - Redraw
" A - Add connection
" H - Toggle database details
" r - Rename/Edit buffer/connection/saved query
" q - Close drawer
" <C-j>/<C-k> - Go to last/first sibling
" K/J - Go to prev/next sibling
" <C-p>/<C-n> - Go to parent/child node
" <Leader>W - (sql) Save currently opened query
" <Leader>E - (sql) Edit bind parameters in opened query
" <Leader>S - (sql) Execute query in visual or normal mode
" <C-]> - (.dbout) Go to entry from foreign key cell
" <motion>ic - (.dbout) Operator pending mapping for cell value
" <Leader>R - (.dbout) Toggle expanded view
```

---

## 9. External dependency surface (vim-dadbod)

The **only** integration points. Lua calls these via `vim.fn[...]` / `vim.cmd`:

| Call | Where | Purpose |
|---|---|---|
| `db#connect(url)` | connect | open connection |
| `db#resolve(url)` | resolve, connections | expand sqlite/jq/duckdb/osquery paths |
| `db#url#parse(url)` | dbout, connections | parse → `{scheme, path, …}` |
| `db#adapter#call(conn,'tables',[conn],[])` | drawer | list tables |
| `db#adapter#call(conn,'input_extension',[],'sql')` | query | temp-file extension |
| `db#adapter#dispatch(conn,callable)` | schemas | build CLI command |
| `db#adapter#schemes()` | table_helpers | enumerate schemes |
| `db#systemlist(cmd, stdin)` | schemas | run introspection query |
| `exists('*db#cancel')` | query | async capability probe |
| `:DB` / `%DB` / `'<,'>DB` / `DB < file` | query | execute SQL (the engine) |

Per-scheme metadata (args, `schemes_query`, `schemes_tables_query`,
`foreign_key_query`, `select_foreign_key_query`, `parse_results`,
`cell_line_number`/`pattern`, `quote`, `default_scheme`, `layout_flag`, `filetype`,
`requires_stdin`, `has_virtual_results`, and the explain prefixes
`explain_prefix`/`explain_analyze_prefix` — present on PostgreSQL:
`'EXPLAIN'` / `'EXPLAIN (ANALYZE, BUFFERS)'`) for
postgres/mysql/mariadb/sqlserver/oracle/bigquery/clickhouse — ported verbatim from
`schemas.vim`. Table-helper templates for
those + sqlite/mongodb ported verbatim from `table_helpers.vim` (incl. scheme aliases
postgres↔postgresql, sqlite↔sqlite3; empty-string helper removal; fallback `List=''`).

---

## 10. Public Lua API (parity with `autoload` entrypoints)

`open(mods)`, `toggle()`, `close()`, `find_buffer()`, `rename_buffer()`,
`print_last_query_info()`, `save_dbout(file)`, `reset_state()`,
`connections_list() → [{name,url,is_connected,source}]`,
`get_conn_info(key) → {url,conn,tables,schemas,scheme,connected}`,
`query(sql) → rows`, `statusline(opts) → string`
(opts `{prefix='DBUI: ', separator=' -> ', show={'db_name','table'}}`;
test-open-query asserts `'DBUI: dadbod_ui_test -> contacts'` and variants),
plus `notifications.{info,warning,error,get_last_msg}`.

---

## 11. Test contract

The themis tests in `test/` define acceptance (incl. `test-connection-groups` and
`test-explain-query`). The Lua port must pass an equivalent
suite (ported to plenary/busted, or run the existing themis suite against a thin
VimScript→Lua shim). Behaviors enumerated above each map to a named test; the
load-bearing assertion values are quoted inline. **Any deviation from a quoted value is
a regression.**
