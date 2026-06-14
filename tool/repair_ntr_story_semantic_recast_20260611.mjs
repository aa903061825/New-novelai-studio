import fs from 'node:fs';
import path from 'node:path';

const FIELD_KEYS = [
  'identity',
  'upper_body',
  'lower_body',
  'upper_clothing',
  'lower_clothing',
];

const BANNED_FIELD_TERM_KEYS = new Set([
  'adjusting hair',
  'averting eyes',
  'avertising eyes',
  'bound legs',
  'breasts squeezed together',
  'covering one eye',
  'covering eyes',
  'dashed eyes',
  'feet up',
  'fingering through clothes',
  'foot on another',
  "foot on another's face",
  'hair spread out',
  "hands in another's clothes",
  'hands on another',
  "hands on another's clothes",
  "hands on another's legs",
  'hands on skirt',
  'heart in eye',
  'heart in eyes',
  'leg hold',
  'leg lock',
  'legs behind head',
  'm legs',
  'fetal position',
  'imminent attack',
  'narrowed eyes',
  'one breast out',
  'pants pull',
  'pantyhose pull',
  'partially submerged',
  'presenting removed panties',
  'presenting_removed_panties',
  'shirt lift',
  'sideways glance',
  'strap slip',
  'strap slips',
  'swimsuit pull',
  'one piece swimsuit pull',
  'tail grab',
  'uneven eyes',
  'upturned eyes',
  'upright straddle',
  'washing hair',
]);

const options = parseArgs(process.argv.slice(2));
const cacheDir = options.cacheDir;
if (!cacheDir) {
  throw new Error('Missing --cache-dir');
}
if (!fs.existsSync(cacheDir)) {
  throw new Error(`Missing cache dir: ${cacheDir}`);
}

const reportPath =
  options.report ?? path.join('build', 'ntr_story_semantic_recast_20260611.json');
const backupDir =
  options.backupDir ??
  path.join('build', 'ntr_story_semantic_recast_backup_20260611');
const tagClassification = loadTagClassification();
const onlyFiles = options.onlyFiles
  ? new Set(options.onlyFiles.split(',').map((value) => value.trim()).filter(Boolean))
  : null;

const files = fs
  .readdirSync(cacheDir)
  .filter((file) => /^script-.*\.json$/u.test(file))
  .filter((file) => !onlyFiles || onlyFiles.has(file))
  .sort();

const summary = {
  cache_dir: cacheDir,
  apply: options.apply,
  files_scanned: files.length,
  files_changed: 0,
  old_role_count: 0,
  new_role_count: 0,
  old_stage_count: 0,
  new_stage_count: 0,
  attention_items_added: 0,
  generic_roles_remaining: 0,
  files: [],
};

