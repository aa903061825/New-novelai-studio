import fs from 'node:fs';
import path from 'node:path';

const repoRoot = 'C:/Users/admin/Downloads/NAI_NEW';
const workspaceRoot =
  'C:/Users/admin/AppData/Roaming/Novel Studio/Novel Studio/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const charactersPath = path.join(libraryRoot, 'characters.json');
const options = parseArgs(process.argv.slice(2));
const queuePath = resolvePath(repoRoot, options.queue);
const planPath = resolvePath(libraryRoot, options.plan);
const previewSuffix = options.suffix;

const artistChain = 'artist:akiyama_enma, artist:ciloranko, artist:ningen_mame';
const quality = 'best quality, amazing quality, very aesthetic, absurdres';
const negativePrompt =
  'lowres, bad anatomy, bad hands, missing fingers, extra fingers, ' +
  'worst quality, low quality, blurry, text, watermark, logo, signature, ' +
  'nsfw, nude, explicit, multiple girls, 2girls, 3girls, group, crowd, ' +
  'multiple views, character sheet, reference sheet, collage, grid, panel, ' +
  'comic, manga panel, speech bubble, chibi, mascot, creature, monster, ' +
  'censored, mosaic censoring, black bars, cropped, out of frame, ' +
  'upper body only, lower body only, close-up, portrait crop, cropped legs, ' +
  'feet only, extra arms, extra legs, duplicate, clone, bad feet, malformed feet';

const sizes = [
  [832, 1216],
  [1024, 1024],
  [1216, 832],
];

const actions = [
  'standing pose, relaxed arms, calm expression',
  'walking forward, hair and clothes gently flowing',
  'turning mid-step, soft dynamic motion',
  'one hand raised slightly, confident stance',
  'light step pose, ribbons and fabric in motion',
  'reaching one hand forward, gentle foreshortening',
];

const backgrounds = [
  'simple white background, clean studio lighting',
  'plain light gray background, no props',
  'minimal pale background, uncluttered',
];

const unsafePattern =
  /\b(nsfw|nude|naked|explicit|sex|sexual|erotic|nipples?|pussy|penis|cum|spread legs|child|loli|shota|young|gore|corpse|blood)\b/i;
const brokenPattern =
  /\b(worst quality|low quality|bad quality|bad anatomy|bad hands|missing fingers?|extra fingers?|extra digits|fewer digits|mutation|deformed|disfigured|duplicate|watermark|signature|username|text|logo|uncensored|censored|mosaic|multiple views|reference sheet|character sheet|collage|comic|panel|chibi|mascot)\b/i;
const qualityPattern =
  /\b(masterpiece|best quality|amazing quality|very aesthetic|absurdres|highres|ultra detailed|official art|great quality|sd)\b/i;
const genericTagPattern =
  /^(girl|1girl|solo|animal_ears|animal ears|long_hair|long hair|short_hair|white_hair|black_hair|brown_hair|blonde_hair|looking_at_viewer|smile)$/i;
const partialOutfitNamePattern =
  /(上装|下装|上半身|下半身|\bupper\b|\blower\b|upper body|lower body|top only|bottom only)/i;
const clothingTagPattern =
  /\b(dress|robe|robes|kimono|jacket|coat|shirt|skirt|shorts|pants|bodystocking|pantyhose|thighhighs|boots|shoes|sandals|socks|uniform|clothes|clothing|sweater|hoodie|cape|sash|belt|collar|sleeves?|necktie|ribbon|apron|vest|bodysuit|swimsuit|bikini|panties|leggings|stockings|gloves|garter|highleg|pelvic_curtain)\b/i;
const upperGarmentPattern =
  /\b(dress|robe|robes|kimono|jacket|coat|shirt|bodystocking|uniform|clothes|clothing|sweater|hoodie|cape|collar|sleeves?|necktie|apron|vest|bodysuit|swimsuit|bikini|highleg|chinese_clothes|japanese_clothes|ancient_egyptian_clothes)\b/i;
const lowerGarmentPattern =
  /\b(skirt|shorts|pants|pantyhose|thighhighs|boots|shoes|sandals|socks|belt|thigh_strap|thigh_belt|leggings|stockings|garter|bare_legs|highleg|pelvic_curtain)\b/i;
const genericFullBodyGarmentPattern =
  /(^|_|\b)(dress|robe|robes|clothes|clothing|bodysuit|bodystocking|swimsuit|bikini)($|_|\b)/i;

function parseArgs(args) {
  const parsed = {
    queue: 'tool/asset-library-requested-character-previews.json',
    plan: 'asset_requested_character_preview_plan.json',
    suffix: 'nai-v45-preview',
    fixedSize: null,
  };
  for (const arg of args) {
    if (arg.startsWith('--queue=')) {
      parsed.queue = arg.slice('--queue='.length);
    } else if (arg.startsWith('--plan=')) {
      parsed.plan = arg.slice('--plan='.length);
    } else if (arg.startsWith('--suffix=')) {
      parsed.suffix = arg.slice('--suffix='.length);
    } else if (arg.startsWith('--size=')) {
      const match = /^(\d+)x(\d+)$/i.exec(arg.slice('--size='.length));
      if (!match) throw new Error(`Invalid --size value: ${arg}`);
      parsed.fixedSize = [Number(match[1]), Number(match[2])];
    }
  }
  return parsed;
}

