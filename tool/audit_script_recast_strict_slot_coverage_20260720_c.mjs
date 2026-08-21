#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

// These are the only source slots in this batch that intentionally describe a
// partial prop interaction rather than a materializable role.  The cache must
// also carry a matching no_role_partial attention item; the source text alone
// is not enough to waive ownership.
const ALLOWED_NO_ROLE_PARTIALS = new Map([
  [
    'script-4-483f0d961dbafdcc\u001f175\u001fslot-1',
    /\bdisembodied hands\b.*\bholding syringe\b/i,
  ],
  [
    'script-4-483f0d961dbafdcc\u001f176\u001fslot-1',
    /\bdisembodied hands\b.*\bholding syringe\b/i,
  ],
  [
    'script-4-483f0d961dbafdcc\u001f177\u001fslot-1',
    /\bdisembodied hands\b.*\bholding syringe\b/i,
  ],
]);

const ROLE_CATEGORIES = new Set([
  'identity',
  'body',
  'clothing',
  'clothingState',
  'clothing_state',
  'accessory',
]);
const ALL_CATEGORIES = new Set([...ROLE_CATEGORIES, 'scene']);

const options = parseArgs(process.argv.slice(2));
if (!options.cacheDir) throw new Error('Pass --cache-dir <directory>.');
const cacheDir = path.resolve(options.cacheDir);
const reportPath = options.report ? path.resolve(options.report) : null;
if (!fs.existsSync(cacheDir)) throw new Error(`Missing cache dir: ${cacheDir}`);

const rows = fs
  .readdirSync(cacheDir)
  .filter((file) => file.endsWith('.json'))
  .sort()
  .map((file) => auditFile(path.join(cacheDir, file)));

const report = {
  tool: 'audit_script_recast_strict_slot_coverage_20260720_c',
  api_used: false,
  cache_dir: cacheDir,
  cache_count: rows.length,
  nonempty_slot_appearance_count: sum(rows, 'nonempty_slot_appearance_count'),
  covered_slot_appearance_count: sum(rows, 'covered_slot_appearance_count'),
  allowed_no_role_partial_count: sum(rows, 'allowed_no_role_partial_count'),
  uncovered_slot_appearance_count: sum(
    rows,
    'uncovered_slot_appearance_count',
  ),
  multiple_owner_slot_appearance_count: sum(
    rows,
    'multiple_owner_slot_appearance_count',
  ),
  generic_role_multi_slot_same_frame_count: sum(
    rows,
    'generic_role_multi_slot_same_frame_count',
  ),
  invalid_role_appearance_count: sum(rows, 'invalid_role_appearance_count'),
  non_role_base_materialization_count: sum(
    rows,
    'non_role_base_materialization_count',
  ),
  invalid_prompt_category_count: sum(rows, 'invalid_prompt_category_count'),
  prompt_occurrence_outside_role_count: sum(
    rows,
    'prompt_occurrence_outside_role_count',
  ),
  prompt_occurrence_no_source_count: sum(
    rows,
    'prompt_occurrence_no_source_count',
  ),
  role_mapping_mismatch_group_count: sum(
    rows,
    'role_mapping_mismatch_group_count',
  ),
  scene_mapping_mismatch_cache_count: sum(
    rows,
    'scene_mapping_mismatch_cache_count',
  ),
  missing_chinese_display_count: sum(rows, 'missing_chinese_display_count'),
  duplicate_stage_label_group_count: sum(
    rows,
    'duplicate_stage_label_group_count',
  ),
  issue_cache_count: rows.filter((row) => row.issue_count > 0).length,
  rows,
};
report.issue_count = sum(rows, 'issue_count');

const output = `${JSON.stringify(report, null, 2)}\n`;
if (reportPath) {
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, output, 'utf8');
}
process.stdout.write(output);
if (report.issue_count > 0) process.exitCode = 2;

