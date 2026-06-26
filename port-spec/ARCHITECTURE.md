# vim-dadbod-ui → Lua Port: Architecture & Build Plan

Companion to `SPEC.md`. This document fixes the Lua module layout, the config story,
the state design, and the order we build & validate in. Decisions are marked
**[DECIDED]** or **[OPEN]** (needs your call before that phase).

---

## 1. Project shape

A standard Neovim Lua plugin laid over the existing repo (we keep VimScript `plugin/`,
`ftplugin/`, `syntax/` as thin shims that forward into Lua):

```
lua/dbui/
  init.lua            -- setup(), public API, command/mapping registration
  config.lua          -- defaults, legacy g: bridging, normalization
  state.lua           -- the dbui singleton: dbs, dbs_list, paths
  database.lua        -- DatabaseObject construction, connect(), schema info
  sources.lua         -- population: dotenv / env / g:dbs / connections file
  connections.lua     -- connections.json add/edit/delete/read/write
  drawer/
    init.lua          -- window, render pipeline, content list
    render.lua        -- section/node rendering
    nodes.lua         -- node types, icons, get_nested helpers
    actions.lua       -- toggle/open/delete/rename
    navigation.lua    -- goto_sibling / goto_node
    help.lua          -- help overlay text
  query.lua           -- buffer lifecycle, execute, bind params, save/rename
  dbout.lua           -- output buffer: cell range, FK jump, layout, header, progress
  schemas.lua         -- per-scheme introspection metadata + query()
  table_helpers.lua   -- per-scheme helper templates + get()
  notifications.lua   -- info/warning/error backends
  utils.lua           -- slug, input, inputlist, readfile, quote_query_value, mappings
plugin/db_ui.vim      -- (kept) commands + g: defaults → forward to lua require('dbui')
ftplugin/*.vim        -- (kept) <Plug> default key maps → call lua actions
syntax/dbui.vim       -- (kept) icon-driven syntax (can stay vimscript)
```

Rationale: the `autoload/db_ui/<module>.vim` → `lua/dbui/<module>.lua` mapping is
1:1, which keeps the port reviewable against the original and lets us migrate
module-by-module. `drawer.vim` (796 lines) is split into sub-files because it's the
densest unit.

**[DECIDED]** Keep `plugin/ftplugin/syntax` as VimScript shims rather than rewriting
mapping/command registration in Lua-only form. They are tiny, already correct, and the
themis tests load them. We replace the `autoload` logic, not the glue.

---

## 2. State design

One module-level singleton in `state.lua`, created lazily on first public call,
cleared by `reset_state()` (the tests rely on reset between cases). Plain Lua tables —
no OOP framework. `DatabaseObject` is a table built by `database.new(entry)`;
methods that act on a db take it as first arg (`database.connect(db)`), mirroring the
VimScript dict-function style without metatables (simpler, easier to reason about).

UI/expanded state lives **on** the db tables (`db.tables.expanded`, etc.) exactly as
today, so render is a pure function of state.

---

## 3. The vim-dadbod boundary

All engine calls funnel through a single `dadbod.lua` thin wrapper (`vim.fn['db#...']`,
`vim.cmd('%DB')`, etc.) so the external surface from SPEC §9 is in one auditable place.
This also makes it trivial to mock in tests. We do **not** vendor or fork dadbod.

Async/sync, `:DB` dispatch, `User *DBExecutePre/Post` autocmds — all preserved as-is;
we just register the autocmds with `nvim_create_autocmd` instead of `augroup` blocks.

---

## 4. Config: modernized + legacy bridge **[DECIDED, but confirm scope]**

`require('dbui').setup(opts)` is the front door. `config.lua`:

1. deep-merges `opts` over the defaults table (SPEC §1.3),
2. **also reads any `g:db_ui_*` / `g:Db_ui_*` that are set**, with precedence
   `setup() opts > g: var > default`.

Why the bridge is non-negotiable: the entire themis suite configures via `g:` vars
(e.g. `g:db_ui_drawer_sections`, `g:db_ui_icons`, `g:dbs`). To keep "the tests are the
contract", Lua must observe `g:` vars. `g:dbs` / `g:db` specifically remain the
connection source and are read live at population time.

