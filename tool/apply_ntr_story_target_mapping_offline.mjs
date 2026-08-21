import fs from 'node:fs';
import path from 'node:path';

const args = parseArgs(process.argv.slice(2));

if (!args.sourceRoot) {
  throw new Error('Pass --source-root <directory>.');
}

const workspace = path.resolve(
  args.workspace ||
    path.join(process.env.APPDATA ?? '', 'Novel Studio', 'Novel Studio', 'novel_studio'),
);
const cacheDir = path.join(workspace, 'script_recast', 'cache');
const sourceRoot = normalizePath(path.resolve(args.sourceRoot));
const characterLibraryPath = path.resolve(
  args.characterLibrary || path.join(workspace, 'library', 'characters.json'),
);
const targetHairstyleTagsById = loadCharacterHairstyleTags(characterLibraryPath);
const backupDir =
  args.backupDir ||
  path.resolve('build', `ntr_story_mapping_cache_backups_${timestampForPath()}`);
const reportPath =
  args.report || path.resolve('build', `ntr_story_mapping_cache_report_${timestampForPath()}.json`);
const allowedFiles = allowedCacheFileNames(args);

const genericGirlBaseTargetTags = ['loli', 'girl'];
const beastEarTargetTags = ['animal_ear_fluff', 'animal_ears'];

if (!fs.existsSync(cacheDir)) {
  throw new Error(`Missing cache dir: ${cacheDir}`);
}

const fallbackTargetCards = [
  {
    key: 'pepe',
    id: 'legacy-character-sheet-r14',
    outfitId: 'default-outfit',
    identity: 'pepe_(arknights)',
    upperBody:
      '1.5:: cat_ears ::, animal_ear_fluff, animal_ears, hair_ornament, jewelry, long_hair, skin_fang, 2:: lotus_flower_headdress ::, -3:: hood ::, -3:: wearing hood ::, -3:: animal hood ::',
    lowerBody: 'cat_tail',
    upperClothing: 'black_jacket, jacket, long_sleeves',
    lowerClothing: 'black_shorts, shorts, shoes',
  },
  {
    key: 'suzuran',
    id: 'legacy-character-sheet-r13',
    outfitId: 'default-outfit',
    identity: 'suzuran_(arknights)',
    upperBody:
      'fox_ears, animal_ears, animal_ear_fluff, green_eyes, long_hair, blonde_hair, neck_ribbon, red_ribbon, ribbon, fang',
    lowerBody: 'fox_tail, tail',
    upperClothing: 'white_shirt, long_sleeves, cross-laced_clothes',
    lowerClothing: 'blue_skirt, skirt',
  },
  {
    key: 'shamare',
    id: 'legacy-character-sheet-r29',
    outfitId: 'default-outfit',
    identity: 'shamare_(arknights)',
    upperBody:
      'animal_ear_fluff, animal_ears, fox_ears, fox_girl, twintails, short_hair, hair_between_eyes, pink_hair, pink_eyes, hair_ornament',
    lowerBody: 'fox_tail, tail',
    upperClothing: 'white_dress, dress, wide_sleeves',
    lowerClothing: 'black_skirt, skirt, socks, black_shoes, shoes',
  },
  {
    key: 'papyrus',
    id: 'legacy-character-sheet-r10',
    outfitId: 'default-outfit',
    identity: 'papyrus_(arknights)',
    upperBody:
      'cat_ears, animal_ears, animal_ear_fluff, green_eyes, orange_hair, long_hair, ahoge, hair_ornament',
    lowerBody: 'cat_tail, fluffy_tail, tail',
    upperClothing: 'green_dress, grey_dress, dress, white_hood, hood, hood_up, brown_gloves, gloves',
    lowerClothing: 'sandals, shoes',
  },
  {
    key: 'eyjafjalla',
    id: 'legacy-character-sheet-r1',
    outfitId: 'default-outfit',
    identity: 'eyjafjalla_(arknights)',
    upperBody: 'sheep_horns, horns, animal_ears, long_hair, blonde_hair, orange_eyes',
    lowerBody: 'sheep_tail, tail',
    upperClothing: 'white_coat, coat, black_dress, dress',
    lowerClothing: 'black_legwear, boots, shoes',
  },
  {
    key: 'myrtle',
    id: 'legacy-character-sheet-r3',
    outfitId: 'default-outfit',
    identity: 'myrtle_(arknights)',
    upperBody:
      'long_hair, ahoge, green_eyes, green_hair, hair_between_eyes, hair_ornament, pointy_ears',
    lowerBody: '',
    upperClothing: 'white_shirt, long_sleeves, dress',
    lowerClothing: 'skirt, shoes',
  },
].map((card) => buildTargetCard(card));

const targetCardSelection = loadTargetCardsFromCharacterLibrary(
  characterLibraryPath,
  fallbackTargetCards,
);
const requestedTargetIds = new Set(
  args.targetCharacterIds.map((value) => stringValue(value).trim()).filter(Boolean),
);
const targetCards = (
  requestedTargetIds.size > 0
    ? targetCardSelection.cards.filter((card) => requestedTargetIds.has(card.id))
    : targetCardSelection.cards
).map((card) => {
  if (card.id !== 'legacy-character-sheet-r14') return card;
  return {
    ...card,
    key: 'pepe',
    outfitId: 'default-outfit-copy',
    upperClothing: 'black_jacket, jacket, long_sleeves',
    lowerClothing: 'black_shorts, shoes, shorts',
  };
});

const files = fs.readdirSync(cacheDir).filter((file) => file.endsWith('.json')).sort();
const report = {
  source_root: args.sourceRoot,
  cache_dir: cacheDir,
  apply: args.apply,
  underwear_color_only: args.underwearColorOnly,
  hair_style_only: args.hairStyleOnly,
  character_library: characterLibraryPath,
  target_hairstyle_profiles: Object.fromEntries(
    targetCards.map((card) => [card.id, card.hairstyleTags]),
  ),
  target_generic_girl_profiles: Object.fromEntries(
    targetCards.map((card) => [card.id, card.genericGirlTags]),
  ),
  target_card_pool: targetCards.map((card) => ({
    id: card.id,
    name: card.name,
    identity: card.identity,
    generic_girl_tags: card.genericGirlTags,
  })),
  target_card_pool_exclusions: targetCardSelection.exclusions,
  target_assignment_counts: {},
  target_character_filter: args.targetCharacterIds,
  backup_dir: args.apply ? backupDir : '',
  files_scanned: files.length,
  file_filter_count: allowedFiles?.size ?? 0,
  files_matched: 0,
  files_changed: 0,
  mapped_roles: 0,
  skipped_roles: 0,
  role_prompt_rules_replaced: 0,
  clothing_rules_replaced: 0,
  clothing_rules_preserved: 0,
  generic_girl_ai_terms_added: 0,
  generic_girl_ai_terms_updated: 0,
  generic_girl_mapping_rules_added: 0,
  generic_girl_mapping_terms_updated: 0,
  multi_term_delete_rules_split: 0,
  delete_term_rules_written: 0,
  semantic_alias_rules_merged: 0,
  underwear_color_rules_split: 0,
  hair_policy_rules_split: 0,
  hair_style_rules_added: 0,
  hair_style_rules_replaced: 0,
  hair_state_rules_preserved: 0,
  hair_style_rules_deleted_missing_target: 0,
  male_hair_replacements_excluded: 0,
  prompt_term_frame_scopes_repaired: 0,
  role_assembly_stages_changed: 0,
  role_swaps_written: 0,
  role_identity_evidence_repaired: 0,
  rows: [],
};

