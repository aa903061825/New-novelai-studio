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

const defaultClassificationCache =
  'E:/NAI\u7684\u811a\u672c\u7fa4/tag_classification_cache.json';
const defaultSourceRoot =
  'E:/NAI\u7684\u811a\u672c\u7fa4/\u4f5c\u54c1\u96c6';

const hardDisallowed = {
  identity: new Set([
    'artist',
    'style',
    'quality',
    'scene',
    'action',
    'camera',
    'clothing',
    'upperBody',
    'lowerBody',
    'upperClothing',
    'lowerClothing',
  ]),
  body: new Set([
    'artist',
    'quality',
    'scene',
    'action',
    'camera',
  ]),
  clothing: new Set([
    'artist',
    'quality',
    'scene',
    'action',
    'camera',
  ]),
};

const options = parseArgs(process.argv.slice(2));
const cacheDir = options.cacheDir ?? defaultCacheDir;
const classificationCachePath =
  options.classificationCache ?? defaultClassificationCache;
const sourceRoot = normalizePath(options.sourceRoot ?? defaultSourceRoot);

if (!fs.existsSync(cacheDir)) {
  throw new Error(`Cache directory does not exist: ${cacheDir}`);
}

const classificationCache = loadClassificationCache(classificationCachePath);
const files = fs
  .readdirSync(cacheDir)
  .filter((file) => file.endsWith('.json'))
  .sort()
  .slice(options.from, options.to);

const rows = files.map((file) =>
  auditCache(path.join(cacheDir, file), classificationCache, sourceRoot),
);
const issueRows = rows.filter((row) => row.issue_count > 0);
const summary = {
  cache_dir: cacheDir,
  source_root: sourceRoot,
  classification_cache: classificationCachePath,
  from: options.from,
  to: options.to ?? files.length,
  cache_count: rows.length,
  ready_count: rows.filter((row) => row.status === 'ready').length,
  total_frames: sum(rows, 'frame_count'),
  parsed_frames: sum(rows, 'parsed_frame_count'),
  png_metadata_missing_frames: sum(rows, 'png_metadata_missing_frame_count'),
  source_frame_mismatch_count: rows.filter(
    (row) => row.source_frame_mismatch,
  ).length,
  slot_coverage_issue_count: sum(rows, 'slot_coverage_issue_count'),
  role_identity_issue_count: sum(rows, 'role_identity_issue_count'),
  role_frame_reference_issue_count: sum(
    rows,
    'role_frame_reference_issue_count',
  ),
  classification_issue_count: sum(rows, 'classification_issue_count'),
  issue_cache_count: issueRows.length,
  issue_samples: issueRows.slice(0, options.maxPrint).map(printableRow),
};

console.log(JSON.stringify(summary, null, 2));
if (options.reportPath) {
  fs.mkdirSync(path.dirname(options.reportPath), { recursive: true });
  fs.writeFileSync(
    options.reportPath,
    JSON.stringify(
      {
        ...summary,
        rows,
      },
      null,
      2,
    ),
    'utf8',
  );
}

