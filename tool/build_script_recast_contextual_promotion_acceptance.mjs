#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

export function buildContextualPromotionAcceptance(options) {
  const expectedCount = Number(options.expectedCount);
  if (!Number.isInteger(expectedCount) || expectedCount <= 0) throw new Error('expectedCount must be positive');
  const cache = inventory(options.cacheDir, 'candidate cache');
  const peer = inventory(options.peerCacheDir, 'peer cache');
  const baseline = inventory(options.baselineDir, 'frozen baseline');
  assertCount(cache, expectedCount, 'candidate cache');
  assertCount(peer, expectedCount, 'peer cache');
  assertCount(baseline, expectedCount, 'frozen baseline');
  assertSameInventory(cache, peer, 'candidate/peer determinism');
  assertSameNames(cache, baseline, 'candidate/baseline scope');

  const decisions = loadJsonl(options.decisionsFile);
  const adjudication = readJson(options.adjudicationReport, 'adjudication report');
  require(adjudication.api_used === false, 'adjudication report must declare api_used=false');
  require(adjudication.complete === true, 'adjudication report is incomplete');
  require(Number(adjudication.candidate_count) === decisions.length, 'adjudication decision count mismatch');

  const anomalyReports = (options.anomalyReports ?? []).map((file) => ({
    file: path.resolve(file),
    value: readJson(file, 'anomaly report'),
  }));
  require(anomalyReports.length > 0, 'at least one anomaly report is required');
  for (const row of anomalyReports) validateAnomalyReport(row.value, row.file);

  const applicationA = validateApplicationReport(
    readJson(options.applicationReportA, 'application report A'),
    options,
    options.cacheDir,
    expectedCount,
    'A',
  );
  const applicationB = validateApplicationReport(
    readJson(options.applicationReportB, 'application report B'),
    options,
    options.peerCacheDir,
    expectedCount,
    'B',
  );
  const preflight = validatePreflight(
    readJson(options.preflightReport, 'preflight report'),
    options,
    decisions.length,
  );
  const validationA = validateContextualValidation(
    readJson(options.validationReportA, 'contextual validation A'),
    options,
    options.cacheDir,
    expectedCount,
    'A',
  );
  const validationB = validateContextualValidation(
    readJson(options.validationReportB, 'contextual validation B'),
    options,
    options.peerCacheDir,
    expectedCount,
    'B',
  );
  const frame = validateFrameReport(readJson(options.frameReport, 'frame report'), options.cacheDir, expectedCount);
  const integrity = validateIntegrityReport(readJson(options.integrityReport, 'integrity report'), options.cacheDir, expectedCount);
  const coverage = validateCoverageReport(readJson(options.coverageReport, 'coverage report'), options.cacheDir);

  const checks = {
    term_review_complete:
      adjudication.complete === true &&
      anomalyReports.every((row) => anomalyComplete(row.value)) &&
      preflight.complete,
    mapping_safety_complete: validationA.complete && validationB.complete,
    frame_semantics_complete: frame.complete,
    role_field_semantics_complete:
      validationA.complete &&
      validationB.complete &&
      validationA.nonMembershipChanges === 0 &&
      validationB.nonMembershipChanges === 0,
    cache_integrity_complete: integrity.complete,
    source_coverage_reviewed: coverage.complete,
    determinism: true,
  };
  for (const [name, value] of Object.entries(checks)) require(value === true, `acceptance gate failed: ${name}`);

  return {
    kind: 'script_recast_promotion_acceptance',
    schema_version: 1,
    api_used: false,
    cache_dir: path.resolve(options.cacheDir),
    cache_files: cache.rows.map(({ file_name, sha256 }) => ({ file_name, sha256 })),
    removed_cache_files: [],
    aggregate_sha256: aggregateHash(cache.rows),
    cache_files_aggregate_sha256: aggregateHash(cache.rows),
    checks,
    evidence: {
      workflow: 'contextual_membership_blind_reaudit',
      decisions: evidenceFile(options.decisionsFile, { decision_count: decisions.length }),
      adjudication_report: evidenceFile(options.adjudicationReport, {
        candidate_count: adjudication.candidate_count,
        correction_count: adjudication.correction_count,
        complete: adjudication.complete,
      }),
      anomaly_reports: anomalyReports.map((row) => evidenceFile(row.file, anomalySummary(row.value))),
      application_report_a: evidenceFile(options.applicationReportA, applicationA),
      application_report_b: evidenceFile(options.applicationReportB, applicationB),
      preflight_report: evidenceFile(options.preflightReport, preflight),
      contextual_validation_a: evidenceFile(options.validationReportA, validationA),
      contextual_validation_b: evidenceFile(options.validationReportB, validationB),
      frame_report: evidenceFile(options.frameReport, frame),
      integrity_report: evidenceFile(options.integrityReport, integrity),
      coverage_report: evidenceFile(options.coverageReport, coverage),
      candidate_inventory: {
        cache_dir: path.resolve(options.cacheDir),
        file_count: cache.rows.length,
        aggregate_sha256: aggregateHash(cache.rows),
      },
      peer_inventory: {
        cache_dir: path.resolve(options.peerCacheDir),
        file_count: peer.rows.length,
        aggregate_sha256: aggregateHash(peer.rows),
      },
      baseline_inventory: {
        cache_dir: path.resolve(options.baselineDir),
        file_count: baseline.rows.length,
        aggregate_sha256: aggregateHash(baseline.rows),
      },
    },
  };
}

