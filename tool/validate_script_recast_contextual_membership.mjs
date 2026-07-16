#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import {
  contextualDecisionTargetConflicts,
  currentPendingTargetKeys,
  finalPendingTargetKeys,
  normalizeContextualStageId,
  normalizeMembershipKey,
  splitContextualPromptAtoms,
  validateContextualPromptParity,
} from './script_recast_contextual_membership.mjs';

const addOutcomes = new Set([
  'ADD_TO_PENDING',
  'MOVE_OWNER',
  'CHANGE_CATEGORY',
  'SPLIT_BY_STAGE',
]);
const removeOutcomes = new Set([
  'REMOVE_FROM_PENDING',
  'MOVE_OWNER',
  'CHANGE_CATEGORY',
]);
const mutatingOutcomes = new Set([...addOutcomes, ...removeOutcomes]);

export function validateContextualMembership({
  baselineDir,
  cacheDir,
  decisionsFile,
  expectedCount,
}) {
  const report = {
    kind: 'script_recast_contextual_membership_validation',
    schema_version: 1,
    api_used: false,
    read_only: true,
    baseline_dir: path.resolve(baselineDir),
    cache_dir: path.resolve(cacheDir),
    decisions_file: path.resolve(decisionsFile),
    expected_count: Number(expectedCount),
    files_scanned: 0,
    decision_count: 0,
    mutating_decision_count: 0,
    parity_issue_count: 0,
    non_membership_change_count: 0,
    unexpected_membership_add_count: 0,
    unexpected_membership_remove_count: 0,
    unexpected_membership_change_count: 0,
    decision_missing_addition_count: 0,
    decision_missing_removal_count: 0,
    decision_occurrence_mismatch_count: 0,
    decision_target_conflict_count: 0,
    baseline_source_occurrence_issue_count: 0,
    candidate_source_occurrence_issue_count: 0,
    source_occurrence_issue_count: 0,
    evidence_binding_issue_count: 0,
    parse_error_count: 0,
    file_set_issue_count: 0,
    violation_count: 0,
    complete: false,
    cache_files: [],
    violations: [],
  };

  try {
    assertDirectory(report.baseline_dir, 'baseline directory');
    assertDirectory(report.cache_dir, 'candidate cache directory');
    assertRegularFile(report.decisions_file, 'decisions file');
    const decisions = loadJsonl(report.decisions_file);
    report.decision_count = decisions.length;
    report.mutating_decision_count = decisions.filter((row) =>
      mutatingOutcomes.has(outcomeOf(row)),
    ).length;
    for (const conflict of contextualDecisionTargetConflicts(decisions)) {
      report.decision_target_conflict_count += 1;
      violation(report, 'decision_target_conflict', conflict);
    }
    const byFile = groupDecisions(decisions);

    const baselineFiles = jsonFiles(report.baseline_dir);
    const candidateFiles = jsonFiles(report.cache_dir);
    report.files_scanned = candidateFiles.length;
    if (
      baselineFiles.length !== report.expected_count ||
      candidateFiles.length !== report.expected_count ||
      JSON.stringify(baselineFiles) !== JSON.stringify(candidateFiles)
    ) {
      report.file_set_issue_count += 1;
      violation(report, 'file_set_mismatch', {
        baseline_count: baselineFiles.length,
        candidate_count: candidateFiles.length,
      });
    }

    for (const fileName of candidateFiles) {
      const baselinePath = path.join(report.baseline_dir, fileName);
      const candidatePath = path.join(report.cache_dir, fileName);
      if (!fs.existsSync(baselinePath)) continue;
      let baseline;
      let candidate;
      try {
        baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf8'));
        candidate = JSON.parse(fs.readFileSync(candidatePath, 'utf8'));
      } catch (error) {
        report.parse_error_count += 1;
        violation(report, 'parse_error', { file_name: fileName, message: errorMessage(error) });
        continue;
      }

      report.cache_files.push({
        file_name: fileName,
        sha256: sha256(fs.readFileSync(candidatePath)),
      });
      const fileDecisions = (byFile.get(fileName) ?? []).filter((row) =>
        mutatingOutcomes.has(outcomeOf(row)),
      );
      validateFile(report, fileName, baseline, candidate, fileDecisions);
    }
  } catch (error) {
    violation(report, 'validation_fatal', { message: errorMessage(error) });
  }

  report.violation_count = report.violations.length;
  report.complete =
    report.files_scanned === report.expected_count &&
    report.violation_count === 0 &&
    report.cache_files.length === report.expected_count;
  return report;
}

