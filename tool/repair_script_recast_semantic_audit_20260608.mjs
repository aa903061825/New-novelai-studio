import fs from 'node:fs';
import path from 'node:path';

const cacheDir = path.join(
  process.env.APPDATA ?? '',
  'org.exception0x0194',
  'nai3_autodraw',
  'novel_studio',
  'script_recast',
  'cache',
);
const classificationPath =
  'E:/NAI\u7684\u811a\u672c\u7fa4/tag_classification_cache.json';
const backupDir = path.join(
  'build',
  `script_recast_semantic_audit_backup_${timestamp()}`,
);
const source = 'codex-script-cache-semantic-audit-20260608';

const changedCacheFiles = new Set();
const changedClassificationKeys = [];
const repairs = [];

if (!fs.existsSync(cacheDir)) throw new Error(`Missing cache dir: ${cacheDir}`);

repairClassificationCache();
repairCacheFiles();

console.log(
  JSON.stringify(
    {
      cache_dir: cacheDir,
      classification_cache: classificationPath,
      backup_dir: path.resolve(backupDir),
      changed_cache_files: [...changedCacheFiles].sort(),
      changed_classification_keys: changedClassificationKeys,
      repair_count: repairs.length,
      repairs,
    },
    null,
    2,
  ),
);

function repairClassificationCache() {
  const cache = JSON.parse(fs.readFileSync(classificationPath, 'utf8'));
  const updates = {
    'positive:white panties': 'lowerClothing',
    'positive:long twin tails': 'upperBody',
    'positive:elbow gloves': 'upperClothing',
    'positive:toeless legwear': 'lowerClothing',
  };
  let touched = false;
  for (const [key, category] of Object.entries(updates)) {
    const before = cache[key] ?? {};
    if (before.category === category && before.source === source) continue;
    cache[key] = {
      ...before,
      category,
      source,
      updatedAt: Math.floor(Date.now() / 1000),
    };
    changedClassificationKeys.push(key);
    touched = true;
  }
  if (touched) {
    fs.mkdirSync(backupDir, { recursive: true });
    fs.copyFileSync(
      classificationPath,
      path.join(backupDir, 'tag_classification_cache.json'),
    );
    fs.writeFileSync(classificationPath, `${JSON.stringify(cache, null, 2)}\n`);
  }
}

