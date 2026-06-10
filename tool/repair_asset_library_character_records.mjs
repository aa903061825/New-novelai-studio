import fs from 'node:fs';
import path from 'node:path';

const repoRoot = 'C:/Users/admin/Downloads/NAI_NEW';
const workspaceRoot =
  'C:/Users/admin/AppData/Roaming/org.exception0x0194/nai3_autodraw/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const charactersPath = path.join(libraryRoot, 'characters.json');
const fixedSeedPath = path.join(repoRoot, 'assets', 'json', 'legacy_artist_studio_seed.json');

const upperNamePattern = /^(上装|上半身|upper|upper body)$/i;
const lowerNamePattern = /^(下装|下半身|lower|lower body)$/i;
const mixedNamePattern = /混合角色候选池/;
const lowConfidenceOutfitNamePattern =
  /^(变体\s*\d+|服装|outfit|variant\s*\d+|imported outfit|preset\s*\d+)$/i;
const generatedPreviewPattern =
  /assets\/references\/(?:strict-character-previews|novelai-character-previews)\//;
const invalidNovelAiOutfitPreviewIds = new Set([
  'legacy-character-sheet-r1-outfit-2',
  'legacy-character-sheet-r5-outfit-3',
  'legacy-character-sheet-r5-outfit-4',
  'legacy-character-sheet-r5-outfit-5',
  'legacy-character-sheet-r10-outfit-3',
  'legacy-character-sheet-r24-outfit-3',
]);

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, ''));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function backup(filePath) {
  const now = new Date();
  const pad = (value) => String(value).padStart(2, '0');
  const stamp = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(
    now.getDate(),
  )}-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  const backupDir = path.join(libraryRoot, `backup-${stamp}-character-record-repair`);
  fs.mkdirSync(backupDir, { recursive: true });
  fs.copyFileSync(filePath, path.join(backupDir, path.basename(filePath)));
  return backupDir;
}

function splitPrompt(value) {
  return String(value || '')
    .replace(/\r\n?/g, '\n')
    .split(/[,\n]/)
    .map((part) => part.trim())
    .filter(Boolean);
}

function cleanTag(value) {
  return String(value || '')
    .trim()
    .replace(/^-?\d+(?:\.\d+)?::\s*/, '')
    .replace(/\s*::-?\d+(?:\.\d+)?$/, '')
    .replace(/^[:\s,[{]+/, '')
    .replace(/[:\s,\]}]+$/, '')
    .replace(/\\+/g, '')
    .replace(/\s+/g, '_')
    .toLowerCase();
}

function uniqueTags(values) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    const cleaned = cleanTag(value);
    if (!cleaned || cleaned.includes(':')) continue;
    if (seen.has(cleaned)) continue;
    seen.add(cleaned);
    result.push(cleaned);
  }
  return result;
}

function skinVariantBaseTag(value) {
  const cleaned = cleanTag(value);
  const match = /^(.+?)_(?:\([^)]+\)_)+\(([^)]+)\)$/.exec(cleaned);
  if (!match) return '';
  return `${match[1]}_(${match[2]})`;
}

function withoutSkinVariantAliases(values) {
  const tags = uniqueTags(values);
  const keys = new Set(tags);
  return tags.filter((tag) => {
    const base = skinVariantBaseTag(tag);
    return !base || !keys.has(base);
  });
}

function isDemographicIdentityTag(value) {
  return /^(girls?|boys?|males?|females?|loli|shota|child|children|young|adult|teen)$/.test(
    cleanTag(value),
  );
}

function demographicIdentityTags(character) {
  return uniqueTags([
    ...splitPrompt(character.traits?.front_full),
    ...splitPrompt(character.traits?.front_upper),
    ...splitPrompt(character.traits?.front_lower),
    ...(character.outfits || []).flatMap((outfit) => [
      ...splitPrompt(outfit.tags?.front_full),
      ...splitPrompt(outfit.tags?.front_upper),
      ...splitPrompt(outfit.tags?.front_lower),
    ]),
  ]).filter(isDemographicIdentityTag);
}

function characterIdentityTags(character) {
  return withoutSkinVariantAliases([
    ...(character.identityTags || []),
    ...(character.anchorTags || []),
    ...splitPrompt(character.traits?.front_full),
    ...demographicIdentityTags(character),
  ]);
}