function auditCache(filePath, classificationCache, sourceRoot) {
  const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const frames = Array.isArray(cache.scriptSnapshot?.frames)
    ? cache.scriptSnapshot.frames
    : [];
  const parsedFrames = frames.filter((frame) => isParsedFrame(frame));
  const frameIndexes = frames
    .map((frame) => toInt(frame.index))
    .filter((index) => index != null)
    .sort((left, right) => left - right);
  const expectedIndexes = Array.from(
    { length: frameIndexes.length },
    (_, index) => index + 1,
  );
  const fingerprintFrameCount = sourceFingerprintFrameCount(
    cache.sourceFingerprint,
  );
  const sourceRootPath = stringValue(cache.sourceRootPath);
  const sourceRootNormalized = normalizePath(sourceRootPath);
  const sourceWithinRoot = sourceRootNormalized.startsWith(sourceRoot);
  const sourceExists = sourceRootPath.trim().length > 0
    ? fs.existsSync(sourceRootPath)
    : false;

  const slotCoverageIssues = slotCoverageAudit(cache, parsedFrames);
  const roleIdentityIssues = roleIdentityAudit(
    cache,
    parsedFrames,
    classificationCache,
  );
  const roleFrameReferenceIssues = roleFrameReferenceAudit(cache, frames);
  const classificationIssues = classificationAudit(cache, classificationCache);
  const pngMetadataMissingFrameCount = frames.filter(
    (frame) =>
      frame?.parsed?.sourcePayload?.source_kind ===
      'png_metadata_missing_frame',
  ).length;
  const sourceFrameMismatch =
    fingerprintFrameCount !== frames.length ||
    !sameIntList(frameIndexes, expectedIndexes) ||
    !sourceExists ||
    !sourceWithinRoot;
  const issueCount =
    (sourceFrameMismatch ? 1 : 0) +
    slotCoverageIssues.length +
    roleIdentityIssues.length +
    roleFrameReferenceIssues.length +
    classificationIssues.length;

  return {
    file_name: path.basename(filePath),
    script_id: stringValue(cache.scriptId),
    script_name: stringValue(cache.scriptName),
    source_root_path: sourceRootPath,
    source_exists: sourceExists,
    source_within_expected_root: sourceWithinRoot,
    status: stringValue(cache.aiRoleExtraction?.status),
    fingerprint_frame_count: fingerprintFrameCount,
    frame_count: frames.length,
    parsed_frame_count: parsedFrames.length,
    png_metadata_missing_frame_count: pngMetadataMissingFrameCount,
    frame_indexes_sequential: sameIntList(frameIndexes, expectedIndexes),
    source_frame_mismatch: sourceFrameMismatch,
    role_count: Array.isArray(cache.aiRoleExtraction?.roles)
      ? cache.aiRoleExtraction.roles.length
      : 0,
    slot_coverage_issue_count: slotCoverageIssues.length,
    role_identity_issue_count: roleIdentityIssues.length,
    role_frame_reference_issue_count: roleFrameReferenceIssues.length,
    classification_issue_count: classificationIssues.length,
    issue_count: issueCount,
    slot_coverage_issues: slotCoverageIssues,
    role_identity_issues: roleIdentityIssues,
    role_frame_reference_issues: roleFrameReferenceIssues,
    classification_issues: classificationIssues,
  };
}

function roleFrameReferenceAudit(cache, frames) {
  const frameByIndex = new Map(
    frames
      .map((frame) => [toInt(frame.index), frame])
      .filter(([index]) => index != null),
  );
  const issues = [];
  for (const role of roles(cache)) {
    const roleId = stringValue(role.source_role_id);
    for (const frameIndex of intList(role.frame_indexes)) {
      if (!frameByIndex.has(frameIndex)) {
        issues.push({
          section: 'aiRoleExtraction',
          role_id: roleId,
          display_name: stringValue(role.display_name),
          field: 'frame_indexes',
          frame_index: frameIndex,
          issue: 'role_frame_index_missing_from_snapshot',
        });
      }
    }
    for (const appearance of appearances(role)) {
      for (const frameIndex of intList(appearance.frame_indexes)) {
        const frame = frameByIndex.get(frameIndex);
        if (!frame) {
          issues.push({
            section: 'aiRoleExtraction',
            role_id: roleId,
            display_name: stringValue(role.display_name),
            field: 'appearances.frame_indexes',
            source_id: stringValue(appearance.source_id),
            frame_index: frameIndex,
            issue: 'appearance_frame_index_missing_from_snapshot',
          });
          continue;
        }
        const slot = slotIndexFromSourceId(appearance.source_id);
        if (slot == null) continue;
        const captions = Array.isArray(frame.parsed?.charCaptions)
          ? frame.parsed.charCaptions
          : [];
        if (slot >= captions.length) {
          issues.push({
            section: 'aiRoleExtraction',
            role_id: roleId,
            display_name: stringValue(role.display_name),
            field: 'appearances.source_id',
            source_id: stringValue(appearance.source_id),
            frame_index: frameIndex,
            frame_slot_count: captions.length,
            issue: 'appearance_slot_missing_from_frame',
          });
        }
      }
    }
  }
  return issues;
}

