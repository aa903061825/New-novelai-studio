import fs from 'node:fs';
import path from 'node:path';

const defaultCacheDir = path.join(
  process.env.APPDATA ?? '',
  'org.exception0x0194',
  'nai3_autodraw',
  'novel_studio',
  'script_recast',
  'cache',
);

const options = parseArgs(process.argv.slice(2));
const cacheDir = options.cacheDir ?? defaultCacheDir;
const backupDir = options.backupDir;
if (!backupDir) throw new Error('--backup-dir is required');

const changed = [];
for (const fileName of fs.readdirSync(cacheDir).filter((file) => file.endsWith('.json')).sort()) {
  const cachePath = path.join(cacheDir, fileName);
  const cache = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
  const root = cache.sourceRootPath;
  if (!root || !fs.existsSync(root)) continue;
  const files = fs.readdirSync(root, { withFileTypes: true }).filter((entry) => entry.isFile()).map((entry) => entry.name);
  const jsonStems = stems(files, '.json').filter((stem) => stem.toLowerCase() !== 'info');
  const pngStems = stems(files, '.png');
  if (jsonStems.length === 0 || pngStems.length === 0) continue;
  if (sameList(jsonStems, pngStems)) continue;

  backupCache(fileName);
  cache.scriptSnapshot = { frames: [] };
  cache.sourceFingerprint = '';
  cache.updatedAt = new Date().toISOString();
  fs.writeFileSync(cachePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
  changed.push({
    file_name: fileName,
    script_name: cache.scriptName,
    json_count: jsonStems.length,
    png_count: pngStems.length,
  });
}

console.log(JSON.stringify({ changed_files: changed }, null, 2));

function stems(files, ext) {
  return files
    .filter((name) => path.extname(name).toLowerCase() === ext)
    .map((name) => path.basename(name, path.extname(name)))
    .sort(naturalCompare);
}

function sameList(left, right) {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

function naturalCompare(left, right) {
  return left.localeCompare(right, undefined, { numeric: true, sensitivity: 'base' });
}

function backupCache(fileName) {
  const source = path.join(cacheDir, fileName);
  const target = path.join(backupDir, fileName);
  if (fs.existsSync(target)) return;
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.copyFileSync(source, target);
}

function parseArgs(args) {
  const parsed = { cacheDir: undefined, backupDir: undefined };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith('--')) continue;
    const equalIndex = arg.indexOf('=');
    const key = equalIndex > 0 ? arg.slice(2, equalIndex) : arg.slice(2);
    const value = equalIndex > 0 ? arg.slice(equalIndex + 1) : args[index + 1] ?? '';
    if (equalIndex < 0) index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'backup-dir') parsed.backupDir = value;
  }
  return parsed;
}
