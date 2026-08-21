#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const args = parseArgs(process.argv.slice(2));
const cacheDir = path.resolve(args.cacheDir);
const sourceRoot = normalizePath(args.sourceRoot);
const profilePath = path.resolve(args.profileFile);
const targetIds = new Set([
  'legacy-character-sheet-r14',
  'legacy-character-sheet-r13',
  'legacy-character-sheet-r29',
  'legacy-character-sheet-r15',
  'legacy-character-sheet-r26',
]);

const report = {
  tool: 'audit_script_recast_exact_mapping_offline_20260820',
  api_used: false,
  source_root: sourceRoot,
  cache_dir: cacheDir,
  profile_file: profilePath,
  files: 0,
  role_count: 0,
  target_role_count: 0,
  target_counts: {},
  unknown_targets: [],
  stale_target_count: 0,
  identity_clothing_leaks: [],
  special_clothing: { terms: 0, ok: 0, violations: [] },
  nonwhite_underwear_or_hosiery: { terms: 0, ok: 0, violations: [] },
  lower_decoration_tail: { terms: 0, ok: 0, violations: [] },
  negative_appearance: { terms: 0, ok: 0, violations: [] },
  ordinary_clothing_preserved: { terms: 0, ok: 0, violations: [] },
  pepe_head_anchor: { terms: 0, ok: 0, violations: [] },
  profiles: {},
  violation_count: 0,
};
const sourceCategories = new Map();

for (const fileName of fs.readdirSync(cacheDir).filter((file) => file.endsWith('.json')).sort()) {
  const filePath = path.join(cacheDir, fileName);
  const cache = loadJson(filePath);
  if (!cache || !isUnderRoot(cache.sourceRootPath)) continue;
  report.files += 1;
  const roles = Array.isArray(cache.aiRoleExtraction?.roles)
    ? cache.aiRoleExtraction.roles
    : [];
  const replacements = Array.isArray(cache.mapping?.rolePromptReplacements)
    ? cache.mapping.rolePromptReplacements
    : [];
  report.role_count += roles.length;
  const roleIdsWithTarget = new Set();
  for (const replacement of replacements) {
    const targetId = stringValue(replacement.targetCharacterId);
    if (targetId) {
      report.target_counts[targetId] = (report.target_counts[targetId] ?? 0) + 1;
      roleIdsWithTarget.add(stringValue(replacement.sourceRoleId));
    }
    if (targetId && !targetIds.has(targetId)) {
      pushSample(report.unknown_targets, {
        file: fileName,
        role: stringValue(replacement.sourceRoleId),
        target: targetId,
      });
    }
    if (targetId === 'legacy-character-sheet-r26') report.stale_target_count += 1;
    if (
      targetId &&
      /(?:black_jacket|black_shorts|black_coat|white_dress|thighhighs|boots|kimono|dress|jacket|coat|shorts|shoes)/i.test(
        stringValue(replacement.targetIdentityPrompt),
      )
    ) {
      pushSample(report.identity_clothing_leaks, {
        file: fileName,
        role: stringValue(replacement.sourceRoleId),
        prompt: stringValue(replacement.targetIdentityPrompt),
      });
    }
    if (targetId) report.target_role_count += 1;
    const mapped = targetIds.has(targetId);
    for (const rule of Array.isArray(replacement.rules) ? replacement.rules : []) {
      for (const term of Array.isArray(rule.sourceTerms) ? rule.sourceTerms : []) {
        const source = stringValue(term.text || term.sourcePhrase);
        const category = normalizeCategory(term.category);
        const categorySet = sourceCategories.get(normalizeText(source)) ?? new Set();
        categorySet.add(category);
        sourceCategories.set(normalizeText(source), categorySet);
        const action = stringValue(rule.action);
        const targetPrompt = stringValue(rule.targetPrompt);
        if (!mapped) continue;

        if (isSpecialClothing(term, source)) {
          report.special_clothing.terms += 1;
          if (action === 'replace' && targetPrompt && !isSpecialClothing(null, targetPrompt)) {
            report.special_clothing.ok += 1;
          } else {
            pushSample(report.special_clothing.violations, {
              file: fileName,
              role: stringValue(replacement.sourceRoleId),
              source,
              category,
              action,
              targetPrompt,
            });
          }
        }

        if (isNonwhiteUnderwearOrHosiery(source)) {
          report.nonwhite_underwear_or_hosiery.terms += 1;
          if (
            action === 'replace' &&
            targetPrompt &&
            hasWord(targetPrompt, 'white|pink') &&
            !hasDisallowedUnderwearColor(targetPrompt)
          ) {
            report.nonwhite_underwear_or_hosiery.ok += 1;
          } else {
            pushSample(report.nonwhite_underwear_or_hosiery.violations, {
              file: fileName,
              role: stringValue(replacement.sourceRoleId),
              source,
              category,
              action,
              targetPrompt,
            });
          }
        }

        if (isLowerDecoration(category, source)) {
          report.lower_decoration_tail.terms += 1;
          if (action === 'replace' && hasWord(targetPrompt, 'cat_tail|fox_tail|tail')) {
            report.lower_decoration_tail.ok += 1;
          } else {
            pushSample(report.lower_decoration_tail.violations, {
              file: fileName,
              role: stringValue(replacement.sourceRoleId),
              source,
              category,
              action,
              targetPrompt,
            });
          }
        }

        if (isNegativeAppearance(source)) {
          report.negative_appearance.terms += 1;
          if (action === 'delete' && !targetPrompt) {
            report.negative_appearance.ok += 1;
          } else {
            pushSample(report.negative_appearance.violations, {
              file: fileName,
              role: stringValue(replacement.sourceRoleId),
              source,
              category,
              action,
              targetPrompt,
            });
          }
        }

        if (isOrdinaryClothing(category, source)) {
          report.ordinary_clothing_preserved.terms += 1;
          if (action === 'replace' || action === 'delete') {
            pushSample(report.ordinary_clothing_preserved.violations, {
              file: fileName,
              role: stringValue(replacement.sourceRoleId),
              source,
              category,
              action,
              targetPrompt,
            });
          }
        }

        if (isPepeHeadTerm(source)) {
          report.pepe_head_anchor.terms += 1;
          if (
            action === 'replace' &&
            targetPrompt.includes('1.5:: cat_ears ::') &&
            targetPrompt.includes('-3:: hood ::') &&
            targetPrompt.includes('-3:: animal hood ::')
          ) {
            report.pepe_head_anchor.ok += 1;
          } else {
            pushSample(report.pepe_head_anchor.violations, {
              file: fileName,
              role: stringValue(replacement.sourceRoleId),
              source,
              category,
              action,
              targetPrompt,
            });
          }
        }
      }
    }
  }
  void roleIdsWithTarget;
}

