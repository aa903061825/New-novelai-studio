import fs from 'node:fs';
import path from 'node:path';

const defaultCacheDir = path.join(
  process.env.APPDATA ?? '',
  'Novel Studio',
  'Novel Studio',
  'novel_studio',
  'script_recast',
  'cache',
);

const options = parseArgs(process.argv.slice(2));
const cacheDir = options.cacheDir ?? defaultCacheDir;
const backupDir =
  options.backupDir ?? path.join('build', 'script_recast_full_audit_backup_20260609');
const quarantineDir =
  options.quarantineDir ??
  path.join('build', 'script_recast_full_audit_quarantine_20260609');

if (!fs.existsSync(cacheDir)) {
  throw new Error(`Cache directory does not exist: ${cacheDir}`);
}

const changedFiles = new Set();
const quarantinedFiles = [];
const repairs = [];

quarantineOutOfScopeIdleCaches();
repairPngCache();
repairSemanticPseudoRoles();

console.log(
  JSON.stringify(
    {
      cache_dir: cacheDir,
      backup_dir: path.resolve(backupDir),
      quarantine_dir: path.resolve(quarantineDir),
      changed_files: [...changedFiles].sort(),
      quarantined_files: quarantinedFiles,
      repair_count: repairs.length,
      repairs,
    },
    null,
    2,
  ),
);

function quarantineOutOfScopeIdleCaches() {
  for (const fileName of [
    'script-2-e69c8f5b21c9790b.json',
    'script-4b52a5bc143eb5fa.json',
  ]) {
    const cachePath = path.join(cacheDir, fileName);
    if (!fs.existsSync(cachePath)) continue;
    const cache = loadCache(fileName);
    const status = stringValue(cache.aiRoleExtraction?.status);
    const roleCount = Array.isArray(cache.aiRoleExtraction?.roles)
      ? cache.aiRoleExtraction.roles.length
      : 0;
    if (status === 'ready' || roleCount > 0) {
      throw new Error(`${fileName}: refusing to quarantine non-idle cache`);
    }
    backupCache(fileName);
    fs.mkdirSync(quarantineDir, { recursive: true });
    fs.copyFileSync(cachePath, path.join(quarantineDir, fileName));
    fs.unlinkSync(cachePath);
    quarantinedFiles.push({
      file_name: fileName,
      script_name: stringValue(cache.scriptName),
      source_root_path: stringValue(cache.sourceRootPath),
      reason: 'source_root_outside_requested_E_drive_and_ai_idle',
    });
  }
}

function repairPngCache() {
  const fileName = 'script-png-a61dbf521d75908e.json';
  if (!fs.existsSync(path.join(cacheDir, fileName))) return;
  const cache = loadCache(fileName);

  const invalidFrames = {
    'role-fujita-kotone': [76, 222],
    'role-generic-boy-slot-1': [138],
    'role-muscular-male': [73, 96, 113, 119, 135, 147, 158, 170, 178, 181],
    'role-sagisawa-fumika': [141],
    'role-dark-skinned-male': [81],
  };
  for (const [roleId, frames] of Object.entries(invalidFrames)) {
    removeRoleFrames(cache, roleId, frames);
    repairs.push({ file_name: fileName, action: 'remove_invalid_png_slot_refs', role_id: roleId, frames });
  }

  const coverages = [
    ['role-fujita-kotone', 'slot-0', [75], 'stage-white-school-swimsuit', {
      label: 'white one-piece swimsuit / school swimsuit',
      identity: 'fujita kotone, girl, twin braids',
      upper_body: 'black bow, medium breasts',
      upper_clothing: 'white one-piece swimsuit, school swimsuit',
    }],
    ['role-fujita-kotone', 'slot-0', [224, 225], 'stage-1', null],
    ['role-muscular-male', 'slot-1', [72, 75, 88, 112, 118, 136, 157, 167, 177], 'stage-1', null],
    ['role-muscular-male', 'slot-2', [72, 220], 'stage-1', null],
    ['role-generic-boy-slot-1', 'slot-1', [131, 140], 'stage-1', null],
    ['role-sagisawa-fumika', 'slot-1', [146, 220, 224, 225], 'stage-1', null],
    ['role-producer-idolmaster', 'slot-2', [225], 'stage-1', null],
  ];
  for (const [roleId, slotId, frames, stageId, stageSeed] of coverages) {
    addRoleCoverage(cache, roleId, slotId, frames, stageId, stageSeed);
    repairs.push({ file_name: fileName, action: 'add_png_slot_coverage', role_id: roleId, slot_id: slotId, frames });
  }

  saveCache(fileName, cache);
}

