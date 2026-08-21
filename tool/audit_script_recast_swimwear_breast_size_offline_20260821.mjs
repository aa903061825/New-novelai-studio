#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const TARGETS = [
  { id: 'legacy-character-sheet-r14', name: '佩佩（无兜帽）', swimwear: 'school_swimsuit', breastSize: 'small_breasts' },
  { id: 'legacy-character-sheet-r13', name: '铃兰', swimwear: 'school_swimsuit', breastSize: 'small_breasts' },
  { id: 'legacy-character-sheet-r29', name: '巫恋', swimwear: 'school_swimsuit', breastSize: 'small_breasts' },
  { id: 'legacy-character-sheet-r15', name: '迷迭香', swimwear: 'school_swimsuit', breastSize: 'small_breasts' },
  { id: 'legacy-character-sheet-r26', name: '薄绿', swimwear: 'school_swimsuit', breastSize: 'small_breasts' },
  { id: 'roccia-wuthering-waves', name: '洛可可', swimwear: 'frilled_bikini', breastSize: 'medium_breasts' },
  { id: 'rossi-arknights-endfield', name: '洛茜', swimwear: 'bikini', breastSize: 'medium_breasts' },
];

const args = parseArgs(process.argv.slice(2));
const cacheDir = path.resolve(args.cacheDir);
const backupDir = path.resolve(args.backupDir);
const sourceRoot = normalizePath(args.sourceRoot);
const profileFile = path.resolve(args.profileFile);
const reportFile = path.resolve(args.report);
const errors = [];
const report = {
  tool: 'audit_script_recast_swimwear_breast_size_offline_20260821',
  api_used: false,
  source_root: sourceRoot,
  cache_dir: cacheDir,
  backup_dir: backupDir,
  profile_file: profileFile,
  files_scanned: 0,
  files_matched: 0,
  variant_count: 0,
  variant_name_counts: Object.fromEntries(TARGETS.map((target) => [target.name, 0])),
  source_rule_checks: 0,
  source_rule_mapped: 0,
  active_mapping_variant_id_unchanged: 0,
  fingerprint_checks: 0,
  fingerprint_mismatches: [],
  profile_checks: {},
  forbidden_terms_in_new_blocks: [],
  errors,
};

const profileLibrary = loadJson(profileFile);
const profileRows = new Map();
for (const target of TARGETS) {
  const matches = (profileLibrary?.profiles || []).filter(
    (profile) => profile?.targetCharacterId === target.id,
  );
  const profile = matches.length === 1 ? matches[0] : null;
  profileRows.set(target.id, profile);
  report.profile_checks[target.id] = {
    name: target.name,
    profile_count: matches.length,
    swimwear_block_ok: false,
    breast_size_block_ok: false,
    desired_term_occurrences_ok: false,
    identity_anchors_ok: target.id !== 'rossi-arknights-endfield',
  };
  if (!profile) {
    addError(`Expected exactly one global profile for ${target.id}; found ${matches.length}.`);
    continue;
  }
  const blocks = profileBlocks(profile);
  const swimBlock = blocks.filter((block) => block.id === `block-${target.id}-swimwear-replacement`);
  const breastBlock = blocks.filter((block) => block.id === `block-${target.id}-breast-size-replacement`);
  report.profile_checks[target.id].swimwear_block_ok = checkBlock(swimBlock, target.swimwear, 'swimwear', target);
  report.profile_checks[target.id].breast_size_block_ok = checkBlock(breastBlock, target.breastSize, 'breast-size', target);
  const desired = [
    ...((swimBlock[0]?.terms || []).map((term) => ({ term, kind: 'swimwear', block: swimBlock[0] }))),
    ...((breastBlock[0]?.terms || []).map((term) => ({ term, kind: 'breast-size', block: breastBlock[0] }))),
  ];
  const occurrences = new Map();
  for (const block of blocks) {
    for (const term of block.terms || []) {
      const key = normalize(term.text);
      const list = occurrences.get(key) || [];
      list.push({ blockId: block.id, action: block.action, targetPrompt: block.targetPrompt });
      occurrences.set(key, list);
    }
  }
  let termsOk = true;
  for (const entry of desired) {
    const key = normalize(entry.term.text);
    const list = occurrences.get(key) || [];
    if (list.length !== 1 || list[0].blockId !== entry.block.id) {
      termsOk = false;
      addError(`${target.id} ${entry.kind} term ${entry.term.text} occurs ${list.length} time(s) outside its canonical block.`);
    }
    if (entry.kind === 'swimwear' && !isSwimwearSuit(entry.term.text, entry.term.category)) {
      report.forbidden_terms_in_new_blocks.push({ target: target.id, kind: entry.kind, term: entry.term.text });
      termsOk = false;
    }
    if (entry.kind === 'breast-size' && !isBreastSizeTerm(entry.term.text)) {
      report.forbidden_terms_in_new_blocks.push({ target: target.id, kind: entry.kind, term: entry.term.text });
      termsOk = false;
    }
  }
  report.profile_checks[target.id].desired_term_occurrences_ok = termsOk;
  if (target.id === 'rossi-arknights-endfield') {
    report.profile_checks[target.id].identity_anchors_ok = String(profile.targetIdentityPrompt || '').includes('wolf_ears');
    if (!report.profile_checks[target.id].identity_anchors_ok) addError('Rossi global identity prompt lost wolf_ears.');
  }
}

