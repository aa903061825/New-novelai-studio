import 'package:nai_casrand/core/constants/parameters.dart';

enum GenerationMode {
  textToImage,
  imageToImage,
  enhance,
  upscale,
  inpaint,
  directorTool,
}

final class GenerationModelCapabilities {
  const GenerationModelCapabilities({
    required this.model,
    required this.isV4,
    required this.isV45,
    required this.isV3,
    required this.supportsVibeTransfer,
    required this.supportsPreciseReference,
    required this.supportsMultiCharacterPrompts,
    required this.supportsPromptMixing,
    required this.supportsSmeaControls,
  });

  factory GenerationModelCapabilities.fromModel(String model) {
    final isKnownModel = models.contains(model);
    final isV45 = isKnownModel && model.startsWith('nai-diffusion-4-5');
    final isV4 = isKnownModel && model.startsWith('nai-diffusion-4');
    final isV3 = isKnownModel &&
        (model == 'nai-diffusion-3' || model == 'nai-diffusion-furry-3');

    return GenerationModelCapabilities(
      model: model,
      isV4: isV4,
      isV45: isV45,
      isV3: isV3,
      supportsVibeTransfer: isV45 || isV4 || isV3,
      supportsPreciseReference: isV45,
      supportsMultiCharacterPrompts: isV45,
      supportsPromptMixing: isV3,
      supportsSmeaControls: isV3,
    );
  }

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

  final String model;
  final bool isV4;
  final bool isV45;
  final bool isV3;
  final bool supportsVibeTransfer;
  final bool supportsPreciseReference;
  final bool supportsMultiCharacterPrompts;
  final bool supportsPromptMixing;
  final bool supportsSmeaControls;
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
