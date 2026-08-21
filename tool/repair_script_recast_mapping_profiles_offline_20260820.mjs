import fs from 'node:fs';
import path from 'node:path';

const DELETE_SENTINEL = '__delete__';

const args = parseArgs(process.argv.slice(2));
const cacheDir = path.resolve(args.cacheDir);
const sourceRoot = normalizePath(path.resolve(args.sourceRoot));
const profilePath = path.resolve(args.profileFile);
const characterLibraryPath = path.resolve(args.characterLibrary);
const reportPath = path.resolve(args.report);
const backupDir = args.backupDir ? path.resolve(args.backupDir) : '';

const defaultTargetIds = [
  'legacy-character-sheet-r14',
  'legacy-character-sheet-r13',
  'legacy-character-sheet-r29',
  'legacy-character-sheet-r15',
  'legacy-character-sheet-r26',
  'roccia-wuthering-waves',
  'rossi-arknights-endfield',
];
const targetIds = args.targetIds.length > 0 ? args.targetIds : defaultTargetIds;

if (!fs.existsSync(cacheDir)) throw new Error(`Missing cache dir: ${cacheDir}`);
if (!fs.existsSync(profilePath)) throw new Error(`Missing profile file: ${profilePath}`);
if (!fs.existsSync(characterLibraryPath)) {
  throw new Error(`Missing character library: ${characterLibraryPath}`);
}

const characterLibrary = loadJson(characterLibraryPath);
const characters = Array.isArray(characterLibrary)
  ? characterLibrary
  : Array.isArray(characterLibrary?.characters)
    ? characterLibrary.characters
    : [];
const targetCards = targetIds.map((id) => buildTargetCard(findCharacter(characters, id)));
if (targetCards.some((card) => !card)) {
  throw new Error('One or more requested target character cards are incomplete.');
}

const sourceTerms = new Map();
const roleCoverage = [];
const files = fs.readdirSync(cacheDir).filter((file) => file.endsWith('.json')).sort();
let filesMatched = 0;
let roleCount = 0;
let targetableRoleCount = 0;

for (const file of files) {
  const cache = loadJson(path.join(cacheDir, file));
  if (!cache || !isUnderSourceRoot(cache.sourceRootPath)) continue;
  filesMatched += 1;
  const roles = Array.isArray(cache.aiRoleExtraction?.roles)
    ? cache.aiRoleExtraction.roles
    : [];
  const replacements = new Map(
    (Array.isArray(cache.mapping?.rolePromptReplacements)
      ? cache.mapping.rolePromptReplacements
      : []
    ).map((replacement) => [stringValue(replacement.sourceRoleId), replacement]),
  );
  for (const role of roles) {
    roleCount += 1;
    if (!isTargetableRole(role)) continue;
    targetableRoleCount += 1;
    const roleTerms = [];
    for (const term of Array.isArray(role.prompt_terms) ? role.prompt_terms : []) {
      addSourceTerm(sourceTerms, term);
      roleTerms.push(term);
    }
    const replacement = replacements.get(stringValue(role.source_role_id));
    for (const rule of Array.isArray(replacement?.rules) ? replacement.rules : []) {
      for (const term of Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : []) {
        addSourceTerm(sourceTerms, term);
        roleTerms.push(term);
      }
    }
    const candidateKeys = new Set(
      roleTerms
        .map((term) => normalizeProfileTerm(term?.text))
        .filter(Boolean),
    );
    const identityKeys = roleTerms
      .filter(isIdentityCandidate)
      .map((term) => normalizeProfileTerm(term?.text))
      .filter(Boolean);
    roleCoverage.push({
      file,
      scriptName: stringValue(cache.scriptName),
      roleId: stringValue(role.source_role_id),
      displayName: stringValue(role.display_name),
      candidateKeys: [...candidateKeys],
      identityKeys: [...new Set(identityKeys)],
    });
  }
}

const builtProfiles = targetCards.map((target) => {
  const blocks = [];
  for (const entry of sourceTerms.values()) {
    const targetPrompt = targetPromptForTerm(entry, target);
    if (!targetPrompt) continue;
    const terms = entry.terms
      .sort((left, right) => left.text.localeCompare(right.text))
      .map((term, index) => ({
        id: stableId(`term-${target.id}-${entry.key}-${index}`),
        text: term.text,
        normalizedKey: normalizeProfileTerm(term.text),
        autoDetect: true,
      }));
    if (terms.length === 0) continue;
    const action = targetPrompt === DELETE_SENTINEL ? 'delete' : 'replace';
    blocks.push({
      id: stableId(`block-${target.id}-${entry.key}`),
      terms,
      matchMode: 'any',
      action,
      ...(action === 'replace' ? { targetPrompt } : {}),
    });
  }
  blocks.sort((left, right) => left.id.localeCompare(right.id));
  const uniqueBlocks = makeUniqueEntryIds(blocks);
  return {
    id: target.id,
    name: target.name,
    targetCharacterId: target.id,
    targetCharacterNameSnapshot: target.name,
    targetIdentityPrompt: target.identityPrompt,
    blocks: uniqueBlocks,
  };
});

