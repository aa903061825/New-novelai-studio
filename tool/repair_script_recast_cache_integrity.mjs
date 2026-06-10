import fs from 'node:fs';
import path from 'node:path';

const defaultCacheDir = path.join(
  process.env.APPDATA ?? '',
  'org.exception0x0194',
  'nai3_autodraw',
  'novel_studio',
  'script_recast',
  'cache',
);

const options = parseArgs(process.argv.slice(2));
const cacheDir = options.cacheDir ?? defaultCacheDir;
const reportPath = options.reportPath;
const backupDir = options.backupDir;

if (!reportPath) throw new Error('--report is required');
if (!backupDir) throw new Error('--backup-dir is required');

const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
const changedFiles = new Set();
const slotRepairs = [];
const classificationRepairs = [];

repairSlotCoverage();
repairClassificationFields();

console.log(
  JSON.stringify(
    {
      cache_dir: cacheDir,
      report: reportPath,
      backup_dir: backupDir,
      changed_files: [...changedFiles].sort(),
      slot_repairs: slotRepairs.length,
      classification_repairs: classificationRepairs.length,
    },
    null,
    2,
  ),
);

function repairSlotCoverage() {
  const repairs = {
    'script-792bacf20c7c1436.json': [
      ['role-sensei-blue-archive-the-animation', 'slot-1', [10]],
      [
        'role-ibuki-blue-archive',
        'slot-0',
        [37, 43, 55, 56, 59, 60, 61, 62, 64, 65, 71],
      ],
      ['role-generic-1boy', 'slot-1', [43, 55]],
      ['role-generic-boy', 'slot-1', [56, 59, 60, 61, 62, 64, 65, 71]],
    ],
    'script-png-a61dbf521d75908e.json': [
      ['role-fujita-kotone', 'slot-0', [75, 224]],
      ['role-muscular-male', 'slot-1', [72, 75, 88, 112, 118, 136, 157, 167, 177]],
      ['role-muscular-male', 'slot-2', [72, 220]],
      ['role-generic-boy-slot-1', 'slot-1', [131, 140]],
      ['role-sagisawa-fumika', 'slot-1', [146, 220, 224]],
    ],
  };

  for (const [fileName, fileRepairs] of Object.entries(repairs)) {
    const cache = loadCache(fileName);
    for (const [roleId, slotId, frames] of fileRepairs) {
      const role = findRole(cache, roleId);
      if (!role) throw new Error(`${fileName}: missing role ${roleId}`);
      const appearance = findAppearance(role, slotId);
      if (!appearance) {
        throw new Error(`${fileName}: missing appearance ${roleId}/${slotId}`);
      }
      addFrames(appearance, 'frame_indexes', frames);
      addFrames(role, 'frame_indexes', frames);
      slotRepairs.push({ file_name: fileName, role_id: roleId, slot_id: slotId, frames });
    }
    saveCache(fileName, cache);
  }
}

function repairClassificationFields() {
  for (const row of report.rows ?? []) {
    const issues = row.classification_issues ?? [];
    if (issues.length === 0) continue;
    const cache = loadCache(row.file_name);
    let touched = false;

    for (const issue of issues) {
      if (issue.section === 'aiRoleExtraction') {
        const role = findRole(cache, issue.role_id);
        const stage = findStage(role, issue.stage_id);
        const field = toStageField(issue.field);
        if (!stage || !field) continue;
        const before = stringValue(stage[field]);
        const after = removePromptTerm(before, issue.term);
        if (after !== before) {
          stage[field] = after;
          touched = true;
          classificationRepairs.push({
            file_name: row.file_name,
            role_id: issue.role_id,
            stage_id: issue.stage_id,
            field: issue.field,
            term: issue.term,
          });
        }
        if (Array.isArray(stage.evidence_terms)) {
          stage.evidence_terms = stage.evidence_terms.filter(
            (term) => normalizedTagKey(term) !== normalizedTagKey(issue.term),
          );
        }
      }

      if (issue.section === 'mapping') {
        const assembly = findAssembly(cache, issue.role_id);
        const stage = findMappingStage(assembly, issue.stage_id);
        const field = toSourcePartsField(issue.field);
        if (!stage?.sourceParts || !field) continue;
        const before = stringValue(stage.sourceParts[field]);
        const after = removePromptTerm(before, issue.term);
        if (after !== before) {
          stage.sourceParts[field] = after;
          stage.sourceSummary = sourceSummary(stage.sourceParts);
          touched = true;
          classificationRepairs.push({
            file_name: row.file_name,
            role_id: issue.role_id,
            stage_id: issue.stage_id,
            field: issue.field,
            term: issue.term,
          });
        }
      }
    }

    if (touched) saveCache(row.file_name, cache);
  }
}

