import fs from 'node:fs';
import path from 'node:path';

const options = parseArgs(process.argv.slice(2));
if (!options.cacheDir) {
  throw new Error(
    'Usage: node tool/audit_script_recast_stage_duplicates.mjs --cache-dir <dir> [--report-path <file>]',
  );
}

const cacheDir = path.resolve(options.cacheDir);
const files = fs
  .readdirSync(cacheDir)
  .filter((file) => file.endsWith('.json'))
  .sort();

const report = {
  cache_dir: cacheDir,
  cache_count: files.length,
  role_count: 0,
  stage_count: 0,
  duplicate_stage_label_group_count: 0,
  issue_cache_count: 0,
  issue_samples: [],
};

for (const file of files) {
  const cache = loadJson(path.join(cacheDir, file), null);
  if (!cache) continue;
  const issues = auditCache(cache);
  report.role_count += issues.roleCount;
  report.stage_count += issues.stageCount;
  report.duplicate_stage_label_group_count += issues.items.length;
  if (issues.items.length > 0) {
    report.issue_cache_count += 1;
    for (const item of issues.items.slice(0, 5)) {
      report.issue_samples.push({
        file_name: file,
        script_name: stringValue(cache.scriptName),
        ...item,
      });
    }
  }
}

report.issue_samples = report.issue_samples.slice(0, 25);
console.log(JSON.stringify(report, null, 2));
if (options.reportPath) {
  const reportPath = path.resolve(options.reportPath);
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
}

function auditCache(cache) {
  const items = [];
  let roleCount = 0;
  let stageCount = 0;
  for (const role of cache.aiRoleExtraction?.roles ?? []) {
    roleCount += 1;
    const byLabel = new Map();
    for (const stage of role.stages ?? []) {
      stageCount += 1;
      const key = normalizedStageLabelKey(stage.label);
      if (!key) continue;
      const group = byLabel.get(key) ?? [];
      group.push(stage);
      byLabel.set(key, group);
    }
    for (const [label_key, stages] of byLabel) {
      if (stages.length <= 1) continue;
      items.push({
        role_id: stringValue(role.source_role_id),
        role_display_name: stringValue(role.display_name),
        label_key,
        label: stringValue(stages[0]?.label),
        stage_count: stages.length,
        stage_ids: stages.map((stage) => stringValue(stage.stage_id)),
        frame_samples: stages.map((stage) =>
          Array.isArray(stage.frame_indexes)
            ? stage.frame_indexes.slice(0, 12)
            : [],
        ),
      });
    }
  }
  return { roleCount, stageCount, items };
}

function normalizedStageLabelKey(label) {
  return stringValue(label)
    .replace(/\s+/g, '')
    .replace(/[\/|,，、;；:：]+/g, '')
    .trim();
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function loadJson(filePath, fallback) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return fallback;
  }
}

function parseArgs(args) {
  const parsed = {
    cacheDir: undefined,
    reportPath: undefined,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    const value = args[index + 1];
    index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'report-path') parsed.reportPath = value;
  }
  return parsed;
}
