import fs from 'node:fs';
import path from 'node:path';

const defaultClassificationCache =
  'E:/NAI\u7684\u811a\u672c\u7fa4/tag_classification_cache.json';

const hardDisallowed = {
  identity: new Set([
    'artist',
    'style',
    'quality',
    'scene',
    'action',
    'camera',
    'clothing',
    'upperBody',
    'lowerBody',
    'upperClothing',
    'lowerClothing',
  ]),
  body: new Set(['artist', 'quality', 'scene', 'action', 'camera']),
  clothing: new Set(['artist', 'quality', 'scene', 'action', 'camera']),
};

const fieldSpecs = [
  {
    aiKey: 'identity',
    sourceKey: 'identity',
    bucket: 'identity',
  },
  {
    aiKey: 'upper_body',
    sourceKey: 'upperBody',
    bucket: 'body',
  },
  {
    aiKey: 'lower_body',
    sourceKey: 'lowerBody',
    bucket: 'body',
  },
  {
    aiKey: 'upper_clothing',
    sourceKey: 'upperClothing',
    bucket: 'clothing',
  },
  {
    aiKey: 'lower_clothing',
    sourceKey: 'lowerClothing',
    bucket: 'clothing',
  },
];

const options = parseArgs(process.argv.slice(2));
if (!options.cacheDir) {
  throw new Error('Missing --cache-dir');
}
if (!fs.existsSync(options.cacheDir)) {
  throw new Error(`Missing cache dir: ${options.cacheDir}`);
}

const classificationCache = loadClassificationCache(
  options.classificationCache ?? defaultClassificationCache,
);
const files = fs
  .readdirSync(options.cacheDir)
  .filter((file) => /^script-.*\.json$/u.test(file))
  .sort();

const summary = {
  cache_dir: path.resolve(options.cacheDir),
  classification_cache: options.classificationCache ?? defaultClassificationCache,
  backup_dir: options.backupDir ? path.resolve(options.backupDir) : null,
  apply: options.apply,
  files_scanned: files.length,
  files_changed: 0,
  ai_stages_changed: 0,
  mapping_stages_changed: 0,
  role_evidence_terms_changed: 0,
  removed_terms: 0,
  removed_by_category: {},
  removed_by_field: {},
  eyewear_upper_clothing_terms_preserved: 0,
  files: [],
};