Internally everything reads from the resolved `config` table (not scattered
`vim.g` lookups), so there's one source of truth. `setup()` is optional — with no call,
defaults + `g:` vars still work (matches today's zero-config behavior).

**[OPEN]** Do we *also* publish per-connection setup in the Lua table
(`opts.connections = {...}`) as a first-class alternative to `g:dbs`? Low cost, nice
ergonomics, but not required for parity. Recommend: yes, in a later phase.

---

## 5. Build order (lowest-dependency first)

Each phase ends green against its slice of the test contract before the next starts.
Phases 1–3 have no UI; we validate them with unit tests + a scratch harness.

| Phase | Modules | Validates against |
|---|---|---|
| 0 | scaffold, `dadbod.lua`, `utils.lua`, `notifications.lua`, `config.lua` | utils + notification unit tests; corrupted-file message |
| 1 | `schemas.lua`, `table_helpers.lua` | helper templates, scheme aliases, `List` fallback |
| 2 | `state.lua`, `database.lua`, `sources.lua`, `connections.lua` | all initialization tests (g:dbs var/array-fn/dict-fn, env, dotenv, custom env, combined), dedup warning, add/edit/delete, corrupted file |
| 3 | `query.lua` (+ bind params) | open-query, table-helpers, bind-parameters (default + custom), buffer naming, tmp location, save/rename, auto-execute |
| 4 | `drawer/*` | db-navigation, goto-sibling/node, find-buffer, toggle-details, drawer-sections, show-help, delete-buffer, custom-icons, connection-groups, toggle/quit, mods, disable-mappings |
| 5 | `dbout.lua` | FK jump, cell yank, header yank, layout toggle, fold; progress spinner |
| 6 | `init.lua` glue, statusline, polish | mods, statusline variants, full-suite pass |

Drawer (phase 4) is the riskiest; it depends on everything below it, which is why it's
late. Within phase 4 we build render → navigation → actions → groups in that order.

---

## 6. Testing strategy **[OPEN — pick one]**

Two viable paths to "the tests are the contract":

- **A — Reuse the themis suite (highest fidelity).** Keep `test/*.vim` almost as-is;
  they call `db_ui#...` autoload functions. We add tiny `autoload` shims that forward
  to Lua (`function db_ui#open(...) return luaeval(...) end`). Pro: literally the same
  assertions, zero translation risk. Con: keeps a VimScript test layer.
- **B — Port to plenary/busted.** Idiomatic, Lua-native, better long-term. Con: every
  assertion is hand-translated → risk of silently weakening the contract.

**Recommendation:** A first (proves parity fast and safely), then optionally grow a
parallel plenary suite for Lua-specific units. Decide before Phase 2.

The port can run **alongside** the original during development: load Lua dbui under a
different command (`:LuaDBUI`) and diff drawer output against `:DBUI` on the same
`g:dbs` for visual regression.

---

## 7. Known sharp edges (flagged for implementation)

- **Bind-param regex** uses VimScript `\(\)` capture semantics and the `[^:]` guard for
  casts. We keep matching via `vim.fn.matchstr`/`substitute` (Vim regex) rather than
  translating to Lua patterns — Lua patterns can't express this cleanly and the tests
  pin the exact behavior (casts, quoted strings, JSON excluded).
- **Drawer is a flat line list**, not a nested widget. Keep it that way; cursor-line ↔
  content-index is the core invariant for every action.
- **`dbout` cell-range math** (normal vs virtual columns, `getcurpos`, `virtcol`) is
  fiddly and visual; port it close to literal and lean on FK-jump/yank tests.
- **Window focus dance** in `query.focus_window` (find existing query win, else create)
  must preserve the "resize drawer if it was the only window" behavior.
- **Timing/async**: progress spinner + `Done after N sec.` depend on dadbod's
  `User *DBExecute*` events; register them, don't reinvent.
- **Notifications** need only the Neovim subset: `vim.notify` path + a float path +
  echo fallback (drop the Vim `popup_create` branch).

---

## 8. Effort & sequencing

Phases 0–2 are mechanical and fast (pure logic, well-tested). Phase 3 (query) and
Phase 4 (drawer) are the bulk. Phase 5 (dbout) is small but finicky. Realistically a
multi-session effort; each phase is independently shippable and independently
verifiable, so we never have a big-bang merge.

---

## 9. Decisions (RESOLVED 2026-06-26)

1. **Testing path** — **plenary/busted**. Lua-native suite. vim-dadbod is mocked at the
   `dadbod.lua` boundary for unit tests; a small set of integration tests run against a
   real SQLite fixture (`test/fixtures/*.db`) + real dadbod. Each behavior in SPEC §11
   maps to a `describe`/`it` block; quoted assertion values are copied verbatim so the
   contract is not weakened.
2. **Legacy `g:` bridge** — **yes**, read `g:db_ui_*`/`g:Db_ui_*` (precedence
   `setup() > g: > default`); `g:dbs`/`g:db` stay live connection sources. `opts.connections`
   added in a **later phase** (after core parity).
3. **Location** — **fresh repo** at `../dadbod-ui.nvim`, `git init`, independent history.
   The `port-spec/` docs are copied in as `doc/`.

Because tests are plenary-native (not the original themis files), we add a CI-style
parity guard: a `scripts/diff-drawer.lua` harness that loads both the original (via the
sibling vimscript repo) and the Lua port over identical `g:dbs` and asserts identical
drawer line output. This catches silent contract drift the hand-translated asserts miss.
