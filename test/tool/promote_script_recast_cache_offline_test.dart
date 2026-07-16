import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('promotion backs up and replaces only the approved cache set', () async {
    final fixture = await _createFixture('success');
    addTearDown(fixture.dispose);

    final result = await _runTool(fixture, apply: true);

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    expect(
        fixture.targetA.readAsStringSync(), fixture.sourceA.readAsStringSync());
    expect(
        fixture.targetB.readAsStringSync(), fixture.sourceB.readAsStringSync());
    expect(fixture.unrelated.readAsStringSync(), 'keep me');
    expect(
      File('${fixture.backupDir.path}/cache/script-a.json').readAsStringSync(),
      fixture.baselineA.readAsStringSync(),
    );
    expect(
        File('${fixture.backupDir.path}/manifest.json').existsSync(), isTrue);

    final report = _readMap(fixture.reportFile);
    expect(report['api_used'], isFalse);
    expect(report['status'], 'ok');
    expect(report['files_scanned'], 2);
    expect(report['files_backed_up'], 2);
    expect(report['files_replaced'], 2);
    expect(report['unrelated_files_unchanged'], isTrue);
    expect(
        report['target_file_count_after'], report['target_file_count_before']);
    expect(report['rollback_errors'], isEmpty);
  });

  test('approved stale cache is removed, reported, and backed up', () async {
    final fixture = await _createFixture('remove-success', withRemoval: true);
    addTearDown(fixture.dispose);

    final result = await _runTool(
      fixture,
      apply: true,
      removeFiles: [_staleName],
    );

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    expect(fixture.stale!.existsSync(), isFalse);
    expect(fixture.activeJson!.readAsStringSync(), 'active json');
    expect(fixture.unrelated.readAsStringSync(), 'keep me');
    expect(
      File('${fixture.backupDir.path}/cache/$_staleName').readAsStringSync(),
      fixture.baselineStale!.readAsStringSync(),
    );

    final report = _readMap(fixture.reportFile);
    expect(report['removed_file_count'], 1);
    expect(report['files_backed_up'], 3);
    expect(report['files_removed'], 1);
    expect(report['unrelated_file_count'], 2);
    expect(
      report['target_file_count_after'],
      (report['target_file_count_before'] as int) - 1,
    );
    expect((report['removed_rows'] as List), hasLength(1));
    final removedRow = (report['removed_rows'] as List).single as Map;
    expect(removedRow['file_name'], _staleName);
    expect(removedRow['baseline_sha256'], _sha256(fixture.baselineStale!));
    expect(removedRow['target_sha256'], _sha256(fixture.baselineStale!));
    expect(
      (report['acceptance_checks'] as Map)['stale_empty_source_removed'],
      isTrue,
    );

    final transaction =
        _readMap(File('${fixture.backupDir.path}/transaction.json'));
    expect(transaction['status'], 'complete');
    expect(transaction['removed_files'], [_staleName]);
  });

  test('stale cache target drift fails closed before backup', () async {
    final fixture = await _createFixture('remove-drift', withRemoval: true);
    addTearDown(fixture.dispose);
    fixture.stale!.writeAsStringSync(_cache(_staleId, 'drifted target'));

    final result = await _runTool(
      fixture,
      apply: true,
      removeFiles: [_staleName],
    );

    expect(result.exitCode, isNot(0));
    expect(
        fixture.stale!.readAsStringSync(), _cache(_staleId, 'drifted target'));
    expect(fixture.targetA.readAsStringSync(),
        fixture.baselineA.readAsStringSync());
    expect(fixture.backupDir.existsSync(), isFalse);
    expect(_readMap(fixture.reportFile)['status'], 'failed');
  });

  test('deletion without stale-source acceptance approval fails closed',
      () async {
    final fixture =
        await _createFixture('remove-unapproved', withRemoval: true);
    addTearDown(fixture.dispose);
    fixture.writeAcceptance(approveRemoval: false);

    final result = await _runTool(
      fixture,
      apply: true,
      removeFiles: [_staleName],
    );

    expect(result.exitCode, isNot(0));
    expect(fixture.stale!.existsSync(), isTrue);
    expect(fixture.backupDir.existsSync(), isFalse);
    expect(_readMap(fixture.reportFile)['status'], 'failed');
  });

  test('a failure after stale deletion restores the deletion and replacements',
      () async {
    final fixture = await _createFixture('remove-rollback', withRemoval: true);
    addTearDown(fixture.dispose);

    final result = await _runTool(
      fixture,
      apply: true,
      removeFiles: [_staleName],
      environment: {'SCRIPT_RECAST_PROMOTION_FAIL_AFTER': '3'},
    );

    expect(result.exitCode, isNot(0));
    expect(fixture.targetA.readAsStringSync(),
        fixture.baselineA.readAsStringSync());
    expect(fixture.targetB.readAsStringSync(),
        fixture.baselineB.readAsStringSync());
    expect(fixture.stale!.readAsStringSync(),
        fixture.baselineStale!.readAsStringSync());
    expect(fixture.activeJson!.readAsStringSync(), 'active json');
    final report = _readMap(fixture.reportFile);
    expect(report['files_replaced'], 0);
    expect(report['files_removed'], 0);
    expect(report['files_rolled_back'], 3);
    expect(report['removed_files_rolled_back'], 1);
    expect(report['rollback_errors'], isEmpty);
  });

  test('dry-run with deletion approval does not mutate target or create backup',
      () async {
    final fixture = await _createFixture('remove-dry-run', withRemoval: true);
    addTearDown(fixture.dispose);
    final staleBefore = fixture.stale!.readAsStringSync();

    final result = await _runTool(
      fixture,
      apply: false,
      removeFiles: [_staleName],
    );

    expect(result.exitCode, 0);
    expect(fixture.stale!.readAsStringSync(), staleBefore);
    expect(fixture.activeJson!.readAsStringSync(), 'active json');
    expect(fixture.backupDir.existsSync(), isFalse);
    final report = _readMap(fixture.reportFile);
    expect(report['files_removed'], 0);
    expect(report['preflight_passed'], isTrue);
    expect(report['unrelated_files_unchanged'], isTrue);
  });

  test('unchanged caches are backed up but not replaced', () async {
    final fixture = await _createFixture('unchanged');
    addTearDown(fixture.dispose);
    fixture.sourceA.writeAsStringSync(fixture.baselineA.readAsStringSync());
    fixture.writeAcceptance();

    final result = await _runTool(fixture, apply: true);

    expect(result.exitCode, 0);
    final report = _readMap(fixture.reportFile);
    expect(report['files_changed'], 1);
    expect(report['files_backed_up'], 2);
    expect(report['files_replaced'], 1);
    expect(fixture.targetA.readAsStringSync(),
        fixture.baselineA.readAsStringSync());
    expect(
        fixture.targetB.readAsStringSync(), fixture.sourceB.readAsStringSync());
  });

  test('baseline drift fails closed before creating a backup', () async {
    final fixture = await _createFixture('drift');
    addTearDown(fixture.dispose);
    fixture.targetA.writeAsStringSync(_cache('script-a', 'user change'));

    final result = await _runTool(fixture, apply: true);

    expect(result.exitCode, isNot(0));
    expect(
        fixture.targetA.readAsStringSync(), _cache('script-a', 'user change'));
    expect(fixture.targetB.readAsStringSync(),
        fixture.baselineB.readAsStringSync());
    expect(fixture.backupDir.existsSync(), isFalse);
    expect(_readMap(fixture.reportFile)['status'], 'failed');
  });

  test('an interrupted promotion restores every replaced cache', () async {
    final fixture = await _createFixture('rollback');
    addTearDown(fixture.dispose);

    final result = await _runTool(
      fixture,
      apply: true,
      environment: {'SCRIPT_RECAST_PROMOTION_FAIL_AFTER': '1'},
    );

    expect(result.exitCode, isNot(0));
    expect(fixture.targetA.readAsStringSync(),
        fixture.baselineA.readAsStringSync());
    expect(fixture.targetB.readAsStringSync(),
        fixture.baselineB.readAsStringSync());
    expect(fixture.unrelated.readAsStringSync(), 'keep me');
    expect(fixture.backupDir.existsSync(), isTrue);
    final report = _readMap(fixture.reportFile);
    expect(report['status'], 'failed');
    expect(report['files_replaced'], 0);
    expect(report['files_rolled_back'], 1);
    expect(report['rollback_errors'], isEmpty);
  });

  test('dry-run performs all hash gates without writing', () async {
    final fixture = await _createFixture('dry-run');
    addTearDown(fixture.dispose);

    final result = await _runTool(fixture, apply: false);

    expect(result.exitCode, 0);
    expect(fixture.targetA.readAsStringSync(),
        fixture.baselineA.readAsStringSync());
    expect(fixture.backupDir.existsSync(), isFalse);
    final report = _readMap(fixture.reportFile);
    expect(report['status'], 'ok');
    expect(report['preflight_passed'], isTrue);
    expect(report['files_changed'], 2);
    expect(report['files_replaced'], 0);
  });

  test('an unsafe report path cannot overwrite a cache on failure', () async {
    final fixture = await _createFixture('unsafe-report');
    addTearDown(fixture.dispose);
    final originalTarget = fixture.targetA.readAsStringSync();

    final result = await _runTool(
      fixture,
      apply: false,
      reportFile: fixture.targetA,
    );

    expect(result.exitCode, isNot(0));
    expect(fixture.targetA.readAsStringSync(), originalTarget);
    expect(_readMap(fixture.targetA)['scriptId'], 'script-a');
  });

  test('a failed semantic acceptance gate blocks promotion before backup',
      () async {
    final fixture = await _createFixture('failed-acceptance');
    addTearDown(fixture.dispose);
    fixture.writeAcceptance(
      checks: {
        ..._passingAcceptanceChecks,
        'frame_semantics_complete': false,
      },
    );

    final result = await _runTool(fixture, apply: true);

    expect(result.exitCode, isNot(0));
    expect(fixture.targetA.readAsStringSync(),
        fixture.baselineA.readAsStringSync());
    expect(fixture.targetB.readAsStringSync(),
        fixture.baselineB.readAsStringSync());
    expect(fixture.backupDir.existsSync(), isFalse);
    expect(_readMap(fixture.reportFile)['status'], 'failed');
  });

  test('an acceptance report cannot approve a later source mutation', () async {
    final fixture = await _createFixture('stale-acceptance');
    addTearDown(fixture.dispose);
    fixture.sourceA
        .writeAsStringSync(_cache('script-a', 'mutated after review'));

    final result = await _runTool(fixture, apply: true);

    expect(result.exitCode, isNot(0));
    expect(fixture.targetA.readAsStringSync(),
        fixture.baselineA.readAsStringSync());
    expect(fixture.backupDir.existsSync(), isFalse);
  });
}