function validateApplicationReport(report, options, outputDir, expectedCount, side) {
  require(report?.kind === 'script_recast_contextual_membership_application', `application ${side} kind mismatch`);
  require(report.api_used === false, `application ${side} must declare api_used=false`);
  require(report.apply === true, `application ${side} was not applied`);
  require(report.status === 'ok', `application ${side} did not finish successfully`);
  require(Array.isArray(report.errors) && report.errors.length === 0, `application ${side} has errors`);
  require(samePath(report.cache_dir, options.baselineDir), `application ${side} baseline binding mismatch`);
  require(samePath(report.output_dir, outputDir), `application ${side} output binding mismatch`);
  require(Number(report.files_scanned) === expectedCount, `application ${side} file count mismatch`);
  require(
    (report.decision_files ?? []).some((file) => samePath(file, options.decisionsFile)),
    `application ${side} decisions binding mismatch`,
  );
  return {
    status: report.status,
    files_scanned: report.files_scanned,
    files_changed: report.files_changed,
    mutating_decision_count: report.mutating_decision_count,
  };
}

function validatePreflight(report, options, decisionCount) {
  require(report?.kind === 'script_recast_contextual_decision_preflight', 'preflight kind mismatch');
  require(report.api_used === false, 'preflight must declare api_used=false');
  require(report.status === 'ok', 'preflight status is not ok');
  require(Number(report.issue_count) === 0, 'preflight has issues');
  require(Array.isArray(report.issues) && report.issues.length === 0, 'preflight issue rows are not empty');
  require(Number(report.decision_count) === decisionCount, 'preflight decision count mismatch');
  require(samePath(report.cache_dir, options.baselineDir), 'preflight baseline binding mismatch');
  require(samePath(report.decisions_file, options.decisionsFile), 'preflight decisions binding mismatch');
  return {
    complete: true,
    status: report.status,
    decision_count: report.decision_count,
    mutating_decision_count: report.mutating_decision_count,
    issue_count: report.issue_count,
  };
}

function validateContextualValidation(report, options, cacheDir, expectedCount, side) {
  require(report?.kind === 'script_recast_contextual_membership_validation', `validation ${side} kind mismatch`);
  require(report.api_used === false && report.read_only === true, `validation ${side} offline/read-only contract failed`);
  require(report.complete === true, `validation ${side} incomplete`);
  require(Number(report.violation_count) === 0, `validation ${side} has violations`);
  require(Array.isArray(report.violations) && report.violations.length === 0, `validation ${side} violation rows are not empty`);
  require(Number(report.files_scanned) === expectedCount, `validation ${side} file count mismatch`);
  require(samePath(report.baseline_dir, options.baselineDir), `validation ${side} baseline binding mismatch`);
  require(samePath(report.cache_dir, cacheDir), `validation ${side} cache binding mismatch`);
  require(samePath(report.decisions_file, options.decisionsFile), `validation ${side} decisions binding mismatch`);
  return {
    complete: true,
    files_scanned: report.files_scanned,
    mutating_decision_count: report.mutating_decision_count,
    violation_count: report.violation_count,
    nonMembershipChanges: Number(report.non_membership_change_count),
  };
}

