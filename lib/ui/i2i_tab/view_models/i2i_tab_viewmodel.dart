import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/generation_capabilities.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/services/config_service.dart';
import 'package:novel_studio/ui/i2i_config/view_models/i2i_config_viewmodel.dart';

class I2iTabViewmodel extends ChangeNotifier {
  PayloadConfig get payloadConfig => GetIt.I<PayloadConfig>();
  ParamConfig get paramConfig => payloadConfig.paramConfig;
  ConfigService get configService => GetIt.I<ConfigService>();

  GenerationModelCapabilities get capabilities =>
      GenerationModelCapabilities.fromModel(paramConfig.model);
  bool get isV4 => capabilities.isV4;
  bool get isV45 => capabilities.isV45;
  bool get supportsVibeTransfer => capabilities.supportsVibeTransfer;
  bool get supportsPreciseReference => capabilities.supportsPreciseReference;
  bool get vibeEnabled => payloadConfig.generationRuntimeState.vibeEnabled;

  bool get usePreciseReference => isV45 && payloadConfig.usePreciseReference;

  I2iVibeViewmodel createI2iViewmodel() {
    return I2iVibeViewmodel(
      config: payloadConfig.i2iConfig,
      paramConfig: paramConfig,
    );
  }

  void setVibeEnabled(bool value) {
    payloadConfig.generationRuntimeState.vibeEnabled =
        supportsVibeTransfer && value;
    configService.saveGenerationRuntimeState(
      payloadConfig.generationRuntimeState,
    );
    notifyListeners();
  }

  void setUsePreciseReference(bool value) {
    if (!supportsPreciseReference) {
      payloadConfig.usePreciseReference = false;
      notifyListeners();
      return;
    }
    payloadConfig.usePreciseReference = value;
    if (value && payloadConfig.generationRuntimeState.vibeEnabled) {
      payloadConfig.generationRuntimeState.vibeEnabled = false;
      configService.saveGenerationRuntimeState(
        payloadConfig.generationRuntimeState,
      );
    }
    notifyListeners();
  }
}
