import fs from 'node:fs';
import path from 'node:path';

const defaultCacheDir = path.join(
  process.env.APPDATA ?? '',
  'org.exception0x0194',
  'nai3_autodraw',
  'novel_studio',
  'script_recast',
  'cache',
);

const defaultSourceRoot = 'E:/codeximage/ntr-story-cache-source';
const defaultManifestPath = 'build/ntr_story_new_cache_ids_20260610.json';
const defaultClassificationCache =
  'E:/NAI\u7684\u811a\u672c\u7fa4/tag_classification_cache.json';

const options = parseArgs(process.argv.slice(2));
const cacheDir = options.cacheDir ?? defaultCacheDir;
const sourceRoot = options.sourceRoot ?? defaultSourceRoot;
const manifestPath = options.manifest ?? defaultManifestPath;
const reportPath =
  options.report ?? 'build/ntr_story_ai1_role_cache_generation_20260610.json';

if (!fs.existsSync(cacheDir)) throw new Error(`Missing cache dir: ${cacheDir}`);
if (!fs.existsSync(sourceRoot)) {
  throw new Error(`Missing source root: ${sourceRoot}`);
}
if (!fs.existsSync(manifestPath)) {
  throw new Error(`Missing manifest: ${manifestPath}`);
}

const classificationCache = loadClassificationCache(
  options.classificationCache ?? defaultClassificationCache,
);
const manifestRows = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const assignedNames = fs
  .readdirSync(sourceRoot, { withFileTypes: true })
  .filter((entry) => entry.isDirectory())
  .map((entry) => entry.name)
  .slice(0, options.assignedCount ?? 32);
const assignedNameSet = new Set(assignedNames.map((name) => name.normalize('NFC')));

const targetRows = manifestRows
  .filter(
    (row) =>
      assignedNameSet.has(stringValue(row.name).normalize('NFC')) &&
      !stringValue(row.status).trim(),
  )
  .sort(
    (left, right) =>
      assignedNames.indexOf(left.name) - assignedNames.indexOf(right.name),
  );

const skippedReadyRows = manifestRows
  .filter(
    (row) =>
      assignedNameSet.has(stringValue(row.name).normalize('NFC')) &&
      stringValue(row.status).trim(),
  )
  .map((row) => ({
    file: row.file,
    script_id: row.id,
    name: row.name,
    status: row.status,
    roles: row.roles,
  }));

const summary = {
  apply: options.apply,
  worker: 'AI-1',
  cache_dir: cacheDir,
  source_root: sourceRoot,
  manifest: manifestPath,
  assigned_name_count: assignedNames.length,
  matched_empty_count: targetRows.length,
  skipped_ready_count: skippedReadyRows.length,
  skipped_ready_rows: skippedReadyRows,
  files_changed: 0,
  ready_written: 0,
  role_count: 0,
  stage_count: 0,
  attention_item_count: 0,
  low_frequency_identity_terms: 0,
  missing_metadata_frames: 0,
  empty_role_frames: 0,
  files: [],
};

