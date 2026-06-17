import fs from 'node:fs';
import path from 'node:path';

const repoRoot = process.cwd();
const workspaceRoot =
  process.argv.find((arg) => arg.startsWith('--workspace='))?.slice(12) ||
  'C:/Users/admin/AppData/Roaming/Novel Studio/Novel Studio/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const charactersPath = path.join(libraryRoot, 'characters.json');
const options = parseArgs(process.argv.slice(2));
const queuePath = resolvePath(repoRoot, options.queue);
const planPath = resolvePath(libraryRoot, options.plan);

const defaultOutfitId = 'default-outfit';
const artistChain = 'artist:akiyama_enma, artist:ciloranko, artist:ningen_mame';
const quality = 'best quality, amazing quality, very aesthetic, absurdres';
const negativePrompt =
  'lowres, bad anatomy, bad hands, missing fingers, extra fingers, ' +
  'worst quality, low quality, blurry, text, watermark, logo, signature, ' +
  'nsfw, nude, explicit, multiple girls, 2girls, 3girls, group, crowd, ' +
  'multiple views, character sheet, collage, grid, panel, comic, manga panel, ' +
  'speech bubble, chibi, mascot, creature, monster, censored, mosaic censoring, ' +
  'black bars, cropped, out of frame, upper body only, lower body only, ' +
  'close-up, portrait crop, cropped legs, feet only, extra arms, extra legs, ' +
  'duplicate, clone, bad feet, malformed feet';

const actions = [
  'standing pose, relaxed arms, calm expression',
  'walking forward, hair and clothes gently flowing',
  'turning mid-step, soft dynamic motion',
  'one hand raised slightly, confident stance',
];

const backgrounds = [
  'simple white background, clean studio lighting',
  'plain light gray background, no props',
  'minimal pale background, uncluttered',
];

function parseArgs(args) {
  const parsed = {
    queue: 'tool/asset-library-variant-outfit-preview-queue.json',
    plan: 'asset_variant_outfit_preview_plan.json',
    suffix: 'nai-v45-variant-outfit',
    fixedSize: [832, 1216],
    characterId: '',
    outfitId: '',
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
    } else if (arg.startsWith('--character=')) {
      parsed.characterId = arg.slice('--character='.length);
    } else if (arg.startsWith('--outfit=')) {
      parsed.outfitId = arg.slice('--outfit='.length);
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

function splitTags(value) {
  return String(value || '')
    .replace(/\r\n?/g, '\n')
    .split(/[,\n]/)
    .map((tag) => tag.trim())
    .filter(Boolean);
}

function unique(values) {
  const seen = new Set();
  const result = [];
  for (const raw of values) {
    const value = String(raw || '').trim();
    const key = value.toLowerCase();
    if (!value || seen.has(key)) continue;
    seen.add(key);
    result.push(value);
  }
  return result;
}

function slugify(value) {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 150);
}

function safePromptTags(values, { filterOutfitLeaks = false } = {}) {
  return unique(values)
    .filter((tag) => !/^(1girl|1boy|solo|standing|full_body|highres)$/i.test(tag))
    .filter((tag) => !filterOutfitLeaks || !outfitLeakPattern.test(tag))
    .filter((tag) => !/\b(nsfw|nude|naked|explicit|sex|loli|shota)\b/i.test(tag));
}

const outfitLeakPattern =
  /(^|[_\s])(hood|hooded|hoodie|wearing_hood|hood_over_head|hood_up|jacket|coat|dress|skirt|shorts|shirt|robe|kimono|swimsuit|bikini|shoes|boots|sandals|socks)($|[_\s])/i;

function normalizeKey(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/[{}\[\]]/g, '')
    .replace(/[()]+/g, ' ')
    .replace(/[_\s]+/g, ' ')
    .trim();
}

function hasKnownSourceName(tag) {
  const key = normalizeKey(tag);
  return key.includes(' arknights') ||
    key.includes(' blue archive') ||
    key.includes(' date a live') ||
    key.includes(' honkai') ||
    key.includes(' genshin impact') ||
    key.includes(' granblue fantasy') ||
    key.includes(' princess connect') ||
    key.includes(' touhou') ||
    key.includes(' azur lane') ||
    key.includes(' fate grand order') ||
    key.includes(' hololive') ||
    key.includes(' nijisanji') ||
    key.includes(' idolmaster') ||
    key.includes(' pokemon');
}

