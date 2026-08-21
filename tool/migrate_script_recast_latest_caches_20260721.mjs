import fs from 'node:fs';
import path from 'node:path';

const options = parseArgs(process.argv.slice(2));
if (!options.cacheDir || !fs.existsSync(options.cacheDir)) {
  throw new Error(`Missing cache dir: ${options.cacheDir ?? ''}`);
}
if (!options.sourceRoot || !fs.existsSync(options.sourceRoot)) {
  throw new Error(`Missing source root: ${options.sourceRoot ?? ''}`);
}

const apply = options.apply;
const cacheDir = path.resolve(options.cacheDir);
const sourceRoot = path.resolve(options.sourceRoot);
const overrideDir = options.overrideDir
  ? path.resolve(options.overrideDir)
  : '';
if (overrideDir && !fs.existsSync(overrideDir)) {
  throw new Error(`Missing override dir: ${overrideDir}`);
}
const workspaceRoot = options.workspaceRoot
  ? path.resolve(options.workspaceRoot)
  : path.dirname(path.dirname(cacheDir));
const assignmentPath = path.join(
  workspaceRoot,
  'script_recast',
  'exhibition_category_assignments.json',
);

const entries = loadScopedCaches(cacheDir, sourceRoot, overrideDir);
const groups = groupByCurrentSourceRoot(entries);
const migrationRows = [];
const idReplacements = new Map();
const outputs = [];
const removals = new Set();

for (const group of groups) {
  const canonicalId = scriptIdForSourceRoot(group[0].cache.sourceRootPath);
  const ranked = [...group].sort(compareCacheCandidates);
  const winner = ranked[ranked.length - 1];
  const merged = canonicalizedCache({
    winner: winner.cache,
    group: ranked.map((entry) => entry.cache),
    canonicalId,
  });
  const targetName = `${canonicalId}.json`;
  const targetPath = path.join(cacheDir, targetName);
  const encoded = `${JSON.stringify(merged, null, 2)}\n`;
  const existingTarget = fs.existsSync(targetPath)
    ? fs.readFileSync(targetPath, 'utf8')
    : null;
  const sourceNames = group.map((entry) => entry.fileName).sort();
  const removeNames = sourceNames.filter((name) => name !== targetName);
  const changed = existingTarget !== encoded || removeNames.length > 0;

  for (const entry of group) {
    if (entry.cache.scriptId !== canonicalId) {
      idReplacements.set(entry.cache.scriptId, canonicalId);
    }
    if (entry.fileName !== targetName) {
      removals.add(entry.fileName);
    }
  }

  outputs.push({
    targetName,
    targetPath,
    encoded,
    changed,
  });
  migrationRows.push({
    script_name: stringValue(merged.scriptName),
    source_root_path: stringValue(merged.sourceRootPath),
    canonical_script_id: canonicalId,
    winner_file: winner.fileName,
    winner_updated_at: stringValue(winner.cache.updatedAt),
    source_files: sourceNames,
    removed_files: removeNames,
    frame_count: arrayValue(merged.scriptSnapshot?.frames).length,
    role_count: arrayValue(merged.aiRoleExtraction?.roles).length,
    role_replacement_group_count:
      arrayValue(merged.mapping?.rolePromptReplacements).length,
    scene_replacement_group_count:
      arrayValue(merged.mapping?.scenePromptReplacements).length,
    finalized: merged.aiRoleExtractionFinalized === true,
    collapsed: merged.aiRoleExtractionDraftCollapsed === true,
    changed,
  });
}

const assignmentPlan = planAssignmentMigration(
  assignmentPath,
  idReplacements,
);
const changedOutputs = outputs.filter((entry) => entry.changed);
const summary = {
  mode: apply ? 'apply' : 'dry-run',
  cache_dir: cacheDir,
  override_dir: overrideDir,
  override_used_count: entries.filter((entry) => entry.overrideUsed).length,
  source_root: sourceRoot,
  workspace_root: workspaceRoot,
  input_cache_count: entries.length,
  output_cache_count: groups.length,
  duplicate_cache_count: entries.length - groups.length,
  duplicate_group_count: groups.filter((group) => group.length > 1).length,
  canonical_id_replacement_count: idReplacements.size,
  changed_output_count: changedOutputs.length,
  removed_cache_count: removals.size,
  completed_cache_count: migrationRows.filter((row) => row.finalized).length,
  incomplete_cache_count: migrationRows.filter((row) => !row.finalized).length,
  assignment_changed: assignmentPlan.changed,
  assignment_replacement_count: assignmentPlan.replacementCount,
  rows: migrationRows,
};

if (!apply) {
  writeOptionalReport(options.report, summary);
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
  process.exit(0);
}