function auditFile(filePath) {
  const cache = readJson(filePath);
  const fileName = path.basename(filePath);
  const scriptId = stringValue(cache.scriptId ?? cache.scriptSnapshot?.id);
  const frames = new Map(
    (cache.scriptSnapshot?.frames ?? []).map((frame) => [
      Number(frame.index),
      frame,
    ]),
  );
  const roles = cache.aiRoleExtraction?.roles ?? [];
  const owners = new Map();
  const issues = [];
  const counters = {
    role_count: roles.length,
    nonempty_slot_appearance_count: 0,
    covered_slot_appearance_count: 0,
    allowed_no_role_partial_count: 0,
    uncovered_slot_appearance_count: 0,
    multiple_owner_slot_appearance_count: 0,
    generic_role_multi_slot_same_frame_count: 0,
    invalid_role_appearance_count: 0,
    non_role_base_materialization_count: 0,
    invalid_prompt_category_count: 0,
    prompt_occurrence_outside_role_count: 0,
    prompt_occurrence_no_source_count: 0,
    role_mapping_mismatch_group_count: 0,
    scene_mapping_mismatch_cache_count: 0,
    missing_chinese_display_count: 0,
    duplicate_stage_label_group_count: 0,
  };

  for (const role of roles) {
    const roleId = stringValue(role.source_role_id);
    const declaredFrames = integerSet(role.frame_indexes);
    const appearanceFrames = new Set();
    const sourcesByFrame = new Map();

    if (!hasHan(role.display_name)) {
      increment(counters, issues, 'missing_chinese_display_count', {
        kind: 'role_display_missing_chinese',
        role_id: roleId,
        display_name: stringValue(role.display_name),
      });
    }

    for (const appearance of role.appearances ?? []) {
      const sourceId = stringValue(appearance.source_id);
      const sourceKind = stringValue(appearance.source_kind);
      for (const value of appearance.frame_indexes ?? []) {
        const frameIndex = Number(value);
        appearanceFrames.add(frameIndex);
        const frameSources = sourcesByFrame.get(frameIndex) ?? new Set();
        frameSources.add(sourceId);
        sourcesByFrame.set(frameIndex, frameSources);

        if (sourceId === 'base' || sourceKind === 'base') {
          const frame = frames.get(frameIndex);
          if (!frame || isNonRoleBase(frame.parsed?.baseCaption)) {
            increment(
              counters,
              issues,
              'non_role_base_materialization_count',
              {
                kind: 'non_role_base_materialization',
                role_id: roleId,
                frame_index: frameIndex,
                source_id: sourceId,
              },
            );
          }
          continue;
        }

        const slotIndex = slotNumber(sourceId);
        const frame = frames.get(frameIndex);
        const caption = frame?.parsed?.charCaptions?.[slotIndex];
        if (
          !Number.isInteger(frameIndex) ||
          slotIndex == null ||
          !frame ||
          !stringValue(caption).trim()
        ) {
          increment(counters, issues, 'invalid_role_appearance_count', {
            kind: 'invalid_role_appearance',
            role_id: roleId,
            frame_index: frameIndex,
            source_id: sourceId,
            reason: !frame
              ? 'frame_missing'
              : slotIndex == null
                ? 'source_id_not_slot'
                : 'slot_missing_or_empty',
          });
          continue;
        }
        addOwner(owners, frameIndex, sourceId, roleId);
      }
    }

    if (!sameNumberSet(declaredFrames, appearanceFrames)) {
      increment(counters, issues, 'invalid_role_appearance_count', {
        kind: 'role_frame_indexes_do_not_match_appearances',
        role_id: roleId,
        declared_frame_indexes: [...declaredFrames].sort(numberSort),
        appearance_frame_indexes: [...appearanceFrames].sort(numberSort),
      });
    }

    if (isGenericRole(role)) {
      for (const [frameIndex, sourceIds] of sourcesByFrame) {
        const slots = [...sourceIds].filter((sourceId) => slotNumber(sourceId) != null);
        if (new Set(slots).size <= 1) continue;
        increment(
          counters,
          issues,
          'generic_role_multi_slot_same_frame_count',
          {
            kind: 'generic_role_multi_slot_same_frame',
            role_id: roleId,
            frame_index: frameIndex,
            source_ids: [...new Set(slots)].sort(),
          },
        );
      }
    }

    auditStageLabels(role, counters, issues);
    auditRolePromptTerms(role, frames, counters, issues);
  }

  for (const frame of frames.values()) {
    const frameIndex = Number(frame.index);
    const captions = frame.parsed?.charCaptions ?? [];
    for (let slotIndex = 0; slotIndex < captions.length; slotIndex += 1) {
      const caption = stringValue(captions[slotIndex]).trim();
      if (!caption) continue;
      counters.nonempty_slot_appearance_count += 1;
      const sourceId = `slot-${slotIndex}`;
      const slotOwners = [
        ...(owners.get(ownerKey(frameIndex, sourceId)) ?? new Set()),
      ].sort();
      if (slotOwners.length === 1) {
        counters.covered_slot_appearance_count += 1;
        continue;
      }
      if (slotOwners.length > 1) {
        increment(counters, issues, 'multiple_owner_slot_appearance_count', {
          kind: 'multiple_owner_slot_appearance',
          frame_index: frameIndex,
          source_id: sourceId,
          owners: slotOwners,
          caption,
        });
        continue;
      }

      const allowanceKey = `${scriptId}\u001f${frameIndex}\u001f${sourceId}`;
      const evidencePattern = ALLOWED_NO_ROLE_PARTIALS.get(allowanceKey);
      if (
        evidencePattern?.test(caption) &&
        hasNoRolePartialAttention(cache, frameIndex, sourceId, evidencePattern)
      ) {
        counters.allowed_no_role_partial_count += 1;
        issues.push({
          kind: 'allowed_no_role_partial',
          frame_index: frameIndex,
          source_id: sourceId,
          caption,
          blocking: false,
        });
        continue;
      }
      increment(counters, issues, 'uncovered_slot_appearance_count', {
        kind: 'uncovered_slot_appearance',
        frame_index: frameIndex,
        source_id: sourceId,
        caption,
        allowance_expected: Boolean(evidencePattern),
      });
    }
  }

  auditSceneTerms(cache, frames, counters, issues);
  auditRoleMappings(cache, counters, issues);
  auditSceneMappings(cache, counters, issues);

  return {
    file_name: fileName,
    script_id: scriptId,
    ...counters,
    issue_count: issues.filter((item) => item.blocking !== false).length,
    issues,
  };
}

