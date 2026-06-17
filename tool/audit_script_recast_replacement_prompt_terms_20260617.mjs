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
const cacheDir = path.resolve(options.cacheDir ?? defaultCacheDir);
const reportPath =
  options.report ??
  path.join('build', 'script_recast_replacement_prompt_terms_audit_20260617.json');

if (!fs.existsSync(cacheDir)) {
  throw new Error(`Missing cache dir: ${cacheDir}`);
}

const files = fs
  .readdirSync(cacheDir)
  .filter((file) => /^script-.*\.json$/.test(file))
  .sort();

const report = {
  cache_dir: cacheDir,
  files_scanned: files.length,
  clothing_evidence_count: 0,
  clothing_missing_prompt_term_count: 0,
  clothing_wrong_category_count: 0,
  clothing_missing_mapping_count: 0,
  clothing_unmatched_role_evidence_count: 0,
  clothing_term_no_role_slot_evidence_count: 0,
  scene_evidence_count: 0,
  scene_missing_prompt_term_count: 0,
  scene_missing_mapping_count: 0,
  issue_cache_count: 0,
  files: [],
};

for (const fileName of files) {
  const filePath = path.join(cacheDir, fileName);
  const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const fileReport = auditCache(fileName, cache);
  report.clothing_evidence_count += fileReport.clothing_evidence_count;
  report.clothing_missing_prompt_term_count +=
    fileReport.clothing_missing_prompt_term_count;
  report.clothing_wrong_category_count += fileReport.clothing_wrong_category_count;
  report.clothing_missing_mapping_count += fileReport.clothing_missing_mapping_count;
  report.clothing_unmatched_role_evidence_count +=
    fileReport.clothing_unmatched_role_evidence_count;
  report.clothing_term_no_role_slot_evidence_count +=
    fileReport.clothing_term_no_role_slot_evidence_count;
  report.scene_evidence_count += fileReport.scene_evidence_count;
  report.scene_missing_prompt_term_count +=
    fileReport.scene_missing_prompt_term_count;
  report.scene_missing_mapping_count += fileReport.scene_missing_mapping_count;

  if (
    fileReport.clothing_missing_prompt_term_count > 0 ||
    fileReport.clothing_wrong_category_count > 0 ||
    fileReport.clothing_missing_mapping_count > 0 ||
    fileReport.clothing_unmatched_role_evidence_count > 0 ||
    fileReport.clothing_term_no_role_slot_evidence_count > 0 ||
    fileReport.scene_missing_prompt_term_count > 0 ||
    fileReport.scene_missing_mapping_count > 0
  ) {
    report.issue_cache_count += 1;
    report.files.push(fileReport);
  }
}

fs.mkdirSync(path.dirname(reportPath), { recursive: true });
fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
console.log(JSON.stringify(report, null, 2));

