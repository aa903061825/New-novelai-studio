import fs from 'node:fs';
import path from 'node:path';

const targetFileName = 'script-e1b24f906b68d31a.json';
const oldRoleId = 'role-girl-slot-0';
const targetRoleId = 'role-succubus';
const targetDisplayName = 'succubus / 魅魔';
const removedPromptTerms = new Set([
  'face not visible',
  'heart eyes',
  'irritating_face',
  'legs not visible',
  'legs outside wall',
  'legs visible',
  'spanked ass',
  'stuck at hips + torso inside wall + head outside wall',
]);
const stageParts = [
  {
    identity: 'girl',
    upper_body:
      'bare shoulders, black choker, blue silver hair, large breasts, pink bow, pink hair ribbon, short double bun hair, white rabbit ears, blue silver eyes',
    lower_body: '',
    upper_clothing:
      'black bra, detached sleeves, white strapless dress',
    lower_clothing: 'white thighhighs',
  },
  {
    identity: 'girl',
    upper_body: '',
    lower_body: 'white rabbit tail',
    upper_clothing: 'white strapless dress, short dress',
    lower_clothing:
      'black panties, white thighhighs, short skirt, white short skirt',
  },
  {
    identity: 'girl',
    upper_body: '',
    lower_body: 'white rabbit tail',
    upper_clothing: '',
    lower_clothing: 'black panties, short skirt, white thighhighs',
  },
  {
    identity: 'girl',
    upper_body: '',
    lower_body: 'white rabbit tail',
    upper_clothing: '',
    lower_clothing: 'white short skirt, white thighhighs',
  },
];
const roleFields = [
  'identity',
  'upper_body',
  'lower_body',
  'upper_clothing',
  'lower_clothing',
];

const options = parseArgs(process.argv.slice(2));
if (!options.cacheDir) {
  throw new Error('Pass --cache-dir <directory>.');
}
const cacheFile = path.join(path.resolve(options.cacheDir), targetFileName);
if (!fs.existsSync(cacheFile)) {
  throw new Error(`Missing target cache: ${cacheFile}`);
}

const cache = JSON.parse(fs.readFileSync(cacheFile, 'utf8'));
const result = repairCache(cache);
if (result.changed && options.apply) {
  result.cache.updatedAt = new Date().toISOString();
  fs.writeFileSync(
    cacheFile,
    `${JSON.stringify(result.cache, null, 2)}\n`,
    'utf8',
  );
}

const report = {
  cache_file: cacheFile,
  apply: options.apply,
  api_used: false,
  files_scanned: 1,
  files_changed: result.changed ? 1 : 0,
  frame_count: result.cache.scriptSnapshot?.frames?.length ?? 0,
  role_count: result.cache.aiRoleExtraction?.roles?.length ?? 0,
  role_ids_renamed: result.roleIdsRenamed,
  stage_fields_changed: result.stageFieldsChanged,
  removed_prompt_terms: result.removedPromptTerms,
  recategorized_prompt_terms: result.recategorizedPromptTerms,
  role_prompt_group_count:
    result.cache.mapping?.rolePromptReplacements?.length ?? 0,
  role_prompt_rule_count: (result.cache.mapping?.rolePromptReplacements ?? [])
    .reduce((count, group) => count + (group.rules?.length ?? 0), 0),
  scene_prompt_group_count:
    result.cache.mapping?.scenePromptReplacements?.length ?? 0,
  scene_prompt_rule_count: (result.cache.mapping?.scenePromptReplacements ?? [])
    .reduce((count, group) => count + (group.rules?.length ?? 0), 0),
};
if (options.report) {
  fs.mkdirSync(path.dirname(path.resolve(options.report)), { recursive: true });
  fs.writeFileSync(
    path.resolve(options.report),
    `${JSON.stringify(report, null, 2)}\n`,
    'utf8',
  );
}
console.log(JSON.stringify(report, null, 2));