for (const fileName of fs.readdirSync(cacheDir).filter((name) => name.endsWith('.json')).sort()) {
  report.files_scanned += 1;
  const filePath = path.join(cacheDir, fileName);
  const cache = loadJson(filePath);
  if (!cache || !isUnderSourceRoot(cache.sourceRootPath)) continue;
  report.files_matched += 1;
  const backupPath = path.join(backupDir, fileName);
  const backup = loadJson(backupPath);
  if (!backup) {
    addError(`Missing pre-refresh backup for ${fileName}.`);
    continue;
  }
  if (activeState(cache) === activeState(backup)) report.active_mapping_variant_id_unchanged += 1;
  else addError(`Active mapping variant changed in ${fileName}.`);
  if (cache.sourceFingerprint !== backup.sourceFingerprint || cache.sourceContentFingerprint !== backup.sourceContentFingerprint) {
    report.fingerprint_mismatches.push({ file: fileName, kind: 'cache-source-fingerprint' });
    addError(`Source fingerprint changed in ${fileName}.`);
  }
  const variants = Array.isArray(cache.mappingVariants) ? cache.mappingVariants : [];
  report.variant_count += variants.length;
  const names = variants.map((variant) => String(variant?.name || ''));
  if (variants.length !== TARGETS.length || new Set(names).size !== TARGETS.length || TARGETS.some((target) => !names.includes(target.name))) {
    addError(`Variant set is not exactly the seven target profiles in ${fileName}.`);
  }
  for (const target of TARGETS) {
    const variant = variants.find((candidate) => candidate?.name === target.name);
    if (!variant) {
      addError(`${fileName} is missing variant ${target.name}.`);
      continue;
    }
    report.variant_name_counts[target.name] += 1;
    if (variant.sourceFingerprint !== cache.sourceFingerprint || variant.sourceContentFingerprint !== cache.sourceContentFingerprint) {
      report.fingerprint_mismatches.push({ file: fileName, variant: target.name, kind: 'variant-source-fingerprint' });
      addError(`${fileName}/${target.name} has a stale source fingerprint.`);
    }
    auditVariant(cache, variant, target);
  }
}

report.fingerprint_checks = report.files_matched + report.variant_count;
report.ok = errors.length === 0 &&
  report.files_matched === 104 &&
  report.variant_count === 728 &&
  report.active_mapping_variant_id_unchanged === 104 &&
  report.fingerprint_mismatches.length === 0 &&
  Object.values(report.profile_checks).every((check) =>
    check.profile_count === 1 && check.swimwear_block_ok && check.breast_size_block_ok &&
    check.desired_term_occurrences_ok && check.identity_anchors_ok,
  );