function auditCache(fileName, cache) {
  const roles = Array.isArray(cache.aiRoleExtraction?.roles)
    ? cache.aiRoleExtraction.roles
    : [];
  const roleBySlotFrame = buildRoleBySlotFrame(roles);
  const roleMappingTerms = buildRoleMappingTermSets(cache);
  const sceneTerms = new Set(
    (Array.isArray(cache.aiRoleExtraction?.scene_terms)
      ? cache.aiRoleExtraction.scene_terms
      : []
    )
      .map((term) => normalizedTagKey(term?.text))
      .filter(Boolean),
  );
  const sceneMappingTerms = buildSceneMappingTermSet(cache);
  const frames = Array.isArray(cache.scriptSnapshot?.frames)
    ? cache.scriptSnapshot.frames
    : [];
  const frameByIndex = buildFrameByIndex(frames);
  const baseRoleCountByFrame = buildBaseRoleCountByFrame(roles);

  const fileReport = {
    file_name: fileName,
    script_id: stringValue(cache.scriptId),
    script_name: stringValue(cache.scriptName),
    clothing_evidence_count: 0,
    clothing_missing_prompt_term_count: 0,
    clothing_wrong_category_count: 0,
    clothing_missing_mapping_count: 0,
    clothing_unmatched_role_evidence_count: 0,
    clothing_term_no_role_slot_evidence_count: 0,
    scene_evidence_count: 0,
    scene_missing_prompt_term_count: 0,
    scene_missing_mapping_count: 0,
    samples: [],
  };

  const seenSceneEvidence = new Set();
  for (const frame of frames) {
    const frameIndex = Number(frame.index);
    if (!Number.isInteger(frameIndex)) continue;
    auditSceneCaption({
      caption: frame.parsed?.baseCaption,
      frameIndex,
      sourceLocation: 'base prompt',
      sceneTerms,
      sceneMappingTerms,
      seenSceneEvidence,
      fileReport,
    });
    const captions = Array.isArray(frame.parsed?.charCaptions)
      ? frame.parsed.charCaptions
      : [];
    captions.forEach((caption, slot) => {
      auditSceneCaption({
        caption,
        frameIndex,
        sourceLocation: `slot-${slot} prompt`,
        sceneTerms,
        sceneMappingTerms,
        seenSceneEvidence,
        fileReport,
      });
      for (const rawTag of parseTags(caption)) {
        const expected = clothingPromptTermForTag(rawTag);
        if (!expected) continue;
        const expectedCategory = clothingPromptTermCategoryForTag(rawTag);
        const expectedKey = normalizedTagKey(expected);
        const matchedRoles =
          roleBySlotFrame.get(`slot-${slot}\u001f${frameIndex}`) ?? [];
        if (matchedRoles.length === 0) {
          if (isUnassignableClothingActionEvidence(rawTag, caption)) {
            continue;
          }
          fileReport.clothing_unmatched_role_evidence_count += 1;
          sample(fileReport, {
            reason: 'clothing_unmatched_role',
            frame: frameIndex,
            slot,
            term: expected,
            expectedCategory,
          });
          continue;
        }
        for (const role of matchedRoles) {
          fileReport.clothing_evidence_count += 1;
          const prompt = promptTermMap(role.prompt_terms);
          const roleTerm = prompt.get(expectedKey);
          if (!roleTerm) {
            fileReport.clothing_missing_prompt_term_count += 1;
            sample(fileReport, {
              reason: 'missing_clothing_prompt_term',
              frame: frameIndex,
              slot,
              role: role.source_role_id,
              term: expected,
              expectedCategory,
            });
            continue;
          }
          if (!promptCategoryMatches(expectedCategory, roleTerm.category)) {
            fileReport.clothing_wrong_category_count += 1;
            sample(fileReport, {
              reason: 'wrong_clothing_category',
              frame: frameIndex,
              slot,
              role: role.source_role_id,
              term: expected,
              expectedCategory,
              category: roleTerm.category,
            });
          }
          const mappedTerms =
            roleMappingTerms.get(stringValue(role.source_role_id)) ?? new Set();
          if (!mappedTerms.has(expectedKey)) {
            fileReport.clothing_missing_mapping_count += 1;
            sample(fileReport, {
              reason: 'missing_role_prompt_mapping',
              frame: frameIndex,
              slot,
              role: role.source_role_id,
              term: expected,
              expectedCategory,
            });
          }
        }
      }
    });
  }

  for (const role of roles) {
    auditRoleClothingPromptTermEvidence({
      role,
      frameByIndex,
      baseRoleCountByFrame,
      fileReport,
    });
  }

  return fileReport;
}