function repairSemanticPseudoRoles() {
  mergeRoleInFile('script-1-53af23b23cebe3c9.json', 'role-kidnapping-girl', 'role-generic-boy');
  mergeRoleInFile('script-1-53af23b23cebe3c9.json', 'role-spanking-girl', 'role-generic-boy');
  mergeRoleInFile('script-1-53af23b23cebe3c9.json', 'role-showing-teeth', 'role-generic-girl');

  mergeRoleInFile(
    'script-1-7b6837c5c2cf3385.json',
    'role-tongue-out-shouting-clenched-teeth-puckered-lips',
    'role-generic-girl',
  );
  patchRole('script-1-7b6837c5c2cf3385.json', 'role-no-humans', (role) => {
    role.display_name = 'black crystallized monster';
    for (const stage of role.stages ?? []) {
      stage.identity = 'boy, black crystallized monster, giant male';
      stage.upper_body = appendTerms(stage.upper_body, [
        'green scars',
        'headless',
        'exoskeleton',
        'extra arms',
      ]);
    }
  });
  patchAssembly('script-1-7b6837c5c2cf3385.json', 'role-no-humans', (assembly) => {
    assembly.displayName = 'black crystallized monster';
    for (const stage of assembly.stages ?? []) {
      stage.sourceParts ??= {};
      stage.sourceParts.identity = 'boy, black crystallized monster, giant male';
      stage.sourceParts.upperBody = appendTerms(stage.sourceParts.upperBody, [
        'green scars',
        'headless',
        'exoskeleton',
        'extra arms',
      ]);
      stage.sourceSummary = sourceSummary(stage.sourceParts);
    }
  });

  patchRole('script-1-d7e07f11f22eaba5.json', 'role-no-abdomen', (role) => {
    role.display_name = 'boy';
    for (const stage of role.stages ?? []) {
      stage.identity = 'boy';
    }
  });
  patchAssembly('script-1-d7e07f11f22eaba5.json', 'role-no-abdomen', (assembly) => {
    assembly.displayName = 'boy';
    for (const stage of assembly.stages ?? []) {
      stage.sourceParts ??= {};
      stage.sourceParts.identity = 'boy';
      stage.sourceSummary = sourceSummary(stage.sourceParts);
    }
  });

  patchRole('script-11b1815651b79e76.json', 'role-year-2025', (role) => {
    role.display_name = 'greater lord rukkhadevata adult form';
    for (const stage of role.stages ?? []) {
      stage.identity = 'greater lord rukkhadevata adult form, girl, mature woman';
      stage.upper_body = '';
      stage.lower_body = '';
      stage.upper_clothing = '';
      stage.lower_clothing = '';
    }
  });
  patchAssembly('script-11b1815651b79e76.json', 'role-year-2025', (assembly) => {
    assembly.displayName = 'greater lord rukkhadevata adult form';
    for (const stage of assembly.stages ?? []) {
      stage.sourceParts ??= {};
      stage.sourceParts.identity = 'greater lord rukkhadevata adult form, girl, mature woman';
      stage.sourceParts.upperBody = '';
      stage.sourceParts.lowerBody = '';
      stage.sourceParts.upperClothing = '';
      stage.sourceParts.lowerClothing = '';
      stage.sourceSummary = sourceSummary(stage.sourceParts);
    }
  });

  mergeRoleInFile('script-16c202326485e8cb.json', 'role-reverse-fellatio', 'role-generic-boy');

  mergeRoleInFile('script-235527775cdf6547.json', 'role-penetrating-girl', 'role-faceless-male');
  mergeRoleInFile('script-235527775cdf6547.json', 'role-supporting-girl', 'role-faceless-male');
  mergeRoleInFile('script-235527775cdf6547.json', 'role-carrying-girl', 'role-faceless-male');
  mergeRoleInFile('script-235527775cdf6547.json', 'role-guiding-girl', 'role-faceless-male');
  mergeRoleInFile('script-235527775cdf6547.json', 'role-penetrating-1girl', 'role-faceless-male');
  patchRole('script-235527775cdf6547.json', 'role-faceless-male', (role) => {
    for (const stage of role.stages ?? []) {
      stage.identity = removeTerms(stage.identity, [
        'hugging 1 girl',
        "pulling down girl's bikini",
      ]);
    }
  });
  patchAssembly('script-235527775cdf6547.json', 'role-faceless-male', (assembly) => {
    for (const stage of assembly.stages ?? []) {
      if (!stage.sourceParts) continue;
      stage.sourceParts.identity = removeTerms(stage.sourceParts.identity, [
        'hugging 1 girl',
        "pulling down girl's bikini",
      ]);
      stage.sourceSummary = sourceSummary(stage.sourceParts);
    }
  });
  patchRole('script-235527775cdf6547.json', 'role-vanya-black-survival', (role) => {
    for (const stage of role.stages ?? []) {
      stage.identity = removeTerms(stage.identity, ['cheek pressed on surface']);
    }
  });
  patchAssembly('script-235527775cdf6547.json', 'role-vanya-black-survival', (assembly) => {
    for (const stage of assembly.stages ?? []) {
      if (!stage.sourceParts) continue;
      stage.sourceParts.identity = removeTerms(stage.sourceParts.identity, ['cheek pressed on surface']);
      stage.sourceSummary = sourceSummary(stage.sourceParts);
    }
  });

  patchRole('script-268ab0a5856036be.json', 'role-man-fingering-girl-vagina-from-front', (role) => {
    role.display_name = 'boy';
    for (const stage of role.stages ?? []) {
      stage.identity = 'boy';
    }
  });
  patchAssembly('script-268ab0a5856036be.json', 'role-man-fingering-girl-vagina-from-front', (assembly) => {
    assembly.displayName = 'boy';
    for (const stage of assembly.stages ?? []) {
      stage.sourceParts ??= {};
      stage.sourceParts.identity = 'boy';
      stage.sourceSummary = sourceSummary(stage.sourceParts);
    }
  });

  mergeRoleInFile('script-3-1c141c744ee6df79.json', 'role-closedeyes', 'role-source-slot-0');
  patchRole('script-3-1c141c744ee6df79.json', 'role-source-slot-0', (role) => {
    if (role.display_name === 'slot-0') role.display_name = 'girl';
    for (const stage of role.stages ?? []) {
      if (stage.identity === 'slot-0') stage.identity = 'girl';
    }
  });
  patchAssembly('script-3-1c141c744ee6df79.json', 'role-source-slot-0', (assembly) => {
    if (assembly.displayName === 'slot-0') assembly.displayName = 'girl';
    for (const stage of assembly.stages ?? []) {
      if (stage.sourceParts?.identity === 'slot-0') {
        stage.sourceParts.identity = 'girl';
        stage.sourceSummary = sourceSummary(stage.sourceParts);
      }
    }
  });

  patchRole('script-3-fe65a5034ff2722e.json', 'role-muscular-chest', (role) => {
    role.display_name = 'bandit';
    for (const stage of role.stages ?? []) {
      stage.identity = 'boy, bandit';
      stage.upper_body = appendTerms(
        removeTerms(stage.upper_body, ['carrying girl with both hands']),
        ['muscular', 'muscular chest'],
      );
    }
  });
  patchAssembly('script-3-fe65a5034ff2722e.json', 'role-muscular-chest', (assembly) => {
    assembly.displayName = 'bandit';
    for (const stage of assembly.stages ?? []) {
      stage.sourceParts ??= {};
      stage.sourceParts.identity = 'boy, bandit';
      stage.sourceParts.upperBody = appendTerms(
        removeTerms(stage.sourceParts.upperBody, ['carrying girl with both hands']),
        ['muscular', 'muscular chest'],
      );
      stage.sourceSummary = sourceSummary(stage.sourceParts);
    }
  });

  patchRole('script-44238bc1c058b6a5.json', 'role-shower-place', (role) => {
    role.display_name = 'boy';
    for (const stage of role.stages ?? []) {
      stage.identity = removeTerms(stage.identity, ['shower (place)']);
      stage.upper_body = removeTerms(stage.upper_body, ['drying hair']);
    }
  });
  patchAssembly('script-44238bc1c058b6a5.json', 'role-shower-place', (assembly) => {
    assembly.displayName = 'boy';
    for (const stage of assembly.stages ?? []) {
      if (!stage.sourceParts) continue;
      stage.sourceParts.identity = removeTerms(stage.sourceParts.identity, ['shower (place)']);
      stage.sourceParts.upperBody = removeTerms(stage.sourceParts.upperBody, ['drying hair']);
      stage.sourceSummary = sourceSummary(stage.sourceParts);
    }
  });
  for (const roleId of ['role-generic-1boy', 'role-faceless-male']) {
    patchRole('script-44238bc1c058b6a5.json', roleId, (role) => {
      for (const stage of role.stages ?? []) {
        if (hasTerm(stage.upper_clothing, 'jeans')) {
          stage.upper_clothing = removeTerms(stage.upper_clothing, ['jeans']);
          stage.lower_clothing = appendTerms(stage.lower_clothing, ['jeans']);
        }
      }
    });
    patchAssembly('script-44238bc1c058b6a5.json', roleId, (assembly) => {
      for (const stage of assembly.stages ?? []) {
        if (!stage.sourceParts) continue;
        if (hasTerm(stage.sourceParts.upperClothing, 'jeans')) {
          stage.sourceParts.upperClothing = removeTerms(stage.sourceParts.upperClothing, ['jeans']);
          stage.sourceParts.lowerClothing = appendTerms(stage.sourceParts.lowerClothing, ['jeans']);
          stage.sourceSummary = sourceSummary(stage.sourceParts);
        }
      }
    });
  }
  patchRole('script-44238bc1c058b6a5.json', 'role-white-shirtfaceless-male', (role) => {
    role.display_name = 'faceless male';
    for (const stage of role.stages ?? []) {
      stage.identity = '1boy, faceless male';
      stage.upper_clothing = appendTerms(removeTerms(stage.upper_clothing, ['jeans']), ['white shirt']);
      stage.lower_clothing = appendTerms(stage.lower_clothing, ['jeans']);
    }
  });
  patchAssembly('script-44238bc1c058b6a5.json', 'role-white-shirtfaceless-male', (assembly) => {
    assembly.displayName = 'faceless male';
    for (const stage of assembly.stages ?? []) {
      stage.sourceParts ??= {};
      stage.sourceParts.identity = '1boy, faceless male';
      stage.sourceParts.upperClothing = appendTerms(
        removeTerms(stage.sourceParts.upperClothing, ['jeans']),
        ['white shirt'],
      );
      stage.sourceParts.lowerClothing = appendTerms(stage.sourceParts.lowerClothing, ['jeans']);
      stage.sourceSummary = sourceSummary(stage.sourceParts);
    }
  });

  mergeRoleInFile(
    'script-70156ab221fa1b08.json',
    'role-surrounded-by-multiple-young-adult-man',
    'role-source-slot-1',
  );
  patchRole('script-70156ab221fa1b08.json', 'role-source-slot-1', (role) => {
    role.display_name = 'young adult man';
    for (const stage of role.stages ?? []) {
      stage.identity = 'young adult man';
      stage.upper_body = appendTerms(
        removeTerms(stage.upper_body, [
          'body out of frame',
          'casual charm',
          'cropped male body',
        ]),
        ['tanned skin', 'athletic build'],
      );
    }
  });
  patchAssembly('script-70156ab221fa1b08.json', 'role-source-slot-1', (assembly) => {
    assembly.displayName = 'young adult man';
    for (const stage of assembly.stages ?? []) {
      stage.sourceParts ??= {};
      stage.sourceParts.identity = 'young adult man';
      stage.sourceParts.upperBody = appendTerms(
        removeTerms(stage.sourceParts.upperBody, [
          'body out of frame',
          'casual charm',
          'cropped male body',
        ]),
        ['tanned skin', 'athletic build'],
      );
      stage.sourceSummary = sourceSummary(stage.sourceParts);
    }
  });

  patchRole('script-9-2-suzuran-aa5519380d114932.json', 'role-loli', (role) => {
    role.display_name = 'suzuran (spring praise) (arknights)';
    for (const stage of role.stages ?? []) {
      stage.identity = 'suzuran_(spring_praise)_(arknights), girl, loli, child';
    }
  });
  patchAssembly('script-9-2-suzuran-aa5519380d114932.json', 'role-loli', (assembly) => {
    assembly.displayName = 'suzuran (spring praise) (arknights)';
    for (const stage of assembly.stages ?? []) {
      stage.sourceParts ??= {};
      stage.sourceParts.identity = 'suzuran_(spring_praise)_(arknights), girl, loli, child';
      stage.sourceSummary = sourceSummary(stage.sourceParts);
    }
  });
}

