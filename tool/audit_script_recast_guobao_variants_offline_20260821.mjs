import fs from 'node:fs';
import path from 'node:path';

const args = parseArgs(process.argv.slice(2));
const cacheDir = path.resolve(args.cacheDir);
const sourceRoot = normalizePath(path.resolve(args.sourceRoot));
const profilePath = path.resolve(args.profileFile);
const backupDir = path.resolve(args.backupDir);
const generatorReportPath = path.resolve(args.generatorReport);
const reportPath = path.resolve(args.report);

const expectedTargets = [
  ['legacy-character-sheet-r14', '佩佩（无兜帽）'],
  ['legacy-character-sheet-r13', '铃兰'],
  ['legacy-character-sheet-r29', '巫恋'],
  ['legacy-character-sheet-r15', '迷迭香'],
  ['legacy-character-sheet-r26', '薄绿'],
  ['roccia-wuthering-waves', '洛可可'],
  ['rossi-arknights-endfield', '洛茜'],
  ['legacy-character-sheet-r24', '果宝'],
];

const errors = [];
const warnings = [];
const profileLibrary = loadJson(profilePath);
const profiles = Array.isArray(profileLibrary?.profiles) ? profileLibrary.profiles : [];
const profileByTargetId = new Map();
const profileChecks = [];

for (const [targetId, expectedName] of expectedTargets) {
  const matches = profiles.filter((profile) => profile?.targetCharacterId === targetId);
  if (matches.length !== 1) {
    errors.push(`expected one profile for ${targetId}, found ${matches.length}`);
    continue;
  }
  const profile = matches[0];
  profileByTargetId.set(targetId, profile);
  const identityTokens = splitPromptTags(profile.targetIdentityPrompt);
  const forbiddenIdentityTokens = identityTokens.filter((term) =>
    isCompositionTag(cleanTag(term)) ||
    hasClothingLikeText(term) ||
    isBodyState(spacedText(term)),
  );
  const blockIds = new Set();
  const termIds = new Set();
  let duplicateBlockIds = 0;
  let duplicateTermIds = 0;
  let effectiveRules = 0;
  const blockByTerm = new Map();
  for (const layer of Array.isArray(profile.layers) ? profile.layers : []) {
    for (const block of Array.isArray(layer.blocks) ? layer.blocks : []) {
      if (blockIds.has(block.id)) duplicateBlockIds += 1;
      blockIds.add(block.id);
      if (block.action === 'delete' || String(block.targetPrompt || '').trim()) effectiveRules += 1;
      for (const term of Array.isArray(block.terms) ? block.terms : []) {
        if (termIds.has(term.id)) duplicateTermIds += 1;
        termIds.add(term.id);
        const key = normalize(term.text);
        if (!blockByTerm.has(key)) blockByTerm.set(key, []);
        blockByTerm.get(key).push(block);
      }
    }
  }
  if (profile.name !== expectedName || profile.targetCharacterNameSnapshot !== expectedName) {
    errors.push(`${targetId} does not use expected display name ${expectedName}`);
  }
  if (!String(profile.targetIdentityPrompt || '').trim()) {
    errors.push(`${targetId} has an empty target identity prompt`);
  }
  if (targetId === 'legacy-character-sheet-r24' && forbiddenIdentityTokens.length > 0) {
    errors.push(`${targetId} identity contains forbidden terms: ${forbiddenIdentityTokens.join(', ')}`);
  }
  if (blockIds.size === 0 || effectiveRules === 0) {
    errors.push(`${targetId} has no effective mapping blocks`);
  }
  if (duplicateBlockIds > 0 || duplicateTermIds > 0) {
    const message = `${targetId} has duplicate block/term ids (${duplicateBlockIds}/${duplicateTermIds})`;
    if (targetId === 'legacy-character-sheet-r24') errors.push(message);
    else warnings.push(message);
  }
  if (targetId === 'legacy-character-sheet-r24') {
    checkFruitRule(blockByTerm, 'one-piece_swimsuit', 'replace', 'bikini');
    checkFruitRule(blockByTerm, 'school_swimsuit', 'replace', 'bikini');
    checkFruitRule(blockByTerm, 'big_breasts', 'delete');
    checkFruitRule(blockByTerm, 'huge_breasts', 'delete');
    checkFruitRule(blockByTerm, 'girl', 'replace', 'girl');
  }
  profileChecks.push({
    targetCharacterId: targetId,
    name: profile.name,
    profileId: profile.id,
    identityPrompt: profile.targetIdentityPrompt,
    blockCount: blockIds.size,
    effectiveRuleCount: effectiveRules,
    uniqueTermCount: termIds.size,
    forbiddenIdentityTokens,
    duplicateBlockIds,
    duplicateTermIds,
  });
}

function checkFruitRule(blockByTerm, sourceTerm, action, targetPrompt = null) {
  const blocks = blockByTerm.get(sourceTerm) || [];
  const valid = blocks.some((block) =>
    block.action === action &&
    (targetPrompt == null || String(block.targetPrompt || '').trim() === targetPrompt),
  );
  if (!valid) {
    errors.push(`果宝 profile missing ${sourceTerm} => ${action}${targetPrompt ? ` ${targetPrompt}` : ''}`);
  }
}

