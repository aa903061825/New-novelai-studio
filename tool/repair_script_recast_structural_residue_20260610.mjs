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
const backupDir = path.join(
  process.cwd(),
  'build',
  'script_recast_structural_residue_backup_20260610',
);

const oldGymRoot =
  'C:\\Users\\admin\\Downloads\\找高张数图集下载\\合并下载';
const newGymRoot = 'E:\\NAI的脚本群\\作品集\\健身房寝取られ';

const repairs = [];

repairFile('script-4b52a5bc143eb5fa.json', repairGymCache);
repairFile('script-2-e69c8f5b21c9790b.json', repairSparkleContinuityCache);
for (const fileName of [
  'script-2-09f7789a32d75447.json',
  'script-3548d2f14c392cf1.json',
  'script-4e79c39083c9c88d.json',
  'script-5806256bfb56f0fb.json',
]) {
  repairFile(fileName, repairFieldFormattingResidue);
}

const summary = {
  apply: options.apply,
  cache_dir: cacheDir,
  backup_dir: options.apply ? backupDir : null,
  repairs,
};

console.log(JSON.stringify(summary, null, 2));

function repairFile(fileName, repair) {
  const filePath = path.join(cacheDir, fileName);
  if (!fs.existsSync(filePath)) {
    repairs.push({ file_name: fileName, changed: false, reason: 'missing' });
    return;
  }
  const originalText = fs.readFileSync(filePath, 'utf8');
  const cache = JSON.parse(originalText);
  const result = repair(cache);
  const nextText = `${JSON.stringify(cache, null, 2)}\n`;
  const changed = nextText !== originalText;
  repairs.push({ file_name: fileName, changed, ...result });
  if (!options.apply || !changed) return;
  fs.mkdirSync(backupDir, { recursive: true });
  const backupPath = path.join(backupDir, fileName);
  if (!fs.existsSync(backupPath)) {
    fs.copyFileSync(filePath, backupPath);
  }
  fs.writeFileSync(filePath, nextText, 'utf8');
}

function repairGymCache(cache) {
  const notes = [];
  replaceGymPaths(cache, notes);
  repairRoleSlotAppearances(cache, {
    'role-belle-zzz': (caption) => caption.includes('belle (zenless zone zero)'),
    'role-recurring-fat-faceless-male': (caption) =>
      caption.includes('fat man') ||
      (caption.includes('dark-skinned male') && !caption.includes('muscular male')),
    'role-asaba-harumasa': (caption) =>
      caption.includes('asaba harumasa') || caption.includes('asaba_harumasa'),
    'role-single-muscular-faceless-male': (caption) =>
      caption.includes('muscular male'),
  }, notes);
  upsertGenericSourceSlotRole(cache, {
    roleId: 'role-source-slot-1',
    displayName: 'boy',
    sourceId: 'slot-1',
    frameIndexes: [10, 131].filter((index) => hasSlotCaption(cache, index, 1)),
    identity: 'boy',
  }, notes);
  return { action: 'repair_gym_renamed_path_and_slot_appearances', notes };
}

function replaceGymPaths(cache, notes) {
  if (cache.sourceRootPath === oldGymRoot) {
    cache.sourceRootPath = newGymRoot;
    notes.push('sourceRootPath');
  }
  if (cache.scriptName === '合并下载') {
    cache.scriptName = '健身房寝取られ';
    notes.push('scriptName');
  }
  if (cache.scriptSnapshot && typeof cache.scriptSnapshot === 'object') {
    if (cache.scriptSnapshot.rootPath === oldGymRoot) {
      cache.scriptSnapshot.rootPath = newGymRoot;
      notes.push('scriptSnapshot.rootPath');
    }
    if (cache.scriptSnapshot.name === '合并下载') {
      cache.scriptSnapshot.name = '健身房寝取られ';
      notes.push('scriptSnapshot.name');
    }
  }
  if (typeof cache.sourceFingerprint === 'string') {
    const next = cache.sourceFingerprint.split(oldGymRoot).join(newGymRoot);
    if (next !== cache.sourceFingerprint) {
      cache.sourceFingerprint = next;
      notes.push('sourceFingerprint');
    }
  }
  for (const frame of frames(cache)) {
    if (typeof frame.sourcePath === 'string' && frame.sourcePath.startsWith(oldGymRoot)) {
      frame.sourcePath = path.win32.join(newGymRoot, path.win32.basename(frame.sourcePath));
      notes.push('frame.sourcePath');
    }
  }
}

