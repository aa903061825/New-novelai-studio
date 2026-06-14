import fs from 'node:fs';
import path from 'node:path';

const defaultCacheDir = path.join(
  'build',
  'script_recast_rebuild_20260612',
  'offline_ai_rebuild_cache',
);

const options = parseArgs(process.argv.slice(2));
const cacheDir = options.cacheDir ?? defaultCacheDir;
if (!fs.existsSync(cacheDir)) {
  throw new Error(`Missing cache dir: ${cacheDir}`);
}

const rows = fs
  .readdirSync(cacheDir)
  .filter((file) => file.endsWith('.json'))
  .sort()
  .map((file) => auditFile(path.join(cacheDir, file)));
const issueRows = rows.filter((row) => row.issue_count > 0);
const summary = {
  cache_dir: cacheDir,
  cache_count: rows.length,
  ready_count: rows.filter((row) => row.status === 'ready').length,
  needs_more_evidence_count: rows.filter(
    (row) => row.status === 'needs_more_evidence',
  ).length,
  role_count: sum(rows, 'role_count'),
  stage_count: sum(rows, 'stage_count'),
  role_display_issue_count: sum(rows, 'role_display_issue_count'),
  stage_label_issue_count: sum(rows, 'stage_label_issue_count'),
  generic_stage_label_count: sum(rows, 'generic_stage_label_count'),
  issue_cache_count: issueRows.length,
  issue_samples: issueRows.slice(0, options.maxPrint).map(printableRow),
};

console.log(JSON.stringify(summary, null, 2));
if (options.report) {
  fs.mkdirSync(path.dirname(options.report), { recursive: true });
  fs.writeFileSync(
    options.report,
    `${JSON.stringify({ ...summary, rows }, null, 2)}\n`,
    'utf8',
  );
}

function auditFile(filePath) {
  const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const extraction = cache.aiRoleExtraction ?? {};
  const roles = Array.isArray(extraction.roles) ? extraction.roles : [];
  const roleDisplayIssues = [];
  const stageLabelIssues = [];
  let stageCount = 0;
  let genericStageLabelCount = 0;
  for (const role of roles) {
    const displayName = stringValue(role.display_name);
    if (!hasChinese(displayName)) {
      roleDisplayIssues.push({
        role_id: stringValue(role.source_role_id),
        display_name: displayName,
        issue: 'role_display_name_missing_chinese',
      });
    }
    const stages = Array.isArray(role.stages) ? role.stages : [];
    for (const stage of stages) {
      stageCount += 1;
      const label = stringValue(stage.label);
      if (label === '常服') {
        genericStageLabelCount += 1;
      }
      if (!hasChinese(label)) {
        stageLabelIssues.push({
          role_id: stringValue(role.source_role_id),
          stage_id: stringValue(stage.stage_id),
          label,
          issue: 'stage_label_missing_chinese',
        });
        continue;
      }
      const banned = bannedStageLabelTerm(label);
      if (banned) {
        stageLabelIssues.push({
          role_id: stringValue(role.source_role_id),
          stage_id: stringValue(stage.stage_id),
          label,
          banned,
          issue: 'stage_label_contains_action_or_story_term',
        });
      }
    }
  }
  return {
    file_name: path.basename(filePath),
    script_id: stringValue(cache.scriptId),
    script_name: stringValue(cache.scriptName),
    status: stringValue(extraction.status),
    role_count: roles.length,
    stage_count: stageCount,
    role_display_issue_count: roleDisplayIssues.length,
    stage_label_issue_count: stageLabelIssues.length,
    generic_stage_label_count: genericStageLabelCount,
    issue_count: roleDisplayIssues.length + stageLabelIssues.length,
    role_display_issues: roleDisplayIssues,
    stage_label_issues: stageLabelIssues,
  };
}

function bannedStageLabelTerm(label) {
  const banned = [
    '扯',
    '抓',
    '拉',
    '按',
    '插',
    '侵犯',
    '强迫',
    '强制',
    '惩罚',
    '犯罪',
    '尸',
    '死亡',
    '绑架',
    '迷晕',
    '勒',
    '哭',
    '喘',
    '高潮',
    '射',
    '体液',
    '精液',
    'Stage',
    'stage',
    'skirt flip',
    'head out of frame',
    'hand on',
    'sex',
    'cum',
    'orgasm',
    'crime scene',
  ];
  return banned.find((term) => label.includes(term)) ?? '';
}

function printableRow(row) {
  return {
    file_name: row.file_name,
    script_name: row.script_name,
    status: row.status,
    role_count: row.role_count,
    stage_count: row.stage_count,
    role_display_issue_count: row.role_display_issue_count,
    stage_label_issue_count: row.stage_label_issue_count,
    generic_stage_label_count: row.generic_stage_label_count,
    role_display_sample: row.role_display_issues.slice(0, 5),
    stage_label_sample: row.stage_label_issues.slice(0, 5),
  };
}

function hasChinese(value) {
  return /[\u4e00-\u9fff]/.test(stringValue(value));
}

function sum(rows, key) {
  return rows.reduce((total, row) => total + (Number(row[key]) || 0), 0);
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function parseArgs(args) {
  const parsed = {
    cacheDir: undefined,
    report: undefined,
    maxPrint: 20,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    const value = args[index + 1];
    index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'report') parsed.report = value;
    if (key === 'max-print') parsed.maxPrint = Number(value) || parsed.maxPrint;
  }
  return parsed;
}
