import fs from 'node:fs';
import path from 'node:path';

const TARGETS = [
  {
    id: 'legacy-character-sheet-r14',
    name: '佩佩（无兜帽）',
    swimwearPrompt: 'school_swimsuit',
    breastSizePrompt: 'small_breasts',
  },
  {
    id: 'legacy-character-sheet-r13',
    name: '铃兰',
    swimwearPrompt: 'school_swimsuit',
    breastSizePrompt: 'small_breasts',
  },
  {
    id: 'legacy-character-sheet-r29',
    name: '巫恋',
    swimwearPrompt: 'school_swimsuit',
    breastSizePrompt: 'small_breasts',
  },
  {
    id: 'legacy-character-sheet-r15',
    name: '迷迭香',
    swimwearPrompt: 'school_swimsuit',
    breastSizePrompt: 'small_breasts',
  },
  {
    id: 'legacy-character-sheet-r26',
    name: '薄绿',
    swimwearPrompt: 'school_swimsuit',
    breastSizePrompt: 'small_breasts',
  },
  {
    id: 'roccia-wuthering-waves',
    name: '洛可可',
    swimwearPrompt: 'frilled_bikini',
    breastSizePrompt: 'medium_breasts',
  },
  {
    id: 'rossi-arknights-endfield',
    name: '洛茜',
    swimwearPrompt: 'bikini',
    breastSizePrompt: 'medium_breasts',
  },
];

const args = parseArgs(process.argv.slice(2));
const cacheDir = path.resolve(args.cacheDir);
const sourceRoot = normalizePath(args.sourceRoot);
const profileFile = path.resolve(args.profileFile);
const reportFile = path.resolve(args.report);
const backupFile = args.backupFile ? path.resolve(args.backupFile) : '';

if (!fs.existsSync(cacheDir)) throw new Error(`Missing cache directory: ${cacheDir}`);
if (!fs.existsSync(profileFile)) throw new Error(`Missing profile library: ${profileFile}`);

const library = loadJson(profileFile);
if (!library || !Array.isArray(library.profiles)) {
  throw new Error(`Invalid role mapping profile library: ${profileFile}`);
}

const profiles = TARGETS.map((target) => {
  const matches = library.profiles.filter(
    (profile) => profile?.targetCharacterId === target.id,
  );
  if (matches.length !== 1) {
    throw new Error(`Expected one profile for ${target.id}, found ${matches.length}.`);
  }
  return { target, profile: matches[0] };
});

const discovered = discoverSourceTerms(cacheDir, sourceRoot);
const changes = [];
for (const { target, profile } of profiles) {
  const swimwear = mergeRuleBlock({
    profile,
    kind: 'swimwear',
    terms: discovered.swimwearTerms,
    blockId: `block-${target.id}-swimwear-replacement`,
    targetPrompt: target.swimwearPrompt,
  });
  const breastSize = mergeRuleBlock({
    profile,
    kind: 'breast-size',
    terms: discovered.breastSizeTerms,
    blockId: `block-${target.id}-breast-size-replacement`,
    targetPrompt: target.breastSizePrompt,
  });
  if (swimwear.changed || breastSize.changed) {
    profile.updatedAt = new Date().toISOString();
  }
  recomputeRecognitionSignatures(profile);
  changes.push({
    targetCharacterId: target.id,
    name: target.name,
    swimwearPrompt: target.swimwearPrompt,
    breastSizePrompt: target.breastSizePrompt,
    swimwear,
    breastSize,
  });
}

const validation = validate(profiles, discovered);
const report = {
  tool: 'repair_script_recast_swimwear_breast_size_offline_20260821',
  api_used: false,
  apply: args.apply,
  source_root: sourceRoot,
  cache_dir: cacheDir,
  profile_file: profileFile,
  discovered_source_file_count: discovered.filesMatched,
  swimwear_terms: discovered.swimwearTerms.map(reportTerm),
  breast_size_terms: discovered.breastSizeTerms.map(reportTerm),
  target_profiles: changes,
  validation,
};

fs.mkdirSync(path.dirname(reportFile), { recursive: true });
fs.writeFileSync(reportFile, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
if (!validation.ok) {
  throw new Error(`Swimwear/breast-size validation failed: ${validation.errors.join('; ')}`);
}

if (args.apply) {
  if (!backupFile) throw new Error('Pass --backup-file when using --apply.');
  fs.mkdirSync(path.dirname(backupFile), { recursive: true });
  fs.copyFileSync(profileFile, backupFile);
  fs.writeFileSync(profileFile, `${JSON.stringify(library, null, 2)}\n`, 'utf8');
}

console.log(JSON.stringify(report, null, 2));

function discoverSourceTerms(cacheDirectory, root) {
  const swimwear = new Map();
  const breastSize = new Map();
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
        const category = normalizeProfileTerm(candidate?.category);
        if (!text) continue;
        if (isSwimwearSuit(text, category)) addTerm(swimwear, text, category, fileName, role);
        if (isBreastSizeTerm(text)) addTerm(breastSize, text, category, fileName, role);
      }
    }
  }
  return {
    filesMatched,
    swimwearTerms: [...swimwear.values()].sort(termSort),
    breastSizeTerms: [...breastSize.values()].sort(termSort),
  };
}

