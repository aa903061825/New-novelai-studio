import fs from 'node:fs';
import path from 'node:path';

const repoRoot = process.cwd();
const workspaceRoot =
  process.argv.find((arg) => arg.startsWith('--workspace='))?.slice(12) ||
  'C:/Users/admin/AppData/Roaming/org.exception0x0194/nai3_autodraw/novel_studio';
const apply = process.argv.includes('--apply');

const libraryRoot = path.join(workspaceRoot, 'library');
const charactersPath = path.join(libraryRoot, 'characters.json');
const seedPath = path.join(repoRoot, 'assets/json/legacy_artist_studio_seed.json');
const localDanbooruTagsPath = path.join(repoRoot, 'tool/asset-library-danbooru-tags.json');
const danbooruQueriesPath = path.join(repoRoot, 'tool/asset-library-danbooru-queries.json');
const postCachePath = path.join(repoRoot, 'tool/asset-library-danbooru-post-tags-cache.json');
const reportPath = path.join(libraryRoot, 'asset_default_outfit_backfill_report.json');

const defaultOutfitId = 'default-outfit';
const defaultOutfitName = '\u9ed8\u8ba4\u670d\u88c5';

const blockedTags = new Set([
  'loli',
  'young',
  'nude',
  'naked',
  'nipples',
  'areolae',
  'ass',
  'breasts',
  'pussy',
  'penis',
  'sex',
  'cum',
  'cameltoe',
  'underboob',
  'sideboob',
  'large_breasts',
  'small_breasts',
  'huge_breasts',
  'navel',
  'topless',
  'topless_female',
  'convenient_censoring',
  'panties',
  'panties_under_pantyhose',
  'bikini_bottom_only',
  'clothes_down',
  'no_shoes',
  'see-through_clothes',
  'torn_clothes',
  'torn_sleeves',
  'untied_bikini',
  'unworn_bikini_top',
  'wet_clothes',
  'cleavage',
  'covered_navel',
  'thighs',
]);

const ignoredExactTags = new Set([
  '1girl',
  '1boy',
  'girl',
  'boy',
  '2boys',
  '2girls',
  '6+girls',
  'absurdres',
  'alternate_costume',
  'character_name',
  'chibi',
  'chibi_only',
  'copyright_logo',
  'feet_out_of_frame',
  'full_body',
  'highres',
  'indoors',
  'logo',
  'looking_at_viewer',
  'mihuashi_username',
  'multiple_boys',
  'multiple_girls',
  'official_alternate_costume',
  'official_art',
  'official_wallpaper',
  'one_eye_closed',
  'second-party_source',
  'simple_background',
  'smile',
  'solo',
  'spoken_object',
  'standing',
]);

const ignoredPattern =
  /(^|_)(arm|bad|background|between_legs|cropped|dated|feet_apart|hand|jumping|knees|source|username|wallpaper|logo|text|watermark|signature|composition|portrait|quality|score|rating|view|pose|sitting|standing|lying|running|walking|looking|smile|closed_mouth|open_mouth|holding|reaching|on_stomach|from_|solo|multiple)($|_)/;

const weaponPattern =
  /(^|_)(weapon|sword|gun|rifle|staff|wand|book|sistrum|umbrella|shield|spear|knife|axe)($|_)/;

const upperClothingPattern =
  /(^|_)(apron|bikini|blouse|bodystocking|bodysuit|cape|capelet|china_dress|chinese_clothes|clothes|clothing|coat|collared_shirt|detached_sleeves|dress|frog_button|glove|gloves|hood|hoodie|jacket|japanese_clothes|kimono|lolita_fashion|long_sleeves|open_clothes|open_coat|open_jacket|robe|shirt|sleeveless|sleeveless_shirt|sleeves|sweater|swimsuit|uniform|vest|pom_pom_\(clothes\))($|_)/;

const lowerClothingPattern =
  /(^|_)(bare_legs|belt|belts|bikini|bodystocking|bodysuit|boot|boots|china_dress|dress|highleg|highleg_dress|japanese_clothes|kimono|kneehighs|leggings|pants|pantyhose|pelvic_curtain|robe|sandal|sandals|shoe|shoes|shorts|skirt|sock|socks|stocking|stockings|swimsuit|thigh_boots|thighhighs|thigh_highs)($|_)/;

