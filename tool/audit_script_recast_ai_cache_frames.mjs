import fs from 'node:fs';
import path from 'node:path';

const defaultCacheDir = path.join(
  process.env.APPDATA ?? '',
  'Novel Studio',
  'Novel Studio',
  'novel_studio',
  'script_recast',
  'cache',
);

const options = parseArgs(process.argv.slice(2));
const cacheDir = options.cacheDir ?? defaultCacheDir;
if (!cacheDir || !fs.existsSync(cacheDir)) {
  throw new Error(`Cache directory does not exist: ${cacheDir}`);
}

const rows = fs
  .readdirSync(cacheDir)
  .filter((file) => file.endsWith('.json'))
  .sort()
  .map((file) => auditCacheFile(path.join(cacheDir, file)))
  .filter((row) => {
    if (options.scriptId && row.scriptId !== options.scriptId) return false;
    if (
      options.nameContains &&
      !row.scriptName.toLowerCase().includes(options.nameContains.toLowerCase())
    ) {
      return false;
    }
    return true;
  });

const incomplete = rows
  .filter(
    (row) =>
      row.snapshotFrameCount !== row.fingerprintFrameCount ||
      row.missingFrameIndexes.length > 0 ||
      row.extraFrameIndexes.length > 0,
  )
  .sort(
    (left, right) =>
      right.snapshotGap - left.snapshotGap ||
      right.missingFrameIndexes.length - left.missingFrameIndexes.length ||
      right.fingerprintFrameCount - left.fingerprintFrameCount,
  );

const summary = {
  cache_dir: cacheDir,
  cache_count: rows.length,
  ready_count: rows.filter((row) => row.status === 'ready').length,
  fingerprint_frame_count: sum(rows, 'fingerprintFrameCount'),
  snapshot_frame_count: sum(rows, 'snapshotFrameCount'),
  covered_frame_count: sum(rows, 'coveredFrameCount'),
  missing_frame_count: rows.reduce(
    (count, row) => count + row.missingFrameIndexes.length,
    0,
  ),
  extra_frame_count: rows.reduce(
    (count, row) => count + row.extraFrameIndexes.length,
    0,
  ),
  incomplete_cache_count: incomplete.length,
  incomplete: incomplete.slice(0, options.maxPrint).map(printableRow),
};

console.log(JSON.stringify(summary, null, 2));
if (options.reportPath) {
  fs.mkdirSync(path.dirname(options.reportPath), { recursive: true });
  fs.writeFileSync(
    options.reportPath,
    JSON.stringify(
      {
        ...summary,
        incomplete: incomplete.map(printableRow),
        rows,
      },
      null,
      2,
    ),
    'utf8',
  );
}

function auditCacheFile(filePath) {
  const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const snapshotFrameIndexes = parsedSnapshotFrameIndexes(cache);
  const snapshotFrameSet = new Set(snapshotFrameIndexes);
  const roleRequiredFrameIndexes = parsedRoleRequiredFrameIndexes(cache);
  const coveredFrameSet = aiCoveredFrameSet(cache.aiRoleExtraction ?? {});
  const coveredFrameIndexes = [...coveredFrameSet]
    .filter((frameIndex) => snapshotFrameSet.has(frameIndex))
    .sort((left, right) => left - right);
  const missingFrameIndexes = roleRequiredFrameIndexes.filter(
    (frameIndex) => !coveredFrameSet.has(frameIndex),
  );
  const extraFrameIndexes = [...coveredFrameSet]
    .filter((frameIndex) => !snapshotFrameSet.has(frameIndex))
    .sort((left, right) => left - right);
  const fingerprintFrameCount = sourceFingerprintFrameCount(
    cache.sourceFingerprint,
  );
  const snapshotFrameCount = snapshotFrameIndexes.length;
  return {
    fileName: path.basename(filePath),
    scriptId: stringValue(cache.scriptId),
    scriptName: stringValue(cache.scriptName),
    sourceRootPath: stringValue(cache.sourceRootPath),
    status: stringValue(cache.aiRoleExtraction?.status),
    fingerprintFrameCount,
    snapshotFrameCount,
    roleRequiredFrameCount: roleRequiredFrameIndexes.length,
    nonRoleFrameCount: snapshotFrameIndexes.length - roleRequiredFrameIndexes.length,
    snapshotGap: fingerprintFrameCount - snapshotFrameCount,
    coveredFrameCount: coveredFrameIndexes.length,
    missingFrameIndexes,
    extraFrameIndexes,
    roleCount: Array.isArray(cache.aiRoleExtraction?.roles)
      ? cache.aiRoleExtraction.roles.length
      : 0,
  };
}

