#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {
  applyContextualMembershipDecisions,
  contextualDecisionTargetConflicts,
  currentPendingTargetKeys,
  finalPendingTargetKeys,
} from './script_recast_contextual_membership.mjs';

const options = parseArgs(process.argv.slice(2));
if (
  !options.cacheDir ||
  !options.outputDir ||
  options.decisionFiles.length === 0 ||
  !options.acceptance ||
  !options.report
) {
  throw new Error(
    'Usage: node tool/apply_script_recast_contextual_membership.mjs ' +
      '--cache-dir <dir> --output-dir <dir> --decisions <final.jsonl> ' +
      '[--decisions <more.jsonl>] --acceptance <acceptance.json> ' +
      '--report <report.json> [--apply]',
  );
}

const report = {
  schema_version: 1,
  kind: 'script_recast_contextual_membership_application',
  api_used: false,
  apply: options.apply,
  cache_dir: options.cacheDir,
  output_dir: options.outputDir,
  decision_files: options.decisionFiles,
  acceptance_file: options.acceptance,
  files_scanned: 0,
  files_changed: 0,
  mutating_decision_count: 0,
  no_change_decision_count: 0,
  outcome_counts: {},
  changed_files: [],
  errors: [],
  status: 'running',
};

try {
  run();
  report.status = 'ok';
} catch (error) {
  report.status = 'failed';
  report.errors.push(String(error?.message ?? error));
  process.exitCode = 1;
} finally {
  fs.mkdirSync(path.dirname(options.report), { recursive: true });
  fs.writeFileSync(options.report, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  const output = `${JSON.stringify(report, null, 2)}\n`;
  if (report.status === 'ok') process.stdout.write(output);
  else process.stderr.write(output);
}

function run() {
  validatePaths();
  const decisions = loadDecisions();
  validateDecisionTargetCollisions(decisions);
  const byFile = new Map();
  for (const decision of decisions) {
    const fileName = path.basename(String(decision?.file_name ?? ''));
    if (!fileName) throw new Error(`${decision?.candidate_id}: missing file_name`);
    const rows = byFile.get(fileName) ?? [];
    rows.push(decision);
    byFile.set(fileName, rows);
  }

  const acceptance = loadAcceptance();
  const files = fs
    .readdirSync(options.cacheDir)
    .filter((file) => file.toLowerCase().endsWith('.json'))
    .sort();
  report.files_scanned = files.length;
  const acceptedNames = [...acceptance.keys()].sort();
  if (JSON.stringify(files) !== JSON.stringify(acceptedNames)) {
    throw new Error(
      `Acceptance/cache file set mismatch: cache=${files.length}, acceptance=${acceptedNames.length}`,
    );
  }
  for (const fileName of byFile.keys()) {
    if (!acceptance.has(fileName)) {
      throw new Error(`Decision targets unknown cache file ${fileName}`);
    }
  }

  const outputs = [];
  for (const fileName of files) {
    const sourcePath = path.join(options.cacheDir, fileName);
    const raw = fs.readFileSync(sourcePath);
    const actualSha = sha256(raw);
    if (actualSha !== acceptance.get(fileName)) {
      throw new Error(`Frozen baseline SHA mismatch for ${fileName}`);
    }
    const cache = JSON.parse(raw.toString('utf8'));
    const fileDecisions = (byFile.get(fileName) ?? []).filter(isMutating);
    let outputRaw = raw;
    let rows = [];
    if (fileDecisions.length > 0) {
      const result = applyContextualMembershipDecisions(cache, fileDecisions);
      rows = result.rows;
      outputRaw = Buffer.from(`${JSON.stringify(result.cache, null, 2)}\n`, 'utf8');
    }
    const changed = !raw.equals(outputRaw);
    if (changed) {
      report.files_changed += 1;
      report.changed_files.push({
        file_name: fileName,
        before_sha256: actualSha,
        after_sha256: sha256(outputRaw),
        decisions: rows,
      });
    }
    outputs.push({ fileName, raw: outputRaw });
  }

  if (!options.apply) return;
  if (fs.existsSync(options.outputDir)) {
    const existing = fs.readdirSync(options.outputDir);
    if (existing.length > 0) {
      throw new Error(`Output directory must be empty: ${options.outputDir}`);
    }
  } else {
    fs.mkdirSync(options.outputDir, { recursive: true });
  }
  for (const output of outputs) {
    fs.writeFileSync(path.join(options.outputDir, output.fileName), output.raw);
  }
}

function validatePaths() {
  if (!fs.existsSync(options.cacheDir) || !fs.statSync(options.cacheDir).isDirectory()) {
    throw new Error(`Missing cache directory ${options.cacheDir}`);
  }
  if (samePath(options.cacheDir, options.outputDir)) {
    throw new Error('Output directory must differ from frozen cache directory');
  }
  for (const file of [...options.decisionFiles, options.acceptance]) {
    if (!fs.existsSync(file) || !fs.statSync(file).isFile()) {
      throw new Error(`Missing input file ${file}`);
    }
  }
}

function loadDecisions() {
  const decisions = [];
  const ids = new Set();
  for (const file of options.decisionFiles) {
    const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/).filter((line) => line.trim());
    for (const [index, line] of lines.entries()) {
      let row;
      try {
        row = JSON.parse(line);
      } catch (error) {
        throw new Error(`${file}:${index + 1}: ${error.message}`);
      }
      const candidateId = String(row?.candidate_id ?? '').trim();
      if (!candidateId) throw new Error(`${file}:${index + 1}: missing candidate_id`);
      if (ids.has(candidateId)) throw new Error(`Duplicate candidate_id ${candidateId}`);
      ids.add(candidateId);
      const outcome = String(row?.final_outcome ?? row?.outcome ?? '').trim();
      report.outcome_counts[outcome] = (report.outcome_counts[outcome] ?? 0) + 1;
      if (isMutating(row)) report.mutating_decision_count += 1;
      else report.no_change_decision_count += 1;
      decisions.push(row);
    }
  }
  return decisions;
}

