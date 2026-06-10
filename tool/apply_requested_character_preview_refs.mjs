import fs from 'node:fs';
import path from 'node:path';

const workspaceRoot =
  'C:/Users/admin/AppData/Roaming/org.exception0x0194/nai3_autodraw/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const charactersPath = path.join(libraryRoot, 'characters.json');
const planPath = path.join(
  libraryRoot,
  'asset_requested_character_preview_plan.json',
);
const reportPath = path.join(
  libraryRoot,
  'asset_requested_character_preview_report.json',
);

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
  const backupDir = path.join(libraryRoot, `backup-${stamp}-requested-character-previews`);
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

const missing = plan.refs
  .filter((entry) => !existsRef(entry.imageRef))
  .map((entry) => ({
    type: entry.type,
    sourceId: entry.sourceId,
    imageRef: entry.imageRef,
  }));

if (missing.length) {
  throw new Error(`Requested preview files are missing: ${JSON.stringify(missing.slice(0, 8))}`);
}

const backupDir = backup(charactersPath);
const refsBySourceId = new Map(plan.refs.map((entry) => [entry.sourceId, entry]));
let characterRefsApplied = 0;
let outfitRefsApplied = 0;

for (const character of characters) {
  character.imageRefs = withoutGeneratedPreviewRefs(character.imageRefs);
  const characterRef = refsBySourceId.get(character.id);
  if (characterRef) {
    character.imageRefs = appendRef(character.imageRefs, characterRef.imageRef);
    characterRefsApplied++;
  }
  for (const outfit of character.outfits || []) {
    outfit.imageRefs = withoutGeneratedPreviewRefs(outfit.imageRefs);
    const outfitRef = refsBySourceId.get(outfit.id);
    if (outfitRef) {
      outfit.imageRefs = appendRef(outfit.imageRefs, outfitRef.imageRef);
      outfitRefsApplied++;
    }
  }
}

writeJson(charactersPath, characters);
writeJson(reportPath, {
  completedAt: new Date().toISOString(),
  workspaceRoot,
  backupDir,
  queuePath: plan.queuePath,
  artistChain: plan.artistChain,
  characterRefsApplied,
  outfitRefsApplied,
  skipped: plan.skipped || [],
});

console.log(
  JSON.stringify(
    {
      characterRefsApplied,
      outfitRefsApplied,
      skipped: (plan.skipped || []).length,
      backupDir,
      reportPath,
    },
    null,
    2,
  ),
);
