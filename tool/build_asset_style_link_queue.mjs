import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const workspaceRoot =
  'C:/Users/admin/AppData/Roaming/org.exception0x0194/nai3_autodraw/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const charactersPath = path.join(libraryRoot, 'characters.json');
const artistChainsPath = path.join(libraryRoot, 'artist_chains.json');
const queuePath = path.join(repoRoot, 'tool', 'asset-library-styled-image-queue.json');
const reportPath = path.join(libraryRoot, 'asset_style_link_report.json');

const unsafePattern =
  /\b(nsfw|nude|naked|explicit|sex|nipples?|pussy|penis|cum|spread legs)\b/i;

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, ''));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function backup(filePath, stamp) {
  const backupDir = path.join(libraryRoot, `backup-${stamp}-style-link`);
  fs.mkdirSync(backupDir, { recursive: true });
  fs.copyFileSync(filePath, path.join(backupDir, path.basename(filePath)));
}

function stamp() {
  const d = new Date();
  const pad = (value) => String(value).padStart(2, '0');
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(
    d.getHours(),
  )}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
}

function slugify(value) {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 96);
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

function prependRef(refs, ref) {
  return unique([ref, ...(refs || [])]);
}

function appendRef(refs, ref) {
  return unique([...(refs || []), ref]);
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
  const prompt = normalizeTagText(chain.prompt);
  return prompt
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

function makeRel(id) {
  return `assets/references/styled/${slugify(id)}.png`;
}

const characters = readJson(charactersPath);
const artistChains = readJson(artistChainsPath);
const usableChains = artistChains.filter(
  (chain) => safeStylePrompt(chain).length > 0 && /\bartist\s*:/i.test(chain.prompt || ''),
);

if (usableChains.length === 0) {
  throw new Error('No usable artist chains found.');
}

const now = stamp();
backup(charactersPath, now);
backup(artistChainsPath, now);

const chainById = new Map(artistChains.map((chain) => [chain.id, chain]));
const queue = [];
const links = [];
let cursor = 0;

function nextChain() {
  const chain = usableChains[cursor % usableChains.length];
  cursor += 1;
  return chain;
}

function addQueueItem({ id, type, title, subject, rel, characterId }) {
  const chain = nextChain();
  const style = safeStylePrompt(chain);
  const chainRef = chainById.get(chain.id);
  if (chainRef) {
    chainRef.imageRefs = appendRef(chainRef.imageRefs, rel);
  }
  queue.push({
    id: `${id}-styled`,
    sourceId: id,
    type,
    ...(characterId ? { characterId } : {}),
    artistChainId: chain.id,
    artistChainName: chain.name,
    title,
    prompt: styledPrompt({ kind: type, subject, style }),
    outputPath: path.join(workspaceRoot, rel),
  });
  links.push({
    sourceId: id,
    type,
    title,
    imageRef: rel,
    artistChainId: chain.id,
    artistChainName: chain.name,
  });
}

for (const character of characters) {
  const rel = makeRel(`${character.id}-styled`);
  character.imageRefs = prependRef(character.imageRefs, rel);
  addQueueItem({
    id: character.id,
    type: 'character',
    title: character.name,
    subject: subjectPrompt(character.traits?.front_full),
    rel,
  });

  for (const outfit of character.outfits || []) {
    if (!(outfit.imageRefs || []).length) continue;
    const outfitRel = makeRel(`${outfit.id}-styled`);
    outfit.imageRefs = prependRef(outfit.imageRefs, outfitRel);
    addQueueItem({
      id: outfit.id,
      type: 'outfit',
      characterId: character.id,
      title: `${character.name} / ${outfit.name}`,
      subject: subjectPrompt(character.traits?.front_full, outfit.tags?.front_full),
      rel: outfitRel,
    });
  }
}

writeJson(charactersPath, characters);
writeJson(artistChainsPath, artistChains);
writeJson(queuePath, queue);
writeJson(reportPath, {
  generatedAt: new Date().toISOString(),
  workspaceRoot,
  artistChains: usableChains.length,
  styledQueue: queue.length,
  queuePath,
  links,
});

console.log(
  JSON.stringify(
    {
      characters: characters.length,
      artistChains: artistChains.length,
      usableArtistChains: usableChains.length,
      styledQueue: queue.length,
      queuePath,
      reportPath,
    },
    null,
    2,
  ),
);
