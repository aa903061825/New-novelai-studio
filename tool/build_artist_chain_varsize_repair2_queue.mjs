import fs from 'node:fs';
import path from 'node:path';

const repoRoot = 'C:/Users/admin/Downloads/NAI_NEW';
const workspaceRoot =
  'C:/Users/admin/AppData/Roaming/Novel Studio/Novel Studio/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const charactersPath = path.join(libraryRoot, 'characters.json');
const artistChainsPath = path.join(libraryRoot, 'artist_chains.json');
const activeQueuePath = path.join(
  repoRoot,
  'tool',
  'asset-library-artist-chain-varsize-active-queue.json',
);
const repairQueuePath = path.join(
  repoRoot,
  'tool',
  'asset-library-artist-chain-varsize-repair2-queue.json',
);
const repairPlanPath = path.join(
  libraryRoot,
  'asset_artist_chain_varsize_repair2_plan.json',
);

const suffix = 'nai-v45-varsize-fix2';
const previewDir = 'assets/references/artist-chain-varsize-previews';
const defaultQuality = 'best quality, amazing quality, very aesthetic, absurdres';
const negativePrompt = [
  'lowres, bad anatomy, bad hands, missing fingers, extra fingers',
  'worst quality, low quality, blurry, text, watermark, logo, signature',
  'nsfw, nude, explicit, multiple girls, 2girls, 3girls, group, crowd',
  'multiple views, character sheet, reference sheet, collage, grid, panel',
  'comic, manga panel, speech bubble, chibi, mascot, creature, monster',
  'emoji, sticker, meme, abstract pattern, psychedelic, posterized colors',
  'censored, mosaic censoring, black bars, cropped, out of frame',
  'overexposed, oversaturated, high contrast, blown highlights',
  'neon glow, glowing text, random letters, japanese text, chinese text',
  'extra arms, extra legs, duplicate, clone, bad feet, malformed feet',
].join(', ');

const targetOldIds = new Set([
  'legacy-artist-sheet-r6c3-legacy-character-sheet-r5-portrait-832x1216-nai-v45-varsize-fix1',
  'legacy-artist-sheet-r6c3-legacy-character-sheet-r13-square-1024x1024-nai-v45-varsize-fix1',
  'legacy-artist-sheet-r6c3-legacy-character-sheet-r26-wide-1216x832-nai-v45-varsize-fix1',
  'legacy-artist-sheet-r8c1-legacy-character-sheet-r14-wide-1216x832-nai-v45-varsize-fix1',
  'legacy-artist-sheet-r4c3-legacy-character-sheet-r14-square-1024x1024-nai-v45-varsize-fix1',
  'legacy-artist-sheet-r10c7-legacy-character-sheet-r25-portrait-832x1216-nai-v45-varsize-fix1',
  'legacy-artist-sheet-r10c7-legacy-character-sheet-r4-square-1024x1024-nai-v45-varsize-fix1',
  'legacy-artist-sheet-r10c7-legacy-character-sheet-r11-wide-1216x832-nai-v45-varsize-fix1',
  'legacy-artist-sheet-r2c3-legacy-character-sheet-r7-portrait-832x1216-nai-v45-varsize-fix1',
  'legacy-artist-sheet-r2c3-legacy-character-sheet-r15-square-1024x1024-nai-v45-varsize-fix1',
  'legacy-artist-sheet-r2c3-legacy-character-sheet-r19-wide-1216x832-nai-v45-varsize-fix1',
]);

const unsafePattern =
  /\b(nsfw|nude|naked|explicit|sex|sexual|erotic|nipples?|pussy|penis|cum|spread legs|uncensored|loli|shota|child|young)\b/i;
const brokenPattern =
  /\b(worst quality|low quality|bad quality|bad anatomy|bad hands|missing fingers?|extra fingers?|extra digits|fewer digits|mutation|deformed|disfigured|duplicate|watermark|signature|username|text|logo|censored|mosaic)\b/i;
const styleNoisePattern =
  /\b(official[_ ]art|official_style|masterpiece|best[_ ]quality|great[_ ]quality|amazing[_ ]quality|very[_ ]aesthetic|absurdres|highres|extremely[_ ]detailed|wallpaper|lighting|illumination|glow|skin|motion[_ ]lines|speed[_ ]lines|chibi|sd|jaggy(?:[_ ]lines)?|outline|artist[_ ]collaboration|detailed|natural|uncensored|year[_ ]\d{4}|3d|photorealistic)\b/i;

const sizeProfiles = {
  'portrait-832x1216': {
    framing: 'full body, feet visible, centered composition',
    action: 'standing pose, relaxed arms, calm expression',
    background: 'soft neutral studio background, muted colors, even daylight',
  },
  'square-1024x1024': {
    framing: 'cowboy shot, centered composition, looking at viewer',
    action: 'gentle hand gesture, clean readable pose',
    background: 'plain warm gray studio background, low saturation, soft light',
  },
  'wide-1216x832': {
    framing: 'full body, centered composition, wide illustration layout',
    action: 'slow walking pose, fabric gently moving',
    background:
      'quiet garden courtyard background, muted colors, balanced soft daylight',
  },
};

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
    .replace(/^-?\d+(?:\.\d+)?::\s*/, '')
    .replace(/\s*::$/, '')
    .trim();
}