const currentLibrary = loadJson(profilePath);
const currentProfiles = Array.isArray(currentLibrary?.profiles)
  ? currentLibrary.profiles
  : [];
const targetById = new Map(builtProfiles.map((profile) => [profile.targetCharacterId, profile]));
const existingByTargetId = new Map(
  currentProfiles
    .filter((profile) => targetById.has(stringValue(profile.targetCharacterId)))
    .map((profile) => [stringValue(profile.targetCharacterId), profile]),
);
const now = new Date().toISOString();
const outputProfiles = currentProfiles.map((profile) => {
  const target = targetById.get(stringValue(profile.targetCharacterId));
  if (!target) return profile;
  const createdAt = validTimestamp(profile.createdAt) ? profile.createdAt : now;
  return {
    id: stringValue(profile.id) || stableId(`profile-${target.targetCharacterId}`),
    name: target.name,
    targetCharacterId: target.targetCharacterId,
    targetCharacterNameSnapshot: target.targetCharacterNameSnapshot,
    targetIdentityPrompt: target.targetIdentityPrompt,
    layers: [layerFor(target)],
    createdAt,
    updatedAt: now,
  };
});
for (const target of builtProfiles) {
  if (existingByTargetId.has(target.targetCharacterId)) continue;
  outputProfiles.push({
    id: stableId(`profile-${target.targetCharacterId}`),
    name: target.name,
    targetCharacterId: target.targetCharacterId,
    targetCharacterNameSnapshot: target.targetCharacterNameSnapshot,
    targetIdentityPrompt: target.targetIdentityPrompt,
    layers: [layerFor(target)],
    createdAt: now,
    updatedAt: now,
  });
}

const output = {
  schemaVersion: 2,
  profiles: outputProfiles,
};

const reviewTerms = [
  '1girl',
  'girl',
  'bunny suit',
  'leotard',
  'tight clothing',
  'black pantyhose',
  'black socks',
  'tail',
  'cat ears',
  'animal ears',
  'hood',
  'mask',
  'black bow',
  'hair ornament',
  'white dress',
  'nude',
  'small breasts',
  'medium breasts',
  'big breasts',
  'huge breasts',
  'flat chest',
  'one-piece swimsuit',
  'school swimsuit',
  'bikini',
];

const coverage = builtProfiles.map((profile) => {
  const blockKeys = new Set(
    profile.blocks.flatMap((block) => block.terms.map((term) => term.normalizedKey)),
  );
  const covered = roleCoverage.filter((role) =>
    role.candidateKeys.some((key) => blockKeys.has(key)),
  );
  const identityCovered = roleCoverage.filter((role) =>
    (role.identityKeys.length > 0 ? role.identityKeys : role.candidateKeys).some((key) =>
      blockKeys.has(key),
    ),
  );
  return {
    targetCharacterId: profile.targetCharacterId,
    name: profile.name,
    blockCount: profile.blocks.length,
    uniqueTermCount: blockKeys.size,
    roleCount: roleCoverage.length,
    rolesCovered: covered.length,
    rolesIdentityCovered: identityCovered.length,
    missingRoleCount: roleCoverage.length - covered.length,
    missingIdentityRoleCount: roleCoverage.length - identityCovered.length,
    missingSamples: roleCoverage
      .filter((role) => !role.candidateKeys.some((key) => blockKeys.has(key)))
      .slice(0, 20),
  };
});