for (const fileName of files) {
  const filePath = path.join(cacheDir, fileName);
  const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const before = JSON.stringify(cache);
  const oldRoles = Array.isArray(cache.aiRoleExtraction?.roles)
    ? cache.aiRoleExtraction.roles
    : [];
  const oldRoleCount = oldRoles.length;
  const oldStageCount = oldRoles.reduce(
    (count, role) => count + (Array.isArray(role.stages) ? role.stages.length : 0),
    0,
  );

  const repair = rebuildRoles(cache, fileName);
  if (!cache.aiRoleExtraction || typeof cache.aiRoleExtraction !== 'object') {
    cache.aiRoleExtraction = {};
  }
  cache.aiRoleExtraction.schema_version =
    cache.aiRoleExtraction.schema_version ?? 'script-recast-ai-cache-v1';
  cache.aiRoleExtraction.status = 'ready';
  cache.aiRoleExtraction.roles = repair.roles;
  cache.aiRoleExtraction.attention_items = mergeAttentionItems(
    cache.aiRoleExtraction.attention_items,
    repair.attentionItems,
  );
  cache.aiRoleExtraction.unassigned_terms = Array.isArray(
    cache.aiRoleExtraction.unassigned_terms,
  )
    ? cache.aiRoleExtraction.unassigned_terms
    : [];
  delete cache.aiRoleExtraction.raw_response;

  const newRoleCount = repair.roles.length;
  const newStageCount = repair.roles.reduce(
    (count, role) => count + (Array.isArray(role.stages) ? role.stages.length : 0),
    0,
  );
  const after = JSON.stringify(cache);
  const changed = before !== after;

  summary.old_role_count += oldRoleCount;
  summary.new_role_count += newRoleCount;
  summary.old_stage_count += oldStageCount;
  summary.new_stage_count += newStageCount;
  summary.attention_items_added += repair.attentionItems.length;
  summary.generic_roles_remaining += repair.genericRolesRemaining;

  const fileReport = {
    file_name: fileName,
    script_name: stringValue(cache.scriptName),
    changed,
    old_role_count: oldRoleCount,
    new_role_count: newRoleCount,
    old_stage_count: oldStageCount,
    new_stage_count: newStageCount,
    attention_items_added: repair.attentionItems.length,
    generic_roles_remaining: repair.genericRolesRemaining,
    roles: repair.roles.map((role) => ({
      source_role_id: role.source_role_id,
      display_name: role.display_name,
      source_kind: role.source_kind,
      frame_count: role.frame_indexes.length,
      appearance_count: role.appearances.length,
      stage_count: role.stages.length,
    })),
    attention_samples: repair.attentionItems.slice(0, 12),
  };
  summary.files.push(fileReport);

  if (changed) {
    summary.files_changed += 1;
    if (options.apply) {
      fs.mkdirSync(backupDir, { recursive: true });
      const backupPath = path.join(backupDir, fileName);
      if (!fs.existsSync(backupPath)) {
        fs.copyFileSync(filePath, backupPath);
      }
      fs.writeFileSync(filePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
    }
  }
}

fs.mkdirSync(path.dirname(reportPath), { recursive: true });
fs.writeFileSync(reportPath, `${JSON.stringify(summary, null, 2)}\n`, 'utf8');
console.log(JSON.stringify(summary, null, 2));

function rebuildRoles(cache, fileName) {
  const roleGroups = new Map();
  const attentionItems = [];
  const frames = Array.isArray(cache.scriptSnapshot?.frames)
    ? cache.scriptSnapshot.frames
    : [];

  for (const frame of frames) {
    const frameIndex = Number(frame.index);
    if (!Number.isFinite(frameIndex)) continue;
    const captions = Array.isArray(frame.parsed?.charCaptions)
      ? frame.parsed.charCaptions
      : [];
    captions.forEach((caption, slotIndex) => {
      const captionText = stringValue(caption);
      if (!captionText.trim()) return;
      const sourceId = `slot-${slotIndex}`;
      const occurrence = buildOccurrence(captionText, frameIndex, sourceId);
      if (occurrence.stableTerms.length === 0) {
        attentionItems.push({
          kind: 'unrouted_nonempty_char_caption',
          source_id: sourceId,
          frame_index: frameIndex,
          note: 'Non-empty charCaption had no stable identity/body/clothing terms after filtering.',
        });
      }
      const roleKey = roleGroupingKey(occurrence, sourceId);
      let group = roleGroups.get(roleKey.key);
      if (!group) {
        group = {
          key: roleKey.key,
          baseSourceId: sourceId,
          displayTerms: roleKey.displayTerms,
          genericOnly: roleKey.genericOnly,
          occurrences: [],
        };
        roleGroups.set(roleKey.key, group);
      }
      group.occurrences.push(occurrence);
    });
  }

  const usedIds = new Set();
  const roles = [];
  const groups = [...roleGroups.values()].sort(compareGroups);
  for (const group of groups) {
    const sourceRoleId = uniqueRoleId(roleIdForGroup(group), usedIds);
    const frameIndexes = uniqueNumbers(group.occurrences.map((item) => item.frameIndex));
    const appearances = buildAppearances(group.occurrences);
    const stages = buildStages(group.occurrences, sourceRoleId);
    const evidenceTerms = uniqueTerms(stages.flatMap((stage) => stage.evidence_terms));
    const displayName =
      group.displayTerms.find((term) => !isGenericDemographic(term)) ??
      group.displayTerms[0] ??
      sourceRoleId.replace(/^role-/u, '');
    if (group.genericOnly) {
      attentionItems.push({
        kind: 'generic_identity_only',
        role: sourceRoleId,
        display_name: displayName,
        frame_count: frameIndexes.length,
        note: 'Role has only generic source identity evidence; left unmerged outside its source slot/descriptors.',
      });
    }
    roles.push({
      source_role_id: sourceRoleId,
      source_kind: appearances.length > 1 ? 'cross_slot' : 'slot',
      display_name: displayName,
      canonical_name: displayName,
      franchise: '',
      confidence: group.genericOnly ? 0.72 : 0.86,
      frame_indexes: frameIndexes,
      appearances,
      stages,
      evidence_terms: evidenceTerms,
      raw_identity_tags: uniqueTerms(stages.flatMap((stage) => splitTerms(stage.identity))),
      variant_tags: [],
    });
  }

  const mergedRoles = mergeDuplicateNamedRoles(roles);
  const genericRolesRemaining = mergedRoles.filter((role) => {
    const name = termKey(role.display_name);
    return /^(girl|boy|male|female|man|woman|1girl|1boy)$/u.test(name);
  }).length;

  return { roles: mergedRoles, attentionItems, genericRolesRemaining, fileName };
}

function buildOccurrence(captionText, frameIndex, sourceId) {
  const routed = {
    identity: [],
    upper_body: [],
    lower_body: [],
    upper_clothing: [],
    lower_clothing: [],
  };
  const unknownStable = [];
  const seen = new Set();
  const sourceTerms = normalizeSourceTerms(splitTerms(captionText));
  for (let termIndex = 0; termIndex < sourceTerms.length; termIndex += 1) {
    const rawTerm = sourceTerms[termIndex];
    const term = cleanDisplayTerm(rawTerm);
    if (!term) continue;
    const route = routeTerm(term, { termIndex, terms: sourceTerms });
    if (!route) continue;
    const key = `${route}\u001f${termKey(term)}`;
    if (seen.has(key)) continue;
    seen.add(key);
    routed[route].push(term);
  }
  for (const field of FIELD_KEYS) {
    routed[field] = uniqueTerms(routed[field]);
  }
  return {
    frameIndex,
    sourceId,
    fields: routed,
    unknownStable,
    stableTerms: stableEvidenceTerms(routed),
  };
}

function routeTerm(term) {
  const key = termKey(term);
  if (!key || shouldDropTerm(key)) return null;
  if (isNamedCharacterTerm(term, key)) return 'identity';
  if (isLowerClothingTerm(key)) return 'lower_clothing';
  if (isUpperClothingTerm(key)) return 'upper_clothing';
  if (isLowerBodyTerm(key)) return 'lower_body';
  if (isUpperBodyTerm(key)) return 'upper_body';
  if (isIdentityTerm(term, key)) return 'identity';
  return null;
}

function roleGroupingKey(occurrence, sourceId) {
  const identity = occurrence.fields.identity;
  const named = identity.filter(
    (term) => !isGenericDemographic(term) && !isGenericMaleDescriptor(term),
  );
  const maleDescriptors = identity.filter(isGenericMaleDescriptor);
  if (named.length > 0) {
    const canonicalNamed = uniqueTerms(named.map(canonicalCharacterTerm));
    return {
      key: `named:${canonicalNamed.map(termKey).join('|')}`,
      displayTerms: [...canonicalNamed, ...identity.filter(isGenericDemographic)],
      genericOnly: false,
    };
  }
  if (maleDescriptors.length > 0) {
    const demographics = identity.filter(isGenericDemographic);
    const descriptorKey = genericDescriptorKey([...demographics, ...maleDescriptors]);
    const descriptorDisplay = genericDescriptorDisplay(maleDescriptors);
    return {
      key: `descriptor:${sourceId}:${descriptorKey}`,
      displayTerms: [...demographics, descriptorDisplay].filter(Boolean),
      genericOnly: false,
    };
  }
  const generic = identity.filter(isGenericDemographic);
  if (generic.length > 0) {
    return {
      key: `generic:${sourceId}:${generic.map(termKey).join('|')}`,
      displayTerms: generic,
      genericOnly: true,
    };
  }
  return {
    key: `unresolved:${sourceId}`,
    displayTerms: ['unresolved role'],
    genericOnly: true,
  };
}

function roleIdForGroup(group) {
  const display =
    group.displayTerms.find((term) => !isGenericDemographic(term)) ??
    group.displayTerms[0] ??
    group.baseSourceId;
  if (group.genericOnly) {
    return `role-source-${group.baseSourceId}-${slug(display)}`;
  }
  return `role-${slug(display)}`;
}

function canonicalCharacterTerm(term) {
  const clean = cleanDisplayTerm(term);
  const match = /^(.*?)\s*(\(.+\))\s*$/u.exec(clean);
  if (!match) return clean;
  const base = clean.slice(0, clean.indexOf('(')).trim();
  const parens = [...clean.matchAll(/\(([^)]+)\)/gu)].map((item) => item[1].trim());
  const franchise = parens.find(isFranchiseQualifier);
  return franchise ? `${base} (${franchise})` : base;
}

