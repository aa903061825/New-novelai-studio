import fs from 'node:fs';
import path from 'node:path';

const repoRoot = 'C:/Users/admin/Downloads/NAI_NEW';
const workspaceRoot =
  'C:/Users/admin/AppData/Roaming/Novel Studio/Novel Studio/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const charactersPath = path.join(libraryRoot, 'characters.json');
const artistChainsPath = path.join(libraryRoot, 'artist_chains.json');
const queuePath = path.join(
  repoRoot,
  'tool',
  'asset-library-artist-chain-varsize-preview-queue.json',
);
const planPath = path.join(
  libraryRoot,
  'asset_artist_chain_varsize_preview_plan.json',
);

const suffix = 'nai-v45-varsize-b1';
const previewDir = 'assets/references/artist-chain-varsize-previews';
const defaultQuality = 'best quality, amazing quality, very aesthetic, absurdres';
const negativePrompt = [
  'lowres, bad anatomy, bad hands, missing fingers, extra fingers',
  'worst quality, low quality, blurry, text, watermark, logo, signature',
  'nsfw, nude, explicit, multiple girls, 2girls, 3girls, group, crowd',
  'multiple views, character sheet, reference sheet, collage, grid, panel',
  'comic, manga panel, speech bubble, mascot, creature, monster',
  'censored, mosaic censoring, black bars, cropped, out of frame',
  'extra arms, extra legs, duplicate, clone, bad feet, malformed feet',
].join(', ');

const excludedCharacterIds = new Set([
  'legacy-character-sheet-r24',
  'legacy-character-sheet-r27',
  'legacy-character-sheet-r30',
]);
const unsafePattern =
  /\b(nsfw|nude|naked|explicit|sex|sexual|erotic|nipples?|pussy|penis|cum|spread legs|uncensored|loli|shota|child|young)\b/i;
const brokenPattern =
  /\b(worst quality|low quality|bad quality|bad anatomy|bad hands|missing fingers?|extra fingers?|extra digits|fewer digits|mutation|deformed|disfigured|duplicate|watermark|signature|username|text|logo|censored|mosaic)\b/i;
const yearPattern = /^year\s+\d{4}$/i;

const sizes = [
  {
    key: 'portrait-832x1216',
    width: 832,
    height: 1216,
    framing: 'full body, feet visible, centered composition',
    action: 'walking forward, hair and clothes gently flowing',
    background:
      'sunlit flower garden background, petals in the air, soft natural light',
  },
  {
    key: 'square-1024x1024',
    width: 1024,
    height: 1024,
    framing: 'cowboy shot, centered composition, looking at viewer',
    action: 'one hand raised slightly, calm confident expression',
    background:
      'cozy atelier background, art desk, warm window light, depth of field',
  },
  {
    key: 'wide-1216x832',
    width: 1216,
    height: 832,
    framing: 'full body, centered composition, wide illustration layout',
    action: 'turning mid-step, ribbons and fabric in motion',
    background:
      'night city street background, neon reflections, cinematic rim lighting',
  },
];

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, ''));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function normalizeTagText(value) {
  return String(value || '')
    .replace(/\r\n?/g, '\n')
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .join(', ');
}

function splitTags(prompt) {
  return normalizeTagText(prompt)
    .split(',')
    .map((tag) => tag.trim())
    .filter(Boolean);
}

function cleanTag(tag) {
  return String(tag || '')
    .replace(/^[{[\s]+/, '')
    .replace(/[}\]\s]+$/, '')
    .replace(/^\d+(?:\.\d+)?::\s*/, '')
    .replace(/\s*::$/, '')
    .trim();
}

function isSafeTag(tag) {
  const value = String(tag || '').trim();
  return (
    value &&
    !unsafePattern.test(value) &&
    !brokenPattern.test(value) &&
    !yearPattern.test(value)
  );
}

function safeChainPrompt(chain) {
  return splitTags(chain.prompt)
    .map((tag) => tag.replace(/\s+/g, ' ').trim())
    .filter(isSafeTag)
    .join(', ');
}

