import fs from 'node:fs';
import path from 'node:path';

const FIELD_KEYS = [
  'identity',
  'upper_body',
  'lower_body',
  'upper_clothing',
  'lower_clothing',
];

const MATERIALIZE_SPECS = [
  {
    keys: ['one piece swimsuit pull'],
    stableField: 'upper_clothing',
    stableTerms: ['one-piece swimsuit'],
  },
  {
    keys: ['swimsuit pull'],
    stableField: 'upper_clothing',
    stableTerms: ['swimsuit'],
  },
  {
    keys: ['shirt lift', 'shirt pull'],
    stableField: 'upper_clothing',
    stableTerms: ['shirt'],
  },
  {
    keys: ['strap slip', 'strap slips'],
    stableField: null,
    stableTerms: [],
  },
  {
    keys: ['pants pull'],
    stableField: 'lower_clothing',
    stableTerms: ['pants'],
  },
  {
    keys: ['pantyhose pull'],
    stableField: 'lower_clothing',
    stableTerms: ['pantyhose'],
  },
  {
    keys: ['shorts pull'],
    stableField: 'lower_clothing',
    stableTerms: ['shorts'],
  },
  {
    keys: ['skirt lift'],
    stableField: 'lower_clothing',
    stableTerms: ['skirt'],
  },
];

const SPECS_BY_KEY = new Map();
for (const spec of MATERIALIZE_SPECS) {
  for (const key of spec.keys) SPECS_BY_KEY.set(key, spec);
}

const options = parseArgs(process.argv.slice(2));
if (!options.cacheDir) throw new Error('Missing --cache-dir');
if (!fs.existsSync(options.cacheDir)) throw new Error(`Missing cache dir: ${options.cacheDir}`);

const onlyFiles = options.onlyFiles
  ? new Set(options.onlyFiles.split(',').map((value) => value.trim()).filter(Boolean))
  : null;

const files = fs
  .readdirSync(options.cacheDir)
  .filter((file) => /^script-.*\.json$/u.test(file))
  .filter((file) => !onlyFiles || onlyFiles.has(file))
  .sort();

const report = {
  cache_dir: options.cacheDir,
  apply: options.apply,
  files_scanned: files.length,
  files_changed: 0,
  stages_changed: 0,
  non_role_terms_added: 0,
  stable_terms_added: 0,
  invalid_non_role_terms_removed: 0,
  files: [],
};