const upperBodyPattern =
  /(^|_)(ahoge|antenna_hair|bangs|blunt_bangs|bonnet|bow|brown_eyes|brown_hair|cat_ears|choker|circlet|covering_one_eye|dog_ears|ear|ears|earring|earrings|eye|eyes|fang|flower_on_head|hair|hair_flower|hair_ornament|hat|headpiece|headdress|horn|horns|jewelry|long_hair|necklace|pink_eyes|purple_eyes|ribbon|sheep_ears|sheep_horns|short_hair|skin_fang|twintails|very_long_hair|white_bonnet|white_hat|yellow_eyes)($|_)/;

const lowerBodyPattern =
  /(^|_)(anklet|cat_tail|dog_tail|leg|legs|tail|tails|tail_ornament|tail_ring|tiger_tail)($|_)/;

const broadCopyrightTags = new Set([
  'arknights',
  'granblue_fantasy',
  'genshin_impact',
  'azur_lane',
  'azur_promilia',
  'honkai_star_rail',
]);

const manualEvidence = {
  // The local cache has no usable official post tags for this outfit.
  // Public tag pages describe the post-office collaboration as an aqua dress.
  'legacy-character-sheet-r20': {
    source: 'manual-web-kirara-post-office',
    query: 'kirara_(post_office)',
    upperClothingTags: ['aqua_dress', 'dress', 'checkered_print', 'boa'],
    lowerClothingTags: ['aqua_dress', 'dress'],
  },
  // The local cache lacks ju_fufu post tags; public image/tag pages agree on
  // yellow jacket, gray shirt, black shorts, gloves, socks, and shoes.
  'legacy-character-sheet-r25': {
    source: 'manual-web-ju-fufu',
    query: 'ju_fufu',
    upperClothingTags: [
      'yellow_jacket',
      'grey_shirt',
      'shirt',
      'fingerless_gloves',
      'gloves',
      'short_sleeves',
    ],
    lowerClothingTags: [
      'black_shorts',
      'shorts',
      'white_socks',
      'socks',
      'shoes',
      'thigh_strap',
    ],
  },
};

function readJson(filePath, fallback) {
  if (!fs.existsSync(filePath)) return fallback;
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
  const backupDir = path.join(libraryRoot, `backup-${stamp}-default-outfits-v2`);
  fs.mkdirSync(backupDir, { recursive: true });
  fs.copyFileSync(filePath, path.join(backupDir, path.basename(filePath)));
  return backupDir;
}

function splitTags(value) {
  return String(value || '')
    .replace(/\r\n?/g, '\n')
    .split(/[,\n]/)
    .map((part) => part.trim())
    .filter(Boolean);
}

function cleanTag(value) {
  return String(value || '')
    .trim()
    .replace(/^[{\[\s]+/, '')
    .replace(/[}\]\s]+$/, '')
    .replace(/^-?\d+(?:\.\d+)?::/, '')
    .replace(/::$/, '')
    .replace(/\\+/g, '')
    .replace(/\s+/g, '_')
    .replace(/_+/g, '_')
    .replace(/\(_/g, '(')
    .replace(/_\)/g, ')')
    .toLowerCase()
    .replace(/^_+|_+$/g, '');
}

function unique(values) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    const tag = cleanTag(value);
    if (!tag || seen.has(tag)) continue;
    seen.add(tag);
    result.push(tag);
  }
  return result;
}

function normalizeDanbooruEntries(raw) {
  if (Array.isArray(raw)) return raw;
  if (Array.isArray(raw?.value)) return raw.value;
  return [];
}

function isBlocked(tag) {
  const key = cleanTag(tag);
  if (!key || blockedTags.has(key) || ignoredExactTags.has(key)) return true;
  if (ignoredPattern.test(key) || weaponPattern.test(key)) return true;
  return [...blockedTags].some((blocked) => key.includes(blocked));
}