const backupDir = options.backupDir
  ? path.resolve(options.backupDir)
  : path.resolve(
      'build',
      `script-recast-latest-cache-backup-${timestampSlug()}`,
    );
fs.mkdirSync(backupDir, { recursive: true });
const backupCacheDir = path.join(backupDir, 'cache');
fs.mkdirSync(backupCacheDir, { recursive: true });

const affectedNames = new Set([
  ...changedOutputs.map((entry) => entry.targetName),
  ...removals,
]);
for (const fileName of [...affectedNames].sort()) {
  const sourcePath = path.join(cacheDir, fileName);
  if (fs.existsSync(sourcePath)) {
    fs.copyFileSync(sourcePath, path.join(backupCacheDir, fileName));
  }
}
if (assignmentPlan.changed && fs.existsSync(assignmentPath)) {
  fs.copyFileSync(
    assignmentPath,
    path.join(backupDir, 'exhibition_category_assignments.json'),
  );
}

for (const output of changedOutputs) {
  atomicWrite(output.targetPath, output.encoded);
}
for (const fileName of [...removals].sort()) {
  const targetPath = path.join(cacheDir, fileName);
  if (fs.existsSync(targetPath)) {
    fs.unlinkSync(targetPath);
  }
}
if (assignmentPlan.changed) {
  atomicWrite(assignmentPath, assignmentPlan.encoded);
}

for (const indexName of [
  'exhibition_index.json',
  'exhibition_summary_index.json',
]) {
  const indexPath = path.join(workspaceRoot, 'script_recast', indexName);
  if (fs.existsSync(indexPath)) {
    fs.copyFileSync(indexPath, path.join(backupDir, indexName));
    fs.unlinkSync(indexPath);
  }
}

const appliedSummary = {
  ...summary,
  backup_dir: backupDir,
  applied_at: new Date().toISOString(),
};
fs.writeFileSync(
  path.join(backupDir, 'manifest.json'),
  `${JSON.stringify(appliedSummary, null, 2)}\n`,
  'utf8',
);
writeOptionalReport(options.report, appliedSummary);
process.stdout.write(`${JSON.stringify(appliedSummary, null, 2)}\n`);

function loadScopedCaches(directory, allowedRoot, overridesDirectory) {
  const result = [];
  for (const fileName of fs
    .readdirSync(directory)
    .filter((name) => name.endsWith('.json'))
    .sort()) {
    const filePath = path.join(directory, fileName);
    const overridePath = overridesDirectory
      ? path.join(overridesDirectory, fileName)
      : '';
    const inputPath = overridePath && fs.existsSync(overridePath)
      ? overridePath
      : filePath;
    let cache;
    try {
      cache = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
    } catch {
      continue;
    }
    if (!pathIsWithin(stringValue(cache.sourceRootPath), allowedRoot)) {
      continue;
    }
    result.push({
      fileName,
      filePath,
      modifiedAt: fs.statSync(inputPath).mtimeMs,
      overrideUsed: inputPath !== filePath,
      cache,
    });
  }
  return result;
}

function groupByCurrentSourceRoot(entriesToGroup) {
  const groupsByPath = new Map();
  for (const entry of entriesToGroup) {
    const key = normalizeWindowsPath(entry.cache.sourceRootPath);
    const group = groupsByPath.get(key) ?? [];
    group.push(entry);
    groupsByPath.set(key, group);
  }
  return [...groupsByPath.values()].sort((left, right) =>
    stringValue(left[0].cache.sourceRootPath).localeCompare(
      stringValue(right[0].cache.sourceRootPath),
    ),
  );
}

function compareCacheCandidates(left, right) {
  const complete = Number(isCompletedReadyCache(left.cache)) -
    Number(isCompletedReadyCache(right.cache));
  if (complete !== 0) return complete;
  const leftContentFingerprint = stringValue(
    left.cache.sourceContentFingerprint,
  );
  const rightContentFingerprint = stringValue(
    right.cache.sourceContentFingerprint,
  );
  if (
    leftContentFingerprint &&
    leftContentFingerprint === rightContentFingerprint
  ) {
    const canonicalIntegrity =
      canonicalRoleIntegrityScore(left.cache) -
      canonicalRoleIntegrityScore(right.cache);
    if (canonicalIntegrity !== 0) return canonicalIntegrity;
  }
  const updated = timestampValue(left.cache.updatedAt) -
    timestampValue(right.cache.updatedAt);
  if (updated !== 0) return updated;
  const currentId =
    Number(left.cache.scriptId === scriptIdForSourceRoot(left.cache.sourceRootPath)) -
    Number(right.cache.scriptId === scriptIdForSourceRoot(right.cache.sourceRootPath));
  if (currentId !== 0) return currentId;
  if (left.modifiedAt !== right.modifiedAt) {
    return left.modifiedAt - right.modifiedAt;
  }
  return left.fileName.localeCompare(right.fileName);
}

