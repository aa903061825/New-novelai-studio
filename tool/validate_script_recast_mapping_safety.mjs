#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const allowedTargetIds = new Set([
  'legacy-character-sheet-r14',
  'legacy-character-sheet-r13',
  'legacy-character-sheet-r29',
  'legacy-character-sheet-r10',
  'legacy-character-sheet-r1',
  'legacy-character-sheet-r3',
]);

const options = parseArgs(process.argv.slice(2));
if (!options.cacheDir || !options.sourceRoot) {
  throw new Error('Pass --cache-dir <directory> and --source-root <directory>.');
}

const cacheDir = path.resolve(options.cacheDir);
const sourceRoot = normalizePath(path.resolve(options.sourceRoot));
if (!fs.existsSync(cacheDir)) {
  throw new Error(`Missing cache dir: ${cacheDir}`);
}
const termReview = loadTermReview(options.termReview);
const termReviewCoverage = {
  missing: new Set(),
  unresolved: new Set(),
};

const report = {
  tool: 'validate_script_recast_mapping_safety',
  api_used: false,
  cache_dir: cacheDir,
  source_root: sourceRoot,
  files_scanned: 0,
  eligible_cache_files: 0,
  mapped_role_count: 0,
  parse_error_count: 0,
  duplicate_script_id_count: 0,
  missing_source_path_count: 0,
  hidden_role_swap_count: 0,
  mapped_male_role_count: 0,
  mapped_nonfemale_role_count: 0,
  eligible_female_unmapped_count: 0,
  unexpected_target_id_count: 0,
  mapped_role_missing_identity_rule_count: 0,
  mapped_role_missing_target_prompt_count: 0,
  mapped_role_prompt_term_coverage_gap_count: 0,
  mapped_role_source_identity_coverage_gap_count: 0,
  unknown_role_replacement_count: 0,
  pseudo_partial_role_count: 0,
  appearance_collision_count: 0,
  target_stage_mismatch_count: 0,
  orphan_target_stage_count: 0,
  mapped_stage_missing_target_count: 0,
  regression_frame_missing_count: 0,
  regression_male_target_count: 0,
  term_review_file: termReview.filePath,
  term_review_decision_count: termReview.decisions.size,
  term_review_missing_term_count: 0,
  term_review_unresolved_term_count: 0,
  term_review_required_role_missing_ai_count: 0,
  term_review_required_role_missing_mapping_count: 0,
  term_review_required_role_category_mismatch_count: 0,
  term_review_required_scene_missing_ai_count: 0,
  term_review_required_scene_missing_mapping_count: 0,
  term_review_required_scene_category_mismatch_count: 0,
  term_review_excluded_ai_leak_count: 0,
  term_review_excluded_mapping_leak_count: 0,
  term_review_excluded_stage_leak_count: 0,
  term_review_wrong_placement_ai_count: 0,
  term_review_wrong_placement_mapping_count: 0,
  term_review_wrong_placement_stage_count: 0,
  term_review_stage_category_mismatch_count: 0,
  term_review_stage_materialization_marker_missing_count: 0,
  term_review_stage_non_role_residue_count: 0,
  term_review_ai_mapping_term_set_mismatch_count: 0,
  term_review_ai_mapping_category_mismatch_count: 0,
  term_review_source_occurrence_invalid_ai_count: 0,
  term_review_source_occurrence_invalid_mapping_count: 0,
  term_review_source_occurrence_duplicate_ai_count: 0,
  term_review_source_occurrence_duplicate_mapping_count: 0,
  term_review_source_occurrence_unbacked_ai_count: 0,
  term_review_source_occurrence_unbacked_mapping_count: 0,
  term_review_source_occurrence_missing_ai_count: 0,
  term_review_source_occurrence_missing_mapping_count: 0,
  term_review_source_occurrence_ai_mapping_mismatch_count: 0,
  term_review_complete: false,
  violation_count: 0,
  rows: [],
};

const scriptIdFiles = new Map();
let regressionScriptSeen = false;
let regressionFrameSeen = false;
const files = fs
  .readdirSync(cacheDir)
  .filter((file) => file.endsWith('.json'))
  .sort();
report.files_scanned = files.length;

