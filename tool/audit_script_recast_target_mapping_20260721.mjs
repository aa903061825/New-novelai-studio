#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const options = parseArgs(process.argv.slice(2));
if (!options.cacheDir) {
  throw new Error('Pass --cache-dir <directory>.');
}

const cacheDir = path.resolve(options.cacheDir);
const characterLibraryPath = path.resolve(
  options.characterLibrary || path.join(cacheDir, '..', '..', 'library', 'characters.json'),
);
const hairAuditEnabled = fs.existsSync(characterLibraryPath);
const targetHairstyleTagsById = hairAuditEnabled
  ? loadCharacterHairstyleTags(characterLibraryPath)
  : new Map();
const fallbackGenericGirlTagsById = new Map([
  ['legacy-character-sheet-r14', ['loli', 'girl', 'cat_girl']],
  ['legacy-character-sheet-r13', ['loli', 'girl', 'fox_girl']],
  ['legacy-character-sheet-r29', ['loli', 'girl', 'fox_girl']],
  ['legacy-character-sheet-r10', ['loli', 'girl', 'cat_girl']],
  ['legacy-character-sheet-r1', ['loli', 'girl', 'sheep_girl']],
  ['legacy-character-sheet-r3', ['loli', 'girl']],
]);
const targetGenericGirlTagsById = hairAuditEnabled
  ? loadCharacterGenericGirlTags(characterLibraryPath)
  : fallbackGenericGirlTagsById;
const expectedPepeAnchor =
  'pepe_(arknights), 1.5:: cat_ears ::, -3:: hood ::, ' +
  '-3:: wearing hood ::, -3:: animal hood ::, ' +
  '2:: lotus_flower_headdress ::';
const expectedHeadAccessoryPrompt = 'animal_ear_fluff, animal_ears';
const pepeTargetId = 'legacy-character-sheet-r14';
const allowedTargetIds = new Set(targetGenericGirlTagsById.keys());
const allowedFiles = new Set(options.cacheFiles);
const files = fs
  .readdirSync(cacheDir)
  .filter(
    (file) =>
      file.endsWith('.json') &&
      (allowedFiles.size === 0 || allowedFiles.has(file)),
  )
  .sort();

const report = {
  tool: 'audit_script_recast_target_mapping_20260721',
  api_used: false,
  cache_dir: cacheDir,
  character_library: characterLibraryPath,
  hair_audit_enabled: hairAuditEnabled,
  target_hairstyle_profiles: Object.fromEntries(targetHairstyleTagsById),
  target_generic_girl_profiles: Object.fromEntries(targetGenericGirlTagsById),
  target_character_filter: options.targetCharacterIds,
  files_scanned: files.length,
  mapped_role_count: 0,
  pepe_role_count: 0,
  non_pepe_role_count: 0,
  girl_rule_count: 0,
  pepe_anchor_rule_count: 0,
  head_accessory_source_term_count: 0,
  conflict_delete_source_term_count: 0,
  multi_term_delete_rule_count: 0,
  black_underwear_swimwear_source_term_count: 0,
  underwear_swimwear_recolor_source_term_count: 0,
  protected_white_pink_underwear_source_term_count: 0,
  male_role_replacement_count_excluded: 0,
  female_hair_style_source_term_count: 0,
  female_hair_state_source_term_count: 0,
  hair_style_rules_deleted_missing_target: 0,
  hair_style_source_coverage_count: 0,
  ordinary_clothing_unmapped_source_term_count: 0,
  merged_rule_count: 0,
  semantic_alias_group_count: 0,
  split_semantic_alias_rule_count: 0,
  targeted_stage_count: 0,
  violation_count: 0,
  assignments: [],
  black_clothing_mappings: [],
  underwear_color_mappings: [],
  hair_mappings: [],
  violations: [],
};