function auditSceneCaption({
  caption,
  frameIndex,
  sourceLocation,
  sceneTerms,
  sceneMappingTerms,
  seenSceneEvidence,
  fileReport,
}) {
  for (const tag of parseTags(caption)) {
    if (!isScenePromptTerm(tag)) continue;
    const text = cleanTag(tag);
    const key = normalizedTagKey(text);
    const evidenceKey = `${key}\u001f${frameIndex}\u001f${sourceLocation}`;
    if (seenSceneEvidence.has(evidenceKey)) continue;
    seenSceneEvidence.add(evidenceKey);
    fileReport.scene_evidence_count += 1;
    if (!sceneTerms.has(key)) {
      fileReport.scene_missing_prompt_term_count += 1;
      sample(fileReport, {
        reason: 'missing_scene_prompt_term',
        frame: frameIndex,
        sourceLocation,
        term: text,
      });
    }
    if (!sceneMappingTerms.has(key)) {
      fileReport.scene_missing_mapping_count += 1;
      sample(fileReport, {
        reason: 'missing_scene_prompt_mapping',
        frame: frameIndex,
        sourceLocation,
        term: text,
      });
    }
  }
}

function auditRoleClothingPromptTermEvidence({
  role,
  frameByIndex,
  baseRoleCountByFrame,
  fileReport,
}) {
  const terms = Array.isArray(role.prompt_terms) ? role.prompt_terms : [];
  for (const term of terms) {
    const category = normalizePromptCategory(term?.category);
    if (category !== 'clothing' && category !== 'clothingState') continue;
    if (
      rolePromptTermHasOwnSlotEvidence(
        role,
        term,
        frameByIndex,
        baseRoleCountByFrame,
      )
    ) {
      continue;
    }
    fileReport.clothing_term_no_role_slot_evidence_count += 1;
    sample(fileReport, {
      reason: 'clothing_term_no_role_slot_evidence',
      role: role.source_role_id,
      term: term?.text,
      category: term?.category,
      sourcePhrase: term?.source_phrase ?? term?.sourcePhrase,
      frameIndexes: term?.frame_indexes ?? term?.frameIndexes ?? [],
    });
  }
}

function rolePromptTermHasOwnSlotEvidence(
  role,
  term,
  frameByIndex,
  baseRoleCountByFrame,
) {
  const candidates = promptTermEvidenceCandidates(term);
  if (candidates.size === 0) return false;
  const termFrames = new Set(
    (Array.isArray(term?.frame_indexes)
      ? term.frame_indexes
      : Array.isArray(term?.frameIndexes)
        ? term.frameIndexes
        : []
    )
      .map(Number)
      .filter(Number.isInteger),
  );
  for (const appearance of Array.isArray(role.appearances)
    ? role.appearances
    : []) {
    const sourceId = stringValue(appearance.source_id || appearance.sourceId);
    const slot = slotIndexFromSourceId(sourceId);
    const appearanceFrames = new Set(
      (Array.isArray(appearance.frame_indexes)
        ? appearance.frame_indexes
        : Array.isArray(appearance.frameIndexes)
          ? appearance.frameIndexes
          : []
      )
        .map(Number)
        .filter(Number.isInteger),
    );
    const framesToCheck =
      termFrames.size > 0
        ? [...termFrames].filter((frameIndex) => appearanceFrames.has(frameIndex))
        : [...appearanceFrames];
    for (const frameIndex of framesToCheck) {
      const frame = frameByIndex.get(frameIndex);
      let caption = '';
      if (sourceId === 'base') {
        if ((baseRoleCountByFrame.get(frameIndex) ?? 0) !== 1) continue;
        caption = frame?.parsed?.baseCaption;
      } else {
        if (!Number.isInteger(slot)) continue;
        const captions = Array.isArray(frame?.parsed?.charCaptions)
          ? frame.parsed.charCaptions
          : [];
        caption = captions[slot];
      }
      for (const rawTag of parseTags(caption)) {
        const evidenceText = clothingPromptTermForTag(rawTag) || cleanTag(rawTag);
        if (candidates.has(normalizedTagKey(evidenceText))) return true;
        if (candidates.has(normalizedTagKey(rawTag))) return true;
      }
    }
  }
  return false;
}

