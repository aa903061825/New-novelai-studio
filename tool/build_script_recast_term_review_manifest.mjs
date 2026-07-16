import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const defaultClassificationCache =
  'E:/NAI\u7684\u811a\u672c\u7fa4/tag_classification_cache.json';
const defaultTranslationCache =
  'E:/NAI\u7684\u811a\u672c\u7fa4/trans_cache.json';

const options = parseArgs(process.argv.slice(2));
if (!options.cacheDir || !options.output) {
  throw new Error(
    'Usage: node tool/build_script_recast_term_review_manifest.mjs ' +
      '--cache-dir <dir> --output <manifest.json> ' +
      '[--source-root <dir>] [--shard-dir <dir>] [--shard-size <n>]',
  );
}

const cacheDir = path.resolve(options.cacheDir);
const outputFile = path.resolve(options.output);
if (!fs.existsSync(cacheDir)) {
  throw new Error(`Missing cache dir: ${cacheDir}`);
}
const classificationCache = loadJson(
  options.classificationCache ?? defaultClassificationCache,
  {},
);
const translationCache = loadJson(
  options.translationCache ?? defaultTranslationCache,
  {},
);
const requestedSourceRoot = normalizePath(options.sourceRoot);
const files = fs
  .readdirSync(cacheDir)
  .filter((file) => file.toLowerCase().endsWith('.json'))
  .sort()
  .filter((file) =>
    options.nameContains
      ? file.toLowerCase().includes(options.nameContains.toLowerCase())
      : true,
  )
  .slice(0, options.limit ?? undefined);

const cacheRows = [];
const terms = new Map();
for (const file of files) {
  const filePath = path.join(cacheDir, file);
  const bytes = fs.readFileSync(filePath);
  let cache;
  try {
    cache = JSON.parse(bytes.toString('utf8'));
  } catch {
    continue;
  }
  const sourceRootPath = stringValue(cache.sourceRootPath).trim();
  if (
    requestedSourceRoot &&
    !isPathInside(normalizePath(sourceRootPath), requestedSourceRoot)
  ) {
    continue;
  }
  const evidence = positiveEvidenceForCache(cache);
  const current = currentTermMembership(cache, file);
  cacheRows.push({
    file_name: file,
    script_id: stringValue(cache.scriptId).trim(),
    script_name: stringValue(cache.scriptName).trim(),
    source_root_path: sourceRootPath,
    sha256: sha256(bytes),
    positive_evidence_sha256: sha256(JSON.stringify(evidence)),
    frame_count: frameList(cache).length,
  });

  for (const row of evidence) {
    for (const tag of row.tags) {
      const normalized = normalizedTagKey(tag);
      if (!normalized) continue;
      const entry = terms.get(normalized) ?? {
        normalized,
        variants: new Map(),
        occurrences: 0,
        frames: new Set(),
        caches: new Set(),
        sourceKinds: new Set(),
        samples: [],
        aiRoleMemberships: new Set(),
        mappingRoleMemberships: new Set(),
        sceneMemberships: new Set(),
        currentCategories: new Set(),
      };
      entry.occurrences += 1;
      entry.variants.set(tag, (entry.variants.get(tag) ?? 0) + 1);
      entry.frames.add(`${file}\u001f${row.frameIndex}`);
      entry.caches.add(file);
      entry.sourceKinds.add(row.sourceKind);
      const roleIds = roleIdsForSource(cache, row.sourceId, row.frameIndex);
      if (entry.samples.length < 6) {
        const sampleKey = `${file}\u001f${row.frameIndex}\u001f${row.sourceId}`;
        if (!entry.samples.some((sample) => sample.key === sampleKey)) {
          entry.samples.push({
            key: sampleKey,
            cache_file: file,
            script_id: stringValue(cache.scriptId).trim(),
            script_name: stringValue(cache.scriptName).trim(),
            source_root_path: sourceRootPath,
            frame_index: row.frameIndex,
            source_id: row.sourceId,
            source_kind: row.sourceKind,
            role_ids: roleIds,
            caption: row.caption.slice(0, 600),
          });
        }
      }
      for (const membership of current.aiRole.get(normalized) ?? []) {
        entry.aiRoleMemberships.add(membership.key);
        if (membership.category) {
          entry.currentCategories.add(membership.category);
        }
      }
      for (const membership of current.mappingRole.get(normalized) ?? []) {
        entry.mappingRoleMemberships.add(membership.key);
        if (membership.category) {
          entry.currentCategories.add(membership.category);
        }
      }
      for (const membership of current.scene.get(normalized) ?? []) {
        entry.sceneMemberships.add(membership.key);
      }
      terms.set(normalized, entry);
    }
  }
}