function characterAnchorTags(character) {
  return withoutSkinVariantAliases([
    ...(character.anchorTags || []),
    ...splitPrompt(character.traits?.front_full).filter((tag) =>
      /\([^)]+\)/.test(tag),
    ),
  ]);
}

function mergePrompt(...values) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    for (const part of splitPrompt(value)) {
      const key = part.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      result.push(part);
    }
  }
  return result.join(', ');
}

function removeStrictPreviewRefs(refs) {
  return (refs || []).filter(
    (ref) => !String(ref).includes('assets/references/strict-character-previews/'),
  );
}

function removeGeneratedPreviewRefs(refs) {
  return (refs || []).filter((ref) => !generatedPreviewPattern.test(String(ref)));
}

function stripGeneratedRefsForInvalidPreview(outfit) {
  if (!invalidNovelAiOutfitPreviewIds.has(outfit.id)) return;
  outfit.imageRefs = removeGeneratedPreviewRefs(outfit.imageRefs);
}

function isLowConfidenceOutfit(outfit) {
  const name = String(outfit.name || '').trim();
  return !name || lowConfidenceOutfitNamePattern.test(name);
}

function normalizedOutfitName(outfit) {
  return String(outfit.name || '').trim().toLowerCase().replace(/\s+/g, ' ');
}

function mergeImageRefs(...refsLists) {
  const seen = new Set();
  const result = [];
  for (const refs of refsLists) {
    for (const ref of refs || []) {
      const trimmed = String(ref || '').trim();
      if (!trimmed || seen.has(trimmed)) continue;
      seen.add(trimmed);
      result.push(trimmed);
    }
  }
  return result;
}

function cloneSeedOutfit(outfit) {
  return {
    id: outfit.id,
    name: outfit.name,
    tags: { ...(outfit.tags || {}) },
    imageRefs: [],
    ...(outfit.source ? { source: outfit.source } : {}),
  };
}

function cloneSeedCharacter(character) {
  return {
    id: character.id,
    name: character.name,
    traits: { ...(character.traits || {}) },
    outfits: (character.outfits || []).map(cloneSeedOutfit),
    imageRefs: [],
    anchorTags: characterAnchorTags(character),
    identityTags: characterIdentityTags(character),
    aliases: [character.name].filter(Boolean),
    ...(character.defaultOutfitId ? { defaultOutfitId: character.defaultOutfitId } : {}),
    ...(character.source ? { source: character.source } : {}),
  };
}

function mergeUpperLowerIntoCharacter(character, outfit) {
  character.traits ||= {};
  const value = mergePrompt(
    outfit.tags?.front_full,
    outfit.tags?.front_upper,
    outfit.tags?.front_lower,
  );
  if (upperNamePattern.test(outfit.name || '')) {
    character.traits.front_upper = mergePrompt(character.traits.front_upper, value);
  } else if (lowerNamePattern.test(outfit.name || '')) {
    character.traits.front_lower = mergePrompt(character.traits.front_lower, value);
  }
}

function removeBadOutfits(character) {
  const kept = [];
  const removed = [];
  for (const outfit of character.outfits || []) {
    if (mixedNamePattern.test(outfit.name || '')) {
      removed.push({ id: outfit.id, name: outfit.name, reason: 'mixed character pool' });
      continue;
    }
    if (upperNamePattern.test(outfit.name || '') || lowerNamePattern.test(outfit.name || '')) {
      mergeUpperLowerIntoCharacter(character, outfit);
      removed.push({ id: outfit.id, name: outfit.name, reason: 'upper/lower prompt' });
      continue;
    }
    if (isLowConfidenceOutfit(outfit)) {
      removed.push({ id: outfit.id, name: outfit.name, reason: 'low-confidence outfit variant' });
      continue;
    }
    outfit.imageRefs = removeStrictPreviewRefs(outfit.imageRefs);
    kept.push(outfit);
  }
  character.outfits = kept;
  return removed;
}

function dedupeOutfits(character) {
  const kept = [];
  const removed = [];
  const byName = new Map();
  for (const outfit of character.outfits || []) {
    const key = normalizedOutfitName(outfit);
    if (!key) {
      removed.push({ id: outfit.id, name: outfit.name, reason: 'empty outfit name' });
      continue;
    }
    const existing = byName.get(key);
    if (existing) {
      existing.imageRefs = mergeImageRefs(existing.imageRefs, outfit.imageRefs);
      removed.push({ id: outfit.id, name: outfit.name, reason: 'duplicate outfit name' });
      continue;
    }
    byName.set(key, outfit);
    kept.push(outfit);
  }
  character.outfits = kept;
  return removed;
}

