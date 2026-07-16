import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('apply synchronizes labels, clears review warnings, and backs up',
      () async {
    final fixture = await _createFixture('apply');
    addTearDown(fixture.dispose);

    final originalText = fixture.cacheFile.readAsStringSync();
    final result = await _runTool(fixture, apply: true);

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );

    final updated = _readMap(fixture.cacheFile);
    final role = _roles(updated).single;
    final aiStage = _stages(role).single;
    final assembly = _assemblies(updated).single;
    final mappingStage = _mappingStages(assembly).single;
    final replacement = _replacements(updated).single;

    expect(role['display_name'], 'Heroine reviewed');
    expect(role['warnings'], ['keep-role-warning']);
    expect(assembly['displayLabel'], 'Heroine reviewed');
    expect(assembly['sourceName'], 'Heroine reviewed');
    expect(replacement['displayLabel'], 'Heroine reviewed');
    expect(aiStage['label'], 'Red jacket');
    expect(aiStage['warnings'], ['keep-stage-warning']);
    expect(mappingStage['label'], 'Red jacket');

    // The semantic review is deliberately label-only.
    expect(updated['scriptId'], 'script-fixture');
    expect(role['source_role_id'], 'role-heroine');
    expect(aiStage['stage_id'], 'stage-red');
    expect(aiStage['frame_indexes'], [1, 2]);
    expect(aiStage['identity'], 'heroine');
    expect(aiStage['upper_clothing'], 'red jacket');
    expect(mappingStage['id'], 'stage-red');
    expect(mappingStage['frameIndexes'], [2, 1]);
    expect(mappingStage['targetCharacterId'], 'target-character');
    expect(replacement['targetCharacterId'], 'target-character');
    expect(
      ((replacement['rules'] as List).single as Map)['action'],
      'replace',
    );

    final backupFile = File('${fixture.backupDir.path}/cache.json');
    expect(backupFile.existsSync(), isTrue);
    expect(backupFile.readAsStringSync(), originalText);

    final report = _readMap(fixture.reportFile);
    expect(report['api_used'], isFalse);
    expect(report['apply'], isTrue);
    expect(report['files_scanned'], 1);
    expect(report['files_matched'], 1);
    expect(report['files_changed'], 1);
    expect(report['files_backed_up'], 1);
    expect(report['corrections_loaded'], 2);
    expect(report['corrections_matched'], 2);
    expect(report['errors'], isEmpty);
  });

  test('dry-run reports changes without writing cache or backup', () async {
    final fixture = await _createFixture('dry-run');
    addTearDown(fixture.dispose);

    final originalText = fixture.cacheFile.readAsStringSync();
    final result = await _runTool(fixture, apply: false);

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    expect(fixture.cacheFile.readAsStringSync(), originalText);
    expect(fixture.backupDir.existsSync(), isFalse);

    final report = _readMap(fixture.reportFile);
    expect(report['apply'], isFalse);
    expect(report['files_changed'], 1);
    expect(report['files_backed_up'], 0);
    expect(report['corrections_matched'], 2);
    expect(report['errors'], isEmpty);
  });

  test('bad frame signature fails closed without cache or backup writes',
      () async {
    final fixture = await _createFixture(
      'bad-signature',
      stageFrameIndexes: const [1, 999],
    );
    addTearDown(fixture.dispose);

    final originalText = fixture.cacheFile.readAsStringSync();
    final result = await _runTool(fixture, apply: true);

    expect(result.exitCode, isNot(0));
    expect(fixture.cacheFile.readAsStringSync(), originalText);
    expect(fixture.backupDir.existsSync(), isFalse);
    expect(
      fixture.reportFile.existsSync(),
      isTrue,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );

    final report = _readMap(fixture.reportFile);
    expect(report['api_used'], isFalse);
    expect(report['files_changed'], 0);
    expect(report['files_backed_up'], 0);
    expect(report['corrections_matched'], lessThan(2));
    expect(report['errors'], isNotEmpty);
  });
}

