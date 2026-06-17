import fs from 'node:fs';
import path from 'node:path';

const defaultCacheDir = path.join(
  process.env.APPDATA ?? '',
  'Novel Studio',\n  'Novel Studio',
  'novel_studio',
  'script_recast',
  'cache',
);

const cacheDir = defaultCacheDir;
const classificationPath =
  'E:/NAI\u7684\u811a\u672c\u7fa4/tag_classification_cache.json';
const backupDir = path.join(
  'build',
  'script_recast_strict_field_audit_backup_20260609',
);
const source = 'codex-script-cache-strict-field-audit-20260609';

const changedFiles = new Set();
const repairs = [];

renameStaleRoleIds();
repairStrictFieldMismatches();
repairClassificationCache();

console.log(
  JSON.stringify(
    {
      cache_dir: cacheDir,
      classification_cache: classificationPath,
      backup_dir: path.resolve(backupDir),
      changed_files: [...changedFiles].sort(),
      repair_count: repairs.length,
      repairs,
    },
    null,
    2,
  ),
);

function renameStaleRoleIds() {
  const renames = {
    'script-1-7b6837c5c2cf3385.json': {
      'role-no-humans': 'role-black-crystallized-monster',
    },
    'script-1-d7e07f11f22eaba5.json': {
      'role-no-abdomen': 'role-partial-boy-body',
    },
    'script-11b1815651b79e76.json': {
      'role-year-2025': 'role-greater-lord-rukkhadevata-adult-form',
    },
    'script-268ab0a5856036be.json': {
      'role-man-fingering-girl-vagina-from-front': 'role-boy-pov-arms',
    },
    'script-3-fe65a5034ff2722e.json': {
      'role-muscular-chest': 'role-bandit',
    },
    'script-44238bc1c058b6a5.json': {
      'role-shower-place': 'role-boy-shower',
      'role-white-shirtfaceless-male': 'role-faceless-male-white-shirt',
    },
    'script-7f28eb7202b8f707.json': {
      'role-dark-skinned': 'role-dark-skinned-male',
    },
    'script-9-2-suzuran-aa5519380d114932.json': {
      'role-loli': 'role-suzuran-spring-praise-arknights',
    },
  };

  for (const [fileName, fileRenames] of Object.entries(renames)) {
    const cache = loadCache(fileName);
    const before = JSON.stringify(cache);
    replaceExactStrings(cache, fileRenames);
    if (fileName === 'script-7f28eb7202b8f707.json') {
      patchRoleObject(cache, 'role-dark-skinned-male', (role) => {
        role.display_name = 'dark-skinned male';
        for (const stage of role.stages ?? []) {
          stage.identity = replaceTerm(stage.identity, 'dark skinned', 'dark-skinned male');
          stage.upper_body = removeTerms(stage.upper_body, ['armlock to another']);
        }
      });
      patchAssemblyObject(cache, 'role-dark-skinned-male', (assembly) => {
        assembly.displayLabel = 'dark-skinned male';
        assembly.sourceName = 'dark-skinned male';
        for (const stage of assembly.stages ?? []) {
          stage.sourceParts ??= {};
          stage.sourceParts.identity = replaceTerm(
            stage.sourceParts.identity,
            'dark skinned',
            'dark-skinned male',
          );
          stage.sourceParts.upperBody = removeTerms(stage.sourceParts.upperBody, [
            'armlock to another',
          ]);
          stage.sourceSummary = sourceSummary(stage.sourceParts);
        }
      });
    }
    if (JSON.stringify(cache) !== before) {
      saveCache(fileName, cache);
      repairs.push({ file_name: fileName, action: 'rename_stale_role_ids' });
    }
  }
}

