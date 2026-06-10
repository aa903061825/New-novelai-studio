import fs from 'node:fs';
import path from 'node:path';

const repoRoot = 'C:/Users/admin/Downloads/NAI_NEW';
const workspaceRoot =
  'C:/Users/admin/AppData/Roaming/org.exception0x0194/nai3_autodraw/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const charactersPath = path.join(libraryRoot, 'characters.json');
const artistChainsPath = path.join(libraryRoot, 'artist_chains.json');
const characterQueuePath = path.join(repoRoot, 'tool', 'asset-library-strict-character-queue.json');
const artistQueuePath = path.join(
  repoRoot,
  'tool',
  'asset-library-strict-artist-preview-queue.json',
);
const planPath = path.join(libraryRoot, 'asset_strict_single_preview_plan.json');

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
const generationDefaults = {
  negativePrompt,
  model: 'nai-diffusion-4-5-full',
  action: 'generate',
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
};
const strictCharacterSize = {
  width: 832,
  height: 1216,
};
const strictArtistSizes = {
  background: {
    width: 1216,
    height: 832,
  },
  plain: {
    width: 1024,
    height: 1024,
  },
};
const roleArtistChain =
  '[artist:chen_bin], [artist:sho_(sho_lwlw)], [artist:ningen_mame], [artist:tianliang_duohe_fangdongye], [[artist:ciloranko]], [[artist:rella]], [[artist:konya_karasue]]';

const unsafePattern =
  /\b(nsfw|nude|naked|explicit|sex|sexual|erotic|nipples?|pussy|penis|cum|spread legs|child|loli|shota|young|gore|corpse|blood)\b/i;
const brokenPattern =
  /\b(worst quality|low quality|bad quality|bad anatomy|bad hands|missing fingers?|extra fingers?|extra digits|fewer digits|mutation|deformed|disfigured|duplicate|watermark|signature|username|text|logo|uncensored|censored|mosaic|multiple views|reference sheet|character sheet|collage|comic|panel|chibi|mascot)\b/i;
const qualityPattern =
  /\b(masterpiece|best quality|amazing quality|very aesthetic|absurdres|highres|ultra detailed|official art|great quality|sd)\b/i;
const genericTagPattern =
  /^(girl|1girl|solo|animal_ears|animal ears|long_hair|long hair|short_hair|white_hair|black_hair|brown_hair|blonde_hair|looking_at_viewer|smile)$/i;
const yearPattern = /^year\s+\d{4}$/i;

const actions = [
  'standing pose, one hand raised slightly',
  'walking forward, hair and clothes gently flowing',
  'turning mid-step, soft dynamic motion',
  'reaching one hand forward, gentle foreshortening',
  'holding a small glowing magic effect, confident stance',
  'light step pose, ribbons and skirt in motion',
];

const plainScenes = [
  'simple white background, clean studio lighting',
  'plain light gray background, no props',
  'minimal pale background, uncluttered',
];

const backgroundScenes = [
  'sunlit flower garden background, petals in the air',
  'soft city street background, warm rim lighting',
  'cozy atelier background, warm window light',
];

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
    .map((line) => line.trim())
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
    .replace(/^:+\s*/, '')
    .replace(/\\+/g, '')
    .trim();
}

function isSafeTag(tag) {
  if (!tag) return false;
  return !unsafePattern.test(tag) && !brokenPattern.test(tag) && !yearPattern.test(tag);
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
    ...knownTags(character.traits?.front_full),
  ]);
  return candidates.find((tag) => /[_()]|\(.*\)/.test(tag)) || candidates[0] || '';
}

function subjectForCharacter(character) {
  const main = bestCharacterTag(character);
  const traits = knownTags(character.traits?.front_full)
    .filter((tag) => tag !== main)
    .slice(0, 3);
  return unique([main, ...traits]).join(', ');
}

function subjectForOutfit(character, outfit) {
  const main = bestCharacterTag(character);
  const outfitTags = knownTags(outfit.tags?.front_full);
  const outfitIdentity =
    outfitTags.find((tag) => /[_()]|\(.*\)/.test(tag) && tag !== main) || '';
  const clothing = outfitTags
    .filter((tag) => tag !== outfitIdentity && tag !== main)
    .filter((tag) => !/girl|ears|tail|hair/i.test(tag))
    .slice(0, 5);
  return unique([outfitIdentity || main, ...clothing]).join(', ');
}

function buildSubjects(characters) {
  const subjects = [];
  for (const character of characters) {
    const prompt = subjectForCharacter(character);
    if (prompt) {
      subjects.push({
        id: character.id,
        type: 'character',
        name: character.name,
        prompt,
      });
    }
    for (const outfit of character.outfits || []) {
      if (!(outfit.imageRefs || []).length) continue;
      const outfitPrompt = subjectForOutfit(character, outfit);
      if (!outfitPrompt) continue;
      subjects.push({
        id: outfit.id,
        characterId: character.id,
        type: 'outfit',
        name: `${character.name} / ${outfit.name}`,
        prompt: outfitPrompt,
      });
    }
  }
  return subjects;
}

function artistToken(entry) {
  const rawName = String(entry?.name || '').trim();
  if (!rawName || unsafePattern.test(rawName) || brokenPattern.test(rawName)) return '';
  const name = rawName.replace(/\s+/g, '_');
  const prefix = entry.prefix || 'artist:';
  const token = `${prefix}${name}`;
  const weight = Number(entry.weight || 1);
  if (Number.isFinite(weight) && weight > 0 && weight !== 1) {
    return `${weight}::${token}::`;
  }
  return token;
}