function repairCacheFiles() {
  patchFile('script-bgl-51b810cf580bcd14.json', (cache) => {
    ensureRole(cache, {
      roleId: 'role-kyoka-princess-connect',
      displayName: 'kyoka (princess connect!)',
      frames: [7, 8, 111, 112, 113, 114, 115, 116],
      sourceId: 'base',
      sourceKind: 'base',
      identity: 'kyoka (princess connect!)',
      upperBody:
        'elf, long hair, purple hair, twintails, sidelocks, blunt bangs, yellow eyes, pointy ears, hair ornament, hair ribbon, blue ribbon, small breasts',
      lowerBody: '',
      upperClothing: '',
      lowerClothing: '',
    });
  });

  patchFile('script-ump45-bbcxhorse-6078908a395fdaff.json', (cache) => {
    ensureRole(cache, {
      roleId: 'role-faceless-male-group',
      displayName: 'faceless male group',
      frames: [78],
      sourceId: 'base',
      sourceKind: 'base',
      identity: 'multiple boys, faceless male',
      upperBody: 'beard, missing tooth, fat',
      lowerBody: '',
      upperClothing: 'dirty clothes',
      lowerClothing: '',
    });
  });

  patchFile('script-nanashi-mumei-3770fc28c5a83f92.json', (cache) => {
    addFramesToRole(cache, 'role-muscular-male', [40], {
      sourceId: 'base',
      sourceKind: 'base',
      stageId: 'stage-1',
    });
  });

  patchFile('script-1-fdc34df71c7933c2.json', (cache) => {
    renameRole(cache, 'role-star-shaped-pupils', 'bunny girl');
    setIdentity(cache, 'role-star-shaped-pupils', 'girl');
    moveTerm(cache, 'role-star-shaped-pupils', 'identity', 'upper_body', 'star-shaped pupils');

    renameRole(cache, 'role-tip-inside', 'brown-skinned male');
    setIdentity(cache, 'role-tip-inside', 'male');
    removeTerms(cache, 'role-tip-inside', [
      'tip inside',
      'penis head entering pussy',
      'stretching pussy',
    ]);

    for (const roleId of [
      'role-pinning-down-girl',
      'role-pinnging-down-girl',
      'role-pressing-girl',
    ]) {
      renameRole(cache, roleId, 'brown-skinned male');
      setIdentity(cache, roleId, 'male');
      removeTerms(cache, roleId, [
        'pinning down girl',
        'pinnging down girl',
        'pressing girl',
        'on top of girl',
      ]);
    }
  });

  patchFile('script-1-7b6837c5c2cf3385.json', (cache) => {
    renameRole(cache, 'role-constricted-pupils', 'girl');
    setIdentity(cache, 'role-constricted-pupils', 'girl');
    moveTerm(cache, 'role-constricted-pupils', 'identity', 'upper_body', 'constricted pupils');
    moveTerm(cache, 'role-constricted-pupils', 'identity', 'upper_body', 'constricted pupils||');
  });

  patchFile('script-792bacf20c7c1436.json', (cache) => {
    removeRole(cache, 'role-source-slot-0');
  });

  patchFile('script-6f722bc858b8a1d6.json', (cache) => {
    renameRole(cache, 'role-source-slot-0', 'chiara bunny girl');
    setIdentity(cache, 'role-source-slot-0', 'chiara');
    moveTerm(cache, 'role-source-slot-0', 'lower_body', 'upper_body', 'long twin tails');
    moveTerm(cache, 'role-source-slot-0', 'lower_body', 'upper_body', '::1.4::long twin tails');
    moveTerm(cache, 'role-source-slot-0', 'lower_body', 'upper_body', 'blowjob::1.4::long twin tails');

    renameRole(cache, 'role-source-slot-1', 'male');
    setIdentity(cache, 'role-source-slot-1', 'male');
    removeTerms(cache, 'role-source-slot-1', ['squeezing ass', 'chiara on top']);

    renameRole(cache, 'role-source-slot-2', 'male');
    setIdentity(cache, 'role-source-slot-2', 'male');
    removeTerms(cache, 'role-source-slot-2', ['green glass bottle', 'pussy insertion']);
  });

  patchFile('script-07ebd39e9b034943.json', (cache) => {
    renameRole(cache, 'role-source-slot-0', 'amamiya kokoro (1st costume)');
    setIdentity(cache, 'role-source-slot-0', 'amamiya kokoro (1st costume)');
    moveTerm(
      cache,
      'role-source-slot-0',
      'upper_clothing',
      'identity',
      'amamiya kokoro (1st costume)',
    );
  });

  patchFile('script-vs-f16e98a8885a8360.json', (cache) => {
    renameRole(cache, 'role-crunch-teeth', 'girl');
    setIdentity(cache, 'role-crunch-teeth', 'girl');
    moveTerm(cache, 'role-crunch-teeth', 'identity', 'upper_body', 'crunch teeth');

    renameRole(cache, 'role-source-slot-0', 'man in black suit');
    setIdentity(cache, 'role-source-slot-0', 'man');
    removeTerms(cache, 'role-source-slot-0', ['hand on another person breasts', 'nipple tweat']);

    renameRole(cache, 'role-source-slot-1', 'man in black suit');
    setIdentity(cache, 'role-source-slot-1', 'man');
  });

  patchFile('script-maid-ru-e1628a286a2ef734.json', (cache) => {
    renameRole(cache, 'role-man-princess-carrying-girl', 'boy');
    setIdentity(cache, 'role-man-princess-carrying-girl', 'boy');
    removeTerms(cache, 'role-man-princess-carrying-girl', [
      'man princess carrying girl',
    ]);

    renameRole(cache, 'role-man-s-princess-carrying-girl', 'man');
    setIdentity(cache, 'role-man-s-princess-carrying-girl', 'man');
    removeTerms(cache, 'role-man-s-princess-carrying-girl', [
      "man's princess carrying girl",
    ]);

    renameRole(cache, 'role-girl-back-to-man', 'girl');
    setIdentity(cache, 'role-girl-back-to-man', 'girl');
    removeTerms(cache, 'role-girl-back-to-man', [
      'girl back to man',
      'choked by man from backside',
    ]);
  });

  patchFile('script-mhsj1-d02b7e5d79ccc0b1.json', (cache) => {
    renameRole(cache, 'role-source-slot-1', 'tentacle monster');
    setIdentity(cache, 'role-source-slot-1', 'tentacle monster');
  });

  patchFile('script-chiara-bunny-girl-3cc207fe3cf1e402.json', (cache) => {
    renameRole(cache, 'role-source-slot-0', 'chiara bunny girl');
    setIdentity(cache, 'role-source-slot-0', 'chiara');

    renameRole(cache, 'role-source-slot-1', 'male');
    setIdentity(cache, 'role-source-slot-1', 'male');
    removeTerms(cache, 'role-source-slot-1', ['chiara on top']);

    renameRole(cache, 'role-source-slot-2', 'male');
    setIdentity(cache, 'role-source-slot-2', 'male');
    removeTerms(cache, 'role-source-slot-2', ['green glass bottle', 'pussy insertion']);
  });

  patchFile('script-tamao-01-7b057e8a47e5be5b.json', (cache) => {
    for (const roleId of [
      'role-commanding-presence',
      'role-from-girl-s-behind',
      'role-ugged-muscular-man',
      'role-source-slot-1',
      'role-source-slot-2',
    ]) {
      renameRole(cache, roleId, 'rugged muscular man');
      setIdentity(cache, roleId, 'rugged muscular man');
      removeTerms(cache, roleId, [
        'commanding presence',
        "from girl's behind",
        'ugged muscular man',
        'slot-1',
        'slot-2',
        "licking girl's cheek",
        "touch her crotch with own hand",
        "licking girl's crotch",
        'body pressing down',
        'lickng breasts',
        'assertive confidence',
        'assertive body language',
        "licking girl's pussy",
        'spread pussy with both hands',
      ]);
    }
  });

  patchAllCaches((cache) => {
    moveEverywhere(cache, 'cat ear panties', 'lower_clothing');
    moveEverywhere(cache, 'white panties', 'lower_clothing');
    moveEverywhere(cache, 'long twin tails', 'upper_body');
    moveEverywhere(cache, 'elbow gloves', 'upper_clothing');
    moveEverywhere(cache, 'toeless legwear', 'lower_clothing');
    removeEverywhere(cache, [
      'upper body out of water',
      'face down on sofa',
      'face of ecstasy',
      'eyes rolling back',
      'penis on ass',
      'stretching pussy',
      'licking pussy',
      'man fingering girl vagina from front',
      'cum nose',
      'breast out',
      'green glass bottle',
      'pussy insertion',
      'on top of girl',
    ]);
  });
}

