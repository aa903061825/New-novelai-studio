import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/workspace/workspace_json_codecs.dart';

void main() {
  group('RecastCacheJsonCodec', () {
    test('removes heavy payload keys from nested recast snapshots', () {
      final compacted = RecastCacheJsonCodec.compact({
        'scriptSnapshot': {
          'frames': [
            {
              'rawJson': jsonEncode({
                'reference_image_multiple': ['large'],
                'Description': 'girl',
              }),
              'parsed': {
                'generationParams': {
                  'reference_image_multiple': ['large'],
                  'steps': 28,
                },
                'sourcePayload': {
                  'Comment': jsonEncode({
                    'reference_strength_multiple': [0.5],
                    'sampler': 'k_euler',
                  }),
                },
              },
            },
          ],
        },
      });

      expect(compacted.changed, isTrue);
      final frame = compacted.value['scriptSnapshot']['frames'][0];
      expect(frame['rawJson'], isNot(contains('reference_image_multiple')));
      expect(frame['parsed']['generationParams'], {'steps': 28});
      expect(
        jsonDecode(frame['parsed']['sourcePayload']['Comment'] as String),
        {'sampler': 'k_euler'},
      );
    });
  });

  group('WorkspaceSanitizer', () {
    test('sanitizes sensitive keys and strings recursively', () {
      final sanitized = WorkspaceSanitizer.sanitizeMap({
        'safe': 'value',
        'apiKey': 'secret',
        'nested': {
          'token': 'secret',
          'name': 'kept',
          'headers': ['Bearer secret', 'plain'],
        },
        'proxy': 'http://127.0.0.1:7890',
      });

      expect(sanitized, {
        'safe': 'value',
        'nested': {
          'name': 'kept',
          'headers': ['plain'],
        },
      });
    });
  });
}
