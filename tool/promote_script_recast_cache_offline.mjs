import fs from 'node:fs';
import path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';

let options;
let report;
let reportPathApproved = false;

try {
  options = parseArgs(process.argv.slice(2));
  report = createReport(options);
  const plan = preflight(options, report);
  if (options.apply) promote(plan, options, report);
  report.status = 'ok';
  writeReport(options.report, report);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
} catch (error) {
  report ??= createEmergencyReport(options);
  report.status = 'failed';
  report.errors.push(errorMessage(error));
  const reportPath = options?.report ?? rawArgValue(process.argv.slice(2), '--report');
  if (reportPath && reportPathApproved) {
    try {
      writeReport(reportPath, report);
    } catch (reportError) {
      process.stderr.write(`Could not write report: ${errorMessage(reportError)}\n`);
    }
  }
  process.stderr.write(`Cache promotion failed closed: ${errorMessage(error)}\n`);
  process.exitCode = 1;
}

function parseArgs(args) {
  const values = new Map();
  const removeFiles = [];
  let apply = false;
  for (let index = 0; index < args.length; index += 1) {
    const flag = args[index];
    if (flag === '--apply') {
      apply = true;
      continue;
    }
    if (flag === '--remove-file') {
      const value = args[index + 1];
      if (!value || value.startsWith('--')) {
        throw new Error(`Missing value for ${flag}`);
      }
      if (!/^script-[^\/\\]+\.json$/.test(value)) {
        throw new Error(`Invalid --remove-file basename: ${value}`);
      }
      if (removeFiles.some((item) => item.toLowerCase() === value.toLowerCase())) {
        throw new Error(`Duplicate --remove-file basename: ${value}`);
      }
      removeFiles.push(value);
      index += 1;
      continue;
    }
    if (![
      '--source-dir',
      '--target-dir',
      '--baseline-dir',
      '--acceptance-report',
      '--backup-dir',
      '--report',
      '--expected-count',
    ].includes(flag)) {
      throw new Error(`Unknown argument: ${flag}`);
    }
    const value = args[index + 1];
    if (!value || value.startsWith('--')) {
      throw new Error(`Missing value for ${flag}`);
    }
    values.set(flag, value);
    index += 1;
  }

  for (const flag of [
    '--source-dir',
    '--target-dir',
    '--baseline-dir',
    '--acceptance-report',
    '--report',
    '--expected-count',
  ]) {
    if (!values.has(flag)) throw new Error(`Required argument missing: ${flag}`);
  }
  if (apply && !values.has('--backup-dir')) {
    throw new Error('--backup-dir is required with --apply.');
  }

  const expectedCount = Number(values.get('--expected-count'));
  if (!Number.isInteger(expectedCount) || expectedCount <= 0) {
    throw new Error('--expected-count must be a positive integer.');
  }
  return {
    sourceDir: path.resolve(values.get('--source-dir')),
    targetDir: path.resolve(values.get('--target-dir')),
    baselineDir: path.resolve(values.get('--baseline-dir')),
    acceptanceReport: path.resolve(values.get('--acceptance-report')),
    backupDir: values.has('--backup-dir')
      ? path.resolve(values.get('--backup-dir'))
      : '',
    report: path.resolve(values.get('--report')),
    expectedCount,
    removeFiles,
    apply,
  };
}

