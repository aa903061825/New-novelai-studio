import fs from 'node:fs';
import path from 'node:path';

const repoRoot = 'C:/Users/admin/Downloads/NAI_NEW';
const workspaceRoot =
  'C:/Users/admin/AppData/Roaming/Novel Studio/Novel Studio/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const artistChainsPath = path.join(libraryRoot, 'artist_chains.json');
const strictQueuePath = path.join(
  repoRoot,
  'tool',
  'asset-library-strict-artist-preview-queue.json',
);
const varsizeQueuePath = path.join(
  repoRoot,
  'tool',
  'asset-library-artist-chain-varsize-preview-queue.json',
);
const queuePath = path.join(
  repoRoot,
  'tool',
  'asset-library-target-vibe-artist-chain-preview-queue.json',
);
const planPath = path.join(
  libraryRoot,
  'asset_target_vibe_artist_chain_preview_plan.json',
);

const qaqRoot = 'E:/NAI\u7684\u811a\u672c\u7fa4/QAQ\u7684\u753b\u98ce';
const targets = [
  {
    artistChainId: 'legacy-artist-sheet-r12c5',
    suffix: 'qaq1-vibe',
    vibeReferences: [
      { path: `${qaqRoot}/1/2d0e77-8b0dd8.naiv4vibe` },
      { path: `${qaqRoot}/1/264960-51baec.naiv4vibe` },
      { path: `${qaqRoot}/1/e08a30-3a2899.naiv4vibe` },
    ],
  },
  {
    artistChainId: 'legacy-artist-sheet-r12c7',
    suffix: 'qaq2-vibe',
    vibeReferences: [
      { path: `${qaqRoot}/2/269c14-666ee3.naiv4vibe` },
      { path: `${qaqRoot}/2/ea2cc6-149e5d.naiv4vibe` },
    ],
  },
];

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, ''));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function suffixImageRef(ref, suffix) {
  const ext = path.extname(ref);
  const base = ext ? ref.slice(0, -ext.length) : ref;
  return `${base}-${suffix}${ext || '.png'}`;
}

function assertVibeFilesExist(target) {
  const missing = target.vibeReferences
    .map((reference) => reference.path)
    .filter((filePath) => !fs.existsSync(filePath));
  if (missing.length) {
    throw new Error(
      `Missing vibe files for ${target.artistChainId}: ${JSON.stringify(missing)}`,
    );
  }
}

const artistChains = readJson(artistChainsPath);
const strictQueue = readJson(strictQueuePath);
const varsizeQueue = readJson(varsizeQueuePath);
const sourceItemsByRef = new Map();
for (const item of [...varsizeQueue, ...strictQueue]) {
  if (item.imageRef) sourceItemsByRef.set(item.imageRef, item);
}

const queue = [];
const planTargets = [];
for (const target of targets) {
  assertVibeFilesExist(target);
  const chain = artistChains.find((item) => item.id === target.artistChainId);
  if (!chain) throw new Error(`Artist chain not found: ${target.artistChainId}`);

  const newImageRefs = [];
  const queuedIds = [];
  for (const previousRef of chain.imageRefs || []) {
    const sourceItem = sourceItemsByRef.get(previousRef);
    if (!sourceItem) {
      throw new Error(
        `No source queue item found for ${target.artistChainId}: ${previousRef}`,
      );
    }
    const imageRef = suffixImageRef(previousRef, target.suffix);
    const id = `${sourceItem.id}-${target.suffix}`;
    queue.push({
      ...sourceItem,
      id,
      imageRef,
      outputPath: path.join(workspaceRoot, imageRef),
      vibeReferences: target.vibeReferences,
    });
    newImageRefs.push(imageRef);
    queuedIds.push(id);
  }

  planTargets.push({
    artistChainId: target.artistChainId,
    artistChainName: chain.name,
    suffix: target.suffix,
    vibeReferences: target.vibeReferences,
    previousImageRefs: chain.imageRefs || [],
    newImageRefs,
    queuedIds,
  });
}

writeJson(queuePath, queue);
writeJson(planPath, {
  generatedAt: new Date().toISOString(),
  workspaceRoot,
  queuePath,
  strictQueuePath,
  varsizeQueuePath,
  targets: planTargets,
});

console.log(
  JSON.stringify(
    {
      queuePath,
      planPath,
      targetCount: planTargets.length,
      queueCount: queue.length,
      targets: planTargets.map((target) => ({
        artistChainId: target.artistChainId,
        imageRefs: target.newImageRefs.length,
        vibeReferences: target.vibeReferences.length,
      })),
    },
    null,
    2,
  ),
);
