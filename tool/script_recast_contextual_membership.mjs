const categoryOrder = new Map([
  ['character', 0],
  ['upperBody', 1],
  ['lowerBody', 2],
  ['upperClothing', 3],
  ['lowerClothing', 4],
  ['accessory', 5],
  ['clothingState', 6],
  ['clothing', 7],
  ['other', 8],
  ['scene', 9],
]);

const allowedCategories = new Set(categoryOrder.keys());
const addOutcomes = new Set([
  'ADD_TO_PENDING',
  'MOVE_OWNER',
  'CHANGE_CATEGORY',
  'SPLIT_BY_STAGE',
]);
const removeOutcomes = new Set([
  'REMOVE_FROM_PENDING',
  'MOVE_OWNER',
  'CHANGE_CATEGORY',
]);

function stringValue(value) {
  return typeof value === 'string' ? value : String(value ?? '');
}

export function normalizeMembershipKey(value) {
  return stringValue(value)
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[{}\[\]()]+/g, ' ')
    .replace(/^\s*[+-]?\d*\.?\d+::/, '')
    .replace(/\s*::\s*$/, '')
    .replace(/\s*:\s*[+-]?\d*\.?\d+\s*$/, '')
    .replace(/[\s_-]+/g, ' ')
    .trim();
}

function safeId(value) {
  return normalizeMembershipKey(value)
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '') || 'term';
}

function cleanAtom(value) {
  let text = stringValue(value).replace(/\r?\n/g, ' ').trim();
  if (!text) return '';
  text = text.replace(/\s+/g, ' ');
  text = text.replace(/^[([{]+|[)\]}]+$/g, '').trim();
  return text
    .replace(/^[+-]?[0-9.]+::\s*/, '')
    .replace(/\s*::[+-]?[0-9.]*$/, '')
    .replace(/\s*:[+-]?\d*\.?\d+\s*$/, '')
    .trim();
}

export function splitContextualPromptAtoms(caption) {
  const atoms = [];
  let current = '';
  let depth = 0;
  for (const char of stringValue(caption)) {
    if ('([{'.includes(char)) depth += 1;
    if (')]}'.includes(char)) depth = Math.max(0, depth - 1);
    if ((char === ',' || char === '，' || char === ';' || char === '；') && depth === 0) {
      const atom = cleanAtom(current);
      if (atom) atoms.push(atom);
      current = '';
    } else {
      current += char;
    }
  }
  const tail = cleanAtom(current);
  if (tail) atoms.push(tail);
  return atoms;
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function sortedInts(values) {
  return [...new Set((values ?? []).map(Number).filter(Number.isInteger))].sort(
    (left, right) => left - right,
  );
}

export function normalizeContextualStageId(value) {
  const text = stringValue(value).trim().toLowerCase();
  if (/^\d+$/.test(text)) return `stage-${Number(text)}`;
  const match = /^stage-(\d+)$/.exec(text);
  return match ? `stage-${Number(match[1])}` : text;
}

function normalizedSourceLocation(value) {
  const text = stringValue(value).trim();
  if (/^base prompt(?:\s+\([^)]*\))?$/.test(text)) return 'base prompt';
  const slot = /^(slot-\d+) prompt(?:\s+\([^)]*\))?$/.exec(text);
  return slot ? `${slot[1]} prompt` : '';
}

function requestedFinalOccurrenceKeys(candidate) {
  if (!Object.hasOwn(candidate ?? {}, 'final_occurrences')) return null;
  if (!Array.isArray(candidate?.final_occurrences) || candidate.final_occurrences.length === 0) {
    throw new Error(`${candidate?.candidate_id}: final_occurrences must be a non-empty array`);
  }
  const result = new Set();
  for (const row of candidate.final_occurrences) {
    const frameIndex = Number(row?.frame_index);
    const sourceLocation = normalizedSourceLocation(row?.source_location);
    if (!Number.isInteger(frameIndex) || !sourceLocation) {
      throw new Error(`${candidate?.candidate_id}: invalid final occurrence`);
    }
    const key = `${frameIndex}\u001f${sourceLocation}`;
    if (result.has(key)) {
      throw new Error(`${candidate?.candidate_id}: duplicate final occurrence ${key}`);
    }
    result.add(key);
  }
  return result;
}

function sourceCaption(cache, frameIndex, sourceLocation) {
  const frame = (cache?.scriptSnapshot?.frames ?? []).find(
    (item) => Number(item?.index) === Number(frameIndex),
  );
  if (!frame) return '';
  if (sourceLocation === 'base prompt') {
    return stringValue(frame?.parsed?.baseCaption);
  }
  const slot = /^slot-(\d+) prompt$/.exec(sourceLocation);
  return slot
    ? stringValue(frame?.parsed?.charCaptions?.[Number(slot[1])])
    : '';
}

