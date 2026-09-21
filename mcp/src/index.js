#!/usr/bin/env node
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';

import { claudeConfigPath, register, unregister } from './claude-config.js';
import {
  Vault,
  VaultError,
  buildRemindTag,
  cleanHotText,
  hotStamp,
  resolveVaultRoot,
} from './vault.js';

/**
 * MCP server over a BloBnot vault.
 *
 * The vault is a plain folder of Markdown files, so this server and the
 * desktop app can both work on it. The app re-reads the vault on Refresh
 * (Ctrl+R), which is how edits made here show up in an already-open window.
 */

const VERSION = '1.1.0';

const server = new McpServer({ name: 'blobnot', version: VERSION });

/** Command-line flags; anything left over is treated as the vault path. */
const argv = process.argv.slice(2);
const flag = (name) => argv.includes(`--${name}`);
const value = (name) => {
  const at = argv.indexOf(`--${name}`);
  return at >= 0 ? argv[at + 1] : undefined;
};
const vaultArg = argv.find((a) => !a.startsWith('--') && argv[argv.indexOf(a) - 1] !== '--vault');

/** Resolved once per process; the vault path does not change while running. */
let vaultPromise;
function getVault() {
  vaultPromise ??= resolveVaultRoot(value('vault') ?? vaultArg).then((root) => new Vault(root));
  return vaultPromise;
}

/**
 * How Claude Desktop should launch this server. A single-executable build is
 * its own command; running from source needs node plus the script path.
 */
async function launchCommand() {
  const sea = await import('node:sea').catch(() => null);
  if (sea?.isSea?.()) return { command: process.execPath, args: [] };
  return { command: process.execPath, args: [process.argv[1]] };
}

const json = (data) => ({ content: [{ type: 'text', text: JSON.stringify(data, null, 2) }] });
const text = (message) => ({ content: [{ type: 'text', text: message }] });
const failure = (message) => ({ content: [{ type: 'text', text: message }], isError: true });

/** Wraps a handler so vault problems come back as tool errors, not crashes. */
function tool(handler) {
  return async (args) => {
    try {
      return await handler(args, await getVault());
    } catch (error) {
      if (error instanceof VaultError) return failure(error.message);
      throw error;
    }
  };
}

/** Note shape for list/search results — body is omitted to keep replies small. */
const summary = (note) => ({
  title: note.title,
  project: note.project,
  modified: note.modified,
  wordCount: note.wordCount,
  tags: note.tags,
  checklist: note.checklist,
});

server.registerTool(
  'list_notes',
  {
    title: 'List notes',
    description:
      'List notes in the vault (titles, project, tags, word count, checklist progress). ' +
      'Optionally filter to one project folder. Note bodies are not included — use read_note.',
    inputSchema: {
      project: z.string().optional().describe('Project folder name; omit for all notes'),
    },
  },
  tool(async ({ project }, vault) => {
    const notes = await vault.listNotes();
    const filtered = project ? notes.filter((n) => n.project === project) : notes;
    return json({ count: filtered.length, notes: filtered.map(summary) });
  }),
);

server.registerTool(
  'read_note',
  {
    title: 'Read note',
    description: 'Read one note by title, including its full Markdown body, links and tags.',
    inputSchema: { title: z.string().describe('Note title (the file name without .md)') },
  },
  tool(async ({ title }, vault) => {
    const note = await vault.findNote(title);
    if (!note) return failure(`No note titled "${title}".`);
    return json(note);
  }),
);