function loadCache(fileName) {
  return JSON.parse(fs.readFileSync(path.join(cacheDir, fileName), 'utf8'));
}

function saveCache(fileName, cache) {
  backupCache(fileName);
  cache.updatedAt = new Date().toISOString();
  fs.writeFileSync(path.join(cacheDir, fileName), `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
  changedFiles.add(fileName);
}

function backupCache(fileName) {
  const source = path.join(cacheDir, fileName);
  const target = path.join(backupDir, fileName);
  if (fs.existsSync(target)) return;
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.copyFileSync(source, target);
}

function findRole(cache, roleId) {
  return (cache.aiRoleExtraction?.roles ?? []).find(
    (role) => stringValue(role.source_role_id) === roleId,
  );
}

function findAppearance(role, slotId) {
  return (role.appearances ?? []).find(
    (appearance) => stringValue(appearance.source_id) === slotId,
  );
}

function findStage(role, stageId) {
  return (role?.stages ?? []).find(
    (stage) => stringValue(stage.stage_id) === stageId,
  );
}

function findAssembly(cache, roleId) {
  return (cache.mapping?.roleAssemblies ?? cache.mapping?.role_assemblies ?? []).find(
    (assembly) => stringValue(assembly.sourceRoleId ?? assembly.source_role_id) === roleId,
  );
}

function findMappingStage(assembly, stageId) {
  return (assembly?.stages ?? []).find((stage) => stringValue(stage.id) === stageId);
}

function addFrames(object, key, frames) {
  object[key] = [...new Set([...intList(object[key]), ...frames])].sort((a, b) => a - b);
}

function removePromptTerm(value, termToRemove) {
  const target = normalizedTagKey(termToRemove);
  return stringValue(value)
    .split(',')
    .map((term) => term.trim())
    .filter((term) => term.length > 0)
    .filter((term) => normalizedTagKey(term) !== target)
    .join(', ');
}

function sourceSummary(sourceParts) {
  return ['identity', 'upperBody', 'lowerBody', 'upperClothing', 'lowerClothing']
    .map((key) => stringValue(sourceParts[key]).trim())
    .filter((value) => value.length > 0)
    .join(', ');
}

function toStageField(field) {
  return {
    identity: 'identity',
    upper_body: 'upper_body',
    lower_body: 'lower_body',
    upper_clothing: 'upper_clothing',
    lower_clothing: 'lower_clothing',
  }[field];
}

function toSourcePartsField(field) {
  return {
    'sourceParts.identity': 'identity',
    'sourceParts.upperBody': 'upperBody',
    'sourceParts.lowerBody': 'lowerBody',
    'sourceParts.upperClothing': 'upperClothing',
    'sourceParts.lowerClothing': 'lowerClothing',
  }[field];
}

function normalizedTagKey(value) {
  return stringValue(value)
    .replace(/\b-?\d+(?:\.\d+)?::/g, '')
    .replace(/::/g, '')
    .replace(/\|/g, '')
    .toLowerCase()
    .replace(/[_-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function intList(value) {
  return Array.isArray(value)
    ? value.filter((number) => Number.isInteger(number))
    : [];
}

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}

function parseArgs(args) {
  const parsed = {
    cacheDir: undefined,
    reportPath: undefined,
    backupDir: undefined,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith('--')) continue;
    const equalIndex = arg.indexOf('=');
    const key = equalIndex > 0 ? arg.slice(2, equalIndex) : arg.slice(2);
    const value = equalIndex > 0 ? arg.slice(equalIndex + 1) : args[index + 1] ?? '';
    if (equalIndex < 0) index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'report') parsed.reportPath = value;
    if (key === 'backup-dir') parsed.backupDir = value;
  }
  return parsed;
}
