import fs from 'node:fs';
import path from 'node:path';

const repoRoot = 'C:/Users/admin/Downloads/NAI_NEW';
const workspaceRoot =
  'C:/Users/admin/AppData/Roaming/org.exception0x0194/nai3_autodraw/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const artistChainsPath = path.join(libraryRoot, 'artist_chains.json');
const sourceQueuePath = path.join(
  repoRoot,
  'tool',
  'asset-library-artist-chain-varsize-preview-queue.json',
);
const repairQueuePath = path.join(
  repoRoot,
  'tool',
  'asset-library-artist-chain-varsize-repair-queue.json',
);
const repairPlanPath = path.join(
  libraryRoot,
  'asset_artist_chain_varsize_repair_plan.json',
);
const activeQueuePath = path.join(
  repoRoot,
  'tool',
  'asset-library-artist-chain-varsize-active-queue.json',
);
const reportPath = path.join(
  libraryRoot,
  'asset_artist_chain_varsize_repair_report.json',
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
    `backup-${stamp()}-artist-chain-varsize-repair`,
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

function replaceOrRemoveRef(refs, oldRef, newRef) {
  const result = [];
  let changed = false;
  for (const ref of refs || []) {
    if (ref === oldRef) {
      changed = true;
      if (newRef) result.push(newRef);
    } else {
      result.push(ref);
    }
  }
  if (!changed && newRef) result.unshift(newRef);
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
const sourceQueue = readJson(sourceQueuePath);
const repairQueue = readJson(repairQueuePath);
const repairPlan = readJson(repairPlanPath);

const missingRepairFiles = repairQueue.filter(
  (item) => !fs.existsSync(item.outputPath),
);
if (missingRepairFiles.length) {
  throw new Error(
    `Repair preview files are missing: ${JSON.stringify(
      missingRepairFiles.slice(0, 8).map((item) => item.outputPath),
    )}`,
  );
}

const backupDir = backup(artistChainsPath);
const replacementsByOld = new Map(
  repairPlan.replacements.map((entry) => [entry.oldImageRef, entry]),
);
const removalsByOld = new Map(
  repairPlan.removals.map((entry) => [entry.oldImageRef, entry]),
);
const oldRefsToReject = new Set([
  ...replacementsByOld.keys(),
  ...removalsByOld.keys(),
]);

let replacementRefsApplied = 0;
let removalRefsApplied = 0;
for (const chain of artistChains) {
  for (const replacement of repairPlan.replacements) {
    if (chain.id !== replacement.artistChainId) continue;
    const before = JSON.stringify(chain.imageRefs || []);
    chain.imageRefs = replaceOrRemoveRef(
      chain.imageRefs,
      replacement.oldImageRef,
      replacement.newImageRef,
    );
    if (JSON.stringify(chain.imageRefs || []) !== before) replacementRefsApplied += 1;
  }
  for (const removal of repairPlan.removals) {
    if (chain.id !== removal.artistChainId) continue;
    const beforeLength = (chain.imageRefs || []).length;
    chain.imageRefs = replaceOrRemoveRef(chain.imageRefs, removal.oldImageRef, '');
    if ((chain.imageRefs || []).length !== beforeLength) removalRefsApplied += 1;
  }
}

const movedRejectedFiles = [];
for (const oldRef of oldRefsToReject) {
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

const activeQueue = sourceQueue
  .filter((item) => !removalsByOld.has(item.imageRef))
  .map((item) => {
    const replacement = replacementsByOld.get(item.imageRef);
    if (!replacement) return item;
    const repair = repairQueue.find((entry) => entry.imageRef === replacement.newImageRef);
    return repair || item;
  });

writeJson(artistChainsPath, artistChains);
writeJson(activeQueuePath, activeQueue);
writeJson(reportPath, {
  completedAt: new Date().toISOString(),
  backupDir,
  sourceQueuePath,
  repairQueuePath,
  activeQueuePath,
  replacementRefsApplied,
  removalRefsApplied,
  movedRejectedFiles,
  replacements: repairPlan.replacements,
  removals: repairPlan.removals,
});

console.log(
  JSON.stringify(
    {
      replacementRefsApplied,
      removalRefsApplied,
      activeQueueCount: activeQueue.length,
      movedRejectedFiles: movedRejectedFiles.length,
      backupDir,
      reportPath,
      activeQueuePath,
    },
    null,
    2,
  ),
);