function validateFile(report, fileName, baseline, candidate, decisions) {
  const parity = validateContextualPromptParity(candidate);
  if (!parity.ok) {
    report.parity_issue_count += 1;
    violation(report, 'ai_mapping_parity', { file_name: fileName, ...parity });
  }

  if (stableJson(stripMembershipSurfaces(baseline)) !== stableJson(stripMembershipSurfaces(candidate))) {
    report.non_membership_change_count += 1;
    violation(report, 'non_membership_change', { file_name: fileName });
  }

  const before = membershipInventory(baseline);
  const after = membershipInventory(candidate);
  const allowed = allowedChanges(decisions);
  const keys = new Set([...before.keys(), ...after.keys()]);
  for (const key of [...keys].sort()) {
    const beforeRows = before.get(key) ?? [];
    const afterRows = after.get(key) ?? [];
    if (stableJson(beforeRows) === stableJson(afterRows)) continue;
    if (beforeRows.length === 0) {
      if (!allowed.additions.has(key)) {
        report.unexpected_membership_add_count += 1;
        violation(report, 'unexpected_membership_add', { file_name: fileName, target: key });
      }
      continue;
    }
    if (afterRows.length === 0) {
      if (!allowed.removals.has(key)) {
        report.unexpected_membership_remove_count += 1;
        violation(report, 'unexpected_membership_remove', { file_name: fileName, target: key });
      }
      continue;
    }
    if (!allowed.additions.has(key) && !allowed.removals.has(key)) {
      report.unexpected_membership_change_count += 1;
      violation(report, 'unexpected_membership_change', { file_name: fileName, target: key });
    }
  }

  for (const [key, rows] of allowed.removals) {
    if (!allowed.additions.has(key) && after.has(key)) {
      report.decision_missing_removal_count += 1;
      violation(report, 'decision_missing_removal', {
        file_name: fileName,
        target: key,
        candidate_ids: rows.map((row) => row.candidate_id),
      });
    }
  }
  for (const [key, rows] of allowed.additions) {
    const terms = after.get(key);
    if (!terms || terms.length === 0) {
      report.decision_missing_addition_count += 1;
      violation(report, 'decision_missing_addition', {
        file_name: fileName,
        target: key,
        candidate_ids: rows.map((row) => row.candidate_id),
      });
      continue;
    }
    for (const decision of rows) {
      if (!decisionHasBoundOccurrence(candidate, key, terms, decision)) {
        report.evidence_binding_issue_count += 1;
        violation(report, 'addition_not_bound_to_decision_evidence', {
          file_name: fileName,
          target: key,
          candidate_id: decision.candidate_id,
        });
      }
      const expectedOccurrences = normalizedDecisionOccurrences(decision);
      if (expectedOccurrences !== null) {
        const actualOccurrences = normalizedTermOccurrences(terms);
        if (stableJson(actualOccurrences) !== stableJson(expectedOccurrences)) {
          report.decision_occurrence_mismatch_count += 1;
          violation(report, 'decision_occurrence_mismatch', {
            file_name: fileName,
            target: key,
            candidate_id: decision.candidate_id,
            expected_occurrences: expectedOccurrences,
            actual_occurrences: actualOccurrences,
          });
        }
      }
    }
  }

  const baselineSourceIssues = sourceOccurrenceIssues(baseline);
  const candidateSourceIssues = sourceOccurrenceIssues(candidate);
  report.baseline_source_occurrence_issue_count += baselineSourceIssues.length;
  report.candidate_source_occurrence_issue_count += candidateSourceIssues.length;
  const baselineIssueKeys = new Set(baselineSourceIssues.map(stableJson));
  for (const issue of candidateSourceIssues) {
    if (baselineIssueKeys.has(stableJson(issue))) continue;
    report.source_occurrence_issue_count += 1;
    violation(report, 'source_occurrence_issue', { file_name: fileName, ...issue });
  }
}

function normalizedDecisionOccurrences(decision) {
  if (!Object.hasOwn(decision ?? {}, 'final_occurrences')) return null;
  return [...new Set((decision?.final_occurrences ?? []).map((row) => {
    const frameIndex = Number(row?.frame_index);
    const sourceLocation = normalizeSourceLocation(row?.source_location);
    return Number.isInteger(frameIndex) && sourceLocation
      ? `${frameIndex}\u001f${sourceLocation}`
      : '';
  }).filter(Boolean))].sort();
}