function roleIdsFromDecision(decision) {
  const matches = [...stringValue(decision?.final_role).matchAll(/role-[a-z0-9-]+/gi)]
    .map((match) => match[0].toLowerCase());
  return [...new Set(matches)];
}

function physicalRows(candidate) {
  const summary = candidate?.raw_occurrence_summary ?? {};
  return [
    ...(Array.isArray(summary.representative_exact)
      ? summary.representative_exact
      : []),
    ...(Array.isArray(summary.representative_containing)
      ? summary.representative_containing
      : []),
  ];
}

function trustedSurfaceKeys(candidate) {
  const keys = new Set([normalizeMembershipKey(candidate?.term)]);
  for (const row of physicalRows(candidate)) {
    const key = normalizeMembershipKey(row?.matched_atom);
    if (key) keys.add(key);
  }
  return keys;
}

function preferredTermText(candidate, cache) {
  const key = normalizeMembershipKey(candidate?.term);
  for (const role of cache?.aiRoleExtraction?.roles ?? []) {
    for (const term of role?.prompt_terms ?? []) {
      if (normalizeMembershipKey(term?.text) === key) {
        return stringValue(term.text).trim();
      }
    }
  }
  for (const term of cache?.aiRoleExtraction?.scene_terms ?? []) {
    if (normalizeMembershipKey(term?.text) === key) {
      return stringValue(term.text).trim();
    }
  }
  for (const row of candidate?.raw_occurrence_summary?.representative_exact ?? []) {
    const surface = stringValue(row?.matched_atom).trim();
    if (
      surface &&
      surface.length <= 160 &&
      !/[\r\n]/.test(surface) &&
      normalizeMembershipKey(surface) === key
    ) {
      return surface;
    }
  }
  return stringValue(candidate?.term).trim();
}

function roleFrameSet(role, stageIds) {
  const requested = new Set(
    (stageIds ?? [])
      .map(normalizeContextualStageId)
      .filter(Boolean),
  );
  if (requested.size > 0) {
    const matchedStages = (role?.stages ?? []).filter((stage) =>
      requested.has(normalizeContextualStageId(stage?.stage_id)),
    );
    // A non-empty reviewer stage scope is a hard boundary.  Falling back to
    // every role frame when no stage id matches silently broadens the term to
    // unrelated stages, so fail closed and let the caller reject the decision.
    if (matchedStages.length === 0) return new Set();
    return new Set(
      sortedInts(matchedStages.flatMap((stage) => stage?.frame_indexes ?? [])),
    );
  }
  return new Set(sortedInts(role?.frame_indexes));
}

function allowedRoleSourceLocations(role, frameIndex) {
  const result = new Set(['base prompt']);
  for (const appearance of role?.appearances ?? []) {
    if (!(appearance?.frame_indexes ?? []).map(Number).includes(Number(frameIndex))) continue;
    const sourceId = stringValue(appearance?.source_id).trim();
    if (/^slot-\d+$/.test(sourceId)) result.add(`${sourceId} prompt`);
    if (sourceId === 'base') result.add('base prompt');
  }
  return result;
}

function allFrameSources(cache, frameIndex) {
  const frame = (cache?.scriptSnapshot?.frames ?? []).find(
    (item) => Number(item?.index) === Number(frameIndex),
  );
  if (!frame) return [];
  const sources = [{ sourceLocation: 'base prompt', caption: stringValue(frame?.parsed?.baseCaption) }];
  for (const [slot, caption] of (frame?.parsed?.charCaptions ?? []).entries()) {
    sources.push({ sourceLocation: `slot-${slot} prompt`, caption: stringValue(caption) });
  }
  return sources;
}