function preflight(currentOptions, currentReport) {
  for (const directory of [
    currentOptions.sourceDir,
    currentOptions.targetDir,
    currentOptions.baselineDir,
  ]) {
    requireDirectory(directory);
  }
  if (
    isSameOrInside(currentOptions.acceptanceReport, currentOptions.sourceDir) ||
    isSameOrInside(currentOptions.acceptanceReport, currentOptions.targetDir) ||
    isSameOrInside(currentOptions.acceptanceReport, currentOptions.baselineDir) ||
    (currentOptions.apply &&
      isSameOrInside(currentOptions.acceptanceReport, currentOptions.backupDir))
  ) {
    throw new Error(
      'The acceptance report must be outside source, target, baseline, and backup directories.',
    );
  }
  if (path.resolve(currentOptions.acceptanceReport) === path.resolve(currentOptions.report)) {
    throw new Error('The acceptance report and promotion report must be different files.');
  }
  requireDistinctDirectories(currentOptions);
  for (const directory of [
    currentOptions.sourceDir,
    currentOptions.targetDir,
    currentOptions.baselineDir,
    ...(currentOptions.apply ? [currentOptions.backupDir] : []),
  ]) {
    if (isSameOrInside(currentOptions.report, directory)) {
      throw new Error('The report must be outside source, target, baseline, and backup directories.');
    }
  }
  if (currentOptions.apply) {
    if (fs.existsSync(currentOptions.backupDir)) {
      throw new Error(`Refusing to reuse an existing backup directory: ${currentOptions.backupDir}`);
    }
    for (const directory of [
      currentOptions.sourceDir,
      currentOptions.targetDir,
      currentOptions.baselineDir,
    ]) {
      if (isSameOrInside(currentOptions.backupDir, directory)) {
        throw new Error('The backup directory must be outside source, target, and baseline directories.');
      }
    }
  }
  probeReportPath(currentOptions.report);
  reportPathApproved = true;

  const sourceNames = directJsonNames(currentOptions.sourceDir);
  const baselineNames = directJsonNames(currentOptions.baselineDir);
  if (sourceNames.length === 0) throw new Error('The source directory contains no JSON caches.');
  if (sourceNames.length !== currentOptions.expectedCount) {
    throw new Error(
      `Expected ${currentOptions.expectedCount} JSON caches, found ${sourceNames.length}.`,
    );
  }
  for (const name of sourceNames) {
    if (!name.startsWith('script-') || name === 'knowledge.json') {
      throw new Error(`Refusing to promote a non-script cache: ${name}`);
    }
  }
  const sourceNameSet = new Set(sourceNames.map((name) => name.toLowerCase()));
  for (const name of currentOptions.removeFiles) {
    if (sourceNameSet.has(name.toLowerCase())) {
      throw new Error(`A --remove-file basename is present in the source set: ${name}`);
    }
  }
  const expectedBaselineNames = [...sourceNames, ...currentOptions.removeFiles]
    .sort((left, right) => left.localeCompare(right, 'en'));
  if (!sameStrings(expectedBaselineNames, baselineNames)) {
    throw new Error('Baseline JSON filename set must equal source plus remove sets.');
  }

  const records = [];
  for (const name of sourceNames) {
    const sourceFile = checkedRegularFile(currentOptions.sourceDir, name);
    const baselineFile = checkedRegularFile(currentOptions.baselineDir, name);
    const targetFile = checkedRegularFile(currentOptions.targetDir, name);
    const sourceCache = validateCacheStructure(sourceFile, name);

    const sourceHash = sha256(sourceFile);
    const baselineHash = sha256(baselineFile);
    const targetHash = sha256(targetFile);
    if (targetHash !== baselineHash) {
      throw new Error(`Target drifted from the approved baseline: ${name}`);
    }
    records.push({
      name,
      sourceFile,
      baselineFile,
      targetFile,
      sourceHash,
      baselineHash,
      changed: sourceHash !== targetHash,
    });
    currentReport.frame_count += sourceCache.scriptSnapshot.frames.length;
    currentReport.role_count += sourceCache.aiRoleExtraction.roles.length;
    currentReport.stage_count += sourceCache.aiRoleExtraction.roles.reduce(
      (total, role) => total + role.stages.length,
      0,
    );
  }

  const removedRecords = [];
  for (const name of currentOptions.removeFiles) {
    const baselineFile = checkedRegularFile(currentOptions.baselineDir, name);
    const targetFile = checkedRegularFile(currentOptions.targetDir, name);
    const baselineHash = sha256(baselineFile);
    const targetHash = sha256(targetFile);
    if (targetHash !== baselineHash) {
      throw new Error(`Target stale cache drifted from the approved baseline: ${name}`);
    }
    removedRecords.push({
      name,
      baselineFile,
      targetFile,
      baselineHash,
      targetHash,
    });
  }

  const plannedRootNames = new Set([
    ...sourceNames,
    ...currentOptions.removeFiles,
  ]);
  const targetInventory = recursiveInventory(currentOptions.targetDir, plannedRootNames);
  currentReport.files_scanned = records.length;
  currentReport.files_changed = records.filter((record) => record.changed).length;
  currentReport.files_unchanged = records.length - currentReport.files_changed;
  currentReport.removed_file_count = removedRecords.length;
  currentReport.target_file_count_before = recursiveFileCount(currentOptions.targetDir);
  currentReport.unrelated_file_count = targetInventory.size;
  currentReport.preflight_passed = true;
  currentReport.rows = records.map((record) => ({
    file_name: record.name,
    baseline_sha256: record.baselineHash,
    source_sha256: record.sourceHash,
    changed: record.changed,
  }));
  currentReport.removed_rows = removedRecords.map((record) => ({
    file_name: record.name,
    baseline_sha256: record.baselineHash,
    target_sha256: record.targetHash,
  }));
  validateAcceptanceReport(currentOptions, currentReport, records, removedRecords);

  return { records, removedRecords, targetInventory };
}