function slotCoverageAudit(cache, parsedFrames) {
  const slotFrameToRoles = new Map();
  for (const role of roles(cache)) {
    for (const appearance of appearances(role)) {
      const slot = slotIndexFromSourceId(appearance.source_id);
      if (slot == null) continue;
      for (const frameIndex of intList(appearance.frame_indexes)) {
        const key = `${frameIndex}:${slot}`;
        const rolesForSlot = slotFrameToRoles.get(key) ?? [];
        rolesForSlot.push(stringValue(role.source_role_id));
        slotFrameToRoles.set(key, rolesForSlot);
      }
    }
  }

  const issues = [];
  for (const frame of parsedFrames) {
    const frameIndex = toInt(frame.index);
    if (frameIndex == null) continue;
    const captions = Array.isArray(frame.parsed?.charCaptions)
      ? frame.parsed.charCaptions
      : [];
    captions.forEach((caption, slot) => {
      if (!stringValue(caption).trim()) return;
      const rolesForSlot = slotFrameToRoles.get(`${frameIndex}:${slot}`) ?? [];
      if (rolesForSlot.length !== 1) {
        issues.push({
          frame_index: frameIndex,
          slot,
          file_name: stringValue(frame.fileName),
          role_refs: rolesForSlot,
          issue:
            rolesForSlot.length === 0
              ? 'missing_slot_role_coverage'
              : 'duplicate_slot_role_coverage',
        });
      }
    });
  }
  return issues;
}

function roleIdentityAudit(cache, parsedFrames, classificationCache) {
  const expectedBySlot = new Map();
  const captionTextBySlot = new Map();
  for (const frame of parsedFrames) {
    const frameIndex = toInt(frame.index);
    if (frameIndex == null) continue;
    const captions = Array.isArray(frame.parsed?.charCaptions)
      ? frame.parsed.charCaptions
      : [];
    captions.forEach((caption, slot) => {
      const key = `${frameIndex}:${slot}`;
      captionTextBySlot.set(key, normalizedTagKey(caption));
      const terms = classifiedTerms(caption, classificationCache, ['character'])
        .filter(isRoleIdentityTerm);
      if (terms.length === 0) return;
      expectedBySlot.set(key, terms);
    });
  }

  const issues = [];
  for (const role of roles(cache)) {
    const roleId = stringValue(role.source_role_id);
    if (/^role-source-slot-\d+$/i.test(roleId)) continue;

    const expectedTerms = new Set();
    const sourceCaptionTexts = [];
    for (const appearance of appearances(role)) {
      const slot = slotIndexFromSourceId(appearance.source_id);
      if (slot == null) continue;
      for (const frameIndex of intList(appearance.frame_indexes)) {
        const key = `${frameIndex}:${slot}`;
        const sourceText = captionTextBySlot.get(key);
        if (sourceText) sourceCaptionTexts.push(sourceText);
        for (const term of expectedBySlot.get(`${frameIndex}:${slot}`) ?? []) {
          expectedTerms.add(term);
        }
      }
    }
    if (roleNameAppearsInSource(role, sourceCaptionTexts)) continue;
    if (expectedTerms.size === 0) continue;
    const roleText = normalizedTagKey(
      [
        role.display_name,
        role.canonical_name,
        ...(Array.isArray(role.raw_identity_tags)
          ? role.raw_identity_tags
          : []),
        ...(Array.isArray(role.evidence_terms) ? role.evidence_terms : []),
        ...stages(role).flatMap((stage) => [
          stage.identity,
          ...(Array.isArray(stage.evidence_terms) ? stage.evidence_terms : []),
        ]),
      ]
        .filter(Boolean)
        .join(', '),
    );
    const matched = [...expectedTerms].some((term) =>
      roleText.includes(normalizedTagKey(term)),
    );
    if (!matched) {
      issues.push({
        role_id: roleId,
        display_name: stringValue(role.display_name),
        expected_character_terms: [...expectedTerms].slice(0, 20),
        issue: 'role_identity_not_supported_by_source_character_terms',
      });
    }
  }
  return issues;
}

function roleNameAppearsInSource(role, sourceCaptionTexts) {
  if (sourceCaptionTexts.length === 0) return false;
  const sourceText = sourceCaptionTexts.join(', ');
  return roleIdentityNames(role).some((name) => sourceText.includes(name));
}

function roleIdentityNames(role) {
  return [
    role.display_name,
    role.canonical_name,
    ...(Array.isArray(role.raw_identity_tags) ? role.raw_identity_tags : []),
  ]
    .flatMap((value) => {
      const normalized = normalizedTagKey(value);
      const withoutQualifier = normalized.replace(/\s*\([^)]*\)\s*/g, ' ').trim();
      return [normalized, withoutQualifier];
    })
    .filter((value) => value.length >= 3);
}

function isRoleIdentityTerm(term) {
  const normalized = normalizedTagKey(term);
  if (/\b(hair|eyes?|pupils?|iris|irises|skin|ears?|face|mouth|teeth|blush|horns?|tail)\b/.test(normalized)) {
    return false;
  }
  return true;
}

