import fs from 'node:fs';
import path from 'node:path';

const workspaceRoot =
  'C:/Users/admin/AppData/Roaming/Novel Studio/Novel Studio/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const charactersPath = path.join(libraryRoot, 'characters.json');
const artistChainsPath = path.join(libraryRoot, 'artist_chains.json');
const queuePath = path.join(
  'C:/Users/admin/Downloads/NAI_NEW',
  'tool',
  'asset-library-artist-chain-character-preview-queue.json',
);
const reportPath = path.join(
  libraryRoot,
  'asset_artist_chain_character_preview_report.json',
);

const targetPreviewCount = 6;
const defaultQuality = 'best quality, amazing quality, very aesthetic, absurdres';
const unsafePattern =
  /\b(nsfw|nude|naked|explicit|sex|sexual|erotic|nipples?|pussy|penis|cum|spread legs|child|loli|shota|young)\b/i;
const brokenPattern =
  /\b(worst quality|low quality|bad quality|bad anatomy|bad hands|missing fingers?|extra fingers?|extra digits|fewer digits|mutation|deformed|disfigured|duplicate|watermark|signature|username|text|logo|censored|mosaic)\b/i;
const qualityPattern =
  /\b(masterpiece|best quality|amazing quality|very aesthetic|absurdres|highres|ultra detailed|official art)\b/i;

const actions = [
  'turning mid-step, hair and clothing flowing in the wind',
  'reaching one hand toward viewer, gentle foreshortening, lively expression',
  'light jump, floating fabric, energetic pose',
  'casting a small glowing magic effect, confident stance',
  'spinning pose, ribbons and skirt in motion',
  'walking forward with a bright gaze, dynamic camera angle',
];

const backgroundScenes = [
  'sunlit flower garden background, petals in the air, soft natural light',
  'night city street background, neon reflections, cinematic rim lighting',
  'cozy atelier background, art desk, warm window light, depth of field',
];

const plainScenes = [
  'simple white background, clean studio lighting, clear silhouette',
  'plain light gray background, no props, crisp character focus',
  'minimal pastel backdrop, uncluttered, reference sheet clarity',
];

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
  const backupDir = path.join(libraryRoot, `backup-${stamp}-character-previews`);
  fs.mkdirSync(backupDir, { recursive: true });
  fs.copyFileSync(filePath, path.join(backupDir, path.basename(filePath)));
  return backupDir;
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
    .replace(/^\d+(?:\.\d+)?::/, '')
    .replace(/::$/, '')
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

function artistToken(entry) {
  const name = String(entry?.name || '').trim().replace(/\s+/g, '_');
  if (!name || unsafePattern.test(name)) return '';
  const prefix = entry.prefix || 'artist:';
  const token = `${prefix}${name}`;
  const weight = Number(entry.weight || 1);
  if (Number.isFinite(weight) && weight !== 1) return `${weight}::${token}::`;
  return token;
}

function stylePrompt(chain) {
  const artistTags = (chain.artists || [])
    .map(artistToken)
    .filter(Boolean)
    .slice(0, 12);
  const styleTags = (chain.styleTags || [])
    .map(cleanTag)
    .filter(isSafeTag)
    .filter((tag) => !qualityPattern.test(tag))
    .slice(0, 10);
  const rawTags = splitTags(chain.prompt)
    .map(cleanTag)
    .filter(isSafeTag)
    .filter((tag) => !qualityPattern.test(tag))
    .filter((tag) => !/^year\s+\d{4}$/i.test(tag))
    .slice(0, 18);
  const tags = unique([...artistTags, ...styleTags, ...rawTags]);
  return tags.length ? tags.join(', ') : 'clean anime illustration style';
}

function subjectTags(subject) {
  const tags = splitTags(subject.tags)
    .map(cleanTag)
    .filter(isSafeTag)
    .filter((tag) => !qualityPattern.test(tag))
    .slice(0, 18);
  return unique(tags).join(', ');
}

function slugify(value) {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 120);
}

