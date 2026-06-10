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
if (!cacheDir || !fs.existsSync(cacheDir)) {
  throw new Error(`Cache directory does not exist: ${cacheDir}`);
}

const rows = fs
  .readdirSync(cacheDir)
  .filter((file) => file.endsWith('.json'))
  .sort()
  .map((file) => auditCacheFile(path.join(cacheDir, file)))
  .filter((row) => {
    if (options.scriptId && row.scriptId !== options.scriptId) return false;
    if (
      options.nameContains &&
      !row.scriptName.toLowerCase().includes(options.nameContains.toLowerCase())
    ) {
      return false;
    }
    return true;
  });

const incomplete = rows
  .filter(
    (row) =>
      row.snapshotFrameCount !== row.fingerprintFrameCount ||
      row.missingFrameIndexes.length > 0 ||
      row.extraFrameIndexes.length > 0,
  )
  .sort(
    (left, right) =>
      right.snapshotGap - left.snapshotGap ||
      right.missingFrameIndexes.length - left.missingFrameIndexes.length ||
      right.fingerprintFrameCount - left.fingerprintFrameCount,
  );

const summary = {
  cache_dir: cacheDir,
  cache_count: rows.length,
  ready_count: rows.filter((row) => row.status === 'ready').length,
  fingerprint_frame_count: sum(rows, 'fingerprintFrameCount'),
  snapshot_frame_count: sum(rows, 'snapshotFrameCount'),
  covered_frame_count: sum(rows, 'coveredFrameCount'),
  missing_frame_count: rows.reduce(
    (count, row) => count + row.missingFrameIndexes.length,
    0,
  ),
  extra_frame_count: rows.reduce(
    (count, row) => count + row.extraFrameIndexes.length,
    0,
  ),
  incomplete_cache_count: incomplete.length,
  incomplete: incomplete.slice(0, options.maxPrint).map(printableRow),
};

console.log(JSON.stringify(summary, null, 2));
if (options.reportPath) {
  fs.mkdirSync(path.dirname(options.reportPath), { recursive: true });
  fs.writeFileSync(
    options.reportPath,
    JSON.stringify(
      {
        ...summary,
        incomplete: incomplete.map(printableRow),
        rows,
      },
      null,
      2,
    ),
    'utf8',
  );
}

function auditCacheFile(filePath) {
  const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const snapshotFrameIndexes = parsedSnapshotFrameIndexes(cache);
  const snapshotFrameSet = new Set(snapshotFrameIndexes);
  const roleRequiredFrameIndexes = parsedRoleRequiredFrameIndexes(cache);
  const coveredFrameSet = aiCoveredFrameSet(cache.aiRoleExtraction ?? {});
  const coveredFrameIndexes = [...coveredFrameSet]
    .filter((frameIndex) => snapshotFrameSet.has(frameIndex))
    .sort((left, right) => left - right);
  const missingFrameIndexes = roleRequiredFrameIndexes.filter(
    (frameIndex) => !coveredFrameSet.has(frameIndex),
  );
  const extraFrameIndexes = [...coveredFrameSet]
    .filter((frameIndex) => !snapshotFrameSet.has(frameIndex))
    .sort((left, right) => left - right);
  const fingerprintFrameCount = sourceFingerprintFrameCount(
    cache.sourceFingerprint,
  );
  const snapshotFrameCount = snapshotFrameIndexes.length;
  return {
    fileName: path.basename(filePath),
    scriptId: stringValue(cache.scriptId),
    scriptName: stringValue(cache.scriptName),
    sourceRootPath: stringValue(cache.sourceRootPath),
    status: stringValue(cache.aiRoleExtraction?.status),
    fingerprintFrameCount,
    snapshotFrameCount,
    roleRequiredFrameCount: roleRequiredFrameIndexes.length,
    nonRoleFrameCount: snapshotFrameIndexes.length - roleRequiredFrameIndexes.length,
    snapshotGap: fingerprintFrameCount - snapshotFrameCount,
    coveredFrameCount: coveredFrameIndexes.length,
    missingFrameIndexes,
    extraFrameIndexes,
    roleCount: Array.isArray(cache.aiRoleExtraction?.roles)
      ? cache.aiRoleExtraction.roles.length
      : 0,
  };
}