function auditRolePromptTerms(role, frames, counters, issues) {
  const roleId = stringValue(role.source_role_id);
  const owned = new Set();
  for (const appearance of role.appearances ?? []) {
    const sourceId = stringValue(appearance.source_id);
    for (const frameIndex of appearance.frame_indexes ?? []) {
      owned.add(ownerKey(Number(frameIndex), sourceId));
    }
  }

  for (const term of role.prompt_terms ?? []) {
    const category = stringValue(term.category);
    if (!ROLE_CATEGORIES.has(category)) {
      increment(counters, issues, 'invalid_prompt_category_count', {
        kind: 'invalid_role_prompt_category',
        role_id: roleId,
        term: stringValue(term.text),
        category,
      });
    }
    for (const occurrence of termOccurrences(term)) {
      const frameIndex = occurrence.frameIndex;
      const sourceIds = sourceIdsFromLocation(occurrence.sourceLocation);
      const ownedSourceIds = sourceIds.filter((sourceId) =>
        owned.has(ownerKey(frameIndex, sourceId)),
      );
      if (ownedSourceIds.length === 0) {
        increment(counters, issues, 'prompt_occurrence_outside_role_count', {
          kind: 'prompt_occurrence_outside_role',
          role_id: roleId,
          term: stringValue(term.text),
          frame_index: frameIndex,
          source_location: occurrence.sourceLocation,
        });
        continue;
      }
      const hasSource = ownedSourceIds.some((sourceId) => {
        const slotIndex = slotNumber(sourceId);
        const caption = frames.get(frameIndex)?.parsed?.charCaptions?.[slotIndex];
        return (
          captionHasExactTerm(caption, term.text) ||
          captionHasExactTerm(caption, term.source_phrase ?? term.text)
        );
      });
      if (!hasSource) {
        increment(counters, issues, 'prompt_occurrence_no_source_count', {
          kind: 'role_prompt_occurrence_no_exact_source',
          role_id: roleId,
          term: stringValue(term.text),
          source_phrase: stringValue(term.source_phrase ?? term.text),
          frame_index: frameIndex,
          source_location: occurrence.sourceLocation,
        });
      }
    }
  }
}

function auditSceneTerms(cache, frames, counters, issues) {
  for (const term of cache.aiRoleExtraction?.scene_terms ?? []) {
    if (!ALL_CATEGORIES.has(stringValue(term.category)) || term.category !== 'scene') {
      increment(counters, issues, 'invalid_prompt_category_count', {
        kind: 'invalid_scene_prompt_category',
        term: stringValue(term.text),
        category: stringValue(term.category),
      });
    }
    for (const occurrence of termOccurrences(term)) {
      if (normalizeSpace(occurrence.sourceLocation) !== 'base prompt') {
        increment(counters, issues, 'prompt_occurrence_outside_role_count', {
          kind: 'scene_prompt_occurrence_not_base',
          term: stringValue(term.text),
          frame_index: occurrence.frameIndex,
          source_location: occurrence.sourceLocation,
        });
        continue;
      }
      const caption = frames.get(occurrence.frameIndex)?.parsed?.baseCaption;
      if (
        !captionHasExactTerm(caption, term.text) &&
        !captionHasExactTerm(caption, term.source_phrase ?? term.text)
      ) {
        increment(counters, issues, 'prompt_occurrence_no_source_count', {
          kind: 'scene_prompt_occurrence_no_exact_source',
          term: stringValue(term.text),
          source_phrase: stringValue(term.source_phrase ?? term.text),
          frame_index: occurrence.frameIndex,
        });
      }
    }
  }
}