function collectOccurrences(cache, candidate, role, stageIds) {
  const surfaces = trustedSurfaceKeys(candidate);
  const frameSet = role
    ? roleFrameSet(role, stageIds)
    : new Set(
        sortedInts((cache?.scriptSnapshot?.frames ?? []).map((frame) => frame?.index)),
      );
  const occurrences = new Map();
  for (const frameIndex of frameSet) {
    const allowed = role ? allowedRoleSourceLocations(role, frameIndex) : null;
    for (const source of allFrameSources(cache, frameIndex)) {
      if (allowed && !allowed.has(source.sourceLocation)) continue;
      const matched = splitContextualPromptAtoms(source.caption).some((atom) =>
        surfaces.has(normalizeMembershipKey(atom)),
      );
      if (!matched) continue;
      occurrences.set(`${frameIndex}\u001f${source.sourceLocation}`, {
        frame_index: frameIndex,
        source_location: source.sourceLocation,
      });
    }
  }

  // Discovery rows preserve the actual raw surface and physical source even
  // when malformed braces prevent atom splitting.  They are scoped by the
  // candidate and are safer than a normalized substring search.
  for (const row of physicalRows(candidate)) {
    const frameIndex = Number(row?.frame_index);
    const sourceLocation = normalizedSourceLocation(row?.source_location);
    const surface = stringValue(row?.matched_atom);
    if (!Number.isInteger(frameIndex) || !sourceLocation || !surface) continue;
    if (!frameSet.has(frameIndex)) continue;
    if (role && !allowedRoleSourceLocations(role, frameIndex).has(sourceLocation)) continue;
    if (!sourceCaption(cache, frameIndex, sourceLocation).includes(surface)) continue;
    occurrences.set(`${frameIndex}\u001f${sourceLocation}`, {
      frame_index: frameIndex,
      source_location: sourceLocation,
    });
  }

  // The semantic reviewers' evidence passed the byte-exact evidence gate.  It
  // is a safe fallback for damaged prompt atoms that the parser cannot split.
  for (const evidence of candidate?.final_evidence ?? candidate?.evidence ?? []) {
    const frameIndex = Number(evidence?.frame_index);
    const sourceLocation = normalizedSourceLocation(evidence?.source_location);
    const excerpt = stringValue(evidence?.verbatim_prompt_excerpt);
    if (!Number.isInteger(frameIndex) || !sourceLocation || !excerpt) continue;
    if (!frameSet.has(frameIndex)) continue;
    if (role && !allowedRoleSourceLocations(role, frameIndex).has(sourceLocation)) continue;
    const caption = sourceCaption(cache, frameIndex, sourceLocation);
    if (!caption.includes(excerpt)) continue;
    occurrences.set(`${frameIndex}\u001f${sourceLocation}`, {
      frame_index: frameIndex,
      source_location: sourceLocation,
    });
  }
  const collected = [...occurrences.values()].sort(
    (left, right) =>
      left.frame_index - right.frame_index ||
      left.source_location.localeCompare(right.source_location),
  );
  const requested = requestedFinalOccurrenceKeys(candidate);
  if (requested === null) return collected;
  const available = new Set(
    collected.map((row) => `${row.frame_index}\u001f${row.source_location}`),
  );
  const missing = [...requested].filter((key) => !available.has(key));
  if (missing.length > 0) {
    throw new Error(
      `${candidate?.candidate_id}: requested final occurrence is not physically bound: ${missing[0]}`,
    );
  }
  return collected.filter((row) =>
    requested.has(`${row.frame_index}\u001f${row.source_location}`),
  );
}

function inspectionScopeMatchesOwner(scopeLabel, ownerId) {
  const label = stringValue(scopeLabel).trim().toLowerCase();
  const owner = stringValue(ownerId).trim().toLowerCase();
  if (!label || !owner) return false;
  let start = label.indexOf(owner);
  while (start >= 0) {
    const before = start === 0 ? '' : label[start - 1];
    const afterIndex = start + owner.length;
    const after = afterIndex >= label.length ? '' : label[afterIndex];
    const beforeBoundary = !before || !/[a-z0-9-]/.test(before);
    const afterBoundary = !after || !/[a-z0-9-]/.test(after);
    if (beforeBoundary && afterBoundary) return true;
    start = label.indexOf(owner, start + 1);
  }
  return false;
}

function inspectionScopeIsScene(scopeLabel) {
  const label = stringValue(scopeLabel).trim().toLowerCase();
  return label === 'scene' || label.startsWith('scene-') || label.includes('/scene');
}

function normalizedDisplayScope(value) {
  return stringValue(value)
    .split('/')[0]
    .trim()
    .toLowerCase()
    .replace(/\s+/g, ' ');
}

function inspectionScopeDescribesMissingTarget(decision) {
  const roleLabel = stringValue(
    decision?.inspection_scope?.current_role_label,
  ).trim().toLowerCase();
  const categoryLabel = stringValue(
    decision?.inspection_scope?.current_category_label,
  ).trim().toLowerCase();
  return (
    roleLabel.includes('none/missing') ||
    ['missing', 'none'].includes(categoryLabel)
  );
}