const termRows = [...terms.values()]
  .map((entry) => {
    const variants = [...entry.variants.entries()].sort(
      (left, right) => right[1] - left[1] || left[0].localeCompare(right[0]),
    );
    const term = variants[0]?.[0] ?? entry.normalized;
    return {
      term,
      normalized_term: entry.normalized,
      occurrence_count: entry.occurrences,
      frame_count: entry.frames.size,
      cache_count: entry.caches.size,
      source_kinds: [...entry.sourceKinds].sort(),
      current_ai_role_count: entry.aiRoleMemberships.size,
      current_mapping_role_count: entry.mappingRoleMemberships.size,
      current_scene_count: entry.sceneMemberships.size,
      current_categories: [...entry.currentCategories].sort(),
      classification_hint: classificationHintForTerm(
        term,
        entry.normalized,
      ),
      translation_hint: translationHintForTerm(term, entry.normalized),
      variants: variants.map(([text, count]) => ({ text, count })),
      samples: entry.samples.map(({ key, ...sample }) => sample),
    };
  })
  .sort((left, right) =>
    left.normalized_term.localeCompare(right.normalized_term),
  );

const manifest = {
  schema_version: 1,
  kind: 'script_recast_term_membership_manifest',
  api_used: false,
  generated_at: new Date().toISOString(),
  cache_dir: cacheDir,
  source_root_path: options.sourceRoot ?? '',
  cache_file_count: cacheRows.length,
  source_term_count: termRows.length,
  cache_files: cacheRows,
  terms: termRows,
};
const manifestText = `${JSON.stringify(manifest, null, 2)}\n`;
const manifestSha256 = sha256(manifestText);
fs.mkdirSync(path.dirname(outputFile), { recursive: true });
fs.writeFileSync(outputFile, manifestText, 'utf8');

let shardCount = 0;
if (options.shardDir) {
  const shardDir = path.resolve(options.shardDir);
  const shardSize = Math.max(1, options.shardSize ?? 250);
  shardCount = Math.ceil(termRows.length / shardSize);
  fs.mkdirSync(shardDir, { recursive: true });
  for (let index = 0; index < shardCount; index += 1) {
    const shardTerms = termRows.slice(index * shardSize, (index + 1) * shardSize);
    const shard = {
      schema_version: 1,
      kind: 'script_recast_term_membership_review_shard',
      api_used: false,
      manifest_file: outputFile,
      manifest_sha256: manifestSha256,
      shard_index: index + 1,
      shard_count: shardCount,
      reviewer: '',
      decisions: shardTerms.map((term) => ({
        term: term.term,
        placement: 'unresolved',
        category: '',
        reason: '',
        evidence: {
          normalized_term: term.normalized_term,
          occurrence_count: term.occurrence_count,
          frame_count: term.frame_count,
          cache_count: term.cache_count,
          source_kinds: term.source_kinds,
          current_ai_role_count: term.current_ai_role_count,
          current_mapping_role_count: term.current_mapping_role_count,
          current_scene_count: term.current_scene_count,
          current_categories: term.current_categories,
          classification_hint: term.classification_hint,
          translation_hint: term.translation_hint,
          variants: term.variants,
          samples: term.samples,
        },
      })),
    };
    const fileName = `term-review-shard-${String(index + 1).padStart(3, '0')}-of-${String(shardCount).padStart(3, '0')}.json`;
    fs.writeFileSync(
      path.join(shardDir, fileName),
      `${JSON.stringify(shard, null, 2)}\n`,
      'utf8',
    );
  }
}

