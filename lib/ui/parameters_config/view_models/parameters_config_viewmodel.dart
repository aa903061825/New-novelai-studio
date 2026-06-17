import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/models/global_generation_params.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/generation_size.dart';
import 'package:novel_studio/data/services/config_service.dart';
import 'package:novel_studio/ui/core/utils/flushbar.dart';

class ParametersConfigViewmodel extends ChangeNotifier {
  PayloadConfig get payloadConfig => GetIt.I();
  ConfigService get configService => GetIt.I();
  ParamConfig get config => payloadConfig.paramConfig;
  GlobalGenerationParams get globalParams =>
      payloadConfig.globalGenerationParams;

  bool get useGlobalSteps => globalParams.useGlobalSteps;
  bool get useGlobalScale => globalParams.useGlobalScale;
  bool get useGlobalCfgRescale => globalParams.useGlobalCfgRescale;
  bool get useGlobalSampler => globalParams.useGlobalSampler;
  bool get useGlobalNegativePrompt => globalParams.useGlobalNegativePrompt;

  int get displayedSteps => globalParams.resolveSteps(config);
  double get displayedScale => globalParams.resolveScale(config);
  double get displayedCfgRescale => globalParams.resolveCfgRescale(config);
  String get displayedSampler => globalParams.resolveSampler(config);
  String get displayedNegativePrompt =>
      globalParams.resolveNegativePrompt(config);

  ParametersConfigViewmodel();

  setSteps(double value) {
    if (useGlobalSteps) {
      globalParams.steps = value.toInt();
      _saveGlobalGenerationParams();
    } else {
      config.steps = value.toInt();
    }
    notifyListeners();
  }

  setScale(double value) {
    if (useGlobalScale) {
      globalParams.scale = value;
      _saveGlobalGenerationParams();
    } else {
      config.scale = value;
    }
    notifyListeners();
  }

  setCfgRescale(double value) {
    if (useGlobalCfgRescale) {
      globalParams.cfgRescale = value;
      _saveGlobalGenerationParams();
    } else {
      config.cfgRescale = value;
    }
    notifyListeners();
  }

  setSampler(String value) {
    if (useGlobalSampler) {
      globalParams.sampler = value;
      _saveGlobalGenerationParams();
    } else {
      config.sampler = value;
    }
    notifyListeners();
  }

  setNoiseScheduler(String value) {
    config.noiseSchedule = value;
    notifyListeners();
  }

  setSm(bool value) {
    config.sm = value;
    notifyListeners();
  }

  setSmDyn(bool value) {
    config.smDyn = value;
    notifyListeners();
  }

  setVarietyPlus(bool value) {
    config.varietyPlus = value;
    notifyListeners();
  }

  setNegativePrompt(String value) {
    if (useGlobalNegativePrompt) {
      globalParams.negativePrompt = value;
      _saveGlobalGenerationParams();
    } else {
      config.negativePrompt = value;
    }
    notifyListeners();
  }

  setRandomSeedEnabled(bool value) {
    config.randomSeed = value;
    notifyListeners();
  }

  setSeed(String value) {
    final parseResult = int.tryParse(value);
    if (parseResult == null) return;
    config.seed = parseResult;
    notifyListeners();
  }

  void removeSize(GenerationSize elem) {
    if (config.sizes.length == 1) return;
    final list = config.sizes.toList();
    list.remove(elem);
    config.sizes = list;
    notifyListeners();
  }

  void addSize(GenerationSize elem) {
    if (config.sizes.contains(elem)) return;
    final list = config.sizes.toList();
    list.add(elem);
    config.sizes = list;
    notifyListeners();
  }

  void addManualSize(String width, String height) {
    var parsedWigth = int.tryParse(width);
    var parsedHeight = int.tryParse(height);
    if (parsedWigth == null || parsedHeight == null) return;
    parsedWigth = (parsedWigth / 64).ceil() * 64;
    parsedHeight = (parsedHeight / 64).ceil() * 64;
    final size = GenerationSize(width: parsedWigth, height: parsedHeight);
    if (config.sizes.contains(size)) return;
    final list = config.sizes.toList();
    list.add(size);
    config.sizes = list;
    notifyListeners();
  }

  void setModel(String value) {
    config.model = value;
    notifyListeners();
  }

  void setBatchResolutionEnabled(bool value) {
    config.enableBatchResolution = value;
    notifyListeners();
  }

  void setBatchResolutionMode(String value) {
    final safeValue = switch (value) {
      'random' => 'random',
      'stop_at_end' => 'stop_at_end',
      _ => 'loop',
    };
    config.batchResolutionMode = safeValue;
    notifyListeners();
  }

  void setBatchResolutionText(String value) {
    config.batchResolutionText = value;
    notifyListeners();
  }

  bool get isV4 => config.model.contains('-4-');

  void setAutoPosition(bool? value) {
    if (value == null) return;
    config.autoPosition = value;
    notifyListeners();
  }

  void setLegacyUc(bool? value) {
    if (value == null) return;
    config.legacyUc = value;
    notifyListeners();
  }

  void setUseGlobalSteps(bool value) {
    if (globalParams.useGlobalSteps == value) return;
    globalParams.useGlobalSteps = value;
    _saveGlobalGenerationParams();
    notifyListeners();
  }

