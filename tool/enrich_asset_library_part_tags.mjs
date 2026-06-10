import fs from 'node:fs';
import path from 'node:path';

const repoRoot = process.cwd();
const workspaceRoot =
  process.argv[2] ||
  'C:/Users/admin/AppData/Roaming/org.exception0x0194/nai3_autodraw/novel_studio';

const charactersPath = path.join(workspaceRoot, 'library', 'characters.json');
const seedPath = path.join(repoRoot, 'assets', 'json', 'legacy_artist_studio_seed.json');
const localDanbooruTagsPath = path.join(repoRoot, 'tool', 'asset-library-danbooru-tags.json');
const postCachePath = path.join(repoRoot, 'tool', 'asset-library-danbooru-post-tags-cache.json');
const reportPath = path.join(workspaceRoot, 'library', 'asset_part_tag_enrich_report.json');
const networkWarnings = [];

const copyrightWords = new Set([
  'arknights',
  'granblue',
  'granblue_fantasy',
  'genshin',
  'genshin_impact',
  'azur',
  'azur_lane',
  'azur_promilia',
  'honkai',
  'star',
  'rail',
  'honkai_star_rail',
  'flower',
  'knight',
  'girl',
  'flower_knight_girl',
]);

const weakSearchWords = new Set([
  'a',
  'an',
  'and',
  'before',
  'girl',
  'in',
  'little',
  'long',
  'of',
  'the',
  'trip',
]);

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
]);

const ignoredExactTags = new Set([
  '1girl',
  '2boys',
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
  'white_background',
  'arm_behind_head',
  'arm_up',
  'bad_feet',
  'between_legs',
  "hand_on_another's_ear",
  'hand_between_own_legs',
  'hand_to_weapon',
  'hand_up',
  'jumping',
  'knees_together_feet_apart',
]);

const ignoredPattern =
  /(^|_)(arm|bad|background|between_legs|cropped|dated|feet_apart|hand|jumping|knees|source|username|wallpaper|logo|text|watermark|signature|composition|portrait|quality|score|rating|view|pose|sitting|standing|lying|running|walking|looking|smile|closed_mouth|open_mouth|holding|reaching|on_stomach|from_|solo|multiple)($|_)/;

const weaponPattern =
  /(^|_)(weapon|sword|gun|rifle|staff|wand|book|sistrum|umbrella|shield|spear|knife|axe)($|_)/;

const upperBodyPattern =
  /(^|_)(ahoge|animal_ear|animal_ears|animal_ear_fluff|bangs|bonnet|bow|braid|breasts|collarbone|dark_skin|dark-skinned_female|ear|ears|eye|eyes|fang|flower|glasses|hair|hairband|hat|head|headdress|horn|horns|jewelry|mark|necklace|ornament|ribbon|skin|twintails|veil)($|_)/;

const lowerBodyPattern =
  /(^|_)(anklet|tail|thigh_belt|thigh_strap)($|_)/;

const upperClothingPattern =
  /(^|_)(apron|bikini|blouse|bodystocking|bodysuit|cape|capelet|china_dress|chinese_clothes|clothes|clothing|coat|collared_shirt|detached_sleeves|dress|frog_button|glove|gloves|hood|hoodie|jacket|japanese_clothes|kimono|lolita_fashion|long_sleeves|open_clothes|open_coat|open_jacket|robe|shirt|sleeveless|sleeveless_shirt|sleeves|sweater|swimsuit|uniform|vest)($|_)/;

const lowerClothingPattern =
  /(^|_)(bare_legs|belt|belts|bikini|bodystocking|bodysuit|boot|boots|china_dress|dress|highleg|highleg_dress|japanese_clothes|kimono|kneehighs|leggings|pants|pantyhose|pelvic_curtain|robe|sandal|sandals|shoe|shoes|shorts|skirt|sock|socks|stocking|stockings|swimsuit|thigh_boots|thighhighs|thigh_highs)($|_)/;

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
  const backupDir = path.join(workspaceRoot, 'library', `backup-${stamp}-part-tags`);
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