for (const fileName of files) {
  const cache = JSON.parse(fs.readFileSync(path.join(cacheDir, fileName), 'utf8'));
  const roles = arrayValue(cache.aiRoleExtraction?.roles);
  const roleById = new Map(
    roles.map((role) => [stringValue(role?.source_role_id), role]),
  );
  const replacements = arrayValue(cache.mapping?.rolePromptReplacements);
  const mapped = replacements.filter((replacement) =>
    stringValue(replacement?.targetCharacterId),
  );
  const mappedRoleIds = new Set(
    mapped.map((replacement) => stringValue(replacement.sourceRoleId)),
  );
  report.mapped_role_count += mapped.length;

  if (arrayValue(cache.mapping?.roleSwaps).length > 0) {
    addViolation(fileName, '', 'hidden_role_swaps_present');
  }

  const primaryRoleId = [...mappedRoleIds].sort((left, right) => {
    const frameDifference =
      roleFrameIndexes(roleById.get(right)).length -
      roleFrameIndexes(roleById.get(left)).length;
    if (frameDifference !== 0) return frameDifference;
    return left.localeCompare(right, undefined, { numeric: true });
  })[0];

  let filePepeCount = 0;
  for (const replacement of mapped) {
    const roleId = stringValue(replacement.sourceRoleId);
    const targetId = stringValue(replacement.targetCharacterId);
    const role = roleById.get(roleId);
    const rules = arrayValue(replacement.rules);
    const isPepe = targetId === pepeTargetId;
    if (isPepe) {
      filePepeCount += 1;
      report.pepe_role_count += 1;
    } else {
      report.non_pepe_role_count += 1;
    }
    report.assignments.push({
      file_name: fileName,
      script_name: stringValue(cache.scriptName),
      source_role_id: roleId,
      source_display_name: stringValue(role?.display_name),
      frame_count: roleFrameIndexes(role).length,
      target_character_id: targetId,
      is_primary_role: roleId === primaryRoleId,
    });

    if (!allowedTargetIds.has(targetId)) {
      addViolation(fileName, roleId, `unexpected_target:${targetId}`);
    }
    if (roleId === primaryRoleId && !isPepe) {
      addViolation(fileName, roleId, `primary_role_not_pepe:${targetId}`);
    }
    if (containsClothingTargetPrompt(replacement.targetIdentityPrompt)) {
      addViolation(fileName, roleId, 'target_identity_prompt_contains_clothing');
    }
    if (
      hairAuditEnabled &&
      !roleIsMale(role) &&
      (options.targetCharacterIds.length === 0 ||
        options.targetCharacterIds.includes(targetId))
    ) {
      auditHairMapping({
        cache,
        fileName,
        replacement,
        role,
        roleId,
        targetId,
      });
    }

    const aliasRules = new Map();
    for (const rule of rules) {
      for (const term of arrayValue(rule.sourceTerms)) {
        const alias = canonicalSourceAliasText(term?.text);
        if (!alias) continue;
        if (!aliasRules.has(alias)) aliasRules.set(alias, new Map());
        aliasRules.get(alias).set(stringValue(rule.id), rule);
      }
    }
    for (const [alias, rulesById] of aliasRules) {
      if (rulesById.size <= 1) continue;
      report.split_semantic_alias_rule_count += 1;
      const sourceTexts = [
        ...new Set(
          [...rulesById.values()].flatMap((rule) =>
            arrayValue(rule.sourceTerms).map((term) => stringValue(term?.text)),
          ),
        ),
      ];
      addViolation(
        fileName,
        roleId,
        `semantic_alias_split:${alias}:${sourceTexts.join('|')}`,
      );
    }
    report.semantic_alias_group_count += [...aliasRules.values()].filter(
      (rulesById) => rulesById.size === 1,
    ).length;

    const girlRules = rules.filter((rule) =>
      arrayValue(rule.sourceTerms).some(isExactGirlTerm),
    );
    report.girl_rule_count += girlRules.length;
    const hasGirlSourceEvidence = roleHasExactGirlSourceEvidence(cache, role);
    if (hasGirlSourceEvidence && girlRules.length !== 1) {
      addViolation(fileName, roleId, `girl_rule_count:${girlRules.length}`);
    } else if (
      hasGirlSourceEvidence &&
      stringValue(girlRules[0].action) !== 'replace' ||
      hasGirlSourceEvidence &&
        stringValue(girlRules[0].targetPrompt) !==
          arrayValue(targetGenericGirlTagsById.get(targetId)).join(', ')
    ) {
      addViolation(fileName, roleId, 'girl_rule_target_mismatch');
    }

    const aiGirlTerms = arrayValue(role?.prompt_terms).filter(isExactGirlTerm);
    if (hasGirlSourceEvidence && aiGirlTerms.length !== 1) {
      addViolation(fileName, roleId, `ai_girl_term_count:${aiGirlTerms.length}`);
    } else if (
      hasGirlSourceEvidence &&
      arrayValue(aiGirlTerms[0].source_occurrences).length === 0
    ) {
      addViolation(fileName, roleId, 'ai_girl_term_missing_occurrences');
    }

    const anchorRules = rules.filter((rule) =>
      arrayValue(rule.sourceTerms).some(
        (term) => isIdentityTerm(term) && !isExactGirlTerm(term),
      ),
    );
    if (isPepe) {
      const matchingAnchors = anchorRules.filter(
        (rule) =>
          stringValue(rule.action) === 'replace' &&
          stringValue(rule.targetPrompt) === expectedPepeAnchor,
      );
      report.pepe_anchor_rule_count += matchingAnchors.length;
      if (matchingAnchors.length === 0) {
        addViolation(fileName, roleId, 'missing_weighted_pepe_anchor');
      }
    } else if (
      anchorRules.some((rule) =>
        stringValue(rule.targetPrompt).includes('lotus_flower_headdress'),
      )
    ) {
      addViolation(fileName, roleId, 'non_pepe_anchor_has_pepe_extras');
    }

    for (const rule of rules) {
      const sourceTerms = arrayValue(rule.sourceTerms);
      const allHeadAccessoryTerms =
        sourceTerms.length > 0 &&
        sourceTerms.every((term) => isHeadAccessoryText(stringValue(term?.text)));
      const targetPromptTokens = new Set(
        stringValue(rule.targetPrompt)
          .split(',')
          .map(normalizedKey)
          .filter(Boolean),
      );
      const expectedHeadAccessoryTokens = expectedHeadAccessoryPrompt
        .split(',')
        .map(normalizedKey)
        .filter(Boolean);
      if (sourceTerms.length > 1) report.merged_rule_count += 1;
      if (stringValue(rule.action) === 'delete' && sourceTerms.length !== 1) {
        report.multi_term_delete_rule_count += 1;
        addViolation(
          fileName,
          roleId,
          `delete_rule_must_have_one_source_term:${stringValue(rule.id)}`,
        );
      }
      for (const term of sourceTerms) {
        const text = stringValue(term?.text);
        if (isHeadAccessoryText(text)) {
          report.head_accessory_source_term_count += 1;
          const conflict = isAppearanceConflict(text);
          if (conflict) {
            report.conflict_delete_source_term_count += 1;
            if (stringValue(rule.action) !== 'delete') {
              addViolation(fileName, roleId, `head_conflict_not_deleted:${text}`);
            }
          } else if (
            stringValue(rule.action) !== 'replace' ||
            !expectedHeadAccessoryTokens.every((token) => targetPromptTokens.has(token)) ||
            (allHeadAccessoryTerms &&
              targetPromptTokens.size !== expectedHeadAccessoryTokens.length)
          ) {
            addViolation(fileName, roleId, `head_accessory_target_mismatch:${text}`);
          }
        } else if (normalizedText(text) === 'tress ribbon') {
          report.conflict_delete_source_term_count += 1;
          if (stringValue(rule.action) !== 'delete') {
            addViolation(fileName, roleId, 'tress_ribbon_not_deleted');
          }
        }

      }
    }
  }

  for (const replacement of replacements) {
    const roleId = stringValue(replacement?.sourceRoleId);
    const role = roleById.get(roleId);
    if (roleIsMale(role)) {
      report.male_role_replacement_count_excluded += 1;
      continue;
    }
    const rules = arrayValue(replacement?.rules);
    for (const rule of rules) {
      for (const term of arrayValue(rule?.sourceTerms)) {
        if (!isClothingTerm(term)) continue;
        const text = stringValue(term?.text);
        if (isBlackUnderwearOrSwimwear(text)) {
          report.black_underwear_swimwear_source_term_count += 1;
          report.black_clothing_mappings.push({
            file_name: fileName,
            source_role_id: roleId,
            source_text: text,
            target_prompt: stringValue(rule?.targetPrompt),
          });
        }
        if (hasOnlyProtectedUnderwearColors(text) && isUnderwearColorPolicyTerm(term)) {
          report.protected_white_pink_underwear_source_term_count += 1;
          if (stringValue(rule?.action)) {
            addViolation(fileName, roleId, `protected_underwear_has_action:${text}`);
          }
          continue;
        }
        if (underwearTermNeedsRecolor(term, rules)) {
          report.underwear_swimwear_recolor_source_term_count += 1;
          report.underwear_color_mappings.push({
            file_name: fileName,
            source_role_id: roleId,
            source_text: text,
            target_prompt: stringValue(rule?.targetPrompt),
          });
          const targetPrompt = normalizedText(rule?.targetPrompt);
          const disallowedTargetColors = underwearColorWordsIn(targetPrompt).filter(
            (color) => color !== 'white' && color !== 'pink',
          );
          if (
            stringValue(rule?.action) !== 'replace' ||
            (!targetPrompt.includes('pink') && !targetPrompt.includes('white')) ||
            disallowedTargetColors.length > 0
          ) {
            addViolation(fileName, roleId, `underwear_color_target_mismatch:${text}`);
          }
          continue;
        }
        report.ordinary_clothing_unmapped_source_term_count += 1;
        if (stringValue(rule?.action)) {
          addViolation(fileName, roleId, `ordinary_clothing_has_action:${text}`);
        }
      }
    }
  }

  if (mapped.length > 0 && filePepeCount !== 1) {
    addViolation(fileName, '', `pepe_role_count:${filePepeCount}`);
  }

  for (const assembly of arrayValue(cache.mapping?.roleAssemblies)) {
    if (!mappedRoleIds.has(stringValue(assembly?.sourceRoleId))) continue;
    for (const stage of arrayValue(assembly?.stages)) {
      report.targeted_stage_count += 1;
      if (!stringValue(stage?.targetCharacterId)) {
        addViolation(fileName, stringValue(assembly?.sourceRoleId), 'stage_missing_target');
      }
      if (
        stringValue(stage?.targetUpperOutfitId) ||
        stringValue(stage?.targetLowerOutfitId)
      ) {
        addViolation(fileName, stringValue(assembly?.sourceRoleId), 'stage_outfit_target_present');
      }
      if (
        stringValue(stage?.manualParts?.upperClothing) ||
        stringValue(stage?.manualParts?.lowerClothing)
      ) {
        addViolation(fileName, stringValue(assembly?.sourceRoleId), 'stage_manual_clothing_present');
      }
      const preserved = new Set(arrayValue(stage?.preservedParts).map(stringValue));
      if (
        stringValue(stage?.sourceParts?.upperClothing) &&
        !preserved.has('upperClothing')
      ) {
        addViolation(fileName, stringValue(assembly?.sourceRoleId), 'upper_clothing_not_preserved');
      }
      if (
        stringValue(stage?.sourceParts?.lowerClothing) &&
        !preserved.has('lowerClothing')
      ) {
        addViolation(fileName, stringValue(assembly?.sourceRoleId), 'lower_clothing_not_preserved');
      }
    }
  }
}