function patchAllCaches(repair) {
  for (const fileName of fs.readdirSync(cacheDir).filter((name) => name.endsWith('.json'))) {
    patchFile(fileName, repair);
  }
}

function patchFile(fileName, repair) {
  const filePath = path.join(cacheDir, fileName);
  if (!fs.existsSync(filePath)) return;
  const before = fs.readFileSync(filePath, 'utf8');
  const cache = JSON.parse(before);
  repair(cache);
  refreshMappingSummaries(cache);
  const after = `${JSON.stringify(cache, null, 2)}\n`;
  if (after === before) return;
  backupCache(fileName, before);
  cache.updatedAt = new Date().toISOString();
  fs.writeFileSync(filePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
  changedCacheFiles.add(fileName);
}

function ensureRole(cache, spec) {
  let role = findRole(cache, spec.roleId);
  if (!role) {
    role = {
      source_role_id: spec.roleId,
      display_name: spec.displayName,
      raw_identity_tags: [],
      frame_indexes: [],
      appearances: [],
      stages: [],
    };
    cache.aiRoleExtraction.roles.push(role);
  }
  role.display_name = spec.displayName;
  addFrames(role, 'frame_indexes', spec.frames);
  ensureAppearance(role, spec.sourceId, spec.sourceKind, spec.frames);
  let stage = role.stages.find((item) => item.stage_id === 'stage-1');
  if (!stage) {
    stage = { stage_id: 'stage-1', label: 'Stage 1', frame_indexes: [] };
    role.stages.push(stage);
  }
  addFrames(stage, 'frame_indexes', spec.frames);
  stage.identity = spec.identity;
  stage.upper_body = spec.upperBody;
  stage.lower_body = spec.lowerBody;
  stage.upper_clothing = spec.upperClothing;
  stage.lower_clothing = spec.lowerClothing;
  stage.evidence_terms = splitTerms(
    [spec.identity, spec.upperBody, spec.lowerBody, spec.upperClothing, spec.lowerClothing]
      .filter(Boolean)
      .join(', '),
  );
  ensureAssembly(cache, spec.roleId, spec.displayName, spec.sourceId, spec.sourceKind, spec.frames, {
    identity: spec.identity,
    upperBody: spec.upperBody,
    lowerBody: spec.lowerBody,
    upperClothing: spec.upperClothing,
    lowerClothing: spec.lowerClothing,
  });
  repairs.push({ file_name: cacheFileName(cache), role_id: spec.roleId, action: 'ensure_role' });
}

function ensureAssembly(cache, roleId, displayName, sourceId, sourceKind, frames, sourceParts) {
  cache.mapping ??= { roleAssemblies: [] };
  cache.mapping.roleAssemblies ??= [];
  let assembly = cache.mapping.roleAssemblies.find((item) => item.sourceRoleId === roleId);
  if (!assembly) {
    assembly = {
      sourceRoleId: roleId,
      displayLabel: displayName,
      sourceName: displayName,
      sourceAppearances: [],
      stages: [],
    };
    cache.mapping.roleAssemblies.push(assembly);
  }
  assembly.displayLabel = displayName;
  assembly.sourceName = displayName;
  let appearance = assembly.sourceAppearances.find((item) => item.sourceId === sourceId);
  if (!appearance) {
    appearance = { sourceId, sourceKind, frameIndexes: [] };
    assembly.sourceAppearances.push(appearance);
  }
  addFrames(appearance, 'frameIndexes', frames);
  let stage = assembly.stages.find((item) => item.id === 'stage-1');
  if (!stage) {
    stage = { id: 'stage-1', label: 'Stage 1', frameIndexes: [], sourceParts: {} };
    assembly.stages.push(stage);
  }
  addFrames(stage, 'frameIndexes', frames);
  stage.sourceParts = compactSourceParts(sourceParts);
  stage.sourceSummary = sourceSummary(stage.sourceParts);
}

function renameRole(cache, roleId, displayName) {
  const role = findRole(cache, roleId);
  if (role) role.display_name = displayName;
  const assembly = findAssembly(cache, roleId);
  if (assembly) {
    assembly.displayLabel = displayName;
    assembly.sourceName = displayName;
  }
  repairs.push({ file_name: cacheFileName(cache), role_id: roleId, action: 'rename', display_name: displayName });
}

function setIdentity(cache, roleId, identity) {
  const role = findRole(cache, roleId);
  for (const stage of role?.stages ?? []) stage.identity = identity;
  const assembly = findAssembly(cache, roleId);
  for (const stage of assembly?.stages ?? []) {
    stage.sourceParts ??= {};
    stage.sourceParts.identity = identity;
  }
}

function addFramesToRole(cache, roleId, frames, { sourceId, sourceKind, stageId }) {
  const role = findRole(cache, roleId);
  if (!role) return;
  addFrames(role, 'frame_indexes', frames);
  ensureAppearance(role, sourceId, sourceKind, frames);
  const stage = role.stages.find((item) => item.stage_id === stageId) ?? role.stages[0];
  if (stage) addFrames(stage, 'frame_indexes', frames);
  const assembly = findAssembly(cache, roleId);
  if (assembly) {
    let appearance = assembly.sourceAppearances.find((item) => item.sourceId === sourceId);
    if (!appearance) {
      appearance = { sourceId, sourceKind, frameIndexes: [] };
      assembly.sourceAppearances.push(appearance);
    }
    addFrames(appearance, 'frameIndexes', frames);
    const mappingStage = assembly.stages.find((item) => item.id === stageId) ?? assembly.stages[0];
    if (mappingStage) addFrames(mappingStage, 'frameIndexes', frames);
  }
  repairs.push({ file_name: cacheFileName(cache), role_id: roleId, action: 'add_frames', frames });
}

function removeRole(cache, roleId) {
  const beforeRoles = cache.aiRoleExtraction.roles.length;
  cache.aiRoleExtraction.roles = cache.aiRoleExtraction.roles.filter(
    (role) => role.source_role_id !== roleId,
  );
  if (cache.mapping?.roleAssemblies) {
    cache.mapping.roleAssemblies = cache.mapping.roleAssemblies.filter(
      (assembly) => assembly.sourceRoleId !== roleId,
    );
  }
  if (cache.aiRoleExtraction.roles.length !== beforeRoles) {
    repairs.push({ file_name: cacheFileName(cache), role_id: roleId, action: 'remove_empty_scene_role' });
  }
}

function moveEverywhere(cache, term, targetField) {
  for (const role of cache.aiRoleExtraction?.roles ?? []) {
    for (const stage of role.stages ?? []) {
      for (const field of ['identity', 'upper_body', 'lower_body', 'upper_clothing', 'lower_clothing']) {
        if (field === targetField) continue;
        moveTermInStage(stage, field, targetField, term);
      }
    }
  }
  for (const assembly of cache.mapping?.roleAssemblies ?? []) {
    for (const stage of assembly.stages ?? []) {
      for (const field of ['identity', 'upperBody', 'lowerBody', 'upperClothing', 'lowerClothing']) {
        const mappingTarget = toMappingField(targetField);
        if (field === mappingTarget) continue;
        moveTermInSourceParts(stage, field, mappingTarget, term);
      }
    }
  }
}

function removeEverywhere(cache, terms) {
  for (const role of cache.aiRoleExtraction?.roles ?? []) {
    for (const stage of role.stages ?? []) removeTermsFromStage(stage, terms);
  }
  for (const assembly of cache.mapping?.roleAssemblies ?? []) {
    for (const stage of assembly.stages ?? []) removeTermsFromSourceParts(stage, terms);
  }
}

function moveTerm(cache, roleId, fromField, toField, term) {
  const role = findRole(cache, roleId);
  for (const stage of role?.stages ?? []) moveTermInStage(stage, fromField, toField, term);
  const assembly = findAssembly(cache, roleId);
  for (const stage of assembly?.stages ?? []) {
    moveTermInSourceParts(stage, toMappingField(fromField), toMappingField(toField), term);
  }
}

function removeTerms(cache, roleId, terms) {
  const role = findRole(cache, roleId);
  for (const stage of role?.stages ?? []) removeTermsFromStage(stage, terms);
  const assembly = findAssembly(cache, roleId);
  for (const stage of assembly?.stages ?? []) removeTermsFromSourceParts(stage, terms);
}

function moveTermInStage(stage, fromField, toField, term) {
  if (!stage) return;
  const removed = removeTermValue(stage[fromField], term);
  if (!removed.changed) return;
  stage[fromField] = removed.value;
  stage[toField] = addTermValue(stage[toField], cleanedWeightTerm(term));
}

function moveTermInSourceParts(stage, fromField, toField, term) {
  if (!stage?.sourceParts) return;
  const removed = removeTermValue(stage.sourceParts[fromField], term);
  if (!removed.changed) return;
  stage.sourceParts[fromField] = removed.value;
  stage.sourceParts[toField] = addTermValue(stage.sourceParts[toField], cleanedWeightTerm(term));
}

function removeTermsFromStage(stage, terms) {
  for (const field of ['identity', 'upper_body', 'lower_body', 'upper_clothing', 'lower_clothing']) {
    for (const term of terms) stage[field] = removeTermValue(stage[field], term).value;
  }
  if (Array.isArray(stage.evidence_terms)) {
    const removeKeys = new Set(terms.map(normalizedTagKey));
    stage.evidence_terms = stage.evidence_terms.filter(
      (term) => !removeKeys.has(normalizedTagKey(term)),
    );
  }
}

function removeTermsFromSourceParts(stage, terms) {
  if (!stage?.sourceParts) return;
  for (const field of ['identity', 'upperBody', 'lowerBody', 'upperClothing', 'lowerClothing']) {
    for (const term of terms) {
      stage.sourceParts[field] = removeTermValue(stage.sourceParts[field], term).value;
    }
  }
}

function refreshMappingSummaries(cache) {
  for (const assembly of cache.mapping?.roleAssemblies ?? []) {
    for (const stage of assembly.stages ?? []) {
      stage.sourceParts = compactSourceParts(stage.sourceParts ?? {});
      stage.sourceSummary = sourceSummary(stage.sourceParts);
    }
  }
}

function ensureAppearance(role, sourceId, sourceKind, frames) {
  let appearance = role.appearances.find((item) => item.source_id === sourceId);
  if (!appearance) {
    appearance = { source_id: sourceId, source_kind: sourceKind, frame_indexes: [] };
    role.appearances.push(appearance);
  }
  addFrames(appearance, 'frame_indexes', frames);
}

function findRole(cache, roleId) {
  return (cache.aiRoleExtraction?.roles ?? []).find((role) => role.source_role_id === roleId);
}

function findAssembly(cache, roleId) {
  return (cache.mapping?.roleAssemblies ?? []).find((assembly) => assembly.sourceRoleId === roleId);
}

function addFrames(object, key, frames) {
  object[key] = [...new Set([...(object[key] ?? []), ...frames])].sort((a, b) => a - b);
}

function removeTermValue(value, term) {
  const target = normalizedTagKey(term);
  const before = splitTerms(value);
  const after = before.filter((item) => normalizedTagKey(item) !== target);
  return { changed: after.length !== before.length, value: after.join(', ') };
}

function addTermValue(value, term) {
  const terms = splitTerms(value);
  const key = normalizedTagKey(term);
  if (!terms.some((item) => normalizedTagKey(item) === key)) terms.push(term);
  return terms.join(', ');
}

function splitTerms(value) {
  return String(value ?? '')
    .split(',')
    .map((term) => term.trim())
    .filter(Boolean);
}

function cleanedWeightTerm(term) {
  return String(term)
    .replace(/\b-?\d+(?:\.\d+)?::/g, '')
    .replace(/::/g, '')
    .replace(/\|/g, '')
    .trim();
}

function normalizedTagKey(value) {
  return cleanedWeightTerm(value)
    .toLowerCase()
    .replace(/[_-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function toMappingField(field) {
  return {
    identity: 'identity',
    upper_body: 'upperBody',
    lower_body: 'lowerBody',
    upper_clothing: 'upperClothing',
    lower_clothing: 'lowerClothing',
  }[field] ?? field;
}

function compactSourceParts(parts) {
  const compacted = {};
  for (const [key, value] of Object.entries(parts ?? {})) {
    if (String(value ?? '').trim()) compacted[key] = String(value).trim();
  }
  return compacted;
}

function sourceSummary(sourceParts) {
  return ['identity', 'upperBody', 'lowerBody', 'upperClothing', 'lowerClothing']
    .map((key) => sourceParts?.[key])
    .filter((value) => String(value ?? '').trim())
    .join(', ');
}

function backupCache(fileName, contents) {
  const target = path.join(backupDir, 'cache', fileName);
  if (fs.existsSync(target)) return;
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, contents, 'utf8');
}

function cacheFileName(cache) {
  return `${cache.scriptId ?? 'unknown'}.json`;
}

function timestamp() {
  const now = new Date();
  const pad = (value) => String(value).padStart(2, '0');
  return `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}_${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
}