const profileData = loadJson(profilePath);
if (profileData) {
  report.profile_schema = profileData.schemaVersion;
  for (const targetId of targetIds) {
    const profile = (profileData.profiles ?? []).find(
      (candidate) => candidate.targetCharacterId === targetId,
    );
    const blocks = Array.isArray(profile?.layers) && profile.layers.length > 0
      ? profile.layers.flatMap((layer) =>
          Array.isArray(layer?.blocks) ? layer.blocks : [],
        )
      : profile?.blocks ?? [];
    const profileReport = {
      name: stringValue(profile?.name),
      block_count: blocks.length,
      identity_prompt: stringValue(profile?.targetIdentityPrompt),
      negative_appearance: { terms: 0, ok: 0, violations: [] },
      special_clothing: { terms: 0, ok: 0, violations: [] },
      lower_decoration_tail: { terms: 0, ok: 0, violations: [] },
      ordinary_clothing_blocks: 0,
      ordinary_clothing_samples: [],
    };
    if (/(?:^|[ ,])(?:black_jacket|black_shorts|black_coat|white_dress|thighhighs|boots|kimono|dress|jacket|coat|shorts|shoes)(?:[ ,]|$)/i.test(profileReport.identity_prompt)) {
      pushSample(profileReport.negative_appearance.violations, {
        issue: 'identity_prompt_contains_clothing',
        prompt: profileReport.identity_prompt,
      });
    }
    for (const block of blocks) {
      const terms = Array.isArray(block.terms) ? block.terms : [];
      for (const term of terms) {
        const source = stringValue(term.text);
        if (isNegativeAppearance(source)) {
          profileReport.negative_appearance.terms += 1;
          if (block.action === 'delete' && !stringValue(block.targetPrompt)) profileReport.negative_appearance.ok += 1;
          else pushSample(profileReport.negative_appearance.violations, { source, action: block.action, targetPrompt: block.targetPrompt });
        }
        if (isSpecialClothing(term, source)) {
          profileReport.special_clothing.terms += 1;
          if (block.action === 'replace' && stringValue(block.targetPrompt) && !isSpecialClothing(null, block.targetPrompt)) profileReport.special_clothing.ok += 1;
          else pushSample(profileReport.special_clothing.violations, { source, action: block.action, targetPrompt: block.targetPrompt });
        }
        const categories = sourceCategories.get(normalizeText(source)) ?? new Set();
        if ([...categories].some((category) => isLowerDecoration(category, source))) {
          profileReport.lower_decoration_tail.terms += 1;
          if (block.action === 'replace' && hasWord(stringValue(block.targetPrompt), 'cat_tail|fox_tail|tail')) profileReport.lower_decoration_tail.ok += 1;
          else pushSample(profileReport.lower_decoration_tail.violations, { source, action: block.action, targetPrompt: block.targetPrompt });
        }
        if ([...categories].some((category) => isOrdinaryClothing(category, source))) {
          profileReport.ordinary_clothing_blocks += 1;
          pushSample(profileReport.ordinary_clothing_samples, {
            source,
            categories: [...categories],
            action: block.action,
            targetPrompt: block.targetPrompt,
          });
        }
      }
    }
    report.profiles[targetId] = profileReport;
  }
}

