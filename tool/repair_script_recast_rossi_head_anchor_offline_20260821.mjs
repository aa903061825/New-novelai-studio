import fs from 'node:fs';
import path from 'node:path';

const args = parseArgs(process.argv.slice(2));
const cacheDir = path.resolve(args.cacheDir);
const sourceRoot = normalizePath(args.sourceRoot);
const profileFile = path.resolve(args.profileFile);
const reportFile = path.resolve(args.report);
const backupFile = args.backupFile ? path.resolve(args.backupFile) : '';
const targetId = 'rossi-arknights-endfield';
const headAnchor =
  'rossi_(arknights), wolf_girl, wolf_ears, animal_ears, animal_ear_fluff, hood, hood_up, ears_through_hood';

if (!fs.existsSync(cacheDir)) throw new Error(`Missing cache directory: ${cacheDir}`);
const library = loadJson(profileFile);
if (!library || !Array.isArray(library.profiles)) {
  throw new Error(`Invalid role mapping profile library: ${profileFile}`);
}

const profile = library.profiles.find(
  (entry) => entry?.targetCharacterId === targetId,
);
if (!profile) throw new Error(`Missing Rossi profile: ${targetId}`);

const changes = [];
const headBlock = (profile.layers || [])
  .flatMap((layer) => Array.isArray(layer.blocks) ? layer.blocks : [])
  .find((block) => block.id === 'block-rossi-arknights-endfield-backwards-hat');
if (!headBlock) throw new Error('Missing Rossi headwear block.');

for (const layer of Array.isArray(profile.layers) ? profile.layers : []) {
  for (const block of Array.isArray(layer.blocks) ? layer.blocks : []) {
    if (block.action !== 'replace') continue;
    const matchingTerms = (Array.isArray(block.terms) ? block.terms : [])
      .map((term) => stringValue(term?.text).trim())
      .filter((term) => isHeadConflict(term) && !isBodyState(term) && !isNegatedAppearanceTerm(term));
    if (matchingTerms.length === 0) continue;
    if (block.targetPrompt === headAnchor) continue;
    const before = block.targetPrompt || '';
    block.targetPrompt = headAnchor;
    changes.push({
      layerId: layer.id || '',
      blockId: block.id || '',
      matchingTerms: [...new Set(matchingTerms)],
      before,
      after: headAnchor,
    });
  }
}

const existingTermKeys = new Set(
  (profile.layers || [])
    .flatMap((layer) => Array.isArray(layer.blocks) ? layer.blocks : [])
    .flatMap((block) => Array.isArray(block.terms) ? block.terms : [])
    .map((term) => normalizeProfileTerm(term?.text)),
);
const discovered = discoverMissingHeadTerms(cacheDir, sourceRoot, existingTermKeys);
const addedTerms = discovered.terms.map((entry) => {
  const normalizedKey = normalizeProfileTerm(entry.text);
  return {
    id: stableId(`term-${targetId}-backwards-hat-${normalizedKey}`),
    text: entry.text,
    normalizedKey,
  };
});
headBlock.terms = [
  ...(Array.isArray(headBlock.terms) ? headBlock.terms : []),
  ...addedTerms,
].sort((left, right) => {
  const keyCompare = String(left.normalizedKey || '').localeCompare(String(right.normalizedKey || ''));
  return keyCompare || String(left.text || '').localeCompare(String(right.text || '')) ||
    String(left.id || '').localeCompare(String(right.id || ''));
});
for (const layer of profile.layers || []) {
  layer.recognitionSignature = [
    ...new Set(
      (layer.blocks || [])
        .flatMap((block) => block.terms || [])
        .map((term) => normalizeProfileTerm(term.text))
        .filter(Boolean),
    ),
  ].sort();
}
if (changes.length > 0 || addedTerms.length > 0) {
  profile.updatedAt = new Date().toISOString();
}

const validation = validate(profile, changes, addedTerms);
const report = {
  tool: 'repair_script_recast_rossi_head_anchor_offline_20260821',
  api_used: false,
  apply: args.apply,
  cache_dir: cacheDir,
  source_root: sourceRoot,
  profile_file: profileFile,
  target_character_id: targetId,
  target_profile_name: profile.name,
  head_anchor: headAnchor,
  changed_block_count: changes.length,
  changes,
  discovered_source_file_count: discovered.filesMatched,
  added_term_count: addedTerms.length,
  added_terms: addedTerms.map((term) => ({
    text: term.text,
    normalizedKey: term.normalizedKey,
  })),
  validation,
};