function resolvePath(baseDir, value) {
  return path.isAbsolute(value) ? value : path.join(baseDir, value);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, ''));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function normalizeText(value) {
  return String(value || '')
    .replace(/\r\n?/g, '\n')
    .split('\n')
    .map((line) =>
      line
        .split(',')
        .map((part) => part.trim())
        .filter(Boolean)
        .join(', '),
    )
    .filter(Boolean)
    .join(', ');
}

function splitTags(value) {
  return normalizeText(value)
    .split(',')
    .map((tag) => tag.trim())
    .filter(Boolean);
}

function cleanTag(value) {
  return String(value || '')
    .replace(/^[{[\s]+/, '')
    .replace(/[}\]\s]+$/, '')
    .replace(/^\d+(?:\.\d+)?::/, '')
    .replace(/::$/, '')
    .replace(/\\+/g, '')
    .trim();
}

function isSafeTag(tag) {
  if (!tag) return false;
  return !unsafePattern.test(tag) && !brokenPattern.test(tag);
}

function unique(values) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    const tag = String(value || '').trim();
    if (!tag) continue;
    const key = tag.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(tag);
  }
  return result;
}

function slugify(value) {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 140);
}

function knownTags(value) {
  return splitTags(value)
    .map(cleanTag)
    .filter(isSafeTag)
    .filter((tag) => !qualityPattern.test(tag))
    .filter((tag) => !genericTagPattern.test(tag));
}

function bestCharacterTag(character) {
  const candidates = unique([
    ...(character.anchorTags || []),
    ...(character.identityTags || []),
    ...knownTags(character.traits?.front_full),
  ]);
  return candidates.find((tag) => /[_()]|\(.*\)/.test(tag)) || candidates[0] || '';
}

function subjectForCharacter(character) {
  const main = bestCharacterTag(character);
  const traits = knownTags(character.traits?.front_full)
    .filter((tag) => tag.toLowerCase() !== main.toLowerCase())
    .slice(0, 5);
  return unique([main, ...traits]).join(', ');
}

function subjectForOutfit(character, outfit) {
  const main = bestCharacterTag(character);
  const outfitTags = knownTags(outfit.tags?.front_full);
  const outfitIdentity =
    outfitTags.find((tag) => /[_()]|\(.*\)/.test(tag) && tag.toLowerCase() !== main.toLowerCase()) ||
    '';
  const clothing = outfitTags
    .filter((tag) => tag.toLowerCase() !== main.toLowerCase())
    .filter((tag) => tag.toLowerCase() !== outfitIdentity.toLowerCase())
    .slice(0, 8);
  return unique([main, outfitIdentity, ...clothing]).join(', ');
}

function isSingleOutfit(outfit) {
  const lines = String(outfit.tags?.front_full || '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  return lines.length <= 3;
}

function parentheticalGroupCount(tag) {
  return (String(tag || '').match(/\([^)]*\)/g) || []).length;
}

function hasNamedFullOutfitTag(character, outfitTags) {
  const main = bestCharacterTag(character).toLowerCase();
  return outfitTags.some((tag) => {
    const lower = tag.toLowerCase();
    if (lower === main) return false;
    return parentheticalGroupCount(tag) >= 2;
  });
}

function clothingTags(value) {
  return knownTags(value).filter((tag) => clothingTagPattern.test(tag));
}

function specificHalfTags(tags) {
  return tags.filter((tag) => !genericFullBodyGarmentPattern.test(tag));
}

function looksLikePartialClothing(outfit) {
  const upper = specificHalfTags(clothingTags(outfit.tags?.front_upper));
  const lower = specificHalfTags(clothingTags(outfit.tags?.front_lower));
  if (upper.length >= 2 && lower.length <= 1) return true;
  if (lower.length >= 3 && upper.length === 0) return true;
  return false;
}

function hasFullClothingSet(outfit) {
  const tags = knownTags(outfit.tags?.front_full);
  const clothes = tags.filter((tag) => clothingTagPattern.test(tag));
  if (clothes.length < 4) return false;
  const upperPool = knownTags(outfit.tags?.front_upper).length
    ? knownTags(outfit.tags?.front_upper)
    : tags;
  const lowerPool = knownTags(outfit.tags?.front_lower).length
    ? knownTags(outfit.tags?.front_lower)
    : tags;
  return (
    upperPool.some((tag) => upperGarmentPattern.test(tag)) &&
    lowerPool.some((tag) => lowerGarmentPattern.test(tag))
  );
}

