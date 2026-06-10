import fs from 'node:fs';
import path from 'node:path';

const workspaceRoot =
  'C:/Users/admin/AppData/Roaming/org.exception0x0194/nai3_autodraw/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const charactersPath = path.join(libraryRoot, 'characters.json');
const artistChainsPath = path.join(libraryRoot, 'artist_chains.json');
const reportPath = path.join(libraryRoot, 'asset_style_link_report.json');
const queuePath = path.join(
  'C:/Users/admin/Downloads/NAI_NEW',
  'tool',
  'asset-library-styled-image-queue.json',
);
const previewRoot = 'E:/codeximage/nai-new/preview-images';

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

function removeRef(refs, ref) {
  const key = ref.replaceAll('\\', '/').toLowerCase();
  return (refs || []).filter((value) => value.replaceAll('\\', '/').toLowerCase() !== key);
}

function appendRef(refs, ref) {
  return unique([...(refs || []), ref]);
}

function findSubject(characters, item) {
  if (item.type === 'character') {
    const character = characters.find((entry) => entry.id === item.sourceId);
    return subjectPrompt(character?.traits?.front_full);
  }
  const character = characters.find((entry) => entry.id === item.characterId);
  const outfit = character?.outfits?.find((entry) => entry.id === item.sourceId);
  return subjectPrompt(character?.traits?.front_full, outfit?.tags?.front_full);
}

function previewPathFor(outputPath) {
  const normalized = outputPath.replaceAll('\\', '/');
  return path.join(previewRoot, normalized.slice(normalized.lastIndexOf('/') + 1));
}

const characters = readJson(charactersPath);
const artistChains = readJson(artistChainsPath);
const queue = readJson(queuePath);
const report = readJson(reportPath);
const chainById = new Map(artistChains.map((chain) => [chain.id, chain]));
const explicitChains = artistChains.filter(
  (chain) => /\bartist\s*:/i.test(chain.prompt || '') && safeStylePrompt(chain).length > 0,
);

if (explicitChains.length === 0) {
  throw new Error('No explicit artist chains found.');
}

function styledCount(chain) {
  return (chain.imageRefs || []).filter((ref) => ref.includes('/styled/')).length;
}

function pickReplacement(currentId) {
  return [...explicitChains]
    .filter((chain) => chain.id !== currentId)
    .sort((a, b) => styledCount(a) - styledCount(b) || a.id.localeCompare(b.id))[0];
}

const repaired = [];
for (const item of queue) {
  if (/\bartist\s*:/i.test(item.prompt || '')) continue;
  const replacement = pickReplacement(item.artistChainId);
  const oldChain = chainById.get(item.artistChainId);
  if (oldChain) oldChain.imageRefs = removeRef(oldChain.imageRefs, item.outputPath);
  if (oldChain) {
    const relative = item.outputPath
      .replaceAll('\\', '/')
      .replace(workspaceRoot.replaceAll('\\', '/'), '')
      .replace(/^\//, '');
    oldChain.imageRefs = removeRef(oldChain.imageRefs, relative);
  }
  const relative = item.outputPath
    .replaceAll('\\', '/')
    .replace(workspaceRoot.replaceAll('\\', '/'), '')
    .replace(/^\//, '');
  replacement.imageRefs = appendRef(replacement.imageRefs, relative);
  item.artistChainId = replacement.id;
  item.artistChainName = replacement.name;
  item.prompt = styledPrompt({
    kind: item.type,
    subject: findSubject(characters, item),
    style: safeStylePrompt(replacement),
  });
  for (const link of report.links || []) {
    if (link.sourceId === item.sourceId && link.imageRef === relative) {
      link.artistChainId = replacement.id;
      link.artistChainName = replacement.name;
    }
  }
  if (fs.existsSync(item.outputPath)) fs.unlinkSync(item.outputPath);
  const preview = previewPathFor(item.outputPath);
  if (fs.existsSync(preview)) fs.unlinkSync(preview);
  repaired.push(item.id);
}

writeJson(artistChainsPath, artistChains);
writeJson(queuePath, queue);
writeJson(reportPath, {
  ...report,
  repairedAt: new Date().toISOString(),
  repairedExplicitArtistPromptItems: repaired,
});

console.log(JSON.stringify({ repaired: repaired.length, items: repaired }, null, 2));
