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

const targetNames = new Set([
  'ユニ 売春援交',
  'ラビットハウスの裏メニュー',
  'レイ 寝取られ',
  'レム&ラム 常識改変',
  '三月なのか 飲酒強姦',
  '丹花イブキ 常識改変',
  '伊落マリー 寝取られ',
  '健身房寝取られ',
  '八重神子&雷電将軍 クソガキ',
  '出張メイド シリアス 寝取られ',
  '初音ミク 常識改変',
  '婦警キョウカ 敗北',
  '敗北ヒロイン ペコリーヌ (前)_合并5个图集',
  '早瀬ユウカ 寝取られ',
  '月雪ミヤコ 寝取られ',
  '枕営業 ネネカ',
  '淫乱に染まった「四糸乃」',
  '淫乱シスター クリア',
  '甘雨 寝取られ',
  '発情剤を飲んでしまった キョウカ',
  '神里綾華 悪堕ち調教',
  '空井サキ 催眠にかけて奈落',
  '篠澤広 パパ活',
  '胡桃は 護摩の杖が ほしいです！',
  '花火 寝取られ (上)_合并2个图集',
  '西住まほ 常識改変洗脳',
  '资金难',
  '重音テト 催眠',
  '銀狼 寝取られ',
  '風紀委員会長 悪堕記 (上)_合并2个图集',
  '食い逃げ ペコリーヌ',
]);

const options = parseArgs(process.argv.slice(2));
const assignmentPath =
  options.assignment ?? 'build/ntr_story_new_cache_ids_20260610.json';
const cacheDir = options.cacheDir ?? defaultCacheDir;
const classificationPath =
  options.classificationCache ?? 'E:/NAI的脚本群/tag_classification_cache.json';
const reportPath =
  options.report ?? 'build/ntr_story_ai2_role_cache_fill_20260610.json';

if (!fs.existsSync(assignmentPath)) {
  throw new Error(`Missing assignment list: ${assignmentPath}`);
}
if (!fs.existsSync(cacheDir)) {
  throw new Error(`Missing active cache dir: ${cacheDir}`);
}

const classificationCache = loadClassificationCache(classificationPath);
const rows = JSON.parse(fs.readFileSync(assignmentPath, 'utf8'));
const selectedRows = rows.filter(
  (row) => stringValue(row.status) === '' && targetNames.has(row.name),
);

if (selectedRows.length !== 31) {
  throw new Error(`Expected 31 AI-2 empty rows, got ${selectedRows.length}`);
}

const summary = {
  apply: options.apply,
  worker: 'AI-2',
  assignment_path: path.resolve(assignmentPath),
  cache_dir: cacheDir,
  classification_cache: classificationPath,
  files_selected: selectedRows.length,
  files_changed: 0,
  ready_count: 0,
  role_count: 0,
  stage_count: 0,
  required_slot_count: 0,
  covered_slot_count: 0,
  base_global_roles: 0,
  attention_items: 0,
  unassigned_terms: 0,
  missing_metadata_frames: 0,
  files: [],
};