report.violation_count = countViolations(report);
console.log(JSON.stringify(report, null, 2));
if (args.report) {
  fs.mkdirSync(path.dirname(path.resolve(args.report)), { recursive: true });
  fs.writeFileSync(path.resolve(args.report), `${JSON.stringify(report, null, 2)}\n`, 'utf8');
}
if (report.violation_count > 0) process.exitCode = 1;

function countViolations(value) {
  if (!value || typeof value !== 'object') return 0;
  let count = 0;
  for (const [key, child] of Object.entries(value)) {
    if (key === 'violations' || key === 'unknown_targets' || key === 'identity_clothing_leaks') {
      if (Array.isArray(child)) count += child.length;
      continue;
    }
    if (key === 'stale_target_count' || key === 'ordinary_clothing_blocks') {
      if (typeof child === 'number') count += child;
      continue;
    }
    if (key === 'target_counts' || key === 'profiles') {
      count += countViolations(child);
      continue;
    }
    if (typeof child === 'object') count += countViolations(child);
  }
  return count;
}

function isUnderRoot(candidate) {
  const normalized = normalizePath(candidate);
  return normalized === sourceRoot || normalized.startsWith(`${sourceRoot}/`);
}

function normalizePath(value) {
  return String(value ?? '').replaceAll('\\', '/').replace(/\/+/g, '/').replace(/\/$/, '').toLowerCase();
}

function normalizeCategory(value) {
  return String(value ?? '').toLowerCase().replaceAll('_', '').replaceAll('-', '').replaceAll(' ', '');
}

function normalizeText(value) {
  return String(value ?? '').toLowerCase().replaceAll('_', ' ').replace(/\s+/g, ' ').trim();
}

function hasWord(value, pattern) {
  return new RegExp(`(?:^|[\\s,])(?:${pattern})(?=[\\s,]|$)`, 'i').test(` ${normalizeText(value)} `);
}

function hasAny(value, pattern) {
  return new RegExp(pattern, 'i').test(normalizeText(value));
}

function isClothingCategory(category) {
  return ['clothing', 'upperclothing', 'lowerclothing', 'clothingstate'].includes(category);
}

function isUnderwear(value) {
  return hasAny(value, '(?:pantyhose|thighhighs|thigh highs|stockings?|tights|socks?|leggings|babydoll|lingerie|garter belt|bras?|thongs?|panties?|underwear)');
}