function repairSparkleContinuityCache(cache) {
  const notes = [];
  const role = findRole(cache, 'role_aventurine_hsr');
  if (!role) return { action: 'repair_sparkle_slot_continuity', notes: ['role_missing'] };
  const frameIndexes = [69, 70, 89].filter((index) =>
    hasSlotCaption(cache, index, 1),
  );
  addAppearanceFrames(role, 'slot-1', frameIndexes);
  addRoleFrames(role, frameIndexes);
  notes.push(`added slot-1 frames ${frameIndexes.join(',')}`);
  return { action: 'repair_sparkle_slot_continuity', notes };
}

function repairFieldFormattingResidue(cache) {
  let changedTerms = 0;
  for (const role of roles(cache)) {
    role.evidence_terms = cleanTermArray(role.evidence_terms);
    role.raw_identity_tags = cleanTermArray(role.raw_identity_tags);
    for (const stage of Array.isArray(role.stages) ? role.stages : []) {
      for (const field of [
        'identity',
        'upper_body',
        'lower_body',
        'upper_clothing',
        'lower_clothing',
      ]) {
        const before = stage[field];
        stage[field] = cleanTermString(stage[field]);
        if (stage[field] !== before) changedTerms++;
      }
      const beforeEvidence = JSON.stringify(stage.evidence_terms ?? []);
      stage.evidence_terms = cleanTermArray(stage.evidence_terms);
      if (JSON.stringify(stage.evidence_terms ?? []) !== beforeEvidence) {
        changedTerms++;
      }
    }
  }
  for (const assembly of cache.mapping?.roleAssemblies ?? []) {
    for (const stage of Array.isArray(assembly.stages) ? assembly.stages : []) {
      const parts = stage.sourceParts;
      if (!parts || typeof parts !== 'object') continue;
      for (const field of [
        'identity',
        'upperBody',
        'lowerBody',
        'upperClothing',
        'lowerClothing',
      ]) {
        const before = parts[field];
        parts[field] = cleanTermString(parts[field]);
        if (parts[field] !== before) changedTerms++;
      }
    }
  }
  return {
    action: 'repair_field_formatting_residue',
    notes: changedTerms > 0 ? [`changed term containers=${changedTerms}`] : [],
  };
}

function repairRoleSlotAppearances(cache, matchers, notes) {
  const roleSlots = new Map(
    Object.keys(matchers).map((roleId) => [roleId, new Map()]),
  );
  for (const frame of frames(cache)) {
    const frameIndex = numberValue(frame.index);
    if (frameIndex == null) continue;
    const captions = Array.isArray(frame.parsed?.charCaptions)
      ? frame.parsed.charCaptions
      : [];
    captions.forEach((caption, slot) => {
      const normalized = normalize(String(caption ?? ''));
      for (const [roleId, matches] of Object.entries(matchers)) {
        if (!matches(normalized)) continue;
        const slots = roleSlots.get(roleId);
        const key = `slot-${slot}`;
        const indexes = slots.get(key) ?? [];
        indexes.push(frameIndex);
        slots.set(key, indexes);
      }
    });
  }

  for (const [roleId, slots] of roleSlots.entries()) {
    const role = findRole(cache, roleId);
    if (!role) {
      notes.push(`${roleId}:missing`);
      continue;
    }
    const appearances = [...slots.entries()]
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([sourceId, indexes]) => ({
        source_id: sourceId,
        frame_indexes: uniqueSorted(indexes),
      }));
    role.appearances = appearances;
    role.frame_indexes = uniqueSorted(appearances.flatMap((item) => item.frame_indexes));
    notes.push(`${roleId}:${appearances.map((item) => `${item.source_id}=${item.frame_indexes.length}`).join('/')}`);
  }
}

function addAppearanceFrames(role, sourceId, frameIndexes) {
  role.appearances = Array.isArray(role.appearances) ? role.appearances : [];
  let appearance = role.appearances.find((item) => item.source_id === sourceId);
  if (!appearance) {
    appearance = { source_id: sourceId, frame_indexes: [] };
    role.appearances.push(appearance);
  }
  appearance.frame_indexes = uniqueSorted([
    ...arrayValue(appearance.frame_indexes),
    ...frameIndexes,
  ]);
}

function addRoleFrames(role, frameIndexes) {
  role.frame_indexes = uniqueSorted([
    ...arrayValue(role.frame_indexes),
    ...frameIndexes,
  ]);
}

