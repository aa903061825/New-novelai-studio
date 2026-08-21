enum GenerationMode {
  textToImage,
  imageToImage,
  enhance,
  upscale,
  inpaint,
  directorTool,
}

const naiDiffusion5Curated = 'nai-diffusion-5-curated';
const naiDiffusion5Full = 'nai-diffusion-5-full';
const defaultGenerationModel = naiDiffusion5Curated;

const generationModels = [
  naiDiffusion5Curated,
  naiDiffusion5Full,
  'nai-diffusion-4-5-full',
  'nai-diffusion-4-5-curated',
  'nai-diffusion-4-full',
  'nai-diffusion-4-curated-preview',
  'nai-diffusion-3',
  'nai-diffusion-furry-3',
];

/// Central compatibility registry for NovelAI image models.
///
/// Unknown models intentionally get conservative capabilities so a newly
/// named model cannot silently receive unsupported request fields.
final class GenerationModelCapabilities {
  const GenerationModelCapabilities({
    required this.model,
    required this.isKnownModel,
    required this.isV3,
    required this.isV4,
    required this.isV45,
    required this.isV5,
    required this.supportsVibeTransfer,
    required this.supportsPreciseReference,
    required this.supportsMultiCharacterPrompts,
    required this.supportsPromptMixing,
    required this.supportsSmeaControls,
    required this.supportsVarietyPlus,
    required this.supportsDynamicThresholding,
    required this.supportsNoiseSchedule,
    required this.supportsAutoPosition,
    required this.supportsFreeformCharacterPosition,
    required this.supportsLegacyUc,
    required this.supportsTransparency,
    required this.supportsQualityPresets,
    required this.supportsUcPresets,
    required this.maxCharacters,
    required this.paramsVersion,
  });

  factory GenerationModelCapabilities.fromModel(String model) {
    final isV5 = model.startsWith('nai-diffusion-5-');
    final isV45 = model.startsWith('nai-diffusion-4-5');
    final isV4 = model.startsWith('nai-diffusion-4');
    final isV3 = model == 'nai-diffusion-3' || model == 'nai-diffusion-furry-3';
    final isKnownModel = generationModels.contains(model) ||
        model == '$naiDiffusion5Curated-inpainting' ||
        model == '$naiDiffusion5Full-inpainting';
    final usesStructuredPrompts = isKnownModel && (isV4 || isV5);

    return GenerationModelCapabilities(
      model: model,
      isKnownModel: isKnownModel,
      isV3: isKnownModel && isV3,
      isV4: isKnownModel && isV4,
      isV45: isKnownModel && isV45,
      isV5: isKnownModel && isV5,
      supportsVibeTransfer: isKnownModel && (isV3 || isV4),
      supportsPreciseReference: isKnownModel && isV45,
      supportsMultiCharacterPrompts: usesStructuredPrompts,
      supportsPromptMixing: isKnownModel && isV3,
      supportsSmeaControls: isKnownModel && isV3,
      supportsVarietyPlus: isKnownModel && !isV5,
      supportsDynamicThresholding: isKnownModel && !isV5,
      supportsNoiseSchedule: isKnownModel && !isV5,
      supportsAutoPosition: usesStructuredPrompts,
      supportsFreeformCharacterPosition: isKnownModel && isV5,
      supportsLegacyUc: isKnownModel && isV4,
      supportsTransparency: isKnownModel && isV5,
      supportsQualityPresets: isKnownModel && isV5,
      supportsUcPresets: isKnownModel && isV5,
      maxCharacters: isKnownModel && isV5 ? 32 : 6,
      paramsVersion: isKnownModel && isV5 ? 4 : 3,
    );
  }

  final String model;
  final bool isKnownModel;
  final bool isV3;

  /// V4 family, including V4.5. V5 is deliberately not included.
  final bool isV4;
  final bool isV45;
  final bool isV5;
  final bool supportsVibeTransfer;
  final bool supportsPreciseReference;
  final bool supportsMultiCharacterPrompts;
  final bool supportsPromptMixing;
  final bool supportsSmeaControls;
  final bool supportsVarietyPlus;
  final bool supportsDynamicThresholding;
  final bool supportsNoiseSchedule;
  final bool supportsAutoPosition;
  final bool supportsFreeformCharacterPosition;
  final bool supportsLegacyUc;
  final bool supportsTransparency;
  final bool supportsQualityPresets;
  final bool supportsUcPresets;
  final int maxCharacters;
  final int paramsVersion;

  bool get usesStructuredPrompts =>
      supportsMultiCharacterPrompts || supportsAutoPosition;

  PromptMixingValidationResult validatePromptMixingSyntax(String prompt) {
    final segments = _promptMixingSegments(prompt);
    final hasMixing = segments.length > 1;
    if (!hasMixing) {
      return const PromptMixingValidationResult(
        hasMixing: false,
        isValid: true,
      );
    }
    if (!supportsPromptMixing) {
      return const PromptMixingValidationResult(
        hasMixing: true,
        isValid: false,
        message: 'Prompt Mixing is only available on V3 or lower models.',
      );
    }
    if (segments.any((segment) => segment.trim().isEmpty)) {
      return const PromptMixingValidationResult(
        hasMixing: true,
        isValid: false,
        message: 'Prompt Mixing requires non-empty prompts around |.',
      );
    }
    return const PromptMixingValidationResult(
      hasMixing: true,
      isValid: true,
    );
  }
}

final class PromptMixingValidationResult {
  final bool hasMixing;
  final bool isValid;
  final String? message;

  const PromptMixingValidationResult({
    required this.hasMixing,
    required this.isValid,
    this.message,
  });
}

List<String> _promptMixingSegments(String prompt) {
  final segments = <String>[''];
  var inRandomizer = false;
  var index = 0;
  while (index < prompt.length) {
    if (index + 1 < prompt.length &&
        prompt.codeUnitAt(index) == 0x7c &&
        prompt.codeUnitAt(index + 1) == 0x7c) {
      inRandomizer = !inRandomizer;
      segments[segments.length - 1] = '${segments.last}||';
      index += 2;
      continue;
    }
    final char = prompt[index];
    if (char == '|' && !inRandomizer) {
      segments.add('');
    } else {
      segments[segments.length - 1] = '${segments.last}$char';
    }
    index += 1;
  }
  return segments;
}
