# BloBnot MCP server

Lets an AI assistant (Claude Desktop, Claude Code, or any MCP client) read and write
your BloBnot vault directly — ask it to find a note, add one, or set a reminder, and
the change lands in the same Markdown files the app uses.

The vault stays plain Markdown. This server talks to the files, not to the running app,
so nothing has to be open for it to work.

## Requirements

- Node.js 18 or newer
- A BloBnot vault folder (any folder of `.md` files)

## Install

```bash
cd mcp
npm install
```

## Point it at a vault

The server looks for a vault in this order:

1. A folder path passed as the first argument
2. The `BLOBNOT_VAULT` environment variable
3. The vault the desktop app opened last (`~/.bloknot/settings.json`)

Option 3 means it usually just works after you have opened BloBnot once.

Android vaults picked through the system folder chooser are `content://` URIs, which
only the app itself can read — set `BLOBNOT_VAULT` to a desktop folder instead.

## Connect it to Claude

**Claude Code** — one command:

```bash
claude mcp add blobnot -- node "D:/claude progects/blobnot/mcp/src/index.js"
```

**Claude Desktop, automatically** — let the server write its own config entry. It merges
into the file, leaving any other servers alone, and keeps a `.bak` copy:

```bash
node src/index.js --register --vault "G:/My Drive/BLOB/BloknotVault"
```

`--unregister` removes it again. The Windows installer runs this for you when you tick
"Connect the MCP server to Claude Desktop". Restart Claude Desktop afterwards.

**Claude Desktop, by hand** — add this to `claude_desktop_config.json`
(`%APPDATA%\Claude\claude_desktop_config.json` on Windows,
`~/Library/Application Support/Claude/claude_desktop_config.json` on macOS),
then restart Claude Desktop:

```json
{
  "mcpServers": {
    "blobnot": {
      "command": "node",
      "args": ["D:/claude progects/blobnot/mcp/src/index.js"],
      "env": {
        "BLOBNOT_VAULT": "G:/My Drive/BLOB/BloknotVault"
      }
    }
  }
}
```

Use the real path to your own vault, and forward slashes even on Windows.

To check the connection, ask the assistant to run `vault_info` — it answers with the
vault path and what it found there.

## Tools

| Tool | What it does |
|------|--------------|
| `vault_info` | Vault path, note/project/reminder counts, tags in use |
| `list_notes` | Titles, project, tags, word count, checklist progress |
| `read_note` | One note's full Markdown body, links and tags |
| `search_notes` | Full-text and `#tag` search with excerpts |
| `write_note` | Create a note, or replace one with `overwrite` |
| `append_to_note` | Add to the end of a note, creating it if missing |
| `archive_note` | Soft-delete into `_archive` (restorable in the app) |
| `list_projects` | Project folders with note counts |
| `list_reminders` | Note reminders, calendar events and `{{remind:}}` tags |
| `add_reminder` | Reminder on a note, inline in its text, or standalone |
| `list_hot_tasks` | Hot tasks in progress, and done ones with when |
| `add_hot_task` | Add a one-line to-do to the top of Hot tasks |
| `complete_hot_task` | Mark a hot task done by its text (or a unique part of it) |
| `find_notes_by_field` | Notes whose fields match, e.g. `status` = `needs fixes` |
| `set_note_field` | Set or remove one field of a note, e.g. `score` to `4` |

Every note also comes back with its `fields` — the `---` block at the top of the
note that the app's Table view is built from. That lets you ask things like "which
weekly reports are still marked needs fixes?" or "set Oleg's report status to done".

## Working alongside the app

Both the app and this server write the same files, and neither locks them. If BloBnot
has a note open while the server rewrites it, whichever saves last wins — the same as
editing the file in another editor. Press **Refresh (Ctrl+R)** in BloBnot to pull in
changes made from the outside.

Nothing here erases notes: `archive_note` moves a file to `_archive/`, and `write_note`
adds a ` (n)` suffix rather than overwriting, unless you explicitly ask it to overwrite.

## File formats it reads and writes

Everything matches what the Flutter app expects:

- Notes — `.md` files; the file name is the title. Sub-folders are projects.
- `_archive/`, `_templates/`, `_hot/`, `attachments/`, `.history/` — reserved, skipped in listings
- `_hot/tasks.md` — hot tasks: `- [ ] task` and `- [x] task ✓ 2026-09-21 14:30`
- `reminders.json` — `{"Note title": "2026-09-20T15:00"}`
- `calendar_events.json` — `[{"id": "...", "title": "...", "when": "..."}]`
- `pinned.json` — `["Note title", ...]`
- `{{remind:2026-09-20T15:00}}` — inline reminder tag inside note text
- `[[Wiki links]]`, `[[Note|alias]]`, `[[Note#Heading]]` — graph edges
- `#tags` — parsed from note text, never stored separately

## Standalone build

`npm run build:exe` bundles the server and a Node runtime into a single executable
(`build/blobnot-mcp.exe`, ~99 MB) using esbuild and Node's SEA support, so it runs on
machines without Node installed. This is what the Windows installer ships.

## Tests

```bash
npm test
```
