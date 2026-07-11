import fs from 'node:fs';
import path from 'node:path';

const defaultClassificationCache =
  'E:/NAI\u7684\u811a\u672c\u7fa4/tag_classification_cache.json';

const options = parseArgs(process.argv.slice(2));
if (!options.cacheDir) {
  throw new Error('Pass --cache-dir <directory>.');
}

const cacheDir = path.resolve(options.cacheDir);
const reportPath = options.report ? path.resolve(options.report) : '';
const classificationCache = loadClassificationCache(
  options.classificationCache || defaultClassificationCache,
);

const fieldRules = {
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
  upper_body: new Set(['artist', 'quality', 'scene', 'action', 'camera']),
  lower_body: new Set(['artist', 'quality', 'scene', 'action', 'camera']),
  upper_clothing: new Set(['artist', 'quality', 'scene', 'action', 'camera']),
  lower_clothing: new Set(['artist', 'quality', 'scene', 'action', 'camera']),
};

const sourcePartRules = {
  identity: fieldRules.identity,
  upperBody: fieldRules.upper_body,
  lowerBody: fieldRules.lower_body,
  upperClothing: fieldRules.upper_clothing,
  lowerClothing: fieldRules.lower_clothing,
};

const files = fs
  .readdirSync(cacheDir)
  .filter((file) => file.endsWith('.json'))
  .sort();

const report = {
  cache_dir: cacheDir,
  apply: options.apply,
  files_scanned: files.length,
  files_changed: 0,
  terms_removed: 0,
  rows: [],
};

for (const file of files) {
  const filePath = path.join(cacheDir, file);
  const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const row = {
    file_name: file,
    script_id: stringValue(cache.scriptId),
    script_name: stringValue(cache.scriptName),
    terms_removed: 0,
    removals: [],
  };

  for (const role of Array.isArray(cache.aiRoleExtraction?.roles)
    ? cache.aiRoleExtraction.roles
    : []) {
    for (const stage of Array.isArray(role.stages) ? role.stages : []) {
      for (const [field, disallowed] of Object.entries(fieldRules)) {
        const result = removeDisallowedTerms(stage[field], disallowed);
        if (!result.changed) continue;
        stage[field] = result.value;
        addRemovals(row, {
          section: 'aiRoleExtraction',
          role_id: stringValue(role.source_role_id),
          stage_id: stringValue(stage.stage_id),
          field,
          removed: result.removed,
        });
      }
    }
  }

  for (const assembly of Array.isArray(cache.mapping?.roleAssemblies)
    ? cache.mapping.roleAssemblies
    : []) {
    for (const stage of Array.isArray(assembly.stages) ? assembly.stages : []) {
      const sourceParts = stage.sourceParts;
      if (!sourceParts || typeof sourceParts !== 'object') continue;
      for (const [field, disallowed] of Object.entries(sourcePartRules)) {
        const result = removeDisallowedTerms(sourceParts[field], disallowed);
        if (!result.changed) continue;
        sourceParts[field] = result.value;
        addRemovals(row, {
          section: 'mapping',
          role_id: stringValue(assembly.sourceRoleId),
          stage_id: stringValue(stage.id),
          field: `sourceParts.${field}`,
          removed: result.removed,
        });
      }
    }
  }

  if (row.terms_removed > 0) {
    report.files_changed += 1;
    report.terms_removed += row.terms_removed;
    report.rows.push(row);
    if (options.apply) {
      fs.writeFileSync(filePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
    }
  }
}

if (reportPath) {
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
}
console.log(JSON.stringify(report, null, 2));

function removeDisallowedTerms(value, disallowed) {
  const terms = splitTerms(value);
  if (terms.length === 0) {
    return { changed: false, value: stringValue(value), removed: [] };
  }
  const kept = [];
  const removed = [];
  for (const term of terms) {
    const category = classificationCache.get(`positive:${normalizedTagKey(term)}`);
    if (category && disallowed.has(category)) {
      removed.push({ term, category });
    } else {
      kept.push(term);
    }
  }
  return {
    changed: removed.length > 0,
    value: kept.join(', '),
    removed,
  };
}

function addRemovals(row, removal) {
  row.terms_removed += removal.removed.length;
  row.removals.push(removal);
}

function splitTerms(value) {
  return stringValue(value)
    .split(',')
    .map((term) => term.trim())
    .filter(Boolean);
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

function normalizedTagKey(value) {
  return stringValue(value)
    .toLowerCase()
    .replace(/[_-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function parseArgs(args) {
  const parsed = {
    cacheDir: '',
    classificationCache: '',
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
    if (key === 'classification-cache') parsed.classificationCache = value;
    if (key === 'report') parsed.report = value;
  }
  return parsed;
}
