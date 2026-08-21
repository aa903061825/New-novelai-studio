#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const options = parseArgs(process.argv.slice(2));
if (!options.cacheFile) {
  throw new Error('Pass --cache-file <cache.json>.');
}
if (options.apply && !options.backupDir) {
  throw new Error('--apply requires --backup-dir <directory>.');
}

const cachePath = path.resolve(options.cacheFile);
const cache = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
const roles = arrayValue(cache.aiRoleExtraction?.roles);
const replacements = arrayValue(cache.mapping?.rolePromptReplacements);
const replacementByRoleId = new Map(
  replacements
    .map((replacement) => [stringValue(replacement?.sourceRoleId), replacement])
    .filter(([roleId]) => roleId),
);

const changes = [];
const unresolved = [];
for (const role of roles) {
  const roleId = stringValue(role?.source_role_id);
  const replacement = replacementByRoleId.get(roleId);
  if (!roleId || !hasTarget(replacement)) continue;

  const evidenceByKey = sourceIdentityEvidence(role, cache.scriptSnapshot);
  for (const evidence of evidenceByKey.values()) {
    const mappedTerms = identityTermsForKey(replacement, evidence.key);
    if (mappedTerms.length > 0 && mappedTerms.every(({ term }) =>
      evidence.occurrences.every((occurrence) =>
        sourceTermCoversOccurrence(term, occurrence),
      ),
    )) {
      continue;
    }

    const target = uniqueIdentityTarget(replacement);
    if (!target) {
      unresolved.push({
        roleId,
        term: evidence.text,
        reason: 'identity target is missing or ambiguous',
      });
      continue;
    }

    const promptTerm = ensurePromptTerm(role, evidence);
    const mappingTerm = identityTermsForKey(replacement, evidence.key)
      .find(({ rule }) =>
        isReplacementRuleForTarget(rule, target),
      )?.term;

    if (mappingTerm) {
      mergeSourceEvidence(mappingTerm, evidence.occurrences, 'mapping');
      changes.push({
        roleId,
        term: evidence.text,
        action: 'extend_existing_identity_rule',
        frames: evidence.occurrences.map((occurrence) => occurrence.frameIndex),
      });
      continue;
    }

    const newMappingTerm = {
      id: promptTerm.id,
      text: evidence.text,
      category: 'character',
      sourcePhrase: evidence.text,
      sourceLocation: evidence.occurrences[0].sourceLocation,
      frameIndexes: [],
      sourceOccurrences: [],
    };
    mergeSourceEvidence(newMappingTerm, evidence.occurrences, 'mapping');
    const newRule = {
      id: stableId(`identity-rule-${roleId}-${evidence.key}`),
      sourceTerms: [newMappingTerm],
      action: 'replace',
      targetPrompt: target.targetPrompt,
    };
    replacement.rules = [newRule, ...arrayValue(replacement.rules)];
    changes.push({
      roleId,
      term: evidence.text,
      action: 'add_identity_rule',
      frames: evidence.occurrences.map((occurrence) => occurrence.frameIndex),
    });
  }
}

const result = {
  tool: 'repair_script_recast_identity_mapping_offline',
  api_used: false,
  cache_file: cachePath,
  apply_requested: options.apply,
  applied: false,
  backup_path: '',
  changes,
  unresolved,
};

if (options.apply && unresolved.length === 0 && changes.length > 0) {
  const backupDir = path.resolve(options.backupDir);
  fs.mkdirSync(backupDir, { recursive: true });
  const backupPath = path.join(backupDir, path.basename(cachePath));
  if (fs.existsSync(backupPath)) {
    throw new Error(`Refusing to overwrite existing backup: ${backupPath}`);
  }
  fs.copyFileSync(cachePath, backupPath);
  const temporaryPath = `${cachePath}.${process.pid}.tmp`;
  try {
    fs.writeFileSync(temporaryPath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
    fs.renameSync(temporaryPath, cachePath);
  } catch (error) {
    if (fs.existsSync(temporaryPath)) fs.unlinkSync(temporaryPath);
    throw error;
  }
  result.applied = true;
  result.backup_path = backupPath;
}

const serialized = `${JSON.stringify(result, null, 2)}\n`;
if (options.report) {
  const reportPath = path.resolve(options.report);
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, serialized, 'utf8');
}
process.stdout.write(serialized);
if (unresolved.length > 0) process.exitCode = 1;