Future<_Fixture> _createFixture(
  String name, {
  List<int> stageFrameIndexes = const [2, 1],
}) async {
  final root = await Directory.systemTemp.createTemp(
    'script-recast-semantic-review-$name-',
  );
  final cacheDir = Directory('${root.path}/cache')..createSync();
  final sourceDir = Directory('${root.path}/source/story')
    ..createSync(recursive: true);
  final cacheFile = File('${cacheDir.path}/cache.json');
  cacheFile.writeAsStringSync(
    '${jsonEncode(_cacheFixture(sourceDir.path))}\n',
  );

  final normalizedSource = sourceDir.path.replaceAll('\\', '/').toUpperCase();
  final reviewFile = File('${root.path}/review.json');
  reviewFile.writeAsStringSync(
    jsonEncode({
      'role_labels': [
        {
          'source_root_path': '$normalizedSource/',
          'role_id': 'role-heroine',
          'display_name': 'Heroine reviewed',
        },
      ],
      'stage_labels': [
        {
          'source_root_path': '$normalizedSource/',
          'role_id': 'role-heroine',
          'stage_id': 'stage-red',
          'frame_indexes': stageFrameIndexes,
          'label': 'Red jacket',
        },
      ],
    }),
  );

  return _Fixture(
    root: root,
    cacheDir: cacheDir,
    cacheFile: cacheFile,
    reviewFile: reviewFile,
    reportFile: File('${root.path}/report.json'),
    backupDir: Directory('${root.path}/backup'),
  );
}

Future<ProcessResult> _runTool(_Fixture fixture, {required bool apply}) {
  return Process.run(
    'node',
    [
      'tool/apply_script_recast_semantic_review.mjs',
      '--cache-dir',
      fixture.cacheDir.path,
      '--review',
      fixture.reviewFile.path,
      '--report',
      fixture.reportFile.path,
      '--backup-dir',
      fixture.backupDir.path,
      if (apply) '--apply',
    ],
    workingDirectory: Directory.current.path,
  );
}

Map<String, dynamic> _cacheFixture(String sourceRootPath) {
  return {
    'scriptId': 'script-fixture',
    'sourceRootPath': sourceRootPath,
    'aiRoleExtraction': {
      'status': 'ready',
      'roles': [
        {
          'source_role_id': 'role-heroine',
          'display_name': 'Old heroine',
          'warnings': [
            'display_name_needs_manual_review',
            'keep-role-warning',
          ],
          'stages': [
            {
              'stage_id': 'stage-red',
              'label': 'Old stage',
              'frame_indexes': [1, 2],
              'identity': 'heroine',
              'upper_body': 'long hair',
              'lower_body': '',
              'upper_clothing': 'red jacket',
              'lower_clothing': 'black skirt',
              'warnings': [
                'label_needs_manual_review',
                'stage_label_needs_manual_review',
                'keep-stage-warning',
              ],
            },
          ],
        },
      ],
    },
    'mapping': {
      'scriptId': 'script-fixture',
      'roleAssemblies': [
        {
          'sourceRoleId': 'role-heroine',
          'displayLabel': 'Old heroine',
          'sourceName': 'Old heroine',
          'targetCharacterId': 'target-character',
          'stages': [
            {
              'id': 'stage-red',
              'label': 'Old stage',
              'frameIndexes': [2, 1],
              'sourceParts': {
                'identity': 'heroine',
                'upperClothing': 'red jacket',
              },
              'targetCharacterId': 'target-character',
            },
          ],
        },
      ],
      'rolePromptReplacements': [
        {
          'sourceRoleId': 'role-heroine',
          'displayLabel': 'Old heroine',
          'targetCharacterId': 'target-character',
          'rules': [
            {
              'id': 'rule-1',
              'action': 'replace',
              'sourceTerms': [
                {'text': 'heroine', 'category': 'identity'},
              ],
            },
          ],
        },
      ],
      'roleSwaps': [],
    },
  };
}

Map<String, dynamic> _readMap(File file) {
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _roles(Map<String, dynamic> cache) {
  final extraction = cache['aiRoleExtraction'] as Map<String, dynamic>;
  return (extraction['roles'] as List).cast<Map<String, dynamic>>();
}

List<Map<String, dynamic>> _stages(Map<String, dynamic> role) {
  return (role['stages'] as List).cast<Map<String, dynamic>>();
}

List<Map<String, dynamic>> _assemblies(Map<String, dynamic> cache) {
  final mapping = cache['mapping'] as Map<String, dynamic>;
  return (mapping['roleAssemblies'] as List).cast<Map<String, dynamic>>();
}

List<Map<String, dynamic>> _mappingStages(Map<String, dynamic> assembly) {
  return (assembly['stages'] as List).cast<Map<String, dynamic>>();
}

List<Map<String, dynamic>> _replacements(Map<String, dynamic> cache) {
  final mapping = cache['mapping'] as Map<String, dynamic>;
  return (mapping['rolePromptReplacements'] as List)
      .cast<Map<String, dynamic>>();
}

class _Fixture {
  const _Fixture({
    required this.root,
    required this.cacheDir,
    required this.cacheFile,
    required this.reviewFile,
    required this.reportFile,
    required this.backupDir,
  });

  final Directory root;
  final Directory cacheDir;
  final File cacheFile;
  final File reviewFile;
  final File reportFile;
  final Directory backupDir;

  Future<void> dispose() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}
