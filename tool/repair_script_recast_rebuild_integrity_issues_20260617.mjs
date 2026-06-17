import fs from 'node:fs';
import path from 'node:path';

const options = parseArgs(process.argv.slice(2));

if (!options.cacheDir) {
  throw new Error('Pass --cache-dir <directory>.');
}

const cacheDir = path.resolve(options.cacheDir);

const identityRepairs = [
  {
    file: 'script-9-11-columbina-b52b5978c5ba41d7.json',
    roleId: 'role-columbina-genshin-impact',
    displayName: 'columbina_(genshin_impact) / 哥伦比娅（原神）',
    canonicalName: 'columbina',
    identityTerms: ['columbina_(genshin_impact)', 'girl'],
    promptTermText: 'columbina_(genshin_impact)',
    sourcePhraseTerm: '[[[columbina_(genshin_impact)]]',
  },
  {
    file: 'script-9-11-ibuki-a6388322b39f7a9f.json',
    roleId: 'role-columbina-genshin-impact',
    displayName: 'columbina_(genshin_impact) / 哥伦比娅（原神）',
    canonicalName: 'columbina',
    identityTerms: ['columbina_(genshin_impact)', 'girl'],
    promptTermText: 'columbina_(genshin_impact)',
    sourcePhraseTerm: '[[[columbina_(genshin_impact)]]',
  },
  {
    file: 'script-9-12-mitsuri-kanroji-72c85cfaca1ca4e3.json',
    roleId: 'role-columbina-genshin-impact',
    displayName: 'columbina_(genshin_impact) / 哥伦比娅（原神）',
    canonicalName: 'columbina',
    identityTerms: ['columbina_(genshin_impact)', 'girl'],
    promptTermText: 'columbina_(genshin_impact)',
    sourcePhraseTerm: '[[[columbina_(genshin_impact)]]',
  },
  {
    file: 'script-9-12-tristan-3df3c5bdd29d4e6c.json',
    roleId: 'role-columbina-genshin-impact',
    displayName: 'columbina_(genshin_impact) / 哥伦比娅（原神）',
    canonicalName: 'columbina',
    identityTerms: ['columbina_(genshin_impact)', 'girl'],
    promptTermText: 'columbina_(genshin_impact)',
    sourcePhraseTerm: '[[[columbina_(genshin_impact)]]',
  },
  {
    file: 'script-9-13-firefly-d04948f3f1e63818.json',
    roleId: 'role-firefly-honkai-star-rail',
    displayName: 'firefly_(honkai:_star_rail) / 流萤（崩坏：星穹铁道）',
    canonicalName: 'firefly',
    identityTerms: ['firefly_(honkai:_star_rail)', 'girl'],
    promptTermText: 'firefly_(honkai:_star_rail)',
    sourcePhraseTerm: '[[firefly_(honkai:_star_rail)]',
  },
  {
    file: 'script-mhsj1-8f7c2db6aaf06c8e.json',
    roleId: 'role-anonymous-male',
    displayName: 'dirty fat ugly man / 肮脏肥胖丑男',
    canonicalName: 'dirty fat ugly man',
    identityTerms: ['dirty fat ugly man'],
    promptTermText: 'dirty fat ugly man',
    replacePromptTermText: 'fat man',
  },
  {
    file: 'script-mhsj1-8f7c2db6aaf06c8e.json',
    roleId: 'role-looking-at-monster',
    displayName: 'dirty fat ugly man / 肮脏肥胖丑男',
    canonicalName: 'dirty fat ugly man',
    identityTerms: ['dirty fat ugly man'],
    promptTermText: 'dirty fat ugly man',
    replacePromptTermText: 'fat man',
  },
];

const fieldRepairs = [
  {
    file: 'script-22602b9d3775a95a.json',
    roleId: 'role-takarada-rikka',
    stageIds: ['stage-6', 'stage-7', 'stage-8', 'stage-9', 'stage-10'],
    field: 'upper_body',
    sourcePartField: 'upperBody',
    removeTerm: 'Letting your hair down',
  },
];

const report = {
  cache_dir: cacheDir,
  apply: options.apply,
  identity_repairs: [],
  field_repairs: [],
  files_changed: 0,
};

const files = new Map();
const changedFiles = new Set();

for (const repair of identityRepairs) {
  const cache = loadCache(repair.file);
  const before = JSON.stringify(cache);
  const row = repairIdentity(cache, repair);
  const changed = JSON.stringify(cache) !== before;
  row.changed = changed;
  report.identity_repairs.push(row);
  if (changed) changedFiles.add(repair.file);
}