const validation = validateOutput(output, coverage, targetCards);
const report = {
  tool: 'repair_script_recast_mapping_profiles_offline_20260820',
  api_used: false,
  apply: args.apply,
  source_root: sourceRoot,
  cache_dir: cacheDir,
  profile_file: profilePath,
  files_matched: filesMatched,
  role_count: roleCount,
  targetable_role_count: targetableRoleCount,
  source_term_count: sourceTerms.size,
  existing_profile_count: currentProfiles.length,
  output_profile_count: outputProfiles.length,
  target_profile_previews: builtProfiles.map((profile) => ({
    targetCharacterId: profile.targetCharacterId,
    name: profile.name,
    targetIdentityPrompt: profile.targetIdentityPrompt,
    blockCount: profile.blocks.length,
    sampleBlocks: profile.blocks
      .filter((block) => block.action === 'delete' || block.targetPrompt)
      .slice(0, 20),
    reviewSamples: reviewTerms.map((term) => ({
      sourceTerm: term,
      blocks: profile.blocks
        .filter((block) => block.terms.some((candidate) =>
          normalizeProfileTerm(candidate.text) === normalizeProfileTerm(term),
        ))
        .map((block) => ({
          action: block.action,
          targetPrompt: block.targetPrompt || '',
          terms: block.terms.map((candidate) => candidate.text),
        })),
    })),
  })),
  target_profiles: coverage,
  validation,
};

fs.mkdirSync(path.dirname(reportPath), { recursive: true });
fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
if (!validation.ok) {
  throw new Error(`Mapping profile validation failed: ${validation.errors.join('; ')}`);
}

if (args.apply) {
  if (!backupDir) throw new Error('Pass --backup-dir when using --apply.');
  fs.mkdirSync(backupDir, { recursive: true });
  fs.copyFileSync(profilePath, path.join(backupDir, path.basename(profilePath)));
  fs.writeFileSync(profilePath, `${JSON.stringify(output, null, 2)}\n`, 'utf8');
}

console.log(JSON.stringify(report, null, 2));

function layerFor(profile) {
  const signature = [
    ...new Set(profile.blocks.flatMap((block) => block.terms.map((term) => term.normalizedKey))),
  ].sort();
  return {
    id: `shared-${profile.targetCharacterId}`,
    kind: 'shared',
    displayName: '全局精确映射',
    recognitionSignature: signature,
    blocks: profile.blocks,
  };
}

function validateOutput(outputLibrary, coverageRows, cards) {
  const errors = [];
  const byId = new Map(
    outputLibrary.profiles.map((profile) => [stringValue(profile.targetCharacterId), profile]),
  );
  for (const card of cards) {
    const profile = byId.get(card.id);
    if (!profile) {
      errors.push(`missing profile ${card.id}`);
      continue;
    }
    if (profile.name !== card.name) errors.push(`wrong profile name ${card.id}`);
    if (splitPromptTags(profile.targetIdentityPrompt).some((term) =>
      isCompositionTag(cleanTag(term)) ||
      hasClothingLikeText(term) ||
      isBodyState(spacedText(term)),
    )) {
      errors.push(`clothing leaked into identity prompt ${card.id}`);
    }
    if (card.id === 'legacy-character-sheet-r14') {
      const prompt = profile.targetIdentityPrompt;
      for (const required of ['girl', 'loli', 'cat_girl', '-3:: hood', '-3:: animal hood']) {
        if (!prompt.includes(required)) errors.push(`Pepe prompt missing ${required}`);
      }
    }
  }
  for (const row of coverageRows) {
    if (row.missingRoleCount > 0) {
      errors.push(`${row.name} has ${row.missingRoleCount} uncovered targetable roles`);
    }
  }
  return { ok: errors.length === 0, errors };
}

function addSourceTerm(map, rawTerm) {
  const text = stringValue(rawTerm?.text || rawTerm?.sourcePhrase).trim();
  const key = normalizeProfileTerm(text);
  if (!text || !key) return;
  const entry = map.get(key) ?? { key, terms: [], categories: new Set() };
  const category = normalizeProfileTerm(rawTerm?.category);
  const signature = `${text}\u001f${category}`;
  if (!entry.terms.some((term) => `${term.text}\u001f${term.category}` === signature)) {
    entry.terms.push({
      text,
      category,
      sourcePhrase: stringValue(rawTerm?.sourcePhrase || rawTerm?.source_phrase),
    });
  }
  if (category) entry.categories.add(category);
  map.set(key, entry);
}

