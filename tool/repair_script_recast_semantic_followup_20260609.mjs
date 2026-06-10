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
const backupDir = path.join('build', 'script_recast_semantic_followup_backup_20260609');

const changedFiles = new Set();
const quarantinedFiles = [];
const repairs = [];
const stageFields = ['identity', 'upper_body', 'lower_body', 'upper_clothing', 'lower_clothing'];
const mappingFields = ['identity', 'upperBody', 'lowerBody', 'upperClothing', 'lowerClothing'];

if (!fs.existsSync(cacheDir)) throw new Error(`Missing cache dir: ${cacheDir}`);

quarantineOutOfScopeCaches();
patchIdentityPollution();
patchSlotPlaceholders();
patchBaseOnlyMissingRoles();
patchTyposAndFieldMoves();

console.log(
  JSON.stringify(
    {
      cache_dir: cacheDir,
      backup_dir: path.resolve(backupDir),
      quarantined_files: quarantinedFiles,
      changed_files: [...changedFiles].sort(),
      repair_count: repairs.length,
      repairs,
    },
    null,
    2,
  ),
);

function patchIdentityPollution() {
  removeIdentityTerms('script-1-407f193d94765cc4.json', 'role-artoria-caster-fate', [
    '3man',
    'man raising knife',
    'hold down girl',
    'surround girl',
  ]);
  moveIdentityTerms('script-1-407f193d94765cc4.json', 'role-artoria-caster-fate', [
    'ahoge',
    'sidelocks',
  ], 'upper_body');
  moveIdentityTerms('script-1-8d66ca375471af19.json', 'role-aesc-the-savior-fate', [
    'high ponytail',
  ], 'upper_body');
  moveIdentityTerms('script-1-fdc34df71c7933c2.json', 'role-justyna-black-survival', [
    'star-shaped pupils',
  ], 'upper_body');
  removeIdentityTerms('script-12bdf2c8b025a229.json', 'role-alina-clover', [
    'focus girl',
  ]);
  moveIdentityTerms('script-13a569c72e90e27e.json', 'role-saren-princess-connect', [
    'ponytail',
  ], 'upper_body');
  removeIdentityTerms('script-13a569c72e90e27e.json', 'role-muscular-male', [
    'male smile',
  ]);
  appendRoleTerms('script-13a569c72e90e27e.json', 'role-muscular-male', 'upper_body', [
    'male smile',
  ]);
  moveIdentityTerms('script-185ea8bcd72046d2.json', 'role-rosa-arknights', [
    'dot pupils',
  ], 'upper_body');
  removeIdentityTerms('script-185ea8bcd72046d2.json', 'role-rosa-arknights', [
    'sleep on chair',
  ]);
  removeIdentityTerms('script-185ea8bcd72046d2.json', 'role-zima-arknights', [
    'laughing another girl',
  ]);
  removeIdentityTerms('script-185ea8bcd72046d2.json', 'role-gavial-arknights', [
    'back against chair back',
  ]);
  removeIdentityTerms('script-18ef6b66df182296.json', 'role-multiple-boys', [
    'surrounding girl',
  ]);
  removeIdentityTerms('script-1f4b19db25637daf.json', 'role-muscular-male', [
    'male smile',
  ]);
  appendRoleTerms('script-1f4b19db25637daf.json', 'role-muscular-male', 'upper_body', [
    'male smile',
  ]);
  removeIdentityTerms('script-1f4b19db25637daf.json', 'role-fat-man', [
    'male smile',
  ]);
  appendRoleTerms('script-1f4b19db25637daf.json', 'role-fat-man', 'upper_body', [
    'male smile',
  ]);
  removeIdentityTerms('script-2705cf452a942ba2.json', 'role-yakushiji-saaya-precure', [
    'Man in school uniform',
  ]);
  removeIdentityTerms('script-2c59a611b096cd3d.json', 'role-fat-man', [
    "girl's chin lift",
  ]);
  removeIdentityTerms('script-2c59a611b096cd3d.json', 'role-multiple-fat-man', [
    "licking girl's cheek",
  ]);
  removeIdentityTerms('script-2c59a611b096cd3d.json', 'role-multiple-older-men', [
    "licking girl's cheek",
  ]);
  removeEverywhereTerms('script-2c59a611b096cd3d.json', 'role-fat-man', [
    'close face-to-face distance',
    'hand under chin',
    'assertive confidence',
  ]);
  removeEverywhereTerms('script-2c59a611b096cd3d.json', 'role-multiple-fat-man', [
    'assertive confidence',
  ]);
  removeIdentityTerms('script-2d4a055edc906afd.json', 'role-doodle-sensei-blue-archive', [
    'spoken mari (blue archive)',
  ]);
  removeIdentityTerms('script-3-fe65a5034ff2722e.json', 'role-lyn-fire-emblem', [
    'boy behind girl',
  ]);
  moveIdentityTerms('script-5322f76cafe408a0.json', 'role-suzuna-princess-connect', [
    'upper teeth only',
  ], 'upper_body');
  moveIdentityTerms('script-54909c2f67b8652b.json', 'role-mizuhara-chizuru', [
    ':nose blush',
    'nose blush',
  ], 'upper_body');
  moveIdentityTerms('script-561fee3678967f25.json', 'role-tokoyami-towa-jirai-kei', [
    'twintails',
  ], 'upper_body');
  removeIdentityTerms('script-6c7dcacbac10b78d.json', 'role-hakui-koyori', [
    'faceless male',
    'man dominant',
    'multiple faceless males',
    'submissive girl',
  ]);
  moveIdentityTerms('script-763e96e36e6eefa2.json', 'role-natsuiro-matsuri-1st-costume', [
    'glaring|tears',
  ], 'upper_body', ['glaring', 'tears']);
  removeEverywhereTerms('script-763e96e36e6eefa2.json', 'role-natsuiro-matsuri-1st-costume', [
    'glaring',
    'tears',
  ]);
  removeIdentityTermFromAllCaches('focus girl');
  removeIdentityTerms('script-7f417466984e264a.json', 'role-boy-man', [
    'creeping up boy',
    'gray scarf boy',
  ]);
  appendRoleTerms('script-7f417466984e264a.json', 'role-boy-man', 'upper_clothing', [
    'gray scarf',
  ]);
  replaceDisplayAndIdentity('script-7f417466984e264a.json', 'role-boy-man', {
    displayName: 'faceless male',
    identity: 'boy, man, faceless male, human',
  });
  removeIdentityTerms('script-792bacf20c7c1436.json', 'role-ibuki-blue-archive', [
    'boy',
  ], { stageIds: ['stage-2'] });
  moveIdentityTerms('script-8894511fe484b060.json', 'role-ganyu-genshin-impact', [
    'clench teeth',
  ], 'upper_body');
  removeIdentityTerms('script-8b340ffd967e661f.json', 'role-wakamo-blue-archive', [
    'spoken doodle sensei (blue archive)',
  ]);
  removeIdentityTerms('script-8b340ffd967e661f.json', 'role-sensei-blue-archive', [
    'girl',
    'male smile',
  ]);
  appendRoleTerms('script-8b340ffd967e661f.json', 'role-sensei-blue-archive', 'upper_body', [
    'male smile',
  ]);
  removeIdentityTerms('script-4e79c39083c9c88d.json', 'role-pecorine-summer-princess-connect', [
    'boy',
  ]);
  removeIdentityTerms('script-5806256bfb56f0fb.json', 'role-nahida-genshin-impact', [
    '1boy',
    'aether (genshin impact)',
    'young boy',
  ]);
}