for (const row of selectedRows) {
  const filePath = path.join(cacheDir, row.file);
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing active cache file: ${filePath}`);
  }
  const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  if (cache.scriptId !== row.id || cache.scriptName !== row.name) {
    throw new Error(
      `Cache mismatch for ${row.file}: expected ${row.id}/${row.name}, got ${cache.scriptId}/${cache.scriptName}`,
    );
  }

  const original = JSON.stringify(cache);
  const extraction = buildExtraction(cache, row);
  cache.aiRoleExtraction = extraction;

  const fileReport = summarizeCache(cache, row);
  summary.files.push(fileReport);
  summary.ready_count += extraction.status === 'ready' ? 1 : 0;
  summary.role_count += extraction.roles.length;
  summary.stage_count += extraction.roles.reduce(
    (total, role) => total + role.stages.length,
    0,
  );
  summary.required_slot_count += fileReport.required_slots;
  summary.covered_slot_count += fileReport.covered_slots;
  summary.base_global_roles += fileReport.base_global_roles;
  summary.attention_items += extraction.attention_items.length;
  summary.unassigned_terms += extraction.unassigned_terms.length;
  summary.missing_metadata_frames += fileReport.missing_metadata_frames;

  if (JSON.stringify(cache) !== original) {
    summary.files_changed += 1;
    if (options.apply) {
      fs.writeFileSync(filePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
    }
  }
}

fs.mkdirSync(path.dirname(reportPath), { recursive: true });
fs.writeFileSync(reportPath, `${JSON.stringify(summary, null, 2)}\n`, 'utf8');
console.log(JSON.stringify(summary, null, 2));

function buildExtraction(cache, row) {
  const roleBuilders = new Map();
  const unassigned = new Map();
  const attentionItems = [];
  const frames = Array.isArray(cache.scriptSnapshot?.frames)
    ? cache.scriptSnapshot.frames
    : [];

  for (const frame of frames) {
    if (!isParsedFrame(frame)) continue;
    const frameIndex = numberValue(frame.index);
    if (frameIndex == null) continue;
    if (
      frame?.parsed?.sourcePayload?.source_kind ===
      'png_metadata_missing_frame'
    ) {
      attentionItems.push({
        frame_index: frameIndex,
        issue: 'png_metadata_missing_frame',
        note: 'Frame has no local PNG metadata; no role fields inferred.',
      });
      continue;
    }
    const captions = Array.isArray(frame.parsed?.charCaptions)
      ? frame.parsed.charCaptions
      : [];
    captions.forEach((caption, slot) => {
      if (!stringValue(caption).trim()) return;
      const sourceId = `slot-${slot}`;
      const terms = splitPromptTerms(caption);
      const parts = routeTerms(terms, unassigned, cache.scriptName);
      const identityKey = roleKeyForParts(parts, slot);
      const role = ensureRole(roleBuilders, identityKey, parts, sourceId, slot);
      role.frameIndexes.add(frameIndex);
      if (!role.appearances.has(sourceId)) role.appearances.set(sourceId, []);
      role.appearances.get(sourceId).push(frameIndex);

      const signature = partsSignature(parts);
      if (!role.stages.has(signature)) {
        role.stages.set(signature, {
          parts,
          sourceIds: new Set(),
          frameIndexes: [],
        });
      }
      const stage = role.stages.get(signature);
      stage.frameIndexes.push(frameIndex);
      stage.sourceIds.add(sourceId);
    });
  }

  const roles = [...roleBuilders.values()]
    .sort((left, right) => {
      const leftMin = Math.min(...left.frameIndexes);
      const rightMin = Math.min(...right.frameIndexes);
      return leftMin - rightMin || left.slot - right.slot;
    })
    .map((builder, index) => materializeRole(builder, index));

  return {
    schema_version: 1,
    status: 'ready',
    chunk_id: 'manual-ai-2-20260610',
    confidence: roles.length > 0 ? 0.86 : 0,
    roles,
    attention_items: dedupeAttentionItems(attentionItems),
    unassigned_terms: [],
  };
}

function ensureRole(roleBuilders, key, parts, sourceId, slot) {
  if (!roleBuilders.has(key)) {
    roleBuilders.set(key, {
      key,
      slot,
      sourceIds: new Set([sourceId]),
      displayName: displayNameForParts(parts, slot),
      canonicalName: canonicalNameForParts(parts, slot),
      rawIdentityTags: new Set(identityTagsForRaw(parts)),
      frameIndexes: new Set(),
      appearances: new Map(),
      stages: new Map(),
      isSourceSlot: key.startsWith('slot:'),
    });
  }
  const role = roleBuilders.get(key);
  role.sourceIds.add(sourceId);
  for (const term of identityTagsForRaw(parts)) role.rawIdentityTags.add(term);
  if (/^Source slot \d+$/u.test(role.displayName)) {
    const identity = parts.identity.find(Boolean);
    if (identity) {
      role.displayName = titleFromIdentity(identity);
      role.canonicalName = cleanPromptTerm(identity);
    }
  }
  return role;
}

function materializeRole(builder, index) {
  const roleId = builder.isSourceSlot
    ? `role-source-slot-${builder.slot}`
    : `role-${slug(builder.canonicalName || builder.displayName || `role-${index}`)}`;
  const frameIndexes = sortedInts([...builder.frameIndexes]);
  const appearances = [...builder.appearances.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([sourceId, values]) => ({
      source_id: sourceId,
      source_kind: 'slot',
      frame_indexes: sortedInts(values),
    }));
  const stages = [...builder.stages.values()]
    .sort((left, right) => {
      const leftMin = Math.min(...left.frameIndexes);
      const rightMin = Math.min(...right.frameIndexes);
      return leftMin - rightMin;
    })
    .map((stage, stageIndex) =>
      materializeStage(roleId, stage, builder.displayName, stageIndex),
    );
  const evidenceTerms = uniqueTerms(
    stages.flatMap((stage) => stage.evidence_terms),
  );
  const rawIdentityTags = uniqueTerms([...builder.rawIdentityTags]).filter(
    (term) => evidenceTerms.some((evidence) => termKey(evidence) === termKey(term)),
  );
  return {
    source_role_id: roleId,
    source_kind: builder.sourceIds.size > 1 ? 'cross_slot' : 'slot',
    display_name: builder.displayName,
    role_reason: builder.isSourceSlot
      ? `Conservative local source-slot role for ${[...builder.sourceIds].sort().join(', ')}; no stable named character identity was inferred.`
      : `Local character tag evidence grouped from ${[...builder.sourceIds].sort().join(', ')}.`,
    canonical_name: builder.canonicalName,
    franchise: franchiseFromIdentity(rawIdentityTags[0] ?? ''),
    raw_identity_tags: rawIdentityTags,
    variant_tags: [],
    merge_with_role_id: '',
    confidence: builder.isSourceSlot ? 0.62 : 0.9,
    frame_indexes: frameIndexes,
    appearances,
    evidence_terms: evidenceTerms,
    warnings: [],
    stages,
    unassigned_terms: [],
  };
}

function materializeStage(roleId, stage, displayName, stageIndex) {
  const parts = stage.parts;
  const frameIndexes = sortedInts(stage.frameIndexes);
  const evidenceTerms = stableEvidenceTerms(parts);
  const label = labelForParts(parts, displayName);
  return {
    stage_id: `${roleId}-stage-${stageIndex + 1}`,
    label,
    appearance_group_id: slug(label || `${roleId}-stage-${stageIndex + 1}`),
    merge_with_stage_ids: [],
    field_reasons: fieldReasons(parts),
    confidence: evidenceTerms.length > 0 ? 0.86 : 0.55,
    frame_indexes: frameIndexes,
    identity: parts.identity.join(', '),
    upper_body: parts.upperBody.join(', '),
    lower_body: parts.lowerBody.join(', '),
    upper_clothing: parts.upperClothing.join(', '),
    lower_clothing: parts.lowerClothing.join(', '),
    evidence_terms: evidenceTerms,
    missing_fields: missingFields(parts),
    warnings: [],
  };
}

function routeTerms(terms, unassigned, scriptName) {
  const parts = {
    identity: [],
    upperBody: [],
    lowerBody: [],
    upperClothing: [],
    lowerClothing: [],
  };
  const seen = new Set();
  for (const term of terms) {
    const clean = cleanPromptTerm(term);
    const key = termKey(clean);
    if (!key || shouldDropTerm(clean)) continue;
    const bucket = routeTerm(clean);
    if (!bucket) {
      if (isPossiblyStableButUnrouted(clean)) {
        const recordKey = `${scriptName}\u001f${clean}`;
        if (!unassigned.has(recordKey)) {
          unassigned.set(recordKey, { term: clean, script: scriptName });
        }
      }
      continue;
    }
    const dedupeKey = `${bucket}\u001f${key}`;
    if (seen.has(dedupeKey) || seen.has(key)) continue;
    seen.add(dedupeKey);
    seen.add(key);
    parts[bucket].push(clean);
  }
  return parts;
}

function routeTerm(term) {
  const category = classificationFor(term);
  if (shouldDropTerm(term)) return null;
  if (isLowerClothingTerm(term)) return 'lowerClothing';
  if (isUpperClothingTerm(term)) return 'upperClothing';
  if (isUpperBodyTerm(term)) return 'upperBody';
  if (isLowerBodyTerm(term)) return 'lowerBody';
  if (category === 'character' && isIdentityTerm(term)) return 'identity';
  if (isGenericIdentityTerm(term)) return 'identity';
  return null;
}

function roleKeyForParts(parts, slot) {
  const named = parts.identity.filter((term) => isNamedIdentityTerm(term));
  if (named.length > 0) {
    return `name:${named.map(termKey).sort().join('|')}`;
  }
  return `slot:${slot}`;
}

function displayNameForParts(parts, slot) {
  const named = parts.identity.find((term) => isNamedIdentityTerm(term));
  if (named) return titleFromIdentity(named);
  const identity = parts.identity.find(Boolean);
  if (identity) return titleFromIdentity(identity);
  return `Source slot ${slot}`;
}

function canonicalNameForParts(parts, slot) {
  const named = parts.identity.find((term) => isNamedIdentityTerm(term));
  if (named) return cleanPromptTerm(named);
  const identity = parts.identity.find(Boolean);
  if (identity) return cleanPromptTerm(identity);
  return `source-slot-${slot}`;
}

function identityTagsForRaw(parts) {
  return parts.identity.filter((term) => {
    const key = termKey(term);
    return key && !/^(1girl|1boy|girl|boy|man|woman|male|female)$/u.test(key);
  });
}

function isNamedIdentityTerm(term) {
  const key = termKey(term);
  if (!key || isGenericIdentityTerm(term)) return false;
  if (isBodyDescriptorTerm(term) || isGarmentTerm(term)) return false;
  if (/\b(hair|eyes?|pupils?|iris|ears?|tail|skin|breasts?|chest|fang|teeth|horns?)\b/u.test(key)) {
    return false;
  }
  return /[()]/u.test(term) || /^[a-z0-9]+(?: [a-z0-9]+){1,5}$/u.test(key);
}

function isIdentityTerm(term) {
  if (isGenericIdentityTerm(term)) return true;
  const key = termKey(term);
  if (!key || isBodyDescriptorTerm(term) || isGarmentTerm(term)) return false;
  if (/\b(hair|eyes?|pupils?|iris|ears?|tail|skin|breasts?|chest|fang|teeth|horns?)\b/u.test(key)) {
    return false;
  }
  if (categoryIsHardNonRole(classificationFor(term))) return false;
  return /[()]/u.test(term) || /^[a-z0-9]+(?: [a-z0-9]+){1,5}$/u.test(key);
}

function isGenericIdentityTerm(term) {
  const key = termKey(term);
  return /^(1girl|1boy|girl|boy|man|woman|male|female|faceless male|faceless female|muscular male|musclar male|fat man|fat male|old man|middle aged man|middle aged male|multiple boys|multiple girls)$/u.test(
    key,
  );
}

function shouldDropTerm(term) {
  const key = termKey(term);
  if (!key) return true;
  if (/^(none|null|nil|unknown|n\/a|empty|other|stage|slot|source slot)$/u.test(key)) {
    return true;
  }
  if (/^(pose|poses|action|actions|explicit|adult|nsfw|safe|safety|review|warning)$/u.test(key)) {
    return true;
  }
  if (/\b(in later frames|in some frames|where present|when present|only coverage|not consistently|varies by frame|if visible|when visible)\b/u.test(key)) {
    return true;
  }
  if (categoryIsHardNonRole(classificationFor(term))) return true;
  if (isGarmentTerm(term)) return false;
  if (isAdultStateTerm(term)) return true;
  return transientPattern().test(key);
}

function categoryIsHardNonRole(category) {
  return new Set(['artist', 'quality', 'scene', 'action', 'camera', 'style', 'promptSyntax']).has(
    category,
  );
}

function transientPattern() {
  return /\b(gym|exercise|workout|yoga pose|pose|push up|wooden floor|floor|bed|pillow|room|hallway|background|camera|pov|close up|from side|side view|dutch angle|looking|standing|sitting|kneeling|lying|running|walking|stretching|bending|squatting|spread legs|arms up|hands up|holding|grabbing|touching|hand over mouth|stun gun|toward another|fingering|sex|intercourse|masturbat|penetrat|cum|semen|orgasm|saliva|pussy|penis|nipples?|areola|navel|ass|butt|stomach bulge|thighs?|blush|nose blush|smile|open mouth|heavy breathing|tears|crying|angry|embarrassed|wet|sweaty|sweat|stained|torn|ripped|damaged|open towel|open clothes|taking off|take off|undressing|lifted|lifting|pulled|pulling|covered nipples|facial|leash handling|solo focus|solo|chair)\b/u;
}

function isAdultStateTerm(term) {
  const key = termKey(term);
  return /\b(nude|naked|topless|bottomless|nipples?|areola|pussy|penis|erection|sex|intercourse|cum|semen|orgasm|masturbat|penetrat|vaginal|anal|fellatio|paizuri|one breast out|covered nipples|underboob|sideboob|cameltoe|see through|wet|sweaty|torn|ripped|damaged|open clothes|undressing|taking off|clothes lift|shirt lift|skirt lift|panty pull|panties around|panties aside)\b/u.test(
    key,
  );
}

function isUpperBodyTerm(term) {
  const key = termKey(term);
  return /\b(hair|twintails?|twin tails?|ponytails?|braids?|headdress|ahoge|eyes?|ears?|horns?|halo|headband|headwear|hat|beret|ornament|ribbon|bow|tiara|necklace|choker|collar|earrings?|fang|teeth|breasts?|chest|skin|tattoo|mask)\b/u.test(
    key,
  );
}

function isLowerBodyTerm(term) {
  const key = termKey(term);
  return /\b(tail|legs?|feet|foot|anklet|thigh strap|toe|toes)\b/u.test(key);
}

function isUpperClothingTerm(term) {
  const key = termKey(term);
  return /\b(shirt|blouse|jacket|coat|overcoat|hoodie|sweater|dress|uniform|bra|bikini top|leotard|bodysuit|swimsuit|school swimsuit|one piece swimsuit|kimono|robe|armor|gloves?|sleeves?|sports bra|towel|mantle|cloak|cape|belt|strap|bowtie|necktie|tie|frills?|lingerie|outfit|costume|clothes|clothing|pajamas|tank top)\b/u.test(
    key,
  );
}

function isLowerClothingTerm(term) {
  const key = termKey(term);
  return /\b(pants|trousers|shorts|skirt|miniskirt|panties|underwear|briefs|leggings|stockings?|socks?|thighhighs?|pantyhose|garter|shoes?|boots?|sandals?|heels?|loafers?|footwear|legwear|bikini bottom|swimsuit bottom|fundoshi|pelvic curtain|mary janes?)\b/u.test(
    key,
  );
}

function isGarmentTerm(term) {
  return isUpperClothingTerm(term) || isLowerClothingTerm(term);
}

function isBodyDescriptorTerm(term) {
  return isUpperBodyTerm(term) || isLowerBodyTerm(term);
}

function isPossiblyStableButUnrouted(term) {
  const category = classificationFor(term);
  return !categoryIsHardNonRole(category) && !isAdultStateTerm(term);
}

function partsSignature(parts) {
  return [
    parts.identity.join('\u001f'),
    parts.upperBody.join('\u001f'),
    parts.lowerBody.join('\u001f'),
    parts.upperClothing.join('\u001f'),
    parts.lowerClothing.join('\u001f'),
  ].join('\u001e');
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

function missingFields(parts) {
  const result = [];
  if (parts.identity.length === 0) result.push('missing_identity');
  if (parts.upperBody.length === 0) result.push('missing_upper_body');
  if (parts.lowerBody.length === 0) result.push('missing_lower_body');
  if (parts.upperClothing.length === 0) result.push('missing_upper_clothing');
  if (parts.lowerClothing.length === 0) result.push('missing_lower_clothing');
  return result;
}

function labelForParts(parts, displayName) {
  const labelTerms = uniqueTerms([
    ...parts.upperClothing,
    ...parts.lowerClothing,
    ...parts.upperBody.filter((term) =>
      /collar|choker|headband|hat|ornament|tail/iu.test(term),
    ),
  ]).slice(0, 4);
  return labelTerms.length > 0 ? labelTerms.join(' / ') : displayName;
}

function fieldReasons(parts) {
  const result = {};
  for (const [field, values] of [
    ['identity', parts.identity],
    ['upper_body', parts.upperBody],
    ['lower_body', parts.lowerBody],
    ['upper_clothing', parts.upperClothing],
    ['lower_clothing', parts.lowerClothing],
  ]) {
    if (values.length > 0) {
      result[field] = 'Local source tag evidence from parsed charCaptions.';
    }
  }
  return result;
}

function titleFromIdentity(value) {
  const clean = cleanPromptTerm(value);
  return clean.replace(/\s*\([^)]*\)\s*/g, ' ').replace(/\s+/g, ' ').trim() || clean;
}

function franchiseFromIdentity(value) {
  const matches = [...stringValue(value).matchAll(/\(([^)]*)\)/g)].map(
    (match) => match[1],
  );
  return matches.length > 0 ? matches[matches.length - 1] : '';
}

function summarizeCache(cache, row) {
  const requiredSlots = requiredSlotKeys(cache);
  const coveredSlots = coveredSlotKeys(cache.aiRoleExtraction);
  const missingSlots = [...requiredSlots].filter((key) => !coveredSlots.has(key));
  const duplicateSlots = duplicateCoveredSlots(cache.aiRoleExtraction);
  return {
    file: row.file,
    id: row.id,
    name: row.name,
    frames: row.frames,
    roles: cache.aiRoleExtraction.roles.length,
    stages: cache.aiRoleExtraction.roles.reduce(
      (total, role) => total + role.stages.length,
      0,
    ),
    required_slots: requiredSlots.size,
    covered_slots: coveredSlots.size,
    missing_slots: missingSlots,
    duplicate_slots: duplicateSlots,
    base_global_roles: cache.aiRoleExtraction.roles.filter((role) =>
      role.appearances.some((appearance) => appearance.source_id === 'base/global'),
    ).length,
    attention_items: cache.aiRoleExtraction.attention_items.length,
    unassigned_terms: cache.aiRoleExtraction.unassigned_terms.length,
    missing_metadata_frames: (cache.scriptSnapshot?.frames ?? []).filter(
      (frame) =>
        frame?.parsed?.sourcePayload?.source_kind ===
        'png_metadata_missing_frame',
    ).length,
  };
}

function requiredSlotKeys(cache) {
  const result = new Set();
  for (const frame of Array.isArray(cache.scriptSnapshot?.frames)
    ? cache.scriptSnapshot.frames
    : []) {
    if (!isParsedFrame(frame)) continue;
    const frameIndex = numberValue(frame.index);
    const captions = Array.isArray(frame.parsed?.charCaptions)
      ? frame.parsed.charCaptions
      : [];
    captions.forEach((caption, slot) => {
      if (stringValue(caption).trim()) result.add(`${frameIndex}:slot-${slot}`);
    });
  }
  return result;
}

function coveredSlotKeys(extraction) {
  const result = new Set();
  for (const role of Array.isArray(extraction?.roles) ? extraction.roles : []) {
    for (const appearance of Array.isArray(role.appearances)
      ? role.appearances
      : []) {
      if (!/^slot-\d+$/u.test(stringValue(appearance.source_id))) continue;
      for (const frameIndex of Array.isArray(appearance.frame_indexes)
        ? appearance.frame_indexes
        : []) {
        result.add(`${frameIndex}:${appearance.source_id}`);
      }
    }
  }
  return result;
}

function duplicateCoveredSlots(extraction) {
  const counts = new Map();
  for (const role of Array.isArray(extraction?.roles) ? extraction.roles : []) {
    for (const appearance of Array.isArray(role.appearances)
      ? role.appearances
      : []) {
      if (!/^slot-\d+$/u.test(stringValue(appearance.source_id))) continue;
      for (const frameIndex of Array.isArray(appearance.frame_indexes)
        ? appearance.frame_indexes
        : []) {
        const key = `${frameIndex}:${appearance.source_id}`;
        counts.set(key, (counts.get(key) ?? 0) + 1);
      }
    }
  }
  return [...counts.entries()]
    .filter(([, count]) => count > 1)
    .map(([key]) => key);
}

function splitPromptTerms(value) {
  const source = stringValue(value);
  const terms = [];
  let current = '';
  let depth = 0;
  for (const char of source) {
    if ('([{'.includes(char)) depth += 1;
    if (')]}'.includes(char) && depth > 0) depth -= 1;
    if (char === ',' && depth === 0) {
      pushTerm(terms, current);
      current = '';
    } else {
      current += char;
    }
  }
  pushTerm(terms, current);
  return terms;
}

function pushTerm(terms, value) {
  const clean = cleanPromptTerm(value);
  if (clean) terms.push(clean);
}

function cleanPromptTerm(value) {
  return stringValue(value)
    .replace(/\b-?\d+(?:\.\d+)?::/g, '')
    .replace(/::/g, '')
    .replace(/[{}[\]]/g, '')
    .replace(/^[\s:|，、。]+|[\s:|，、。]+$/gu, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function termKey(value) {
  return cleanPromptTerm(value)
    .toLowerCase()
    .replace(/[_-]+/g, ' ')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function normalizedCacheKey(value) {
  const [prefix, ...parts] = String(value).split(':');
  return `${prefix}:${termKey(parts.join(':'))}`;
}

function classificationFor(term) {
  return classificationCache.get(`positive:${termKey(term)}`) ?? '';
}

function loadClassificationCache(filePath) {
  if (!fs.existsSync(filePath)) return new Map();
  const raw = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const result = new Map();
  for (const [key, value] of Object.entries(raw)) {
    if (value && typeof value.category === 'string') {
      result.set(normalizedCacheKey(key), value.category);
    }
  }
  return result;
}

function uniqueTerms(values) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    const clean = cleanPromptTerm(value);
    const key = termKey(clean);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(clean);
  }
  return result;
}

function sortedInts(values) {
  return [...new Set(values.map(Number).filter(Number.isInteger))].sort(
    (left, right) => left - right,
  );
}

function slug(value) {
  const ascii = termKey(value)
    .normalize('NFKD')
    .replace(/[^\x00-\x7F]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return ascii || `role-${Math.abs(hashString(String(value)))}`;
}

function hashString(value) {
  let hash = 0;
  for (let index = 0; index < value.length; index += 1) {
    hash = (hash * 31 + value.charCodeAt(index)) | 0;
  }
  return hash;
}

function dedupeAttentionItems(items) {
  const seen = new Set();
  const result = [];
  for (const item of items) {
    const key = JSON.stringify(item);
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(item);
  }
  return result;
}

function isParsedFrame(frame) {
  return (
    stringValue(frame?.parseStatus ?? frame?.parse_status).toLowerCase() ===
    'parsed'
  );
}

function numberValue(value) {
  const number = Number(value);
  return Number.isInteger(number) ? number : null;
}

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}

function parseArgs(args) {
  const parsed = {
    apply: false,
    assignment: undefined,
    cacheDir: undefined,
    classificationCache: undefined,
    report: undefined,
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
    if (key === 'assignment') parsed.assignment = value;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'classification-cache') parsed.classificationCache = value;
    if (key === 'report') parsed.report = value;
  }
  return parsed;
}
