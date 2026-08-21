import 'dart:math';

import '../../core/constants/defaults.dart';
import 'generation_capabilities.dart';
import 'generation_presets.dart';
import 'generation_size.dart';

class ParamConfig {
  List<GenerationSize> sizes;
  int nSamples;

  int steps;
  String sampler;
  String noiseSchedule;
  double scale;
  double cfgRescale;
  bool sm;
  bool smDyn;
  bool varietyPlus;

  bool randomSeed;
  int seed;

  bool dynamicThresholding;
  double controlNetStrength;
  double uncondScale;

  bool qualityToggle;
  int ucPreset;
  String qualityPreset;
  String ucPresetMode;
  bool transparentBackground;
  String negativePrompt;

  bool legacy;
  bool addOriginalImage;

  String model = defaultGenerationModel;

  bool autoPosition;
  bool legacyUc;

  bool enableBatchResolution;
  String batchResolutionText;
  String batchResolutionMode;

  int _batchResolutionIndex = 0;

  ParamConfig({
    this.model = defaultGenerationModel,
    this.sizes = const [GenerationSize(height: 1216, width: 832)],
    this.scale = 6.5,
    this.sampler = 'k_euler_ancestral',
    this.steps = 28,
    this.randomSeed = true,
    this.seed = 0,
    this.nSamples = 1,
    this.ucPreset = 2,
    this.qualityToggle = false,
    this.qualityPreset = 'none',
    this.ucPresetMode = 'none',
    this.transparentBackground = false,
    this.sm = true,
    this.smDyn = true,
    this.dynamicThresholding = false,
    this.controlNetStrength = 1.0,
    this.legacy = false,
    this.addOriginalImage = false,
    this.uncondScale = 1.0,
    this.cfgRescale = 0.1,
    this.noiseSchedule = 'native',
    this.varietyPlus = false,
    this.negativePrompt = defaultUC,
    this.autoPosition = false,
    this.legacyUc = false,
    this.enableBatchResolution = false,
    this.batchResolutionText = '',
    this.batchResolutionMode = 'loop',
  });

  Map<String, dynamic> toJson() {
    return {
      'model': model,
      'sizes': sizes.map((elem) => elem.toJson()).toList(),
      'scale': scale,
      'sampler': sampler,
      'steps': steps,
      'n_samples': nSamples,
      'ucPreset': ucPreset,
      'qualityToggle': qualityToggle,
      'quality_preset': qualityPreset,
      'uc_preset_mode': ucPresetMode,
      'transparent_background': transparentBackground,
      'sm': sm,
      'sm_dyn': smDyn,
      'random_seed': randomSeed,
      'dynamic_thresholding': dynamicThresholding,
      'controlnet_strength': controlNetStrength,
      'legacy': legacy,
      'add_original_image': addOriginalImage,
      'uncond_scale': uncondScale,
      'cfg_rescale': cfgRescale,
      'noise_schedule': noiseSchedule,
      'negative_prompt': negativePrompt,
      'reference_image_multiple': [],
      'reference_information_extracted_multiple': [],
      'reference_strength_multiple': [],
      'variety_plus': varietyPlus,
      'auto_position': autoPosition,
      'legacy_uc': legacyUc,
      'enable_batch_resolution': enableBatchResolution,
      'batch_resolution_text': batchResolutionText,
      'batch_resolution_mode': batchResolutionMode,
    };
  }

  List<GenerationSize> parseBatchResolutions() {
    final parsedList = <GenerationSize>[];
    final lines = batchResolutionText.split(RegExp(r'[\r\n]+'));
    final pattern = RegExp(r'^\s*(\d+)\s*[xX*×]\s*(\d+)\s*$');

    for (final line in lines) {
      final match = pattern.firstMatch(line);
      if (match == null) continue;
      var parsedWidth = int.tryParse(match.group(1)!);
      var parsedHeight = int.tryParse(match.group(2)!);
      if (parsedWidth == null || parsedHeight == null) continue;
      if (parsedWidth <= 0 || parsedHeight <= 0) continue;
      parsedWidth = (parsedWidth / 64).ceil() * 64;
      parsedHeight = (parsedHeight / 64).ceil() * 64;

      parsedList.add(GenerationSize(width: parsedWidth, height: parsedHeight));
    }

    return parsedList;
  }