const generatorReport = loadJson(generatorReportPath);
if (generatorReport?.source_write_attempts !== 0) {
  errors.push('generator reported source-root write attempts');
}

const cacheRows = [];
const files = fs.readdirSync(cacheDir).filter((file) => file.endsWith('.json')).sort();
for (const file of files) {
  const filePath = path.join(cacheDir, file);
  const cache = loadJson(filePath);
  if (!cache || !isUnderSourceRoot(cache.sourceRootPath)) continue;
  const backupPath = path.join(backupDir, file);
  const before = loadJson(backupPath);
  const variants = Array.isArray(cache.mappingVariants) ? cache.mappingVariants : [];
  const names = variants.map((variant) => String(variant.name || '').trim());
  const nameCounts = counts(names);
  const missingNames = expectedTargets.map(([, name]) => name).filter((name) => nameCounts[name] !== 1);
  const extraNames = names.filter((name) => !expectedTargets.some(([, expected]) => expected === name));
  const activePreserved = before?.activeMappingVariantId === cache.activeMappingVariantId;
  if (!before) errors.push(`${file} has no matching generator backup`);
  if (variants.length !== expectedTargets.length) errors.push(`${file} has ${variants.length} variants, expected ${expectedTargets.length}`);
  if (missingNames.length > 0) errors.push(`${file} missing or duplicated names: ${missingNames.join(', ')}`);
  if (extraNames.length > 0) errors.push(`${file} has unexpected variant names: ${extraNames.join(', ')}`);
  if (!activePreserved) errors.push(`${file} changed activeMappingVariantId`);
  const fingerprintIssues = [];
  const fruitIssues = [];
  let sourceTermIdCollisionCount = 0;
  let fruitVariant = null;
  for (const variant of variants) {
    if (variant.sourceFingerprint !== cache.sourceFingerprint ||
        variant.sourceContentFingerprint !== cache.sourceContentFingerprint) {
      fingerprintIssues.push(variant.id || variant.name);
    }
    for (const replacement of variant.mapping?.rolePromptReplacements || []) {
      const sourceTermIds = new Set();
      for (const rule of replacement.rules || []) {
        for (const sourceTerm of rule.sourceTerms || []) {
          if (sourceTermIds.has(sourceTerm.id)) sourceTermIdCollisionCount += 1;
          sourceTermIds.add(sourceTerm.id);
        }
      }
    }
    if (variant.name !== '果宝') continue;
    fruitVariant = variant;
    const targetNames = Object.values(variant.targetCharacterNamesByRoleId || {});
    if (targetNames.length !== (variant.mapping?.rolePromptReplacements || []).length) {
      fruitIssues.push('targetCharacterNamesByRoleId count mismatch');
    }
    if (targetNames.some((name) => name !== '果宝')) fruitIssues.push('non-Chinese target role display name');
    for (const replacement of variant.mapping?.rolePromptReplacements || []) {
      if (replacement.targetCharacterId !== 'legacy-character-sheet-r24') fruitIssues.push(`wrong target id ${replacement.targetCharacterId}`);
      if (replacement.targetIdentityPrompt !== profileByTargetId.get('legacy-character-sheet-r24')?.targetIdentityPrompt) {
        fruitIssues.push(`identity prompt mismatch for ${replacement.sourceRoleId}`);
      }
      if (replacement.activeMappingProfileId !== profileByTargetId.get('legacy-character-sheet-r24')?.id) {
        fruitIssues.push(`profile id mismatch for ${replacement.sourceRoleId}`);
      }
    }
  }
  if (!fruitVariant) fruitIssues.push('果宝 variant missing');
  if (sourceTermIdCollisionCount > 0) errors.push(`${file} has ${sourceTermIdCollisionCount} duplicate source term ids across variants`);
  if (fingerprintIssues.length > 0) errors.push(`${file} fingerprint mismatches: ${fingerprintIssues.join(', ')}`);
  if (fruitIssues.length > 0) errors.push(`${file} 果宝 variant: ${fruitIssues.join('; ')}`);
  cacheRows.push({
    file,
    scriptId: cache.scriptId,
    scriptName: cache.scriptName,
    frameCount: Array.isArray(cache.scriptSnapshot?.frames) ? cache.scriptSnapshot.frames.length : null,
    roleCount: Array.isArray(cache.aiRoleExtraction?.roles) ? cache.aiRoleExtraction.roles.length : null,
    variantCount: variants.length,
    variantNames: names,
    activeMappingVariantId: cache.activeMappingVariantId,
    activeMappingVariantIdPreserved: activePreserved,
    fingerprintMismatchCount: fingerprintIssues.length,
    sourceTermIdCollisionCount,
    fruitRoleCount: fruitVariant?.mapping?.rolePromptReplacements?.length || 0,
    fruitIssueCount: fruitIssues.length,
  });
}