function mergeSeedTraits(character, seedCharacter) {
  character.traits ||= {};
  const seedTraits = seedCharacter.traits || {};
  if (!character.traits.front_full && seedTraits.front_full) {
    character.traits.front_full = seedTraits.front_full;
  }
  if (seedTraits.front_upper) {
    character.traits.front_upper = mergePrompt(
      character.traits.front_upper,
      seedTraits.front_upper,
    );
  }
  if (seedTraits.front_lower) {
    character.traits.front_lower = mergePrompt(
      character.traits.front_lower,
      seedTraits.front_lower,
    );
  }
}

function mergeMissingSeedOutfits(character, seedCharacter) {
  const existingIds = new Set((character.outfits || []).map((outfit) => outfit.id));
  const added = [];
  for (const seedOutfit of seedCharacter.outfits || []) {
    if (
      mixedNamePattern.test(seedOutfit.name || '') ||
      upperNamePattern.test(seedOutfit.name || '') ||
      lowerNamePattern.test(seedOutfit.name || '') ||
      isLowConfidenceOutfit(seedOutfit)
    ) {
      continue;
    }
    if (existingIds.has(seedOutfit.id)) continue;
    const outfit = cloneSeedOutfit(seedOutfit);
    character.outfits ||= [];
    character.outfits.push(outfit);
    existingIds.add(outfit.id);
    added.push({ id: outfit.id, name: outfit.name });
  }
  return added;
}

function repairDefaultOutfit(character) {
  if ((character.outfits || []).some((outfit) => outfit.id === character.defaultOutfitId)) {
    return;
  }
  if (character.outfits?.length) {
    character.defaultOutfitId = character.outfits[0].id;
  } else {
    delete character.defaultOutfitId;
  }
}

const characters = readJson(charactersPath);
const fixedSeed = readJson(fixedSeedPath);
const seedCharacters = fixedSeed.characters || [];
const seedById = new Map(seedCharacters.map((character) => [character.id, character]));
const currentById = new Map(characters.map((character) => [character.id, character]));
const backupDir = backup(charactersPath);
const report = {
  completedAt: new Date().toISOString(),
  backupDir,
  removedOutfits: [],
  addedCharacters: [],
  addedOutfits: [],
};

for (const character of characters) {
  character.imageRefs = removeStrictPreviewRefs(character.imageRefs);
  report.removedOutfits.push(
    ...removeBadOutfits(character).map((entry) => ({
      characterId: character.id,
      characterName: character.name,
      ...entry,
    })),
  );
  const seedCharacter = seedById.get(character.id);
  if (seedCharacter) {
    mergeSeedTraits(character, seedCharacter);
    report.addedOutfits.push(
      ...mergeMissingSeedOutfits(character, seedCharacter).map((entry) => ({
        characterId: character.id,
        characterName: character.name,
        ...entry,
      })),
    );
  }
  report.removedOutfits.push(
    ...dedupeOutfits(character).map((entry) => ({
      characterId: character.id,
      characterName: character.name,
      ...entry,
    })),
  );
  repairDefaultOutfit(character);
}

for (const seedCharacter of seedCharacters) {
  if (currentById.has(seedCharacter.id)) continue;
  const character = cloneSeedCharacter(seedCharacter);
  character.outfits = (character.outfits || []).filter(
    (outfit) =>
      !mixedNamePattern.test(outfit.name || '') &&
      !upperNamePattern.test(outfit.name || '') &&
      !lowerNamePattern.test(outfit.name || '') &&
      !isLowConfidenceOutfit(outfit),
  );
  report.removedOutfits.push(
    ...dedupeOutfits(character).map((entry) => ({
      characterId: character.id,
      characterName: character.name,
      ...entry,
    })),
  );
  repairDefaultOutfit(character);
  characters.push(character);
  report.addedCharacters.push({ id: character.id, name: character.name });
}

writeJson(charactersPath, characters);
writeJson(path.join(libraryRoot, 'asset_character_record_repair_report.json'), report);

console.log(JSON.stringify(report, null, 2));