for (const fileName of files) {
  const filePath = path.join(options.cacheDir, fileName);
  const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const original = JSON.stringify(cache);
  const fileReport = {
    file_name: fileName,
    script_name: stringValue(cache.scriptName),
    ai_stages_changed: 0,
    mapping_stages_changed: 0,
    removed_terms: 0,
    samples: [],
  };

  cleanExtraction(cache, classificationCache, fileReport);
  cleanMapping(cache, classificationCache, fileReport);

  if (JSON.stringify(cache) !== original) {
    summary.files_changed += 1;
    summary.files.push(fileReport);
    if (options.apply) {
      if (options.backupDir) {
        fs.mkdirSync(options.backupDir, { recursive: true });
        const backupPath = path.join(options.backupDir, fileName);
        if (!fs.existsSync(backupPath)) {
          fs.copyFileSync(filePath, backupPath);
        }
      }
      fs.writeFileSync(filePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
    }
  }
}

if (options.report) {
  fs.mkdirSync(path.dirname(options.report), { recursive: true });
  fs.writeFileSync(options.report, `${JSON.stringify(summary, null, 2)}\n`, 'utf8');
}

console.log(JSON.stringify(summary, null, 2));

function cleanExtraction(cache, classificationCache, fileReport) {
  const extraction = cache.aiRoleExtraction;
  if (!extraction || typeof extraction !== 'object') return;
  const roles = Array.isArray(extraction.roles) ? extraction.roles : [];
  for (const role of roles) {
    const roleEvidenceBefore = JSON.stringify(role.evidence_terms ?? []);
    const roleEvidenceTerms = [];
    let roleTouched = false;
    const stages = Array.isArray(role.stages) ? role.stages : [];
    for (const stage of stages) {
      const before = JSON.stringify(stage);
      for (const spec of fieldSpecs) {
        const next = cleanField({
          value: stage[spec.aiKey],
          fieldName: spec.aiKey,
          bucket: spec.bucket,
          classificationCache,
          fileReport,
        });
        stage[spec.aiKey] = next;
      }
      if (JSON.stringify(stage) !== before) {
        stage.evidence_terms = stableEvidenceTerms({
          identity: stage.identity,
          upperBody: stage.upper_body,
          lowerBody: stage.lower_body,
          upperClothing: stage.upper_clothing,
          lowerClothing: stage.lower_clothing,
        });
        stage.missing_fields = cleanMissingFields(stage);
        roleEvidenceTerms.push(...stage.evidence_terms);
        fileReport.ai_stages_changed += 1;
        summary.ai_stages_changed += 1;
        roleTouched = true;
      } else {
        roleEvidenceTerms.push(...stableEvidenceTerms({
          identity: stage.identity,
          upperBody: stage.upper_body,
          lowerBody: stage.lower_body,
          upperClothing: stage.upper_clothing,
          lowerClothing: stage.lower_clothing,
        }));
      }
    }
    if (!roleTouched) continue;
    role.evidence_terms = uniqueTerms(roleEvidenceTerms);
    role.raw_identity_tags = filterTermsByEvidence(
      role.raw_identity_tags,
      role.evidence_terms,
    );
    role.variant_tags = filterTermsByEvidence(role.variant_tags, role.evidence_terms);
    if (JSON.stringify(role.evidence_terms ?? []) !== roleEvidenceBefore) {
      summary.role_evidence_terms_changed += 1;
    }
  }
}

function cleanMapping(cache, classificationCache, fileReport) {
  const assemblies = cache.mapping?.roleAssemblies ?? cache.mapping?.role_assemblies;
  if (!Array.isArray(assemblies)) return;
  for (const assembly of assemblies) {
    const stages = Array.isArray(assembly.stages) ? assembly.stages : [];
    for (const stage of stages) {
      const before = JSON.stringify(stage);
      const sourceParts = stage.sourceParts ?? stage.source_parts ?? {};
      const nextParts = {};
      let fieldChanged = false;
      for (const spec of fieldSpecs) {
        const beforeValue = stringValue(
          sourceParts[spec.sourceKey] ?? sourceParts[toSnake(spec.sourceKey)],
        );
        const next = cleanField({
          value: beforeValue,
          fieldName: `sourceParts.${spec.sourceKey}`,
          bucket: spec.bucket,
          classificationCache,
          fileReport,
        });
        if (next !== beforeValue) fieldChanged = true;
        if (next) nextParts[spec.sourceKey] = next;
      }
      if (!fieldChanged) continue;
      stage.sourceParts = nextParts;
      if ('source_parts' in stage) delete stage.source_parts;
      stage.sourceSummary = sourceSummary(nextParts);
      if (JSON.stringify(stage) !== before) {
        fileReport.mapping_stages_changed += 1;
        summary.mapping_stages_changed += 1;
      }
    }
  }
}

function cleanField({
  value,
  fieldName,
  bucket,
  classificationCache,
  fileReport,
}) {
  const disallowed = hardDisallowed[bucket];
  const kept = [];
  let removed = false;
  for (const term of splitPromptTerms(value)) {
    const category = classificationCache.get(`positive:${normalizedTagKey(term)}`);
    if (
      category &&
      disallowed.has(category) &&
      !isEyewearUpperClothingOverride(fieldName, term)
    ) {
      recordRemoval(fileReport, fieldName, term, category);
      removed = true;
      continue;
    }
    if (isEyewearUpperClothingOverride(fieldName, term)) {
      summary.eyewear_upper_clothing_terms_preserved += 1;
    }
    kept.push(term);
  }
  return removed ? uniqueTerms(kept).join(', ') : stringValue(value);
}

function isEyewearUpperClothingOverride(fieldName, term) {
  return /upper_?clothing|upperClothing/u.test(fieldName) &&
    /\b(glasses|sunglasses|eyewear|goggles|monocle)\b/iu.test(
      normalizedTagKey(term),
    );
}

function recordRemoval(fileReport, fieldName, term, category) {
  summary.removed_terms += 1;
  summary.removed_by_category[category] =
    (summary.removed_by_category[category] ?? 0) + 1;
  summary.removed_by_field[fieldName] =
    (summary.removed_by_field[fieldName] ?? 0) + 1;
  fileReport.removed_terms += 1;
  if (fileReport.samples.length < 20) {
    fileReport.samples.push({
      field: fieldName,
      term: redactIfNeeded(term),
      category,
      reason: 'hard_category_mismatch',
    });
  }
}

function cleanMissingFields(stage) {
  if (!Array.isArray(stage.missing_fields)) return [];
  const stillMissing = new Set();
  if (!stringValue(stage.identity).trim()) stillMissing.add('missing_identity');
  if (!stringValue(stage.upper_body).trim()) stillMissing.add('missing_upper_body');
  if (!stringValue(stage.lower_body).trim()) stillMissing.add('missing_lower_body');
  if (!stringValue(stage.upper_clothing).trim()) {
    stillMissing.add('missing_upper_clothing');
  }
  if (!stringValue(stage.lower_clothing).trim()) {
    stillMissing.add('missing_lower_clothing');
  }
  return uniqueTerms(
    stage.missing_fields.filter((field) => stillMissing.has(stringValue(field))),
  );
}

function stableEvidenceTerms(parts) {
  return uniqueTerms([
    ...splitPromptTerms(parts.identity),
    ...splitPromptTerms(parts.upperBody),
    ...splitPromptTerms(parts.lowerBody),
    ...splitPromptTerms(parts.upperClothing),
    ...splitPromptTerms(parts.lowerClothing),
  ]);
}

function filterTermsByEvidence(values, evidenceTerms) {
  if (!Array.isArray(values)) return [];
  const evidenceKeys = new Set(evidenceTerms.map(normalizedTagKey));
  return uniqueTerms(
    values.filter((value) => evidenceKeys.has(normalizedTagKey(value))),
  );
}

function sourceSummary(sourceParts) {
  return fieldSpecs
    .map((spec) => stringValue(sourceParts[spec.sourceKey]).trim())
    .filter(Boolean)
    .join(', ');
}

function splitPromptTerms(value) {
  const source = stringValue(value);
  const terms = [];
  let current = '';
  let depth = 0;
  for (const char of source) {
    if ('([{'.includes(char)) depth += 1;
    if (')]}'.includes(char) && depth > 0) depth -= 1;
    if (char === ',' && depth === 0) {
      pushSplitTerm(terms, current);
      current = '';
    } else {
      current += char;
    }
  }
  pushSplitTerm(terms, current);
  return terms;
}

function pushSplitTerm(terms, value) {
  const clean = cleanPromptTerm(value);
  if (!clean) return;
  if (/^\|.*\|$/u.test(clean) && clean.includes('|')) {
    for (const part of clean.split('|')) {
      const nested = cleanPromptTerm(part);
      if (nested) terms.push(nested);
    }
    return;
  }
  terms.push(clean);
}

function cleanPromptTerm(value) {
  return stringValue(value)
    .replace(/\b-?\d+(?:\.\d+)?::/gu, '')
    .replace(/::/gu, '')
    .replace(/[{}[\]]/gu, '')
    .replace(/[|]/gu, '')
    .trim()
    .replace(
      /^((?:1\s*)?(?:girl|girls|female|woman|loli|boy|boys|male|man|men))\s+[+-]?\d+(?:\.\d+)?$/iu,
      '$1',
    )
    .replace(/\s+/gu, ' ')
    .trim();
}

function normalizedTagKey(value) {
  return cleanPromptTerm(value)
    .toLowerCase()
    .replace(/[_-]+/gu, ' ')
    .replace(/\s+/gu, ' ')
    .trim();
}

function uniqueTerms(values) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    const clean = cleanPromptTerm(value);
    const key = normalizedTagKey(clean);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(clean);
  }
  return result;
}

