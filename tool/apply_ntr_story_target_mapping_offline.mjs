import fs from 'node:fs';
import path from 'node:path';

const args = parseArgs(process.argv.slice(2));

if (!args.sourceRoot) {
  throw new Error('Pass --source-root <directory>.');
}

const workspace = path.resolve(
  args.workspace ??
    path.join(process.env.APPDATA ?? '', 'Novel Studio', 'Novel Studio', 'novel_studio'),
);
const cacheDir = path.join(workspace, 'script_recast', 'cache');
const sourceRoot = normalizePath(path.resolve(args.sourceRoot));
const backupDir =
  args.backupDir ??
  path.resolve('build', `ntr_story_mapping_cache_backups_${timestampForPath()}`);
const reportPath =
  args.report ?? path.resolve('build', `ntr_story_mapping_cache_report_${timestampForPath()}.json`);
const allowedFiles = args.importReport ? importReportFileNames(args.importReport) : null;

if (!fs.existsSync(cacheDir)) {
  throw new Error(`Missing cache dir: ${cacheDir}`);
}

const targetCards = [
  {
    key: 'pepe',
    id: 'legacy-character-sheet-r14',
    outfitId: 'default-outfit-copy',
    identity: 'pepe_(arknights)',
    upperBody:
      '1.5:: cat_ears ::, animal_ear_fluff, animal_ears, hair_ornament, jewelry, long_hair, skin_fang, 3:: lotus_flower_headdress ::, -3:: hood ::, -3:: wearing hood ::, -3:: animal hood ::',
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
    upperBody: 'fox_ears, animal_ears, white_hair, red_eyes',
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
].map((card) => ({
  ...card,
  identityBody: joinPrompts([card.identity, card.upperBody, card.lowerBody]),
  clothing: joinPrompts([card.upperClothing, card.lowerClothing]),
  fullPrompt: joinPrompts([
    card.identity,
    card.upperBody,
    card.lowerBody,
    card.upperClothing,
    card.lowerClothing,
  ]),
}));

const files = fs.readdirSync(cacheDir).filter((file) => file.endsWith('.json')).sort();
const report = {
  source_root: args.sourceRoot,
  cache_dir: cacheDir,
  apply: args.apply,
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
  role_assembly_stages_changed: 0,
  role_swaps_written: 0,
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
    cache.updatedAt = new Date().toISOString();
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
  report.role_assembly_stages_changed += result.roleAssemblyStagesChanged;
  report.role_swaps_written += result.roleSwapsWritten;
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
  const mappableRoleIds = orderedRoleIds(cache, roleInfos).filter((roleId) =>
    shouldMapRole(roleInfos.get(roleId), roleId),
  );
  const targetByRoleId = new Map();
  for (let index = 0; index < mappableRoleIds.length; index += 1) {
    targetByRoleId.set(mappableRoleIds[index], targetCards[index % targetCards.length]);
  }

  const result = {
    mappedRoles: mappableRoleIds.length,
    skippedRoles: orderedRoleIds(cache, roleInfos).length - mappableRoleIds.length,
    rolePromptRulesReplaced: 0,
    clothingRulesReplaced: 0,
    clothingRulesPreserved: 0,
    roleAssemblyStagesChanged: 0,
    roleSwapsWritten: 0,
  };

  if (Array.isArray(cache.mapping.rolePromptReplacements)) {
    for (const replacement of cache.mapping.rolePromptReplacements) {
      const target = targetByRoleId.get(stringValue(replacement.sourceRoleId));
      if (!target) continue;
      replacement.targetCharacterId = target.id;
      replacement.targetIdentityPrompt = target.fullPrompt;
      if (!Array.isArray(replacement.rules)) replacement.rules = [];
      for (const rule of replacement.rules) {
        const decision = replacementDecisionForRule(rule, target);
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
          if (hasClothingTerm(rule)) {
            result.clothingRulesPreserved += 1;
          }
        }
      }
      const roleId = stringValue(replacement.sourceRoleId);
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
      replacement.rules = mergeCompatibleReplacementRules(replacement.rules);
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
      clearReplacementTarget(replacement);
    }
  }

  cache.mapping.roleSwaps = [];
  result.roleSwapsWritten = 0;
  return result;
}

