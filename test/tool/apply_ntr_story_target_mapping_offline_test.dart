import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dynamic role mappings do not create global slot swaps', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-target-mapping-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final workspace = Directory('${tempRoot.path}/workspace');
    final cacheDir = Directory(
      '${workspace.path}/script_recast/cache',
    )..createSync(recursive: true);
    final sourceRoot = Directory('${tempRoot.path}/source')..createSync();
    final storyRoot = Directory('${sourceRoot.path}/story')..createSync();
    final cacheFile = File('${cacheDir.path}/script-dynamic-role.json');
    cacheFile.writeAsStringSync(
      jsonEncode(_dynamicRoleCache(storyRoot.path)),
    );

    final result = await Process.run(
      'node',
      [
        'tool/apply_ntr_story_target_mapping_offline.mjs',
        '--workspace',
        workspace.path,
        '--source-root',
        sourceRoot.path,
        '--backup-dir',
        '${tempRoot.path}/backup',
        '--report',
        '${tempRoot.path}/report.json',
        '--apply',
      ],
      workingDirectory: Directory.current.path,
    );

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final updated =
        jsonDecode(cacheFile.readAsStringSync()) as Map<String, dynamic>;
    final mapping = updated['mapping'] as Map<String, dynamic>;
    final replacements =
        (mapping['rolePromptReplacements'] as List).cast<Map>();
    final replacement = replacements.single;
    final rules = (replacement['rules'] as List).cast<Map>();

    expect(replacement['targetCharacterId'], isNotEmpty);
    expect(
      rules.any(
        (rule) =>
            rule['action'] == 'replace' &&
            (rule['sourceTerms'] as List).cast<Map>().any(
                  (term) =>
                      term['category'] == 'character' && term['text'] == 'girl',
                ),
      ),
      isTrue,
      reason: 'A generic-only role still needs an explicit identity rule.',
    );
    expect(mapping['roleSwaps'], isEmpty);
    expect(updated['updatedAt'], '2026-07-10T00:00:00.000Z');
  });
}

Map<String, dynamic> _dynamicRoleCache(String sourceRootPath) {
  return {
    'scriptId': 'script-dynamic-role',
    'scriptName': 'Dynamic role fixture',
    'sourceRootPath': sourceRootPath,
    'updatedAt': DateTime.utc(2026, 7, 10).toIso8601String(),
    'aiRoleExtraction': {
      'status': 'ready',
      'roles': [
        {
          'source_role_id': 'role-heroine',
          'source_kind': 'cross_slot',
          'display_name': 'heroine / girl',
          'raw_identity_tags': ['girl'],
          'appearances': [
            {
              'source_id': 'slot-0',
              'source_kind': 'slot',
              'frame_indexes': [1],
            },
            {
              'source_id': 'slot-1',
              'source_kind': 'slot',
              'frame_indexes': [2],
            },
          ],
          'stages': [
            {
              'stage_id': 'stage-1',
              'label': 'default',
              'frame_indexes': [1, 2],
              'identity': 'girl',
              'upper_body': '',
              'lower_body': '',
              'upper_clothing': 'red jacket',
              'lower_clothing': '',
            },
          ],
          'prompt_terms': [
            {
              'id': 'term-red-jacket',
              'text': 'red jacket',
              'category': 'upperClothing',
              'frame_indexes': [1, 2],
            },
          ],
        },
      ],
    },
    'mapping': {
      'id': 'mapping-script-dynamic-role',
      'scriptId': 'script-dynamic-role',
      'roleSwaps': [],
      'artistSwap': null,
      'rolePromptReplacements': [
        {
          'sourceRoleId': 'role-heroine',
          'displayLabel': 'Heroine',
          'sourcePreview': 'heroine, red jacket',
          'rules': [
            {
              'id': 'rule-heroine',
              'sourceTerms': [
                {
                  'id': 'term-red-jacket',
                  'text': 'red jacket',
                  'category': 'upperClothing',
                },
              ],
            },
          ],
        },
      ],
      'roleAssemblies': [
        {
          'sourceRoleId': 'role-heroine',
          'displayLabel': 'Heroine',
          'sourceAppearances': [
            {
              'sourceId': 'slot-0',
              'sourceKind': 'slot',
              'frameIndexes': [1],
            },
            {
              'sourceId': 'slot-1',
              'sourceKind': 'slot',
              'frameIndexes': [2],
            },
          ],
          'stages': [
            {
              'id': 'stage-1',
              'label': 'default',
              'frameIndexes': [1, 2],
              'sourceParts': {
                'identity': 'heroine',
                'upperClothing': 'red jacket',
              },
            },
          ],
        },
      ],
    },
  };
}
