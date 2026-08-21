import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/services/script_recast_parser_service.dart';

void main() {
  test('keeps the latest complete cache under the current path-derived id',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'script-recast-latest-cache-migration-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final workspace = Directory(_join(root.path, 'workspace'))
      ..createSync(recursive: true);
    final cacheDir = Directory(
      _join(workspace.path, 'script_recast', 'cache'),
    )..createSync(recursive: true);
    final sourceRoot = Directory(_join(root.path, 'source'))
      ..createSync(recursive: true);
    final scriptDir = Directory(_join(sourceRoot.path, 'Moved Script'))
      ..createSync(recursive: true);
    File(_join(scriptDir.path, '001.json')).writeAsStringSync('{}');
    final canonicalId =
        ScriptRecastParserService.scriptIdForDirectory(scriptDir);
    const oldId = 'script-old-location';
    const contentFingerprint = 'schema:test|frames:1|same-content';

    final oldCache = _cache(
      scriptId: oldId,
      sourceRootPath: scriptDir.path,
      contentFingerprint: contentFingerprint,
      updatedAt: '2026-07-20T10:00:00Z',
      displayName: '旧角色',
      categories: const ['NTR'],
      finalized: true,
    );
    final latestCache = _cache(
      scriptId: canonicalId,
      sourceRootPath: scriptDir.path,
      contentFingerprint: contentFingerprint,
      updatedAt: '2026-07-21T10:00:00Z',
      displayName: '最新角色',
    );
    File(_join(cacheDir.path, '$oldId.json'))
        .writeAsStringSync(jsonEncode(oldCache));
    File(_join(cacheDir.path, '$canonicalId.json'))
        .writeAsStringSync(jsonEncode(latestCache));
    final overrideDir = Directory(_join(root.path, 'overrides'))
      ..createSync(recursive: true);
    final overrideCache = _cache(
      scriptId: canonicalId,
      sourceRootPath: scriptDir.path,
      contentFingerprint: contentFingerprint,
      updatedAt: '2026-07-22T10:00:00Z',
      displayName: 'Override Latest',
    );
    File(_join(overrideDir.path, '$canonicalId.json'))
        .writeAsStringSync(jsonEncode(overrideCache));
    final assignments = File(
      _join(workspace.path, 'script_recast',
          'exhibition_category_assignments.json'),
    )..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({
              'NTR': [oldId],
            })}\n',
      );

    final dryRun = await _runMigration(
      cacheDir: cacheDir,
      sourceRoot: sourceRoot,
      workspace: workspace,
      overrideDir: overrideDir,
    );
    expect(dryRun.exitCode, 0, reason: dryRun.stderr as String?);
    final dryReport = jsonDecode(dryRun.stdout as String) as Map;
    expect(dryReport['input_cache_count'], 2);
    expect(dryReport['output_cache_count'], 1);
    expect(dryReport['removed_cache_count'], 1);
    expect(dryReport['override_used_count'], 1);
    expect(File(_join(cacheDir.path, '$oldId.json')).existsSync(), isTrue);

    final backupDir = Directory(_join(root.path, 'backup'));
    final applied = await _runMigration(
      cacheDir: cacheDir,
      sourceRoot: sourceRoot,
      workspace: workspace,
      overrideDir: overrideDir,
      apply: true,
      backupDir: backupDir,
    );
    expect(
      applied.exitCode,
      0,
      reason: 'stdout:\n${applied.stdout}\nstderr:\n${applied.stderr}',
    );

    expect(File(_join(cacheDir.path, '$oldId.json')).existsSync(), isFalse);
    final migratedFile = File(_join(cacheDir.path, '$canonicalId.json'));
    final migrated = jsonDecode(migratedFile.readAsStringSync()) as Map;
    expect(migrated['scriptId'], canonicalId);
    expect(migrated['aiRoleExtractionFinalized'], isTrue);
    expect(migrated['aiRoleExtractionDraftCollapsed'], isTrue);
    expect(migrated['exhibitionCategoryNames'], ['NTR']);
    expect(
      ((migrated['aiRoleExtraction'] as Map)['roles'] as List)
          .single['display_name'],
      'Override Latest',
    );
    expect((migrated['mapping'] as Map)['scriptId'], canonicalId);
    expect((migrated['mapping'] as Map)['id'], 'mapping-$canonicalId');
    expect((migrated['scriptSnapshot'] as Map)['id'], canonicalId);
    expect(
      migrated['sourceFingerprint'].toString().split('|').first,
      canonicalId,
    );
    expect(
      jsonDecode(assignments.readAsStringSync())['NTR'],
      [canonicalId],
    );
    expect(
      File(_join(backupDir.path, 'cache', '$oldId.json')).existsSync(),
      isTrue,
    );
    expect(
      File(_join(backupDir.path, 'cache', '$canonicalId.json')).existsSync(),
      isTrue,
    );

    final finalDryRun = await _runMigration(
      cacheDir: cacheDir,
      sourceRoot: sourceRoot,
      workspace: workspace,
    );
    final finalReport = jsonDecode(finalDryRun.stdout as String) as Map;
    expect(finalReport['changed_output_count'], 0);
    expect(finalReport['removed_cache_count'], 0);
    expect(finalReport['incomplete_cache_count'], 0);
  });

  test('prefers a merged canonical role over a newer same-content split',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'script-recast-merged-role-migration-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final workspace = Directory(_join(root.path, 'workspace'))
      ..createSync(recursive: true);
    final cacheDir = Directory(
      _join(workspace.path, 'script_recast', 'cache'),
    )..createSync(recursive: true);
    final sourceRoot = Directory(_join(root.path, 'source'))
      ..createSync(recursive: true);
    final scriptDir = Directory(_join(sourceRoot.path, 'Ayaka Script'))
      ..createSync(recursive: true);
    File(_join(scriptDir.path, '001.json')).writeAsStringSync('{}');
    final canonicalId =
        ScriptRecastParserService.scriptIdForDirectory(scriptDir);
    const oldId = 'script-old-ayaka';
    const contentFingerprint = 'schema:test|frames:1|same-ayaka-content';

    final merged = _cache(
      scriptId: oldId,
      sourceRootPath: scriptDir.path,
      contentFingerprint: contentFingerprint,
      updatedAt: '2026-07-20T10:00:00Z',
      displayName: 'kamisato ayaka / 神里绫华',
      finalized: true,
    );
    _setAyakaRoles(merged, split: false);
    final split = _cache(
      scriptId: canonicalId,
      sourceRootPath: scriptDir.path,
      contentFingerprint: contentFingerprint,
      updatedAt: '2026-07-21T10:00:00Z',
      displayName: 'kamisato ayaka / 神里绫华',
      finalized: true,
    );
    _setAyakaRoles(split, split: true);
    File(_join(cacheDir.path, '$oldId.json'))
        .writeAsStringSync(jsonEncode(merged));
    File(_join(cacheDir.path, '$canonicalId.json'))
        .writeAsStringSync(jsonEncode(split));

    final result = await _runMigration(
      cacheDir: cacheDir,
      sourceRoot: sourceRoot,
      workspace: workspace,
    );

    expect(result.exitCode, 0, reason: result.stderr as String?);
    final report = jsonDecode(result.stdout as String) as Map;
    final row = (report['rows'] as List).single as Map;
    expect(row['winner_file'], '$oldId.json');
    expect(row['role_count'], 1);
  });
}