function scopedCurrentPendingOccurrences(decision) {
  const occurrences = Array.isArray(decision?.current_pending_occurrences)
    ? decision.current_pending_occurrences
    : [];
  const scopeLabel = stringValue(decision?.inspection_scope?.current_role_label).trim();
  if (!scopeLabel) return occurrences;

  const selectedOwners = new Set();
  let inferredSourceCategory = '';
  if (inspectionScopeDescribesMissingTarget(decision)) {
    const currentTargets = new Map();
    for (const occurrence of occurrences) {
      const isScene =
        occurrence?.role_id === 'scene' ||
        occurrence?.owner === 'scene' ||
        occurrence?.field === 'scene_terms' ||
        occurrence?.surface === 'mapping_scene_pending';
      const ownerId = isScene
        ? 'scene'
        : stringValue(occurrence?.role_id ?? occurrence?.owner).trim();
      const category = stringValue(occurrence?.category).trim();
      if (!ownerId || !category) continue;
      currentTargets.set(`${ownerId}\u001f${category}`, { ownerId, category });
    }
    // Missing-target review candidates use the declared scope for the new
    // owner. Their removal source is safe only when the evidence identifies
    // one unambiguous current owner/category target; multi-target residue
    // still fails closed.
    if (currentTargets.size === 1) {
      const [{ ownerId, category }] = currentTargets.values();
      selectedOwners.add(ownerId);
      inferredSourceCategory = category;
    }
  } else if (inspectionScopeIsScene(scopeLabel)) {
    selectedOwners.add('scene');
  } else {
    const normalizedScope = normalizedDisplayScope(scopeLabel);
    for (const occurrence of occurrences) {
      const ownerId = stringValue(occurrence?.role_id ?? occurrence?.owner).trim();
      if (ownerId && inspectionScopeMatchesOwner(scopeLabel, ownerId)) {
        selectedOwners.add(ownerId);
        continue;
      }
      const displayName = normalizedDisplayScope(occurrence?.role_display_name);
      if (ownerId && displayName && normalizedScope === displayName) {
        selectedOwners.add(ownerId);
      }
    }
  }

  // A declared scope that cannot be reconciled with the occurrence owners is
  // unsafe. Return no targets so mutating decisions fail closed instead of
  // deleting every same-name role membership carried by a legacy candidate.
  if (selectedOwners.size === 0) return [];

  const categoryScope =
    inferredSourceCategory ||
    stringValue(decision?.inspection_scope?.current_category_label).trim();
  const normalizedCategory = categoryScope.toLowerCase();
  const hasCategoryScope =
    categoryScope &&
    !['missing', 'none', 'unknown', 'unassigned', 'mixed'].includes(normalizedCategory);

  return occurrences.filter((occurrence) => {
    const isScene =
      occurrence?.role_id === 'scene' ||
      occurrence?.owner === 'scene' ||
      occurrence?.field === 'scene_terms' ||
      occurrence?.surface === 'mapping_scene_pending';
    const ownerId = isScene
      ? 'scene'
      : stringValue(occurrence?.role_id ?? occurrence?.owner).trim();
    if (!selectedOwners.has(ownerId)) return false;
    const occurrenceCategory = stringValue(occurrence?.category).trim();
    return !hasCategoryScope || !occurrenceCategory || occurrenceCategory === categoryScope;
  });
}

function removeCurrentAiTerms(cache, decision) {
  let removed = 0;
  const extraction = cache.aiRoleExtraction ?? {};
  const scopedOccurrences = scopedCurrentPendingOccurrences(decision);
  for (const occurrence of scopedOccurrences) {
    if (occurrence?.structure !== 'aiRoleExtraction') continue;
    if (occurrence?.field === 'prompt_terms') {
      const role = (extraction.roles ?? []).find(
        (item) => item?.source_role_id === occurrence?.role_id,
      );
      if (!role) continue;
      const before = role.prompt_terms?.length ?? 0;
      role.prompt_terms = (role.prompt_terms ?? []).filter(
        (term) => term?.id !== occurrence?.prompt_term_id,
      );
      removed += before - role.prompt_terms.length;
    } else if (occurrence?.field === 'scene_terms') {
      const before = extraction.scene_terms?.length ?? 0;
      extraction.scene_terms = (extraction.scene_terms ?? []).filter(
        (term) => term?.id !== occurrence?.scene_term_id,
      );
      removed += before - extraction.scene_terms.length;
    }
  }

  // Fail-safe for old mapping-only residue: scope the fallback by exact role,
  // category, and normalized term; never remove every same-name term in a file.
  if (removed === 0 && decision?.current_pending_presence === true) {
    const termKey = normalizeMembershipKey(decision?.term);
    for (const occurrence of scopedOccurrences) {
      const roleId = stringValue(occurrence?.role_id ?? occurrence?.owner).trim();
      const category = stringValue(occurrence?.category).trim();
      if (!termKey) continue;
      if (
        roleId === 'scene' ||
        occurrence?.field === 'scene_terms' ||
        occurrence?.surface === 'mapping_scene_pending'
      ) {
        const before = extraction.scene_terms?.length ?? 0;
        extraction.scene_terms = (extraction.scene_terms ?? []).filter(
          (term) =>
            !(
              normalizeMembershipKey(term?.text) === termKey &&
              (!category || term?.category === category)
            ),
        );
        removed += before - extraction.scene_terms.length;
        continue;
      }
      if (!roleId) continue;
      const role = (extraction.roles ?? []).find((item) => item?.source_role_id === roleId);
      if (!role) continue;
      const before = role.prompt_terms?.length ?? 0;
      role.prompt_terms = (role.prompt_terms ?? []).filter(
        (term) =>
          !(
            normalizeMembershipKey(term?.text) === termKey &&
            (!category || term?.category === category)
          ),
      );
      removed += before - role.prompt_terms.length;
    }
  }
  return removed;
}