function targetPromptForTerm(entry, target) {
  const terms = entry.terms;
  const source = terms.map((term) => spacedText(term.text)).join(' ');
  const classificationSource = spacedText(entry.key);
  const category = preferredCategory(entry);
  if (!source.trim()) return '';
  if (isCompositionSource(classificationSource)) return '';

  if (isGenericGirl(category, classificationSource)) return target.genericTags.join(', ');
  if (isNegatedAppearanceTerm(classificationSource)) return DELETE_SENTINEL;
  if (isBreastSizeTerm(classificationSource)) return target.breastSizePrompt;
  if (isSwimwearSuit(source, category)) return target.swimwearPrompt;
  if (isHeadConflict(classificationSource) && !isBodyState(classificationSource)) {
    if (target.id === 'legacy-character-sheet-r14') {
      return pepeHeadAnchor();
    }
    if (target.id === 'rossi-arknights-endfield') {
      return rossiHeadAnchor();
    }
  }
  if (isCharacterAnchor(category, classificationSource)) return target.anchorPrompt;
  if (isClothingCategory(category, source)) {
    const recolor = recoloredUnderwearPrompt(terms.map((term) => term.text));
    const lowerTail = isLowerDecoration(category, source) ? targetTailTags(target) : '';
    const combined = [...new Set([recolor, lowerTail].filter(Boolean))].join(', ');
    if (combined) return combined;
    if (isDisallowedClothing(source)) {
      const replacement = category === 'upperclothing'
        ? target.upperClothing
        : category === 'lowerclothing'
          ? target.lowerClothing
          : target.clothing;
      return [...new Set([replacement, lowerTail].filter(Boolean))].join(', ');
    }
    return '';
  }
  if (isPreservedHairState(source)) return '';
  if (isLowerDecoration(category, source)) return targetTailTags(target);
  if (isStableAppearance(category, source)) {
    if (hasAnyWord(source, ['tail'])) return targetTailTags(target) || DELETE_SENTINEL;
    if (hasAnyWord(source, ['hood', 'hooded', 'hat', 'bonnet', 'headwear'])) {
      return targetTagsOrDelete(target, ['hood', 'hat', 'bonnet', 'headwear']);
    }
    if (hasAnyWord(source, ['mask', 'veil'])) {
      return targetTagsOrDelete(target, ['mask', 'veil']);
    }
    if (hasAnyWord(source, ['collar', 'choker', 'necklace', 'jewelry', 'ring', 'rings'])) {
      return targetTagsOrDelete(target, ['collar', 'choker', 'necklace', 'jewelry', 'ring']);
    }
    if (hasAnyWord(source, ['ribbon', 'bow', 'ornament', 'flower', 'headdress', 'headpiece', 'band', 'bell', 'key'])) {
      return targetTagsOrDelete(target, ['ribbon', 'bow', 'ornament', 'flower', 'headdress', 'headpiece', 'band', 'bell', 'key']);
    }
    if (hasAnyWord(source, ['hair', 'ahoge', 'bun', 'braid', 'bang', 'ponytail', 'twintail'])) {
      return targetHairTags(target) || DELETE_SENTINEL;
    }
    if (hasAnyWord(source, ['eye', 'eyes', 'pupil', 'pupils', 'heterochromia'])) {
      return targetTagsOrDelete(target, ['eye', 'pupil', 'heterochromia']);
    }
    if (hasAnyWord(source, ['fang'])) return targetTagsOrDelete(target, ['fang']);
    if (hasAnyWord(source, ['ear', 'ears', 'horn', 'halo'])) {
      return targetTagsOrDelete(target, ['ear', 'horn', 'halo']);
    }
  }
  return '';
}

