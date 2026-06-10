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
    final isV3 =
        isKnownModel &&
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