function classifyClothing(tags) {
  const upperClothingTags = [];
  const lowerClothingTags = [];
  for (const rawTag of tags) {
    const tag = cleanTag(rawTag);
    if (isBlocked(tag)) continue;
    if (upperClothingPattern.test(tag)) upperClothingTags.push(tag);
    if (lowerClothingPattern.test(tag)) lowerClothingTags.push(tag);
  }
  return {
    upperClothingTags: unique(upperClothingTags).slice(0, 12),
    lowerClothingTags: unique(lowerClothingTags).slice(0, 12),
  };
}

function classifyBody(tags) {
  const upperBodyTags = [];
  const lowerBodyTags = [];
  for (const rawTag of tags) {
    const tag = cleanTag(rawTag);
    if (isBlocked(tag)) continue;
    if (upperClothingPattern.test(tag) || lowerClothingPattern.test(tag)) {
      continue;
    }
    if (upperBodyPattern.test(tag)) upperBodyTags.push(tag);
    if (lowerBodyPattern.test(tag)) lowerBodyTags.push(tag);
  }
  return {
    upperBodyTags: unique(upperBodyTags),
    lowerBodyTags: unique(lowerBodyTags),
  };
}

function classifyWeapons(tags) {
  return unique(
    tags
      .map(cleanTag)
      .filter((tag) => tag && weaponPattern.test(tag)),
  );
}

function characterBodyTags(character) {
  const upper = splitTags(character.traits?.front_upper || '');
  const lower = splitTags(character.traits?.front_lower || '');
  const full = splitTags(character.traits?.front_full || '');
  const upperBody = classifyBody([...upper, ...full]);
  const lowerBody = classifyBody([...lower, ...full]);
  return {
    upperBodyTags: upperBody.upperBodyTags,
    lowerBodyTags: lowerBody.lowerBodyTags,
  };
}

function outfitBodyTags(outfit) {
  const upper = splitTags(outfit.tags?.front_upper || '');
  const lower = splitTags(outfit.tags?.front_lower || '');
  const full = splitTags(outfit.tags?.front_full || '');
  const upperBody = classifyBody([...upper, ...full]);
  const lowerBody = classifyBody([...lower, ...full]);
  return {
    upperBodyTags: upperBody.upperBodyTags,
    lowerBodyTags: lowerBody.lowerBodyTags,
  };
}

function outfitClothingTags(outfit) {
  const upper = splitTags(outfit.tags?.front_upper || '');
  const lower = splitTags(outfit.tags?.front_lower || '');
  const full = splitTags(outfit.tags?.front_full || '');
  const classifiedUpper = classifyClothing([...upper, ...full]);
  const classifiedLower = classifyClothing([...lower, ...full]);
  return {
    upperClothingTags: classifiedUpper.upperClothingTags,
    lowerClothingTags: classifiedLower.lowerClothingTags,
  };
}

function enrichedPartTags(character, outfit, clothingOverride = {}) {
  const characterBody = characterBodyTags(character);
  const outfitBody = outfitBodyTags(outfit);
  const outfitClothing = outfitClothingTags(outfit);
  const existing = outfit.partTags || {};
  return {
    upperBodyTags: unique([
      ...characterBody.upperBodyTags,
      ...outfitBody.upperBodyTags,
      ...(existing.upperBodyTags || []),
    ]),
    upperClothingTags: unique([
      ...(clothingOverride.upperClothingTags || []),
      ...(existing.upperClothingTags || []),
      ...outfitClothing.upperClothingTags,
    ]),
    lowerBodyTags: unique([
      ...characterBody.lowerBodyTags,
      ...outfitBody.lowerBodyTags,
      ...(existing.lowerBodyTags || []),
    ]),
    lowerClothingTags: unique([
      ...(clothingOverride.lowerClothingTags || []),
      ...(existing.lowerClothingTags || []),
      ...outfitClothing.lowerClothingTags,
    ]),
    weaponTags: unique([
      ...(existing.weaponTags || []),
      ...classifyWeapons(splitTags(outfit.tags?.front_full || '')),
    ]),
  };
}

function hasCompleteClothing(evidence) {
  return evidence.upperClothingTags.length > 0 && evidence.lowerClothingTags.length > 0;
}

