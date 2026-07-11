import fs from 'node:fs';
import path from 'node:path';

const options = parseArgs(process.argv.slice(2));
if (!options.cacheDir || !fs.existsSync(options.cacheDir)) {
  throw new Error(`Missing cache dir: ${options.cacheDir ?? ''}`);
}
if (!options.sourceRoot || !fs.existsSync(options.sourceRoot)) {
  throw new Error(`Missing source root: ${options.sourceRoot ?? ''}`);
}

const outputDir = options.outputDir ?? options.cacheDir;
fs.mkdirSync(outputDir, { recursive: true });

const sourceDirs = walkDirectories(options.sourceRoot).filter(hasFrameEvidence);
const sourceDirsByName = new Map();
for (const directory of sourceDirs) {
  const key = normalizeName(path.basename(directory));
  const current = sourceDirsByName.get(key) ?? [];
  current.push(directory);
  sourceDirsByName.set(key, current);
}

const rows = [];
for (const file of fs.readdirSync(options.cacheDir).filter((name) => name.endsWith('.json')).sort()) {
  const sourcePath = path.join(options.cacheDir, file);
  const outputPath = path.join(outputDir, file);
  const cache = JSON.parse(fs.readFileSync(sourcePath, 'utf8'));
  const oldRoot = stringValue(cache.sourceRootPath);
  if (!oldRoot || fs.existsSync(oldRoot)) {
    if (sourcePath !== outputPath) fs.copyFileSync(sourcePath, outputPath);
    rows.push({
      file_name: file,
      script_name: stringValue(cache.scriptName),
      old_source_root_path: oldRoot,
      new_source_root_path: oldRoot,
      status: 'unchanged',
    });
    continue;
  }

  const scriptName = stringValue(cache.scriptName);
  const candidates = sourceDirsByName.get(normalizeName(scriptName)) ?? [];
  const withImages = candidates.filter(hasImages);
  const chosen =
    withImages.length === 1
      ? withImages[0]
      : candidates.length === 1
        ? candidates[0]
        : '';

  if (!chosen) {
    if (sourcePath !== outputPath) fs.copyFileSync(sourcePath, outputPath);
    rows.push({
      file_name: file,
      script_name: scriptName,
      old_source_root_path: oldRoot,
      candidates,
      status: candidates.length === 0 ? 'unresolved_no_match' : 'unresolved_multiple_matches',
    });
    continue;
  }

  cache.sourceRootPath = chosen;
  if (typeof cache.sourceFingerprint === 'string') {
    cache.sourceFingerprint = replacePathInFingerprint(
      cache.sourceFingerprint,
      oldRoot,
      chosen,
    );
  }
  const snapshotFrameUpdates = rebaseScriptSnapshotPaths(cache, chosen);
  fs.writeFileSync(outputPath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
  rows.push({
    file_name: file,
    script_name: scriptName,
    old_source_root_path: oldRoot,
    new_source_root_path: chosen,
    snapshot_frame_updates: snapshotFrameUpdates,
    status: 'updated',
  });
}

const summary = {
  cache_dir: options.cacheDir,
  output_dir: outputDir,
  source_root: options.sourceRoot,
  cache_count: rows.length,
  updated_count: rows.filter((row) => row.status === 'updated').length,
  unresolved_count: rows.filter((row) => row.status.startsWith('unresolved')).length,
  unresolved: rows.filter((row) => row.status.startsWith('unresolved')),
};

console.log(JSON.stringify(summary, null, 2));
if (options.report) {
  fs.mkdirSync(path.dirname(options.report), { recursive: true });
  fs.writeFileSync(options.report, JSON.stringify({ ...summary, rows }, null, 2), 'utf8');
}

function walkDirectories(root) {
  const result = [];
  const stack = [root];
  while (stack.length > 0) {
    const current = stack.pop();
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const next = path.join(current, entry.name);
      result.push(next);
      stack.push(next);
    }
  }
  return result;
}

function hasFrameEvidence(directory) {
  try {
    return fs.readdirSync(directory).some((file) => /\.(?:json|png)$/i.test(file));
  } catch {
    return false;
  }
}

function hasImages(directory) {
  try {
    return fs.readdirSync(directory).some((file) => /\.png$/i.test(file));
  } catch {
    return false;
  }
}

