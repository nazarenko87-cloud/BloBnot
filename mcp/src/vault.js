import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';

/**
 * File-level access to a BloBnot vault.
 *
 * Every format here mirrors what the Flutter app reads and writes, so the app
 * and this server can share one vault folder without converting anything:
 * notes are `.md` files, metadata lives in JSON files next to them.
 */

/** Folders the app hides from the note list — mirrors VaultStorage._reservedDirs. */
const RESERVED_DIRS = new Set(['_archive', '_templates', '_hot', 'attachments', '.history']);

const LINK_RE = /\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|[^\]]+)?\]\]/g;
const TAG_RE = /(?:^|\s)#([\wЀ-ӿ-]+)/g;
const CHECKBOX_RE = /^\s*[-*] \[( |x|X)\]/gm;
const REMIND_RE = /\{\{remind:([^}]+)\}\}/g;

/** Characters that are illegal in a Windows filename, plus path separators. */
const ILLEGAL_TITLE_RE = /[<>:"/\\|?*]/;

export class VaultError extends Error {}

/**
 * Locate the vault: `BLOBNOT_VAULT` wins, otherwise fall back to the folder
 * the desktop app opened last (`~/.bloknot/settings.json`).
 */
export async function resolveVaultRoot(explicit) {
  const candidate = explicit || process.env.BLOBNOT_VAULT || (await lastVaultFromAppSettings());
  if (!candidate) {
    throw new VaultError(
      'No vault configured. Set the BLOBNOT_VAULT environment variable to your ' +
        'vault folder, or open a vault once in the BloBnot desktop app.',
    );
  }
  if (candidate.startsWith('content://')) {
    throw new VaultError(
      'The last vault is an Android SAF folder (content:// URI), which is only ' +
        'reachable from inside the app. Set BLOBNOT_VAULT to a desktop folder path.',
    );
  }
  const root = path.resolve(candidate);
  const stat = await fs.stat(root).catch(() => null);
  if (!stat?.isDirectory()) {
    throw new VaultError(`Vault folder does not exist: ${root}`);
  }
  return root;
}

async function lastVaultFromAppSettings() {
  const file = path.join(os.homedir(), '.bloknot', 'settings.json');
  const data = await readJson(file, null);
  return typeof data?.vault === 'string' ? data.vault : null;
}

async function readJson(file, fallback) {
  try {
    return JSON.parse(await fs.readFile(file, 'utf8'));
  } catch {
    return fallback;
  }
}

async function writeJson(file, data) {
  await fs.writeFile(file, JSON.stringify(data), 'utf8');
}

export class Vault {
  constructor(root) {
    this.root = root;
  }

  /**
   * Absolute path for a vault-relative path, refusing anything that escapes
   * the vault (`..`, absolute paths, drive letters) — note titles reach this
   * from model input, so containment is enforced here rather than trusted.
   */
  resolve(relative) {
    const full = path.resolve(this.root, relative);
    const rel = path.relative(this.root, full);
    if (rel.startsWith('..') || path.isAbsolute(rel)) {
      throw new VaultError(`Path escapes the vault: ${relative}`);
    }
    return full;
  }

  assertValidTitle(title) {
    if (!title || !title.trim()) throw new VaultError('Note title cannot be empty.');
    if (ILLEGAL_TITLE_RE.test(title)) {
      throw new VaultError(`Note title contains illegal characters: ${title}`);
    }
  }

  /** Folder for a project name, or the vault root when the name is empty. */
  projectDir(project) {
    if (!project) return this.root;
    this.assertValidTitle(project);
    return this.resolve(project);
  }

  /** First-level subfolders, minus dot- and reserved folders. */
  async listProjects() {
    const entries = await fs.readdir(this.root, { withFileTypes: true });
    return entries
      .filter((e) => e.isDirectory() && !e.name.startsWith('.') && !RESERVED_DIRS.has(e.name))
      .map((e) => e.name)
      .sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
  }

  /** Every `.md` file in the vault, recursively, skipping reserved folders. */
  async listNotes() {
    const notes = [];
    const walk = async (dir) => {
      const entries = await fs.readdir(dir, { withFileTypes: true });
      for (const entry of entries) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          if (entry.name.startsWith('.') || RESERVED_DIRS.has(entry.name)) continue;
          await walk(full);
        } else if (entry.name.toLowerCase().endsWith('.md')) {
          notes.push(full);
        }
      }
    };
    await walk(this.root);
    const loaded = await Promise.all(notes.map((f) => this.readNoteAt(f)));
    return loaded.sort((a, b) => a.title.toLowerCase().localeCompare(b.title.toLowerCase()));
  }

  async readNoteAt(fullPath) {
    const [body, stat] = await Promise.all([
      fs.readFile(fullPath, 'utf8'),
      fs.stat(fullPath),
    ]);
    const relative = path.relative(this.root, fullPath).split(path.sep).join('/');
    const segments = relative.split('/');
    return {
      title: path.basename(fullPath).replace(/\.md$/i, ''),
      project: segments.length > 1 ? segments[0] : '',
      relPath: relative,
      body,
      modified: stat.mtime.toISOString(),
      ...derive(body),
    };
  }

  /** Find a note by exact title first, then case-insensitively. */
  async findNote(title) {
    const notes = await this.listNotes();
    return (
      notes.find((n) => n.title === title) ??
      notes.find((n) => n.title.toLowerCase() === title.toLowerCase()) ??
      null
    );
  }

  /**
   * Write a note, creating the project folder when needed. Existing notes are
   * overwritten only when [overwrite] is set; otherwise the title gets a
   * ` (n)` suffix, the same de-duplication the app uses.
   */
  async writeNote({ title, body, project = '', overwrite = false }) {
    this.assertValidTitle(title);
    const dir = this.projectDir(project);
    await fs.mkdir(dir, { recursive: true });

    let finalTitle = title;
    if (!overwrite) {
      let i = 1;
      while (await exists(path.join(dir, `${finalTitle}.md`))) {
        finalTitle = `${title} (${i})`;
        i += 1;
      }
    }
    const full = path.join(dir, `${finalTitle}.md`);
    await fs.writeFile(full, body, 'utf8');
    return this.readNoteAt(full);
  }

  /** Soft delete: move the note into `_archive/`, de-duplicating the name. */
  async archiveNote(note) {
    const archiveDir = path.join(this.root, '_archive');
    await fs.mkdir(archiveDir, { recursive: true });
    let dest = path.join(archiveDir, `${note.title}.md`);
    let i = 1;
    while (await exists(dest)) {
      dest = path.join(archiveDir, `${note.title} (${i}).md`);
      i += 1;
    }
    await fs.rename(this.resolve(note.relPath), dest);
    return path.relative(this.root, dest).split(path.sep).join('/');
  }

  // --- metadata files, byte-compatible with the Flutter stores ---

  /** `{vault}/reminders.json`: note title → ISO-8601 timestamp. */
  async readReminders() {
    const raw = await readJson(path.join(this.root, 'reminders.json'), {});
    return raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
  }

  async writeReminders(map) {
    await writeJson(path.join(this.root, 'reminders.json'), map);
  }

  /** `{vault}/calendar_events.json`: standalone reminders `[{id, title, when}]`. */
  async readEvents() {
    const raw = await readJson(path.join(this.root, 'calendar_events.json'), []);
    return Array.isArray(raw) ? raw : [];
  }

  async writeEvents(events) {
    await writeJson(path.join(this.root, 'calendar_events.json'), events);
  }

  /** `{vault}/pinned.json`: a sorted JSON array of note titles. */
  async readPinned() {
    const raw = await readJson(path.join(this.root, 'pinned.json'), []);
    return Array.isArray(raw) ? raw.filter((t) => typeof t === 'string') : [];
  }

  async writePinned(titles) {
    await writeJson(path.join(this.root, 'pinned.json'), [...new Set(titles)].sort());
  }

  // --- hot tasks: `_hot/tasks.md`, the same checklist the app reads ---

  /** `[{text, done}]`, `done` a `YYYY-MM-DD HH:MM` stamp or null. */
  async readHotTasks() {
    let source = '';
    try {
      source = await fs.readFile(path.join(this.root, ...HOT_TASKS), 'utf8');
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
    const tasks = [];
    for (const raw of source.split('\n')) {
      const m = HOT_LINE.exec(raw.trimEnd());
      if (!m) continue;
      let text = m[2];
      let done = null;
      if (m[1].toLowerCase() === 'x') {
        const s = HOT_STAMP.exec(text);
        if (s) text = text.slice(0, s.index);
        done = s ? s[1].replace('T', ' ') : hotStamp(new Date());
      }
      text = cleanHotText(text);
      if (text) tasks.push({ text, done });
    }
    return tasks;
  }

  /** In-progress first in their order, then done newest first — as the app writes it. */
  async writeHotTasks(tasks) {
    const open = tasks.filter((t) => !t.done);
    const done = tasks.filter((t) => t.done).sort((a, b) => b.done.localeCompare(a.done));
    const lines = [
      '# Hot tasks',
      '',
      ...open.map((t) => `- [ ] ${t.text}`),
      ...done.map((t) => `- [x] ${t.text} ✓ ${t.done}`),
      '',
    ];
    const file = path.join(this.root, ...HOT_TASKS);
    await fs.mkdir(path.dirname(file), { recursive: true });
    await fs.writeFile(file, lines.join('\n'), 'utf8');
  }
}