export function currentPendingTargetKeys(decision) {
  const result = [];
  const termKey = normalizeMembershipKey(decision?.term);
  for (const occurrence of scopedCurrentPendingOccurrences(decision)) {
    const roleId = stringValue(occurrence?.role_id ?? occurrence?.owner).trim();
    const category = stringValue(
      occurrence?.category ?? decision?.inspection_scope?.current_category_label,
    ).trim();
    if (
      roleId === 'scene' ||
      occurrence?.field === 'scene_terms' ||
      occurrence?.surface === 'mapping_scene_pending'
    ) {
      if (termKey) result.push(['scene', category || 'scene', termKey].join('\u001f'));
      continue;
    }
    if (roleId && termKey) {
      result.push(['role', roleId, category, termKey].join('\u001f'));
    }
  }
  return [...new Set(result)];
}

export function finalPendingTargetKeys(decision) {
  const result = [];
  const termKey = normalizeMembershipKey(decision?.term);
  const category = stringValue(decision?.final_category).trim();
  if (!termKey || !category) return result;
  if (category === 'scene') return [['scene', 'scene', termKey].join('\u001f')];
  for (const roleId of roleIdsFromDecision(decision)) {
    result.push(['role', roleId, category, termKey].join('\u001f'));
  }
  return [...new Set(result)];
}

export function contextualDecisionTargetConflicts(decisions) {
  const removals = new Map();
  const additions = new Map();
  const conflicts = [];
  for (const decision of decisions) {
    const outcome = stringValue(decision?.final_outcome ?? decision?.outcome).trim();
    if (!removeOutcomes.has(outcome)) continue;
    for (const contextualTarget of currentPendingTargetKeys(decision)) {
      const target = [decision?.file_name, contextualTarget].join('\u001f');
      const existing = removals.get(target);
      if (
        existing &&
        existing.candidate_id !== decision?.candidate_id &&
        existing.outcome !== outcome
      ) {
        conflicts.push({
          kind: 'conflicting_removal_outcomes',
          target,
          candidate_ids: [existing.candidate_id, decision?.candidate_id],
          outcomes: [existing.outcome, outcome],
        });
      } else if (!existing) {
        removals.set(target, { candidate_id: decision?.candidate_id, outcome });
      }
    }
  }
  for (const decision of decisions) {
    const outcome = stringValue(decision?.final_outcome ?? decision?.outcome).trim();
    if (!addOutcomes.has(outcome)) continue;
    for (const contextualTarget of finalPendingTargetKeys(decision)) {
      const target = [decision?.file_name, contextualTarget].join('\u001f');
      const rows = additions.get(target) ?? [];
      rows.push({ candidate_id: decision?.candidate_id, outcome });
      additions.set(target, rows);
    }
  }
  for (const [target, additionRows] of additions) {
    const removal = removals.get(target);
    if (!removal) continue;
    for (const addition of additionRows) {
      // MOVE_OWNER and CHANGE_CATEGORY deliberately remove the old contextual
      // set and may re-add one surviving target from that same candidate.
      if (addition.candidate_id === removal.candidate_id) continue;
      conflicts.push({
        kind: 'remove_add_same_target',
        target,
        candidate_ids: [removal.candidate_id, addition.candidate_id],
        outcomes: [removal.outcome, addition.outcome],
      });
    }
  }
  return conflicts;
}