function repairStrictFieldMismatches() {
  moveTerm('script-1-407f193d94765cc4.json', 'role-artoria-caster-fate', 'lower_body', 'upper_body', 'twin tails');
  moveTerm('script-6f722bc858b8a1d6.json', 'role-source-slot-0', 'lower_body', 'upper_body', 'twin tails');

  moveTerm(
    'script-1-fdc34df71c7933c2.json',
    'role-star-shaped-pupils',
    'lower_body',
    'lower_clothing',
    'garter belt connected to bunny tail',
  );
  moveTerm(
    'script-54909c2f67b8652b.json',
    'role-mizuhara-chizuru',
    'lower_clothing',
    'upper_body',
    'red ribbon',
  );

  moveMappingManualTerm(
    'script-8ec34e70cc47b935.json',
    'role-fujita-kotone',
    'identity',
    'upperBody',
    'animal_ear_fluff',
  );

  replaceIdentityTerm(
    'script-70156ab221fa1b08.json',
    'role-source-slot-1',
    'young adult man',
    'man',
  );
  removeEverywhere('script-9-2-suzuran-aa5519380d114932.json', 'role-suzuran-spring-praise-arknights', ['child']);

  removeEverywhere('script-6f722bc858b8a1d6.json', null, ['penis in mouth']);
  removeEverywhere('script-1-edaa6f276ebf3bd1.json', null, ['innocent face now broken']);
  removeEverywhere('script-3a94b5f09224185a.json', null, ['ultimate hyper rolling eyes']);

  for (const fileName of fs
    .readdirSync(cacheDir)
    .filter((file) => file.endsWith('.json'))) {
    removeEverywhere(fileName, null, [
      'no face',
      'no face visible',
      'face not visible',
      'no torso',
      'no other body parts',
      'no legs',
      'shaded face',
      'focus face',
      'hand over mouth',
    ]);
  }
}

