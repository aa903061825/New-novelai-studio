#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const TOOL_NAME = 'audit_merge_script_recast_mapping_rules_offline_20260820';
const REPORT_SCHEMA_VERSION = 1;
const SAMPLE_LIMIT = 100;
export const DEFAULT_TARGET_CHARACTER_IDS = Object.freeze([
  'legacy-character-sheet-r14',
  'legacy-character-sheet-r13',
  'legacy-character-sheet-r29',
  'legacy-character-sheet-r15',
  'legacy-character-sheet-r26',
]);

export function resolveDefaultWorkspace(env = process.env) {
  const appData = stringValue(env.APPDATA).trim();
  if (!appData) return '';
  return path.join(appData, 'Novel Studio', 'Novel Studio', 'novel_studio');
}

export function effectiveReplacementAction(rule) {
  if (stringValue(rule?.action).trim() === 'delete') return 'delete';
  if (stringValue(rule?.targetPrompt).trim()) return 'replace';
  const multiplier = finitePositiveNumberOrNull(rule?.targetWeightMultiplier);
  return multiplier == null ? 'none' : 'replace';
}

export function resolveRoleReplacementLayers(replacement, assembly) {
  const stages = arrayValue(assembly?.stages);
  const stageById = new Map(
    stages.map((stage) => [stringValue(stage?.id).trim(), stage]),
  );
  const overrideByRuleId = new Map();
  for (const override of arrayValue(replacement?.layerOverrides)) {
    const ruleId = stringValue(override?.ruleId).trim();
    if (ruleId) overrideByRuleId.set(ruleId, override);
  }

  const assignmentsByRuleId = new Map();
  for (const rule of arrayValue(replacement?.rules)) {
    const ruleId = stringValue(rule?.id).trim();
    const override = overrideByRuleId.get(ruleId);
    assignmentsByRuleId.set(
      ruleId,
      override
        ? manualLayerAssignment(ruleId, override, stageById)
        : automaticLayerAssignment(rule, stages),
    );
  }

  const specs = [
    {
      id: 'shared',
      label: '共享',
      kind: 'shared',
      stageId: '',
      frameIndexes: [],
    },
    ...stages.map((stage) => ({
      id: `stage:${stringValue(stage?.id).trim()}`,
      label: stringValue(stage?.label).trim(),
      kind: 'stage',
      stageId: stringValue(stage?.id).trim(),
      frameIndexes: normalizedFrameIndexes(stage?.frameIndexes),
    })),
    {
      id: 'pending',
      label: '待确认',
      kind: 'pending',
      stageId: '',
      frameIndexes: [],
    },
  ];
  const rules = arrayValue(replacement?.rules);
  const layers = specs.map((spec) => {
    const assignedRules = rules.filter(
      (rule) =>
        assignmentsByRuleId.get(stringValue(rule?.id).trim())?.layerId ===
        spec.id,
    );
    return {
      ...spec,
      ruleIds: assignedRules.map((rule) => stringValue(rule?.id).trim()),
      ruleCount: assignedRules.length,
      mappedRuleCount: assignedRules.filter(
        (rule) => effectiveReplacementAction(rule) !== 'none',
      ).length,
    };
  });
  return { layers, assignmentsByRuleId };
}

export function analyzeCacheForSafeMerges(
  cache,
  fileName = 'cache.json',
  options = {},
) {
  const mapping = objectValue(cache?.mapping);
  const assemblies = arrayValue(mapping?.roleAssemblies);
  const assemblyByRoleId = new Map(
    assemblies.map((assembly) => [
      stringValue(assembly?.sourceRoleId).trim(),
      assembly,
    ]),
  );
  const roleReplacements = arrayValue(mapping?.rolePromptReplacements);
  const safeGroups = [];
  const rejectedNearGroups = [];
  const emptyLayers = [];
  const noEffectRules = [];
  const suspiciousEmptyStages = [];
  const duplicateRuleIds = [];
  const targetCharacterIds = options.targetCharacterIds == null
    ? null
    : new Set(options.targetCharacterIds);
  let ruleCount = 0;
  let effectiveRuleCount = 0;
  let zeroRuleReplacementCount = 0;
  let zeroEffectiveRuleReplacementCount = 0;

  for (const replacement of roleReplacements) {
    const sourceRoleId = stringValue(replacement?.sourceRoleId).trim();
    const assembly = assemblyByRoleId.get(sourceRoleId);
    const layerResult = resolveRoleReplacementLayers(replacement, assembly);
    const rules = arrayValue(replacement?.rules);
    const ruleIdCounts = occurrenceCounts(
      rules.map((rule) => stringValue(rule?.id).trim()).filter(Boolean),
    );
    const duplicateRuleIdSet = new Set(
      [...ruleIdCounts.entries()]
        .filter(([, count]) => count > 1)
        .map(([id]) => id),
    );
    for (const ruleId of duplicateRuleIdSet) {
      duplicateRuleIds.push({
        file: fileName,
        scriptId: stringValue(cache?.scriptId),
        sourceRoleId,
        ruleId,
        count: ruleIdCounts.get(ruleId),
      });
    }
    ruleCount += rules.length;
    const effectiveRules = rules.filter(
      (rule) => effectiveReplacementAction(rule) !== 'none',
    );
    effectiveRuleCount += effectiveRules.length;
    if (rules.length === 0) zeroRuleReplacementCount += 1;
    if (effectiveRules.length === 0) zeroEffectiveRuleReplacementCount += 1;

    const sourceRuleKeys = new Set();
    for (const rule of rules) {
      for (const term of includedSourceTerms(rule)) {
        const key = normalizeSourceKey(term?.text || term?.sourcePhrase);
        if (key) sourceRuleKeys.add(key);
      }
      if (effectiveReplacementAction(rule) === 'none') {
        noEffectRules.push({
          file: fileName,
          scriptId: stringValue(cache?.scriptId),
          scriptName: stringValue(cache?.scriptName),
          sourceRoleId,
          displayLabel: stringValue(replacement?.displayLabel),
          ruleId: stringValue(rule?.id),
          layerId:
            layerResult.assignmentsByRuleId.get(stringValue(rule?.id).trim())
              ?.layerId ?? 'pending',
          classification: classifyNoEffectRule(rule, replacement),
          sourceTerms: includedSourceTerms(rule).map((term) => ({
            text: stringValue(term?.text),
            category: stringValue(term?.category),
          })),
        });
      }
    }

    for (const layer of layerResult.layers) {
      if (layer.ruleCount !== 0) continue;
      const row = {
        file: fileName,
        scriptId: stringValue(cache?.scriptId),
        scriptName: stringValue(cache?.scriptName),
        sourceRoleId,
        displayLabel: stringValue(replacement?.displayLabel),
        layerId: layer.id,
        kind: layer.kind,
        label: layer.label,
        frameIndexes: layer.frameIndexes,
      };
      emptyLayers.push(row);
      if (layer.kind === 'stage') {
        const stage = arrayValue(assembly?.stages).find(
          (candidate) => stringValue(candidate?.id).trim() === layer.stageId,
        );
        const sourcePartTerms = sourcePartTags(stage?.sourceParts);
        const uncoveredSourceParts = sourcePartTerms.filter(
          (term) => !sourceRuleKeys.has(normalizeSourceKey(term)),
        );
        const actionableUncoveredSourceParts = uncoveredSourceParts.filter(
          isPotentiallyMappableStageSourcePart,
        );
        if (
          stringValue(replacement?.targetCharacterId).trim() &&
          actionableUncoveredSourceParts.length > 0
        ) {
          suspiciousEmptyStages.push({
            ...row,
            sourcePartTerms,
            uncoveredSourceParts: actionableUncoveredSourceParts,
          });
        }
      }
    }

    const targetCharacterId = stringValue(replacement?.targetCharacterId).trim();
    if (
      targetCharacterIds == null ||
      targetCharacterIds.has(targetCharacterId)
    ) {
      const grouping = findSafeRuleMergeGroups({
        cache,
        replacement,
        assembly,
        layerResult,
        duplicateRuleIdSet,
        fileName,
      });
      safeGroups.push(...grouping.safeGroups);
      rejectedNearGroups.push(...grouping.rejectedNearGroups);
    }
  }

  return {
    file: fileName,
    scriptId: stringValue(cache?.scriptId),
    scriptName: stringValue(cache?.scriptName),
    roleReplacementCount: roleReplacements.length,
    ruleCount,
    effectiveRuleCount,
    zeroRuleReplacementCount,
    zeroEffectiveRuleReplacementCount,
    emptyLayers,
    noEffectRules,
    suspiciousEmptyStages,
    duplicateRuleIds,
    safeGroups,
    rejectedNearGroups,
  };
}