function mergePromptTerm(terms, { idPrefix, text, category, occurrences }) {
  const key = normalizeMembershipKey(text);
  let term = (terms ?? []).find(
    (item) =>
      item?.category === category && normalizeMembershipKey(item?.text) === key,
  );
  if (!term) {
    term = {
      id: `${idPrefix}-${category}-${safeId(text)}`,
      text,
      category,
      source_phrase: text,
      source_location: '',
      frame_indexes: [],
      source_occurrences: [],
    };
    terms.push(term);
  }
  const merged = new Map();
  for (const occurrence of [
    ...(term.source_occurrences ?? []),
    ...occurrences,
  ]) {
    const frameIndex = Number(occurrence?.frame_index);
    const sourceLocation = normalizedSourceLocation(occurrence?.source_location);
    if (!Number.isInteger(frameIndex) || !sourceLocation) continue;
    merged.set(`${frameIndex}\u001f${sourceLocation}`, {
      frame_index: frameIndex,
      source_location: sourceLocation,
    });
  }
  term.source_occurrences = [...merged.values()].sort(
    (left, right) =>
      left.frame_index - right.frame_index ||
      left.source_location.localeCompare(right.source_location),
  );
  term.frame_indexes = sortedInts(term.source_occurrences.map((item) => item.frame_index));
  term.source_location = [...new Set(term.source_occurrences.map((item) => item.source_location))]
    .sort()
    .join('; ');
  term.source_phrase ||= text;
  terms.sort(
    (left, right) =>
      (categoryOrder.get(left?.category) ?? 99) -
        (categoryOrder.get(right?.category) ?? 99) ||
      stringValue(left?.text).localeCompare(stringValue(right?.text)),
  );
  return term;
}

function addDecisionTerm(cache, decision) {
  const category = stringValue(decision?.final_category).trim();
  if (!allowedCategories.has(category)) {
    throw new Error(`${decision?.candidate_id}: invalid final category ${category}`);
  }
  const text = preferredTermText(decision, cache);
  if (!text) throw new Error(`${decision?.candidate_id}: blank final term`);
  const addedTargets = [];
  if (category === 'scene') {
    const occurrences = collectOccurrences(cache, decision, null, []);
    if (occurrences.length === 0) {
      throw new Error(`${decision?.candidate_id}: scene addition has no physical occurrence`);
    }
    cache.aiRoleExtraction.scene_terms ??= [];
    mergePromptTerm(cache.aiRoleExtraction.scene_terms, {
      idPrefix: 'scene',
      text,
      category: 'scene',
      occurrences,
    });
    return ['scene'];
  }

  const roleIds = roleIdsFromDecision(decision);
  if (roleIds.length === 0) {
    throw new Error(`${decision?.candidate_id}: no concrete final role id`);
  }
  for (const roleId of roleIds) {
    const role = (cache.aiRoleExtraction?.roles ?? []).find(
      (item) => stringValue(item?.source_role_id).toLowerCase() === roleId,
    );
    if (!role) throw new Error(`${decision?.candidate_id}: missing final role ${roleId}`);
    const occurrences = collectOccurrences(
      cache,
      decision,
      role,
      decision?.final_stage_ids ?? [],
    );
    if (occurrences.length === 0) {
      throw new Error(
        `${decision?.candidate_id}: ${roleId} addition has no role-scoped physical occurrence`,
      );
    }
    role.prompt_terms ??= [];
    mergePromptTerm(role.prompt_terms, {
      idPrefix: `role-${safeId(roleId)}`,
      text,
      category,
      occurrences,
    });
    addedTargets.push(roleId);
  }
  return addedTargets;
}

function sourceTermFromAi(term) {
  return {
    id: stringValue(term?.id).trim() || `term-${safeId(term?.text)}`,
    text: stringValue(term?.text).trim(),
    category: stringValue(term?.category).trim() || 'character',
    ...(stringValue(term?.source_phrase).trim()
      ? { sourcePhrase: stringValue(term.source_phrase).trim() }
      : {}),
    ...(stringValue(term?.source_location).trim()
      ? { sourceLocation: stringValue(term.source_location).trim() }
      : {}),
    ...(sortedInts(term?.frame_indexes).length > 0
      ? { frameIndexes: sortedInts(term.frame_indexes) }
      : {}),
    ...((term?.source_occurrences ?? []).length > 0
      ? {
          sourceOccurrences: term.source_occurrences.map((item) => ({
            frameIndex: item.frame_index,
            sourceLocation: item.source_location,
          })),
        }
      : {}),
  };
}

function ruleMatchKeys(term) {
  const text = normalizeMembershipKey(term?.text);
  const category = normalizeMembershipKey(term?.category);
  const id = normalizeMembershipKey(term?.id);
  return [text, `${category}\u001f${text}`, `id\u001f${id}`].filter(Boolean);
}