for (const fileName of files) {
  const filePath = path.join(cacheDir, fileName);
  let cache;
  try {
    cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (error) {
    report.parse_error_count += 1;
    report.rows.push({ file_name: fileName, violations: [`parse_error: ${error}`] });
    continue;
  }
  if (!isUnderSourceRoot(cache.sourceRootPath, sourceRoot)) continue;
  report.eligible_cache_files += 1;
  const violations = [];
  const scriptId = stringValue(cache.scriptId);
  const seenFiles = scriptIdFiles.get(scriptId) ?? [];
  seenFiles.push(fileName);
  scriptIdFiles.set(scriptId, seenFiles);

  if (!cache.sourceRootPath || !fs.existsSync(cache.sourceRootPath)) {
    report.missing_source_path_count += 1;
    violations.push('missing_source_path');
  }

  const roles = arrayValue(cache.aiRoleExtraction?.roles);
  const roleById = new Map(
    roles
      .map((role) => [stringValue(role?.source_role_id), role])
      .filter(([id]) => id),
  );
  const replacements = arrayValue(cache.mapping?.rolePromptReplacements);
  const replacementByRoleId = new Map(
    replacements
      .map((replacement) => [stringValue(replacement?.sourceRoleId), replacement])
      .filter(([id]) => id),
  );
  const assemblies = arrayValue(cache.mapping?.roleAssemblies);
  const assemblyByRoleId = new Map(
    assemblies
      .map((assembly) => [stringValue(assembly?.sourceRoleId), assembly])
      .filter(([id]) => id),
  );
  const roleSwaps = arrayValue(cache.mapping?.roleSwaps);
  if (roleSwaps.length > 0) {
    report.hidden_role_swap_count += roleSwaps.length;
    violations.push(`hidden_role_swaps:${roleSwaps.length}`);
  }

  const appearanceOwners = new Map();
  for (const role of roles) {
    const roleId = stringValue(role?.source_role_id);
    for (const appearance of arrayValue(role?.appearances)) {
      const sourceId = stringValue(appearance?.source_id);
      if (!sourceId) continue;
      for (const frameIndex of numberList(appearance?.frame_indexes)) {
        const key = `${frameIndex}\u001f${sourceId}`;
        const owners = appearanceOwners.get(key) ?? new Set();
        owners.add(roleId);
        appearanceOwners.set(key, owners);
      }
    }
    if (isPseudoPartialRole(role, cache.scriptSnapshot)) {
      report.pseudo_partial_role_count += 1;
      violations.push(`pseudo_partial_role:${roleId}`);
    }
  }
  for (const [key, owners] of appearanceOwners) {
    if (owners.size <= 1) continue;
    report.appearance_collision_count += 1;
    violations.push(`appearance_collision:${key}:${[...owners].join(',')}`);
  }

  for (const role of roles) {
    const roleId = stringValue(role?.source_role_id);
    const replacement = replacementByRoleId.get(roleId);
    if (isTargetableFemaleRole(role) && !hasTarget(replacement)) {
      report.eligible_female_unmapped_count += 1;
      violations.push(`eligible_female_unmapped:${roleId}`);
    }
  }

  for (const replacement of replacements) {
    const roleId = stringValue(replacement?.sourceRoleId);
    const role = roleById.get(roleId);
    if (!role) {
      report.unknown_role_replacement_count += 1;
      violations.push(`unknown_role_replacement:${roleId}`);
    }
    if (!hasTarget(replacement)) continue;
    report.mapped_role_count += 1;
    const targetId = stringValue(replacement.targetCharacterId);
    if (!allowedTargetIds.has(targetId)) {
      report.unexpected_target_id_count += 1;
      violations.push(`unexpected_target:${roleId}:${targetId}`);
    }
    if (!stringValue(replacement.targetIdentityPrompt)) {
      report.mapped_role_missing_target_prompt_count += 1;
      violations.push(`missing_target_prompt:${roleId}`);
    }
    if (role && isMaleRole(role)) {
      report.mapped_male_role_count += 1;
      violations.push(`mapped_male_role:${roleId}`);
    } else if (role && !isValidMappedFemaleRole(role)) {
      report.mapped_nonfemale_role_count += 1;
      violations.push(`mapped_nonfemale_role:${roleId}`);
    }
    if (!hasIdentityReplacementRule(replacement)) {
      report.mapped_role_missing_identity_rule_count += 1;
      violations.push(`missing_identity_rule:${roleId}`);
    }
    if (role) {
      for (const term of uncoveredRolePromptTerms(role, replacement)) {
        report.mapped_role_prompt_term_coverage_gap_count += 1;
        violations.push(
          `role_prompt_term_uncovered:${roleId}:${stringValue(term?.text)}`,
        );
      }
      for (const gap of uncoveredRoleSourceIdentityTerms(
        role,
        replacement,
        cache.scriptSnapshot,
      )) {
        report.mapped_role_source_identity_coverage_gap_count += 1;
        violations.push(
          `source_identity_coverage_gap:${roleId}:${gap.frameIndex}:` +
            `${gap.sourceLocation}:${gap.term}`,
        );
      }
    }
  }

  if (termReview.enabled) {
    validateTermReviewForCache({
      cache,
      roles,
      roleById,
      replacementByRoleId,
      violations,
    });
  }

  for (const assembly of assemblies) {
    const roleId = stringValue(assembly?.sourceRoleId);
    const replacement = replacementByRoleId.get(roleId);
    const targetId = hasTarget(replacement)
      ? stringValue(replacement.targetCharacterId)
      : '';
    for (const stage of arrayValue(assembly?.stages)) {
      const stageTargetId = stringValue(stage?.targetCharacterId);
      if (!targetId && stageTargetId) {
        report.orphan_target_stage_count += 1;
        violations.push(`orphan_target_stage:${roleId}:${stringValue(stage?.id)}`);
      } else if (targetId && !stageTargetId) {
        report.mapped_stage_missing_target_count += 1;
        violations.push(`mapped_stage_missing_target:${roleId}:${stringValue(stage?.id)}`);
      } else if (targetId && stageTargetId !== targetId) {
        report.target_stage_mismatch_count += 1;
        violations.push(`target_stage_mismatch:${roleId}:${stageTargetId}:${targetId}`);
      }
    }
  }

  if (options.regressionScriptId && scriptId === options.regressionScriptId) {
    regressionScriptSeen = true;
    const frame = arrayValue(cache.scriptSnapshot?.frames).find(
      (candidate) =>
        normalizedLeaf(candidate?.fileName) ===
        normalizedLeaf(options.regressionFrameFile),
    );
    if (frame) {
      regressionFrameSeen = true;
      const frameIndex = Number(frame.index);
      const captions = arrayValue(frame.parsed?.charCaptions);
      for (let slotIndex = 0; slotIndex < captions.length; slotIndex += 1) {
        if (!captionIsMale(captions[slotIndex])) continue;
        const sourceId = `slot-${slotIndex}`;
        const hiddenSwapTargetsSlot = roleSwaps.some(
          (swap) => stringValue(swap?.sourceRoleId) === sourceId,
        );
        const mappedRoleTargetsSlot = assemblies.some((assembly) => {
          const replacement = replacementByRoleId.get(
            stringValue(assembly?.sourceRoleId),
          );
          if (!hasTarget(replacement)) return false;
          return arrayValue(assembly?.sourceAppearances).some(
            (appearance) =>
              stringValue(appearance?.sourceId) === sourceId &&
              numberList(appearance?.frameIndexes).includes(frameIndex),
          );
        });
        if (hiddenSwapTargetsSlot || mappedRoleTargetsSlot) {
          report.regression_male_target_count += 1;
          violations.push(`regression_male_target:${frame.fileName}:${sourceId}`);
        }
      }
    }
  }

  if (violations.length > 0) {
    report.rows.push({
      file_name: fileName,
      script_id: scriptId,
      script_name: stringValue(cache.scriptName),
      violations,
    });
  }
}

for (const [scriptId, names] of scriptIdFiles) {
  if (scriptId && names.length > 1) {
    report.duplicate_script_id_count += 1;
    report.rows.push({
      script_id: scriptId,
      violations: [`duplicate_script_id:${names.join(',')}`],
    });
  }
}

if (
  options.regressionScriptId &&
  (!regressionScriptSeen || !regressionFrameSeen)
) {
  report.regression_frame_missing_count += 1;
  report.rows.push({
    script_id: options.regressionScriptId,
    violations: [
      `regression_frame_missing:${options.regressionFrameFile || ''}`,
    ],
  });
}

const termReviewViolationKeys = Object.keys(report).filter(
  (key) =>
    key.startsWith('term_review_') &&
    key.endsWith('_count') &&
    key !== 'term_review_decision_count',
);
report.term_review_complete =
  termReview.enabled &&
  termReviewViolationKeys.every((key) => Number(report[key] ?? 0) === 0);

const violationKeys = [
  'parse_error_count',
  'duplicate_script_id_count',
  'missing_source_path_count',
  'hidden_role_swap_count',
  'mapped_male_role_count',
  'mapped_nonfemale_role_count',
  'eligible_female_unmapped_count',
  'unexpected_target_id_count',
  'mapped_role_missing_identity_rule_count',
  'mapped_role_missing_target_prompt_count',
  'mapped_role_prompt_term_coverage_gap_count',
  'mapped_role_source_identity_coverage_gap_count',
  'unknown_role_replacement_count',
  'pseudo_partial_role_count',
  'appearance_collision_count',
  'target_stage_mismatch_count',
  'orphan_target_stage_count',
  'mapped_stage_missing_target_count',
  'regression_frame_missing_count',
  'regression_male_target_count',
  ...termReviewViolationKeys,
];
report.violation_count = violationKeys.reduce(
  (sum, key) => sum + Number(report[key] ?? 0),
  0,
);

const serialized = `${JSON.stringify(report, null, 2)}\n`;
if (options.report) {
  const reportPath = path.resolve(options.report);
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, serialized, 'utf8');
}
process.stdout.write(serialized);
if (report.violation_count > 0) process.exitCode = 1;