function safeChainPrompt(chain) {
  return splitTags(chain.prompt)
    .map((tag) =>
      tag
        .replace(/\s+/g, ' ')
        .trim()
        .replace(/^:+\s*/, ''),
    )
    .filter(isSafeTag)
    .join(', ');
}

function looseArtistTags(chain) {
  return splitTags(chain.prompt)
    .map(cleanTag)
    .filter(isSafeTag)
    .filter((tag) => !qualityPattern.test(tag))
    .map((tag) => {
      const artistMatch = tag.match(/artist\s*:\s*([^:,\]}]+)/i);
      if (artistMatch) return `artist:${artistMatch[1].trim().replace(/\s+/g, '_')}`;
      return '';
    })
    .filter(Boolean);
}

function styleForChain(chain) {
  const artists = (chain.artists || []).map(artistToken).filter(Boolean);
  const loose = artists.length ? [] : looseArtistTags(chain);
  const styles = (chain.styleTags || [])
    .map(cleanTag)
    .filter(isSafeTag)
    .filter((tag) => !qualityPattern.test(tag))
    .filter((tag) => !genericTagPattern.test(tag))
    .slice(0, 5);
  return unique([...artists, ...loose, ...styles]).slice(0, 10).join(', ');
}

function strictPrompt({ style, subject, mode, variant, useBackground }) {
  const action = actions[variant % actions.length];
  const scene = useBackground
    ? backgroundScenes[variant % backgroundScenes.length]
    : plainScenes[variant % plainScenes.length];
  return [
    style,
    subject,
    defaultQuality,
    'girl',
    '1girl',
    'solo',
    'single character',
    'one person only',
    'full body',
    'feet visible',
    'centered composition',
    action,
    useBackground ? 'illustration with background' : 'no detailed background',
    scene,
    'clean readable pose',
    'appealing character portrait',
    'safe, non-explicit, tasteful outfit',
    'no text',
    'no watermark',
  ]
    .filter(Boolean)
    .join(', ');
}

const characters = readJson(charactersPath);
const artistChains = readJson(artistChainsPath);
const subjects = buildSubjects(characters);
if (!subjects.length) throw new Error('No usable subjects.');

const characterQueue = subjects.map((subject, index) => {
  const rel = `assets/references/strict-character-previews/${slugify(
    `${subject.id}-strict-single`,
  )}.png`;
  return {
    id: `${subject.id}-strict-single`,
    type: subject.type,
    sourceId: subject.id,
    ...(subject.characterId ? { characterId: subject.characterId } : {}),
    subjectName: subject.name,
    mode: 'plain',
    imageRef: rel,
    quality: defaultQuality,
    title: `${subject.name} / strict single`,
    prompt: strictPrompt({
      style: roleArtistChain,
      subject: subject.prompt,
      mode: 'plain',
      variant: index,
      useBackground: false,
      }),
      ...generationDefaults,
      ...strictCharacterSize,
      outputPath: path.join(workspaceRoot, rel),
    };
});

const artistQueue = [];
for (let chainIndex = 0; chainIndex < artistChains.length; chainIndex++) {
  const chain = artistChains[chainIndex];
  const style = safeChainPrompt(chain) || styleForChain(chain) || roleArtistChain;
  for (let index = 0; index < 6; index++) {
    const subject = subjects[(chainIndex * 6 + index * 5) % subjects.length];
    const useBackground = index % 2 === 0;
    const mode = useBackground ? 'background' : 'plain';
    const rel = `assets/references/strict-artist-chain-previews/${slugify(
      `${chain.id}-${subject.id}-${useBackground ? 'bg' : 'plain'}-${index + 1}`,
    )}.png`;
    artistQueue.push({
      id: `${chain.id}-${subject.id}-${useBackground ? 'bg' : 'plain'}-${index + 1}`,
      type: 'artist_chain_preview',
      artistChainId: chain.id,
      artistChainName: chain.name,
      subjectId: subject.id,
      subjectName: subject.name,
      mode,
      imageRef: rel,
      quality: defaultQuality,
      title: `${chain.name} / ${subject.name} / strict ${index + 1}`,
      prompt: strictPrompt({
        style,
        subject: subject.prompt,
        mode: useBackground ? 'background' : 'plain',
        variant: index,
        useBackground,
      }),
      ...generationDefaults,
      ...strictArtistSizes[mode],
      outputPath: path.join(workspaceRoot, rel),
    });
  }
}

writeJson(characterQueuePath, characterQueue);
writeJson(artistQueuePath, artistQueue);
writeJson(planPath, {
  generatedAt: new Date().toISOString(),
  workspaceRoot,
  defaultQuality,
  negativePrompt,
  generationDefaults,
  strictCharacterSize,
  strictArtistSizes,
  roleArtistChain,
  characterQueuePath,
  artistQueuePath,
  characterQueue: characterQueue.length,
  artistQueue: artistQueue.length,
  subjects: subjects.length,
  characterRefs: characterQueue.map((item) => ({
    sourceId: item.sourceId,
    type: item.type,
    characterId: item.characterId,
    imageRef: item.imageRef,
  })),
  artistRefs: artistChains.map((chain) => ({
    artistChainId: chain.id,
    imageRefs: artistQueue
      .filter((item) => item.artistChainId === chain.id)
      .map((item) => item.imageRef),
  })),
});

console.log(
  JSON.stringify(
    {
      subjects: subjects.length,
      artistChains: artistChains.length,
      characterQueue: characterQueue.length,
      artistQueue: artistQueue.length,
      characterQueuePath,
      artistQueuePath,
      planPath,
    },
    null,
    2,
  ),
);