function rebaseScriptSnapshotPaths(cache, sourceRoot) {
  const snapshot = cache.scriptSnapshot;
  if (!snapshot || typeof snapshot !== 'object') return 0;
  snapshot.rootPath = sourceRoot;
  if (!Array.isArray(snapshot.frames)) return 0;

  const filesByLeaf = filesByNormalizedLeaf(sourceRoot);
  let updated = 0;
  for (const frame of snapshot.frames) {
    if (!frame || typeof frame !== 'object') continue;
    const sourceLeaf = firstNonEmpty([
      pathLeaf(stringValue(frame.sourcePath)),
      stringValue(frame.fileName),
    ]);
    const sourceFile = fileForLeaf(filesByLeaf, sourceLeaf);
    const nextSourcePath = sourceFile ?? joinPath(sourceRoot, sourceLeaf);

    const imageLeaf = pathLeaf(stringValue(frame.sourceImagePath));
    const imageFile = fileForLeaf(filesByLeaf, imageLeaf);
    const sourceImageFile = isImagePath(sourceFile ?? '') ? sourceFile : '';
    const pairedImageFile = sourceLeaf ? pairedImageForSource(filesByLeaf, sourceLeaf) : '';
    const nextSourceImagePath = firstNonEmpty([
      imageFile,
      sourceImageFile,
      pairedImageFile,
    ]);

    if (nextSourcePath && frame.sourcePath !== nextSourcePath) {
      frame.sourcePath = nextSourcePath;
      updated += 1;
    }
    if (frame.sourceImagePath !== nextSourceImagePath) {
      frame.sourceImagePath = nextSourceImagePath;
      updated += 1;
    }
  }
  return updated;
}

function filesByNormalizedLeaf(sourceRoot) {
  const result = new Map();
  for (const file of walkFiles(sourceRoot)) {
    const key = normalizeName(path.basename(file));
    if (!key || result.has(key)) continue;
    result.set(key, file);
  }
  return result;
}

function walkFiles(root) {
  const result = [];
  const stack = [root];
  while (stack.length > 0) {
    const current = stack.pop();
    let entries = [];
    try {
      entries = fs.readdirSync(current, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      const next = path.join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(next);
      } else if (entry.isFile()) {
        result.push(next);
      }
    }
  }
  return result.sort((left, right) => {
    const byDepth = pathDepth(left) - pathDepth(right);
    return byDepth === 0 ? left.localeCompare(right) : byDepth;
  });
}

function fileForLeaf(filesByLeaf, leaf) {
  const key = normalizeName(leaf);
  return key ? filesByLeaf.get(key) ?? '' : '';
}

function pairedImageForSource(filesByLeaf, sourceLeaf) {
  const stem = pathStem(sourceLeaf);
  if (!stem) return '';
  for (const extension of ['.png', '.jpg', '.jpeg', '.webp']) {
    const match = fileForLeaf(filesByLeaf, `${stem}${extension}`);
    if (match) return match;
  }
  return '';
}

function isImagePath(value) {
  return /\.(?:png|jpe?g|webp)$/i.test(stringValue(value));
}

function pathLeaf(value) {
  const normalized = stringValue(value).trim().replace(/\\/g, '/');
  if (!normalized) return '';
  const parts = normalized.split('/').filter(Boolean);
  return parts.length === 0 ? '' : parts[parts.length - 1];
}

function pathStem(value) {
  const leaf = pathLeaf(value);
  const extension = path.extname(leaf);
  return extension ? leaf.slice(0, -extension.length) : leaf;
}

function joinPath(root, leaf) {
  const trimmed = stringValue(leaf).trim();
  return trimmed ? path.join(root, trimmed) : '';
}

function firstNonEmpty(values) {
  for (const value of values) {
    const trimmed = stringValue(value).trim();
    if (trimmed) return trimmed;
  }
  return '';
}

function pathDepth(value) {
  return stringValue(value)
    .replace(/\\/g, '/')
    .split('/')
    .filter(Boolean).length;
}

function replacePathInFingerprint(fingerprint, oldRoot, newRoot) {
  const oldNormalized = normalizeFingerprintPath(oldRoot);
  const newNormalized = normalizeFingerprintPath(newRoot);
  return fingerprint.split(oldNormalized).join(newNormalized);
}

function normalizeFingerprintPath(value) {
  return stringValue(value).replace(/\\/g, '/').toLowerCase();
}

function normalizeName(value) {
  return stringValue(value).normalize('NFC').trim().toLowerCase();
}

function parseArgs(args) {
  const parsed = {
    cacheDir: '',
    outputDir: '',
    sourceRoot: '',
    report: '',
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith('--')) continue;
    const equalIndex = arg.indexOf('=');
    const key = equalIndex > 0 ? arg.slice(2, equalIndex) : arg.slice(2);
    const value = equalIndex > 0 ? arg.slice(equalIndex + 1) : args[index + 1] ?? '';
    if (equalIndex < 0) index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'output-dir') parsed.outputDir = value;
    if (key === 'source-root') parsed.sourceRoot = value;
    if (key === 'report') parsed.report = value;
  }
  return parsed;
}

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}