function patchSlotPlaceholders() {
  replaceDisplayAndIdentity('script-341cc96322ea7cdc.json', 'role-source-slot-0', {
    displayName: 'amamiya kokoro (1st costume)',
    identity: 'amamiya kokoro (1st costume)',
  });
  moveTerm('script-341cc96322ea7cdc.json', 'role-source-slot-0', 'upper_clothing', 'identity', [
    'amamiya kokoro (1st costume)',
  ]);
  replaceDisplayAndIdentity('script-341cc96322ea7cdc.json', 'role-source-slot-1', {
    displayName: 'boy',
    identity: 'boy',
  });
  replaceDisplayAndIdentity('script-2p-d4aeb3f3a7f6ab91.json', 'role-source-slot-1', {
    displayName: 'boy',
    identity: 'boy',
  });
  replaceDisplayAndIdentity('script-3b2edfc5bb9ab592.json', 'role-source-slot-1', {
    displayName: 'boy',
    identity: 'boy',
  });
  replaceDisplayAndIdentity('script-3f6fb7fa51b5cbb3.json', 'role-source-slot-1', {
    displayName: 'boy',
    identity: 'boy',
  });
  replaceDisplayAndIdentity('script-54a71b8d38654f96.json', 'role-source-slot-1', {
    displayName: 'boy',
    identity: 'boy',
  });
  replaceDisplayAndIdentity('script-561fee3678967f25.json', 'role-source-slot-1', {
    displayName: 'boy',
    identity: 'boy',
  });
  replaceDisplayAndIdentity('script-44238bc1c058b6a5.json', 'role-source-slot-0', {
    displayName: 'bathroom scene',
    identity: '',
  });
  replaceDisplayAndIdentity('script-3a94b5f09224185a.json', 'role-source-slot-1', {
    displayName: 'giant orc',
    identity: 'giant orc',
  });
  replaceDisplayAndIdentity('script-3a94b5f09224185a.json', 'role-source-slot-2', {
    displayName: 'giant orc',
    identity: 'giant orc',
  });
}

