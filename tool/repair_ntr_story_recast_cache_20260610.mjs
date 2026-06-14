import fs from 'node:fs';
import path from 'node:path';

const targetIds = new Set([
  'script-0f5b80222278c773',
  'script-2-1adaf3e6f876d937',
  'script-4b60783933b7075b',
  'script-0ffd027df52a5972',
]);

const options = parseArgs(process.argv.slice(2));
const cacheDir = options.cacheDir ?? 'E:/codex-temp/ntr-script-recast-audit-cache';
const reportPath =
  options.report ?? 'build/ntr_story_structural_repair_20260610.json';

if (!fs.existsSync(cacheDir)) {
  throw new Error(`Missing cache dir: ${cacheDir}`);
}

const summary = {
  cache_dir: cacheDir,
  apply: options.apply,
  files_scanned: 0,
  files_changed: 0,
  invalid_appearance_frames_removed: 0,
  missing_slot_frames_added: 0,
  roles_added: 0,
  terms_removed: 0,
  terms_replaced: 0,
  empty_stages_removed: 0,
  files: [],
};

for (const fileName of fs.readdirSync(cacheDir).filter((file) => file.endsWith('.json')).sort()) {
  const filePath = path.join(cacheDir, fileName);
  const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  if (!targetIds.has(stringValue(cache.scriptId))) continue;
  summary.files_scanned += 1;

  const original = JSON.stringify(cache);
  const report = {
    file_name: fileName,
    script_name: stringValue(cache.scriptName),
    removed_invalid_appearance_frames: 0,
    added_missing_slot_frames: 0,
    added_roles: 0,
    removed_terms: [],
    replaced_terms: [],
  };

  filterInvalidAppearanceFrames(cache, report);
  applyManualCoverage(cache, report);
  filterInvalidAppearanceFrames(cache, report);
  syncRoleFrameIndexes(cache, report);
  cleanKnownTermResidue(cache, report);

  if (JSON.stringify(cache) !== original) {
    summary.files_changed += 1;
    summary.files.push(report);
    if (options.apply) {
      fs.writeFileSync(filePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
    }
  }
}

fs.mkdirSync(path.dirname(reportPath), { recursive: true });
fs.writeFileSync(reportPath, `${JSON.stringify(summary, null, 2)}\n`, 'utf8');
console.log(JSON.stringify(summary, null, 2));

function filterInvalidAppearanceFrames(cache, report) {
  for (const role of roles(cache)) {
    for (const appearance of Array.isArray(role.appearances)
      ? role.appearances
      : []) {
      const sourceId = stringValue(appearance.source_id);
      const before = intList(appearance.frame_indexes);
      if (!sourceId.startsWith('slot-')) continue;
      const after = before.filter((frameIndex) =>
        frameHasSlot(cache, frameIndex, sourceId),
      );
      const removed = before.length - after.length;
      if (removed > 0) {
        appearance.frame_indexes = after;
        report.removed_invalid_appearance_frames += removed;
        summary.invalid_appearance_frames_removed += removed;
      }
    }
    role.appearances = (Array.isArray(role.appearances) ? role.appearances : [])
      .filter((appearance) => intList(appearance.frame_indexes).length > 0);
  }
}

function applyManualCoverage(cache, report) {
  switch (stringValue(cache.scriptId)) {
    case 'script-0ffd027df52a5972':
      addFramesToExistingRole(cache, {
        role: (role) => stringValue(role.canonical_name) === 'pecorine',
        sourceId: 'slot-0',
        stageId: 'stage-pecorine-white-bikini',
        frameIndexes: [37, 38, 39, 42],
        report,
      });
      break;
    case 'script-2-1adaf3e6f876d937':
      addConservativeBoyHandsRole(cache, report);
      break;
    case 'script-4b60783933b7075b':
      addFramesToExistingRole(cache, {
        role: (role) => stringValue(role.source_role_id) === 'role-fatman',
        sourceId: 'slot-1',
        stageId: 'fatman-stage-0',
        frameIndexes: [73, 74],
        report,
      });
      addFramesToExistingRole(cache, {
        role: (role) => stringValue(role.source_role_id) === 'role-maho',
        sourceId: 'slot-0',
        stageId: 'maho-stage-1',
        frameIndexes: [77],
        report,
      });
      break;
  }
}

function addFramesToExistingRole(cache, config) {
  const role = roles(cache).find(config.role);
  if (!role) return;
  const validFrames = config.frameIndexes.filter((frameIndex) =>
    frameHasSlot(cache, frameIndex, config.sourceId),
  );
  if (validFrames.length === 0) return;

  const appearance = ensureAppearance(role, config.sourceId);
  const beforeAppearance = intList(appearance.frame_indexes);
  appearance.frame_indexes = sortedUnique([...beforeAppearance, ...validFrames]);

  const stage = (Array.isArray(role.stages) ? role.stages : []).find(
    (candidate) => stringValue(candidate.id) === config.stageId,
  );
  if (stage) {
    stage.frame_indexes = sortedUnique([
      ...intList(stage.frame_indexes),
      ...validFrames,
    ]);
  }
  role.frame_indexes = sortedUnique([...intList(role.frame_indexes), ...validFrames]);
  const added = validFrames.filter((frame) => !beforeAppearance.includes(frame)).length;
  config.report.added_missing_slot_frames += added;
  summary.missing_slot_frames_added += added;
}

function addConservativeBoyHandsRole(cache, report) {
  const frameIndexes = [18].filter((frameIndex) =>
    frameHasSlot(cache, frameIndex, 'slot-1'),
  );
  if (frameIndexes.length === 0) return;
  const existing = roles(cache).find(
    (role) => stringValue(role.source_role_id) === 'role-source-slot-1-frame-18',
  );
  if (existing) return;
  cache.aiRoleExtraction.roles.push({
    source_role_id: 'role-source-slot-1-frame-18',
    source_kind: 'slot',
    display_name: 'Boy',
    canonical_name: 'boy',
    franchise: '',
    confidence: 0.45,
    frame_indexes: frameIndexes,
    appearances: [
      {
        source_id: 'slot-1',
        source_kind: 'slot',
        frame_indexes: frameIndexes,
      },
    ],
    raw_identity_tags: ['boy'],
    variant_tags: [],
    evidence_terms: ['boy'],
    role_reason:
      'Conservative source slot coverage for a boy/disembodied-hands frame; no stable identity inferred.',
    merge_with_role_id: null,
    stages: [
      {
        id: 'stage-boy-hands-0',
        label: 'Boy',
        frame_indexes: frameIndexes,
        identity: 'boy',
        upper_body: '',
        lower_body: '',
        upper_clothing: '',
        lower_clothing: '',
        evidence_terms: ['boy'],
        missing_fields: [],
        field_reasons: {},
        warnings: [],
      },
    ],
    unassigned_terms: [],
    warnings: [],
  });
  report.added_roles += 1;
  report.added_missing_slot_frames += frameIndexes.length;
  summary.roles_added += 1;
  summary.missing_slot_frames_added += frameIndexes.length;
}

function syncRoleFrameIndexes(cache, report) {
  for (const role of roles(cache)) {
    const validFrames = sortedUnique(
      (Array.isArray(role.appearances) ? role.appearances : [])
        .flatMap((appearance) => intList(appearance.frame_indexes)),
    );
    role.frame_indexes = validFrames;
    const keptStages = [];
    for (const stage of Array.isArray(role.stages) ? role.stages : []) {
      const filtered = intList(stage.frame_indexes)
        .filter((frameIndex) => validFrames.includes(frameIndex));
      if (filtered.length === 0) {
        report.removed_terms.push({
          reason: 'empty_stage_after_slot_filter',
          term: stringValue(stage.id),
        });
        summary.empty_stages_removed += 1;
        continue;
      }
      stage.frame_indexes = filtered;
      keptStages.push(stage);
    }
    role.stages = keptStages;
  }
}

function cleanKnownTermResidue(cache, report) {
  for (const role of roles(cache)) {
    for (const stage of Array.isArray(role.stages) ? role.stages : []) {
      replaceTerm(stage, 'identity', 'musclar male', 'muscular male', report);
      removeTerm(stage, 'upper_body', 'barcode tattoo', report);
      removeTerm(stage, 'upper_body', 'orange flower', report);
      removeTerm(stage, 'upper_body', 'heart in eye', report);
      removeTerm(stage, 'upper_body', 'heart in eyes', report);
      replaceTermList(stage, 'evidence_terms', 'musclar male', 'muscular male', report);
      removeTermFromList(stage, 'evidence_terms', 'barcode tattoo', report);
      removeTermFromList(stage, 'evidence_terms', 'orange flower', report);
      removeTermFromList(stage, 'evidence_terms', 'heart in eye', report);
      removeTermFromList(stage, 'evidence_terms', 'heart in eyes', report);
    }
    replaceTermList(role, 'evidence_terms', 'musclar male', 'muscular male', report);
    removeTermFromList(role, 'evidence_terms', 'barcode tattoo', report);
    removeTermFromList(role, 'evidence_terms', 'orange flower', report);
    removeTermFromList(role, 'evidence_terms', 'heart in eye', report);
    removeTermFromList(role, 'evidence_terms', 'heart in eyes', report);
    replaceTermList(role, 'raw_identity_tags', 'musclar male', 'muscular male', report);
  }
}

function ensureAppearance(role, sourceId) {
  role.appearances = Array.isArray(role.appearances) ? role.appearances : [];
  let appearance = role.appearances.find(
    (candidate) => stringValue(candidate.source_id) === sourceId,
  );
  if (!appearance) {
    appearance = {
      source_id: sourceId,
      source_kind: 'slot',
      frame_indexes: [],
    };
    role.appearances.push(appearance);
  }
  return appearance;
}

function frameHasSlot(cache, frameIndex, sourceId) {
  const slot = Number(sourceId.replace('slot-', ''));
  if (!Number.isInteger(slot) || slot < 0) return false;
  const frame = frames(cache).find((candidate) => Number(candidate.index) === frameIndex);
  const captions = Array.isArray(frame?.parsed?.charCaptions)
    ? frame.parsed.charCaptions
    : [];
  return stringValue(captions[slot]).trim().length > 0;
}

function removeTerm(object, field, term, report) {
  const values = splitTerms(object[field]);
  const next = values.filter((value) => key(value) !== key(term));
  if (next.length !== values.length) {
    object[field] = next.join(', ');
    report.removed_terms.push({ field, term });
    summary.terms_removed += values.length - next.length;
  }
}

function replaceTerm(object, field, from, to, report) {
  const values = splitTerms(object[field]);
  let changed = false;
  const next = values.map((value) => {
    if (key(value) !== key(from)) return value;
    changed = true;
    return to;
  });
  if (changed) {
    object[field] = next.join(', ');
    report.replaced_terms.push({ field, from, to });
    summary.terms_replaced += 1;
  }
}

function removeTermFromList(object, field, term, report) {
  const values = Array.isArray(object[field]) ? object[field] : [];
  const next = values.filter((value) => key(value) !== key(term));
  if (next.length !== values.length) {
    object[field] = next;
    report.removed_terms.push({ field, term });
    summary.terms_removed += values.length - next.length;
  }
}

function replaceTermList(object, field, from, to, report) {
  const values = Array.isArray(object[field]) ? object[field] : [];
  let changed = false;
  const next = values.map((value) => {
    if (key(value) !== key(from)) return value;
    changed = true;
    return to;
  });
  if (changed) {
    object[field] = sortedUnique(next);
    report.replaced_terms.push({ field, from, to });
    summary.terms_replaced += 1;
  }
}

function roles(cache) {
  return Array.isArray(cache.aiRoleExtraction?.roles)
    ? cache.aiRoleExtraction.roles
    : [];
}

function frames(cache) {
  return Array.isArray(cache.scriptSnapshot?.frames)
    ? cache.scriptSnapshot.frames
    : [];
}

function splitTerms(value) {
  return stringValue(value)
    .split(',')
    .map((part) => part.trim())
    .filter(Boolean);
}

function intList(values) {
  return (Array.isArray(values) ? values : [])
    .map((value) => Number(value))
    .filter((value) => Number.isInteger(value) && value > 0);
}

function sortedUnique(values) {
  return [...new Set(values)].sort((left, right) => {
    if (typeof left === 'number' && typeof right === 'number') {
      return left - right;
    }
    return String(left).localeCompare(String(right));
  });
}

function key(value) {
  return stringValue(value).trim().toLowerCase();
}

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}

function parseArgs(args) {
  const parsed = { apply: false };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--apply') {
      parsed.apply = true;
    } else if (arg === '--cache-dir' && args[index + 1]) {
      parsed.cacheDir = args[++index];
    } else if (arg.startsWith('--cache-dir=')) {
      parsed.cacheDir = arg.slice('--cache-dir='.length);
    } else if (arg === '--report' && args[index + 1]) {
      parsed.report = args[++index];
    } else if (arg.startsWith('--report=')) {
      parsed.report = arg.slice('--report='.length);
    }
  }
  return parsed;
}