function normalizedTermOccurrences(terms) {
  return [...new Set((terms ?? []).flatMap((term) =>
    (term?.source_occurrences ?? []).map((row) => {
      const frameIndex = Number(row?.frame_index);
      const sourceLocation = normalizeSourceLocation(row?.source_location);
      return Number.isInteger(frameIndex) && sourceLocation
        ? `${frameIndex}\u001f${sourceLocation}`
        : '';
    }),
  ).filter(Boolean))].sort();
}

function allowedChanges(decisions) {
  const additions = new Map();
  const removals = new Map();
  for (const decision of decisions) {
    const outcome = outcomeOf(decision);
    if (removeOutcomes.has(outcome)) {
      for (const key of removalTargetKeys(decision)) pushMap(removals, key, decision);
    }
    if (addOutcomes.has(outcome)) {
      for (const key of additionTargetKeys(decision)) pushMap(additions, key, decision);
    }
  }
  return { additions, removals };
}

function removalTargetKeys(decision) {
  // Use the same scope resolution as the applicator. Legacy candidates can
  // aggregate same-term occurrences from several roles, while their declared
  // inspection scope authorizes removal from only one role/category target.
  return new Set(currentPendingTargetKeys(decision));
}

function additionTargetKeys(decision) {
  return new Set(finalPendingTargetKeys(decision));
}

function membershipInventory(cache) {
  const result = new Map();
  for (const role of cache?.aiRoleExtraction?.roles ?? []) {
    const roleId = String(role?.source_role_id ?? '').trim().toLowerCase();
    for (const term of role?.prompt_terms ?? []) {
      const key = targetKey('role', roleId, String(term?.category ?? ''), term?.text);
      pushMap(result, key, canonicalTerm(term));
    }
  }
  for (const term of cache?.aiRoleExtraction?.scene_terms ?? []) {
    const key = targetKey('scene', '', String(term?.category ?? 'scene'), term?.text);
    pushMap(result, key, canonicalTerm(term));
  }
  for (const rows of result.values()) rows.sort((left, right) => stableJson(left).localeCompare(stableJson(right)));
  return result;
}

function canonicalTerm(term) {
  return JSON.parse(JSON.stringify(term));
}

function decisionHasBoundOccurrence(cache, key, terms, decision) {
  const parsed = parseTargetKey(key);
  const role = parsed.scope === 'role'
    ? (cache?.aiRoleExtraction?.roles ?? []).find(
        (item) => String(item?.source_role_id ?? '').toLowerCase() === parsed.owner,
      )
    : null;
  const stageFrames = role ? requestedRoleFrames(role, decision?.final_stage_ids ?? []) : null;
  if (role && stageFrames && stageFrames.size === 0) return false;
  return terms.some((term) =>
    (term?.source_occurrences ?? []).some((occurrence) => {
      const frameIndex = Number(occurrence?.frame_index);
      const sourceLocation = normalizeSourceLocation(occurrence?.source_location);
      if (!Number.isInteger(frameIndex) || !sourceLocation) return false;
      if (stageFrames && !stageFrames.has(frameIndex)) return false;
      if (role && !allowedRoleSources(role, frameIndex).has(sourceLocation)) return false;
      const caption = captionAt(cache, frameIndex, sourceLocation);
      if (!caption) return false;
      return evidenceMatches(decision, frameIndex, sourceLocation, caption);
    }),
  );
}

function evidenceMatches(decision, frameIndex, sourceLocation, caption) {
  const surfaces = new Set([normalizeMembershipKey(decision?.term)]);
  const summary = decision?.raw_occurrence_summary ?? {};
  const physical = [
    ...(summary?.representative_exact ?? []),
    ...(summary?.representative_containing ?? []),
  ];
  for (const row of physical) {
    const surface = String(row?.matched_atom ?? '');
    if (surface) surfaces.add(normalizeMembershipKey(surface));
    if (
      Number(row?.frame_index) === frameIndex &&
      normalizeSourceLocation(row?.source_location) === sourceLocation &&
      surface &&
      caption.includes(surface)
    ) return true;
  }
  for (const row of decision?.final_evidence ?? decision?.evidence ?? []) {
    const excerpt = String(row?.verbatim_prompt_excerpt ?? '');
    if (
      Number(row?.frame_index) === frameIndex &&
      normalizeSourceLocation(row?.source_location) === sourceLocation &&
      excerpt &&
      caption.includes(excerpt)
    ) return true;
  }
  return splitContextualPromptAtoms(caption).some((atom) =>
    surfaces.has(normalizeMembershipKey(atom)),
  );
}

