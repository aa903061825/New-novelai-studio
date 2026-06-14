import fs from 'node:fs';
import path from 'node:path';

const options = parseArgs(process.argv.slice(2));
if (!options.cacheDir) {
  throw new Error('Usage: node tool/audit_script_recast_stage_consistency.mjs --cache-dir <dir> [--report-path <file>]');
}

const cacheDir = path.resolve(options.cacheDir);
const files = fs
  .readdirSync(cacheDir)
  .filter((file) => file.endsWith('.json'))
  .sort();

const report = {
  cache_dir: cacheDir,
  cache_count: files.length,
  stage_count: 0,
  mixed_stage_issue_count: 0,
  issue_cache_count: 0,
  issue_samples: [],
};

for (const file of files) {
  const cache = loadJson(path.join(cacheDir, file), null);
  if (!cache) continue;
  const issues = auditCache(cache);
  report.stage_count += issues.stageCount;
  report.mixed_stage_issue_count += issues.items.length;
  if (issues.items.length > 0) {
    report.issue_cache_count += 1;
    for (const item of issues.items.slice(0, 5)) {
      report.issue_samples.push({
        file_name: file,
        script_name: stringValue(cache.scriptName),
        ...item,
      });
    }
  }
}

report.issue_samples = report.issue_samples.slice(0, 25);
console.log(JSON.stringify(report, null, 2));
if (options.reportPath) {
  fs.mkdirSync(path.dirname(path.resolve(options.reportPath)), { recursive: true });
  fs.writeFileSync(options.reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
}

function auditCache(cache) {
  const frames = new Map();
  for (const frame of cache.scriptSnapshot?.frames ?? []) {
    frames.set(Number(frame.index), frame);
  }
  const items = [];
  let stageCount = 0;
  for (const role of cache.aiRoleExtraction?.roles ?? []) {
    const appearances = new Map();
    for (const appearance of role.appearances ?? []) {
      appearances.set(appearance.source_id, new Set(appearance.frame_indexes ?? []));
    }
    for (const stage of role.stages ?? []) {
      stageCount += 1;
      const buckets = new Set();
      for (const frameIndex of stage.frame_indexes ?? []) {
        const frame = frames.get(Number(frameIndex));
        if (!frame) continue;
        for (const [sourceId, sourceFrames] of appearances.entries()) {
          if (!sourceFrames.has(frameIndex)) continue;
          const slot = Number(String(sourceId).replace(/^slot-/, ''));
          const caption = frame.parsed?.charCaptions?.[slot];
          const bucket = appearanceBucketForCaption(caption);
          if (bucket !== 'unspecified') buckets.add(bucket);
        }
      }
      const criticalBuckets = [...buckets].sort();
      if (hasMixedAppearanceState(criticalBuckets)) {
        items.push({
          role_id: role.source_role_id,
          stage_id: stage.stage_id,
          label: stage.label,
          buckets: criticalBuckets,
          frame_count: (stage.frame_indexes ?? []).length,
          frame_sample: (stage.frame_indexes ?? []).slice(0, 12),
        });
      }
    }
  }
  return { stageCount, items };
}

function hasMixedAppearanceState(buckets) {
  const set = new Set(buckets);
  if (
    set.has('towel') &&
    buckets.some((bucket) => !['towel', 'nude'].includes(bucket))
  ) {
    return true;
  }
  if (set.has('towel')) {
    return false;
  }
  if (
    set.has('nude') &&
    buckets.some((bucket) => !['nude', 'partial-nude'].includes(bucket))
  ) {
    return true;
  }
  return buckets.filter((bucket) =>
    ['nude', 'towel', 'underwear', 'swimsuit'].includes(bucket),
  ).length > 2;
}

function appearanceBucketForCaption(caption) {
  const terms = new Set();
  for (const tag of parseTags(caption)) {
    if (isIdentityLikeTag(tag)) continue;
    const normalized = normalizedTagKey(tag);
    const term = stageSignatureTerm(normalized);
    if (term) terms.add(term);
  }
  if (terms.has('towel')) return 'towel';
  if (terms.has('nude')) return 'nude';
  if (terms.has('topless') || terms.has('bottomless')) return 'partial-nude';
  if (terms.has('underwear')) return 'underwear';
  if (terms.has('overalls')) return 'overalls';
  if (terms.has('tank top')) return 'tank top';
  if (terms.has('dress')) return 'dress';
  if (terms.has('uniform')) return 'uniform';
  if (terms.has('swimsuit')) return 'swimsuit';
  if (terms.has('outerwear')) return 'outerwear';
  return 'unspecified';
}

function stageSignatureTerm(normalized) {
  if (!normalized) return '';
  if (isHoldingTowelTerm(normalized)) return '';
  if (isNonRoleReplacementStateTerm(normalized)) return '';
  if (/\b(no panties|no underwear)\b/.test(normalized)) return 'no underwear';
  if (/\b(no overall|no overalls)\b/.test(normalized)) return 'no overalls';
  if (/\b(topless)\b/.test(normalized)) return 'topless';
  if (/\b(bottomless)\b/.test(normalized)) return 'bottomless';
  if (/\b(nude|naked|completely nude|no clothes)\b/.test(normalized)) {
    return 'nude';
  }
  if (isActualTowelTerm(normalized)) return 'towel';
  if (/\b(overalls?|overall skirt)\b/.test(normalized)) return 'overalls';
  if (/\b(tank top)\b/.test(normalized)) return 'tank top';
  if (/\b(panties|underwear)\b/.test(normalized)) return 'underwear';
  if (/\b(dress|skirt)\b/.test(normalized)) return 'dress';
  if (/\b(uniform|serafuku)\b/.test(normalized)) return 'uniform';
  if (/\b(swimsuit|bikini)\b/.test(normalized)) return 'swimsuit';
  if (/\b(hoodie|hooded jacket|jacket|coat)\b/.test(normalized)) return 'outerwear';
  return '';
}

function isActualTowelTerm(normalized) {
  if (isHoldingTowelTerm(normalized)) return false;
  return (
    normalized === 'towel' ||
    /\b(naked towel|white towel|bath towel|towel wrap|wrapped in towel|towel around body|large towel around body|long white towel around body|long towel around body)\b/.test(
      normalized,
    )
  );
}

function isHoldingTowelTerm(normalized) {
  return /\b(holding towel|hold towel|towel in hand|cover mouth with a towel|covering mouth with a towel|open towel)\b/.test(
    normalized,
  );
}

function isNonRoleReplacementStateTerm(normalized) {
  return [
    /\b(nude male'?s? arm|nude male s arm|nude man'?s? arm|nude man s arm|nude boy'?s? arm|nude boy s arm|male'?s? arm|male s arm|man'?s? arm|man s arm|boy'?s? arm|boy s arm|nude arm)\b/,
    /\b(girl panties|hand wedgie|wedgie|hand in panties|hand in another s panties|hand inside .*bikini bottom|holding .*pants|holding another s pants|holding .*panties)\b/,
    /\b(hand on skirt|hands on skirt|lifting .*skirt|lifted .*skirt|lifting other s skirt|lifting another s skirt|removing .*top|removing other s top)\b/,
    /\b(pants pull|bikini pull|pulling down .*bikini|hands on bikini|hands on breasts|bikini top pull|hands on bikini top)\b/,
    /\b(grabbing another s (?:jacket|coat|skirt|dress|clothes|pants|panties|bikini)|grabbing girl s underwear|tear .*underwear|poke .*shirt)\b/,
    /\b(lifted .*bra|lifting .*bra|lifting .*dress|dress .*lift|torn .*skirt|torn .*dress|skirt pull|skirt lift)\b/,
    /\b(partially undressed|torn clothes|forced exposure|pussy cutout|breasts? out|face to crotch|undressing another)\b/,
    /\b(bikini aside|swimsuit aside|leotard aside|bra aside|shirt aside|skirt aside|clothes aside|panties aside)\b/,
  ].some((pattern) => pattern.test(normalized));
}

function isIdentityLikeTag(tag) {
  const raw = stringValue(tag).trim();
  const normalized = normalizedTagKey(raw);
  if (!normalized) return false;
  if (/^(?:1|2)?girls?$|^(?:1)?boys?$|^female$|^male$|^woman$|^man$/.test(normalized)) {
    return true;
  }
  if (/\([^)]{3,}\)/.test(raw) && !/^artist[:\s]/i.test(raw)) {
    return true;
  }
  return false;
}