function repairCache(input) {
  const cache = structuredClone(input);
  const before = JSON.stringify(cache);
  const extraction = cache.aiRoleExtraction;
  if (!extraction || !Array.isArray(extraction.roles)) {
    throw new Error('Target cache has no AI role extraction roles.');
  }
  const role = extraction.roles.find(
    (item) =>
      item?.source_role_id === oldRoleId ||
      (item?.appearances ?? []).some(
        (appearance) => appearance?.source_id === 'slot-0',
      ),
  );
  if (!role) {
    throw new Error('Could not find the slot-0 succubus role.');
  }
  if (!Array.isArray(role.stages) || role.stages.length !== stageParts.length) {
    throw new Error(
      `Expected ${stageParts.length} succubus stages, found ${role.stages?.length ?? 0}.`,
    );
  }

  let roleIdsRenamed = 0;
  let stageFieldsChanged = 0;
  const removed = [];
  const recategorized = [];
  if (role.source_role_id !== targetRoleId) {
    role.source_role_id = targetRoleId;
    roleIdsRenamed += 1;
  }
  role.display_name = targetDisplayName;
  role.canonical_name = 'succubus';
  role.franchise = '';
  role.raw_identity_tags = ['girl'];

  role.prompt_terms = (role.prompt_terms ?? []).flatMap((term) => {
    const text = String(term?.text ?? '').trim();
    if (removedPromptTerms.has(text)) {
      removed.push(text);
      return [];
    }
    if (text === 'pink bow' && term.category !== 'accessory') {
      recategorized.push({
        text,
        from: term.category,
        to: 'accessory',
      });
      return [{ ...term, category: 'accessory' }];
    }
    return [term];
  });

  for (let index = 0; index < role.stages.length; index += 1) {
    const stage = role.stages[index];
    const nextParts = stageParts[index];
    for (const field of roleFields) {
      if (String(stage[field] ?? '') !== nextParts[field]) {
        stage[field] = nextParts[field];
        stageFieldsChanged += 1;
      }
    }
    stage.evidence_terms = evidenceTerms(nextParts);
    stage.missing_fields = roleFields
      .filter((field) => !nextParts[field])
      .map((field) => `missing_${field}`);
    stage.field_reasons = {
      identity: fieldReason('identity', nextParts.identity),
      upper_body: fieldReason('upper body/accessory', nextParts.upper_body),
      lower_body: fieldReason('lower body/accessory', nextParts.lower_body),
      upper_clothing: fieldReason('upper clothing', nextParts.upper_clothing),
      lower_clothing: fieldReason('lower clothing', nextParts.lower_clothing),
    };
  }
  role.evidence_terms = unique(role.stages.flatMap((stage) => stage.evidence_terms));

  syncMapping(cache, role);
  return {
    cache,
    changed: before !== JSON.stringify(cache),
    roleIdsRenamed,
    stageFieldsChanged,
    removedPromptTerms: unique(removed),
    recategorizedPromptTerms: recategorized,
  };
}

function syncMapping(cache, role) {
  const mapping = cache.mapping;
  if (!mapping) throw new Error('Target cache has no mapping.');
  const allowedTerms = new Map(
    (role.prompt_terms ?? []).map((term) => [String(term.id), term]),
  );
  const promptGroup = (mapping.rolePromptReplacements ?? []).find(
    (group) => group?.sourceRoleId === oldRoleId || group?.sourceRoleId === targetRoleId,
  );
  if (!promptGroup) throw new Error('Missing succubus role prompt mapping group.');
  promptGroup.sourceRoleId = targetRoleId;
  promptGroup.displayLabel = targetDisplayName;
  promptGroup.sourcePreview = (role.prompt_terms ?? [])
    .map((term) => term.text)
    .join(', ');
  promptGroup.rules = (promptGroup.rules ?? []).flatMap((rule) => {
    const sourceTerms = (rule.sourceTerms ?? []).flatMap((sourceTerm) => {
      const term = allowedTerms.get(String(sourceTerm?.id ?? ''));
      if (!term) return [];
      return [
        {
          ...sourceTerm,
          text: term.text,
          category: term.category,
          sourcePhrase: term.source_phrase,
          sourceLocation: term.source_location,
          frameIndexes: term.frame_indexes,
          sourceOccurrences: (term.source_occurrences ?? []).map((occurrence) => ({
            frameIndex: occurrence.frameIndex ?? occurrence.frame_index,
            sourceLocation:
              occurrence.sourceLocation ?? occurrence.source_location,
          })),
        },
      ];
    });
    return sourceTerms.length === 0 ? [] : [{ ...rule, sourceTerms }];
  });

  const assembly = (mapping.roleAssemblies ?? []).find(
    (item) => item?.sourceRoleId === oldRoleId || item?.sourceRoleId === targetRoleId,
  );
  if (!assembly) throw new Error('Missing succubus role assembly.');
  assembly.sourceRoleId = targetRoleId;
  assembly.displayLabel = targetDisplayName;
  assembly.sourceName = targetDisplayName;
  for (const mappingStage of assembly.stages ?? []) {
    const stage = role.stages.find((item) => item.stage_id === mappingStage.id);
    if (!stage) throw new Error(`Missing AI stage for mapping stage ${mappingStage.id}.`);
    mappingStage.label = stage.label;
    mappingStage.frameIndexes = stage.frame_indexes;
    mappingStage.sourceParts = dropEmptyValues({
      identity: stage.identity,
      upperBody: stage.upper_body,
      lowerBody: stage.lower_body,
      upperClothing: stage.upper_clothing,
      lowerClothing: stage.lower_clothing,
    });
    mappingStage.sourceSummary = Object.values(mappingStage.sourceParts)
      .filter(Boolean)
      .join(', ');
  }
}

function evidenceTerms(parts) {
  return unique(roleFields.flatMap((field) => splitTerms(parts[field])));
}

function splitTerms(value) {
  return String(value ?? '')
    .split(',')
    .map((term) => term.trim())
    .filter(Boolean);
}

function unique(values) {
  return [...new Set(values)];
}

function dropEmptyValues(value) {
  return Object.fromEntries(
    Object.entries(value).filter(([, nested]) => String(nested ?? '').trim()),
  );
}

function fieldReason(label, value) {
  return value
    ? `${label[0].toUpperCase()}${label.slice(1)} terms are sourced from assigned role frames.`
    : `No stable ${label} role evidence was present.`;
}

function parseArgs(args) {
  const parsed = { cacheDir: '', report: '', apply: false };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--apply') {
      parsed.apply = true;
      continue;
    }
    if (arg === '--cache-dir' && index + 1 < args.length) {
      parsed.cacheDir = args[++index];
      continue;
    }
    if (arg === '--report' && index + 1 < args.length) {
      parsed.report = args[++index];
    }
  }
  return parsed;
}