function mergeRoleInFile(fileName, sourceRoleId, targetRoleId) {
  if (!fs.existsSync(path.join(cacheDir, fileName))) return;
  const cache = loadCache(fileName);
  const merged = mergeRole(cache, sourceRoleId, targetRoleId, fileName);
  if (merged) {
    repairs.push({ file_name: fileName, action: 'merge_pseudo_role', source_role_id: sourceRoleId, target_role_id: targetRoleId });
    saveCache(fileName, cache);
  }
}

function mergeRole(cache, sourceRoleId, targetRoleId, fileName) {
  const roles = cache.aiRoleExtraction?.roles ?? [];
  const source = roles.find((role) => role.source_role_id === sourceRoleId);
  const target = roles.find((role) => role.source_role_id === targetRoleId);
  if (!source) return false;
  if (!target) throw new Error(`${fileName}: missing target ${targetRoleId}`);

  addFrames(target, 'frame_indexes', source.frame_indexes ?? []);
  for (const sourceAppearance of source.appearances ?? []) {
    const targetAppearance = findOrCreateAppearance(target, sourceAppearance.source_id, sourceAppearance.source_kind);
    addFrames(targetAppearance, 'frame_indexes', sourceAppearance.frame_indexes ?? []);
  }
  const targetStage = firstStage(target);
  addFrames(targetStage, 'frame_indexes', source.frame_indexes ?? []);
  cache.aiRoleExtraction.roles = roles.filter((role) => role.source_role_id !== sourceRoleId);

  const assemblies = cache.mapping?.roleAssemblies ?? cache.mapping?.role_assemblies ?? [];
  const sourceAssembly = assemblies.find((assembly) => assemblyId(assembly) === sourceRoleId);
  const targetAssembly = assemblies.find((assembly) => assemblyId(assembly) === targetRoleId);
  if (sourceAssembly && targetAssembly) {
    for (const sourceAppearance of sourceAssembly.sourceAppearances ?? sourceAssembly.source_appearances ?? []) {
      const targetAppearance = findOrCreateMappingAppearance(
        targetAssembly,
        sourceAppearance.sourceId ?? sourceAppearance.source_id,
        sourceAppearance.sourceKind ?? sourceAppearance.source_kind,
      );
      addFrames(targetAppearance, 'frameIndexes', sourceAppearance.frameIndexes ?? sourceAppearance.frame_indexes ?? []);
    }
    addFrames(firstMappingStage(targetAssembly), 'frameIndexes', source.frame_indexes ?? []);
    if (cache.mapping?.roleAssemblies) {
      cache.mapping.roleAssemblies = assemblies.filter((assembly) => assemblyId(assembly) !== sourceRoleId);
    } else if (cache.mapping?.role_assemblies) {
      cache.mapping.role_assemblies = assemblies.filter((assembly) => assemblyId(assembly) !== sourceRoleId);
    }
  }
  return true;
}