report.violation_count = report.violations.length;
if (options.report) {
  const reportPath = path.resolve(options.report);
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
}
process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
if (report.violation_count > 0) process.exitCode = 1;

function addViolation(fileName, roleId, message) {
  report.violations.push({
    file_name: fileName,
    ...(roleId ? { source_role_id: roleId } : {}),
    message,
  });
}

function auditHairMapping({ cache, fileName, replacement, role, roleId, targetId }) {
  const rules = arrayValue(replacement?.rules);
  const hairstyleTags = targetHairstyleTagsById.get(targetId) ?? [];
  const ruleByAlias = new Map();
  for (const rule of rules) {
    for (const term of arrayValue(rule?.sourceTerms)) {
      const alias = canonicalSourceAliasText(term?.text || term?.sourcePhrase);
      if (alias) ruleByAlias.set(alias, rule);
      const text = stringValue(term?.text || term?.sourcePhrase);
      if (isPreservedHairStateText(text)) {
        report.female_hair_state_source_term_count += 1;
        if (stringValue(rule?.action)) {
          addViolation(fileName, roleId, `hair_state_not_preserved:${text}`);
        }
        continue;
      }
      const isHairStyle = isHairStyleText(text);
      if (isHairStyle && isAppearanceConflict(text)) {
        if (stringValue(rule?.action) !== 'delete') {
          addViolation(fileName, roleId, `hair_conflict_not_deleted:${text}`);
        }
        continue;
      }
      if (!isHairStyle) continue;
      report.female_hair_style_source_term_count += 1;
      report.hair_mappings.push({
        file_name: fileName,
        source_role_id: roleId,
        source_text: text,
        target_character_id: targetId,
        target_prompt: stringValue(rule?.targetPrompt),
        action: stringValue(rule?.action),
      });
      if (hairstyleTags.length === 0) {
        if (stringValue(rule?.action) !== 'delete' || stringValue(rule?.targetPrompt)) {
          addViolation(fileName, roleId, `hair_style_missing_target_not_deleted:${text}`);
        } else {
          report.hair_style_rules_deleted_missing_target += 1;
        }
      } else if (
        stringValue(rule?.action) !== 'replace' ||
        !samePromptTags(rule?.targetPrompt, hairstyleTags)
      ) {
        addViolation(fileName, roleId, `hair_style_target_mismatch:${text}`);
      }
    }
  }

  for (const sourceTerm of hairstyleSourceTermsForRole(cache, role)) {
    const alias = canonicalSourceAliasText(sourceTerm.text);
    if (!alias) continue;
    report.hair_style_source_coverage_count += 1;
    if (!ruleByAlias.has(alias)) {
      addViolation(fileName, roleId, `hair_style_source_unmapped:${sourceTerm.text}`);
    }
  }
}

