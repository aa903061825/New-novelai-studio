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

const fieldNames = [
  'identity',
  'upper_body',
  'lower_body',
  'upper_clothing',
  'lower_clothing',
];

const camelFieldNames = {
  identity: 'identity',
  upper_body: 'upperBody',
  upper_clothing: 'upperClothing',
  lower_body: 'lowerBody',
  lower_clothing: 'lowerClothing',
};

const options = parseArgs(process.argv.slice(2));
const cacheDir = path.resolve(options.cacheDir ?? defaultCacheDir);

if (!fs.existsSync(cacheDir)) {
  throw new Error(`Cache directory does not exist: ${cacheDir}`);
}

const rows = [];
for (const fileName of fs
  .readdirSync(cacheDir)
  .filter((file) => file.endsWith('.json'))
  .sort()) {
  rows.push(proofreadFile(path.join(cacheDir, fileName)));
}

const changedRows = rows.filter((row) => row.files_changed > 0);
const summary = {
  cache_dir: cacheDir,
  apply: options.apply,
  cache_count: rows.length,
  files_changed: changedRows.length,
  roles_changed: sum(rows, 'roles_changed'),
  stages_changed: sum(rows, 'stages_changed'),
  terms_removed: sum(rows, 'terms_removed'),
  issue_samples: changedRows.slice(0, options.maxPrint).map((row) => ({
    file_name: row.file_name,
    script_name: row.script_name,
    terms_removed: row.terms_removed,
    changes: row.changes.slice(0, 12),
  })),
};

console.log(JSON.stringify(summary, null, 2));

if (options.report) {
  fs.mkdirSync(path.dirname(options.report), { recursive: true });
  fs.writeFileSync(
    options.report,
    `${JSON.stringify({ ...summary, rows }, null, 2)}\n`,
    'utf8',
  );
}

