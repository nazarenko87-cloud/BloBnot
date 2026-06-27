# BloBnot
BloBnot is notebook for ideas and notes , simple , free and with glifs

A minimalist, cross-platform notes app for project documentation — local Markdown files with an Obsidian-style link graph. Built with Flutter for Windows and Android (web preview included).

Your notes are plain .md files in a folder you choose. No database, no lock-in — point the vault at a Google Drive folder and the same notes follow you across devices. Data lives outside the app folder, so it survives updates.

Features
Plain Markdown vault — every note is a .md file on disk; pick any folder as your vault.
Knowledge graph — neon force-directed graph of your notes. [[wiki links]] become edges; each top-level folder becomes a project hub node. Drag, zoom, click to open, export to PNG.
Wiki links — [[Note]], [[Note|alias]], and [[Note#Heading]], with [[ autocomplete and a link picker. Renaming a note auto-updates every link to it.
Code-style editor — line numbers, live Markdown syntax highlighting, split edit/preview, bold/italic/colour, lists, images, and freehand drawings.
Projects — folders as projects: rename, delete, and drag to reorder (order persists); collapsed on startup.
Tag glyphs — map a #tag or keyword to an icon, shown as a medallion in the list, graph, and dashboard.
Dashboard — card overview of every note, with search.
Reminders — per-note reminders with background notifications.
Themes — petrol "terminal" dark mode and a warm paper light mode, plus accent presets.
Local lock — optional salted-SHA-256 password on launch.
Calculator built in.
Build
Requires the Flutter SDK.

flutter pub get
flutter run                       # debug (add -d chrome for the web preview)
flutter build windows --release   # Windows
flutter build apk --release       # Android
How it works
The storage layer is platform-agnostic via conditional imports (dart.library.js_interop): native builds use dart:io files, the web preview uses localStorage. Links and tags are parsed from note text on the fly — the graph is derived, never stored separately.