function classificationAudit(cache, classificationCache) {
  const issues = [];
  for (const role of roles(cache)) {
    for (const stage of stages(role)) {
      auditFieldTerms({
        issues,
        classificationCache,
        roleId: stringValue(role.source_role_id),
        stageId: stringValue(stage.stage_id),
        section: 'aiRoleExtraction',
        field: 'identity',
        value: stringValue(stage.identity),
        disallowed: hardDisallowed.identity,
      });
      auditFieldTerms({
        issues,
        classificationCache,
        roleId: stringValue(role.source_role_id),
        stageId: stringValue(stage.stage_id),
        section: 'aiRoleExtraction',
        field: 'upper_body',
        value: stringValue(stage.upper_body),
        disallowed: hardDisallowed.body,
      });
      auditFieldTerms({
        issues,
        classificationCache,
        roleId: stringValue(role.source_role_id),
        stageId: stringValue(stage.stage_id),
        section: 'aiRoleExtraction',
        field: 'lower_body',
        value: stringValue(stage.lower_body),
        disallowed: hardDisallowed.body,
      });
      auditFieldTerms({
        issues,
        classificationCache,
        roleId: stringValue(role.source_role_id),
        stageId: stringValue(stage.stage_id),
        section: 'aiRoleExtraction',
        field: 'upper_clothing',
        value: stringValue(stage.upper_clothing),
        disallowed: hardDisallowed.clothing,
      });
      auditFieldTerms({
        issues,
        classificationCache,
        roleId: stringValue(role.source_role_id),
        stageId: stringValue(stage.stage_id),
        section: 'aiRoleExtraction',
        field: 'lower_clothing',
        value: stringValue(stage.lower_clothing),
        disallowed: hardDisallowed.clothing,
      });
    }
  }
  for (const assembly of roleAssemblies(cache)) {
    for (const stage of Array.isArray(assembly.stages) ? assembly.stages : []) {
      const sourceParts = stage.sourceParts ?? stage.source_parts ?? {};
      auditFieldTerms({
        issues,
        classificationCache,
        roleId: stringValue(assembly.sourceRoleId ?? assembly.source_role_id),
        stageId: stringValue(stage.id),
        section: 'mapping',
        field: 'sourceParts.identity',
        value: stringValue(sourceParts.identity),
        disallowed: hardDisallowed.identity,
      });
      auditFieldTerms({
        issues,
        classificationCache,
        roleId: stringValue(assembly.sourceRoleId ?? assembly.source_role_id),
        stageId: stringValue(stage.id),
        section: 'mapping',
        field: 'sourceParts.upperBody',
        value: stringValue(sourceParts.upperBody ?? sourceParts.upper_body),
        disallowed: hardDisallowed.body,
      });
      auditFieldTerms({
        issues,
        classificationCache,
        roleId: stringValue(assembly.sourceRoleId ?? assembly.source_role_id),
        stageId: stringValue(stage.id),
        section: 'mapping',
        field: 'sourceParts.lowerBody',
        value: stringValue(sourceParts.lowerBody ?? sourceParts.lower_body),
        disallowed: hardDisallowed.body,
      });
      auditFieldTerms({
        issues,
        classificationCache,
        roleId: stringValue(assembly.sourceRoleId ?? assembly.source_role_id),
        stageId: stringValue(stage.id),
        section: 'mapping',
        field: 'sourceParts.upperClothing',
        value: stringValue(
          sourceParts.upperClothing ?? sourceParts.upper_clothing,
        ),
        disallowed: hardDisallowed.clothing,
      });
      auditFieldTerms({
        issues,
        classificationCache,
        roleId: stringValue(assembly.sourceRoleId ?? assembly.source_role_id),
        stageId: stringValue(stage.id),
        section: 'mapping',
        field: 'sourceParts.lowerClothing',
        value: stringValue(
          sourceParts.lowerClothing ?? sourceParts.lower_clothing,
        ),
        disallowed: hardDisallowed.clothing,
      });
    }
  }
  return issues;
}

function auditFieldTerms({
  issues,
  classificationCache,
  roleId,
  stageId,
  section,
  field,
  value,
  disallowed,
}) {
  for (const term of splitPromptTerms(value)) {
    const category = classificationCache.get(`positive:${normalizedTagKey(term)}`);
    if (!category || !disallowed.has(category)) continue;
    issues.push({
      section,
      role_id: roleId,
      stage_id: stageId,
      field,
      term,
      category,
      issue: 'hard_category_mismatch',
    });
  }
}

