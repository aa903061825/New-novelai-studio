import fs from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';

class FailClosedError extends Error {}

let args;
let report;
let appliedTransaction;

try {
  args = parseArgs(process.argv.slice(2));
  report = createReport(args);
  appliedTransaction = run(args, report);
  report.status = 'ok';
  writeReport(args.report, report);
  appliedTransaction = null;
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
} catch (error) {
  if (appliedTransaction) rollbackTransaction(appliedTransaction);
  const fallbackReportPath = args?.report ?? reportPathFromRawArgs(process.argv.slice(2));
  report ??= createEmergencyReport(args);
  if (!(error instanceof FailClosedError)) {
    addError(report, 'runtime_error', errorMessage(error));
  }
  report.status = 'failed';
  if (args?.apply) {
    report.files_changed = 0;
    report.files_backed_up = 0;
  }
  if (fallbackReportPath) {
    try {
      writeReport(fallbackReportPath, report);
    } catch (reportError) {
      process.stderr.write(`Could not write report: ${errorMessage(reportError)}\n`);
    }
  }
  process.stderr.write(`Semantic review failed closed: ${errorMessage(error)}\n`);
  process.exitCode = 1;
}

function run(options, currentReport) {
  validatePaths(options, currentReport);
  const corrections = loadCorrections(options.reviews, currentReport);
  const records = loadCacheRecords(options, currentReport);
  failIfErrors(currentReport);

  for (const correction of corrections.roleLabels) {
    applyRoleLabelCorrection(correction, records, currentReport);
  }
  for (const correction of corrections.stageLabels) {
    applyStageLabelCorrection(correction, records, currentReport);
  }
  failIfErrors(currentReport);

  const changedRecords = [];
  for (const record of records) {
    const changed = JSON.stringify(record.working) !== record.originalJson;
    if (record.matched) currentReport.files_matched += 1;
    if (changed) {
      changedRecords.push(record);
      currentReport.files_changed += 1;
    }
    currentReport.rows.push({
      cache_file: record.relativePath,
      script_id: stringValue(record.working.scriptId),
      source_root_path: stringValue(record.working.sourceRootPath),
      matched: record.matched,
      changed,
    });
  }

  if (!options.apply || changedRecords.length === 0) return null;

  const transaction = prepareTransaction(changedRecords, options, currentReport);
  failIfErrors(currentReport);
  return applyTransaction(transaction, currentReport);
}

function validatePaths(options, currentReport) {
  if (!fs.existsSync(options.cacheDir) || !fs.statSync(options.cacheDir).isDirectory()) {
    addError(currentReport, 'missing_cache_dir', `Missing cache directory: ${options.cacheDir}`);
  }
  for (const reviewFile of options.reviews) {
    if (!fs.existsSync(reviewFile) || !fs.statSync(reviewFile).isFile()) {
      addError(currentReport, 'missing_review_file', `Missing review file: ${reviewFile}`);
    }
  }
  if (options.apply && !options.backupDir) {
    addError(currentReport, 'missing_backup_dir', '--backup-dir is required with --apply.');
  }
  if (
    options.apply &&
    options.backupDir &&
    isSameOrInside(options.backupDir, options.cacheDir)
  ) {
    addError(
      currentReport,
      'unsafe_backup_dir',
      'The backup directory must be outside the cache directory.',
    );
  }
}