function proofreadFile(filePath) {
  const before = fs.readFileSync(filePath, 'utf8');
  const cache = JSON.parse(before);
  const changes = [];
  const changedRoles = new Set();
  const changedStages = new Set();

  for (const role of cache.aiRoleExtraction?.roles ?? []) {
    for (const stage of role.stages ?? []) {
      for (const field of fieldNames) {
        proofreadField({
          changes,
          changedRoles,
          changedStages,
          section: 'aiRoleExtraction',
          scriptName: stringValue(cache.scriptName),
          roleId: stringValue(role.source_role_id),
          roleLabel: stringValue(role.display_name),
          stageId: stringValue(stage.stage_id),
          stageLabel: stringValue(stage.label),
          frameIndexes: intList(stage.frame_indexes),
          object: stage,
          field,
        });
      }
    }
  }

  for (const assembly of cache.mapping?.roleAssemblies ?? []) {
    for (const stage of assembly.stages ?? []) {
      const sourceParts = stage.sourceParts ?? {};
      for (const field of fieldNames) {
        proofreadField({
          changes,
          changedRoles,
          changedStages,
          section: 'mapping.roleAssemblies',
          scriptName: stringValue(cache.scriptName),
          roleId: stringValue(assembly.sourceRoleId),
          roleLabel: stringValue(assembly.displayLabel),
          stageId: stringValue(stage.id),
          stageLabel: stringValue(stage.label),
          frameIndexes: intList(stage.frameIndexes),
          object: sourceParts,
          field: camelFieldNames[field],
          semanticField: field,
        });
      }
    }
  }

  if (changes.length > 0 && options.apply) {
    fs.writeFileSync(filePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
  }

  return {
    file_name: path.basename(filePath),
    script_id: stringValue(cache.scriptId),
    script_name: stringValue(cache.scriptName),
    files_changed: changes.length > 0 ? 1 : 0,
    roles_changed: changedRoles.size,
    stages_changed: changedStages.size,
    terms_removed: changes.reduce(
      (total, change) => total + change.removed_terms.length,
      0,
    ),
    changes,
  };
}

function proofreadField({
  changes,
  changedRoles,
  changedStages,
  section,
  scriptName,
  roleId,
  roleLabel,
  stageId,
  stageLabel,
  frameIndexes,
  object,
  field,
  semanticField = field,
}) {
  const terms = splitTerms(object[field]);
  if (terms.length === 0) return;

  const kept = [];
  const removed = [];
  for (const term of terms) {
    const problem = roleFieldProblem(semanticField, term);
    if (problem) {
      removed.push({ term, problem });
    } else {
      kept.push(term);
    }
  }
  if (removed.length === 0) return;

  object[field] = kept.join(', ');
  changedRoles.add(`${section}:${roleId}`);
  changedStages.add(`${section}:${roleId}:${stageId}`);
  changes.push({
    section,
    script_name: scriptName,
    role_id: roleId,
    role_label: roleLabel,
    stage_id: stageId,
    stage_label: stageLabel,
    frame_indexes: frameIndexes.slice(0, 20),
    field: semanticField,
    before: terms.join(', '),
    after: kept.join(', '),
    removed_terms: removed,
  });
}

function roleFieldProblem(field, term) {
  const key = normalize(term);
  if (!key) return null;
  if (isExplicitActionOrFluid(key)) return 'action_or_explicit_transient_term';
  if (isPoseCameraScene(key)) return 'pose_camera_or_scene_term';
  if (isExpressionOrEmotion(key)) return 'expression_or_emotion_term';
  if (isSpecificDamagedGarment(key)) return null;
  if (isTemporaryCondition(key)) return 'temporary_condition_term';
  if (
    field === 'identity' &&
    isGarmentOrBodyDescriptor(key) &&
    !isCharacterIdentityTerm(term)
  ) {
    return 'non_identity_term_in_identity';
  }
  return null;
}

function isExplicitActionOrFluid(key) {
  return /\b(facial|sex|intercourse|masturbat|penetrat|cum|semen|saliva|pussy|penis|vibrator|sex toy|orgasm|licking|sucking|fingering|rape|molest|assault|tentacle bind|tentacle between breasts?)\b/u.test(
    key,
  );
}

function isPoseCameraScene(key) {
  return /\b(pose|pov|camera|close up|close-up|from side|side view|dutch angle|looking|standing|sitting|kneeling|lying|running|walking|bending|squatting|spread legs|arms up|hands up|holding|grabbing|touching|hands on|floor|bed|pillow|room|hallway|background|indoors|outdoors)\b/u.test(
    key,
  );
}

function isExpressionOrEmotion(key) {
  return /\b(blush|smile|open mouth|dashed eyes|closed eyes|one eye closed|covering eyes|covering one eye|heavy breathing|tears|crying|angry|embarrassed|tired|scared|surprised|heart in eyes?)\b/u.test(
    key,
  );
}

function isTemporaryCondition(key) {
  return /\b(wet|sweaty|sweat|stained|torn|ripped|damaged|lifted|lifting|pulled|pulling|taking off|take off|undressing|open clothes|open towel|clothing aside|clothes aside)\b/u.test(
    key,
  );
}

function isSpecificDamagedGarment(key) {
  if (!/\b(torn|ripped|damaged)\b/u.test(key)) return false;
  if (/\b(lifted|lifting|pulled|pulling|taking off|take off|undressing|holding|grabbing|other'?s?|another)\b/u.test(key)) {
    return false;
  }
  return /\b(pantyhose|stockings?|thighhighs?|socks?|legwear|panties|underwear|briefs|bikini|swimsuit|bra|bodysuit|leotard|dress|shirt|blouse|jacket|coat|outerwear|skirt|pants|shorts)\b/u.test(
    key,
  );
}

function isGarmentOrBodyDescriptor(key) {
  return /\b(hair|eyes?|ears?|horns?|halo|hat|hood|headdress|tail|skin|breasts?|shirt|jacket|coat|dress|uniform|bra|bikini|swimsuit|kimono|robe|armor|apron|vest|gloves?|sleeves?|towel|tank top|pants|shorts|skirt|panties|underwear|stockings?|socks?|shoes?|boots?)\b/u.test(
    key,
  );
}

function isCharacterIdentityTerm(term) {
  const text = stringValue(term).trim();
  const key = normalize(text);
  if (!key) return false;
  if (
    /^(?:1|2)?girls?$|^(?:1|2)?boys?$|^female$|^male$|^woman$|^man$|^loli$|^student$|^teacher$|^goblin$|^monster$/u.test(
      key,
    )
  ) {
    return true;
  }
  if (/[([][^)\]]{3,}[)\]]/u.test(text)) {
    return true;
  }
  return false;
}

function splitTerms(value) {
  return stringValue(value)
    .split(',')
    .map((term) => term.trim())
    .filter(Boolean);
}

function intList(value) {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => Number.parseInt(String(item), 10))
    .filter((item) => Number.isFinite(item))
    .sort((left, right) => left - right);
}

function sum(rows, key) {
  return rows.reduce((total, row) => total + (Number(row[key]) || 0), 0);
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function normalize(value) {
  return stringValue(value).trim().toLowerCase().replaceAll('_', ' ');
}

function parseArgs(argv) {
  const parsed = {
    apply: false,
    cacheDir: undefined,
    maxPrint: 20,
    report: undefined,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--apply') {
      parsed.apply = true;
    } else if (arg === '--cache-dir') {
      parsed.cacheDir = argv[++index];
    } else if (arg === '--report') {
      parsed.report = argv[++index];
    } else if (arg === '--max-print') {
      parsed.maxPrint = Number.parseInt(argv[++index], 10);
    }
  }
  return parsed;
}