function buildTargetCard(character) {
  if (!character) return null;
  const id = stringValue(character.id);
  const identityTags = [
    ...(Array.isArray(character.identityTags) ? character.identityTags : []),
    ...splitPromptTags(character.traits?.front_full || ''),
    ...splitPromptTags(character.traits?.front_upper || ''),
    ...splitPromptTags(character.traits?.front_lower || ''),
  ];
  const rawStable = uniqueTags(identityTags);
  const stable = rawStable.filter((tag) =>
    !isCompositionTag(tag) &&
    !isBodyState(spacedText(tag)) &&
    !hasClothingLikeText(tag) &&
    !isLowerDecoration('lowerbody', spacedText(tag)),
  );
  const anchor = uniqueTags([
    ...(Array.isArray(character.anchorTags) ? character.anchorTags : []),
    ...stable,
  ]).find((tag) =>
    !isCompositionTag(tag) &&
    !isBodyState(spacedText(tag)) &&
    !hasClothingLikeText(tag) &&
    !isLowerDecoration('lowerbody', spacedText(tag)),
  ) || '';
  const femaleEvidence = rawStable.some((tag) =>
    tag === 'girl' || tag === 'female' || /^\d+girls?$/.test(tag) || tag.endsWith('_girl'),
  );
  const generic = id === 'legacy-character-sheet-r14'
    ? ['loli', 'girl', 'cat_girl']
    : uniqueTags([
        ...stable.filter((tag) => tag === 'girl' || tag === 'loli' || tag === 'young' || tag.endsWith('_girl')),
        ...(femaleEvidence ? ['girl'] : []),
      ]);
  const outfits = Array.isArray(character.outfits) ? character.outfits : [];
  const defaultOutfit = id === 'legacy-character-sheet-r14'
    ? outfits.find((outfit) => outfit.id === 'default-outfit-copy' || outfit.name === '无兜帽') || outfits[0]
    : outfits.find((outfit) => outfit.id === character.defaultOutfitId) || outfits[0];
  const upperClothing = uniqueTags(defaultOutfit?.partTags?.upperClothingTags || []).join(', ');
  const lowerClothing = uniqueTags(defaultOutfit?.partTags?.lowerClothingTags || []).join(', ');
  const identityPrompt = id === 'legacy-character-sheet-r14'
    ? [
        'pepe_(arknights)',
        'loli',
        'girl',
        'cat_girl',
        '1.5:: cat_ears ::',
        ...uniqueTags(stable.filter((tag) => ['animal_ear_fluff', 'animal_ears', 'hair_ornament', 'jewelry', 'long_hair', 'skin_fang', 'cat_tail'].includes(tag))),
        '-3:: hood ::',
        '-3:: wearing hood ::',
        '-3:: animal hood ::',
        '2:: lotus_flower_headdress ::',
      ].join(', ')
    : uniqueTags([anchor, ...generic, ...stable]).join(', ');
  return {
    id,
    name: id === 'legacy-character-sheet-r14'
      ? '佩佩（无兜帽）'
      : stringValue(character.name) || id,
    anchorPrompt: id === 'legacy-character-sheet-r14' ? pepeHeadAnchor() : anchor,
    genericTags: uniqueTags(generic),
    stable,
    identityPrompt,
    upperClothing,
    lowerClothing,
    clothing: uniqueTags([...splitPromptTags(upperClothing), ...splitPromptTags(lowerClothing)]).join(', '),
    swimwearPrompt: swimwearReplacement(id),
    breastSizePrompt: breastSizeReplacement(id, rawStable),
  };
}

function swimwearReplacement(id) {
  if (['legacy-character-sheet-r14', 'legacy-character-sheet-r13', 'legacy-character-sheet-r29', 'legacy-character-sheet-r15', 'legacy-character-sheet-r26'].includes(id)) {
    return 'school_swimsuit';
  }
  if (id === 'roccia-wuthering-waves') return 'frilled_bikini';
  if (id === 'rossi-arknights-endfield') return 'bikini';
  return 'bikini';
}

function breastSizeReplacement(id, rawStable = []) {
  if (['legacy-character-sheet-r14', 'legacy-character-sheet-r13', 'legacy-character-sheet-r29', 'legacy-character-sheet-r15', 'legacy-character-sheet-r26'].includes(id)) {
    return 'small_breasts';
  }
  if (['roccia-wuthering-waves', 'rossi-arknights-endfield'].includes(id)) {
    return 'medium_breasts';
  }
  const explicit = rawStable.find((tag) =>
    /^(?:small|medium|large|huge|gigantic|big)_breasts?$/.test(cleanTag(tag)) ||
    /^(?:flat|flet)_chest$/.test(cleanTag(tag)) ||
    /^alternate_breast_size_(?:larger|smaller)$/.test(cleanTag(tag)),
  );
  return explicit ? cleanTag(explicit) : DELETE_SENTINEL;
}

function targetHairTags(target) {
  return target.stable.filter((tag) =>
    /(?:hair|bang|braid|ponytail|twintail|bun|ahoge|sidelock|tress)/.test(tag) &&
    !/(?:ornament|band|ribbon|flower|bow|key)/.test(tag),
  ).join(', ');
}

function targetTailTags(target) {
  return target.stable
    .filter((tag) => /(?:^|_)tail(?:_|$)/.test(tag))
    .join(', ');
}

function targetTagsOrDelete(target, needles) {
  return targetTags(target, needles) || DELETE_SENTINEL;
}

function targetTags(target, needles) {
  return targetTagPool(target, needles)
    .filter((tag) => needles.some((needle) => targetTagMatchesNeedle(tag, needle)))
    .join(', ');
}

function targetTagPool(target, needles) {
  const normalizedNeedles = needles.map((needle) => cleanTag(needle));
  const includeDefaultOutfit = normalizedNeedles.some((needle) =>
    ['hood', 'hat', 'bonnet', 'headwear', 'collar', 'choker', 'necklace', 'jewelry', 'ring'].includes(needle),
  );
  return includeDefaultOutfit
    ? uniqueTags([...target.stable, ...splitPromptTags(target.clothing)])
    : target.stable;
}