function validateAcceptanceReport(currentOptions, currentReport, records, removedRecords) {
  if (!fs.existsSync(currentOptions.acceptanceReport)) {
    throw new Error(`Acceptance report does not exist: ${currentOptions.acceptanceReport}`);
  }
  const stat = fs.lstatSync(currentOptions.acceptanceReport);
  if (!stat.isFile() || stat.isSymbolicLink()) {
    throw new Error(
      `Acceptance report must be a regular non-symlink file: ${currentOptions.acceptanceReport}`,
    );
  }

  let acceptance;
  try {
    acceptance = JSON.parse(fs.readFileSync(currentOptions.acceptanceReport, 'utf8'));
  } catch (error) {
    throw new Error(`Invalid acceptance report JSON: ${errorMessage(error)}`);
  }
  if (
    acceptance?.kind !== 'script_recast_promotion_acceptance' ||
    acceptance?.schema_version !== 1 ||
    acceptance?.api_used !== false
  ) {
    throw new Error('Acceptance report contract is invalid or does not declare api_used=false.');
  }
  if (
    typeof acceptance.cache_dir !== 'string' ||
    path.resolve(acceptance.cache_dir).toLowerCase() !== currentOptions.sourceDir.toLowerCase()
  ) {
    throw new Error('Acceptance report was created for a different cache directory.');
  }

  const requiredChecks = [
    'term_review_complete',
    'mapping_safety_complete',
    'frame_semantics_complete',
    'role_field_semantics_complete',
    'cache_integrity_complete',
    'source_coverage_reviewed',
  ];
  if (removedRecords.length > 0) requiredChecks.push('stale_empty_source_removed');
  for (const check of requiredChecks) {
    if (acceptance?.checks?.[check] !== true) {
      throw new Error(`Acceptance gate did not pass: ${check}`);
    }
  }

  if (!Array.isArray(acceptance.cache_files)) {
    throw new Error('Acceptance report has no cache_files inventory.');
  }
  const acceptedByName = new Map();
  for (const row of acceptance.cache_files) {
    const name = typeof row?.file_name === 'string' ? row.file_name : '';
    const hash = typeof row?.sha256 === 'string' ? row.sha256.toLowerCase() : '';
    if (!name || !/^[a-f0-9]{64}$/.test(hash)) {
      throw new Error('Acceptance report contains an invalid cache_files row.');
    }
    if (acceptedByName.has(name)) {
      throw new Error(`Acceptance report contains a duplicate cache file: ${name}`);
    }
    acceptedByName.set(name, hash);
  }
  const recordNames = records.map((record) => record.name).sort();
  const acceptedNames = [...acceptedByName.keys()].sort();
  if (!sameStrings(recordNames, acceptedNames)) {
    throw new Error('Acceptance report cache filename set differs from the promotion source.');
  }
  for (const record of records) {
    if (acceptedByName.get(record.name) !== record.sourceHash) {
      throw new Error(`Acceptance report is stale for cache: ${record.name}`);
    }
  }

  if (removedRecords.length > 0) {
    if (!Array.isArray(acceptance.removed_cache_files)) {
      throw new Error('Acceptance report has no removed_cache_files inventory.');
    }
    const acceptedRemovedByName = new Map();
    for (const row of acceptance.removed_cache_files) {
      const name = typeof row?.file_name === 'string' ? row.file_name : '';
      const hash = typeof row?.sha256 === 'string' ? row.sha256.toLowerCase() : '';
      if (!name || !/^[a-f0-9]{64}$/.test(hash)) {
        throw new Error('Acceptance report contains an invalid removed_cache_files row.');
      }
      if (acceptedRemovedByName.has(name)) {
        throw new Error(`Acceptance report contains a duplicate removed cache file: ${name}`);
      }
      acceptedRemovedByName.set(name, hash);
    }
    const removedNames = removedRecords.map((record) => record.name).sort();
    const acceptedRemovedNames = [...acceptedRemovedByName.keys()].sort();
    if (!sameStrings(removedNames, acceptedRemovedNames)) {
      throw new Error('Acceptance report removed_cache_files set differs from the remove set.');
    }
    for (const record of removedRecords) {
      if (acceptedRemovedByName.get(record.name) !== record.baselineHash) {
        throw new Error(`Acceptance report is stale for removed cache: ${record.name}`);
      }
    }
  }

  currentReport.acceptance_report = currentOptions.acceptanceReport;
  currentReport.acceptance_report_sha256 = sha256(currentOptions.acceptanceReport);
  currentReport.acceptance_checks = Object.fromEntries(
    requiredChecks.map((check) => [check, true]),
  );
  currentReport.acceptance_passed = true;
}

