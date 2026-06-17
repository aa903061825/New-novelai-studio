import fs from 'node:fs';
import path from 'node:path';

const workspaceRoot =
  'C:/Users/admin/AppData/Roaming/Novel Studio/Novel Studio/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const charactersPath = path.join(libraryRoot, 'characters.json');
const artistChainsPath = path.join(libraryRoot, 'artist_chains.json');
const planPath = path.join(libraryRoot, 'asset_strict_single_preview_plan.json');
const reportPath = path.join(libraryRoot, 'asset_strict_single_preview_report.json');

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, ''));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function backup(filePath, suffix) {
  const now = new Date();
  const pad = (value) => String(value).padStart(2, '0');
  const stamp = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(
    now.getDate(),
  )}-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  const backupDir = path.join(libraryRoot, `backup-${stamp}-${suffix}`);
  fs.mkdirSync(backupDir, { recursive: true });
  fs.copyFileSync(filePath, path.join(backupDir, path.basename(filePath)));
  return backupDir;
}

function existsRef(ref) {
  const target = path.isAbsolute(ref) ? ref : path.join(workspaceRoot, ref);
  return fs.existsSync(target);
}

function mergeRefs(existingRefs, nextRefs) {
  const merged = [];
  for (const ref of [...(existingRefs || []), ...nextRefs]) {
    if (!merged.includes(ref)) merged.push(ref);
  }
  return merged;
}

const characters = readJson(charactersPath);
const artistChains = readJson(artistChainsPath);
const plan = readJson(planPath);

const missing = [
  ...plan.characterRefs.flatMap((item) =>
    existsRef(item.imageRef) ? [] : [{ type: 'character', id: item.sourceId, ref: item.imageRef }],
  ),
  ...plan.artistRefs.flatMap((entry) =>
    entry.imageRefs
      .filter((ref) => !existsRef(ref))
      .map((ref) => ({ type: 'artist_chain', id: entry.artistChainId, ref })),
  ),
];

if (missing.length) {
  throw new Error(`Strict preview files are missing: ${JSON.stringify(missing.slice(0, 8))}`);
}

const characterBackupDir = backup(charactersPath, 'strict-single-previews');
const artistBackupDir = backup(artistChainsPath, 'strict-single-previews');

const charRefById = new Map(plan.characterRefs.map((entry) => [entry.sourceId, entry.imageRef]));
for (const character of characters) {
  const characterRef = charRefById.get(character.id);
  if (characterRef) {
    character.imageRefs = mergeRefs(character.imageRefs, [characterRef]);
  }
  for (const outfit of character.outfits || []) {
    const outfitRef = charRefById.get(outfit.id);
    if (outfitRef) {
      outfit.imageRefs = mergeRefs(outfit.imageRefs, [outfitRef]);
    }
  }
}

const artistRefById = new Map(
  plan.artistRefs.map((entry) => [entry.artistChainId, entry.imageRefs]),
);
for (const chain of artistChains) {
  const refs = artistRefById.get(chain.id);
  if (refs?.length) {
    chain.imageRefs = refs;
  }
}

writeJson(charactersPath, characters);
writeJson(artistChainsPath, artistChains);
writeJson(reportPath, {
  completedAt: new Date().toISOString(),
  workspaceRoot,
  defaultQuality: plan.defaultQuality,
  roleArtistChain: plan.roleArtistChain,
  characterBackupDir,
  artistBackupDir,
  characterRefsApplied: plan.characterRefs.length,
  artistChainsApplied: plan.artistRefs.length,
  artistPreviewRefsApplied: plan.artistRefs.reduce(
    (sum, entry) => sum + entry.imageRefs.length,
    0,
  ),
});

console.log(
  JSON.stringify(
    {
      characterRefsApplied: plan.characterRefs.length,
      artistChainsApplied: plan.artistRefs.length,
      artistPreviewRefsApplied: plan.artistRefs.reduce(
        (sum, entry) => sum + entry.imageRefs.length,
        0,
      ),
      reportPath,
    },
    null,
    2,
  ),
);
