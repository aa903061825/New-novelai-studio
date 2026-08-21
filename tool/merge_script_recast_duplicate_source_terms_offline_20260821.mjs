#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const args = parseArgs(process.argv.slice(2));
const cacheDir = path.resolve(args.cacheDir);
const sourceRoot = normalizePath(args.sourceRoot);
const reportFile = path.resolve(args.report);
const backupDir = args.backupDir ? path.resolve(args.backupDir) : '';

if (!fs.existsSync(cacheDir)) throw new Error(`Missing cache directory: ${cacheDir}`);
if (args.apply && !backupDir) throw new Error('Pass --backup-dir when using --apply.');

const report = {
  tool: 'merge_script_recast_duplicate_source_terms_offline_20260821',
  api_used: false,
  apply: args.apply,
  source_root: sourceRoot,
  cache_dir: cacheDir,
  backup_dir: args.apply ? backupDir : '',
  files_scanned: 0,
  files_matched: 0,
  files_with_merges: 0,
  files_changed: 0,
  merged_mapping_term_count: 0,
  merged_ai_term_count: 0,
  removed_empty_rule_count: 0,
  source_write_attempts: 0,
  merges: [],
  validation: { ok: true, errors: [] },
};
const mutations = [];

for (const fileName of fs.readdirSync(cacheDir).filter((name) => name.endsWith('.json')).sort()) {
  report.files_scanned += 1;
  const filePath = path.join(cacheDir, fileName);
  const cache = loadJson(filePath);
  if (!cache || !isUnderSourceRoot(cache.sourceRootPath)) continue;
  report.files_matched += 1;
  const updated = JSON.parse(JSON.stringify(cache));
  const result = mergeDuplicateTerms(updated, fileName);
  if (result.merges.length === 0) continue;
  report.files_with_merges += 1;
  report.merged_mapping_term_count += result.mappingTermCount;
  report.merged_ai_term_count += result.aiTermCount;
  report.removed_empty_rule_count += result.removedEmptyRuleCount;
  for (const merge of result.merges) {
    if (report.merges.length < 100) report.merges.push(merge);
  }
  mutations.push({ fileName, filePath, original: cache, updated });
}

if (args.apply && mutations.length > 0) {
  prepareBackups(mutations, backupDir);
  for (const mutation of mutations) {
    writeJsonAtomic(mutation.filePath, mutation.updated);
    report.files_changed += 1;
    const persisted = loadJson(mutation.filePath);
    const remaining = duplicateSameIdAndNormalizedText(persisted);
    if (remaining.length > 0) {
      report.validation.ok = false;
      report.validation.errors.push(`Duplicate source terms remain in ${mutation.fileName}: ${remaining.join('; ')}`);
    }
  }
}

