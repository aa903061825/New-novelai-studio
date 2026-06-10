import fs from 'node:fs';
import path from 'node:path';

const repoRoot = 'C:/Users/admin/Downloads/NAI_NEW';
const workspaceRoot =
  'C:/Users/admin/AppData/Roaming/org.exception0x0194/nai3_autodraw/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const charactersPath = path.join(libraryRoot, 'characters.json');
const artistChainsPath = path.join(libraryRoot, 'artist_chains.json');
const sourceQueuePath = path.join(
  repoRoot,
  'tool',
  'asset-library-artist-chain-varsize-preview-queue.json',
);
const auditPath = path.join(
  libraryRoot,
  'asset_artist_chain_varsize_visual_audit.json',
);
const repairQueuePath = path.join(
  repoRoot,
  'tool',
  'asset-library-artist-chain-varsize-repair-queue.json',
);
const repairPlanPath = path.join(
  libraryRoot,
  'asset_artist_chain_varsize_repair_plan.json',
);

const suffix = 'nai-v45-varsize-fix1';
const previewDir = 'assets/references/artist-chain-varsize-previews';
const defaultQuality = 'best quality, amazing quality, very aesthetic, absurdres';
const negativePrompt = [
  'lowres, bad anatomy, bad hands, missing fingers, extra fingers',
  'worst quality, low quality, blurry, text, watermark, logo, signature',
  'nsfw, nude, explicit, multiple girls, 2girls, 3girls, group, crowd',
  'multiple views, character sheet, reference sheet, collage, grid, panel',
  'comic, manga panel, speech bubble, mascot, creature, monster',
  'censored, mosaic censoring, black bars, cropped, out of frame',
  'overexposed, oversaturated, high contrast, blown highlights',
  'neon glow, glowing text, random letters, japanese text, chinese text',
  'extra arms, extra legs, duplicate, clone, bad feet, malformed feet',
].join(', ');

const dirtyPromptPattern =
  /\b(official art|official_style|masterpiece|extremely detailed|8k|cg unity|beautiful detailed glow|best illumination|cinematic lighting|detailed lighting|glossy skin|soft skin|subsurface scattering|humid skin|detailed skin texture|shiny skin|deep skin|motion lines|speed lines|chibi|sd|jaggy lines|outline|volumetric lighting)\b/i;
const unsafePattern =
  /\b(nsfw|nude|naked|explicit|sex|sexual|erotic|nipples?|pussy|penis|cum|spread legs|uncensored|loli|shota|child|young)\b/i;
const brokenPattern =
  /\b(worst quality|low quality|bad quality|bad anatomy|bad hands|missing fingers?|extra fingers?|extra digits|fewer digits|mutation|deformed|disfigured|duplicate|watermark|signature|username|text|logo|censored|mosaic)\b/i;
const styleNoisePattern =
  /\b(official[_ ]art|official_style|masterpiece|best[_ ]quality|great[_ ]quality|amazing[_ ]quality|very[_ ]aesthetic|absurdres|highres|extremely[_ ]detailed|wallpaper|lighting|illumination|glow|skin|motion[_ ]lines|speed[_ ]lines|chibi|sd|jaggy(?:[_ ]lines)?|outline|artist[_ ]collaboration|detailed|natural|uncensored|year[_ ]\d{4}|3d|photorealistic)\b/i;

