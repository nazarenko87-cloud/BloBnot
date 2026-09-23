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
- **Hot tasks** — the flame at the top of the rail: a quick list of running to-dos with
  *In progress* and *Done* columns. Tap a task to strike it through and stamp the time;
  tap a done one to bring it back. Done tasks move to an archive after 30 days. Stored as
  a plain checklist in `_hot/tasks.md`, so it syncs with the vault like any note.
- **Fields and Table** — give a note fields in a `---` block at the top (`manager: Oleg`,
  `status: needs fixes`, `score: 4`) and the Table view lists every such note as a row:
  sort by any column, search, filter by project or by a value, and edit a value right in
  its cell. The same front-matter format Obsidian uses, so the fields travel with the file.
- **Dashboard** — card overview with stats, an activity heatmap and an interactive calendar.
- **Calculator** — the classic keypad (memory, %, x², √, 1/x) plus offline converters for
  length, weight, temperature, area, volume, speed, time and data. *Insert into note* puts
  the result at the cursor.
- **Reminders** — per-note, inline `{{remind:}}` tags, and standalone calendar events.
- **Attachments** — files live in `attachments/` next to your notes.
- **Themes** — dark and light in several colour styles, including a monochrome
  "Newsprint" Lite, an Ubuntu-styled Lite 2, and a mid-grey Graphite.
- **Local lock** — optional salted-SHA-256 password on launch.
- **AI access** — an [MCP server](mcp/) so Claude can read and write the same vault.

## Install

Everything is on the [Releases page](https://github.com/nazarenko87-cloud/BloBnot/releases).

### Windows

Download `BloBnot-<version>-setup.exe` and run it. It installs for the current user, so
there is no admin prompt, and it adds a Start Menu entry and a proper uninstaller. The
setup also offers the optional **MCP server** and can connect it to Claude Desktop for
you — see below.

Prefer no installer? `BloBnot-<version>-windows-portable.zip` has the same files. Unpack
the **whole** archive and run `blobnot.exe` — it needs the `data/` folder and the `.dll`
files beside it.

On first launch it asks for a vault folder. Pick any folder, empty is fine; your notes
live there from then on.

### Android

Download the `.apk` and allow installing from an unknown source, since the build is not
distributed through Play. On first launch, pick a vault folder through the system folder
chooser — including a Google Drive folder, which is how the same notes reach your phone.

### Linux

On Ubuntu or Debian, download `BloBnot-<version>-amd64.deb` and install it:

```bash
sudo apt install ./BloBnot-<version>-amd64.deb
```

BloBnot then appears in the app menu. On any other distribution, use
`BloBnot-<version>-x86_64.AppImage`: make it executable (`chmod +x`) and run it.

#### Syncing the vault with Google Drive (rclone)

GNOME's built-in Google Drive integration shows files under internal IDs instead of
their names, so BloBnot cannot use it as a vault. Instead, keep the vault in an ordinary
local folder and let [rclone](https://rclone.org) sync it with Drive both ways:

```bash
sudo apt install rclone
blobnot-sync-setup
```

`blobnot-sync-setup` comes with the .deb (AppImage users can download it from the
release). It asks you to sign in to Google once, copies the vault to `~/BloBnot-Vault`,
and from then on syncs every 5 minutes in the background. Open `~/BloBnot-Vault` in
BloBnot as your vault.

- Different Drive folder or local folder: `blobnot-sync-setup --remote gdrive:My/Vault --local ~/Notes`
- Sync right now: `blobnot-sync-setup --run` · see what it did: `blobnot-sync-setup --status`
- Stop syncing (files stay): `blobnot-sync-setup --uninstall`

Needs rclone 1.58 or newer. With 1.66+, if the same note changed on two devices between
syncs, the newer version wins and the other is kept as a conflict copy — nothing is lost.

### Build from source

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install). Android builds
also need a JDK 17 and the Android SDK; Linux builds need `clang cmake ninja-build
pkg-config libgtk-3-dev`.

```bash
flutter pub get
flutter run                       # debug
flutter build windows --release   # Windows -> build/windows/x64/runner/Release/
flutter build apk --release       # Android -> build/app/outputs/flutter-apk/
flutter build linux --release     # Linux   -> build/linux/x64/release/bundle/
linux/packaging/build-packages.sh 2.5 dist   # Linux .deb and AppImage
```

## MCP server (optional)

[`mcp/`](mcp/) contains an MCP server that gives an AI assistant access to your vault:
searching notes, writing new ones, and setting reminders — all in the same files the app
uses. It is entirely optional; the app does not need it and never talks to it.

The easiest way to get it is the Windows installer — tick **MCP server** during setup,
and optionally **Connect the MCP server to Claude Desktop**, which writes the config
entry for you. The bundled build carries its own Node runtime, so nothing else is needed.

From source instead:

```bash
cd mcp
npm install
claude mcp add blobnot -- node "<full path>/mcp/src/index.js"
```

See [mcp/README.md](mcp/README.md) for the tool list, manual Claude Desktop setup, and
how the server and app share one vault safely.

## Releases

Pushing a version tag builds and publishes everything through
[GitHub Actions](.github/workflows/release.yml) — the installer, the portable zip and
the APK, attached to a draft release:

```bash
git tag v2.2
git push origin v2.2
```

To build the installer locally you need [Inno Setup 6](https://jrsoftware.org/isdl.php):

```bash
flutter build windows --release
cd mcp && npm run build:exe && cd ..   # optional MCP component
iscc /DAppVersion=2.2 installer/blobnot.iss
```

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