function validateFrameReport(report, cacheDir, expectedCount) {
  require(samePath(report.cache_dir, cacheDir), 'frame report cache binding mismatch');
  if (report.cache_count != null) require(Number(report.cache_count) === expectedCount, 'frame report cache count mismatch');
  const fields = ['mixed_stage_issue_count', 'label_state_issue_count', 'field_source_issue_count', 'ui_label_issue_count'];
  for (const field of fields) require(Number(report[field]) === 0, `frame report ${field} must be zero`);
  return { complete: true, cache_count: report.cache_count, ...Object.fromEntries(fields.map((field) => [field, report[field]])) };
}

function validateIntegrityReport(report, cacheDir, expectedCount) {
  require(samePath(report.cache_dir, cacheDir), 'integrity report cache binding mismatch');
  require(Number(report.cache_count) === expectedCount, 'integrity cache count mismatch');
  require(Number(report.ready_count) === expectedCount, 'integrity ready count mismatch');
  require(Number(report.total_frames) === Number(report.parsed_frames), 'integrity parsed frame mismatch');
  for (const field of ['png_metadata_missing_frames', 'source_frame_mismatch_count', 'role_identity_issue_count', 'role_frame_reference_issue_count']) {
    require(Number(report[field]) === 0, `integrity ${field} must be zero`);
  }
  return {
    complete: true,
    cache_count: report.cache_count,
    ready_count: report.ready_count,
    total_frames: report.total_frames,
    parsed_frames: report.parsed_frames,
    png_metadata_missing_frames: report.png_metadata_missing_frames,
    source_frame_mismatch_count: report.source_frame_mismatch_count,
    role_identity_issue_count: report.role_identity_issue_count,
    role_frame_reference_issue_count: report.role_frame_reference_issue_count,
  };
}

function validateCoverageReport(report, cacheDir) {
  require(report.api_used === false && report.read_only === true, 'coverage offline/read-only contract failed');
  require(samePath(report.cache_dir, cacheDir), 'coverage cache binding mismatch');
  require(report.source_coverage_reviewed === true, 'coverage is not reviewed');
  require(Array.isArray(report.violations) && report.violations.length === 0, 'coverage has violations');
  require(Array.isArray(report.errors) && report.errors.length === 0, 'coverage has errors');
  require(report.checks && Object.values(report.checks).every((value) => value === true), 'coverage checks are incomplete');
  const review = report.uncached_png_without_prompt_metadata_review;
  require(review?.status === 'reviewed_unrecoverable_without_metadata', 'coverage unrecoverable review missing');
  return {
    complete: true,
    source_coverage_reviewed: true,
    unrecoverable_without_metadata_count: review.count,
    checks_true_count: Object.keys(report.checks).length,
  };
}

function validateAnomalyReport(report, file) {
  require(report?.api_used === false, `anomaly report must declare api_used=false: ${file}`);
  require(anomalyComplete(report), `anomaly report incomplete: ${file}`);
  if (Array.isArray(report.errors)) require(report.errors.length === 0, `anomaly report has errors: ${file}`);
  if (report.error_count != null) require(Number(report.error_count) === 0, `anomaly report error_count is nonzero: ${file}`);
}

function anomalyComplete(report) {
  const focusedComplete =
    report?.completeness?.focused_scope_complete === true &&
    Number(report?.manually_reviewed_count ?? report?.reviewed_count) ===
      Number(report?.risk_enumeration_count ?? report?.target_count);
  const structuralCoverage = Number(
    report?.structurally_verified_count ?? report?.structural_coverage,
  );
  const structuralTarget = Number(
    report?.structural_target_count ?? report?.target_count ?? report?.removal_end_count,
  );
  const boundedComplete =
    report?.bounded_scope_complete === true &&
    Number.isInteger(structuralCoverage) &&
    structuralCoverage > 0 &&
    (!Number.isFinite(structuralTarget) || structuralCoverage === structuralTarget);
  return (
    report?.complete === true ||
    focusedComplete ||
    boundedComplete ||
    ['ok', 'complete', 'completed', 'complete_focused_scope'].includes(
      String(report?.status ?? '').toLowerCase(),
    )
  );
}

function anomalySummary(report) {
  return {
    complete: anomalyComplete(report),
    status: report?.status,
    enumerated_count: report?.enumerated_count ?? report?.target_count ?? report?.candidate_count,
    reviewed_count: report?.reviewed_count ?? report?.manually_reviewed_count ?? report?.verified_count,
    correction_count: report?.correction_count ?? report?.anomaly_count,
  };
}

