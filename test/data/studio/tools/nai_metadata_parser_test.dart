import 'dart:convert';
import 'dart:typed_data';

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

    test('parses fullContent and Stealth_PNGInfo as alternate JSON payloads',
        () {
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

    test('extracts object Comment v4 negative prompt and source', () {
      final result = NaiMetadataParser.parseMap({
        'Source': 'NovelAI Diffusion V4.5 4BDE2A90',
        'Description': 'base scene',
        'Comment': {
          'width': 832,
          'height': 1216,
          'seed': 2787767294,
          'v4_prompt': {
            'caption': {
              'base_caption': 'base scene from v4',
              'char_captions': [
                {
                  'char_caption': 'girl, twin braids',
                  'centers': [
                    {'x': 0.5, 'y': 0.5},
                  ],
                },
              ],
            },
          },
          'v4_negative_prompt': {
            'caption': {
              'base_caption': 'blurry, lowres',
              'char_captions': [
                {
                  'char_caption': 'bad hands',
                  'centers': [
                    {'x': 0.5, 'y': 0.5},
                  ],
                },
              ],
            },
          },
        },
      });

      expect(result.source, 'NovelAI Diffusion V4.5 4BDE2A90');
      expect(result.prompt, 'base scene');
      expect(result.negativePrompt, 'blurry, lowres');
      expect(result.charCaptions, ['girl, twin braids']);
      expect(result.negativeCharCaptions, ['bad hands']);
      expect(result.width, 832);
      expect(result.height, 1216);
      expect(result.parameters['seed'], 2787767294);
    });

    test('extracts ComfyUI sampler graph text instead of raw prompt JSON', () {
      final result = NaiMetadataParser.parseMap({
        'prompt': jsonEncode({
          '63': {
            'class_type': 'KSampler',
            'inputs': {
              'seed': 317540284430262,
              'steps': 40,
              'cfg': 5.5,
              'sampler_name': 'er_sde',
              'scheduler': 'beta',
              'positive': ['11', 0],
              'negative': ['12', 0],
            },
          },
          '11': {
            'class_type': 'CLIPTextEncode',
            'inputs': {
              'text': ['92', 0],
            },
          },
          '12': {
            'class_type': 'CLIPTextEncode',
            'inputs': {
              'text': 'score_1, score_2, bad hands, watermark',
            },
          },
          '92': {
            'class_type': 'PreviewAny',
            'inputs': {
              'source': ['89', 0],
            },
          },
          '89': {
            'class_type': 'JoinStringMulti',
            'inputs': {
              'delimiter': ' ',
              'string_1': ['100', 0],
              'string_2': ['103', 0],
              'string_3': ['101', 0],
            },
          },
          '100': {
            'class_type': 'CR Text',
            'inputs': {
              'text': 'masterpiece, @artist',
            },
          },
          '103': {
            'class_type': 'CR Text',
            'inputs': {
              'text': 'very aesthetic, best quality',
            },
          },
          '101': {
            'class_type': 'CR Text',
            'inputs': {
              'text': '2girls, lantern light',
            },
          },
        }),
        'workflow': jsonEncode({'id': 'sample-workflow'}),
      });

      expect(result.prompt, contains('masterpiece, @artist'));
      expect(result.prompt, contains('very aesthetic, best quality'));
      expect(result.prompt, contains('2girls, lantern light'));
      expect(result.prompt, isNot(contains('"class_type"')));
      expect(result.negativePrompt, 'score_1, score_2, bad hands, watermark');
      expect(result.parameters['seed'], 317540284430262);
      expect(result.parameters['steps'], 40);
      expect(result.parameters['scale'], 5.5);
      expect(result.parameters['sampler'], 'er_sde');
      expect(result.parameters['noise_schedule'], 'beta');
      expect(result.hasStructuredMetadata, isTrue);
    });

    test('extracts ComfyUI loader prompt UI positive and negative strings', () {
      final result = NaiMetadataParser.parseMap({
        'prompt': jsonEncode({
          '2': {
            'class_type': 'Eff. Loader SDXL',
            'inputs': {
              'empty_latent_width': 768,
              'empty_latent_height': 1024,
              'positive': ['47', 0],
              'negative': ['49', 0],
            },
          },
          '47': {
            'class_type': 'WeiLinPromptUIWithoutLora',
            'inputs': {
              'positive': 'OninekoFG, 1girl, jellyfish girl',
            },
          },
          '49': {
            'class_type': 'WeiLinPromptUIWithoutLora',
            'inputs': {
              'positive': 'bad hands, lowres, watermark',
            },
          },
        }),
      });

      expect(result.prompt, 'OninekoFG, 1girl, jellyfish girl');
      expect(result.negativePrompt, 'bad hands, lowres, watermark');
      expect(result.width, 768);
      expect(result.height, 1024);
      expect(result.parameters['width'], 768);
      expect(result.parameters['height'], 1024);
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

    test('does not serialize raw image bytes into fallback raw content', () {
      final result = NaiMetadataParser.parseMap({
        'Source': 'image-only.png',
        'imageBytes': Uint8List.fromList(List.filled(4096, 7)),
      });

      expect(result.prompt, isNull);
      expect(result.rawContent, isNot(contains('7,7,7')));
      expect(result.rawContent.length, lessThan(128));
    });
  });
}
