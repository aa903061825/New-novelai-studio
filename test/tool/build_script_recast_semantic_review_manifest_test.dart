import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('groups duplicate sources and writes stable evidence-backed shards',
      () async {
    final fixture = await _ManifestFixture.create();
    addTearDown(fixture.dispose);

    fixture.writeCache(
      'a-one.json',
      _cache(
        scriptId: 'script-alpha-1',
        scriptName: 'Alpha Story',
        sourceRootPath: r'C:\Stories\Alpha',
        roleFrameCount: 4,
      ),
    );
    fixture.writeCache(
      'A-two.json',
      _cache(
        scriptId: 'script-alpha-2',
        scriptName: 'Alpha Story Duplicate',
        sourceRootPath: 'c:/stories/alpha/',
        roleFrameCount: 4,
      ),
    );
    fixture.writeCache(
      'beta.json',
      _cache(
        scriptId: 'script-beta',
        scriptName: 'Beta Story',
        sourceRootPath: r'C:\Stories\Beta',
        roleFrameCount: 1,
        includeRoleWarning: false,
        stageWarning: 'stage_label_needs_manual_review',
      ),
    );
    fixture.writeCache(
      'gamma.json',
      _cache(
        scriptId: 'script-gamma',
        scriptName: 'Gamma Story',
        sourceRootPath: r'C:\Stories\Gamma',
        roleFrameCount: 2,
        includeStageWarning: false,
      ),
    );

    final first = await fixture.runGenerator(fixture.firstOutput);
    final second = await fixture.runGenerator(fixture.secondOutput);

    expect(
      first.exitCode,
      0,
      reason: 'stdout:\n${first.stdout}\nstderr:\n${first.stderr}',
    );
    expect(
      second.exitCode,
      0,
      reason: 'stdout:\n${second.stdout}\nstderr:\n${second.stderr}',
    );

    for (final name in ['manifest.json', 'shard_1.json', 'shard_2.json']) {
      expect(
        File('${fixture.firstOutput.path}/$name').readAsStringSync(),
        File('${fixture.secondOutput.path}/$name').readAsStringSync(),
        reason: '$name should be byte-stable across runs',
      );
    }

    final manifest = fixture.readJson(fixture.firstOutput, 'manifest.json');
    expect(manifest['api_used'], isFalse);
    expect(manifest['mode'], 'read_only');
    expect(manifest['shard_count'], 2);
    expect((manifest['sources'] as List), hasLength(3));

    final alpha = (manifest['sources'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((source) => source['script_name'] == 'Alpha Story');
    expect(alpha['source_root_path'], r'C:\Stories\Alpha');
    expect(alpha['cache_files'], ['a-one.json', 'A-two.json']);
    expect(alpha['script_ids'], ['script-alpha-1', 'script-alpha-2']);
    expect((alpha['roles'] as List), hasLength(1));
    expect((alpha['stages'] as List), hasLength(1));

    final role = (alpha['roles'] as List).single as Map<String, dynamic>;
    expect(role['role_id'], 'role-review');
    expect(role['display_name'], 'Review Role');
    expect(role['canonical_name'], 'review_character');
    expect(role['raw_identity_tags'], ['review_character', 'girl']);
    expect(role['frame_indexes'], [1, 2, 3, 4]);
    expect((role['char_caption_evidence'] as List), hasLength(3));
    expect(role['char_caption_evidence'], [
      {
        'frame_index': 1,
        'source_id': 'slot-1',
        'slot_index': 1,
        'char_caption': 'slot one frame 1',
      },
      {
        'frame_index': 2,
        'source_id': 'slot-1',
        'slot_index': 1,
        'char_caption': 'slot one frame 2',
      },
      {
        'frame_index': 3,
        'source_id': 'slot-1',
        'slot_index': 1,
        'char_caption': 'slot one frame 3',
      },
    ]);

    final stage = (alpha['stages'] as List).single as Map<String, dynamic>;
    expect(stage['role_id'], 'role-review');
    expect(stage['stage_id'], 'stage-review');
    expect(stage['current_label'], 'Needs Review');
    expect(stage['frame_indexes'], [2, 3]);
    expect(stage['evidence_terms'], ['white shirt', 'blue skirt']);
    expect(stage['identity'], 'review_character');
    expect(stage['upper_body'], 'long hair');
    expect(stage['lower_body'], 'long legs');
    expect(stage['upper_clothing'], 'white shirt');
    expect(stage['lower_clothing'], 'blue skirt');
    expect(stage['char_caption_evidence'], [
      {
        'frame_index': 2,
        'source_id': 'slot-1',
        'slot_index': 1,
        'char_caption': 'slot one frame 2',
      },
      {
        'frame_index': 3,
        'source_id': 'slot-1',
        'slot_index': 1,
        'char_caption': 'slot one frame 3',
      },
    ]);

    final shards = [
      fixture.readJson(fixture.firstOutput, 'shard_1.json'),
      fixture.readJson(fixture.firstOutput, 'shard_2.json'),
    ];
    final alphaShardCount = shards.where((shard) {
      return (shard['sources'] as List).cast<Map>().any(
            (source) =>
                (source['cache_files'] as List).contains('a-one.json') ||
                (source['cache_files'] as List).contains('A-two.json'),
          );
    }).length;
    expect(alphaShardCount, 1, reason: 'same-source caches must not be split');

    final assignedPaths = shards
        .expand((shard) => (shard['sources'] as List).cast<Map>())
        .map((source) => source['source_root_path'])
        .toList();
    expect(assignedPaths, hasLength(3));
    expect(assignedPaths.toSet(), hasLength(3));
  });

  test('fails closed when duplicate caches have different AI structures',
      () async {
    final fixture = await _ManifestFixture.create();
    addTearDown(fixture.dispose);

    final firstCache = _cache(
      scriptId: 'script-one',
      scriptName: 'Story',
      sourceRootPath: r'C:\Stories\Same',
      roleFrameCount: 2,
    );
    final secondCache = _cache(
      scriptId: 'script-two',
      scriptName: 'Story Duplicate',
      sourceRootPath: 'c:/stories/same/',
      roleFrameCount: 2,
    );
    final roles = ((secondCache['aiRoleExtraction'] as Map)['roles'] as List);
    (roles.first as Map)['display_name'] = 'Different Role';

    fixture.writeCache('one.json', firstCache);
    fixture.writeCache('two.json', secondCache);
    final before = fixture.cacheContents();

    final result = await fixture.runGenerator(fixture.firstOutput);

    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('inconsistent AI structure'));
    expect(File('${fixture.firstOutput.path}/manifest.json').existsSync(),
        isFalse);
    expect(fixture.cacheContents(), before,
        reason: 'cache files are read-only');
  });
}