function bestLocalTag(query, localTags) {
  const key = cleanTag(query);
  const entries = normalizeDanbooruEntries(localTags[key])
    .filter((entry) => entry && !entry.is_deprecated)
    .map((entry) => ({
      name: cleanTag(entry.name),
      category: Number(entry.category),
      postCount: Number(entry.post_count || 0),
    }));
  return (
    entries.find((entry) => entry.name === key && entry.category === 4 && entry.postCount > 0)
      ?.name ||
    entries.find((entry) => entry.category === 4 && entry.postCount > 0)?.name ||
    entries.find((entry) => entry.name === key && entry.postCount > 0)?.name ||
    ''
  );
}

function exactKnownTags(text, localTags, queries) {
  const normalizedText = cleanTag(text);
  const found = [];
  for (const query of [...queries].sort((a, b) => cleanTag(b).length - cleanTag(a).length)) {
    const normalizedQuery = cleanTag(query);
    if (broadCopyrightTags.has(normalizedQuery)) continue;
    const tag = bestLocalTag(normalizedQuery, localTags) || normalizedQuery;
    if (!tag) continue;
    if (normalizedText.includes(normalizedQuery) || normalizedText.includes(tag)) {
      found.push(tag);
    }
  }
  for (const rawTag of splitTags(text)) {
    const tag = bestLocalTag(rawTag, localTags);
    if (tag && !broadCopyrightTags.has(tag)) found.push(tag);
  }
  return unique(found);
}

function postTags(post) {
  return unique(splitTags(String(post?.tagStringGeneral || '').replaceAll(' ', ',')));
}

function officialPostCandidates(query, cache) {
  if (!query) return [];
  const rawPosts = [
    ...(cache.officialPosts?.[`${query} official_art`] || []).map((post, index) => ({
      post,
      kind: 'official_art',
      index,
    })),
    ...(cache.officialPosts?.[`${query} official_alternate_costume`] || []).map(
      (post, index) => ({
        post,
        kind: 'official_alternate_costume',
        index,
      }),
    ),
  ];
  return rawPosts
    .filter(({ post }) => ['g', 's', undefined].includes(post.rating))
    .map(({ post, kind, index }) => {
      const tags = postTags(post);
      const classified = classifyClothing(tags);
      if (!hasCompleteClothing(classified)) return null;
      const tagSet = new Set(tags);
      const characterTagCount = Number(post.tagCountCharacter || 0);
      const soloScore =
        (tagSet.has('solo') ? 80 : 0) +
        (tagSet.has('1girl') || tagSet.has('1boy') ? 40 : 0) -
        (tagSet.has('multiple_girls') || tagSet.has('multiple_boys') ? 180 : 0);
      const characterScore =
        characterTagCount <= 0 ? 0 : -Math.max(0, characterTagCount - 1) * 90;
      const alternateScore = tagSet.has('official_alternate_costume') ? -160 : 0;
      const kindScore = kind === 'official_art' ? 500 : 300;
      const id = post.id || `${query}-${kind}-${index + 1}`;
      return namedEvidence({
        source: `danbooru-${kind}-post:${id}`,
        query,
        upperClothingTags: classified.upperClothingTags,
        lowerClothingTags: classified.lowerClothingTags,
        score:
          kindScore +
          soloScore +
          characterScore +
          alternateScore +
          classified.upperClothingTags.length +
          classified.lowerClothingTags.length,
      });
    })
    .filter(Boolean)
    .sort((a, b) => b.score - a.score || a.source.localeCompare(b.source));
}

function namedEvidence({ source, query = '', upperClothingTags, lowerClothingTags, score = 0 }) {
  return {
    source,
    query,
    score,
    upperClothingTags: unique(upperClothingTags).slice(0, 12),
    lowerClothingTags: unique(lowerClothingTags).slice(0, 12),
  };
}

function frontFullEvidence(character) {
  const classified = classifyClothing(splitTags(character.traits?.front_full || ''));
  if (!hasCompleteClothing(classified)) return null;
  return namedEvidence({
    source: 'front_full',
    upperClothingTags: classified.upperClothingTags,
    lowerClothingTags: classified.lowerClothingTags,
    score: 300 + classified.upperClothingTags.length + classified.lowerClothingTags.length,
  });
}

