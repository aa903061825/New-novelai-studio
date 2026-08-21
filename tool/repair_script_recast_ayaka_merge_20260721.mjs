#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const options = parseArgs(process.argv.slice(2));
if (!options.cacheDir) {
  throw new Error(
    'Usage: node tool/repair_script_recast_ayaka_merge_20260721.mjs ' +
      '--cache-dir <dir> [--backup-dir <dir>] [--report <json>] [--apply]',
  );
}

const cacheDir = path.resolve(options.cacheDir);
const fileName = 'script-8debf5ec0f3b74a2.json';
const filePath = path.join(cacheDir, fileName);
if (!fs.existsSync(filePath)) throw new Error(`Missing target cache: ${filePath}`);

const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
const roles = cache.aiRoleExtraction?.roles ?? [];
const ayakaRoles = roles.filter(
  (role) => String(role.canonical_name ?? '') === 'kamisato ayaka',
);
if (ayakaRoles.length !== 1) {
  throw new Error(`Expected exactly one canonical Ayaka role, found ${ayakaRoles.length}.`);
}
if (
  roles.some(
    (role) =>
      role.source_role_id === 'role-hamedoori-template-meme' ||
      role.source_role_id === 'role-null-nyanpyoun',
  )
) {
  throw new Error('Pseudo-role residue remains; refusing to relabel an invalid cache.');
}

const labels = new Map([
  ['role-kamisato-ayaka\u001fstage-3', '上身裸体 / 完整白色连裤袜'],
  ['role-kamisato-ayaka\u001fstage-4', '上身裸体 / 破损白色连裤袜'],
  ['role-kamisato-ayaka\u001fstage-6', '服装未标注'],
  ['role-anonymous-male\u001fstage-3', '服装未标注'],
  ['role-aether-genshin-impact\u001fstage-2', '服装未标注'],
]);

let changes = 0;
const rows = [];
for (const role of roles) {
  for (const stage of role.stages ?? []) {
    const key = `${role.source_role_id}\u001f${stage.stage_id}`;
    const nextLabel = labels.get(key);
    if (!nextLabel) continue;
    const previousLabel = String(stage.label ?? '');
    const nextWarnings = (stage.warnings ?? []).filter(
      (warning) =>
        warning !== 'duplicate_label_disambiguated_by_local_evidence' &&
        warning !== 'stage_label_needs_manual_review',
    );
    if (
      previousLabel !== nextLabel ||
      JSON.stringify(stage.warnings ?? []) !== JSON.stringify(nextWarnings)
    ) {
      stage.label = nextLabel;
      stage.warnings = nextWarnings;
      changes += 1;
      rows.push({
        source_role_id: role.source_role_id,
        stage_id: stage.stage_id,
        from: previousLabel,
        to: nextLabel,
      });
    }
  }
}

for (const assembly of cache.mapping?.roleAssemblies ?? []) {
  for (const stage of assembly.stages ?? []) {
    const key = `${assembly.sourceRoleId}\u001f${stage.id}`;
    const nextLabel = labels.get(key);
    if (nextLabel && stage.label !== nextLabel) {
      stage.label = nextLabel;
      changes += 1;
    }
  }
}

const report = {
  tool: 'repair_script_recast_ayaka_merge_20260721',
  api_used: false,
  apply: options.apply,
  cache_file: filePath,
  files_changed: changes > 0 ? 1 : 0,
  value_changes: changes,
  rows,
};

if (options.apply && changes > 0) {
  if (options.backupDir) {
    const backupDir = path.resolve(options.backupDir);
    fs.mkdirSync(backupDir, { recursive: true });
    const backupPath = path.join(backupDir, fileName);
    if (!fs.existsSync(backupPath)) fs.copyFileSync(filePath, backupPath);
  }
  fs.writeFileSync(filePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
}
if (options.report) {
  const reportPath = path.resolve(options.report);
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
}
console.log(JSON.stringify(report, null, 2));

function parseArgs(args) {
  const parsed = {
    cacheDir: '',
    backupDir: '',
    report: '',
    apply: false,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--apply') {
      parsed.apply = true;
      continue;
    }
    const value = args[index + 1];
    if (arg === '--cache-dir') parsed.cacheDir = value;
    if (arg === '--backup-dir') parsed.backupDir = value;
    if (arg === '--report') parsed.report = value;
    if (arg.startsWith('--')) index += 1;
  }
  return parsed;
}
