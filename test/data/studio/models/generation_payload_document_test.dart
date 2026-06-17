import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/generation_payload_document.dart';

void main() {
  group('GenerationPayloadDocument', () {
    test('prefers v4 positive and negative captions from parameters', () {
      final document = GenerationPayloadDocument.fromMap({
        'input': 'legacy positive',
        'parameters': {
          'v4_prompt': {
            'caption': {'base_caption': 'v4 positive'},
          },
          'v4_negative_prompt': {
            'caption': {'base_caption': 'v4 negative'},
          },
          'negative_prompt': 'legacy negative',
        },
      });

      expect(document.positivePrompt, 'v4 positive');
      expect(document.negativePrompt, 'v4 negative');
    });

    test('falls back to legacy prompt fields when v4 captions are missing', () {
      final inputDocument = GenerationPayloadDocument.fromMap({
        'input': 'legacy input',
        'parameters': {'uc': 'legacy uc'},
      });
      final descriptionDocument = GenerationPayloadDocument.fromMap({
        'Description': 'legacy description',
      });

      expect(inputDocument.positivePrompt, 'legacy input');
      expect(inputDocument.negativePrompt, 'legacy uc');
      expect(descriptionDocument.positivePrompt, 'legacy description');
    });

    test('normalizes malformed payload maps to safe empty values', () {
      final document = GenerationPayloadDocument.fromMap({
        'parameters': 'not a map',
        'input': 42,
      });

      expect(document.positivePrompt, '');
      expect(document.negativePrompt, '');
      expect(document.parameters, isEmpty);
      expect(document.visibleParameterGroups, isEmpty);
    });

    test('groups visible parameters and hides large nested values', () {
      final document = GenerationPayloadDocument.fromMap({
        'model': 'nai-diffusion-4',
        'parameters': {
          'width': 832,
          'height': 1216,
          'steps': 28,
          'scale': 5.5,
          'cfg_schedule_eligibility': true,
          'seed': 123,
          'request_type': 'generate',
          'reference_image_multiple': ['large-base64'],
        },
      });

      expect(document.visibleParameterGroups.map((group) => group.id), [
        'core',
        'quality',
        'request',
      ]);
      expect(
        document.visibleParameterGroups
            .expand((group) => group.parameters)
            .map((parameter) => parameter.key),
        containsAll([
          'model',
          'width',
          'height',
          'steps',
          'scale',
          'cfg_schedule_eligibility',
          'seed',
        ]),
      );
      expect(
        document.visibleParameterGroups
            .expand((group) => group.parameters)
            .map((parameter) => parameter.key),
        isNot(contains('reference_image_multiple')),
      );
    });
  });
}
