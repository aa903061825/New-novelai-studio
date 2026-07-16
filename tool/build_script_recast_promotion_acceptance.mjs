import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';

let options;

try {
  options = parseArgs(process.argv.slice(2));
  const acceptance = buildAcceptance(options);
  writeJson(options.output, acceptance);
  process.stdout.write(`${JSON.stringify(acceptance, null, 2)}\n`);
} catch (error) {
  process.stderr.write(
    `Script Recast promotion acceptance failed closed: ${errorMessage(error)}\n`,
  );
  process.exitCode = 1;
}

function buildAcceptance(currentOptions) {
  const inputReports = readInputReports(currentOptions);
  const cache = inventoryDirectory(currentOptions.cacheDir, 'final cache A');
  const peerCache = inventoryDirectory(
    currentOptions.peerCacheDir,
    'final cache B',
  );
  const baseline = inventoryDirectory(
    currentOptions.baselineDir,
    'active baseline cache',
  );

  assertOutputPathSafe(currentOptions.output, currentOptions, inputReports);
  assertExpectedCount(cache, currentOptions.expectedCount, 'final cache A');
  assertExpectedCount(
    peerCache,
    currentOptions.expectedCount,
    'final cache B',
  );
  assertSameInventory(cache, peerCache, 'final cache A/B');

  const removeNames = currentOptions.removeFiles.slice().sort(compareText);
  const expectedBaselineCount =
    currentOptions.expectedCount + removeNames.length;
  assertExpectedCount(
    baseline,
    expectedBaselineCount,
    'active baseline cache',
  );
  const removed = validateBaselineSet(baseline, cache, removeNames);

  const buildA = validateBuildReport(
    inputReports.buildReportA,
    currentOptions,
    removeNames,
    'A',
  );
  const buildB = validateBuildReport(
    inputReports.buildReportB,
    currentOptions,
    removeNames,
    'B',
  );
  assertBuildOutputMatchesFinal(buildA.output, cache, removeNames, 'A');
  assertBuildOutputMatchesFinal(buildB.output, peerCache, removeNames, 'B');

  const sourceRoots = inspectFinalSourceRoots(cache, currentOptions);
  const removedSourceChecks = inspectRemovedSources(removed);

  const mapping = validateMappingReport(
    inputReports.mappingReport,
    currentOptions,
  );
  const frame = validateFrameReport(inputReports.frameReport, currentOptions);
  const integrity = validateIntegrityReport(
    inputReports.integrityReport,
    currentOptions,
  );
  const coverage = validateCoverageReport(
    inputReports.coverageReport,
    currentOptions,
  );
  const termReview = validateTermReview(inputReports.termReview);

  const cacheAggregate = aggregateHash(cache.rows);
  const peerAggregate = aggregateHash(peerCache.rows);
  const determinism =
    cacheAggregate === peerAggregate &&
    cacheAggregate === aggregateHash(cache.rows.slice().sort(compareRows)) &&
    isSorted(cache.rows);

  if (!determinism) {
    throw new Error('Final cache inventory is not deterministic or does not match its peer.');
  }

  const checks = {
    term_review_complete: buildA.termReviewComplete && buildB.termReviewComplete,
    mapping_safety_complete: mapping.complete,
    frame_semantics_complete: frame.complete,
    role_field_semantics_complete: mapping.roleFieldSemanticsComplete,
    cache_integrity_complete: integrity.complete,
    source_coverage_reviewed: coverage.complete,
    stale_empty_source_removed: removedSourceChecks.complete,
    determinism,
  };
  for (const [name, value] of Object.entries(checks)) {
    if (value !== true) throw new Error(`Acceptance gate did not pass: ${name}`);
  }

  const reportEvidenceRows = {
    build_report_a: reportEvidence(inputReports.buildReportA, buildA.counts),
    build_report_b: reportEvidence(inputReports.buildReportB, buildB.counts),
    mapping_report: reportEvidence(inputReports.mappingReport, mapping.counts),
    frame_report: reportEvidence(inputReports.frameReport, frame.counts),
    integrity_report: reportEvidence(
      inputReports.integrityReport,
      integrity.counts,
    ),
    coverage_report: reportEvidence(
      inputReports.coverageReport,
      coverage.counts,
    ),
    term_review: reportEvidence(inputReports.termReview, termReview.counts),
  };

  return {
    kind: 'script_recast_promotion_acceptance',
    schema_version: 1,
    api_used: false,
    cache_dir: currentOptions.cacheDir,
    cache_files: cache.rows.map(({ file_name, sha256 }) => ({ file_name, sha256 })),
    removed_cache_files: removed.map(({ file_name, sha256 }) => ({ file_name, sha256 })),
    aggregate_sha256: cacheAggregate,
    cache_files_aggregate_sha256: cacheAggregate,
    checks,
    evidence: {
      reports: reportEvidenceRows,
      ...reportEvidenceRows,
      cache_inventory: {
        cache_dir: currentOptions.cacheDir,
        file_count: cache.rows.length,
        aggregate_sha256: cacheAggregate,
      },
      peer_cache_inventory: {
        cache_dir: currentOptions.peerCacheDir,
        file_count: peerCache.rows.length,
        aggregate_sha256: peerAggregate,
      },
      baseline_inventory: {
        cache_dir: currentOptions.baselineDir,
        file_count: baseline.rows.length,
        aggregate_sha256: aggregateHash(baseline.rows),
        remove_file_count: removed.length,
      },
      source_roots: {
        distinct_count: sourceRoots.distinctCount,
        duplicate_count: sourceRoots.duplicateCount,
        expected_distinct_count: currentOptions.expectedSourceRootCount,
        expected_duplicate_count: currentOptions.expectedDuplicateRootCount,
        groups: sourceRoots.groups,
      },
      removed_sources: removedSourceChecks.rows,
      authorities: {
        frame_semantics: {
          authoritative_fields: [
            'mixed_stage_issue_count',
            'label_state_issue_count',
            'field_source_issue_count',
            'ui_label_issue_count',
          ],
          legacy_field_route_authoritative: false,
        },
        cache_integrity: {
          authoritative_fields: [
            'cache_count',
            'ready_count',
            'total_frames',
            'parsed_frames',
            'png_metadata_missing_frames',
            'source_frame_mismatch_count',
            'role_identity_issue_count',
            'role_frame_reference_issue_count',
          ],
          legacy_non_authoritative_fields: [
            'classification_issue_count',
            'slot_coverage_issue_count',
          ],
          replacement_validator: 'mapping_report.term_review_* occurrence counters',
        },
      },
    },
  };
}

