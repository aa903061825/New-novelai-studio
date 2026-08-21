#!/usr/bin/env node
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
const defaultSourceRoot =
  'E:/NAI\u7684\u811a\u672c\u7fa4/\u4f5c\u54c1\u96c6/\u5e26\u56fe\u7cbe\u54c1';

const targetRegressionGroups = [
  {
    id: 'hair_bun',
    label: '\u4e38\u5b50\u5934',
    terms: ['hair bun', 'bun hair', 'single hair bun'],
  },
  {
    id: 'double_bun',
    label: '\u53cc\u4e38\u5b50\u5934',
    terms: ['double bun', 'double hair bun', 'two hair buns'],
  },
  {
    id: 'twintails',
    label: '\u53cc\u9a6c\u5c3e',
    terms: ['twintails', 'twin tails', 'two side up'],
  },
  {
    id: 'wings',
    label: '\u7fc5\u8180',
    terms: ['wings', 'angel wings', 'demon wings', 'bat wings', 'cristal wings', 'crystal wings'],
  },
  {
    id: 'gyaru',
    label: '\u8fa3\u59b9',
    terms: ['gyaru', 'gal'],
  },
  {
    id: 'demon_girl',
    label: '\u6076\u9b54\u5c11\u5973',
    terms: ['demon girl', 'devil girl', 'demon horns', 'demon tail'],
  },
];

const options = parseArgs(process.argv.slice(2));
if (options.help) {
  printHelp();
  process.exit(0);
}

const cacheDir = path.resolve(options.cacheDir ?? defaultCacheDir);
const sourceRoot = normalizePath(options.sourceRoot ?? defaultSourceRoot);
const reportPath = options.report ? path.resolve(options.report) : null;
const schema = options.schema ? loadRepairSchema(path.resolve(options.schema)) : null;
const backupDir =
  options.backupDir ??
  path.join(
    cacheDir,
    `_backup_complete_terms_${new Date().toISOString().replace(/[:.]/g, '-')}`,
  );

if (!fs.existsSync(cacheDir)) {
  throw new Error(`Missing cache dir: ${cacheDir}`);
}

const files = fs
  .readdirSync(cacheDir)
  .filter((file) => file.endsWith('.json'))
  .sort();

const report = {
  tool: 'script_recast_complete_term_audit',
  api_used: false,
  apply: options.apply,
  cache_dir: cacheDir,
  source_root: sourceRoot,
  schema_path: options.schema ? path.resolve(options.schema) : null,
  backup_dir: options.apply ? backupDir : null,
  files_scanned: files.length,
  eligible_cache_files: 0,
  duplicate_script_ids: [],
  source_script_dir_count: 0,
  cached_source_path_count: 0,
  source_dirs_without_cache_count: 0,
  source_dirs_without_cache_sample: [],
  cached_source_paths_without_image_dir_count: 0,
  cached_source_paths_without_image_dir_sample: [],
  cached_paths_missing_on_disk_count: 0,
  cached_paths_missing_on_disk_sample: [],
  files_with_uncovered_source_terms: 0,
  files_with_target_regression_candidates: 0,
  files_changed: 0,
  role_prompt_terms_merged: 0,
  scene_terms_merged: 0,
  role_mapping_rules_merged: 0,
  scene_mapping_rules_merged: 0,
  rows: [],
};

const scriptIdFiles = new Map();
const cachedSourcePaths = new Set();
const cachedPathsMissingOnDisk = new Set();

for (const fileName of files) {
  const filePath = path.join(cacheDir, fileName);
  const cache = loadJson(filePath);
  if (!cache || !looksLikeRecastCache(cache)) continue;
  if (!isUnderSourceRoot(cache.sourceRootPath, sourceRoot)) continue;
  report.eligible_cache_files += 1;
  const sourcePath = normalizePath(cache.sourceRootPath);
  if (sourcePath) {
    cachedSourcePaths.add(sourcePath);
    if (!fs.existsSync(cache.sourceRootPath)) {
      cachedPathsMissingOnDisk.add(sourcePath);
    }
  }

  const scriptId = stringValue(cache.scriptId);
  const seen = scriptIdFiles.get(scriptId) ?? [];
  seen.push(fileName);
  scriptIdFiles.set(scriptId, seen);

  const schemaEntry = schemaEntryForCache(schema, cache);
  const beforeText = JSON.stringify(cache);
  const audit = auditCache(fileName, cache, schemaEntry);

  if (audit.uncovered_source_term_count > 0) {
    report.files_with_uncovered_source_terms += 1;
  }
  if (audit.target_regression_candidates.length > 0) {
    report.files_with_target_regression_candidates += 1;
  }

  let nextCache = cache;
  let repair = emptyRepairResult();
  if (schemaEntry) {
    repair = mergeSchemaIntoCache(cache, schemaEntry);
    nextCache = repair.cache;
  }

  const afterText = JSON.stringify(nextCache);
  const changed = beforeText !== afterText;
  if (changed) {
    report.files_changed += 1;
    report.role_prompt_terms_merged += repair.rolePromptTermsMerged;
    report.scene_terms_merged += repair.sceneTermsMerged;
    report.role_mapping_rules_merged += repair.roleMappingRulesMerged;
    report.scene_mapping_rules_merged += repair.sceneMappingRulesMerged;
  }

  if (
    options.reportUnchanged ||
    audit.uncovered_source_term_count > 0 ||
    audit.target_regression_candidates.length > 0 ||
    changed
  ) {
    report.rows.push({
      ...audit,
      would_change: changed,
      role_prompt_terms_merged: repair.rolePromptTermsMerged,
      scene_terms_merged: repair.sceneTermsMerged,
      role_mapping_rules_merged: repair.roleMappingRulesMerged,
      scene_mapping_rules_merged: repair.sceneMappingRulesMerged,
    });
  }

  if (options.apply && changed) {
    fs.mkdirSync(backupDir, { recursive: true });
    fs.copyFileSync(filePath, path.join(backupDir, fileName));
    nextCache.updatedAt = new Date().toISOString();
    fs.writeFileSync(filePath, `${JSON.stringify(nextCache, null, 2)}\n`, 'utf8');
  }
}