function promote(plan, currentOptions, currentReport) {
  const backupCacheDir = path.join(currentOptions.backupDir, 'cache');
  const token = `${process.pid}-${randomUUID()}`;
  const lockFile = path.join(currentOptions.targetDir, '.codex-script-recast-promotion.lock');
  const transactionFile = path.join(currentOptions.backupDir, 'transaction.json');
  const replaced = [];
  const removed = [];
  const committed = [];
  let pendingMutation = null;
  let activeTemp = '';
  const writeTransaction = (
    status,
    mutations = committed,
    pendingFile = null,
    pendingAction = null,
    extra = {},
  ) => {
    writeDurableJson(transactionFile, {
      api_used: false,
      status,
      token,
      committed_files: mutations
        .filter((item) => item.action === 'replace')
        .map((item) => item.record.name),
      removed_files: mutations
        .filter((item) => item.action === 'remove')
        .map((item) => item.record.name),
      pending_file: pendingFile,
      pending_action: pendingAction,
      ...extra,
    });
  };

  acquireLock(lockFile, currentOptions, token);
  try {
    fs.mkdirSync(backupCacheDir, { recursive: true });
    for (const record of [...plan.records, ...plan.removedRecords]) {
      const backupFile = path.join(backupCacheDir, record.name);
      fs.copyFileSync(record.targetFile, backupFile, fs.constants.COPYFILE_EXCL);
      syncFile(backupFile);
      if (sha256(backupFile) !== record.baselineHash) {
        throw new Error(`Backup hash mismatch: ${record.name}`);
      }
      currentReport.files_backed_up += 1;
    }

    fs.writeFileSync(
      path.join(currentOptions.backupDir, 'manifest.json'),
      `${JSON.stringify({
        api_used: false,
        created_at: new Date().toISOString(),
        source_dir: currentOptions.sourceDir,
        target_dir: currentOptions.targetDir,
        baseline_dir: currentOptions.baselineDir,
        acceptance_report: currentOptions.acceptanceReport,
        acceptance_report_sha256: currentReport.acceptance_report_sha256,
        files: currentReport.rows,
        removed_files: currentReport.removed_rows,
      }, null, 2)}\n`,
      { encoding: 'utf8', flag: 'wx' },
    );
    writeTransaction('prepared', committed, null, null, {
      created_at: new Date().toISOString(),
    });

    const failAfter = Number(process.env.SCRIPT_RECAST_PROMOTION_FAIL_AFTER ?? 0);
    for (const record of plan.records.filter((item) => item.changed)) {
      pendingMutation = { action: 'replace', record, applied: false };
      if (sha256(record.targetFile) !== record.baselineHash) {
        throw new Error(`Target changed during promotion: ${record.name}`);
      }
      activeTemp = `${record.targetFile}.codex-promote-${token}.tmp`;
      if (fs.existsSync(activeTemp)) throw new Error(`Temporary file already exists: ${activeTemp}`);
      fs.copyFileSync(record.sourceFile, activeTemp, fs.constants.COPYFILE_EXCL);
      syncFile(activeTemp);
      if (sha256(activeTemp) !== record.sourceHash) {
        throw new Error(`Temporary file hash mismatch: ${record.name}`);
      }
      writeTransaction('committing', committed, record.name, 'replace');
      atomicReplace(activeTemp, record.targetFile);
      pendingMutation.applied = true;
      activeTemp = '';
      replaced.push(record);
      committed.push(pendingMutation);
      pendingMutation = null;
      currentReport.files_replaced = replaced.length;
      if (sha256(record.targetFile) !== record.sourceHash) {
        throw new Error(`Promoted file hash mismatch: ${record.name}`);
      }
      if (failAfter > 0 && committed.length === failAfter) {
        throw new Error(`Injected failure after ${failAfter} mutations.`);
      }
      writeTransaction('committing', committed);
    }

    for (const record of plan.removedRecords) {
      pendingMutation = { action: 'remove', record, applied: false };
      if (sha256(record.targetFile) !== record.baselineHash) {
        throw new Error(`Target stale cache changed during promotion: ${record.name}`);
      }
      writeTransaction('committing', committed, record.name, 'remove');
      fs.unlinkSync(record.targetFile);
      pendingMutation.applied = true;
      removed.push(record);
      committed.push(pendingMutation);
      pendingMutation = null;
      currentReport.files_removed = removed.length;
      verifyRemovedFiles([record]);
      if (failAfter > 0 && committed.length === failAfter) {
        throw new Error(`Injected failure after ${failAfter} mutations.`);
      }
      writeTransaction('committing', committed);
    }

    verifyPromotedFiles(plan.records);
    verifyRemovedFiles(plan.removedRecords);
    const postInventory = recursiveInventory(
      currentOptions.targetDir,
      new Set([
        ...plan.records.map((record) => record.name),
        ...plan.removedRecords.map((record) => record.name),
        path.basename(lockFile),
      ]),
    );
    if (!sameInventory(plan.targetInventory, postInventory)) {
      throw new Error('An unrelated target file changed during promotion.');
    }
    currentReport.unrelated_files_unchanged = true;
    currentReport.target_file_count_after =
      recursiveFileCount(currentOptions.targetDir) - (fs.existsSync(lockFile) ? 1 : 0);
    writeTransaction('complete', committed, null, null, {
      completed_at: new Date().toISOString(),
    });
  } catch (error) {
    if (activeTemp) removeFileQuietly(activeTemp);
    const rollbackMutations = [...committed];
    if (pendingMutation?.applied) rollbackMutations.push(pendingMutation);
    const rollbackResult = rollback(rollbackMutations, backupCacheDir, token);
    currentReport.files_rolled_back = rollbackResult.restored;
    currentReport.removed_files_rolled_back = rollbackResult.removedRestored;
    currentReport.rollback_errors.push(...rollbackResult.errors);
    if (rollbackResult.errors.length > 0) {
      writeTransaction('rollback_failed', rollbackMutations);
      throw new Error(
        `${errorMessage(error)} Rollback failures: ${rollbackResult.errors.join('; ')}`,
      );
    }
    currentReport.files_replaced = 0;
    currentReport.files_removed = 0;
    if (fs.existsSync(currentOptions.backupDir)) {
      writeTransaction('rolled_back', rollbackMutations);
    }
    throw error;
  } finally {
    removeFileQuietly(lockFile);
  }
}