function classifiedTerms(value, classificationCache, categories) {
  const allowed = new Set(categories);
  return splitPromptTerms(value).filter((term) => {
    const category = classificationCache.get(`positive:${normalizedTagKey(term)}`);
    return allowed.has(category);
  });
}

function splitPromptTerms(value) {
  return stringValue(value)
    .split(',')
    .map(cleanPromptTerm)
    .filter((term) => term.length > 0);
}

function cleanPromptTerm(value) {
  return value
    .replace(/\b-?\d+(?:\.\d+)?::/g, '')
    .replace(/::/g, '')
    .replace(/\|/g, '')
    .trim();
}

function normalizedTagKey(value) {
  return cleanPromptTerm(value)
    .toLowerCase()
    .replace(/[_-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function sourceFingerprintFrameCount(fingerprint) {
  if (typeof fingerprint !== 'string' || !fingerprint.trim()) return 0;
  return fingerprint
    .split('|')
    .slice(2)
    .filter((part) => /^\d+:/.test(part)).length;
}

function roles(cache) {
  return Array.isArray(cache.aiRoleExtraction?.roles)
    ? cache.aiRoleExtraction.roles
    : [];
}

function appearances(role) {
  return Array.isArray(role.appearances) ? role.appearances : [];
}

function stages(role) {
  return Array.isArray(role.stages) ? role.stages : [];
}

function roleAssemblies(cache) {
  const assemblies =
    cache.mapping?.roleAssemblies ?? cache.mapping?.role_assemblies;
  return Array.isArray(assemblies) ? assemblies : [];
}

function slotIndexFromSourceId(value) {
  const match = /^slot-(\d+)$/i.exec(stringValue(value).trim());
  return match ? Number(match[1]) : null;
}

function intList(value) {
  return Array.isArray(value)
    ? value.map(toInt).filter((number) => number != null)
    : [];
}

function toInt(value) {
  if (Number.isInteger(value)) return value;
  if (typeof value === 'number') return Math.trunc(value);
  if (typeof value === 'string' && /^-?\d+$/.test(value.trim())) {
    return Number(value);
  }
  return null;
}

function isParsedFrame(frame) {
  return stringValue(frame?.parseStatus ?? frame?.parse_status).toLowerCase() ===
    'parsed';
}

function loadClassificationCache(filePath) {
  const raw = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const result = new Map();
  for (const [key, value] of Object.entries(raw)) {
    if (value && typeof value.category === 'string') {
      result.set(normalizedCacheKey(key), value.category);
    }
  }
  return result;
}

function normalizedCacheKey(key) {
  const [prefix, ...parts] = String(key).split(':');
  return `${prefix}:${normalizedTagKey(parts.join(':'))}`;
}

function normalizePath(value) {
  const normalized = String(value).replace(/\\/g, '/');
  return process.platform === 'win32' ? normalized.toLowerCase() : normalized;
}

function sameIntList(left, right) {
  if (left.length !== right.length) return false;
  for (let index = 0; index < left.length; index += 1) {
    if (left[index] !== right[index]) return false;
  }
  return true;
}

function printableRow(row) {
  return {
    file_name: row.file_name,
    script_name: row.script_name,
    source_root_path: row.source_root_path,
    frame_count: row.frame_count,
    parsed_frame_count: row.parsed_frame_count,
    png_metadata_missing_frame_count: row.png_metadata_missing_frame_count,
    source_frame_mismatch: row.source_frame_mismatch,
    slot_coverage_issue_count: row.slot_coverage_issue_count,
    role_identity_issue_count: row.role_identity_issue_count,
    role_frame_reference_issue_count: row.role_frame_reference_issue_count,
    classification_issue_count: row.classification_issue_count,
    slot_coverage_sample: row.slot_coverage_issues.slice(0, 8),
    role_identity_sample: row.role_identity_issues.slice(0, 8),
    role_frame_reference_sample: row.role_frame_reference_issues.slice(0, 8),
    classification_sample: row.classification_issues.slice(0, 8),
  };
}

function parseArgs(args) {
  const parsed = {
    cacheDir: undefined,
    classificationCache: undefined,
    sourceRoot: undefined,
    reportPath: undefined,
    from: 0,
    to: undefined,
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
    if (key === 'classification-cache') parsed.classificationCache = value;
    if (key === 'source-root') parsed.sourceRoot = value;
    if (key === 'report') parsed.reportPath = value;
    if (key === 'from') parsed.from = Number(value) || 0;
    if (key === 'to') parsed.to = value === '' ? undefined : Number(value);
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