  bool get hasNextBatchResolution {
    if (!enableBatchResolution) return true;
    if (batchResolutionMode != 'stop_at_end') return true;
    final list = parseBatchResolutions();
    return _batchResolutionIndex < list.length;
  }

  void resetBatchResolutionCursor() {
    _batchResolutionIndex = 0;
  }

  GenerationSize? takeBatchResolution() {
    if (!enableBatchResolution) return null;
    final list = parseBatchResolutions();
    if (list.isEmpty) return null;

    if (batchResolutionMode == 'random') {
      return list[Random().nextInt(list.length)];
    }

    if (batchResolutionMode == 'stop_at_end') {
      if (_batchResolutionIndex >= list.length) return null;
      final selected = list[_batchResolutionIndex];
      _batchResolutionIndex += 1;
      return selected;
    }

    final selected = list[_batchResolutionIndex % list.length];
    _batchResolutionIndex += 1;
    return selected;
  }

  /// Different from toJson(), some fields in payload need to be calculated from other params.
  Map<String, dynamic> getPayload() {
    final capabilities = GenerationModelCapabilities.fromModel(model);
    final effectiveSampler =
        !capabilities.supportsSmeaControls && sampler == 'ddim_v3'
            ? 'k_euler_ancestral'
            : sampler;
    final effectiveNoiseSchedule =
        capabilities.supportsNoiseSchedule ? noiseSchedule : 'karras';
    bool? preferBrownian;
    bool? deliberateEulerAncestralBug;
    if (effectiveSampler == 'k_euler_ancestral' &&
        effectiveNoiseSchedule != 'native') {
      preferBrownian = true;
      deliberateEulerAncestralBug = false;
    }
    double? skipCfgAboveSigma;
    final selectedSize =
        takeBatchResolution() ?? sizes[Random().nextInt(sizes.length)];
    final width = selectedSize.width;
    final height = selectedSize.height;
    if (varietyPlus && capabilities.supportsVarietyPlus) {
      final w = width / 8;
      final h = height / 8;
      final v = pow(4.0 * w * h / 63232, 0.5);
      skipCfgAboveSigma = 19.0 * v;
    }
    var payload = {
      "params_version": capabilities.paramsVersion,
      "width": width,
      "height": height,
      "scale": scale,
      "sampler": effectiveSampler,
      "steps": steps,
      "n_samples": nSamples,
      "ucPreset": capabilities.isV5 ? ucPresetHint(ucPresetMode) : 2,
      "qualityToggle": capabilities.isV5 ? qualityPreset != 'none' : false,
      'sm': sm,
      'sm_dyn': smDyn,
      "dynamic_thresholding": capabilities.supportsDynamicThresholding
          ? dynamicThresholding
          : false,
      "controlnet_strength": controlNetStrength,
      "legacy": legacy,
      "add_original_image": true,
      "cfg_rescale": cfgRescale,
      "noise_schedule": effectiveNoiseSchedule,
      "skip_cfg_above_sigma": skipCfgAboveSigma,
      "use_coords": true,
      "seed": randomSeed ? Random().nextInt(1 << 32 - 1) : seed,
      "characterPrompts": [],
      "v4_prompt": {},
      "v4_negative_prompt": {},
      "negative_prompt": negativePrompt,
      "reference_image_multiple": [],
      "reference_information_extracted_multiple": [],
      "reference_strength_multiple": [],
      "deliberate_euler_ancestral_bug": deliberateEulerAncestralBug,
      "prefer_brownian": preferBrownian,
      "legacy_uc": capabilities.supportsLegacyUc ? legacyUc : false,
    };
    payload['legacy_v3_extend'] = false;
    payload.removeWhere((k, v) => v == null);
    if (!capabilities.supportsSmeaControls) {
      payload.remove('sm');
      payload.remove('sm_dyn');
      if (capabilities.isV4 && noiseSchedule.contains('native')) {
        payload['noise_schedule'] = 'karras';
      }
    }
    if (capabilities.isV5) {
      payload['tag_hint_qt'] = qualityPresetHint(qualityPreset);
      payload['tag_hint_uc_preset'] = ucPresetHint(ucPresetMode);
      payload['tag_hint_transparent_background'] = transparentBackground;
      payload['straight_alpha'] = transparentBackground;
    }
    return payload;
  }