for (const fileName of files) {
  const filePath = path.join(options.cacheDir, fileName);
  const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const before = JSON.stringify(cache);
  const fileReport = {
    file_name: fileName,
    script_name: stringValue(cache.scriptName),
    stages_changed: 0,
    non_role_terms_added: [],
    stable_terms_added: [],
    invalid_non_role_terms_removed: [],
  };

  materializeCache(cache, fileReport);

  if (JSON.stringify(cache) !== before) {
    report.files_changed += 1;
    report.files.push(fileReport);
    if (options.apply) {
      if (options.backupDir) {
        fs.mkdirSync(options.backupDir, { recursive: true });
        const backupPath = path.join(options.backupDir, fileName);
        if (!fs.existsSync(backupPath)) fs.copyFileSync(filePath, backupPath);
      }
      fs.writeFileSync(filePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
    }
  }
}

writeJson(options.report, report);
console.log(JSON.stringify(report, null, 2));

function materializeCache(cache, fileReport) {
  const frames = frameMap(cache);
  for (const role of rolesOf(cache)) {
    let roleChanged = false;
    const appearances = Array.isArray(role.appearances) ? role.appearances : [];
    for (const stage of Array.isArray(role.stages) ? role.stages : []) {
      const before = JSON.stringify(stage);
      const sourceTerms = sourceTermsForStage(stage, appearances, frames);
      const additions = [];
      for (const term of sourceTerms) {
        const spec = SPECS_BY_KEY.get(termKey(term));
        if (!spec) continue;
        additions.push({ term, spec });
      }

      if (additions.length > 0) {
        for (const { term, spec } of additions) {
          if (appendNonRoleTerm(stage, term)) {
            report.non_role_terms_added += 1;
            fileReport.non_role_terms_added.push(stageReport(role, stage, term));
          }
          if (spec.stableField) {
            for (const stableTerm of spec.stableTerms) {
              if (ensureStableTerm(stage, spec.stableField, stableTerm)) {
                report.stable_terms_added += 1;
                fileReport.stable_terms_added.push(
                  stageReport(role, stage, stableTerm, {
                    source_term: term,
                    field: spec.stableField,
                  }),
                );
              }
            }
          }
        }
      }

      const removed = sanitizeNonRole(stage, sourceTerms);
      for (const term of removed) {
        report.invalid_non_role_terms_removed += 1;
        fileReport.invalid_non_role_terms_removed.push(stageReport(role, stage, term));
      }

      if (JSON.stringify(stage) !== before) {
        refreshStage(stage);
        roleChanged = true;
        fileReport.stages_changed += 1;
        report.stages_changed += 1;
      }
    }
    if (roleChanged) {
      role.evidence_terms = uniqueTerms(
        (Array.isArray(role.stages) ? role.stages : []).flatMap((stage) => stage.evidence_terms ?? []),
      );
      role.raw_identity_tags = uniqueTerms(
        (Array.isArray(role.stages) ? role.stages : []).flatMap((stage) => splitTerms(stage.identity)),
      );
    }
  }
}

function sourceTermsForStage(stage, appearances, frames) {
  const stageFrames = new Set((Array.isArray(stage.frame_indexes) ? stage.frame_indexes : []).map(Number));
  const terms = [];
  for (const appearance of appearances) {
    const slotMatch = /^slot-(\d+)$/u.exec(stringValue(appearance.source_id));
    if (!slotMatch) continue;
    const slotIndex = Number(slotMatch[1]);
    for (const frameIndexValue of Array.isArray(appearance.frame_indexes)
      ? appearance.frame_indexes
      : []) {
      const frameIndex = Number(frameIndexValue);
      if (!stageFrames.has(frameIndex)) continue;
      const caption = frames.get(frameIndex)?.parsed?.charCaptions?.[slotIndex];
      terms.push(...splitTerms(caption));
    }
  }
  return uniqueTerms(terms);
}

function appendNonRoleTerm(stage, term) {
  const existing = splitTerms(stage.non_role);
  const key = termKey(term);
  if (!key || existing.some((value) => termKey(value) === key)) {
    if (existing.length > 0) stage.non_role_materialized = true;
    return false;
  }
  existing.push(term);
  stage.non_role = uniqueTerms(existing).join(', ');
  stage.non_role_materialized = true;
  return true;
}

function ensureStableTerm(stage, field, stableTerm) {
  const existing = splitTerms(stage[field]);
  const stableKey = termKey(stableTerm);
  if (existing.some((term) => termSatisfiesStable(term, stableKey))) return false;
  existing.push(stableTerm);
  stage[field] = uniqueTerms(existing).join(', ');
  return true;
}

function sanitizeNonRole(stage, sourceTerms) {
  if (!('non_role' in stage) && !('non_role_materialized' in stage)) return [];
  const sourceKeys = new Set(sourceTerms.map(termKey));
  const kept = [];
  const removed = [];
  for (const term of splitTerms(stage.non_role)) {
    if (!sourceKeys.has(termKey(term))) {
      removed.push(term);
      continue;
    }
    kept.push(term);
  }
  if (kept.length > 0) {
    stage.non_role = uniqueTerms(kept).join(', ');
    stage.non_role_materialized = true;
    return removed;
  }
  delete stage.non_role;
  delete stage.non_role_materialized;
  return removed;
}

function refreshStage(stage) {
  stage.evidence_terms = stableEvidenceTerms(stage);
  const missing = new Set(Array.isArray(stage.missing_fields) ? stage.missing_fields : []);
  for (const field of FIELD_KEYS) {
    const missingKey = `missing_${field}`;
    if (stringValue(stage[field]).trim()) missing.delete(missingKey);
    else missing.add(missingKey);
  }
  stage.missing_fields = [...missing].sort();
  if (stage.field_reasons && typeof stage.field_reasons === 'object') {
    for (const field of FIELD_KEYS) {
      if (!stringValue(stage[field]).trim()) delete stage.field_reasons[field];
    }
  }
}

function stableEvidenceTerms(stage) {
  return uniqueTerms(FIELD_KEYS.flatMap((field) => splitTerms(stage[field])));
}

function termSatisfiesStable(term, stableKey) {
  const key = termKey(term);
  return key === stableKey || key.endsWith(` ${stableKey}`) || key.includes(` ${stableKey} `);
}

function stageReport(role, stage, term, extra = {}) {
  return {
    role: stringValue(role.source_role_id),
    stage: stringValue(stage.stage_id),
    term,
    ...extra,
  };
}

function frameMap(cache) {
  const result = new Map();
  for (const frame of Array.isArray(cache.scriptSnapshot?.frames)
    ? cache.scriptSnapshot.frames
    : []) {
    result.set(Number(frame.index), frame);
  }
  return result;
}

function rolesOf(cache) {
  return Array.isArray(cache.aiRoleExtraction?.roles) ? cache.aiRoleExtraction.roles : [];
}

function splitTerms(value) {
  const source = stringValue(value);
  const terms = [];
  let current = '';
  let depth = 0;
  for (const char of source) {
    if ('([{'.includes(char)) depth += 1;
    if (')]}'.includes(char) && depth > 0) depth -= 1;
    if (char === ',' && depth === 0) {
      pushTerm(terms, current);
      current = '';
    } else {
      current += char;
    }
  }
  pushTerm(terms, current);
  return terms;
}

function pushTerm(terms, value) {
  const clean = cleanDisplayTerm(value);
  if (clean) terms.push(clean);
}

function cleanDisplayTerm(value) {
  return stringValue(value)
    .replace(/\b-?\d+(?:\.\d+)?::/gu, '')
    .replace(/::/gu, '')
    .replace(/[{}[\]]/gu, '')
    .replace(/^[\s:|,+]+|[\s:|,+]+$/gu, '')
    .replace(/\s+/gu, ' ')
    .trim();
}

function termKey(value) {
  return cleanDisplayTerm(value)
    .toLowerCase()
    .replace(/[_-]+/gu, ' ')
    .replace(/\s+/gu, ' ')
    .trim();
}

function uniqueTerms(values) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    const clean = cleanDisplayTerm(value);
    const key = termKey(clean);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(clean);
  }
  return result;
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function writeJson(filePath, value) {
  if (!filePath) return;
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function parseArgs(args) {
  const parsed = {
    apply: false,
    cacheDir: undefined,
    backupDir: undefined,
    report: path.join('build', 'ntr_story_clothing_action_non_role_20260611.json'),
    onlyFiles: undefined,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--apply') {
      parsed.apply = true;
      continue;
    }
    if (arg === '--dry-run') {
      parsed.apply = false;
      continue;
    }
    if (!arg.startsWith('--')) continue;
    const equal = arg.indexOf('=');
    const key = equal > 0 ? arg.slice(2, equal) : arg.slice(2);
    const value =
      equal > 0
        ? arg.slice(equal + 1)
        : args[index + 1]?.startsWith('--')
          ? ''
          : args[index + 1] ?? '';
    if (equal < 0 && value !== '') index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'backup-dir') parsed.backupDir = value;
    if (key === 'report') parsed.report = value;
    if (key === 'only-files') parsed.onlyFiles = value;
  }
  return parsed;
}