function canonicalRoleIntegrityScore(cache) {
  const roles = arrayValue(cache.aiRoleExtraction?.roles);
  let duplicateCount = 0;
  for (let leftIndex = 0; leftIndex < roles.length; leftIndex += 1) {
    for (
      let rightIndex = leftIndex + 1;
      rightIndex < roles.length;
      rightIndex += 1
    ) {
      if (rolesAreCompatibleCanonicalDuplicates(
        roles[leftIndex],
        roles[rightIndex],
      )) {
        duplicateCount += 1;
      }
    }
  }
  return -duplicateCount;
}

function rolesAreCompatibleCanonicalDuplicates(left, right) {
  const leftName = normalizeCanonicalText(left?.canonical_name);
  const rightName = normalizeCanonicalText(right?.canonical_name);
  if (!leftName || leftName !== rightName) return false;
  const leftFranchise = normalizeCanonicalText(left?.franchise);
  const rightFranchise = normalizeCanonicalText(right?.franchise);
  if (
    leftFranchise &&
    rightFranchise &&
    leftFranchise !== rightFranchise
  ) {
    return false;
  }
  const leftSources = new Set(
    arrayValue(left?.appearances)
      .map((appearance) => sourceAppearanceKey(appearance))
      .filter(Boolean),
  );
  return arrayValue(right?.appearances).some((appearance) =>
    leftSources.has(sourceAppearanceKey(appearance)),
  );
}

function sourceAppearanceKey(appearance) {
  const sourceId = stringValue(appearance?.source_id).trim();
  if (!sourceId) return '';
  return `${stringValue(appearance?.source_kind).trim()}\u001f${sourceId}`;
}

function normalizeCanonicalText(value) {
  return stringValue(value)
    .trim()
    .toLowerCase()
    .replaceAll('_', ' ')
    .replace(/\s+/g, ' ');
}

function isCompletedReadyCache(cache) {
  const extraction = cache.aiRoleExtraction;
  const roles = arrayValue(extraction?.roles);
  if (extraction?.status !== 'ready' || roles.length === 0) return false;
  if (arrayValue(extraction?.attention_items).some((item) => item?.blocking === true)) {
    return false;
  }
  if (roles.some((role) => arrayValue(role?.prompt_terms).length === 0)) {
    return false;
  }
  const roleGroups = arrayValue(cache.mapping?.rolePromptReplacements);
  const mappedRoleIds = new Set(
    roleGroups.map((group) => stringValue(group?.sourceRoleId)).filter(Boolean),
  );
  if (
    roles.some(
      (role) => !mappedRoleIds.has(stringValue(role?.source_role_id)),
    )
  ) {
    return false;
  }
  if (
    arrayValue(extraction?.scene_terms).length > 0 &&
    arrayValue(cache.mapping?.scenePromptReplacements).length === 0
  ) {
    return false;
  }
  return true;
}

function canonicalizedCache({ winner, group, canonicalId }) {
  const cache = structuredClone(winner);
  const categories = normalizedStrings([
    ...group.flatMap((entry) => arrayValue(entry.exhibitionCategoryNames)),
    ...group.flatMap((entry) =>
      arrayValue(entry.scriptSnapshot?.meta?.legacyCategoryNames),
    ),
  ]);
  const sourceRootPath = stringValue(cache.sourceRootPath);
  const completed = isCompletedReadyCache(cache);

  cache.scriptId = canonicalId;
  cache.exhibitionCategoryNames = categories;
  cache.aiRoleExtractionDraftCollapsed = completed;
  cache.aiRoleExtractionFinalized = completed;
  if (cache.mapping && typeof cache.mapping === 'object') {
    cache.mapping.id = `mapping-${canonicalId}`;
    cache.mapping.scriptId = canonicalId;
  }
  if (cache.scriptSnapshot && typeof cache.scriptSnapshot === 'object') {
    cache.scriptSnapshot.id = canonicalId;
    cache.scriptSnapshot.rootPath = sourceRootPath;
    cache.scriptSnapshot.meta = {
      ...(cache.scriptSnapshot.meta ?? {}),
      ...(categories.length > 0 ? { legacyCategoryNames: categories } : {}),
    };
  }
  if (typeof cache.sourceFingerprint === 'string') {
    const separator = cache.sourceFingerprint.indexOf('|');
    cache.sourceFingerprint = separator < 0
      ? canonicalId
      : `${canonicalId}${cache.sourceFingerprint.slice(separator)}`;
  }
  return cache;
}