function loadCorrections(reviewFiles, currentReport) {
  const roleByKey = new Map();
  const stageByKey = new Map();

  for (const reviewFile of reviewFiles) {
    let review;
    try {
      review = JSON.parse(fs.readFileSync(reviewFile, 'utf8'));
    } catch (error) {
      addError(
        currentReport,
        'invalid_review_json',
        `Could not parse review JSON: ${reviewFile}: ${errorMessage(error)}`,
      );
      continue;
    }
    if (!isPlainObject(review)) {
      addError(currentReport, 'invalid_review_schema', `Review must be an object: ${reviewFile}`);
      continue;
    }
    if (!Array.isArray(review.role_labels) || !Array.isArray(review.stage_labels)) {
      addError(
        currentReport,
        'invalid_review_schema',
        `Review must contain role_labels and stage_labels arrays: ${reviewFile}`,
      );
      continue;
    }

    review.role_labels.forEach((item, index) => {
      const correction = parseRoleCorrection(item, reviewFile, index, currentReport);
      if (!correction) return;
      const existing = roleByKey.get(correction.key);
      if (existing && existing.label !== correction.label) {
        addError(
          currentReport,
          'conflicting_correction',
          `Conflicting role labels for ${correction.sourceRootPath} / ${correction.roleId}.`,
        );
        return;
      }
      roleByKey.set(correction.key, existing ?? correction);
    });

    review.stage_labels.forEach((item, index) => {
      const correction = parseStageCorrection(item, reviewFile, index, currentReport);
      if (!correction) return;
      const existing = stageByKey.get(correction.key);
      if (!existing) {
        stageByKey.set(correction.key, correction);
        return;
      }
      const labelsConflict = existing.label !== correction.label;
      const stageIdsConflict =
        existing.stageId && correction.stageId && existing.stageId !== correction.stageId;
      if (labelsConflict || stageIdsConflict) {
        addError(
          currentReport,
          'conflicting_correction',
          `Conflicting stage labels for ${correction.sourceRootPath} / ` +
            `${correction.roleId} / [${correction.frameIndexes.join(', ')}].`,
        );
        return;
      }
      if (!existing.stageId && correction.stageId) existing.stageId = correction.stageId;
    });
  }

  const roleLabels = [...roleByKey.values()];
  const stageLabels = [...stageByKey.values()];
  currentReport.role_corrections_loaded = roleLabels.length;
  currentReport.stage_corrections_loaded = stageLabels.length;
  currentReport.corrections_loaded = roleLabels.length + stageLabels.length;
  if (currentReport.corrections_loaded === 0 && currentReport.errors.length === 0) {
    addError(currentReport, 'empty_review', 'The review files contain no corrections.');
  }
  return { roleLabels, stageLabels };
}

function parseRoleCorrection(item, reviewFile, index, currentReport) {
  const location = `${reviewFile}:role_labels[${index}]`;
  if (!isPlainObject(item)) {
    addError(currentReport, 'invalid_role_correction', `${location} must be an object.`);
    return null;
  }
  const sourceRootPath = requiredString(item.source_root_path);
  const roleId = requiredString(item.role_id);
  const label = validLabel(item.display_name);
  if (!sourceRootPath || !roleId || label === null) {
    addError(
      currentReport,
      'invalid_role_correction',
      `${location} requires non-empty source_root_path, role_id, and single-line display_name.`,
    );
    return null;
  }
  const sourceKey = normalizeSourcePath(sourceRootPath);
  return {
    key: `${sourceKey}\u0000${roleId}`,
    sourceKey,
    sourceRootPath,
    roleId,
    label,
    location,
  };
}

function parseStageCorrection(item, reviewFile, index, currentReport) {
  const location = `${reviewFile}:stage_labels[${index}]`;
  if (!isPlainObject(item)) {
    addError(currentReport, 'invalid_stage_correction', `${location} must be an object.`);
    return null;
  }
  const sourceRootPath = requiredString(item.source_root_path);
  const roleId = requiredString(item.role_id);
  const label = validLabel(item.label);
  const frameIndexes = normalizeFrameIndexes(item.frame_indexes);
  let stageId = '';
  if (Object.hasOwn(item, 'stage_id')) {
    stageId = requiredString(item.stage_id);
    if (!stageId) {
      addError(currentReport, 'invalid_stage_correction', `${location} has an invalid stage_id.`);
      return null;
    }
  }
  if (!sourceRootPath || !roleId || label === null || frameIndexes === null) {
    addError(
      currentReport,
      'invalid_stage_correction',
      `${location} requires source_root_path, role_id, valid frame_indexes, and a single-line label.`,
    );
    return null;
  }
  const sourceKey = normalizeSourcePath(sourceRootPath);
  const signature = frameSignature(frameIndexes);
  return {
    key: `${sourceKey}\u0000${roleId}\u0000${signature}`,
    sourceKey,
    sourceRootPath,
    roleId,
    stageId,
    frameIndexes,
    signature,
    label,
    location,
  };
}