function patchRole(fileName, roleId, patch) {
  if (!fs.existsSync(path.join(cacheDir, fileName))) return;
  const cache = loadCache(fileName);
  const role = findRole(cache, roleId);
  if (!role) return;
  const before = JSON.stringify(role);
  patch(role, cache);
  if (JSON.stringify(role) !== before) {
    repairs.push({ file_name: fileName, action: 'patch_role', role_id: roleId });
    saveCache(fileName, cache);
  }
}

function patchAssembly(fileName, roleId, patch) {
  if (!fs.existsSync(path.join(cacheDir, fileName))) return;
  const cache = loadCache(fileName);
  const assembly = findAssembly(cache, roleId);
  if (!assembly) return;
  const before = JSON.stringify(assembly);
  patch(assembly, cache);
  if (JSON.stringify(assembly) !== before) {
    repairs.push({ file_name: fileName, action: 'patch_mapping_assembly', role_id: roleId });
    saveCache(fileName, cache);
  }
}

function removeRoleFrames(cache, roleId, frames) {
  const role = findRole(cache, roleId);
  if (role) {
    role.frame_indexes = removeFrames(role.frame_indexes, frames);
    for (const appearance of role.appearances ?? []) {
      appearance.frame_indexes = removeFrames(appearance.frame_indexes, frames);
    }
    for (const stage of role.stages ?? []) {
      stage.frame_indexes = removeFrames(stage.frame_indexes, frames);
    }
  }
  const assembly = findAssembly(cache, roleId);
  if (assembly) {
    for (const appearance of assembly.sourceAppearances ?? assembly.source_appearances ?? []) {
      if (appearance.frameIndexes) appearance.frameIndexes = removeFrames(appearance.frameIndexes, frames);
      if (appearance.frame_indexes) appearance.frame_indexes = removeFrames(appearance.frame_indexes, frames);
    }
    for (const stage of assembly.stages ?? []) {
      if (stage.frameIndexes) stage.frameIndexes = removeFrames(stage.frameIndexes, frames);
      if (stage.frame_indexes) stage.frame_indexes = removeFrames(stage.frame_indexes, frames);
    }
  }
}