for (const [scriptId, names] of scriptIdFiles) {
  if (scriptId && names.length > 1) {
    report.duplicate_script_ids.push({ script_id: scriptId, files: names });
  }
}

const sourceScriptDirs = findImageScriptDirs(sourceRoot);
const sourceScriptDirSet = new Set(sourceScriptDirs);
const sourceDirsWithoutCache = sourceScriptDirs.filter(
  (dir) => !cachedSourcePaths.has(dir),
);
const cachedPathsWithoutImageDir = [...cachedSourcePaths]
  .filter((dir) => !sourceScriptDirSet.has(dir))
  .sort();
report.source_script_dir_count = sourceScriptDirs.length;
report.cached_source_path_count = cachedSourcePaths.size;
report.source_dirs_without_cache_count = sourceDirsWithoutCache.length;
report.source_dirs_without_cache_sample = sourceDirsWithoutCache.slice(0, 50);
report.cached_source_paths_without_image_dir_count =
  cachedPathsWithoutImageDir.length;
report.cached_source_paths_without_image_dir_sample =
  cachedPathsWithoutImageDir.slice(0, 50);
report.cached_paths_missing_on_disk_count = cachedPathsMissingOnDisk.size;
report.cached_paths_missing_on_disk_sample = [...cachedPathsMissingOnDisk].slice(0, 50);

if (reportPath) {
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
}
console.log(JSON.stringify(report, null, 2));

if (
  options.assertTargets &&
  (report.files_with_target_regression_candidates > 0 ||
    report.duplicate_script_ids.length > 0)
) {
  process.exitCode = 2;
}

function auditCache(fileName, cache, schemaEntry) {
  const sourceTerms = collectSourceTerms(cache);
  const aiRoleTermKeys = roleAiTermKeySet(cache);
  const aiSceneTermKeys = sceneAiTermKeySet(cache);
  const mappedRoleTermKeys = roleMappingTermKeySet(cache);
  const mappedSceneTermKeys = sceneMappingTermKeySet(cache);
  const coveredKeys = new Set([
    ...aiRoleTermKeys.global,
    ...aiSceneTermKeys,
    ...mappedRoleTermKeys.global,
    ...mappedSceneTermKeys,
  ]);
  const uncovered = sourceTerms.filter((term) => !coveredKeys.has(term.normalized));
  const targetCandidates = targetRegressionCandidates({
    sourceTerms,
    aiRoleTermKeys,
    aiSceneTermKeys,
    mappedRoleTermKeys,
    mappedSceneTermKeys,
  });

  return {
    file_name: fileName,
    script_id: stringValue(cache.scriptId),
    script_name: stringValue(cache.scriptName),
    source_term_count: sourceTerms.length,
    ai_role_prompt_term_count: aiRoleTermKeys.global.size,
    ai_scene_term_count: aiSceneTermKeys.size,
    mapped_role_prompt_term_count: mappedRoleTermKeys.global.size,
    mapped_scene_prompt_term_count: mappedSceneTermKeys.size,
    uncovered_source_term_count: uncovered.length,
    uncovered_source_terms_sample: uncovered.slice(0, 30),
    target_regression_candidates: targetCandidates,
    schema_terms_present: Boolean(schemaEntry),
  };
}

function collectSourceTerms(cache) {
  const terms = new Map();
  const frames = Array.isArray(cache.scriptSnapshot?.frames)
    ? cache.scriptSnapshot.frames
    : [];

  const addCaption = ({ caption, frameIndex, sourceId, sourceKind, polarity }) => {
    for (const tag of parseTags(caption)) {
      const text = cleanTag(tag);
      const normalized = normalizedTagKey(text);
      if (!normalized) continue;
      const key = `${polarity}\u001f${normalized}`;
      const existing = terms.get(key);
      if (existing) {
        addSorted(existing.frame_indexes, frameIndex);
        existing.sources.add(sourceId);
        return;
      }
      terms.set(key, {
        text,
        normalized,
        polarity,
        frame_indexes: [frameIndex],
        sources: new Set([sourceId]),
        source_kinds: new Set([sourceKind]),
      });
    }
  };

  for (const frame of frames) {
    const frameIndex = Number(frame?.index);
    if (!Number.isInteger(frameIndex)) continue;
    const parsed = frame.parsed ?? {};
    addCaption({
      caption: parsed.baseCaption,
      frameIndex,
      sourceId: 'base',
      sourceKind: 'base',
      polarity: 'positive',
    });
    const charCaptions = Array.isArray(parsed.charCaptions)
      ? parsed.charCaptions
      : [];
    charCaptions.forEach((caption, slotIndex) => {
      addCaption({
        caption,
        frameIndex,
        sourceId: `slot-${slotIndex}`,
        sourceKind: 'slot',
        polarity: 'positive',
      });
    });
    addCaption({
      caption: parsed.negativeBase,
      frameIndex,
      sourceId: 'negative-base',
      sourceKind: 'negative',
      polarity: 'negative',
    });
    const negativeCaptions = Array.isArray(parsed.negativeCharCaptions)
      ? parsed.negativeCharCaptions
      : [];
    negativeCaptions.forEach((caption, slotIndex) => {
      addCaption({
        caption,
        frameIndex,
        sourceId: `negative-slot-${slotIndex}`,
        sourceKind: 'negative',
        polarity: 'negative',
      });
    });
  }

  return [...terms.values()].map((term) => ({
    text: term.text,
    normalized: term.normalized,
    polarity: term.polarity,
    frame_indexes: term.frame_indexes,
    sources: [...term.sources].sort(),
    source_kinds: [...term.source_kinds].sort(),
  }));
}