export function mergeSafeGroupsIntoCache(cache, analysis, now = new Date()) {
  const next = deepClone(cache);
  const replacements = arrayValue(next?.mapping?.rolePromptReplacements);
  const groupsByRoleId = new Map();
  for (const group of analysis.safeGroups) {
    const list = groupsByRoleId.get(group.sourceRoleId) ?? [];
    list.push(group);
    groupsByRoleId.set(group.sourceRoleId, list);
  }

  let rulesRemoved = 0;
  let groupsMerged = 0;
  for (const replacement of replacements) {
    const sourceRoleId = stringValue(replacement?.sourceRoleId).trim();
    const groups = groupsByRoleId.get(sourceRoleId) ?? [];
    if (groups.length === 0) continue;
    const ruleById = new Map(
      arrayValue(replacement?.rules).map((rule) => [
        stringValue(rule?.id).trim(),
        rule,
      ]),
    );
    const survivorByRuleId = new Map();
    const removedRuleIds = new Set();
    for (const group of groups) {
      const groupRules = group.ruleIds.map((id) => ruleById.get(id));
      if (groupRules.some((rule) => !rule)) {
        throw new Error(
          `Cache changed during merge planning: ${analysis.file} ${sourceRoleId}`,
        );
      }
      const survivor = groupRules[0];
      const mergedTerms = [];
      const seenTermIds = new Set();
      for (const rule of groupRules) {
        for (const term of arrayValue(rule?.sourceTerms)) {
          const termId = stringValue(term?.id).trim();
          if (!termId || seenTermIds.add(termId)) mergedTerms.push(term);
        }
      }
      survivorByRuleId.set(stringValue(survivor?.id).trim(), {
        ...survivor,
        sourceTerms: mergedTerms,
      });
      for (const rule of groupRules.slice(1)) {
        removedRuleIds.add(stringValue(rule?.id).trim());
      }
      rulesRemoved += groupRules.length - 1;
      groupsMerged += 1;
    }
    replacement.rules = arrayValue(replacement?.rules).flatMap((rule) => {
      const ruleId = stringValue(rule?.id).trim();
      if (removedRuleIds.has(ruleId)) return [];
      return [survivorByRuleId.get(ruleId) ?? rule];
    });
    if (Array.isArray(replacement.layerOverrides)) {
      replacement.layerOverrides = replacement.layerOverrides.filter(
        (override) => !removedRuleIds.has(stringValue(override?.ruleId).trim()),
      );
      if (replacement.layerOverrides.length === 0) {
        delete replacement.layerOverrides;
      }
    }
  }
  if (groupsMerged > 0) {
    next.updatedAt = normalizeTimestamp(now);
  }
  return { cache: next, rulesRemoved, groupsMerged };
}

export function analyzeProfileLibraryForSafeMerges(
  library,
  fileName = 'role_mapping_profiles.json',
) {
  const safeGroups = [];
  let blockCount = 0;
  for (const profile of arrayValue(library?.profiles)) {
    for (const layer of effectiveProfileLayers(profile)) {
      const blocks = arrayValue(layer?.blocks);
      blockCount += blocks.length;
      const byKey = new Map();
      for (const [blockIndex, block] of blocks.entries()) {
        const eligibility = profileBlockMergeEligibility(block);
        if (!eligibility.ok) continue;
        const list = byKey.get(eligibility.key) ?? [];
        list.push({ block, blockIndex });
        byKey.set(eligibility.key, list);
      }
      for (const entriesWithSameOutput of byKey.values()) {
        if (entriesWithSameOutput.length < 2) continue;
        const blocksWithSameOutput = entriesWithSameOutput.map(
          (entry) => entry.block,
        );
        if (profileGroupHasTargetSourceOverlap(blocksWithSameOutput)) continue;
        safeGroups.push({
          file: fileName,
          profileId: stringValue(profile?.id),
          profileName: stringValue(profile?.name),
          targetCharacterId: stringValue(profile?.targetCharacterId),
          layerId: stringValue(layer?.id),
          layerKind: stringValue(layer?.kind),
          action: effectiveReplacementAction(blocksWithSameOutput[0]),
          targetPrompt: stringValue(blocksWithSameOutput[0]?.targetPrompt),
          targetWeightMultiplier:
            finitePositiveNumberOrNull(
              blocksWithSameOutput[0]?.targetWeightMultiplier,
            ),
          blockIndexes: entriesWithSameOutput.map((entry) => entry.blockIndex),
          blockIds: blocksWithSameOutput.map((block) => stringValue(block?.id)),
          sourceTerms: blocksWithSameOutput.flatMap((block) =>
            arrayValue(block?.terms).map((term) => stringValue(term?.text)),
          ),
        });
      }
    }
  }
  return { blockCount, safeGroups };
}

export function mergeSafeGroupsIntoProfileLibrary(
  library,
  analysis,
  now = new Date(),
) {
  const next = deepClone(library);
  const groupsByProfileAndLayer = new Map();
  for (const group of analysis.safeGroups) {
    const key = `${group.profileId}\u001f${group.layerId}`;
    const list = groupsByProfileAndLayer.get(key) ?? [];
    list.push(group);
    groupsByProfileAndLayer.set(key, list);
  }
  let blocksRemoved = 0;
  let groupsMerged = 0;
  for (const profile of arrayValue(next?.profiles)) {
    let profileChanged = false;
    for (const layer of effectiveProfileLayers(profile)) {
      const key = `${stringValue(profile?.id)}\u001f${stringValue(layer?.id)}`;
      const groups = groupsByProfileAndLayer.get(key) ?? [];
      if (groups.length === 0) continue;
      const layerBlocks = arrayValue(layer?.blocks);
      const survivorByBlockIndex = new Map();
      const removedBlockIndexes = new Set();
      for (const group of groups) {
        const blocks = group.blockIndexes.map((index) => layerBlocks[index]);
        if (blocks.some((block) => !block)) {
          throw new Error(
            `Profile library changed during merge planning: ${group.profileId}`,
          );
        }
        const survivor = blocks[0];
        const survivorIndex = group.blockIndexes[0];
        survivorByBlockIndex.set(survivorIndex, {
          ...survivor,
          terms: mergeProfileTerms(blocks.flatMap((block) => arrayValue(block?.terms))),
        });
        for (const blockIndex of group.blockIndexes.slice(1)) {
          removedBlockIndexes.add(blockIndex);
        }
        blocksRemoved += blocks.length - 1;
        groupsMerged += 1;
        profileChanged = true;
      }
      layer.blocks = layerBlocks.flatMap((block, blockIndex) => {
        if (removedBlockIndexes.has(blockIndex)) return [];
        return [survivorByBlockIndex.get(blockIndex) ?? block];
      });
    }
    if (profileChanged) profile.updatedAt = normalizeTimestamp(now);
  }
  return { library: next, blocksRemoved, groupsMerged };
}