function patchBaseOnlyMissingRoles() {
  ensureRole('script-2705cf452a942ba2.json', {
    roleId: 'role-man-in-school-uniform',
    displayName: 'man in school uniform',
    frames: range(9, 63),
    identity: 'man, man in school uniform',
    upperClothing: 'school uniform',
  });
  ensureRole('script-6c7dcacbac10b78d.json', {
    roleId: 'role-faceless-male',
    displayName: 'faceless male',
    frames: range(43, 62),
    identity: 'boy, faceless male',
  });
  ensureRole('script-6c7dcacbac10b78d.json', {
    roleId: 'role-multiple-faceless-males',
    displayName: 'multiple faceless males',
    frames: range(63, 80),
    identity: 'multiple boys, faceless male, multiple faceless males',
  });
  ensureRole('script-5806256bfb56f0fb.json', {
    roleId: 'role-aether-genshin-impact',
    displayName: 'aether (genshin impact)',
    frames: range(2, 11),
    identity: '1boy, aether (genshin impact), young boy',
  });
}

function patchTyposAndFieldMoves() {
  renameRoleId('script-3c2914435cd84a5c.json', 'role-musclar-male', 'role-muscular-male');
  replaceDisplayAndIdentity('script-3c2914435cd84a5c.json', 'role-muscular-male', {
    displayName: 'muscular male',
    identity: 'boy, faceless male, male smile, muscular male',
  });
  replaceTermEverywhere('script-3c2914435cd84a5c.json', 'faceless mald', 'faceless male');
  replaceTermEverywhere('script-3c2914435cd84a5c.json', 'musclar male', 'muscular male');

  replaceDisplayAndIdentity('script-54909c2f67b8652b.json', 'role-faceless-man', {
    displayName: 'faceless man',
    identity: 'boy, faceless man',
  });
  replaceDisplayAndIdentity('script-54909c2f67b8652b.json', 'role-boy', {
    displayName: 'boy',
    identity: 'boy',
  });
  replaceTermEverywhere('script-54909c2f67b8652b.json', 'faceless man:', 'faceless man');
  replaceTermEverywhere('script-54909c2f67b8652b.json', 'boy :', 'boy');
  splitLowerClothingTerm(
    'script-54909c2f67b8652b.json',
    'role-mizuhara-chizuru',
    'white skirt::red ribbon',
    'white skirt',
    'red ribbon',
  );

  moveTerm('script-9-15-vivian-e378f3268754f0a8.json', 'role-dark-skinned-male', 'upper_body', 'identity', [
    'faceless',
  ], ['faceless male']);
  appendRoleTerms('script-9-15-vivian-e378f3268754f0a8.json', 'role-dark-skinned-male', 'identity', [
    'dark-skinned male',
  ]);
  moveTerm('script-9-2-ruan-mei-f7d1cdc0f1f3f826.json', 'role-dark-skinned-male', 'upper_body', 'identity', [
    'faceless',
  ], ['faceless male']);
  appendRoleTerms('script-9-2-ruan-mei-f7d1cdc0f1f3f826.json', 'role-dark-skinned-male', 'identity', [
    'dark-skinned male',
  ]);
}

