import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { buildContextualPromotionAcceptance } from '../../tool/build_script_recast_contextual_promotion_acceptance.mjs';

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'contextual-acceptance-'));
try {
  const baselineDir = directory('baseline');
  const cacheDir = directory('cache');
  const peerCacheDir = directory('peer');
  for (const dir of [baselineDir, cacheDir, peerCacheDir]) {
    write(path.join(dir, 'script-a.json'), { scriptId: 'a' });
  }
  const decisionsFile = file('decisions.jsonl');
  fs.writeFileSync(
    decisionsFile,
    `${JSON.stringify({ candidate_id: 'cand-a', file_name: 'script-a.json', final_outcome: 'KEEP_CURRENT' })}\n`,
  );
  const adjudicationReport = json('adjudication.json', {
    kind: 'script_recast_context_corrected_adjudication',
    api_used: false,
    candidate_count: 1,
    correction_count: 0,
    complete: true,
  });
  const anomalyReport = json('anomaly.json', {
    api_used: false,
    complete: true,
    reviewed_count: 1,
    correction_count: 0,
    errors: [],
  });
  const applicationReportA = json('application-a.json', application(cacheDir));
  const applicationReportB = json('application-b.json', application(peerCacheDir));
  const preflightReport = json('preflight.json', {
    kind: 'script_recast_contextual_decision_preflight',
    api_used: false,
    status: 'ok',
    issue_count: 0,
    issues: [],
    decision_count: 1,
    mutating_decision_count: 0,
    cache_dir: baselineDir,
    decisions_file: decisionsFile,
  });
  const validationReportA = json('validation-a.json', validation(cacheDir));
  const validationReportB = json('validation-b.json', validation(peerCacheDir));
  const frameReport = json('frame.json', {
    cache_dir: cacheDir,
    cache_count: 1,
    mixed_stage_issue_count: 0,
    label_state_issue_count: 0,
    field_source_issue_count: 0,
    ui_label_issue_count: 0,
  });
  const integrityReport = json('integrity.json', {
    cache_dir: cacheDir,
    cache_count: 1,
    ready_count: 1,
    total_frames: 1,
    parsed_frames: 1,
    png_metadata_missing_frames: 0,
    source_frame_mismatch_count: 0,
    role_identity_issue_count: 0,
    role_frame_reference_issue_count: 0,
  });
  const coverageReport = json('coverage.json', {
    api_used: false,
    read_only: true,
    cache_dir: cacheDir,
    source_coverage_reviewed: true,
    checks: { all: true },
    violations: [],
    errors: [],
    uncached_png_without_prompt_metadata_review: {
      status: 'reviewed_unrecoverable_without_metadata',
      count: 0,
    },
  });

  const options = {
    cacheDir,
    peerCacheDir,
    baselineDir,
    applicationReportA,
    applicationReportB,
    preflightReport,
    validationReportA,
    validationReportB,
    frameReport,
    integrityReport,
    coverageReport,
    decisionsFile,
    adjudicationReport,
    anomalyReports: [anomalyReport],
    expectedCount: 1,
  };
  const acceptance = buildContextualPromotionAcceptance(options);
  assert.equal(acceptance.kind, 'script_recast_promotion_acceptance');
  assert.equal(acceptance.api_used, false);
  assert.equal(acceptance.cache_files.length, 1);
  assert.ok(Object.values(acceptance.checks).every((value) => value === true));

  const incompleteBoundedAnomaly = json('anomaly-bounded-incomplete.json', {
    api_used: false,
    bounded_scope_complete: true,
    structural_coverage: 0,
    target_count: 1,
    errors: [],
  });
  assert.throws(
    () =>
      buildContextualPromotionAcceptance({
        ...options,
        anomalyReports: [incompleteBoundedAnomaly],
      }),
    /anomaly report incomplete/,
    'bounded anomaly reviews must prove non-empty structural coverage',
  );

  const completeBoundedAnomaly = json('anomaly-bounded-complete.json', {
    api_used: false,
    bounded_scope_complete: true,
    structural_coverage: 1,
    target_count: 1,
    errors: [],
  });
  assert.equal(
    buildContextualPromotionAcceptance({
      ...options,
      anomalyReports: [completeBoundedAnomaly],
    }).checks.term_review_complete,
    true,
  );

  write(path.join(peerCacheDir, 'script-a.json'), { scriptId: 'changed' });
  assert.throws(
    () => buildContextualPromotionAcceptance(options),
    /determinism mismatch/,
  );

  function application(outputDir) {
    return {
      kind: 'script_recast_contextual_membership_application',
      api_used: false,
      apply: true,
      status: 'ok',
      errors: [],
      cache_dir: baselineDir,
      output_dir: outputDir,
      decision_files: [decisionsFile],
      files_scanned: 1,
      files_changed: 0,
      mutating_decision_count: 0,
    };
  }

  function validation(targetDir) {
    return {
      kind: 'script_recast_contextual_membership_validation',
      api_used: false,
      read_only: true,
      complete: true,
      violation_count: 0,
      violations: [],
      files_scanned: 1,
      mutating_decision_count: 0,
      non_membership_change_count: 0,
      baseline_dir: baselineDir,
      cache_dir: targetDir,
      decisions_file: decisionsFile,
    };
  }

  function directory(name) {
    const value = path.join(root, name);
    fs.mkdirSync(value);
    return value;
  }

  function file(name) {
    return path.join(root, name);
  }

  function json(name, value) {
    const target = file(name);
    write(target, value);
    return target;
  }

  function write(target, value) {
    fs.writeFileSync(target, `${JSON.stringify(value, null, 2)}\n`);
  }
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}

process.stdout.write('contextual promotion acceptance regression: ok\n');