export function runOfflineAuditMerge(options) {
  const cacheDir = path.resolve(options.cacheDir);
  const sourceRoot = path.resolve(options.sourceRoot);
  const apply = Boolean(options.apply);
  const backupDir = options.backupDir
    ? path.resolve(options.backupDir)
    : '';
  const profileFile = options.profileFile
    ? path.resolve(options.profileFile)
    : '';
  const now = options.now instanceof Date ? options.now : new Date();
  if (!fs.existsSync(cacheDir) || !fs.statSync(cacheDir).isDirectory()) {
    throw new Error(`Missing cache directory: ${cacheDir}`);
  }
  if (apply && !backupDir) {
    throw new Error('--backup-dir is required with --apply.');
  }
  if (profileFile && !fs.existsSync(profileFile)) {
    throw new Error(`Missing role mapping profile file: ${profileFile}`);
  }

  const requestedFiles = new Set(
    arrayValue(options.cacheFiles)
      .flatMap((value) => stringValue(value).split(','))
      .map((value) => value.trim())
      .filter(Boolean),
  );
  const fileNames = fs
    .readdirSync(cacheDir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith('.json'))
    .map((entry) => entry.name)
    .filter((name) => requestedFiles.size === 0 || requestedFiles.has(name))
    .sort();
  const parseErrors = [];
  const fileAnalyses = [];
  const mutations = [];
  let scanned = 0;
  let matched = 0;

  for (const fileName of fileNames) {
    scanned += 1;
    const filePath = path.join(cacheDir, fileName);
    let cache;
    try {
      cache = readJson(filePath);
    } catch (error) {
      pushSample(parseErrors, { file: fileName, error: error.message });
      continue;
    }
    if (!isPathUnderRoot(cache?.sourceRootPath, sourceRoot)) continue;
    matched += 1;
    const analysis = analyzeCacheForSafeMerges(cache, fileName);
    fileAnalyses.push(analysis);
    if (analysis.safeGroups.length === 0) continue;
    const beforeInvariant = cacheInvariantHash(cache);
    const beforeTermLedger = sourceTermLedgerHash(cache);
    const merge = mergeSafeGroupsIntoCache(cache, analysis, now);
    validateMergedCache({
      before: cache,
      after: merge.cache,
      analysis,
      beforeInvariant,
      beforeTermLedger,
    });
    mutations.push({
      kind: 'cache',
      fileName,
      filePath,
      original: cache,
      updated: merge.cache,
      beforeHash: hashJson(cache),
      afterHash: hashJson(merge.cache),
      groupsMerged: merge.groupsMerged,
      entriesRemoved: merge.rulesRemoved,
    });
  }

  let profileAnalysis = null;
  if (profileFile) {
    const library = readJson(profileFile);
    profileAnalysis = analyzeProfileLibraryForSafeMerges(
      library,
      path.basename(profileFile),
    );
    if (profileAnalysis.safeGroups.length > 0) {
      const merge = mergeSafeGroupsIntoProfileLibrary(
        library,
        profileAnalysis,
        now,
      );
      validateMergedProfileLibrary(library, merge.library);
      mutations.push({
        kind: 'profile',
        fileName: path.basename(profileFile),
        filePath: profileFile,
        original: library,
        updated: merge.library,
        beforeHash: hashJson(library),
        afterHash: hashJson(merge.library),
        groupsMerged: merge.groupsMerged,
        entriesRemoved: merge.blocksRemoved,
      });
    }
  }

  if (parseErrors.length > 0) {
    throw new Error(
      `Refusing to apply or certify an incomplete scan; ${parseErrors.length} cache file(s) failed to parse.`,
    );
  }

  if (apply && mutations.length > 0) {
    prepareBackups(mutations, backupDir);
    for (const mutation of mutations) {
      writeJsonAtomic(mutation.filePath, mutation.updated);
      const persisted = readJson(mutation.filePath);
      if (hashJson(persisted) !== mutation.afterHash) {
        throw new Error(`Post-write verification failed: ${mutation.filePath}`);
      }
    }
  }

  const allSafeGroups = fileAnalyses.flatMap((analysis) => analysis.safeGroups);
  const emptyLayers = fileAnalyses.flatMap((analysis) => analysis.emptyLayers);
  const noEffectRules = fileAnalyses.flatMap((analysis) => analysis.noEffectRules);
  const suspiciousNoEffectRules = noEffectRules.filter(
    (row) => row.classification === 'suspicious-missing-effect',
  );
  const intentionalNoEffectRules = noEffectRules.filter(
    (row) => row.classification !== 'suspicious-missing-effect',
  );
  const suspiciousEmptyStages = fileAnalyses.flatMap(
    (analysis) => analysis.suspiciousEmptyStages,
  );
  const rejectedNearGroups = fileAnalyses.flatMap(
    (analysis) => analysis.rejectedNearGroups,
  );
  const cacheMutations = mutations.filter((mutation) => mutation.kind === 'cache');
  const profileMutation = mutations.find(
    (mutation) => mutation.kind === 'profile',
  );
  const report = {
    tool: TOOL_NAME,
    schema_version: REPORT_SCHEMA_VERSION,
    api_used: false,
    mode: apply ? 'apply' : 'dry-run',
    generated_at: normalizeTimestamp(now),
    workspace_path: options.workspace ? path.resolve(options.workspace) : '',
    cache_dir: cacheDir,
    cache_dir_real: safeRealPath(cacheDir),
    source_root: normalizePathForReport(sourceRoot),
    source_root_write_attempted: false,
    profile_file: profileFile,
    backup_dir: apply ? backupDir : '',
    summary: {
      cache_json_scanned: scanned,
      cache_files_matched: matched,
      parse_error_count: parseErrors.length,
      role_replacement_count: sum(fileAnalyses, 'roleReplacementCount'),
      rule_count_before: sum(fileAnalyses, 'ruleCount'),
      effective_rule_count_before: sum(fileAnalyses, 'effectiveRuleCount'),
      no_effect_rule_count: noEffectRules.length,
      intentional_or_preserved_no_effect_rule_count:
        intentionalNoEffectRules.length,
      suspicious_no_effect_rule_count: suspiciousNoEffectRules.length,
      zero_rule_replacement_count: sum(
        fileAnalyses,
        'zeroRuleReplacementCount',
      ),
      zero_effective_rule_replacement_count: sum(
        fileAnalyses,
        'zeroEffectiveRuleReplacementCount',
      ),
      empty_layer_count: emptyLayers.length,
      empty_shared_layer_count: emptyLayers.filter(
        (row) => row.kind === 'shared',
      ).length,
      empty_stage_layer_count: emptyLayers.filter(
        (row) => row.kind === 'stage',
      ).length,
      empty_pending_layer_count: emptyLayers.filter(
        (row) => row.kind === 'pending',
      ).length,
      suspicious_empty_stage_count: suspiciousEmptyStages.length,
      safe_cache_merge_group_count: allSafeGroups.length,
      safe_cache_rules_in_groups: allSafeGroups.reduce(
        (count, group) => count + group.ruleIds.length,
        0,
      ),
      cache_rules_removed_if_applied: cacheMutations.reduce(
        (count, mutation) => count + mutation.entriesRemoved,
        0,
      ),
      cache_files_changed_if_applied: cacheMutations.length,
      rejected_near_merge_group_count: rejectedNearGroups.length,
      profile_block_count_before: profileAnalysis?.blockCount ?? 0,
      safe_profile_merge_group_count:
        profileAnalysis?.safeGroups.length ?? 0,
      profile_blocks_removed_if_applied:
        profileMutation?.entriesRemoved ?? 0,
      files_written: apply ? mutations.length : 0,
    },
    zero_count_root_causes: {
      empty_layer_explanation:
        'The layer resolver emits shared, every role-assembly stage, and pending tabs even when a tab owns no rules. A displayed “0 条” can therefore be a structural empty stage rather than a missing cache.',
      mapped_count_explanation:
        'The UI mapped count includes only rules whose effective action is replace/delete or has a source-weight multiplier. Preserved source clothing/body-state rules intentionally have no effect and are not counted as mapped.',
      empty_layer_samples: emptyLayers.slice(0, SAMPLE_LIMIT),
      suspicious_empty_stage_samples: suspiciousEmptyStages.slice(
        0,
        SAMPLE_LIMIT,
      ),
      intentional_or_preserved_no_effect_samples: intentionalNoEffectRules.slice(
        0,
        SAMPLE_LIMIT,
      ),
      suspicious_no_effect_samples: suspiciousNoEffectRules.slice(
        0,
        SAMPLE_LIMIT,
      ),
    },
    safe_cache_merge_groups: allSafeGroups,
    rejected_near_merge_group_samples: rejectedNearGroups.slice(
      0,
      SAMPLE_LIMIT,
    ),
    profile_safe_merge_groups: profileAnalysis?.safeGroups ?? [],
    changed_files: mutations.map((mutation) => ({
      kind: mutation.kind,
      path: mutation.filePath,
      groups_merged: mutation.groupsMerged,
      entries_removed: mutation.entriesRemoved,
      before_sha256: mutation.beforeHash,
      after_sha256: mutation.afterHash,
      applied: apply,
    })),
    proof: {
      merge_contract: [
        'same role/profile layer owner',
        'same effective action and exact normalized target output',
        'match mode is any; no anchor, manual phrase, or exclusions',
        'same resolved replacement layer and same explicit override state',
        'same term frame-scope mode',
        'target output does not overlap a source term',
        'post-merge automatic/manual layer resolution is unchanged',
        'source term JSON ledger and all non-role-replacement cache fields are byte-semantically unchanged',
      ],
      source_root_read_only: true,
      project_api_or_credentials_used: false,
    },
  };
  return report;
}