Future<ProcessResult> _runMigration({
  required Directory cacheDir,
  required Directory sourceRoot,
  required Directory workspace,
  bool apply = false,
  Directory? backupDir,
  Directory? overrideDir,
}) {
  return Process.run(
    'node',
    [
      'tool/migrate_script_recast_latest_caches_20260721.mjs',
      '--cache-dir',
      cacheDir.path,
      '--source-root',
      sourceRoot.path,
      '--workspace-root',
      workspace.path,
      if (overrideDir != null) ...['--override-dir', overrideDir.path],
      if (apply) '--apply',
      if (backupDir != null) ...['--backup-dir', backupDir.path],
    ],
    workingDirectory: Directory.current.path,
  );
}

Map<String, dynamic> _cache({
  required String scriptId,
  required String sourceRootPath,
  required String contentFingerprint,
  required String updatedAt,
  required String displayName,
  List<String> categories = const [],
  bool finalized = false,
}) {
  const roleId = 'slot-0';
  return {
    'scriptId': scriptId,
    'scriptName': 'Moved Script',
    'sourceRootPath': sourceRootPath,
    'sourceFingerprint': '$scriptId|source|frame',
    'sourceContentFingerprint': contentFingerprint,
    'updatedAt': updatedAt,
    if (categories.isNotEmpty) 'exhibitionCategoryNames': categories,
    if (finalized) 'aiRoleExtractionFinalized': true,
    if (finalized) 'aiRoleExtractionDraftCollapsed': true,
    'mapping': {
      'id': 'mapping-$scriptId',
      'scriptId': scriptId,
      'roleSwaps': [],
      'roleAssemblies': [],
      'rolePromptReplacements': [
        {
          'sourceRoleId': roleId,
          'displayLabel': displayName,
          'rules': [
            {
              'id': 'rule-1',
              'sourceTerms': [
                {
                  'id': 'term-1',
                  'text': 'blue eyes',
                  'category': 'body',
                },
              ],
            },
          ],
        },
      ],
      'scenePromptReplacements': [],
    },
    'aiRoleExtraction': {
      'status': 'ready',
      'roles': [
        {
          'source_role_id': roleId,
          'display_name': displayName,
          'prompt_terms': [
            {
              'id': 'term-1',
              'text': 'blue eyes',
              'category': 'body',
            },
          ],
          'stages': [],
        },
      ],
      'attention_items': [],
      'scene_terms': [],
    },
    'scriptSnapshot': {
      'id': scriptId,
      'name': 'Moved Script',
      'rootPath': sourceRootPath,
      'frames': [
        {
          'index': 1,
          'fileName': '001.json',
          'sourcePath': _join(sourceRootPath, '001.json'),
          'parsed': {
            'baseCaption': '',
            'charCaptions': ['blue eyes'],
          },
        },
      ],
      'meta': <String, dynamic>{},
    },
  };
}

