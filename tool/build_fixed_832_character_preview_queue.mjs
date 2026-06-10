import fs from 'node:fs';
import path from 'node:path';

const repoRoot = 'C:/Users/admin/Downloads/NAI_NEW';
const workspaceRoot =
  'C:/Users/admin/AppData/Roaming/org.exception0x0194/nai3_autodraw/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const sourceQueuePath = path.join(
  repoRoot,
  'tool',
  'asset-library-requested-character-previews.json',
);
const sourcePlanPath = path.join(
  libraryRoot,
  'asset_requested_character_preview_plan.json',
);
const queuePath = path.join(
  repoRoot,
  'tool',
  'asset-library-requested-character-previews-832p-b2.json',
);
const planPath = path.join(
  libraryRoot,
  'asset_requested_character_preview_plan_832p_b2.json',
);
const suffix = 'nai-v45-832p-b2';

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, ''));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function slugify(value) {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 140);
}

function previewRefFor(sourceId) {
  return `assets/references/novelai-character-previews/${slugify(
    `${sourceId}-${suffix}`,
  )}.png`;
}

const sourceQueue = readJson(sourceQueuePath);
const sourcePlan = readJson(sourcePlanPath);
const sourceRefsById = new Map(sourcePlan.refs.map((entry) => [entry.sourceId, entry]));
const queue = [];
const refs = [];

for (const item of sourceQueue) {
  const sourceRef = sourceRefsById.get(item.sourceId);
  if (!sourceRef) {
    throw new Error(`Missing source plan ref for ${item.sourceId}`);
  }
  const imageRef = previewRefFor(item.sourceId);
  const id = `${item.sourceId}-${suffix}`;
  queue.push({
    ...item,
    id,
    imageRef,
    title: `${item.title} / 832x1216 batch 2`,
    width: 832,
    height: 1216,
    outputPath: path.join(workspaceRoot, imageRef),
  });
  refs.push({
    ...sourceRef,
    imageRef,
    promptSubject: sourceRef.promptSubject,
    batch: '832p-b2',
  });
}

writeJson(queuePath, queue);
writeJson(planPath, {
  generatedAt: new Date().toISOString(),
  workspaceRoot,
  artistChain: sourcePlan.artistChain,
  quality: sourcePlan.quality,
  negativePrompt: sourcePlan.negativePrompt,
  queuePath,
  sourceQueuePath,
  sourcePlanPath,
  suffix,
  fixedSize: { width: 832, height: 1216 },
  queueCount: queue.length,
  refs,
  skipped: sourcePlan.skipped || [],
});

console.log(
  JSON.stringify(
    {
      queued: queue.length,
      skipped: (sourcePlan.skipped || []).length,
      queuePath,
      planPath,
    },
    null,
    2,
  ),
);