function validateTermReviewForCache({
  cache,
  roles,
  roleById,
  replacementByRoleId,
  violations,
}) {
  const positiveTerms = positiveSourceTermsForCache(cache);
  for (const [key, term] of positiveTerms) {
    const decision = termReview.decisions.get(key);
    if (!decision) {
      registerTermReviewCoverageViolation('missing', key, term, violations);
    } else if (decision.placement === 'unresolved') {
      registerTermReviewCoverageViolation('unresolved', key, term, violations);
    }
  }

  const aiRoleTermsById = new Map();
  const mappingRoleTermsById = new Map();
  const aiRoleTerms = new Map();
  const mappingRoleTerms = new Map();
  const roleIds = new Set([
    ...roleById.keys(),
    ...replacementByRoleId.keys(),
  ]);
  for (const roleId of roleIds) {
    const aiTerms = promptTermCategoryMap(
      roleById.get(roleId)?.prompt_terms ?? roleById.get(roleId)?.promptTerms,
    );
    const mappingTerms = mappingPromptTermCategoryMap(
      replacementByRoleId.get(roleId),
    );
    aiRoleTermsById.set(roleId, aiTerms);
    mappingRoleTermsById.set(roleId, mappingTerms);
    mergePromptTermCategoryMaps(aiRoleTerms, aiTerms);
    mergePromptTermCategoryMaps(mappingRoleTerms, mappingTerms);
    compareAiAndMappingTermMaps(
      aiTerms,
      mappingTerms,
      `role:${roleId}`,
      violations,
    );
    auditReviewedPlacements(aiTerms, 'ai', 'role', roleId, violations);
    auditReviewedPlacements(
      mappingTerms,
      'mapping',
      'role',
      roleId,
      violations,
    );
    validateReviewedStageTerms(
      roleById.get(roleId),
      roleId,
      violations,
    );
  }

  const roleContextsByTerm = new Map();
  for (const role of roles) {
    const roleId = stringValue(role?.source_role_id ?? role?.sourceRoleId);
    if (!roleId) continue;
    for (const key of positiveSourceTermsForRole(
      role,
      cache.scriptSnapshot,
    ).keys()) {
      if (termReview.decisions.get(key)?.placement !== 'role') continue;
      const contexts = roleContextsByTerm.get(key) ?? new Set();
      contexts.add(roleId);
      roleContextsByTerm.set(key, contexts);
    }
  }

  for (const [key, term] of positiveTerms) {
    const decision = termReview.decisions.get(key);
    if (decision?.placement !== 'role') continue;
    const contexts = roleContextsByTerm.get(key);
    if (contexts?.size) {
      for (const roleId of contexts) {
        if (
          isReviewedGenericIdentityOmittableForConcreteRole({
            term,
            category: decision.category,
            role: roleById.get(roleId),
          })
        ) {
          continue;
        }
        validateRequiredReviewedTerm({
          key,
          term,
          category: decision.category,
          placement: 'role',
          context: roleId,
          aiTerms: aiRoleTerms,
          mappingTerms: mappingRoleTerms,
          violations,
        });
      }
    } else {
      validateRequiredReviewedTerm({
        key,
        term,
        category: decision.category,
        placement: 'role',
        context: 'any-role',
        aiTerms: aiRoleTerms,
        mappingTerms: mappingRoleTerms,
        violations,
      });
    }
  }

  const aiSceneTerms = promptTermCategoryMap(
    cache.aiRoleExtraction?.scene_terms ??
      cache.aiRoleExtraction?.sceneTerms,
  );
  const mappingSceneTerms = sceneMappingPromptTermCategoryMap(cache.mapping);
  compareAiAndMappingTermMaps(
    aiSceneTerms,
    mappingSceneTerms,
    'scene',
    violations,
  );
  auditReviewedPlacements(aiSceneTerms, 'ai', 'scene', 'scene', violations);
  auditReviewedPlacements(
    mappingSceneTerms,
    'mapping',
    'scene',
    'scene',
    violations,
  );
  for (const [key, term] of positiveTerms) {
    const decision = termReview.decisions.get(key);
    if (decision?.placement !== 'scene') continue;
    validateRequiredReviewedTerm({
      key,
      term,
      category: 'scene',
      placement: 'scene',
      context: 'scene',
      aiTerms: aiSceneTerms,
      mappingTerms: mappingSceneTerms,
      violations,
    });
  }

  validateTermReviewSourceOccurrences({
    cache,
    roles,
    roleById,
    replacementByRoleId,
    roleContextsByTermOccurrence: physicalRoleContextsByTermOccurrence(
      roles,
      cache.scriptSnapshot,
    ),
    violations,
  });
}

function validateTermReviewSourceOccurrences({
  cache,
  roles,
  roleById,
  replacementByRoleId,
  roleContextsByTermOccurrence,
  violations,
}) {
  const sourceEvidence = physicalSourceEvidenceForCache(cache);
  const expected = expectedReviewedPhysicalOccurrences(sourceEvidence);
  const aiRoleOccurrences = new Map();
  const mappingRoleOccurrences = new Map();
  const aiRoleOccurrencesByContext = new Map();
  const mappingRoleOccurrencesByContext = new Map();
  const aiSceneOccurrences = new Map();
  const mappingSceneOccurrences = new Map();

  for (const role of roles) {
    const roleId = stringValue(role?.source_role_id ?? role?.sourceRoleId);
    const context = `role:${roleId || '<missing>'}`;
    const contextOccurrences = new Map();
    aiRoleOccurrencesByContext.set(context, contextOccurrences);
    for (const term of promptTermArray(role)) {
      collectStructuredPromptTermOccurrences({
        term,
        surface: 'ai',
        context,
        sourceEvidence,
        occurrenceMap: aiRoleOccurrences,
        contextOccurrenceMap: contextOccurrences,
        violations,
      });
    }
  }

  for (const replacement of replacementByRoleId.values()) {
    const roleId = stringValue(replacement?.sourceRoleId ?? replacement?.source_role_id);
    const context = `role:${roleId || '<missing>'}`;
    const contextOccurrences = new Map();
    mappingRoleOccurrencesByContext.set(context, contextOccurrences);
    for (const rule of arrayValue(replacement?.rules)) {
      for (const term of promptTermArray(rule, 'sourceTerms', 'source_terms')) {
        collectStructuredPromptTermOccurrences({
          term,
          surface: 'mapping',
          context,
          sourceEvidence,
          occurrenceMap: mappingRoleOccurrences,
          contextOccurrenceMap: contextOccurrences,
          violations,
        });
      }
    }
  }

  for (const term of promptTermArray(
    cache.aiRoleExtraction,
    'scene_terms',
    'sceneTerms',
  )) {
    collectStructuredPromptTermOccurrences({
      term,
      surface: 'ai',
      context: 'scene',
      sourceEvidence,
      occurrenceMap: aiSceneOccurrences,
      violations,
    });
  }

  for (const replacement of arrayAliasValue(
    cache.mapping,
    'scenePromptReplacements',
    'scene_prompt_replacements',
  )) {
    for (const rule of arrayValue(replacement?.rules)) {
      for (const term of promptTermArray(rule, 'sourceTerms', 'source_terms')) {
        collectStructuredPromptTermOccurrences({
          term,
          surface: 'mapping',
          context: 'scene',
          sourceEvidence,
          occurrenceMap: mappingSceneOccurrences,
          violations,
        });
      }
    }
  }

  compareSourceOccurrenceMapsByContext(
    aiRoleOccurrencesByContext,
    mappingRoleOccurrencesByContext,
    'role',
    violations,
  );
  compareSourceOccurrenceMaps(
    aiSceneOccurrences,
    mappingSceneOccurrences,
    'scene',
    violations,
  );

  validateExpectedSourceOccurrences({
    expected: expected.role,
    aiOccurrences: aiRoleOccurrences,
    mappingOccurrences: mappingRoleOccurrences,
    placement: 'role',
    roleById,
    roleContextsByTermOccurrence,
    violations,
  });
  validateExpectedSourceOccurrences({
    expected: expected.scene,
    aiOccurrences: aiSceneOccurrences,
    mappingOccurrences: mappingSceneOccurrences,
    placement: 'scene',
    roleById,
    roleContextsByTermOccurrence,
    violations,
  });
}