function loadCacheRecords(options, currentReport) {
  if (currentReport.errors.some((error) => error.code === 'missing_cache_dir')) return [];
  const excluded = new Set(
    [...options.reviews, options.report].map((file) => normalizeFsPath(file)),
  );
  const files = listJsonFiles(options.cacheDir).filter(
    (file) => !excluded.has(normalizeFsPath(file)),
  );
  const records = [];
  currentReport.files_scanned = files.length;

  for (const file of files) {
    let originalText;
    let cache;
    try {
      originalText = fs.readFileSync(file, 'utf8');
      cache = JSON.parse(originalText);
    } catch (error) {
      addError(
        currentReport,
        'invalid_cache_json',
        `Could not parse cache JSON: ${file}: ${errorMessage(error)}`,
      );
      continue;
    }
    if (!isPlainObject(cache) || !requiredString(cache.sourceRootPath)) {
      addError(currentReport, 'invalid_cache_schema', `Invalid cache sourceRootPath: ${file}`);
      continue;
    }
    records.push({
      file,
      relativePath: path.relative(options.cacheDir, file),
      sourceKey: normalizeSourcePath(cache.sourceRootPath),
      originalText,
      originalJson: JSON.stringify(cache),
      working: JSON.parse(originalText),
      matched: false,
    });
  }
  currentReport.source_paths_scanned = new Set(records.map((record) => record.sourceKey)).size;
  return records;
}

function applyRoleLabelCorrection(correction, records, currentReport) {
  const sourceRecords = records.filter((record) => record.sourceKey === correction.sourceKey);
  if (sourceRecords.length === 0) {
    addMatchZeroError(currentReport, correction, 'role');
    return;
  }

  const errorCountBefore = currentReport.errors.length;
  let matchedCaches = 0;
  for (const record of sourceRecords) {
    const surfaces = roleSurfaces(record, correction.roleId, currentReport);
    if (!surfaces) continue;
    const { roles, assemblies, replacements } = surfaces;
    if (roles.length === 0 && assemblies.length === 0 && replacements.length === 0) continue;
    if (roles.length !== 1 || assemblies.length !== 1 || replacements.length !== 1) {
      addError(
        currentReport,
        'ambiguous_role_match',
        `Expected one AI role, assembly, and replacement for ${correction.roleId} in ${record.file}; ` +
          `found ${roles.length}, ${assemblies.length}, and ${replacements.length}.`,
      );
      continue;
    }
    if (!warningsAreValid(roles[0], record.file, correction.roleId, currentReport)) continue;

    setLabelField(roles[0], 'display_name', correction.label, currentReport);
    clearWarnings(
      roles[0],
      new Set(['display_name_needs_manual_review']),
      currentReport,
    );
    setLabelField(assemblies[0], 'displayLabel', correction.label, currentReport);
    setLabelField(assemblies[0], 'sourceName', correction.label, currentReport);
    setLabelField(replacements[0], 'displayLabel', correction.label, currentReport);
    record.matched = true;
    matchedCaches += 1;
    currentReport.role_cache_matches += 1;
  }

  if (matchedCaches === 0 && currentReport.errors.length === errorCountBefore) {
    addMatchZeroError(currentReport, correction, 'role');
    return;
  }
  if (matchedCaches > 0 && currentReport.errors.length === errorCountBefore) {
    currentReport.role_corrections_matched += 1;
    currentReport.corrections_matched += 1;
  }
}

