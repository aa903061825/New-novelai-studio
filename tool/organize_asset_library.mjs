import fs from 'node:fs';
import path from 'node:path';

const repoRoot = process.cwd();
const workspaceRoot =
  process.argv[2] ||
  'C:/Users/admin/AppData/Roaming/Novel Studio/Novel Studio/novel_studio';

const charactersPath = path.join(workspaceRoot, 'library', 'characters.json');
const artistChainsPath = path.join(
  workspaceRoot,
  'library',
  'artist_chains.json',
);
const referencesDir = path.join(workspaceRoot, 'assets', 'references');
const reportPath = path.join(workspaceRoot, 'library', 'asset_organize_report.json');
const imageQueuePath = path.join(repoRoot, 'tool', 'asset-library-image-queue.json');
const danbooruPath = path.join(repoRoot, 'tool', 'asset-library-danbooru-tags.json');

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function normalizeTagText(text) {
  return String(text || '')
    .replace(/\r\n/g, '\n')
    .split('\n')
    .map((line) =>
      line
        .split(',')
        .map((part) => part.trim())
        .filter(Boolean)
        .join(', '),
    )
    .filter(Boolean)
    .join('\n');
}

function splitTags(text) {
  return String(text || '')
    .replace(/\r\n/g, '\n')
    .split(/[,\n]/)
    .map((part) => part.trim())
    .filter(Boolean);
}

function cleanTag(tag) {
  return String(tag || '')
    .trim()
    .replace(/^-?\d+(?:\.\d+)?::\s*/, '')
    .replace(/\s*::-?\d+(?:\.\d+)?$/, '')
    .replace(/^[:\s,[{]+/, '')
    .replace(/[:\s,\]}]+$/, '')
    .replace(/\\+/g, '')
    .replace(/\s+/g, '_')
    .toLowerCase();
}

function unique(values) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    const cleaned = String(value || '').trim();
    if (!cleaned) continue;
    const key = cleaned.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(cleaned);
  }
  return result;
}

function usableMetadataTag(value) {
  const cleaned = cleanTag(value);
  if (!cleaned || cleaned.includes(':')) return '';
  if (cleaned === 'arknights') return '';
  return cleaned;
}

function skinVariantBaseTag(value) {
  const cleaned = usableMetadataTag(value);
  const match = /^(.+?)_(?:\([^)]+\)_)+\(([^)]+)\)$/.exec(cleaned);
  if (!match) return '';
  return `${match[1]}_(${match[2]})`;
}

function withoutSkinVariantAliases(values) {
  const tags = unique(values.map(usableMetadataTag).filter(Boolean));
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
  const values = [
    character.traits?.front_full,
    character.traits?.front_upper,
    character.traits?.front_lower,
    ...(character.outfits || []).flatMap((outfit) => [
      outfit.tags?.front_full,
      outfit.tags?.front_upper,
      outfit.tags?.front_lower,
    ]),
  ];
  return unique(
    values
      .flatMap(splitTags)
      .map(usableMetadataTag)
      .filter(isDemographicIdentityTag),
  );
}

const upperKeywords = [
  'ahoge',
  'animal_ear',
  'arm',
  'bangs',
  'bonnet',
  'bow',
  'braid',
  'breast',
  'cape',
  'capelet',
  'chest',
  'choker',
  'collar',
  'collarbone',
  'coat',
  'dress',
  'ear',
  'eye',
  'face',
  'fang',
  'flower',
  'glasses',
  'glove',
  'hair',
  'hairband',
  'hat',
  'head',
  'headdress',
  'horn',
  'jacket',
  'jewelry',
  'mask',
  'mouth',
  'neck',
  'necktie',
  'ribbon',
  'robe',
  'shirt',
  'shoulder',
  'sleeve',
  'torso',
  'upper',
  'veil',
];

const lowerKeywords = [
  'anklet',
  'bare_legs',
  'barefoot',
  'belt',
  'boot',
  'dress',
  'foot',
  'highleg',
  'knee',
  'leg',
  'pantyhose',
  'pants',
  'pelvic',
  'sandal',
  'shoe',
  'skirt',
  'sock',
  'strap',
  'tail',
  'thigh',
  'thighhigh',
  'toe',
];

const upperClothingKeywords = [
  'bonnet',
  'cape',
  'capelet',
  'choker',
  'collar',
  'coat',
  'dress',
  'glove',
  'hat',
  'headdress',
  'jacket',
  'necktie',
  'robe',
  'shirt',
  'sleeve',
  'veil',
];