if (cacheRows.length !== 104) errors.push(`expected 104 source-root caches, found ${cacheRows.length}`);

const report = {
  tool: 'audit_script_recast_guobao_variants_offline_20260821',
  api_used: false,
  source_root: sourceRoot,
  cache_dir: cacheDir,
  profile_file: profilePath,
  backup_dir: backupDir,
  generator_report: generatorReportPath,
  expected_variant_count: expectedTargets.length,
  files_matched: cacheRows.length,
  variant_count: cacheRows.reduce((sum, row) => sum + row.variantCount, 0),
  fruit_variant_count: cacheRows.filter((row) => row.fruitIssueCount === 0).length,
  active_mapping_variant_id_unchanged: cacheRows.filter((row) => row.activeMappingVariantIdPreserved).length,
  fingerprint_mismatch_count: cacheRows.reduce((sum, row) => sum + row.fingerprintMismatchCount, 0),
  profile_checks: profileChecks,
  cache_rows: cacheRows,
  errors,
  warnings,
  ok: errors.length === 0,
};

fs.mkdirSync(path.dirname(reportPath), { recursive: true });
fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
console.log(JSON.stringify({
  ok: report.ok,
  files_matched: report.files_matched,
  variant_count: report.variant_count,
  fruit_variant_count: report.fruit_variant_count,
  active_mapping_variant_id_unchanged: report.active_mapping_variant_id_unchanged,
  fingerprint_mismatch_count: report.fingerprint_mismatch_count,
  profile_count_checked: report.profile_checks.length,
  errors: report.errors,
}, null, 2));
if (!report.ok) process.exitCode = 1;

function parseArgs(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 1) {
    const arg = values[index];
    if (!arg.startsWith('--')) continue;
    parsed[arg.slice(2)] = values[++index];
  }
  for (const key of ['cache-dir', 'source-root', 'profile-file', 'backup-dir', 'generator-report', 'report']) {
    if (!parsed[key]) throw new Error(`Pass --${key}.`);
  }
  return {
    cacheDir: parsed['cache-dir'],
    sourceRoot: parsed['source-root'],
    profileFile: parsed['profile-file'],
    backupDir: parsed['backup-dir'],
    generatorReport: parsed['generator-report'],
    report: parsed.report,
  };
}

function loadJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
}

function counts(values) {
  const result = {};
  for (const value of values) result[value] = (result[value] || 0) + 1;
  return result;
}

function splitPromptTags(value) {
  return String(value || '').split(',').map((part) => part.trim()).filter(Boolean);
}

function cleanTag(value) {
  return String(value || '')
    .replace(/^[-+]?\d+(?:\.\d+)?::\s*/, '')
    .replace(/\s*::$/, '')
    .replace(/[\s-]+/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_|_$/g, '')
    .trim()
    .toLowerCase();
}

function normalize(value) {
  return String(value || '').trim().toLowerCase().replace(/[\s_]+/g, '_').replace(/[.,!?]+$/g, '');
}

function spacedText(value) {
  return ` ${String(value || '').replaceAll('_', ' ').replace(/\s+/g, ' ').trim().toLowerCase()} `;
}

function hasWord(spaced, word) {
  return spaced.includes(` ${word} `);
}

function hasAnyWord(spaced, words) {
  return words.some((word) => hasWord(spaced, word));
}

function hasClothingLikeText(value) {
  const text = spacedText(value);
  return hasAnyWord(text, ['dress', 'shirt', 'skirt', 'coat', 'jacket', 'shorts', 'pants', 'socks', 'sock', 'shoes', 'boots', 'sandals', 'kimono', 'swimsuit', 'bikini', 'underwear', 'panties', 'pantyhose', 'thighhighs', 'thigh highs', 'stockings', 'tights', 'leggings', 'gloves', 'bra', 'lingerie', 'bodysuit', 'leotard', 'bunnysuit', 'rabbitcostume', 'maid', 'nun', 'uniform', 'clothes', 'outfit', 'costume', 'sleeve', 'sleeves', 'sash', 'strap', 'straps', 'tassel', 'button', 'buttons', 'frill', 'frills', 'pleat', 'pleats']);
}

function isBodyState(value) {
  return hasAnyWord(spacedText(value), ['ass', 'breast', 'breasts', 'cleavage', 'collarbone', 'pregnant', 'pussy', 'pubic', 'nipple', 'nipples', 'navel', 'belly', 'stomach', 'legs', 'leg', 'thighs', 'thigh', 'clitoris', 'clitoral', 'vulva', 'labia', 'anus', 'penis', 'testicles', 'genitals', 'cervix', 'areola']);
}

function isCompositionTag(value) {
  return /^\d+(?:girls?|boys?)$/.test(value) || ['solo', 'multiple_girls', 'multiple_boys'].includes(value);
}

function normalizePath(value) {
  return String(value || '').replaceAll('\\', '/').replace(/\/+$/, '').toLowerCase();
}

function isUnderSourceRoot(value) {
  const current = normalizePath(value);
  return current === sourceRoot || current.startsWith(`${sourceRoot}/`);
}