function applyStageTarget(stage, target) {
  const before = JSON.stringify(stage);
  const sourceParts = stage.sourceParts ?? {};
  const upperReplacement = clothingReplacementPromptFor(
    sourceParts.upperClothing,
    target,
    'upper',
  );
  const lowerReplacement = clothingReplacementPromptFor(
    sourceParts.lowerClothing,
    target,
    'lower',
  );
  const summaryReplacement = clothingReplacementPromptFor(
    joinPrompts([stage.sourceSummary, stage.label]),
    target,
    'full',
  );
  const replaceUpper = Boolean(upperReplacement);
  const replaceLower = Boolean(lowerReplacement);
  const replaceFromSummary = Boolean(summaryReplacement) && !replaceUpper && !replaceLower;

  stage.targetCharacterId = target.id;
  stage.targetUpperOutfitId = target.outfitId;
  stage.targetLowerOutfitId = target.outfitId;
  stage.omittedParts = [];
  stage.manualParts = {
    identity: target.identity,
    upperBody: target.upperBody,
    ...(target.lowerBody.trim() ? { lowerBody: target.lowerBody } : {}),
    ...(replaceUpper
      ? {
          upperClothing: upperReplacement,
        }
      : {}),
    ...(replaceLower
      ? {
          lowerClothing: lowerReplacement,
        }
      : {}),
    ...(replaceFromSummary
      ? {
          upperClothing: summaryReplacement,
        }
      : {}),
  };
  stage.preservedParts = ['upperClothing', 'lowerClothing'].filter((part) => {
    if (!stringValue(sourceParts[part]).trim()) return false;
    if (part === 'upperClothing' && (replaceUpper || replaceFromSummary)) return false;
    if (part === 'lowerClothing' && replaceLower) return false;
    return true;
  });
  return JSON.stringify(stage) !== before;
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

function replacementDecisionForRule(rule, target) {
  const terms = Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : [];
  const clothingPrompt = clothingReplacementPromptForRule(rule, target);
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
  if (isHairAccessoryText(text)) {
    return targetTagsMatching(target, ['ornament', 'jewelry', 'headdress', 'flower', 'ribbon']);
  }
  if (
    text.includes(' pony tail ') ||
    hasAnyWord(text, [
      'ahoge',
      'ponytail',
      'ponytails',
      'twintails',
      'braid',
      'braids',
      'braided',
      'bangs',
    ])
  ) {
    return targetHairTagsForTerm(target, text);
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
    'bikini',
    'bodysuit',
    'bra',
    'bunnysuit',
    'coat',
    'clothes',
    'dress',
    'glove',
    'gloves',
    'jacket',
    'leotard',
    'lingerie',
    'pants',
    'panties',
    'pantyhose',
    'shirt',
    'shorts',
    'skirt',
    'suit',
    'swimsuit',
    'thighhighs',
    'underwear',
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
  const sourceHasAhoge = hasWord(sourceSpaced, 'ahoge');
  const ahogeTags = sourceHasAhoge ? targetTagsMatching(target, ['ahoge']) : [];
  const hairTags = targetTagsMatching(target, ['hair']).filter(
    (tag) =>
      !tagMatchesNeedle(tag, 'ear') &&
      !tagMatchesNeedle(tag, 'ornament') &&
      !tagMatchesNeedle(tag, 'jewelry') &&
      !tagMatchesNeedle(tag, 'headdress') &&
      !tagMatchesNeedle(tag, 'flower') &&
      !tagMatchesNeedle(tag, 'ribbon'),
  );
  const colors = [
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
  const sourceHasColor = colors.some((color) => hasWord(sourceSpaced, color));
  const preferred = [];
  if (sourceHasColor) {
    preferred.push(
      ...hairTags.filter((tag) => colors.some((color) => tagMatchesNeedle(tag, `${color}_hair`))),
    );
  }
  preferred.push(
    ...hairTags.filter((tag) =>
      ['long_hair', 'very_long_hair', 'short_hair', 'twintails', 'hair_between_eyes'].some(
        (needle) => tagMatchesNeedle(tag, needle),
      ),
    ),
  );
  preferred.push(...ahogeTags);
  preferred.push(...hairTags);
  return uniquePrompts(preferred).slice(0, 3);
}

function clothingReplacementPromptForRule(rule, target) {
  const terms = Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : [];
  const source = terms.map((term) => term?.text).join(', ');
  const directPrompt = clothingReplacementPromptFor(source, target, 'direct-rule');
  if (directPrompt) return directPrompt;
  if (!terms.some((term) => isDisallowedNonSwimwearClothing(term?.text))) {
    return '';
  }
  if (terms.some((term) => spacedText(term?.text).includes(' aside '))) {
    return 'clothes aside';
  }
  const categories = terms.map((term) => normalizeKey(term?.category));
  if (categories.some((category) => category === 'upperclothing')) {
    return target.upperClothing;
  }
  if (categories.some((category) => category === 'lowerclothing')) {
    return target.lowerClothing;
  }
  return target.upperClothing;
}

function isIdentityReplacementTerm(term) {
  const category = normalizeKey(term?.category);
  const text = spacedText(term?.text);
  const phrase = spacedText(term?.sourcePhrase);
  const source = text.trim() ? text : phrase;
  if (isSkippedRoleText(source) && !hasFemaleRoleText(source)) return false;
  if (isNegatedAppearanceText(source)) return false;
  if (isHairStyleSource(source) || isHairAccessoryText(source)) return true;
  if (isPoseActionOrBodyState(source)) return false;
  if (category === 'character' || category === 'identity') return true;
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

function isStableAppearanceAnchor(spaced) {
  return (
    isHairStyleSource(spaced) ||
    isHairAccessoryText(spaced) ||
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
  return (
    spaced.includes(' pony tail ') ||
    hasAnyWord(spaced, [
      'ahoge',
      'ponytail',
      'ponytails',
      'twintails',
      'braid',
      'braids',
      'braided',
      'bangs',
      'hair',
    ])
  );
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

function isNegatedAppearanceText(spaced) {
  return hasAnyWord(spaced, ['no', 'without']) || spaced.includes(' lack of ');
}

function hasClothingTerm(rule) {
  return (Array.isArray(rule?.sourceTerms) ? rule.sourceTerms : []).some((term) => {
    const category = normalizeKey(term?.category);
    return (
      category === 'clothing' ||
      category === 'clothingstate' ||
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
        return category === 'character' || category === 'identity';
      }),
  );
  if (hasIdentityReplacement) return false;

  const identity = sourceIdentityTermForRole(role);
  if (!identity) return false;
  const frameIndexes = roleFrameIndexes(role);
  const termId = `synthetic-${roleId}-identity`;
  rules.unshift({
    id: `synthetic-rule-${roleId}-identity`,
    sourceTerms: [
      {
        id: termId,
        text: identity,
        category: 'character',
        sourcePhrase: identity,
        sourceLocation: 'role identity evidence',
        ...(frameIndexes.length > 0 ? { frameIndexes } : {}),
      },
    ],
    action: 'replace',
    targetPrompt: characterAnchorTagsForTarget(target).join(', '),
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
  return candidates.map(stringValue).map((value) => value.trim()).find(Boolean) ?? '';
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

function replacementMergeKey(rule) {
  const action = stringValue(rule?.action);
  if (action !== 'replace' && action !== 'delete') return '';
  const targetPrompt = action === 'replace' ? stringValue(rule?.targetPrompt).trim() : '';
  if (action === 'replace' && !targetPrompt) return '';
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
  const targetKey = action === 'delete' ? '__delete__' : normalizePromptKey(targetPrompt);
  return `${[...uniqueGroups][0]}=>${targetKey}`;
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
  if (isHairAccessoryText(spaced)) return 'accessory';
  if (isHairStyleSource(spaced)) return 'hair';
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
    Boolean(directBlackClothingReplacementPrompt(text)) ||
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
    const mergedFrameIndexes = uniqueNumbers([
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

function shouldMapRole(role, roleId) {
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
  return hasFemaleRoleText(text);
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
  ].some((needle) => normalized.includes(needle));
}

function clothingReplacementPromptFor(value, target, placement) {
  const source = stringValue(value);
  if (!source.trim()) return '';
  const prompts = [];
  let useTargetClothing = false;
  let hasNonBlackSwimwear = false;
  for (const tag of splitPromptTags(source)) {
    if (isSwimwear(tag) && !isBlackPrompt(tag)) {
      hasNonBlackSwimwear = true;
    }
    const prompt = directBlackClothingReplacementPrompt(tag);
    if (prompt) {
      prompts.push(prompt);
      continue;
    }
    if (isDisallowedNonSwimwearClothing(tag)) {
      useTargetClothing = true;
    }
  }
  if (prompts.length > 0) return uniquePrompts(prompts).join(', ');
  if (placement !== 'rule' && placement !== 'direct-rule' && hasNonBlackSwimwear) return '';
  if (!useTargetClothing) return '';
  if (placement === 'direct-rule') return '';
  if (placement === 'upper') return target.upperClothing;
  if (placement === 'lower') return target.lowerClothing;
  return target.clothing;
}

function directBlackClothingReplacementPrompt(value) {
  const text = spacedText(value);
  if (!isBlackPrompt(value)) return '';
  if (isSwimwear(value)) {
    if (text.includes(' school swimsuit ')) return 'white school swimsuit';
    if (text.includes(' one piece swimsuit ') || text.includes(' one-piece swimsuit ')) {
      return 'white one-piece swimsuit';
    }
    if (text.includes(' highleg swimsuit ') || text.includes(' highleg one piece swimsuit ')) {
      return 'white highleg swimsuit';
    }
    if (text.includes(' bikini ')) return 'white bikini';
    return 'white swimsuit';
  }
  if (text.includes(' lace ') || text.includes(' laced ') || text.includes(' lacy ')) {
    if (text.includes(' panties ')) return 'white lace panties';
    if (text.includes(' panty ')) return 'white lace panties';
    if (text.includes(' bra ')) return 'white lace bra';
    if (text.includes(' lingerie ')) return 'white lace lingerie';
    if (text.includes(' underwear ')) return 'white lace underwear';
    if (text.includes(' dress ')) return 'white lace dress';
    if (text.includes(' trim ')) return 'white lace trim';
    return 'white lace';
  }
  if (isUnderwear(value)) {
    if (text.includes(' panties ') || text.includes(' panty ')) return 'pink panties';
    if (text.includes(' bra ')) return 'white bra';
    if (text.includes(' lingerie ')) return 'white lingerie';
    if (text.includes(' thong ')) return 'pink thong';
    if (text.includes(' garter belt ')) return 'white garter belt';
    if (text.includes(' underwear ')) return 'white underwear';
    return 'white underwear';
  }
  return '';
}

function isBlackPrompt(value) {
  return hasWord(spacedText(value), 'black');
}

function isDisallowedNonSwimwearClothing(value) {
  const text = normalizeKey(value);
  if (!text) return false;
  return [
    'bunnysuit',
    'bunnygirl',
    'bunnycostume',
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
    ' underwear ',
    ' panties ',
    ' panty ',
    ' bra ',
    ' lingerie ',
    ' thong ',
    ' garter belt ',
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
    apply: false,
  };
  for (let index = 0; index < values.length; index += 1) {
    const arg = values[index];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    if (key === 'apply') {
      parsed.apply = true;
      continue;
    }
    const value = values[index + 1];
    index += 1;
    if (key === 'source-root') parsed.sourceRoot = value;
    if (key === 'workspace') parsed.workspace = value;
    if (key === 'backup-dir') parsed.backupDir = value;
    if (key === 'report') parsed.report = value;
    if (key === 'import-report') parsed.importReport = value;
  }
  return parsed;
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

function joinPrompts(parts) {
  return parts.map(stringValue).map((part) => part.trim()).filter(Boolean).join(', ');
}

function timestampForPath() {
  return new Date().toISOString().replace(/[-:T.Z]/g, '').slice(0, 14);
}