function repairClassificationCache() {
  const cache = JSON.parse(fs.readFileSync(classificationPath, 'utf8'));
  const updates = {
    'positive:twin tails': 'upperBody',
    'positive:dark-skinned male': 'role',
    'positive:young adult man': 'role',
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
    repairs.push({ file_name: path.basename(classificationPath), action: 'update_classification', key, category });
    touched = true;
  }
  if (touched) {
    fs.mkdirSync(backupDir, { recursive: true });
    fs.copyFileSync(
      classificationPath,
      path.join(backupDir, 'tag_classification_cache.json'),
    );
    fs.writeFileSync(classificationPath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
  }
}

function moveTerm(fileName, roleId, fromField, toField, term) {
  const cache = loadCache(fileName);
  const before = JSON.stringify(cache);
  patchRoleObject(cache, roleId, (role) => {
    for (const stage of role.stages ?? []) {
      if (hasTerm(stage[fromField], term)) {
        stage[fromField] = removeTerms(stage[fromField], [term]);
        stage[toField] = appendTerms(stage[toField], [term]);
      }
    }
  });
  patchAssemblyObject(cache, roleId, (assembly) => {
    for (const stage of assembly.stages ?? []) {
      stage.sourceParts ??= {};
      const sourceFrom = toSourcePartField(fromField);
      const sourceTo = toSourcePartField(toField);
      if (hasTerm(stage.sourceParts[sourceFrom], term)) {
        stage.sourceParts[sourceFrom] = removeTerms(stage.sourceParts[sourceFrom], [term]);
        stage.sourceParts[sourceTo] = appendTerms(stage.sourceParts[sourceTo], [term]);
        stage.sourceSummary = sourceSummary(stage.sourceParts);
      }
    }
  });
  if (JSON.stringify(cache) !== before) {
    saveCache(fileName, cache);
    repairs.push({ file_name: fileName, action: 'move_term', role_id: roleId, term, from: fromField, to: toField });
  }
}

function moveMappingManualTerm(fileName, roleId, fromField, toField, term) {
  const cache = loadCache(fileName);
  const before = JSON.stringify(cache);
  patchAssemblyObject(cache, roleId, (assembly) => {
    for (const stage of assembly.stages ?? []) {
      stage.manualParts ??= {};
      if (hasTerm(stage.manualParts[fromField], term)) {
        stage.manualParts[fromField] = removeTerms(stage.manualParts[fromField], [term]);
        stage.manualParts[toField] = appendTerms(stage.manualParts[toField], [term]);
      }
    }
  });
  if (JSON.stringify(cache) !== before) {
    saveCache(fileName, cache);
    repairs.push({ file_name: fileName, action: 'move_manual_term', role_id: roleId, term, from: fromField, to: toField });
  }
}

function replaceIdentityTerm(fileName, roleId, fromTerm, toTerm) {
  const cache = loadCache(fileName);
  const before = JSON.stringify(cache);
  patchRoleObject(cache, roleId, (role) => {
    for (const stage of role.stages ?? []) {
      stage.identity = replaceTerm(stage.identity, fromTerm, toTerm);
    }
  });
  patchAssemblyObject(cache, roleId, (assembly) => {
    for (const stage of assembly.stages ?? []) {
      stage.sourceParts ??= {};
      stage.sourceParts.identity = replaceTerm(stage.sourceParts.identity, fromTerm, toTerm);
      stage.sourceSummary = sourceSummary(stage.sourceParts);
    }
  });
  if (JSON.stringify(cache) !== before) {
    saveCache(fileName, cache);
    repairs.push({ file_name: fileName, action: 'replace_identity_term', role_id: roleId, from: fromTerm, to: toTerm });
  }
}

function removeEverywhere(fileName, roleId, terms) {
  const cache = loadCache(fileName);
  const before = JSON.stringify(cache);
  for (const role of cache.aiRoleExtraction?.roles ?? []) {
    if (roleId && role.source_role_id !== roleId) continue;
    for (const stage of role.stages ?? []) {
      for (const field of ['identity', 'upper_body', 'lower_body', 'upper_clothing', 'lower_clothing']) {
        stage[field] = removeTerms(stage[field], terms);
      }
      if (Array.isArray(stage.evidence_terms)) {
        const blocked = new Set(terms.map(normalizedTagKey));
        stage.evidence_terms = stage.evidence_terms.filter(
          (item) => !blocked.has(normalizedTagKey(item)),
        );
      }
    }
    if (Array.isArray(role.evidence_terms)) {
      const blocked = new Set(terms.map(normalizedTagKey));
      role.evidence_terms = role.evidence_terms.filter(
        (item) => !blocked.has(normalizedTagKey(item)),
      );
    }
  }
  for (const assembly of cache.mapping?.roleAssemblies ?? []) {
    if (roleId && assembly.sourceRoleId !== roleId) continue;
    for (const stage of assembly.stages ?? []) {
      for (const partsKey of ['sourceParts', 'manualParts']) {
        if (!stage[partsKey]) continue;
        for (const field of ['identity', 'upperBody', 'lowerBody', 'upperClothing', 'lowerClothing']) {
          stage[partsKey][field] = removeTerms(stage[partsKey][field], terms);
        }
      }
      stage.sourceSummary = sourceSummary(stage.sourceParts);
    }
  }
  if (JSON.stringify(cache) !== before) {
    saveCache(fileName, cache);
    repairs.push({ file_name: fileName, action: 'remove_terms', role_id: roleId ?? '*', terms });
  }
}

function patchRoleObject(cache, roleId, patch) {
  const role = (cache.aiRoleExtraction?.roles ?? []).find(
    (item) => item.source_role_id === roleId,
  );
  if (role) patch(role);
}

function patchAssemblyObject(cache, roleId, patch) {
  const assembly = (cache.mapping?.roleAssemblies ?? []).find(
    (item) => item.sourceRoleId === roleId,
  );
  if (assembly) patch(assembly);
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
  if (typeof value === 'string' && renames[value]) {
    return renames[value];
  }
  return value;
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
  const sourcePath = path.join(cacheDir, fileName);
  const backupPath = path.join(backupDir, fileName);
  if (fs.existsSync(backupPath)) return;
  fs.mkdirSync(path.dirname(backupPath), { recursive: true });
  fs.copyFileSync(sourcePath, backupPath);
}

function toSourcePartField(stageField) {
  return {
    identity: 'identity',
    upper_body: 'upperBody',
    lower_body: 'lowerBody',
    upper_clothing: 'upperClothing',
    lower_clothing: 'lowerClothing',
  }[stageField];
}

function appendTerms(value, terms) {
  const existing = splitTerms(value);
  const keys = new Set(existing.map(normalizedTagKey));
  for (const term of terms) {
    const key = normalizedTagKey(term);
    if (!keys.has(key)) {
      existing.push(term);
      keys.add(key);
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

function replaceTerm(value, fromTerm, toTerm) {
  const target = normalizedTagKey(fromTerm);
  const terms = splitTerms(value).map((term) =>
    normalizedTagKey(term) === target ? toTerm : term,
  );
  const deduped = [];
  const keys = new Set();
  for (const term of terms) {
    const key = normalizedTagKey(term);
    if (!keys.has(key)) {
      deduped.push(term);
      keys.add(key);
    }
  }
  return deduped.join(', ');
}

function hasTerm(value, term) {
  const target = normalizedTagKey(term);
  return splitTerms(value).some((item) => normalizedTagKey(item) === target);
}

function splitTerms(value) {
  return String(value ?? '')
    .split(',')
    .map((term) => term.trim())
    .filter((term) => term.length > 0);
}

function normalizedTagKey(value) {
  return String(value ?? '')
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
    .map((key) => String(sourceParts?.[key] ?? '').trim())
    .filter((value) => value.length > 0)
    .join(', ');
}