function findSafeRuleMergeGroups({
  cache,
  replacement,
  assembly,
  layerResult,
  fileName,
}) {
  const strictGroupsByKey = new Map();
  const nearGroupsByKey = new Map();
  const ruleEligibilityById = new Map();
  for (const rule of arrayValue(replacement?.rules)) {
    const ruleId = stringValue(rule?.id).trim();
    const assignment = layerResult.assignmentsByRuleId.get(ruleId);
    const eligibility = ruleMergeEligibility(rule, replacement, assignment);
    ruleEligibilityById.set(ruleId, eligibility);
    if (eligibility.nearKey) {
      const near = nearGroupsByKey.get(eligibility.nearKey) ?? [];
      near.push(rule);
      nearGroupsByKey.set(eligibility.nearKey, near);
    }
    if (!eligibility.ok) continue;
    const list = strictGroupsByKey.get(eligibility.strictKey) ?? [];
    list.push(rule);
    strictGroupsByKey.set(eligibility.strictKey, list);
  }

  const safeGroups = [];
  const safeRuleIds = new Set();
  for (const rules of strictGroupsByKey.values()) {
    if (rules.length < 2) continue;
    const validation = validateRuleMergeGroup(rules);
    if (!validation.ok) continue;
    const first = rules[0];
    const firstAssignment = layerResult.assignmentsByRuleId.get(
      stringValue(first?.id).trim(),
    );
    const evidence = actualMergeEvidence({
      cache,
      replacement,
      assembly,
      rules,
    });
    const group = {
      file: fileName,
      scriptId: stringValue(cache?.scriptId),
      scriptName: stringValue(cache?.scriptName),
      sourceRoleId: stringValue(replacement?.sourceRoleId),
      displayLabel: stringValue(replacement?.displayLabel),
      targetCharacterId: stringValue(replacement?.targetCharacterId),
      layerId: firstAssignment?.layerId ?? 'pending',
      layerKind: firstAssignment?.kind ?? 'pending',
      stageId: firstAssignment?.stageId ?? '',
      explicitLayerOverride: firstAssignment?.isManual ?? false,
      action: effectiveReplacementAction(first),
      targetPrompt: stringValue(first?.targetPrompt),
      targetWeightMultiplier: finitePositiveNumberOrNull(
        first?.targetWeightMultiplier,
      ),
      ruleIds: rules.map((rule) => stringValue(rule?.id)),
      sourceTerms: rules.flatMap((rule) =>
        includedSourceTerms(rule).map((term) => ({
          id: stringValue(term?.id),
          text: stringValue(term?.text),
          category: stringValue(term?.category),
          frameIndexes: normalizedFrameIndexes(term?.frameIndexes),
        })),
      ),
      observed_hit_location_count: evidence.hitLocationCount,
      observed_multi_rule_hit_location_count: evidence.multiRuleHitLocationCount,
      observed_hit_samples: evidence.samples,
      proof: validation.proof,
    };
    safeGroups.push(group);
    for (const rule of rules) safeRuleIds.add(stringValue(rule?.id).trim());
  }

  const rejectedNearGroups = [];
  for (const rules of nearGroupsByKey.values()) {
    if (rules.length < 2) continue;
    const ids = rules.map((rule) => stringValue(rule?.id).trim());
    if (ids.every((id) => safeRuleIds.has(id))) continue;
    const reasons = new Set();
    const layers = new Set();
    const overrides = new Set();
    const scopes = new Set();
    for (const rule of rules) {
      const eligibility = ruleEligibilityById.get(stringValue(rule?.id).trim());
      for (const reason of eligibility?.reasons ?? []) reasons.add(reason);
      if (eligibility?.layerId) layers.add(eligibility.layerId);
      if (eligibility?.overrideSignature != null) {
        overrides.add(eligibility.overrideSignature);
      }
      if (eligibility?.scopeMode) scopes.add(eligibility.scopeMode);
    }
    if (layers.size > 1) reasons.add('different-resolved-layers');
    if (overrides.size > 1) reasons.add('different-explicit-layer-state');
    if (scopes.size > 1) reasons.add('different-frame-scope-mode');
    rejectedNearGroups.push({
      file: fileName,
      scriptId: stringValue(cache?.scriptId),
      sourceRoleId: stringValue(replacement?.sourceRoleId),
      targetCharacterId: stringValue(replacement?.targetCharacterId),
      targetPrompt: stringValue(rules[0]?.targetPrompt),
      ruleIds: ids,
      reasons: [...reasons].sort(),
    });
  }
  return { safeGroups, rejectedNearGroups };
}