function addTerm(map, text, category, fileName, role) {
  const key = normalizeProfileTerm(text);
  if (!key) return;
  const entry = map.get(key) || {
    key,
    text,
    files: new Set(),
    roles: new Set(),
    categories: new Set(),
  };
  entry.files.add(fileName);
  entry.roles.add(stringValue(role?.source_role_id));
  if (category) entry.categories.add(category);
  map.set(key, entry);
}

function mergeRuleBlock({ profile, kind, terms, blockId, targetPrompt }) {
  const desiredKeys = new Set(terms.map((term) => term.key));
  const layers = Array.isArray(profile.layers) ? profile.layers : [];
  let targetLayer = layers.find((layer) =>
    (layer.blocks || []).some((block) => block.id === blockId),
  );
  if (!targetLayer) {
    targetLayer = layers.find((layer) => layer.kind === 'shared') || layers[0];
  }
  if (!targetLayer) throw new Error(`Profile ${profile.targetCharacterId} has no mapping layer.`);

  let targetBlock = (targetLayer.blocks || []).find((block) => block.id === blockId);
  const originalTargetPrompt = targetBlock?.targetPrompt;
  const originalTargetTermKeys = (targetBlock?.terms || [])
    .map((term) => normalizeProfileTerm(term?.text))
    .sort()
    .join('\u0000');
  const originalTargetTermIds = (targetBlock?.terms || [])
    .map((term) => stringValue(term?.id))
    .join('\u0000');
  const originalBlockCount = (profile.layers || []).flatMap((layer) => layer.blocks || []).length;
  const existingByKey = new Map();
  const movedFrom = [];
  const removedBlocks = [];
  for (const layer of layers) {
    const keptBlocks = [];
    for (const block of Array.isArray(layer.blocks) ? layer.blocks : []) {
      const blockTerms = Array.isArray(block.terms) ? block.terms : [];
      const keptTerms = [];
      let removedFromBlock = false;
      for (const term of blockTerms) {
        const key = normalizeProfileTerm(term?.text);
        if (!desiredKeys.has(key)) {
          keptTerms.push(term);
          continue;
        }
        removedFromBlock = true;
        if (!existingByKey.has(key)) existingByKey.set(key, term);
        if (block.id !== blockId) movedFrom.push({ blockId: block.id, term: term.text });
      }
      if (removedFromBlock) {
        block.terms = keptTerms;
      }
      if (block.terms?.length === 0 && block.id !== blockId) {
        removedBlocks.push(block.id);
        continue;
      }
      keptBlocks.push(block);
      if (block.id === blockId) targetBlock = block;
    }
    layer.blocks = keptBlocks;
  }

  const usedTermIds = new Set();
  const generatedTerms = terms.map((entry) => {
    const existing = existingByKey.get(entry.key);
    const baseId = existing?.id || stableId(`term-${profile.targetCharacterId}-${kind}-${entry.key}`);
    let termId = baseId;
    let suffix = 1;
    while (usedTermIds.has(termId)) {
      termId = stableId(`${baseId}-${suffix}`);
      suffix += 1;
    }
    usedTermIds.add(termId);
    return {
      ...(existing || {}),
      id: termId,
      text: entry.text,
      normalizedKey: entry.key,
    };
  });
  if (!targetBlock) {
    targetBlock = {
      id: blockId,
      terms: [],
      matchMode: 'any',
      action: 'replace',
      targetPrompt,
    };
    targetLayer.blocks = [...(targetLayer.blocks || []), targetBlock];
  }
  targetBlock.terms = generatedTerms;
  targetBlock.matchMode = 'any';
  targetBlock.action = 'replace';
  targetBlock.targetPrompt = targetPrompt;

  const finalBlockCount = (profile.layers || []).flatMap((layer) => layer.blocks || []).length;
  const addedTerms = terms.filter((term) => !existingByKey.has(term.key)).map((term) => term.text);
  const finalTargetTermKeys = generatedTerms
    .map((term) => normalizeProfileTerm(term.text))
    .sort()
    .join('\u0000');
  const finalTargetTermIds = generatedTerms.map((term) => stringValue(term.id)).join('\u0000');
  const targetChanged = originalTargetPrompt !== targetPrompt ||
    originalTargetTermKeys !== finalTargetTermKeys ||
    originalTargetTermIds !== finalTargetTermIds;
  return {
    kind,
    blockId,
    targetPrompt,
    sourceTermCount: terms.length,
    sourceTerms: terms.map((term) => term.text),
    addedTerms,
    movedFrom,
    removedBlocks,
    originalBlockCount,
    finalBlockCount,
    changed: addedTerms.length > 0 || movedFrom.length > 0 || removedBlocks.length > 0 || targetChanged,
  };
}