function safeSubjectTags(character) {
  return splitTags(character.traits?.front_full)
    .map(cleanTag)
    .filter(isSafeTag)
    .join(', ');
}

function slugify(value) {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 150);
}

function buildPrompt({ chainPrompt, subjectTags, size, index }) {
  const background =
    index % 2 === 0
      ? size.background
      : 'clean bright studio background, subtle decorative shapes, soft light';
  return [
    chainPrompt,
    subjectTags,
    defaultQuality,
    '1girl, solo, single character, one person only',
    size.framing,
    size.action,
    background,
    'clean readable pose, appealing character portrait',
    'safe, non-explicit, tasteful outfit',
    'no text, no watermark',
  ]
    .filter(Boolean)
    .join(', ');
}

const characters = readJson(charactersPath);
const artistChains = readJson(artistChainsPath);
const subjects = characters
  .filter((character) => !excludedCharacterIds.has(character.id))
  .map((character) => ({
    ...character,
    subjectTags: safeSubjectTags(character),
  }))
  .filter((character) => character.subjectTags);

if (!subjects.length) {
  throw new Error('No usable character subjects after exclusions.');
}

const queue = [];
const refs = [];
const skipped = [];

for (let chainIndex = 0; chainIndex < artistChains.length; chainIndex++) {
  const chain = artistChains[chainIndex];
  const chainPrompt = safeChainPrompt(chain);
  if (chain.source?.type !== 'legacy_artist_workbook') {
    skipped.push({
      id: chain.id,
      name: chain.name,
      reason: 'not_from_artist_workbook',
    });
    continue;
  }
  if (String(chain.name || '').includes(String.fromCharCode(0x53cd, 0x5411, 0x8bcd))) {
    skipped.push({ id: chain.id, name: chain.name, reason: 'negative_prompt_card' });
    continue;
  }
  if (!chainPrompt) {
    skipped.push({ id: chain.id, name: chain.name, reason: 'empty_after_filter' });
    continue;
  }

  const chainRefs = [];
  for (let sizeIndex = 0; sizeIndex < sizes.length; sizeIndex++) {
    const size = sizes[sizeIndex];
    const character =
      subjects[(chainIndex * 5 + sizeIndex * 7) % subjects.length];
    const id = `${chain.id}-${character.id}-${size.key}-${suffix}`;
    const imageRef = `${previewDir}/${slugify(id)}.png`;
    const item = {
      id: slugify(id),
      type: 'artist_chain_varsize_preview',
      artistChainId: chain.id,
      artistChainName: chain.name,
      characterId: character.id,
      characterName: character.name,
      sizeKey: size.key,
      imageRef,
      title: `${chain.name} / ${character.name} / ${size.key}`,
      prompt: buildPrompt({
        chainPrompt,
        subjectTags: character.subjectTags,
        size,
        index: sizeIndex,
      }),
      negativePrompt,
      model: 'nai-diffusion-4-5-full',
      action: 'generate',
      width: size.width,
      height: size.height,
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
      outputPath: path.join(workspaceRoot, imageRef),
    };
    queue.push(item);
    chainRefs.push({
      imageRef,
      sizeKey: size.key,
      width: size.width,
      height: size.height,
      characterId: character.id,
      characterName: character.name,
    });
  }
  refs.push({
    artistChainId: chain.id,
    artistChainName: chain.name,
    imageRefs: chainRefs,
  });
}

writeJson(queuePath, queue);
writeJson(planPath, {
  generatedAt: new Date().toISOString(),
  workspaceRoot,
  queuePath,
  suffix,
  previewDir,
  sizes: sizes.map(({ key, width, height }) => ({ key, width, height })),
  defaultQuality,
  negativePrompt,
  excludedCharacterIds: [...excludedCharacterIds],
  subjectCount: subjects.length,
  queueCount: queue.length,
  refs,
  skipped,
});

console.log(
  JSON.stringify(
    {
      artistChains: artistChains.length,
      generatedChains: refs.length,
      skipped: skipped.length,
      subjectCount: subjects.length,
      queueCount: queue.length,
      queuePath,
      planPath,
    },
    null,
    2,
  ),
);