function samePromptTags(value, expected) {
  const actual = stringValue(value)
    .split(',')
    .map(normalizedKey)
    .filter(Boolean)
    .sort();
  const wanted = expected.map(normalizedKey).filter(Boolean).sort();
  return JSON.stringify(actual) === JSON.stringify(wanted);
}

function isIdentityTerm(term) {
  const category = normalizedKey(term?.category);
  return category === 'identity' || category === 'character';
}

function isExactGirlTerm(term) {
  return isIdentityTerm(term) && normalizedText(term?.text) === 'girl';
}

function roleHasExactGirlSourceEvidence(cache, role) {
  const frames = new Map(
    arrayValue(cache.scriptSnapshot?.frames).map((frame) => [Number(frame?.index), frame]),
  );
  for (const appearance of arrayValue(role?.appearances)) {
    const sourceId = stringValue(appearance?.source_id || appearance?.sourceId);
    const match = /^slot-(\d+)$/i.exec(sourceId);
    if (!match) continue;
    const slotIndex = Number(match[1]);
    for (const frameIndex of arrayValue(
      appearance?.frame_indexes ?? appearance?.frameIndexes,
    )) {
      const caption = stringValue(frames.get(Number(frameIndex))?.parsed?.charCaptions?.[slotIndex]);
      if (
        caption.split(',').some(
          (tag) => normalizedText(cleanSourcePromptTag(tag)) === 'girl',
        )
      ) {
        return true;
      }
    }
  }
  return false;
}