for (const file of files) {
  if (allowedFiles && !allowedFiles.has(file)) {
    continue;
  }
  const cachePath = path.join(cacheDir, file);
  const cache = loadJson(cachePath);
  if (!cache || !isUnderSourceRoot(cache.sourceRootPath)) {
    continue;
  }

  report.files_matched += 1;
  const before = JSON.stringify(cache);
  const result = applyTargetMapping(cache);
  const changed = JSON.stringify(cache) !== before;

  if (changed) {
    report.files_changed += 1;
    if (args.apply) {
      fs.mkdirSync(backupDir, { recursive: true });
      fs.copyFileSync(cachePath, path.join(backupDir, file));
      fs.writeFileSync(cachePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
    }
  }

  report.mapped_roles += result.mappedRoles;
  report.skipped_roles += result.skippedRoles;
  report.role_prompt_rules_replaced += result.rolePromptRulesReplaced;
  report.clothing_rules_replaced += result.clothingRulesReplaced;
  report.clothing_rules_preserved += result.clothingRulesPreserved;
  report.generic_girl_ai_terms_added += result.genericGirlAiTermsAdded;
  report.generic_girl_ai_terms_updated += result.genericGirlAiTermsUpdated;
  report.generic_girl_mapping_rules_added += result.genericGirlMappingRulesAdded;
  report.generic_girl_mapping_terms_updated += result.genericGirlMappingTermsUpdated;
  report.multi_term_delete_rules_split += result.multiTermDeleteRulesSplit;
  report.delete_term_rules_written += result.deleteTermRulesWritten;
  report.semantic_alias_rules_merged += result.semanticAliasRulesMerged;
  report.underwear_color_rules_split += result.underwearColorRulesSplit;
  report.hair_policy_rules_split += result.hairPolicyRulesSplit;
  report.hair_style_rules_added += result.hairStyleRulesAdded;
  report.hair_style_rules_replaced += result.hairStyleRulesReplaced;
  report.hair_state_rules_preserved += result.hairStateRulesPreserved;
  report.hair_style_rules_deleted_missing_target +=
    result.hairStyleRulesDeletedMissingTarget;
  report.male_hair_replacements_excluded += result.maleHairReplacementsExcluded;
  report.prompt_term_frame_scopes_repaired +=
    result.promptTermFrameScopesRepaired;
  report.role_assembly_stages_changed += result.roleAssemblyStagesChanged;
  report.role_swaps_written += result.roleSwapsWritten;
  report.role_identity_evidence_repaired += result.roleIdentityEvidenceRepaired;
  for (const assignment of result.targetAssignments) {
    report.target_assignment_counts[assignment.target_character_id] =
      (report.target_assignment_counts[assignment.target_character_id] ?? 0) + 1;
  }
  report.rows.push({
    file_name: file,
    script_id: stringValue(cache.scriptId),
    script_name: stringValue(cache.scriptName),
    changed,
    ...result,
  });
}

fs.mkdirSync(path.dirname(reportPath), { recursive: true });
fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
console.log(JSON.stringify(report, null, 2));

function applyTargetMapping(cache) {
  cache.mapping ??= {
    id: `mapping-${cache.scriptId}`,
    scriptId: cache.scriptId,
    roleSwaps: [],
    artistSwap: null,
  };

  const roleInfos = roleInfosById(cache);
  const mappableRoleIds = orderedMappableRoleIds(cache, roleInfos);
  const targetByRoleId = assignTargetCards(cache, mappableRoleIds);
  const roleIdentityEvidenceRepaired = repairKnownFemaleRoleIdentityEvidence(cache);

  const result = {
    mappedRoles: args.underwearColorOnly || args.hairStyleOnly ? 0 : mappableRoleIds.length,
    skippedRoles: args.underwearColorOnly || args.hairStyleOnly
      ? 0
      : orderedRoleIds(cache, roleInfos).length - mappableRoleIds.length,
    rolePromptRulesReplaced: 0,
    clothingRulesReplaced: 0,
    clothingRulesPreserved: 0,
    genericGirlAiTermsAdded: 0,
    genericGirlAiTermsUpdated: 0,
    genericGirlMappingRulesAdded: 0,
    genericGirlMappingTermsUpdated: 0,
    multiTermDeleteRulesSplit: 0,
    deleteTermRulesWritten: 0,
    semanticAliasRulesMerged: 0,
    underwearColorRulesSplit: 0,
    hairPolicyRulesSplit: 0,
    hairStyleRulesAdded: 0,
    hairStyleRulesReplaced: 0,
    hairStateRulesPreserved: 0,
    hairStyleRulesDeletedMissingTarget: 0,
    maleHairReplacementsExcluded: 0,
    promptTermFrameScopesRepaired: 0,
    roleAssemblyStagesChanged: 0,
    roleSwapsWritten: 0,
    roleIdentityEvidenceRepaired,
    targetAssignments:
      args.underwearColorOnly || args.hairStyleOnly
        ? []
        : mappableRoleIds.map((roleId) => ({
            source_role_id: roleId,
            target_character_id: targetByRoleId.get(roleId)?.id ?? '',
          })),
  };

  if (args.underwearColorOnly) {
    applyUnderwearColorPolicyOnly(cache, roleInfos, result);
    return result;
  }
  if (args.hairStyleOnly) {
    applyHairStylePolicyOnly(cache, roleInfos, result);
    return result;
  }

  result.promptTermFrameScopesRepaired =
    repairPromptTermFrameScopesFromOccurrences(cache, new Set(mappableRoleIds));

  if (Array.isArray(cache.mapping.rolePromptReplacements)) {
    for (const replacement of cache.mapping.rolePromptReplacements) {
      const target = targetByRoleId.get(stringValue(replacement.sourceRoleId));
      if (!target) continue;
      const roleId = stringValue(replacement.sourceRoleId);
      const girlEvidence = ensureGenericGirlMappingEvidence({
        cache,
        replacement,
        role: roleInfos.get(roleId),
        roleId,
      });
      result.genericGirlAiTermsAdded += girlEvidence.aiTermAdded;
      result.genericGirlAiTermsUpdated += girlEvidence.aiTermUpdated;
      result.genericGirlMappingRulesAdded += girlEvidence.mappingRuleAdded;
      result.genericGirlMappingTermsUpdated += girlEvidence.mappingTermUpdated;
      replacement.targetCharacterId = target.id;
      replacement.targetIdentityPrompt = target.identityBody;
      if (!Array.isArray(replacement.rules)) replacement.rules = [];
      const underwearColorSplit = splitUnderwearColorPolicyRules(
        replacement.rules,
        roleInfos.get(roleId),
      );
      replacement.rules = underwearColorSplit.rules;
      result.underwearColorRulesSplit += underwearColorSplit.rulesSplit;
      replacement.rules = splitClothingPolicyRules(
        replacement.rules,
        roleInfos.get(roleId),
        target,
      ).rules;
      const hairPolicySplit = splitHairPolicyRules(replacement.rules);
      replacement.rules = hairPolicySplit.rules;
      result.hairPolicyRulesSplit += hairPolicySplit.rulesSplit;
      for (const rule of replacement.rules) {
        const terms = Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : [];
        if (terms.length > 0 && terms.every(isPreservedHairStateTerm)) {
          clearRuleEffect(rule);
          result.hairStateRulesPreserved += terms.length;
          continue;
        }
        const decision = replacementDecisionForRule(
          rule,
          target,
          {
            allRules: replacement.rules,
            role: roleInfos.get(roleId),
          },
        );
        if (decision.kind === 'identity') {
          setReplaceRule(rule, decision.targetPrompt);
          result.rolePromptRulesReplaced += 1;
        } else if (decision.kind === 'delete-identity') {
          setDeleteRule(rule);
          result.rolePromptRulesReplaced += 1;
        } else if (decision.kind === 'clothing') {
          setReplaceRule(rule, decision.targetPrompt);
          result.clothingRulesReplaced += 1;
        } else {
          clearRuleEffect(rule);
          if (hasClothingTerm(rule)) result.clothingRulesPreserved += 1;
        }
      }
      if (
        ensureIdentityReplacementRule({
          replacement,
          role: roleInfos.get(roleId),
          roleId,
          target,
        })
      ) {
        result.rolePromptRulesReplaced += 1;
      }
      const aliasMerge = mergeSemanticAliasRules(replacement.rules);
      result.semanticAliasRulesMerged += aliasMerge.rulesMerged;
      const splitDeletes = splitIndependentDeleteRules(aliasMerge.rules);
      result.multiTermDeleteRulesSplit += splitDeletes.rulesSplit;
      result.deleteTermRulesWritten += splitDeletes.termRulesWritten;
      replacement.rules = mergeCompatibleReplacementRules(splitDeletes.rules);
    }
  }

  if (Array.isArray(cache.mapping.roleAssemblies)) {
    for (const assembly of cache.mapping.roleAssemblies) {
      const target = targetByRoleId.get(stringValue(assembly.sourceRoleId));
      if (!target || !Array.isArray(assembly.stages)) continue;
      for (const stage of assembly.stages) {
        const changed = applyStageTarget(stage, target);
        if (changed) result.roleAssemblyStagesChanged += 1;
      }
    }
    for (const assembly of cache.mapping.roleAssemblies) {
      const roleId = stringValue(assembly.sourceRoleId);
      if (targetByRoleId.has(roleId) || !Array.isArray(assembly.stages)) continue;
      const role = roleInfos.get(roleId);
      if (!role || roleIsMale(role) || roleIsGlobalOrShared(role)) {
        if (!role) {
          for (const stage of assembly.stages) {
            const changed = clearStageTarget(stage);
            if (changed) result.roleAssemblyStagesChanged += 1;
          }
        }
        continue;
      }
      for (const stage of assembly.stages) {
        const changed = clearStageTarget(stage);
        if (changed) result.roleAssemblyStagesChanged += 1;
      }
    }
  }

  if (Array.isArray(cache.mapping.rolePromptReplacements)) {
    for (const replacement of cache.mapping.rolePromptReplacements) {
      const roleId = stringValue(replacement.sourceRoleId);
      if (targetByRoleId.has(roleId)) continue;
      const role = roleInfos.get(roleId);
      if (!role) {
        clearReplacementTarget(replacement);
        continue;
      }
      if (roleIsMale(role) || roleIsGlobalOrShared(role)) continue;
      clearReplacementTarget(replacement);
      const underwearColorSplit = splitUnderwearColorPolicyRules(
        replacement.rules,
        roleInfos.get(roleId),
      );
      replacement.rules = underwearColorSplit.rules;
      result.underwearColorRulesSplit += underwearColorSplit.rulesSplit;
      for (const rule of replacement.rules) {
        const targetPrompt = clothingReplacementPromptForRule(rule, null, {
          allRules: replacement.rules,
          role: roleInfos.get(roleId),
        });
        if (!targetPrompt) continue;
        setReplaceRule(rule, targetPrompt);
        result.clothingRulesReplaced += 1;
      }
      replacement.rules = mergeCompatibleReplacementRules(replacement.rules);
    }
  }

  cache.mapping.roleSwaps = [];
  result.roleSwapsWritten = 0;
  return result;
}

function applyUnderwearColorPolicyOnly(cache, roleInfos, result) {
  const replacements = Array.isArray(cache.mapping?.rolePromptReplacements)
    ? cache.mapping.rolePromptReplacements
    : [];
  for (const replacement of replacements) {
    if (!Array.isArray(replacement?.rules)) continue;
    const roleId = stringValue(replacement.sourceRoleId);
    const role = roleInfos.get(roleId);
    if (roleIsMale(role)) continue;
    const split = splitUnderwearColorPolicyRules(replacement.rules, role);
    replacement.rules = split.rules;
    result.underwearColorRulesSplit += split.rulesSplit;
    for (const rule of replacement.rules) {
      const terms = Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : [];
      if (terms.length === 0 || !terms.every(isUnderwearColorPolicyTerm)) {
        continue;
      }
      const targets = uniquePrompts(
        terms.map((term) =>
          directUnderwearColorReplacementPrompt(term?.text, {
            term,
            allRules: replacement.rules,
            role,
          }),
        ),
      );
      if (targets.length > 0) {
        setReplaceRule(rule, targets.join(', '));
        result.clothingRulesReplaced += 1;
      } else {
        clearRuleEffect(rule);
        result.clothingRulesPreserved += 1;
      }
    }
  }
}

function applyHairStylePolicyOnly(cache, roleInfos, result) {
  const replacements = Array.isArray(cache.mapping?.rolePromptReplacements)
    ? cache.mapping.rolePromptReplacements
    : [];
  const targetById = new Map(targetCards.map((target) => [target.id, target]));

  for (const replacement of replacements) {
    if (!Array.isArray(replacement?.rules)) continue;
    const roleId = stringValue(replacement.sourceRoleId);
    const role = roleInfos.get(roleId);
    if (roleIsMale(role)) {
      result.maleHairReplacementsExcluded += 1;
      continue;
    }
    const targetId = stringValue(replacement.targetCharacterId);
    if (
      args.targetCharacterIds.length > 0 &&
      !args.targetCharacterIds.includes(targetId)
    ) {
      continue;
    }
    const target = targetById.get(targetId);
    if (!target) continue;

    const split = splitHairPolicyRules(replacement.rules);
    replacement.rules = split.rules;
    result.hairPolicyRulesSplit += split.rulesSplit;

    const representedAliases = new Set(
      replacement.rules.flatMap((rule) =>
        (Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : [])
          .map((term) => canonicalSourceAliasText(term?.text || term?.sourcePhrase))
          .filter(Boolean),
      ),
    );
    const missingTerms = hairstyleSourceTermsForRole(cache, role).filter((term) => {
      const alias = canonicalSourceAliasText(term?.text || term?.sourcePhrase);
      if (!alias || representedAliases.has(alias)) return false;
      representedAliases.add(alias);
      return true;
    });
    const usedRuleIds = new Set(
      replacement.rules.map((rule) => stringValue(rule?.id)).filter(Boolean),
    );
    for (const term of missingTerms) {
      replacement.rules.push({
        id: uniqueHairRuleId(roleId, term, usedRuleIds),
        sourceTerms: [term],
      });
      result.hairStyleRulesAdded += 1;
    }

    for (const rule of replacement.rules) {
      const terms = Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : [];
      if (terms.length === 0) continue;
      if (terms.every(isPreservedHairStateTerm)) {
        clearRuleEffect(rule);
        result.hairStateRulesPreserved += terms.length;
        continue;
      }
      if (!terms.every(isHairStyleReplacementTerm)) continue;
      if (target.hairstyleTags.length > 0) {
        setReplaceRule(rule, target.hairstyleTags.join(', '));
        result.hairStyleRulesReplaced += terms.length;
      } else {
        setDeleteRule(rule);
        result.hairStyleRulesDeletedMissingTarget += terms.length;
      }
    }
    const deleteSplit = splitHairStyleDeleteRules(replacement.rules);
    replacement.rules = deleteSplit.rules;
    result.hairPolicyRulesSplit += deleteSplit.rulesSplit;
  }
}

function splitHairStyleDeleteRules(rules) {
  const sourceRules = Array.isArray(rules) ? rules : [];
  const usedIds = new Set(sourceRules.map((rule) => stringValue(rule?.id)).filter(Boolean));
  const result = [];
  let rulesSplit = 0;
  for (const rule of sourceRules) {
    const terms = Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : [];
    if (
      stringValue(rule?.action) !== 'delete' ||
      terms.length <= 1 ||
      !terms.every(isHairStyleReplacementTerm)
    ) {
      result.push(rule);
      continue;
    }
    rulesSplit += 1;
    const originalId = stringValue(rule?.id) || 'hair-style-delete-rule';
    for (let index = 0; index < terms.length; index += 1) {
      const next = {
        ...rule,
        id:
          index === 0
            ? originalId
            : uniqueHairSplitRuleId(originalId, 'delete', index, usedIds),
        sourceTerms: [terms[index]],
      };
      if (Array.isArray(next.excludedTermIds)) {
        next.excludedTermIds = next.excludedTermIds.filter(
          (termId) => stringValue(termId) === stringValue(terms[index]?.id),
        );
        if (next.excludedTermIds.length === 0) delete next.excludedTermIds;
      }
      result.push(next);
    }
  }
  return { rules: result, rulesSplit };
}

function splitHairPolicyRules(rules) {
  const sourceRules = Array.isArray(rules) ? rules : [];
  const usedIds = new Set(sourceRules.map((rule) => stringValue(rule?.id)).filter(Boolean));
  const result = [];
  let rulesSplit = 0;

  for (const rule of sourceRules) {
    const terms = Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : [];
    if (terms.length <= 1 || (rule.matchMode ?? 'any') !== 'any') {
      result.push(rule);
      continue;
    }
    const groups = new Map();
    for (const term of terms) {
      const key = isPreservedHairStateTerm(term)
        ? 'hair-state'
        : isHairStyleReplacementTerm(term)
          ? 'hair-style'
          : 'other';
      const group = groups.get(key) ?? [];
      group.push(term);
      groups.set(key, group);
    }
    if (groups.size <= 1) {
      result.push(rule);
      continue;
    }

    rulesSplit += 1;
    const originalId = stringValue(rule?.id) || 'hair-policy-rule';
    let index = 0;
    for (const [groupName, groupTerms] of groups) {
      const next = {
        ...rule,
        id:
          index === 0
            ? originalId
            : uniqueHairSplitRuleId(originalId, groupName, index, usedIds),
        sourceTerms: groupTerms,
      };
      if (Array.isArray(next.excludedTermIds)) {
        const termIds = new Set(groupTerms.map((term) => stringValue(term?.id)));
        next.excludedTermIds = next.excludedTermIds.filter((termId) =>
          termIds.has(stringValue(termId)),
        );
        if (next.excludedTermIds.length === 0) delete next.excludedTermIds;
      }
      result.push(next);
      index += 1;
    }
  }
  return { rules: result, rulesSplit };
}

function uniqueHairSplitRuleId(originalId, groupName, index, usedIds) {
  const base = `${originalId}-hair-${groupName}-${index + 1}`;
  return uniqueId(base, usedIds);
}

function uniqueHairRuleId(roleId, term, usedIds) {
  const termKey = slugForId(term?.text || term?.sourcePhrase) || 'style';
  return uniqueId(`rule-${roleId}-body-${termKey}`, usedIds);
}

function uniqueId(base, usedIds) {
  let candidate = base;
  let suffix = 2;
  while (usedIds.has(candidate)) {
    candidate = `${base}-${suffix}`;
    suffix += 1;
  }
  usedIds.add(candidate);
  return candidate;
}

function repairPromptTermFrameScopesFromOccurrences(cache, allowedRoleIds = null) {
  let repaired = 0;
  for (const role of Array.isArray(cache.aiRoleExtraction?.roles)
    ? cache.aiRoleExtraction.roles
    : []) {
    if (
      allowedRoleIds instanceof Set &&
      !allowedRoleIds.has(stringValue(role?.source_role_id))
    ) {
      continue;
    }
    for (const term of Array.isArray(role?.prompt_terms) ? role.prompt_terms : []) {
      const frameIndexes = uniqueNumbers(
        (Array.isArray(term?.source_occurrences) ? term.source_occurrences : [])
          .map((occurrence) => Number(occurrence?.frame_index))
          .filter(Number.isInteger),
      );
      if (frameIndexes.length === 0 || sameNumberList(term.frame_indexes, frameIndexes)) {
        continue;
      }
      term.frame_indexes = frameIndexes;
      repaired += 1;
    }
  }
  for (const replacement of Array.isArray(cache.mapping?.rolePromptReplacements)
    ? cache.mapping.rolePromptReplacements
    : []) {
    if (
      allowedRoleIds instanceof Set &&
      !allowedRoleIds.has(stringValue(replacement?.sourceRoleId))
    ) {
      continue;
    }
    for (const rule of Array.isArray(replacement?.rules) ? replacement.rules : []) {
      for (const term of Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : []) {
        const frameIndexes = uniqueNumbers(
          (Array.isArray(term?.sourceOccurrences) ? term.sourceOccurrences : [])
            .map((occurrence) => Number(occurrence?.frameIndex))
            .filter(Number.isInteger),
        );
        if (frameIndexes.length === 0 || sameNumberList(term.frameIndexes, frameIndexes)) {
          continue;
        }
        term.frameIndexes = frameIndexes;
        repaired += 1;
      }
    }
  }
  return repaired;
}

function sameNumberList(values, expected) {
  const normalized = uniqueNumbers(Array.isArray(values) ? values : []);
  return (
    normalized.length === expected.length &&
    normalized.every((value, index) => value === expected[index])
  );
}

function applyStageTarget(stage, target) {
  const before = JSON.stringify(stage);
  const sourceParts = stage.sourceParts ?? {};

  stage.targetCharacterId = target.id;
  delete stage.targetUpperOutfitId;
  delete stage.targetLowerOutfitId;
  stage.omittedParts = [];
  stage.manualParts = {
    identity: target.identity,
    upperBody: target.upperBody,
    ...(target.lowerBody.trim() ? { lowerBody: target.lowerBody } : {}),
  };
  stage.preservedParts = ['upperClothing', 'lowerClothing'].filter((part) =>
    stringValue(sourceParts[part]).trim(),
  );
  return JSON.stringify(stage) !== before;
}

function ensureGenericGirlMappingEvidence({ cache, replacement, role, roleId }) {
  const occurrences = genericGirlSourceOccurrences(cache, role);
  if (occurrences.length === 0) {
    return {
      aiTermAdded: 0,
      aiTermUpdated: 0,
      mappingRuleAdded: 0,
      mappingTermUpdated: 0,
    };
  }

  if (!Array.isArray(role.prompt_terms)) role.prompt_terms = [];
  let aiTerm = role.prompt_terms.find(isGenericGirlIdentityTerm);
  let aiTermAdded = 0;
  let aiTermUpdated = 0;
  const frameIndexes = uniqueNumbers(occurrences.map((entry) => entry.frame_index));
  const sourceLocations = uniquePrompts(
    occurrences.map((entry) => entry.source_location),
  );
  if (!aiTerm) {
    aiTerm = {
      id: uniquePromptTermId(role.prompt_terms, `role-${roleId}-identity-girl`),
      text: 'girl',
      category: 'identity',
      source_phrase: 'girl',
      source_location: sourceLocations.join('; '),
      frame_indexes: frameIndexes,
      source_occurrences: occurrences,
    };
    role.prompt_terms.push(aiTerm);
    aiTermAdded = 1;
  } else {
    const before = JSON.stringify(aiTerm);
    aiTerm.source_phrase = 'girl';
    aiTerm.source_location = sourceLocations.join('; ');
    aiTerm.frame_indexes = frameIndexes;
    aiTerm.source_occurrences = occurrences;
    aiTermUpdated = JSON.stringify(aiTerm) === before ? 0 : 1;
  }

  if (!Array.isArray(replacement.rules)) replacement.rules = [];
  let existingMappingTerm;
  for (const rule of replacement.rules) {
    existingMappingTerm = (Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : []).find(
      isGenericGirlIdentityTerm,
    );
    if (existingMappingTerm) break;
  }
  let mappingRuleAdded = 0;
  let mappingTermUpdated = 0;
  if (!existingMappingTerm) {
    const mappingTerm = mappingPromptTermFromAi(aiTerm);
    replacement.rules.push({
      id: uniqueReplacementRuleId(
        replacement.rules,
        `role-${roleId}-${stringValue(aiTerm.id)}`,
      ),
      sourceTerms: [mappingTerm],
    });
    replacement.sourcePreview = appendSourcePreviewTerm(
      replacement.sourcePreview,
      'girl',
    );
    mappingRuleAdded = 1;
  } else {
    const before = JSON.stringify(existingMappingTerm);
    Object.assign(existingMappingTerm, mappingPromptTermFromAi(aiTerm));
    mappingTermUpdated = JSON.stringify(existingMappingTerm) === before ? 0 : 1;
  }
  return {
    aiTermAdded,
    aiTermUpdated,
    mappingRuleAdded,
    mappingTermUpdated,
  };
}

function genericGirlSourceOccurrences(cache, role) {
  if (!role || typeof role !== 'object') return [];
  const frames = new Map(
    (Array.isArray(cache.scriptSnapshot?.frames) ? cache.scriptSnapshot.frames : []).map(
      (frame) => [Number(frame?.index), frame],
    ),
  );
  const occurrences = [];
  const seen = new Set();
  for (const appearance of Array.isArray(role.appearances) ? role.appearances : []) {
    const sourceId = stringValue(appearance?.source_id);
    const match = /^slot-(\d+)$/i.exec(sourceId);
    if (!match) continue;
    const slotIndex = Number(match[1]);
    for (const frameIndex of Array.isArray(appearance?.frame_indexes)
      ? appearance.frame_indexes
      : []) {
      const frame = frames.get(Number(frameIndex));
      const caption = frame?.parsed?.charCaptions?.[slotIndex];
      if (!captionHasExactPromptTag(caption, 'girl')) continue;
      const sourceLocation = `${sourceId} prompt`;
      const key = `${Number(frameIndex)}\u001f${sourceLocation}`;
      if (seen.has(key)) continue;
      seen.add(key);
      occurrences.push({
        frame_index: Number(frameIndex),
        source_location: sourceLocation,
      });
    }
  }
  return occurrences.sort(
    (left, right) =>
      left.frame_index - right.frame_index ||
      left.source_location.localeCompare(right.source_location, undefined, {
        numeric: true,
        sensitivity: 'base',
      }),
  );
}

function captionHasExactPromptTag(caption, expected) {
  const expectedKey = normalizedSourcePromptTag(expected);
  return splitPromptTags(caption).some(
    (tag) => normalizedSourcePromptTag(tag) === expectedKey,
  );
}

function normalizedSourcePromptTag(value) {
  return stringValue(value)
    .trim()
    .toLowerCase()
    .replace(/^[+-]?\d+(?:\.\d+)?\s*::\s*/, '')
    .replace(/\s*::\s*$/, '')
    .replaceAll('_', ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function uniquePromptTermId(terms, baseId) {
  const ids = new Set(terms.map((term) => stringValue(term?.id)));
  if (!ids.has(baseId)) return baseId;
  for (let suffix = 2; ; suffix += 1) {
    const candidate = `${baseId}-${suffix}`;
    if (!ids.has(candidate)) return candidate;
  }
}

function mappingPromptTermFromAi(term) {
  return {
    id: stringValue(term?.id),
    text: stringValue(term?.text),
    category: stringValue(term?.category),
    sourcePhrase: stringValue(term?.source_phrase),
    sourceLocation: stringValue(term?.source_location),
    frameIndexes: Array.isArray(term?.frame_indexes) ? term.frame_indexes : [],
    sourceOccurrences: Array.isArray(term?.source_occurrences)
      ? term.source_occurrences.map((occurrence) => ({
          frameIndex: Number(occurrence?.frame_index),
          sourceLocation: stringValue(occurrence?.source_location),
        }))
      : [],
  };
}

function uniqueReplacementRuleId(rules, baseId) {
  const ids = new Set(rules.map((rule) => stringValue(rule?.id)));
  if (!ids.has(baseId)) return baseId;
  for (let suffix = 2; ; suffix += 1) {
    const candidate = `${baseId}-${suffix}`;
    if (!ids.has(candidate)) return candidate;
  }
}

function appendSourcePreviewTerm(value, term) {
  const tags = splitPromptTags(value);
  if (tags.some((tag) => normalizedSourcePromptTag(tag) === normalizedSourcePromptTag(term))) {
    return stringValue(value);
  }
  return joinPrompts([value, term]);
}

function clearStageTarget(stage) {
  const before = JSON.stringify(stage);
  delete stage.targetCharacterId;
  delete stage.targetUpperOutfitId;
  delete stage.targetLowerOutfitId;
  delete stage.omittedParts;
  delete stage.preservedParts;
  delete stage.manualParts;
  return JSON.stringify(stage) !== before;
}

function roleSwapsForTargetedRoles(cache, targetByRoleId) {
  const swapsBySourceId = new Map();
  const assemblies = Array.isArray(cache.mapping.roleAssemblies)
    ? cache.mapping.roleAssemblies
    : [];
  for (const assembly of assemblies) {
    const target = targetByRoleId.get(stringValue(assembly.sourceRoleId));
    if (!target) continue;
    const appearances = Array.isArray(assembly.sourceAppearances)
      ? assembly.sourceAppearances
      : [];
    for (const appearance of appearances) {
      const sourceId = stringValue(appearance.sourceId);
      const sourceKind = stringValue(appearance.sourceKind);
      if (!sourceId || sourceKind !== 'slot') continue;
      swapsBySourceId.set(sourceId, {
        sourceRoleId: sourceId,
        targetCharacterId: target.id,
        targetOutfitId: target.outfitId,
      });
    }
  }
  return [...swapsBySourceId.values()].sort((left, right) =>
    left.sourceRoleId.localeCompare(right.sourceRoleId, undefined, {
      numeric: true,
      sensitivity: 'base',
    }),
  );
}

function replacementDecisionForRule(rule, target, context = {}) {
  const terms = Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : [];
  const clothingPrompt = clothingReplacementPromptForRule(
    rule,
    target,
    context,
  );
  if (clothingPrompt) {
    return { kind: 'clothing', targetPrompt: clothingPrompt };
  }
  const identity = identityReplacementForRule(rule, target);
  if (identity.targetPrompt) {
    return { kind: 'identity', targetPrompt: identity.targetPrompt };
  }
  if (identity.hasIdentityTerm) {
    return { kind: 'delete-identity' };
  }
  return { kind: 'preserve' };
}

function identityReplacementPromptForRule(rule, target) {
  return identityReplacementForRule(rule, target).targetPrompt;
}

function identityReplacementForRule(rule, target) {
  const terms = Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : [];
  const prompts = [];
  let hasIdentityTerm = false;
  for (const term of terms) {
    if (!isIdentityReplacementTerm(term)) continue;
    hasIdentityTerm = true;
    prompts.push(...identityReplacementTagsForTerm(term, target));
  }
  return { hasIdentityTerm, targetPrompt: uniquePrompts(prompts).join(', ') };
}

function identityReplacementTagsForTerm(term, target) {
  const category = normalizeKey(term?.category);
  const text = spacedText(term?.text);
  if (isGenericGirlIdentityTerm(term)) {
    return target?.genericGirlTags ?? genericGirlBaseTargetTags;
  }
  if (isExplicitConflictingAppearanceText(text)) {
    return [];
  }
  if (isPreservedHairStateText(text)) {
    return [];
  }
  if (isHairStyleSource(text)) {
    return targetHairTagsForTerm(target, text);
  }
  if (isHeadAccessoryText(text)) {
    if (target?.key === 'pepe') {
      return [
        '1.5:: cat_ears ::',
        '-3:: hood ::',
        '-3:: wearing hood ::',
        '-3:: animal hood ::',
        '2:: lotus_flower_headdress ::',
      ];
    }
    const targetHeadTags = targetTagsMatching(target, [
      'ear',
      'ears',
      'headband',
      'hairband',
      'headdress',
      'headpiece',
      'ornament',
      'ribbon',
    ]);
    return targetHeadTags.length > 0 ? targetHeadTags : beastEarTargetTags;
  }
  if (isLowerDecorationOrAccessoryTerm(term, text)) {
    return targetTagsMatching(target, ['tail']);
  }
  if (hasAnyWord(text, ['tail'])) {
    return targetTagsMatching(target, ['tail']);
  }
  if (hasAnyWord(text, ['ear', 'ears', 'halo', 'horn', 'horns'])) {
    return targetTagsMatching(target, ['ear', 'ears', 'horn', 'horns']);
  }
  if (hasAnyWord(text, ['fang', 'fangs'])) {
    return targetTagsMatching(target, ['fang']);
  }
  if (hasAnyWord(text, ['ornament', 'onrament', 'jewelry', 'headdress', 'flower', 'flowers'])) {
    return targetTagsMatching(target, ['ornament', 'jewelry', 'headdress', 'flower']);
  }
  if (hasAnyWord(text, ['ribbon', 'choker', 'necklace', 'bracelet'])) {
    return targetTagsMatching(target, ['ribbon', 'choker', 'necklace', 'bracelet']);
  }
  if (hasAnyWord(text, ['hair'])) {
    return targetHairTagsForTerm(target, text);
  }
  if (hasAnyWord(text, ['eye', 'eyes'])) {
    return targetTagsMatching(target, ['eye', 'eyes']);
  }
  if (category === 'character' || category === 'identity') {
    return isCharacterAnchorTerm(term) ? characterAnchorTagsForTarget(target) : [];
  }
  return [];
}

function isCharacterAnchorTerm(term) {
  const text = spacedText(term?.text);
  const raw = stringValue(term?.text).trim();
  if (!raw) return false;
  if (isPoseActionOrBodyState(text)) return false;
  if (isSkippedRoleText(text) && !hasFemaleRoleText(text)) return false;
  if (isStableAppearanceAnchor(text)) return false;
  if (isClothingLikeText(text) && !/[()]/.test(raw)) return false;
  if (hasFemaleRoleText(text)) return true;
  if (/[()]/.test(raw) || raw.includes('_(')) return true;
  return true;
}

function isClothingLikeText(spaced) {
  return hasAnyWord(spaced, [
    'apron',
    'armor',
    'armour',
    'bikini',
    'bodysuit',
    'bra',
    'bunnysuit',
    'bunny',
    'coat',
    'clothes',
    'dress',
    'glove',
    'gloves',
    'jacket',
    'leotard',
    'lingerie',
    'maid',
    'nun',
    'pants',
    'panties',
    'pantyhose',
    'shirt',
    'shorts',
    'skirt',
    'suit',
    'swimsuit',
    'thighhighs',
    'tight',
    'bodycon',
    'underwear',
    'uniform',
    'unzipping',
    'veil',
  ]);
}

function characterAnchorTagsForTarget(target) {
  if (target.key === 'pepe') {
    return [
      target.identity,
      '1.5:: cat_ears ::',
      '-3:: hood ::',
      '-3:: wearing hood ::',
      '-3:: animal hood ::',
      '2:: lotus_flower_headdress ::',
    ];
  }
  return [target.identity];
}

function targetTagsMatching(target, needles) {
  const tags = splitPromptTags(joinPrompts([target.upperBody, target.lowerBody]));
  const result = [];
  for (const tag of tags) {
    if (needles.some((needle) => tagMatchesNeedle(tag, needle))) {
      result.push(tag);
    }
  }
  return result;
}

function tagMatchesNeedle(tag, needle) {
  const key = normalizeKey(tag);
  const wanted = normalizeKey(needle);
  return key.includes(wanted);
}

function targetHairTagsForTerm(target, sourceSpaced) {
  void sourceSpaced;
  return Array.isArray(target?.hairstyleTags) ? target.hairstyleTags : [];
}

function clothingReplacementPromptForRule(rule, target, context = {}) {
  const terms = Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : [];
  const underwearPrompts = terms.map((term) =>
    directUnderwearColorReplacementPrompt(term?.text, {
      term,
      allRules: context.allRules ?? [],
      role: context.role,
    }),
  );
  if (!target) return uniquePrompts(underwearPrompts).join(', ');

  const lowerTailPrompt = uniquePrompts(
    terms
      .filter((term) =>
        isLowerDecorationOrAccessoryTerm(term, spacedText(term?.text)),
      )
      .flatMap(() => targetTagsMatching(target, ['tail'])),
  ).join(', ');

  const disallowedTerms = terms.filter((term) =>
    isDisallowedNonSwimwearClothing(term?.text),
  );
  if (disallowedTerms.length === 0) {
    return uniquePrompts([...underwearPrompts, lowerTailPrompt]).join(', ');
  }
  const categories = new Set(
    disallowedTerms.map((term) => normalizeKey(term?.category)),
  );
  const placement =
    categories.size === 1 && categories.has('upperclothing')
      ? 'upper'
      : categories.size === 1 && categories.has('lowerclothing')
        ? 'lower'
        : 'rule';
  const specialPrompt = clothingReplacementPromptFor(
    disallowedTerms.map((term) => stringValue(term?.text)).join(', '),
    target,
    placement,
  );
  return uniquePrompts([...underwearPrompts, lowerTailPrompt, specialPrompt]).join(', ');
}

function isIdentityReplacementTerm(term) {
  const category = normalizeKey(term?.category);
  const text = spacedText(term?.text);
  const phrase = spacedText(term?.sourcePhrase);
  const source = text.trim() ? text : phrase;
  if (isSkippedRoleText(source) && !hasFemaleRoleText(source)) return false;
  if (isPreservedHairStateText(source)) return false;
  if (isNegatedAppearanceText(source)) {
    const positiveSource = source
      .replace(/\b(?:no|without)\b/g, ' ')
      .replace(' lack of ', ' ');
    return isStableAppearanceAnchor(positiveSource) || isHeadAccessoryText(positiveSource);
  }
  if (isHairStyleSource(source) || isHeadAccessoryText(source)) return true;
  if (isPoseActionOrBodyState(source)) return false;
  if (
    (category === 'character' || category === 'identity') &&
    isClothingLikeText(source) &&
    !/[()]/.test(stringValue(term?.text))
  ) {
    return false;
  }
  if (category === 'character' || category === 'identity') return true;
  if (
    category === 'accessory' &&
    !isHeadAccessoryText(source) &&
    !isLowerDecorationOrAccessoryTerm(term, source)
  ) {
    return false;
  }
  if (
    category !== 'upperbody' &&
    category !== 'lowerbody' &&
    category !== 'body' &&
    category !== 'accessory'
  ) {
    return false;
  }
  return isStableAppearanceAnchor(source);
}

function isLowerDecorationOrAccessoryTerm(term, spaced) {
  const category = normalizeKey(term?.category);
  if (
    category !== 'lowerbody' &&
    category !== 'lowerclothing' &&
    category !== 'accessory'
  ) return false;
  if (
    hasAnyWord(spaced, [
      'hair',
      'head',
      'face',
      'ear',
      'ears',
      'headdress',
      'headband',
      'hairband',
    ]) ||
    /\b(?:no|without|lack of)\b/.test(spaced)
  ) {
    return false;
  }
  const explicitLowerMarker = hasAnyWord(spaced, [
    'anklet',
    'garter',
    'garterbelt',
    'leg strap',
    'leg ribbon',
    'leg ornament',
    'legwear',
    'thigh strap',
    'thighstrap',
    'tail',
  ]);
  if (explicitLowerMarker) return true;
  return category === 'lowerbody' && hasAnyWord(spaced, ['ornament', 'ribbon']);
}

function isStableAppearanceAnchor(spaced) {
  return (
    isHairStyleSource(spaced) ||
    isHeadAccessoryText(spaced) ||
    hasAnyWord(spaced, [
      'ahoge',
      'fang',
      'fangs',
      'horn',
      'horns',
      'halo',
      'tail',
      'ears',
      'ear',
      'headdress',
      'hair',
      'ponytail',
      'ponytails',
      'twintails',
      'braid',
      'braids',
      'braided',
      'bangs',
      'jewelry',
      'ornament',
      'ribbon',
      'flower',
      'flowers',
      'necklace',
      'bracelet',
      'choker',
      'wings',
    ]) ||
    /\b(?:black|blue|brown|blonde|green|grey|gray|orange|pink|purple|red|silver|white|yellow)\s+(?:eyes?|hair)\b/.test(
      spaced,
    ) ||
    /\b(?:animal|cat|dog|fox|rabbit|bunny|sheep|horse|elf|pointy)\s+(?:ears?|tail)\b/.test(
      spaced,
    )
  );
}

function isPoseActionOrBodyState(spaced) {
  return hasAnyWord(spaced, [
    'anal',
    'anus',
    'ass',
    'arm',
    'arms',
    'around',
    'breast',
    'breasts',
    'cameltoe',
    'cleavage',
    'close',
    'closed',
    'collarbone',
    'cum',
    'cowgirl',
    'ejaculation',
    'empty',
    'erect',
    'face',
    'fellatio',
    'finger',
    'fingers',
    'focus',
    'grab',
    'grabbing',
    'legs',
    'leg',
    'liquid',
    'mouth',
    'mound',
    'navel',
    'nipple',
    'nipples',
    'open',
    'penis',
    'pressed',
    'pussy',
    'pubic',
    'question',
    'semen',
    'saliva',
    'sex',
    'spread',
    'stomach',
    'symbol',
    'surface',
    'thrusting',
    'throat',
    'touching',
    'upturned',
    'vaginal',
    'vulva',
    'wrapped',
  ]);
}

function isHairStyleSource(spaced) {
  if (
    hasAnyWord(spaced, ['pubic', 'male', 'leg', 'chest', 'body', 'facial', 'armpit']) ||
    spaced.includes(' between legs ')
  ) {
    return false;
  }
  if (spaced.trim() === 'tress ribbon') return false;
  if (isPreservedHairStateText(spaced) || isHairAccessoryText(spaced)) return false;
  if (isHairColorText(spaced)) return false;
  return (
    spaced.includes(' pony tail ') ||
    spaced.includes(' one side up ') ||
    spaced.includes(' two side up ') ||
    spaced.includes(' bob cut ') ||
    spaced.includes(' pixie cut ') ||
    (hasWord(spaced, 'hair') &&
      hasAnyWord(spaced, [
        'alternate',
        'asymmetric',
        'asymmetrical',
        'between',
        'blunt',
        'curly',
        'intakes',
        'length',
        'long',
        'medium',
        'over',
        'short',
        'straight',
        'up',
        'very',
        'wavy',
      ])) ||
    hasAnyWord(spaced, [
      'ahoge',
      'bun',
      'buns',
      'drill',
      'drills',
      'hairstyle',
      'hairstyles',
      'locks',
      'ponytail',
      'ponytails',
      'sidelock',
      'sidelocks',
      'tress',
      'tresses',
      'twintails',
      'braid',
      'braids',
      'braided',
      'bangs',
    ])
  );
}

function isHairStyleReplacementTerm(term) {
  const source = spacedText(term?.text || term?.sourcePhrase);
  return isHairStyleSource(source);
}

function isPreservedHairStateTerm(term) {
  return isPreservedHairStateText(spacedText(term?.text || term?.sourcePhrase));
}

function isPreservedHairStateText(spaced) {
  return [
    ' adjusting hair ',
    ' cum on hair ',
    ' damp hair ',
    ' disheveled hair ',
    ' floating hair ',
    ' flowing hair ',
    ' hair down ',
    ' hair let down ',
    ' hair loose ',
    ' hair spread out ',
    ' loose hair ',
    ' messy hair ',
    ' spread out hair ',
    ' tousled hair ',
    ' unkempt hair ',
    ' wet hair ',
    ' windblown hair ',
  ].some((phrase) => spaced.includes(phrase));
}

function isHairColorText(spaced) {
  const colors = [
    'aqua',
    'black',
    'blue',
    'blonde',
    'brown',
    'green',
    'grey',
    'gray',
    'orange',
    'pink',
    'purple',
    'red',
    'silver',
    'white',
    'yellow',
  ];
  return hasAnyWord(spaced, ['hair']) && colors.some((color) => hasWord(spaced, color));
}

function hairstyleSourceTermsForRole(cache, role) {
  if (!role || typeof role !== 'object') return [];
  const aiTerms = (Array.isArray(role.prompt_terms) ? role.prompt_terms : [])
    .filter(isHairStyleReplacementTerm)
    .map(mappingTermFromAiTerm);
  return [...aiTerms, ...rawHairstyleTermsForRole(cache, role)];
}

function mappingTermFromAiTerm(term) {
  const frameIndexes = uniqueNumbers(
    Array.isArray(term?.frame_indexes)
      ? term.frame_indexes
      : Array.isArray(term?.frameIndexes)
        ? term.frameIndexes
        : [],
  );
  const occurrences = Array.isArray(term?.source_occurrences)
    ? term.source_occurrences
    : Array.isArray(term?.sourceOccurrences)
      ? term.sourceOccurrences
      : [];
  return {
    id: stringValue(term?.id),
    text: stringValue(term?.text),
    category: stringValue(term?.category) || 'upperBody',
    sourcePhrase: stringValue(term?.source_phrase || term?.sourcePhrase || term?.text),
    sourceLocation: stringValue(term?.source_location || term?.sourceLocation),
    ...(frameIndexes.length > 0 ? { frameIndexes } : {}),
    ...(occurrences.length > 0
      ? {
          sourceOccurrences: occurrences.map((occurrence) => ({
            frameIndex: Number(occurrence?.frame_index ?? occurrence?.frameIndex),
            sourceLocation: stringValue(
              occurrence?.source_location || occurrence?.sourceLocation,
            ),
          })),
        }
      : {}),
  };
}

function rawHairstyleTermsForRole(cache, role) {
  const frames = new Map(
    (Array.isArray(cache.scriptSnapshot?.frames) ? cache.scriptSnapshot.frames : [])
      .map((frame) => [Number(frame?.index), frame])
      .filter(([index]) => Number.isInteger(index)),
  );
  const groups = new Map();
  for (const appearance of Array.isArray(role?.appearances) ? role.appearances : []) {
    const sourceId = stringValue(appearance?.source_id || appearance?.sourceId);
    const match = /^slot-(\d+)$/.exec(sourceId);
    if (!match) continue;
    const slotIndex = Number(match[1]);
    const sourceLocation = `${sourceId} prompt`;
    for (const frameIndex of uniqueNumbers(
      Array.isArray(appearance?.frame_indexes)
        ? appearance.frame_indexes
        : Array.isArray(appearance?.frameIndexes)
          ? appearance.frameIndexes
          : [],
    )) {
      const caption = stringValue(
        frames.get(frameIndex)?.parsed?.charCaptions?.[slotIndex],
      );
      for (const sourcePhrase of splitPromptTags(caption).map(cleanSourcePromptTag)) {
        const text = sourcePhrase.replaceAll('_', ' ').replace(/\s+/g, ' ').trim();
        if (!text || !isHairStyleSource(spacedText(text))) continue;
        const alias = canonicalSourceAliasText(text);
        const group = groups.get(alias) ?? {
          text,
          sourcePhrase,
          frameIndexes: new Set(),
          sourceLocations: new Set(),
          sourceOccurrences: [],
        };
        group.frameIndexes.add(frameIndex);
        group.sourceLocations.add(sourceLocation);
        group.sourceOccurrences.push({ frameIndex, sourceLocation });
        groups.set(alias, group);
      }
    }
  }
  const roleId = stringValue(role?.source_role_id || role?.sourceRoleId);
  return [...groups.values()].map((group) => ({
    id: `role-${roleId}-body-${slugForId(group.text)}`,
    text: group.text,
    category: 'upperBody',
    sourcePhrase: group.sourcePhrase,
    sourceLocation: [...group.sourceLocations].sort().join('; '),
    frameIndexes: [...group.frameIndexes].sort((left, right) => left - right),
    sourceOccurrences: group.sourceOccurrences.sort(
      (left, right) => left.frameIndex - right.frameIndex,
    ),
  }));
}

function cleanSourcePromptTag(value) {
  return stringValue(value)
    .replace(/^[-+]?\d+(?:\.\d+)?::\s*/, '')
    .replace(/^:+\s*/, '')
    .replace(/\s*::$/, '')
    .trim();
}

function slugForId(value) {
  return stringValue(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function isHairAccessoryText(spaced) {
  return (
    hasAnyWord(spaced, ['hair']) &&
    hasAnyWord(spaced, [
      'bow',
      'bows',
      'feather',
      'feathers',
      'flower',
      'flowers',
      'ornament',
      'ornaments',
      'ribbon',
      'ribbons',
      'ring',
      'rings',
    ])
  );
}

function isHeadAccessoryText(spaced) {
  if (isHairStyleSource(spaced)) return false;
  if (hasAnyWord(spaced, ['clitoris', 'clitoral'])) return false;
  if (isHairAccessoryText(spaced)) return true;
  if (hasAnyWord(spaced, ['ear', 'ears'])) return true;
  if (
    hasAnyWord(spaced, [
      'hood',
      'hooded',
      'animal hood',
      'wearing hood',
      'headwear',
      'head wear',
    ])
  ) {
    return true;
  }
  if (hasAnyWord(spaced, ['fake']) && hasAnyWord(spaced, ['ear', 'ears'])) {
    return true;
  }
  if (
    hasAnyWord(spaced, [
      'cap',
      'crown',
      'hairband',
      'hat',
      'headband',
      'headdress',
      'headgear',
      'headpiece',
      'tiara',
      'veil',
    ])
  ) {
    return true;
  }
  return (
    hasAnyWord(spaced, ['hair', 'head']) &&
    hasAnyWord(spaced, [
      'band',
      'bow',
      'bows',
      'feather',
      'feathers',
      'flower',
      'flowers',
      'ornament',
      'ornaments',
      'ribbon',
      'ribbons',
      'ring',
      'rings',
    ])
  );
}

function isGenericGirlIdentityTerm(term) {
  const category = normalizeKey(term?.category);
  return (
    (category === 'character' || category === 'identity') &&
    spacedText(term?.text).trim() === 'girl'
  );
}

function isExplicitConflictingAppearanceText(spaced) {
  return isNegatedAppearanceText(spaced) || spaced.trim() === 'tress ribbon';
}

function isNegatedAppearanceText(spaced) {
  return hasAnyWord(spaced, ['no', 'without']) || spaced.includes(' lack of ');
}

function hasClothingTerm(rule) {
  return (Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : []).some((term) => {
    const category = normalizeKey(term?.category);
    return (
      category === 'clothing' ||
      category === 'upperclothing' ||
      category === 'lowerclothing' ||
      category === 'clothingstate' ||
      isClothingLikeText(spacedText(term?.text)) ||
      Boolean(clothingReplacementPromptFor(term?.text, targetCards[0], 'rule')) ||
      isSwimwear(term?.text)
    );
  });
}

function setReplaceRule(rule, targetPrompt) {
  rule.action = 'replace';
  rule.targetPrompt = targetPrompt;
  delete rule.targetWeightMultiplier;
}

function setDeleteRule(rule) {
  rule.action = 'delete';
  delete rule.targetPrompt;
  delete rule.targetWeightMultiplier;
}

function ensureIdentityReplacementRule({ replacement, role, roleId, target }) {
  const rules = Array.isArray(replacement.rules) ? replacement.rules : [];
  const hasIdentityReplacement = rules.some(
    (rule) =>
      stringValue(rule?.action) === 'replace' &&
      stringValue(rule?.targetPrompt).trim() &&
      (Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : []).some((term) => {
        const category = normalizeKey(term?.category);
        return (
          (category === 'character' || category === 'identity') &&
          !isGenericGirlIdentityTerm(term)
        );
      }),
  );
  if (hasIdentityReplacement) return false;

  const identity = sourceIdentityTermForRole(role);
  if (!identity) return false;
  const frameIndexes = roleFrameIndexes(role);
  const termId = `synthetic-${roleId}-identity`;
  const syntheticTerm = {
    id: termId,
    text: identity,
    category: 'character',
    sourcePhrase: identity,
    sourceLocation: 'role identity evidence',
    ...(frameIndexes.length > 0 ? { frameIndexes } : {}),
  };
  const targetPrompt = uniquePrompts([
    ...(isGenericGirlIdentityTerm(syntheticTerm)
      ? target?.genericGirlTags ?? genericGirlBaseTargetTags
      : []),
    ...characterAnchorTagsForTarget(target),
  ]).join(', ');
  rules.unshift({
    id: `synthetic-rule-${roleId}-identity`,
    sourceTerms: [syntheticTerm],
    action: 'replace',
    targetPrompt,
  });
  replacement.rules = rules;
  return true;
}

function sourceIdentityTermForRole(role) {
  if (!role || typeof role !== 'object') return '';
  const candidates = [
    ...(Array.isArray(role.raw_identity_tags) ? role.raw_identity_tags : []),
    role.canonical_name,
    ...(Array.isArray(role.stages)
      ? role.stages.flatMap((stage) => splitPromptTags(stage?.identity))
      : []),
  ];
  const normalized = candidates.map(stringValue).map((value) => value.trim()).filter(Boolean);
  return (
    normalized.find((value) => !isGenericDemographicIdentityText(value)) ??
    normalized[0] ??
    ''
  );
}

function isGenericDemographicIdentityText(value) {
  const text = spacedText(value).trim();
  return ['girl', 'girls', 'female', 'woman', 'women', 'loli', 'child'].includes(text);
}

function roleFrameIndexes(role) {
  if (!role || typeof role !== 'object') return [];
  return uniqueNumbers([
    ...(Array.isArray(role.frame_indexes) ? role.frame_indexes : []),
    ...(Array.isArray(role.appearances)
      ? role.appearances.flatMap((appearance) =>
          Array.isArray(appearance?.frame_indexes) ? appearance.frame_indexes : [],
        )
      : []),
    ...(Array.isArray(role.stages)
      ? role.stages.flatMap((stage) =>
          Array.isArray(stage?.frame_indexes) ? stage.frame_indexes : [],
        )
      : []),
  ]);
}

function splitUnderwearColorPolicyRules(rules, role) {
  const sourceRules = Array.isArray(rules) ? rules : [];
  if (roleIsMale(role)) {
    return { rules: sourceRules, rulesSplit: 0 };
  }
  const usedIds = new Set(
    sourceRules.map((rule) => stringValue(rule?.id)).filter(Boolean),
  );
  const result = [];
  let rulesSplit = 0;

  for (const rule of sourceRules) {
    const terms = Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : [];
    if (terms.length <= 1 || (rule.matchMode ?? 'any') !== 'any') {
      result.push(rule);
      continue;
    }
    const groups = new Map();
    for (const term of terms) {
      const targetPrompt = directUnderwearColorReplacementPrompt(term?.text, {
        term,
        allRules: sourceRules,
        role,
      });
      const key = targetPrompt
        ? `replace:${normalizePromptKey(targetPrompt)}`
        : isUnderwearColorPolicyTerm(term)
          ? 'policy-preserve'
          : 'nonpolicy-preserve';
      const group = groups.get(key) ?? { targetPrompt, terms: [] };
      group.terms.push(term);
      groups.set(key, group);
    }
    if (groups.size <= 1) {
      result.push(rule);
      continue;
    }

    rulesSplit += 1;
    const originalId = stringValue(rule?.id) || 'underwear-color-rule';
    let index = 0;
    for (const group of groups.values()) {
      const next = {
        ...rule,
        id:
          index === 0
            ? originalId
            : uniqueUnderwearColorRuleId(
                originalId,
                group.targetPrompt,
                index,
                usedIds,
              ),
        sourceTerms: group.terms,
      };
      if (Array.isArray(next.excludedTermIds)) {
        const termIds = new Set(group.terms.map((term) => stringValue(term?.id)));
        next.excludedTermIds = next.excludedTermIds.filter((termId) =>
          termIds.has(stringValue(termId)),
        );
        if (next.excludedTermIds.length === 0) delete next.excludedTermIds;
      }
      result.push(next);
      index += 1;
    }
  }

  return { rules: result, rulesSplit };
}

function uniqueUnderwearColorRuleId(originalId, targetPrompt, index, usedIds) {
  const targetKey = normalizeKey(targetPrompt) || `preserve-${index + 1}`;
  const base = `${originalId}-underwear-color-${targetKey}`;
  let candidate = base;
  let suffix = 2;
  while (usedIds.has(candidate)) {
    candidate = `${base}-${suffix}`;
    suffix += 1;
  }
  usedIds.add(candidate);
  return candidate;
}

function splitClothingPolicyRules(rules, role, target) {
  const sourceRules = Array.isArray(rules) ? rules : [];
  const usedIds = new Set(
    sourceRules.map((rule) => stringValue(rule?.id)).filter(Boolean),
  );
  const result = [];
  for (const rule of sourceRules) {
    const terms = Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : [];
    if (terms.length <= 1 || (rule.matchMode ?? 'any') !== 'any') {
      result.push(rule);
      continue;
    }
    const groups = new Map();
    for (const term of terms) {
      const singleRule = { ...rule, sourceTerms: [term] };
      const prompt = clothingReplacementPromptForRule(singleRule, target, {
        allRules: sourceRules,
        role,
      });
      const key = prompt
        ? `replace:${normalizePromptKey(prompt)}`
        : hasClothingTerm(singleRule)
          ? 'preserve-clothing'
          : 'non-clothing';
      const group = groups.get(key) ?? { targetPrompt: prompt, terms: [] };
      group.terms.push(term);
      groups.set(key, group);
    }
    if (groups.size <= 1) {
      result.push(rule);
      continue;
    }
    let index = 0;
    for (const group of groups.values()) {
      const next = {
        ...rule,
        id: index === 0
          ? stringValue(rule?.id) || 'clothing-policy-rule'
          : uniqueClothingPolicyRuleId(
              stringValue(rule?.id) || 'clothing-policy-rule',
              index,
              usedIds,
            ),
        sourceTerms: group.terms,
      };
      if (Array.isArray(next.excludedTermIds)) {
        const termIds = new Set(group.terms.map((term) => stringValue(term?.id)));
        next.excludedTermIds = next.excludedTermIds.filter((termId) =>
          termIds.has(stringValue(termId)),
        );
        if (next.excludedTermIds.length === 0) delete next.excludedTermIds;
      }
      result.push(next);
      index += 1;
    }
  }
  return { rules: result };
}

function uniqueClothingPolicyRuleId(originalId, index, usedIds) {
  let candidate = `${originalId}-clothing-policy-${index + 1}`;
  let suffix = 2;
  while (usedIds.has(candidate)) {
    candidate = `${originalId}-clothing-policy-${index + 1}-${suffix}`;
    suffix += 1;
  }
  usedIds.add(candidate);
  return candidate;
}

function splitIndependentDeleteRules(rules) {
  const sourceRules = Array.isArray(rules) ? rules : [];
  const usedIds = new Set(sourceRules.map((rule) => stringValue(rule?.id)).filter(Boolean));
  const splitRules = [];
  let rulesSplit = 0;
  let termRulesWritten = 0;

  for (const rule of sourceRules) {
    const terms = Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : [];
    const canSplit =
      stringValue(rule?.action) === 'delete' &&
      terms.length > 1 &&
      (rule.matchMode ?? 'any') === 'any' &&
      rule.targetWeightMultiplier == null &&
      !stringValue(rule.manualPhrase).trim() &&
      !stringValue(rule.anchorTermId).trim();
    if (!canSplit) {
      splitRules.push(rule);
      continue;
    }

    rulesSplit += 1;
    termRulesWritten += terms.length;
    const originalId = stringValue(rule.id) || 'delete-rule';
    for (let index = 0; index < terms.length; index += 1) {
      const term = terms[index];
      const next = {
        ...rule,
        id:
          index === 0
            ? originalId
            : uniqueSplitDeleteRuleId(originalId, term, index, usedIds),
        sourceTerms: [term],
      };
      if ((next.matchMode ?? 'any') === 'any') delete next.matchMode;
      if (Array.isArray(next.excludedTermIds)) {
        next.excludedTermIds = next.excludedTermIds.filter(
          (termId) => stringValue(termId) === stringValue(term?.id),
        );
        if (next.excludedTermIds.length === 0) delete next.excludedTermIds;
      }
      splitRules.push(next);
    }
  }

  return { rules: splitRules, rulesSplit, termRulesWritten };
}

function uniqueSplitDeleteRuleId(originalId, term, index, usedIds) {
  const termKey = normalizeKey(term?.id || term?.text) || `term${index + 1}`;
  const base = `${originalId}-delete-${termKey}`;
  let candidate = base;
  let suffix = 2;
  while (usedIds.has(candidate)) {
    candidate = `${base}-${suffix}`;
    suffix += 1;
  }
  usedIds.add(candidate);
  return candidate;
}

function mergeCompatibleReplacementRules(rules) {
  const merged = [];
  const indexByKey = new Map();
  for (const rule of rules) {
    const key = replacementMergeKey(rule);
    if (!key) {
      merged.push(rule);
      continue;
    }
    const existingIndex = indexByKey.get(key);
    if (existingIndex == null) {
      if ((rule.matchMode ?? 'any') === 'any') delete rule.matchMode;
      indexByKey.set(key, merged.length);
      merged.push(rule);
      continue;
    }
    const existing = merged[existingIndex];
    existing.sourceTerms = mergeReplacementSourceTerms([
      ...(Array.isArray(existing.sourceTerms) ? existing.sourceTerms : []),
      ...(Array.isArray(rule.sourceTerms) ? rule.sourceTerms : []),
    ]);
    if ((existing.matchMode ?? 'any') === 'any') delete existing.matchMode;
  }
  return merged;
}

function mergeSemanticAliasRules(rules) {
  const merged = [];
  const indexByKey = new Map();
  let rulesMerged = 0;
  for (const rule of Array.isArray(rules) ? rules : []) {
    const key = semanticAliasRuleKey(rule);
    if (!key) {
      merged.push(rule);
      continue;
    }
    const existingIndex = indexByKey.get(key);
    if (existingIndex == null) {
      indexByKey.set(key, merged.length);
      merged.push(rule);
      continue;
    }
    const existing = merged[existingIndex];
    existing.sourceTerms = mergeReplacementSourceTerms([
      ...(Array.isArray(existing.sourceTerms) ? existing.sourceTerms : []),
      ...(Array.isArray(rule.sourceTerms) ? rule.sourceTerms : []),
    ]);
    rulesMerged += 1;
  }
  return { rules: merged, rulesMerged };
}

function semanticAliasRuleKey(rule) {
  if ((rule?.matchMode ?? 'any') !== 'any') return '';
  if (rule?.targetWeightMultiplier != null) return '';
  if (stringValue(rule?.manualPhrase).trim()) return '';
  if (stringValue(rule?.anchorTermId).trim()) return '';
  if (Array.isArray(rule?.excludedTermIds) && rule.excludedTermIds.length > 0) return '';
  const terms = Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : [];
  if (terms.length === 0) return '';
  const aliases = new Set(terms.map((term) => canonicalSourceAliasText(term?.text)));
  if (aliases.size !== 1 || aliases.has('')) return '';
  return [
    [...aliases][0],
    stringValue(rule?.action),
    normalizePromptKey(rule?.targetPrompt),
  ].join('=>');
}

function canonicalSourceAliasText(value) {
  const normalized = normalizedSourcePromptTag(value);
  if (!normalized) return '';
  const tokens = normalized.split(' ');
  const collapsed = [];
  for (const token of tokens) {
    const corrected = token === 'armpt' || token === 'armpts' ? 'armpits' : token;
    const canonical = corrected === 'armpit' ? 'armpits' : corrected;
    if (collapsed[collapsed.length - 1] !== canonical) collapsed.push(canonical);
  }
  return collapsed.join(' ');
}

function replacementMergeKey(rule) {
  const action = stringValue(rule?.action);
  if (action !== 'replace') return '';
  const targetPrompt = stringValue(rule?.targetPrompt).trim();
  if (!targetPrompt) return '';
  if ((rule.matchMode ?? 'any') !== 'any') return '';
  if (rule.targetWeightMultiplier != null) return '';
  if (stringValue(rule.manualPhrase).trim()) return '';
  if (stringValue(rule.anchorTermId).trim()) return '';
  if (Array.isArray(rule.excludedTermIds) && rule.excludedTermIds.length > 0) return '';
  const terms = Array.isArray(rule.sourceTerms) ? rule.sourceTerms : [];
  if (terms.length === 0) return '';
  const groups = terms.map(replacementMergeGroupForTerm);
  if (groups.some((group) => !group)) return '';
  const uniqueGroups = new Set(groups);
  if (uniqueGroups.size !== 1) return '';
  return `${[...uniqueGroups][0]}=>${normalizePromptKey(targetPrompt)}`;
}

function replacementMergeGroupForTerm(term) {
  const category = normalizeKey(term?.category) || 'unknown';
  const text = spacedText(term?.text || term?.sourcePhrase);
  if (!text.trim()) return '';
  if (isClothingReplacementSourceTerm(term)) {
    return `clothing:${category}:${clothingMergeSemantic(text)}`;
  }
  const appearance = stableAppearanceMergeSemantic(text);
  if (appearance) return `appearance:${category}:${appearance}`;
  if (isPoseActionOrBodyState(text)) return '';
  if (category === 'character' || category === 'identity') {
    return `identity:${category}`;
  }
  if (isStableAppearanceAnchor(text)) return `appearance:${category}`;
  return '';
}

function stableAppearanceMergeSemantic(spaced) {
  if (isPreservedHairStateText(spaced)) return '';
  if (isHairStyleSource(spaced)) return 'hair';
  if (isHeadAccessoryText(spaced)) return 'accessory';
  if (hasAnyWord(spaced, ['tail'])) return 'tail';
  if (hasAnyWord(spaced, ['ear', 'ears', 'halo', 'horn', 'horns'])) return 'ears';
  if (hasAnyWord(spaced, ['fang', 'fangs'])) return 'fang';
  if (hasAnyWord(spaced, ['ornament', 'onrament', 'jewelry', 'headdress', 'flower', 'flowers'])) {
    return 'accessory';
  }
  if (hasAnyWord(spaced, ['ribbon', 'choker', 'necklace', 'bracelet'])) return 'accessory';
  if (hasAnyWord(spaced, ['eye', 'eyes'])) return 'eyes';
  if (hasAnyWord(spaced, ['wings'])) return 'wings';
  return '';
}

function isClothingReplacementSourceTerm(term) {
  const category = normalizeKey(term?.category);
  const text = term?.text;
  return (
    category === 'clothing' ||
    category === 'upperclothing' ||
    category === 'lowerclothing' ||
    category === 'clothingstate' ||
    Boolean(directUnderwearColorReplacementPrompt(text, { term })) ||
    isDisallowedNonSwimwearClothing(text) ||
    isSwimwear(text) ||
    isUnderwear(text)
  );
}

function clothingMergeSemantic(spaced) {
  if (spaced.includes(' lace ') || spaced.includes(' laced ') || spaced.includes(' lacy ')) {
    return 'lace';
  }
  if (isUnderwear(spaced)) return 'underwear';
  if (isSwimwear(spaced)) return 'swimwear';
  if (isDisallowedNonSwimwearClothing(spaced)) return 'special-clothing';
  return 'clothing';
}

function mergeReplacementSourceTerms(terms) {
  const result = [];
  const indexByKey = new Map();
  for (const term of terms) {
    const key = replacementSourceTermKey(term);
    const existingIndex = indexByKey.get(key);
    if (existingIndex == null) {
      indexByKey.set(key, result.length);
      result.push(term);
      continue;
    }
    const existing = result[existingIndex];
    const mergedSourceOccurrences = mergeSourceOccurrences([
      ...(Array.isArray(existing.sourceOccurrences) ? existing.sourceOccurrences : []),
      ...(Array.isArray(term?.sourceOccurrences) ? term.sourceOccurrences : []),
    ]);
    if (mergedSourceOccurrences.length > 0) {
      existing.sourceOccurrences = mergedSourceOccurrences;
    }
    const mergedFrameIndexes = mergedSourceOccurrences.length > 0
      ? uniqueNumbers(mergedSourceOccurrences.map((occurrence) => occurrence.frameIndex))
      : uniqueNumbers([
          ...(Array.isArray(existing.frameIndexes) ? existing.frameIndexes : []),
          ...(Array.isArray(term?.frameIndexes) ? term.frameIndexes : []),
        ]);
    if (mergedFrameIndexes.length > 0) existing.frameIndexes = mergedFrameIndexes;
    if (!stringValue(existing.sourcePhrase).trim() && stringValue(term?.sourcePhrase).trim()) {
      existing.sourcePhrase = term.sourcePhrase;
    }
    if (!stringValue(existing.sourceLocation).trim() && stringValue(term?.sourceLocation).trim()) {
      existing.sourceLocation = term.sourceLocation;
    }
  }
  return result;
}

function mergeSourceOccurrences(occurrences) {
  const result = [];
  const seen = new Set();
  for (const occurrence of occurrences) {
    const frameIndex = Number(occurrence?.frameIndex);
    if (!Number.isInteger(frameIndex)) continue;
    const sourceLocation = stringValue(occurrence?.sourceLocation).trim();
    const key = `${frameIndex}|${sourceLocation}`;
    if (seen.has(key)) continue;
    seen.add(key);
    result.push({
      ...occurrence,
      frameIndex,
      ...(sourceLocation ? { sourceLocation } : {}),
    });
  }
  return result.sort((left, right) =>
    left.frameIndex - right.frameIndex ||
    stringValue(left.sourceLocation).localeCompare(stringValue(right.sourceLocation)),
  );
}

function replacementSourceTermKey(term) {
  return [
    normalizeKey(term?.category),
    normalizeKey(term?.text),
    normalizeKey(term?.sourcePhrase),
    normalizeKey(term?.sourceLocation),
  ].join('|');
}

function uniqueNumbers(values) {
  return [...new Set(values.filter((value) => Number.isFinite(value)).map((value) => Number(value)))]
    .sort((left, right) => left - right);
}

function normalizePromptKey(value) {
  return splitPromptTags(value).map(normalizeKey).join(',');
}

function clearRuleEffect(rule) {
  delete rule.action;
  delete rule.targetPrompt;
  delete rule.targetWeightMultiplier;
}

function clearReplacementTarget(replacement) {
  delete replacement.targetCharacterId;
  delete replacement.targetIdentityPrompt;
  if (!Array.isArray(replacement.rules)) return;
  for (const rule of replacement.rules) {
    clearRuleEffect(rule);
  }
}

function roleInfosById(cache) {
  const result = new Map();
  const roles = Array.isArray(cache.aiRoleExtraction?.roles)
    ? cache.aiRoleExtraction.roles
    : [];
  for (const role of roles) {
    const id = stringValue(role.source_role_id);
    if (!id) continue;
    result.set(id, role);
  }
  const assemblies = Array.isArray(cache.mapping?.roleAssemblies)
    ? cache.mapping.roleAssemblies
    : [];
  for (const assembly of assemblies) {
    const id = stringValue(assembly.sourceRoleId);
    if (!id || result.has(id)) continue;
    result.set(id, assembly);
  }
  return result;
}

function repairKnownFemaleRoleIdentityEvidence(cache) {
  let repaired = 0;
  const roles = Array.isArray(cache?.aiRoleExtraction?.roles)
    ? cache.aiRoleExtraction.roles
    : [];
  for (const role of roles) {
    if (normalizeKey(role?.canonical_name) !== 'pecorine') continue;
    const evidenceText = [
      ...(Array.isArray(role?.prompt_terms)
        ? role.prompt_terms.flatMap((term) => [term?.text, term?.source_phrase])
        : []),
      ...(Array.isArray(role?.evidence_terms) ? role.evidence_terms : []),
      ...(Array.isArray(role?.stages)
        ? role.stages.flatMap((stage) => [stage?.identity])
        : []),
    ]
      .map(stringValue)
      .join(' ');
    if (hasAnyWord(spacedText(evidenceText), ['boy', '1boy', 'male', 'man', 'men'])) {
      continue;
    }
    const rawTags = Array.isArray(role.raw_identity_tags)
      ? role.raw_identity_tags
      : [];
    const filteredTags = rawTags.filter(
      (tag) => !hasAnyWord(spacedText(tag), ['boy', '1boy']),
    );
    if (filteredTags.length === rawTags.length) continue;
    role.raw_identity_tags = filteredTags;
    repaired += 1;
  }
  return repaired;
}

function orderedRoleIds(cache, roleInfos) {
  const ids = [];
  const seen = new Set();
  for (const role of Array.isArray(cache.aiRoleExtraction?.roles)
    ? cache.aiRoleExtraction.roles
    : []) {
    const id = stringValue(role.source_role_id);
    if (id && !seen.has(id)) {
      ids.push(id);
      seen.add(id);
    }
  }
  for (const id of roleInfos.keys()) {
    if (!seen.has(id)) ids.push(id);
  }
  return ids;
}

function orderedMappableRoleIds(cache, roleInfos) {
  const originalOrder = orderedRoleIds(cache, roleInfos);
  const orderById = new Map(originalOrder.map((roleId, index) => [roleId, index]));
  return originalOrder
    .filter((roleId) => shouldMapRole(roleInfos.get(roleId), roleId))
    .sort((left, right) => {
      const frameDifference =
        roleFrameIndexes(roleInfos.get(right)).length -
        roleFrameIndexes(roleInfos.get(left)).length;
      if (frameDifference !== 0) return frameDifference;
      return orderById.get(left) - orderById.get(right);
    });
}

function shouldMapRole(role, roleId) {
  if (roleIsNonHumanAnimal(role)) return false;
  const identityText = roleIdentitySearchText(role, roleId);
  if (hasFemaleRoleText(identityText) && !isSkippedRoleText(identityText)) {
    return true;
  }
  if (isSkippedRoleText(identityText) && !hasFemaleRoleText(identityText)) {
    return false;
  }
  const text = roleSearchText(role, roleId);
  if (!text.trim()) return false;
  if (isSkippedRoleText(text)) return false;
  return hasFemaleRoleText(text) || hasConcreteRoleIdentity(role);
}

function roleIsNonHumanAnimal(role) {
  if (!role || typeof role !== 'object') return false;
  const tags = arrayValue(role.raw_identity_tags)
    .map((value) =>
      spacedText(value)
        .trim()
        .replace(/\s+/g, ' '),
    )
    .filter(Boolean);
  if (tags.length === 0 || tags.some((tag) => hasFemaleRoleText(tag))) return false;
  return tags.every((tag) =>
    /^(?:(?:black|white|brown|grey|gray|red|blue|wild|large|small) )?(?:animal|bear|cat|cow|dog|horse|pig|rabbit|wolf)$/.test(
      tag,
    ),
  );
}

function hasConcreteRoleIdentity(role) {
  if (!role || typeof role !== 'object') return false;
  const candidates = [
    role.canonical_name,
    ...(Array.isArray(role.raw_identity_tags) ? role.raw_identity_tags : []),
  ]
    .map(stringValue)
    .map((value) => value.trim())
    .filter(Boolean);
  return candidates.some(
    (value) =>
      !isGenericDemographicIdentityText(value) &&
      !isSkippedRoleText(value) &&
      !isPoseActionOrBodyState(spacedText(value)),
  );
}

function roleIdentitySearchText(role, roleId) {
  if (!role || typeof role !== 'object') return roleId;
  const chunks = [
    roleId,
    role.display_name,
    role.displayLabel,
    role.sourceName,
    role.canonical_name,
    role.franchise,
    ...(Array.isArray(role.raw_identity_tags) ? role.raw_identity_tags : []),
    ...(Array.isArray(role.variant_tags) ? role.variant_tags : []),
    ...(Array.isArray(role.stages) ? role.stages.map((stage) => stage.identity) : []),
  ];
  return chunks.map(stringValue).join(' ').toLowerCase();
}

function roleSearchText(role, roleId) {
  if (!role || typeof role !== 'object') return roleId;
  const chunks = [
    roleId,
    role.display_name,
    role.displayLabel,
    role.sourceName,
    role.canonical_name,
    role.franchise,
    ...(Array.isArray(role.raw_identity_tags) ? role.raw_identity_tags : []),
    ...(Array.isArray(role.variant_tags) ? role.variant_tags : []),
    ...(Array.isArray(role.evidence_terms) ? role.evidence_terms.slice(0, 20) : []),
    ...(Array.isArray(role.stages)
      ? role.stages.flatMap((stage) => [
          stage.identity,
          stage.upper_body,
          stage.lower_body,
          stage.upper_clothing,
          stage.lower_clothing,
        ])
      : []),
  ];
  return chunks.map(stringValue).join(' ').toLowerCase();
}

function isSkippedRoleText(text) {
  const normalized = ` ${String(text).replaceAll('_', ' ').toLowerCase()} `;
  if (normalized.includes(' pecorine ')) return false;
  return [
    ' 1boy ',
    ' boy ',
    ' boys ',
    ' male ',
    ' man ',
    ' old man ',
    ' fat man ',
    ' bald man ',
    ' muscular male ',
    ' faceless male ',
    ' dark skinned male ',
    ' black male ',
    ' black man ',
    ' male focus ',
    ' father ',
    ' dad ',
    ' uncle ',
    ' sensei ',
    ' teacher ',
    ' shota ',
    ' gyaruo ',
    ' doctor arknights ',
    ' producer ',
    ' shidou ',
    ' shido ',
    ' emiya ',
    ' natsuki subaru ',
    ' aventurine ',
    ' wise zenless zone zero ',
    ' yuuki princess connect ',
    ' monster ',
    ' tentacle ',
    ' orc ',
  ].some((needle) => normalized.includes(needle));
}

function hasFemaleRoleText(text) {
  const normalized = ` ${String(text).replaceAll('_', ' ').toLowerCase()} `;
  return [
    ' 1girl ',
    ' 2girls ',
    ' 3girls ',
    ' girl ',
    ' girls ',
    ' female ',
    ' woman ',
    ' women ',
    ' heroine ',
    ' pecorine ',
  ].some((needle) => normalized.includes(needle));
}

function clothingReplacementPromptFor(value, target, placement) {
  const source = stringValue(value);
  if (!source.trim()) return '';
  const prompts = [];
  let useTargetClothing = false;
  let hasProtectedSwimwear = false;
  for (const tag of splitPromptTags(source)) {
    if (isSwimwear(tag) && hasOnlyProtectedUnderwearColors(tag)) {
      hasProtectedSwimwear = true;
    }
    const prompt = directUnderwearColorReplacementPrompt(tag);
    if (prompt) {
      prompts.push(prompt);
      continue;
    }
    if (isDisallowedNonSwimwearClothing(tag)) {
      useTargetClothing = true;
    }
  }
  if (prompts.length > 0) return uniquePrompts(prompts).join(', ');
  if (placement !== 'rule' && placement !== 'direct-rule' && hasProtectedSwimwear) return '';
  if (!useTargetClothing) return '';
  if (placement === 'direct-rule') return '';
  if (placement === 'upper') return target.upperClothing;
  if (placement === 'lower') return target.lowerClothing;
  return target.clothing;
}

function directUnderwearColorReplacementPrompt(value, context = {}) {
  const term = context.term ?? { text: value, category: 'clothing' };
  if (roleIsMale(context.role)) return '';
  if (isDisallowedNonSwimwearClothing(value)) return '';
  if (!isUnderwearColorPolicyTerm(term)) return '';
  if (hasOnlyProtectedUnderwearColors(value)) return '';

  const explicitColors = underwearColorWordsIn(value);
  const hasDisallowedColor = explicitColors.some(
    (color) => color !== 'white' && color !== 'pink',
  );
  if (
    !hasDisallowedColor &&
    underwearColorCoveredByPeerTerms(term, context.allRules ?? [])
  ) {
    return '';
  }

  const color = preferredUnderwearTargetColor(term, context);
  const basePrompt = coloredUnderwearBasePrompt(value, color);
  if (!basePrompt) return '';
  const source = stringValue(value)
    .trim()
    .replaceAll('_', ' ')
    .replace(/\s+/g, ' ');
  if (hasConflictingUnderwearColorStyle(value)) {
    return basePrompt;
  }
  if (hasDisallowedColor) {
    const colorPattern = new RegExp(
      `\\b(?:${underwearColorWords().join('|')})\\b`,
      'gi',
    );
    let recolored = source.replace(colorPattern, color);
    const duplicatePattern = new RegExp(
      `\\b${color}\\s+(?:and\\s+)?${color}\\b`,
      'gi',
    );
    while (duplicatePattern.test(recolored)) {
      recolored = recolored.replace(duplicatePattern, color);
    }
    return recolored;
  }
  return uniquePrompts([source, basePrompt]).join(', ');
}

function isUnderwearColorPolicyTerm(term) {
  const category = normalizeKey(term?.category);
  const value = term?.text ?? term?.sourcePhrase;
  const text = spacedText(value);
  if (
    !['clothing', 'upperclothing', 'lowerclothing', 'clothingstate'].includes(
      category,
    )
  ) {
    return false;
  }
  if (category === 'clothingstate' && !isDamagedUnderwearState(text)) return false;
  if (!isUnderwear(value)) return false;
  if (/\b(?:no|without)\s+(?:bra|panties|panty|underwear|bikini|swimsuit)\b/.test(text)) {
    return false;
  }
  if (text.includes(' panty shot ')) return false;
  if (
    text.includes(' thong leotard ') ||
    text.includes(' thong bodysuit ') ||
    text.includes(' thong unitard ')
  ) {
    return false;
  }
  return true;
}

function isDamagedUnderwearState(value) {
  const text = spacedText(value);
  return hasAnyWord(text, ['ripped', 'torn']) && isUnderwear(value);
}

function underwearColorWords() {
  return [
    'aqua',
    'beige',
    'black',
    'blue',
    'brown',
    'cyan',
    'gold',
    'gray',
    'green',
    'grey',
    'lavender',
    'magenta',
    'maroon',
    'navy',
    'orange',
    'pink',
    'purple',
    'red',
    'silver',
    'violet',
    'white',
    'yellow',
  ];
}

function underwearColorWordsIn(value) {
  const text = spacedText(value);
  return underwearColorWords().filter((color) => hasWord(text, color));
}

function hasOnlyProtectedUnderwearColors(value) {
  const colors = underwearColorWordsIn(value);
  return (
    colors.length > 0 &&
    colors.every((color) => color === 'white' || color === 'pink')
  );
}

function hasConflictingUnderwearColorStyle(value) {
  const text = spacedText(value);
  return [
    ' two tone ',
    ' multicolored ',
    ' multi colored ',
    ' colorful ',
    ' rainbow ',
  ].some((needle) => text.includes(needle));
}

function underwearColorCoveredByPeerTerms(term, allRules) {
  const frames = termFrameIndexes(term);
  if (frames.length === 0) return false;
  const family = underwearColorFamily(term?.text);
  if (!family) return false;
  const covered = new Set();
  for (const rule of Array.isArray(allRules) ? allRules : []) {
    for (const peer of Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : []) {
      if (peer === term || underwearColorFamily(peer?.text) !== family) continue;
      if (underwearColorWordsIn(peer?.text).length === 0) continue;
      for (const frameIndex of termFrameIndexes(peer)) covered.add(frameIndex);
    }
  }
  return frames.every((frameIndex) => covered.has(frameIndex));
}

function termFrameIndexes(term) {
  const occurrenceFrames = uniqueNumbers([
    ...(Array.isArray(term?.sourceOccurrences)
      ? term.sourceOccurrences.map((occurrence) => occurrence?.frameIndex)
      : []),
    ...(Array.isArray(term?.source_occurrences)
      ? term.source_occurrences.map((occurrence) => occurrence?.frame_index)
      : []),
  ]);
  if (occurrenceFrames.length > 0) return occurrenceFrames;
  return uniqueNumbers(
    Array.isArray(term?.frameIndexes) ? term.frameIndexes : [],
  );
}

function preferredUnderwearTargetColor(term, context) {
  const peerColor = protectedPeerUnderwearColor(term, context.allRules ?? []);
  if (peerColor) return peerColor;
  const family = underwearColorFamily(term?.text);
  if ((family === 'panties' || family === 'thong') && !roleIsMale(context.role)) {
    return 'pink';
  }
  return 'white';
}

function protectedPeerUnderwearColor(term, allRules) {
  const family = underwearColorFamily(term?.text);
  const frames = new Set(termFrameIndexes(term));
  if (!family || frames.size === 0) return '';
  let foundWhite = false;
  for (const rule of Array.isArray(allRules) ? allRules : []) {
    for (const peer of Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : []) {
      if (peer === term || underwearColorFamily(peer?.text) !== family) continue;
      if (!termFrameIndexes(peer).some((frameIndex) => frames.has(frameIndex))) continue;
      const colors = underwearColorWordsIn(peer?.text);
      if (colors.includes('pink') && colors.every((color) => color === 'pink' || color === 'white')) {
        return 'pink';
      }
      if (colors.includes('white') && colors.every((color) => color === 'pink' || color === 'white')) {
        foundWhite = true;
      }
    }
  }
  return foundWhite ? 'white' : '';
}

function roleIsMale(role) {
  if (!role || typeof role !== 'object') return false;
  const text = [
    role.source_role_id,
    role.display_name,
    role.canonical_name,
    ...(Array.isArray(role.raw_identity_tags) ? role.raw_identity_tags : []),
  ]
    .map(stringValue)
    .join(' ');
  return isSkippedRoleText(text) && !hasFemaleRoleText(text);
}

function roleIsGlobalOrShared(role) {
  const sourceKind = normalizeKey(role?.source_kind || role?.sourceKind);
  return sourceKind === 'global' || sourceKind === 'shared';
}

function underwearColorFamily(value) {
  const text = spacedText(value);
  if (isSwimwear(value)) return 'swimwear';
  if (text.includes(' pantyhose ')) return 'pantyhose';
  if (text.includes(' thighhighs ') || text.includes(' thigh highs ')) return 'thighhighs';
  if (text.includes(' stockings ') || text.includes(' stocking ')) return 'stockings';
  if (text.includes(' tights ')) return 'tights';
  if (text.includes(' socks ') || text.includes(' sock ')) return 'socks';
  if (text.includes(' leggings ')) return 'leggings';
  if (text.includes(' babydoll ')) return 'babydoll';
  if (text.includes(' lingerie ')) return 'lingerie';
  if (text.includes(' garter belt ') || text.includes(' garterbelt ')) return 'garter-belt';
  if (text.includes(' bra ')) return 'bra';
  if (text.includes(' thong ')) return 'thong';
  if (text.includes(' panties ') || text.includes(' panty ')) return 'panties';
  if (text.includes(' underwear ')) return 'underwear';
  return '';
}

function coloredUnderwearBasePrompt(value, color) {
  const family = underwearColorFamily(value);
  if (family === 'swimwear') {
    const text = spacedText(value);
    if (text.includes(' bikini ')) return `${color} bikini`;
    if (text.includes(' swimsuit ')) return `${color} swimsuit`;
    return `${color} swimwear`;
  }
  if (
    family === 'pantyhose' ||
    family === 'thighhighs' ||
    family === 'stockings' ||
    family === 'tights' ||
    family === 'socks' ||
    family === 'leggings'
  ) {
    const source = stringValue(value)
      .trim()
      .replaceAll('_', ' ')
      .replace(/\s+/g, ' ');
    const colorPattern = new RegExp(
      `\\b(?:${underwearColorWords().join('|')})\\b`,
      'gi',
    );
    return source.replace(colorPattern, color).trim();
  }
  if (family === 'panties') return `${color} panties`;
  if (family === 'thong') return `${color} thong`;
  if (family === 'bra') return `${color} bra`;
  if (family === 'babydoll') return `${color} babydoll`;
  if (family === 'lingerie') return `${color} lingerie`;
  if (family === 'garter-belt') return `${color} garter belt`;
  if (family === 'underwear') return `${color} underwear`;
  return '';
}

function isDisallowedNonSwimwearClothing(value) {
  const text = normalizeKey(value);
  if (!text) return false;
  const spaced = spacedText(value);
  if (
    hasAnyWord(spaced, ['ear', 'ears', 'tail']) &&
    !hasAnyWord(spaced, [
      'suit',
      'costume',
      'outfit',
      'dress',
      'clothing',
      'clothes',
      'bunnysuit',
      'bunnygirl',
      'bunnycostume',
      'rabbitgirl',
      'rabbitcostume',
      'rabbitsuit',
    ])
  ) {
    return false;
  }
  return [
    'bunnysuit',
    'bunnygirl',
    'bunnycostume',
    'bunnysuitcostume',
    'bunny',
    'rabbitsuit',
    'rabbitgirl',
    'rabbitcostume',
    'leotard',
    'bodysuit',
    'catsuit',
    'plugsuit',
    'pilotsuit',
    'unitsuit',
    'unitard',
    'skinsuit',
    'skintight',
    'skin_tight',
    'tightclothing',
    'tightclothes',
    'tightoutfit',
    'tightdress',
    'tightsuit',
    'bodycon',
    'skinnyfit',
    'latex',
    'rubber',
    'wetsuit',
    'racingsuit',
    'competitionwear',
  ].some((needle) => text.includes(needle));
}

function isSwimwear(value) {
  const text = spacedText(value);
  return (
    text.includes(' swimsuit ') ||
    text.includes(' swimwear ') ||
    text.includes(' bikini ')
  );
}

function isUnderwear(value) {
  const text = spacedText(value);
  return [
    ' pantyhose ',
    ' thighhighs ',
    ' thigh highs ',
    ' stockings ',
    ' stocking ',
    ' tights ',
    ' socks ',
    ' sock ',
    ' leggings ',
    ' underwear ',
    ' panties ',
    ' panty ',
    ' bra ',
    ' lingerie ',
    ' thong ',
    ' garter belt ',
    ' garterbelt ',
    ' babydoll ',
  ].some((needle) => text.includes(needle));
}

function isUnderSourceRoot(value) {
  const current = normalizePath(value);
  return current === sourceRoot || current.startsWith(`${sourceRoot}/`);
}

function parseArgs(values) {
  const parsed = {
    sourceRoot: '',
    workspace: '',
    backupDir: '',
    report: '',
    importReport: '',
    characterLibrary: '',
    targetCharacterIds: [],
    defaultTargetCharacterId: '',
    cacheFiles: [],
    apply: false,
    underwearColorOnly: false,
    hairStyleOnly: false,
  };
  for (let index = 0; index < values.length; index += 1) {
    const arg = values[index];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    if (key === 'apply' || key === 'underwear-color-only' || key === 'hair-style-only') {
      if (key === 'apply') parsed.apply = true;
      if (key === 'underwear-color-only') parsed.underwearColorOnly = true;
      if (key === 'hair-style-only') parsed.hairStyleOnly = true;
      continue;
    }
    const value = values[index + 1];
    index += 1;
    if (key === 'source-root') parsed.sourceRoot = value;
    if (key === 'workspace') parsed.workspace = value;
    if (key === 'backup-dir') parsed.backupDir = value;
    if (key === 'report') parsed.report = value;
    if (key === 'import-report') parsed.importReport = value;
    if (key === 'character-library') parsed.characterLibrary = value;
    if (key === 'target-character-id') parsed.targetCharacterIds.push(value);
    if (key === 'default-target-character-id') parsed.defaultTargetCharacterId = value;
    if (key === 'cache-file') parsed.cacheFiles.push(path.basename(value));
  }
  return parsed;
}

function allowedCacheFileNames(options) {
  const explicit = new Set(options.cacheFiles);
  if (explicit.size > 0) return explicit;
  return options.importReport ? importReportFileNames(options.importReport) : null;
}

function importReportFileNames(file) {
  const report = loadJson(path.resolve(file));
  const rows = Array.isArray(report?.rows) ? report.rows : [];
  const fileNames = rows
    .map((row) => stringValue(row.cache_file_name).trim())
    .filter(Boolean);
  if (fileNames.length === 0) {
    throw new Error(`Import report has no cache_file_name rows: ${file}`);
  }
  return new Set(fileNames);
}

function loadJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return null;
  }
}

function loadTargetCardsFromCharacterLibrary(file, fallbackCards) {
  const library = loadJson(file);
  const characters = Array.isArray(library)
    ? library
    : Array.isArray(library?.characters)
      ? library.characters
      : [];
  if (characters.length === 0) {
    return { cards: fallbackCards, exclusions: [] };
  }
  const explicitlyExcludedIds = new Set([
    'legacy-character-sheet-r27', // 露露卡：用户明确排除
    'legacy-character-sheet-r30', // 缇缇：用户明确排除
  ]);
  const exclusions = [];
  const cards = characters
    .filter((character) => {
      const id = stringValue(character?.id);
      const name = stringValue(character?.name) || id;
      const reasons = [];
      if (arrayValue(character?.imageRefs).map(stringValue).filter(Boolean).length === 0) {
        reasons.push('missing-preview');
      }
      if (explicitlyExcludedIds.has(id)) reasons.push('explicitly-excluded');
      if (reasons.length > 0) exclusions.push({ id, name, reasons });
      return reasons.length === 0;
    })
    .map(targetCardFromLibraryCharacter)
    .filter(Boolean);
  const pepe = cards.find((card) => card.id === 'legacy-character-sheet-r14');
  if (!pepe || cards.length < 2) {
    return { cards: fallbackCards, exclusions };
  }
  return {
    cards: [pepe, ...cards.filter((card) => card.id !== pepe.id)],
    exclusions,
  };
}

function targetCardFromLibraryCharacter(character) {
  const id = stringValue(character?.id);
  const identity = targetIdentityForLibraryCharacter(character);
  if (!id || !identity) return null;
  const outfits = Array.isArray(character?.outfits) ? character.outfits : [];
  const defaultOutfitId = stringValue(character?.defaultOutfitId);
  const defaultOutfit =
    id === 'legacy-character-sheet-r14'
      ? outfits.find(
          (outfit) =>
            stringValue(outfit?.id) === 'default-outfit-copy' ||
            stringValue(outfit?.name) === '无兜帽',
        ) ??
        outfits.find((outfit) => stringValue(outfit?.id) === defaultOutfitId) ??
        outfits[0]
      : outfits.find((outfit) => stringValue(outfit?.id) === defaultOutfitId) ??
        outfits[0];
  return buildTargetCard({
    key: id === 'legacy-character-sheet-r14' ? 'pepe' : id,
    id,
    name: stringValue(character?.name) || id,
    outfitId: stringValue(defaultOutfit?.id),
    identity,
    identityTags: arrayValue(character?.identityTags),
    frontFull: stringValue(character?.traits?.front_full),
    upperBody: stringValue(character?.traits?.front_upper),
    lowerBody: stringValue(character?.traits?.front_lower),
    upperClothing: arrayValue(defaultOutfit?.partTags?.upperClothingTags).join(', '),
    lowerClothing: arrayValue(defaultOutfit?.partTags?.lowerClothingTags).join(', '),
  });
}

function targetIdentityForLibraryCharacter(character) {
  const anchor = arrayValue(character?.anchorTags)
    .map(stringValue)
    .find(Boolean);
  if (anchor) return anchor;
  return splitPromptTags(character?.traits?.front_full).find((tag) => {
    const source = stringValue(tag);
    const normalized = spacedText(tag).trim();
    if (!normalized || isGenericDemographicIdentityText(normalized)) return false;
    return source.includes('(') && source.includes(')');
  }) ?? '';
}

function buildTargetCard(card) {
  const genericGirlTags = targetGenericGirlTags(card);
  const result = {
    ...card,
    name: stringValue(card?.name) || stringValue(card?.key) || stringValue(card?.id),
    genericGirlTags,
  };
  result.hairstyleTags =
    targetHairstyleTagsById.get(result.id) ?? extractHairstyleTags(result.upperBody);
  result.identityBody = joinPrompts([
    result.identity,
    ...result.genericGirlTags,
    result.upperBody,
    result.lowerBody,
  ]);
  result.clothing = joinPrompts([result.upperClothing, result.lowerClothing]);
  result.fullPrompt = joinPrompts([
    result.identity,
    result.upperBody,
    result.lowerBody,
    result.upperClothing,
    result.lowerClothing,
  ]);
  return result;
}

function targetGenericGirlTags(card) {
  const explicit = splitPromptTags(
    joinPrompts([
      card?.frontFull,
      ...(Array.isArray(card?.identityTags) ? card.identityTags : []),
    ]),
  ).filter((tag) => {
    const key = normalizeKey(tag);
    return (
      key === 'girl' ||
      key === 'loli' ||
      key === 'young' ||
      key.endsWith('girl')
    );
  });
  const speciesGirlTags = targetSpeciesGirlTags(card);
  if (card?.key === 'pepe') {
    return uniquePrompts([...genericGirlBaseTargetTags, ...speciesGirlTags]);
  }
  return uniquePrompts([...explicit, ...speciesGirlTags]);
}

function targetSpeciesGirlTags(card) {
  const species = [
    'snow_leopard',
    'leopard',
    'tiger',
    'rabbit',
    'sheep',
    'fox',
    'cat',
    'dog',
    'wolf',
    'dragon',
    'mouse',
    'bear',
    'cow',
    'horse',
    'goat',
    'demon',
  ];
  const allTags = splitPromptTags(
    joinPrompts([
      card?.frontFull,
      card?.upperBody,
      card?.lowerBody,
      ...arrayValue(card?.identityTags),
    ]),
  );
  const normalizedTags = allTags.map((tag) =>
    stringValue(tag)
      .toLowerCase()
      .replace(/^(?:-?\d+(?:\.\d+)?::)+/, '')
      .replace(/::+$/g, '')
      .replace(/[\s-]+/g, '_')
      .replace(/_+/g, '_')
      .replace(/^_|_$/g, ''),
  );
  for (const kind of species) {
    if (normalizedTags.includes(`${kind}_girl`)) return [`${kind}_girl`];
  }
  const upper = normalizeKey(card?.upperBody);
  const lower = normalizeKey(card?.lowerBody);
  for (const kind of species) {
    const key = normalizeKey(kind);
    if (upper.includes(`${key}ear`) || upper.includes(`${key}horn`)) {
      return [`${kind}_girl`];
    }
  }
  for (const kind of species) {
    const key = normalizeKey(kind);
    if (lower.includes(`${key}tail`)) return [`${kind}_girl`];
  }
  return [];
}

function assignTargetCards(cache, roleIds) {
  const result = new Map();
  if (roleIds.length === 0 || targetCards.length === 0) return result;
  const pepe =
    targetCards.find((card) => card.id === 'legacy-character-sheet-r14') ??
    targetCards[0];
  if (args.defaultTargetCharacterId) {
    const requested = targetCards.find(
      (card) => card.id === args.defaultTargetCharacterId,
    );
    const defaultTarget = requested ?? pepe;
    for (const roleId of roleIds) result.set(roleId, defaultTarget);
    return result;
  }
  result.set(roleIds[0], pepe);
  const companions = targetCards.filter((card) => card.id !== pepe.id);
  if (companions.length === 0) {
    for (const roleId of roleIds.slice(1)) result.set(roleId, pepe);
    return result;
  }
  const offset = stableStringHash(stringValue(cache?.scriptId)) % companions.length;
  for (let index = 1; index < roleIds.length; index += 1) {
    result.set(roleIds[index], companions[(offset + index - 1) % companions.length]);
  }
  return result;
}

function stableStringHash(value) {
  let hash = 0x811c9dc5;
  for (const character of String(value ?? '')) {
    hash ^= character.codePointAt(0);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash;
}

function loadCharacterHairstyleTags(file) {
  const library = loadJson(file);
  const characters = Array.isArray(library)
    ? library
    : Array.isArray(library?.characters)
      ? library.characters
      : [];
  const result = new Map();
  for (const character of characters) {
    const id = stringValue(character?.id);
    if (!id) continue;
    const defaultOutfitId = stringValue(character?.defaultOutfitId);
    const outfits = Array.isArray(character?.outfits) ? character.outfits : [];
    const defaultOutfit =
      outfits.find((outfit) => stringValue(outfit?.id) === defaultOutfitId) ?? outfits[0];
    const characterHairstyleTags = extractHairstyleTags(
      character?.traits?.front_upper,
    );
    const outfitHairstyleTags = extractHairstyleTags(
      defaultOutfit?.partTags?.upperBodyTags,
    );
    result.set(
      id,
      characterHairstyleTags.length > 0
        ? characterHairstyleTags
        : outfitHairstyleTags,
    );
  }
  return result;
}

function extractHairstyleTags(value) {
  const values = Array.isArray(value) ? value : splitPromptTags(value);
  return uniquePrompts(
    values.map(cleanSourcePromptTag).filter(isTargetHairstyleTag),
  );
}

function isTargetHairstyleTag(value) {
  const key = stringValue(value).toLowerCase().replace(/[\s-]+/g, '_');
  if (!key) return false;
  if (
    /^(?:aqua|black|blue|blonde|brown|green|grey|gray|orange|pink|purple|red|silver|white|yellow)_hair$/.test(
      key,
    )
  ) {
    return false;
  }
  if (
    /(?:hair_?ornament|hair_?band|hair_?bow|hair_?ribbon|hair_?flower|hair_?clip|headwear|headdress)/.test(
      key,
    )
  ) {
    return false;
  }
  return (
    /(?:hair|bang|braid|ponytail|twintail|bun|drill|ahoge|sidelock|tress)/.test(key) ||
    key === 'covering_one_eye'
  );
}

function normalizePath(value) {
  return String(value ?? '').replaceAll('\\', '/').replace(/\/+$/, '').toLowerCase();
}

function normalizeKey(value) {
  return String(value ?? '')
    .toLowerCase()
    .replace(/[\s_()-]+/g, '');
}

function spacedText(value) {
  return ` ${String(value ?? '')
    .toLowerCase()
    .replace(/[_-]+/g, ' ')
    .replace(/[(){}[\]:]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()} `;
}

function hasWord(spaced, word) {
  return spaced.includes(` ${word} `);
}

function hasAnyWord(spaced, words) {
  return words.some((word) => hasWord(spaced, word));
}

function splitPromptTags(value) {
  return String(value ?? '')
    .split(',')
    .map((tag) => tag.trim())
    .filter(Boolean);
}

function uniquePrompts(values) {
  const result = [];
  const seen = new Set();
  for (const value of values) {
    const clean = stringValue(value).trim();
    if (!clean) continue;
    const key = normalizeKey(clean);
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(clean);
  }
  return result;
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function arrayValue(value) {
  return Array.isArray(value) ? value : [];
}

function joinPrompts(parts) {
  return parts.map(stringValue).map((part) => part.trim()).filter(Boolean).join(', ');
}

function timestampForPath() {
  return new Date().toISOString().replace(/[-:T.Z]/g, '').slice(0, 14);
}
