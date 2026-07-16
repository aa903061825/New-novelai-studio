import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a complete offline term review manifest and review shards',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-term-review-manifest-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final cacheDir = Directory('${tempRoot.path}/cache')
      ..createSync(recursive: true);
    final outputFile = File('${tempRoot.path}/manifest.json');
    final shardDir = Directory('${tempRoot.path}/shards');
    final classificationFile = File('${tempRoot.path}/classification.json')
      ..writeAsStringSync(jsonEncode({
        'positive:alternate hairstyle': {
          'category': 'other',
          'source': 'fixture-stale-classifier',
        },
        'positive:facial': {
          'category': 'upperBody',
          'source': 'fixture-stale-classifier',
        },
      }));
    final translationFile = File('${tempRoot.path}/translation.json')
      ..writeAsStringSync(jsonEncode({
        'alternate hairstyle_en2zh': {
          'translation': '替代发型',
          'source': 'fixture',
        },
      }));
    File('${cacheDir.path}/script-reisa.json')
        .writeAsStringSync(jsonEncode(_cacheFixture()));

    final result = await Process.run(
      'node',
      [
        'tool/build_script_recast_term_review_manifest.mjs',
        '--cache-dir',
        cacheDir.path,
        '--output',
        outputFile.path,
        '--shard-dir',
        shardDir.path,
        '--shard-size',
        '3',
        '--classification-cache',
        classificationFile.path,
        '--translation-cache',
        translationFile.path,
      ],
      workingDirectory: Directory.current.path,
    );

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final manifest =
        jsonDecode(outputFile.readAsStringSync()) as Map<String, dynamic>;
    expect(manifest['kind'], 'script_recast_term_membership_manifest');
    expect(manifest['api_used'], isFalse);
    expect(manifest['cache_file_count'], 1);
    expect(manifest['source_term_count'], 6);
    expect((manifest['cache_files'] as List), hasLength(1));
    expect(
      ((manifest['cache_files'] as List).single as Map)['sha256'],
      hasLength(64),
    );

    final terms = (manifest['terms'] as List).cast<Map>();
    final alternate = terms.singleWhere(
      (term) => term['normalized_term'] == 'alternate hairstyle',
    );
    expect(alternate['occurrence_count'], 2);
    expect(alternate['frame_count'], 2);
    expect(alternate['cache_count'], 1);
    expect(alternate['current_ai_role_count'], 0);
    expect(alternate['current_mapping_role_count'], 0);
    expect(alternate['translation_hint'], '替代发型');
    expect(
      (alternate['classification_hint'] as Map)['category'],
      'other',
    );
    expect(
      (((alternate['samples'] as List).first as Map)['role_ids'] as List),
      contains('role-reisa-blue-archive'),
    );

    final facial = terms.singleWhere(
      (term) => term['normalized_term'] == 'facial',
    );
    expect(facial['current_ai_role_count'], 1);
    expect(facial['current_mapping_role_count'], 1);

    final shardFiles = shardDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    expect(shardFiles, hasLength(2));
    final decisions = <Map>[];
    for (final shardFile in shardFiles) {
      final shard = jsonDecode(shardFile.readAsStringSync()) as Map;
      expect(shard['kind'], 'script_recast_term_membership_review_shard');
      expect(shard['api_used'], isFalse);
      expect(shard['manifest_sha256'], hasLength(64));
      decisions.addAll((shard['decisions'] as List).cast<Map>());
    }
    expect(decisions, hasLength(6));
    expect(decisions.map((item) => item['placement']).toSet(), {'unresolved'});
    expect(
      decisions.map((item) => item['term']).toSet(),
      terms.map((item) => item['term']).toSet(),
    );
  });
}

Map<String, dynamic> _cacheFixture() {
  return {
    'scriptId': 'script-reisa',
    'scriptName': 'Reisa fixture',
    'sourceRootPath': 'C:/fixture/reisa',
    'scriptSnapshot': {
      'frames': [
        {
          'index': 1,
          'fileName': 'nai_1.png',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': 'outdoors, masterpiece',
            'charCaptions': [
              'girl, alternate hairstyle, facial, twin drills',
            ],
          },
        },
        {
          'index': 2,
          'fileName': 'nai_2.png',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': 'outdoors, masterpiece',
            'charCaptions': [
              'girl, alternate hairstyle, twin drills',
            ],
          },
        },
      ],
    },
    'aiRoleExtraction': {
      'schema_version': 1,
      'status': 'ready',
      'roles': [
        {
          'source_role_id': 'role-reisa-blue-archive',
          'display_name': 'Reisa',
          'appearances': [
            {
              'source_id': 'slot-0',
              'source_kind': 'slot',
              'frame_indexes': [1, 2],
            },
          ],
          'prompt_terms': [
            {
              'id': 'facial',
              'text': 'facial',
              'category': 'upperBody',
              'frame_indexes': [1],
            },
          ],
          'stages': [],
        },
      ],
      'scene_terms': [
        {
          'id': 'outdoors',
          'text': 'outdoors',
          'category': 'scene',
          'frame_indexes': [1, 2],
        },
      ],
    },
    'mapping': {
      'rolePromptReplacements': [
        {
          'sourceRoleId': 'role-reisa-blue-archive',
          'rules': [
            {
              'id': 'facial-rule',
              'sourceTerms': [
                {
                  'id': 'facial',
                  'text': 'facial',
                  'category': 'upperBody',
                },
              ],
            },
          ],
        },
      ],
      'scenePromptReplacements': [],
    },
  };
}
