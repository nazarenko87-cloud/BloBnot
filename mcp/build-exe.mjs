/**
 * Builds a single-executable `blobnot-mcp` — the MCP server plus its
 * dependencies plus a Node runtime in one file, so the installer can offer the
 * server without asking anyone to install Node first.
 *
 * Two steps: esbuild bundles the ESM sources into one CommonJS file (Node's
 * SEA takes a single script), then Node's SEA blob is injected into a copy of
 * the running Node binary.
 *
 *   node build-exe.mjs
 *
 * Paths stay relative to this folder throughout: the project path can contain
 * spaces, and a shell-invoked `npx` would split an absolute one.
 */
import { execFileSync } from 'node:child_process';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const isWindows = process.platform === 'win32';
const exeName = isWindows ? 'blobnot-mcp.exe' : 'blobnot-mcp';
const exeRel = `build/${exeName}`;

// No shell: both this script's own path and Node's install path routinely
// contain spaces, which a shell would split.
const run = (cmd, args, options = {}) =>
  execFileSync(cmd, args, { stdio: 'inherit', cwd: here, ...options });

/** Run a dependency's CLI through node, rather than relying on npx/PATH. */
const runTool = (script, args) => run(process.execPath, [script, ...args]);

await fs.rm(path.join(here, 'build'), { recursive: true, force: true });
await fs.mkdir(path.join(here, 'build'), { recursive: true });

console.log('> bundling');
runTool('node_modules/esbuild/bin/esbuild', [
  'src/index.js',
  '--bundle',
  '--platform=node',
  '--format=cjs',
  '--target=node20',
  '--outfile=build/bundle.cjs',
]);

console.log('> preparing SEA blob');
await fs.writeFile(
  path.join(here, 'build', 'sea-config.json'),
  JSON.stringify({
    main: 'build/bundle.cjs',
    output: 'build/sea-prep.blob',
    disableExperimentalSEAWarning: true,
  }),
);
run(process.execPath, ['--experimental-sea-config', 'build/sea-config.json']);

console.log('> copying the node runtime');
await fs.copyFile(process.execPath, path.join(here, exeRel));

// Node's own binary is signed; postject invalidates that signature, and
// Windows refuses to run a binary whose signature no longer matches. Stripping
// it first avoids that. Best effort — signtool is not always installed.
if (isWindows) {
  try {
    run('signtool', ['remove', '/s', exeRel], { stdio: 'ignore' });
  } catch {
    console.log('  (signtool unavailable — continuing unsigned)');
  }
}

console.log('> injecting');
runTool('node_modules/postject/dist/cli.js', [
  exeRel,
  'NODE_SEA_BLOB',
  'build/sea-prep.blob',
  '--sentinel-fuse',
  'NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2',
]);

const { size } = await fs.stat(path.join(here, exeRel));
console.log(`\nBuilt ${exeRel} (${(size / 1024 / 1024).toFixed(1)} MB)`);