function buildSubjects(characters) {
  const subjects = [];
  for (const character of characters) {
    if (character.traits?.front_full) {
      subjects.push({
        id: character.id,
        type: 'character',
        name: character.name,
        tags: character.traits.front_full,
      });
    }
    for (const outfit of character.outfits || []) {
      if (!(outfit.imageRefs || []).length) continue;
      subjects.push({
        id: outfit.id,
        type: 'outfit',
        characterId: character.id,
        name: `${character.name} / ${outfit.name}`,
        tags: [character.traits?.front_full, outfit.tags?.front_full]
          .filter(Boolean)
          .join(', '),
      });
    }
  }
  return subjects.filter((subject) => subjectTags(subject));
}

function promptFor({ chain, subject, mode, variant }) {
  const scene =
    mode === 'background'
      ? backgroundScenes[variant % backgroundScenes.length]
      : plainScenes[variant % plainScenes.length];
  const shot =
    variant % 3 === 0
      ? 'full body solo portrait'
      : variant % 3 === 1
        ? 'cowboy shot solo portrait'
        : 'upper body solo portrait';
  return [
    defaultQuality,
    stylePrompt(chain),
    subjectTags(subject),
    'solo, single character, one person only',
    shot,
    actions[variant % actions.length],
    mode === 'background' ? 'illustration with background' : 'no detailed background',
    scene,
    'expressive eyes, appealing composition, clean readable pose',
    'safe, non-explicit, tasteful outfit',
    'no text, no watermark, no logo, no signature',
  ]
    .filter(Boolean)
    .join(', ');
}

const characters = readJson(charactersPath);
const artistChains = readJson(artistChainsPath);
const subjects = buildSubjects(characters);
if (!subjects.length) throw new Error('No usable character subjects found.');

const backupDir = backup(artistChainsPath);
const queue = [];
const reportRows = [];

for (let chainIndex = 0; chainIndex < artistChains.length; chainIndex++) {
  const chain = artistChains[chainIndex];
  const refs = [];
  const subjectRows = [];
  for (let index = 0; index < targetPreviewCount; index++) {
    const mode = index % 2 === 0 ? 'background' : 'plain';
    const subject = subjects[(chainIndex * targetPreviewCount + index * 7) % subjects.length];
    const rel = `assets/references/artist-character-previews/${slugify(
      `${chain.id}-${subject.id}-${mode}-${index + 1}`,
    )}.png`;
    refs.push(rel);
    subjectRows.push({
      preview: rel,
      subjectId: subject.id,
      subjectName: subject.name,
      mode,
    });
    queue.push({
      id: `${chain.id}-${subject.id}-${mode}-${index + 1}`,
      type: 'artist_chain_character_preview',
      artistChainId: chain.id,
      artistChainName: chain.name,
      subjectId: subject.id,
      subjectName: subject.name,
      mode,
      quality: defaultQuality,
      title: `${chain.name} / ${subject.name} / ${mode} ${index + 1}`,
      prompt: promptFor({ chain, subject, mode, variant: index }),
      outputPath: path.join(workspaceRoot, rel),
    });
  }
  const previousImageRefs = chain.imageRefs || [];
  chain.imageRefs = refs;
  reportRows.push({
    id: chain.id,
    name: chain.name,
    previousImageRefCount: previousImageRefs.length,
    previews: subjectRows,
  });
}

writeJson(artistChainsPath, artistChains);
writeJson(queuePath, queue);
writeJson(reportPath, {
  generatedAt: new Date().toISOString(),
  workspaceRoot,
  backupDir,
  targetPreviewCount,
  defaultQuality,
  subjectCount: subjects.length,
  queuePath,
  totalQueued: queue.length,
  chains: reportRows,
});

console.log(
  JSON.stringify(
    {
      artistChains: artistChains.length,
      subjects: subjects.length,
      targetPreviewCount,
      totalQueued: queue.length,
      queuePath,
      reportPath,
      backupDir,
    },
    null,
    2,
  ),
);