void _setAyakaRoles(Map<String, dynamic> cache, {required bool split}) {
  final roles = <Map<String, dynamic>>[
    _ayakaRole(
      id: 'role-kamisato-ayaka',
      termId: 'term-ayaka',
      term: 'kamisato ayaka',
      frames: split ? const [1] : const [1, 2],
    ),
    if (split)
      _ayakaRole(
        id: 'role-kamisato-ayaka-springbloom-missive',
        termId: 'term-springbloom',
        term: 'kamisato ayaka (springbloom missive)',
        franchise: 'springbloom missive',
        frames: const [2],
      ),
  ];
  (cache['aiRoleExtraction'] as Map)['roles'] = roles;
  (cache['mapping'] as Map)['rolePromptReplacements'] = [
    for (final role in roles)
      {
        'sourceRoleId': role['source_role_id'],
        'displayLabel': role['display_name'],
        'rules': [
          {
            'id': 'rule-${role['source_role_id']}',
            'sourceTerms': role['prompt_terms'],
          },
        ],
      },
  ];
}

Map<String, dynamic> _ayakaRole({
  required String id,
  required String termId,
  required String term,
  required List<int> frames,
  String franchise = '',
}) {
  return {
    'source_role_id': id,
    'source_kind': 'slot',
    'display_name': term,
    'canonical_name': 'kamisato ayaka',
    'franchise': franchise,
    'frame_indexes': frames,
    'appearances': [
      {
        'source_id': 'slot-0',
        'source_kind': 'slot',
        'frame_indexes': frames,
      },
    ],
    'prompt_terms': [
      {
        'id': termId,
        'text': term,
        'category': 'identity',
        'frame_indexes': frames,
      },
    ],
    'stages': <Map<String, dynamic>>[],
  };
}

String _join(String first, String second, [String? third]) {
  final joined = '$first${Platform.pathSeparator}$second';
  return third == null ? joined : '$joined${Platform.pathSeparator}$third';
}