const lowerClothingKeywords = [
  'anklet',
  'belt',
  'boot',
  'dress',
  'highleg',
  'pantyhose',
  'pants',
  'pelvic',
  'sandal',
  'shoe',
  'skirt',
  'sock',
  'strap',
  'thighhigh',
];

function includesAny(tag, keywords) {
  const cleaned = cleanTag(tag);
  return keywords.some((keyword) => cleaned.includes(keyword));
}

function pickTags(text, keywords) {
  return unique(splitTags(text).filter((tag) => includesAny(tag, keywords)));
}

function summarizeSplit(text) {
  const upperBody = pickTags(text, upperKeywords);
  const lowerBody = pickTags(text, lowerKeywords);
  const upperClothing = pickTags(text, upperClothingKeywords);
  const lowerClothing = pickTags(text, lowerClothingKeywords);
  return {
    upperBody,
    lowerBody,
    upperClothing,
    lowerClothing,
  };
}

function loadDanbooru() {
  if (!fs.existsSync(danbooruPath)) return {};
  const raw = readJson(danbooruPath);
  const result = {};
  for (const [query, wrapped] of Object.entries(raw)) {
    const entries = Array.isArray(wrapped)
      ? wrapped
      : Array.isArray(wrapped?.value)
        ? wrapped.value
        : [];
    const usable = entries
      .filter((entry) => entry && !entry.error && !entry.is_deprecated)
      .map((entry) => ({
        name: entry.name,
        postCount: Number(entry.post_count || 0),
        category: Number(entry.category),
      }));
    result[query] = usable;
  }
  return result;
}

const danbooru = loadDanbooru();

function normalizedDanbooruKey(value) {
  return cleanTag(value)
    .replace(/_+/g, '_')
    .replace(/\(_/g, '(')
    .replace(/_\)/g, ')');
}

function exactDanbooruTag(candidate) {
  const key = normalizedDanbooruKey(candidate);
  const entries = danbooru[key] || [];
  const exact =
    entries.find((entry) => entry.category === 4 && entry.name === key) ||
    entries.find(
      (entry) =>
        entry.category === 4 &&
        entry.name.replace(/_\(cosplay\)$/, '') === key,
    ) ||
    entries.find((entry) => entry.category === 4) ||
    entries.find((entry) => entry.category === 3);
  return exact?.name;
}

function extractKnownTags(text) {
  const found = [];
  const lowerText = normalizeTagText(text).toLowerCase().replace(/\s+/g, '_');
  for (const query of Object.keys(danbooru)) {
    if (!query.includes('(') && query !== 'ju_fufu') continue;
    const tag = exactDanbooruTag(query);
    if (!tag) continue;
    if (lowerText.includes(query) || lowerText.includes(tag)) {
      found.push(tag);
    }
  }
  for (const rawTag of splitTags(text)) {
    const tag = exactDanbooruTag(rawTag);
    if (tag) found.push(tag);
  }
  return unique(found);
}

function labelFromDanbooruTag(tag, fallback) {
  if (!tag) return fallback;
  const parts = [...String(tag).matchAll(/\(([^)]+)\)/g)].map((match) => match[1]);
  const costume = parts.find(
    (part) =>
      ![
        'arknights',
        'granblue_fantasy',
        'genshin_impact',
        'azur_promilia',
        'flower_knight_girl',
      ].includes(part),
  );
  if (!costume) return fallback;
  return costume
    .split('_')
    .map((word) => `${word.charAt(0).toUpperCase()}${word.slice(1)}`)
    .join(' ');
}

function looksGenericOutfitName(name) {
  return /^变体\s*\d+$/u.test(name) || name === '服装';
}

function mergeNote(existing, sections) {
  const lines = [];
  const retained = String(existing || '')
    .trim()
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith('整理:'))
    .join('\n');
  if (retained) lines.push(retained);
  const useful = Object.entries(sections).filter(([, value]) => value);
  if (useful.length) {
    lines.push(
      `整理: ${useful
        .map(([label, value]) => `${label}: ${value}`)
        .join(' | ')}`,
    );
  }
  return lines.join('\n');
}

function updateViewVariants(variants) {
  const next = { ...variants };
  next.front_full = normalizeTagText(next.front_full || '');
  const split = summarizeSplit(next.front_full);
  if (!next.front_upper && split.upperBody.length) {
    next.front_upper = split.upperBody.join(', ');
  }
  if (!next.front_lower && split.lowerBody.length) {
    next.front_lower = split.lowerBody.join(', ');
  }
  return { next, split };
}