function syncRules(sourceRoleId, terms, existingRules) {
  const existingByKey = new Map();
  for (const rule of existingRules ?? []) {
    for (const term of rule?.sourceTerms ?? []) {
      for (const key of ruleMatchKeys(term)) {
        if (!existingByKey.has(key)) existingByKey.set(key, rule);
      }
    }
  }
  const emitted = new Set();
  return terms.map((term) => {
    const sourceTerm = sourceTermFromAi(term);
    let existing = null;
    for (const key of ruleMatchKeys(sourceTerm)) {
      existing = existingByKey.get(key);
      if (existing) break;
    }
    const generatedId = `role-${sourceRoleId}-${sourceTerm.id}`;
    let id = stringValue(existing?.id).trim() || generatedId;
    let suffix = 2;
    while (emitted.has(id)) id = `${generatedId}-${suffix++}`;
    emitted.add(id);
    const next = existing
      ? { ...existing, id, sourceTerms: [sourceTerm] }
      : { id, sourceTerms: [sourceTerm] };
    if (next.anchorTermId && next.anchorTermId !== sourceTerm.id) delete next.anchorTermId;
    if (Array.isArray(next.excludedTermIds)) {
      next.excludedTermIds = next.excludedTermIds.filter((value) => value === sourceTerm.id);
      if (next.excludedTermIds.length === 0) delete next.excludedTermIds;
    }
    return next;
  });
}

function promptParts(stage) {
  const result = {};
  for (const [source, target] of [
    ['identity', 'identity'],
    ['upper_body', 'upperBody'],
    ['lower_body', 'lowerBody'],
    ['upper_clothing', 'upperClothing'],
    ['lower_clothing', 'lowerClothing'],
  ]) {
    const value = stringValue(stage?.[source]).trim();
    if (value) result[target] = value;
  }
  return result;
}

function retainedStageFields(stage) {
  const result = {};
  for (const key of [
    'targetCharacterId',
    'targetUpperOutfitId',
    'targetLowerOutfitId',
    'omittedParts',
    'preservedParts',
    'manualParts',
  ]) {
    const value = stage?.[key];
    if (value == null) continue;
    if (typeof value === 'string' && !value) continue;
    if (Array.isArray(value) && value.length === 0) continue;
    if (typeof value === 'object' && !Array.isArray(value) && Object.keys(value).length === 0) continue;
    result[key] = value;
  }
  return result;
}

export function rebuildContextualPromptMappings(cache) {
  const extraction = cache.aiRoleExtraction ?? { roles: [], scene_terms: [] };
  const mapping = cache.mapping ?? {};
  const existingRoleReplacements = new Map(
    (mapping.rolePromptReplacements ?? []).map((item) => [item?.sourceRoleId, item]),
  );
  const existingAssemblies = new Map(
    (mapping.roleAssemblies ?? []).map((item) => [item?.sourceRoleId, item]),
  );
  mapping.rolePromptReplacements = (extraction.roles ?? [])
    .filter((role) => (role?.prompt_terms ?? []).length > 0)
    .map((role) => {
      const roleId = stringValue(role?.source_role_id).trim();
      const existing = existingRoleReplacements.get(roleId) ?? {};
      return {
        sourceRoleId: roleId,
        displayLabel: stringValue(role?.display_name).trim() || roleId,
        sourcePreview: (role.prompt_terms ?? []).map((term) => term.text).join(', '),
        ...(stringValue(existing?.targetCharacterId).trim()
          ? { targetCharacterId: existing.targetCharacterId }
          : {}),
        ...(stringValue(existing?.targetIdentityPrompt).trim()
          ? { targetIdentityPrompt: existing.targetIdentityPrompt }
          : {}),
        rules: syncRules(roleId, role.prompt_terms, existing?.rules ?? []),
      };
    });

  const existingScene = (mapping.scenePromptReplacements ?? []).find(
    (item) => item?.id === 'scene-ai',
  ) ?? {};
  const sceneTerms = extraction.scene_terms ?? [];
  mapping.scenePromptReplacements = sceneTerms.length === 0
    ? []
    : [{
        id: 'scene-ai',
        label: stringValue(existingScene?.label).trim() || 'Scene',
        rules: syncRules('scene', sceneTerms, existingScene?.rules ?? []).map((rule, index) => ({
          ...rule,
          id: stringValue(rule.id).startsWith('role-scene-')
            ? `scene-${sceneTerms[index]?.id ?? safeId(sceneTerms[index]?.text)}`
            : rule.id,
        })),
      }];

  mapping.roleAssemblies = (extraction.roles ?? []).map((role) => {
    const roleId = stringValue(role?.source_role_id).trim();
    const previous = existingAssemblies.get(roleId) ?? {};
    const previousStages = new Map((previous?.stages ?? []).map((stage) => [stage?.id, stage]));
    return {
      sourceRoleId: roleId,
      displayLabel: stringValue(role?.display_name).trim() || roleId,
      sourceName: stringValue(role?.display_name).trim() || roleId,
      sourceAppearances: (role?.appearances ?? []).map((appearance) => ({
        sourceId: appearance?.source_id,
        sourceKind: appearance?.source_kind,
        frameIndexes: appearance?.frame_indexes ?? [],
      })),
      stages: (role?.stages ?? []).map((stage) => ({
        id: stage?.stage_id,
        label: stage?.label,
        frameIndexes: stage?.frame_indexes ?? [],
        sourceSummary: (stage?.evidence_terms ?? []).join(', '),
        sourceParts: promptParts(stage),
        ...retainedStageFields(previousStages.get(stage?.stage_id)),
      })),
    };
  });
  cache.mapping = mapping;
  return cache;
}