function parseArgs(args) {
  const values = new Map();
  const removeFiles = [];
  const singletonFlags = new Set([
    '--cache-dir',
    '--peer-cache-dir',
    '--baseline-dir',
    '--build-report-a',
    '--build-report-b',
    '--mapping-report',
    '--frame-report',
    '--integrity-report',
    '--coverage-report',
    '--term-review',
    '--expected-count',
    '--expected-source-root-count',
    '--expected-duplicate-root-count',
    '--expected-unrecoverable-without-metadata-count',
    '--output',
  ]);

  for (let index = 0; index < args.length; index += 1) {
    const raw = args[index];
    if (raw === '--remove-file') {
      const value = requireValue(args, ++index, raw);
      validateBasename(value, raw);
      const key = nameKey(value);
      if (removeFiles.some((item) => nameKey(item) === key)) {
        throw new Error(`Duplicate --remove-file basename: ${value}`);
      }
      removeFiles.push(value);
      continue;
    }

    const equalIndex = raw.indexOf('=');
    const flag = equalIndex >= 0 ? raw.slice(0, equalIndex) : raw;
    const inlineValue = equalIndex >= 0 ? raw.slice(equalIndex + 1) : undefined;
    if (!singletonFlags.has(flag)) throw new Error(`Unknown argument: ${raw}`);
    if (values.has(flag)) throw new Error(`Duplicate argument: ${flag}`);
    const value = inlineValue ?? requireValue(args, ++index, flag);
    if (!value || value.startsWith('--')) throw new Error(`Missing value for ${flag}`);
    values.set(flag, value);
  }

  for (const flag of singletonFlags) {
    if (!values.has(flag)) throw new Error(`Required argument missing: ${flag}`);
  }

  const expectedCount = positiveInteger(values.get('--expected-count'), '--expected-count');
  const expectedSourceRootCount = nonNegativeInteger(
    values.get('--expected-source-root-count'),
    '--expected-source-root-count',
  );
  const expectedDuplicateRootCount = nonNegativeInteger(
    values.get('--expected-duplicate-root-count'),
    '--expected-duplicate-root-count',
  );
  const expectedUnrecoverableWithoutMetadataCount = nonNegativeInteger(
    values.get('--expected-unrecoverable-without-metadata-count'),
    '--expected-unrecoverable-without-metadata-count',
  );

  return {
    cacheDir: path.resolve(values.get('--cache-dir')),
    peerCacheDir: path.resolve(values.get('--peer-cache-dir')),
    baselineDir: path.resolve(values.get('--baseline-dir')),
    buildReportA: path.resolve(values.get('--build-report-a')),
    buildReportB: path.resolve(values.get('--build-report-b')),
    mappingReport: path.resolve(values.get('--mapping-report')),
    frameReport: path.resolve(values.get('--frame-report')),
    integrityReport: path.resolve(values.get('--integrity-report')),
    coverageReport: path.resolve(values.get('--coverage-report')),
    termReview: path.resolve(values.get('--term-review')),
    output: path.resolve(values.get('--output')),
    removeFiles,
    expectedCount,
    expectedSourceRootCount,
    expectedDuplicateRootCount,
    expectedUnrecoverableWithoutMetadataCount,
  };
}