function quarantineOutOfScopeCaches() {
  const expectedRoot = normalizePath('E:/NAI\u7684\u811a\u672c\u7fa4/\u4f5c\u54c1\u96c6');
  const quarantineDir = path.join(backupDir, 'quarantine');
  for (const fileName of [
    'script-2-e69c8f5b21c9790b.json',
    'script-4b52a5bc143eb5fa.json',
  ]) {
    const filePath = path.join(cacheDir, fileName);
    if (!fs.existsSync(filePath)) continue;
    const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    const sourceRootPath = String(cache.sourceRootPath ?? '');
    if (normalizePath(sourceRootPath).startsWith(expectedRoot)) continue;
    const before = fs.readFileSync(filePath, 'utf8');
    backupCache(fileName, before);
    fs.mkdirSync(quarantineDir, { recursive: true });
    fs.writeFileSync(path.join(quarantineDir, fileName), before, 'utf8');
    fs.unlinkSync(filePath);
    quarantinedFiles.push({
      file_name: fileName,
      script_name: String(cache.scriptName ?? ''),
      source_root_path: sourceRootPath,
      reason: 'source_root_outside_requested_E_drive_source_root',
    });
  }
}

function removeIdentityTerms(fileName, roleId, terms, options = {}) {
  patchFile(fileName, (cache) => {
    const before = JSON.stringify(cache);
    forEachRoleStage(cache, roleId, options.stageIds, ({ roleStage, mappingStage }) => {
      roleStage.identity = removeTerms(roleStage.identity, terms);
      if (mappingStage?.sourceParts) {
        mappingStage.sourceParts.identity = removeTerms(mappingStage.sourceParts.identity, terms);
      }
    });
    if (JSON.stringify(cache) !== before) {
      repairs.push({ file_name: fileName, action: 'remove_identity_terms', role_id: roleId, terms });
    }
  });
}

function removeEverywhereTerms(fileName, roleId, terms) {
  patchFile(fileName, (cache) => {
    const before = JSON.stringify(cache);
    forEachRoleStage(cache, roleId, null, ({ roleStage, mappingStage }) => {
      for (const field of stageFields) roleStage[field] = removeTerms(roleStage[field], terms);
      if (mappingStage?.sourceParts) {
        for (const field of mappingFields) {
          mappingStage.sourceParts[field] = removeTerms(mappingStage.sourceParts[field], terms);
        }
      }
    });
    if (JSON.stringify(cache) !== before) {
      repairs.push({ file_name: fileName, action: 'remove_terms', role_id: roleId, terms });
    }
  });
}

function removeIdentityTermFromAllCaches(term) {
  for (const fileName of fs.readdirSync(cacheDir).filter((file) => file.endsWith('.json'))) {
    patchFile(fileName, (cache) => {
      const before = JSON.stringify(cache);
      for (const role of roles(cache)) {
        for (const stage of role.stages ?? []) {
          stage.identity = removeTerms(stage.identity, [term]);
        }
      }
      for (const assembly of assemblies(cache)) {
        for (const stage of assembly.stages ?? []) {
          if (!stage.sourceParts) continue;
          stage.sourceParts.identity = removeTerms(stage.sourceParts.identity, [term]);
        }
      }
      if (JSON.stringify(cache) !== before) {
        repairs.push({ file_name: fileName, action: 'remove_global_identity_term', term });
      }
    });
  }
}

function moveIdentityTerms(fileName, roleId, terms, targetField, replacementTerms = terms) {
  moveTerm(fileName, roleId, 'identity', targetField, terms, replacementTerms);
}

function moveTerm(fileName, roleId, fromField, targetField, terms, replacementTerms = terms) {
  patchFile(fileName, (cache) => {
    const before = JSON.stringify(cache);
    forEachRoleStage(cache, roleId, null, ({ roleStage, mappingStage }) => {
      let moved = false;
      for (const term of terms) {
        const result = removeTermValue(roleStage[fromField], term);
        roleStage[fromField] = result.value;
        moved ||= result.changed;
      }
      if (moved) {
        roleStage[targetField] = appendTerms(roleStage[targetField], replacementTerms);
      }
      if (mappingStage?.sourceParts) {
        const sourceFrom = toMappingField(fromField);
        const sourceTarget = toMappingField(targetField);
        let mappingMoved = false;
        for (const term of terms) {
          const result = removeTermValue(mappingStage.sourceParts[sourceFrom], term);
          mappingStage.sourceParts[sourceFrom] = result.value;
          mappingMoved ||= result.changed;
        }
        if (mappingMoved) {
          mappingStage.sourceParts[sourceTarget] = appendTerms(
            mappingStage.sourceParts[sourceTarget],
            replacementTerms,
          );
        }
      }
    });
    if (JSON.stringify(cache) !== before) {
      repairs.push({ file_name: fileName, action: 'move_terms', role_id: roleId, from: fromField, to: targetField, terms });
    }
  });
}