function parseTags(text) {
  return stripNegativeWeightedGroups(stringValue(text).replace(/\r?\n/g, ','))
    .replace(/::\s*[+-]?\d+(?:\.\d+)?\s*::/g, ',')
    .replace(/::+/g, ',')
    .replace(/[、，；;|]+/g, ',')
    .split(',')
    .map(cleanTag)
    .filter(Boolean);
}

function stripNegativeWeightedGroups(text) {
  return stringValue(text).replace(/-\d+(?:\.\d+)?\s*::[\s\S]*?::/g, ',');
}

function cleanTag(value) {
  let text = stringValue(value).trim();
  if (!text) return '';
  let changed = true;
  while (changed) {
    const leadingWeight = text.match(/^([+-]?\d+(?:\.\d+)?)\s*::\s*/);
    if (leadingWeight && Number(leadingWeight[1]) <= 0) return '';
    const next = text.replace(/^[+]?\d+(?:\.\d+)?\s*::\s*/g, '').trim();
    changed = next !== text;
    text = next;
  }
  text = text.replace(/::+$/g, '').replace(/^:+|:+$/g, '').trim();
  text = text.replace(/^(?:and|with)\s+/i, '').trim();
  const weighted = text.match(/^\((.*):[+-]?\d+(?:\.\d+)?\)$/);
  if (weighted) text = weighted[1].trim();
  return text.replace(/\s+/g, ' ').trim();
}

function normalizedTagKey(value) {
  return stringValue(value)
    .toLowerCase()
    .replace(/[_-]+/g, ' ')
    .replace(/[(){}\[\]'":!?]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function loadJson(filePath, fallback) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return fallback;
  }
}

function parseArgs(args) {
  const parsed = { cacheDir: '', reportPath: '' };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith('--')) continue;
    const value = args[index + 1];
    index += 1;
    if (arg === '--cache-dir') parsed.cacheDir = value;
    if (arg === '--report-path') parsed.reportPath = value;
  }
  return parsed;
}