function validate(profileRows, discovered) {
  const errors = [];
  for (const { target, profile } of profileRows) {
    if (target.id === 'rossi-arknights-endfield' &&
        !String(profile.targetIdentityPrompt || '').includes('wolf_ears')) {
      errors.push('Rossi identity prompt lost wolf_ears');
    }
    for (const spec of [
      ['swimwear', discovered.swimwearTerms, `block-${target.id}-swimwear-replacement`, target.swimwearPrompt],
      ['breast-size', discovered.breastSizeTerms, `block-${target.id}-breast-size-replacement`, target.breastSizePrompt],
    ]) {
      const [kind, terms, blockId, prompt] = spec;
      const matches = (profile.layers || [])
        .flatMap((layer) => layer.blocks || [])
        .filter((block) => block.id === blockId);
      if (matches.length !== 1) {
        errors.push(`${target.id} ${kind} block count is ${matches.length}`);
        continue;
      }
      const block = matches[0];
      if (block.action !== 'replace' || block.targetPrompt !== prompt) {
        errors.push(`${target.id} ${kind} block has the wrong action or target`);
      }
      const keys = block.terms.map((term) => normalizeProfileTerm(term.text));
      if (new Set(keys).size !== keys.length) errors.push(`${target.id} ${kind} block has duplicate terms`);
      const termIds = block.terms.map((term) => stringValue(term.id)).filter(Boolean);
      if (new Set(termIds).size !== termIds.length) errors.push(`${target.id} ${kind} block has duplicate term ids`);
      for (const term of terms) {
        if (keys.filter((key) => key === term.key).length !== 1) {
          errors.push(`${target.id} ${kind} is missing ${term.text}`);
        }
      }
    }
  }
  return { ok: errors.length === 0, errors };
}

function recomputeRecognitionSignatures(profile) {
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
}

function reportTerm(term) {
  return {
    text: term.text,
    normalizedKey: term.key,
    sourceFileCount: term.files.size,
    sourceRoleCount: term.roles.size,
    categories: [...term.categories].sort(),
  };
}

function termSort(left, right) {
  return left.text.localeCompare(right.text) || left.key.localeCompare(right.key);
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
  if (!text.trim() || (/(?:boy|male|man|old man|fat man|muscular male|dark skinned male|father|dad|uncle|sensei|teacher|shota|doctor arknights|producer|shido|shidou|yuuki|monster|tentacle|orc)/.test(text) && !knownFemaleCharacter)) return false;
  if (knownFemaleCharacter || /\b(?:girl|girls|female|woman|women|heroine|1girl|2girls|3girls)\b/.test(text)) return true;
  return [...(Array.isArray(role?.raw_identity_tags) ? role.raw_identity_tags : []), role?.canonical_name]
    .map(stringValue)
    .some((value) => value.trim() && !/^(?:girl|female|woman|male|man|boy)$/i.test(value.trim()));
}

function isSwimwearSuit(value, category) {
  if (category === 'identity' || category === 'character' ||
      category === 'clothingstate' || category === 'clothing_state') return false;
  const source = spacedText(value);
  if (!hasAnyWord(source, ['swimsuit', 'swimwear', 'swim suit'])) return false;
  if (hasAnyWord(source, ['aside', 'only', 'pull', 'pulled', 'lift', 'unworn', 'under clothes', 'top only', 'bottom only', 'side'])) return false;
  return true;
}

function isBreastSizeTerm(value) {
  const normalized = normalizeProfileTerm(value).replace(/[.,!?]+$/g, '');
  return /^(?:small|medium|large|huge|gigantic|big)_breasts?$/.test(normalized) ||
    /^(?:flat|flet)_chest$/.test(normalized) ||
    /^alternate_breast_size_(?:larger|smaller)$/.test(normalized);
}

function spacedText(value) {
  return ` ${String(value || '').replaceAll('_', ' ').replace(/\s+/g, ' ').trim().toLowerCase()} `;
}

function hasAnyWord(spaced, words) {
  return words.some((word) => spaced.includes(` ${word} `));
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