const _passingAcceptanceChecks = <String, bool>{
  'term_review_complete': true,
  'mapping_safety_complete': true,
  'frame_semantics_complete': true,
  'role_field_semantics_complete': true,
  'cache_integrity_complete': true,
  'source_coverage_reviewed': true,
};
const _staleId = 'script-092611ab3cdc0fc1';
const _staleName = '$_staleId.json';

Future<_Fixture> _createFixture(
  String name, {
  bool withRemoval = false,
}) async {
  final root =
      await Directory.systemTemp.createTemp('script-recast-promote-$name-');
  final sourceDir = Directory('${root.path}/source')..createSync();
  final targetDir = Directory('${root.path}/target')..createSync();
  final baselineDir = Directory('${root.path}/baseline')..createSync();

  final sourceA = File('${sourceDir.path}/script-a.json')
    ..writeAsStringSync(_cache('script-a', 'new a'));
  final sourceB = File('${sourceDir.path}/script-b.json')
    ..writeAsStringSync(_cache('script-b', 'new b'));
  final baselineA = File('${baselineDir.path}/script-a.json')
    ..writeAsStringSync(_cache('script-a', 'old a'));
  final baselineB = File('${baselineDir.path}/script-b.json')
    ..writeAsStringSync(_cache('script-b', 'old b'));
  final targetA = File('${targetDir.path}/script-a.json')
    ..writeAsStringSync(baselineA.readAsStringSync());
  final targetB = File('${targetDir.path}/script-b.json')
    ..writeAsStringSync(baselineB.readAsStringSync());
  File? baselineStale;
  File? stale;
  File? activeJson;
  if (withRemoval) {
    baselineStale = File('${baselineDir.path}/$_staleName')
      ..writeAsStringSync(_cache(_staleId, 'stale baseline'));
    stale = File('${targetDir.path}/$_staleName')
      ..writeAsStringSync(baselineStale.readAsStringSync());
    activeJson = File('${targetDir.path}/script-active.json')
      ..writeAsStringSync('active json');
  }
  final unrelatedDir = Directory('${targetDir.path}/_invalid')..createSync();
  final unrelated = File('${unrelatedDir.path}/knowledge.json')
    ..writeAsStringSync('keep me');

  final fixture = _Fixture(
    root: root,
    sourceDir: sourceDir,
    targetDir: targetDir,
    baselineDir: baselineDir,
    backupDir: Directory('${root.path}/backup'),
    reportFile: File('${root.path}/report.json'),
    sourceA: sourceA,
    sourceB: sourceB,
    baselineA: baselineA,
    baselineB: baselineB,
    targetA: targetA,
    targetB: targetB,
    unrelated: unrelated,
    baselineStale: baselineStale,
    stale: stale,
    activeJson: activeJson,
    acceptanceFile: File('${root.path}/acceptance.json'),
  );
  fixture.writeAcceptance();
  return fixture;
}