function promptTermEvidenceCandidates(term) {
  const candidates = new Set();
  for (const value of [
    term?.text,
    term?.source_phrase,
    term?.sourcePhrase,
  ]) {
    const text = cleanTag(value);
    const key = normalizedTagKey(text);
    if (key) candidates.add(key);
  }
  return candidates;
}

function slotIndexFromSourceId(sourceId) {
  const match = stringValue(sourceId).match(/^slot-(\d+)$/);
  return match ? Number(match[1]) : NaN;
}

function buildFrameByIndex(frames) {
  const map = new Map();
  for (const frame of frames) {
    const frameIndex = Number(frame?.index);
    if (Number.isInteger(frameIndex)) map.set(frameIndex, frame);
  }
  return map;
}

function buildBaseRoleCountByFrame(roles) {
  const map = new Map();
  for (const role of roles) {
    for (const appearance of Array.isArray(role.appearances)
      ? role.appearances
      : []) {
      const sourceId = stringValue(appearance.source_id || appearance.sourceId);
      if (sourceId !== 'base') continue;
      for (const frameIndex of Array.isArray(appearance.frame_indexes)
        ? appearance.frame_indexes
        : Array.isArray(appearance.frameIndexes)
          ? appearance.frameIndexes
          : []) {
        const numeric = Number(frameIndex);
        if (!Number.isInteger(numeric)) continue;
        map.set(numeric, (map.get(numeric) ?? 0) + 1);
      }
    }
  }
  return map;
}

function buildRoleBySlotFrame(roles) {
  const map = new Map();
  for (const role of roles) {
    for (const appearance of Array.isArray(role.appearances)
      ? role.appearances
      : []) {
      const sourceId = stringValue(appearance.source_id || appearance.sourceId);
      if (!sourceId) continue;
      for (const frameIndex of Array.isArray(appearance.frame_indexes)
        ? appearance.frame_indexes
        : []) {
        const key = `${sourceId}\u001f${Number(frameIndex)}`;
        if (!map.has(key)) map.set(key, []);
        map.get(key).push(role);
      }
    }
  }
  return map;
}

function buildRoleMappingTermSets(cache) {
  const map = new Map();
  for (const replacement of Array.isArray(cache.mapping?.rolePromptReplacements)
    ? cache.mapping.rolePromptReplacements
    : []) {
    const roleId = stringValue(replacement.sourceRoleId);
    if (!roleId) continue;
    const set = map.get(roleId) ?? new Set();
    for (const rule of Array.isArray(replacement.rules)
      ? replacement.rules
      : []) {
      for (const term of Array.isArray(rule.sourceTerms)
        ? rule.sourceTerms
        : []) {
        const key = normalizedTagKey(term?.text);
        if (key) set.add(key);
      }
    }
    map.set(roleId, set);
  }
  return map;
}

function buildSceneMappingTermSet(cache) {
  const set = new Set();
  for (const replacement of Array.isArray(cache.mapping?.scenePromptReplacements)
    ? cache.mapping.scenePromptReplacements
    : []) {
    for (const rule of Array.isArray(replacement.rules)
      ? replacement.rules
      : []) {
      for (const term of Array.isArray(rule.sourceTerms)
        ? rule.sourceTerms
        : []) {
        const key = normalizedTagKey(term?.text);
        if (key) set.add(key);
      }
    }
  }
  return set;
}

function promptTermMap(terms) {
  const map = new Map();
  for (const term of Array.isArray(terms) ? terms : []) {
    const key = normalizedTagKey(term?.text);
    if (key) map.set(key, term);
  }
  return map;
}

function promptCategoryMatches(expected, actual) {
  return normalizePromptCategory(expected) === normalizePromptCategory(actual);
}

function normalizePromptCategory(category) {
  const value = stringValue(category);
  if (value === 'clothing_state') return 'clothingState';
  return value;
}