console.log(
  JSON.stringify(
    {
      api_used: false,
      cache_file_count: cacheRows.length,
      source_term_count: termRows.length,
      manifest_file: outputFile,
      manifest_sha256: manifestSha256,
      shard_count: shardCount,
    },
    null,
    2,
  ),
);

function positiveEvidenceForCache(cache) {
  const rows = [];
  for (const frame of frameList(cache)) {
    if (!isParsedFrame(frame)) continue;
    const frameIndex = Number(frame.index);
    const baseCaption = stringValue(frame.parsed?.baseCaption);
    rows.push({
      frameIndex,
      sourceId: 'base',
      sourceKind: 'base',
      caption: baseCaption,
      tags: parseTags(baseCaption),
    });
    const captions = Array.isArray(frame.parsed?.charCaptions)
      ? frame.parsed.charCaptions
      : [];
    captions.forEach((caption, slot) => {
      rows.push({
        frameIndex,
        sourceId: `slot-${slot}`,
        sourceKind: 'slot',
        caption: stringValue(caption),
        tags: parseTags(caption),
      });
    });
  }
  return rows;
}

function roleIdsForSource(cache, sourceId, frameIndex) {
  const result = [];
  for (const role of cache.aiRoleExtraction?.roles ?? []) {
    for (const appearance of role?.appearances ?? []) {
      if (stringValue(appearance?.source_id).trim() !== sourceId) continue;
      if (!(appearance?.frame_indexes ?? []).map(Number).includes(frameIndex)) {
        continue;
      }
      const roleId = stringValue(role?.source_role_id).trim();
      if (roleId && !result.includes(roleId)) result.push(roleId);
    }
  }
  return result.sort();
}

function currentTermMembership(cache, file) {
  const aiRole = new Map();
  const mappingRole = new Map();
  const scene = new Map();
  for (const role of cache.aiRoleExtraction?.roles ?? []) {
    const roleId = stringValue(role?.source_role_id).trim();
    for (const term of role?.prompt_terms ?? []) {
      addMembership(aiRole, term, `${file}\u001f${roleId}`);
    }
  }
  for (const replacement of cache.mapping?.rolePromptReplacements ?? []) {
    const roleId = stringValue(replacement?.sourceRoleId).trim();
    for (const rule of replacement?.rules ?? []) {
      for (const term of rule?.sourceTerms ?? []) {
        addMembership(mappingRole, term, `${file}\u001f${roleId}`);
      }
    }
  }
  for (const term of cache.aiRoleExtraction?.scene_terms ?? []) {
    addMembership(scene, term, `${file}\u001fai`);
  }
  for (const replacement of cache.mapping?.scenePromptReplacements ?? []) {
    for (const rule of replacement?.rules ?? []) {
      for (const term of rule?.sourceTerms ?? []) {
        addMembership(scene, term, `${file}\u001fmapping`);
      }
    }
  }
  return { aiRole, mappingRole, scene };
}

function addMembership(map, term, key) {
  const normalized = normalizedTagKey(term?.text);
  if (!normalized) return;
  const rows = map.get(normalized) ?? [];
  rows.push({ key, category: stringValue(term?.category).trim() });
  map.set(normalized, rows);
}

function classificationHintForTerm(term, normalized) {
  const candidates = uniqueExact([
    term,
    term.toLowerCase(),
    normalized,
    normalized.replace(/\s+/g, '_'),
    normalized.replace(/\s+/g, '-'),
  ]);
  for (const candidate of candidates) {
    const entry = classificationCache[`positive:${candidate}`];
    if (entry && typeof entry === 'object') {
      return {
        category: stringValue(entry.category).trim(),
        source: stringValue(entry.source).trim(),
      };
    }
  }
  return {};
}