Future<ProcessResult> _runTool(
  _Fixture fixture, {
  required bool apply,
  List<String> removeFiles = const [],
  Map<String, String>? environment,
  File? reportFile,
}) {
  return Process.run(
    'node',
    [
      'tool/promote_script_recast_cache_offline.mjs',
      '--source-dir',
      fixture.sourceDir.path,
      '--target-dir',
      fixture.targetDir.path,
      '--baseline-dir',
      fixture.baselineDir.path,
      '--acceptance-report',
      fixture.acceptanceFile.path,
      '--backup-dir',
      fixture.backupDir.path,
      '--report',
      (reportFile ?? fixture.reportFile).path,
      '--expected-count',
      '2',
      for (final removeFile in removeFiles) ...[
        '--remove-file',
        removeFile,
      ],
      if (apply) '--apply',
    ],
    environment: environment,
    includeParentEnvironment: true,
    workingDirectory: Directory.current.path,
  );
}

String _cache(String scriptId, String value) => '${jsonEncode({
          'scriptId': scriptId,
          'sourceRootPath': 'C:/fixture/$scriptId',
          'sourceFingerprint': '$scriptId|fingerprint|$value',
          'sourceContentFingerprint': 'schema:unknown|frames:0|$value',
          'scriptSnapshot': {'frames': <Object>[]},
          'aiRoleExtraction': {'status': 'ready', 'roles': <Object>[]},
          'mapping': {
            'id': 'mapping-$scriptId',
            'scriptId': scriptId,
            'rolePromptReplacements': <Object>[],
            'roleAssemblies': <Object>[],
          },
        })}\n';

