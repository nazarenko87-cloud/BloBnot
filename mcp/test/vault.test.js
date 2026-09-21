import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, before, test } from 'node:test';

import { Vault, VaultError } from '../src/vault.js';

let root;
let vault;

before(async () => {
  root = await fs.mkdtemp(path.join(os.tmpdir(), 'blobnot-mcp-'));
  vault = new Vault(root);
  await fs.mkdir(path.join(root, 'Work'));
  await fs.mkdir(path.join(root, '_archive'));
  await fs.writeFile(
    path.join(root, 'Alpha.md'),
    '# Alpha\n\nSees [[Beta]] #idea\n- [x] done\n- [ ] todo\n{{remind:2026-09-20T15:00}}\n',
  );
  await fs.writeFile(path.join(root, 'Work', 'Beta.md'), '# Beta\n\n#work note body\n');
  await fs.writeFile(path.join(root, '_archive', 'Old.md'), '# Old\n');
});

after(async () => {
  await fs.rm(root, { recursive: true, force: true });
});

test('lists notes recursively and skips reserved folders', async () => {
  const notes = await vault.listNotes();
  assert.deepEqual(
    notes.map((n) => n.title),
    ['Alpha', 'Beta'],
  );
  assert.equal(notes.find((n) => n.title === 'Beta').project, 'Work');
});

test('derives links, tags, checklist and inline reminders from the body', async () => {
  const alpha = await vault.findNote('Alpha');
  assert.deepEqual(alpha.links, ['Beta']);
  assert.deepEqual(alpha.tags, ['idea']);
  assert.deepEqual(alpha.checklist, { total: 2, done: 1 });
  assert.deepEqual(alpha.lineReminders, ['2026-09-20T15:00']);
});

test('finds a note case-insensitively', async () => {
  assert.equal((await vault.findNote('alpha')).title, 'Alpha');
  assert.equal(await vault.findNote('nope'), null);
});

test('de-duplicates a clashing title instead of overwriting', async () => {
  const saved = await vault.writeNote({ title: 'Alpha', body: '# copy\n' });
  assert.equal(saved.title, 'Alpha (1)');
  assert.equal((await vault.findNote('Alpha')).body.startsWith('# Alpha'), true);
});

test('overwrite replaces the body in place', async () => {
  await vault.writeNote({ title: 'Beta', body: '# Beta v2\n', project: 'Work', overwrite: true });
  const beta = await vault.findNote('Beta');
  assert.equal(beta.body, '# Beta v2\n');
  assert.equal(beta.project, 'Work');
});

test('archiving moves the file into _archive', async () => {
  const note = await vault.writeNote({ title: 'Temp', body: '# Temp\n' });
  const dest = await vault.archiveNote(note);
  assert.equal(dest, '_archive/Temp.md');
  assert.equal(await vault.findNote('Temp'), null);
});

test('reminders round-trip through reminders.json in the app format', async () => {
  await vault.writeReminders({ Alpha: '2026-09-20T15:00:00.000' });
  const raw = JSON.parse(await fs.readFile(path.join(root, 'reminders.json'), 'utf8'));
  assert.deepEqual(raw, { Alpha: '2026-09-20T15:00:00.000' });
  assert.deepEqual(await vault.readReminders(), raw);
});

test('hot tasks: reads the app format and is not listed as a note or project', async () => {
  await fs.mkdir(path.join(root, '_hot'), { recursive: true });
  await fs.writeFile(
    path.join(root, '_hot', 'tasks.md'),
    '# Hot tasks\r\n\r\n- [ ] Call Oleg\r\n- [x] Send invoice ✓ 2026-09-21 14:30\r\nprose\r\n',
  );
  assert.deepEqual(await vault.readHotTasks(), [
    { text: 'Call Oleg', done: null },
    { text: 'Send invoice', done: '2026-09-21 14:30' },
  ]);
  const notes = await vault.listNotes();
  assert.ok(!notes.some((n) => n.relPath.startsWith('_hot/')));
  assert.ok(!(await vault.listProjects()).includes('_hot'));
});

test('hot tasks: writes open first, then done newest first', async () => {
  await vault.writeHotTasks([
    { text: 'older', done: '2026-09-20 10:00' },
    { text: 'open', done: null },
    { text: 'newer', done: '2026-09-21 09:00' },
  ]);
  const saved = await fs.readFile(path.join(root, '_hot', 'tasks.md'), 'utf8');
  assert.equal(
    saved,
    '# Hot tasks\n\n- [ ] open\n- [x] newer ✓ 2026-09-21 09:00\n- [x] older ✓ 2026-09-20 10:00\n',
  );
});

test('rejects paths and titles that escape the vault', async () => {
  assert.throws(() => vault.resolve('../outside.md'), VaultError);
  assert.throws(() => vault.assertValidTitle('../evil'), VaultError);
  assert.throws(() => vault.assertValidTitle(''), VaultError);
  await assert.rejects(() => vault.writeNote({ title: '../evil', body: 'x' }), VaultError);
});