function targetTagMatchesNeedle(tag, needle) {
  const tagTokens = cleanTag(tag).split('_').filter(Boolean);
  const needleTokens = cleanTag(needle).split('_').filter(Boolean);
  if (needleTokens.length === 0 || needleTokens.length > tagTokens.length) return false;
  for (let index = 0; index <= tagTokens.length - needleTokens.length; index += 1) {
    const matches = needleTokens.every((token, offset) =>
      singularTagToken(tagTokens[index + offset]) === singularTagToken(token),
    );
    if (matches) return true;
  }
  return false;
}

function singularTagToken(value) {
  const token = cleanTag(value);
  if (token.endsWith('ies') && token.length > 3) return token.slice(0, -3) + 'y';
  if (token.endsWith('s') && !token.endsWith('ss') && token.length > 2) return token.slice(0, -1);
  return token;
}

function isCompositionTag(tag) {
  return /^\d+(?:girls?|boys?)$/.test(tag) ||
    ['solo', 'multiple_girls', 'multiple_boys'].includes(tag);
}

function isCompositionSource(source) {
  return /^\s*\d+\s*(?:girls?|boys?)\s*$/.test(source) ||
    /^\s*(?:solo|multiple girls|multiple boys)\s*$/.test(source);
}

function preferredCategory(entry) {
  const categories = [...entry.categories];
  const clothingCategory = categories.find((category) => category.includes('clothing'));
  if (clothingCategory) return clothingCategory;
  if (entry.terms.some((term) => hasClothingLikeText(term.text) && !/[()]/.test(term.text))) {
    return 'clothing';
  }
  return categories.find((category) => category === 'identity' || category === 'character') ||
    categories[0] || '';
}

function isIdentityCandidate(term) {
  const category = normalizeProfileTerm(term?.category);
  return category === 'identity' || category === 'character';
}

function isCharacterAnchor(category, source) {
  if (category !== 'identity' && category !== 'character') return false;
  if (isGenericGirl(category, source)) return false;
  if (isBodyState(source) || hasClothingLikeText(source)) return false;
  return true;
}

function isGenericGirl(category, source) {
  return (category === 'identity' || category === 'character') &&
    /^(?:girl|loli|young|female|woman|heroine)$/.test(source.trim());
}

function isClothingCategory(category, source) {
  return category === 'clothing' || category === 'upperclothing' || category === 'lowerclothing' ||
    category === 'clothingstate' || hasClothingLikeText(source);
}

function isStableAppearance(category, source) {
  if (
    category === 'accessory' &&
    !isLowerDecoration(category, source) &&
    !hasAnyWord(source, ['hair', 'head', 'ear', 'ears', 'hood', 'hooded', 'hat', 'bonnet', 'headwear', 'headband', 'hairband', 'headdress', 'headpiece', 'veil', 'mask', 'collar', 'choker', 'necklace', 'jewelry', 'ring', 'ribbon', 'bow', 'ornament', 'flower', 'bell', 'key'])
  ) return false;
  return ['identity', 'character', 'upperbody', 'lowerbody', 'body', 'accessory'].includes(category) &&
    !isBodyState(source) &&
    hasAnyWord(source, ['hair', 'ahoge', 'bun', 'braid', 'bang', 'ponytail', 'twintail', 'ear', 'ears', 'horn', 'halo', 'tail', 'fang', 'eye', 'eyes', 'pupil', 'pupils', 'heterochromia', 'hood', 'hooded', 'hat', 'bonnet', 'headwear', 'ribbon', 'bow', 'ornament', 'jewelry', 'flower', 'headdress', 'headpiece', 'band', 'bell', 'key', 'mask', 'veil', 'collar', 'choker', 'necklace', 'ring']);
}

function isLowerDecoration(category, source) {
  if (
    category !== 'lowerbody' &&
    category !== 'lowerclothing' &&
    category !== 'accessory'
  ) return false;
  if (isNegatedAppearanceTerm(source)) return false;
  if (hasAnyWord(source, ['hair', 'head', 'face', 'ear', 'ears', 'headdress', 'headband', 'hairband'])) return false;
  const explicitLowerMarker = hasAnyWord(source, ['anklet', 'garter', 'garterbelt', 'tail', 'leg strap', 'leg ribbon', 'leg ornament', 'legwear', 'thigh strap', 'thighstrap']);
  if (explicitLowerMarker) return true;
  return category === 'lowerbody' && hasAnyWord(source, ['ornament', 'ribbon']);
}

