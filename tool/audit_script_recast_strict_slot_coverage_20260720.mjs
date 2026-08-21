#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const args = parseArgs(process.argv.slice(2));
if (!args.cacheDir) {
  console.error('Usage: node tool/audit_script_recast_strict_slot_coverage_20260720.mjs --cache-dir <dir> [--allow-no-role-partials <json>] [--report <json>]');
  process.exit(1);
}

const cacheDir = path.resolve(args.cacheDir);
const allowPath = args.allowPath ? path.resolve(args.allowPath) : null;
const allowDoc = allowPath ? readJson(allowPath) : { entries: [] };
const allowEntries = Array.isArray(allowDoc) ? allowDoc : allowDoc.entries ?? [];
const allowByKey = new Map();
const allowanceIssues = [];
for (const entry of allowEntries) {
  const normalized = {
    script_id: String(entry.script_id ?? entry.scriptId ?? ''),
    frame_index: Number(entry.frame_index ?? entry.frameIndex),
    source_id: String(entry.source_id ?? entry.sourceId ?? ''),
    reason: String(entry.reason ?? '').trim(),
  };
  const key = slotKey(normalized.script_id, normalized.frame_index, normalized.source_id);
  if (!normalized.script_id || !Number.isInteger(normalized.frame_index) || !/^slot-\d+$/.test(normalized.source_id) || !normalized.reason) {
    allowanceIssues.push({ kind: 'invalid_allowance', entry });
    continue;
  }
  if (allowByKey.has(key)) allowanceIssues.push({ kind: 'duplicate_allowance', entry: normalized });
  allowByKey.set(key, normalized);
}

const files = fs.readdirSync(cacheDir).filter((name) => name.endsWith('.json')).sort();
const rows = [];
const observedKeys = new Set();
let nonEmptySlots = 0;
let ownedOnce = 0;
for (const fileName of files) {
  const cache = readJson(path.join(cacheDir, fileName));
  const scriptId = String(cache.scriptId ?? cache.scriptSnapshot?.id ?? '');
  if (!scriptId || !Array.isArray(cache.scriptSnapshot?.frames)) continue;
  const owners = buildOwners(cache);
  for (const frame of cache.scriptSnapshot.frames) {
    const frameIndex = Number(frame.index);
    const captions = Array.isArray(frame.parsed?.charCaptions) ? frame.parsed.charCaptions : [];
    for (let slotIndex = 0; slotIndex < captions.length; slotIndex += 1) {
      const caption = String(captions[slotIndex] ?? '').trim();
      if (!caption) continue;
      nonEmptySlots += 1;
      const sourceId = `slot-${slotIndex}`;
      const key = slotKey(scriptId, frameIndex, sourceId);
      observedKeys.add(key);
      const slotOwners = [...(owners.get(`${frameIndex}\u001f${sourceId}`) ?? [])].sort();
      if (slotOwners.length === 1) {
        ownedOnce += 1;
        if (allowByKey.has(key)) {
          allowanceIssues.push({
            kind: 'stale_allowance_owned_slot',
            ...allowByKey.get(key),
            owners: slotOwners,
            evidence: caption,
          });
        }
        continue;
      }
      const allowance = allowByKey.get(key);
      rows.push({
        script_id: scriptId,
        file_name: fileName,
        frame_index: frameIndex,
        source_id: sourceId,
        kind: slotOwners.length === 0 ? (allowance ? 'allowed_no_role_partial' : 'uncovered_slot') : 'duplicate_slot_ownership',
        owners: slotOwners,
        evidence: caption,
        ...(allowance ? { allowance_reason: allowance.reason } : {}),
      });
    }
  }
}

for (const [key, entry] of allowByKey) {
  if (!observedKeys.has(key)) allowanceIssues.push({ kind: 'allowance_target_missing_or_empty', ...entry });
}

const uncovered = rows.filter((row) => row.kind === 'uncovered_slot');
const duplicates = rows.filter((row) => row.kind === 'duplicate_slot_ownership');
const allowed = rows.filter((row) => row.kind === 'allowed_no_role_partial');
const report = {
  tool: 'audit_script_recast_strict_slot_coverage_20260720',
  api_used: false,
  cache_dir: cacheDir,
  allow_no_role_partials: allowPath,
  files_scanned: files.length,
  non_empty_char_caption_slots: nonEmptySlots,
  uniquely_owned_slots: ownedOnce,
  uncovered_slot_count: uncovered.length,
  duplicate_ownership_count: duplicates.length,
  allowed_no_role_partial_count: allowed.length,
  allowance_issue_count: allowanceIssues.length,
  rows,
  allowance_issues: allowanceIssues,
};

const output = `${JSON.stringify(report, null, 2)}\n`;
if (args.reportPath) {
  const reportPath = path.resolve(args.reportPath);
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, output, 'utf8');
}
process.stdout.write(output);
if (uncovered.length || duplicates.length || allowanceIssues.length) process.exitCode = 2;

function buildOwners(cache) {
  const result = new Map();
  for (const role of cache.aiRoleExtraction?.roles ?? []) {
    const roleId = String(role.source_role_id ?? '');
    for (const appearance of role.appearances ?? []) {
      const sourceId = String(appearance.source_id ?? '');
      for (const frameIndexValue of appearance.frame_indexes ?? []) {
        const frameIndex = Number(frameIndexValue);
        const key = `${frameIndex}\u001f${sourceId}`;
        const values = result.get(key) ?? new Set();
        values.add(roleId);
        result.set(key, values);
      }
    }
  }
  return result;
}

function slotKey(scriptId, frameIndex, sourceId) {
  return `${scriptId}\u001f${frameIndex}\u001f${sourceId}`;
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function parseArgs(values) {
  const result = { cacheDir: '', allowPath: '', reportPath: '' };
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === '--cache-dir') result.cacheDir = values[++index] ?? '';
    else if (value === '--allow-no-role-partials') result.allowPath = values[++index] ?? '';
    else if (value === '--report') result.reportPath = values[++index] ?? '';
    else throw new Error(`Unknown argument: ${value}`);
  }
  return result;
}
