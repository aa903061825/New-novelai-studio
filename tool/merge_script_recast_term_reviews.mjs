import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const options = parseArgs(process.argv.slice(2));
if (!options.manifest || !options.shardDir || !options.output) {
  throw new Error(
    'Usage: node tool/merge_script_recast_term_reviews.mjs ' +
      '--manifest <manifest.json> --shard-dir <dir> --output <review.json>',
  );
}

const manifestPath = path.resolve(options.manifest);
const shardDir = path.resolve(options.shardDir);
const outputPath = path.resolve(options.output);
const manifestText = fs.readFileSync(manifestPath, 'utf8');
const manifestSha256 = sha256(manifestText);
const manifest = JSON.parse(manifestText);
if (
  manifest?.kind !== 'script_recast_term_membership_manifest' ||
  Number(manifest?.schema_version) !== 1 ||
  manifest?.api_used !== false ||
  !Array.isArray(manifest?.terms)
) {
  throw new Error(`Invalid offline term manifest: ${manifestPath}`);
}
if (!fs.existsSync(shardDir)) {
  throw new Error(`Missing review shard dir: ${shardDir}`);
}

const expectedTerms = new Map();
for (const term of manifest.terms) {
  const key = normalizedTagKey(term?.term ?? term?.normalized_term);
  if (!key || expectedTerms.has(key)) {
    throw new Error(`Manifest contains an empty or duplicate term: ${key}`);
  }
  expectedTerms.set(key, cleanTag(term?.term));
}

const shardFiles = fs
  .readdirSync(shardDir)
  .filter((file) => file.toLowerCase().endsWith('.json'))
  .sort();
if (shardFiles.length === 0) {
  throw new Error(`No review shards found in ${shardDir}`);
}

const allowedRoleCategories = new Set([
  'character',
  'upperBody',
  'lowerBody',
  'upperClothing',
  'lowerClothing',
  'accessory',
  'clothingState',
  'clothing',
  'other',
]);
const decisions = new Map();
const reviewers = new Set();
const shardIndexes = new Set();
let expectedShardCount = null;
for (const file of shardFiles) {
  const shardPath = path.join(shardDir, file);
  const shard = JSON.parse(fs.readFileSync(shardPath, 'utf8'));
  if (
    shard?.kind !== 'script_recast_term_membership_review_shard' ||
    Number(shard?.schema_version) !== 1 ||
    shard?.api_used !== false ||
    !Array.isArray(shard?.decisions)
  ) {
    throw new Error(`Invalid offline review shard: ${shardPath}`);
  }
  if (stringValue(shard.manifest_sha256).trim() !== manifestSha256) {
    throw new Error(`Manifest hash mismatch in review shard: ${file}`);
  }
  const shardIndex = Number(shard.shard_index);
  const shardCount = Number(shard.shard_count);
  if (!Number.isInteger(shardIndex) || !Number.isInteger(shardCount)) {
    throw new Error(`Invalid shard index/count in ${file}`);
  }
  if (expectedShardCount == null) expectedShardCount = shardCount;
  if (expectedShardCount !== shardCount || shardIndexes.has(shardIndex)) {
    throw new Error(`Conflicting shard index/count in ${file}`);
  }
  shardIndexes.add(shardIndex);
  const reviewer = stringValue(shard.reviewer).trim();
  if (!reviewer) throw new Error(`Missing reviewer in ${file}`);
  reviewers.add(reviewer);

  for (const rawDecision of shard.decisions) {
    const term = cleanTag(rawDecision?.term);
    const key = normalizedTagKey(term);
    if (!expectedTerms.has(key)) {
      throw new Error(`Review shard contains unknown term "${term}" in ${file}`);
    }
    if (decisions.has(key)) {
      throw new Error(`Duplicate review decision for "${term}".`);
    }
    const placement = stringValue(rawDecision?.placement).trim();
    if (placement === 'unresolved') {
      throw new Error(`Term "${term}" remains unresolved in ${file}.`);
    }
    if (!['role', 'scene', 'exclude'].includes(placement)) {
      throw new Error(`Invalid placement "${placement}" for "${term}".`);
    }
    let category = stringValue(rawDecision?.category).trim();
    if (placement === 'role') {
      if (category === 'identity') category = 'character';
      if (!allowedRoleCategories.has(category)) {
        throw new Error(`Invalid role category "${category}" for "${term}".`);
      }
    } else if (placement === 'scene') {
      category = 'scene';
    } else {
      category = '';
    }
    decisions.set(key, {
      term: expectedTerms.get(key),
      placement,
      ...(category ? { category } : {}),
      reason: stringValue(rawDecision?.reason).trim(),
    });
  }
}

if (expectedShardCount !== shardFiles.length) {
  throw new Error(
    `Review shard set is incomplete: expected ${expectedShardCount}, ` +
      `found ${shardFiles.length}.`,
  );
}
for (let index = 1; index <= expectedShardCount; index += 1) {
  if (!shardIndexes.has(index)) {
    throw new Error(`Review shard ${index} is missing.`);
  }
}
const missing = [...expectedTerms.keys()].filter((key) => !decisions.has(key));
if (missing.length > 0) {
  throw new Error(
    `Review is missing ${missing.length} term decision(s): ` +
      missing.slice(0, 40).map((key) => expectedTerms.get(key)).join(', '),
  );
}

const review = {
  schema_version: 1,
  kind: 'script_recast_term_membership_review',
  api_used: false,
  reviewer: [...reviewers].sort().join(', '),
  manifest_file: manifestPath,
  manifest_sha256: manifestSha256,
  source_root_path: stringValue(manifest.source_root_path),
  cache_files: manifest.cache_files ?? [],
  decisions: manifest.terms.map((term) =>
    decisions.get(normalizedTagKey(term?.term ?? term?.normalized_term)),
  ),
};
fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(review, null, 2)}\n`, 'utf8');
const counts = {};
for (const decision of review.decisions) {
  const key = decision.placement === 'role'
    ? `role:${decision.category}`
    : decision.placement;
  counts[key] = (counts[key] ?? 0) + 1;
}
console.log(
  JSON.stringify(
    {
      api_used: false,
      output: outputPath,
      decision_count: review.decisions.length,
      reviewers: [...reviewers].sort(),
      counts,
    },
    null,
    2,
  ),
);

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function cleanTag(value) {
  return stringValue(value).trim().replace(/\s+/g, ' ');
}

function normalizedTagKey(value) {
  return cleanTag(value)
    .toLowerCase()
    .replace(/[_-]+/g, ' ')
    .replace(/[(){}\[\]'":!?锛屻€侊紱;]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function parseArgs(args) {
  const parsed = { manifest: undefined, shardDir: undefined, output: undefined };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    const value = args[index + 1];
    index += 1;
    if (key === 'manifest') parsed.manifest = value;
    if (key === 'shard-dir') parsed.shardDir = value;
    if (key === 'output') parsed.output = value;
  }
  return parsed;
}