function ruleMergeEligibility(rule, replacement, assignment) {
  const reasons = [];
  const action = effectiveReplacementAction(rule);
  const targetPrompt = canonicalTargetPrompt(rule?.targetPrompt);
  const multiplier = finitePositiveNumberOrNull(rule?.targetWeightMultiplier);
  const nearKey = action === 'none'
    ? ''
    : [
        action,
        targetPrompt,
        multiplier ?? '',
      ].join('\u001f');
  if (action === 'none') reasons.push('no-effective-action');
  if ((stringValue(rule?.matchMode).trim() || 'any') !== 'any') {
    reasons.push('non-any-match-mode');
  }
  if (stringValue(rule?.anchorTermId).trim()) reasons.push('anchor-rule');
  if (stringValue(rule?.manualPhrase).trim()) reasons.push('manual-phrase');
  if (arrayValue(rule?.excludedTermIds).length > 0) {
    reasons.push('excluded-source-terms');
  }
  const terms = includedSourceTerms(rule);
  if (terms.length === 0) reasons.push('no-included-source-terms');
  const scopeMode = sourceTermScopeMode(terms);
  if (scopeMode === 'mixed') reasons.push('mixed-frame-scope-within-rule');
  if (!assignment) reasons.push('missing-layer-assignment');
  const overrideSignature = assignment?.isManual
    ? `${assignment.kind}:${assignment.stageId}`
    : 'automatic';
  const layerId = assignment?.layerId ?? '';
  const strictKey = [
    stringValue(replacement?.targetCharacterId),
    action,
    targetPrompt,
    multiplier ?? '',
    layerId,
    overrideSignature,
    scopeMode,
  ].join('\u001f');
  return {
    ok: reasons.length === 0,
    reasons,
    nearKey,
    strictKey,
    layerId,
    overrideSignature,
    scopeMode,
  };
}

function validateRuleMergeGroup(rules) {
  const targetKeys = new Set(
    splitPromptTags(stringValue(rules[0]?.targetPrompt)).map(normalizeSourceKey),
  );
  const sourceKeys = new Set(
    rules.flatMap((rule) =>
      includedSourceTerms(rule).map((term) =>
        normalizeSourceKey(term?.text || term?.sourcePhrase),
      ),
    ),
  );
  sourceKeys.delete('');
  targetKeys.delete('');
  const overlap = [...sourceKeys].filter((key) => targetKeys.has(key));
  if (overlap.length > 0) {
    return { ok: false, proof: [], overlap };
  }
  const termJsonById = new Map();
  for (const rule of rules) {
    for (const term of arrayValue(rule?.sourceTerms)) {
      const id = stringValue(term?.id).trim();
      if (!id) continue;
      const encoded = stableStringify(term);
      const previous = termJsonById.get(id);
      if (previous != null && previous !== encoded) {
        return { ok: false, proof: [], conflictingTermId: id };
      }
      termJsonById.set(id, encoded);
    }
  }
  return {
    ok: true,
    proof: [
      'OR(A)->X plus OR(B)->X is merged as OR(A,B)->X',
      'source term evidence objects are retained unchanged',
      'same resolved layer and explicit override state',
      'target/source keys are disjoint',
    ],
  };
}

function actualMergeEvidence({ cache, replacement, assembly, rules }) {
  let hitLocationCount = 0;
  let multiRuleHitLocationCount = 0;
  const samples = [];
  for (const frame of arrayValue(cache?.scriptSnapshot?.frames)) {
    const frameIndex = integerOrNull(frame?.index);
    if (frameIndex == null) continue;
    const parsed = objectValue(frame?.parsed);
    const prompts = [
      { location: null, prompt: stringValue(parsed?.baseCaption) },
      ...arrayValue(parsed?.charCaptions).map((prompt, index) => ({
        location: index,
        prompt: stringValue(prompt),
      })),
    ];
    const fallbackLocations = fallbackPromptLocations(
      replacement,
      assembly,
      frameIndex,
    );
    for (const prompt of prompts) {
      const presentKeys = new Set(
        splitPromptTags(prompt.prompt).map(normalizeSourceKey).filter(Boolean),
      );
      const hitRuleIds = [];
      for (const rule of rules) {
        const terms = includedSourceTerms(rule).filter((term) =>
          termCanTargetPromptLocation(
            term,
            frameIndex,
            prompt.location,
            fallbackLocations,
          ),
        );
        if (
          terms.some((term) =>
            presentKeys.has(normalizeSourceKey(term?.text || term?.sourcePhrase)),
          )
        ) {
          hitRuleIds.push(stringValue(rule?.id));
        }
      }
      if (hitRuleIds.length === 0) continue;
      hitLocationCount += 1;
      if (hitRuleIds.length > 1) multiRuleHitLocationCount += 1;
      pushSample(samples, {
        frameIndex,
        location: prompt.location == null ? 'base' : `slot-${prompt.location}`,
        hitRuleIds,
      }, 10);
    }
  }
  return { hitLocationCount, multiRuleHitLocationCount, samples };
}

function termCanTargetPromptLocation(
  term,
  frameIndex,
  location,
  fallbackLocations,
) {
  const frameIndexes = normalizedFrameIndexes(term?.frameIndexes);
  if (frameIndexes.length > 0 && !frameIndexes.includes(frameIndex)) return false;
  const occurrences = arrayValue(term?.sourceOccurrences);
  if (occurrences.length > 0) {
    const current = occurrences.filter(
      (occurrence) => integerOrNull(occurrence?.frameIndex) === frameIndex,
    );
    if (current.length === 0) return false;
    const physical = new Set(
      current.flatMap((occurrence) =>
        physicalPromptLocations(occurrence?.sourceLocation),
      ),
    );
    if (physical.size > 0) return physical.has(location);
    return fallbackLocations.has(location);
  }
  const physical = new Set(physicalPromptLocations(term?.sourceLocation));
  if (physical.size > 0) return physical.has(location);
  return fallbackLocations.has(location);
}

function fallbackPromptLocations(replacement, assembly, frameIndex) {
  const locations = new Set();
  const appearances = arrayValue(assembly?.sourceAppearances);
  if (appearances.length > 0) {
    for (const appearance of appearances) {
      const frames = normalizedFrameIndexes(appearance?.frameIndexes);
      if (frames.length > 0 && !frames.includes(frameIndex)) continue;
      const sourceId = stringValue(appearance?.sourceId).trim().toLowerCase();
      const sourceKind = stringValue(appearance?.sourceKind).trim().toLowerCase();
      if (isBaseRoleSource(sourceId) || isBaseRoleSource(sourceKind)) {
        locations.add(null);
        continue;
      }
      const match = sourceId.match(/^slot-(\d+)$/);
      if (sourceKind === 'slot' || match) {
        const index = match ? Number.parseInt(match[1], 10) : null;
        if (index != null && index >= 0) locations.add(index);
      }
    }
    return locations;
  }
  const sourceRoleId = stringValue(replacement?.sourceRoleId).trim().toLowerCase();
  const match = sourceRoleId.match(/^slot-(\d+)$/);
  if (match) locations.add(Number.parseInt(match[1], 10));
  else if (isBaseRoleSource(sourceRoleId)) locations.add(null);
  return locations;
}