function applyStageLabelCorrection(correction, records, currentReport) {
  const sourceRecords = records.filter((record) => record.sourceKey === correction.sourceKey);
  if (sourceRecords.length === 0) {
    addMatchZeroError(currentReport, correction, 'stage');
    return;
  }

  const errorCountBefore = currentReport.errors.length;
  let matchedCaches = 0;
  for (const record of sourceRecords) {
    const surfaces = roleSurfaces(record, correction.roleId, currentReport, {
      replacementsRequired: false,
    });
    if (!surfaces) continue;
    const { roles, assemblies } = surfaces;
    if (roles.length === 0 && assemblies.length === 0) continue;
    if (roles.length !== 1 || assemblies.length !== 1) {
      addError(
        currentReport,
        'ambiguous_role_match',
        `Expected one AI role and assembly for stage correction ${correction.roleId} in ` +
          `${record.file}; found ${roles.length} and ${assemblies.length}.`,
      );
      continue;
    }
    if (!Array.isArray(roles[0].stages) || !Array.isArray(assemblies[0].stages)) {
      addError(
        currentReport,
        'invalid_stage_collection',
        `Missing stage arrays for ${correction.roleId} in ${record.file}.`,
      );
      continue;
    }

    const aiStages = roles[0].stages.filter(
      (stage) => signatureForCacheFrames(stage?.frame_indexes) === correction.signature,
    );
    const mappingStages = assemblies[0].stages.filter(
      (stage) => signatureForCacheFrames(stage?.frameIndexes) === correction.signature,
    );
    if (aiStages.length !== 1 || mappingStages.length !== 1) {
      addError(
        currentReport,
        aiStages.length > 1 || mappingStages.length > 1
          ? 'ambiguous_stage_match'
          : 'frame_signature_mismatch',
        `Expected one AI and mapping stage with frames [${correction.frameIndexes.join(', ')}] ` +
          `for ${correction.roleId} in ${record.file}; found ${aiStages.length} and ` +
          `${mappingStages.length}.`,
      );
      continue;
    }

    const aiStageId = requiredString(aiStages[0].stage_id);
    const mappingStageId = requiredString(mappingStages[0].id);
    if (!aiStageId || !mappingStageId || aiStageId !== mappingStageId) {
      addError(
        currentReport,
        'stage_id_mismatch',
        `AI and mapping stage IDs disagree for ${correction.roleId} in ${record.file}.`,
      );
      continue;
    }
    if (
      correction.stageId &&
      (correction.stageId !== aiStageId || correction.stageId !== mappingStageId)
    ) {
      addError(
        currentReport,
        'stage_id_mismatch',
        `Expected stage_id ${correction.stageId}, found ${aiStageId} in ${record.file}.`,
      );
      continue;
    }
    if (!warningsAreValid(aiStages[0], record.file, aiStageId, currentReport)) continue;

    setLabelField(aiStages[0], 'label', correction.label, currentReport);
    clearWarnings(
      aiStages[0],
      new Set(['label_needs_manual_review', 'stage_label_needs_manual_review']),
      currentReport,
    );
    setLabelField(mappingStages[0], 'label', correction.label, currentReport);
    record.matched = true;
    matchedCaches += 1;
    currentReport.stage_cache_matches += 1;
  }

  if (matchedCaches === 0 && currentReport.errors.length === errorCountBefore) {
    addMatchZeroError(currentReport, correction, 'stage');
    return;
  }
  if (matchedCaches > 0 && currentReport.errors.length === errorCountBefore) {
    currentReport.stage_corrections_matched += 1;
    currentReport.corrections_matched += 1;
  }
}

function roleSurfaces(record, roleId, currentReport, { replacementsRequired = true } = {}) {
  const extraction = record.working.aiRoleExtraction;
  const mapping = record.working.mapping;
  if (!isPlainObject(extraction) || !Array.isArray(extraction.roles)) {
    addError(currentReport, 'invalid_role_collection', `Missing AI roles array: ${record.file}`);
    return null;
  }
  if (
    !isPlainObject(mapping) ||
    !Array.isArray(mapping.roleAssemblies) ||
    (replacementsRequired && !Array.isArray(mapping.rolePromptReplacements))
  ) {
    addError(currentReport, 'invalid_mapping_collection', `Missing mapping role arrays: ${record.file}`);
    return null;
  }
  return {
    roles: extraction.roles.filter((role) => role?.source_role_id === roleId),
    assemblies: mapping.roleAssemblies.filter(
      (assembly) => assembly?.sourceRoleId === roleId,
    ),
    replacements: Array.isArray(mapping.rolePromptReplacements)
      ? mapping.rolePromptReplacements.filter(
          (replacement) => replacement?.sourceRoleId === roleId,
        )
      : [],
  };
}

function prepareTransaction(changedRecords, options, currentReport) {
  const token = `${process.pid}-${randomUUID()}`;
  const items = changedRecords.map((record) => ({
    record,
    backupFile: path.join(options.backupDir, record.relativePath),
    tempFile: `${record.file}.semantic-review-${token}.tmp`,
  }));

  for (const item of items) {
    if (fs.existsSync(item.backupFile)) {
      addError(
        currentReport,
        'backup_exists',
        `Refusing to overwrite existing backup: ${item.backupFile}`,
      );
    }
    if (fs.existsSync(item.tempFile)) {
      addError(currentReport, 'temp_exists', `Refusing to overwrite temp file: ${item.tempFile}`);
    }
  }
  return { items, backupRoot: options.backupDir };
}