function isNegatedAppearanceTerm(source) {
  if (isUnderwearOrHosiery(source)) return false;
  if (isBodyState(source)) return false;
  if (!/\b(?:no|without|lack of)\b/.test(source)) return false;
  return hasAnyWord(source, ['hair', 'ear', 'ears', 'horn', 'halo', 'tail', 'ornament', 'ribbon', 'headdress', 'headpiece', 'hood', 'hat', 'headband', 'hairband']);
}

function isHeadConflict(source) {
  return hasAnyWord(source, ['hood', 'hooded', 'animal hood', 'wearing hood', 'hat', 'bonnet', 'headwear']);
}

function isBreastSizeTerm(source) {
  const normalized = normalizeProfileTerm(source).replace(/[.,!?]+$/g, '');
  return /^(?:small|medium|large|huge|gigantic|big)_breasts?$/.test(normalized) ||
    /^(?:flat|flet)_chest$/.test(normalized) ||
    /^alternate_breast_size_(?:larger|smaller)$/.test(normalized);
}

function isSwimwearSuit(source, category) {
  if (
    category === 'identity' || category === 'character' ||
    category === 'clothingstate' || category === 'clothing_state'
  ) return false;
  if (hasAnyWord(source, ['aside', 'only', 'pull', 'pulled', 'lift', 'unworn', 'under clothes', 'top only', 'bottom only', 'side'])) return false;
  return hasAnyWord(source, ['swimsuit', 'swimwear', 'swim suit', 'one piece swimsuit']);
}

function isBodyState(source) {
  return hasAnyWord(source, ['ass', 'breast', 'breasts', 'cleavage', 'collarbone', 'pregnant', 'pussy', 'pubic', 'nipple', 'nipples', 'navel', 'belly', 'stomach', 'legs', 'leg', 'thighs', 'clitoris', 'clitoral', 'vulva', 'labia', 'anus', 'penis', 'testicles', 'genitals', 'cervix', 'areola']);
}

function isPreservedHairState(source) {
  return hasAnyWord(source, ['wet', 'messy', 'tousled', 'damp', 'disheveled', 'flowing', 'floating', 'loose', 'spread']);
}

function isDisallowedClothing(source) {
  return ['bunnysuit', 'bunnygirl', 'bunnycostume', 'bunny', 'rabbitgirl', 'rabbitcostume', 'rabbitsuit', 'leotard', 'bodysuit', 'catsuit', 'plugsuit', 'pilotsuit', 'unitsuit', 'unitard', 'skinsuit', 'skintight', 'tight clothing', 'tight clothes', 'tight outfit', 'tight dress', 'bodycon', 'latex', 'rubber', 'wetsuit', 'racingsuit', 'competitionwear'].some((needle) => source.replaceAll(' ', '').includes(needle.replaceAll(' ', '')));
}

function recoloredUnderwearPrompt(values) {
  for (const value of values) {
    const source = cleanTag(value);
    const spaced = ` ${source.replaceAll('_', ' ')} `;
    if (!isUnderwearOrHosiery(spaced)) continue;
    const colors = ['aqua', 'beige', 'black', 'blue', 'brown', 'cyan', 'gold', 'gray', 'green', 'grey', 'lavender', 'magenta', 'maroon', 'navy', 'orange', 'purple', 'red', 'silver', 'violet', 'yellow'];
    const hasDisallowed = colors.some((color) => hasWord(spaced, color));
    if (!hasDisallowed) continue;
    const targetColor = hasAnyWord(spaced, ['panties', 'panty', 'thong']) ? 'pink' : 'white';
    const pattern = new RegExp(`(?:^|_)(${colors.join('|')})(?=_|$)`, 'gi');
    return source.replace(pattern, targetColor).trim();
  }
  return '';
}

function isUnderwearOrHosiery(spaced) {
  return hasAnyWord(spaced, ['underwear', 'panties', 'panty', 'bra', 'lingerie', 'thong', 'garter belt', 'garterbelt', 'babydoll', 'pantyhose', 'thighhighs', 'thigh highs', 'stockings', 'stocking', 'tights', 'socks', 'sock', 'leggings']);
}

function hasClothingLikeText(value) {
  const text = ` ${String(value || '').toLowerCase().replaceAll('_', ' ')} `;
  return hasAnyWord(text, ['dress', 'shirt', 'skirt', 'coat', 'jacket', 'shorts', 'pants', 'socks', 'sock', 'shoes', 'boots', 'sandals', 'kimono', 'swimsuit', 'bikini', 'underwear', 'panties', 'pantyhose', 'thighhighs', 'thigh highs', 'stockings', 'tights', 'leggings', 'gloves', 'bra', 'lingerie', 'bodysuit', 'leotard', 'bunnysuit', 'rabbitcostume', 'maid', 'nun', 'uniform', 'clothes', 'outfit', 'costume', 'sleeve', 'sleeves', 'sash', 'strap', 'straps', 'tassel', 'button', 'buttons', 'frill', 'frills', 'pleat', 'pleats']);
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
  ) {
    return false;
  }
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

