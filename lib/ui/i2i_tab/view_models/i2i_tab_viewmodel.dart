import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/ui/i2i_config/view_models/i2i_config_viewmodel.dart';

class I2iTabViewmodel extends ChangeNotifier {
  PayloadConfig get payloadConfig => GetIt.I<PayloadConfig>();
  ParamConfig get paramConfig => payloadConfig.paramConfig;
  ConfigService get configService => GetIt.I<ConfigService>();

  bool get isV4 => paramConfig.model.contains('-4-');
  bool get isV45 => paramConfig.model.contains('-4-5-');
  bool get vibeEnabled => payloadConfig.generationRuntimeState.vibeEnabled;

  bool get usePreciseReference => isV45 && payloadConfig.usePreciseReference;

  I2iVibeViewmodel createI2iViewmodel() {
    return I2iVibeViewmodel(
      config: payloadConfig.i2iConfig,
      paramConfig: paramConfig,
    );
  }

  void setVibeEnabled(bool value) {
    payloadConfig.generationRuntimeState.vibeEnabled = value;
    configService.saveGenerationRuntimeState(
      payloadConfig.generationRuntimeState,
    );
    notifyListeners();
  }

  void setUsePreciseReference(bool value) {
    if (!isV45) {
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