function parityKeys(cache) {
  const aiRole = new Set();
  const mappingRole = new Set();
  for (const role of cache?.aiRoleExtraction?.roles ?? []) {
    for (const term of role?.prompt_terms ?? []) {
      aiRole.add(`${role.source_role_id}\u001f${term.category}\u001f${normalizeMembershipKey(term.text)}`);
    }
  }
  for (const group of cache?.mapping?.rolePromptReplacements ?? []) {
    for (const rule of group?.rules ?? []) {
      for (const term of rule?.sourceTerms ?? []) {
        mappingRole.add(`${group.sourceRoleId}\u001f${term.category}\u001f${normalizeMembershipKey(term.text)}`);
      }
    }
  }
  const aiScene = new Set(
    (cache?.aiRoleExtraction?.scene_terms ?? []).map(
      (term) => `${term.category}\u001f${normalizeMembershipKey(term.text)}`,
    ),
  );
  const mappingScene = new Set();
  for (const group of cache?.mapping?.scenePromptReplacements ?? []) {
    for (const rule of group?.rules ?? []) {
      for (const term of rule?.sourceTerms ?? []) {
        mappingScene.add(`${term.category}\u001f${normalizeMembershipKey(term.text)}`);
      }
    }
  }
  return { aiRole, mappingRole, aiScene, mappingScene };
}

function setDifference(left, right) {
  return [...left].filter((value) => !right.has(value));
}

export function validateContextualPromptParity(cache) {
  const sets = parityKeys(cache);
  const errors = [
    ...setDifference(sets.aiRole, sets.mappingRole).map((key) => `role_ai_only:${key}`),
    ...setDifference(sets.mappingRole, sets.aiRole).map((key) => `role_mapping_only:${key}`),
    ...setDifference(sets.aiScene, sets.mappingScene).map((key) => `scene_ai_only:${key}`),
    ...setDifference(sets.mappingScene, sets.aiScene).map((key) => `scene_mapping_only:${key}`),
  ];
  return { ok: errors.length === 0, errors };
}

export function applyContextualMembershipDecisions(cacheValue, decisions) {
  const cache = cloneJson(cacheValue);
  cache.aiRoleExtraction ??= { roles: [], scene_terms: [] };
  cache.aiRoleExtraction.roles ??= [];
  cache.aiRoleExtraction.scene_terms ??= [];
  const rows = [];
  const removedPendingTargets = new Set();
  for (const decision of decisions) {
    const outcome = stringValue(decision?.final_outcome ?? decision?.outcome).trim();
    if (![
      'KEEP_CURRENT',
      'REMOVE_FROM_PENDING',
      'ADD_TO_PENDING',
      'MOVE_OWNER',
      'CHANGE_CATEGORY',
      'SPLIT_BY_STAGE',
      'INVALID_CANDIDATE',
    ].includes(outcome)) {
      throw new Error(`${decision?.candidate_id}: unsupported final outcome ${outcome}`);
    }
    const scoped = {
      ...decision,
      final_outcome: outcome,
      final_evidence: decision?.final_evidence ?? decision?.evidence ?? [],
    };
    const removed = removeOutcomes.has(outcome)
      ? removeCurrentAiTerms(cache, scoped)
      : 0;
    const currentTargetKeys = currentPendingTargetKeys(scoped);
    const alreadyRemovedByEarlierDecision =
      currentTargetKeys.length > 0 &&
      currentTargetKeys.every((key) => removedPendingTargets.has(key));
    if (
      removeOutcomes.has(outcome) &&
      scoped?.current_pending_presence === true &&
      removed === 0 &&
      !alreadyRemovedByEarlierDecision
    ) {
      throw new Error(`${scoped?.candidate_id}: current pending target was not removed`);
    }
    if (removed > 0) {
      for (const key of currentTargetKeys) removedPendingTargets.add(key);
    }
    const addedTargets = addOutcomes.has(outcome)
      ? addDecisionTerm(cache, scoped)
      : [];
    rows.push({
      candidate_id: scoped?.candidate_id,
      term: scoped?.term,
      outcome,
      removed_term_count: removed,
      added_targets: addedTargets,
    });
  }
  rebuildContextualPromptMappings(cache);
  const parity = validateContextualPromptParity(cache);
  if (!parity.ok) throw new Error(`AI/mapping parity failed: ${parity.errors.join(', ')}`);
  return { cache, rows, parity };
}