function inventory(directory, label) {
  const resolved = path.resolve(directory);
  require(fs.existsSync(resolved) && fs.statSync(resolved).isDirectory(), `missing ${label}: ${resolved}`);
  const entries = fs.readdirSync(resolved, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
  const rows = entries.map((entry) => {
    require(entry.isFile() && !entry.isSymbolicLink() && entry.name.toLowerCase().endsWith('.json'), `${label} contains unsupported entry: ${entry.name}`);
    const file = path.join(resolved, entry.name);
    JSON.parse(fs.readFileSync(file, 'utf8'));
    return { file_name: entry.name, sha256: sha256(fs.readFileSync(file)) };
  });
  return { directory: resolved, rows };
}

function assertCount(inventoryValue, count, label) {
  require(inventoryValue.rows.length === count, `${label} expected ${count}, found ${inventoryValue.rows.length}`);
}

function assertSameInventory(left, right, label) {
  require(stableJson(left.rows) === stableJson(right.rows), `${label} mismatch`);
}

function assertSameNames(left, right, label) {
  require(
    stableJson(left.rows.map((row) => row.file_name)) === stableJson(right.rows.map((row) => row.file_name)),
    `${label} filename mismatch`,
  );
}

function aggregateHash(rows) {
  return sha256(Buffer.from(rows.map((row) => `${row.file_name}\u0000${row.sha256}\n`).join(''), 'utf8'));
}

function evidenceFile(file, counts) {
  const resolved = path.resolve(file);
  return { file: resolved, sha256: sha256(fs.readFileSync(resolved)), counts };
}

function readJson(file, label) {
  const resolved = path.resolve(file);
  require(fs.existsSync(resolved) && fs.statSync(resolved).isFile(), `missing ${label}: ${resolved}`);
  return JSON.parse(fs.readFileSync(resolved, 'utf8'));
}

function loadJsonl(file) {
  const resolved = path.resolve(file);
  return fs.readFileSync(resolved, 'utf8').split(/\r?\n/).filter((line) => line.trim()).map(JSON.parse);
}

function samePath(left, right) {
  return typeof left === 'string' && path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
}

function stableJson(value) {
  return JSON.stringify(value);
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function require(condition, message) {
  if (!condition) throw new Error(message);
}

function parseArgs(args) {
  const values = {};
  const anomalyReports = [];
  for (let index = 0; index < args.length; index += 2) {
    const key = args[index];
    const value = args[index + 1];
    if (!value) throw new Error(`missing value for ${key}`);
    if (key === '--anomaly-report') anomalyReports.push(path.resolve(value));
    else values[key] = value;
  }
  const mapped = {
    cacheDir: values['--cache-dir'],
    peerCacheDir: values['--peer-cache-dir'],
    baselineDir: values['--baseline-dir'],
    applicationReportA: values['--application-report-a'],
    applicationReportB: values['--application-report-b'],
    preflightReport: values['--preflight-report'],
    validationReportA: values['--validation-report-a'],
    validationReportB: values['--validation-report-b'],
    frameReport: values['--frame-report'],
    integrityReport: values['--integrity-report'],
    coverageReport: values['--coverage-report'],
    decisionsFile: values['--decisions'],
    adjudicationReport: values['--adjudication-report'],
    expectedCount: Number(values['--expected-count']),
    output: values['--output'],
    anomalyReports,
  };
  for (const [key, value] of Object.entries(mapped)) {
    if (key === 'anomalyReports') continue;
    if (value == null || value === '' || (key === 'expectedCount' && !Number.isInteger(value))) throw new Error(`required argument missing for ${key}`);
  }
  return mapped;
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  try {
    const options = parseArgs(process.argv.slice(2));
    const acceptance = buildContextualPromotionAcceptance(options);
    fs.mkdirSync(path.dirname(path.resolve(options.output)), { recursive: true });
    fs.writeFileSync(path.resolve(options.output), `${JSON.stringify(acceptance, null, 2)}\n`, 'utf8');
    process.stdout.write(`${JSON.stringify(acceptance, null, 2)}\n`);
  } catch (error) {
    process.stderr.write(`Contextual promotion acceptance failed closed: ${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  }
}