function rollback(mutations, backupCacheDir, token) {
  const errors = [];
  let restored = 0;
  let removedRestored = 0;
  for (const mutation of [...mutations].reverse()) {
    const { record } = mutation;
    const backupFile = path.join(backupCacheDir, record.name);
    const rollbackTemp = `${record.targetFile}.codex-rollback-${token}.tmp`;
    try {
      removeFileQuietly(rollbackTemp);
      fs.copyFileSync(backupFile, rollbackTemp, fs.constants.COPYFILE_EXCL);
      syncFile(rollbackTemp);
      if (sha256(rollbackTemp) !== record.baselineHash) {
        throw new Error('rollback temporary hash mismatch');
      }
      atomicReplace(rollbackTemp, record.targetFile);
      if (sha256(record.targetFile) !== record.baselineHash) {
        throw new Error('restored target hash mismatch');
      }
      restored += 1;
      if (mutation.action === 'remove') removedRestored += 1;
    } catch (error) {
      removeFileQuietly(rollbackTemp);
      errors.push(`${record.name}: ${errorMessage(error)}`);
    }
  }
  return { errors, restored, removedRestored };
}

function verifyPromotedFiles(records) {
  for (const record of records) {
    if (sha256(record.targetFile) !== record.sourceHash) {
      throw new Error(`Final target verification failed: ${record.name}`);
    }
  }
}