function isFranchiseQualifier(value) {
  const key = termKey(value);
  return /\b(princess connect|blue archive|genshin|honkai|star rail|azur lane|fate|date a live|girls und panzer|hololive|touhou|vocaloid|project sekai|arknights|umamusume|nikke|granblue|glanblue|kancolle|idolmaster|re:?zero|re zero|rezero)\b/u.test(
    key,
  );
}

function genericDescriptorKey(terms) {
  const keys = terms.map(termKey).join(' ');
  if (/\b(fat man|obese man|fat male)\b/u.test(keys)) return 'fat-man';
  if (/\b(very dark skinned|very dark-skinned|dark skinned|dark-skinned|black skin|african|afican|black man)\b/u.test(keys)) {
    return 'dark-skinned-male';
  }
  if (/\b(old man|middle aged man)\b/u.test(keys)) return 'old-man';
  if (/\b(faceless male)\b/u.test(keys)) return 'faceless-male';
  if (/\b(muscular male|musclar male|muscular|musclar)\b/u.test(keys)) return 'muscular-male';
  return terms.map(termKey).join('|') || 'generic-male';
}

function genericDescriptorDisplay(terms) {
  const key = genericDescriptorKey(terms);
  if (key === 'fat-man') return terms.find((term) => /fat|obese/i.test(term)) ?? 'fat man';
  if (key === 'dark-skinned-male') {
    return (
      terms.find((term) => /dark-skinned|dark skinned|very dark|black skin|african|afican/i.test(term)) ??
      'dark-skinned male'
    );
  }
  if (key === 'old-man') return terms.find((term) => /old|middle/i.test(term)) ?? 'old man';
  if (key === 'faceless-male') return terms.find((term) => /faceless/i.test(term)) ?? 'faceless male';
  if (key === 'muscular-male') {
    return terms.find((term) => /muscular|musclar/i.test(term)) ?? 'muscular male';
  }
  return terms[0] ?? '';
}