function parseArtistEntries(prompt) {
  const entries = [];
  const re = /(?:(\d+(?:\.\d+)?)::\s*)?artist:\s*([^,:\n\]}]+(?:\([^)]*\))?)/gi;
  let match;
  while ((match = re.exec(prompt))) {
    const name = match[2].trim().replace(/\s+/g, '_');
    if (!name) continue;
    entries.push({
      name,
      ...(match[1] ? { weight: Number(match[1]) } : {}),
    });
  }
  return unique(entries.map((entry) => JSON.stringify(entry))).map((entry) =>
    JSON.parse(entry),
  );
}

function parseStyleTags(prompt) {
  return unique(
    splitTags(prompt)
      .map((tag) =>
        tag
          .replace(/^[{[\s]+/, '')
          .replace(/[}\]\s]+$/, '')
          .replace(/^\d+(?:\.\d+)?::/, '')
          .replace(/::$/, '')
          .trim(),
      )
      .filter((tag) => tag && !/^artist:/i.test(tag))
      .filter((tag) => !/^\d{4}$/.test(tag))
      .slice(0, 24),
  );
}

function isValidImageRef(ref) {
  if (!ref || typeof ref !== 'string') return false;
  const direct = path.isAbsolute(ref) ? ref : path.join(workspaceRoot, ref);
  if (fs.existsSync(direct)) return true;
  const candidates = [
    path.join(workspaceRoot, ref),
    path.join(workspaceRoot, 'assets', 'references', ref),
    path.join(workspaceRoot, 'imports', 'artist_studio', ref),
    path.join(workspaceRoot, 'imports', 'external', ref),
  ];
  return candidates.some((candidate) => fs.existsSync(candidate));
}

function slugify(value) {
  return String(value || 'asset')
    .normalize('NFKD')
    .replace(/[^\x00-\x7F]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80) || 'asset';
}

function safePreviewPrompt(title, tagText, kind) {
  const blocked = new Set([
    'cleavage',
    'underboob',
    'sideboob',
    'nude',
    'naked',
    'sensitive',
    'maebari',
    'highleg',
    'covered_nipples',
    'huge_breasts',
    'loli',
    'young',
  ]);
  const safeTags = splitTags(tagText)
    .map(cleanTag)
    .filter((tag) => tag && !blocked.has(tag))
    .filter((tag) => !tag.includes('artist:'))
    .slice(0, 28);
  return [
    `Safe non-explicit anime ${kind} reference sheet for asset library preview.`,
    `Subject: ${title}.`,
    `Tags to suggest design: ${safeTags.join(', ')}.`,
    'Single character, modest outfit, clean standing pose, clear silhouette, plain light background, no text, no watermark.',
  ].join(' ');
}

const characters = readJson(charactersPath);
const artistChains = readJson(artistChainsPath);
const report = {
  generatedAt: new Date().toISOString(),
  workspaceRoot,
  characters: [],
  artistChains: [],
  movedArtistPrompts: [],
  warnings: [],
};
const imageQueue = [];

const existingArtistIds = new Set(artistChains.map((chain) => chain.id));