fs.mkdirSync(path.dirname(reportFile), { recursive: true });
fs.writeFileSync(reportFile, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
if (!validation.ok) {
  throw new Error(`Rossi head-anchor validation failed: ${validation.errors.join('; ')}`);
}

if (args.apply) {
  if (!backupFile) throw new Error('Pass --backup-file when using --apply.');
  fs.mkdirSync(path.dirname(backupFile), { recursive: true });
  fs.copyFileSync(profileFile, backupFile);
  fs.writeFileSync(profileFile, `${JSON.stringify(library, null, 2)}\n`, 'utf8');
}

console.log(JSON.stringify(report, null, 2));

function validate(targetProfile, changed, added) {
  const errors = [];
  if (!targetProfile.targetIdentityPrompt.includes('wolf_ears')) {
    errors.push('Rossi identity prompt is missing wolf_ears');
  }
  if (changed.length === 0) {
    const hasHeadAnchor = (targetProfile.layers || [])
      .flatMap((layer) => layer.blocks || [])
      .some((block) => block.targetPrompt === headAnchor);
    if (!hasHeadAnchor) errors.push('No Rossi head block carries the wolf-ear anchor');
  }
  for (const change of changed) {
    if (!change.after.includes('wolf_ears')) {
      errors.push(`Changed block ${change.blockId} is missing wolf_ears`);
    }
  }
  const headTerms = new Set(
    (targetProfile.layers || [])
      .flatMap((layer) => layer.blocks || [])
      .find((block) => block.id === 'block-rossi-arknights-endfield-backwards-hat')?.terms
      ?.map((term) => normalizeProfileTerm(term.text)) || [],
  );
  for (const term of added) {
    if (!headTerms.has(term.normalizedKey)) {
      errors.push(`Added head term is missing from Rossi head block: ${term.text}`);
    }
    if (!isHeadConflict(term.text) || isBodyState(term.text) || isNegatedAppearanceTerm(term.text)) {
      errors.push(`Added term is not a valid non-body head term: ${term.text}`);
    }
  }
  return { ok: errors.length === 0, errors };
}

function discoverMissingHeadTerms(cacheDirectory, root, existingKeys) {
  const terms = new Map();
  let filesMatched = 0;
  for (const fileName of fs.readdirSync(cacheDirectory).filter((name) => name.endsWith('.json')).sort()) {
    const cache = loadJson(path.join(cacheDirectory, fileName));
    if (!cache || !isUnderSourceRoot(cache.sourceRootPath, root)) continue;
    filesMatched += 1;
    const replacements = new Map(
      (Array.isArray(cache.mapping?.rolePromptReplacements)
        ? cache.mapping.rolePromptReplacements
        : [])
        .map((replacement) => [stringValue(replacement?.sourceRoleId), replacement]),
    );
    for (const role of Array.isArray(cache.aiRoleExtraction?.roles) ? cache.aiRoleExtraction.roles : []) {
      if (!isTargetableRole(role)) continue;
      const candidates = [
        ...(Array.isArray(role.prompt_terms) ? role.prompt_terms : []),
        ...((replacements.get(stringValue(role.source_role_id))?.rules || [])
          .flatMap((rule) => Array.isArray(rule.sourceTerms) ? rule.sourceTerms : [])),
      ];
      for (const candidate of candidates) {
        const text = stringValue(candidate?.text || candidate?.sourcePhrase || candidate?.source_phrase).trim();
        const key = normalizeProfileTerm(text);
        if (!key || existingKeys.has(key) || !isHeadConflict(text) ||
            isBodyState(text) || isNegatedAppearanceTerm(text)) continue;
        const entry = terms.get(key) || { text, files: new Set(), categories: new Set() };
        entry.files.add(fileName);
        const category = normalizeProfileTerm(candidate?.category);
        if (category) entry.categories.add(category);
        terms.set(key, entry);
      }
    }
  }
  return {
    filesMatched,
    terms: [...terms.values()].sort((left, right) => left.text.localeCompare(right.text)),
  };
}

function isTargetableRole(role) {
  const sourceKind = normalizeProfileTerm(role?.source_kind || role?.sourceKind);
  if (sourceKind === 'global' || sourceKind === 'shared') return false;
  const rawIdentityTags = Array.isArray(role?.raw_identity_tags)
    ? role.raw_identity_tags.map(stringValue).map((value) => value.trim().toLowerCase()).filter(Boolean)
    : [];
  if (
    rawIdentityTags.length > 0 &&
    rawIdentityTags.every((tag) => /^(?:(?:black|white|brown|grey|gray|red|blue|wild|large|small) )?(?:animal|bear|cat|cow|dog|horse|pig|rabbit|wolf)$/.test(tag))
  ) return false;
  const text = [
    role?.source_role_id,
    role?.display_name,
    role?.canonical_name,
    ...(Array.isArray(role?.raw_identity_tags) ? role.raw_identity_tags : []),
  ].map(stringValue).join(' ').toLowerCase().replaceAll('_', ' ');
  const knownFemaleCharacter = /\bpecorine\b/.test(text);
  if (!text.trim() || (/\b(?:boy|male|man|old man|fat man|muscular male|dark skinned male|father|dad|uncle|sensei|teacher|shota|doctor arknights|producer|shido|shidou|yuuki|monster|tentacle|orc)\b/.test(text) && !knownFemaleCharacter)) return false;
  if (knownFemaleCharacter || /\b(?:girl|girls|female|woman|women|heroine|1girl|2girls|3girls)\b/.test(text)) return true;
  return [...(Array.isArray(role?.raw_identity_tags) ? role.raw_identity_tags : []), role?.canonical_name]
    .map(stringValue)
    .some((value) => value.trim() && !/^(?:girl|female|woman|male|man|boy)$/i.test(value.trim()));
}

function isHeadConflict(value) {
  const spaced = ` ${String(value || '').toLowerCase().replaceAll('_', ' ').replace(/\s+/g, ' ').trim()} `;
  return ['hood', 'hooded', 'animal hood', 'wearing hood', 'hat', 'bonnet', 'headwear']
    .some((word) => spaced.includes(` ${word} `));
}

function isBodyState(value) {
  const spaced = ` ${String(value || '').toLowerCase().replaceAll('_', ' ').replace(/\s+/g, ' ').trim()} `;
  return ['ass', 'breast', 'breasts', 'cleavage', 'collarbone', 'pregnant', 'pussy', 'pubic', 'nipple', 'nipples', 'navel', 'belly', 'stomach', 'legs', 'leg', 'thighs', 'thigh', 'clitoris', 'clitoral', 'vulva', 'labia', 'anus', 'penis', 'testicles', 'genitals', 'cervix', 'areola']
    .some((word) => spaced.includes(` ${word} `));
}

function isNegatedAppearanceTerm(value) {
  const spaced = ` ${String(value || '').toLowerCase().replaceAll('_', ' ').replace(/\s+/g, ' ').trim()} `;
  if (!/(?: no | without | lack of )/.test(spaced)) return false;
  return ['hair', 'ear', 'ears', 'horn', 'halo', 'tail', 'ornament', 'ribbon', 'headdress', 'headpiece', 'hood', 'hat', 'headband', 'hairband']
    .some((word) => spaced.includes(` ${word} `));
}

function normalizeProfileTerm(value) {
  return stringValue(value).trim().toLowerCase().replace(/[\s_]+/g, '_');
}

function isUnderSourceRoot(value, root) {
  const current = normalizePath(value);
  return current === root || current.startsWith(`${root}/`);
}

function normalizePath(value) {
  return stringValue(value).replaceAll('\\', '/').replace(/\/+$/, '').toLowerCase();
}

function stableId(value) {
  return String(value).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 180) || 'profile-entry';
}

function loadJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function parseArgs(values) {
  const parsed = {
    cacheDir: '',
    sourceRoot: '',
    profileFile: '',
    report: '',
    backupFile: '',
    apply: false,
  };
  for (let index = 0; index < values.length; index += 1) {
    const arg = values[index];
    if (arg === '--apply') {
      parsed.apply = true;
      continue;
    }
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    const value = values[++index];
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'source-root') parsed.sourceRoot = value;
    if (key === 'profile-file') parsed.profileFile = value;
    if (key === 'report') parsed.report = value;
    if (key === 'backup-file') parsed.backupFile = value;
  }
  if (!parsed.cacheDir || !parsed.sourceRoot || !parsed.profileFile || !parsed.report) {
    throw new Error('Pass --cache-dir, --source-root, --profile-file, and --report.');
  }
  return parsed;
}
