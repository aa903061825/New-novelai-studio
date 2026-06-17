import fs from 'node:fs';
import path from 'node:path';

const repoRoot = 'C:/Users/admin/Downloads/NAI_NEW';
const workspaceRoot =
  'C:/Users/admin/AppData/Roaming/Novel Studio/Novel Studio/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const artistChainsPath = path.join(libraryRoot, 'artist_chains.json');
const activeQueuePath = path.join(
  repoRoot,
  'tool',
  'asset-library-artist-chain-varsize-active-queue.json',
);
const repairQueuePath = path.join(
  repoRoot,
  'tool',
  'asset-library-artist-chain-varsize-repair2-queue.json',
);
const repairPlanPath = path.join(
  libraryRoot,
  'asset_artist_chain_varsize_repair2_plan.json',
);
const reportPath = path.join(
  libraryRoot,
  'asset_artist_chain_varsize_repair2_report.json',
);
const asciiPreviewRoot = 'E:/codeximage/nai-new/preview-images';
const rejectedRoot = 'E:/codeximage/nai-new/rejected-preview-images/artist-chain-varsize';

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, ''));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function pad(value) {
  return String(value).padStart(2, '0');
}

function stamp() {
  const now = new Date();
  return `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(
    now.getHours(),
  )}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
}

function backup(filePath) {
  const backupDir = path.join(
    libraryRoot,
    `backup-${stamp()}-artist-chain-varsize-repair2`,
  );
  fs.mkdirSync(backupDir, { recursive: true });
  fs.copyFileSync(filePath, path.join(backupDir, path.basename(filePath)));
  return backupDir;
}

function refToWorkspacePath(ref) {
  return path.isAbsolute(ref) ? ref : path.join(workspaceRoot, ref);
}

function fileNameFromRef(ref) {
  return ref.replaceAll('\\', '/').split('/').pop();
}

function replaceRef(refs, oldRef, newRef) {
  const result = [];
  let changed = false;
  for (const ref of refs || []) {
    if (ref === oldRef) {
      changed = true;
      result.push(newRef);
    } else {
      result.push(ref);
    }
  }
  if (!changed) result.unshift(newRef);
  return [...new Set(result)];
}

function moveIfExists(sourcePath, targetDir) {
  if (!fs.existsSync(sourcePath)) return '';
  fs.mkdirSync(targetDir, { recursive: true });
  const targetPath = path.join(targetDir, path.basename(sourcePath));
  if (fs.existsSync(targetPath)) fs.unlinkSync(targetPath);
  fs.renameSync(sourcePath, targetPath);
  return targetPath;
}

const artistChains = readJson(artistChainsPath);
const activeQueue = readJson(activeQueuePath);
const repairQueue = readJson(repairQueuePath);
const repairPlan = readJson(repairPlanPath);

const missingRepairFiles = repairQueue.filter(
  (item) => !fs.existsSync(item.outputPath),
);
if (missingRepairFiles.length) {
  throw new Error(
    `Repair2 preview files are missing: ${JSON.stringify(
      missingRepairFiles.slice(0, 8).map((item) => item.outputPath),
    )}`,
  );
}

const backupDir = backup(artistChainsPath);
let replacementRefsApplied = 0;
for (const chain of artistChains) {
  for (const replacement of repairPlan.replacements) {
    if (chain.id !== replacement.artistChainId) continue;
    const before = JSON.stringify(chain.imageRefs || []);
    chain.imageRefs = replaceRef(
      chain.imageRefs,
      replacement.oldImageRef,
      replacement.newImageRef,
    );
    if (JSON.stringify(chain.imageRefs || []) !== before) replacementRefsApplied += 1;
  }
}

const replacementsByOld = new Map(
  repairPlan.replacements.map((entry) => [entry.oldImageRef, entry]),
);
const activeQueueNext = activeQueue.map((item) => {
  const replacement = replacementsByOld.get(item.imageRef);
  if (!replacement) return item;
  return repairQueue.find((entry) => entry.imageRef === replacement.newImageRef) || item;
});

const movedRejectedFiles = [];
for (const oldRef of replacementsByOld.keys()) {
  const workspaceMoved = moveIfExists(
    refToWorkspacePath(oldRef),
    path.join(workspaceRoot, 'assets/references/rejected-artist-chain-varsize'),
  );
  if (workspaceMoved) movedRejectedFiles.push(workspaceMoved);
  const asciiMoved = moveIfExists(
    path.join(asciiPreviewRoot, fileNameFromRef(oldRef)),
    rejectedRoot,
  );
  if (asciiMoved) movedRejectedFiles.push(asciiMoved);
}

writeJson(artistChainsPath, artistChains);
writeJson(activeQueuePath, activeQueueNext);
writeJson(reportPath, {
  completedAt: new Date().toISOString(),
  backupDir,
  activeQueuePath,
  repairQueuePath,
  replacementRefsApplied,
  activeQueueCount: activeQueueNext.length,
  movedRejectedFiles,
  replacements: repairPlan.replacements,
});

console.log(
  JSON.stringify(
    {
      replacementRefsApplied,
      activeQueueCount: activeQueueNext.length,
      movedRejectedFiles: movedRejectedFiles.length,
      backupDir,
      reportPath,
      activeQueuePath,
    },
    null,
    2,
  ),
);