function physicalSourceEvidenceForCache(cache) {
  const byTerm = new Map();
  for (const frame of parsedFrames(cache.scriptSnapshot)) {
    const frameIndex = integerValue(frame?.index);
    if (frameIndex == null) continue;
    addPhysicalSourceEvidence(
      byTerm,
      frameIndex,
      'base prompt',
      frame.parsed?.baseCaption,
    );
    const captions = arrayValue(frame.parsed?.charCaptions);
    for (let slotIndex = 0; slotIndex < captions.length; slotIndex += 1) {
      addPhysicalSourceEvidence(
        byTerm,
        frameIndex,
        `slot-${slotIndex} prompt`,
        captions[slotIndex],
      );
    }
  }
  return byTerm;
}

function physicalRoleContextsByTermOccurrence(roles, scriptSnapshot) {
  const result = new Map();
  const frames = new Map();
  for (const frame of parsedFrames(scriptSnapshot)) {
    const frameIndex = integerValue(frame?.index);
    if (frameIndex != null) frames.set(frameIndex, frame);
  }

  for (const role of roles) {
    const roleId = stringValue(role?.source_role_id ?? role?.sourceRoleId);
    if (!roleId) continue;
    for (const appearance of arrayValue(role?.appearances)) {
      const sourceId = stringValue(
        appearance?.source_id ?? appearance?.sourceId,
      );
      const sourceLocation = physicalSourceLocationForSourceId(sourceId);
      if (!sourceLocation) continue;
      for (const frameIndex of numberList(
        appearance?.frame_indexes ?? appearance?.frameIndexes,
      )) {
        const frame = frames.get(frameIndex);
        if (!frame) continue;
        const pair = sourceOccurrencePairKey(frameIndex, sourceLocation);
        for (const term of parsePromptTags(
          promptCaptionForSource(frame, sourceId),
        )) {
          const termKey = normalizedTagKey(term);
          if (!termKey) continue;
          const byPair = result.get(termKey) ?? new Map();
          const contexts = byPair.get(pair) ?? new Set();
          contexts.add(roleId);
          byPair.set(pair, contexts);
          result.set(termKey, byPair);
        }
      }
    }
  }
  return result;
}

function physicalSourceLocationForSourceId(sourceId) {
  if (normalizeText(sourceId) === 'base') return 'base prompt';
  const slotIndex = slotIndexForSourceId(sourceId);
  return slotIndex == null ? '' : `slot-${slotIndex} prompt`;
}

function addPhysicalSourceEvidence(byTerm, frameIndex, sourceLocation, caption) {
  for (const term of parsePromptTags(caption)) {
    const termKey = normalizedTagKey(term);
    if (!termKey) continue;
    const evidence = byTerm.get(termKey) ?? {
      term,
      occurrences: new Set(),
    };
    evidence.occurrences.add(
      sourceOccurrencePairKey(frameIndex, sourceLocation),
    );
    byTerm.set(termKey, evidence);
  }
}

function expectedReviewedPhysicalOccurrences(sourceEvidence) {
  const expected = {
    role: new Map(),
    scene: new Map(),
  };
  for (const [termKey, evidence] of sourceEvidence) {
    const decision = termReview.decisions.get(termKey);
    if (!decision || !expected[decision.placement]) continue;
    expected[decision.placement].set(termKey, {
      term: decision.term,
      category: canonicalPromptCategory(decision.category),
      occurrences: new Set(evidence.occurrences),
    });
  }
  return expected;
}

function collectStructuredPromptTermOccurrences({
  term,
  surface,
  context,
  sourceEvidence,
  occurrenceMap,
  contextOccurrenceMap,
  violations,
}) {
  const termText = cleanPromptTag(term?.text);
  const termKey = normalizedTagKey(termText);
  const category = canonicalPromptCategory(term?.category);
  const occurrenceList = structuredOccurrenceList(term, surface);
  const validOccurrences = new Set();
  const seenOccurrences = new Set();

  if (!occurrenceList.present) return;
  if (!Array.isArray(occurrenceList.value)) {
    registerSourceOccurrenceViolation(
      'invalid',
      surface,
      `${context}:${termText || '<missing-term>'}`,
      violations,
    );
    return;
  }

  for (let index = 0; index < occurrenceList.value.length; index += 1) {
    const rawOccurrence = occurrenceList.value[index];
    if (
      rawOccurrence == null ||
      typeof rawOccurrence !== 'object' ||
      Array.isArray(rawOccurrence)
    ) {
      registerSourceOccurrenceViolation(
        'invalid',
        surface,
        `${context}:${termText || '<missing-term>'}:${index + 1}`,
        violations,
      );
      continue;
    }
    const frameIndex = integerValue(
      rawOccurrence.frame_index ?? rawOccurrence.frameIndex,
    );
    const sourceLocation = physicalSourceLocation(
      rawOccurrence.source_location ?? rawOccurrence.sourceLocation,
    );
    if (frameIndex == null || !sourceLocation || !termKey) {
      registerSourceOccurrenceViolation(
        'invalid',
        surface,
        `${context}:${termText || '<missing-term>'}:${index + 1}`,
        violations,
      );
      continue;
    }
    const pair = sourceOccurrencePairKey(frameIndex, sourceLocation);
    if (seenOccurrences.has(pair)) {
      registerSourceOccurrenceViolation(
        'duplicate',
        surface,
        `${context}:${termText}:${pair}`,
        violations,
      );
    }
    seenOccurrences.add(pair);
    validOccurrences.add(pair);
  }

  const backedOccurrences = sourceEvidence.get(termKey)?.occurrences ?? new Set();
  for (const pair of validOccurrences) {
    if (backedOccurrences.has(pair)) continue;
    registerSourceOccurrenceViolation(
      'unbacked',
      surface,
      `${context}:${termText}:${pair}`,
      violations,
    );
  }

  addSourceOccurrencesToMap(
    occurrenceMap,
    `${termKey}\u001f${category}`,
    validOccurrences,
  );
  if (contextOccurrenceMap) {
    addSourceOccurrencesToMap(
      contextOccurrenceMap,
      `${termKey}\u001f${category}`,
      validOccurrences,
    );
  }
}

function validateExpectedSourceOccurrences({
  expected,
  aiOccurrences,
  mappingOccurrences,
  placement,
  roleById,
  roleContextsByTermOccurrence,
  violations,
}) {
  for (const [termKey, evidence] of expected) {
    const categoryKey = `${termKey}\u001f${evidence.category}`;
    const aiSet = aiOccurrences.get(categoryKey) ?? new Set();
    const mappingSet = mappingOccurrences.get(categoryKey) ?? new Set();
    for (const pair of evidence.occurrences) {
      const contexts =
        roleContextsByTermOccurrence.get(termKey)?.get(pair) ?? new Set();
      const omittedByIdentityEvidenceOnly =
        placement === 'role' &&
        evidence.category === 'character' &&
        contexts.size === 0 &&
        isBuilderOmittableGenericIdentity(evidence.term);
      const omittedByConcreteRole =
        placement === 'role' &&
        [...contexts].some((roleId) =>
          isReviewedGenericIdentityOmittableForConcreteRole({
            term: evidence.term,
            category: evidence.category,
            role: roleById.get(roleId),
          }),
        );
      if (omittedByIdentityEvidenceOnly || omittedByConcreteRole) continue;
      if (!aiSet.has(pair)) {
        registerSourceOccurrenceViolation(
          'missing',
          'ai',
          `${placement}:${evidence.term}:${pair}`,
          violations,
        );
      }
      if (!mappingSet.has(pair)) {
        registerSourceOccurrenceViolation(
          'missing',
          'mapping',
          `${placement}:${evidence.term}:${pair}`,
          violations,
        );
      }
    }
  }
}