function roleAiTermKeySet(cache) {
  const byRole = new Map();
  const global = new Set();
  for (const role of cache.aiRoleExtraction?.roles ?? []) {
    const sourceRoleId = stringValue(role.source_role_id ?? role.sourceRoleId);
    const set = byRole.get(sourceRoleId) ?? new Set();
    for (const term of role.prompt_terms ?? role.promptTerms ?? []) {
      const key = normalizedTagKey(term?.text);
      if (!key) continue;
      set.add(key);
      global.add(key);
    }
    byRole.set(sourceRoleId, set);
  }
  return { byRole, global };
}

function sceneAiTermKeySet(cache) {
  const set = new Set();
  for (const term of cache.aiRoleExtraction?.scene_terms ??
    cache.aiRoleExtraction?.sceneTerms ??
    []) {
    const key = normalizedTagKey(term?.text);
    if (key) set.add(key);
  }
  return set;
}

function roleMappingTermKeySet(cache) {
  const byRole = new Map();
  const global = new Set();
  const replacements = Array.isArray(cache.mapping?.rolePromptReplacements)
    ? cache.mapping.rolePromptReplacements
    : [];
  for (const replacement of replacements) {
    const sourceRoleId = stringValue(replacement.sourceRoleId);
    const set = byRole.get(sourceRoleId) ?? new Set();
    for (const rule of replacement.rules ?? []) {
      for (const term of rule.sourceTerms ?? []) {
        const key = normalizedTagKey(term?.text);
        if (!key) continue;
        set.add(key);
        global.add(key);
      }
    }
    byRole.set(sourceRoleId, set);
  }
  return { byRole, global };
}

function sceneMappingTermKeySet(cache) {
  const set = new Set();
  const replacements = Array.isArray(cache.mapping?.scenePromptReplacements)
    ? cache.mapping.scenePromptReplacements
    : [];
  for (const replacement of replacements) {
    for (const rule of replacement.rules ?? []) {
      for (const term of rule.sourceTerms ?? []) {
        const key = normalizedTagKey(term?.text);
        if (key) set.add(key);
      }
    }
  }
  return set;
}

function targetRegressionCandidates({
  sourceTerms,
  aiRoleTermKeys,
  aiSceneTermKeys,
  mappedRoleTermKeys,
  mappedSceneTermKeys,
}) {
  const sourceByKey = new Map(sourceTerms.map((term) => [term.normalized, term]));
  const rows = [];
  for (const group of targetRegressionGroups) {
    for (const rawTerm of group.terms) {
      const key = normalizedTagKey(rawTerm);
      const source = sourceByKey.get(key);
      if (!source) continue;
      const inAiRole = aiRoleTermKeys.global.has(key);
      const inRoleMapping = mappedRoleTermKeys.global.has(key);
      const inAiScene = aiSceneTermKeys.has(key);
      const inSceneMapping = mappedSceneTermKeys.has(key);
      if (inAiRole && inRoleMapping) continue;
      rows.push({
        group: group.id,
        label: group.label,
        term: source.text,
        normalized: key,
        frame_indexes: source.frame_indexes,
        sources: source.sources,
        ai_role_prompt_term: inAiRole,
        role_prompt_mapping: inRoleMapping,
        ai_scene_term: inAiScene,
        scene_prompt_mapping: inSceneMapping,
        note:
          'audit-only: source term exists but current AI/mapping coverage is incomplete; classification must come from AI/Codex schema, not local repair rules',
      });
    }
  }
  return rows;
}