function isClothingTerm(term) {
  return new Set([
    'clothing',
    'clothingstate',
    'upperclothing',
    'lowerclothing',
  ]).has(normalizedKey(term?.category));
}

function isBlackUnderwearOrSwimwear(value) {
  const text = ` ${normalizedText(value)} `;
  if (!text.includes(' black ')) return false;
  return [
    ' adjusting hair ',
    ' cum on hair ',
    ' bikini ',
    ' bra ',
    ' garter belt ',
    ' lingerie ',
    ' panties ',
    ' panty ',
    ' swimsuit ',
    ' swimwear ',
    ' thong ',
    ' underwear ',
    ' babydoll ',
  ].some((needle) => text.includes(needle));
}

function underwearTermNeedsRecolor(term, rules) {
  if (!isUnderwearColorPolicyTerm(term)) return false;
  const text = stringValue(term?.text);
  if (hasOnlyProtectedUnderwearColors(text)) return false;
  const colors = underwearColorWordsIn(text);
  if (colors.some((color) => color !== 'white' && color !== 'pink')) {
    return true;
  }
  return !underwearColorCoveredByPeerTerms(term, rules);
}

function isUnderwearColorPolicyTerm(term) {
  const category = normalizedKey(term?.category);
  const text = ` ${normalizedText(term?.text ?? term?.sourcePhrase)} `;
  if (!isUnderwearOrSwimwearText(text)) return false;
  if (
    category === 'clothingstate' &&
    !([' ripped ', ' torn '].some((needle) => text.includes(needle)) &&
      isUnderwearOrSwimwearText(text))
  ) {
    return false;
  }
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

function isUnderwearOrSwimwearText(text) {
  return [
    ' bikini ',
    ' bra ',
    ' garter belt ',
    ' lingerie ',
    ' panties ',
    ' panty ',
    ' swimsuit ',
    ' swimwear ',
    ' thong ',
    ' underwear ',
    ' babydoll ',
  ].some((needle) => text.includes(needle));
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
  const text = ` ${normalizedText(value)} `;
  return underwearColorWords().filter((color) => text.includes(` ${color} `));
}

function hasOnlyProtectedUnderwearColors(value) {
  const colors = underwearColorWordsIn(value);
  return (
    colors.length > 0 &&
    colors.every((color) => color === 'white' || color === 'pink')
  );
}

function underwearColorCoveredByPeerTerms(term, rules) {
  const frames = mappingTermFrameIndexes(term);
  if (frames.length === 0) return false;
  const family = underwearColorFamily(term?.text);
  if (!family) return false;
  const covered = new Set();
  for (const rule of arrayValue(rules)) {
    for (const peer of arrayValue(rule?.sourceTerms)) {
      if (peer === term || underwearColorFamily(peer?.text) !== family) continue;
      if (underwearColorWordsIn(peer?.text).length === 0) continue;
      for (const frameIndex of mappingTermFrameIndexes(peer)) covered.add(frameIndex);
    }
  }
  return frames.every((frameIndex) => covered.has(frameIndex));
}

function mappingTermFrameIndexes(term) {
  return [
    ...new Set([
      ...arrayValue(term?.frameIndexes),
      ...arrayValue(term?.sourceOccurrences).map(
        (occurrence) => occurrence?.frameIndex,
      ),
    ].map(Number).filter(Number.isFinite)),
  ].sort((left, right) => left - right);
}

function underwearColorFamily(value) {
  const text = ` ${normalizedText(value)} `;
  if (
    text.includes(' bikini ') ||
    text.includes(' swimsuit ') ||
    text.includes(' swimwear ')
  ) {
    return 'swimwear';
  }
  if (text.includes(' babydoll ')) return 'babydoll';
  if (text.includes(' lingerie ')) return 'lingerie';
  if (text.includes(' garter belt ')) return 'garter-belt';
  if (text.includes(' bra ')) return 'bra';
  if (text.includes(' thong ')) return 'thong';
  if (text.includes(' panties ') || text.includes(' panty ')) return 'panties';
  if (text.includes(' underwear ')) return 'underwear';
  return '';
}

function canonicalSourceAliasText(value) {
  const normalized = normalizedText(value);
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

function isPreservedHairStateText(value) {
  const text = ` ${normalizedText(value)} `;
  return [
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
  ].some((phrase) => text.includes(phrase));
}

function isHairStyleText(value) {
  const text = ` ${normalizedText(value)} `;
  if (normalizedText(value) === 'tress ribbon') return false;
  if (
    [
      ' pubic ',
      ' male ',
      ' leg ',
      ' chest ',
      ' body ',
      ' facial ',
      ' armpit ',
    ].some((needle) => text.includes(needle)) ||
    text.includes(' between legs ') ||
    isPreservedHairStateText(text)
  ) {
    return false;
  }
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
  if (text.includes(' hair ') && colors.some((color) => text.includes(` ${color} `))) {
    return false;
  }
  if (
    text.includes(' hair ') &&
    [
      ' bow ',
      ' bows ',
      ' feather ',
      ' feathers ',
      ' flower ',
      ' flowers ',
      ' ornament ',
      ' ornaments ',
      ' ribbon ',
      ' ribbons ',
      ' ring ',
      ' rings ',
    ].some((needle) => text.includes(needle))
  ) {
    return false;
  }
  return (
    [
      ' pony tail ',
      ' one side up ',
      ' two side up ',
      ' bob cut ',
      ' pixie cut ',
    ].some((needle) => text.includes(needle)) ||
    (text.includes(' hair ') &&
      [
        ' alternate ',
        ' asymmetric ',
        ' asymmetrical ',
        ' between ',
        ' blunt ',
        ' curly ',
        ' intakes ',
        ' length ',
        ' long ',
        ' medium ',
        ' over ',
        ' short ',
        ' straight ',
        ' up ',
        ' very ',
        ' wavy ',
      ].some((needle) => text.includes(needle))) ||
    [
      ' ahoge ',
      ' bun ',
      ' buns ',
      ' drill ',
      ' drills ',
      ' hairstyle ',
      ' hairstyles ',
      ' locks ',
      ' ponytail ',
      ' ponytails ',
      ' sidelock ',
      ' sidelocks ',
      ' tress ',
      ' tresses ',
      ' twintails ',
      ' braid ',
      ' braids ',
      ' braided ',
      ' bangs ',
    ].some((needle) => text.includes(needle))
  );
}

function hairstyleSourceTermsForRole(cache, role) {
  const result = new Map();
  for (const term of arrayValue(role?.prompt_terms)) {
    const text = stringValue(term?.text || term?.source_phrase);
    if (isHairStyleText(text)) result.set(canonicalSourceAliasText(text), { text });
  }
  const frames = new Map(
    arrayValue(cache.scriptSnapshot?.frames).map((frame) => [Number(frame?.index), frame]),
  );
  for (const appearance of arrayValue(role?.appearances)) {
    const sourceId = stringValue(appearance?.source_id || appearance?.sourceId);
    const match = /^slot-(\d+)$/.exec(sourceId);
    if (!match) continue;
    const slotIndex = Number(match[1]);
    for (const frameIndex of arrayValue(
      appearance?.frame_indexes ?? appearance?.frameIndexes,
    )) {
      const caption = stringValue(frames.get(Number(frameIndex))?.parsed?.charCaptions?.[slotIndex]);
      for (const sourcePhrase of caption.split(',').map(cleanSourcePromptTag)) {
        const text = sourcePhrase.replaceAll('_', ' ').replace(/\s+/g, ' ').trim();
        if (isHairStyleText(text)) result.set(canonicalSourceAliasText(text), { text });
      }
    }
  }
  return [...result.values()];
}

function cleanSourcePromptTag(value) {
  return stringValue(value)
    .replace(/^[-+]?\d+(?:\.\d+)?::\s*/, '')
    .replace(/^:+\s*/, '')
    .replace(/\s*::$/, '')
    .trim();
}

function isHeadAccessoryText(value) {
  const text = ` ${normalizedText(value)} `;
  if (isHairStyleText(text)) return false;
  if (text.includes(' fake ') && (text.includes(' ear ') || text.includes(' ears '))) {
    return true;
  }
  if (
    [
      ' cap ',
      ' crown ',
      ' hairband ',
      ' hat ',
      ' headband ',
      ' headdress ',
      ' headgear ',
      ' headpiece ',
      ' tiara ',
      ' veil ',
    ].some((needle) => text.includes(needle))
  ) {
    return true;
  }
  const hasHairOrHead = text.includes(' hair ') || text.includes(' head ');
  const hasAccessory = [
    ' band ',
    ' bow ',
    ' bows ',
    ' feather ',
    ' feathers ',
    ' flower ',
    ' flowers ',
    ' ornament ',
    ' ornaments ',
    ' ribbon ',
    ' ribbons ',
    ' ring ',
    ' rings ',
  ].some((needle) => text.includes(needle));
  return hasHairOrHead && hasAccessory;
}

function isAppearanceConflict(value) {
  const text = ` ${normalizedText(value)} `;
  return (
    text.includes(' no ') ||
    text.includes(' without ') ||
    text.includes(' lack of ') ||
    normalizedText(value) === 'tress ribbon'
  );
}

function containsClothingTargetPrompt(value) {
  const clothingWords = new Set([
    'bikini',
    'bra',
    'coat',
    'dress',
    'jacket',
    'panties',
    'shirt',
    'shorts',
    'skirt',
    'swimsuit',
    'underwear',
  ]);
  return stringValue(value).split(',').some((rawTag) => {
    const tag = normalizedText(
      rawTag.replace(/^(?:-?\d+(?:\.\d+)?::)+/, '').replace(/::+$/g, ''),
    );
    if (!tag || tag === 'dress bow') return false;
    return tag.split(' ').some((word) => clothingWords.has(word));
  });
}

function roleFrameIndexes(role) {
  return [
    ...new Set([
      ...arrayValue(role?.frame_indexes),
      ...arrayValue(role?.appearances).flatMap((appearance) =>
        arrayValue(appearance?.frame_indexes),
      ),
      ...arrayValue(role?.stages).flatMap((stage) =>
        arrayValue(stage?.frame_indexes),
      ),
    ].map(Number).filter(Number.isFinite)),
  ].sort((left, right) => left - right);
}

function loadCharacterHairstyleTags(file) {
  const library = JSON.parse(fs.readFileSync(file, 'utf8'));
  const characters = Array.isArray(library)
    ? library
    : arrayValue(library?.characters);
  const result = new Map();
  for (const character of characters) {
    const id = stringValue(character?.id);
    if (!id) continue;
    const outfits = arrayValue(character?.outfits);
    const defaultOutfit =
      outfits.find(
        (outfit) => stringValue(outfit?.id) === stringValue(character?.defaultOutfitId),
      ) ?? outfits[0];
    const characterHairstyleTags = extractHairstyleTags(
      character?.traits?.front_upper,
    );
    const outfitHairstyleTags = extractHairstyleTags(
      defaultOutfit?.partTags?.upperBodyTags,
    );
    result.set(
      id,
      characterHairstyleTags.length > 0
        ? uniqueStrings(characterHairstyleTags)
        : uniqueStrings(outfitHairstyleTags),
    );
  }
  return result;
}

function loadCharacterGenericGirlTags(file) {
  const library = JSON.parse(fs.readFileSync(file, 'utf8'));
  const characters = Array.isArray(library)
    ? library
    : arrayValue(library?.characters);
  const result = new Map();
  const explicitlyExcludedIds = new Set([
    'legacy-character-sheet-r27',
    'legacy-character-sheet-r30',
  ]);
  for (const character of characters) {
    const id = stringValue(character?.id);
    const hasPreview = arrayValue(character?.imageRefs)
      .map(stringValue)
      .some(Boolean);
    if (!id || !hasPreview || explicitlyExcludedIds.has(id)) continue;
    result.set(id, [
      'loli',
      'girl',
      ...characterSpeciesGirlTags(character),
    ]);
  }
  return result.size > 0 ? result : fallbackGenericGirlTagsById;
}

function characterSpeciesGirlTags(character) {
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
  const rawTags = [
    ...stringValue(character?.traits?.front_full).split(','),
    ...stringValue(character?.traits?.front_upper).split(','),
    ...stringValue(character?.traits?.front_lower).split(','),
    ...arrayValue(character?.identityTags),
  ];
  const normalizedTags = rawTags.map((tag) =>
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
  const upper = normalizedKey(character?.traits?.front_upper);
  const lower = normalizedKey(character?.traits?.front_lower);
  for (const kind of species) {
    const key = normalizedKey(kind);
    if (upper.includes(`${key}ear`) || upper.includes(`${key}horn`)) {
      return [`${kind}_girl`];
    }
  }
  for (const kind of species) {
    const key = normalizedKey(kind);
    if (lower.includes(`${key}tail`)) return [`${kind}_girl`];
  }
  return [];
}

function extractHairstyleTags(value) {
  const values = Array.isArray(value) ? value : stringValue(value).split(',');
  return values.map(cleanSourcePromptTag).filter(isTargetHairstyleTag);
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

function uniqueStrings(values) {
  const result = [];
  const seen = new Set();
  for (const value of values) {
    const key = normalizedKey(value);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(stringValue(value));
  }
  return result;
}

function parseArgs(args) {
  const result = {
    cacheDir: '',
    report: '',
    characterLibrary: '',
    targetCharacterIds: [],
    cacheFiles: [],
  };
  for (let index = 0; index < args.length; index += 1) {
    const key = args[index];
    if (!key.startsWith('--')) continue;
    const value = args[index + 1];
    index += 1;
    if (key === '--cache-dir') result.cacheDir = value;
    if (key === '--report') result.report = value;
    if (key === '--character-library') result.characterLibrary = value;
    if (key === '--target-character-id') result.targetCharacterIds.push(value);
    if (key === '--cache-file') result.cacheFiles.push(path.basename(value));
  }
  return result;
}

function normalizedKey(value) {
  return stringValue(value).toLowerCase().replace(/[\s_-]+/g, '');
}

function normalizedText(value) {
  return stringValue(value)
    .toLowerCase()
    .replaceAll('_', ' ')
    .replaceAll('-', ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function stringValue(value) {
  return value == null ? '' : String(value).trim();
}

function arrayValue(value) {
  return Array.isArray(value) ? value : [];
}

function roleIsMale(role) {
  if (!role || typeof role !== 'object') return false;
  const text = ` ${[
    role.source_role_id,
    role.display_name,
    role.canonical_name,
    ...arrayValue(role.raw_identity_tags),
  ]
    .map((value) => stringValue(value).toLowerCase().replaceAll('_', ' '))
    .join(' ')} `;
  const hasFemale = [
    ' 1girl ',
    ' 2girls ',
    ' 3girls ',
    ' girl ',
    ' girls ',
    ' female ',
    ' woman ',
    ' women ',
    ' heroine ',
  ].some((needle) => text.includes(needle));
  if (hasFemale) return false;
  return [
    ' 1boy ',
    ' boy ',
    ' boys ',
    ' male ',
    ' man ',
    ' father ',
    ' dad ',
    ' uncle ',
    ' sensei ',
    ' teacher ',
    ' shota ',
    ' gyaruo ',
  ].some((needle) => text.includes(needle));
}