function uniqueRoleId(base, usedIds) {
  let candidate = base;
  let index = 2;
  while (usedIds.has(candidate)) {
    candidate = `${base}-${index}`;
    index += 1;
  }
  usedIds.add(candidate);
  return candidate;
}

function buildAppearances(occurrences) {
  const bySource = new Map();
  for (const occurrence of occurrences) {
    if (!bySource.has(occurrence.sourceId)) bySource.set(occurrence.sourceId, []);
    bySource.get(occurrence.sourceId).push(occurrence.frameIndex);
  }
  return [...bySource.entries()]
    .sort((a, b) => a[0].localeCompare(b[0]))
    .map(([sourceId, frameIndexes]) => ({
      source_id: sourceId,
      source_kind: 'slot',
      frame_indexes: uniqueNumbers(frameIndexes),
    }));
}

function buildStages(occurrences, sourceRoleId) {
  const byFields = new Map();
  for (const occurrence of occurrences) {
    const key = FIELD_KEYS.map((field) => occurrence.fields[field].join('\u001e')).join('\u001f');
    let group = byFields.get(key);
    if (!group) {
      group = { fields: occurrence.fields, frames: [] };
      byFields.set(key, group);
    }
    group.frames.push(occurrence.frameIndex);
  }
  return [...byFields.values()]
    .sort((a, b) => Math.min(...a.frames) - Math.min(...b.frames))
    .map((group, index) => {
      const fields = {};
      for (const field of FIELD_KEYS) fields[field] = group.fields[field].join(', ');
      const evidenceTerms = stableEvidenceTerms(fields);
      return {
        stage_id: `${sourceRoleId}-stage-${index + 1}`,
        label: labelForStage(fields),
        appearance_group_id: slug(labelForStage(fields) || fields.identity || `${index + 1}`),
        merge_with_stage_ids: [],
        field_reasons: fieldReasons(fields),
        confidence: 0.84,
        frame_indexes: uniqueNumbers(group.frames),
        identity: fields.identity,
        upper_body: fields.upper_body,
        lower_body: fields.lower_body,
        upper_clothing: fields.upper_clothing,
        lower_clothing: fields.lower_clothing,
        evidence_terms: evidenceTerms,
        missing_fields: missingFields(fields),
        warnings: [],
      };
    });
}

