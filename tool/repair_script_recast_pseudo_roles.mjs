import fs from 'node:fs';
import path from 'node:path';

const defaultCacheDir = path.join(
  process.env.APPDATA ?? '',
  'Novel Studio',\n  'Novel Studio',
  'novel_studio',
  'script_recast',
  'cache',
);

const options = parseArgs(process.argv.slice(2));
const cacheDir = options.cacheDir ?? defaultCacheDir;
const backupDir = options.backupDir;
if (!backupDir) throw new Error('--backup-dir is required');

const mergePlan = {
  'script-561fee3678967f25.json': {
    'role-index-finger-in-anus': 'role-generic-boy',
    'role-on-girl': 'role-generic-boy',
  },
  'script-5d1834a86497b1a9.json': {
    'role-on-girl': 'role-generic-male-slot-1',
    'role-stradding-on-girl': 'role-generic-male-slot-1',
    'role-zooming-in-girl': 'role-generic-girl',
    'role-focus-girl': 'role-generic-girl',
  },
  'script-6046520367d84291.json': {
    'role-hitachi-magic-wand': 'role-generic-boy',
  },
  'script-6f722bc858b8a1d6.json': {
    'role-looking-down-at-girl': 'role-faceless-male',
    'role-looking-down-at-chiara': 'role-source-slot-0',
    'role-watching-chiara': 'role-source-slot-0',
  },
  'script-70156ab221fa1b08.json': {
    'role-muscular-build': 'role-source-slot-1',
    'role-gaze-focused-on-girl': 'role-source-slot-1',
  },
  'script-722efa0ded8beacd.json': {
    'role-hitachi-magic-wand': 'role-dark-skinned-male',
  },
  'script-7f417466984e264a.json': {
    'role-manga': 'role-boy-man',
    'role-black-food-at-boy': 'role-boy-man',
    'role-human': 'role-boy-man',
    'role-no-damaged-boy': 'role-boy-man',
  },
  'script-88111ea21587363d.json': {
    'role-girl-s': 'role-shokuhou-misaki',
    'role-saber-fate': 'role-shokuhou-misaki',
  },
  'script-341cc96322ea7cdc.json': {
    'role-index-finger-in-anus': 'role-generic-boy',
    'role-fingering-anus': 'role-generic-boy',
  },
  'script-3f6fb7fa51b5cbb3.json': {
    'role-girl-s': 'role-generic-boy',
  },
  'script-54a71b8d38654f96.json': {
    'role-girl-s': 'role-generic-boy',
  },
  'script-647e4743c821f51b.json': {
    'role-girl-s': 'role-generic-boy',
  },
  'script-6e9a77149425e027.json': {
    'role-on-girl': 'role-generic-boy',
  },
  'script-763e96e36e6eefa2.json': {
    'role-girl-s': 'role-generic-boy',
    'role-hug-girl': 'role-generic-boy',
  },
  'script-83307dbb21df5a03.json': {
    'role-male-smile': 'role-generic-boy-slot-1',
    'role-size-difference': 'role-generic-boy-slot-1',
  },
  'script-9-11-columbina-2261dfc4d39e5c56.json': {
    'role-hoshimachi-suisei-sailor': 'role-columbina-genshin-impact',
  },
  'script-dae6e611c4cc6d8f.json': {
    'role-hitachi-magic-wand': 'role-musclar-male',
  },
  'script-e166d314b8a93afe.json': {
    'role-girl-s': 'role-generic-boy',
  },
  'script-e63a1606e1499415.json': {
    'role-hitachi-magic-wand': 'role-fat-man',
  },
  'script-nahida-bbc-sph-587aac461b4fe79b.json': {
    'role-foreskin': 'role-dark-skinned-male',
  },
  'script-8894511fe484b060.json': {
    'role-stand-behind-girl': 'role-source-slot-1',
  },
  'script-8e54ade32f6b78cf.json': {
    'role-hitachi-magic-wand': 'role-fat-man',
  },
  'script-9-10-koyuki-kurosaki-49724fc84939ea11.json': {
    'role-hoshimachi-suisei-sailor': 'role-koyuki-blue-archive',
  },
  'script-9684933c44f8ed13.json': {
    'role-on-girl': 'role-generic-boy',
  },
  'script-9ce26710e9df4534.json': {
    'role-inside-girl': 'role-bihyung-black-survival',
    'role-male-focus': 'role-faceless-male',
    'role-pinning-girl-against-air': 'role-faceless-male',
  },
  'script-9d9a9b8cba7b7b3d.json': {
    'role-hard-fingering': 'role-generic-boy',
    'role-attack-her': 'role-generic-boy',
  },
  'script-9e737e880b72b757.json': {
    'role-date-a-live-black-school-uniform': 'role-izayoi-miku',
  },
  'script-a65708e8bdd91eab.json': {
    'role-men-stand-in-front-of-and-behind-the-girl': 'role-a-man-behind-a-girl',
    'role-pulling-on-a-girl-s-underwear': 'role-a-man-behind-a-girl',
    'role-multiple-smartphones-pointing-at-girl': 'role-a-man-behind-a-girl',
    'role-a-girl-only-on-the-smartphone-screen': 'role-takarada-rikka',
    'role-heart-shaped-pupilslicking-lips': 'role-takarada-rikka',
  },
  'script-asagi-aiba-1dfa47f6395645a6.json': {
    'role-on-tears': 'role-source-slot-0',
  },
  'script-b21684ad008ba388.json': {
    'role-foreskin': 'role-generic-boy-slot-1',
    'role-pointing-urinal': 'role-generic-boy-slot-1',
    'role-male-smile': 'role-generic-boy-slot-1',
  },
  'script-bb8fe4471921dae6.json': {
    'role-princess-carrying-girl': 'role-generic-boy-slot-0',
  },
  'script-bbcec036f9db6907.json': {
    'role-pulling-dildo': 'role-dark-skinned-male',
    'role-african': 'role-dark-skinned-male',
  },
  'script-bihyung-40dca041f080b77d.json': {
    'role-inside-girl': 'role-bihyung-black-survival',
    'role-male-focus': 'role-faceless-male',
    'role-pinning-girl-against-air': 'role-faceless-male',
  },
  'script-c1fb0c3205ebbef4.json': {
    'role-girl-s': 'role-eris-greyrat',
  },
  'script-c25eca79a8816b70.json': {
    'role-on-girl': 'role-generic-boy',
    'role-girl-s': 'role-usada-pekora-1st-costume',
  },
  'script-cceebb3b65d577ac.json': {
    'role-hitachi-magic-wand': 'role-generic-boy',
  },
  'script-cd944aeae667c857.json': {
    'role-squatting-on-girl-with-knees': 'role-generic-boy',
  },
  'script-cee4bd86846da79c.json': {
    'role-girl-s': 'role-sakura-miko-1st-costume',
  },
  'script-chiara-bunny-girl-3cc207fe3cf1e402.json': {
    'role-looking-down-at-girl': 'role-faceless-male',
    'role-looking-down-at-chiara': 'role-chiara-black-survival',
    'role-watching-chiara': 'role-chiara-black-survival',
  },
  'script-chino-d8b69d596705d537.json': {
    'role-man-strangle-girl-from-backside': 'role-generic-boy-slot-1',
  },
  'script-crime-scene-die-bde83e0209084892.json': {
    'role-licking-girl-vagina': 'role-generic-boy-slot-1',
    'role-licking-girl-pant': 'role-generic-boy-slot-1',
    'role-tongue-licking-girl-vagina': 'role-generic-boy-slot-1',
    'role-chasing-girl': 'role-generic-boy-slot-0',
    'role-princess-carrying-girl': 'role-generic-boy-slot-0',
  },
  'script-d808f7151358db82.json': {
    'role-elbow-on-ground': 'role-generic-boy',
  },
};