function translationHintForTerm(term, normalized) {
  const candidates = uniqueExact([
    `${term}_en2zh`,
    `${term.toLowerCase()}_en2zh`,
    `${normalized}_en2zh`,
  ]);
  for (const candidate of candidates) {
    const entry = translationCache[candidate];
    if (typeof entry === 'string' && entry.trim()) return entry.trim();
    if (entry && typeof entry === 'object') {
      const translation = stringValue(entry.translation).trim();
      if (translation) return translation;
    }
  }
  return '';
}

function frameList(cache) {
  return Array.isArray(cache?.scriptSnapshot?.frames)
    ? cache.scriptSnapshot.frames
    : [];
}

function isParsedFrame(frame) {
  return frame?.parsed && frame.parseStatus !== 'failed';
}

function parseTags(text) {
  return stripNegativeWeightedGroups(stringValue(text).replace(/\r?\n/g, ','))
    .replace(/::\s*[+-]?\d+(?:\.\d+)?\s*::/g, ',')
    .replace(/::+/g, ',')
    .replace(/[\uFF0C\u3001\uFF1B]/g, ',')
    .replace(/[锛屻€侊紱;|]+/g, ',')
    .split(',')
    .map(cleanTag)
    .filter(Boolean);
}

function stripNegativeWeightedGroups(text) {
  return stringValue(text).replace(/-\d+(?:\.\d+)?\s*::[\s\S]*?::/g, ',');
}

function cleanTag(value) {
  let text = stringValue(value).trim();
  if (!text) return '';
  text = text.replace(/^["']|["']$/g, '').trim();
  if (/^-\d+(?:\.\d+)?\s*::\s*/.test(text)) return '';
  let changed = true;
  while (changed) {
    const match = text.match(/^([+-]?\d+(?:\.\d+)?)\s*::\s*/);
    if (match && Number(match[1]) <= 0) return '';
    const next = text.replace(/^[+]?\d+(?:\.\d+)?\s*::\s*/g, '').trim();
    changed = next !== text;
    text = next;
  }
  text = text.replace(/::+$/g, '').replace(/^:+|:+$/g, '').trim();
  const weighted = text.match(/^\((.*):([+-]?\d+(?:\.\d+)?)\)$/);
  if (weighted) {
    if (Number(weighted[2]) <= 0) return '';
    text = weighted[1].trim();
  }
  let unwrapped = true;
  while (unwrapped) {
    const match = text.match(/^\(([^()]+)\)$/);
    if (!match) {
      unwrapped = false;
    } else {
      text = match[1].trim();
    }
  }
  return text
    .replace(/^[{}\[\]]+|[{}\[\]]+$/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function normalizedTagKey(value) {
  return stringValue(value)
    .toLowerCase()
    .replace(/[_-]+/g, ' ')
    .replace(/[(){}\[\]'":!?锛屻€侊紱;]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function normalizePath(value) {
  return stringValue(value)
    .replace(/\\/g, '/')
    .replace(/\/+$/g, '')
    .toLowerCase();
}

function isPathInside(candidate, root) {
  return candidate === root || candidate.startsWith(`${root}/`);
}

function uniqueExact(values) {
  const result = [];
  const seen = new Set();
  for (const value of values) {
    const text = stringValue(value).trim();
    if (!text || seen.has(text)) continue;
    seen.add(text);
    result.push(text);
  }
  return result;
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function loadJson(filePath, fallback) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return fallback;
  }
}

function parseArgs(args) {
  const parsed = {
    cacheDir: undefined,
    output: undefined,
    sourceRoot: undefined,
    shardDir: undefined,
    shardSize: undefined,
    classificationCache: undefined,
    translationCache: undefined,
    nameContains: undefined,
    limit: undefined,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    const value = args[index + 1];
    index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'output') parsed.output = value;
    if (key === 'source-root') parsed.sourceRoot = value;
    if (key === 'shard-dir') parsed.shardDir = value;
    if (key === 'shard-size') parsed.shardSize = Number(value);
    if (key === 'classification-cache') parsed.classificationCache = value;
    if (key === 'translation-cache') parsed.translationCache = value;
    if (key === 'name-contains') parsed.nameContains = value;
    if (key === 'limit') parsed.limit = Number(value);
  }
  return parsed;
}
