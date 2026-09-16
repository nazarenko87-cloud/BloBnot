import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';

/**
 * Registers this server in Claude Desktop's config file, so the installer can
 * offer a "connect it for me" checkbox instead of asking people to hand-edit
 * JSON. Other servers already in the file are preserved.
 */

const SERVER_KEY = 'blobnot';

export function claudeConfigPath() {
  if (process.platform === 'win32') {
    const appData = process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming');
    return path.join(appData, 'Claude', 'claude_desktop_config.json');
  }
  if (process.platform === 'darwin') {
    return path.join(os.homedir(), 'Library', 'Application Support', 'Claude', 'claude_desktop_config.json');
  }
  return path.join(os.homedir(), '.config', 'Claude', 'claude_desktop_config.json');
}

async function readConfig(file) {
  try {
    const parsed = JSON.parse(await fs.readFile(file, 'utf8'));
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch (error) {
    if (error.code === 'ENOENT') return {};
    // A config we cannot parse is a config we must not overwrite — someone
    // else's servers are in there.
    throw new Error(
      `Claude Desktop config exists but is not valid JSON: ${file}\n` +
        `Fix or remove it first (${error.message}).`,
    );
  }
}

async function writeConfig(file, config) {
  await fs.mkdir(path.dirname(file), { recursive: true });
  await fs.writeFile(file, `${JSON.stringify(config, null, 2)}\n`, 'utf8');
}

/** Back up an existing config once per change, so a bad merge is recoverable. */
async function backup(file) {
  try {
    await fs.copyFile(file, `${file}.bak`);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
}

/**
 * Point Claude Desktop at this executable. [vault] is optional — without it the
 * server falls back to whatever vault the app opened last.
 */
export async function register({ command, args = [], vault } = {}) {
  const file = claudeConfigPath();
  const config = await readConfig(file);
  await backup(file);

  config.mcpServers ??= {};
  config.mcpServers[SERVER_KEY] = {
    command: command ?? process.execPath,
    ...(args.length ? { args } : {}),
    ...(vault ? { env: { BLOBNOT_VAULT: vault } } : {}),
  };

  await writeConfig(file, config);
  return file;
}

export async function unregister() {
  const file = claudeConfigPath();
  const config = await readConfig(file);
  if (!config.mcpServers?.[SERVER_KEY]) return null;

  await backup(file);
  delete config.mcpServers[SERVER_KEY];
  await writeConfig(file, config);
  return file;
}