function seedOutfitCandidates(character, seedById) {
  const seed = seedById.get(character.id);
  if (!seed) return [];
  return (seed.outfits || [])
    .map((outfit, index) => {
      const tags = [
        ...splitTags(outfit.tags?.front_full || ''),
        ...splitTags(outfit.tags?.front_upper || ''),
        ...splitTags(outfit.tags?.front_lower || ''),
      ];
      const classified = classifyClothing(tags);
      if (!hasCompleteClothing(classified)) return null;
      const sourceName = `seed:${outfit.id || `${character.id}-outfit-${index + 1}`}`;
      const label = outfit.name ? `${sourceName}/${outfit.name}` : sourceName;
      const sourceScore = String(outfit.id || '').includes('-outfit-0') ? 80 : 0;
      const evidence = namedEvidence({
        source: label,
        upperClothingTags: classified.upperClothingTags,
        lowerClothingTags: classified.lowerClothingTags,
        score:
          sourceScore +
          200 +
          classified.upperClothingTags.length +
          classified.lowerClothingTags.length,
      });
      evidence.outfit = outfit;
      evidence.outfitId = outfit.id || '';
      return evidence;
    })
    .filter(Boolean)
    .sort((a, b) => b.score - a.score || a.source.localeCompare(b.source));
}

function officialEvidence(character, localTags, queries, cache) {
  const knownTags = exactKnownTags(character.traits?.front_full || '', localTags, queries);
  for (const query of knownTags) {
    const official = officialPostCandidates(query, cache)[0];
    if (official) return official;
  }
  return null;
}

function manualOutfitEvidence(character) {
  const manual = manualEvidence[character.id];
  if (!manual) return null;
  return namedEvidence({
    source: manual.source,
    query: manual.query,
    upperClothingTags: manual.upperClothingTags,
    lowerClothingTags: manual.lowerClothingTags,
    score: 50 + manual.upperClothingTags.length + manual.lowerClothingTags.length,
  });
}

function selectDefaultEvidence(character, localTags, queries, cache, seedById) {
  const front = frontFullEvidence(character);
  if (front) return front;

  const official = officialEvidence(character, localTags, queries, cache);
  if (official) return official;

  const seed = seedOutfitCandidates(character, seedById)[0];
  if (seed) return seed;

  return manualOutfitEvidence(character);
}

function promptFromTags(tags) {
  return unique(tags || []).join(', ');
}

function defaultOutfitFor(character, evidence) {
  const outfit = {
    id: defaultOutfitId,
    name: defaultOutfitName,
    tags: {
      front_full: promptFromTags([
        ...evidence.upperClothingTags,
        ...evidence.lowerClothingTags,
      ]),
      front_upper: promptFromTags(evidence.upperClothingTags),
      front_lower: promptFromTags(evidence.lowerClothingTags),
    },
    imageRefs: [...(character.imageRefs || [])],
    note: [
      '\u6574\u7406: \u9ed8\u8ba4\u670d\u88c5\u8865\u5168',
      evidence.query ? `Danbooru: ${evidence.query}` : '',
      `\u6765\u6e90: ${evidence.source}`,
    ]
      .filter(Boolean)
      .join(' | '),
  };
  return {
    ...outfit,
    partTags: enrichedPartTags(character, outfit, {
      upperClothingTags: evidence.upperClothingTags,
      lowerClothingTags: evidence.lowerClothingTags,
    }),
  };
}

function removeExistingDefaultOutfits(character) {
  return (character.outfits || []).filter((outfit) => outfit.id !== defaultOutfitId);
}

function restoredSeedOutfits(character, seedById, defaultEvidence, existingOutfits) {
  const existingIds = new Set(existingOutfits.map((outfit) => outfit.id));
  return seedOutfitCandidates(character, seedById)
    .filter((candidate) => {
      const outfit = candidate.outfit;
      if (!outfit?.id) return false;
      if (outfit.id === defaultEvidence.outfitId) return false;
      return !existingIds.has(outfit.id);
    })
    .map((candidate) => normalizeSeedOutfit(character, candidate));
}

