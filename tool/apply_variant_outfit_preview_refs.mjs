import fs from 'node:fs';
import path from 'node:path';

const workspaceRoot =
  process.argv.find((arg) => arg.startsWith('--workspace='))?.slice(12) ||
  'C:/Users/admin/AppData/Roaming/org.exception0x0194/nai3_autodraw/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const charactersPath = path.join(libraryRoot, 'characters.json');
const planPath = resolvePath(
  libraryRoot,
  process.argv.find((arg) => arg.startsWith('--plan='))?.slice(7) ||
    'asset_variant_outfit_preview_plan.json',
);
const reportPath = resolvePath(
  libraryRoot,
  process.argv.find((arg) => arg.startsWith('--report='))?.slice(9) ||
    'asset_variant_outfit_preview_report.json',
);

function resolvePath(baseDir, value) {
  return path.isAbsolute(value) ? value : path.join(baseDir, value);
}

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
  const backupDir = path.join(libraryRoot, `backup-${stamp}-variant-outfit-previews`);
  fs.mkdirSync(backupDir, { recursive: true });
  fs.copyFileSync(filePath, path.join(backupDir, path.basename(filePath)));
  return backupDir;
}

function existsRef(ref) {
  const target = path.isAbsolute(ref) ? ref : path.join(workspaceRoot, ref);
  return fs.existsSync(target);
}

function appendRef(refs, ref) {
  const result = [ref, ...(refs || []).filter((item) => item !== ref)];
  return result.filter(Boolean);
}

function withoutGeneratedPreviewRefs(refs) {
  return (refs || []).filter(
    (ref) =>
      !String(ref).includes('assets/references/strict-character-previews/') &&
      !String(ref).includes('assets/references/novelai-character-previews/'),
  );
}

const characters = readJson(charactersPath);
const plan = readJson(planPath);
const refs = (plan.refs || []).filter((entry) => entry.type === 'outfit');

const missing = refs
  .filter((entry) => !existsRef(entry.imageRef))
  .map((entry) => ({
    characterId: entry.characterId,
    outfitId: entry.sourceId,
    imageRef: entry.imageRef,
  }));

if (missing.length) {
  throw new Error(`Variant outfit preview files are missing: ${JSON.stringify(missing.slice(0, 8))}`);
}

const backupDir = backup(charactersPath);
let outfitRefsApplied = 0;
const notFound = [];

for (const entry of refs) {
  const character = characters.find((candidate) => candidate.id === entry.characterId);
  const outfit = character?.outfits?.find((candidate) => candidate.id === entry.sourceId);
  if (!character || !outfit) {
    notFound.push({
      characterId: entry.characterId,
      outfitId: entry.sourceId,
    });
    continue;
  }
  outfit.imageRefs = appendRef(withoutGeneratedPreviewRefs(outfit.imageRefs), entry.imageRef);
  outfitRefsApplied += 1;
}

writeJson(charactersPath, characters);
writeJson(reportPath, {
  completedAt: new Date().toISOString(),
  workspaceRoot,
  backupDir,
  queuePath: plan.queuePath,
  outfitRefsApplied,
  notFound,
  skipped: plan.skipped || [],
});

console.log(
  JSON.stringify(
    {
      outfitRefsApplied,
      notFound: notFound.length,
      skipped: (plan.skipped || []).length,
      backupDir,
      reportPath,
    },
    null,
    2,
  ),
);
