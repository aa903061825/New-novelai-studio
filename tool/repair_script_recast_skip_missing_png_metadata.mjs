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

const changedFiles = [];
let skippedFrames = 0;

for (const fileName of fs.readdirSync(cacheDir).filter((file) => file.endsWith('.json')).sort()) {
  const cachePath = path.join(cacheDir, fileName);
  const cache = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
  const frames = Array.isArray(cache.scriptSnapshot?.frames)
    ? cache.scriptSnapshot.frames
    : [];
  const missing = frames.filter(isMissingPngMetadataFrame);
  if (missing.length === 0) continue;

  const frameIndexMap = new Map();
  const nextFrames = [];
  for (const frame of frames) {
    const oldIndex = toInt(frame.index);
    if (oldIndex == null) continue;
    if (isMissingPngMetadataFrame(frame)) {
      skippedFrames += 1;
      continue;
    }
    const nextIndex = nextFrames.length + 1;
    frameIndexMap.set(oldIndex, nextIndex);
    nextFrames.push({
      ...frame,
      index: nextIndex,
    });
  }

  remapFrameIndexLists(cache.aiRoleExtraction, frameIndexMap);
  remapFrameIndexLists(cache.mapping, frameIndexMap);

  cache.scriptSnapshot.frames = nextFrames;
  cache.scriptSnapshot.parseWarnings = [
    ...new Set([
      ...(Array.isArray(cache.scriptSnapshot.parseWarnings)
        ? cache.scriptSnapshot.parseWarnings.filter((value) => typeof value === 'string')
        : []),
      `Skipped ${missing.length} PNG images because prompt metadata was missing or unreadable: ${missing.map((frame) => frame.fileName).join(', ')}.`,
    ]),
  ];
  cache.scriptSnapshot.meta = {
    ...(cache.scriptSnapshot.meta && typeof cache.scriptSnapshot.meta === 'object'
      ? cache.scriptSnapshot.meta
      : {}),
    frameCount: nextFrames.length,
    skippedMetadataFrameCount:
      Number(cache.scriptSnapshot.meta?.skippedMetadataFrameCount ?? 0) + missing.length,
    skippedMetadataFiles: [
      ...new Set([
        ...(Array.isArray(cache.scriptSnapshot.meta?.skippedMetadataFiles)
          ? cache.scriptSnapshot.meta.skippedMetadataFiles
          : []),
        ...missing.map((frame) => frame.fileName),
      ]),
    ],
  };
  cache.sourceFingerprint = sourceFingerprint(cache);
  cache.updatedAt = new Date().toISOString();

  backupCache(fileName);
  fs.writeFileSync(cachePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
  changedFiles.push(fileName);
}

console.log(JSON.stringify({ changed_files: changedFiles, skipped_frames: skippedFrames }, null, 2));

function isMissingPngMetadataFrame(frame) {
  return frame?.parsed?.sourcePayload?.source_kind === 'png_metadata_missing_frame';
}

function remapFrameIndexLists(value, frameIndexMap) {
  if (Array.isArray(value)) {
    for (const item of value) remapFrameIndexLists(item, frameIndexMap);
    return;
  }
  if (!value || typeof value !== 'object') return;
  for (const [key, child] of Object.entries(value)) {
    if ((key === 'frame_indexes' || key === 'frameIndexes') && Array.isArray(child)) {
      value[key] = [
        ...new Set(
          child
            .map((index) => frameIndexMap.get(toInt(index)))
            .filter((index) => Number.isInteger(index)),
        ),
      ].sort((left, right) => left - right);
    } else {
      remapFrameIndexLists(child, frameIndexMap);
    }
  }
}

function sourceFingerprint(cache) {
  const snapshot = cache.scriptSnapshot ?? {};
  const frames = Array.isArray(snapshot.frames) ? snapshot.frames : [];
  const parts = [
    cache.scriptId ?? snapshot.id ?? '',
    snapshot.rootPath ?? cache.sourceRootPath ?? '',
    ...frames.map(
      (frame) =>
        `${frame.index}:${frame.fileName}:${frame.sourcePath}:${stableContentHash(String(frame.rawJson ?? ''))}`,
    ),
  ];
  return parts.join('|');
}

function stableContentHash(value) {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, '0');
}

function backupCache(fileName) {
  const source = path.join(cacheDir, fileName);
  const target = path.join(backupDir, fileName);
  if (fs.existsSync(target)) return;
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.copyFileSync(source, target);
}

function toInt(value) {
  if (Number.isInteger(value)) return value;
  if (typeof value === 'string' && /^-?\d+$/.test(value.trim())) {
    return Number(value);
  }
  return null;
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