function physicalPromptLocations(value) {
  const normalized = stringValue(value).trim().toLowerCase();
  if (!normalized) return [];
  const locations = [];
  if (/(?:^|[^a-z0-9])base(?:[\s_-]+(?:prompt|caption))?(?:$|[^a-z0-9])/.test(normalized)) {
    locations.push(null);
  }
  for (const match of normalized.matchAll(/(?:^|[^a-z0-9])slot[-_\s]?(\d+)(?!\d)/g)) {
    const index = Number.parseInt(match[1], 10);
    if (Number.isInteger(index) && index >= 0) locations.push(index);
  }
  return locations;
}

function manualLayerAssignment(ruleId, override, stageById) {
  const kind = stringValue(override?.kind).trim() || 'pending';
  if (kind === 'shared') {
    return layerAssignment(ruleId, 'shared', '', true, false);
  }
  if (kind === 'stage') {
    const stageId = stringValue(override?.stageId).trim();
    if (stageById.has(stageId)) {
      return layerAssignment(ruleId, 'stage', stageId, true, false);
    }
    return layerAssignment(ruleId, 'pending', '', true, true);
  }
  return layerAssignment(ruleId, 'pending', '', true, false);
}

function automaticLayerAssignment(rule, stages) {
  const ruleId = stringValue(rule?.id).trim();
  const terms = includedSourceTerms(rule);
  if (terms.length === 0) return layerAssignment(ruleId, 'pending');
  if (
    terms.every(
      (term) => normalizeCategory(term?.category) === 'character',
    )
  ) {
    return layerAssignment(ruleId, 'shared');
  }
  if (stages.length === 0) return layerAssignment(ruleId, 'pending');
  const evidenceByTerm = new Map(
    terms.map((term) => [stringValue(term?.id), evidenceFrames(term)]),
  );
  if (
    [...evidenceByTerm.values()].every((frames) => frames.length === 0) &&
    stages.length === 1
  ) {
    return layerAssignment(ruleId, 'stage', stringValue(stages[0]?.id).trim());
  }
  if ([...evidenceByTerm.values()].some((frames) => frames.length === 0)) {
    return layerAssignment(ruleId, 'pending');
  }
  const stageIdsByFrame = new Map();
  for (const stage of stages) {
    const stageId = stringValue(stage?.id).trim();
    for (const frameIndex of normalizedFrameIndexes(stage?.frameIndexes)) {
      const ids = stageIdsByFrame.get(frameIndex) ?? new Set();
      ids.add(stageId);
      stageIdsByFrame.set(frameIndex, ids);
    }
  }
  const hitStageIdsByTerm = [];
  for (const frames of evidenceByTerm.values()) {
    const hit = new Set();
    for (const frameIndex of frames) {
      const containing = stageIdsByFrame.get(frameIndex) ?? new Set();
      if (containing.size !== 1) return layerAssignment(ruleId, 'pending');
      hit.add([...containing][0]);
    }
    hitStageIdsByTerm.push(hit);
  }
  const allStageIds = new Set(stages.map((stage) => stringValue(stage?.id).trim()));
  if (
    stages.length > 1 &&
    hitStageIdsByTerm.every(
      (ids) => ids.size === allStageIds.size && [...allStageIds].every((id) => ids.has(id)),
    )
  ) {
    return layerAssignment(ruleId, 'shared');
  }
  let uniqueStageId = null;
  for (const ids of hitStageIdsByTerm) {
    if (ids.size !== 1) return layerAssignment(ruleId, 'pending');
    const stageId = [...ids][0];
    if (uniqueStageId != null && uniqueStageId !== stageId) {
      return layerAssignment(ruleId, 'pending');
    }
    uniqueStageId = stageId;
  }
  return uniqueStageId == null
    ? layerAssignment(ruleId, 'pending')
    : layerAssignment(ruleId, 'stage', uniqueStageId);
}

function layerAssignment(
  ruleId,
  kind,
  stageId = '',
  isManual = false,
  hasStaleOverride = false,
) {
  return {
    ruleId,
    kind,
    stageId,
    layerId: kind === 'stage' ? `stage:${stageId}` : kind,
    isManual,
    hasStaleOverride,
  };
}

function profileBlockMergeEligibility(block) {
  const reasons = [];
  const action = effectiveReplacementAction(block);
  if (action === 'none') reasons.push('no-effective-action');
  if ((stringValue(block?.matchMode).trim() || 'any') !== 'any') {
    reasons.push('non-any-match-mode');
  }
  if (stringValue(block?.anchorTermKey).trim()) reasons.push('anchor-block');
  if (arrayValue(block?.terms).length === 0) reasons.push('no-source-terms');
  const key = [
    action,
    canonicalTargetPrompt(block?.targetPrompt),
    finitePositiveNumberOrNull(block?.targetWeightMultiplier) ?? '',
  ].join('\u001f');
  return { ok: reasons.length === 0, reasons, key };
}

function profileGroupHasTargetSourceOverlap(blocks) {
  const targetKeys = new Set(
    splitPromptTags(stringValue(blocks[0]?.targetPrompt)).map(normalizeSourceKey),
  );
  return blocks.some((block) =>
    arrayValue(block?.terms).some((term) =>
      targetKeys.has(normalizeSourceKey(term?.text)),
    ),
  );
}

function effectiveProfileLayers(profile) {
  const layers = arrayValue(profile?.layers);
  if (layers.length > 0) return layers;
  const blocks = arrayValue(profile?.blocks);
  if (blocks.length === 0) return [];
  return [{ id: 'legacy-shared', kind: 'shared', blocks }];
}

function mergeProfileTerms(terms) {
  // A profile can intentionally retain two evidence records whose normalized
  // display text is identical but whose ids or auto-detection provenance differ.
  // Merging containers must never collapse those source-evidence records.
  return [...terms];
}

function validateMergedCache({
  before,
  after,
  analysis,
  beforeInvariant,
  beforeTermLedger,
}) {
  if (cacheInvariantHash(after) !== beforeInvariant) {
    throw new Error(`Out-of-scope cache mutation detected: ${analysis.file}`);
  }
  if (sourceTermLedgerHash(after) !== beforeTermLedger) {
    throw new Error(`Source term evidence changed during merge: ${analysis.file}`);
  }
  const beforeReplacements = arrayValue(before?.mapping?.rolePromptReplacements);
  const afterReplacements = arrayValue(after?.mapping?.rolePromptReplacements);
  if (beforeReplacements.length !== afterReplacements.length) {
    throw new Error(`Role replacement owner count changed: ${analysis.file}`);
  }
  const expectedLayerBySurvivor = new Map(
    analysis.safeGroups.map((group) => [group.ruleIds[0], group.layerId]),
  );
  const afterAssemblyByRole = new Map(
    arrayValue(after?.mapping?.roleAssemblies).map((assembly) => [
      stringValue(assembly?.sourceRoleId),
      assembly,
    ]),
  );
  for (const replacement of afterReplacements) {
    const layerResult = resolveRoleReplacementLayers(
      replacement,
      afterAssemblyByRole.get(stringValue(replacement?.sourceRoleId)),
    );
    for (const [ruleId, expectedLayer] of expectedLayerBySurvivor.entries()) {
      const assignment = layerResult.assignmentsByRuleId.get(ruleId);
      if (assignment && assignment.layerId !== expectedLayer) {
        throw new Error(
          `Merged rule layer drifted in ${analysis.file}: ${ruleId} ${expectedLayer} -> ${assignment.layerId}`,
        );
      }
    }
  }
}