function tagWords(value) {
  return cleanTag(value)
    .replace(/[()':]/g, '_')
    .split('_')
    .map((word) => word.trim())
    .filter(Boolean);
}

function isBlocked(tag) {
  const key = cleanTag(tag);
  if (!key || blockedTags.has(key) || ignoredExactTags.has(key)) return true;
  if (ignoredPattern.test(key)) return true;
  return [...blockedTags].some((blocked) => key.includes(blocked));
}

function isCharacterOrCopyrightTag(tag, knownCharacterTags) {
  const key = cleanTag(tag);
  if (knownCharacterTags.has(key)) return true;
  const words = tagWords(key);
  return (
    words.some((word) => copyrightWords.has(word)) &&
    !upperClothingPattern.test(key) &&
    !lowerClothingPattern.test(key)
  );
}

function classifyTags(tags, knownCharacterTags) {
  const buckets = {
    upperBodyTags: [],
    upperClothingTags: [],
    lowerBodyTags: [],
    lowerClothingTags: [],
    weaponTags: [],
  };

  for (const raw of tags) {
    const tag = cleanTag(raw);
    if (!tag || isBlocked(tag)) continue;
    if (weaponPattern.test(tag)) {
      buckets.weaponTags.push(tag);
      continue;
    }
    if (isCharacterOrCopyrightTag(tag, knownCharacterTags)) continue;

    if (upperBodyPattern.test(tag)) {
      buckets.upperBodyTags.push(tag);
    }
    if (upperClothingPattern.test(tag)) {
      buckets.upperClothingTags.push(tag);
    }
    if (lowerBodyPattern.test(tag)) {
      buckets.lowerBodyTags.push(tag);
    }
    if (lowerClothingPattern.test(tag)) {
      buckets.lowerClothingTags.push(tag);
    }
  }

  return Object.fromEntries(
    Object.entries(buckets).map(([key, values]) => [key, unique(values).slice(0, 14)]),
  );
}

function normalizeDanbooruEntries(raw) {
  if (Array.isArray(raw)) return raw;
  if (Array.isArray(raw?.value)) return raw.value;
  return [];
}

function bestLocalTag(query, localTags) {
  const entries = normalizeDanbooruEntries(localTags[cleanTag(query)])
    .filter((entry) => entry && !entry.is_deprecated)
    .map((entry) => ({
      name: cleanTag(entry.name),
      category: Number(entry.category),
      postCount: Number(entry.post_count || 0),
    }));
  const characterEntries = entries
    .filter((entry) => entry.category === 4)
    .sort((a, b) => b.postCount - a.postCount);
  return (
    characterEntries.find((entry) => entry.postCount > 0)?.name ||
    entries.find((entry) => entry.category !== 4 && entry.postCount > 0)?.name ||
    ''
  );
}

function searchPattern(candidate) {
  const words = tagWords(candidate)
    .filter((word) => !copyrightWords.has(word))
    .filter((word) => !weakSearchWords.has(word));
  const copyright = tagWords(candidate).find((word) => copyrightWords.has(word));
  const useful = words.slice(0, 3);
  if (copyright) useful.push(copyright);
  if (useful.length < 2) return '';
  return `${useful.join('*')}*`;
}

async function danbooruJson(url) {
  let lastError;
  for (let attempt = 1; attempt <= 2; attempt += 1) {
    try {
      const response = await fetch(url, {
        headers: {
          'User-Agent': 'Codex asset-library tag enrichment',
        },
        signal: AbortSignal.timeout(12000),
      });
      if (!response.ok) {
        throw new Error(`Danbooru request failed ${response.status}: ${url}`);
      }
      return response.json();
    } catch (error) {
      lastError = error;
      await delay(500 * attempt);
    }
  }
  throw lastError;
}

function saveCache(cache) {
  writeJson(postCachePath, cache);
}

async function findDanbooruTag(candidate, localTags, cache) {
  const local = bestLocalTag(candidate, localTags);
  if (local) return local;
  const pattern = searchPattern(candidate);
  if (!pattern) return '';
  cache.tagSearches ||= {};
  if (!cache.tagSearches[pattern]) {
    const urls = [
      new URL('https://danbooru.donmai.us/tags.json'),
      new URL('https://safebooru.donmai.us/tags.json'),
    ];
    for (const url of urls) {
      url.searchParams.set('search[name_matches]', pattern);
      url.searchParams.set('limit', '12');
    }
    let value = null;
    let lastError = null;
    try {
      value = await danbooruJson(urls[0]);
    } catch (error) {
      lastError = error;
      try {
        value = await danbooruJson(urls[1]);
      } catch (fallbackError) {
        lastError = fallbackError;
      }
    }
    if (value) {
      cache.tagSearches[pattern] = normalizeDanbooruEntries(value);
    } else {
      networkWarnings.push({ type: 'tagSearch', pattern, error: String(lastError) });
      cache.tagSearches[pattern] = [];
    }
    saveCache(cache);
    await delay(350);
  }
  const entries = normalizeDanbooruEntries(cache.tagSearches[pattern])
    .filter((entry) => entry && !entry.is_deprecated)
    .map((entry) => ({
      name: cleanTag(entry.name),
      category: Number(entry.category),
      postCount: Number(entry.post_count || 0),
    }))
    .sort((a, b) => {
      if (a.category === 4 && b.category !== 4) return -1;
      if (a.category !== 4 && b.category === 4) return 1;
      return b.postCount - a.postCount;
    });
  return entries[0]?.name || '';
}

async function fetchPostSummaries(query, cache, bucket) {
  if (!query) return [];
  cache[bucket] ||= {};
  if (!cache[bucket][query]) {
    const urls = [
      new URL('https://danbooru.donmai.us/posts.json'),
      new URL('https://safebooru.donmai.us/posts.json'),
    ];
    for (const url of urls) {
      url.searchParams.set('tags', query);
      url.searchParams.set('limit', '20');
    }
    let postsValue = null;
    let lastError = null;
    try {
      postsValue = await danbooruJson(urls[0]);
    } catch (error) {
      lastError = error;
      try {
        postsValue = await danbooruJson(urls[1]);
      } catch (fallbackError) {
        lastError = fallbackError;
      }
    }
    if (postsValue) {
      cache[bucket][query] = normalizeDanbooruEntries(postsValue).map((post) => ({
        id: post.id,
        rating: post.rating,
        tagCountCharacter: Number(post.tag_count_character || 0),
        tagStringGeneral: post.tag_string_general || '',
      }));
    } else {
      networkWarnings.push({ type: bucket, query, error: String(lastError) });
      cache[bucket][query] = [];
    }
    saveCache(cache);
    await delay(350);
  }
  return normalizeDanbooruEntries(cache[bucket][query]);
}

function tagsFromPostSummaries(posts, { preferFocused = true } = {}) {
  const safePosts = posts.filter((post) => ['g', 's'].includes(post.rating));
  const focused = safePosts.filter(
    (post) =>
      post.tagCountCharacter <= 4 &&
      !/(^| )(multiple_girls|multiple_boys|6\+girls|2boys)( |$)/.test(
        post.tagStringGeneral || '',
      ),
  );
  const usable = preferFocused && focused.length ? focused : safePosts;
  const counts = new Map();
  for (const post of usable) {
    for (const tagName of splitTags(String(post.tagStringGeneral || '').replaceAll(' ', ','))) {
      const tag = cleanTag(tagName);
      if (!tag) continue;
      counts.set(tag, (counts.get(tag) || 0) + 1);
    }
  }
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .map(([tagName]) => tagName);
}

async function fetchGeneralPostTags(tag, cache) {
  return tagsFromPostSummaries(await fetchPostSummaries(tag, cache, 'posts'));
}

async function fetchOfficialPostTags(tag, cache) {
  const posts = [
    ...(await fetchPostSummaries(`${tag} official_art`, cache, 'officialPosts')),
    ...(await fetchPostSummaries(
      `${tag} official_alternate_costume`,
      cache,
      'officialPosts',
    )),
  ];
  return tagsFromPostSummaries(posts, { preferFocused: false });
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function outfitCandidates(outfit) {
  return unique(splitTags(outfit.tags?.front_full || '')).filter((tag) => {
    const words = tagWords(tag);
    return words.length > 1 && (tag.includes('(') || words.some((word) => copyrightWords.has(word)));
  });
}

function characterCandidates(character) {
  return unique(splitTags(character.traits?.front_full || '')).filter((tag) => {
    const words = tagWords(tag);
    return words.length > 1 && (tag.includes('(') || words.some((word) => copyrightWords.has(word)));
  });
}

function mergePartTags(primary, secondary) {
  return {
    upperBodyTags: unique([...(primary.upperBodyTags || []), ...(secondary.upperBodyTags || [])]),
    upperClothingTags: unique([
      ...(primary.upperClothingTags || []),
      ...(secondary.upperClothingTags || []),
    ]),
    lowerBodyTags: unique([...(primary.lowerBodyTags || []), ...(secondary.lowerBodyTags || [])]),
    lowerClothingTags: unique([
      ...(primary.lowerClothingTags || []),
      ...(secondary.lowerClothingTags || []),
    ]),
    weaponTags: unique([...(primary.weaponTags || []), ...(secondary.weaponTags || [])]),
  };
}

function bodyTagsFromOutfit(outfit, knownCharacterTags) {
  const explicitTags = [
    ...splitTags(outfit.tags?.front_full || ''),
    ...splitTags(outfit.tags?.front_upper || ''),
    ...splitTags(outfit.tags?.front_lower || ''),
    ...(outfit.partTags?.upperBodyTags || []),
    ...(outfit.partTags?.lowerBodyTags || []),
  ];
  const parts = classifyTags(explicitTags, knownCharacterTags);
  return {
    upperBodyTags: parts.upperBodyTags || [],
    lowerBodyTags: parts.lowerBodyTags || [],
  };
}

function mergeCharacterBody(character, outfitBodyCandidates, knownCharacterTags) {
  character.traits ||= {};
  const explicit = classifyTags(
    [
      ...splitTags(character.traits.front_full || ''),
      ...splitTags(character.traits.front_upper || ''),
      ...splitTags(character.traits.front_lower || ''),
    ],
    knownCharacterTags,
  );
  const upper = unique([
    ...(explicit.upperBodyTags || []),
    ...outfitBodyCandidates.flatMap((entry) => entry.upperBodyTags || []),
  ]).slice(0, 14);
  const lower = unique([
    ...(explicit.lowerBodyTags || []),
    ...outfitBodyCandidates.flatMap((entry) => entry.lowerBodyTags || []),
  ]).slice(0, 14);
  if (upper.length) {
    character.traits.front_upper = promptFromTags(upper);
  } else {
    delete character.traits.front_upper;
  }
  if (lower.length) {
    character.traits.front_lower = promptFromTags(lower);
  } else {
    delete character.traits.front_lower;
  }
  return { upperBodyTags: upper, lowerBodyTags: lower };
}

function bodyOverrides(localOutfitParts, characterBody) {
  const upperCharacter = new Set(characterBody.upperBodyTags || []);
  const lowerCharacter = new Set(characterBody.lowerBodyTags || []);
  return {
    upperBodyTags: unique(localOutfitParts.upperBodyTags || []).filter(
      (tag) => !upperCharacter.has(cleanTag(tag)),
    ),
    lowerBodyTags: unique(localOutfitParts.lowerBodyTags || []).filter(
      (tag) => !lowerCharacter.has(cleanTag(tag)),
    ),
  };
}

function compactPartTags(partTags) {
  return Object.fromEntries(
    Object.entries(partTags)
      .map(([key, values]) => [key, unique(values).slice(0, 14)])
      .filter(([, values]) => values.length),
  );
}

function promptFromTags(tags) {
  return unique(tags || []).join(', ');
}

function cleanExistingNote(note) {
  return String(note || '')
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith('整理:'))
    .join('\n');
}

function mergeNote(existing, sections) {
  const retained = cleanExistingNote(existing);
  const parts = Object.entries(sections)
    .filter(([, value]) => String(value || '').trim())
    .map(([label, value]) => `${label}: ${value}`);
  return [retained, parts.length ? `整理: ${parts.join(' | ')}` : '']
    .filter(Boolean)
    .join('\n');
}

function applyTagsToOutfit(outfit, partTags, danbooruTags) {
  outfit.tags ||= {};
  const upperClothing = promptFromTags(partTags.upperClothingTags);
  const lowerClothing = promptFromTags(partTags.lowerClothingTags);
  if (upperClothing) {
    outfit.tags.front_upper = upperClothing;
  } else {
    delete outfit.tags.front_upper;
  }
  if (lowerClothing) {
    outfit.tags.front_lower = lowerClothing;
  } else {
    delete outfit.tags.front_lower;
  }

  outfit.partTags = compactPartTags(partTags);
  outfit.note = mergeNote(outfit.note, {
    Danbooru标签: danbooruTags.join(', '),
    上身: promptFromTags(partTags.upperBodyTags),
    上装: promptFromTags(partTags.upperClothingTags),
    下身: promptFromTags(partTags.lowerBodyTags),
    下装: promptFromTags(partTags.lowerClothingTags),
    武器道具: promptFromTags(partTags.weaponTags),
  });
}

async function enrichCharacters(characters, localTags, cache) {
  const knownCharacterTags = new Set();
  for (const wrapped of Object.values(localTags)) {
    for (const entry of normalizeDanbooruEntries(wrapped)) {
      if (Number(entry.category) === 4) {
        knownCharacterTags.add(cleanTag(entry.name));
      }
    }
  }

  const report = [];
  for (const character of characters) {
    const characterBody = classifyTags(
      [],
      knownCharacterTags,
    );
    const outfitBodyCandidates = (character.outfits || []).map((outfit) =>
      bodyTagsFromOutfit(outfit, knownCharacterTags),
    );
    const characterDanbooruTags = [];
    const resolvedCharacterDanbooruTags = [];
    for (const candidate of unique([
      ...characterCandidates(character),
      ...(character.outfits || []).flatMap((outfit) => outfitCandidates(outfit)),
    ])) {
      const resolved = await findDanbooruTag(candidate, localTags, cache);
      if (!resolved) continue;
      knownCharacterTags.add(resolved);
      resolvedCharacterDanbooruTags.push(resolved);
      characterDanbooruTags.push(...(await fetchGeneralPostTags(resolved, cache)));
    }
    let characterOfficialTags = null;
    async function loadCharacterOfficialTags() {
      if (characterOfficialTags) return characterOfficialTags;
      characterOfficialTags = [];
      for (const resolved of unique(resolvedCharacterDanbooruTags)) {
        characterOfficialTags.push(...(await fetchOfficialPostTags(resolved, cache)));
      }
      return characterOfficialTags;
    }
    outfitBodyCandidates.push(classifyTags(characterDanbooruTags, knownCharacterTags));
    Object.assign(
      characterBody,
      mergeCharacterBody(character, outfitBodyCandidates, knownCharacterTags),
    );

    for (const outfit of character.outfits || []) {
      const candidates = outfitCandidates(outfit);
      const danbooruTags = [];
      const resolvedDanbooruTags = [];
      const localOutfitTags = [
        ...splitTags(outfit.tags?.front_full || ''),
        ...splitTags(outfit.tags?.front_upper || ''),
        ...splitTags(outfit.tags?.front_lower || ''),
      ];
      const localOutfitParts = classifyTags(localOutfitTags, knownCharacterTags);
      const hasDetailedLocalClothing =
        localOutfitParts.upperClothingTags.length > 0 ||
        localOutfitParts.lowerClothingTags.length > 0;
      if (!hasDetailedLocalClothing) {
        for (const candidate of candidates) {
          const resolved = await findDanbooruTag(candidate, localTags, cache);
          if (!resolved) continue;
          knownCharacterTags.add(resolved);
          resolvedDanbooruTags.push(resolved);
          danbooruTags.push(...(await fetchGeneralPostTags(resolved, cache)));
        }
      }

      const outfitParts = classifyTags(
        [...localOutfitTags, ...danbooruTags],
        knownCharacterTags,
      );
      if (outfitParts.upperClothingTags.length === 0) {
        const officialTags = await loadCharacterOfficialTags();
        outfitParts.upperClothingTags = classifyTags(
          officialTags,
          knownCharacterTags,
        ).upperClothingTags || [];
      }
      const body = bodyOverrides(localOutfitParts, characterBody);
      const partTags = {
        upperBodyTags: body.upperBodyTags,
        upperClothingTags: outfitParts.upperClothingTags || [],
        lowerBodyTags: body.lowerBodyTags,
        lowerClothingTags: outfitParts.lowerClothingTags || [],
        weaponTags: outfitParts.weaponTags || [],
      };
      applyTagsToOutfit(outfit, partTags, unique(resolvedDanbooruTags));

      report.push({
        characterId: character.id,
        characterName: character.name,
        outfitId: outfit.id,
        outfitName: outfit.name,
        danbooruTags: unique([
          ...resolvedCharacterDanbooruTags,
          ...resolvedDanbooruTags,
        ]),
        partTags: compactPartTags(partTags),
      });
    }
  }
  return report;
}

async function main() {
  const characters = readJson(charactersPath, []);
  const seed = readJson(seedPath, {});
  const seedCharacters = seed.characters || [];
  const localTags = readJson(localDanbooruTagsPath, {});
  const cache = readJson(postCachePath, { tagSearches: {}, posts: {} });

  const backupDir = backup(charactersPath);
  const runtimeReport = await enrichCharacters(characters, localTags, cache);
  const seedReport = await enrichCharacters(seedCharacters, localTags, cache);

  writeJson(charactersPath, characters);
  if (seed.characters) writeJson(seedPath, seed);
  writeJson(postCachePath, cache);
  writeJson(reportPath, {
    completedAt: new Date().toISOString(),
    workspaceRoot,
    backupDir,
    runtimeOutfits: runtimeReport.length,
    seedOutfits: seedReport.length,
    runtimeReport,
    networkWarnings,
  });

  const filled = runtimeReport.filter((entry) =>
    Object.values(entry.partTags).some((tags) => tags.length),
  ).length;
  console.log(
    JSON.stringify(
      {
        characters: characters.length,
        outfits: runtimeReport.length,
        outfitsWithPartTags: filled,
        seedOutfits: seedReport.length,
        backupDir,
        reportPath,
        postCachePath,
        networkWarnings: networkWarnings.length,
      },
      null,
      2,
    ),
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