function planAssignmentMigration(filePath, replacements) {
  if (!fs.existsSync(filePath)) {
    return {
      changed: false,
      replacementCount: 0,
      encoded: '{}\n',
    };
  }
  const assignments = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  let replacementCount = 0;
  const migrated = {};
  for (const [category, values] of Object.entries(assignments)) {
    const next = [];
    const seen = new Set();
    for (const value of arrayValue(values)) {
      const current = stringValue(value);
      const replacement = replacements.get(current) ?? current;
      if (replacement !== current) replacementCount += 1;
      if (replacement && !seen.has(replacement)) {
        seen.add(replacement);
        next.push(replacement);
      }
    }
    migrated[category] = next;
  }
  const encoded = `${JSON.stringify(migrated, null, 2)}\n`;
  return {
    changed: encoded !== fs.readFileSync(filePath, 'utf8'),
    replacementCount,
    encoded,
  };
}

function scriptIdForSourceRoot(sourcePath) {
  const normalized = stringValue(sourcePath).replace(/\\/g, '/');
  const parts = normalized.split('/').filter((part) => part.trim());
  const label = parts.length === 0 ? 'script' : parts[parts.length - 1];
  const slug = asciiSlug(label);
  const hash = stableTextFingerprint(normalized);
  return slug ? `script-${slug}-${hash}` : `script-${hash}`;
}

function stableTextFingerprint(text) {
  let hash = 0xcbf29ce484222325n;
  for (const byte of Buffer.from(text, 'utf8')) {
    hash ^= BigInt(byte);
    hash = (hash * 0x100000001b3n) & 0xffffffffffffffffn;
  }
  return hash.toString(16).padStart(16, '0');
}

function asciiSlug(value) {
  let result = '';
  let previousDash = false;
  for (const character of stringValue(value).toLowerCase()) {
    const rune = character.codePointAt(0);
    const isDigit = rune >= 0x30 && rune <= 0x39;
    const isLetter = rune >= 0x61 && rune <= 0x7a;
    if (isDigit || isLetter) {
      result += character;
      previousDash = false;
    } else if (!previousDash && result) {
      result += '-';
      previousDash = true;
    }
  }
  result = result.replace(/-+$/, '');
  return result.length <= 48
    ? result
    : result.slice(0, 48).replace(/-+$/, '');
}

function pathIsWithin(candidate, root) {
  const candidatePath = path.resolve(stringValue(candidate));
  const rootPath = path.resolve(root);
  const relative = path.relative(rootPath, candidatePath);
  return (
    relative === '' ||
    (!relative.startsWith(`..${path.sep}`) &&
      relative !== '..' &&
      !path.isAbsolute(relative))
  );
}

function normalizeWindowsPath(value) {
  return path.win32
    .normalize(stringValue(value))
    .replace(/[\\/]+$/, '')
    .toLowerCase();
}

function normalizedStrings(values) {
  const result = [];
  const seen = new Set();
  for (const value of values) {
    const trimmed = stringValue(value).trim();
    const key = trimmed.toLowerCase();
    if (trimmed && !seen.has(key)) {
      seen.add(key);
      result.push(trimmed);
    }
  }
  return result;
}

function atomicWrite(targetPath, source) {
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  const tempPath = `${targetPath}.latest-${process.pid}.tmp`;
  fs.writeFileSync(tempPath, source, 'utf8');
  fs.renameSync(tempPath, targetPath);
}

function writeOptionalReport(reportPath, value) {
  if (!reportPath) return;
  const resolved = path.resolve(reportPath);
  fs.mkdirSync(path.dirname(resolved), { recursive: true });
  fs.writeFileSync(resolved, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function timestampValue(value) {
  const parsed = Date.parse(stringValue(value));
  return Number.isFinite(parsed) ? parsed : 0;
}

function timestampSlug() {
  return new Date().toISOString().replace(/[:.]/g, '-');
}

function arrayValue(value) {
  return Array.isArray(value) ? value : [];
}

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}

function parseArgs(args) {
  const parsed = {
    apply: false,
    cacheDir: '',
    sourceRoot: '',
    workspaceRoot: '',
    overrideDir: '',
    backupDir: '',
    report: '',
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--apply') {
      parsed.apply = true;
      continue;
    }
    if (!arg.startsWith('--')) continue;
    const equalIndex = arg.indexOf('=');
    const key = equalIndex > 0 ? arg.slice(2, equalIndex) : arg.slice(2);
    const value = equalIndex > 0
      ? arg.slice(equalIndex + 1)
      : args[index + 1] ?? '';
    if (equalIndex < 0) index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'source-root') parsed.sourceRoot = value;
    if (key === 'workspace-root') parsed.workspaceRoot = value;
    if (key === 'override-dir') parsed.overrideDir = value;
    if (key === 'backup-dir') parsed.backupDir = value;
    if (key === 'report') parsed.report = value;
  }
  return parsed;
}
