import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('audits complete source terms without local repair', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-recast-complete-term-audit-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final cacheDir = Directory('${tempDir.path}${Platform.pathSeparator}cache')
      ..createSync(recursive: true);
    final sourceRoot = '${tempDir.path}${Platform.pathSeparator}source';
    final reportFile =
        File('${tempDir.path}${Platform.pathSeparator}report.json');
    final cacheFile =
        File('${cacheDir.path}${Platform.pathSeparator}cache.json');
    await cacheFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        _cacheJson(
          sourceRootPath: sourceRoot,
          promptTerms: [
            _term('term-double-bun', 'double bun', 'upperBody'),
          ],
          sceneTerms: [
            _term('scene-bedroom', 'bedroom', 'scene'),
          ],
          roleRules: [
            _rule(
              'legacy-double-bun-rule',
              _term('legacy-double-bun', 'double bun', 'upperBody'),
              targetPrompt: 'single braid',
            ),
          ],
          sceneRules: [
            _rule(
              'legacy-bedroom-rule',
              _term('scene-bedroom', 'bedroom', 'scene'),
              targetPrompt: 'sunny courtyard',
            ),
          ],
        ),
      ),
      encoding: utf8,
    );
    final before = await cacheFile.readAsString(encoding: utf8);

    final result = await Process.run(
      'node',
      [
        'tool/script_recast_complete_term_audit.mjs',
        '--cache-dir',
        cacheDir.path,
        '--source-root',
        sourceRoot,
        '--report',
        reportFile.path,
        '--report-unchanged',
      ],
      workingDirectory: Directory.current.path,
      runInShell: Platform.isWindows,
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(await cacheFile.readAsString(encoding: utf8), before);

    final report = jsonDecode(await reportFile.readAsString(encoding: utf8))
        as Map<String, dynamic>;
    expect(report['api_used'], isFalse);
    expect(report['eligible_cache_files'], 1);
    expect(report['files_changed'], 0);
    final rows = (report['rows'] as List).cast<Map<String, dynamic>>();
    expect(rows, hasLength(1));
    expect(rows.single['source_term_count'], greaterThanOrEqualTo(5));
    expect(
      (rows.single['target_regression_candidates'] as List)
          .cast<Map<String, dynamic>>()
          .map((row) => row['normalized']),
      containsAll(['gyaru', 'demon girl', 'cristal wings']),
    );
  });

  test('applies explicit schema while preserving confirmed mappings', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-recast-complete-term-repair-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final cacheDir = Directory('${tempDir.path}${Platform.pathSeparator}cache')
      ..createSync(recursive: true);
    final backupDir =
        Directory('${tempDir.path}${Platform.pathSeparator}backup');
    final sourceRoot = '${tempDir.path}${Platform.pathSeparator}source';
    final cacheFile =
        File('${cacheDir.path}${Platform.pathSeparator}cache.json');
    final schemaFile =
        File('${tempDir.path}${Platform.pathSeparator}schema.json');

    await cacheFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        _cacheJson(
          sourceRootPath: sourceRoot,
          promptTerms: const [],
          sceneTerms: const [],
          roleRules: [
            _rule(
              'legacy-double-bun-rule',
              _term('legacy-double-bun', 'double bun', 'upperBody'),
              targetPrompt: 'single braid',
            ),
          ],
          sceneRules: const [],
        ),
      ),
      encoding: utf8,
    );
    await schemaFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'caches': [
          {
            'scriptId': 'script-a',
            'rolePromptTerms': [
              {
                'sourceRoleId': 'role-a',
                'displayLabel': 'Role A',
                'terms': [
                  _term('term-double-bun', 'double bun', 'upperBody'),
                  _term('term-gyaru', 'gyaru', 'character'),
                ],
              },
            ],
            'sceneTerms': [
              _term('scene-bedroom', 'bedroom', 'scene'),
            ],
            'termCacheSuggestions': [
              {
                'text': 'gyaru',
                'translation': '辣妹',
                'category': 'character',
                'source': 'codex_offline',
              },
            ],
          },
        ],
      }),
      encoding: utf8,
    );

    final result = await Process.run(
      'node',
      [
        'tool/script_recast_complete_term_audit.mjs',
        '--cache-dir',
        cacheDir.path,
        '--source-root',
        sourceRoot,
        '--schema',
        schemaFile.path,
        '--apply',
        '--backup-dir',
        backupDir.path,
      ],
      workingDirectory: Directory.current.path,
      runInShell: Platform.isWindows,
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final updated = jsonDecode(await cacheFile.readAsString(encoding: utf8))
        as Map<String, dynamic>;
    final role = (updated['aiRoleExtraction']['roles'] as List).single
        as Map<String, dynamic>;
    expect(
      (role['prompt_terms'] as List).map((term) => term['text']),
      ['double bun', 'gyaru'],
    );
    final replacement = (updated['mapping']['rolePromptReplacements'] as List)
        .single as Map<String, dynamic>;
    final rules = (replacement['rules'] as List).cast<Map<String, dynamic>>();
    expect(rules, hasLength(2));
    expect(rules.first['id'], 'legacy-double-bun-rule');
    expect(rules.first['targetPrompt'], 'single braid');
    expect(
      ((rules.first['sourceTerms'] as List).single
          as Map<String, dynamic>)['id'],
      'term-double-bun',
    );
    expect(
      ((rules.last['sourceTerms'] as List).single
          as Map<String, dynamic>)['text'],
      'gyaru',
    );
    expect(updated['aiRoleExtraction']['scene_terms'], hasLength(1));
    expect(updated['mapping']['scenePromptReplacements'], hasLength(1));
    expect(updated['aiRoleExtraction']['term_cache_suggestions'], hasLength(1));
    final backups = backupDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList();
    expect(backups, hasLength(1));
  });
}