function upsertGenericSourceSlotRole(
  cache,
  { roleId, displayName, sourceId, frameIndexes, identity },
  notes,
) {
  if (frameIndexes.length === 0) return;
  const extraction = cache.aiRoleExtraction ?? {};
  extraction.roles = Array.isArray(extraction.roles) ? extraction.roles : [];
  cache.aiRoleExtraction = extraction;
  let role = findRole(cache, roleId);
  if (!role) {
    role = {
      source_role_id: roleId,
      source_kind: 'char_caption_generic_role',
      display_name: displayName,
      role_reason: '源帧只有泛化角色槽位，保留为源槽位角色以避免错挂到具名角色。',
      canonical_name: '',
      franchise: '',
      raw_identity_tags: [identity],
      variant_tags: [],
      merge_with_role_id: '',
      confidence: 0.8,
      frame_indexes: [],
      appearances: [],
      evidence_terms: [identity],
      warnings: [],
      stages: [
        {
          stage_id: `${roleId}-stage-1`,
          label: identity,
          appearance_group_id: `${roleId}-stage-1`,
          merge_with_stage_ids: [],
          field_reasons: {
            identity: '源帧泛化角色证据。',
            upper_body: '',
            lower_body: '',
            upper_clothing: '',
            lower_clothing: '',
          },
          confidence: 0.8,
          frame_indexes: [],
          identity,
          upper_body: '',
          lower_body: '',
          upper_clothing: '',
          lower_clothing: '',
          evidence_terms: [identity],
          missing_fields: [],
          warnings: [],
        },
      ],
      unassigned_terms: [],
    };
    extraction.roles.push(role);
  }
  role.display_name = displayName;
  role.raw_identity_tags = [identity];
  role.evidence_terms = [identity];
  addAppearanceFrames(role, sourceId, frameIndexes);
  addRoleFrames(role, frameIndexes);
  const stage = Array.isArray(role.stages) ? role.stages[0] : null;
  if (stage) {
    stage.frame_indexes = uniqueSorted(frameIndexes);
    stage.identity = identity;
    stage.upper_body = '';
    stage.lower_body = '';
    stage.upper_clothing = '';
    stage.lower_clothing = '';
    stage.evidence_terms = [identity];
    stage.warnings = [];
  }
  notes.push(`${roleId}:${sourceId}=${frameIndexes.length}`);
}

function hasSlotCaption(cache, frameIndex, slot) {
  const frame = frames(cache).find((item) => numberValue(item.index) === frameIndex);
  const captions = Array.isArray(frame?.parsed?.charCaptions)
    ? frame.parsed.charCaptions
    : [];
  return String(captions[slot] ?? '').trim().length > 0;
}

function findRole(cache, roleId) {
  return roles(cache).find((role) => (role.roleId ?? role.source_role_id) === roleId);
}

function roles(cache) {
  return Array.isArray(cache.aiRoleExtraction?.roles)
    ? cache.aiRoleExtraction.roles
    : [];
}

function frames(cache) {
  return Array.isArray(cache.scriptSnapshot?.frames) ? cache.scriptSnapshot.frames : [];
}

function cleanTermString(value) {
  if (typeof value !== 'string') return value;
  return cleanTermArray(value.split(',')).join(', ');
}

function cleanTermArray(value) {
  if (!Array.isArray(value)) return value;
  const cleaned = [];
  for (const raw of value) {
    for (const term of cleanOneTerm(raw)) {
      if (!cleaned.includes(term)) cleaned.push(term);
    }
  }
  return cleaned;
}

function cleanOneTerm(value) {
  const term = String(value ?? '').trim();
  if (!term) return [];
  if (term === 'pregnant/big belly') return ['pregnant', 'big belly'];
  if (term === 'white gloves/elbow gloves') return ['white gloves', 'elbow gloves'];
  if (term === 'feet)') return ['feet'];
  if (term === 'kokkoro(princess connect!)') return [];
  if (term === 'char2：dark skin') return ['dark skin'];
  return [term];
}

function normalize(value) {
  return value.toLowerCase().replace(/_/g, ' ').replace(/\s+/g, ' ').trim();
}

function arrayValue(value) {
  return Array.isArray(value) ? value : [];
}

function numberValue(value) {
  const number = Number(value);
  return Number.isInteger(number) ? number : null;
}

function uniqueSorted(values) {
  return [...new Set(values.map(Number).filter((value) => Number.isInteger(value)))]
    .sort((left, right) => left - right);
}

function parseArgs(args) {
  const parsed = { apply: false, cacheDir: undefined };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--apply') {
      parsed.apply = true;
      continue;
    }
    const equalIndex = arg.indexOf('=');
    const key = equalIndex > 0 ? arg.slice(2, equalIndex) : arg.slice(2);
    const value = equalIndex > 0 ? arg.slice(equalIndex + 1) : args[index + 1] ?? '';
    if (equalIndex < 0) index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
  }
  return parsed;
}