function readInputReports(currentOptions) {
  return {
    buildReportA: readReport(currentOptions.buildReportA, 'build report A'),
    buildReportB: readReport(currentOptions.buildReportB, 'build report B'),
    mappingReport: readReport(currentOptions.mappingReport, 'mapping report'),
    frameReport: readReport(currentOptions.frameReport, 'frame report'),
    integrityReport: readReport(
      currentOptions.integrityReport,
      'integrity report',
    ),
    coverageReport: readReport(
      currentOptions.coverageReport,
      'coverage report',
    ),
    termReview: readReport(currentOptions.termReview, 'term review'),
  };
}

function readReport(filePath, label) {
  const stat = checkedRegularFile(filePath, label);
  const sha256 = sha256File(filePath);
  let value;
  try {
    value = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (error) {
    throw new Error(`${label} is not valid JSON: ${errorMessage(error)}`);
  }
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${label} must contain a JSON object.`);
  }
  return { path: filePath, stat, sha256, value };
}

function validateBuildReport(reportInfo, currentOptions, removeNames, side) {
  const report = reportInfo.value;
  requireBoolean(report.api_used, false, `build report ${side}.api_used`);
  requireBoolean(report.apply, true, `build report ${side}.apply`);
  const outputDirValue = stringValue(report.output_dir).trim();
  if (!outputDirValue) throw new Error(`build report ${side} has no output_dir.`);
  const outputDir = path.resolve(outputDirValue);
  assertDirectory(outputDir, `build report ${side} output_dir`);

  const output = inventoryDirectory(outputDir, `parent rebuilt ${side}`);
  const expectedOutputCount = currentOptions.expectedCount + removeNames.length;
  assertExpectedCount(output, expectedOutputCount, `parent rebuilt ${side}`);
  requireCountFromAliases(
    report,
    ['files_scanned', 'cache_file_count', 'cache_count'],
    expectedOutputCount,
    `build report ${side} file count`,
  );
  requireBoolean(
    report.term_review_complete,
    true,
    `build report ${side}.term_review_complete`,
  );
  requireZeroFromAliases(
    report,
    [
      'term_review_missing_term_count',
      'term_review_missing_count',
      'missing_term_count',
    ],
    `build report ${side} missing term count`,
  );
  requireZeroFromAliases(
    report,
    [
      'term_review_baseline_mismatch_count',
      'term_review_baseline_mismatches_count',
      'baseline_mismatch_count',
    ],
    `build report ${side} baseline mismatch count`,
  );

  const termReviewField = firstPresentKey(report, [
    'term_review_file',
    'term_review_path',
  ]);
  if (termReviewField) {
    const reportTermReview = path.resolve(stringValue(report[termReviewField]));
    if (!samePath(reportTermReview, currentOptions.termReview)) {
      throw new Error(`build report ${side} is bound to a different term review.`);
    }
  }

  return {
    output: { ...output, directory: outputDir },
    termReviewComplete: report.term_review_complete === true,
    counts: {
      files_scanned: readCount(report, ['files_scanned', 'cache_file_count', 'cache_count']),
      term_review_complete: report.term_review_complete,
      term_review_missing_term_count: readCount(report, [
        'term_review_missing_term_count',
        'term_review_missing_count',
        'missing_term_count',
      ]),
      term_review_baseline_mismatch_count: readCount(report, [
        'term_review_baseline_mismatch_count',
        'term_review_baseline_mismatches_count',
        'baseline_mismatch_count',
      ]),
      output_dir: outputDir,
    },
  };
}

function assertBuildOutputMatchesFinal(buildOutput, finalCache, removeNames, side) {
  const expectedNames = new Map(finalCache.rows.map((row) => [nameKey(row.file_name), row]));
  const removeKeys = new Set(removeNames.map(nameKey));
  for (const row of buildOutput.rows) {
    const key = nameKey(row.file_name);
    if (removeKeys.has(key)) continue;
    const finalRow = expectedNames.get(key);
    if (!finalRow || finalRow.file_name !== row.file_name) {
      throw new Error(`Final cache ${side} differs from builder output beyond --remove-file entries: ${row.file_name}`);
    }
    if (finalRow.sha256 !== row.sha256) {
      throw new Error(`Final cache ${side} hash differs from builder output: ${row.file_name}`);
    }
  }
  if (buildOutput.rows.length !== finalCache.rows.length + removeNames.length) {
    throw new Error(`Builder output ${side} does not contain final cache plus remove set.`);
  }
  for (const row of finalCache.rows) {
    const outputRow = buildOutput.byKey.get(nameKey(row.file_name));
    if (!outputRow || outputRow.sha256 !== row.sha256) {
      throw new Error(`Final cache ${side} is not exactly builder output minus remove set: ${row.file_name}`);
    }
  }
  for (const removeName of removeNames) {
    const outputRow = buildOutput.byKey.get(nameKey(removeName));
    if (!outputRow) {
      throw new Error(`Builder output ${side} is missing removed cache: ${removeName}`);
    }
  }
}

function validateMappingReport(reportInfo, currentOptions) {
  const report = reportInfo.value;
  requireBoolean(report.api_used, false, 'mapping report.api_used');
  requirePathBinding(report.cache_dir, currentOptions.cacheDir, 'mapping report.cache_dir');
  requireCountFromAliases(
    report,
    ['files_scanned', 'files', 'cache_count'],
    currentOptions.expectedCount,
    'mapping report file count',
  );
  requireNumber(report.violation_count, 0, 'mapping report.violation_count');
  requireBoolean(
    report.term_review_complete,
    true,
    'mapping report.term_review_complete',
  );
  const nonZeroCounters = findNonZeroAuthoritativeCounters(report);
  if (nonZeroCounters.length > 0) {
    throw new Error(`Mapping report has non-zero authoritative counters: ${nonZeroCounters.join(', ')}`);
  }
  const roleFields = Object.keys(report)
    .filter(
      (key) =>
        /^term_review_stage_/.test(key) &&
        (/_count$/.test(key) ||
          /category_mismatch|non_role_residue|materialization/i.test(key)),
    )
    .sort(compareText);
  for (const key of roleFields) requireNumber(report[key], 0, `mapping report.${key}`);
  return {
    complete: report.violation_count === 0 && report.term_review_complete === true,
    roleFieldSemanticsComplete:
      report.violation_count === 0 &&
      report.term_review_complete === true &&
      roleFields.every((key) => Number(report[key]) === 0),
    counts: collectEvidenceCounts(report, [
      'files_scanned',
      'files',
      'cache_count',
      'violation_count',
      'term_review_complete',
      ...roleFields,
      ...Object.keys(report).filter((key) => /term|occurrence|mapping/i.test(key) && /_count$/.test(key)),
    ]),
  };
}

function validateFrameReport(reportInfo, currentOptions) {
  const report = reportInfo.value;
  requirePathBinding(report.cache_dir, currentOptions.cacheDir, 'frame report.cache_dir');
  const fields = [
    'mixed_stage_issue_count',
    'label_state_issue_count',
    'field_source_issue_count',
    'ui_label_issue_count',
  ];
  for (const field of fields) requireNumber(report[field], 0, `frame report.${field}`);
  return {
    complete: fields.every((field) => Number(report[field]) === 0),
    counts: collectEvidenceCounts(report, [
      'cache_count',
      ...fields,
      'field_route_issue_count',
    ]),
  };
}

function validateIntegrityReport(reportInfo, currentOptions) {
  const report = reportInfo.value;
  requirePathBinding(report.cache_dir, currentOptions.cacheDir, 'integrity report.cache_dir');
  requireNumber(report.cache_count, currentOptions.expectedCount, 'integrity report.cache_count');
  requireNumber(report.ready_count, currentOptions.expectedCount, 'integrity report.ready_count');
  requireNumber(report.total_frames, report.parsed_frames, 'integrity report total_frames/parsed_frames');
  const zeroFields = [
    [
      'png_metadata_missing_frames',
      'png_metadata_missing_frame_count',
      'png_metadata_missing_count',
    ],
    ['source_frame_mismatch_count', 'source_mismatch_count'],
    ['role_identity_issue_count'],
    ['role_frame_reference_issue_count'],
  ];
  for (const aliases of zeroFields) requireZeroFromAliases(report, aliases, `integrity report ${aliases[0]}`);
  const complete =
    report.cache_count === currentOptions.expectedCount &&
    report.ready_count === currentOptions.expectedCount &&
    report.total_frames === report.parsed_frames &&
    zeroFields.every((aliases) => {
      const key = firstPresentKey(report, aliases);
      return key != null && report[key] === 0;
    });
  return {
    complete,
    counts: collectEvidenceCounts(report, [
      'cache_count',
      'ready_count',
      'total_frames',
      'parsed_frames',
      'png_metadata_missing_frames',
      'png_metadata_missing_frame_count',
      'png_metadata_missing_count',
      'source_frame_mismatch_count',
      'role_identity_issue_count',
      'role_frame_reference_issue_count',
      'classification_issue_count',
      'slot_coverage_issue_count',
    ]),
  };
}

function validateCoverageReport(reportInfo, currentOptions) {
  const report = reportInfo.value;
  requireBoolean(report.api_used, false, 'coverage report.api_used');
  requireBoolean(report.read_only, true, 'coverage report.read_only');
  requireBoolean(
    report.source_coverage_reviewed,
    true,
    'coverage report.source_coverage_reviewed',
  );
  requirePathBinding(report.cache_dir, currentOptions.cacheDir, 'coverage report.cache_dir');
  if (!report.checks || typeof report.checks !== 'object' || Array.isArray(report.checks)) {
    throw new Error('coverage report.checks is missing.');
  }
  const checkEntries = Object.entries(report.checks);
  if (checkEntries.length === 0 || checkEntries.some(([, value]) => value !== true)) {
    throw new Error('coverage report checks must all be true.');
  }
  if (!Array.isArray(report.violations) || report.violations.length !== 0) {
    throw new Error('coverage report.violations must be empty.');
  }
  if (!Array.isArray(report.errors) || report.errors.length !== 0) {
    throw new Error('coverage report.errors must be empty.');
  }

  const review = report.uncached_png_without_prompt_metadata_review ??
    report.unrecoverable_without_metadata_review;
  const count = firstNumberAtPaths(report, [
    ['unrecoverable_without_metadata_count'],
    ['summary', 'uncached_png_without_prompt_metadata_count'],
    ['summary', 'unrecoverable_without_metadata_count'],
    ['uncached_png_without_prompt_metadata_review', 'count'],
    ['unrecoverable_without_metadata_review', 'count'],
  ]);
  if (count === undefined) throw new Error('coverage report has no unrecoverable-without-metadata count.');
  if (count !== currentOptions.expectedUnrecoverableWithoutMetadataCount) {
    throw new Error(
      `coverage report unrecoverable-without-metadata count must be ${currentOptions.expectedUnrecoverableWithoutMetadataCount}, found ${count}.`,
    );
  }
  const status = stringValue(review?.status).trim() ||
    stringValue(report.unrecoverable_without_metadata_status).trim();
  if (status !== 'reviewed_unrecoverable_without_metadata') {
    throw new Error(`coverage report has invalid unrecoverable review status: ${status || '<missing>'}`);
  }
  const complete =
    report.api_used === false &&
    report.read_only === true &&
    report.source_coverage_reviewed === true &&
    checkEntries.length > 0 &&
    checkEntries.every(([, value]) => value === true) &&
    report.violations.length === 0 &&
    report.errors.length === 0 &&
    count === currentOptions.expectedUnrecoverableWithoutMetadataCount &&
    status === 'reviewed_unrecoverable_without_metadata';
  return {
    complete,
    counts: {
      cache_dir: currentOptions.cacheDir,
      source_coverage_reviewed: report.source_coverage_reviewed,
      unrecoverable_without_metadata_count: count,
      unrecoverable_without_metadata_status: status,
      checks_true_count: checkEntries.length,
      violations_count: report.violations.length,
      errors_count: report.errors.length,
    },
  };
}

function validateTermReview(reportInfo) {
  const report = reportInfo.value;
  requireBoolean(report.api_used, false, 'term review.api_used');
  if (report.kind != null && report.kind !== 'script_recast_term_membership_review') {
    throw new Error(`term review has an unexpected kind: ${report.kind}`);
  }
  if (report.decisions != null && !Array.isArray(report.decisions)) {
    throw new Error('term review.decisions must be an array when present.');
  }
  const decisions = Array.isArray(report.decisions) ? report.decisions.length : 0;
  return {
    counts: {
      decision_count: decisions,
      api_used: report.api_used,
    },
  };
}

function inspectFinalSourceRoots(cache, currentOptions) {
  const groups = new Map();
  for (const row of cache.rows) {
    const value = readJsonFile(row.path, `final cache ${row.file_name}`);
    const sourceRootPath = stringValue(value.sourceRootPath).trim();
    if (!sourceRootPath) throw new Error(`Final cache has no sourceRootPath: ${row.file_name}`);
    const key = canonicalPathKey(sourceRootPath);
    const group = groups.get(key) ?? { source_root_path: path.resolve(sourceRootPath), cache_files: [] };
    group.cache_files.push(row.file_name);
    groups.set(key, group);
  }
  const rows = [...groups.values()]
    .map((group) => ({ ...group, cache_files: group.cache_files.sort(compareText) }))
    .sort((left, right) => compareText(left.source_root_path, right.source_root_path));
  const distinctCount = rows.length;
  const duplicateCount = currentOptions.expectedCount - distinctCount;
  if (distinctCount !== currentOptions.expectedSourceRootCount) {
    throw new Error(`Expected ${currentOptions.expectedSourceRootCount} distinct source roots, found ${distinctCount}.`);
  }
  if (duplicateCount !== currentOptions.expectedDuplicateRootCount) {
    throw new Error(`Expected ${currentOptions.expectedDuplicateRootCount} duplicate source roots, found ${duplicateCount}.`);
  }
  return { distinctCount, duplicateCount, groups: rows };
}

function inspectRemovedSources(removed) {
  const rows = [];
  for (const row of removed) {
    const value = readJsonFile(row.path, `removed baseline cache ${row.file_name}`);
    const sourceRootPath = stringValue(value.sourceRootPath).trim();
    if (!sourceRootPath) throw new Error(`Removed cache has no sourceRootPath: ${row.file_name}`);
    const sourceRoot = path.resolve(sourceRootPath);
    const imageFiles = existingImageFiles(sourceRoot);
    if (imageFiles.length > 0) {
      throw new Error(`Removed cache source root still contains images: ${sourceRoot}`);
    }
    rows.push({
      file_name: row.file_name,
      source_root_path: sourceRoot,
      source_root_exists: pathExists(sourceRoot),
      image_count: imageFiles.length,
      checks: { stale_empty_source_removed: imageFiles.length === 0 },
    });
  }
  const complete = rows.every((row) => row.image_count === 0);
  return {
    complete,
    rows: rows.sort((left, right) => compareText(left.file_name, right.file_name)),
  };
}

function validateBaselineSet(baseline, cache, removeNames) {
  const finalKeys = new Set(cache.rows.map((row) => nameKey(row.file_name)));
  const removeKeys = new Set();
  for (const name of removeNames) {
    const key = nameKey(name);
    if (finalKeys.has(key)) throw new Error(`--remove-file is present in final cache: ${name}`);
    if (removeKeys.has(key)) throw new Error(`Duplicate remove cache: ${name}`);
    removeKeys.add(key);
  }
  const expectedKeys = new Set([...finalKeys, ...removeKeys]);
  if (baseline.byKey.size !== expectedKeys.size) {
    throw new Error('Baseline filename set must equal final cache plus remove set.');
  }
  for (const row of cache.rows) {
    const baselineRow = baseline.byKey.get(nameKey(row.file_name));
    if (!baselineRow || baselineRow.file_name !== row.file_name) {
      throw new Error(`Baseline is missing final cache filename: ${row.file_name}`);
    }
  }
  return removeNames.map((file_name) => {
    const row = baseline.byKey.get(nameKey(file_name));
    if (!row || row.file_name !== file_name) {
      throw new Error(`Baseline is missing remove cache filename: ${file_name}`);
    }
    return row;
  });
}

function inventoryDirectory(directory, label) {
  assertDirectory(directory, label);
  const entries = fs.readdirSync(directory, { withFileTypes: true }).sort((left, right) => compareText(left.name, right.name));
  const rows = [];
  for (const entry of entries) {
    const filePath = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) throw new Error(`${label} contains a symlink: ${filePath}`);
    if (entry.isDirectory()) throw new Error(`${label} must contain only direct JSON files: ${filePath}`);
    if (!entry.isFile()) throw new Error(`${label} contains an unsupported entry: ${filePath}`);
    if (!entry.name.toLowerCase().endsWith('.json')) {
      throw new Error(`${label} contains a non-JSON file: ${filePath}`);
    }
    checkedRegularFile(filePath, `${label} cache ${entry.name}`);
    rows.push({ file_name: entry.name, path: filePath, sha256: sha256File(filePath) });
  }
  const byKey = new Map();
  for (const row of rows) {
    const key = nameKey(row.file_name);
    if (byKey.has(key)) throw new Error(`${label} has case-colliding filenames: ${row.file_name}`);
    byKey.set(key, row);
  }
  return { directory, rows, byKey };
}

function assertExpectedCount(inventory, expected, label) {
  if (inventory.rows.length !== expected) {
    throw new Error(`${label} must contain ${expected} JSON files, found ${inventory.rows.length}.`);
  }
}

function assertSameInventory(left, right, label) {
  if (left.rows.length !== right.rows.length) throw new Error(`${label} filename sets differ.`);
  for (const row of left.rows) {
    const other = right.byKey.get(nameKey(row.file_name));
    if (!other || other.file_name !== row.file_name || other.sha256 !== row.sha256) {
      throw new Error(`${label} differs at ${row.file_name}.`);
    }
  }
}

function assertDirectory(directory, label) {
  let stat;
  try {
    stat = fs.lstatSync(directory);
  } catch (error) {
    throw new Error(`${label} does not exist: ${directory} (${errorMessage(error)})`);
  }
  if (!stat.isDirectory() || stat.isSymbolicLink()) {
    throw new Error(`${label} must be a regular non-symlink directory: ${directory}`);
  }
}

function checkedRegularFile(filePath, label) {
  let stat;
  try {
    stat = fs.lstatSync(filePath);
  } catch (error) {
    throw new Error(`${label} does not exist: ${filePath} (${errorMessage(error)})`);
  }
  if (!stat.isFile() || stat.isSymbolicLink()) {
    throw new Error(`${label} must be a regular non-symlink file: ${filePath}`);
  }
  return stat;
}

function assertOutputPathSafe(output, currentOptions, inputReports) {
  if (pathExists(output)) {
    const stat = fs.lstatSync(output);
    if (stat.isSymbolicLink()) throw new Error(`Output must not be a symlink: ${output}`);
    if (stat.isDirectory()) throw new Error(`Output must be a file: ${output}`);
  }
  const canonicalOutput = canonicalPathForSafety(output);
  const protectedDirectories = [
    currentOptions.cacheDir,
    currentOptions.peerCacheDir,
    currentOptions.baselineDir,
  ];
  for (const reportKey of ['buildReportA', 'buildReportB']) {
    const report = inputReports[reportKey]?.value;
    const outputDir = stringValue(report?.output_dir).trim();
    if (outputDir) protectedDirectories.push(path.resolve(outputDir));
  }
  for (const directory of protectedDirectories) {
    if (isSameOrInside(canonicalOutput, canonicalPathForSafety(directory))) {
      throw new Error(`Output path must be outside protected cache directories: ${output}`);
    }
  }
  for (const report of Object.values(inputReports)) {
    if (samePath(canonicalOutput, canonicalPathForSafety(report.path))) {
      throw new Error(`Output path must not overwrite an input report: ${output}`);
    }
  }
}

function existingImageFiles(directory) {
  if (!pathExists(directory)) return [];
  const rootStat = fs.lstatSync(directory);
  if (rootStat.isSymbolicLink() || !rootStat.isDirectory()) {
    throw new Error(`Removed sourceRootPath must be a directory when it exists: ${directory}`);
  }
  const images = [];
  walk(directory, '');
  return images.sort(compareText);

  function walk(current, relative) {
    const entries = fs.readdirSync(current, { withFileTypes: true }).sort((left, right) => compareText(left.name, right.name));
    for (const entry of entries) {
      const filePath = path.join(current, entry.name);
      const relativePath = relative ? path.join(relative, entry.name) : entry.name;
      if (entry.isSymbolicLink()) {
        if (isImagePath(entry.name)) images.push(filePath);
        else throw new Error(`Removed sourceRootPath contains a symlink: ${filePath}`);
      } else if (entry.isDirectory()) {
        walk(filePath, relativePath);
      } else if (entry.isFile() && isImagePath(entry.name)) {
        images.push(filePath);
      }
    }
  }
}

function findNonZeroAuthoritativeCounters(report) {
  return Object.keys(report)
    .filter((key) => /term|occurrence|mapping/i.test(key))
    .filter((key) => key !== 'term_review_decision_count')
    .filter(
      (key) =>
        /_count$/.test(key) ||
        /^term_review_stage_/.test(key),
    )
    .filter((key) => {
      const value = report[key];
      return typeof value !== 'number' || !Number.isInteger(value) || value !== 0;
    })
    .sort(compareText);
}

function requireZeroFromAliases(object, aliases, label) {
  const key = firstPresentKey(object, aliases);
  if (!key) throw new Error(`${label} is missing.`);
  requireNumber(object[key], 0, `${label} (${key})`);
}

function requireCountFromAliases(object, aliases, expected, label) {
  const key = firstPresentKey(object, aliases);
  if (!key) throw new Error(`${label} is missing.`);
  const value = object[key];
  const count = Array.isArray(value) ? value.length : value;
  requireNumber(count, expected, `${label} (${key})`);
}

function requireNumber(value, expected, label) {
  if (!Number.isInteger(value) || value !== expected) {
    throw new Error(`${label} must be ${expected}, found ${String(value)}.`);
  }
}

function requireBoolean(value, expected, label) {
  if (value !== expected) throw new Error(`${label} must be ${String(expected)}.`);
}

function requirePathBinding(value, expected, label) {
  if (typeof value !== 'string' || !samePath(path.resolve(value), expected)) {
    throw new Error(`${label} is bound to a different directory.`);
  }
}

function firstPresentKey(object, aliases) {
  return aliases.find((key) => Object.prototype.hasOwnProperty.call(object, key));
}

function readCount(object, aliases) {
  const key = firstPresentKey(object, aliases);
  if (!key) return null;
  const value = Array.isArray(object[key]) ? object[key].length : object[key];
  return Number.isInteger(value) ? value : null;
}

function firstNumberAtPaths(object, paths) {
  for (const parts of paths) {
    let value = object;
    for (const part of parts) value = value?.[part];
    if (Number.isInteger(value)) return value;
  }
  return undefined;
}

function collectEvidenceCounts(object, keys) {
  const result = {};
  for (const key of [...new Set(keys)].sort(compareText)) {
    if (Object.prototype.hasOwnProperty.call(object, key)) result[key] = object[key];
  }
  return result;
}

function reportEvidence(reportInfo, counts) {
  return {
    path: reportInfo.path,
    report_path: reportInfo.path,
    sha256: reportInfo.sha256,
    counts,
  };
}

function readJsonFile(filePath, label) {
  try {
    const value = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('root must be an object');
    return value;
  } catch (error) {
    throw new Error(`${label} is not valid JSON: ${errorMessage(error)}`);
  }
}

function sha256File(filePath) {
  const hash = createHash('sha256');
  const descriptor = fs.openSync(filePath, 'r');
  const buffer = Buffer.allocUnsafe(1024 * 1024);
  try {
    let bytesRead = 0;
    do {
      bytesRead = fs.readSync(descriptor, buffer, 0, buffer.length, null);
      if (bytesRead > 0) hash.update(buffer.subarray(0, bytesRead));
    } while (bytesRead > 0);
  } finally {
    fs.closeSync(descriptor);
  }
  return hash.digest('hex');
}

function sha256Text(value) {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

function aggregateHash(rows) {
  const manifest = rows
    .slice()
    .sort(compareRows)
    .map(({ file_name, sha256 }) => ({ file_name, sha256 }));
  return sha256Text(`${JSON.stringify(manifest)}\n`);
}

function writeJson(filePath, value) {
  const parent = path.dirname(filePath);
  fs.mkdirSync(parent, { recursive: true });
  if (pathExists(filePath)) {
    const stat = fs.lstatSync(filePath);
    if (stat.isSymbolicLink() || !stat.isFile()) throw new Error(`Output became unsafe before write: ${filePath}`);
  }
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function canonicalPathKey(value) {
  let resolved = path.resolve(value);
  if (pathExists(resolved)) {
    try {
      resolved = fs.realpathSync.native(resolved);
    } catch {
      // The normalized absolute path remains a stable key for a missing root.
    }
  }
  return normalizePathForCompare(resolved);
}

function canonicalPathForSafety(value) {
  const resolved = path.resolve(value);
  let current = resolved;
  const suffix = [];
  while (!pathExists(current) && path.dirname(current) !== current) {
    suffix.unshift(path.basename(current));
    current = path.dirname(current);
  }
  if (pathExists(current)) {
    try {
      return path.resolve(fs.realpathSync.native(current), ...suffix);
    } catch {
      return resolved;
    }
  }
  return resolved;
}

function isSameOrInside(candidate, parent) {
  const relative = path.relative(parent, candidate);
  return relative === '' || (!relative.startsWith('..') && !path.isAbsolute(relative));
}

function samePath(left, right) {
  return normalizePathForCompare(path.resolve(left)) === normalizePathForCompare(path.resolve(right));
}

function normalizePathForCompare(value) {
  const normalized = path.resolve(value).replaceAll('\\', '/').replace(/\/+$/, '');
  return process.platform === 'win32' ? normalized.toLowerCase() : normalized;
}

function pathExists(value) {
  try {
    fs.lstatSync(value);
    return true;
  } catch (error) {
    if (error?.code === 'ENOENT') return false;
    throw error;
  }
}

function validateBasename(value, label) {
  if (
    !value ||
    value === '.' ||
    value === '..' ||
    value.includes('/') ||
    value.includes('\\') ||
    value.includes('\u0000') ||
    !value.toLowerCase().endsWith('.json')
  ) {
    throw new Error(`${label} must be a JSON basename: ${value}`);
  }
}

function requireValue(args, index, flag) {
  const value = args[index];
  if (value == null || value === '' || value.startsWith('--')) {
    throw new Error(`Missing value for ${flag}`);
  }
  return value;
}

function positiveInteger(value, label) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) throw new Error(`${label} must be a positive integer.`);
  return parsed;
}

function nonNegativeInteger(value, label) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0) throw new Error(`${label} must be a non-negative integer.`);
  return parsed;
}

function nameKey(value) {
  return process.platform === 'win32' ? value.toLowerCase() : value;
}

function compareRows(left, right) {
  return compareText(left.file_name, right.file_name);
}

function compareText(left, right) {
  const a = String(left);
  const b = String(right);
  return a < b ? -1 : a > b ? 1 : 0;
}

function isSorted(rows) {
  return rows.every((row, index) => index === 0 || compareRows(rows[index - 1], row) <= 0);
}

function isImagePath(value) {
  return /\.(?:png|jpe?g|webp|gif|bmp|avif|tiff?)$/i.test(value);
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}
