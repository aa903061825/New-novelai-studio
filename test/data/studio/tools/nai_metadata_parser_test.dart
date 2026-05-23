import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/tools/nai_metadata_parser.dart';

void main() {
  group('NaiMetadataParser', () {
    test('uses a raw prompt string as prompt and raw content fallback', () {
      final result = NaiMetadataParser.parseString(
        'masterpiece, quiet atelier, soft rain',
      );

      expect(result.prompt, 'masterpiece, quiet atelier, soft rain');
      expect(result.rawContent, 'masterpiece, quiet atelier, soft rain');
      expect(result.parameters, isEmpty);
      expect(result.hasStructuredMetadata, isFalse);
    });

    test('extracts Description prompt and JSON Comment parameters', () {
      final result = NaiMetadataParser.parseMap({
        'Description': 'silver hair, cinematic portrait',
        'Comment': jsonEncode({
          'steps': 28,
          'seed': 123456,
          'width': 832,
          'height': 1216,
        }),
      });

      expect(result.prompt, 'silver hair, cinematic portrait');
      expect(result.parameters['steps'], 28);
      expect(result.parameters['seed'], 123456);
      expect(result.width, 832);
      expect(result.height, 1216);
      expect(result.resolution, '832x1216');
      expect(result.rawContent, contains('cinematic portrait'));
      expect(result.hasStructuredMetadata, isTrue);
    });

    test('parses fullContent and Stealth_PNGInfo as alternate JSON payloads', () {
      final result = NaiMetadataParser.parseMap({
        'fullContent': jsonEncode({
          'prompt': 'glass garden, moonlit',
          'parameters': {
            'scale': 6.0,
            'resolution': '1024x768',
          },
        }),
        'Stealth_PNGInfo': jsonEncode({
          'Comment': jsonEncode({
            'sampler': 'k_euler',
          }),
        }),
      });

      expect(result.prompt, 'glass garden, moonlit');
      expect(result.parameters['scale'], 6.0);
      expect(result.parameters['sampler'], 'k_euler');
      expect(result.width, 1024);
      expect(result.height, 768);
      expect(result.rawContent, contains('glass garden'));
    });

    test('extracts NAI v4 base caption, char captions, coords, and size', () {
      final result = NaiMetadataParser.parseMap({
        'Comment': jsonEncode({
          'v4_prompt': {
            'caption': {
              'base_caption': 'two girls, city lights',
              'char_captions': [
                {
                  'char_caption': 'blue eyes, short hair',
                  'centers': [
                    {'x': 0.25, 'y': 0.55},
                  ],
                },
                {
                  'caption': 'red dress',
                  'coords': {'x': 0.75, 'y': 0.45},
                },
              ],
            },
          },
          'width': 1216,
          'height': 832,
        }),
      });

      expect(result.prompt, 'two girls, city lights');
      expect(result.charCaptions, [
        'blue eyes, short hair',
        'red dress',
      ]);
      expect(result.coords, [
        {'x': 0.25, 'y': 0.55},
        {'x': 0.75, 'y': 0.45},
      ]);
      expect(result.width, 1216);
      expect(result.height, 832);
      expect(result.parameters['v4_prompt'], isA<Map<String, dynamic>>());
    });

    test('keeps raw content when structured fields are missing', () {
      final result = NaiMetadataParser.parseMap({
        'Source': 'NovelAI',
        'Comment': 'not json but still useful',
      });

      expect(result.prompt, isNull);
      expect(result.parameters, isEmpty);
      expect(result.rawContent, contains('not json but still useful'));
      expect(result.hasStructuredMetadata, isFalse);
    });
  });
}