server.registerTool(
  'search_notes',
  {
    title: 'Search notes',
    description:
      'Full-text search across note titles and bodies, with an optional #tag filter. ' +
      'Returns matching notes with a short excerpt around the first hit.',
    inputSchema: {
      query: z.string().optional().describe('Text to look for (case-insensitive)'),
      tag: z.string().optional().describe('Only notes carrying this #tag (without the #)'),
      limit: z.number().int().positive().max(100).optional().describe('Max results, default 20'),
    },
  },
  tool(async ({ query, tag, limit = 20 }, vault) => {
    if (!query && !tag) return failure('Provide a query, a tag, or both.');
    const needle = query?.toLowerCase();
    const wanted = tag?.toLowerCase().replace(/^#/, '');
    const hits = [];
    for (const note of await vault.listNotes()) {
      if (wanted && !note.tags.includes(wanted)) continue;
      if (!needle) {
        hits.push({ ...summary(note), excerpt: note.body.slice(0, 200) });
        continue;
      }
      const at = note.body.toLowerCase().indexOf(needle);
      const inTitle = note.title.toLowerCase().includes(needle);
      if (at < 0 && !inTitle) continue;
      const from = at < 0 ? 0 : Math.max(0, at - 80);
      hits.push({ ...summary(note), excerpt: note.body.slice(from, from + 240) });
    }
    return json({ count: hits.length, notes: hits.slice(0, limit) });
  }),
);

server.registerTool(
  'write_note',
  {
    title: 'Write note',
    description:
      'Create a new note, or replace an existing one when overwrite is true. ' +
      'Without overwrite, a clashing title gets a " (n)" suffix instead of losing data.',
    inputSchema: {
      title: z.string().describe('Note title; becomes the .md file name'),
      body: z.string().describe('Full Markdown body. [[Wiki links]] and #tags work.'),
      project: z.string().optional().describe('Project folder; omit for the vault root'),
      overwrite: z.boolean().optional().describe('Replace an existing note with this title'),
    },
  },
  tool(async ({ title, body, project = '', overwrite = false }, vault) => {
    if (overwrite) {
      const existing = await vault.findNote(title);
      if (existing) {
        const saved = await vault.writeNote({
          title: existing.title,
          body,
          project: existing.project,
          overwrite: true,
        });
        return json({ action: 'replaced', note: summary(saved) });
      }
    }
    const saved = await vault.writeNote({ title, body, project });
    return json({ action: 'created', note: summary(saved) });
  }),
);

server.registerTool(
  'append_to_note',
  {
    title: 'Append to note',
    description:
      'Append text to the end of an existing note, creating the note when it does not exist. ' +
      'Use this for adding an item to a running list instead of rewriting the whole body.',
    inputSchema: {
      title: z.string().describe('Note title'),
      text: z.string().describe('Markdown to append'),
      project: z.string().optional().describe('Project folder used if the note must be created'),
    },
  },
  tool(async ({ title, text: addition, project = '' }, vault) => {
    const existing = await vault.findNote(title);
    if (!existing) {
      const created = await vault.writeNote({ title, body: `# ${title}\n\n${addition}\n`, project });
      return json({ action: 'created', note: summary(created) });
    }
    const separator = existing.body.endsWith('\n') ? '' : '\n';
    const saved = await vault.writeNote({
      title: existing.title,
      body: `${existing.body}${separator}${addition}\n`,
      project: existing.project,
      overwrite: true,
    });
    return json({ action: 'appended', note: summary(saved) });
  }),
);

server.registerTool(
  'archive_note',
  {
    title: 'Archive note',
    description:
      'Soft-delete a note by moving it to the vault\'s _archive folder — the same thing the ' +
      'app does, so it can be restored from Archive in the UI. Nothing is erased.',
    inputSchema: { title: z.string().describe('Note title') },
  },
  tool(async ({ title }, vault) => {
    const note = await vault.findNote(title);
    if (!note) return failure(`No note titled "${title}".`);
    const dest = await vault.archiveNote(note);
    return text(`Archived "${note.title}" to ${dest}.`);
  }),
);

server.registerTool(
  'list_projects',
  {
    title: 'List projects',
    description: 'List project folders in the vault, with a note count for each.',
    inputSchema: {},
  },
  tool(async (_args, vault) => {
    const [projects, notes] = await Promise.all([vault.listProjects(), vault.listNotes()]);
    return json({
      root: notes.filter((n) => !n.project).length,
      projects: projects.map((name) => ({
        name,
        notes: notes.filter((n) => n.project === name).length,
      })),
    });
  }),
);

server.registerTool(
  'list_reminders',
  {
    title: 'List reminders',
    description:
      'All reminders in the vault, across the three kinds BloBnot supports: note reminders, ' +
      'standalone calendar events, and {{remind:}} tags inside note text.',
    inputSchema: {},
  },
  tool(async (_args, vault) => {
    const [reminders, events, notes] = await Promise.all([
      vault.readReminders(),
      vault.readEvents(),
      vault.listNotes(),
    ]);
    const lines = notes.flatMap((n) =>
      n.lineReminders.map((when) => ({ kind: 'line', note: n.title, when })),
    );
    return json({
      notes: Object.entries(reminders).map(([note, when]) => ({ kind: 'note', note, when })),
      events: events.map((e) => ({ kind: 'event', id: e.id, title: e.title, when: e.when })),
      lines,
    });
  }),
);

server.registerTool(
  'add_reminder',
  {
    title: 'Add reminder',
    description:
      'Add a reminder. With a note title it attaches to that note; without one it creates a ' +
      'standalone calendar event shown on the dashboard calendar. The app alerts when due.',
    inputSchema: {
      when: z.string().describe('When it is due, ISO-8601 local time e.g. 2026-09-20T15:00'),
      title: z.string().optional().describe('Standalone reminder text (when no note is given)'),
      note: z.string().optional().describe('Attach to this note instead of standing alone'),
      inline: z
        .boolean()
        .optional()
        .describe('With a note: append a {{remind:}} tag to its text instead of a note reminder'),
    },
  },
  tool(async ({ when, title, note, inline = false }, vault) => {
    if (Number.isNaN(Date.parse(when))) return failure(`Not a valid date-time: ${when}`);

    if (note) {
      const target = await vault.findNote(note);
      if (!target) return failure(`No note titled "${note}".`);
      if (inline) {
        const separator = target.body.endsWith('\n') ? '' : '\n';
        const line = title ? `${title} ${buildRemindTag(when)}` : buildRemindTag(when);
        await vault.writeNote({
          title: target.title,
          body: `${target.body}${separator}${line}\n`,
          project: target.project,
          overwrite: true,
        });
        return text(`Added an inline reminder to "${target.title}" for ${when}.`);
      }
      const reminders = await vault.readReminders();
      reminders[target.title] = when;
      await vault.writeReminders(reminders);
      return text(`Reminder set on note "${target.title}" for ${when}.`);
    }

    if (!title) return failure('Provide a title for a standalone reminder, or a note to attach to.');
    const events = await vault.readEvents();
    const event = { id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`, title, when };
    events.push(event);
    await vault.writeEvents(events);
    return json({ action: 'created', event });
  }),
);

server.registerTool(
  'list_hot_tasks',
  {
    title: 'List hot tasks',
    description:
      'Short running to-dos from the Hot tasks view: what is in progress, and what was done ' +
      'recently (with when). Done tasks older than 30 days live in the app\'s archive.',
    inputSchema: {},
  },
  tool(async (_args, vault) => {
    const tasks = await vault.readHotTasks();
    return json({
      inProgress: tasks.filter((t) => !t.done).map((t) => t.text),
      done: tasks.filter((t) => t.done).map((t) => ({ text: t.text, done: t.done })),
    });
  }),
);

server.registerTool(
  'add_hot_task',
  {
    title: 'Add hot task',
    description:
      'Add a short to-do to the top of Hot tasks → In progress. Keep it to one line: ' +
      'what needs doing, not a note.',
    inputSchema: { text: z.string().describe('The task, one short line') },
  },
  tool(async ({ text: raw }, vault) => {
    const task = cleanHotText(raw);
    if (!task) return failure('Task text cannot be empty.');
    const tasks = await vault.readHotTasks();
    await vault.writeHotTasks([{ text: task, done: null }, ...tasks]);
    return text(`Added hot task "${task}".`);
  }),
);

server.registerTool(
  'complete_hot_task',
  {
    title: 'Complete hot task',
    description:
      'Mark an in-progress hot task done, stamped with the current time. Matches the exact ' +
      'text first, then case-insensitively, then a unique partial match.',
    inputSchema: { text: z.string().describe('The task text, or a unique part of it') },
  },
  tool(async ({ text: query }, vault) => {
    const tasks = await vault.readHotTasks();
    const open = tasks.filter((t) => !t.done);
    const q = cleanHotText(query).toLowerCase();
    const partial = open.filter((t) => t.text.toLowerCase().includes(q));
    const match =
      open.find((t) => t.text === cleanHotText(query)) ??
      open.find((t) => t.text.toLowerCase() === q) ??
      (partial.length === 1 ? partial[0] : null);
    if (!match) {
      return failure(
        partial.length > 1
          ? `"${query}" matches ${partial.length} tasks: ${partial.map((t) => t.text).join('; ')}`
          : `No in-progress hot task matches "${query}".`,
      );
    }
    const stamp = hotStamp(new Date());
    await vault.writeHotTasks(tasks.map((t) => (t === match ? { ...t, done: stamp } : t)));
    return text(`Done: "${match.text}" at ${stamp}.`);
  }),
);

server.registerTool(
  'vault_info',
  {
    title: 'Vault info',
    description:
      'Where the vault is and what it holds: note, project and reminder counts, pinned notes, ' +
      'and the tags in use. Good first call to confirm the server sees the right folder.',
    inputSchema: {},
  },
  tool(async (_args, vault) => {
    const [notes, projects, reminders, events, pinned] = await Promise.all([
      vault.listNotes(),
      vault.listProjects(),
      vault.readReminders(),
      vault.readEvents(),
      vault.readPinned(),
    ]);
    const tags = new Set(notes.flatMap((n) => n.tags));
    return json({
      vault: vault.root,
      notes: notes.length,
      projects: projects.length,
      pinned,
      reminders: Object.keys(reminders).length + events.length,
      tags: [...tags].sort(),
      words: notes.reduce((sum, n) => sum + n.wordCount, 0),
    });
  }),
);

// --- entry point ---
//
// Normally this process IS the MCP server and stdout belongs to the protocol,
// so nothing may be printed there. The setup flags below are the exception:
// they do their work, report on stderr, and exit without starting a server.

const USAGE = [
  `blobnot-mcp ${VERSION} — MCP server for a BloBnot vault`,
  '',
  'Usage:',
  '  blobnot-mcp [--vault <folder>]     run the server (stdio)',
  '  blobnot-mcp --register [--vault <folder>]',
  '                                    add it to Claude Desktop',
  '  blobnot-mcp --unregister          remove it from Claude Desktop',
  '',
  'Without --vault the server uses BLOBNOT_VAULT, then the vault the',
  'BloBnot desktop app opened last.',
  '',
].join('\n');

async function main() {
  if (flag('version')) {
    process.stderr.write(`blobnot-mcp ${VERSION}\n`);
    return;
  }
  if (flag('help')) {
    process.stderr.write(USAGE);
    return;
  }

  if (flag('unregister')) {
    const file = await unregister();
    process.stderr.write(
      file ? `Removed "blobnot" from ${file}\n` : `Nothing to remove in ${claudeConfigPath()}\n`,
    );
    return;
  }

  if (flag('register')) {
    const vault = value('vault') ?? vaultArg;
    if (vault) await resolveVaultRoot(vault); // fail now, not at first use
    const file = await register({ ...(await launchCommand()), vault });
    process.stderr.write(`Registered "blobnot" in ${file}\nRestart Claude Desktop to pick it up.\n`);
    return;
  }

  await server.connect(new StdioServerTransport());
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
});