function applyTransaction(transaction, currentReport) {
  transaction.createdBackups = [];
  const createdTemps = [];
  transaction.backupRootExisted = fs.existsSync(transaction.backupRoot);
  try {
    for (const item of transaction.items) {
      fs.writeFileSync(
        item.tempFile,
        `${JSON.stringify(item.record.working, null, 2)}\n`,
        { encoding: 'utf8', flag: 'wx' },
      );
      createdTemps.push(item.tempFile);
    }
    for (const item of transaction.items) {
      fs.mkdirSync(path.dirname(item.backupFile), { recursive: true });
      fs.copyFileSync(item.record.file, item.backupFile, fs.constants.COPYFILE_EXCL);
      transaction.createdBackups.push(item.backupFile);
    }
    for (const item of transaction.items) {
      fs.copyFileSync(item.tempFile, item.record.file);
    }
    currentReport.files_backed_up = transaction.createdBackups.length;
    return transaction;
  } catch (error) {
    rollbackTransaction(transaction);
    currentReport.files_backed_up = 0;
    throw error;
  } finally {
    for (const tempFile of createdTemps) removeFileQuietly(tempFile);
  }
}

function rollbackTransaction(transaction) {
  for (const item of transaction.items) {
    if (!fs.existsSync(item.backupFile)) continue;
    try {
      fs.copyFileSync(item.backupFile, item.record.file);
    } catch {
      // Keep attempting every rollback so one bad file does not block the rest.
    }
  }
  for (const backupFile of [...(transaction.createdBackups ?? [])].reverse()) {
    removeFileQuietly(backupFile);
  }
  if (!transaction.backupRootExisted) removeEmptyTree(transaction.backupRoot);
}

function createReport(options) {
  return {
    api_used: false,
    status: 'running',
    apply: options.apply,
    cache_dir: options.cacheDir,
    review_files: [...options.reviews],
    report_path: options.report,
    backup_dir: options.apply ? options.backupDir : '',
    files_scanned: 0,
    source_paths_scanned: 0,
    files_matched: 0,
    files_changed: 0,
    files_backed_up: 0,
    corrections_loaded: 0,
    corrections_matched: 0,
    role_corrections_loaded: 0,
    role_corrections_matched: 0,
    stage_corrections_loaded: 0,
    stage_corrections_matched: 0,
    role_cache_matches: 0,
    stage_cache_matches: 0,
    label_fields_updated: 0,
    warnings_removed: 0,
    errors: [],
    rows: [],
  };
}

function createEmergencyReport(options) {
  return {
    api_used: false,
    status: 'failed',
    apply: options?.apply ?? false,
    files_scanned: 0,
    files_matched: 0,
    files_changed: 0,
    files_backed_up: 0,
    corrections_loaded: 0,
    corrections_matched: 0,
    errors: [],
    rows: [],
  };
}

function parseArgs(values) {
  const parsed = {
    cacheDir: '',
    reviews: [],
    report: '',
    backupDir: '',
    apply: false,
  };
  const valueKeys = new Set(['cache-dir', 'review', 'report', 'backup-dir']);
  for (let index = 0; index < values.length; index += 1) {
    const arg = values[index];
    if (arg === '--apply') {
      parsed.apply = true;
      continue;
    }
    if (!arg.startsWith('--')) throw new Error(`Unexpected argument: ${arg}`);
    const equalAt = arg.indexOf('=');
    const key = arg.slice(2, equalAt >= 0 ? equalAt : undefined);
    if (!valueKeys.has(key)) throw new Error(`Unknown argument: --${key}`);
    const value = equalAt >= 0 ? arg.slice(equalAt + 1) : values[++index];
    if (!value || value.startsWith('--')) throw new Error(`Missing value for --${key}`);
    if (key === 'cache-dir') parsed.cacheDir = path.resolve(value);
    if (key === 'review') parsed.reviews.push(path.resolve(value));
    if (key === 'report') parsed.report = path.resolve(value);
    if (key === 'backup-dir') parsed.backupDir = path.resolve(value);
  }
  if (!parsed.cacheDir) throw new Error('--cache-dir is required.');
  if (parsed.reviews.length === 0) throw new Error('At least one --review is required.');
  parsed.report ||= path.resolve(
    'build',
    `script_recast_semantic_review_report_${timestampForPath()}.json`,
  );
  return parsed;
}

