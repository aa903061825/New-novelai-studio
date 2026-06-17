import fs from 'node:fs';
import path from 'node:path';

const defaultCacheDir = path.join(
  process.env.APPDATA ?? '',
  'Novel Studio',\n  'Novel Studio',
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
  lower_body: 'lowerBody',
  upper_clothing: 'upperClothing',
  lower_clothing: 'lowerClothing',
};

const options = parseArgs(process.argv.slice(2));
const cacheDir = options.cacheDir ?? defaultCacheDir;

if (!fs.existsSync(cacheDir)) {
  throw new Error(`Cache directory does not exist: ${cacheDir}`);
}

const rows = fs
  .readdirSync(cacheDir)
  .filter((file) => file.endsWith('.json'))
  .sort()
  .map((file) => auditFile(path.join(cacheDir, file)));

const issueRows = rows.filter((row) => row.issue_count > 0);
const summary = {
  cache_dir: cacheDir,
  cache_count: rows.length,
  role_count: sum(rows, 'role_count'),
  stage_count: sum(rows, 'stage_count'),
  issue_count: sum(rows, 'issue_count'),
  issue_cache_count: issueRows.length,
  issue_samples: issueRows.slice(0, options.maxPrint).map((row) => ({
    file_name: row.file_name,
    script_name: row.script_name,
    issue_count: row.issue_count,
    issues: row.issues.slice(0, 12),
  })),
};

console.log(JSON.stringify(summary, null, 2));

if (options.reportPath) {
  fs.mkdirSync(path.dirname(options.reportPath), { recursive: true });
  fs.writeFileSync(
    options.reportPath,
    JSON.stringify({ ...summary, rows }, null, 2),
    'utf8',
  );
}

function auditFile(filePath) {
  const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const issues = [];
  const aiRoles = Array.isArray(cache.aiRoleExtraction?.roles)
    ? cache.aiRoleExtraction.roles
    : [];

  for (const role of aiRoles) {
    for (const stage of Array.isArray(role.stages) ? role.stages : []) {
      auditFieldObject({
        issues,
        section: 'aiRoleExtraction',
        filePath,
        scriptName: stringValue(cache.scriptName),
        roleId: stringValue(role.source_role_id),
        roleLabel: stringValue(role.display_name),
        stageId: stringValue(stage.stage_id),
        stageLabel: stringValue(stage.label),
        frameIndexes: intList(stage.frame_indexes),
        fields: stage,
        camel: false,
      });
    }
  }

  const assemblies = Array.isArray(cache.mapping?.roleAssemblies)
    ? cache.mapping.roleAssemblies
    : [];
  for (const assembly of assemblies) {
    for (const stage of Array.isArray(assembly.stages) ? assembly.stages : []) {
      auditFieldObject({
        issues,
        section: 'mapping.roleAssemblies',
        filePath,
        scriptName: stringValue(cache.scriptName),
        roleId: stringValue(assembly.sourceRoleId),
        roleLabel: stringValue(assembly.displayLabel),
        stageId: stringValue(stage.id),
        stageLabel: stringValue(stage.label),
        frameIndexes: intList(stage.frameIndexes),
        fields: stage.sourceParts ?? {},
        camel: true,
      });
    }
  }

  const roleCount = aiRoles.length;
  const stageCount = aiRoles.reduce(
    (total, role) => total + (Array.isArray(role.stages) ? role.stages.length : 0),
    0,
  );

  return {
    file_name: path.basename(filePath),
    script_name: stringValue(cache.scriptName),
    role_count: roleCount,
    stage_count: stageCount,
    issue_count: issues.length,
    issues,
  };
}

function auditFieldObject({
  issues,
  section,
  scriptName,
  roleId,
  roleLabel,
  stageId,
  stageLabel,
  frameIndexes,
  fields,
  camel,
}) {
  for (const snakeField of fieldNames) {
    const field = camel ? camelFieldNames[snakeField] : snakeField;
    for (const term of splitTerms(fields[field])) {
      const problem = roleFieldProblem(snakeField, term);
      if (!problem) continue;
      issues.push({
        section,
        script_name: scriptName,
        role_id: roleId,
        role_label: roleLabel,
        stage_id: stageId,
        stage_label: stageLabel,
        frame_indexes: frameIndexes.slice(0, 20),
        field: snakeField,
        term,
        issue: problem,
      });
    }
  }
}

function roleFieldProblem(field, term) {
  const key = normalize(term);
  if (!key) return null;
  if (isExplicitActionOrFluid(key)) return 'action_or_explicit_transient_term';
  if (isPoseCameraScene(key)) return 'pose_camera_or_scene_term';
  if (isExpressionOrEmotion(key)) return 'expression_or_emotion_term';
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
  if (/\b(wet|sweaty|sweat|stained|torn|ripped|damaged|lifted|lifting|pulled|pulling|taking off|take off|undressing|open clothes|open towel|clothing aside|clothes aside)\b/u.test(key)) {
    return true;
  }
  return false;
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
  if (/^(?:1|2)?girls?$|^(?:1)?boys?$|^female$|^male$|^woman$|^man$|^loli$/u.test(key)) {
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
    from: 0,
    maxPrint: 20,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--cache-dir') {
      parsed.cacheDir = argv[++index];
    } else if (arg === '--report-path') {
      parsed.reportPath = argv[++index];
    } else if (arg === '--max-print') {
      parsed.maxPrint = Number.parseInt(argv[++index], 10);
    }
  }
  return parsed;
}