function parsedRoleRequiredFrameIndexes(cache) {
  const frames = cache.scriptSnapshot?.frames;
  if (!Array.isArray(frames)) return [];
  return frames
    .filter((frame) => {
      const status = stringValue(frame.parseStatus ?? frame.parse_status);
      if (status.toLowerCase() !== 'parsed') return false;
      const captions = Array.isArray(frame.parsed?.charCaptions)
        ? frame.parsed.charCaptions
        : [];
      return captions.some((caption) => roleRelevantCaption(caption));
    })
    .map((frame) => Number(frame.index))
    .filter((value) => Number.isInteger(value) && value >= 0)
    .sort((left, right) => left - right);
}

function roleRelevantCaption(caption) {
  const tags = parsePromptTerms(caption);
  const normalized = tags.map(normalizedTagKey).filter(Boolean);
  if (normalized.length === 0) return false;
  if (
    normalized.every((tag) => isContextTerm(tag) || isHardNoRoleTerm(tag))
  ) {
    return false;
  }

  if (tags.some(hasConcreteCharacterShape)) return true;

  const hasBasicIdentity = normalized.some(isBasicGenericIdentity);
  const hasSpecificIdentity = normalized.some(isSpecificGenericIdentity);
  const hasAnyIdentity = hasBasicIdentity || hasSpecificIdentity;
  const hasStableEvidence = hasStableRoleEvidence(tags);
  const hasWholePresence = hasWholeCharacterPresenceEvidence(tags);

  if (!hasAnyIdentity && !hasStableEvidence) return false;
  if (
    hasOnlyPartialHumanEvidence(tags) &&
    !hasSpecificIdentity &&
    !hasDurablePartialRoleEvidence(tags)
  ) {
    return false;
  }
  if (hasBasicIdentity && (hasStableEvidence || hasWholePresence)) return true;
  if (hasSpecificIdentity || hasStableEvidence) return true;
  return false;
}

function parsePromptTerms(value) {
  return stripNegativeWeightedGroups(stringValue(value))
    .replace(/\r?\n/g, ',')
    .replace(/::\s*[+-]?\d+(?:\.\d+)?\s*::/g, ',')
    .replace(/::+/g, ',')
    .split(/[，、；;,|]+/)
    .map(cleanPromptTerm)
    .filter((term) => term.length > 0);
}

function stripNegativeWeightedGroups(text) {
  return stringValue(text).replace(/-\d+(?:\.\d+)?\s*::[\s\S]*?::/g, ',');
}

function cleanPromptTerm(value) {
  return stringValue(value)
    .replace(/\b-?\d+(?:\.\d+)?::/g, '')
    .replace(/::/g, '')
    .trim()
    .replace(
      /^((?:1\s*)?(?:girl|girls|female|woman|loli|boy|boys|male|man|men))\s+[+-]?\d+(?:\.\d+)?$/i,
      '$1',
    )
    .trim();
}