function slugify(value) {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 150);
}

function unique(values) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    const text = String(value || '').trim();
    if (!text) continue;
    const key = text.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(text);
  }
  return result;
}

function normalizeArtistName(value) {
  return String(value || '')
    .trim()
    .replace(/^artist:\s*/i, '')
    .replace(/\s+/g, '_');
}

function isCleanArtistName(name) {
  return (
    name &&
    !unsafePattern.test(name) &&
    !styleNoisePattern.test(name) &&
    !/^-?\d+(?:\.\d+)?(?:::|$)/.test(name) &&
    !/::/.test(name) &&
    /[a-zA-Z_]/.test(name)
  );
}

function formatArtistToken(name, weight = 1) {
  const normalized = normalizeArtistName(name);
  if (!isCleanArtistName(normalized)) return '';
  const tokenName = /\d$/.test(normalized) ? `${normalized} ` : normalized;
  const numericWeight = Number(weight || 1);
  if (Number.isFinite(numericWeight) && numericWeight > 0 && numericWeight !== 1) {
    return `${numericWeight}::artist:${tokenName}::`;
  }
  return `artist:${normalized}`;
}

function artistToken(entry) {
  return formatArtistToken(entry?.name, entry?.weight);
}

function rawArtistToken(tag) {
  const raw = String(tag || '').trim();
  if (/^-/.test(raw)) return '';
  const weighted = raw.match(/^(\d+(?:\.\d+)?)::\s*(.+?)\s*::$/);
  if (weighted) {
    return formatArtistToken(weighted[2], Number(weighted[1]));
  }
  if (/::/.test(raw)) return '';
  return formatArtistToken(raw, 1);
}

function cleanArtistPrompt(chain) {
  const fromStructured = (chain.artists || []).map(artistToken).filter(Boolean);
  if (fromStructured.length) return unique(fromStructured).slice(0, 10).join(', ');

  return unique(splitTags(chain.prompt).map(rawArtistToken).filter(Boolean))
    .slice(0, 10)
    .join(', ');
}

function safeSubjectTags(character) {
  return splitTags(character.traits?.front_full)
    .filter((tag) => !/^-/.test(tag.trim()))
    .map(cleanTag)
    .filter(
      (tag) =>
        tag &&
        !unsafePattern.test(tag) &&
        !brokenPattern.test(tag) &&
        !/\b(hood up|wearing hood|hood over head)\b/i.test(tag),
    )
    .join(', ');
}

function buildPrompt({ artistPrompt, subjectTags, size }) {
  return [
    artistPrompt,
    subjectTags,
    defaultQuality,
    '1girl, solo, single character, one person only',
    size.framing,
    size.action,
    size.background,
    'natural skin tones, balanced lighting, no overexposure',
    'clean readable pose, appealing character portrait',
    'safe, non-explicit, tasteful outfit',
    'no text, no watermark',
  ]
    .filter(Boolean)
    .join(', ');
}

const activeQueue = readJson(activeQueuePath);
const artistChains = readJson(artistChainsPath);
const characters = readJson(charactersPath);

const queue = [];
const replacements = [];
for (const source of activeQueue.filter((item) => targetOldIds.has(item.id))) {
  const chain = artistChains.find((item) => item.id === source.artistChainId);
  const character = characters.find((item) => item.id === source.characterId);
  const size = sizeProfiles[source.sizeKey];
  const artistPrompt = chain ? cleanArtistPrompt(chain) : '';
  if (!chain || !character || !size || !artistPrompt) {
    throw new Error(`Cannot repair ${source.id}; missing chain, character, size, or artist prompt.`);
  }

  const newId = slugify(
    `${source.artistChainId}-${source.characterId}-${source.sizeKey}-${suffix}`,
  );
  const newImageRef = `${previewDir}/${newId}.png`;
  queue.push({
    ...source,
    id: newId,
    imageRef: newImageRef,
    title: `${source.title} / repaired-2`,
    prompt: buildPrompt({
      artistPrompt,
      subjectTags: safeSubjectTags(character),
      size,
    }),
    negativePrompt,
    outputPath: path.join(workspaceRoot, newImageRef),
  });
  replacements.push({
    oldId: source.id,
    newId,
    artistChainId: source.artistChainId,
    sizeKey: source.sizeKey,
    oldImageRef: source.imageRef,
    newImageRef,
  });
}

writeJson(repairQueuePath, queue);
writeJson(repairPlanPath, {
  generatedAt: new Date().toISOString(),
  workspaceRoot,
  activeQueuePath,
  repairQueuePath,
  suffix,
  targetOldIds: [...targetOldIds],
  repairQueueCount: queue.length,
  replacementCount: replacements.length,
  removalCount: 0,
  replacements,
  removals: [],
});

console.log(
  JSON.stringify(
    {
      repairQueueCount: queue.length,
      repairQueuePath,
      repairPlanPath,
      prompts: queue.map((item) => ({ id: item.id, prompt: item.prompt })),
    },
    null,
    2,
  ),
);