function setLabelField(object, key, value, currentReport) {
  if (object[key] !== value) currentReport.label_fields_updated += 1;
  object[key] = value;
}

function warningsAreValid(object, file, itemId, currentReport) {
  if (object.warnings == null || Array.isArray(object.warnings)) return true;
  addError(
    currentReport,
    'invalid_warnings',
    `Warnings must be an array for ${itemId} in ${file}.`,
  );
  return false;
}

function clearWarnings(object, removable, currentReport) {
  if (!Array.isArray(object.warnings)) return;
  const before = object.warnings.length;
  object.warnings = object.warnings.filter((warning) => !removable.has(warning));
  currentReport.warnings_removed += before - object.warnings.length;
}

function addMatchZeroError(currentReport, correction, type) {
  const suffix =
    type === 'stage' ? ` / [${correction.frameIndexes.join(', ')}]` : '';
  addError(
    currentReport,
    'match_zero',
    `No ${type} match for ${correction.sourceRootPath} / ${correction.roleId}${suffix}.`,
  );
}

function addError(currentReport, code, message) {
  currentReport.errors.push({ code, message });
}

function failIfErrors(currentReport) {
  if (currentReport.errors.length > 0) {
    throw new FailClosedError(`${currentReport.errors.length} validation error(s).`);
  }
}

function validLabel(value) {
  if (typeof value !== 'string' || /[\r\n\u2028\u2029]/.test(value)) return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function requiredString(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function normalizeFrameIndexes(value) {
  if (!Array.isArray(value) || value.length === 0) return null;
  if (!value.every((item) => Number.isSafeInteger(item) && item >= 0)) return null;
  const unique = new Set(value);
  if (unique.size !== value.length) return null;
  return [...value].sort((left, right) => left - right);
}

function signatureForCacheFrames(value) {
  const normalized = normalizeFrameIndexes(value);
  return normalized ? frameSignature(normalized) : null;
}

function frameSignature(value) {
  return value.join(',');
}

function normalizeSourcePath(value) {
  let normalized = String(value ?? '').trim().replaceAll('\\', '/');
  normalized = normalized.replace(/\/{2,}/g, '/');
  if (!/^[a-z]:\/$/i.test(normalized)) normalized = normalized.replace(/\/+$/, '');
  return normalized.toLowerCase();
}

function normalizeFsPath(value) {
  return path.resolve(value).replaceAll('\\', '/').toLowerCase();
}

function listJsonFiles(root) {
  const result = [];
  const visit = (directory) => {
    const entries = fs.readdirSync(directory, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(directory, entry.name);
      if (entry.isDirectory()) visit(fullPath);
      if (entry.isFile() && entry.name.toLowerCase().endsWith('.json')) result.push(fullPath);
    }
  };
  visit(root);
  return result.sort((left, right) => left.localeCompare(right));
}

function isSameOrInside(candidate, parent) {
  const relative = path.relative(path.resolve(parent), path.resolve(candidate));
  return relative === '' || (!relative.startsWith('..') && !path.isAbsolute(relative));
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function writeReport(file, currentReport) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(currentReport, null, 2)}\n`, 'utf8');
}

function reportPathFromRawArgs(values) {
  for (let index = 0; index < values.length; index += 1) {
    if (values[index] === '--report' && values[index + 1]) return path.resolve(values[index + 1]);
    if (values[index].startsWith('--report=')) {
      return path.resolve(values[index].slice('--report='.length));
    }
  }
  return '';
}

function removeFileQuietly(file) {
  try {
    if (fs.existsSync(file)) fs.unlinkSync(file);
  } catch {
    // Best effort cleanup only.
  }
}

function removeEmptyTree(root) {
  if (!fs.existsSync(root)) return;
  const entries = fs.readdirSync(root, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.isDirectory()) removeEmptyTree(path.join(root, entry.name));
  }
  try {
    if (fs.readdirSync(root).length === 0) fs.rmdirSync(root);
  } catch {
    // Best effort cleanup only.
  }
}

function timestampForPath() {
  return new Date().toISOString().replace(/[-:T.Z]/g, '').slice(0, 14);
}

function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}
