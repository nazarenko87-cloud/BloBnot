# BloBnot

A minimalist, cross-platform notes app for project documentation — local Markdown files
with an Obsidian-style link graph. Built with Flutter for Windows and Android.

Your notes are plain `.md` files in a folder you choose. No database, no lock-in — point
the vault at a Google Drive folder and the same notes follow you across devices. Data
lives outside the app folder, so it survives updates.

## Features

- **Plain Markdown vault** — every note is a `.md` file on disk; pick any folder as your vault.
- **Knowledge graph** — force-directed graph of your notes. `[[wiki links]]` become edges;
  each top-level folder becomes a project hub node. Drag, zoom, click to open.
- **Wiki links** — `[[Note]]`, `[[Note|alias]]` and `[[Note#Heading]]`, with `[[` autocomplete
  and a link picker. Renaming a note auto-updates every link to it.
- **Code-style editor** — line numbers, live Markdown syntax highlighting, split edit/preview,
  formatting toolbar, images, and paste-a-screenshot straight into a note.
- **Projects** — folders as projects: rename, delete, and drag to reorder.
- **Tag glyphs** — map a `#tag` or a note to an icon, shown as a medallion in the list,
  graph and dashboard.
- **Dashboard** — card overview with stats, an activity heatmap and an interactive calendar.
- **Reminders** — per-note, inline `{{remind:}}` tags, and standalone calendar events.
- **Attachments** — files live in `attachments/` next to your notes.
- **Themes** — dark and light, four colour styles plus a monochrome "Newsprint" Lite theme.
- **Local lock** — optional salted-SHA-256 password on launch.
- **AI access** — an [MCP server](mcp/) so Claude can read and write the same vault.

## Install

### Windows

Grab `blobnot.exe` together with its `data/` folder and the `.dll` files from a release
build, keep them in one folder, and run `blobnot.exe`. No installer, no admin rights —
it is a portable app. On first launch it asks for a vault folder; pick any folder (an
empty one is fine) and your notes live there from then on.

### Android

Install the `.apk`. Android will ask you to allow installing from an unknown source,
since the build is not distributed through Play. On first launch, pick a vault folder
through the system folder chooser — including a Google Drive folder, which is how the
same notes reach your phone.

### Build from source

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install). Android builds
also need a JDK 17 and the Android SDK.

```bash
flutter pub get
flutter run                       # debug
flutter build windows --release   # Windows -> build/windows/x64/runner/Release/
flutter build apk --release       # Android -> build/app/outputs/flutter-apk/
```

## MCP server (optional)

[`mcp/`](mcp/) contains an MCP server that gives an AI assistant access to your vault:
searching notes, writing new ones, and setting reminders — all in the same files the app
uses. It is entirely optional; the app does not need it and never talks to it.

```bash
cd mcp
npm install
claude mcp add blobnot -- node "<full path>/mcp/src/index.js"
```

See [mcp/README.md](mcp/README.md) for Claude Desktop setup, the tool list, and how the
server and app share one vault safely.

## How it works

Notes are files; everything else is derived. Links and tags are parsed from note text on
the fly — the graph is never stored separately. Per-vault state (`settings.json`,
`reminders.json`, `pinned.json`, `glyphs.json`, `calendar_events.json`) sits next to the
notes so it travels with the vault; only the path of the last opened vault is kept in
`~/.bloknot/settings.json`.

The storage layer is platform-agnostic behind a `VaultBackend` interface: desktop builds
use `dart:io` file access, Android uses the Storage Access Framework so a vault can live
in a cloud-synced folder.

## Tests

```bash
flutter test          # app
cd mcp && npm test    # MCP server
```