const sizes = {
  'portrait-832x1216': {
    width: 832,
    height: 1216,
    framing: 'full body, feet visible, centered composition',
    action: 'standing pose, relaxed arms, calm expression',
    background:
      'soft neutral studio background, balanced exposure, muted color palette',
  },
  'square-1024x1024': {
    width: 1024,
    height: 1024,
    framing: 'cowboy shot, centered composition, looking at viewer',
    action: 'gentle hand gesture, clean readable pose',
    background:
      'plain warm gray studio background, low saturation, soft natural light',
  },
  'wide-1216x832': {
    width: 1216,
    height: 832,
    framing: 'full body, centered composition, wide illustration layout',
    action: 'slow walking pose, fabric gently moving',
    background:
      'quiet garden courtyard background, muted colors, soft daylight',
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

function artistToken(entry) {
  const name = String(entry?.name || '')
    .trim()
    .replace(/\s+/g, '_');
  if (
    !name ||
    unsafePattern.test(name) ||
    styleNoisePattern.test(name) ||
    /^-?\d+(?:\.\d+)?(?:::|$)/.test(name) ||
    /::/.test(name)
  ) {
    return '';
  }
  const token = `artist:${name}`;
  const weight = Number(entry.weight || 1);
  if (Number.isFinite(weight) && weight > 0 && weight !== 1) {
    return `${weight}::${token}::`;
  }
  return token;
}

function inferredArtistToken(tag) {
  const raw = String(tag || '').trim();
  if (/^-/.test(raw) || /::.*::/.test(cleanTag(raw))) return '';
  const cleaned = cleanTag(tag)
    .replace(/^artist:\s*/i, '')
    .replace(/\s+/g, '_')
    .trim();
  if (!cleaned || unsafePattern.test(cleaned) || styleNoisePattern.test(cleaned)) {
    return '';
  }
  if (/^-?\d+(?:\.\d+)?(?:::|$)/.test(cleaned) || /::/.test(cleaned)) return '';
  if (!/[a-zA-Z_]/.test(cleaned)) return '';
  return `artist:${cleaned}`;
}

function cleanArtistPrompt(chain) {
  const fromStructured = (chain.artists || []).map(artistToken).filter(Boolean);
  if (fromStructured.length) return unique(fromStructured).slice(0, 10).join(', ');

  return unique(
    splitTags(chain.prompt)
      .filter((tag) => !dirtyPromptPattern.test(tag))
      .map(inferredArtistToken)
      .filter(Boolean),
  )
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

const sourceQueue = readJson(sourceQueuePath);
const audit = readJson(auditPath);
const artistChains = readJson(artistChainsPath);
const characters = readJson(charactersPath);
const flaggedIds = new Set((audit.flagged || []).map((row) => row.id));
const dirtyIds = new Set(
  sourceQueue
    .filter((item) => dirtyPromptPattern.test(item.prompt || ''))
    .map((item) => item.id),
);
const repairSourceItems = sourceQueue.filter(
  (item) => flaggedIds.has(item.id) || dirtyIds.has(item.id),
);

const queue = [];
const replacements = [];
const removals = [];

for (const source of repairSourceItems) {
  const chain = artistChains.find((item) => item.id === source.artistChainId);
  const character = characters.find((item) => item.id === source.characterId);
  const size = sizes[source.sizeKey];
  const artistPrompt = chain ? cleanArtistPrompt(chain) : '';

  if (!chain || !character || !size || !artistPrompt) {
    removals.push({
      oldImageRef: source.imageRef,
      oldId: source.id,
      artistChainId: source.artistChainId,
      reason: !artistPrompt ? 'no_clean_artist_prompt' : 'missing_source_data',
    });
    continue;
  }

  const newId = slugify(
    `${source.artistChainId}-${source.characterId}-${source.sizeKey}-${suffix}`,
  );
  const newImageRef = `${previewDir}/${newId}.png`;
  queue.push({
    ...source,
    id: newId,
    imageRef: newImageRef,
    title: `${source.title} / repaired`,
    prompt: buildPrompt({
      artistPrompt,
      subjectTags: safeSubjectTags(character),
      size,
    }),
    negativePrompt,
    width: size.width,
    height: size.height,
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
  sourceQueuePath,
  auditPath,
  repairQueuePath,
  suffix,
  dirtyMatched: dirtyIds.size,
  flaggedMatched: flaggedIds.size,
  repairQueueCount: queue.length,
  replacementCount: replacements.length,
  removalCount: removals.length,
  replacements,
  removals,
});

console.log(
  JSON.stringify(
    {
      dirtyMatched: dirtyIds.size,
      flaggedMatched: flaggedIds.size,
      repairQueueCount: queue.length,
      removals: removals.length,
      repairQueuePath,
      repairPlanPath,
    },
    null,
    2,
  ),
);
