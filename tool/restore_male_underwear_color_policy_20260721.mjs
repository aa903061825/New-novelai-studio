#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const options = parseArgs(process.argv.slice(2));
if (!options.cacheDir || !options.baselineDir) {
  throw new Error(
    'Pass --cache-dir <dir> --baseline-dir <dir> [--cache-file <file>] [--apply].',
  );
}

const cacheDir = path.resolve(options.cacheDir);
const baselineDir = path.resolve(options.baselineDir);
const backupDir = options.backupDir
  ? path.resolve(options.backupDir)
  : path.resolve('build', `male_underwear_restore_backup_${timestampForPath()}`);
const allowedFiles = new Set(options.cacheFiles);
const files = fs
  .readdirSync(cacheDir)
  .filter(
    (file) =>
      file.endsWith('.json') &&
      (allowedFiles.size === 0 || allowedFiles.has(file)) &&
      fs.existsSync(path.join(baselineDir, file)),
  )
  .sort();

const report = {
  tool: 'restore_male_underwear_color_policy_20260721',
  api_used: false,
  apply: options.apply,
  cache_dir: cacheDir,
  baseline_dir: baselineDir,
  backup_dir: options.apply ? backupDir : '',
  files_scanned: files.length,
  files_changed: 0,
  male_rules_restored: 0,
  unmatched_rule_count: 0,
  rows: [],
  unmatched_rules: [],
};

for (const file of files) {
  const cachePath = path.join(cacheDir, file);
  const baselinePath = path.join(baselineDir, file);
  const cache = loadJson(cachePath);
  const baseline = loadJson(baselinePath);
  if (!cache || !baseline) continue;

  const before = JSON.stringify(cache);
  const roleById = new Map([
    ...arrayValue(baseline.aiRoleExtraction?.roles),
    ...arrayValue(cache.aiRoleExtraction?.roles),
  ].map((role) => [stringValue(role?.source_role_id), role]));
  const baselineReplacementByRole = new Map(
    arrayValue(baseline.mapping?.rolePromptReplacements).map((replacement) => [
      stringValue(replacement?.sourceRoleId),
      replacement,
    ]),
  );
  const restoredRules = [];

  for (const replacement of arrayValue(cache.mapping?.rolePromptReplacements)) {
    const roleId = stringValue(replacement?.sourceRoleId);
    if (!roleIsMale(roleById.get(roleId))) continue;
    const baselineReplacement = baselineReplacementByRole.get(roleId);
    const baselineRuleById = new Map(
      arrayValue(baselineReplacement?.rules).map((rule) => [
        stringValue(rule?.id),
        rule,
      ]),
    );
    for (const rule of arrayValue(replacement?.rules)) {
      if (!ruleHasUnderwearOrSwimwearTerm(rule)) continue;
      const ruleId = stringValue(rule?.id);
      const baselineRule = baselineRuleById.get(ruleId);
      if (!baselineRule) {
        report.unmatched_rule_count += 1;
        report.unmatched_rules.push({ file_name: file, source_role_id: roleId, rule_id: ruleId });
        continue;
      }
      const effectBefore = ruleEffect(rule);
      restoreRuleEffect(rule, baselineRule);
      const effectAfter = ruleEffect(rule);
      if (JSON.stringify(effectBefore) === JSON.stringify(effectAfter)) continue;
      report.male_rules_restored += 1;
      restoredRules.push({
        source_role_id: roleId,
        rule_id: ruleId,
        source_terms: arrayValue(rule?.sourceTerms).map((term) => stringValue(term?.text)),
        before: effectBefore,
        after: effectAfter,
      });
    }
  }

  const changed = JSON.stringify(cache) !== before;
  if (changed) {
    report.files_changed += 1;
    if (options.apply) {
      fs.mkdirSync(backupDir, { recursive: true });
      fs.copyFileSync(cachePath, path.join(backupDir, file));
      fs.writeFileSync(cachePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
    }
  }
  report.rows.push({ file_name: file, changed, restored_rules: restoredRules });
}

if (options.report) {
  const reportPath = path.resolve(options.report);
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
}
console.log(JSON.stringify(report, null, 2));
if (report.unmatched_rule_count > 0) process.exitCode = 1;

function restoreRuleEffect(rule, baselineRule) {
  for (const key of ['action', 'targetPrompt', 'targetWeightMultiplier']) {
    if (Object.hasOwn(baselineRule, key)) {
      rule[key] = structuredClone(baselineRule[key]);
    } else {
      delete rule[key];
    }
  }
}

function ruleEffect(rule) {
  const result = {};
  for (const key of ['action', 'targetPrompt', 'targetWeightMultiplier']) {
    if (Object.hasOwn(rule ?? {}, key)) result[key] = rule[key];
  }
  return result;
}

function ruleHasUnderwearOrSwimwearTerm(rule) {
  return arrayValue(rule?.sourceTerms).some((term) => {
    const category = normalizedKey(term?.category);
    const text = ` ${normalizedText(term?.text ?? term?.sourcePhrase)} `;
    if (category === 'clothingstate') return false;
    if (text.includes(' thong leotard ') || text.includes(' thong bodysuit ')) {
      return false;
    }
    return [
      ' bikini ',
      ' swimsuit ',
      ' swimwear ',
      ' underwear ',
      ' panties ',
      ' panty ',
      ' bra ',
      ' lingerie ',
      ' thong ',
      ' garter belt ',
      ' babydoll ',
    ].some((needle) => text.includes(needle));
  });
}

function roleIsMale(role) {
  if (!role || typeof role !== 'object') return false;
  const text = ` ${[
    role.source_role_id,
    role.display_name,
    role.canonical_name,
    ...arrayValue(role.raw_identity_tags),
  ]
    .map((value) => normalizedText(value))
    .join(' ')} `;
  if (
    [' 1girl ', ' 2girls ', ' 3girls ', ' girl ', ' girls ', ' female ', ' woman ', ' women ']
      .some((needle) => text.includes(needle))
  ) {
    return false;
  }
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

function parseArgs(values) {
  const result = {
    cacheDir: '',
    baselineDir: '',
    backupDir: '',
    report: '',
    cacheFiles: [],
    apply: false,
  };
  for (let index = 0; index < values.length; index += 1) {
    const key = values[index];
    if (!key.startsWith('--')) continue;
    if (key === '--apply') {
      result.apply = true;
      continue;
    }
    const value = values[index + 1];
    index += 1;
    if (key === '--cache-dir') result.cacheDir = value;
    if (key === '--baseline-dir') result.baselineDir = value;
    if (key === '--backup-dir') result.backupDir = value;
    if (key === '--report') result.report = value;
    if (key === '--cache-file') result.cacheFiles.push(path.basename(value));
  }
  return result;
}

function loadJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return null;
  }
}

function arrayValue(value) {
  return Array.isArray(value) ? value : [];
}

function stringValue(value) {
  return value == null ? '' : String(value).trim();
}

function normalizedText(value) {
  return stringValue(value)
    .toLowerCase()
    .replaceAll('_', ' ')
    .replaceAll('-', ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function normalizedKey(value) {
  return normalizedText(value).replaceAll(' ', '');
}

function timestampForPath() {
  return new Date().toISOString().replaceAll(':', '').replaceAll('-', '').replaceAll('.', '');
}
