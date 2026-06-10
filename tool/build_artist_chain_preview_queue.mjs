import fs from 'node:fs';
import path from 'node:path';

const workspaceRoot =
  'C:/Users/admin/AppData/Roaming/org.exception0x0194/nai3_autodraw/novel_studio';
const libraryRoot = path.join(workspaceRoot, 'library');
const artistChainsPath = path.join(libraryRoot, 'artist_chains.json');
const queuePath = path.join(
  'C:/Users/admin/Downloads/NAI_NEW',
  'tool',
  'asset-library-artist-chain-preview-queue.json',
);
const reportPath = path.join(libraryRoot, 'asset_artist_chain_preview_report.json');

const targetPreviewCount = 6;
const defaultQuality = 'best quality, amazing quality, very aesthetic, absurdres';
const unsafePattern =
  /\b(nsfw|nude|naked|explicit|sex|sexual|erotic|nipples?|pussy|penis|cum|spread legs|loli|shota|child|young)\b/i;
const brokenQualityPattern =
  /\b(worst quality|low quality|bad quality|bad anatomy|bad hands|missing fingers?|extra fingers?|extra digits|fewer digits|mutation|deformed|disfigured|duplicate|watermark|signature|username|text|logo|censored|mosaic)\b/i;

const backgroundScenes = [
  'cozy sunlit atelier background, art desk, soft daylight, depth of field',
  'quiet garden background, flowers, soft wind, warm natural light',
  'night city street background, neon reflections, cinematic rim lighting',
];
const plainScenes = [
  'simple white background, no scenery, clean studio lighting',
  'plain light gray background, no props, crisp silhouette',
  'minimal pastel backdrop, uncluttered, design sheet clarity',
];

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
  const backupDir = path.join(libraryRoot, `backup-${stamp}-artist-previews`);
  fs.mkdirSync(backupDir, { recursive: true });
  fs.copyFileSync(filePath, path.join(backupDir, path.basename(filePath)));
  return backupDir;
}

function normalizeTagText(value) {
  return String(value || '')
    .replace(/\r\n?/g, '\n')
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .join(', ');
}

function splitTags(prompt) {
  return normalizeTagText(prompt)
    .split(',')
    .map((tag) => tag.trim())
    .filter(Boolean);
}

function safeStylePrompt(chain) {
  return splitTags(chain.prompt)
    .filter((tag) => !unsafePattern.test(tag))
    .filter((tag) => !brokenQualityPattern.test(tag))
    .filter((tag) => tag !== defaultQuality)
    .join(', ');
}

function slugify(value) {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 96);
}

function unique(values) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    if (!value || typeof value !== 'string') continue;
    const key = value.replaceAll('\\', '/').toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(value);
  }
  return result;
}

function appendRef(refs, ref) {
  return unique([...(refs || []), ref]);
}

function refExists(ref) {
  if (!ref || typeof ref !== 'string') return false;
  const candidate = path.isAbsolute(ref) ? ref : path.join(workspaceRoot, ref);
  return fs.existsSync(candidate);
}

function promptFor({ chain, style, mode, variant }) {
  const scene =
    mode === 'background'
      ? backgroundScenes[variant % backgroundScenes.length]
      : plainScenes[variant % plainScenes.length];
  const framing =
    variant % 3 === 0
      ? 'full body, front view'
      : variant % 3 === 1
        ? 'cowboy shot, looking at viewer'
        : 'upper body portrait, expressive eyes';
  return [
    defaultQuality,
    style,
    '1girl, solo, adult original character',
    framing,
    mode === 'background'
      ? 'finished illustration sample with background'
      : 'character reference sample without background',
    scene,
    'clean linework, detailed eyes, balanced color palette',
    'safe, non-explicit, tasteful outfit',
    'no text, no watermark, no logo, no signature',
    `style sample for ${chain.name}`,
  ]
    .filter(Boolean)
    .join(', ');
}

const artistChains = readJson(artistChainsPath);
const backupDir = backup(artistChainsPath);
const queue = [];
const reportRows = [];

for (const chain of artistChains) {
  const validCount = (chain.imageRefs || []).filter(refExists).length;
  const missingCount = Math.max(0, targetPreviewCount - validCount);
  const style = safeStylePrompt(chain);
  if (!style || missingCount === 0) {
    reportRows.push({
      id: chain.id,
      name: chain.name,
      validBefore: validCount,
      generated: 0,
      skipped: !style ? 'empty_style_after_filter' : '',
    });
    continue;
  }

  let backgroundCount = Math.ceil(missingCount / 2);
  let plainCount = missingCount - backgroundCount;
  const modes = [];
  while (backgroundCount > 0 || plainCount > 0) {
    if (backgroundCount > 0) {
      modes.push('background');
      backgroundCount -= 1;
    }
    if (plainCount > 0) {
      modes.push('plain');
      plainCount -= 1;
    }
  }

  for (let index = 0; index < modes.length; index++) {
    const mode = modes[index];
    const rel = `assets/references/artist-previews/${slugify(
      `${chain.id}-${mode}-${validCount + index + 1}`,
    )}.png`;
    chain.imageRefs = appendRef(chain.imageRefs, rel);
    queue.push({
      id: `${chain.id}-${mode}-${validCount + index + 1}`,
      type: 'artist_chain_preview',
      artistChainId: chain.id,
      artistChainName: chain.name,
      mode,
      quality: defaultQuality,
      title: `${chain.name} / ${mode} ${validCount + index + 1}`,
      prompt: promptFor({ chain, style, mode, variant: index }),
      outputPath: path.join(workspaceRoot, rel),
    });
  }

  reportRows.push({
    id: chain.id,
    name: chain.name,
    validBefore: validCount,
    generated: modes.length,
    validTarget: targetPreviewCount,
    modes,
  });
}

writeJson(artistChainsPath, artistChains);
writeJson(queuePath, queue);
writeJson(reportPath, {
  generatedAt: new Date().toISOString(),
  workspaceRoot,
  targetPreviewCount,
  defaultQuality,
  backupDir,
  queuePath,
  totalQueued: queue.length,
  chains: reportRows,
});

console.log(
  JSON.stringify(
    {
      artistChains: artistChains.length,
      targetPreviewCount,
      totalQueued: queue.length,
      queuePath,
      reportPath,
      backupDir,
    },
    null,
    2,
  ),
);