for (const row of targetRows) {
  const filePath = path.join(cacheDir, row.file);
  if (!fs.existsSync(filePath)) {
    throw new Error(`Target cache file missing: ${filePath}`);
  }

  const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  if (stringValue(cache.scriptId) !== stringValue(row.id)) {
    throw new Error(
      `scriptId mismatch for ${row.file}: cache=${cache.scriptId} manifest=${row.id}`,
    );
  }
  if (stringValue(cache.scriptName).normalize('NFC') !== stringValue(row.name).normalize('NFC')) {
    throw new Error(
      `scriptName mismatch for ${row.file}: cache=${cache.scriptName} manifest=${row.name}`,
    );
  }

  const original = JSON.stringify(cache);
  const generation = generateExtraction(cache);
  cache.aiRoleExtraction = generation.extraction;
  cache.updatedAt = new Date().toISOString();

  const changed = JSON.stringify(cache) !== original;
  if (changed) {
    summary.files_changed += 1;
    if (options.apply) {
      fs.writeFileSync(filePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
      summary.ready_written += 1;
    }
  }

  summary.role_count += generation.extraction.roles.length;
  summary.stage_count += generation.extraction.roles.reduce(
    (total, role) => total + (Array.isArray(role.stages) ? role.stages.length : 0),
    0,
  );
  summary.attention_item_count += generation.extraction.attention_items.length;
  summary.low_frequency_identity_terms += generation.lowFrequencyIdentityTerms.length;
  summary.missing_metadata_frames += generation.missingMetadataFrames.length;
  summary.empty_role_frames += generation.emptyRoleFrames.length;
  summary.files.push({
    file_name: row.file,
    script_id: row.id,
    script_name: row.name,
    frames: cache.scriptSnapshot?.frames?.length ?? 0,
    role_slots: generation.roleSlotCount,
    roles: generation.extraction.roles.length,
    stages: generation.extraction.roles.reduce(
      (total, role) => total + (Array.isArray(role.stages) ? role.stages.length : 0),
      0,
    ),
    attention_items: generation.extraction.attention_items.length,
    low_frequency_identity_terms: generation.lowFrequencyIdentityTerms.slice(0, 30),
    empty_role_frames: generation.emptyRoleFrames,
    missing_metadata_frames: generation.missingMetadataFrames,
    role_summaries: generation.extraction.roles.map((role) => ({
      source_role_id: role.source_role_id,
      display_name: role.display_name,
      canonical_name: role.canonical_name,
      source_ids: role.appearances.map((appearance) => appearance.source_id),
      frames: role.frame_indexes.length,
      stages: role.stages.length,
      raw_identity_tags: role.raw_identity_tags,
    })),
  });
}

fs.mkdirSync(path.dirname(reportPath), { recursive: true });
fs.writeFileSync(reportPath, `${JSON.stringify(summary, null, 2)}\n`, 'utf8');
console.log(JSON.stringify(summary, null, 2));

function generateExtraction(cache) {
  const frames = Array.isArray(cache.scriptSnapshot?.frames)
    ? cache.scriptSnapshot.frames
    : [];
  const roleSlots = [];
  const emptyRoleFrames = [];
  const missingMetadataFrames = [];

  for (const frame of frames) {
    const frameIndex = toInt(frame.index);
    if (frameIndex == null) continue;
    if (frame?.parsed?.sourcePayload?.source_kind === 'png_metadata_missing_frame') {
      missingMetadataFrames.push(frameIndex);
    }
    const captions = Array.isArray(frame.parsed?.charCaptions)
      ? frame.parsed.charCaptions
      : [];
    let nonEmptyCaptions = 0;
    captions.forEach((caption, slot) => {
      const text = stringValue(caption).trim();
      if (!text) return;
      nonEmptyCaptions += 1;
      roleSlots.push({
        frameIndex,
        slot,
        sourceId: `slot-${slot}`,
        terms: splitTerms(text),
        caption: text,
      });
    });
    if (nonEmptyCaptions === 0) emptyRoleFrames.push(frameIndex);
  }

  const specificCounts = countSpecificIdentityTerms(roleSlots);
  const lowFrequencyIdentityTerms = [...specificCounts.entries()]
    .filter(([, count]) => count < options.minSpecificFrames)
    .map(([key, count]) => ({
      term: key,
      count,
    }))
    .sort((left, right) => right.count - left.count || left.term.localeCompare(right.term));

  const roleBuilders = new Map();
  for (const roleSlot of roleSlots) {
    const assignment = assignRole(roleSlot, specificCounts);
    const builder = ensureRoleBuilder(roleBuilders, assignment);
    builder.roleSlots.push({
      ...roleSlot,
      assignment,
      parts: partsFromTerms(roleSlot.terms, assignment),
    });
  }

  const roles = [...roleBuilders.values()]
    .map((builder) => materializeRole(builder))
    .sort((left, right) => {
      const leftFirst = left.frame_indexes[0] ?? Number.MAX_SAFE_INTEGER;
      const rightFirst = right.frame_indexes[0] ?? Number.MAX_SAFE_INTEGER;
      return leftFirst - rightFirst || left.source_role_id.localeCompare(right.source_role_id);
    });

  const attentionItems = [];
  if (missingMetadataFrames.length > 0) {
    attentionItems.push({
      kind: 'missing_metadata_frames',
      frame_indexes: missingMetadataFrames,
      note: 'PNG metadata missing in local scriptSnapshot; no role fields inferred from those frames.',
    });
  }
  for (const item of lowFrequencyIdentityTerms.slice(0, 50)) {
    attentionItems.push({
      kind: 'low_frequency_identity_term',
      term: item.term,
      count: item.count,
      note: 'Not promoted to a named role by the local conservative threshold.',
    });
  }

  return {
    roleSlotCount: roleSlots.length,
    lowFrequencyIdentityTerms,
    missingMetadataFrames,
    emptyRoleFrames,
    extraction: {
      schema_version: 'script_recast_ai_role_extraction_v1',
      status: 'ready',
      confidence: roles.length > 0 ? 0.78 : 0,
      roles,
      artist_chains: [],
      strong_filter_keywords: [],
      attention_items: attentionItems,
      unassigned_terms: [],
    },
  };
}

function countSpecificIdentityTerms(roleSlots) {
  const counts = new Map();
  for (const roleSlot of roleSlots) {
    const seenInSlot = new Set();
    for (const term of roleSlot.terms) {
      if (!isSpecificIdentityCandidate(term)) continue;
      const key = identityBaseKey(term);
      if (!key || seenInSlot.has(key)) continue;
      seenInSlot.add(key);
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
  }
  return counts;
}

function assignRole(roleSlot, specificCounts) {
  const specificCandidates = roleSlot.terms
    .filter(isSpecificIdentityCandidate)
    .map((term) => ({
      term,
      key: identityBaseKey(term),
      count: specificCounts.get(identityBaseKey(term)) ?? 0,
    }))
    .filter((candidate) => candidate.key && candidate.count >= options.minSpecificFrames)
    .sort((left, right) => {
      if (right.count !== left.count) return right.count - left.count;
      return roleSlot.terms.indexOf(left.term) - roleSlot.terms.indexOf(right.term);
    });

  if (specificCandidates.length > 0) {
    const winner = specificCandidates[0];
    return {
      kind: 'specific',
      key: `specific:${winner.key}`,
      roleId: `role-${slugify(winner.key)}`,
      canonicalName: slugify(winner.key).replace(/-/g, '_'),
      displayName: displayNameFromIdentityTerm(winner.term),
      identityKey: winner.key,
      primaryTerm: winner.term,
    };
  }

  const genericTerms = roleSlot.terms.filter(isGenericIdentityTerm);
  const primaryGeneric = chooseGenericIdentity(genericTerms);
  const genericLabel = primaryGeneric ? displayNameFromIdentityTerm(primaryGeneric) : `Source Slot ${roleSlot.slot}`;
  return {
    kind: 'generic',
    key: `slot:${roleSlot.slot}`,
    roleId: `role-source-slot-${roleSlot.slot}`,
    canonicalName: `source_slot_${roleSlot.slot}`,
    displayName: genericLabel,
    identityKey: `source slot ${roleSlot.slot}`,
    primaryTerm: primaryGeneric,
  };
}

function ensureRoleBuilder(roleBuilders, assignment) {
  let builder = roleBuilders.get(assignment.key);
  if (!builder) {
    builder = {
      assignment,
      roleSlots: [],
    };
    roleBuilders.set(assignment.key, builder);
  }
  return builder;
}

function materializeRole(builder) {
  const roleSlots = builder.roleSlots;
  const assignment = builder.assignment;
  const frames = sortedUnique(roleSlots.map((slot) => slot.frameIndex));
  const sourceIds = sortedUniqueStrings(roleSlots.map((slot) => slot.sourceId));
  const appearances = sourceIds.map((sourceId) => ({
    source_id: sourceId,
    source_kind: sourceId.startsWith('slot-') ? 'slot' : 'base',
    frame_indexes: sortedUnique(
      roleSlots
        .filter((slot) => slot.sourceId === sourceId)
        .map((slot) => slot.frameIndex),
    ),
  }));

  const stageMap = new Map();
  for (const roleSlot of roleSlots) {
    const signature = signatureForParts(roleSlot.parts);
    let stage = stageMap.get(signature);
    if (!stage) {
      stage = {
        parts: roleSlot.parts,
        frameIndexes: [],
      };
      stageMap.set(signature, stage);
    }
    stage.frameIndexes.push(roleSlot.frameIndex);
  }

  const stages = [...stageMap.values()]
    .sort((left, right) => {
      const leftFirst = Math.min(...left.frameIndexes);
      const rightFirst = Math.min(...right.frameIndexes);
      return leftFirst - rightFirst;
    })
    .map((stage, index) => {
      const stageId = `${assignment.roleId}-stage-${index + 1}`;
      const frameIndexes = sortedUnique(stage.frameIndexes);
      const evidenceTerms = stableEvidenceTerms(stage.parts);
      return {
        stage_id: stageId,
        label: labelForParts(stage.parts),
        appearance_group_id: stageId,
        merge_with_stage_ids: [],
        field_reasons: fieldReasons(stage.parts),
        confidence: assignment.kind === 'specific' ? 0.82 : 0.62,
        frame_indexes: frameIndexes,
        identity: stage.parts.identity.join(', '),
        upper_body: stage.parts.upperBody.join(', '),
        lower_body: stage.parts.lowerBody.join(', '),
        upper_clothing: stage.parts.upperClothing.join(', '),
        lower_clothing: stage.parts.lowerClothing.join(', '),
        evidence_terms: evidenceTerms,
        missing_fields: [],
        warnings: [],
      };
    });

  const roleEvidenceTerms = uniqueTerms(stages.flatMap((stage) => stage.evidence_terms));
  const rawIdentityTags = uniqueTerms(
    roleSlots.flatMap((slot) =>
      slot.parts.identity.filter(
        (term) =>
          isSpecificIdentityCandidate(term) ||
          (assignment.kind === 'generic' && isGenericIdentityTerm(term)),
      ),
    ),
  );

  return {
    source_role_id: assignment.roleId,
    source_kind: sourceIds.length > 1 ? 'cross_slot' : 'slot',
    display_name: assignment.displayName,
    role_reason:
      assignment.kind === 'specific'
        ? 'Local source captions contain the same stable character identity tag across these frame slots.'
        : 'Local source captions have a role-bearing slot without a promoted stable named identity.',
    canonical_name: assignment.canonicalName,
    franchise: '',
    raw_identity_tags: rawIdentityTags,
    variant_tags: variantTagsFromRawIdentities(rawIdentityTags, assignment.identityKey),
    merge_with_role_id: '',
    confidence: assignment.kind === 'specific' ? 0.82 : 0.62,
    frame_indexes: frames,
    appearances,
    evidence_terms: roleEvidenceTerms,
    warnings: [],
    stages,
    unassigned_terms: [],
  };
}

function partsFromTerms(terms, assignment) {
  const parts = {
    identity: [],
    upperBody: [],
    lowerBody: [],
    upperClothing: [],
    lowerClothing: [],
  };

  const specificTermsForAssignment = terms.filter(
    (term) =>
      isSpecificIdentityCandidate(term) &&
      identityBaseKey(term) === assignment.identityKey,
  );
  if (assignment.kind === 'specific') {
    parts.identity.push(...specificTermsForAssignment);
  }

  const genericTerms = terms.filter(isGenericIdentityTerm);
  const selectedGeneric = chooseGenericIdentity(genericTerms);
  if (selectedGeneric) parts.identity.push(selectedGeneric);
  if (assignment.kind === 'generic' && parts.identity.length === 0 && assignment.primaryTerm) {
    parts.identity.push(assignment.primaryTerm);
  }

  for (const term of terms) {
    if (isSpecificIdentityCandidate(term) || isGenericIdentityTerm(term)) continue;
    const route = routeRoleFieldTerm(term);
    if (!route) continue;
    parts[route].push(term);
  }

  return {
    identity: uniqueTerms(parts.identity),
    upperBody: uniqueTerms(parts.upperBody),
    lowerBody: uniqueTerms(parts.lowerBody),
    upperClothing: uniqueTerms(parts.upperClothing),
    lowerClothing: uniqueTerms(parts.lowerClothing),
  };
}

function routeRoleFieldTerm(term) {
  if (shouldDropTerm(term)) return null;
  if (isLowerClothingTerm(term)) return 'lowerClothing';
  if (isUpperClothingTerm(term)) return 'upperClothing';
  if (isUpperBodyTerm(term)) return 'upperBody';
  if (isLowerBodyTerm(term)) return 'lowerBody';
  return null;
}

function isSpecificIdentityCandidate(term) {
  const clean = cleanDisplayTerm(term);
  const key = termKey(clean);
  if (!key || isGenericIdentityTerm(clean)) return false;
  if (shouldDropTerm(clean)) return false;
  if (isBodyDescriptorTerm(clean) || isGarmentTerm(clean)) return false;
  if (/\b(faceless|muscular|musclar|dark skinned|dark skined|very dark skined|fat man|male smile|solo|male focus|assertive female|cheerleader|nun|elf|dragon girl|chair)\b/u.test(key)) {
    return false;
  }
  if (/\b(african|shaved head|hitachi magic wand|magic wand|emphasis lines|speed lines|motion lines|reaching|towards viewer|rimming|deepthroat|hypnosis|broken hypnosis|counting money|money|spoken|dollar sign|interrobang|partially visible|vulva|testicles|caressing|straddling|paizuri|pointing|shouting|mature male|surprise|outfit|costume|cosplay|recruitment|teamwork|holding|pom pom|shape|place|meme|relationship|sword|sexual|sex|piledriver|cheating|shrug|official alternate costume)\b/u.test(key)) {
    return false;
  }
  const category = categoryForTerm(clean);
  if (
    category &&
    !['character', 'copyright'].includes(category) &&
    !(/[()]/u.test(clean) && !hardNonIdentityCategories().has(category))
  ) {
    return false;
  }
  if (/[()]/u.test(clean)) return true;
  if (category === 'character' && /^[a-z][a-z0-9]+(?:_[a-z0-9]+)+$/u.test(clean)) {
    return true;
  }
  if (category === 'character' && /^[a-z0-9]+(?: [a-z0-9]+){1,4}$/u.test(key)) {
    return true;
  }
  if (category === 'character' && /^(pekomama)$/u.test(key)) return true;
  return false;
}

function isGenericIdentityTerm(term) {
  const key = termKey(term);
  return /^(1?girl|1?boy|girl|boy|woman|man|male|female|loli|child|old man)$/u.test(key);
}

function chooseGenericIdentity(terms) {
  const unique = uniqueTerms(terms);
  const priority = [
    'girl',
    '1girl',
    'loli',
    'child',
    'boy',
    '1boy',
    'man',
    'old man',
    'male',
    'woman',
    'female',
  ];
  return (
    [...unique].sort((left, right) => {
      const leftIndex = priority.indexOf(termKey(left));
      const rightIndex = priority.indexOf(termKey(right));
      return (
        (leftIndex < 0 ? 999 : leftIndex) -
        (rightIndex < 0 ? 999 : rightIndex)
      );
    })[0] ?? ''
  );
}

function shouldDropTerm(term) {
  const clean = cleanDisplayTerm(term);
  const key = termKey(clean);
  if (!key) return true;
  if (/^artist:/iu.test(clean)) return true;
  const category = categoryForTerm(clean);
  if (
    category &&
    [
      'artist',
      'negativeArtist',
      'style',
      'quality',
      'scene',
      'action',
      'camera',
      'negativeContent',
      'promptSyntax',
    ].includes(category)
  ) {
    return true;
  }
  if (/^(none|null|nil|unknown|n\/a|empty|other|stage|slot|source slot)$/u.test(key)) {
    return true;
  }
  if (/^(pose|poses|action|actions|explicit|adult|nsfw|safe|safety|review|warning)$/u.test(key)) {
    return true;
  }
  if (/^(text|japanese text|english text|speech bubble|spoken question mark|spoken exclamation mark|year \d+|best quality|amazing quality|very aesthetic|highres|incredibly absurdres)$/u.test(key)) {
    return true;
  }
  if (/\b(in later frames|in some frames|where present|when present|only coverage|not consistently|varies by frame|if visible|when visible)\b/u.test(key)) {
    return true;
  }
  if (hardTransientRegardlessOfGarmentPattern().test(key)) return true;
  if (isGarmentTerm(clean)) return false;
  if (isBodyDescriptorTerm(clean)) return transientBodyPattern().test(key);
  return transientPattern().test(key);
}

function hardTransientRegardlessOfGarmentPattern() {
  return /\b(crying|tears?|cum|precum|semen|penis|pussy|nipples?|areola|pubic|vibrator|sex toy|toy|orgasm|masturbat|penetrat|grabbing|holding|pulling|tail pulling|sweaty|between legs|looking through|through clothes|unworn|partially visible|vulva|testicles|paizuri|deepthroat|fellatio|handjob|kissing|licking|breastfeeding|lactation|naked|nude|hand|hands|wet|see through|lift|removed|open)\b/u;
}

function transientBodyPattern() {
  return /\b(pupils?|iris|irises|half closed|closed eyes?|empty eyes?|heart shaped|heart in eye|one eye closed|wide eyed|rolling eyes|uneven eyes|dashed eyes|glowing eyes|skin fang|teeth|mouth|blush|nose blush|nipples?|areola|navel|pussy|penis|ass|butt|anus|thighs?|armpits?|kneepits?|collarbone|ribs)\b/u;
}

function transientPattern() {
  return /\b(gym|exercise|workout|yoga pose|pose|push up|wooden floor|floor|bed|pillow|room|hallway|background|camera|pov|close up|from side|side view|straight on|dutch angle|looking|standing|sitting|kneeling|lying|running|walking|stretching|bending|squatting|spread legs|arms up|hands up|holding|grabbing|touching|hand over mouth|stun gun|toward another|fingering|sex|intercourse|masturbat|penetrat|cum|semen|orgasm|saliva|pussy|penis|nipples?|areola|navel|ass|butt|anus|stomach bulge|thighs?|blush|nose blush|smile|open mouth|heavy breathing|tears|crying|angry|embarrassed|wet|sweaty|sweat|stained|torn|torned|ripped|damaged|open towel|open clothes|open shirt|open jacket|partially removed|taking off|take off|undressing|lifted|lifting|pulled|pulling|covered nipples|facial|leash handling|nude|naked|bottomless|topless|completely nude|solo|solo focus|defeat|corruption|rape|bdsm|restrained|rope|bound|vibrator|dildo|sex toy|pregnant|lactation|breastfeeding|mother and child|baby|swaddled|carrying baby|mind break|fertilization|impregnation|ovum|after kiss|kiss|french kiss|fellatio|handjob|dog|animal|cross section|uterus|cervix|blood|dirty|barcode tattoo|pubic tattoo|tattoo|whip marks|heart)\b/u;
}

function isUpperBodyTerm(term) {
  const key = termKey(term);
  return /\b(hair|twintails?|twin tails?|ponytails?|braids?|headdress|ahoge|eyes?|ears?|horns?|halo|headband|headwear|hat|beret|ornament|ribbon|bow|tiara|necklace|choker|collar|earrings?|breasts?|chest|skin|mask)\b/u.test(key);
}

function isLowerBodyTerm(term) {
  const key = termKey(term);
  return /\b(tail|legs?|feet|foot|anklet|thigh strap)\b/u.test(key);
}

function isUpperClothingTerm(term) {
  const key = termKey(term);
  return /\b(shirt|blouse|jacket|coat|overcoat|hoodie|sweater|dress|uniform|bra|bikini top|leotard|bodysuit|swimsuit|school swimsuit|one piece swimsuit|kimono|robe|armor|gloves?|sleeves?|sports bra|towel|mantle|cloak|cape|belt|strap|bowtie|necktie|tie|frills?|lingerie|outfit|costume|clothes|clothing|pajamas|tank top|sailor collar|neckerchief|harness)\b/u.test(key);
}

function isLowerClothingTerm(term) {
  const key = termKey(term);
  return /\b(pants|trousers|shorts|skirt|miniskirt|panties|underwear|briefs|leggings|stockings?|socks?|thighhighs?|pantyhose|garter|shoes?|boots?|sandals?|heels?|loafers?|footwear|legwear|bikini bottom|swimsuit bottom|fundoshi|pelvic curtain|mary janes?)\b/u.test(key);
}

function isGarmentTerm(term) {
  return isUpperClothingTerm(term) || isLowerClothingTerm(term);
}

function isBodyDescriptorTerm(term) {
  return isUpperBodyTerm(term) || isLowerBodyTerm(term);
}

function categoryForTerm(term) {
  return classificationCache.get(`positive:${termKey(term)}`) ?? '';
}

function hardNonIdentityCategories() {
  return new Set([
    'artist',
    'negativeArtist',
    'style',
    'quality',
    'scene',
    'action',
    'camera',
    'clothing',
    'upperClothing',
    'lowerClothing',
    'upperBody',
    'lowerBody',
    'negativeContent',
    'promptSyntax',
  ]);
}

function identityBaseKey(term) {
  let key = termKey(term);
  key = key
    .replace(/\b(blue archive|princess connect|azur lane|genshin impact|fate grand order|shadowverse|glanblue fantasy|granblue fantasy)\b/g, ' ')
    .replace(/\b(summer|idol|mechanic|first year|dangerous beast|demi servant|scorching hot training|pillowed counseling|joyride of love|luxurious wheels|enraptured companion|female)\b/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return key;
}

function displayNameFromIdentityTerm(term) {
  const clean = cleanDisplayTerm(term);
  if (!clean) return 'Source Role';
  return clean
    .replace(/_/g, ' ')
    .replace(/\s*\([^)]*\)\s*/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/\b\w/g, (match) => match.toUpperCase());
}

function variantTagsFromRawIdentities(rawIdentityTags, baseKey) {
  const variants = [];
  for (const term of rawIdentityTags) {
    const clean = cleanDisplayTerm(term);
    const groups = [...clean.matchAll(/\(([^)]*)\)/g)].map((match) => match[1]);
    for (const group of groups) {
      const key = termKey(group);
      if (!key || baseKey.includes(key)) continue;
      if (/^(blue archive|princess connect!?|azur lane|genshin impact|fate grand order|shadowverse|glanblue fantasy|granblue fantasy)$/u.test(key)) {
        continue;
      }
      variants.push(group);
    }
  }
  return uniqueTerms(variants);
}

function signatureForParts(parts) {
  return JSON.stringify({
    identity: parts.identity.map(termKey),
    upperBody: parts.upperBody.map(termKey),
    lowerBody: parts.lowerBody.map(termKey),
    upperClothing: parts.upperClothing.map(termKey),
    lowerClothing: parts.lowerClothing.map(termKey),
  });
}

function labelForParts(parts) {
  const labelTerms = uniqueTerms([
    ...parts.upperClothing,
    ...parts.lowerClothing,
    ...parts.upperBody.filter((term) =>
      /collar|choker|headband|hat|ornament|tail/u.test(
        termKey(term),
      ),
    ),
  ]).slice(0, 4);
  if (labelTerms.length > 0) return labelTerms.join(' / ');
  return parts.identity.join(' / ') || 'source evidence';
}

function fieldReasons(parts) {
  const reasons = {};
  if (parts.identity.length > 0) {
    reasons.identity = 'Exact source caption identity or generic role tags.';
  }
  if (parts.upperBody.length > 0) {
    reasons.upper_body = 'Exact source caption stable upper-body traits or accessories.';
  }
  if (parts.lowerBody.length > 0) {
    reasons.lower_body = 'Exact source caption stable lower-body traits or accessories.';
  }
  if (parts.upperClothing.length > 0) {
    reasons.upper_clothing = 'Exact source caption upper or one-piece clothing tags.';
  }
  if (parts.lowerClothing.length > 0) {
    reasons.lower_clothing = 'Exact source caption lower clothing tags.';
  }
  return reasons;
}

function stableEvidenceTerms(parts) {
  return uniqueTerms([
    ...parts.identity,
    ...parts.upperBody,
    ...parts.lowerBody,
    ...parts.upperClothing,
    ...parts.lowerClothing,
  ]);
}

function splitTerms(value) {
  const source = stringValue(value);
  const terms = [];
  let current = '';
  let depth = 0;
  for (const char of source) {
    if ('([{'.includes(char)) depth += 1;
    if (')]}'.includes(char) && depth > 0) depth -= 1;
    if (char === ',' && depth === 0) {
      pushSplitTerm(terms, current);
      current = '';
    } else {
      current += char;
    }
  }
  pushSplitTerm(terms, current);
  return terms;
}

function pushSplitTerm(terms, value) {
  const clean = cleanDisplayTerm(value);
  if (!clean) return;
  if (/^\|.*\|$/.test(clean) && clean.includes('|')) {
    for (const part of clean.split('|')) {
      const nested = cleanDisplayTerm(part);
      if (nested) terms.push(nested);
    }
    return;
  }
  terms.push(clean);
}

function cleanDisplayTerm(value) {
  return stringValue(value)
    .replace(/\b-?\d+(?:\.\d+)?::/g, '')
    .replace(/::/g, '')
    .replace(/[{}[\]]/g, '')
    .replace(/^[\s:|,]+|[\s:|,]+$/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function termKey(value) {
  return cleanDisplayTerm(value)
    .toLowerCase()
    .replace(/\b-?\d+(?:\.\d+)?::/g, ' ')
    .replace(/::/g, ' ')
    .replace(/[_-]+/g, ' ')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function uniqueTerms(values) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    const clean = cleanDisplayTerm(value);
    const key = termKey(clean);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(clean);
  }
  return result;
}

function sortedUnique(values) {
  return [...new Set(values.map(Number).filter((value) => Number.isInteger(value)))]
    .sort((left, right) => left - right);
}

function sortedUniqueStrings(values) {
  return [...new Set(values.map(String))].sort((left, right) =>
    left.localeCompare(right),
  );
}

function slugify(value) {
  const slug = termKey(value).replace(/\s+/g, '-').replace(/^-+|-+$/g, '');
  return slug || 'source-role';
}

function loadClassificationCache(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return new Map();
  const raw = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const result = new Map();
  for (const [key, value] of Object.entries(raw)) {
    if (!value || typeof value.category !== 'string') continue;
    const [prefix, ...parts] = String(key).split(':');
    result.set(`${prefix}:${termKey(parts.join(':'))}`, value.category);
  }
  return result;
}

function parseArgs(args) {
  const parsed = {
    apply: false,
    cacheDir: undefined,
    sourceRoot: undefined,
    manifest: undefined,
    classificationCache: undefined,
    report: undefined,
    assignedCount: 32,
    minSpecificFrames: 5,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--apply') {
      parsed.apply = true;
      continue;
    }
    if (!arg.startsWith('--')) continue;
    const equal = arg.indexOf('=');
    const key = equal > 0 ? arg.slice(2, equal) : arg.slice(2);
    const value = equal > 0 ? arg.slice(equal + 1) : args[index + 1] ?? '';
    if (equal < 0) index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'source-root') parsed.sourceRoot = value;
    if (key === 'manifest') parsed.manifest = value;
    if (key === 'classification-cache') parsed.classificationCache = value;
    if (key === 'report') parsed.report = value;
    if (key === 'assigned-count') parsed.assignedCount = Number(value) || 32;
    if (key === 'min-specific-frames') {
      parsed.minSpecificFrames = Number(value) || 5;
    }
  }
  return parsed;
}

function toInt(value) {
  if (Number.isInteger(value)) return value;
  if (typeof value === 'number') return Math.trunc(value);
  if (typeof value === 'string' && /^-?\d+$/.test(value.trim())) {
    return Number(value);
  }
  return null;
}

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}