function isNonwhiteUnderwearOrHosiery(value) {
  return isUnderwear(value) && hasDisallowedUnderwearColor(value);
}

function hasDisallowedUnderwearColor(value) {
  return hasAny(value, '\\b(?:aqua|beige|black|blue|brown|cyan|gold|gray|grey|green|lavender|magenta|maroon|navy|orange|purple|red|silver|violet|yellow)\\b');
}

function isSpecialClothing(term, value) {
  const source = normalizeText(value);
  if (hasWord(source, 'no|without|lack')) return false;
  const compact = source.replaceAll(' ', '');
  const token = ['bunnysuit', 'bunnygirl', 'bunnycostume', 'bunnysuitcostume', 'bunny', 'rabbitsuit', 'rabbitgirl', 'rabbitcostume', 'leotard', 'bodysuit', 'catsuit', 'plugsuit', 'pilotsuit', 'unitsuit', 'unitard', 'skinsuit', 'skintight', 'tightclothing', 'tightclothes', 'tightoutfit', 'tightdress', 'bodycon', 'latex', 'rubber', 'wetsuit', 'racingsuit', 'competitionwear'].some((needle) => compact.includes(needle));
  if (!token) return false;
  if (term && isClothingCategory(normalizeCategory(term.category))) return true;
  return hasAny(source, '(?:dress|clothes|clothing|leotard|bodysuit|catsuit|suit|latex|bodycon|tight)');
}

function isLowerDecoration(category, value) {
  if (!['lowerbody', 'lowerclothing', 'accessory'].includes(category)) return false;
  const source = normalizeText(value);
  if (hasWord(source, 'no|without|lack')) return false;
  if (hasWord(source, 'hair|head|face|ear|ears|headdress|headband|hairband')) return false;
  const explicitLowerMarker = hasWord(source, 'anklet|garter|garterbelt|tail|leg strap|leg ribbon|leg ornament|legwear|thigh strap|thighstrap');
  if (explicitLowerMarker) return true;
  return category === 'lowerbody' && hasWord(source, 'ornament|ribbon');
}

function isNegativeAppearance(value) {
  const source = normalizeText(value);
  if (isUnderwear(source) || !hasWord(source, 'no|without|lack')) return false;
  if (hasWord(source, 'eyewear|glasses|spectacles')) return false;
  if (hasAny(source, '(?:ponytail|twintail|braid|bang|bun|ahoge)')) return false;
  return hasAny(source, '(?:hair|ear|ears|horn|halo|tail|ornament|ribbon|headdress|headpiece|hood|hat|headband|hairband)');
}

function isOrdinaryClothing(category, value) {
  return isClothingCategory(category) && !isPepeHeadTerm(value) && !isNegativeAppearance(value) && !isSpecialClothing({ category }, value) && !isUnderwear(value) && !isLowerDecoration(category, value);
}

function isPepeHeadTerm(value) {
  const source = normalizeText(value);
  if (hasWord(source, 'no|without|lack')) return false;
  if (hasWord(source, 'clitoris|clitoral')) return false;
  return hasWord(source, 'hood|animal hood|wearing hood|hat|bonnet|headband|hairband|headdress|bunny ears|rabbit ears');
}

function pushSample(array, value) {
  if (array.length < 25) array.push(value);
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function loadJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
}

function parseArgs(argv) {
  const parsed = { cacheDir: '', sourceRoot: '', profileFile: '', report: '' };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith('--')) continue;
    const equalIndex = arg.indexOf('=');
    const key = (equalIndex >= 0 ? arg.slice(2, equalIndex) : arg.slice(2));
    const value = equalIndex >= 0 ? arg.slice(equalIndex + 1) : argv[++index];
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'source-root') parsed.sourceRoot = value;
    if (key === 'profile-file') parsed.profileFile = value;
    if (key === 'report') parsed.report = value;
  }
  if (!parsed.cacheDir || !parsed.sourceRoot || !parsed.profileFile) {
    throw new Error('Usage: node tool/audit_script_recast_exact_mapping_offline_20260820.mjs --cache-dir <dir> --source-root <dir> --profile-file <file> [--report <file>]');
  }
  return parsed;
}