function clothingPromptTermForTag(tag) {
  const normalized = normalizedTagKey(tag);
  if (!normalized) return '';
  if (isKnownFranchiseCharacterTag(tag, normalized) || isVariantNamedCharacterTag(tag)) {
    return '';
  }
  if (isOtherCharacterClothingActionTag(normalized)) return '';
  if (isNonClothingPhraseWithClothingToken(normalized)) return '';
  if (!isAllowedClothingStatePromptTerm(normalized) && !containsGarmentOrClothingToken(normalized)) {
    return '';
  }
  return cleanPromptReplacementStateTag(tag);
}

function clothingPromptTermCategoryForTag(tag) {
  const normalized = normalizedTagKey(tag);
  if (!normalized) return 'clothing';
  return isAllowedClothingStatePromptTerm(normalized) ? 'clothingState' : 'clothing';
}

function isUnassignableClothingActionEvidence(tag, caption) {
  const normalized = normalizedTagKey(tag);
  const normalizedCaption = normalizedTagKey(caption);
  if (!normalized) return false;
  if (
    /\b(?:another(?:'?s| s)?|other(?:'?s| s)?|girls?|girl(?:'?s| s)?)\b/.test(
      normalized,
    ) &&
    containsGarmentOrClothingToken(normalized)
  ) {
    return true;
  }
  if (
    /\b(?:grab(?:bing)?|hands?\s+on|pressing|fingering|fingering\s+through\s+clothes|touching|undressing|panties?\s+grab|grab\s+(?:panties?|clothes?)|skirt\s+lift|bikini\s+aside|clothes?\s+to\s+lift|lift\s+(?:down|fown)|wand\b.*\bpanty)\b/.test(
      normalized,
    ) &&
    /\b(?:pov hands?|pov|disembodied hands?|only hands?|partial body|cropped limbs?|cut off silhouette|foreground obstruction)\b/.test(
      normalizedCaption,
    )
  ) {
    return true;
  }
  return false;
}

function cleanPromptReplacementStateTag(tag) {
  let text = cleanTag(tag);
  if (!text) return '';
  let previous = '';
  while (previous !== text) {
    previous = text;
    text = text.replace(/^[{}\[\]\s]+|[{}\[\]\s]+$/g, '').trim();
  }
  return text.replace(/\s+/g, ' ').trim();
}

function isAllowedClothingStatePromptTerm(normalized) {
  if (!normalized) return false;
  if (isCrossSubjectClothingCompositionTerm(normalized)) return false;
  if (/^(?:top down bottom up|top-down bottom-up)$/.test(normalized)) return false;
  if (/^(?:no panties|no underwear|no bra|no clothes)$/.test(normalized)) {
    return true;
  }
  if (/^(?:no shirt|no pants|no skirt|no socks|no shoes|no footwear)$/.test(normalized)) {
    return true;
  }
  if (
    /^(?:bottomless|bottomless female|topless|topless female|male topless|nude|naked|fully nude|fully naked|completely nude|completely naked|com pletely nude|compeltely nude)$/.test(
      normalized,
    )
  ) {
    return true;
  }
  if (/^(?:partially undressed|undressing|undressed|forced exposure)$/.test(normalized)) {
    return true;
  }
  if (/^(?:clothed|fully clothed|partially clothed)$/.test(normalized)) {
    return true;
  }
  return isClothingRelatedActionOrStateTerm(normalized);
}

function isClothingRelatedActionOrStateTerm(normalized) {
  if (!containsGarmentOrClothingToken(normalized)) return false;
  return (
    /\b(aside|pulled aside|pull aside|pull(?:ed|ing)?|lift(?:ed|ing)?|tug(?:ged|ging)?|open(?:ed|ing)?|unbutton(?:ed|ing)?|take off|taking off|remov(?:e|ed|ing)|tear(?:ing)?|torn|ripped|damaged|shredded|burn(?:ed|t)|burning|dirt|wet|soaked|stained|dirty|muddy|bloodstained|transparent|see through|see-through|yank(?:ed|ing)?(?: down)?|down|off|slip(?:ped|ping)?|flip(?:ped|ping)?|around one leg|on floor|on the floor|at floor|around waist|discarded|unworn|dropped|scattered|holding|in hand)\b/.test(
      normalized,
    ) ||
    /\b(?:through|under|over|inside)\s+clothes?\b/.test(normalized) ||
    /\b(?:fire|dirt|mud|blood)\s+on\s+clothes?\b/.test(normalized) ||
    /\b(breasts? out|one breast out|open clothes|open shirt|open jacket|open kimono|open towel|partially undressed)\b/.test(
      normalized,
    ) ||
    /(脱衣|脱ぎ|脱い|脱げ|脱が|破れ|破損|破损|裂け|撕裂|濡れ|湿|濕|汚れ|污|ずらし|ずらされ|めく|捲|開き|開け|はだけ|半脱ぎ|拉开|拉開|掀起|脱下|未穿|拿着)/.test(
      normalized,
    )
  );
}

function containsGarmentOrClothingToken(normalized) {
  if (normalized === 'top') return true;
  if (
    /\b(clothes?|clothing|outfits?|costumes?|attire|apparel|garb|shirt|blouse|halter top|crop top|tank top|bikini top|bra|bikini(?: bottom)?|swimsuits?|swimwear|one piece swimsuit|leotard|bodysuit|dress|skirt|kimono|yukata|uniform|serafuku|jacket|coat|hoodie|hood|bunny suit|bunny outfit|maid outfit|suit|pant(?:y|ies)|underwear|underclothes|lingerie|pants|shorts|stockings?|pantyhose|thighhighs?|socks?|shoes?|footwear|boots?|sneakers?|sandals?|heels?|legwear|towel|strap|sleeves?|garter|robe|apron|armor|vest|cloak|blazer|sweater)\b/.test(
      normalized,
    )
  ) {
    return true;
  }
  return /(服饰|服飾|服装|服裝|衣服|衣装|衣裝|衣裳|衣類|衣类|制服|校服|水着|泳装|泳裝|浴衣|和服|着物|メイド服|メイド衣装|下着|パンツ|ブラジャー|靴下|靴|ブーツ|スカート|シャツ|ブラウス|ワンピース|コスチューム|衣裳)/.test(
    normalized,
  );
}

function isCrossSubjectClothingCompositionTerm(normalized) {
  return /\bclothed (?:female|girl|woman|male|boy|man) nude (?:female|girl|woman|male|boy|man)\b/.test(
    normalized,
  );
}

function isNonClothingPhraseWithClothingToken(normalized) {
  if (/^(?:top down bottom up|top-down bottom-up)$/.test(normalized)) return true;
  if (/\b(?:girl|boy|woman|man|female|male)\s+on\s+top\b/.test(normalized)) {
    return true;
  }
  if (/\bdry(?:ing)?\s+with\s+(?:a\s+)?towel\b/.test(normalized)) return true;
  return false;
}

function isOtherCharacterClothingActionTag(tag) {
  return /\b(unbuttoning|removing|tearing|pulling|lifting|grabbing)\b.*\b(?:other|another|girl)(?:'?s| s)?\b.*\b(shirt|bra|skirt|dress|pant(?:y|ies)|underwear|bikini|clothes|pantyhose|stockings?|thighhighs?|socks?|legwear)\b/.test(
    tag,
  );
}

function isKnownFranchiseCharacterTag(tag, normalized) {
  const raw = stringValue(tag);
  if (!/[_\s]*\([^)]{3,}\)/.test(raw) || /^artist[:\s]/i.test(raw)) {
    return false;
  }
  return /\b(fate|princess connect|blue archive|azur lane|genshin impact|honkai|star rail|arknights|granblue fantasy|zenless zone zero|re zero|date a live|hololive|idolmaster|girls frontline|touhou|kancolle|umamusume|flower knight girl|black survival)\b/.test(
    normalized,
  );
}