function verifyRemovedFiles(records) {
  for (const record of records) {
    if (pathExists(record.targetFile)) {
      throw new Error(`Final target removal verification failed: ${record.name}`);
    }
  }
}

function pathExists(file) {
  try {
    fs.lstatSync(file);
    return true;
  } catch (error) {
    if (error?.code === 'ENOENT') return false;
    throw error;
  }
}

function directJsonNames(directory) {
  return fs.readdirSync(directory, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.toLowerCase().endsWith('.json'))
    .map((entry) => entry.name)
    .sort((left, right) => left.localeCompare(right, 'en'));
}

function checkedRegularFile(directory, name) {
  const file = path.join(directory, name);
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink()) {
    throw new Error(`Expected a regular non-symlink file: ${file}`);
  }
  return file;
}

function validateCacheStructure(file, name) {
  let value;
  try {
    value = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (error) {
    throw new Error(`Invalid source cache JSON ${name}: ${errorMessage(error)}`);
  }
  const expected = name.slice(0, -'.json'.length);
  if (value?.scriptId !== expected) {
    throw new Error(`Source scriptId does not match filename: ${name}`);
  }
  if (typeof value.sourceRootPath !== 'string' || !value.sourceRootPath.trim()) {
    throw new Error(`Source cache has no sourceRootPath: ${name}`);
  }
  if (!value.scriptSnapshot || !Array.isArray(value.scriptSnapshot.frames)) {
    throw new Error(`Source cache has no scriptSnapshot.frames: ${name}`);
  }
  if (
    !value.aiRoleExtraction ||
    value.aiRoleExtraction.status !== 'ready' ||
    !Array.isArray(value.aiRoleExtraction.roles)
  ) {
    throw new Error(`Source cache does not contain a ready role extraction: ${name}`);
  }
  for (const role of value.aiRoleExtraction.roles) {
    if (typeof role?.source_role_id !== 'string' || !Array.isArray(role?.stages)) {
      throw new Error(`Source cache contains an invalid extracted role: ${name}`);
    }
  }
  if (
    !value.mapping ||
    value.mapping.id !== `mapping-${expected}` ||
    value.mapping.scriptId !== expected ||
    !Array.isArray(value.mapping.rolePromptReplacements) ||
    !Array.isArray(value.mapping.roleAssemblies)
  ) {
    throw new Error(`Source cache contains an invalid mapping envelope: ${name}`);
  }
  if (typeof value.sourceFingerprint !== 'string' || !value.sourceFingerprint) {
    throw new Error(`Source cache contains an incomplete fingerprint envelope: ${name}`);
  }
  if (
    value.sourceContentFingerprint != null &&
    typeof value.sourceContentFingerprint !== 'string'
  ) {
    throw new Error(`Source cache contains an invalid content fingerprint: ${name}`);
  }
  return value;
}

function recursiveInventory(root, excludedRootNames) {
  const inventory = new Map();
  walk(root, '');
  return inventory;

  function walk(directory, relativeDirectory) {
    const entries = fs.readdirSync(directory, { withFileTypes: true })
      .sort((left, right) => left.name.localeCompare(right.name, 'en'));
    for (const entry of entries) {
      const relative = relativeDirectory
        ? path.join(relativeDirectory, entry.name)
        : entry.name;
      const absolute = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        walk(absolute, relative);
      } else if (entry.isFile()) {
        if (!relativeDirectory && excludedRootNames.has(entry.name)) continue;
        inventory.set(normalizeRelative(relative), sha256(absolute));
      } else {
        throw new Error(`Unsupported target entry type: ${absolute}`);
      }
    }
  }
}

function recursiveFileCount(root) {
  let count = 0;
  walk(root);
  return count;

  function walk(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const absolute = path.join(directory, entry.name);
      if (entry.isDirectory()) walk(absolute);
      else if (entry.isFile()) count += 1;
      else throw new Error(`Unsupported target entry type: ${absolute}`);
    }
  }
}

function sha256(file) {
  const hash = createHash('sha256');
  const fd = fs.openSync(file, 'r');
  const buffer = Buffer.allocUnsafe(1024 * 1024);
  try {
    let bytesRead;
    do {
      bytesRead = fs.readSync(fd, buffer, 0, buffer.length, null);
      if (bytesRead > 0) hash.update(buffer.subarray(0, bytesRead));
    } while (bytesRead > 0);
  } finally {
    fs.closeSync(fd);
  }
  return hash.digest('hex');
}

