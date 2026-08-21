import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const sourceCacheDir = String.raw`C:\Users\admin\AppData\Roaming\org.exception0x0194\nai3_autodraw\novel_studio\script_recast\cache`;
const targetCacheDir = String.raw`C:\Users\admin\AppData\Roaming\Novel Studio\Novel Studio\novel_studio\script_recast\cache`;
const allowedSourceRoot = String.raw`E:\NAI的脚本群\作品集\带图精品`;
const targetFiles = [
  'script-2-386d8895c7683ba6.json',
  'script-2-db8e8408f5c5a47b.json',
  'script-2-e55e317517d0fe4b.json',
  'script-32294165a138a3c9.json',
  'script-4-483f0d961dbafdcc.json',
  'script-4d8a25fdbfe8f855.json',
  'script-a196cfd91d2e07a3.json',
  'script-ako-dress-bbc-ntr-3ad4bf46dce6774e.json',
  'script-d539a04e23fddcb6.json',
  'script-maki-camp-bbc-ntr-af6f4d2f59ae3d94.json',
  'script-reisa-magical-defeat-3277fc501f49a035.json',
  'script-toki-bunny-bbc-ntr-657f2ea003b35f20.json',
];

const apply = process.argv.includes('--apply');
const backupArgIndex = process.argv.indexOf('--backup-dir');
const explicitBackupDir = backupArgIndex >= 0
  ? process.argv[backupArgIndex + 1]
  : null;

function normalizeWindowsPath(value) {
  return path.win32.normalize(value).replace(/[\\/]+$/, '').toLowerCase();
}

function sha256(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

function timestampSlug() {
  return new Date().toISOString().replace(/[:.]/g, '-');
}

function loadAndValidateSource(fileName) {
  const sourcePath = path.join(sourceCacheDir, fileName);
  if (!fs.existsSync(sourcePath)) {
    throw new Error(`Missing source cache: ${sourcePath}`);
  }
  const bytes = fs.readFileSync(sourcePath);
  const cache = JSON.parse(bytes.toString('utf8'));
  const expectedName = `${String(cache.scriptId ?? '').trim()}.json`;
  if (expectedName !== fileName) {
    throw new Error(`${fileName}: scriptId does not match file name`);
  }
  const sourceRootPath = String(cache.sourceRootPath ?? '').trim();
  const normalizedSourceRoot = normalizeWindowsPath(sourceRootPath);
  const normalizedAllowedRoot = normalizeWindowsPath(allowedSourceRoot);
  if (
    normalizedSourceRoot !== normalizedAllowedRoot &&
    !normalizedSourceRoot.startsWith(`${normalizedAllowedRoot}\\`)
  ) {
    throw new Error(`${fileName}: sourceRootPath is outside the allowed root`);
  }
  const frames = cache?.scriptSnapshot?.frames;
  if (!Array.isArray(frames) || frames.length === 0) {
    throw new Error(`${fileName}: scriptSnapshot.frames is empty`);
  }
  const missingImages = frames.filter((frame) => {
    const candidates = [frame?.sourceImagePath, frame?.sourcePath]
      .map((value) => String(value ?? '').trim())
      .filter(Boolean);
    return !candidates.some((candidate) => fs.existsSync(candidate));
  });
  if (missingImages.length > 0) {
    throw new Error(`${fileName}: ${missingImages.length} frame images are missing`);
  }
  return {
    bytes,
    cache,
    frameCount: frames.length,
    sourcePath,
    sourceHash: sha256(bytes),
  };
}

const plan = targetFiles.map((fileName) => {
  const source = loadAndValidateSource(fileName);
  const targetPath = path.join(targetCacheDir, fileName);
  const targetBytes = fs.existsSync(targetPath) ? fs.readFileSync(targetPath) : null;
  const targetHash = targetBytes == null ? null : sha256(targetBytes);
  return {
    fileName,
    scriptId: source.cache.scriptId,
    scriptName: source.cache.scriptName,
    sourceRootPath: source.cache.sourceRootPath,
    frameCount: source.frameCount,
    sourcePath: source.sourcePath,
    sourceHash: source.sourceHash,
    targetPath,
    targetHash,
    action: targetHash == null
      ? 'create'
      : targetHash === source.sourceHash
        ? 'unchanged'
        : 'replace',
    bytes: source.bytes,
  };
});

const changed = plan.filter((entry) => entry.action !== 'unchanged');
const summary = {
  mode: apply ? 'apply' : 'dry-run',
  sourceCacheDir,
  targetCacheDir,
  allowedSourceRoot,
  targetCount: plan.length,
  createCount: plan.filter((entry) => entry.action === 'create').length,
  replaceCount: plan.filter((entry) => entry.action === 'replace').length,
  unchangedCount: plan.filter((entry) => entry.action === 'unchanged').length,
  entries: plan.map(({ bytes: _, ...entry }) => entry),
};

if (!apply) {
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
  process.exit(0);
}

const backupDir = explicitBackupDir
  ? path.resolve(explicitBackupDir)
  : path.resolve('build', `script-recast-workspace-sync-${timestampSlug()}`);
fs.mkdirSync(backupDir, { recursive: true });
fs.mkdirSync(targetCacheDir, { recursive: true });

for (const entry of changed) {
  if (entry.action === 'replace') {
    fs.copyFileSync(entry.targetPath, path.join(backupDir, entry.fileName));
  }
}

for (const entry of changed) {
  const tempPath = `${entry.targetPath}.sync-${process.pid}.tmp`;
  fs.writeFileSync(tempPath, entry.bytes);
  fs.renameSync(tempPath, entry.targetPath);
}

const appliedEntries = plan.map(({ bytes: _, ...entry }) => ({
  ...entry,
  appliedTargetHash: sha256(fs.readFileSync(entry.targetPath)),
}));
const manifest = {
  ...summary,
  backupDir,
  appliedAt: new Date().toISOString(),
  entries: appliedEntries,
};
fs.writeFileSync(
  path.join(backupDir, 'manifest.json'),
  `${JSON.stringify(manifest, null, 2)}\n`,
  'utf8',
);
process.stdout.write(`${JSON.stringify(manifest, null, 2)}\n`);