function mergeSchemaIntoCache(cache, schemaEntry) {
  const next = structuredClone(cache);
  if (!next.aiRoleExtraction || typeof next.aiRoleExtraction !== 'object') {
    next.aiRoleExtraction = { schema_version: 1, status: 'ready', roles: [] };
  }
  if (!Array.isArray(next.aiRoleExtraction.roles)) {
    next.aiRoleExtraction.roles = [];
  }
  if (!next.mapping || typeof next.mapping !== 'object') {
    next.mapping = {
      id: `mapping-${stringValue(next.scriptId)}`,
      scriptId: stringValue(next.scriptId),
      roleSwaps: [],
      artistSwap: null,
    };
  }

  let rolePromptTermsMerged = 0;
  let sceneTermsMerged = 0;
  let roleMappingRulesMerged = 0;
  let sceneMappingRulesMerged = 0;

  const rolesById = new Map();
  for (const role of next.aiRoleExtraction.roles) {
    const id = stringValue(role.source_role_id ?? role.sourceRoleId);
    if (id) rolesById.set(id, role);
  }

  for (const rolePatch of schemaEntry.rolePromptTerms ?? []) {
    const sourceRoleId = stringValue(rolePatch.sourceRoleId ?? rolePatch.source_role_id);
    if (!sourceRoleId) continue;
    let role = rolesById.get(sourceRoleId);
    if (!role) {
      role = {
        source_role_id: sourceRoleId,
        display_name: stringValue(rolePatch.displayLabel ?? rolePatch.display_name) || sourceRoleId,
        appearances: [],
        stages: [],
        prompt_terms: [],
      };
      next.aiRoleExtraction.roles.push(role);
      rolesById.set(sourceRoleId, role);
    }
    const result = mergePromptTerms(role.prompt_terms ?? [], rolePatch.terms ?? []);
    role.prompt_terms = result.terms;
    rolePromptTermsMerged += result.merged;
  }

  const sceneResult = mergePromptTerms(
    next.aiRoleExtraction.scene_terms ?? [],
    schemaEntry.sceneTerms ?? [],
    { defaultCategory: 'scene' },
  );
  next.aiRoleExtraction.scene_terms = sceneResult.terms;
  sceneTermsMerged += sceneResult.merged;

  const mappingRoleResult = mergeRolePromptReplacementSchema(
    next.mapping.rolePromptReplacements ?? [],
    schemaEntry.rolePromptTerms ?? [],
  );
  next.mapping.rolePromptReplacements = mappingRoleResult.replacements;
  roleMappingRulesMerged += mappingRoleResult.rulesMerged;

  const mappingSceneResult = mergeScenePromptReplacementSchema(
    next.mapping.scenePromptReplacements ?? [],
    schemaEntry.sceneTerms ?? [],
  );
  next.mapping.scenePromptReplacements = mappingSceneResult.replacements;
  sceneMappingRulesMerged += mappingSceneResult.rulesMerged;

  if (Array.isArray(schemaEntry.termCacheSuggestions)) {
    const existing = Array.isArray(next.aiRoleExtraction.term_cache_suggestions)
      ? next.aiRoleExtraction.term_cache_suggestions
      : [];
    next.aiRoleExtraction.term_cache_suggestions = mergeCacheSuggestions(
      existing,
      schemaEntry.termCacheSuggestions,
    );
  }

  return {
    cache: next,
    rolePromptTermsMerged,
    sceneTermsMerged,
    roleMappingRulesMerged,
    sceneMappingRulesMerged,
  };
}

function mergePromptTerms(existingTerms, incomingTerms, options = {}) {
  const byKey = new Map();
  const order = [];
  for (const term of Array.isArray(existingTerms) ? existingTerms : []) {
    mergePromptTermIntoMaps({
      byKey,
      order,
      term,
      options,
      countNew: false,
    });
  }

  let merged = 0;
  for (const incoming of Array.isArray(incomingTerms) ? incomingTerms : []) {
    if (
      mergePromptTermIntoMaps({
        byKey,
        order,
        term: incoming,
        options,
        countNew: true,
      })
    ) {
      merged += 1;
    }
  }
  return { terms: order.map((key) => byKey.get(key)), merged };
}

function mergeRolePromptReplacementSchema(existingReplacements, rolePatches) {
  const byRole = new Map();
  const order = [];
  for (const replacement of Array.isArray(existingReplacements)
    ? existingReplacements
    : []) {
    const roleId = stringValue(replacement.sourceRoleId);
    if (!roleId) continue;
    byRole.set(roleId, structuredClone(replacement));
    order.push(roleId);
  }

  let rulesMerged = 0;
  for (const rolePatch of Array.isArray(rolePatches) ? rolePatches : []) {
    const roleId = stringValue(rolePatch.sourceRoleId ?? rolePatch.source_role_id);
    if (!roleId) continue;
    let replacement = byRole.get(roleId);
    if (!replacement) {
      replacement = {
        sourceRoleId: roleId,
        displayLabel: stringValue(rolePatch.displayLabel ?? rolePatch.display_name) || roleId,
        sourcePreview: '',
        rules: [],
      };
      byRole.set(roleId, replacement);
      order.push(roleId);
    }
    const result = mergeReplacementRules(
      replacement.rules ?? [],
      rolePatch.terms ?? [],
      (term) => `role-${safeId(roleId)}-${safeId(term.category)}-${safeId(term.text)}`,
    );
    replacement.rules = result.rules;
    replacement.sourcePreview = sourcePreviewForTerms(rolePatch.terms, replacement.sourcePreview);
    rulesMerged += result.merged;
  }

  return { replacements: order.map((roleId) => byRole.get(roleId)), rulesMerged };
}

function mergeScenePromptReplacementSchema(existingReplacements, sceneTerms) {
  const terms = Array.isArray(sceneTerms) ? sceneTerms : [];
  if (terms.length === 0) {
    return {
      replacements: Array.isArray(existingReplacements) ? existingReplacements : [],
      rulesMerged: 0,
    };
  }
  const replacements = Array.isArray(existingReplacements)
    ? structuredClone(existingReplacements)
    : [];
  let replacement = replacements[0];
  if (!replacement) {
    replacement = { id: 'scene-ai', label: 'Scene', rules: [] };
    replacements.push(replacement);
  }
  const result = mergeReplacementRules(
    replacement.rules ?? [],
    terms,
    (term) => `scene-${safeId(term.text)}`,
    { defaultCategory: 'scene' },
  );
  replacement.rules = result.rules;
  return { replacements, rulesMerged: result.merged };
}

