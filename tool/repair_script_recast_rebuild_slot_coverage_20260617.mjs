import fs from 'node:fs';
import path from 'node:path';

const options = parseArgs(process.argv.slice(2));

if (!options.cacheDir) {
  throw new Error('Pass --cache-dir <directory>.');
}

const cacheDir = path.resolve(options.cacheDir);
const repairs = [
  {
    file: 'script-4d5e53fce21f8103.json',
    frame: 29,
    slot: 1,
    roleId: 'role-anonymous-male',
  },
  {
    file: 'script-74529dcc32ff45fb.json',
    frame: 21,
    slot: 1,
    roleId: 'role-anonymous-male',
  },
  {
    file: 'script-e5fbf28b524e4996.json',
    frame: 28,
    slot: 1,
    roleId: 'role-anonymous-male',
  },
];

const report = {
  cache_dir: cacheDir,
  apply: options.apply,
  repairs: [],
  files_changed: 0,
};

const changedFiles = new Set();

for (const repair of repairs) {
  const filePath = path.join(cacheDir, repair.file);
  const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const before = JSON.stringify(cache);
  const row = applyRepair(cache, repair);
  const changed = JSON.stringify(cache) !== before;
  row.changed = changed;
  report.repairs.push(row);
  if (changed) {
    changedFiles.add(repair.file);
    if (options.apply) {
      cache.updatedAt = new Date().toISOString();
      fs.writeFileSync(filePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
    }
  }
}

report.files_changed = changedFiles.size;

console.log(JSON.stringify(report, null, 2));
if (options.report) {
  fs.mkdirSync(path.dirname(options.report), { recursive: true });
  fs.writeFileSync(options.report, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
}

function applyRepair(cache, repair) {
  const frame = (cache.scriptSnapshot?.frames ?? []).find(
    (item) => Number(item.index) === repair.frame,
  );
  const caption = stringValue(frame?.parsed?.charCaptions?.[repair.slot]).trim();
  if (!caption) {
    throw new Error(`${repair.file}: frame ${repair.frame} slot ${repair.slot} is empty.`);
  }
  if (!/\bboy\b/i.test(caption)) {
    throw new Error(
      `${repair.file}: frame ${repair.frame} slot ${repair.slot} does not contain boy evidence.`,
    );
  }

  const role = (cache.aiRoleExtraction?.roles ?? []).find(
    (item) => item.source_role_id === repair.roleId,
  );
  if (!role) {
    throw new Error(`${repair.file}: missing role ${repair.roleId}.`);
  }

  addSortedInt(role.frame_indexes, repair.frame);
  const appearance =
    (role.appearances ?? []).find(
      (item) => item.source_id === `slot-${repair.slot}`,
    ) ??
    role.appearances?.[0];
  if (!appearance) {
    throw new Error(`${repair.file}: role ${repair.roleId} has no appearance.`);
  }
  addSortedInt(appearance.frame_indexes, repair.frame);

  const stage = chooseStage(role);
  addSortedInt(stage.frame_indexes, repair.frame);
  ensureArrayValue(stage.evidence_terms, 'boy');

  const term = ensurePromptTerm(role, repair);
  const assembly = (cache.mapping?.roleAssemblies ?? []).find(
    (item) => item.sourceRoleId === repair.roleId,
  );
  if (assembly) {
    const sourceAppearance =
      (assembly.sourceAppearances ?? []).find(
        (item) => item.sourceId === `slot-${repair.slot}`,
      ) ??
      assembly.sourceAppearances?.[0];
    if (sourceAppearance) {
      addSortedInt(sourceAppearance.frameIndexes, repair.frame);
    }
    const assemblyStage = (assembly.stages ?? []).find(
      (item) => item.id === stage.stage_id,
    );
    if (assemblyStage) {
      addSortedInt(assemblyStage.frameIndexes, repair.frame);
      if (!stringValue(assemblyStage.sourceSummary).includes('boy')) {
        assemblyStage.sourceSummary = assemblyStage.sourceSummary
          ? `${assemblyStage.sourceSummary}, boy`
          : 'boy';
      }
      assemblyStage.sourceParts = assemblyStage.sourceParts ?? {};
      if (!stringValue(assemblyStage.sourceParts.identity).includes('boy')) {
        assemblyStage.sourceParts.identity = assemblyStage.sourceParts.identity
          ? `${assemblyStage.sourceParts.identity}, boy`
          : 'boy';
      }
    }
  }

  const replacementGroup = (cache.mapping?.rolePromptReplacements ?? []).find(
    (item) => item.sourceRoleId === repair.roleId,
  );
  if (replacementGroup) {
    ensureReplacementRule(replacementGroup, repair.roleId, term);
  }

  return {
    file_name: repair.file,
    script_name: cache.scriptName,
    frame_index: repair.frame,
    slot: repair.slot,
    role_id: repair.roleId,
    stage_id: stage.stage_id,
    prompt_term_id: term.id,
  };
}

function chooseStage(role) {
  const stages = role.stages ?? [];
  const withBoy = stages.find((stage) => /\bboy\b/i.test(stringValue(stage.identity)));
  const stage = withBoy ?? stages[0];
  if (!stage) {
    throw new Error(`${role.source_role_id}: no stage available.`);
  }
  return stage;
}

function ensurePromptTerm(role, repair) {
  role.prompt_terms = Array.isArray(role.prompt_terms) ? role.prompt_terms : [];
  const id = `role-${repair.roleId}-identity-boy`;
  let term = role.prompt_terms.find(
    (item) => normalized(item.text) === 'boy' && stringValue(item.category) === 'identity',
  );
  if (!term) {
    term = {
      id,
      text: 'boy',
      category: 'identity',
      source_phrase: 'boy',
      source_location: `slot-${repair.slot} prompt`,
      frame_indexes: [],
    };
    role.prompt_terms.push(term);
  }
  if (!term.id) term.id = id;
  if (!term.source_phrase) term.source_phrase = 'boy';
  if (!term.source_location) term.source_location = `slot-${repair.slot} prompt`;
  term.frame_indexes = Array.isArray(term.frame_indexes) ? term.frame_indexes : [];
  addSortedInt(term.frame_indexes, repair.frame);
  return term;
}

function ensureReplacementRule(group, sourceRoleId, term) {
  group.rules = Array.isArray(group.rules) ? group.rules : [];
  const ruleId = `role-${sourceRoleId}-${term.id}`;
  let rule = group.rules.find((item) => item.id === ruleId);
  const sourceTerm = {
    id: term.id,
    text: term.text,
    category: term.category,
    sourcePhrase: term.source_phrase,
    sourceLocation: term.source_location,
    frameIndexes: term.frame_indexes,
  };
  if (!rule) {
    rule = {
      id: ruleId,
      sourceTerms: [sourceTerm],
    };
    group.rules.push(rule);
  } else {
    rule.sourceTerms = [sourceTerm];
  }
  const previewTerms = new Set(
    stringValue(group.sourcePreview)
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean),
  );
  previewTerms.add(term.text);
  group.sourcePreview = [...previewTerms].join(', ');
}

function addSortedInt(values, value) {
  if (!Array.isArray(values)) {
    throw new Error('Expected an array.');
  }
  if (!values.includes(value)) values.push(value);
  values.sort((left, right) => Number(left) - Number(right));
}

function ensureArrayValue(values, value) {
  if (!Array.isArray(values)) return;
  if (!values.includes(value)) values.push(value);
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