function compareSourceOccurrenceMaps(left, right, placement, violations) {
  const keys = new Set([...left.keys(), ...right.keys()]);
  for (const key of keys) {
    const leftSet = left.get(key) ?? new Set();
    const rightSet = right.get(key) ?? new Set();
    if (setsEqual(leftSet, rightSet)) continue;
    registerSourceOccurrenceViolation(
      'ai_mapping_mismatch',
      'source',
      `${placement}:${key}:ai=${sourceOccurrenceSetText(leftSet)}:` +
        `mapping=${sourceOccurrenceSetText(rightSet)}`,
      violations,
    );
  }
}

function compareSourceOccurrenceMapsByContext(
  left,
  right,
  placement,
  violations,
) {
  const contexts = new Set([...left.keys(), ...right.keys()]);
  for (const context of contexts) {
    compareSourceOccurrenceMaps(
      left.get(context) ?? new Map(),
      right.get(context) ?? new Map(),
      `${placement}:${context}`,
      violations,
    );
  }
}

function addSourceOccurrencesToMap(target, key, occurrences) {
  if (!key || key.startsWith('\u001f') || occurrences.size === 0) return;
  const existing = target.get(key) ?? new Set();
  for (const occurrence of occurrences) existing.add(occurrence);
  target.set(key, existing);
}

function registerSourceOccurrenceViolation(kind, surface, detail, violations) {
  const reportKey =
    kind === 'ai_mapping_mismatch'
      ? 'term_review_source_occurrence_ai_mapping_mismatch_count'
      : `term_review_source_occurrence_${kind}_${surface}_count`;
  const violationKind = kind === 'missing' ? 'contract_missing' : kind;
  report[reportKey] += 1;
  violations.push(
    `term_review_source_occurrence_${violationKind}:${surface}:${detail}`,
  );
}

function structuredOccurrenceList(term, surface) {
  const keys =
    surface === 'ai'
      ? ['source_occurrences', 'sourceOccurrences']
      : ['sourceOccurrences', 'source_occurrences'];
  for (const key of keys) {
    if (Object.prototype.hasOwnProperty.call(term ?? {}, key)) {
      return { present: true, value: term[key] };
    }
  }
  return { present: false, value: null };
}

function promptTermArray(value, primaryKey = 'prompt_terms', fallbackKey = 'promptTerms') {
  return arrayAliasValue(value, primaryKey, fallbackKey);
}

function arrayAliasValue(value, primaryKey, fallbackKey) {
  const primary = value?.[primaryKey];
  if (Array.isArray(primary)) return primary;
  const fallback = value?.[fallbackKey];
  return Array.isArray(fallback) ? fallback : [];
}

function physicalSourceLocation(value) {
  const location = stringValue(value);
  if (location === 'base prompt') return location;
  if (/^slot-(?:0|[1-9]\d*) prompt$/.test(location)) return location;
  return '';
}

function sourceOccurrencePairKey(frameIndex, sourceLocation) {
  return `${frameIndex}\u001f${sourceLocation}`;
}

function sourceOccurrenceSetText(occurrences) {
  return [...occurrences].sort().join(',') || '<empty>';
}

function isReviewedGenericIdentityOmittableForConcreteRole({
  term,
  category,
  role,
}) {
  if (canonicalPromptCategory(category) !== 'character') return false;
  if (!isBuilderOmittableGenericIdentity(term)) return false;
  const canonicalName = stringValue(
    role?.canonical_name ?? role?.canonicalName,
  );
  if (!canonicalName || isBuilderOmittableGenericIdentity(canonicalName)) {
    return false;
  }
  return !hasPseudoIdentityMarker(role);
}

function isBuilderOmittableGenericIdentity(value) {
  return /^(?:solo|\d+\s*girls?|girls?|woman|women|female|\d+\s*boys?|boys?|man|men|male|guy|guys|child|student|loli)$/.test(
    normalizedTagKey(value),
  );
}

function validateReviewedStageTerms(role, roleId, violations) {
  const stageFields = [
    ['identity', 'character'],
    ['upper_body', 'upperBody'],
    ['lower_body', 'lowerBody'],
    ['upper_clothing', 'upperClothing'],
    ['lower_clothing', 'lowerClothing'],
  ];
  for (const stage of arrayValue(role?.stages)) {
    const stageId = stringValue(stage?.stage_id ?? stage?.stageId);
    if ((stage?.non_role_materialized ?? stage?.nonRoleMaterialized) !== true) {
      report.term_review_stage_materialization_marker_missing_count += 1;
      violations.push(
        `term_review_stage_materialization_marker_missing:${roleId}:${stageId}`,
      );
    }
    const nonRole = stringValue(stage?.non_role ?? stage?.nonRole);
    if (parsePromptTags(nonRole).length > 0) {
      report.term_review_stage_non_role_residue_count += 1;
      violations.push(
        `term_review_stage_non_role_residue:${roleId}:${stageId}`,
      );
    }
    for (const [field, expectedCategory] of stageFields) {
      const camelField = field.replace(/_([a-z])/g, (_, letter) =>
        letter.toUpperCase(),
      );
      for (const term of parsePromptTags(stage?.[field] ?? stage?.[camelField])) {
        const decision = termReview.decisions.get(normalizedTagKey(term));
        if (!decision || decision.placement === 'unresolved') continue;
        if (decision.placement === 'exclude') {
          report.term_review_excluded_stage_leak_count += 1;
          violations.push(
            `term_review_excluded_stage_leak:${roleId}:${stageId}:${term}`,
          );
        } else if (decision.placement !== 'role') {
          report.term_review_wrong_placement_stage_count += 1;
          violations.push(
            `term_review_wrong_placement_stage:${roleId}:${stageId}:${term}:` +
              `expected=${decision.placement}`,
          );
        } else if (
          canonicalPromptCategory(decision.category) !== expectedCategory
        ) {
          report.term_review_stage_category_mismatch_count += 1;
          violations.push(
            `term_review_stage_category_mismatch:${roleId}:${stageId}:${term}:` +
              `expected=${canonicalPromptCategory(decision.category)}:` +
              `actual=${expectedCategory}`,
          );
        }
      }
    }
  }
}

function registerTermReviewCoverageViolation(kind, key, term, violations) {
  const seen = termReviewCoverage[kind];
  if (seen.has(key)) return;
  seen.add(key);
  const reportKey =
    kind === 'missing'
      ? 'term_review_missing_term_count'
      : 'term_review_unresolved_term_count';
  report[reportKey] = seen.size;
  violations.push(`term_review_${kind}:${term}`);
}

function validateRequiredReviewedTerm({
  key,
  term,
  category,
  placement,
  context,
  aiTerms,
  mappingTerms,
  violations,
}) {
  const prefix = `term_review_required_${placement}`;
  const aiCategories = aiTerms.get(key);
  const mappingCategories = mappingTerms.get(key);
  if (!aiCategories) {
    report[`${prefix}_missing_ai_count`] += 1;
    violations.push(`${prefix}_missing_ai:${context}:${term}`);
  }
  if (!mappingCategories) {
    report[`${prefix}_missing_mapping_count`] += 1;
    violations.push(`${prefix}_missing_mapping:${context}:${term}`);
  }
  const expectedCategory = canonicalPromptCategory(category);
  const wrongAi =
    aiCategories != null && !aiCategories.has(expectedCategory);
  const wrongMapping =
    mappingCategories != null && !mappingCategories.has(expectedCategory);
  if (wrongAi || wrongMapping) {
    report[`${prefix}_category_mismatch_count`] += 1;
    violations.push(
      `${prefix}_category_mismatch:${context}:${term}:` +
        `expected=${expectedCategory}:` +
        `ai=${categorySetText(aiCategories)}:` +
        `mapping=${categorySetText(mappingCategories)}`,
    );
  }
}

