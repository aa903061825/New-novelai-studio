import fs from 'node:fs';
import path from 'node:path';

const options = parseArgs(process.argv.slice(2));
if (!options.cacheDir) {
  throw new Error('Pass --cache-dir <directory>.');
}

const roleLabels = new Map([
  [
    'role-marie-antoinette-fate',
    'marie antoinette (fate) / \u739b\u4e3d\u00b7\u5b89\u6258\u74e6\u5185\u7279\uff08Fate\uff09',
  ],
  [
    'role-maki-camp-blue-archive',
    'maki (camp) (blue archive) / \u771f\u6728\uff08\u8425\u5730\uff09\uff08\u78a7\u84dd\u6863\u6848\uff09',
  ],
  [
    'role-reisa-blue-archive',
    'reisa (blue archive) / \u73b2\u7eb1\uff08\u78a7\u84dd\u6863\u6848\uff09',
  ],
  [
    'role-toki-bunny-blue-archive',
    'toki (bunny) (blue archive) / \u65f6\uff08\u5154\u5973\u90ce\uff09\uff08\u78a7\u84dd\u6863\u6848\uff09',
  ],
]);

const stageLabelReplacements = new Map([
  ['\u88d9\u88c5\u63c0\u8d77', '\u88d9\u6446\u6380\u8d77'],
]);

const cacheDir = path.resolve(options.cacheDir);
const reportPath = options.report ? path.resolve(options.report) : '';
const files = fs
  .readdirSync(cacheDir)
  .filter((file) => file.endsWith('.json'))
  .sort();

const report = {
  cache_dir: cacheDir,
  apply: options.apply,
  files_scanned: files.length,
  files_changed: 0,
  role_labels_changed: 0,
  stage_labels_changed: 0,
  rows: [],
};

for (const file of files) {
  const filePath = path.join(cacheDir, file);
  const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const row = {
    file_name: file,
    script_id: stringValue(cache.scriptId),
    script_name: stringValue(cache.scriptName),
    role_label_changes: [],
    stage_label_changes: [],
  };

  for (const role of Array.isArray(cache.aiRoleExtraction?.roles)
    ? cache.aiRoleExtraction.roles
    : []) {
    const roleId = stringValue(role.source_role_id);
    const nextLabel = roleLabels.get(roleId);
    if (nextLabel && role.display_name !== nextLabel) {
      row.role_label_changes.push({
        role_id: roleId,
        field: 'aiRoleExtraction.display_name',
        before: role.display_name,
        after: nextLabel,
      });
      role.display_name = nextLabel;
    }
    for (const stage of Array.isArray(role.stages) ? role.stages : []) {
      updateStageLabel(row, {
        section: 'aiRoleExtraction',
        role_id: roleId,
        stage_id: stringValue(stage.stage_id),
        object: stage,
      });
    }
  }

  for (const replacement of Array.isArray(cache.mapping?.rolePromptReplacements)
    ? cache.mapping.rolePromptReplacements
    : []) {
    const roleId = stringValue(replacement.sourceRoleId);
    const nextLabel = roleLabels.get(roleId);
    if (nextLabel && replacement.displayLabel !== nextLabel) {
      row.role_label_changes.push({
        role_id: roleId,
        field: 'mapping.rolePromptReplacements.displayLabel',
        before: replacement.displayLabel,
        after: nextLabel,
      });
      replacement.displayLabel = nextLabel;
    }
  }

  for (const assembly of Array.isArray(cache.mapping?.roleAssemblies)
    ? cache.mapping.roleAssemblies
    : []) {
    const roleId = stringValue(assembly.sourceRoleId);
    const nextLabel = roleLabels.get(roleId);
    for (const field of ['displayLabel', 'sourceName']) {
      if (nextLabel && assembly[field] !== nextLabel) {
        row.role_label_changes.push({
          role_id: roleId,
          field: `mapping.roleAssemblies.${field}`,
          before: assembly[field],
          after: nextLabel,
        });
        assembly[field] = nextLabel;
      }
    }
    for (const stage of Array.isArray(assembly.stages) ? assembly.stages : []) {
      updateStageLabel(row, {
        section: 'mapping.roleAssemblies',
        role_id: roleId,
        stage_id: stringValue(stage.id),
        object: stage,
      });
    }
  }

  if (row.role_label_changes.length || row.stage_label_changes.length) {
    report.files_changed += 1;
    report.role_labels_changed += row.role_label_changes.length;
    report.stage_labels_changed += row.stage_label_changes.length;
    report.rows.push(row);
    if (options.apply) {
      fs.writeFileSync(filePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
    }
  }
}

if (reportPath) {
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
}
console.log(JSON.stringify(report, null, 2));

function updateStageLabel(row, { section, role_id, stage_id, object }) {
  const before = stringValue(object.label);
  let after = before;
  for (const [from, to] of stageLabelReplacements) {
    after = after.replaceAll(from, to);
  }
  if (after === before) return;
  row.stage_label_changes.push({
    section,
    role_id,
    stage_id,
    before,
    after,
  });
  object.label = after;
}

function parseArgs(args) {
  const parsed = { cacheDir: '', report: '', apply: false };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    if (key === 'apply') {
      parsed.apply = true;
      continue;
    }
    const value = args[index + 1];
    index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'report') parsed.report = value;
  }
  return parsed;
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}