function appendRoleTerms(fileName, roleId, field, terms) {
  patchFile(fileName, (cache) => {
    const before = JSON.stringify(cache);
    forEachRoleStage(cache, roleId, null, ({ roleStage, mappingStage }) => {
      roleStage[field] = appendTerms(roleStage[field], terms);
      if (mappingStage?.sourceParts) {
        mappingStage.sourceParts[toMappingField(field)] = appendTerms(
          mappingStage.sourceParts[toMappingField(field)],
          terms,
        );
      }
    });
    if (JSON.stringify(cache) !== before) {
      repairs.push({ file_name: fileName, action: 'append_terms', role_id: roleId, field, terms });
    }
  });
}

function replaceDisplayAndIdentity(fileName, roleId, { displayName, identity }) {
  patchFile(fileName, (cache) => {
    const before = JSON.stringify(cache);
    const role = findRole(cache, roleId);
    if (role && displayName != null) role.display_name = displayName;
    forEachRoleStage(cache, roleId, null, ({ roleStage, mappingStage }) => {
      if (identity != null) roleStage.identity = identity;
      if (mappingStage?.sourceParts && identity != null) mappingStage.sourceParts.identity = identity;
    });
    const assembly = findAssembly(cache, roleId);
    if (assembly && displayName != null) {
      assembly.displayLabel = displayName;
      assembly.sourceName = displayName;
    }
    if (JSON.stringify(cache) !== before) {
      repairs.push({ file_name: fileName, action: 'replace_display_identity', role_id: roleId, displayName, identity });
    }
  });
}

function ensureRole(fileName, spec) {
  patchFile(fileName, (cache) => {
    const before = JSON.stringify(cache);
    cache.aiRoleExtraction ??= { status: 'ready', roles: [] };
    cache.aiRoleExtraction.roles ??= [];
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
    ensureAppearance(role, 'base', 'base', spec.frames);
    let stage = role.stages.find((item) => item.stage_id === 'stage-1');
    if (!stage) {
      stage = { stage_id: 'stage-1', label: 'Stage 1', frame_indexes: [] };
      role.stages.push(stage);
    }
    addFrames(stage, 'frame_indexes', spec.frames);
    stage.identity = spec.identity ?? '';
    stage.upper_body = spec.upperBody ?? '';
    stage.lower_body = spec.lowerBody ?? '';
    stage.upper_clothing = spec.upperClothing ?? '';
    stage.lower_clothing = spec.lowerClothing ?? '';

    cache.mapping ??= { roleAssemblies: [] };
    cache.mapping.roleAssemblies ??= [];
    let assembly = findAssembly(cache, spec.roleId);
    if (!assembly) {
      assembly = {
        sourceRoleId: spec.roleId,
        displayLabel: spec.displayName,
        sourceName: spec.displayName,
        sourceAppearances: [],
        stages: [],
      };
      cache.mapping.roleAssemblies.push(assembly);
    }
    assembly.displayLabel = spec.displayName;
    assembly.sourceName = spec.displayName;
    ensureMappingAppearance(assembly, 'base', 'base', spec.frames);
    let mappingStage = assembly.stages.find((item) => item.id === 'stage-1');
    if (!mappingStage) {
      mappingStage = { id: 'stage-1', label: 'Stage 1', frameIndexes: [], sourceParts: {} };
      assembly.stages.push(mappingStage);
    }
    addFrames(mappingStage, 'frameIndexes', spec.frames);
    mappingStage.sourceParts = {
      identity: spec.identity ?? '',
      upperBody: spec.upperBody ?? '',
      lowerBody: spec.lowerBody ?? '',
      upperClothing: spec.upperClothing ?? '',
      lowerClothing: spec.lowerClothing ?? '',
    };
    if (JSON.stringify(cache) !== before) {
      repairs.push({ file_name: fileName, action: 'ensure_role', role_id: spec.roleId, frames: spec.frames });
    }
  });
}