function normalizedTagKey(value) {
  return cleanPromptTerm(value)
    .toLowerCase()
    .replace(/[_-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function hasConcreteCharacterShape(tag) {
  const normalized = normalizedTagKey(tag);
  if (!normalized || /^artist[:\s]/.test(normalized) || normalized.startsWith('@')) {
    return false;
  }
  if (isHardNoRoleTerm(normalized) || isContextTerm(normalized)) return false;
  if (!/\([^)]{2,}\)/.test(tag)) return false;
  if (
    /\b(?:artist|channel|caststation|nyanpyoun|raarami|ahemaru|ratatatat|eonsang|freng)\b/.test(
      normalized,
    )
  ) {
    return false;
  }
  return true;
}

function hasStableRoleEvidence(tags) {
  if (hasWholeCharacterPresenceEvidence(tags)) return true;
  for (const tag of tags) {
    const normalized = normalizedTagKey(tag);
    if (!normalized || isHardNoRoleTerm(normalized)) continue;
    const category = auditCategoryForTag(tag);
    if (
      category === 'upperBody' ||
      category === 'lowerBody' ||
      category === 'upperClothing' ||
      category === 'lowerClothing'
    ) {
      return true;
    }
  }
  return false;
}

function hasOnlyPartialHumanEvidence(tags) {
  const normalized = tags.map(normalizedTagKey).filter(Boolean);
  const partial = normalized.some((tag) =>
    /\b(pov|disembodied hands?|pov hands?|pov arms?|only hands?|only lower body|only upper body|large hands?|transparent body|huge penis|penis|hand on pussy|fingering|licking nipple|suck .*nipple|pant bulge)\b/.test(
      tag,
    ),
  );
  if (!partial) return false;
  return !hasWholeCharacterPresenceEvidence(tags);
}

function hasDurablePartialRoleEvidence(tags) {
  for (const tag of tags) {
    const normalized = normalizedTagKey(tag);
    if (!normalized || isHardNoRoleTerm(normalized)) continue;
    if (
      /\b(student|hair|eyes?|shirt|pants|trousers|jacket|dress|skirt|robe|hat|ribbon|tail|ears?|uniform|suit|clothed|nude|naked|topless|bottomless|standing|sitting|lying)\b/.test(
        normalized,
      )
    ) {
      return true;
    }
    const category = auditCategoryForTag(tag);
    if (
      category === 'upperBody' ||
      category === 'lowerBody' ||
      category === 'upperClothing' ||
      category === 'lowerClothing'
    ) {
      return true;
    }
  }
  return false;
}

function hasWholeCharacterPresenceEvidence(tags) {
  const normalized = tags.map(normalizedTagKey).filter(Boolean).join(', ');
  return /\b(full body|whole body|entire body|body visible|torso|upper body|lower body|back view|from behind|standing|sitting|lying|kneeling|on back|on stomach|clothed|nude|naked|completely nude|naked man|naked male|nude male|shirtless|faceless|bald)\b/.test(
    normalized,
  );
}

function auditCategoryForTag(tag) {
  const normalized = normalizedTagKey(tag);
  if (!normalized) return 'nonRole';
  if (isHardNoRoleTerm(normalized)) return 'nonRole';
  if (isBasicGenericIdentity(normalized) || isSpecificGenericIdentity(normalized)) {
    return 'identity';
  }
  if (/\b(tail|paw|hooves?)\b/.test(normalized)) return 'lowerBody';
  if (
    /\b(hair|eyes?|iris|pupil|ears?|horns?|halo|fang|fangs|skin|face|hat|cap|hair ornament|headdress|headwear|jewelry|earrings?|necklace|choker|collar|ribbon|bow|twintails?|twin tails?|pony ?tail|pigtails?|braids?|bangs?|hairclip|hairband|glasses|crown|bracelet|tattoo|mole|cleavage|collarbone|shoulders?|armpits?|ribs?|chest|breasts?|bust|flat chest|midriff|abs)\b/.test(
      normalized,
    )
  ) {
    return 'upperBody';
  }
  if (
    /\b(thighs?|thick thighs?|bare legs?|legs?|navel|stomach|hips?|waist|barefoot|toes?|thighcut)\b/.test(
      normalized,
    )
  ) {
    return 'lowerBody';
  }
  if (
    /\b(shoes?|boots?|sneakers?|socks?|thighhigs|thighhighs?|pantyhose|stockings?|sandals?|heels?|pants|shorts|skirt|miniskirt|panties|underwear|briefs|trousers|leggings|garter|legwear|buruma|bikini bottoms?|bikini bottom only|side tie bikini bottom|side-tie bikini bottom)\b/.test(
      normalized,
    )
  ) {
    return 'lowerClothing';
  }
  if (
    /\b(shirt|tanktop|blouse|jacket|hoodie|hood|coat|suit|dress|uniform|serafuku|school swimsuit|kimono|yukata|bra|bikini|swimsuit|leotard|sleeves?|robe|armor|apron|overalls|tank top|crop top|cropped shirt|camisole|vest|cloak|hooded jacket|blazer|sweater|gloves?)\b/.test(
      normalized,
    )
  ) {
    return 'upperClothing';
  }
  return 'nonRole';
}

function isBasicGenericIdentity(term) {
  return /^(?:1\s*)?(?:girl|girls|female|woman|loli|boy|boys|male|man|men|guy|guys)$|^2\s*(?:girls|boys|males|men|guys)$/.test(
    normalizedTagKey(term),
  );
}

function isSpecificGenericIdentity(term) {
  return /\b(fat man|fat men|fat male|big man|old man|bald man|bald head|male bald head|african|black man|black skinned male|dark skinned male|dark-skinned male|muscular male|faceless male|bandit|orc|giant orc|homeless man|homless man|goblin|monster|monster boy|tentacle monster|flower tentacle vine monster|tentacle vine monster|vine monster|student|thief)\b/.test(
    normalizedTagKey(term),
  );
}

function isContextTerm(normalized) {
  return /\b(bathroom|bath|bathtub|shower|onsen|hot spring|workshop|factory|garage|mechanic|school|classroom|campus|train|subway|station|street|city|bedroom|bed|indoors|outdoors|building)\b/.test(
    normalized,
  );
}

function isHardNoRoleTerm(normalized) {
  if (/^artist[:\s]/.test(normalized) || normalized.startsWith('@')) return true;
  return /\b(quality|masterpiece|aesthetic|absurdres|highres|simple illustration|artist collaboration|solo|solo focus|multiple views|text|no text|looking|watching|closed eyes|open mouth|blush|crying|pain|sex|cum|orgy|fingering|petting|penetration|spread legs|spreading legs|spreading another|breast squeeze|breast grobbed|breast grabbed|breast grab|grab breast|grabbing breast|hair grab|grab .*hair|grabbing .*hair|pulling .*hair|face grab|grab .*face|leg grab|legs? grab|grab .*legs?|thigh grab|thighs? grab|hands? on another|hand on another|arms? on another|pov arms?|bare arms?|onee shota|grab panties|panties grab|grab another|grabbing another|ass|pussy|penis|nipples|areola|pubic|vaginal|anal|censored|mosaic|pov hands?|disembodied hands?|disemdbodied hands?|large hands?|transparent body|huge penis|veiny penis|erection|motion blur|motion lines|no humans|only face|only hands?|only lower body|only upper body|out of frame|head out of frame|head ouf of the frame|legs? lock|leg lock|holding|grabbing|caressing|licking|sucking|food|plate|skewer|bikini aside|swimsuit aside|leotard aside|skirt aside|skirt lift|covering .*mouth|finger on pussy|stethoscope on pussy|penis insert|insert .*mouth)\b/.test(
    normalized,
  );
}

function parsedSnapshotFrameIndexes(cache) {
  const frames = cache.scriptSnapshot?.frames;
  if (!Array.isArray(frames)) return [];
  return frames
    .filter((frame) => {
      const status = stringValue(frame.parseStatus ?? frame.parse_status);
      return status.toLowerCase() === 'parsed';
    })
    .map((frame) => Number(frame.index))
    .filter((value) => Number.isInteger(value) && value >= 0)
    .sort((left, right) => left - right);
}

function aiCoveredFrameSet(extraction) {
  const covered = new Set();
  for (const role of Array.isArray(extraction.roles) ? extraction.roles : []) {
    addInts(covered, role.frame_indexes ?? role.frameIndexes);
    for (const appearance of Array.isArray(role.appearances)
      ? role.appearances
      : []) {
      addInts(covered, appearance.frame_indexes ?? appearance.frameIndexes);
    }
    for (const stage of Array.isArray(role.stages) ? role.stages : []) {
      addInts(covered, stage.frame_indexes ?? stage.frameIndexes);
    }
  }
  return covered;
}

function addInts(set, values) {
  if (!Array.isArray(values)) return;
  for (const value of values) {
    const numberValue = Number(value);
    if (Number.isInteger(numberValue) && numberValue >= 0) {
      set.add(numberValue);
    }
  }
}

function sourceFingerprintFrameCount(fingerprint) {
  if (typeof fingerprint !== 'string' || !fingerprint.trim()) return 0;
  return fingerprint
    .split('|')
    .slice(2)
    .filter((part) => /^\d+:/.test(part)).length;
}

function printableRow(row) {
  return {
    file_name: row.fileName,
    script_id: row.scriptId,
    script_name: row.scriptName,
    source_root_path: row.sourceRootPath,
    status: row.status,
    fingerprint_frames: row.fingerprintFrameCount,
    snapshot_frames: row.snapshotFrameCount,
    role_required_frames: row.roleRequiredFrameCount,
    non_role_frames: row.nonRoleFrameCount,
    snapshot_gap: row.snapshotGap,
    covered_frames: row.coveredFrameCount,
    missing_frames: row.missingFrameIndexes.length,
    missing_sample: row.missingFrameIndexes.slice(0, 20),
    extra_frames: row.extraFrameIndexes.length,
    extra_sample: row.extraFrameIndexes.slice(0, 20),
    role_count: row.roleCount,
  };
}

function parseArgs(args) {
  const parsed = {
    cacheDir: undefined,
    scriptId: undefined,
    nameContains: undefined,
    reportPath: undefined,
    maxPrint: 20,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith('--')) continue;
    const equalIndex = arg.indexOf('=');
    const key = equalIndex > 0 ? arg.slice(2, equalIndex) : arg.slice(2);
    const value =
      equalIndex > 0 ? arg.slice(equalIndex + 1) : args[index + 1] ?? '';
    if (equalIndex < 0) index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'script-id') parsed.scriptId = value;
    if (key === 'name-contains') parsed.nameContains = value;
    if (key === 'report') parsed.reportPath = value;
    if (key === 'max-print' || key === 'maxPrint') {
      parsed.maxPrint = Number(value) || parsed.maxPrint;
    }
  }
  return parsed;
}

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}

function sum(rows, key) {
  return rows.reduce((total, row) => total + row[key], 0);
}