function addRoleCoverage(cache, roleId, slotId, frames, stageId, stageSeed) {
  const role = findRole(cache, roleId);
  if (!role) throw new Error(`missing role ${roleId}`);
  addFrames(role, 'frame_indexes', frames);
  const appearance = findOrCreateAppearance(role, slotId, 'slot');
  addFrames(appearance, 'frame_indexes', frames);
  const stage = findOrCreateStage(role, stageId, stageSeed);
  addFrames(stage, 'frame_indexes', frames);

  const assembly = findAssembly(cache, roleId);
  if (!assembly) return;
  const mappingAppearance = findOrCreateMappingAppearance(assembly, slotId, 'slot');
  addFrames(mappingAppearance, 'frameIndexes', frames);
  const mappingStage = findOrCreateMappingStage(assembly, stageId, stageSeed);
  addFrames(mappingStage, 'frameIndexes', frames);
}

function findOrCreateAppearance(role, sourceId, sourceKind = 'slot') {
  role.appearances ??= [];
  let appearance = role.appearances.find((item) => item.source_id === sourceId);
  if (!appearance) {
    appearance = { source_id: sourceId, source_kind: sourceKind, frame_indexes: [] };
    role.appearances.push(appearance);
  }
  return appearance;
}

function findOrCreateMappingAppearance(assembly, sourceId, sourceKind = 'slot') {
  assembly.sourceAppearances ??= [];
  let appearance = assembly.sourceAppearances.find((item) => item.sourceId === sourceId);
  if (!appearance) {
    appearance = { sourceId, sourceKind, frameIndexes: [] };
    assembly.sourceAppearances.push(appearance);
  }
  return appearance;
}

