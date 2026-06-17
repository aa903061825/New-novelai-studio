import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/use_cases/generate_payload_use_case.dart';

class StudioImageOperationValidationResult {
  final bool isValid;
  final String? message;

  const StudioImageOperationValidationResult._({
    required this.isValid,
    this.message,
  });

  const StudioImageOperationValidationResult.valid() : this._(isValid: true);

  const StudioImageOperationValidationResult.invalid(String message)
      : this._(isValid: false, message: message);
}

class StudioImageOperationService {
  static const int maxUpscaleSourceDimension = 1024;

  const StudioImageOperationService();

  StudioImageOperationValidationResult validateUpscaleSource({
    required int width,
    required int height,
  }) {
    if (width <= 0 || height <= 0) {
      return const StudioImageOperationValidationResult.invalid(
        'Upscale source image dimensions are missing.',
      );
    }
    if (width > maxUpscaleSourceDimension ||
        height > maxUpscaleSourceDimension) {
      return const StudioImageOperationValidationResult.invalid(
        'Upscale source images must be 1024x1024 or smaller.',
      );
    }
    return const StudioImageOperationValidationResult.valid();
  }

  StudioImageOperationValidationResult validateInpaintMask({
    required String maskImageB64,
    required int sourceWidth,
    required int sourceHeight,
    required int maskWidth,
    required int maskHeight,
  }) {
    if (maskImageB64.trim().isEmpty) {
      return const StudioImageOperationValidationResult.invalid(
        'Inpaint mask image is missing.',
      );
    }
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      return const StudioImageOperationValidationResult.invalid(
        'Inpaint source image dimensions are missing.',
      );
    }
    if (maskWidth <= 0 || maskHeight <= 0) {
      return const StudioImageOperationValidationResult.invalid(
        'Inpaint mask image dimensions are missing.',
      );
    }
    if (sourceWidth != maskWidth || sourceHeight != maskHeight) {
      return const StudioImageOperationValidationResult.invalid(
        'Inpaint mask dimensions must match the source image.',
      );
    }
    return const StudioImageOperationValidationResult.valid();
  }

  PayloadGenerationResult buildEnhancePayload({
    required PayloadConfig payloadConfig,
    required String sourceImageB64,
    required double strength,
    required double noise,
  }) {
    final operationConfig = PayloadConfig.fromJson(payloadConfig.toJson());
    operationConfig.i2iConfig.loadJson({
      'image_b64': sourceImageB64,
      'width': payloadConfig.i2iConfig.width,
      'height': payloadConfig.i2iConfig.height,
      'strength': strength.clamp(0.0, 1.0),
      'noise': noise.clamp(0.0, 1.0),
      'override_prompt_enabled': false,
      'override_prompt': '',
    });
    return GeneratePayloadUseCase(payloadConfig: operationConfig)();
  }

  PayloadGenerationResult buildInpaintPayload({
    required PayloadConfig payloadConfig,
    required String sourceImageB64,
    required int sourceWidth,
    required int sourceHeight,
    required String maskImageB64,
    required int maskWidth,
    required int maskHeight,
    required double strength,
  }) {
    final validation = validateInpaintMask(
      maskImageB64: maskImageB64,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      maskWidth: maskWidth,
      maskHeight: maskHeight,
    );
    if (!validation.isValid) {
      throw StateError(validation.message ?? 'Inpaint mask is invalid.');
    }

    final operationConfig = PayloadConfig.fromJson(payloadConfig.toJson());
    final baseResult = GeneratePayloadUseCase(payloadConfig: operationConfig)();
    final payload = Map<String, dynamic>.from(baseResult.payload);
    final parameters = Map<String, dynamic>.from(
      payload['parameters']! as Map,
    );
    final clampedStrength = strength.clamp(0.0, 1.0);
    parameters['image'] = sourceImageB64;
    parameters['mask'] = maskImageB64;
    parameters['inpaintImg2ImgStrength'] = clampedStrength;
    parameters['img2img'] = {
      'strength': clampedStrength,
      'color_correct': true,
    };
    payload['action'] = 'infill';
    payload['model'] = _inpaintingModel(payload['model'] as String?);
    payload['parameters'] = parameters;
    return PayloadGenerationResult(
      comment: baseResult.comment,
      suggestedFileName: baseResult.suggestedFileName,
      contentOrderText: baseResult.contentOrderText,
      payload: payload,
    );
  }

  String _inpaintingModel(String? model) {
    final value = model?.trim() ?? '';
    if (value.isEmpty || value.endsWith('-inpainting')) {
      return value;
    }
    const previewSuffix = '-preview';
    if (value.endsWith(previewSuffix)) {
      return '${value.substring(0, value.length - previewSuffix.length)}-inpainting';
    }
    return '$value-inpainting';
  }
}
