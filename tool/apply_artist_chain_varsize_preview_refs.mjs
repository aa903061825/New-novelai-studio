import fs from 'node:fs';
import path from 'node:path';

const workspaceRoot =
  'C:/Users/admin/AppData/Roaming/Novel Studio/Novel Studio/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const artistChainsPath = path.join(libraryRoot, 'artist_chains.json');
const planPath = path.join(
  libraryRoot,
  'asset_artist_chain_varsize_preview_plan.json',
);
const reportPath = path.join(
  libraryRoot,
  'asset_artist_chain_varsize_preview_report.json',
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
    `backup-${stamp}-artist-chain-varsize-previews`,
  );
  fs.mkdirSync(backupDir, { recursive: true });
  fs.copyFileSync(filePath, path.join(backupDir, path.basename(filePath)));
  return backupDir;
}

function existsRef(ref) {
  const target = path.isAbsolute(ref) ? ref : path.join(workspaceRoot, ref);
  return fs.existsSync(target);
}

function prependRefs(refs, newRefs) {
  const result = [];
  const seen = new Set();
  for (const ref of [...newRefs, ...(refs || [])]) {
    if (!ref || typeof ref !== 'string') continue;
    const key = ref.replaceAll('\\', '/').toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(ref);
  }
  return result;
}

const artistChains = readJson(artistChainsPath);
const plan = readJson(planPath);
const missing = [];

for (const entry of plan.refs || []) {
  for (const ref of entry.imageRefs || []) {
    if (!existsRef(ref.imageRef)) {
      missing.push({
        artistChainId: entry.artistChainId,
        imageRef: ref.imageRef,
      });
    }
  }
}

if (missing.length) {
  throw new Error(
    `Artist-chain varsize preview files are missing: ${JSON.stringify(
      missing.slice(0, 8),
    )}`,
  );
}

const refsByChain = new Map(
  (plan.refs || []).map((entry) => [
    entry.artistChainId,
    entry.imageRefs.map((ref) => ref.imageRef),
  ]),
);
const backupDir = backup(artistChainsPath);
let artistChainsApplied = 0;
let imageRefsApplied = 0;

for (const chain of artistChains) {
  const refs = refsByChain.get(chain.id);
  if (!refs?.length) continue;
  chain.imageRefs = prependRefs(chain.imageRefs, refs);
  artistChainsApplied += 1;
  imageRefsApplied += refs.length;
}

writeJson(artistChainsPath, artistChains);
writeJson(reportPath, {
  completedAt: new Date().toISOString(),
  workspaceRoot,
  backupDir,
  queuePath: plan.queuePath,
  suffix: plan.suffix,
  previewDir: plan.previewDir,
  sizes: plan.sizes,
  skipped: plan.skipped || [],
  artistChainsApplied,
  imageRefsApplied,
});

console.log(
  JSON.stringify(
    {
      artistChainsApplied,
      imageRefsApplied,
      skipped: (plan.skipped || []).length,
      backupDir,
      reportPath,
    },
    null,
    2,
  ),
);