function compareAiAndMappingTermMaps(
  aiTerms,
  mappingTerms,
  context,
  violations,
) {
  const keys = new Set([...aiTerms.keys(), ...mappingTerms.keys()]);
  for (const key of keys) {
    const aiCategories = aiTerms.get(key);
    const mappingCategories = mappingTerms.get(key);
    if (!aiCategories || !mappingCategories) {
      report.term_review_ai_mapping_term_set_mismatch_count += 1;
      violations.push(
        `term_review_ai_mapping_set_mismatch:${context}:${key}:` +
          `ai=${Boolean(aiCategories)}:mapping=${Boolean(mappingCategories)}`,
      );
      continue;
    }
    if (!setsEqual(aiCategories, mappingCategories)) {
      report.term_review_ai_mapping_category_mismatch_count += 1;
      violations.push(
        `term_review_ai_mapping_category_mismatch:${context}:${key}:` +
          `ai=${categorySetText(aiCategories)}:` +
          `mapping=${categorySetText(mappingCategories)}`,
      );
    }
  }
}

function auditReviewedPlacements(
  terms,
  surface,
  actualPlacement,
  context,
  violations,
) {
  for (const key of terms.keys()) {
    const decision = termReview.decisions.get(key);
    if (!decision) continue;
    if (decision.placement === 'exclude') {
      const reportKey = `term_review_excluded_${surface}_leak_count`;
      report[reportKey] += 1;
      violations.push(
        `term_review_excluded_${surface}_leak:${context}:${decision.term}`,
      );
      continue;
    }
    if (
      (decision.placement === 'role' || decision.placement === 'scene') &&
      decision.placement !== actualPlacement
    ) {
      const reportKey = `term_review_wrong_placement_${surface}_count`;
      report[reportKey] += 1;
      violations.push(
        `term_review_wrong_placement_${surface}:${context}:` +
          `${decision.term}:expected=${decision.placement}`,
      );
    }
  }
}

function positiveSourceTermsForCache(cache) {
  const result = new Map();
  for (const frame of parsedFrames(cache.scriptSnapshot)) {
    addParsedPromptTerms(result, frame.parsed?.baseCaption);
    for (const caption of arrayValue(frame.parsed?.charCaptions)) {
      addParsedPromptTerms(result, caption);
    }
  }
  return result;
}

function positiveSourceTermsForRole(role, scriptSnapshot) {
  const result = new Map();
  const frames = new Map(
    parsedFrames(scriptSnapshot).map((frame) => [Number(frame.index), frame]),
  );
  for (const appearance of arrayValue(role?.appearances)) {
    const sourceId = stringValue(
      appearance?.source_id ?? appearance?.sourceId,
    );
    for (const frameIndex of numberList(
      appearance?.frame_indexes ?? appearance?.frameIndexes,
    )) {
      const frame = frames.get(frameIndex);
      if (!frame) continue;
      addParsedPromptTerms(
        result,
        promptCaptionForSource(frame, sourceId),
      );
    }
  }
  return result;
}

function parsedFrames(scriptSnapshot) {
  return arrayValue(scriptSnapshot?.frames).filter(
    (frame) =>
      stringValue(frame?.parseStatus ?? frame?.parse_status).toLowerCase() ===
      'parsed',
  );
}

function promptCaptionForSource(frame, sourceId) {
  if (normalizeText(sourceId) === 'base') return frame.parsed?.baseCaption;
  const match = /^slot-(\d+)$/i.exec(sourceId);
  if (!match) return '';
  return arrayValue(frame.parsed?.charCaptions)[Number(match[1])] ?? '';
}

function addParsedPromptTerms(result, caption) {
  for (const term of parsePromptTags(caption)) {
    const key = normalizedTagKey(term);
    if (key && !result.has(key)) result.set(key, term);
  }
}

function promptTermCategoryMap(terms) {
  const result = new Map();
  for (const term of arrayValue(terms)) {
    const key = normalizedTagKey(cleanPromptTag(term?.text));
    if (!key) continue;
    const categories = result.get(key) ?? new Set();
    categories.add(canonicalPromptCategory(term?.category));
    result.set(key, categories);
  }
  return result;
}

function mappingPromptTermCategoryMap(replacement) {
  const terms = [];
  for (const rule of arrayValue(replacement?.rules)) {
    terms.push(...arrayValue(rule?.sourceTerms ?? rule?.source_terms));
  }
  return promptTermCategoryMap(terms);
}

function sceneMappingPromptTermCategoryMap(mapping) {
  const result = new Map();
  for (const replacement of arrayValue(
    mapping?.scenePromptReplacements ?? mapping?.scene_prompt_replacements,
  )) {
    mergePromptTermCategoryMaps(
      result,
      mappingPromptTermCategoryMap(replacement),
    );
  }
  return result;
}

function mergePromptTermCategoryMaps(target, source) {
  for (const [key, sourceCategories] of source) {
    const categories = target.get(key) ?? new Set();
    for (const category of sourceCategories) categories.add(category);
    target.set(key, categories);
  }
}

function canonicalPromptCategory(value) {
  const key = stringValue(value)
    .replace(/[_\s-]+/g, '')
    .toLowerCase();
  return (
    {
      identity: 'character',
      character: 'character',
      upperbody: 'upperBody',
      lowerbody: 'lowerBody',
      upperclothing: 'upperClothing',
      lowerclothing: 'lowerClothing',
      accessory: 'accessory',
      clothingstate: 'clothingState',
      clothing: 'clothing',
      scene: 'scene',
      other: 'other',
    }[key] ?? stringValue(value).trim()
  );
}

function categorySetText(value) {
  return value ? [...value].sort().join('|') : '<missing>';
}

function setsEqual(left, right) {
  return left.size === right.size && [...left].every((value) => right.has(value));
}

function loadTermReview(filePath) {
  const rawPath = stringValue(filePath);
  if (!rawPath) {
    return { enabled: false, filePath: '', decisions: new Map() };
  }
  const resolved = path.resolve(rawPath);
  let document;
  try {
    document = JSON.parse(fs.readFileSync(resolved, 'utf8'));
  } catch (error) {
    throw new Error(`Unable to read term review ${resolved}: ${error.message}`);
  }
  if (document?.kind !== 'script_recast_term_membership_review') {
    throw new Error(
      `Invalid term review kind in ${resolved}: ` +
        `${stringValue(document?.kind) || '<missing>'}`,
    );
  }
  if (Number(document?.schema_version) !== 1) {
    throw new Error(`Unsupported term review schema in ${resolved}.`);
  }
  if (document?.api_used !== false) {
    throw new Error(
      `Term review ${resolved} must explicitly declare api_used=false.`,
    );
  }
  if (!Array.isArray(document?.decisions)) {
    throw new Error(`Term review ${resolved} has no decisions array.`);
  }

  const allowedRoleCategories = new Set([
    'character',
    'upperBody',
    'lowerBody',
    'upperClothing',
    'lowerClothing',
    'accessory',
    'clothingState',
    'clothing',
    'other',
  ]);
  const decisions = new Map();
  for (const [index, rawDecision] of document.decisions.entries()) {
    const term = cleanPromptTag(rawDecision?.term);
    const key = normalizedTagKey(term);
    const placement = stringValue(rawDecision?.placement);
    if (!key) {
      throw new Error(`Term review decision ${index + 1} has no term.`);
    }
    if (!['role', 'scene', 'exclude', 'unresolved'].includes(placement)) {
      throw new Error(
        `Term review decision for "${term}" has invalid placement "${placement}".`,
      );
    }
    let category = stringValue(rawDecision?.category);
    if (placement === 'role') {
      if (category === 'identity') category = 'character';
      if (!allowedRoleCategories.has(category)) {
        throw new Error(
          `Term review role decision for "${term}" has invalid category ` +
            `"${category || '<missing>'}".`,
        );
      }
    } else if (placement === 'scene') {
      category = 'scene';
    } else {
      category = '';
    }
    if (decisions.has(key)) {
      throw new Error(`Duplicate term review decision for "${term}".`);
    }
    decisions.set(key, {
      term,
      placement,
      category,
      reason: stringValue(rawDecision?.reason),
    });
  }
  return { enabled: true, filePath: resolved, decisions };
}

