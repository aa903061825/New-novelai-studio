import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('merges only complete conflict-free offline review shards', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-term-review-merge-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });
    final cacheDir = Directory('${tempRoot.path}/cache')
      ..createSync(recursive: true);
    final shardDir = Directory('${tempRoot.path}/shards');
    final manifestFile = File('${tempRoot.path}/manifest.json');
    final outputFile = File('${tempRoot.path}/review.json');
    File('${cacheDir.path}/fixture.json').writeAsStringSync(jsonEncode({
      'scriptId': 'fixture',
      'scriptName': 'Fixture',
      'sourceRootPath': 'C:/fixture',
      'scriptSnapshot': {
        'frames': [
          {
            'index': 1,
            'parseStatus': 'parsed',
            'parsed': {
              'baseCaption': 'outdoors',
              'charCaptions': [
                'girl, alternate hairstyle, facial',
              ],
            },
          },
        ],
      },
    }));
    final manifestResult = await Process.run(
      'node',
      [
        'tool/build_script_recast_term_review_manifest.mjs',
        '--cache-dir',
        cacheDir.path,
        '--output',
        manifestFile.path,
        '--shard-dir',
        shardDir.path,
        '--shard-size',
        '2',
        '--classification-cache',
        '${tempRoot.path}/missing-classification.json',
        '--translation-cache',
        '${tempRoot.path}/missing-translation.json',
      ],
      workingDirectory: Directory.current.path,
    );
    expect(manifestResult.exitCode, 0);

    for (final shardFile in shardDir.listSync().whereType<File>()) {
      final shard = jsonDecode(shardFile.readAsStringSync()) as Map;
      shard['reviewer'] = 'codex-fixture';
      shardFile.writeAsStringSync('${jsonEncode(shard)}\n');
    }

    final incompleteResult = await Process.run(
      'node',
      [
        'tool/merge_script_recast_term_reviews.mjs',
        '--manifest',
        manifestFile.path,
        '--shard-dir',
        shardDir.path,
        '--output',
        outputFile.path,
      ],
      workingDirectory: Directory.current.path,
    );
    expect(incompleteResult.exitCode, isNot(0));
    expect('${incompleteResult.stderr}', contains('unresolved'));
    expect(outputFile.existsSync(), isFalse);

    for (final shardFile in shardDir.listSync().whereType<File>()) {
      final shard = jsonDecode(shardFile.readAsStringSync()) as Map;
      shard['reviewer'] = 'codex-fixture';
      for (final decision in (shard['decisions'] as List).cast<Map>()) {
        if (decision['term'] == 'outdoors') {
          decision['placement'] = 'scene';
          decision['category'] = 'scene';
        } else if (decision['term'] == 'girl') {
          decision['placement'] = 'role';
          decision['category'] = 'character';
        } else if (decision['term'] == 'alternate hairstyle') {
          decision['placement'] = 'role';
          decision['category'] = 'upperBody';
        } else if (decision['term'] == 'facial') {
          decision['placement'] = 'exclude';
          decision['category'] = '';
        }
        decision['reason'] = 'fixture review';
      }
      shardFile.writeAsStringSync('${jsonEncode(shard)}\n');
    }

    final result = await Process.run(
      'node',
      [
        'tool/merge_script_recast_term_reviews.mjs',
        '--manifest',
        manifestFile.path,
        '--shard-dir',
        shardDir.path,
        '--output',
        outputFile.path,
      ],
      workingDirectory: Directory.current.path,
    );
    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final review = jsonDecode(outputFile.readAsStringSync()) as Map;
    expect(review['kind'], 'script_recast_term_membership_review');
    expect(review['api_used'], isFalse);
    expect(review['manifest_sha256'], hasLength(64));
    expect((review['cache_files'] as List), hasLength(1));
    final decisions = (review['decisions'] as List).cast<Map>();
    expect(decisions, hasLength(4));
    expect(decisions.map((item) => item['placement']),
        isNot(contains('unresolved')));
    expect(
      decisions.singleWhere((item) => item['term'] == 'facial')['placement'],
      'exclude',
    );
  });
}