  factory ParamConfig.fromJson(Map<String, dynamic> json) {
    return ParamConfig(
      model: json['model'] ?? defaultGenerationModel,
      sizes: (json['sizes'] as List<dynamic>?)
              ?.map((elem) => GenerationSize.fromJson(elem))
              .toList() ??
          const [GenerationSize(height: 1216, width: 832)],
      scale: json['scale'],
      sampler: json['sampler'],
      steps: json['steps'],
      nSamples: json['n_samples'],
      ucPreset: json['ucPreset'] ?? 0,
      qualityToggle: json['qualityToggle'] ?? false,
      qualityPreset:
          json['quality_preset'] ?? qualityPresetFromHint(json['tag_hint_qt']),
      ucPresetMode: json['uc_preset_mode'] ??
          ucPresetFromHint(json['tag_hint_uc_preset']),
      transparentBackground: json['transparent_background'] ??
          json['tag_hint_transparent_background'] ??
          json['straight_alpha'] ??
          false,
      sm: json['sm'],
      smDyn: json['sm_dyn'],
      dynamicThresholding: json['dynamic_thresholding'],
      varietyPlus: json['variety_plus'] ?? false,
      controlNetStrength: json['controlnet_strength'] is int
          ? (json['controlnet_strength'] as int).toDouble()
          : json['controlnet_strength'],
      legacy: json['legacy'],
      addOriginalImage: json['add_original_image'],
      uncondScale: json['uncond_scale'] is int
          ? (json['uncond_scale'] as int).toDouble()
          : json['uncond_scale'],
      cfgRescale: json['cfg_rescale'] is int
          ? (json['cfg_rescale'] as int).toDouble()
          : json['cfg_rescale'],
      noiseSchedule: json['noise_schedule'],
      negativePrompt: json['negative_prompt'],
      autoPosition: json['auto_position'] ?? false,
      legacyUc: json['legacy_uc'] ?? false,
      enableBatchResolution: json['enable_batch_resolution'] ?? false,
      batchResolutionText: json['batch_resolution_text'] ?? '',
      batchResolutionMode: switch (json['batch_resolution_mode']) {
        'random' => 'random',
        'stop_at_end' => 'stop_at_end',
        _ => 'loop',
      },
    );
  }

  ParamConfig copy() {
    return ParamConfig(
      model: model,
      sizes: sizes
          .map((elem) => GenerationSize(width: elem.width, height: elem.height))
          .toList(),
      scale: scale,
      sampler: sampler,
      steps: steps,
      randomSeed: randomSeed,
      seed: seed,
      nSamples: nSamples,
      ucPreset: ucPreset,
      qualityToggle: qualityToggle,
      qualityPreset: qualityPreset,
      ucPresetMode: ucPresetMode,
      transparentBackground: transparentBackground,
      sm: sm,
      smDyn: smDyn,
      dynamicThresholding: dynamicThresholding,
      controlNetStrength: controlNetStrength,
      legacy: legacy,
      addOriginalImage: addOriginalImage,
      uncondScale: uncondScale,
      cfgRescale: cfgRescale,
      noiseSchedule: noiseSchedule,
      varietyPlus: varietyPlus,
      negativePrompt: negativePrompt,
      autoPosition: autoPosition,
      legacyUc: legacyUc,
      enableBatchResolution: enableBatchResolution,
      batchResolutionText: batchResolutionText,
      batchResolutionMode: batchResolutionMode,
    ).._batchResolutionIndex = _batchResolutionIndex;
  }