function parsedRoleRequiredFrameIndexes(cache) {
  const frames = cache.scriptSnapshot?.frames;
  if (!Array.isArray(frames)) return [];
  return frames
    .filter((frame) => {
      const status = stringValue(frame.parseStatus ?? frame.parse_status);
      if (status.toLowerCase() !== 'parsed') return false;
      const captions = Array.isArray(frame.parsed?.charCaptions)
        ? frame.parsed.charCaptions
        : [];
      return captions.some((caption) => stringValue(caption).trim().length > 0);
    })
    .map((frame) => Number(frame.index))
    .filter((value) => Number.isInteger(value) && value >= 0)
    .sort((left, right) => left - right);
}

function parsedSnapshotFrameIndexes(cache) {
  const frames = cache.scriptSnapshot?.frames;
  if (!Array.isArray(frames)) return [];
  return frames
    .filter((frame) => {
      const status = stringValue(frame.parseStatus ?? frame.parse_status);
      return status.toLowerCase() === 'parsed';
    })
    .map((frame) => Number(frame.index))
    .filter((value) => Number.isInteger(value) && value >= 0)
    .sort((left, right) => left - right);
}

function aiCoveredFrameSet(extraction) {
  const covered = new Set();
  for (const role of Array.isArray(extraction.roles) ? extraction.roles : []) {
    addInts(covered, role.frame_indexes ?? role.frameIndexes);
    for (const appearance of Array.isArray(role.appearances)
      ? role.appearances
      : []) {
      addInts(covered, appearance.frame_indexes ?? appearance.frameIndexes);
    }
    for (const stage of Array.isArray(role.stages) ? role.stages : []) {
      addInts(covered, stage.frame_indexes ?? stage.frameIndexes);
    }
  }
  return covered;
}

function addInts(set, values) {
  if (!Array.isArray(values)) return;
  for (const value of values) {
    const numberValue = Number(value);
    if (Number.isInteger(numberValue) && numberValue >= 0) {
      set.add(numberValue);
    }
  }
}

function sourceFingerprintFrameCount(fingerprint) {
  if (typeof fingerprint !== 'string' || !fingerprint.trim()) return 0;
  return fingerprint
    .split('|')
    .slice(2)
    .filter((part) => /^\d+:/.test(part)).length;
}

function printableRow(row) {
  return {
    file_name: row.fileName,
    script_id: row.scriptId,
    script_name: row.scriptName,
    source_root_path: row.sourceRootPath,
    status: row.status,
    fingerprint_frames: row.fingerprintFrameCount,
    snapshot_frames: row.snapshotFrameCount,
    role_required_frames: row.roleRequiredFrameCount,
    non_role_frames: row.nonRoleFrameCount,
    snapshot_gap: row.snapshotGap,
    covered_frames: row.coveredFrameCount,
    missing_frames: row.missingFrameIndexes.length,
    missing_sample: row.missingFrameIndexes.slice(0, 20),
    extra_frames: row.extraFrameIndexes.length,
    extra_sample: row.extraFrameIndexes.slice(0, 20),
    role_count: row.roleCount,
  };
}

function parseArgs(args) {
  const parsed = {
    cacheDir: undefined,
    scriptId: undefined,
    nameContains: undefined,
    reportPath: undefined,
    maxPrint: 20,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith('--')) continue;
    const equalIndex = arg.indexOf('=');
    const key = equalIndex > 0 ? arg.slice(2, equalIndex) : arg.slice(2);
    const value =
      equalIndex > 0 ? arg.slice(equalIndex + 1) : args[index + 1] ?? '';
    if (equalIndex < 0) index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'script-id') parsed.scriptId = value;
    if (key === 'name-contains') parsed.nameContains = value;
    if (key === 'report') parsed.reportPath = value;
    if (key === 'max-print') parsed.maxPrint = Number(value) || parsed.maxPrint;
  }
  return parsed;
}

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}

function sum(rows, key) {
  return rows.reduce((total, row) => total + row[key], 0);
}