function parsePromptTags(text) {
  return stripNegativeWeightedGroups(stringValue(text).replace(/\r?\n/g, ','))
    .replace(/::\s*[+-]?\d+(?:\.\d+)?\s*::/g, ',')
    .replace(/::+/g, ',')
    .replace(/[\uFF0C\u3001\uFF1B]/g, ',')
    .replace(/[;|]+/g, ',')
    .split(',')
    .map(cleanPromptTag)
    .filter(Boolean);
}

function stripNegativeWeightedGroups(text) {
  return stringValue(text).replace(/-\d+(?:\.\d+)?\s*::[\s\S]*?::/g, ',');
}

function cleanPromptTag(value) {
  let text = stringValue(value);
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
  text = text
    .replace(
      /^((?:1\s*)?(?:girl|girls|female|woman|loli|boy|boys|male|man|men))\s+[+-]?\d+(?:\.\d+)?$/i,
      '$1',
    )
    .trim();
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
  text = text
    .replace(/^[{}\[\]]+|[{}\[\]]+$/g, '')
    .trim();
  text = text.replace(/\s+/g, ' ').trim();
  if (!text || text === '-' || text === '::') return '';
  return text;
}

function normalizedTagKey(value) {
  return stringValue(value)
    .toLowerCase()
    .replace(/[（）［］｛｝【】〈〉《》「」『』〔〕〖〗〘〙〚〛<>＜＞“”‘’]+/g, ' ')
    .replace(/[_＿\-‐‑‒–—−]+/g, ' ')
    .replace(/[(){}\[\]'":!?，、；;]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function isPseudoPartialRole(role, scriptSnapshot) {
  if (hasPseudoIdentityMarker(role)) return true;
  if (stringValue(role?.canonical_name)) return false;
  const rawIdentityTags = arrayValue(role?.raw_identity_tags).map(normalizeText);
  if (
    rawIdentityTags.some(
      (tag) => tag && !isBasicGenericIdentity(tag),
    )
  ) {
    return false;
  }
  const frames = new Map(
    arrayValue(scriptSnapshot?.frames).map((frame) => [Number(frame.index), frame]),
  );
  const captions = [];
  for (const appearance of arrayValue(role?.appearances)) {
    const sourceId = stringValue(appearance?.source_id);
    const slotIndex = slotIndexForSourceId(sourceId);
    if (slotIndex == null) continue;
    for (const frameIndex of numberList(appearance?.frame_indexes)) {
      const frame = frames.get(frameIndex);
      const caption = arrayValue(frame?.parsed?.charCaptions)[slotIndex];
      if (typeof caption === 'string' && caption.trim()) captions.push(caption);
    }
  }
  if (captions.length === 0) return false;
  return captions.every(
    (caption) => hasPartialOnlyMarker(caption) && !hasWholeCharacterMarker(caption),
  );
}

function hasPseudoIdentityMarker(role) {
  const identityTerms = [
    role?.canonical_name,
    ...arrayValue(role?.raw_identity_tags),
  ].map(normalizeText);
  return identityTerms.some(
    (term) =>
      /^(?:no humans?|foreskin|clitoral hood|labia|vulva|vagina|penis|testicles?|scrotum|nipples?|areolae?)$/.test(
        term,
      ) ||
      isParentheticalObjectIdentityTag(term) ||
      /^(?:touching|behind)(?:\s|$)/.test(term),
  );
}

function isParentheticalObjectIdentityTag(term) {
  const normalized = normalizeText(term);
  if (/^(?:ring of light|light ring|halo)$/.test(normalized)) return true;
  const match = normalized.match(/^([^()]+) \(([^()]+)\)$/);
  if (!match) return false;
  const base = match[1].trim();
  const qualifier = match[2].trim();
  return (
    /^(?:sword|weapon|object|item|vehicle)$/.test(qualifier) ||
    /^(?:ring of light|light ring|halo)$/.test(base) ||
    /\b(?:sword|weapon|shield|gun|rifle|pistol|staff|wand|spear|axe|dagger|knife|blade|hammer|vehicle|motorcycle)$/.test(
      base,
    )
  );
}

function hasIdentityReplacementRule(replacement) {
  return arrayValue(replacement?.rules).some((rule) => {
    if (stringValue(rule?.action).toLowerCase() !== 'replace') return false;
    if (!stringValue(rule?.targetPrompt)) return false;
    return arrayValue(rule?.sourceTerms).some((term) => {
      const category = normalizeText(term?.category);
      return category === 'character' || category === 'identity';
    });
  });
}

function uncoveredRolePromptTerms(role, replacement) {
  const covered = new Set();
  for (const rule of arrayValue(replacement?.rules)) {
    for (const term of arrayValue(rule?.sourceTerms)) {
      for (const key of promptTermCoverageKeys(term)) covered.add(key);
    }
  }
  return arrayValue(role?.prompt_terms).filter((term) => {
    const keys = promptTermCoverageKeys(term);
    return keys.length > 0 && !keys.some((key) => covered.has(key));
  });
}

function uncoveredRoleSourceIdentityTerms(role, replacement, scriptSnapshot) {
  const mappedIdentityTerms = [];
  for (const rule of arrayValue(replacement?.rules)) {
    for (const term of arrayValue(rule?.sourceTerms ?? rule?.source_terms)) {
      const category = normalizeText(term?.category);
      if (category !== 'character' && category !== 'identity') continue;
      const text = cleanPromptTag(
        term?.text ?? term?.sourcePhrase ?? term?.source_phrase,
      );
      const key = normalizedTagKey(text);
      if (key) mappedIdentityTerms.push({ term, key });
    }
  }

  const canonicalKey = normalizedTagKey(role?.canonical_name);
  const rawIdentityKeys = new Set(
    arrayValue(role?.raw_identity_tags)
      .map((tag) => normalizedTagKey(tag))
      .filter(Boolean),
  );
  const promptIdentityKeys = new Set(
    arrayValue(role?.prompt_terms)
      .filter((term) => {
        const category = normalizeText(term?.category);
        return category === 'character' || category === 'identity';
      })
      .map((term) => normalizedTagKey(term?.text))
      .filter(Boolean),
  );
  const frames = new Map(
    parsedFrames(scriptSnapshot).map((frame) => [Number(frame.index), frame]),
  );
  const gaps = [];
  const seen = new Set();

  for (const appearance of arrayValue(role?.appearances)) {
    const sourceId = stringValue(
      appearance?.source_id ?? appearance?.sourceId,
    );
    if (!sourceId) continue;
    const sourceLocation = sourceId === 'base' ? 'base prompt' : `${sourceId} prompt`;
    for (const frameIndex of numberList(
      appearance?.frame_indexes ?? appearance?.frameIndexes,
    )) {
      const frame = frames.get(frameIndex);
      if (!frame) continue;
      for (const sourceTerm of parsePromptTags(
        promptCaptionForSource(frame, sourceId),
      )) {
        if (!isSourceIdentityTerm(sourceTerm, {
          canonicalKey,
          rawIdentityKeys,
          promptIdentityKeys,
        })) {
          continue;
        }
        const key = normalizedTagKey(sourceTerm);
        const covered = mappedIdentityTerms.some(({ term, key: mappedKey }) =>
          mappedKey === key && sourceTermCoversFrame(term, frameIndex, sourceLocation),
        );
        if (covered) continue;
        const gapKey = `${key}\u001f${frameIndex}\u001f${sourceLocation}`;
        if (seen.has(gapKey)) continue;
        seen.add(gapKey);
        gaps.push({
          term: cleanPromptTag(sourceTerm),
          frameIndex,
          sourceLocation,
        });
      }
    }
  }
  return gaps;
}

function isSourceIdentityTerm(
  sourceTerm,
  { canonicalKey, rawIdentityKeys, promptIdentityKeys },
) {
  const cleaned = cleanPromptTag(sourceTerm);
  const key = normalizedTagKey(cleaned);
  if (!key || isBasicGenericIdentity(cleaned) || isParentheticalObjectIdentityTag(cleaned)) {
    return false;
  }
  const baseKey = parentheticalBaseKey(cleaned);
  if (canonicalKey && (key === canonicalKey || baseKey === canonicalKey)) {
    return true;
  }
  if (!rawIdentityKeys.has(key)) return false;
  if (canonicalKey) {
    return key.includes(canonicalKey) || baseKey === canonicalKey;
  }
  return promptIdentityKeys.has(key);
}

function parentheticalBaseKey(value) {
  const cleaned = cleanPromptTag(value);
  const match = cleaned.match(/^([^()]+)\s*\([^()]+\)$/);
  return normalizedTagKey(match ? match[1] : cleaned);
}

function sourceTermCoversFrame(term, frameIndex, sourceLocation) {
  const frameIndexes = numberList(term?.frameIndexes ?? term?.frame_indexes);
  if (frameIndexes.length > 0) return frameIndexes.includes(frameIndex);
  const occurrences = arrayValue(
    term?.sourceOccurrences ?? term?.source_occurrences,
  );
  if (occurrences.length === 0) return true;
  return occurrences.some((occurrence) => {
    const occurrenceFrame = Number(
      occurrence?.frameIndex ?? occurrence?.frame_index,
    );
    const occurrenceLocation = stringValue(
      occurrence?.sourceLocation ?? occurrence?.source_location,
    );
    return (
      occurrenceFrame === frameIndex &&
      (!occurrenceLocation || occurrenceLocation === sourceLocation)
    );
  });
}

function promptTermCoverageKeys(term) {
  const id = stringValue(term?.id).toLowerCase();
  const text = normalizeText(term?.text);
  const category = normalizeText(term?.category);
  return [
    id ? `id\u001f${id}` : '',
    text ? `text\u001f${category}\u001f${text}` : '',
  ].filter(Boolean);
}

function hasTarget(replacement) {
  return Boolean(stringValue(replacement?.targetCharacterId));
}

function isTargetableFemaleRole(role) {
  const text = roleIdentityText(role);
  return hasFemaleText(text) && !hasMaleText(text);
}

function isValidMappedFemaleRole(role) {
  if (isTargetableFemaleRole(role)) return true;
  if (isMaleRole(role)) return false;
  const hasConcreteIdentity = Boolean(
    stringValue(role?.canonical_name) ||
      arrayValue(role?.raw_identity_tags).some(
        (tag) => !isBasicGenericIdentity(tag),
      ),
  );
  if (!hasConcreteIdentity) return false;
  return promptTermArray(role).some((term) => {
    const category = normalizeText(term?.category);
    return (
      (category === 'identity' || category === 'character') &&
      hasFemaleText(normalizeText(term?.text))
    );
  });
}

function isMaleRole(role) {
  const text = roleIdentityText(role);
  return hasMaleText(text) && !hasFemaleText(text);
}

function roleIdentityText(role) {
  return [
    role?.source_role_id,
    role?.display_name,
    role?.canonical_name,
    role?.franchise,
    ...arrayValue(role?.raw_identity_tags),
    ...arrayValue(role?.variant_tags),
    ...arrayValue(role?.stages).map((stage) => stage?.identity),
  ]
    .map(normalizeText)
    .join(' ');
}

function hasFemaleText(text) {
  return /\b(?:\d+\s*girls?|girls?|female|woman|women|loli)\b/.test(text);
}

function hasMaleText(text) {
  return /\b(?:\d+\s*boys?|boys?|male|males|man|men|faceless male|fat man|old man|muscular male|musclar male)\b/.test(
    text,
  );
}

function captionIsMale(caption) {
  return hasMaleText(normalizeText(caption));
}

function hasPartialOnlyMarker(caption) {
  return /\b(?:pov hands?|only hands?|disembodied hands?|pov arms?)\b/.test(
    normalizeText(caption),
  );
}

function hasWholeCharacterMarker(caption) {
  return /\b(?:full body|whole body|entire body|body visible|torso|upper body|lower body|back view|from behind|standing|sitting|lying|kneeling|clothed|nude|naked|shirtless|faceless|bald)\b/.test(
    normalizeText(caption),
  );
}

function isBasicGenericIdentity(value) {
  return /^(?:\d+\s*girls?|girls?|female|woman|women|\d+\s*boys?|boys?|male|males|man|men|loli|child)$/.test(
    normalizeText(value),
  );
}

function slotIndexForSourceId(sourceId) {
  const match = /^slot-(\d+)$/.exec(sourceId);
  return match ? Number(match[1]) : null;
}

function numberList(value) {
  return arrayValue(value)
    .map(Number)
    .filter(Number.isFinite);
}

function integerValue(value) {
  if (typeof value === 'number') {
    return Number.isInteger(value) ? value : null;
  }
  if (typeof value === 'string' && /^-?\d+$/.test(value.trim())) {
    const parsed = Number(value.trim());
    return Number.isSafeInteger(parsed) ? parsed : null;
  }
  return null;
}

function normalizedLeaf(value) {
  return path.basename(stringValue(value).replaceAll('\\', '/')).toLowerCase();
}

function isUnderSourceRoot(value, root) {
  const current = normalizePath(value);
  return current === root || current.startsWith(`${root}/`);
}

function normalizePath(value) {
  return stringValue(value).replaceAll('\\', '/').replace(/\/$/, '').toLowerCase();
}

function normalizeText(value) {
  return stringValue(value)
    .replaceAll('_', ' ')
    .replaceAll('-', ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

function stringValue(value) {
  return value == null ? '' : String(value).trim();
}

function arrayValue(value) {
  return Array.isArray(value) ? value : [];
}

function parseArgs(args) {
  const parsed = {
    cacheDir: '',
    sourceRoot: '',
    report: '',
    regressionScriptId: '',
    regressionFrameFile: '',
    termReview: '',
  };
  for (let index = 0; index < args.length; index += 1) {
    const key = args[index];
    const value = args[index + 1];
    if (key === '--term-review' && (value == null || value.startsWith('--'))) {
      throw new Error('Missing value for --term-review.');
    }
    if (!key.startsWith('--') || value == null || value.startsWith('--')) continue;
    index += 1;
    if (key === '--cache-dir') parsed.cacheDir = value;
    if (key === '--source-root') parsed.sourceRoot = value;
    if (key === '--report') parsed.report = value;
    if (key === '--regression-script-id') parsed.regressionScriptId = value;
    if (key === '--regression-frame-file') parsed.regressionFrameFile = value;
    if (key === '--term-review') parsed.termReview = value;
  }
  return parsed;
}