Map<String, dynamic> _readMap(File file) =>
    jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

String _sha256(File file) => sha256.convert(file.readAsBytesSync()).toString();

class _Fixture {
  const _Fixture({
    required this.root,
    required this.sourceDir,
    required this.targetDir,
    required this.baselineDir,
    required this.backupDir,
    required this.reportFile,
    required this.sourceA,
    required this.sourceB,
    required this.baselineA,
    required this.baselineB,
    required this.targetA,
    required this.targetB,
    required this.unrelated,
    required this.baselineStale,
    required this.stale,
    required this.activeJson,
    required this.acceptanceFile,
  });

  final Directory root;
  final Directory sourceDir;
  final Directory targetDir;
  final Directory baselineDir;
  final Directory backupDir;
  final File reportFile;
  final File sourceA;
  final File sourceB;
  final File baselineA;
  final File baselineB;
  final File targetA;
  final File targetB;
  final File unrelated;
  final File? baselineStale;
  final File? stale;
  final File? activeJson;
  final File acceptanceFile;

  void writeAcceptance({
    Map<String, bool>? checks,
    bool includeRemovedFiles = true,
    bool approveRemoval = true,
  }) {
    final files = [sourceA, sourceB]
        .map((file) => {
              'file_name': file.uri.pathSegments.last,
              'sha256': sha256.convert(file.readAsBytesSync()).toString(),
            })
        .toList()
      ..sort((left, right) => (left['file_name'] as String)
          .compareTo(right['file_name'] as String));
    final acceptanceChecks = <String, bool>{
      ..._passingAcceptanceChecks,
      if (baselineStale != null && approveRemoval)
        'stale_empty_source_removed': true,
      ...?checks,
    };
    final acceptance = <String, dynamic>{
      'kind': 'script_recast_promotion_acceptance',
      'schema_version': 1,
      'api_used': false,
      'cache_dir': sourceDir.absolute.path,
      'cache_files': files,
      'checks': acceptanceChecks,
    };
    if (baselineStale != null && includeRemovedFiles) {
      acceptance['removed_cache_files'] = [
        {
          'file_name': _staleName,
          'sha256': sha256.convert(baselineStale!.readAsBytesSync()).toString(),
        },
      ];
    }
    acceptanceFile.writeAsStringSync('${jsonEncode(acceptance)}\n');
  }

  void dispose() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}