function sourceIdentityEvidence(role, scriptSnapshot) {
  const result = new Map();
  const canonicalKey = normalizedTagKey(role?.canonical_name);
  const rawIdentityKeys = new Set(
    arrayValue(role?.raw_identity_tags)
      .map((tag) => normalizedTagKey(tag))
      .filter(Boolean),
  );
  const promptIdentityKeys = new Set(
    arrayValue(role?.prompt_terms)
      .filter((term) => {
        const category = normalizeText(term?.category);
        return category === 'character' || category === 'identity';
      })
      .map((term) => normalizedTagKey(term?.text))
      .filter(Boolean),
  );
  const frames = new Map(
    parsedFrames(scriptSnapshot).map((frame) => [Number(frame.index), frame]),
  );

  for (const appearance of arrayValue(role?.appearances)) {
    const sourceId = stringValue(
      appearance?.source_id ?? appearance?.sourceId,
    );
    if (!sourceId) continue;
    const sourceLocation = sourceId === 'base' ? 'base prompt' : `${sourceId} prompt`;
    for (const frameIndex of numberList(
      appearance?.frame_indexes ?? appearance?.frameIndexes,
    )) {
      const frame = frames.get(frameIndex);
      if (!frame) continue;
      for (const sourceTerm of parsePromptTags(
        promptCaptionForSource(frame, sourceId),
      )) {
        if (!isSourceIdentityTerm(sourceTerm, {
          canonicalKey,
          rawIdentityKeys,
          promptIdentityKeys,
        })) {
          continue;
        }
        const text = cleanPromptTag(sourceTerm);
        const key = normalizedTagKey(text);
        const evidence = result.get(key) ?? { key, text, occurrences: [] };
        const occurrenceKey = `${frameIndex}\u001f${sourceLocation}`;
        if (!evidence.occurrences.some((occurrence) =>
          `${occurrence.frameIndex}\u001f${occurrence.sourceLocation}` === occurrenceKey,
        )) {
          evidence.occurrences.push({ frameIndex, sourceLocation });
        }
        result.set(key, evidence);
      }
    }
  }
  return result;
}

function ensurePromptTerm(role, evidence) {
  const promptTerms = arrayValue(role.prompt_terms);
  const existing = promptTerms.find((term) =>
    normalizedTagKey(term?.text) === evidence.key &&
    ['character', 'identity'].includes(normalizeText(term?.category)),
  );
  if (existing) {
    mergeSourceEvidence(existing, evidence.occurrences, 'ai');
    return existing;
  }
  const promptTerm = {
    id: stableId(`source-identity-${role.source_role_id}-${evidence.key}`),
    text: evidence.text,
    category: 'character',
    source_phrase: evidence.text,
    source_location: evidence.occurrences[0].sourceLocation,
    frame_indexes: [],
    source_occurrences: [],
  };
  mergeSourceEvidence(promptTerm, evidence.occurrences, 'ai');
  promptTerms.push(promptTerm);
  role.prompt_terms = promptTerms;
  const rawIdentityTags = arrayValue(role.raw_identity_tags);
  if (!rawIdentityTags.some((tag) => normalizedTagKey(tag) === evidence.key)) {
    rawIdentityTags.push(evidence.text);
    role.raw_identity_tags = rawIdentityTags;
  }
  return promptTerm;
}

function identityTermsForKey(replacement, key) {
  const result = [];
  for (const rule of arrayValue(replacement?.rules)) {
    for (const term of arrayValue(rule?.sourceTerms ?? rule?.source_terms)) {
      const category = normalizeText(term?.category);
      const text = cleanPromptTag(
        term?.text ?? term?.sourcePhrase ?? term?.source_phrase,
      );
      if (
        (category === 'character' || category === 'identity') &&
        normalizedTagKey(text) === key
      ) {
        result.push({ rule, term });
      }
    }
  }
  return result;
}

