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
  tool: 'repair_script_recast_duplicate_source_term_ids_offline_20260821',
  api_used: false,
  apply: args.apply,
  source_root: sourceRoot,
  cache_dir: cacheDir,
  backup_dir: args.apply ? backupDir : '',
  files_scanned: 0,
  files_matched: 0,
  files_with_collisions: 0,
  files_changed: 0,
  collision_count: 0,
  changed_term_count: 0,
  changed_reference_count: 0,
  source_write_attempts: 0,
  collisions: [],
  validation: { ok: true, errors: [] },
};
const mutations = [];

for (const fileName of fs.readdirSync(cacheDir).filter((name) => name.endsWith('.json')).sort()) {
  report.files_scanned += 1;
  const filePath = path.join(cacheDir, fileName);
  const cache = loadJson(filePath);
  if (!cache || !isUnderSourceRoot(cache.sourceRootPath)) continue;
  report.files_matched += 1;
  const plan = buildPlan(cache, fileName);
  if (plan.collisions.length === 0) continue;
  report.files_with_collisions += 1;
  report.collision_count += plan.collisions.length;
  for (const collision of plan.collisions) {
    if (report.collisions.length < 100) report.collisions.push(collision);
  }
  const next = JSON.parse(JSON.stringify(cache));
  const applied = applyPlan(next, plan);
  report.changed_term_count += applied.changedTermCount;
  report.changed_reference_count += applied.changedReferenceCount;
  mutations.push({ fileName, filePath, original: cache, updated: next });
}

if (args.apply && mutations.length > 0) {
  prepareBackups(mutations, backupDir);
  for (const mutation of mutations) {
    writeJsonAtomic(mutation.filePath, mutation.updated);
    report.files_changed += 1;
    const persisted = loadJson(mutation.filePath);
    if (!persisted || remainingCollisions(persisted).length > 0) {
      report.validation.ok = false;
      report.validation.errors.push(`Duplicate source term ids remain in ${mutation.fileName}.`);
    }
  }
}