Map<String, dynamic> _cacheJson({
  required String sourceRootPath,
  required List<Map<String, dynamic>> promptTerms,
  required List<Map<String, dynamic>> sceneTerms,
  required List<Map<String, dynamic>> roleRules,
  required List<Map<String, dynamic>> sceneRules,
}) {
  return {
    'scriptId': 'script-a',
    'scriptName': 'Script A',
    'sourceRootPath': '$sourceRootPath/story-a',
    'sourceFingerprint': 'fingerprint',
    'updatedAt': '2026-06-27T00:00:00.000Z',
    'scriptSnapshot': {
      'id': 'script-a',
      'name': 'Script A',
      'rootPath': '$sourceRootPath/story-a',
      'frames': [
        {
          'index': 1,
          'path': 'frame-1.png',
          'parsed': {
            'baseCaption': 'bedroom, cinematic lighting',
            'charCaptions': [
              'girl, double bun, gyaru, demon girl, cristal wings',
            ],
            'negativeBase': 'bad anatomy',
            'negativeCharCaptions': ['extra arms'],
          },
        },
      ],
      'detectedSchema': 'v4Slotted',
      'parseWarnings': [],
      'meta': {'frameCount': 1},
    },
    'mapping': {
      'id': 'mapping-script-a',
      'scriptId': 'script-a',
      'roleSwaps': [],
      'artistSwap': null,
      'rolePromptReplacements': [
        {
          'sourceRoleId': 'role-a',
          'displayLabel': 'Role A',
          'sourcePreview': 'double bun',
          'rules': roleRules,
        },
      ],
      if (sceneRules.isNotEmpty)
        'scenePromptReplacements': [
          {
            'id': 'scene-ai',
            'label': 'Scene',
            'rules': sceneRules,
          },
        ],
    },
    'aiRoleExtraction': {
      'schema_version': 1,
      'status': 'ready',
      'confidence': 0.8,
      'roles': [
        {
          'source_role_id': 'role-a',
          'display_name': 'Role A',
          'appearances': [
            {
              'source_id': 'slot-0',
              'source_kind': 'slot',
              'frame_indexes': [1],
            },
          ],
          'stages': [],
          if (promptTerms.isNotEmpty) 'prompt_terms': promptTerms,
        },
      ],
      if (sceneTerms.isNotEmpty) 'scene_terms': sceneTerms,
    },
  };
}

Map<String, dynamic> _term(String id, String text, String category) {
  return {
    'id': id,
    'text': text,
    'category': category,
    'source_phrase': text,
    'source_location': 'slot-0 prompt',
    'frame_indexes': [1],
  };
}

Map<String, dynamic> _rule(
  String id,
  Map<String, dynamic> term, {
  String targetPrompt = '',
}) {
  return {
    'id': id,
    'sourceTerms': [term],
    if (targetPrompt.isNotEmpty) 'targetPrompt': targetPrompt,
  };
}