function looksLikeOutfitIdentityTag(tag) {
  const value = String(tag || '').trim();
  if (!value) return false;
  const groups = value.match(/\([^)]*[a-z][^)]*\)/gi) || [];
  return groups.length >= 2 && hasKnownSourceName(value);
}

function outfitIdentitySubject(outfit) {
  return unique(
    splitTags(outfit?.tags?.front_full || '').filter(looksLikeOutfitIdentityTag),
  );
}

function characterSubject(character) {
  return safePromptTags([
    ...(character.anchorTags || []),
    ...(character.identityTags || []),
  ], { filterOutfitLeaks: true }).slice(0, 8);
}

function outfitSubject(outfit) {
  const partTags = outfit.partTags || {};
  return safePromptTags([
    outfit.name,
    ...splitTags(outfit.tags?.front_full || ''),
    ...splitTags(outfit.tags?.front_upper || ''),
    ...splitTags(outfit.tags?.front_lower || ''),
    ...(partTags.upperBodyTags || []),
    ...(partTags.upperClothingTags || []),
    ...(partTags.lowerBodyTags || []),
    ...(partTags.lowerClothingTags || []),
    ...(partTags.weaponTags || []),
  ]).slice(0, 32);
}

function shouldQueueOutfit(outfit) {
  if (!outfit?.id || outfit.id === defaultOutfitId) return false;
  const partTags = outfit.partTags || {};
  const upper = [
    ...(partTags.upperClothingTags || []),
    ...splitTags(outfit.tags?.front_upper || ''),
  ];
  const lower = [
    ...(partTags.lowerClothingTags || []),
    ...splitTags(outfit.tags?.front_lower || ''),
  ];
  return upper.length > 0 && lower.length > 0;
}

function negativePromptFor(outfit) {
  return unique([
    negativePrompt,
    ...splitTags(outfit.negativePrompt || ''),
  ]).join(', ');
}

function promptFor({ character, outfit, index }) {
  const outfitIdentity = outfitIdentitySubject(outfit);
  const subject = outfitIdentity.length > 0
    ? outfitSubject(outfit)
    : [...characterSubject(character), ...outfitSubject(outfit)];
  return [
    artistChain,
    ...subject,
    quality,
    '1girl, solo, single character, one person only',
    'full body, head-to-toe, entire body visible, feet visible, centered composition',
    actions[index % actions.length],
    backgrounds[index % backgrounds.length],
    'clean readable outfit, accurate costume details',
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
  if (options.characterId && character.id !== options.characterId) continue;
  for (const outfit of character.outfits || []) {
    if (options.outfitId && outfit.id !== options.outfitId) continue;
    if (!shouldQueueOutfit(outfit)) {
      if (outfit?.id && outfit.id !== defaultOutfitId) {
        skipped.push({
          characterId: character.id,
          outfitId: outfit.id,
          outfitName: outfit.name,
          reason: 'missing upper or lower clothing tags',
        });
      }
      continue;
    }
    const index = queue.length;
    const [width, height] = options.fixedSize;
    const rel = `assets/references/novelai-character-previews/${slugify(
      `${character.id}-${outfit.id}-${options.suffix}`,
    )}.png`;
    const item = {
      id: `${character.id}-${outfit.id}-${options.suffix}`,
      type: 'outfit',
      sourceId: outfit.id,
      characterId: character.id,
      subjectName: `${character.name} / ${outfit.name}`,
      imageRef: rel,
      title: `${character.name} / ${outfit.name} / variant outfit preview`,
      prompt: promptFor({ character, outfit, index }),
      negativePrompt: negativePromptFor(outfit),
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
    };
    queue.push(item);
    refs.push({
      type: 'outfit',
      sourceId: outfit.id,
      characterId: character.id,
      imageRef: rel,
      promptSubject: unique([
        ...(outfitIdentitySubject(outfit).length > 0 ? [] : characterSubject(character)),
        ...outfitSubject(outfit),
      ]).join(', '),
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