function mergeReplacementRules(existingRules, incomingTerms, idForTerm, options = {}) {
  const rules = [];
  const emittedIds = new Set();
  const existingRuleByTermKey = new Map();
  const incomingCoverageKeys = new Set();
  const emittedCoverageKeys = new Set();
  const emittedRulesByCoverageKey = new Map();
  const sourceTermIdRemap = replacementSourceTermIdRemap(
    existingRules,
    incomingTerms,
    options,
  );
  for (const rule of Array.isArray(existingRules) ? existingRules : []) {
    for (const term of rule.sourceTerms ?? []) {
      for (const key of replacementExistingLookupKeys(term, options)) {
        if (!existingRuleByTermKey.has(key)) {
          existingRuleByTermKey.set(key, rule);
        }
      }
    }
  }

  let merged = 0;
  for (const incoming of Array.isArray(incomingTerms) ? incomingTerms : []) {
    const replacementTerm = promptReplacementTermFromAi(incoming, options);
    const keys = replacementIncomingLookupKeys(replacementTerm, options);
    if (keys.length === 0) continue;
    keys.forEach((key) => incomingCoverageKeys.add(key));
    const existing = keys
      .map((key) => existingRuleByTermKey.get(key))
      .find((rule) => rule && !emittedIds.has(rule.id));
    if (existing) {
      const refreshed = replacementRuleWithSourceTerms(
        existing,
        [replacementTerm],
        sourceTermIdRemap,
      );
      rules.push(refreshed);
      emittedIds.add(existing.id);
      keys.forEach((key) => {
        emittedCoverageKeys.add(key);
        if (!emittedRulesByCoverageKey.has(key)) {
          emittedRulesByCoverageKey.set(key, refreshed);
        }
      });
      continue;
    }
    const id = stringValue(incoming.ruleId ?? incoming.rule_id) || idForTerm(replacementTerm);
    if (emittedIds.has(id)) continue;
    const rule = { id, sourceTerms: [replacementTerm] };
    rules.push(rule);
    emittedIds.add(id);
    keys.forEach((key) => {
      emittedCoverageKeys.add(key);
      if (!emittedRulesByCoverageKey.has(key)) {
        emittedRulesByCoverageKey.set(key, rule);
      }
    });
    merged += 1;
  }

  for (const rule of Array.isArray(existingRules) ? existingRules : []) {
    if (emittedIds.has(rule.id)) continue;
    if (
      isSchemaCoveredDuplicateRule(rule, {
        incomingCoverageKeys,
        emittedCoverageKeys,
        emittedRulesByCoverageKey,
        sourceTermIdRemap,
        options,
      })
    ) {
      continue;
    }
    rules.push(rule);
    emittedIds.add(rule.id);
  }
  return { rules, merged };
}

function replacementRuleWithSourceTerms(rule, sourceTerms, sourceTermIdRemap) {
  return replacementRuleWithRemappedTermIds(
    { ...rule, sourceTerms },
    sourceTermIdRemap,
  );
}

function replacementRuleWithRemappedTermIds(rule, sourceTermIdRemap) {
  if (!(sourceTermIdRemap instanceof Map) || sourceTermIdRemap.size === 0) {
    return rule;
  }
  const remapped = { ...rule };
  if (typeof remapped.anchorTermId === 'string') {
    remapped.anchorTermId =
      sourceTermIdRemap.get(remapped.anchorTermId.trim()) ?? remapped.anchorTermId;
  }
  if (Array.isArray(remapped.excludedTermIds)) {
    remapped.excludedTermIds = remapped.excludedTermIds.map((id) => {
      if (typeof id !== 'string') return id;
      return sourceTermIdRemap.get(id.trim()) ?? id;
    });
  }
  return remapped;
}

function replacementSourceTermIdRemap(existingRules, incomingTerms, options = {}) {
  const incomingReplacementTerms = (Array.isArray(incomingTerms) ? incomingTerms : [])
    .map((term) => promptReplacementTermFromAi(term, options));
  const remap = new Map();
  for (const rule of Array.isArray(existingRules) ? existingRules : []) {
    for (const oldTerm of rule.sourceTerms ?? []) {
      const oldId = stringValue(oldTerm?.id);
      if (!oldId) continue;
      const oldKeys = replacementExistingLookupKeys(oldTerm, options);
      for (const newTerm of incomingReplacementTerms) {
        const newKeys = replacementIncomingLookupKeys(newTerm, options);
        if (!oldKeys.some((key) => newKeys.includes(key))) continue;
        const newId = stringValue(newTerm?.id);
        if (newId && newId !== oldId && !remap.has(oldId)) {
          remap.set(oldId, newId);
        }
        break;
      }
    }
  }
  return remap;
}

function promptReplacementTermFromAi(term, options = {}) {
  const normalized = normalizePromptTerm(term, options);
  return {
    id: normalized.id || `term-${safeId(normalized.text)}`,
    text: normalized.text,
    category: normalized.category,
    ...(normalized.source_phrase ? { sourcePhrase: normalized.source_phrase } : {}),
    ...(normalized.source_location ? { sourceLocation: normalized.source_location } : {}),
    ...(normalized.frame_indexes.length > 0
      ? { frameIndexes: normalized.frame_indexes }
      : {}),
  };
}

function replacementTermKey(term, options = {}) {
  const text = normalizedTagKey(term?.text);
  if (!text) return '';
  const category = canonicalPromptTermCategory(
    term?.category || options.defaultCategory || 'character',
  );
  return `${category}\u001f${text}`;
}