function uniqueIdentityTarget(replacement) {
  const candidates = [];
  for (const rule of arrayValue(replacement?.rules)) {
    if (stringValue(rule?.action).toLowerCase() !== 'replace') continue;
    const targetPrompt = stringValue(rule?.targetPrompt);
    if (!targetPrompt) continue;
    const hasIdentityTerm = arrayValue(rule?.sourceTerms ?? rule?.source_terms).some(
      (term) => ['character', 'identity'].includes(normalizeText(term?.category)),
    );
    if (!hasIdentityTerm) continue;
    const signature = `${stringValue(replacement?.targetCharacterId)}\u001f${targetPrompt}`;
    if (!candidates.some((candidate) => candidate.signature === signature)) {
      candidates.push({ signature, targetPrompt, rule });
    }
  }
  return candidates.length === 1 ? candidates[0] : null;
}

function isReplacementRuleForTarget(rule, target) {
  return (
    stringValue(rule?.action).toLowerCase() === 'replace' &&
    stringValue(rule?.targetPrompt) === target.targetPrompt
  );
}

function mergeSourceEvidence(term, occurrences, surface) {
  const frameKey = surface === 'ai' ? 'frame_indexes' : 'frameIndexes';
  const occurrenceKey = surface === 'ai'
    ? 'source_occurrences'
    : 'sourceOccurrences';
  const frames = new Set(numberList(term[frameKey]));
  for (const occurrence of occurrences) frames.add(occurrence.frameIndex);
  term[frameKey] = [...frames].sort((left, right) => left - right);
  const existing = arrayValue(term[occurrenceKey]);
  const seen = new Set(existing.map((occurrence) =>
    `${Number(occurrence?.frameIndex ?? occurrence?.frame_index)}\u001f` +
      `${stringValue(occurrence?.sourceLocation ?? occurrence?.source_location)}`,
  ));
  for (const occurrence of occurrences) {
    const key = `${occurrence.frameIndex}\u001f${occurrence.sourceLocation}`;
    if (seen.has(key)) continue;
    existing.push(surface === 'ai'
      ? {
          frame_index: occurrence.frameIndex,
          source_location: occurrence.sourceLocation,
        }
      : {
          frameIndex: occurrence.frameIndex,
          sourceLocation: occurrence.sourceLocation,
        });
    seen.add(key);
  }
  term[occurrenceKey] = existing;
}

function sourceTermCoversOccurrence(term, occurrence) {
  const frames = numberList(term?.frameIndexes ?? term?.frame_indexes);
  if (frames.length > 0 && !frames.includes(occurrence.frameIndex)) return false;
  const occurrences = arrayValue(
    term?.sourceOccurrences ?? term?.source_occurrences,
  );
  if (occurrences.length === 0) return frames.length === 0 || frames.includes(occurrence.frameIndex);
  return occurrences.some((candidate) =>
    Number(candidate?.frameIndex ?? candidate?.frame_index) === occurrence.frameIndex &&
    stringValue(candidate?.sourceLocation ?? candidate?.source_location) ===
      occurrence.sourceLocation,
  );
}

function isSourceIdentityTerm(
  sourceTerm,
  { canonicalKey, rawIdentityKeys, promptIdentityKeys },
) {
  const cleaned = cleanPromptTag(sourceTerm);
  const key = normalizedTagKey(cleaned);
  if (!key || isBasicGenericIdentity(cleaned) || isParentheticalObjectIdentityTag(cleaned)) {
    return false;
  }
  const baseKey = parentheticalBaseKey(cleaned);
  if (canonicalKey && (key === canonicalKey || baseKey === canonicalKey)) return true;
  if (!rawIdentityKeys.has(key)) return false;
  if (canonicalKey) return key.includes(canonicalKey) || baseKey === canonicalKey;
  return promptIdentityKeys.has(key);
}

function parentheticalBaseKey(value) {
  const cleaned = cleanPromptTag(value);
  const match = cleaned.match(/^([^()]+)\s*\([^()]+\)$/);
  return normalizedTagKey(match ? match[1] : cleaned);
}