function normalizeSeedOutfit(character, candidate) {
  const outfit = candidate.outfit;
  const tags = outfit.tags || {};
  const partTags = outfit.partTags || {};
  const normalized = {
    id: outfit.id,
    name: outfit.name || '\u670d\u88c5',
    tags: {
      front_full: tags.front_full || promptFromTags([
        ...candidate.upperClothingTags,
        ...candidate.lowerClothingTags,
      ]),
      front_upper: tags.front_upper || promptFromTags(candidate.upperClothingTags),
      front_lower: tags.front_lower || promptFromTags(candidate.lowerClothingTags),
    },
    imageRefs: [...(outfit.imageRefs || [])],
    note:
      outfit.note ||
      `\u6574\u7406: \u4ece seed \u6062\u590d\u670d\u88c5 | \u6765\u6e90: ${candidate.source}`,
    partTags,
  };
  return {
    ...normalized,
    partTags: enrichedPartTags(character, normalized, {
      upperClothingTags:
        partTags.upperClothingTags?.length > 0
          ? partTags.upperClothingTags
          : candidate.upperClothingTags,
      lowerClothingTags:
        partTags.lowerClothingTags?.length > 0
          ? partTags.lowerClothingTags
          : candidate.lowerClothingTags,
    }),
  };
}

function stripInheritedCharacterPreviewRefs(character, outfit) {
  if (outfit.id === defaultOutfitId) return outfit.imageRefs || [];
  const characterRefs = new Set((character.imageRefs || []).map((ref) => String(ref).trim()));
  return (outfit.imageRefs || []).filter((ref) => {
    const trimmed = String(ref || '').trim();
    return trimmed && !characterRefs.has(trimmed);
  });
}

function enrichExistingOutfit(character, outfit) {
  return {
    ...outfit,
    imageRefs: stripInheritedCharacterPreviewRefs(character, outfit),
    partTags: enrichedPartTags(character, outfit),
  };
}

function main() {
  const characters = readJson(charactersPath, []);
  const seed = readJson(seedPath, {});
  const seedById = new Map((seed.characters || []).map((character) => [character.id, character]));
  const localTags = readJson(localDanbooruTagsPath, {});
  const queries = readJson(danbooruQueriesPath, []);
  const cache = readJson(postCachePath, { posts: {}, officialPosts: {} });

  const report = {
    completedAt: new Date().toISOString(),
    mode: apply ? 'apply' : 'dry-run',
    workspaceRoot,
    backupDir: '',
    upserted: [],
    skipped: [],
  };

  for (const character of characters) {
    const evidence = selectDefaultEvidence(character, localTags, queries, cache, seedById);
    if (!evidence || !hasCompleteClothing(evidence)) {
      report.skipped.push({
        characterId: character.id,
        characterName: character.name,
        reason: 'missing single-source upper/lower clothing evidence',
        source: evidence?.source || '',
        query: evidence?.query || '',
        upperClothingTags: evidence?.upperClothingTags || [],
        lowerClothingTags: evidence?.lowerClothingTags || [],
      });
      continue;
    }

    const existingOutfits = removeExistingDefaultOutfits(character).map((outfit) =>
      enrichExistingOutfit(character, outfit),
    );
    const restoredOutfits = restoredSeedOutfits(
      character,
      seedById,
      evidence,
      existingOutfits,
    );
    const outfit = defaultOutfitFor(character, evidence);
    report.upserted.push({
      characterId: character.id,
      characterName: character.name,
      outfitId: outfit.id,
      outfitName: outfit.name,
      previousDefaultCount: (character.outfits || []).length - existingOutfits.length,
      keptOutfitCount: existingOutfits.length,
      restoredOutfitCount: restoredOutfits.length,
      restoredOutfits: restoredOutfits.map((restored) => ({
        outfitId: restored.id,
        outfitName: restored.name,
      })),
      query: evidence.query,
      source: evidence.source,
      upperClothingTags: evidence.upperClothingTags,
      lowerClothingTags: evidence.lowerClothingTags,
    });

    if (apply) {
      character.outfits = [outfit, ...existingOutfits, ...restoredOutfits];
      character.defaultOutfitId = defaultOutfitId;
    }
  }

  if (apply) {
    report.backupDir = backup(charactersPath);
    writeJson(charactersPath, characters);
    writeJson(reportPath, report);
  }

  console.log(JSON.stringify(report, null, 2));
}

main();