function sourceOccurrenceIssues(cache) {
  const issues = [];
  const rows = [];
  for (const role of cache?.aiRoleExtraction?.roles ?? []) {
    for (const term of role?.prompt_terms ?? []) rows.push({ role, term, scope: role?.source_role_id });
  }
  for (const term of cache?.aiRoleExtraction?.scene_terms ?? []) rows.push({ role: null, term, scope: 'scene' });
  for (const { role, term, scope } of rows) {
    const seen = new Set();
    const frames = [];
    for (const occurrence of term?.source_occurrences ?? []) {
      const frameIndex = Number(occurrence?.frame_index);
      const sourceLocation = normalizeSourceLocation(occurrence?.source_location);
      const occurrenceKey = `${frameIndex}\u001f${sourceLocation}`;
      if (!Number.isInteger(frameIndex) || !sourceLocation || seen.has(occurrenceKey)) {
        issues.push({ scope, term: term?.text, issue: 'invalid_or_duplicate_occurrence' });
        continue;
      }
      seen.add(occurrenceKey);
      frames.push(frameIndex);
      if (!captionExists(cache, frameIndex, sourceLocation)) {
        issues.push({ scope, term: term?.text, issue: 'occurrence_source_missing', frame_index: frameIndex, source_location: sourceLocation });
      } else if (role && !allowedRoleSources(role, frameIndex).has(sourceLocation)) {
        issues.push({ scope, term: term?.text, issue: 'occurrence_outside_role_source', frame_index: frameIndex, source_location: sourceLocation });
      }
    }
    const actualFrames = [...new Set(frames)].sort((a, b) => a - b);
    const declaredFrames = [...new Set((term?.frame_indexes ?? []).map(Number).filter(Number.isInteger))].sort((a, b) => a - b);
    if (JSON.stringify(actualFrames) !== JSON.stringify(declaredFrames)) {
      issues.push({ scope, term: term?.text, issue: 'frame_occurrence_mismatch' });
    }
  }
  return issues;
}

function requestedRoleFrames(role, stageIds) {
  const requested = new Set((stageIds ?? []).map(normalizeContextualStageId).filter(Boolean));
  if (requested.size === 0) return null;
  const frames = (role?.stages ?? [])
    .filter((stage) => requested.has(normalizeContextualStageId(stage?.stage_id)))
    .flatMap((stage) => stage?.frame_indexes ?? [])
    .map(Number)
    .filter(Number.isInteger);
  return new Set(frames);
}

function allowedRoleSources(role, frameIndex) {
  const result = new Set(['base prompt']);
  for (const appearance of role?.appearances ?? []) {
    if (!(appearance?.frame_indexes ?? []).map(Number).includes(frameIndex)) continue;
    const sourceId = String(appearance?.source_id ?? '').trim();
    if (/^slot-\d+$/.test(sourceId)) result.add(`${sourceId} prompt`);
    if (sourceId === 'base') result.add('base prompt');
  }
  return result;
}

function captionAt(cache, frameIndex, sourceLocation) {
  const frame = (cache?.scriptSnapshot?.frames ?? []).find(
    (item) => Number(item?.index) === frameIndex,
  );
  if (!frame) return '';
  if (sourceLocation === 'base prompt') return String(frame?.parsed?.baseCaption ?? '');
  const match = /^slot-(\d+) prompt$/.exec(sourceLocation);
  return match ? String(frame?.parsed?.charCaptions?.[Number(match[1])] ?? '') : '';
}

function captionExists(cache, frameIndex, sourceLocation) {
  const frame = (cache?.scriptSnapshot?.frames ?? []).find(
    (item) => Number(item?.index) === frameIndex,
  );
  if (!frame) return false;
  if (sourceLocation === 'base prompt') return typeof frame?.parsed?.baseCaption === 'string';
  const match = /^slot-(\d+) prompt$/.exec(sourceLocation);
  return Boolean(match && typeof frame?.parsed?.charCaptions?.[Number(match[1])] === 'string');
}

function stripMembershipSurfaces(value) {
  const copy = JSON.parse(JSON.stringify(value));
  if (copy?.aiRoleExtraction) {
    delete copy.aiRoleExtraction.scene_terms;
    for (const role of copy.aiRoleExtraction.roles ?? []) delete role.prompt_terms;
  }
  if (copy?.mapping) {
    delete copy.mapping.rolePromptReplacements;
    delete copy.mapping.scenePromptReplacements;
  }
  return copy;
}