function isVariantNamedCharacterTag(tag) {
  const text = stringValue(tag).trim();
  const match = text.match(/^([a-z][a-z _-]{1,40})[_\s]*\(([^)]{3,})\)$/i);
  if (!match || /^artist[:\s]/i.test(text)) return false;
  const canonical = normalizedTagKey(match[1]);
  const variant = normalizedTagKey(match[2]);
  if (!/^[a-z]+(?:\s+[a-z]+){0,3}$/.test(canonical)) return false;
  if (containsGarmentOrClothingToken(canonical)) return false;
  return /\b(swimsuit|bikini|dress|uniform|kimono|yukata|maid|costume|outfit|casual|summer|winter|school)\b/.test(
    variant,
  );
}

function isScenePromptTerm(tag) {
  const normalized = normalizedTagKey(tag);
  if (!normalized) return false;
  if (containsGarmentOrClothingToken(normalized)) return false;
  if (
    /\b(princess connect|blue archive|azur lane|genshin impact|honkai|star rail|arknights|granblue fantasy|zenless zone zero|re zero|date a live|hololive|idolmaster|touhou|pokemon|fate)\b/.test(
      normalized,
    )
  ) {
    return false;
  }
  if (
    /\b(hair|eyes?|iris|pupil|ears?|horns?|halo|fangs?|skin|face|hat|cap|ornament|headdress|headwear|jewelry|earrings?|necklace|choker|collar|ribbon|bow|twintails?|ponytail|pigtails?|braids?|bangs|hairclip|hairband|glasses|crown|bracelet|tattoo|mole|cleavage|collarbone|shoulders?|armpits?|chest|breasts?|bust|midriff|abs|thighs?|legs?|feet|toes?|hips?|waist|navel|stomach)\b/.test(
      normalized,
    )
  ) {
    return false;
  }
  return /\b(bathroom|bath|bathtub|shower|onsen|hot spring|workshop|factory|garage|mechanic|school|classroom|train|subway|station|street|city|bedroom|bed|indoors|outdoors)\b/.test(
    normalized,
  );
}