fs.mkdirSync(path.dirname(reportFile), { recursive: true });
fs.writeFileSync(reportFile, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
console.log(JSON.stringify(report, null, 2));
if (!report.validation.ok) process.exitCode = 1;

function mergeDuplicateTerms(cache, fileName) {
  const result = {
    mappingTermCount: 0,
    aiTermCount: 0,
    removedEmptyRuleCount: 0,
    merges: [],
  };
  for (const replacement of cache.mapping?.rolePromptReplacements || []) {
    const owner = stringValue(replacement?.sourceRoleId).trim();
    const canonicalByKey = new Map();
    const nextRules = [];
    for (const rule of replacement.rules || []) {
      const nextTerms = [];
      for (const term of rule.sourceTerms || []) {
        const key = `${normalizeText(term.text)}\u001f${stringValue(term.id)}`;
        const canonical = canonicalByKey.get(key);
        if (!canonical) {
          canonicalByKey.set(key, { term, rule });
          nextTerms.push(term);
          continue;
        }
        mergeEvidence(canonical.term, term);
        result.mappingTermCount += 1;
        result.merges.push({
          file: fileName,
          representation: 'mapping',
          sourceRoleId: owner,
          sourceTermId: term.id,
          keptText: canonical.term.text,
          mergedText: term.text,
          ruleId: rule.id,
        });
      }
      if (nextTerms.length === 0) {
        result.removedEmptyRuleCount += 1;
        continue;
      }
      nextRules.push({ ...rule, sourceTerms: nextTerms });
    }
    replacement.rules = nextRules;
  }
  for (const role of cache.aiRoleExtraction?.roles || []) {
    const owner = stringValue(role?.source_role_id).trim();
    const canonicalByKey = new Map();
    const nextTerms = [];
    for (const term of role.prompt_terms || []) {
      const key = `${normalizeText(term.text)}\u001f${stringValue(term.id)}`;
      const canonical = canonicalByKey.get(key);
      if (!canonical) {
        canonicalByKey.set(key, term);
        nextTerms.push(term);
        continue;
      }
      mergeEvidence(canonical, term);
      result.aiTermCount += 1;
      result.merges.push({
        file: fileName,
        representation: 'aiRoleExtraction',
        sourceRoleId: owner,
        sourceTermId: term.id,
        keptText: canonical.text,
        mergedText: term.text,
      });
    }
    role.prompt_terms = nextTerms;
  }
  return result;
}

function mergeEvidence(target, source) {
  for (const key of ['frameIndexes', 'frame_indexes', 'sourceOccurrences', 'source_occurrences']) {
    if (!Array.isArray(source?.[key])) continue;
    const values = Array.isArray(target?.[key]) ? target[key] : [];
    target[key] = uniqueJson([...values, ...source[key]]);
  }
  for (const key of ['sourcePhrase', 'source_phrase', 'sourceLocation', 'source_location']) {
    if (!String(target?.[key] || '').trim() && String(source?.[key] || '').trim()) {
      target[key] = source[key];
    }
  }
}

function duplicateSameIdAndNormalizedText(cache) {
  const collisions = [];
  const check = (owner, terms, representation) => {
    const counts = new Map();
    for (const term of terms || []) {
      const key = `${stringValue(term?.id)}\u001f${normalizeText(term?.text)}`;
      counts.set(key, (counts.get(key) || 0) + 1);
    }
    for (const [key, count] of counts) {
      if (count > 1) collisions.push(`${representation}:${owner}:${key}:${count}`);
    }
  };
  for (const replacement of cache.mapping?.rolePromptReplacements || []) {
    const owner = stringValue(replacement?.sourceRoleId).trim();
    check(owner, (replacement.rules || []).flatMap((rule) => rule.sourceTerms || []), 'mapping');
  }
  for (const role of cache.aiRoleExtraction?.roles || []) {
    check(stringValue(role?.source_role_id).trim(), role.prompt_terms || [], 'aiRoleExtraction');
  }
  return collisions;
}

function prepareBackups(mutations, directory) {
  fs.mkdirSync(directory, { recursive: true });
  const manifest = [];
  for (const mutation of mutations) {
    const backup = path.join(directory, mutation.fileName);
    if (fs.existsSync(backup)) throw new Error(`Refusing to overwrite existing backup: ${backup}`);
    fs.copyFileSync(mutation.filePath, backup, fs.constants.COPYFILE_EXCL);
    manifest.push({ source: mutation.filePath, backup, file: mutation.fileName });
  }
  const manifestPath = path.join(directory, 'manifest.json');
  if (fs.existsSync(manifestPath)) throw new Error(`Refusing to overwrite existing backup manifest: ${manifestPath}`);
  fs.writeFileSync(manifestPath, `${JSON.stringify({ tool: 'merge_script_recast_duplicate_source_terms_offline_20260821', files: manifest }, null, 2)}\n`, 'utf8');
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

function uniqueJson(values) {
  const result = [];
  const seen = new Set();
  for (const value of values) {
    const key = JSON.stringify(value);
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(value);
  }
  return result;
}

function isUnderSourceRoot(value) {
  const current = normalizePath(value);
  return current === sourceRoot || current.startsWith(`${sourceRoot}/`);
}

function normalizePath(value) {
  return stringValue(value).replaceAll('\\', '/').replace(/\/+$/, '').toLowerCase();
}

function normalizeText(value) {
  return stringValue(value).trim().toLowerCase().replace(/[\s_]+/g, '_');
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

function parseArgs(values) {
  const parsed = { cacheDir: '', sourceRoot: '', report: '', backupDir: '', apply: false };
  for (let index = 0; index < values.length; index += 1) {
    const arg = values[index];
    if (arg === '--apply') {
      parsed.apply = true;
      continue;
    }
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
    parsed[key] = values[++index];
  }
  if (!parsed.cacheDir || !parsed.sourceRoot || !parsed.report) throw new Error('Pass --cache-dir, --source-root, and --report.');
  return parsed;
}
