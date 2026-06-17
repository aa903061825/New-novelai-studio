import fs from 'node:fs';
import path from 'node:path';

const workspaceRoot =
  'C:/Users/admin/AppData/Roaming/Novel Studio/Novel Studio/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const charactersPath = path.join(libraryRoot, 'characters.json');
const artistChainsPath = path.join(libraryRoot, 'artist_chains.json');
const reportPath = path.join(libraryRoot, 'asset_style_link_report.json');
const styledQueuePath = path.join(
  'C:/Users/admin/Downloads/NAI_NEW',
  'tool',
  'asset-library-styled-image-queue.json',
);
const supplementQueuePath = path.join(
  'C:/Users/admin/Downloads/NAI_NEW',
  'tool',
  'asset-library-style-only-supplement-queue.json',
);

const unsafePattern =
  /\b(nsfw|nude|naked|explicit|sex|nipples?|pussy|penis|cum|spread legs)\b/i;

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, ''));
}

function writeJson(filePath, value) {
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

function safeStylePrompt(chain) {
  return normalizeTagText(chain.prompt)
    .split(',')
    .map((part) => part.trim())
    .filter((part) => part && !unsafePattern.test(part))
    .join(', ');
}

function subjectPrompt(base, extra = '') {
  return [normalizeTagText(base), normalizeTagText(extra)]
    .filter(Boolean)
    .join(', ');
}

function styledPrompt({ kind, subject, style }) {
  return [
    'masterpiece, best quality, anime illustration',
    style,
    subject,
    kind === 'outfit'
      ? 'outfit reference, full body, front view'
      : 'character reference, full body, front view',
    'single character, clean standing pose, clear silhouette',
    'plain light background, no text, no watermark',
    'safe, non-explicit, modest outfit',
  ]
    .filter(Boolean)
    .join(', ');
}

function unique(values) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    if (!value || typeof value !== 'string') continue;
    const key = value.replaceAll('\\', '/').toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(value);
  }
  return result;
}

function appendRef(refs, ref) {
  return unique([...(refs || []), ref]);
}

function slugify(value) {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 120);
}

function findSource(characters, item) {
  if (item.type === 'character') {
    const character = characters.find((entry) => entry.id === item.sourceId);
    return {
      character,
      subject: subjectPrompt(character?.traits?.front_full),
      attach(ref) {
        character.imageRefs = appendRef(character.imageRefs, ref);
      },
    };
  }
  const character = characters.find((entry) => entry.id === item.characterId);
  const outfit = character?.outfits?.find((entry) => entry.id === item.sourceId);
  return {
    character,
    outfit,
    subject: subjectPrompt(character?.traits?.front_full, outfit?.tags?.front_full),
    attach(ref) {
      outfit.imageRefs = appendRef(outfit.imageRefs, ref);
    },
  };
}

const characters = readJson(charactersPath);
const artistChains = readJson(artistChainsPath);
const styledQueue = readJson(styledQueuePath);
const report = readJson(reportPath);
const repairedItems = report.repairedExplicitArtistPromptItems || [];
const fallbackItems = styledQueue.filter((item) => repairedItems.includes(item.id));

const missingChains = artistChains.filter(
  (chain) =>
    safeStylePrompt(chain).length > 0 &&
    !(chain.imageRefs || []).some((ref) => String(ref).includes('/styled/')),
);

const queue = [];
for (let index = 0; index < missingChains.length; index++) {
  const chain = missingChains[index];
  const baseItem = fallbackItems[index % fallbackItems.length] || styledQueue[index];
  const source = findSource(characters, baseItem);
  if (!source?.subject) continue;
  const rel = `assets/references/styled/${slugify(
    `${baseItem.sourceId}-${chain.id}-supplement`,
  )}.png`;
  source.attach(rel);
  chain.imageRefs = appendRef(chain.imageRefs, rel);
  const item = {
    id: `${baseItem.sourceId}-${chain.id}-supplement`,
    sourceId: baseItem.sourceId,
    type: baseItem.type,
    ...(baseItem.characterId ? { characterId: baseItem.characterId } : {}),
    artistChainId: chain.id,
    artistChainName: chain.name,
    title: `${baseItem.title} / ${chain.name}`,
    prompt: styledPrompt({
      kind: baseItem.type,
      subject: source.subject,
      style: safeStylePrompt(chain),
    }),
    outputPath: path.join(workspaceRoot, rel),
  };
  queue.push(item);
  report.links = [
    ...(report.links || []),
    {
      sourceId: baseItem.sourceId,
      type: baseItem.type,
      title: item.title,
      imageRef: rel,
      artistChainId: chain.id,
      artistChainName: chain.name,
      supplement: true,
    },
  ];
}

writeJson(charactersPath, characters);
writeJson(artistChainsPath, artistChains);
writeJson(supplementQueuePath, queue);
writeJson(reportPath, {
  ...report,
  supplementedAt: new Date().toISOString(),
  styleOnlySupplementQueue: queue.length,
});

console.log(
  JSON.stringify(
    {
      missingChains: missingChains.length,
      supplementQueue: queue.length,
      supplementQueuePath,
    },
    null,
    2,
  ),
);