function parseTags(text) {
  return stripNegativeWeightedGroups(stringValue(text))
    .replace(/\r?\n/g, ',')
    .replace(/::\s*[+-]?\d+(?:\.\d+)?\s*::/g, ',')
    .replace(/::+/g, ',')
    .replace(/[\uFF0C\u3001\uFF1B]/g, ',')
    .replace(/[锛屻€侊紱;|]+/g, ',')
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
  text = text.replace(/^["']|["']$/g, '').trim();
  if (/^-\d+(?:\.\d+)?\s*::\s*/.test(text)) return '';
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
  const weighted = text.match(/^\((.*):([+-]?\d+(?:\.\d+)?)\)$/);
  if (weighted) {
    if (Number(weighted[2]) <= 0) return '';
    text = weighted[1].trim();
  }
  let unwrapped = true;
  while (unwrapped) {
    const next = text.match(/^\(([^()]+)\)$/);
    if (!next) {
      unwrapped = false;
    } else {
      text = next[1].trim();
    }
  }
  return text.replace(/\s+/g, ' ').trim();
}

function normalizedTagKey(value) {
  return stringValue(value)
    .toLowerCase()
    .replace(/[_-]+/g, ' ')
    .replace(/[(){}\[\]'":!?锛屻€侊紱;]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function sample(fileReport, item) {
  if (fileReport.samples.length < 30) {
    fileReport.samples.push(item);
  }
}

function stringValue(value) {
  return value == null ? '' : String(value);
}

function parseArgs(args) {
  const values = {};
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    if (index + 1 < args.length && !args[index + 1].startsWith('--')) {
      values[toCamel(key)] = args[index + 1];
      index += 1;
    } else {
      values[toCamel(key)] = true;
    }
  }
  return values;
}

function toCamel(value) {
  return value.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
}