function findCharacter(charactersList, id) {
  return charactersList.find((character) => stringValue(character?.id) === id);
}

function pepeHeadAnchor() {
  return 'pepe_(arknights), 1.5:: cat_ears ::, -3:: hood ::, -3:: wearing hood ::, -3:: animal hood ::, 2:: lotus_flower_headdress ::';
}

function rossiHeadAnchor() {
  return 'rossi_(arknights), wolf_girl, wolf_ears, animal_ears, animal_ear_fluff, hood, hood_up, ears_through_hood';
}

function uniqueTags(values) {
  const result = [];
  const seen = new Set();
  for (const value of values) {
    const tag = cleanTag(value);
    if (!tag || seen.has(tag)) continue;
    seen.add(tag);
    result.push(tag);
  }
  return result;
}

function cleanTag(value) {
  return stringValue(value)
    .replace(/^[-+]?\d+(?:\.\d+)?::\s*/, '')
    .replace(/\s*::$/, '')
    .replace(/[\s-]+/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_|_$/g, '')
    .trim()
    .toLowerCase();
}

function splitPromptTags(value) {
  return String(value || '').split(',').map((part) => part.trim()).filter(Boolean);
}

function normalizeProfileTerm(value) {
  return stringValue(value)
    .trim()
    .toLowerCase()
    .replace(/[\s_]+/g, '_')
    .replace(/_+\(/g, '(')
    .replace(/\(_+/g, '(')
    .replace(/_+\)/g, ')')
    .replace(/[.,!?]+$/g, '');
}

function spacedText(value) {
  return ` ${String(value || '').replaceAll('_', ' ').replace(/\s+/g, ' ').trim().toLowerCase()} `;
}

function hasWord(spaced, word) {
  return spaced.includes(` ${word} `);
}

function hasAnyWord(spaced, words) {
  return words.some((word) => hasWord(spaced, word));
}

function isUnderSourceRoot(value) {
  const current = normalizePath(value);
  return current === sourceRoot || current.startsWith(`${sourceRoot}/`);
}

function normalizePath(value) {
  return String(value || '').replaceAll('\\', '/').replace(/\/+$/, '').toLowerCase();
}

function stableId(value) {
  return String(value).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 180) || 'profile-entry';
}

function makeUniqueEntryIds(blocks) {
  const blockIds = new Set();
  const termIds = new Set();
  return blocks.map((block) => {
    const blockSignature = block.terms.map((term) => `${term.text}\u001f${term.normalizedKey}`).join('\u001e');
    const blockId = makeUniqueId(block.id, blockSignature, blockIds);
    const terms = block.terms.map((term) => ({
      ...term,
      id: makeUniqueId(
        term.id,
        `${term.text}\u001f${term.normalizedKey}`,
        termIds,
      ),
    }));
    return { ...block, id: blockId, terms };
  });
}

function makeUniqueId(base, signature, used) {
  let candidate = base;
  if (used.has(candidate)) {
    const suffix = shortHash(signature);
    candidate = `${base}-${suffix}`;
    let counter = 2;
    while (used.has(candidate)) {
      candidate = `${base}-${suffix}-${counter}`;
      counter += 1;
    }
  }
  used.add(candidate);
  return candidate;
}

function shortHash(value) {
  let hash = 2166136261;
  for (const character of String(value)) {
    hash ^= character.codePointAt(0);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(36);
}

function validTimestamp(value) {
  return Boolean(value && !Number.isNaN(Date.parse(value)));
}

function loadJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return null;
  }
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function parseArgs(values) {
  const parsed = {
    cacheDir: '',
    sourceRoot: '',
    profileFile: '',
    characterLibrary: '',
    report: '',
    backupDir: '',
    targetIds: [],
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
    if (key === 'character-library') parsed.characterLibrary = value;
    if (key === 'report') parsed.report = value;
    if (key === 'backup-dir') parsed.backupDir = value;
    if (key === 'target-id') parsed.targetIds.push(value);
  }
  for (const key of ['cacheDir', 'sourceRoot', 'profileFile', 'characterLibrary', 'report']) {
    if (!parsed[key]) throw new Error(`Pass --${key.replace(/[A-Z]/g, (match) => `-${match.toLowerCase()}`)}.`);
  }
  return parsed;
}
