import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/core/constants/defaults.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/services/script_recast_engine.dart';
import 'package:novel_studio/data/studio/services/script_recast_parser_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_payload_adapter.dart';

void main() {
  group('ScriptRecastPayloadAdapter', () {
    test('converts recast metadata payload into direct NAI request payload',
        () async {
      final script = await ScriptRecastParserService().parseDirectory(
        Directory('test/fixtures/script_recast/v4_slotted'),
      );
      final result = const ScriptRecastEngine().resolvePayloads(
        script: script,
        mapping: RecastMapping.defaults(script.id),
        characters: const [],
        artistChains: const [],
      );

      final request = const ScriptRecastPayloadAdapter().toNaiRequestPayload(
        result.frames.first.payload,
      );

      expect(request.keys, containsAll(['input', 'model', 'action']));
      expect(request['input'], contains('city lights'));
      expect(request['input'], contains('artist:terasu_mc'));
      expect(request['model'], 'nai-diffusion-4-5-full');
      expect(request['action'], 'generate');
      expect(request, isNot(contains('Comment')));

      final parameters = request['parameters'] as Map<String, dynamic>;
      expect(parameters['seed'], 123456);
      expect(parameters['width'], 1216);
      expect(parameters['height'], 832);
      expect(parameters, isNot(contains('extra_passthrough_testing')));
      expect(parameters['params_version'], 3);
      expect(parameters['n_samples'], 1);
      expect(parameters['v4_prompt'], isA<Map<String, dynamic>>());
      expect(parameters['v4_negative_prompt'], isA<Map<String, dynamic>>());

      final prompt = parameters['v4_prompt'] as Map<String, dynamic>;
      final caption = prompt['caption'] as Map<String, dynamic>;
      expect(caption['base_caption'], contains('city lights'));
      expect(
          caption['char_captions'],
          isA<List>().having(
            (items) => items.length,
            'length',
            2,
          ));
    });

    test('normalizes base inline scripts into v4 prompt fields', () async {
      final script = await ScriptRecastParserService().parseDirectory(
        Directory('test/fixtures/script_recast/base_inline'),
      );
      final result = const ScriptRecastEngine().resolvePayloads(
        script: script,
        mapping: RecastMapping.defaults(script.id),
        characters: const [],
        artistChains: const [],
      );

      final request = const ScriptRecastPayloadAdapter().toNaiRequestPayload(
        result.frames.first.payload,
      );

      expect(request['input'], contains('vulpisfoglia_(arknights)'));
      expect(request['model'], 'nai-diffusion-4-full');
      final parameters = request['parameters'] as Map<String, dynamic>;
      final negative = parameters['v4_negative_prompt'] as Map<String, dynamic>;
      final negativeCaption = negative['caption'] as Map<String, dynamic>;
      expect(negativeCaption['base_caption'], contains('lowres'));
    });

    test('merges the batch default with original negative prompts once', () {
      final firstRequest =
          const ScriptRecastPayloadAdapter().toNaiRequestPayload(
        const {
          'input': 'direct prompt',
          'parameters': {
            'negative_prompt': 'bad anatomy, custom legacy negative',
            'v4_negative_prompt': {
              'caption': {
                'base_caption': 'bad anatomy, custom v4 negative',
                'char_captions': [
                  {'char_caption': 'bad hands'},
                ],
              },
            },
          },
        },
      );

      final firstParameters =
          firstRequest['parameters'] as Map<String, dynamic>;
      final firstNegative =
          firstParameters['v4_negative_prompt'] as Map<String, dynamic>;
      final firstCaption = firstNegative['caption'] as Map<String, dynamic>;
      final expected = '$defaultBatchNegativePrompt, '
          'bad anatomy, custom v4 negative, '
          'bad anatomy, custom legacy negative';

      expect(firstParameters['negative_prompt'], expected);
      expect(firstCaption['base_caption'], expected);
      expect(
        ((firstCaption['char_captions'] as List).single as Map)['char_caption'],
        'bad hands',
      );

      final secondRequest =
          const ScriptRecastPayloadAdapter().toNaiRequestPayload(firstRequest);
      final secondParameters =
          secondRequest['parameters'] as Map<String, dynamic>;
      final secondNegative =
          secondParameters['v4_negative_prompt'] as Map<String, dynamic>;
      final secondCaption = secondNegative['caption'] as Map<String, dynamic>;

      expect(secondParameters['negative_prompt'], expected);
      expect(secondCaption['base_caption'], expected);
    });

    test('preserves already direct request payloads while filling defaults',
        () {
      final request = const ScriptRecastPayloadAdapter().toNaiRequestPayload(
        const {
          'input': 'direct prompt',
          'model': 'nai-diffusion-4-curated-preview',
          'action': 'generate',
          'parameters': {
            'seed': 7,
            'extra_passthrough_testing': {'bucket': 'web-only'},
            'width': 1024,
            'height': 1024,
            'v4_prompt': {
              'caption': {
                'base_caption': 'direct prompt',
                'char_captions': [],
              },
            },
          },
        },
      );

      expect(request['input'], 'direct prompt');
      expect(request['model'], 'nai-diffusion-4-curated-preview');
      final parameters = request['parameters'] as Map<String, dynamic>;
      expect(parameters['seed'], 7);
      expect(parameters, isNot(contains('extra_passthrough_testing')));
      expect(parameters['params_version'], 3);
      expect(parameters['characterPrompts'], isEmpty);
    });

    test('normalizes edit request parameters into prompt generation requests',
        () {
      final request = const ScriptRecastPayloadAdapter().toNaiRequestPayload(
        const {
          'input': 'recast prompt',
          'model': 'nai-diffusion-4-5-full',
          'action': 'generate',
          'parameters': {
            'request_type': 'NativeInfillingRequest',
            'add_original_image': false,
            'img2img': 'source-image',
            'mask': 'mask-image',
            'image': 'legacy-image',
            'strength': 0.7,
            'seed': 7,
          },
        },
      );

      final parameters = request['parameters'] as Map<String, dynamic>;
      expect(parameters['request_type'], 'PromptGenerateRequest');
      expect(parameters, isNot(contains('add_original_image')));
      expect(parameters, isNot(contains('img2img')));
      expect(parameters, isNot(contains('mask')));
      expect(parameters, isNot(contains('image')));
      expect(parameters, isNot(contains('strength')));
      expect(parameters['seed'], 7);
    });

    test('disables coordinate mode when char captions have no centers', () {
      final request = const ScriptRecastPayloadAdapter().toNaiRequestPayload(
        const {
          'input': 'recast prompt',
          'model': 'nai-diffusion-4-5-full',
          'action': 'generate',
          'parameters': {
            'request_type': 'PromptGenerateRequest',
            'v4_prompt': {
              'use_coords': true,
              'caption': {
                'base_caption': 'scene prompt',
                'char_captions': [
                  {'char_caption': 'first character'},
                  {'char_caption': 'second character'},
                ],
              },
            },
          },
        },
      );

      final parameters = request['parameters'] as Map<String, dynamic>;
      final prompt = parameters['v4_prompt'] as Map<String, dynamic>;
      expect(prompt['use_coords'], isFalse);
      final caption = prompt['caption'] as Map<String, dynamic>;
      final charCaptions = caption['char_captions'] as List<dynamic>;
      expect(
        charCaptions,
        everyElement(
          isA<Map<String, dynamic>>().having(
            (entry) => entry['centers'],
            'centers',
            [
              {'x': 0.5, 'y': 0.5},
            ],
          ),
        ),
      );
    });

    test('normalizes edit metadata into prompt generation requests', () {
      final request = const ScriptRecastPayloadAdapter().toNaiRequestPayload(
        const {
          'Description': 'prompt from metadata',
          'Source': 'NovelAI Diffusion V4.5 1229B44F',
          'Comment': {
            'v4_prompt': {
              'caption': {
                'base_caption': 'prompt from metadata',
                'char_captions': [],
              },
            },
          },
          'parameters': {
            'request_type': 'NativeInfillingRequest',
            'add_original_image': false,
            'img2img': 'source-image',
            'mask': 'mask-image',
            'image': 'legacy-image',
            'strength': 0.7,
          },
        },
      );

      expect(request['model'], 'nai-diffusion-4-5-full');
      final parameters = request['parameters'] as Map<String, dynamic>;
      expect(parameters['request_type'], 'PromptGenerateRequest');
      expect(parameters, isNot(contains('add_original_image')));
      expect(parameters, isNot(contains('img2img')));
      expect(parameters, isNot(contains('mask')));
      expect(parameters, isNot(contains('image')));
      expect(parameters, isNot(contains('strength')));
    });

    test('removes display-only placeholders from direct request payloads', () {
      final artistLabel = '${_artistChainLabel()} 24';
      final rolePlaceholder = '[${_roleLabel()}B${_lowerBodyLabel()}]';

      final request = const ScriptRecastPayloadAdapter().toNaiRequestPayload(
        {
          'input': 'city lights, $artistLabel, detailed eyes',
          'model': 'nai-diffusion-4-curated-preview',
          'action': 'generate',
          'parameters': {
            'v4_prompt': {
              'caption': {
                'base_caption': 'city lights, $artistLabel, detailed eyes',
                'char_captions': [
                  {'char_caption': 'new heroine, $rolePlaceholder, red eyes'},
                ],
              },
            },
          },
        },
      );

      expect(request['input'], 'city lights, detailed eyes');
      final parameters = request['parameters'] as Map<String, dynamic>;
      final prompt = parameters['v4_prompt'] as Map<String, dynamic>;
      final caption = prompt['caption'] as Map<String, dynamic>;
      expect(caption['base_caption'], 'city lights, detailed eyes');
      final charCaptions = caption['char_captions'] as List;
      final firstChar = charCaptions.single as Map<String, dynamic>;
      expect(firstChar['char_caption'], 'new heroine, red eyes');
    });

    test('drops malformed director reference arrays from direct payloads', () {
      final request = const ScriptRecastPayloadAdapter().toNaiRequestPayload(
        const {
          'input': 'direct prompt',
          'parameters': {
            'seed': 7,
            'director_reference_images': [],
            'director_reference_strength_values': [0.8],
            'director_reference_secondary_strength_values': [0.2],
            'director_reference_information_extracted': [1.0],
            'director_reference_descriptions': [
              {
                'caption': {
                  'base_caption': 'character',
                  'char_captions': [],
                },
                'legacy_uc': false,
              },
            ],
          },
        },
      );

      final parameters = request['parameters'] as Map<String, dynamic>;
      expect(parameters.containsKey('director_reference_images'), isFalse);
      expect(
        parameters.containsKey('director_reference_strength_values'),
        isFalse,
      );
      expect(
        parameters.containsKey('director_reference_secondary_strength_values'),
        isFalse,
      );
      expect(
        parameters.containsKey('director_reference_information_extracted'),
        isFalse,
      );
      expect(
          parameters.containsKey('director_reference_descriptions'), isFalse);
    });

    test('drops malformed director reference arrays from metadata payloads',
        () {
      final request = const ScriptRecastPayloadAdapter().toNaiRequestPayload(
        const {
          'Description': 'prompt from metadata',
          'Source': 'NovelAI Diffusion V4.5',
          'Comment': {
            'v4_prompt': {
              'caption': {
                'base_caption': 'prompt from metadata',
                'char_captions': [],
              },
            },
            'v4_negative_prompt': {
              'caption': {
                'base_caption': 'bad anatomy',
                'char_captions': [],
              },
            },
          },
          'parameters': {
            'seed': 42,
            'director_reference_images': [],
            'director_reference_strength_values': [0.8],
            'director_reference_secondary_strength_values': [0.2],
            'director_reference_information_extracted': [1.0],
            'director_reference_descriptions': [
              {
                'caption': {
                  'base_caption': 'style',
                  'char_captions': [],
                },
                'legacy_uc': false,
              },
            ],
          },
        },
      );

      final parameters = request['parameters'] as Map<String, dynamic>;
      expect(parameters.containsKey('director_reference_images'), isFalse);
      expect(
          parameters.containsKey('director_reference_descriptions'), isFalse);
    });

    test('sanitizes direct V5 payloads using the model capability registry',
        () {
      final request = const ScriptRecastPayloadAdapter().toNaiRequestPayload(
        const {
          'input': 'V5 prompt',
          'model': 'nai-diffusion-5-full',
          'action': 'generate',
          'parameters': {
            'params_version': 3,
            'sampler': 'ddim_v3',
            'noise_schedule': 'exponential',
            'sm': true,
            'sm_dyn': true,
            'dynamic_thresholding': true,
            'skip_cfg_above_sigma': 19.0,
            'legacy_uc': true,
            'reference_image_multiple': ['legacy-vibe'],
            'reference_strength_multiple': [0.5],
            'reference_information_extracted_multiple': [1.0],
            'v4_negative_prompt': {
              'caption': {
                'base_caption': 'bad anatomy',
                'char_captions': [],
              },
              'legacy_uc': true,
            },
          },
        },
      );

      final parameters = request['parameters'] as Map<String, dynamic>;
      expect(parameters['params_version'], 4);
      expect(parameters['sampler'], 'k_euler_ancestral');
      expect(parameters['noise_schedule'], 'karras');
      expect(parameters.containsKey('sm'), isFalse);
      expect(parameters.containsKey('sm_dyn'), isFalse);
      expect(parameters.containsKey('skip_cfg_above_sigma'), isFalse);
      expect(parameters['dynamic_thresholding'], isFalse);
      expect(parameters['legacy_uc'], isFalse);
      expect(parameters.containsKey('reference_image_multiple'), isFalse);
      expect(
        (parameters['v4_negative_prompt'] as Map<String, dynamic>)['legacy_uc'],
        isFalse,
      );
    });
  });
}

String _artistChainLabel() {
  return String.fromCharCodes([0x753b, 0x5e08, 0x4e32]);
}

String _roleLabel() {
  return String.fromCharCodes([0x89d2, 0x8272]);
}

String _lowerBodyLabel() {
  return String.fromCharCodes([0x4e0b, 0x8eab]);
}