function auditRoleMappings(cache, counters, issues) {
  const roles = cache.aiRoleExtraction?.roles ?? [];
  const groups = cache.mapping?.rolePromptReplacements ?? [];
  const groupsByRole = new Map();
  for (const group of groups) {
    const roleId = stringValue(group.sourceRoleId);
    const values = groupsByRole.get(roleId) ?? [];
    values.push(group);
    groupsByRole.set(roleId, values);
  }

  const roleIds = new Set(roles.map((role) => stringValue(role.source_role_id)));
  for (const role of roles) {
    const roleId = stringValue(role.source_role_id);
    const matches = groupsByRole.get(roleId) ?? [];
    const mappedTerms = matches.flatMap(flattenRuleTerms);
    if (
      matches.length !== 1 ||
      canonicalTermList(role.prompt_terms ?? []) !== canonicalTermList(mappedTerms)
    ) {
      increment(counters, issues, 'role_mapping_mismatch_group_count', {
        kind: 'role_prompt_mapping_mismatch',
        role_id: roleId,
        mapping_group_count: matches.length,
        ai_term_count: (role.prompt_terms ?? []).length,
        mapping_term_count: mappedTerms.length,
      });
    }
  }
  for (const [roleId, matches] of groupsByRole) {
    if (roleIds.has(roleId)) continue;
    increment(counters, issues, 'role_mapping_mismatch_group_count', {
      kind: 'orphan_role_prompt_mapping',
      role_id: roleId,
      mapping_group_count: matches.length,
    });
  }
}

function auditSceneMappings(cache, counters, issues) {
  const aiTerms = cache.aiRoleExtraction?.scene_terms ?? [];
  const mappedTerms = (cache.mapping?.scenePromptReplacements ?? []).flatMap(
    flattenRuleTerms,
  );
  if (canonicalTermList(aiTerms) === canonicalTermList(mappedTerms)) return;
  increment(counters, issues, 'scene_mapping_mismatch_cache_count', {
    kind: 'scene_prompt_mapping_mismatch',
    ai_term_count: aiTerms.length,
    mapping_term_count: mappedTerms.length,
  });
}

function auditStageLabels(role, counters, issues) {
  const roleId = stringValue(role.source_role_id);
  const byLabel = new Map();
  for (const stage of role.stages ?? []) {
    const label = stringValue(stage.label).trim();
    if (!hasHan(label)) {
      increment(counters, issues, 'missing_chinese_display_count', {
        kind: 'stage_label_missing_chinese',
        role_id: roleId,
        stage_id: stringValue(stage.stage_id),
        label,
      });
    }
    const key = normalizeSpace(label);
    const values = byLabel.get(key) ?? [];
    values.push(stringValue(stage.stage_id));
    byLabel.set(key, values);
  }
  for (const [label, stageIds] of byLabel) {
    if (!label || stageIds.length <= 1) continue;
    increment(counters, issues, 'duplicate_stage_label_group_count', {
      kind: 'duplicate_stage_label_group',
      role_id: roleId,
      label,
      stage_ids: stageIds,
    });
  }
}

function termOccurrences(term) {
  const sourceLocation = stringValue(term.source_location ?? term.sourceLocation);
  const provided = term.source_occurrences ?? term.sourceOccurrences ?? [];
  const byKey = new Map();
  const providedFrames = new Set();
  for (const occurrence of provided) {
    const frameIndex = Number(
      occurrence.frame_index ?? occurrence.frameIndex,
    );
    const location = stringValue(
      occurrence.source_location ?? occurrence.sourceLocation ?? sourceLocation,
    );
    byKey.set(`${frameIndex}\u001f${location}`, {
      frameIndex,
      sourceLocation: location,
    });
    providedFrames.add(frameIndex);
  }
  for (const value of term.frame_indexes ?? term.frameIndexes ?? []) {
    const frameIndex = Number(value);
    if (providedFrames.has(frameIndex)) continue;
    const key = `${frameIndex}\u001f${sourceLocation}`;
    if (!byKey.has(key)) {
      byKey.set(key, { frameIndex, sourceLocation });
    }
  }
  return [...byKey.values()].sort(
    (left, right) =>
      left.frameIndex - right.frameIndex ||
      left.sourceLocation.localeCompare(right.sourceLocation),
  );
}