fs.mkdirSync(path.dirname(reportFile), { recursive: true });
fs.writeFileSync(reportFile, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
console.log(JSON.stringify({
  tool: report.tool,
  ok: report.ok,
  files_matched: report.files_matched,
  variant_count: report.variant_count,
  active_mapping_variant_id_unchanged: report.active_mapping_variant_id_unchanged,
  fingerprint_mismatches: report.fingerprint_mismatches.length,
  source_rule_checks: report.source_rule_checks,
  source_rule_mapped: report.source_rule_mapped,
  profile_checks: report.profile_checks,
  forbidden_terms_in_new_blocks: report.forbidden_terms_in_new_blocks.length,
  error_count: errors.length,
  error_samples: errors.slice(0, 20),
}, null, 2));
if (!report.ok) process.exitCode = 1;

function auditVariant(cache, variant, target) {
  const replacements = Array.isArray(variant.mapping?.rolePromptReplacements)
    ? variant.mapping.rolePromptReplacements
    : [];
  const replacementByRole = new Map(replacements.map((replacement) => [String(replacement?.sourceRoleId || ''), replacement]));
  for (const [roleId, terms] of sourceTermsByRole(cache).entries()) {
    const replacement = replacementByRole.get(roleId);
    for (const entry of terms.values()) {
      report.source_rule_checks += 1;
      const matchingRules = (replacement?.rules || []).filter((rule) =>
        (rule.sourceTerms || []).some((term) => normalize(term.text) === entry.key),
      );
      const expected = entry.kind === 'swimwear' ? target.swimwear : target.breastSize;
      const correct = matchingRules.filter((rule) => rule.action === 'replace' && rule.targetPrompt === expected);
      const incorrectEffective = matchingRules.filter((rule) =>
        rule.action === 'delete' || (rule.action === 'replace' && rule.targetPrompt !== expected),
      );
      if (correct.length > 0 && incorrectEffective.length === 0) {
        report.source_rule_mapped += 1;
      } else {
        addError(`${cache.scriptId}/${target.name}/${roleId}/${entry.text} is not mapped to ${expected}.`);
      }
    }
  }
}

function sourceTermsByRole(cache) {
  const byRole = new Map();
  const replacements = new Map((cache.mapping?.rolePromptReplacements || []).map((replacement) => [String(replacement?.sourceRoleId || ''), replacement]));
  for (const role of cache.aiRoleExtraction?.roles || []) {
    if (!isTargetableRole(role)) continue;
    const roleId = String(role.source_role_id || '');
    const candidates = [
      ...(Array.isArray(role.prompt_terms) ? role.prompt_terms : []),
      ...((replacements.get(roleId)?.rules || []).flatMap((rule) => rule.sourceTerms || [])),
    ];
    const terms = byRole.get(roleId) || new Map();
    for (const candidate of candidates) {
      const text = String(candidate?.text || candidate?.sourcePhrase || candidate?.source_phrase || '').trim();
      const category = normalize(candidate?.category);
      if (!text) continue;
      let kind = '';
      if (isSwimwearSuit(text, category)) kind = 'swimwear';
      else if (isBreastSizeTerm(text)) kind = 'breast-size';
      if (!kind) continue;
      const key = normalize(text);
      terms.set(`${kind}\u0000${key}`, { key, text, category, kind });
    }
    if (terms.size > 0) byRole.set(roleId, terms);
  }
  return byRole;
}

function checkBlock(matches, prompt, kind, target) {
  if (matches.length !== 1) {
    addError(`${target.id} ${kind} block count is ${matches.length}.`);
    return false;
  }
  const block = matches[0];
  const ok = block.action === 'replace' && (block.matchMode || 'any') === 'any' && block.targetPrompt === prompt && (block.terms || []).length > 0;
  if (!ok) addError(`${target.id} ${kind} block has an invalid action, match mode, target, or term list.`);
  return ok;
}

function profileBlocks(profile) {
  if (Array.isArray(profile?.layers) && profile.layers.length > 0) return profile.layers.flatMap((layer) => layer.blocks || []);
  return profile?.blocks || [];
}

function isTargetableRole(role) {
  const sourceKind = normalize(role?.source_kind || role?.sourceKind);
  if (sourceKind === 'global' || sourceKind === 'shared') return false;
  const rawIdentityTags = Array.isArray(role?.raw_identity_tags)
    ? role.raw_identity_tags.map(String).map((value) => value.trim().toLowerCase()).filter(Boolean)
    : [];
  if (rawIdentityTags.length > 0 && rawIdentityTags.every((tag) => /^(?:(?:black|white|brown|grey|gray|red|blue|wild|large|small) )?(?:animal|bear|cat|cow|dog|horse|pig|rabbit|wolf)$/.test(tag))) return false;
  const text = [role?.source_role_id, role?.display_name, role?.canonical_name, ...(Array.isArray(role?.raw_identity_tags) ? role.raw_identity_tags : [])]
    .map(String).join(' ').toLowerCase().replaceAll('_', ' ');
  const knownFemaleCharacter = /\bpecorine\b/.test(text);
  if (!text.trim() || (/\b(?:boy|male|man|old man|fat man|muscular male|dark skinned male|father|dad|uncle|sensei|teacher|shota|doctor arknights|producer|shido|shidou|yuuki|monster|tentacle|orc)\b/.test(text) && !knownFemaleCharacter)) return false;
  if (knownFemaleCharacter || /\b(?:girl|girls|female|woman|women|heroine|1girl|2girls|3girls)\b/.test(text)) return true;
  return [...rawIdentityTags, role?.canonical_name].map(String).some((value) => value.trim() && !/^(?:girl|female|woman|male|man|boy)$/i.test(value.trim()));
}

function isSwimwearSuit(value, category) {
  if (['identity', 'character', 'clothingstate', 'clothing_state'].includes(category)) return false;
  const source = spaced(value);
  if (!/(?:^| )swim(?:suit|wear)(?: |$)/.test(source) && !source.includes(' swim suit ')) return false;
  return !hasAnyWord(source, ['aside', 'only', 'pull', 'pulled', 'lift', 'unworn', 'under clothes', 'top only', 'bottom only', 'side']);
}

function isBreastSizeTerm(value) {
  const normalized = normalize(value).replace(/[.,!?]+$/g, '');
  return /^(?:small|medium|large|huge|gigantic|big)_breasts?$/.test(normalized) || /^(?:flat|flet)_chest$/.test(normalized) || /^alternate_breast_size_(?:larger|smaller)$/.test(normalized);
}

function activeState(cache) {
  return stableStringify({
    top: cache?.activeMappingVariantId,
    mapping: cache?.mapping?.activeMappingVariantId,
    variants: cache?.mappingVariants?.activeMappingVariantId,
  });
}

function addError(message) {
  if (errors.length < 200) errors.push(message);
}

function spaced(value) {
  return ` ${String(value || '').replaceAll('_', ' ').replace(/\s+/g, ' ').trim().toLowerCase()} `;
}

function hasAnyWord(value, words) {
  return words.some((word) => value.includes(` ${word} `));
}

function normalize(value) {
  return String(value ?? '').trim().toLowerCase().replace(/[\s_]+/g, '_');
}

function normalizePath(value) {
  return String(value ?? '').replaceAll('\\', '/').replace(/\/+$/, '').toLowerCase();
}

function isUnderSourceRoot(value) {
  const current = normalizePath(value);
  return current === sourceRoot || current.startsWith(`${sourceRoot}/`);
}

function stableStringify(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`;
  return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`).join(',')}}`;
}

function loadJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
}

function parseArgs(argv) {
  const parsed = { cacheDir: '', sourceRoot: '', profileFile: '', backupDir: '', report: '' };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
    parsed[key] = argv[++index];
  }
  if (!parsed.cacheDir || !parsed.sourceRoot || !parsed.profileFile || !parsed.backupDir || !parsed.report) throw new Error('Pass --cache-dir, --source-root, --profile-file, --backup-dir, and --report.');
  return parsed;
}