const changed = [];
const merged = [];

for (const [fileName, filePlan] of Object.entries(mergePlan)) {
  const cachePath = path.join(cacheDir, fileName);
  const cache = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
  for (const [sourceRoleId, targetRoleId] of Object.entries(filePlan)) {
    mergeRole(cache, sourceRoleId, targetRoleId, fileName);
    merged.push({ file_name: fileName, source_role_id: sourceRoleId, target_role_id: targetRoleId });
  }
  backupCache(fileName);
  cache.updatedAt = new Date().toISOString();
  fs.writeFileSync(cachePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
  changed.push(fileName);
}

console.log(JSON.stringify({ changed_files: changed, merged_roles: merged.length }, null, 2));

function mergeRole(cache, sourceRoleId, targetRoleId, fileName) {
  const roles = cache.aiRoleExtraction?.roles ?? [];
  const source = roles.find((role) => role.source_role_id === sourceRoleId);
  const target = roles.find((role) => role.source_role_id === targetRoleId);
  if (!source) return false;
  if (!target) throw new Error(`${fileName}: missing target ${targetRoleId}`);

  addFrames(target, 'frame_indexes', source.frame_indexes ?? []);
  for (const sourceAppearance of source.appearances ?? []) {
    const targetAppearance = findOrCreateAppearance(target, sourceAppearance);
    addFrames(targetAppearance, 'frame_indexes', sourceAppearance.frame_indexes ?? []);
  }
  addFrames(firstStage(target), 'frame_indexes', source.frame_indexes ?? []);
  cache.aiRoleExtraction.roles = roles.filter((role) => role.source_role_id !== sourceRoleId);

  const assemblies = cache.mapping?.roleAssemblies ?? cache.mapping?.role_assemblies ?? [];
  const sourceAssembly = assemblies.find((assembly) => assemblyId(assembly) === sourceRoleId);
  const targetAssembly = assemblies.find((assembly) => assemblyId(assembly) === targetRoleId);
  if (sourceAssembly && targetAssembly) {
    for (const sourceAppearance of sourceAssembly.sourceAppearances ?? sourceAssembly.source_appearances ?? []) {
      const targetAppearance = findOrCreateMappingAppearance(targetAssembly, sourceAppearance);
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

function findOrCreateAppearance(role, sourceAppearance) {
  const sourceId = sourceAppearance.source_id;
  let target = (role.appearances ?? []).find((appearance) => appearance.source_id === sourceId);
  if (!target) {
    target = {
      source_id: sourceId,
      source_kind: sourceAppearance.source_kind ?? 'slot',
      frame_indexes: [],
    };
    role.appearances = [...(role.appearances ?? []), target];
  }
  return target;
}

function findOrCreateMappingAppearance(assembly, sourceAppearance) {
  const sourceId = sourceAppearance.sourceId ?? sourceAppearance.source_id;
  let target = (assembly.sourceAppearances ?? []).find((appearance) => appearance.sourceId === sourceId);
  if (!target) {
    target = {
      sourceId,
      sourceKind: sourceAppearance.sourceKind ?? sourceAppearance.source_kind ?? 'slot',
      frameIndexes: [],
    };
    assembly.sourceAppearances = [...(assembly.sourceAppearances ?? []), target];
  }
  return target;
}

function firstStage(role) {
  if (!Array.isArray(role.stages)) role.stages = [];
  if (role.stages.length === 0) role.stages.push({ stage_id: 'stage-1', label: 'Default', frame_indexes: [] });
  return role.stages[0];
}

function firstMappingStage(assembly) {
  if (!Array.isArray(assembly.stages)) assembly.stages = [];
  if (assembly.stages.length === 0) assembly.stages.push({ id: 'stage-1', label: 'Default', frameIndexes: [] });
  return assembly.stages[0];
}

function addFrames(object, key, frames) {
  object[key] = [...new Set([...(object[key] ?? []), ...frames])]
    .filter((value) => Number.isInteger(value))
    .sort((left, right) => left - right);
}

function assemblyId(assembly) {
  return assembly.sourceRoleId ?? assembly.source_role_id;
}

function backupCache(fileName) {
  const source = path.join(cacheDir, fileName);
  const target = path.join(backupDir, fileName);
  if (fs.existsSync(target)) return;
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.copyFileSync(source, target);
}

function parseArgs(args) {
  const parsed = { cacheDir: undefined, backupDir: undefined };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith('--')) continue;
    const equalIndex = arg.indexOf('=');
    const key = equalIndex > 0 ? arg.slice(2, equalIndex) : arg.slice(2);
    const value = equalIndex > 0 ? arg.slice(equalIndex + 1) : args[index + 1] ?? '';
    if (equalIndex < 0) index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'backup-dir') parsed.backupDir = value;
  }
  return parsed;
}