function mergeDuplicateNamedRoles(roles) {
  const usedIds = new Set();
  const groups = new Map();
  const ordered = [];
  for (const role of roles) {
    const key = namedMergeKey(role);
    if (!key) {
      const cloned = structuredClone(role);
      cloned.source_role_id = uniqueRoleId(cloned.source_role_id, usedIds);
      ordered.push(cloned);
      continue;
    }
    let group = groups.get(key);
    if (!group) {
      group = [];
      groups.set(key, group);
      ordered.push(group);
    }
    group.push(role);
  }

  return ordered.map((entry) => {
    if (!Array.isArray(entry)) return entry;
    const first = entry[0];
    const sourceRoleId = uniqueRoleId(roleIdForDisplay(first.display_name), usedIds);
    const appearances = mergeAppearances(entry.flatMap((role) => role.appearances ?? []));
    const stages = mergeStagesForRole(
      entry.flatMap((role) => role.stages ?? []),
      sourceRoleId,
    );
    const frameIndexes = uniqueNumbers(entry.flatMap((role) => role.frame_indexes ?? []));
    const evidenceTerms = uniqueTerms(stages.flatMap((stage) => stage.evidence_terms ?? []));
    return {
      ...first,
      source_role_id: sourceRoleId,
      source_kind: appearances.length > 1 ? 'cross_slot' : 'slot',
      frame_indexes: frameIndexes,
      appearances,
      stages,
      evidence_terms: evidenceTerms,
      raw_identity_tags: uniqueTerms(stages.flatMap((stage) => splitTerms(stage.identity))),
      variant_tags: uniqueTerms(entry.flatMap((role) => role.variant_tags ?? [])),
    };
  });
}

function namedMergeKey(role) {
  const name = termKey(role.display_name);
  if (!name || name === 'unresolved role') return null;
  if (isGenericDemographic(name) || isGenericMaleDescriptor(name)) return null;
  if (/^role-source-slot-/u.test(stringValue(role.source_role_id))) return null;
  return name;
}

function roleIdForDisplay(displayName) {
  return `role-${slug(displayName)}`;
}

function mergeAppearances(appearances) {
  const bySource = new Map();
  for (const appearance of appearances) {
    const sourceId = stringValue(appearance.source_id);
    if (!sourceId) continue;
    if (!bySource.has(sourceId)) bySource.set(sourceId, []);
    bySource.get(sourceId).push(...(appearance.frame_indexes ?? []));
  }
  return [...bySource.entries()]
    .sort((a, b) => a[0].localeCompare(b[0]))
    .map(([sourceId, frameIndexes]) => ({
      source_id: sourceId,
      source_kind: 'slot',
      frame_indexes: uniqueNumbers(frameIndexes),
    }));
}

function mergeStagesForRole(stages, sourceRoleId) {
  const byFields = new Map();
  for (const stage of stages) {
    const fields = {};
    for (const field of FIELD_KEYS) fields[field] = stringValue(stage[field]);
    const key = FIELD_KEYS.map((field) => fields[field]).join('\u001f');
    let group = byFields.get(key);
    if (!group) {
      group = { fields, frames: [] };
      byFields.set(key, group);
    }
    group.frames.push(...(stage.frame_indexes ?? []));
  }
  return [...byFields.values()]
    .sort((a, b) => Math.min(...a.frames) - Math.min(...b.frames))
    .map((group, index) => {
      const evidenceTerms = stableEvidenceTerms(group.fields);
      return {
        stage_id: `${sourceRoleId}-stage-${index + 1}`,
        label: labelForStage(group.fields),
        appearance_group_id: slug(labelForStage(group.fields) || group.fields.identity || `${index + 1}`),
        merge_with_stage_ids: [],
        field_reasons: fieldReasons(group.fields),
        confidence: 0.84,
        frame_indexes: uniqueNumbers(group.frames),
        identity: group.fields.identity,
        upper_body: group.fields.upper_body,
        lower_body: group.fields.lower_body,
        upper_clothing: group.fields.upper_clothing,
        lower_clothing: group.fields.lower_clothing,
        evidence_terms: evidenceTerms,
        missing_fields: missingFields(group.fields),
        warnings: [],
      };
    });
}

function compareGroups(a, b) {
  const af = Math.min(...a.occurrences.map((item) => item.frameIndex));
  const bf = Math.min(...b.occurrences.map((item) => item.frameIndex));
  return af - bf || a.key.localeCompare(b.key);
}