  int loadJson(Map<String, dynamic> json) {
    int loadCount = 0;
    if (json.containsKey('width') && json.containsKey('height')) {
      final width = json['width'];
      final height = json['height'];
      sizes = [GenerationSize(width: width, height: height)];
      loadCount += 2;
    }
    if (json.containsKey('scale')) {
      scale = json['scale'];
      loadCount++;
    }
    if (json.containsKey('sampler')) {
      sampler = json['sampler'];
      loadCount++;
    }
    if (json.containsKey('steps')) {
      steps = json['steps'];
      loadCount++;
    }
    if (json.containsKey('n_samples')) {
      nSamples = json['n_samples'];
      loadCount++;
    }
    if (json.containsKey('ucPreset')) {
      ucPreset = json['ucPreset'];
      if (GenerationModelCapabilities.fromModel(model).isV5) {
        ucPresetMode = ucPresetFromHint(ucPreset);
      }
      loadCount++;
    }
    if (json.containsKey('qualityToggle')) {
      qualityToggle = json['qualityToggle'];
      if (GenerationModelCapabilities.fromModel(model).isV5 && qualityToggle) {
        qualityPreset = 'standard';
      }
      loadCount++;
    }
    if (json.containsKey('quality_preset')) {
      final value = json['quality_preset']?.toString();
      if (value != null && generationQualityPresets.contains(value)) {
        qualityPreset = value;
        loadCount++;
      }
    } else if (json.containsKey('tag_hint_qt')) {
      qualityPreset = qualityPresetFromHint(json['tag_hint_qt']);
      loadCount++;
    }
    if (json.containsKey('uc_preset_mode')) {
      final value = json['uc_preset_mode']?.toString();
      if (value != null && generationUcPresets.contains(value)) {
        ucPresetMode = value;
        loadCount++;
      }
    } else if (json.containsKey('tag_hint_uc_preset')) {
      ucPresetMode = ucPresetFromHint(json['tag_hint_uc_preset']);
      loadCount++;
    }
    final transparencyKey = json.containsKey('transparent_background')
        ? 'transparent_background'
        : json.containsKey('tag_hint_transparent_background')
            ? 'tag_hint_transparent_background'
            : json.containsKey('straight_alpha')
                ? 'straight_alpha'
                : null;
    if (transparencyKey != null && json[transparencyKey] is bool) {
      transparentBackground = json[transparencyKey];
      loadCount++;
    }
    if (json.containsKey('sm')) {
      sm = json['sm'];
      loadCount++;
    }
    if (json.containsKey('sm_dyn')) {
      smDyn = json['sm_dyn'];
      loadCount++;
    }
    if (json.containsKey('dynamic_thresholding')) {
      dynamicThresholding = json['dynamic_thresholding'];
      loadCount++;
    }
    if (json.containsKey('controlnet_strength')) {
      controlNetStrength = json['controlnet_strength'] is int
          ? (json['controlnet_strength'] as int).toDouble()
          : json['controlnet_strength'];
      loadCount++;
    }
    if (json.containsKey('legacy')) {
      legacy = json['legacy'];
      loadCount++;
    }
    if (json.containsKey('add_original_image')) {
      addOriginalImage = json['add_original_image'];
      loadCount++;
    }
    if (json.containsKey('uncond_scale')) {
      uncondScale = json['uncond_scale'] is int
          ? (json['uncond_scale'] as int).toDouble()
          : json['uncond_scale'];
      loadCount++;
    }
    if (json.containsKey('cfg_rescale')) {
      cfgRescale = json['cfg_rescale'] is int
          ? (json['cfg_rescale'] as int).toDouble()
          : json['cfg_rescale'];
      loadCount++;
    }
    if (json.containsKey('noise_schedule')) {
      noiseSchedule = json['noise_schedule'];
      loadCount++;
    }
    if (json.containsKey('negative_prompt')) {
      negativePrompt = json['negative_prompt'];
      loadCount++;
    }
    if (json.containsKey('seed')) {
      seed = json['seed'];
      randomSeed = false;
      loadCount++;
    }
    if (json.containsKey('use_coords')) {
      autoPosition = json['use_coords'];
      loadCount++;
    }
    if (json.containsKey('uc')) {
      negativePrompt = json['uc'];
      loadCount++;
    }
    return loadCount;
  }
}