for (const repair of fieldRepairs) {
  const cache = loadCache(repair.file);
  const before = JSON.stringify(cache);
  const row = repairFieldLeak(cache, repair);
  const changed = JSON.stringify(cache) !== before;
  row.changed = changed;
  report.field_repairs.push(row);
  if (changed) changedFiles.add(repair.file);
}

for (const file of changedFiles) {
  const cache = files.get(file);
  cache.updatedAt = new Date().toISOString();
  if (options.apply) {
    fs.writeFileSync(
      path.join(cacheDir, file),
      `${JSON.stringify(cache, null, 2)}\n`,
      'utf8',
    );
  }
}

report.files_changed = changedFiles.size;

console.log(JSON.stringify(report, null, 2));
if (options.report) {
  fs.mkdirSync(path.dirname(options.report), { recursive: true });
  fs.writeFileSync(options.report, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
}

function loadCache(file) {
  if (!files.has(file)) {
    files.set(file, JSON.parse(fs.readFileSync(path.join(cacheDir, file), 'utf8')));
  }
  return files.get(file);
}

function repairIdentity(cache, repair) {
  const role = findRole(cache, repair.roleId);
  role.display_name = repair.displayName;
  role.canonical_name = repair.canonicalName;
  role.raw_identity_tags = unique([
    ...(Array.isArray(role.raw_identity_tags) ? role.raw_identity_tags : []),
    ...repair.identityTerms,
  ]);
  role.evidence_terms = unique([
    ...(Array.isArray(role.evidence_terms) ? role.evidence_terms : []),
    ...repair.identityTerms,
  ]);

  for (const stage of role.stages ?? []) {
    stage.identity = mergeTerms(stage.identity, repair.identityTerms);
    stage.evidence_terms = unique([
      ...(Array.isArray(stage.evidence_terms) ? stage.evidence_terms : []),
      ...repair.identityTerms,
    ]);
  }

  const term = ensureIdentityPromptTerm(role, repair);
  repairRoleReplacementGroup(cache, repair, term);
  repairRoleAssembly(cache, repair);

  return {
    file_name: repair.file,
    script_name: cache.scriptName,
    role_id: repair.roleId,
    display_name: role.display_name,
    identity_terms: repair.identityTerms,
    prompt_term_id: term.id,
  };
}

function repairFieldLeak(cache, repair) {
  const role = findRole(cache, repair.roleId);
  const touchedStages = [];
  for (const stage of role.stages ?? []) {
    if (!repair.stageIds.includes(stage.stage_id)) continue;
    stage[repair.field] = removeTerm(stage[repair.field], repair.removeTerm);
    if (Array.isArray(stage.evidence_terms)) {
      stage.evidence_terms = stage.evidence_terms.filter(
        (term) => normalized(term) !== normalized(repair.removeTerm),
      );
    }
    touchedStages.push(stage.stage_id);
  }
  const assembly = (cache.mapping?.roleAssemblies ?? []).find(
    (item) => item.sourceRoleId === repair.roleId,
  );
  if (assembly) {
    for (const stage of assembly.stages ?? []) {
      if (!repair.stageIds.includes(stage.id)) continue;
      stage.sourceParts = stage.sourceParts ?? {};
      const beforePart = stringValue(stage.sourceParts[repair.sourcePartField]);
      const afterPart = removeTerm(beforePart, repair.removeTerm);
      const beforeSummary = stringValue(stage.sourceSummary);
      const afterSummary = beforeSummary
        .split(',')
        .map((term) => term.trim())
        .filter((term) => term && normalized(term) !== normalized(repair.removeTerm))
        .join(', ');
      if (afterPart !== beforePart) {
        stage.sourceParts[repair.sourcePartField] = afterPart;
      }
      if (afterSummary !== beforeSummary) {
        stage.sourceSummary = afterSummary || sourceSummaryFromParts(stage.sourceParts);
      }
    }
  }
  return {
    file_name: repair.file,
    script_name: cache.scriptName,
    role_id: repair.roleId,
    removed_term: repair.removeTerm,
    stage_ids: touchedStages,
  };
}

function ensureIdentityPromptTerm(role, repair) {
  role.prompt_terms = Array.isArray(role.prompt_terms) ? role.prompt_terms : [];
  const oldText = repair.replacePromptTermText;
  let term = oldText
    ? role.prompt_terms.find(
        (item) =>
          normalized(item.text) === normalized(oldText) &&
          stringValue(item.category) === 'identity',
      )
    : undefined;
  if (!term) {
    term = role.prompt_terms.find(
      (item) =>
        normalized(item.text) === normalized(repair.promptTermText) &&
        stringValue(item.category) === 'identity',
    );
  }
  if (!term) {
    term = {
      id: `role-${repair.roleId}-identity-${safeId(repair.promptTermText)}`,
      text: repair.promptTermText,
      category: 'identity',
      source_phrase: repair.sourcePhraseTerm ?? repair.promptTermText,
      source_location: 'slot prompt',
      frame_indexes: role.frame_indexes ?? [],
    };
    role.prompt_terms.push(term);
  }
  term.text = repair.promptTermText;
  term.category = 'identity';
  term.source_phrase = repair.sourcePhraseTerm ?? repair.promptTermText;
  term.source_location = term.source_location || 'slot prompt';
  term.frame_indexes = sortedInts(term.frame_indexes?.length ? term.frame_indexes : role.frame_indexes);
  term.id = `role-${repair.roleId}-identity-${safeId(repair.promptTermText)}`;
  return term;
}

function repairRoleReplacementGroup(cache, repair, term) {
  const group = (cache.mapping?.rolePromptReplacements ?? []).find(
    (item) => item.sourceRoleId === repair.roleId,
  );
  if (!group) return;
  group.displayLabel = repair.displayName;
  group.sourcePreview = previewFromPromptTerms(findRole(cache, repair.roleId).prompt_terms);
  const oldRuleId = repair.replacePromptTermText
    ? `role-${repair.roleId}-role-${repair.roleId}-identity-${safeId(repair.replacePromptTermText)}`
    : '';
  const ruleId = `role-${repair.roleId}-${term.id}`;
  let rule =
    group.rules?.find((item) => item.id === ruleId || item.id === oldRuleId) ?? null;
  if (!rule) {
    group.rules = Array.isArray(group.rules) ? group.rules : [];
    rule = { id: ruleId, sourceTerms: [] };
    group.rules.push(rule);
  }
  rule.id = ruleId;
  rule.sourceTerms = [
    {
      id: term.id,
      text: term.text,
      category: term.category,
      sourcePhrase: term.source_phrase,
      sourceLocation: term.source_location,
      frameIndexes: term.frame_indexes,
    },
  ];
}

function repairRoleAssembly(cache, repair) {
  const assembly = (cache.mapping?.roleAssemblies ?? []).find(
    (item) => item.sourceRoleId === repair.roleId,
  );
  if (!assembly) return;
  assembly.displayLabel = repair.displayName;
  assembly.sourceName = repair.displayName;
  for (const stage of assembly.stages ?? []) {
    stage.sourceParts = stage.sourceParts ?? {};
    stage.sourceParts.identity = mergeTerms(
      stage.sourceParts.identity,
      repair.identityTerms,
    );
    stage.sourceSummary = sourceSummaryFromParts(stage.sourceParts);
  }
}

function findRole(cache, roleId) {
  const role = (cache.aiRoleExtraction?.roles ?? []).find(
    (item) => item.source_role_id === roleId,
  );
  if (!role) throw new Error(`${cache.scriptName}: missing role ${roleId}`);
  return role;
}

function mergeTerms(value, terms) {
  return unique([
    ...splitTerms(value),
    ...terms,
  ]).join(', ');
}

function removeTerm(value, termToRemove) {
  return splitTerms(value)
    .filter((term) => normalized(term) !== normalized(termToRemove))
    .join(', ');
}

function sourceSummaryFromParts(parts) {
  return [
    parts.identity,
    parts.upperBody,
    parts.lowerBody,
    parts.upperClothing,
    parts.lowerClothing,
  ]
    .flatMap(splitTerms)
    .filter(Boolean)
    .join(', ');
}

function previewFromPromptTerms(terms) {
  return (Array.isArray(terms) ? terms : [])
    .map((term) => stringValue(term.text).trim())
    .filter(Boolean)
    .join(', ');
}

function splitTerms(value) {
  return stringValue(value)
    .split(',')
    .map((term) => term.trim())
    .filter(Boolean);
}

function unique(values) {
  const result = [];
  const seen = new Set();
  for (const value of values) {
    const text = stringValue(value).trim();
    const key = normalized(text);
    if (!text || seen.has(key)) continue;
    seen.add(key);
    result.push(text);
  }
  return result;
}

function sortedInts(values) {
  return [...(Array.isArray(values) ? values : [])]
    .map(Number)
    .filter((value) => Number.isInteger(value))
    .sort((left, right) => left - right);
}

function safeId(value) {
  return normalized(value).replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'term';
}

function normalized(value) {
  return stringValue(value).trim().toLowerCase().replace(/[_-]+/g, ' ');
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function parseArgs(args) {
  const parsed = {
    cacheDir: '',
    report: '',
    apply: false,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    if (key === 'apply') {
      parsed.apply = true;
      continue;
    }
    const value = args[index + 1];
    index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'report') parsed.report = value;
  }
  return parsed;
}