function fieldReasons(fields) {
  const result = {};
  for (const field of FIELD_KEYS) {
    if (stringValue(fields[field]).trim()) {
      result[field] = 'Local source tag evidence from parsed charCaptions.';
    }
  }
  return result;
}

function missingFields(fields) {
  const result = [];
  for (const field of FIELD_KEYS) {
    if (!stringValue(fields[field]).trim()) result.push(`missing_${field}`);
  }
  return result;
}

function labelForStage(fields) {
  const terms = [
    ...splitTerms(fields.upper_clothing),
    ...splitTerms(fields.lower_clothing),
    ...splitTerms(fields.upper_body).filter((term) =>
      /\b(collar|choker|headband|hat|headdress|halo|horn|ears?|tail|ribbon|bow)\b/iu.test(term),
    ),
    ...splitTerms(fields.lower_body).filter((term) => /\b(tail|anklet)\b/iu.test(term)),
  ];
  return uniqueTerms(terms).slice(0, 4).join(' / ');
}

function stableEvidenceTerms(parts) {
  return uniqueTerms([
    ...splitTerms(parts.identity),
    ...splitTerms(parts.upper_body),
    ...splitTerms(parts.lower_body),
    ...splitTerms(parts.upper_clothing),
    ...splitTerms(parts.lower_clothing),
  ]);
}

function mergeAttentionItems(existing, additions) {
  const result = Array.isArray(existing) ? [...existing] : [];
  const seen = new Set(result.map((item) => JSON.stringify(item)));
  for (const item of additions) {
    const key = JSON.stringify(item);
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(item);
  }
  return result;
}

function shouldDropTerm(key) {
  if (/^(none|null|nil|unknown|n\/a|empty|other)$/u.test(key)) return true;
  if (BANNED_FIELD_TERM_KEYS.has(key)) return true;
  if (isPureFranchiseQualifierKey(key)) return true;
  if (/^(african|afican)$/u.test(key)) return true;
  if (/^(teamwork|teamwork \(sexual\)|recruitment|recruitment \(blue archive\))$/u.test(key)) {
    return true;
  }
  if (/^(solo|duo|trio|multiple views|artist name|signature|watermark)$/u.test(key)) return true;
  if (
    /\b(pose|standing|sitting|kneeling|lying|running|walking|bending|squatting|jumping|from |view|pov|camera|close up|zoom|focus|out of frame|background|indoors?|outdoors?|bed|floor|wall|room|gym|train|desk|chair|table)\b/u.test(
      key,
    )
  ) {
    return true;
  }
  if (
    /\b(looking|staring|smile|open mouth|closed mouth|half closed|one eye closed|closed eyes|empty eyes|dashed eyes|rolling eyes|shading eyes|covering eyes|covering one eye|heart shaped pupils|heart-shaped pupils|tears?|crying|angry|annoyed|blush|sweat|saliva|drool|spoken|speech|sound effect|motion lines|shaded face|anger vein|embarrassed|surprised|scared|pain|upper teeth only)\b/u.test(
      key,
    )
  ) {
    return true;
  }
  if (
    /\b(holding|grabbing|groping|touching|hug|hugging|kiss|lick|licking|suck|sucking|breast sucking|breast press|bouncing breast|bouncing breasts|ears? licking|licking ears?|leg grab|legs grab|leg up|legs up|leg lift|legs together|legs apart|knees to chest|hand between legs|hair grab|covering own eyes|head between|undress|undressing|taking off|lifting|lifted|pulling|spreading|spread legs|spraed legs|m legs|arms up|hands up|hand on|hands on|hands in|tray|condom|magic wand|hitachi magic wand|panties around|holding panties|skirt lift|shorts pull|pants pull|pantyhose pull|shirt pull|clothes pull)\b/u.test(
      key,
    )
  ) {
    return true;
  }
  if (
    /\b(sex|sexual|intercourse|rape|fellatio|paizuri|masturbat|penetrat|cum|semen|ejaculat|orgasm|pussy|penis|erection|vibrator|sex toy|toy|pubic|nipples?|areola|breasts out|ass|butt|navel|stomach bulge|bouncing breasts)\b/u.test(
      key,
    )
  ) {
    return true;
  }
  if (/\b(naked|nude|topless|bottomless|wet|sweaty|stained|torn|ripped|damaged|aside|open clothes|clothes lift|covered nipples)\b/u.test(key)) {
    return true;
  }
  return false;
}

