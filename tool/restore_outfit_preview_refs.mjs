import fs from 'node:fs';
import path from 'node:path';

const args = new Set(process.argv.slice(2));
const apply = args.has('--apply');
const workspaceRoot =
  'C:/Users/admin/AppData/Roaming/Novel Studio/Novel Studio/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const charactersPath = path.join(libraryRoot, 'characters.json');
const reportPath = path.join(libraryRoot, 'asset_outfit_preview_ref_restore_report.json');
const cachePath = path.join(libraryRoot, 'asset_catalog_cache.json');

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, ''));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function timestamp() {
  const now = new Date();
  const pad = (value) => String(value).padStart(2, '0');
  return `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(
    now.getDate(),
  )}-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
}

function outfitKey(character, outfit) {
  return `${character.id}\u0000${outfit.id}`;
}

function existsRef(ref) {
  const target = path.isAbsolute(ref) ? ref : path.join(workspaceRoot, ref);
  return fs.existsSync(target);
}

function isNovelAiCharacterPreviewRef(ref) {
  return ref.includes('/novelai-character-previews/') ||
    ref.includes('\\novelai-character-previews\\');
}

function isStrictCharacterPreviewRef(ref) {
  return ref.includes('/strict-character-previews/') ||
    ref.includes('\\strict-character-previews\\');
}

function refMatchesOutfit(ref, outfit) {
  return path.basename(ref).includes(outfit.id);
}

function collectHistoricalRefs() {
  const novelAiRefsByOutfit = new Map();
  const strictRefsByOutfit = new Map();
  const backupDirs = fs
    .readdirSync(libraryRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && entry.name.startsWith('backup-'))
    .map((entry) => entry.name)
    .sort();

  for (const backupDir of backupDirs) {
    const filePath = path.join(libraryRoot, backupDir, 'characters.json');
    if (!fs.existsSync(filePath)) continue;
    let characters;
    try {
      characters = readJson(filePath);
    } catch {
      continue;
    }
    for (const character of characters) {
      for (const outfit of character.outfits || []) {
        const key = outfitKey(character, outfit);
        for (const ref of outfit.imageRefs || []) {
          if (!existsRef(ref)) continue;
          if (!refMatchesOutfit(ref, outfit)) continue;
          if (isNovelAiCharacterPreviewRef(ref)) {
            const refs = novelAiRefsByOutfit.get(key) || [];
            if (!refs.includes(ref)) refs.push(ref);
            novelAiRefsByOutfit.set(key, refs);
          } else if (isStrictCharacterPreviewRef(ref)) {
            const refs = strictRefsByOutfit.get(key) || [];
            if (!refs.includes(ref)) refs.push(ref);
            strictRefsByOutfit.set(key, refs);
          }
        }
      }
    }
  }

  return { novelAiRefsByOutfit, strictRefsByOutfit };
}

function appendUnique(target, refs) {
  for (const ref of refs) {
    if (existsRef(ref) && !target.includes(ref)) target.push(ref);
  }
}

const characters = readJson(charactersPath);
const { novelAiRefsByOutfit, strictRefsByOutfit } = collectHistoricalRefs();
const changes = [];

for (const character of characters) {
  for (const outfit of character.outfits || []) {
    const currentRefs = outfit.imageRefs || [];
    if (currentRefs.length !== 1) continue;

    const key = outfitKey(character, outfit);
    const merged = [...currentRefs];
    appendUnique(merged, novelAiRefsByOutfit.get(key) || []);
    if (merged.length < 2) {
      appendUnique(merged, strictRefsByOutfit.get(key) || []);
    }
    if (merged.length <= currentRefs.length) continue;

    changes.push({
      characterId: character.id,
      characterName: character.name,
      outfitId: outfit.id,
      outfitName: outfit.name,
      before: currentRefs,
      after: merged,
      added: merged.filter((ref) => !currentRefs.includes(ref)),
    });
    outfit.imageRefs = merged;
  }
}

let backupDir = null;
let cacheBackupPath = null;
if (apply && changes.length > 0) {
  backupDir = path.join(libraryRoot, `backup-${timestamp()}-outfit-preview-ref-restore`);
  fs.mkdirSync(backupDir, { recursive: true });
  fs.copyFileSync(charactersPath, path.join(backupDir, 'characters.json'));
  if (fs.existsSync(cachePath)) {
    cacheBackupPath = path.join(backupDir, 'asset_catalog_cache.json');
    fs.renameSync(cachePath, cacheBackupPath);
  }
  writeJson(charactersPath, characters);
}

const report = {
  completedAt: new Date().toISOString(),
  mode: apply ? 'apply' : 'dry-run',
  workspaceRoot,
  backupDir,
  cacheBackupPath,
  changedOutfits: changes.length,
  changes,
};

if (apply) writeJson(reportPath, report);
console.log(JSON.stringify(report, null, 2));