function renameRoleId(fileName, fromRoleId, toRoleId) {
  patchFile(fileName, (cache) => {
    const before = JSON.stringify(cache);
    replaceExactStrings(cache, { [fromRoleId]: toRoleId });
    if (JSON.stringify(cache) !== before) {
      repairs.push({ file_name: fileName, action: 'rename_role_id', from: fromRoleId, to: toRoleId });
    }
  });
}

function replaceTermEverywhere(fileName, fromTerm, toTerm) {
  patchFile(fileName, (cache) => {
    const before = JSON.stringify(cache);
    for (const role of roles(cache)) {
      if (role.display_name && normalizedTagKey(role.display_name) === normalizedTagKey(fromTerm)) {
        role.display_name = toTerm;
      }
      for (const stage of role.stages ?? []) {
        for (const field of stageFields) {
          stage[field] = replaceTerm(stage[field], fromTerm, toTerm);
        }
      }
    }
    for (const assembly of assemblies(cache)) {
      if (assembly.displayLabel && normalizedTagKey(assembly.displayLabel) === normalizedTagKey(fromTerm)) {
        assembly.displayLabel = toTerm;
      }
      if (assembly.sourceName && normalizedTagKey(assembly.sourceName) === normalizedTagKey(fromTerm)) {
        assembly.sourceName = toTerm;
      }
      for (const stage of assembly.stages ?? []) {
        if (!stage.sourceParts) continue;
        for (const field of mappingFields) {
          stage.sourceParts[field] = replaceTerm(stage.sourceParts[field], fromTerm, toTerm);
        }
      }
    }
    if (JSON.stringify(cache) !== before) {
      repairs.push({ file_name: fileName, action: 'replace_term', from: fromTerm, to: toTerm });
    }
  });
}

function splitLowerClothingTerm(fileName, roleId, combined, lowerTerm, upperTerm) {
  patchFile(fileName, (cache) => {
    const before = JSON.stringify(cache);
    forEachRoleStage(cache, roleId, null, ({ roleStage, mappingStage }) => {
      roleStage.lower_clothing = replaceTerm(roleStage.lower_clothing, combined, lowerTerm);
      roleStage.upper_body = appendTerms(roleStage.upper_body, [upperTerm]);
      if (mappingStage?.sourceParts) {
        mappingStage.sourceParts.lowerClothing = replaceTerm(
          mappingStage.sourceParts.lowerClothing,
          combined,
          lowerTerm,
        );
        mappingStage.sourceParts.upperBody = appendTerms(mappingStage.sourceParts.upperBody, [upperTerm]);
      }
    });
    if (JSON.stringify(cache) !== before) {
      repairs.push({ file_name: fileName, action: 'split_lower_clothing_term', role_id: roleId, combined, lowerTerm, upperTerm });
    }
  });
}

function patchFile(fileName, patch) {
  const filePath = path.join(cacheDir, fileName);
  if (!fs.existsSync(filePath)) return;
  const before = fs.readFileSync(filePath, 'utf8');
  const cache = JSON.parse(before);
  patch(cache);
  refreshMappingSummaries(cache);
  const after = `${JSON.stringify(cache, null, 2)}\n`;
  if (after === before) return;
  backupCache(fileName, before);
  cache.updatedAt = new Date().toISOString();
  const finalText = `${JSON.stringify(cache, null, 2)}\n`;
  fs.writeFileSync(filePath, finalText, 'utf8');
  changedFiles.add(fileName);
}

function forEachRoleStage(cache, roleId, stageIds, callback) {
  const allowedStages = Array.isArray(stageIds) ? new Set(stageIds) : null;
  const role = findRole(cache, roleId);
  const assembly = findAssembly(cache, roleId);
  for (const roleStage of role?.stages ?? []) {
    if (allowedStages && !allowedStages.has(roleStage.stage_id)) continue;
    const mappingStage = (assembly?.stages ?? []).find((item) => item.id === roleStage.stage_id);
    callback({ roleStage, mappingStage });
  }
}

function findRole(cache, roleId) {
  return roles(cache).find((role) => role.source_role_id === roleId);
}

function findAssembly(cache, roleId) {
  return assemblies(cache).find((assembly) => assembly.sourceRoleId === roleId);
}

function roles(cache) {
  return Array.isArray(cache.aiRoleExtraction?.roles) ? cache.aiRoleExtraction.roles : [];
}

function assemblies(cache) {
  return Array.isArray(cache.mapping?.roleAssemblies) ? cache.mapping.roleAssemblies : [];
}