function syncFile(file) {
  const fd = fs.openSync(file, 'r+');
  try {
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
}

function atomicReplace(source, target) {
  const retryableCodes = new Set(['EACCES', 'EBUSY', 'EPERM']);
  for (let attempt = 0; ; attempt += 1) {
    try {
      fs.renameSync(source, target);
      return;
    } catch (error) {
      if (attempt >= 4 || !retryableCodes.has(error?.code)) throw error;
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 25 * (attempt + 1));
    }
  }
}

function acquireLock(lockFile, currentOptions, token) {
  const payload = `${JSON.stringify({
    token,
    pid: process.pid,
    source_dir: currentOptions.sourceDir,
    baseline_dir: currentOptions.baselineDir,
    acceptance_report: currentOptions.acceptanceReport,
    acceptance_report_sha256: '',
    acceptance_checks: {},
    acceptance_passed: false,
    started_at: new Date().toISOString(),
  }, null, 2)}\n`;
  fs.writeFileSync(lockFile, payload, { encoding: 'utf8', flag: 'wx' });
  syncFile(lockFile);
}

function writeDurableJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(temp, `${JSON.stringify(value, null, 2)}\n`, {
    encoding: 'utf8',
    flag: 'wx',
  });
  syncFile(temp);
  atomicReplace(temp, file);
  syncFile(file);
}

function probeReportPath(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const probe = `${file}.${process.pid}-${randomUUID()}.probe`;
  try {
    fs.writeFileSync(probe, 'probe', { encoding: 'utf8', flag: 'wx' });
    syncFile(probe);
  } finally {
    removeFileQuietly(probe);
  }
}

function sameStrings(left, right) {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

function sameInventory(left, right) {
  if (left.size !== right.size) return false;
  for (const [name, hash] of left) {
    if (right.get(name) !== hash) return false;
  }
  return true;
}

function requireDirectory(directory) {
  if (!fs.existsSync(directory) || !fs.statSync(directory).isDirectory()) {
    throw new Error(`Directory does not exist: ${directory}`);
  }
}

function requireDistinctDirectories(currentOptions) {
  const directories = [
    currentOptions.sourceDir,
    currentOptions.targetDir,
    currentOptions.baselineDir,
  ].map((directory) => fs.realpathSync.native(directory).toLowerCase());
  if (new Set(directories).size !== directories.length) {
    throw new Error('Source, target, and baseline directories must be distinct.');
  }
}

function isSameOrInside(candidate, parent) {
  const relative = path.relative(path.resolve(parent), path.resolve(candidate));
  return relative === '' || (!relative.startsWith('..') && !path.isAbsolute(relative));
}

function normalizeRelative(value) {
  return value.split(path.sep).join('/');
}

function removeFileQuietly(file) {
  try {
    fs.rmSync(file, { force: true });
  } catch {
    // Best-effort cleanup only; the backup remains available for recovery.
  }
}

function createReport(currentOptions) {
  return {
    api_used: false,
    status: 'running',
    apply: currentOptions.apply,
    source_dir: currentOptions.sourceDir,
    target_dir: currentOptions.targetDir,
    baseline_dir: currentOptions.baselineDir,
    backup_dir: currentOptions.backupDir,
    report_path: currentOptions.report,
    expected_count: currentOptions.expectedCount,
    remove_files: currentOptions.removeFiles,
    preflight_passed: false,
    files_scanned: 0,
    files_changed: 0,
    files_unchanged: 0,
    files_backed_up: 0,
    files_replaced: 0,
    files_removed: 0,
    files_rolled_back: 0,
    removed_files_rolled_back: 0,
    removed_file_count: 0,
    unrelated_file_count: 0,
    unrelated_files_unchanged: !currentOptions.apply,
    target_file_count_before: 0,
    target_file_count_after: 0,
    frame_count: 0,
    role_count: 0,
    stage_count: 0,
    rollback_errors: [],
    errors: [],
    rows: [],
    removed_rows: [],
  };
}

function createEmergencyReport(currentOptions) {
  return {
    api_used: false,
    status: 'failed',
    apply: currentOptions?.apply ?? process.argv.includes('--apply'),
    errors: [],
    rollback_errors: [],
  };
}

function writeReport(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(temp, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
  fs.renameSync(temp, file);
}

function rawArgValue(args, flag) {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : '';
}

function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}