  void setUseGlobalScale(bool value) {
    if (globalParams.useGlobalScale == value) return;
    globalParams.useGlobalScale = value;
    _saveGlobalGenerationParams();
    notifyListeners();
  }

  void setUseGlobalCfgRescale(bool value) {
    if (globalParams.useGlobalCfgRescale == value) return;
    globalParams.useGlobalCfgRescale = value;
    _saveGlobalGenerationParams();
    notifyListeners();
  }

  void setUseGlobalSampler(bool value) {
    if (globalParams.useGlobalSampler == value) return;
    globalParams.useGlobalSampler = value;
    _saveGlobalGenerationParams();
    notifyListeners();
  }

  void setUseGlobalNegativePrompt(bool value) {
    if (globalParams.useGlobalNegativePrompt == value) return;
    globalParams.useGlobalNegativePrompt = value;
    _saveGlobalGenerationParams();
    notifyListeners();
  }

  int applyMetadataToActiveSource(Map<String, dynamic> commentData) {
    final remaining = Map<String, dynamic>.from(commentData);
    var didUpdateGlobalParams = false;
    var loadedCount = 0;

    int applyInt(
      String key, {
      required bool useGlobal,
      required void Function(int value) applyGlobal,
    }) {
      if (!remaining.containsKey(key)) return 0;
      final rawValue = remaining.remove(key);
      final parsedValue =
          rawValue is int ? rawValue : int.tryParse('$rawValue');
      if (parsedValue == null) return 0;
      if (useGlobal) {
        applyGlobal(parsedValue);
        didUpdateGlobalParams = true;
        return 1;
      }
      return config.loadJson({key: parsedValue});
    }

    int applyDouble(
      String key, {
      required bool useGlobal,
      required void Function(double value) applyGlobal,
    }) {
      if (!remaining.containsKey(key)) return 0;
      final rawValue = remaining.remove(key);
      final parsedValue = switch (rawValue) {
        int value => value.toDouble(),
        double value => value,
        _ => double.tryParse('$rawValue'),
      };
      if (parsedValue == null) return 0;
      if (useGlobal) {
        applyGlobal(parsedValue);
        didUpdateGlobalParams = true;
        return 1;
      }
      return config.loadJson({key: parsedValue});
    }

    int applyString(
      String key, {
      required bool useGlobal,
      required void Function(String value) applyGlobal,
    }) {
      if (!remaining.containsKey(key)) return 0;
      final rawValue = remaining.remove(key);
      final parsedValue = rawValue?.toString();
      if (parsedValue == null) return 0;
      if (useGlobal) {
        applyGlobal(parsedValue);
        didUpdateGlobalParams = true;
        return 1;
      }
      return config.loadJson({key: parsedValue});
    }

    loadedCount += applyInt(
      'steps',
      useGlobal: useGlobalSteps,
      applyGlobal: (value) => globalParams.steps = value,
    );
    loadedCount += applyDouble(
      'scale',
      useGlobal: useGlobalScale,
      applyGlobal: (value) => globalParams.scale = value,
    );
    loadedCount += applyDouble(
      'cfg_rescale',
      useGlobal: useGlobalCfgRescale,
      applyGlobal: (value) => globalParams.cfgRescale = value,
    );
    loadedCount += applyString(
      'sampler',
      useGlobal: useGlobalSampler,
      applyGlobal: (value) => globalParams.sampler = value,
    );
    loadedCount += applyString(
      'negative_prompt',
      useGlobal: useGlobalNegativePrompt,
      applyGlobal: (value) => globalParams.negativePrompt = value,
    );
    loadedCount += applyString(
      'uc',
      useGlobal: useGlobalNegativePrompt,
      applyGlobal: (value) => globalParams.negativePrompt = value,
    );

    loadedCount += config.loadJson(remaining);
    if (didUpdateGlobalParams) {
      _saveGlobalGenerationParams();
    }
    return loadedCount;
  }

  void loadAllMetadata(
    BuildContext context,
    Map<String, dynamic> commentData,
    String? prompt,
    String? model,
  ) {
    int loadedCount = applyMetadataToActiveSource(commentData);
    if (prompt != null) {
      payloadConfig.overridePrompt = prompt;
      payloadConfig.useOverridePrompt = true;
      loadedCount++;
    }
    if (model != null) {
      payloadConfig.paramConfig.model = model;
      loadedCount++;
    }
    notifyListeners();
    showInfoBar(
        context,
        tr(
          'loaded_parameters_count',
          namedArgs: {'num': loadedCount.toString()},
        ));
  }

  void loadSingleImageMetadata(
      BuildContext context, Map<String, dynamic> commentData, String key) {
    final loadedCount = applyMetadataToActiveSource(commentData);
    if (loadedCount == 0) return;
    notifyListeners();
    showInfoBar(
        context,
        tr(
          'pasted_parameter',
          namedArgs: {'parameter_name': key},
        ));
  }

  void setOverridePrompt(BuildContext context, String? prompt) {
    if (prompt == null) return;
    payloadConfig.overridePrompt = prompt;
    payloadConfig.useOverridePrompt = true;
    notifyListeners();
    showInfoBar(
        context,
        tr(
          'pasted_parameter',
          namedArgs: {'parameter_name': tr('prompt')},
        ));
  }

  void _saveGlobalGenerationParams() {
    configService.saveGlobalGenerationParams(globalParams);
  }
}
