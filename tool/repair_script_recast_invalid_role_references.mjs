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
let removedFrameRefs = 0;
let removedSlotRefs = 0;

for (const fileName of fs.readdirSync(cacheDir).filter((file) => file.endsWith('.json')).sort()) {
  const cachePath = path.join(cacheDir, fileName);
  const cache = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
  const frameByIndex = new Map(
    (cache.scriptSnapshot?.frames ?? [])
      .map((frame) => [toInt(frame.index), frame])
      .filter(([index]) => index != null),
  );
  let touched = false;

  const validAnyFrame = (index) => frameByIndex.has(index);
  const validAppearanceFrame = (sourceId, index) => {
    const frame = frameByIndex.get(index);
    if (!frame) {
      removedFrameRefs += 1;
      return false;
    }
    const slot = slotIndexFromSourceId(sourceId);
    if (slot == null) return true;
    const captions = Array.isArray(frame.parsed?.charCaptions)
      ? frame.parsed.charCaptions
      : [];
    if (slot >= captions.length) {
      removedSlotRefs += 1;
      return false;
    }
    return true;
  };

  for (const role of cache.aiRoleExtraction?.roles ?? []) {
    touched = filterFrameList(role, 'frame_indexes', validAnyFrame) || touched;
    for (const appearance of role.appearances ?? []) {
      touched = filterFrameList(
        appearance,
        'frame_indexes',
        (index) => validAppearanceFrame(appearance.source_id, index),
      ) || touched;
    }
    for (const stage of role.stages ?? []) {
      touched = filterFrameList(stage, 'frame_indexes', validAnyFrame) || touched;
    }
  }

  for (const assembly of cache.mapping?.roleAssemblies ?? cache.mapping?.role_assemblies ?? []) {
    for (const appearance of assembly.sourceAppearances ?? assembly.source_appearances ?? []) {
      touched = filterFrameList(
        appearance,
        'frameIndexes',
        (index) => validAppearanceFrame(appearance.sourceId ?? appearance.source_id, index),
      ) || touched;
      touched = filterFrameList(
        appearance,
        'frame_indexes',
        (index) => validAppearanceFrame(appearance.sourceId ?? appearance.source_id, index),
      ) || touched;
    }
    for (const stage of assembly.stages ?? []) {
      touched = filterFrameList(stage, 'frameIndexes', validAnyFrame) || touched;
      touched = filterFrameList(stage, 'frame_indexes', validAnyFrame) || touched;
    }
  }

  if (touched) {
    backupCache(fileName);
    cache.updatedAt = new Date().toISOString();
    fs.writeFileSync(cachePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
    changed.push(fileName);
  }
}

console.log(JSON.stringify({ changed_files: changed, removed_frame_refs: removedFrameRefs, removed_slot_refs: removedSlotRefs }, null, 2));

function filterFrameList(object, key, predicate) {
  if (!Array.isArray(object?.[key])) return false;
  const before = object[key];
  const after = before.filter((index) => Number.isInteger(index) && predicate(index));
  if (after.length === before.length && after.every((value, index) => value === before[index])) {
    return false;
  }
  object[key] = [...new Set(after)].sort((left, right) => left - right);
  return true;
}

function backupCache(fileName) {
  const source = path.join(cacheDir, fileName);
  const target = path.join(backupDir, fileName);
  if (fs.existsSync(target)) return;
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.copyFileSync(source, target);
}

function slotIndexFromSourceId(value) {
  const match = /^slot-(\d+)$/i.exec(String(value ?? '').trim());
  return match ? Number(match[1]) : null;
}

function toInt(value) {
  return Number.isInteger(value) ? value : null;
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