function validateMergedProfileLibrary(before, after) {
  if (profileInvariantHash(before) !== profileInvariantHash(after)) {
    throw new Error('Out-of-scope role mapping profile mutation detected.');
  }
  if (profileTermLedgerHash(before) !== profileTermLedgerHash(after)) {
    throw new Error('Role mapping profile source terms changed during merge.');
  }
}

function prepareBackups(mutations, backupDir) {
  fs.mkdirSync(backupDir, { recursive: true });
  const manifest = [];
  for (const mutation of mutations) {
    const backupPath = path.join(backupDir, mutation.fileName);
    if (fs.existsSync(backupPath)) {
      throw new Error(`Refusing to overwrite existing backup: ${backupPath}`);
    }
    fs.copyFileSync(mutation.filePath, backupPath, fs.constants.COPYFILE_EXCL);
    manifest.push({
      kind: mutation.kind,
      source: mutation.filePath,
      backup: backupPath,
      sha256: mutation.beforeHash,
    });
  }
  const manifestPath = path.join(backupDir, 'manifest.json');
  if (fs.existsSync(manifestPath)) {
    throw new Error(`Refusing to overwrite existing backup manifest: ${manifestPath}`);
  }
  fs.writeFileSync(
    manifestPath,
    `${JSON.stringify({ tool: TOOL_NAME, files: manifest }, null, 2)}\n`,
    'utf8',
  );
}

function writeJsonAtomic(filePath, value) {
  const temporary = `${filePath}.${process.pid}.${Date.now()}.tmp`;
  try {
    fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
    fs.renameSync(temporary, filePath);
  } finally {
    if (fs.existsSync(temporary)) fs.rmSync(temporary, { force: true });
  }
}

function cacheInvariantHash(cache) {
  const clone = deepClone(cache);
  delete clone.updatedAt;
  if (clone.mapping) delete clone.mapping.rolePromptReplacements;
  return hashJson(clone);
}

function sourceTermLedgerHash(cache) {
  const rows = [];
  for (const replacement of arrayValue(cache?.mapping?.rolePromptReplacements)) {
    const roleId = stringValue(replacement?.sourceRoleId);
    for (const rule of arrayValue(replacement?.rules)) {
      for (const term of arrayValue(rule?.sourceTerms)) {
        rows.push(`${roleId}\u001f${stringValue(term?.id)}\u001f${stableStringify(term)}`);
      }
    }
  }
  rows.sort();
  return sha256(rows.join('\n'));
}

function profileInvariantHash(library) {
  const clone = deepClone(library);
  for (const profile of arrayValue(clone?.profiles)) {
    delete profile.updatedAt;
    for (const layer of effectiveProfileLayers(profile)) delete layer.blocks;
    delete profile.blocks;
  }
  return hashJson(clone);
}

function profileTermLedgerHash(library) {
  const rows = [];
  for (const profile of arrayValue(library?.profiles)) {
    for (const layer of effectiveProfileLayers(profile)) {
      for (const block of arrayValue(layer?.blocks)) {
        for (const term of arrayValue(block?.terms)) {
          rows.push(
            `${stringValue(profile?.id)}\u001f${stringValue(layer?.id)}\u001f${stableStringify(term)}`,
          );
        }
      }
    }
  }
  rows.sort();
  return sha256(rows.join('\n'));
}

function classifyNoEffectRule(rule, replacement) {
  if (!stringValue(replacement?.targetCharacterId).trim()) {
    return 'unassigned-role';
  }
  return includedSourceTerms(rule).some(requiresExplicitMappingPolicy)
    ? 'suspicious-missing-effect'
    : 'intentional-preserve-or-transient';
}

function requiresExplicitMappingPolicy(term) {
  const category = normalizeCategory(term?.category);
  const source = spacedText(term?.text || term?.sourcePhrase);
  if (!source.trim()) return false;
  if (category === 'character' || category === 'identity') {
    return !/^(?:girl|girls|female|woman|women|loli|young|1girl|2girls)$/.test(
      normalizeSourceKey(source),
    );
  }
  if (isSpecialClothing(source)) return true;
  if (isNonwhiteUnderwearOrHosiery(source)) return true;
  if (isNegatedAppearance(source)) return true;
  if (isLowerDecoration(category, source)) return true;
  if (
    ['upperbody', 'lowerbody', 'body', 'accessory'].includes(category) &&
    /\b(?:hair|ears?|horns?|halo|tails?|hair ribbon|hair ornament|headdress|headwear|headband|hairband)\b/.test(
      source,
    ) &&
    !/\b(?:wet|messy|tousled|damp|disheveled|flowing|floating|loose|spread)\b/.test(
      source,
    )
  ) {
    return true;
  }
  return false;
}

function isSpecialClothing(value) {
  const compact = normalizeSourceKey(value).replaceAll(' ', '');
  return [
    'bunnysuit',
    'bunnygirl',
    'bunnycostume',
    'rabbitsuit',
    'rabbitgirl',
    'leotard',
    'bodysuit',
    'catsuit',
    'plugsuit',
    'pilotsuit',
    'unitsuit',
    'unitard',
    'skinsuit',
    'skintight',
    'tightclothing',
    'tightoutfit',
    'bodycon',
    'latex',
    'wetsuit',
    'racingsuit',
    'competitionwear',
  ].some((needle) => compact.includes(needle));
}

function isNonwhiteUnderwearOrHosiery(value) {
  const source = normalizeSourceKey(value);
  return /\b(?:pantyhose|thighhighs|thigh highs|stockings?|tights|socks?|leggings|lingerie|bras?|thongs?|panties|underwear)\b/.test(
    source,
  ) &&
    /\b(?:aqua|beige|black|blue|brown|cyan|gold|gray|grey|green|lavender|magenta|maroon|navy|orange|purple|red|silver|violet|yellow)\b/.test(
      source,
    );
}

function isNegatedAppearance(value) {
  const source = normalizeSourceKey(value);
  return /\b(?:no|without|lack of)\b/.test(source) &&
    /\b(?:hair|ears?|horns?|halo|tails?|ornament|ribbon|headdress|headpiece|hood|hat|headband|hairband)\b/.test(
      source,
    );
}

function isLowerDecoration(category, value) {
  if (!['lowerbody', 'lowerclothing', 'accessory'].includes(category)) {
    return false;
  }
  const source = normalizeSourceKey(value);
  if (/\b(?:hair|head|face|ears?|headdress|headband|hairband)\b/.test(source)) {
    return false;
  }
  return /\b(?:anklet|garter|garter belt|tail|leg strap|leg ribbon|leg ornament|legwear|thigh strap)\b/.test(
    source,
  );
}