function findOrCreateStage(role, stageId, stageSeed) {
  role.stages ??= [];
  let stage = role.stages.find((item) => item.stage_id === stageId);
  if (!stage) {
    stage = {
      stage_id: stageId,
      label: stageSeed?.label ?? 'Stage',
      frame_indexes: [],
      identity: stageSeed?.identity ?? '',
      upper_body: stageSeed?.upper_body ?? '',
      lower_body: stageSeed?.lower_body ?? '',
      upper_clothing: stageSeed?.upper_clothing ?? '',
      lower_clothing: stageSeed?.lower_clothing ?? '',
    };
    role.stages.push(stage);
  }
  return stage;
}

function findOrCreateMappingStage(assembly, stageId, stageSeed) {
  assembly.stages ??= [];
  let stage = assembly.stages.find((item) => item.id === stageId);
  if (!stage) {
    const sourceParts = {
      identity: stageSeed?.identity ?? '',
      upperBody: stageSeed?.upper_body ?? '',
      lowerBody: stageSeed?.lower_body ?? '',
      upperClothing: stageSeed?.upper_clothing ?? '',
      lowerClothing: stageSeed?.lower_clothing ?? '',
    };
    stage = {
      id: stageId,
      label: stageSeed?.label ?? 'Stage',
      frameIndexes: [],
      sourceParts,
      sourceSummary: sourceSummary(sourceParts),
      manualParts: {},
      omittedParts: [],
    };
    assembly.stages.push(stage);
  }
  return stage;
}

