import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const options = parseArgs(process.argv.slice(2));
if (!options.cacheDir) {
  throw new Error('Usage: node tool/audit_script_recast_strict_slot_coverage_20260720_a.mjs --cache-dir <dir> [--no-role-partials <file>] [--report <file>]');
}
const cacheDir = path.resolve(options.cacheDir);
if (!fs.existsSync(cacheDir)) throw new Error(`Missing cache dir: ${cacheDir}`);
const partialDocument = loadJson(options.noRolePartials, { items: [] });
const partials = new Map((partialDocument.items ?? []).map((item) => [partialKey(item.scriptId, item.frameIndex, item.slot), item]));
const usedPartials = new Set();
const rows = [];

for (const fileName of fs.readdirSync(cacheDir).filter((name) => name.endsWith('.json')).sort()) {
  const cache = JSON.parse(fs.readFileSync(path.join(cacheDir, fileName), 'utf8'));
  const roles = cache.aiRoleExtraction?.roles ?? [];
  const appearances = [];
  for (const role of roles) {
    for (const appearance of role.appearances ?? []) {
      for (const frameIndex of appearance.frame_indexes ?? []) {
        appearances.push({ roleId: role.source_role_id, sourceId: appearance.source_id, frameIndex: Number(frameIndex) });
      }
    }
  }
  const row = {
    file_name: fileName,
    script_id: cache.scriptId,
    frame_count: cache.scriptSnapshot?.frames?.length ?? 0,
    role_count: roles.length,
    non_empty_slot_count: 0,
    covered_slot_count: 0,
    no_role_partial_count: 0,
    missing_slot_count: 0,
    multiple_role_slot_count: 0,
    invalid_role_reference_count: 0,
    same_role_multi_slot_frame_count: 0,
    issues: [],
    no_role_partials: [],
  };
  const frameMap = new Map((cache.scriptSnapshot?.frames ?? []).map((frame) => [Number(frame.index), frame]));
  for (const frame of cache.scriptSnapshot?.frames ?? []) {
    const frameIndex = Number(frame.index);
    const captions = Array.isArray(frame.parsed?.charCaptions) ? frame.parsed.charCaptions : [];
    for (let slot = 0; slot < captions.length; slot += 1) {
      const caption = stringValue(captions[slot]).trim();
      if (!caption) continue;
      row.non_empty_slot_count += 1;
      const sourceId = `slot-${slot}`;
      const refs = appearances.filter((item) => item.frameIndex === frameIndex && item.sourceId === sourceId);
      if (refs.length === 1) {
        row.covered_slot_count += 1;
      } else if (refs.length > 1) {
        row.multiple_role_slot_count += 1;
        row.issues.push({ issue: 'multiple_roles_cover_slot', frame_index: frameIndex, slot, role_ids: refs.map((item) => item.roleId), caption });
      } else {
        const key = partialKey(cache.scriptId, frameIndex, slot);
        const allowed = partials.get(key);
        const evidenceHash = sha256(caption);
        if (allowed && (!allowed.captionSha256 || allowed.captionSha256 === evidenceHash)) {
          usedPartials.add(key);
          row.no_role_partial_count += 1;
          row.no_role_partials.push({ frame_index: frameIndex, slot, caption, caption_sha256: evidenceHash, reason: allowed.reason ?? '' });
        } else {
          row.missing_slot_count += 1;
          row.issues.push({ issue: 'missing_non_empty_slot_role', frame_index: frameIndex, slot, caption, caption_sha256: evidenceHash, partial_hash_mismatch: Boolean(allowed) });
        }
      }
    }
  }
  for (const ref of appearances) {
    const frame = frameMap.get(ref.frameIndex);
    const slot = Number(ref.sourceId.slice('slot-'.length));
    const caption = stringValue(frame?.parsed?.charCaptions?.[slot]).trim();
    if (!frame || !caption) {
      row.invalid_role_reference_count += 1;
      row.issues.push({ issue: 'role_reference_without_non_empty_slot', role_id: ref.roleId, frame_index: ref.frameIndex, source_id: ref.sourceId });
    }
  }
  for (const role of roles) {
    const byFrame = new Map();
    for (const appearance of role.appearances ?? []) {
      for (const frameIndex of appearance.frame_indexes ?? []) {
        const ids = byFrame.get(Number(frameIndex)) ?? [];
        ids.push(appearance.source_id);
        byFrame.set(Number(frameIndex), ids);
      }
    }
    for (const [frameIndex, sourceIds] of byFrame) {
      if (sourceIds.length <= 1) continue;
      row.same_role_multi_slot_frame_count += 1;
      row.issues.push({ issue: 'same_role_occupies_multiple_slots', role_id: role.source_role_id, frame_index: frameIndex, source_ids: sourceIds });
    }
  }
  rows.push(row);
}

const stalePartials = [...partials.entries()].filter(([key]) => !usedPartials.has(key)).map(([, item]) => item);
const summary = {
  kind: 'script_recast_strict_slot_coverage_audit',
  cache_dir: cacheDir,
  no_role_partials_file: options.noRolePartials ? path.resolve(options.noRolePartials) : '',
  cache_count: rows.length,
  frame_count: sum(rows, 'frame_count'),
  role_count: sum(rows, 'role_count'),
  non_empty_slot_count: sum(rows, 'non_empty_slot_count'),
  covered_slot_count: sum(rows, 'covered_slot_count'),
  no_role_partial_count: sum(rows, 'no_role_partial_count'),
  missing_slot_count: sum(rows, 'missing_slot_count'),
  multiple_role_slot_count: sum(rows, 'multiple_role_slot_count'),
  invalid_role_reference_count: sum(rows, 'invalid_role_reference_count'),
  same_role_multi_slot_frame_count: sum(rows, 'same_role_multi_slot_frame_count'),
  stale_no_role_partial_count: stalePartials.length,
  stale_no_role_partials: stalePartials,
  issue_cache_count: rows.filter((row) => row.issues.length > 0).length,
  rows,
};
console.log(JSON.stringify(summary, null, 2));
if (options.report) {
  const reportPath = path.resolve(options.report);
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify(summary, null, 2)}\n`, 'utf8');
}
if (summary.issue_cache_count > 0 || summary.stale_no_role_partial_count > 0) process.exitCode = 1;

function parseArgs(args) {
  const result = { cacheDir: '', noRolePartials: '', report: '' };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    const value = args[index + 1] ?? '';
    index += 1;
    if (key === 'cache-dir') result.cacheDir = value;
    if (key === 'no-role-partials') result.noRolePartials = value;
    if (key === 'report') result.report = value;
  }
  return result;
}

function loadJson(filePath, fallback) {
  if (!filePath) return fallback;
  try { return JSON.parse(fs.readFileSync(filePath, 'utf8')); } catch { return fallback; }
}

function partialKey(scriptId, frameIndex, slot) {
  return `${scriptId}\u001f${Number(frameIndex)}\u001f${Number(slot)}`;
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function sum(rows, key) {
  return rows.reduce((total, row) => total + Number(row[key] ?? 0), 0);
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}