function hasTarget(replacement) {
  return Boolean(stringValue(replacement?.targetCharacterId));
}

function parsedFrames(scriptSnapshot) {
  return arrayValue(scriptSnapshot?.frames).filter((frame) =>
    stringValue(frame?.parseStatus ?? frame?.parse_status).toLowerCase() === 'parsed',
  );
}

function promptCaptionForSource(frame, sourceId) {
  if (normalizeText(sourceId) === 'base') return frame.parsed?.baseCaption;
  const match = /^slot-(\d+)$/i.exec(sourceId);
  if (!match) return '';
  return arrayValue(frame.parsed?.charCaptions)[Number(match[1])] ?? '';
}

function parsePromptTags(text) {
  return stringValue(text)
    .replace(/\r?\n/g, ',')
    .replace(/::\s*[+-]?\d+(?:\.\d+)?\s*::/g, ',')
    .replace(/::+/g, ',')
    .replace(/[\uFF0C\u3001\uFF1B]/g, ',')
    .replace(/[;|]+/g, ',')
    .split(',')
    .map(cleanPromptTag)
    .filter(Boolean);
}

function cleanPromptTag(value) {
  let text = stringValue(value).replace(/^["']|["']$/g, '').trim();
  if (!text) return '';
  text = text.replace(/\s+/g, ' ').trim();
  return text;
}

function normalizedTagKey(value) {
  return stringValue(value)
    .toLowerCase()
    .replace(/[（）［］｛｝【】〈〉《》「」『』〔〕〖〗〘〙〚〛<>＜＞“”‘’]+/g, ' ')
    .replace(/[_＿\-‐‑‒–—−]+/g, ' ')
    .replace(/[(){}\[\]'":!?，、；;]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function normalizeText(value) {
  return stringValue(value)
    .replaceAll('_', ' ')
    .replaceAll('-', ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

function isParentheticalObjectIdentityTag(term) {
  const normalized = normalizeText(term);
  if (/^(?:ring of light|light ring|halo)$/.test(normalized)) return true;
  const match = normalized.match(/^([^()]+) \(([^()]+)\)$/);
  if (!match) return false;
  const base = match[1].trim();
  const qualifier = match[2].trim();
  return (
    /^(?:sword|weapon|object|item|vehicle)$/.test(qualifier) ||
    /^(?:ring of light|light ring|halo)$/.test(base) ||
    /\b(?:sword|weapon|shield|gun|rifle|pistol|staff|wand|spear|axe|dagger|knife|blade|hammer|vehicle|motorcycle)$/.test(base)
  );
}

function isBasicGenericIdentity(value) {
  return /^(?:\d+\s*girls?|girls?|female|woman|women|\d+\s*boys?|boys?|male|males|man|men|loli|child)$/.test(
    normalizeText(value),
  );
}

function stableId(value) {
  let hash = 2166136261;
  for (const character of value) {
    hash ^= character.charCodeAt(0);
    hash = Math.imul(hash, 16777619);
  }
  const slug = value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 72);
  return `${slug || 'identity'}-${(hash >>> 0).toString(16).padStart(8, '0')}`;
}

function numberList(value) {
  return arrayValue(value).map(Number).filter(Number.isFinite);
}

function stringValue(value) {
  return value == null ? '' : String(value).trim();
}

function arrayValue(value) {
  return Array.isArray(value) ? value : [];
}

function parseArgs(args) {
  const parsed = { cacheFile: '', backupDir: '', report: '', apply: false };
  for (let index = 0; index < args.length; index += 1) {
    const key = args[index];
    if (key === '--apply') {
      parsed.apply = true;
      continue;
    }
    const value = args[index + 1];
    if (!key.startsWith('--') || value == null || value.startsWith('--')) continue;
    index += 1;
    if (key === '--cache-file') parsed.cacheFile = value;
    if (key === '--backup-dir') parsed.backupDir = value;
    if (key === '--report') parsed.report = value;
  }
  return parsed;
}