function firstStage(role) {
  role.stages ??= [];
  if (role.stages.length === 0) {
    role.stages.push({
      stage_id: 'stage-1',
      label: 'Stage 1',
      frame_indexes: [],
      identity: stringValue(role.display_name),
      upper_body: '',
      lower_body: '',
      upper_clothing: '',
      lower_clothing: '',
    });
  }
  return role.stages[0];
}

function firstMappingStage(assembly) {
  assembly.stages ??= [];
  if (assembly.stages.length === 0) {
    assembly.stages.push({
      id: 'stage-1',
      frameIndexes: [],
      sourceParts: {},
      sourceSummary: '',
      manualParts: {},
      omittedParts: [],
    });
  }
  return assembly.stages[0];
}

function findRole(cache, roleId) {
  return (cache.aiRoleExtraction?.roles ?? []).find((role) => role.source_role_id === roleId);
}

function findAssembly(cache, roleId) {
  return (cache.mapping?.roleAssemblies ?? cache.mapping?.role_assemblies ?? []).find(
    (assembly) => assemblyId(assembly) === roleId,
  );
}

function assemblyId(assembly) {
  return stringValue(assembly.sourceRoleId ?? assembly.source_role_id);
}

function loadCache(fileName) {
  return JSON.parse(fs.readFileSync(path.join(cacheDir, fileName), 'utf8'));
}

function saveCache(fileName, cache) {
  backupCache(fileName);
  cache.updatedAt = new Date().toISOString();
  fs.writeFileSync(path.join(cacheDir, fileName), `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
  changedFiles.add(fileName);
}

function backupCache(fileName) {
  const source = path.join(cacheDir, fileName);
  const target = path.join(backupDir, fileName);
  if (fs.existsSync(target)) return;
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.copyFileSync(source, target);
}

function addFrames(object, key, frames) {
  object[key] = [...new Set([...intList(object[key]), ...frames])].sort((left, right) => left - right);
}

function removeFrames(value, frames) {
  const blocked = new Set(frames);
  return intList(value).filter((frame) => !blocked.has(frame));
}

function appendTerms(value, terms) {
  const existing = splitTerms(value);
  const keys = new Set(existing.map(normalizedTagKey));
  for (const term of terms) {
    if (!keys.has(normalizedTagKey(term))) {
      existing.push(term);
      keys.add(normalizedTagKey(term));
    }
  }
  return existing.join(', ');
}

function removeTerms(value, terms) {
  const blocked = new Set(terms.map(normalizedTagKey));
  return splitTerms(value)
    .filter((term) => !blocked.has(normalizedTagKey(term)))
    .join(', ');
}

function hasTerm(value, term) {
  const target = normalizedTagKey(term);
  return splitTerms(value).some((item) => normalizedTagKey(item) === target);
}

function splitTerms(value) {
  return stringValue(value)
    .split(',')
    .map((term) => term.trim())
    .filter((term) => term.length > 0);
}

function normalizedTagKey(value) {
  return stringValue(value)
    .replace(/\b-?\d+(?:\.\d+)?::/g, '')
    .replace(/::/g, '')
    .replace(/\|/g, '')
    .toLowerCase()
    .replace(/[_-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function sourceSummary(sourceParts) {
  return ['identity', 'upperBody', 'lowerBody', 'upperClothing', 'lowerClothing']
    .map((key) => stringValue(sourceParts?.[key]).trim())
    .filter((value) => value.length > 0)
    .join(', ');
}

function intList(value) {
  return Array.isArray(value)
    ? value.map((item) => Number(item)).filter((item) => Number.isInteger(item))
    : [];
}

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}

function parseArgs(args) {
  const parsed = { cacheDir: undefined, backupDir: undefined, quarantineDir: undefined };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith('--')) continue;
    const equalIndex = arg.indexOf('=');
    const key = equalIndex > 0 ? arg.slice(2, equalIndex) : arg.slice(2);
    const value = equalIndex > 0 ? arg.slice(equalIndex + 1) : args[index + 1] ?? '';
    if (equalIndex < 0) index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'backup-dir') parsed.backupDir = value;
    if (key === 'quarantine-dir') parsed.quarantineDir = value;
  }
  return parsed;
}