class _ManifestFixture {
  final Directory root;
  final Directory cacheDir;
  final Directory firstOutput;
  final Directory secondOutput;

  const _ManifestFixture({
    required this.root,
    required this.cacheDir,
    required this.firstOutput,
    required this.secondOutput,
  });

  static Future<_ManifestFixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'script-recast-semantic-review-manifest-test-',
    );
    return _ManifestFixture(
      root: root,
      cacheDir: Directory('${root.path}/cache')..createSync(),
      firstOutput: Directory('${root.path}/output-one'),
      secondOutput: Directory('${root.path}/output-two'),
    );
  }

  void writeCache(String filename, Map<String, dynamic> cache) {
    File('${cacheDir.path}/$filename').writeAsStringSync(jsonEncode(cache));
  }

  Future<ProcessResult> runGenerator(Directory outputDir) {
    return Process.run(
      'node',
      [
        'tool/build_script_recast_semantic_review_manifest.mjs',
        '--cache-dir',
        cacheDir.path,
        '--output-dir',
        outputDir.path,
        '--shards',
        '2',
      ],
      workingDirectory: Directory.current.path,
    );
  }

  Map<String, dynamic> readJson(Directory directory, String filename) {
    return jsonDecode(File('${directory.path}/$filename').readAsStringSync())
        as Map<String, dynamic>;
  }

  Map<String, String> cacheContents() {
    final files = cacheDir.listSync().whereType<File>().toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    return {for (final file in files) file.path: file.readAsStringSync()};
  }

  Future<void> dispose() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}

Map<String, dynamic> _cache({
  required String scriptId,
  required String scriptName,
  required String sourceRootPath,
  required int roleFrameCount,
  bool includeRoleWarning = true,
  bool includeStageWarning = true,
  String stageWarning = 'label_needs_manual_review',
}) {
  final frameIndexes = [
    for (var index = 1; index <= roleFrameCount; index++) index
  ];
  final stageIndexes = roleFrameCount >= 3
      ? [2, 3]
      : frameIndexes.take(1).toList(growable: false);
  return {
    'scriptId': scriptId,
    'scriptName': scriptName,
    'sourceRootPath': sourceRootPath,
    'aiRoleExtraction': {
      'status': 'ready',
      'roles': [
        {
          'source_role_id': 'role-review',
          'display_name': 'Review Role',
          'canonical_name': 'review_character',
          'raw_identity_tags': ['review_character', 'girl'],
          'frame_indexes': frameIndexes,
          'appearances': [
            {
              'source_id': 'slot-1',
              'source_kind': 'slot',
              'frame_indexes': frameIndexes,
            },
          ],
          'warnings': includeRoleWarning
              ? ['display_name_needs_manual_review']
              : ['unrelated_role_warning'],
          'stages': [
            {
              'stage_id': 'stage-review',
              'label': 'Needs Review',
              'frame_indexes': stageIndexes,
              'evidence_terms': ['white shirt', 'blue skirt'],
              'identity': 'review_character',
              'upper_body': 'long hair',
              'lower_body': 'long legs',
              'upper_clothing': 'white shirt',
              'lower_clothing': 'blue skirt',
              'warnings': includeStageWarning
                  ? [stageWarning]
                  : ['unrelated_stage_warning'],
            },
            {
              'stage_id': 'stage-clean',
              'label': 'Clean Label',
              'frame_indexes': frameIndexes.take(1).toList(),
              'warnings': <String>[],
            },
          ],
        },
        {
          'source_role_id': 'role-clean',
          'display_name': 'Clean Role',
          'canonical_name': '',
          'raw_identity_tags': ['girl'],
          'frame_indexes': frameIndexes,
          'appearances': [
            {
              'source_id': 'slot-0',
              'source_kind': 'slot',
              'frame_indexes': frameIndexes,
            },
          ],
          'warnings': <String>[],
          'stages': <Map<String, dynamic>>[],
        },
      ],
    },
    'scriptSnapshot': {
      'frames': [
        for (final index in frameIndexes)
          {
            'index': index,
            'parsed': {
              'charCaptions': [
                'slot zero frame $index',
                'slot one frame $index',
              ],
            },
          },
      ],
    },
  };
}
