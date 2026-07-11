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
  unknown_role_replacement_count: 0,
  pseudo_partial_role_count: 0,
  appearance_collision_count: 0,
  target_stage_mismatch_count: 0,
  orphan_target_stage_count: 0,
  mapped_stage_missing_target_count: 0,
  regression_frame_missing_count: 0,
  regression_male_target_count: 0,
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
    } else if (role && !isTargetableFemaleRole(role)) {
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
    }
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
  'unknown_role_replacement_count',
  'pseudo_partial_role_count',
  'appearance_collision_count',
  'target_stage_mismatch_count',
  'orphan_target_stage_count',
  'mapped_stage_missing_target_count',
  'regression_frame_missing_count',
  'regression_male_target_count',
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

function isPseudoPartialRole(role, scriptSnapshot) {
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
  return /\b(?:1girl|2girls|3girls|girls?|female|woman|women|loli)\b/.test(text);
}

function hasMaleText(text) {
  return /\b(?:1boy|2boys|boys?|male|males|man|men|faceless male|fat man|old man|muscular male|musclar male)\b/.test(
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
  return /^(?:1girl|2girls|3girls|girls?|female|woman|women|1boy|2boys|boys?|male|males|man|men|loli|child)$/.test(
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
  };
  for (let index = 0; index < args.length; index += 1) {
    const key = args[index];
    const value = args[index + 1];
    if (!key.startsWith('--') || value == null || value.startsWith('--')) continue;
    index += 1;
    if (key === '--cache-dir') parsed.cacheDir = value;
    if (key === '--source-root') parsed.sourceRoot = value;
    if (key === '--report') parsed.report = value;
    if (key === '--regression-script-id') parsed.regressionScriptId = value;
    if (key === '--regression-frame-file') parsed.regressionFrameFile = value;
  }
  return parsed;
}