function ensureAppearance(role, sourceId, sourceKind, frames) {
  role.appearances ??= [];
  let appearance = role.appearances.find((item) => item.source_id === sourceId);
  if (!appearance) {
    appearance = { source_id: sourceId, source_kind: sourceKind, frame_indexes: [] };
    role.appearances.push(appearance);
  }
  addFrames(appearance, 'frame_indexes', frames);
}

function ensureMappingAppearance(assembly, sourceId, sourceKind, frames) {
  assembly.sourceAppearances ??= [];
  let appearance = assembly.sourceAppearances.find((item) => item.sourceId === sourceId);
  if (!appearance) {
    appearance = { sourceId, sourceKind, frameIndexes: [] };
    assembly.sourceAppearances.push(appearance);
  }
  addFrames(appearance, 'frameIndexes', frames);
}

function refreshMappingSummaries(cache) {
  for (const assembly of assemblies(cache)) {
    for (const stage of assembly.stages ?? []) {
      stage.sourceParts = compactSourceParts(stage.sourceParts ?? {});
      stage.sourceSummary = sourceSummary(stage.sourceParts);
    }
  }
}

function replaceExactStrings(value, renames) {
  if (Array.isArray(value)) {
    for (let index = 0; index < value.length; index += 1) {
      value[index] = replaceExactStrings(value[index], renames);
    }
    return value;
  }
  if (value && typeof value === 'object') {
    for (const key of Object.keys(value)) {
      value[key] = replaceExactStrings(value[key], renames);
    }
    return value;
  }
  if (typeof value === 'string' && renames[value]) return renames[value];
  return value;
}

function addFrames(object, key, frames) {
  object[key] = [...new Set([...(object[key] ?? []), ...frames])].sort((left, right) => left - right);
}

function appendTerms(value, terms) {
  const existing = splitTerms(value);
  const keys = new Set(existing.map(normalizedTagKey));
  for (const term of terms) {
    const cleaned = cleanedTerm(term);
    const key = normalizedTagKey(cleaned);
    if (!cleaned || keys.has(key)) continue;
    existing.push(cleaned);
    keys.add(key);
  }
  return existing.join(', ');
}

function removeTerms(value, terms) {
  const blocked = new Set(terms.map(normalizedTagKey));
  return splitTerms(value)
    .filter((term) => !blocked.has(normalizedTagKey(term)))
    .join(', ');
}

function removeTermValue(value, term) {
  const before = splitTerms(value);
  const after = before.filter((item) => normalizedTagKey(item) !== normalizedTagKey(term));
  return { changed: before.length !== after.length, value: after.join(', ') };
}

function replaceTerm(value, fromTerm, toTerm) {
  const target = normalizedTagKey(fromTerm);
  const terms = splitTerms(value).map((term) =>
    normalizedTagKey(term) === target ? cleanedTerm(toTerm) : term,
  );
  const output = [];
  const seen = new Set();
  for (const term of terms) {
    const key = normalizedTagKey(term);
    if (!term || seen.has(key)) continue;
    output.push(term);
    seen.add(key);
  }
  return output.join(', ');
}

function splitTerms(value) {
  return String(value ?? '')
    .split(',')
    .map((term) => term.trim())
    .filter(Boolean);
}

function normalizedTagKey(value) {
  return cleanedTerm(value)
    .toLowerCase()
    .replace(/[_-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function cleanedTerm(value) {
  return String(value ?? '')
    .replace(/\b-?\d+(?:\.\d+)?::/g, '')
    .replace(/::/g, '')
    .replace(/\|/g, ', ')
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
  const result = {};
  for (const field of mappingFields) {
    result[field] = String(parts?.[field] ?? '').trim();
  }
  return result;
}

function sourceSummary(sourceParts) {
  return mappingFields
    .map((key) => String(sourceParts?.[key] ?? '').trim())
    .filter(Boolean)
    .join(', ');
}

function backupCache(fileName, contents) {
  const target = path.join(backupDir, fileName);
  if (fs.existsSync(target)) return;
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, contents, 'utf8');
}

function normalizePath(value) {
  const normalized = String(value).replace(/\\/g, '/');
  return process.platform === 'win32' ? normalized.toLowerCase() : normalized;
}

function range(start, end) {
  return Array.from({ length: end - start + 1 }, (_, index) => start + index);
}
