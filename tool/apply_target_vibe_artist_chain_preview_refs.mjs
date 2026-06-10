import fs from 'node:fs';
import path from 'node:path';

const workspaceRoot =
  'C:/Users/admin/AppData/Roaming/org.exception0x0194/nai3_autodraw/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const artistChainsPath = path.join(libraryRoot, 'artist_chains.json');
const planPath = path.join(
  libraryRoot,
  'asset_target_vibe_artist_chain_preview_plan.json',
);
const reportPath = path.join(
  libraryRoot,
  'asset_target_vibe_artist_chain_preview_report.json',
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
  const backupDir = path.join(
    libraryRoot,
    `backup-${stamp}-target-vibe-artist-chain-previews`,
  );
  fs.mkdirSync(backupDir, { recursive: true });
  fs.copyFileSync(filePath, path.join(backupDir, path.basename(filePath)));
  return backupDir;
}

function existsRef(ref) {
  const target = path.isAbsolute(ref) ? ref : path.join(workspaceRoot, ref);
  return fs.existsSync(target);
}

const artistChains = readJson(artistChainsPath);
const plan = readJson(planPath);
const missing = [];
for (const target of plan.targets || []) {
  for (const imageRef of target.newImageRefs || []) {
    if (!existsRef(imageRef)) {
      missing.push({ artistChainId: target.artistChainId, imageRef });
    }
  }
}

if (missing.length) {
  throw new Error(
    `Target vibe preview files are missing: ${JSON.stringify(
      missing.slice(0, 8),
    )}`,
  );
}

const backupDir = backup(artistChainsPath);
let artistChainsApplied = 0;
let imageRefsApplied = 0;
const refsByChain = new Map(
  (plan.targets || []).map((target) => [
    target.artistChainId,
    target.newImageRefs || [],
  ]),
);

for (const chain of artistChains) {
  const refs = refsByChain.get(chain.id);
  if (!refs?.length) continue;
  chain.imageRefs = refs;
  artistChainsApplied += 1;
  imageRefsApplied += refs.length;
}

writeJson(artistChainsPath, artistChains);
writeJson(reportPath, {
  completedAt: new Date().toISOString(),
  workspaceRoot,
  queuePath: plan.queuePath,
  backupDir,
  artistChainsApplied,
  imageRefsApplied,
  targets: plan.targets || [],
});

console.log(
  JSON.stringify(
    {
      artistChainsApplied,
      imageRefsApplied,
      backupDir,
      reportPath,
    },
    null,
    2,
  ),
);