function targetKey(scope, owner, category, term) {
  const termKey = normalizeMembershipKey(term);
  return scope === 'scene'
    ? ['scene', category || 'scene', termKey].join('\u001f')
    : ['role', String(owner).toLowerCase(), category, termKey].join('\u001f');
}

function parseTargetKey(key) {
  const parts = key.split('\u001f');
  return parts[0] === 'scene'
    ? { scope: 'scene', owner: 'scene', category: parts[1], term: parts[2] }
    : { scope: 'role', owner: parts[1], category: parts[2], term: parts[3] };
}

function roleIds(decision) {
  return [...String(decision?.final_role ?? '').matchAll(/role-[a-z0-9-]+/gi)]
    .map((match) => match[0].toLowerCase())
    .filter((value, index, values) => values.indexOf(value) === index);
}

function normalizeSourceLocation(value) {
  const text = String(value ?? '').trim();
  if (/^base prompt(?:\s+\([^)]*\))?$/.test(text)) return 'base prompt';
  const match = /^(slot-\d+) prompt(?:\s+\([^)]*\))?$/.exec(text);
  return match ? `${match[1]} prompt` : '';
}

function groupDecisions(decisions) {
  const result = new Map();
  for (const decision of decisions) {
    const fileName = path.basename(String(decision?.file_name ?? ''));
    pushMap(result, fileName, decision);
  }
  return result;
}

function loadJsonl(file) {
  const ids = new Set();
  return fs
    .readFileSync(file, 'utf8')
    .split(/\r?\n/)
    .filter((line) => line.trim())
    .map((line, index) => {
      const row = JSON.parse(line);
      const id = String(row?.candidate_id ?? '').trim();
      if (!id || ids.has(id)) throw new Error(`${file}:${index + 1}: invalid/duplicate candidate_id`);
      ids.add(id);
      return row;
    });
}

function jsonFiles(directory) {
  return fs.readdirSync(directory).filter((name) => name.toLowerCase().endsWith('.json')).sort();
}

function pushMap(map, key, value) {
  const rows = map.get(key) ?? [];
  rows.push(value);
  map.set(key, rows);
}

function violation(report, kind, fields) {
  report.violations.push({ kind, ...fields });
}

function outcomeOf(decision) {
  return String(decision?.final_outcome ?? decision?.outcome ?? '').trim();
}

function stableJson(value) {
  return JSON.stringify(sortObject(value));
}

function sortObject(value) {
  if (Array.isArray(value)) return value.map(sortObject);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(
    Object.keys(value).sort().map((key) => [key, sortObject(value[key])]),
  );
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function assertDirectory(value, label) {
  if (!fs.existsSync(value) || !fs.statSync(value).isDirectory()) throw new Error(`missing ${label}: ${value}`);
}

function assertRegularFile(value, label) {
  if (!fs.existsSync(value) || !fs.statSync(value).isFile()) throw new Error(`missing ${label}: ${value}`);
}

function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

function parseArgs(args) {
  const result = {};
  for (let index = 0; index < args.length; index += 2) {
    const key = args[index];
    const value = args[index + 1];
    if (!value) throw new Error(`missing value for ${key}`);
    if (key === '--baseline-dir') result.baselineDir = path.resolve(value);
    else if (key === '--cache-dir') result.cacheDir = path.resolve(value);
    else if (key === '--decisions') result.decisionsFile = path.resolve(value);
    else if (key === '--expected-count') result.expectedCount = Number(value);
    else if (key === '--report') result.report = path.resolve(value);
    else throw new Error(`unknown argument ${key}`);
  }
  if (!result.baselineDir || !result.cacheDir || !result.decisionsFile || !result.report || !Number.isInteger(result.expectedCount)) {
    throw new Error('Usage: node validate_script_recast_contextual_membership.mjs --baseline-dir <dir> --cache-dir <dir> --decisions <jsonl> --expected-count <n> --report <json>');
  }
  return result;
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  let options;
  try {
    options = parseArgs(process.argv.slice(2));
    const report = validateContextualMembership(options);
    fs.mkdirSync(path.dirname(options.report), { recursive: true });
    fs.writeFileSync(options.report, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    if (!report.complete) process.exitCode = 1;
  } catch (error) {
    process.stderr.write(`${errorMessage(error)}\n`);
    process.exitCode = 1;
  }
}