function replacementTermKeys(term, options = {}) {
  return replacementIncomingLookupKeys(term, options);
}

function replacementIncomingLookupKeys(term, options = {}) {
  const primary = replacementTermKey(term, options);
  if (!primary) return [];
  const text = normalizedTagKey(term?.text);
  if (!text) return [];
  const category = canonicalPromptTermCategory(
    term?.category || options.defaultCategory || 'character',
  );
  const keys = [primary];
  if (isRefinedLegacyClothingCategory(category)) {
    keys.push(replacementLegacyClothingKey(text));
  }
  return [...new Set(keys.filter(Boolean))];
}

function replacementExistingLookupKeys(term, options = {}) {
  const primary = replacementTermKey(term, options);
  if (!primary) return [];
  const text = normalizedTagKey(term?.text);
  if (!text) return [];
  const category = canonicalPromptTermCategory(
    term?.category || options.defaultCategory || 'character',
  );
  const keys = [primary];
  if (category === 'clothing') {
    keys.push(replacementLegacyClothingKey(text));
  }
  return [...new Set(keys.filter(Boolean))];
}

function replacementLegacyClothingKey(text) {
  return text ? `legacy-clothing-compatible\u001f${text}` : '';
}

function isRefinedLegacyClothingCategory(category) {
  return (
    category === 'accessory' ||
    category === 'clothingState' ||
    category === 'upperClothing' ||
    category === 'lowerClothing'
  );
}

function isSchemaCoveredDuplicateRule(
  rule,
  {
    incomingCoverageKeys,
    emittedCoverageKeys,
    emittedRulesByCoverageKey,
    sourceTermIdRemap,
    options = {},
  } = {},
) {
  const sourceTerms = Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : [];
  if (sourceTerms.length === 0) return false;
  const covered = sourceTerms.every((term) => {
    const keys = replacementExistingLookupKeys(term, options);
    return (
      keys.length > 0 &&
      keys.some((key) => incomingCoverageKeys.has(key)) &&
      keys.some((key) => emittedCoverageKeys.has(key))
    );
  });
  if (!covered) return false;
  if (!hasUserAuthoredReplacementState(rule)) {
    return true;
  }
  const candidateRules = [];
  const candidateIds = new Set();
  for (const term of sourceTerms) {
    for (const key of replacementExistingLookupKeys(term, options)) {
      const candidate = emittedRulesByCoverageKey?.get(key);
      const id = stringValue(candidate?.id);
      if (!candidate || candidateIds.has(id)) continue;
      candidateIds.add(id);
      candidateRules.push(candidate);
    }
  }
  return candidateRules.some((candidate) =>
    replacementUserStateEquivalent(rule, candidate, sourceTermIdRemap),
  );
}

function hasUserAuthoredReplacementState(rule) {
  return Object.keys(replacementUserState(rule)).length > 0;
}

function replacementUserStateEquivalent(left, right, sourceTermIdRemap) {
  return (
    stableJson(replacementUserState(left, sourceTermIdRemap)) ===
    stableJson(replacementUserState(right))
  );
}

function replacementUserState(rule, sourceTermIdRemap = new Map()) {
  const state = {};
  for (const key of Object.keys(rule ?? {}).sort()) {
    if (!isReplacementUserStateKey(key)) continue;
    const value = normalizedReplacementUserStateValue(
      key,
      rule[key],
      sourceTermIdRemap,
    );
    if (value !== undefined) {
      state[key] = value;
    }
  }
  return state;
}

function isReplacementUserStateKey(key) {
  return (
    key === 'action' ||
    key === 'matchMode' ||
    key === 'anchorTermId' ||
    key === 'excludedTermIds' ||
    key === 'targetWeightMultiplier' ||
    key === 'targetBlockWeightMultiplier' ||
    key.startsWith('target') ||
    key.startsWith('manual')
  );
}

function normalizedReplacementUserStateValue(key, value, sourceTermIdRemap) {
  if (key === 'action') {
    const action = stringValue(value);
    return action && action !== 'none' ? action : undefined;
  }
  if (key === 'matchMode') {
    const matchMode = stringValue(value);
    return matchMode && matchMode !== 'any' ? matchMode : undefined;
  }
  if (key === 'anchorTermId') {
    const id = stringValue(value);
    if (!id) return undefined;
    return sourceTermIdRemap?.get(id) ?? id;
  }
  if (key === 'excludedTermIds') {
    if (!Array.isArray(value) || value.length === 0) return undefined;
    return value
      .map((id) => {
        const stringId = stringValue(id);
        return sourceTermIdRemap?.get(stringId) ?? stringId;
      })
      .filter(Boolean)
      .sort();
  }
  if (typeof value === 'string') {
    const text = value.trim();
    return text ? text : undefined;
  }
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : undefined;
  }
  if (typeof value === 'boolean') {
    return value;
  }
  if (Array.isArray(value)) {
    return value.length > 0 ? value : undefined;
  }
  if (value && typeof value === 'object') {
    return Object.keys(value).length > 0 ? value : undefined;
  }
  return undefined;
}

function stableJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableJson(item)).join(',')}]`;
  }
  if (value && typeof value === 'object') {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

function normalizePromptTerm(term, options = {}) {
  const text = cleanTag(term?.text);
  return {
    id: stringValue(term?.id),
    text,
    category: canonicalPromptTermCategory(
      term?.category || options.defaultCategory || 'character',
    ),
    source_phrase: cleanTag(term?.source_phrase ?? term?.sourcePhrase ?? text),
    source_location: stringValue(term?.source_location ?? term?.sourceLocation),
    frame_indexes: sortedInts(term?.frame_indexes ?? term?.frameIndexes ?? []),
  };
}

function mergePromptTermIntoMaps({ byKey, order, term, options = {}, countNew }) {
  const category = canonicalPromptTermCategory(
    term?.category || options.defaultCategory || 'character',
  );
  const normalized = normalizedTagKey(term?.text);
  if (!normalized) return false;
  const normalizedTerm = normalizePromptTerm(term, { defaultCategory: category });
  const strictKey = promptTermStrictKey(category, normalized);
  const existingKey = promptTermMergeKey(byKey, category, normalized) || strictKey;
  const previous = byKey.get(existingKey);
  if (!previous) {
    byKey.set(strictKey, normalizedTerm);
    order.push(strictKey);
    return Boolean(countNew);
  }

  const merged = mergePromptTermRecords(previous, normalizedTerm);
  const mergedKey = promptTermStrictKey(merged.category, normalized);
  if (mergedKey !== existingKey) {
    byKey.delete(existingKey);
    const orderIndex = order.indexOf(existingKey);
    if (orderIndex >= 0) {
      order[orderIndex] = mergedKey;
    } else if (!order.includes(mergedKey)) {
      order.push(mergedKey);
    }
  }
  byKey.set(mergedKey, merged);
  return false;
}

function promptTermStrictKey(category, normalizedText) {
  return `${category}\u001f${normalizedText}`;
}

function promptTermMergeKey(byKey, category, normalizedText) {
  const strictKey = promptTermStrictKey(category, normalizedText);
  if (byKey.has(strictKey)) return strictKey;
  if (isRefinedClothingCategory(category)) {
    const legacyKey = promptTermStrictKey('clothing', normalizedText);
    return byKey.has(legacyKey) ? legacyKey : '';
  }
  if (category === 'clothing') {
    const refinedKeys = [
      'upperClothing',
      'lowerClothing',
      'accessory',
      'clothingState',
    ]
      .map((refined) => promptTermStrictKey(refined, normalizedText))
      .filter((key) => byKey.has(key));
    return refinedKeys.length === 1 ? refinedKeys[0] : '';
  }
  return '';
}

function mergePromptTermRecords(previous, incoming) {
  const preferred =
    pickPreferredPromptTermCategory(previous.category, incoming.category) ===
    incoming.category
      ? incoming
      : previous;
  const fallback = preferred === incoming ? previous : incoming;
  return {
    ...fallback,
    ...preferred,
    id: stringValue(preferred.id) || stringValue(fallback.id),
    source_phrase: cleanTag(preferred.source_phrase || fallback.source_phrase || preferred.text),
    source_location: stringValue(preferred.source_location || fallback.source_location),
    frame_indexes: sortedInts([
      ...(previous.frame_indexes ?? []),
      ...(incoming.frame_indexes ?? []),
    ]),
  };
}

function pickPreferredPromptTermCategory(leftCategory, rightCategory) {
  const left = canonicalPromptTermCategory(leftCategory);
  const right = canonicalPromptTermCategory(rightCategory);
  const leftRank = promptTermCategoryPreferenceRank(left);
  const rightRank = promptTermCategoryPreferenceRank(right);
  if (rightRank > leftRank) return right;
  if (leftRank > rightRank) return left;
  return right;
}

function promptTermCategoryPreferenceRank(category) {
  if (category === 'clothing') return 0;
  if (
    category === 'upperClothing' ||
    category === 'lowerClothing' ||
    category === 'accessory' ||
    category === 'clothingState'
  ) {
    return 1;
  }
  return 0;
}

function isRefinedClothingCategory(category) {
  return (
    category === 'upperClothing' ||
    category === 'lowerClothing' ||
    category === 'accessory' ||
    category === 'clothingState'
  );
}

function canonicalPromptTermCategory(category) {
  const value = stringValue(category || 'character');
  if (value === 'clothing_state') return 'clothingState';
  return value;
}

function mergeCacheSuggestions(existing, incoming) {
  const byKey = new Map();
  const order = [];
  for (const suggestion of existing) {
    const key = normalizedTagKey(suggestion?.text);
    if (!key) continue;
    byKey.set(key, suggestion);
    order.push(key);
  }
  for (const suggestion of incoming) {
    const key = normalizedTagKey(suggestion?.text);
    if (!key || byKey.has(key)) continue;
    byKey.set(key, suggestion);
    order.push(key);
  }
  return order.map((key) => byKey.get(key));
}

function schemaEntryForCache(schema, cache) {
  if (!schema) return null;
  const scriptId = stringValue(cache.scriptId);
  const entries = Array.isArray(schema.caches) ? schema.caches : [];
  return (
    entries.find((entry) => stringValue(entry.scriptId) === scriptId) ??
    entries.find((entry) => stringValue(entry.scriptName) === stringValue(cache.scriptName)) ??
    null
  );
}

function loadRepairSchema(filePath) {
  const decoded = loadJson(filePath);
  if (!decoded || typeof decoded !== 'object') {
    throw new Error(`Invalid repair schema: ${filePath}`);
  }
  return decoded;
}

function findImageScriptDirs(root) {
  if (!root || !fs.existsSync(root)) return [];
  const result = new Set();
  const visit = (dir) => {
    let entries = [];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch (_) {
      return;
    }
    if (
      entries.some(
        (entry) =>
          entry.isFile() &&
          /\.(png|jpe?g|webp)$/i.test(entry.name),
      )
    ) {
      result.add(normalizePath(dir));
    }
    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      if (entry.name.startsWith('.')) continue;
      visit(path.join(dir, entry.name));
    }
  };
  visit(root);
  return [...result].sort();
}

function emptyRepairResult() {
  return {
    cache: null,
    rolePromptTermsMerged: 0,
    sceneTermsMerged: 0,
    roleMappingRulesMerged: 0,
    sceneMappingRulesMerged: 0,
  };
}

function parseTags(caption) {
  const text = stringValue(caption);
  const tags = [];
  let current = '';
  let depth = 0;
  for (const char of text) {
    if (char === '(' || char === '[' || char === '{') depth += 1;
    if (char === ')' || char === ']' || char === '}') depth = Math.max(0, depth - 1);
    if (char === ',' && depth === 0) {
      const tag = cleanTag(current);
      if (tag) tags.push(tag);
      current = '';
      continue;
    }
    current += char;
  }
  const tail = cleanTag(current);
  if (tail) tags.push(tail);
  return tags;
}

function cleanTag(value) {
  let text = stringValue(value).trim();
  if (!text) return '';
  text = text.replace(/\s+/g, ' ');
  text = text.replace(/^[([{]+|[)\]}]+$/g, '').trim();
  text = text.replace(/^[0-9.]+::\s*/, '').replace(/\s*::[0-9.]*$/, '').trim();
  return text;
}

function normalizedTagKey(value) {
  return cleanTag(value)
    .toLowerCase()
    .replace(/_/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function sourcePreviewForTerms(terms, fallback) {
  const values = [];
  const seen = new Set();
  for (const term of Array.isArray(terms) ? terms : []) {
    const text = cleanTag(term?.text);
    const key = normalizedTagKey(text);
    if (!key || seen.has(key)) continue;
    values.push(text);
    seen.add(key);
  }
  return values.length > 0 ? values.join(', ') : stringValue(fallback);
}

function withoutEmptyStrings(value) {
  const result = {};
  for (const [key, entry] of Object.entries(value)) {
    if (typeof entry === 'string' && entry.trim() === '') continue;
    result[key] = entry;
  }
  return result;
}

function addSorted(values, value) {
  if (!values.includes(value)) {
    values.push(value);
    values.sort((a, b) => a - b);
  }
}

function sortedInts(values) {
  return [...new Set((Array.isArray(values) ? values : []).map(Number))]
    .filter(Number.isInteger)
    .sort((a, b) => a - b);
}

function looksLikeRecastCache(cache) {
  return (
    cache &&
    typeof cache === 'object' &&
    typeof cache.scriptId === 'string' &&
    cache.scriptSnapshot &&
    typeof cache.scriptSnapshot === 'object'
  );
}

function isUnderSourceRoot(value, root) {
  if (!root) return true;
  const source = normalizePath(value);
  return source === root || source.startsWith(`${root}/`);
}

function normalizePath(value) {
  return stringValue(value).replace(/\\/g, '/').replace(/\/+$/, '');
}

function safeId(value) {
  return (
    normalizedTagKey(value)
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 80) || 'term'
  );
}

function stringValue(value) {
  return value == null ? '' : String(value);
}

function loadJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (error) {
    return null;
  }
}

function parseArgs(args) {
  const parsed = {
    apply: false,
    assertTargets: false,
    reportUnchanged: false,
    help: false,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--apply') {
      parsed.apply = true;
    } else if (arg === '--assert-targets') {
      parsed.assertTargets = true;
    } else if (arg === '--report-unchanged') {
      parsed.reportUnchanged = true;
    } else if (arg === '--help' || arg === '-h') {
      parsed.help = true;
    } else if (arg === '--cache-dir') {
      parsed.cacheDir = requireValue(args, (index += 1), arg);
    } else if (arg === '--source-root') {
      parsed.sourceRoot = requireValue(args, (index += 1), arg);
    } else if (arg === '--report') {
      parsed.report = requireValue(args, (index += 1), arg);
    } else if (arg === '--schema') {
      parsed.schema = requireValue(args, (index += 1), arg);
    } else if (arg === '--backup-dir') {
      parsed.backupDir = requireValue(args, (index += 1), arg);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }
  if (parsed.apply && !parsed.schema) {
    throw new Error('--apply requires --schema so local code never invents role/scene terms');
  }
  return parsed;
}

function requireValue(args, index, name) {
  const value = args[index];
  if (!value || value.startsWith('--')) {
    throw new Error(`Missing value for ${name}`);
  }
  return value;
}

function printHelp() {
  console.log(`Usage:
  node tool/script_recast_complete_term_audit.mjs --cache-dir <dir> [options]

Options:
  --source-root <dir>      Limit caches to this source root.
  --report <file>         Write JSON report.
  --schema <file>         Explicit AI/Codex repair schema to merge.
  --apply                 Write schema merge results. Requires --schema.
  --backup-dir <dir>      Backup directory for --apply.
  --assert-targets        Exit 2 if target regression candidates remain.
  --report-unchanged      Include all eligible caches in report.rows.

This tool is local-only and does not call project/user APIs. It audits complete
deduplicated source prompt terms, but never classifies source terms by local
semantic rules. Repairs are applied only from an explicit schema.`);
}
