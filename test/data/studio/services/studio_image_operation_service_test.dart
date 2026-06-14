import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/generation_size.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/services/studio_image_operation_service.dart';

PayloadConfig _payloadConfig() {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const ['unused'], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(
      sizes: const [GenerationSize(width: 832, height: 1216)],
      randomSeed: false,
      seed: 12345,
    ),
    settings: Settings.fromJson(const {}),
    overridePrompt: 'enhance prompt',
    useOverridePrompt: true,
    useCharacterPromptWithOverride: false,
  );
}

void main() {
  group('StudioImageOperationService', () {
    test('validates dedicated upscale source dimensions', () {
      final service = StudioImageOperationService();

      expect(
        service.validateUpscaleSource(width: 1024, height: 1024).isValid,
        isTrue,
      );
      expect(
        service.validateUpscaleSource(width: 1025, height: 768).isValid,
        isFalse,
      );
      expect(
        service.validateUpscaleSource(width: 768, height: 1025).isValid,
        isFalse,
      );
    });

    test('buildEnhancePayload emits clamped img2img request', () {
      final payload = _payloadConfig();
      final service = StudioImageOperationService();

      final result = service.buildEnhancePayload(
        payloadConfig: payload,
        sourceImageB64: 'source-image',
        strength: -0.5,
        noise: 1.5,
      );

      final params = result.payload['parameters'] as Map<String, dynamic>;
      expect(result.payload['action'], 'img2img');
      expect(result.payload['input'], contains('enhance prompt'));
      expect(params['image'], 'source-image');
      expect(params['strength'], 0.0);
      expect(params['noise'], 1.0);
      expect(payload.i2iConfig.imageB64, isNull);
    });

    test('validates inpaint masks before request construction', () {
      final service = StudioImageOperationService();

      expect(
        service
            .validateInpaintMask(
              maskImageB64: 'mask-image',
              sourceWidth: 832,
              sourceHeight: 1216,
              maskWidth: 832,
              maskHeight: 1216,
            )
            .isValid,
        isTrue,
      );
      expect(
        service
            .validateInpaintMask(
              maskImageB64: '',
              sourceWidth: 832,
              sourceHeight: 1216,
              maskWidth: 832,
              maskHeight: 1216,
            )
            .isValid,
        isFalse,
      );
      expect(
        service
            .validateInpaintMask(
              maskImageB64: 'mask-image',
              sourceWidth: 832,
              sourceHeight: 1216,
              maskWidth: 512,
              maskHeight: 512,
            )
            .isValid,
        isFalse,
      );
    });

    test('buildInpaintPayload emits infill request without mutating config',
        () {
      final payload = _payloadConfig();
      payload.paramConfig.model = 'nai-diffusion-4-5-full';
      final service = StudioImageOperationService();

      final result = service.buildInpaintPayload(
        payloadConfig: payload,
        sourceImageB64: 'source-image',
        sourceWidth: 832,
        sourceHeight: 1216,
        maskImageB64: 'mask-image',
        maskWidth: 832,
        maskHeight: 1216,
        strength: 1.5,
      );

      final params = result.payload['parameters'] as Map<String, dynamic>;
      expect(result.payload['action'], 'infill');
      expect(result.payload['model'], 'nai-diffusion-4-5-full-inpainting');
      expect(result.payload['input'], contains('enhance prompt'));
      expect(params['image'], 'source-image');
      expect(params['mask'], 'mask-image');
      expect(params['inpaintImg2ImgStrength'], 1.0);
      expect(params['img2img'], {'strength': 1.0, 'color_correct': true});
      expect(payload.i2iConfig.imageB64, isNull);
      expect(payload.paramConfig.model, 'nai-diffusion-4-5-full');
    });
  });
}