function canonicalTermList(terms) {
  return JSON.stringify(
    terms
      .map((term) => ({
        id: stringValue(term.id),
        text: stringValue(term.text),
        category: stringValue(term.category),
        sourcePhrase: stringValue(term.source_phrase ?? term.sourcePhrase),
        sourceLocation: stringValue(
          term.source_location ?? term.sourceLocation,
        ),
        frameIndexes: [
          ...(term.frame_indexes ?? term.frameIndexes ?? []),
        ]
          .map(Number)
          .sort(numberSort),
        sourceOccurrences: termOccurrences(term),
      }))
      .sort((left, right) => left.id.localeCompare(right.id)),
  );
}

function flattenRuleTerms(group) {
  return (group.rules ?? []).flatMap((rule) => rule.sourceTerms ?? []);
}

function hasNoRolePartialAttention(cache, frameIndex, sourceId, pattern) {
  return (cache.aiRoleExtraction?.attention_items ?? []).some((item) => {
    if (stringValue(item.kind) !== 'no_role_partial') return false;
    if (stringValue(item.source_id) !== sourceId) return false;
    if (!integerSet(item.frame_indexes).has(frameIndex)) return false;
    return pattern.test(stringValue(item.evidence));
  });
}

function captionHasExactTerm(caption, phrase) {
  const target = normalizeTag(phrase);
  if (!target) return false;
  return stringValue(caption)
    .split(',')
    .map(normalizeTag)
    .some((tag) => tag === target);
}

function normalizeTag(value) {
  let result = stringValue(value)
    .normalize('NFKC')
    .replace(/[‘’]/g, "'")
    .replace(/_/g, ' ')
    .trim()
    .toLowerCase();
  result = result.replace(/^[-+]?\d+(?:\.\d+)?\s*::\s*/, '');
  result = result.replace(/^::\s*/, '');
  result = result.replace(/\s*::\s*$/, '');
  return result.replace(/\s+/g, ' ').trim();
}

function sourceIdsFromLocation(value) {
  return [
    ...new Set(
      [...stringValue(value).matchAll(/\b(slot-\d+)\b/gi)].map((match) =>
        match[1].toLowerCase(),
      ),
    ),
  ];
}

function slotNumber(sourceId) {
  const match = stringValue(sourceId).match(/^slot-(\d+)$/);
  return match ? Number(match[1]) : null;
}

function isGenericRole(role) {
  const roleId = normalizeSpace(role.source_role_id);
  if (/\b(?:anonymous|muscular-male|fat-man|dark-skinned-male)\b/.test(roleId)) {
    return true;
  }
  const canonical = normalizeTag(role.canonical_name);
  return new Set([
    'boy',
    'girl',
    'male',
    'female',
    'man',
    'woman',
    'muscular male',
    'fat man',
    'dark-skinned male',
  ]).has(canonical);
}

function isNonRoleBase(value) {
  const tags = stringValue(value).split(',').map(normalizeTag);
  if (tags.includes('no human') || tags.includes('no humans')) return true;
  return !tags.some((tag) =>
    /^(?:\d+)?(?:girl|girls|boy|boys|woman|women|man|men)$/.test(tag),
  );
}

function hasHan(value) {
  return /\p{Script=Han}/u.test(stringValue(value));
}

function addOwner(owners, frameIndex, sourceId, roleId) {
  const key = ownerKey(frameIndex, sourceId);
  const values = owners.get(key) ?? new Set();
  values.add(roleId);
  owners.set(key, values);
}

function ownerKey(frameIndex, sourceId) {
  return `${frameIndex}\u001f${sourceId}`;
}

function increment(counters, issues, counter, item) {
  counters[counter] += 1;
  issues.push({ ...item, blocking: true });
}

function integerSet(values) {
  return new Set((values ?? []).map(Number).filter(Number.isInteger));
}

function sameNumberSet(left, right) {
  if (left.size !== right.size) return false;
  return [...left].every((value) => right.has(value));
}

function normalizeSpace(value) {
  return stringValue(value).normalize('NFKC').trim().toLowerCase().replace(/\s+/g, ' ');
}

function numberSort(left, right) {
  return left - right;
}

function stringValue(value) {
  return value == null ? '' : String(value);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function sum(items, key) {
  return items.reduce((total, item) => total + Number(item[key] ?? 0), 0);
}

function parseArgs(values) {
  const result = {};
  for (let index = 0; index < values.length; index += 1) {
    const arg = values[index];
    if (!arg.startsWith('--')) throw new Error(`Unknown argument: ${arg}`);
    const key = arg
      .slice(2)
      .replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
    result[key] = values[index + 1];
    index += 1;
  }
  return result;
}