for (const character of characters) {
  const traitUpdate = updateViewVariants(character.traits || {});
  character.traits = traitUpdate.next;
  const characterTags = extractKnownTags(character.traits.front_full);
  const demographicTags = demographicIdentityTags(character);
  const baseCharacterTags = withoutSkinVariantAliases([
    ...(character.anchorTags || []),
    ...characterTags,
  ]);
  character.anchorTags = baseCharacterTags;
  character.identityTags = withoutSkinVariantAliases([
    ...(character.identityTags || []),
    ...baseCharacterTags,
    ...demographicTags,
    ...traitUpdate.split.upperBody.map(cleanTag),
    ...traitUpdate.split.lowerBody.map(cleanTag),
  ]);
  character.aliases = unique([
    ...(character.aliases || []).filter((value) => !String(value).includes(':')),
    character.name,
    ...baseCharacterTags,
  ]);

  if (!character.imageRefs?.some(isValidImageRef)) {
    const rel = `assets/references/${slugify(character.id)}.png`;
    character.imageRefs = [rel];
    imageQueue.push({
      id: character.id,
      type: 'character',
      title: character.name,
      prompt: safePreviewPrompt(
        `${character.name} (${characterTags[0] || character.id})`,
        character.traits.front_full,
        'character',
      ),
      outputPath: path.join(workspaceRoot, rel),
    });
  }

  const organizedOutfits = [];
  for (const outfit of character.outfits || []) {
    const frontFull = outfit.tags?.front_full || '';
    const isArtistDump = /artist:/i.test(frontFull) && splitTags(frontFull).length > 12;
    if (isArtistDump) {
      const chainId = `${outfit.id}-artist-chain`;
      if (!existingArtistIds.has(chainId)) {
        artistChains.push({
          id: chainId,
          name: `${character.name} 混合画师串`,
          tags: ['角色误入画师串', character.name],
          prompt: normalizeTagText(frontFull),
          styleTags: parseStyleTags(frontFull),
          source: { type: 'asset_library_organizer', id: outfit.id },
          note: '从角色服装格中识别出画师串，已移入画师串库。',
          artists: parseArtistEntries(frontFull),
        });
        existingArtistIds.add(chainId);
      }
      report.movedArtistPrompts.push({
        characterId: character.id,
        outfitId: outfit.id,
        newArtistChainId: chainId,
      });
      continue;
    }

    const update = updateViewVariants(outfit.tags || {});
    outfit.tags = update.next;
    const outfitTags = extractKnownTags(outfit.tags.front_full);
    const mixedCharacterPool =
      outfitTags.length > 6 && String(outfit.tags.front_full || '').includes('\n');
    if (mixedCharacterPool) {
      report.warnings.push({
        id: outfit.id,
        type: 'mixed_character_pool',
        message: '该条目包含多个角色/服装 tag，已从角色服装列表移除。',
      });
      continue;
    } else if (looksGenericOutfitName(outfit.name)) {
      outfit.name = labelFromDanbooruTag(outfitTags[0], outfit.name);
    }

    if (!mixedCharacterPool && !outfit.imageRefs?.some(isValidImageRef)) {
      const rel = `assets/references/${slugify(outfit.id)}.png`;
      outfit.imageRefs = [rel];
      imageQueue.push({
        id: outfit.id,
        type: 'outfit',
        characterId: character.id,
        title: `${character.name} / ${outfit.name}`,
        prompt: safePreviewPrompt(
          `${character.name} ${outfit.name}`,
          `${character.traits.front_full}, ${outfit.tags.front_full}`,
          'outfit',
        ),
        outputPath: path.join(workspaceRoot, rel),
      });
    }

    outfit.note = mergeNote(outfit.note, {
      Danbooru标签: outfitTags.join(', '),
      上装: update.split.upperClothing.join(', '),
      下装: update.split.lowerClothing.join(', '),
      上身: outfit.tags.front_upper || '',
      下身: outfit.tags.front_lower || '',
    });
    organizedOutfits.push(outfit);
  }
  character.outfits = organizedOutfits;
  character.defaultOutfitId = organizedOutfits.some(
    (outfit) => outfit.id === character.defaultOutfitId,
  )
    ? character.defaultOutfitId
    : organizedOutfits[0]?.id;
  if (!character.defaultOutfitId) delete character.defaultOutfitId;

  character.note = mergeNote(character.note, {
    Danbooru标签: characterTags.join(', '),
    上身: character.traits.front_upper || '',
    下身: character.traits.front_lower || '',
  });
  report.characters.push({
    id: character.id,
    name: character.name,
    anchorTags: character.anchorTags || [],
    outfitCount: character.outfits.length,
    imageRefs: character.imageRefs || [],
  });
}

for (const chain of artistChains) {
  chain.prompt = normalizeTagText(chain.prompt || '');
  chain.artists = parseArtistEntries(chain.prompt);
  chain.styleTags = unique([...(chain.styleTags || []), ...parseStyleTags(chain.prompt)]);
  chain.tags = unique([...(chain.tags || []), chain.name]);
  if (!chain.imageRefs?.some(isValidImageRef)) {
    const rel = `assets/references/${slugify(chain.id)}.png`;
    chain.imageRefs = [rel];
    imageQueue.push({
      id: chain.id,
      type: 'artist_chain',
      title: chain.name,
      prompt: safePreviewPrompt(chain.name, chain.prompt, 'style sample'),
      outputPath: path.join(workspaceRoot, rel),
    });
  }
  chain.note = mergeNote(chain.note, {
    画师: chain.artists.map((artist) => artist.name).join(', '),
    风格词: chain.styleTags.slice(0, 12).join(', '),
  });
  report.artistChains.push({
    id: chain.id,
    name: chain.name,
    artistCount: chain.artists.length,
    styleTagCount: chain.styleTags.length,
    imageRefs: chain.imageRefs || [],
  });
}

fs.mkdirSync(referencesDir, { recursive: true });
writeJson(charactersPath, characters);
writeJson(artistChainsPath, artistChains);
writeJson(reportPath, report);
writeJson(imageQueuePath, imageQueue);

console.log(
  JSON.stringify(
    {
      characters: characters.length,
      outfits: characters.reduce(
        (count, character) => count + (character.outfits?.length || 0),
        0,
      ),
      artistChains: artistChains.length,
      imageQueue: imageQueue.length,
      reportPath,
      imageQueuePath,
    },
    null,
    2,
  ),
);