const HOT_TASKS = ['_hot', 'tasks.md'];
const HOT_LINE = /^\s*[-*] \[( |x|X)\]\s?(.*)$/;
const HOT_STAMP = /\s*✓\s*(\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2})?)\s*$/;

export function cleanHotText(text) {
  return String(text).replace(/\s+/g, ' ').trim();
}

/** Local time, minute precision — the stamp format the app writes. */
export function hotStamp(date) {
  const two = (n) => String(n).padStart(2, '0');
  return (
    `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())} ` +
    `${two(date.getHours())}:${two(date.getMinutes())}`
  );
}

async function exists(file) {
  return fs
    .access(file)
    .then(() => true)
    .catch(() => false);
}

/** Values the app derives from note text on the fly rather than storing. */
function derive(body) {
  const links = [...body.matchAll(LINK_RE)].map((m) => m[1].trim()).filter(Boolean);
  const tags = [...body.matchAll(TAG_RE)].map((m) => m[1].toLowerCase());
  const boxes = [...body.matchAll(CHECKBOX_RE)];
  const lineReminders = [...body.matchAll(REMIND_RE)]
    .map((m) => m[1].trim())
    .filter((s) => !Number.isNaN(Date.parse(s)));
  const words = body.trim() ? body.trim().split(/\s+/).length : 0;
  return {
    links: [...new Set(links)],
    tags: [...new Set(tags)],
    wordCount: words,
    checklist: boxes.length
      ? { total: boxes.length, done: boxes.filter((m) => m[1].toLowerCase() === 'x').length }
      : null,
    lineReminders,
  };
}

/** `{{remind:ISO}}` tag, the inline reminder format the app parses. */
export function buildRemindTag(iso) {
  return `{{remind:${iso}}}`;
}