function loadClassificationCache(filePath) {
  const raw = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const result = new Map();
  for (const [key, value] of Object.entries(raw)) {
    if (value && typeof value.category === 'string') {
      result.set(normalizedCacheKey(key), value.category);
    }
  }
  return result;
}

function normalizedCacheKey(key) {
  const [prefix, ...parts] = String(key).split(':');
  return `${prefix}:${normalizedTagKey(parts.join(':'))}`;
}

function toSnake(value) {
  return String(value).replace(/[A-Z]/gu, (match) => `_${match.toLowerCase()}`);
}

function redactIfNeeded(term) {
  return /sex|cum|penis|pussy|nipples?|areola|orgasm|semen|masturbat|penetrat/iu.test(term)
    ? '[redacted]'
    : term;
}

function parseArgs(args) {
  const parsed = {
    apply: false,
    cacheDir: undefined,
    classificationCache: undefined,
    backupDir: undefined,
    report: undefined,
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
    const equalIndex = arg.indexOf('=');
    const key = equalIndex > 0 ? arg.slice(2, equalIndex) : arg.slice(2);
    const value =
      equalIndex > 0 ? arg.slice(equalIndex + 1) : args[index + 1] ?? '';
    if (equalIndex < 0) index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'classification-cache') parsed.classificationCache = value;
    if (key === 'backup-dir') parsed.backupDir = value;
    if (key === 'report') parsed.report = value;
  }
  return parsed;
}

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}