function isIdentityTerm(term, key) {
  if (isNamedCharacterTerm(term, key)) return true;
  if (isGenericDemographic(key) || isGenericMaleDescriptor(key)) return true;
  const cached = tagClassification.get(key);
  if (
    cached === 'character' &&
    !isBodyDescriptorTerm(key) &&
    !isGarmentTerm(key) &&
    !shouldDropTerm(key)
  ) {
    return true;
  }
  const parens = [...term.matchAll(/\(([^)]+)\)/gu)].map((item) => item[1].trim());
  if (
    parens.some(isFranchiseQualifier) &&
    !isBodyDescriptorTerm(key) &&
    !isGarmentTerm(key) &&
    !shouldDropTerm(key)
  ) {
    return true;
  }
  if (/^(orc|monster|tentacle monster|animal|dog|cat)$/u.test(key)) return true;
  return false;
}

function normalizeSourceTerms(terms) {
  const result = [];
  for (let index = 0; index < terms.length; index += 1) {
    const term = cleanDisplayTerm(terms[index]);
    if (!term) continue;
    const next = cleanDisplayTerm(terms[index + 1]);
    if (next && isPureFranchiseQualifierTerm(next) && canPrefixFranchiseQualifier(term)) {
      result.push(`${term} ${next}`);
      index += 1;
      continue;
    }
    if (isPureFranchiseQualifierTerm(term)) continue;
    result.push(term);
  }
  return result;
}

function canPrefixFranchiseQualifier(term) {
  const key = termKey(term);
  if (!key || shouldDropTerm(key)) return false;
  if (isGenericDemographic(key) || isGenericMaleDescriptor(key)) return false;
  if (isGarmentTerm(key) || isBodyDescriptorTerm(key)) return false;
  return /^[a-z][a-z0-9_'\- ]{1,80}$/iu.test(cleanDisplayTerm(term));
}

function isPureFranchiseQualifierTerm(term) {
  const match = /^\(([^)]+)\)$/u.exec(cleanDisplayTerm(term));
  return Boolean(match && isFranchiseQualifier(match[1]));
}

function isPureFranchiseQualifierKey(key) {
  const match = /^\(([^)]+)\)$/u.exec(key);
  return Boolean(match && isFranchiseQualifier(match[1]));
}

function isNamedCharacterTerm(term, key) {
  const clean = cleanDisplayTerm(term);
  if (!clean || isPureFranchiseQualifierTerm(clean)) return false;
  const parens = [...clean.matchAll(/\(([^)]+)\)/gu)].map((item) => item[1].trim());
  const base = clean.slice(0, clean.indexOf('(') >= 0 ? clean.indexOf('(') : clean.length).trim();
  if (base && parens.some(isFranchiseQualifier)) {
    return true;
  }
  if (tagClassification.get(key) === 'character' && !isGarmentTerm(key) && !isBodyDescriptorTerm(key)) {
    return true;
  }
  if (looksLikeSourceNameToken(clean, key)) return true;
  return false;
}

function looksLikeSourceNameToken(clean, key) {
  if (!clean.includes('_')) return false;
  if (shouldDropTerm(key) || isGarmentTerm(key) || isBodyDescriptorTerm(key)) return false;
  if (/^(official|alternate|solo|spoken|source|negative|bad|extra|missing)_/iu.test(clean)) {
    return false;
  }
  return /^[a-z][a-z0-9_]*(?:\([^)]+\)|_[a-z0-9]+)*(?:\s+cosplay)?$/iu.test(clean);
}

function isGenericDemographic(value) {
  const key = termKey(value);
  return /^(1girl|1boy|girl|boy|woman|man|male|female|loli|child|multiple girls|multiple boys)$/u.test(
    key,
  );
}

function isGenericMaleDescriptor(value) {
  const key = termKey(value);
  return /\b(dark skinned male|dark-skinned male|very dark skinned male|very dark-skinned male|faceless male|muscular male|musclar male|old man|middle aged man|fat man|obese man|ugly man|black man|african|afican)\b/u.test(
    key,
  );
}

function isUpperBodyTerm(key) {
  if (/\b(teeth only|head between)\b/u.test(key)) return false;
  return /\b(hair|bangs|twintails?|twin tails?|ponytails?|braids?|ahoge|eyes?|pupils?|iris|ears?|horns?|halo|headband|headdress|headwear|hat|cap|beret|crown|tiara|ornament|ribbon|bow|necklace|choker|collar|earrings?|fangs?|fang|breasts?|chest|skin|tan|dark skin|black skin|scar|tattoo|mole|mask|glasses)\b/u.test(
    key,
  );
}