fs.mkdirSync(path.dirname(reportFile), { recursive: true });
fs.writeFileSync(reportFile, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
console.log(JSON.stringify(report, null, 2));
if (!report.validation.ok) process.exitCode = 1;

function buildPlan(cache, fileName) {
  const occurrences = new Map();
  const add = (owner, term, location) => {
    const id = stringValue(term?.id).trim();
    const text = stringValue(term?.text).trim();
    if (!owner || !id || !text) return;
    const ownerMap = occurrences.get(owner) || new Map();
    const idMap = ownerMap.get(id) || new Map();
    const key = normalizeText(text);
    const list = idMap.get(key) || [];
    list.push({ term, location, text });
    idMap.set(key, list);
    ownerMap.set(id, idMap);
    occurrences.set(owner, ownerMap);
  };
  for (const replacement of cache.mapping?.rolePromptReplacements || []) {
    const owner = stringValue(replacement?.sourceRoleId).trim();
    for (const [ruleIndex, rule] of (replacement.rules || []).entries()) {
      for (const [termIndex, term] of (rule.sourceTerms || []).entries()) {
        add(owner, term, `mapping.rolePromptReplacements[${owner}].rules[${ruleIndex}].sourceTerms[${termIndex}]`);
      }
    }
  }
  for (const [roleIndex, role] of (cache.aiRoleExtraction?.roles || []).entries()) {
    const owner = stringValue(role?.source_role_id).trim();
    for (const [termIndex, term] of (role.prompt_terms || []).entries()) {
      add(owner, term, `aiRoleExtraction.roles[${roleIndex}].prompt_terms[${termIndex}]`);
    }
  }

  const idPlan = new Map();
  const collisions = [];
  for (const [owner, ownerMap] of occurrences.entries()) {
    const usedIds = new Set();
    for (const id of ownerMap.keys()) usedIds.add(id);
    for (const [oldId, textMap] of ownerMap.entries()) {
      if (textMap.size < 2) continue;
      const sortedTexts = [...textMap.keys()].sort((left, right) => left.localeCompare(right));
      const nextByText = new Map();
      for (const [index, text] of sortedTexts.entries()) {
        let nextId = index === 0 ? oldId : `${oldId}--${slug(text)}`;
        let suffix = 2;
        while (usedIds.has(nextId) && nextId !== oldId) {
          nextId = `${oldId}--${slug(text)}-${suffix}`;
          suffix += 1;
        }
        usedIds.add(nextId);
        nextByText.set(text, nextId);
      }
      idPlan.set(planKey(owner, oldId), nextByText);
      collisions.push({
        file: fileName,
        sourceRoleId: owner,
        oldId,
        texts: sortedTexts,
        nextIds: Object.fromEntries(nextByText.entries()),
      });
    }
  }
  return { idPlan, collisions };
}

function applyPlan(cache, plan) {
  let changedTermCount = 0;
  let changedReferenceCount = 0;
  const replacementByOwner = new Map(
    (cache.mapping?.rolePromptReplacements || []).map((replacement) => [stringValue(replacement?.sourceRoleId).trim(), replacement]),
  );
  for (const replacement of cache.mapping?.rolePromptReplacements || []) {
    const owner = stringValue(replacement?.sourceRoleId).trim();
    for (const rule of replacement.rules || []) {
      const originalTerms = (rule.sourceTerms || []).map((term) => ({ id: stringValue(term.id), text: stringValue(term.text) }));
      const nextIds = originalTerms.map(({ id, text }) => resolveId(plan.idPlan, owner, id, text));
      for (let index = 0; index < (rule.sourceTerms || []).length; index += 1) {
        const term = rule.sourceTerms[index];
        const nextId = nextIds[index];
        if (nextId !== term.id) {
          term.id = nextId;
          changedTermCount += 1;
        }
      }
      const nextExcluded = [];
      for (const oldId of rule.excludedTermIds || []) {
        const candidates = originalTerms
          .filter((term) => term.id === oldId)
          .map((term) => resolveId(plan.idPlan, owner, term.id, term.text));
        const values = candidates.length > 0 ? candidates : [oldId];
        for (const value of values) if (!nextExcluded.includes(value)) nextExcluded.push(value);
      }
      if (JSON.stringify(nextExcluded) !== JSON.stringify(rule.excludedTermIds || [])) {
        rule.excludedTermIds = nextExcluded;
        changedReferenceCount += 1;
      }
      const anchorTerm = originalTerms.find((term) => term.id === rule.anchorTermId);
      if (anchorTerm) {
        const nextAnchor = resolveId(plan.idPlan, owner, anchorTerm.id, anchorTerm.text);
        if (nextAnchor !== rule.anchorTermId) {
          rule.anchorTermId = nextAnchor;
          changedReferenceCount += 1;
        }
      }
    }
  }
  for (const role of cache.aiRoleExtraction?.roles || []) {
    const owner = stringValue(role?.source_role_id).trim();
    for (const term of role.prompt_terms || []) {
      const nextId = resolveId(plan.idPlan, owner, stringValue(term.id), stringValue(term.text));
      if (nextId !== term.id) {
        term.id = nextId;
        changedTermCount += 1;
      }
    }
  }
  void replacementByOwner;
  return { changedTermCount, changedReferenceCount };
}

function remainingCollisions(cache) {
  return buildPlan(cache, '').collisions;
}

function resolveId(idPlan, owner, oldId, text) {
  return idPlan.get(planKey(owner, oldId))?.get(normalizeText(text)) || oldId;
}

function planKey(owner, oldId) {
  return `${owner}\u001f${oldId}`;
}

function slug(value) {
  return normalizeText(value).replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'term';
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
  fs.writeFileSync(manifestPath, `${JSON.stringify({ tool: 'repair_script_recast_duplicate_source_term_ids_offline_20260821', files: manifest }, null, 2)}\n`, 'utf8');
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