function isPotentiallyMappableStageSourcePart(value) {
  const source = normalizeSourceKey(value);
  if (!source) return false;
  if (isSpecialClothing(source)) return true;
  if (isNonwhiteUnderwearOrHosiery(source)) return true;
  if (isNegatedAppearance(source)) return true;
  return /\b(?:hair|ears?|horns?|halo|tails?|ornament|ribbon|headdress|headpiece|hood|hat|headband|hairband|choker|garter|anklet|leg strap|leg ribbon|leg ornament|thigh strap)\b/.test(
    source,
  );
}

function sourcePartTags(sourceParts) {
  return Object.values(objectValue(sourceParts)).flatMap((value) =>
    splitPromptTags(stringValue(value)),
  );
}

function sourceTermScopeMode(terms) {
  const scoped = terms.filter(
    (term) => normalizedFrameIndexes(term?.frameIndexes).length > 0,
  ).length;
  if (scoped === 0) return 'unscoped';
  if (scoped === terms.length) return 'scoped';
  return 'mixed';
}

function includedSourceTerms(rule) {
  const excluded = new Set(arrayValue(rule?.excludedTermIds).map(stringValue));
  return arrayValue(rule?.sourceTerms).filter(
    (term) => !excluded.has(stringValue(term?.id)),
  );
}

function evidenceFrames(term) {
  const occurrences = arrayValue(term?.sourceOccurrences);
  if (occurrences.length > 0) {
    return normalizedFrameIndexes(
      occurrences.map((occurrence) => occurrence?.frameIndex),
    );
  }
  return normalizedFrameIndexes(term?.frameIndexes);
}

function normalizedFrameIndexes(values) {
  return [
    ...new Set(
      arrayValue(values)
        .map(integerOrNull)
        .filter((value) => value != null && value >= 0),
    ),
  ].sort((left, right) => left - right);
}

function normalizeCategory(value) {
  return stringValue(value)
    .toLowerCase()
    .replaceAll('_', '')
    .replaceAll('-', '')
    .replaceAll(' ', '');
}

function canonicalTargetPrompt(value) {
  return splitPromptTags(stringValue(value))
    .map((tag) => tag.replace(/\s+/g, ' ').trim().toLowerCase())
    .join(', ');
}

function splitPromptTags(value) {
  return stringValue(value)
    .split(',')
    .map((tag) => tag.trim())
    .filter(Boolean);
}

function normalizeSourceKey(value) {
  let text = stringValue(value).trim().toLowerCase();
  text = text.replace(/^[+-]?\d+(?:\.\d+)?\s*::\s*/, '');
  text = text.replace(/\s*::\s*$/, '');
  const weighted = text.match(/^\((.*):[+-]?\d+(?:\.\d+)?\)$/);
  if (weighted) text = weighted[1];
  return text
    .replaceAll('_', ' ')
    .replaceAll('-', ' ')
    .replace(/[{}\[\]]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function spacedText(value) {
  return ` ${normalizeSourceKey(value)} `;
}

function isBaseRoleSource(value) {
  return ['base', 'base-role', 'base role', 'global', 'shared'].includes(
    stringValue(value).trim().toLowerCase(),
  );
}

function finitePositiveNumberOrNull(value) {
  const number = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(number) && number > 0 ? number : null;
}

function integerOrNull(value) {
  const number = typeof value === 'number' ? value : Number(value);
  return Number.isInteger(number) ? number : null;
}

function normalizeTimestamp(value) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) throw new Error(`Invalid timestamp: ${value}`);
  return date.toISOString();
}

function isPathUnderRoot(candidate, root) {
  const normalizedCandidate = normalizePathForCompare(candidate);
  const normalizedRoot = normalizePathForCompare(root);
  return (
    normalizedCandidate === normalizedRoot ||
    normalizedCandidate.startsWith(`${normalizedRoot}/`)
  );
}

function normalizePathForCompare(value) {
  return stringValue(value)
    .replaceAll('\\', '/')
    .replace(/\/+$/, '')
    .toLowerCase();
}

function normalizePathForReport(value) {
  return stringValue(value).replaceAll('\\', '/').replace(/\/+$/, '');
}

function safeRealPath(value) {
  try {
    return fs.realpathSync(value);
  } catch {
    return value;
  }
}

function hashJson(value) {
  return sha256(stableStringify(value));
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function stableStringify(value) {
  return JSON.stringify(sortJson(value));
}

function sortJson(value) {
  if (Array.isArray(value)) return value.map(sortJson);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(
    Object.keys(value)
      .sort()
      .map((key) => [key, sortJson(value[key])]),
  );
}

function deepClone(value) {
  return JSON.parse(JSON.stringify(value));
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function arrayValue(value) {
  return Array.isArray(value) ? value : [];
}

function objectValue(value) {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value
    : {};
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function sum(rows, key) {
  return rows.reduce((total, row) => total + (Number(row?.[key]) || 0), 0);
}

function occurrenceCounts(values) {
  const counts = new Map();
  for (const value of values) {
    counts.set(value, (counts.get(value) ?? 0) + 1);
  }
  return counts;
}

function pushSample(array, value, limit = SAMPLE_LIMIT) {
  if (array.length < limit) array.push(value);
}

function parseArgs(argv) {
  const parsed = {
    workspace: '',
    cacheDir: '',
    sourceRoot: String.raw`E:\NAI的脚本群\作品集\带图精品`,
    profileFile: '',
    report: '',
    backupDir: '',
    cacheFiles: [],
    apply: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--apply') {
      parsed.apply = true;
      continue;
    }
    if (!argument.startsWith('--')) continue;
    const equalIndex = argument.indexOf('=');
    const key = equalIndex < 0
      ? argument.slice(2)
      : argument.slice(2, equalIndex);
    const value = equalIndex < 0 ? argv[++index] : argument.slice(equalIndex + 1);
    if (value == null) throw new Error(`Missing value for --${key}`);
    if (key === 'workspace') parsed.workspace = value;
    else if (key === 'cache-dir') parsed.cacheDir = value;
    else if (key === 'source-root') parsed.sourceRoot = value;
    else if (key === 'profile-file') parsed.profileFile = value;
    else if (key === 'report') parsed.report = value;
    else if (key === 'backup-dir') parsed.backupDir = value;
    else if (key === 'cache-file') parsed.cacheFiles.push(value);
    else throw new Error(`Unknown argument: --${key}`);
  }
  parsed.workspace = parsed.workspace || resolveDefaultWorkspace();
  if (!parsed.cacheDir) {
    if (!parsed.workspace) {
      throw new Error('Pass --workspace or --cache-dir.');
    }
    parsed.cacheDir = path.join(parsed.workspace, 'script_recast', 'cache');
  }
  if (!parsed.sourceRoot) throw new Error('Pass --source-root.');
  return parsed;
}

function isMainModule() {
  if (!process.argv[1]) return false;
  return path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url));
}

if (isMainModule()) {
  try {
    const options = parseArgs(process.argv.slice(2));
    const report = runOfflineAuditMerge(options);
    if (options.report) {
      const reportPath = path.resolve(options.report);
      fs.mkdirSync(path.dirname(reportPath), { recursive: true });
      fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
    }
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  } catch (error) {
    process.stderr.write(`${error?.stack || error}\n`);
    process.exitCode = 1;
  }
}
