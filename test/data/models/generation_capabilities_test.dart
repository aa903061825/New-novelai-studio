import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/generation_capabilities.dart';

void main() {
  group('GenerationModelCapabilities.fromModel', () {
    test('enables official V4.5 controls for full and curated models', () {
      for (final model in [
        'nai-diffusion-4-5-full',
        'nai-diffusion-4-5-curated',
      ]) {
        final capabilities = GenerationModelCapabilities.fromModel(model);

        expect(capabilities.model, model);
        expect(capabilities.isV45, isTrue);
        expect(capabilities.isV4, isTrue);
        expect(capabilities.isV3, isFalse);
        expect(capabilities.supportsVibeTransfer, isTrue);
        expect(capabilities.supportsPreciseReference, isTrue);
        expect(capabilities.supportsMultiCharacterPrompts, isTrue);
        expect(capabilities.supportsPromptMixing, isFalse);
        expect(capabilities.supportsSmeaControls, isFalse);
      }
    });

    test('keeps legacy prompt mixing and SMEA controls for anime V3', () {
      final capabilities = GenerationModelCapabilities.fromModel(
        'nai-diffusion-3',
      );

      expect(capabilities.model, 'nai-diffusion-3');
      expect(capabilities.isV45, isFalse);
      expect(capabilities.isV4, isFalse);
      expect(capabilities.isV3, isTrue);
      expect(capabilities.supportsVibeTransfer, isTrue);
      expect(capabilities.supportsPreciseReference, isFalse);
      expect(capabilities.supportsMultiCharacterPrompts, isFalse);
      expect(capabilities.supportsPromptMixing, isTrue);
      expect(capabilities.supportsSmeaControls, isTrue);
    });

    test('keeps legacy prompt mixing and SMEA controls for furry V3', () {
      final capabilities = GenerationModelCapabilities.fromModel(
        'nai-diffusion-furry-3',
      );

      expect(capabilities.model, 'nai-diffusion-furry-3');
      expect(capabilities.isV45, isFalse);
      expect(capabilities.isV4, isFalse);
      expect(capabilities.isV3, isTrue);
      expect(capabilities.supportsVibeTransfer, isTrue);
      expect(capabilities.supportsPreciseReference, isFalse);
      expect(capabilities.supportsMultiCharacterPrompts, isFalse);
      expect(capabilities.supportsPromptMixing, isTrue);
      expect(capabilities.supportsSmeaControls, isTrue);
    });

    test('preserves unknown models without exposing advanced controls', () {
      final capabilities = GenerationModelCapabilities.fromModel(
        'custom-experimental-model',
      );

      expect(capabilities.model, 'custom-experimental-model');
      expect(capabilities.isV45, isFalse);
      expect(capabilities.isV4, isFalse);
      expect(capabilities.isV3, isFalse);
      expect(capabilities.supportsVibeTransfer, isFalse);
      expect(capabilities.supportsPreciseReference, isFalse);
      expect(capabilities.supportsMultiCharacterPrompts, isFalse);
      expect(capabilities.supportsPromptMixing, isFalse);
      expect(capabilities.supportsSmeaControls, isFalse);
    });
  });

  test('GenerationMode exposes supported generation modes', () {
    expect(GenerationMode.values, [
      GenerationMode.textToImage,
      GenerationMode.imageToImage,
      GenerationMode.enhance,
      GenerationMode.upscale,
      GenerationMode.inpaint,
      GenerationMode.directorTool,
    ]);
  });
}