function classifyOutfitTarget(character, outfit) {
  if (partialOutfitNamePattern.test(outfit.name || '')) {
    return {
      shouldQueue: false,
      reason: 'upper/lower or half-body outfit entry; prompt text only',
    };
  }
  if (!isSingleOutfit(outfit)) {
    return {
      shouldQueue: false,
      reason: 'multi-line mixed candidate outfit; not a single outfit preview target',
    };
  }
  const outfitTags = knownTags(outfit.tags?.front_full);
  if (!outfitTags.length) {
    return { shouldQueue: false, reason: 'empty outfit prompt' };
  }
  if (hasNamedFullOutfitTag(character, outfitTags)) {
    return { shouldQueue: true, reason: 'named full outfit tag' };
  }
  if (looksLikePartialClothing(outfit)) {
    return {
      shouldQueue: false,
      reason: 'partial upper/lower clothing tags; prompt text only',
    };
  }
  if (hasFullClothingSet(outfit)) {
    return { shouldQueue: true, reason: 'complete clothing set tags' };
  }
  return {
    shouldQueue: false,
    reason: 'identity/accessory traits only; not a full outfit preview target',
  };
}

function promptFor({ subject, index }) {
  return [
    artistChain,
    subject,
    quality,
    '1girl, solo, single character, one person only',
    'full body, head-to-toe, entire body visible, feet visible, not cropped, centered composition',
    actions[index % actions.length],
    backgrounds[index % backgrounds.length],
    'clean readable pose, appealing character portrait',
    'no text, no watermark',
  ]
    .filter(Boolean)
    .join(', ');
}

const characters = readJson(charactersPath);
const queue = [];
const refs = [];
const skipped = [];

for (const character of characters) {
  const characterSubject = subjectForCharacter(character);
  if (characterSubject) {
    const index = queue.length;
    const [width, height] = sizes[index % sizes.length];
    const rel = `assets/references/novelai-character-previews/${slugify(
      `${character.id}-nai-v45-preview`,
    )}.png`;
    queue.push({
      id: `${character.id}-nai-v45-preview`,
      type: 'character',
      sourceId: character.id,
      subjectName: character.name,
      imageRef: rel,
      title: `${character.name} / NovelAI v4.5 preview`,
      prompt: promptFor({ subject: characterSubject, index }),
      negativePrompt,
      model: 'nai-diffusion-4-5-full',
      action: 'generate',
      width,
      height,
      steps: 28,
      sampler: 'k_euler_ancestral',
      noise_schedule: 'karras',
      scale: 6.6,
      cfg_rescale: 0.1,
      ucPreset: 2,
      qualityToggle: false,
      dynamic_thresholding: false,
      legacy: false,
      legacy_uc: false,
      use_coords: true,
      use_order: true,
      outputPath: path.join(workspaceRoot, rel),
    });
    refs.push({
      type: 'character',
      sourceId: character.id,
      imageRef: rel,
      promptSubject: characterSubject,
    });
  }

  for (const outfit of character.outfits || []) {
    const classification = classifyOutfitTarget(character, outfit);
    if (!classification.shouldQueue) {
      skipped.push({
        characterId: character.id,
        outfitId: outfit.id,
        outfitName: outfit.name,
        reason: classification.reason,
      });
      continue;
    }
    const outfitSubject = subjectForOutfit(character, outfit);
    if (!outfitSubject) {
      skipped.push({
        characterId: character.id,
        outfitId: outfit.id,
        outfitName: outfit.name,
        reason: 'empty outfit prompt',
      });
      continue;
    }
    const index = queue.length;
    const [width, height] = sizes[index % sizes.length];
    const rel = `assets/references/novelai-character-previews/${slugify(
      `${outfit.id}-nai-v45-preview`,
    )}.png`;
    queue.push({
      id: `${outfit.id}-nai-v45-preview`,
      type: 'outfit',
      sourceId: outfit.id,
      characterId: character.id,
      subjectName: `${character.name} / ${outfit.name}`,
      imageRef: rel,
      title: `${character.name} / ${outfit.name} / NovelAI v4.5 preview`,
      prompt: promptFor({ subject: outfitSubject, index }),
      negativePrompt,
      model: 'nai-diffusion-4-5-full',
      action: 'generate',
      width,
      height,
      steps: 28,
      sampler: 'k_euler_ancestral',
      noise_schedule: 'karras',
      scale: 6.6,
      cfg_rescale: 0.1,
      ucPreset: 2,
      qualityToggle: false,
      dynamic_thresholding: false,
      legacy: false,
      legacy_uc: false,
      use_coords: true,
      use_order: true,
      outputPath: path.join(workspaceRoot, rel),
    });
    refs.push({
      type: 'outfit',
      sourceId: outfit.id,
      characterId: character.id,
      imageRef: rel,
      promptSubject: outfitSubject,
      upperPrompt: normalizeText(outfit.tags?.front_upper),
      lowerPrompt: normalizeText(outfit.tags?.front_lower),
    });
  }
}

writeJson(queuePath, queue);
writeJson(planPath, {
  generatedAt: new Date().toISOString(),
  workspaceRoot,
  artistChain,
  quality,
  negativePrompt,
  queuePath,
  queueCount: queue.length,
  refs,
  skipped,
});

console.log(
  JSON.stringify(
    {
      characters: characters.length,
      queued: queue.length,
      skipped: skipped.length,
      queuePath,
      planPath,
    },
    null,
    2,
  ),
);