function validateDecisionTargetCollisions(decisions) {
  const conflicts = contextualDecisionTargetConflicts(decisions);
  if (conflicts.length > 0) {
    const first = conflicts[0];
    throw new Error(
      `Conflicting decisions target one contextual membership: ` +
        `${first.candidate_ids.join('/')} (${first.outcomes.join('/')})`,
    );
  }
  const currentTargets = new Map();
  for (const decision of decisions.filter(isMutating)) {
    const outcome = String(decision?.final_outcome ?? decision?.outcome ?? '').trim();
    if (!['REMOVE_FROM_PENDING', 'MOVE_OWNER', 'CHANGE_CATEGORY'].includes(outcome)) {
      continue;
    }
    for (const contextualTarget of currentPendingTargetKeys(decision)) {
      const target = [decision.file_name, contextualTarget].join('\u001f');
      const existing = currentTargets.get(target);
      if (existing && existing.candidate_id !== decision.candidate_id) {
        if (existing.outcome !== outcome) {
          throw new Error(
            `Conflicting decisions target one pending occurrence: ` +
              `${existing.candidate_id}/${existing.outcome} and ` +
              `${decision.candidate_id}/${outcome}`,
          );
        }
        continue;
      }
      currentTargets.set(target, { candidate_id: decision.candidate_id, outcome });
    }
  }

  const additions = new Map();
  for (const decision of decisions.filter(isMutating)) {
    const outcome = String(decision?.final_outcome ?? decision?.outcome ?? '').trim();
    if (!['ADD_TO_PENDING', 'MOVE_OWNER', 'CHANGE_CATEGORY', 'SPLIT_BY_STAGE'].includes(outcome)) {
      continue;
    }
    for (const contextualTarget of finalPendingTargetKeys(decision)) {
      const key = [decision.file_name, contextualTarget].join('\u001f');
      const existing = additions.get(key);
      // Independent discovery candidates can legitimately converge on the
      // same contextual addition (for example, one ADD and one MOVE from a
      // pseudo-owner).  The applicator merges their role-scoped occurrences.
      if (existing && existing !== decision.candidate_id) continue;
      additions.set(key, decision.candidate_id);
    }
  }
}

function loadAcceptance() {
  const value = JSON.parse(fs.readFileSync(options.acceptance, 'utf8'));
  if (
    value?.kind !== 'script_recast_promotion_acceptance' ||
    value?.api_used !== false ||
    !Array.isArray(value?.cache_files)
  ) {
    throw new Error(`Invalid acceptance document ${options.acceptance}`);
  }
  const result = new Map();
  for (const row of value.cache_files) {
    const fileName = path.basename(String(row?.file_name ?? ''));
    const digest = String(row?.sha256 ?? '').trim().toLowerCase();
    if (!fileName || !/^[0-9a-f]{64}$/.test(digest) || result.has(fileName)) {
      throw new Error(`Invalid acceptance row for ${fileName || '<missing>'}`);
    }
    result.set(fileName, digest);
  }
  return result;
}

function isMutating(decision) {
  return [
    'REMOVE_FROM_PENDING',
    'ADD_TO_PENDING',
    'MOVE_OWNER',
    'CHANGE_CATEGORY',
    'SPLIT_BY_STAGE',
  ].includes(String(decision?.final_outcome ?? decision?.outcome ?? '').trim());
}

function parseArgs(args) {
  const parsed = { apply: false, decisionFiles: [] };
  for (let index = 0; index < args.length; index += 1) {
    const key = args[index];
    if (key === '--apply') {
      parsed.apply = true;
      continue;
    }
    const value = args[index + 1];
    if (!value) throw new Error(`Missing value for ${key}`);
    index += 1;
    if (key === '--cache-dir') parsed.cacheDir = path.resolve(value);
    else if (key === '--output-dir') parsed.outputDir = path.resolve(value);
    else if (key === '--decisions') parsed.decisionFiles.push(path.resolve(value));
    else if (key === '--acceptance') parsed.acceptance = path.resolve(value);
    else if (key === '--report') parsed.report = path.resolve(value);
    else throw new Error(`Unknown argument ${key}`);
  }
  return parsed;
}

function samePath(left, right) {
  return path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}