function isLowerBodyTerm(key) {
  if (/\b(leg grab|spread legs|m legs)\b/u.test(key)) return false;
  return /\b(tail|legs?|feet|foot|hooves?|anklet|thigh strap|thighs? strap)\b/u.test(
    key,
  );
}

function isUpperClothingTerm(key) {
  if (/\b(aside|torn|ripped|damaged|open clothes|lifting|holding)\b/u.test(key)) {
    return false;
  }
  return /\b(shirt|blouse|jacket|coat|overcoat|hoodie|sweater|dress|uniform|bra|bikini top|bikini|neckerchief|sailor collar|harness|leotard|bodysuit|swimsuit|school swimsuit|one piece swimsuit|kimono|robe|armor|apron|gloves?|sleeves?|sports bra|towel|mantle|cloak|cape|belt|strap|bowtie|necktie|tie|frills?|lingerie|outfit|costume|clothes|clothing|pajamas|tank top|vest|corset|collared shirt|suit)\b/u.test(
    key,
  );
}

function isLowerClothingTerm(key) {
  if (/\b(aside|torn|ripped|damaged|around)\b/u.test(key)) return false;
  return /\b(pants|trousers|shorts|skirt|miniskirt|panties|underwear|briefs|leggings|stockings?|socks?|thighhighs?|pantyhose|garter|shoes?|boots?|sandals?|heels?|loafers?|footwear|legwear|bikini bottom|swimsuit bottom|fundoshi|pelvic curtain|mary janes?|sneakers?)\b/u.test(
    key,
  );
}

function isGarmentTerm(key) {
  return isUpperClothingTerm(key) || isLowerClothingTerm(key);
}

function isBodyDescriptorTerm(key) {
  return isUpperBodyTerm(key) || isLowerBodyTerm(key);
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
  if (/^\|.*\|$/u.test(clean) && clean.includes('|')) {
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
    .replace(/\b-?\d+(?:\.\d+)?::/gu, '')
    .replace(/::/gu, '')
    .replace(/[{}[\]]/gu, '')
    .replace(/^[\s:|,+]+|[\s:|,+]+$/gu, '')
    .replace(/\s+/gu, ' ')
    .trim();
}

function termKey(value) {
  return cleanDisplayTerm(value)
    .toLowerCase()
    .replace(/[_-]+/gu, ' ')
    .replace(/\s*\(([^)]+)\)\s*/gu, ' ($1)')
    .replace(/\s+/gu, ' ')
    .trim();
}

function slug(value) {
  const ascii = termKey(value)
    .replace(/\(([^)]+)\)/gu, '$1')
    .replace(/[^a-z0-9]+/gu, '-')
    .replace(/^-+|-+$/gu, '')
    .slice(0, 80);
  return ascii || 'unresolved';
}

function uniqueTerms(values) {
  const result = [];
  const seen = new Set();
  for (const value of values) {
    const term = cleanDisplayTerm(value);
    const key = termKey(term);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(term);
  }
  return result;
}

function uniqueNumbers(values) {
  return [...new Set(values.map(Number).filter(Number.isFinite))].sort((a, b) => a - b);
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function loadTagClassification() {
  const result = new Map();
  const filePath = firstExistingPath([
    process.env.TAG_CACHE_PATH,
    'E:/NAI的脚本群/tag_classification_cache.json',
  ]);
  if (!filePath || !fs.existsSync(filePath)) return result;
  const raw = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  for (const [rawKey, value] of Object.entries(raw)) {
    const key = rawKey.replace(/^positive:/u, '');
    const category = typeof value === 'string' ? value : value?.category;
    if (!key || !category) continue;
    result.set(termKey(key), category);
  }
  return result;
}

function firstExistingPath(paths) {
  for (const filePath of paths) {
    if (filePath && fs.existsSync(filePath)) return filePath;
  }
  return '';
}

function parseArgs(args) {
  const parsed = { apply: false };
  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    if (arg === '--apply') {
      parsed.apply = true;
      continue;
    }
    const key = arg.startsWith('--') ? arg.slice(2) : arg;
    const value = args[i + 1];
    if (value == null || value.startsWith('--')) continue;
    i += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'report') parsed.report = value;
    if (key === 'backup-dir') parsed.backupDir = value;
    if (key === 'only-files') parsed.onlyFiles = value;
  }
  return parsed;
}
