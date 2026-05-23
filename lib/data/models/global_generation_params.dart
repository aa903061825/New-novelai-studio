import '../../core/constants/defaults.dart';
import 'param_config.dart';

class GlobalGenerationParams {
  bool useGlobalSteps;
  bool useGlobalScale;
  bool useGlobalCfgRescale;
  bool useGlobalSampler;
  bool useGlobalNegativePrompt;

  int steps;
  double scale;
  double cfgRescale;
  String sampler;
  String negativePrompt;

  GlobalGenerationParams({
    this.useGlobalSteps = false,
    this.useGlobalScale = false,
    this.useGlobalCfgRescale = false,
    this.useGlobalSampler = false,
    this.useGlobalNegativePrompt = false,
    this.steps = 28,
    this.scale = 6.5,
    this.cfgRescale = 0.1,
    this.sampler = 'k_euler_ancestral',
    this.negativePrompt = defaultUC,
  });

  factory GlobalGenerationParams.fromJson(Map<String, dynamic> json) {
    return GlobalGenerationParams(
      useGlobalSteps: json['use_global_steps'] ?? false,
      useGlobalScale: json['use_global_scale'] ?? false,
      useGlobalCfgRescale: json['use_global_cfg_rescale'] ?? false,
      useGlobalSampler: json['use_global_sampler'] ?? false,
      useGlobalNegativePrompt: json['use_global_negative_prompt'] ?? false,
      steps: json['steps'] ?? 28,
      scale: (json['scale'] is int)
          ? (json['scale'] as int).toDouble()
          : (json['scale'] ?? 6.5),
      cfgRescale: (json['cfg_rescale'] is int)
          ? (json['cfg_rescale'] as int).toDouble()
          : (json['cfg_rescale'] ?? 0.1),
      sampler: json['sampler'] ?? 'k_euler_ancestral',
      negativePrompt: json['negative_prompt'] ?? defaultUC,
    );
  }

  factory GlobalGenerationParams.fromParamConfig(ParamConfig config) {
    return GlobalGenerationParams(
      steps: config.steps,
      scale: config.scale,
      cfgRescale: config.cfgRescale,
      sampler: config.sampler,
      negativePrompt: config.negativePrompt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'use_global_steps': useGlobalSteps,
      'use_global_scale': useGlobalScale,
      'use_global_cfg_rescale': useGlobalCfgRescale,
      'use_global_sampler': useGlobalSampler,
      'use_global_negative_prompt': useGlobalNegativePrompt,
      'steps': steps,
      'scale': scale,
      'cfg_rescale': cfgRescale,
      'sampler': sampler,
      'negative_prompt': negativePrompt,
    };
  }

  int resolveSteps(ParamConfig config) => useGlobalSteps ? steps : config.steps;

  double resolveScale(ParamConfig config) => useGlobalScale ? scale : config.scale;

  double resolveCfgRescale(ParamConfig config) =>
      useGlobalCfgRescale ? cfgRescale : config.cfgRescale;

  String resolveSampler(ParamConfig config) =>
      useGlobalSampler ? sampler : config.sampler;

  String resolveNegativePrompt(ParamConfig config) =>
      useGlobalNegativePrompt ? negativePrompt : config.negativePrompt;

  ParamConfig resolveParamConfig(ParamConfig config) {
    final resolved = config.copy();
    resolved.steps = resolveSteps(config);
    resolved.scale = resolveScale(config);
    resolved.cfgRescale = resolveCfgRescale(config);
    resolved.sampler = resolveSampler(config);
    resolved.negativePrompt = resolveNegativePrompt(config);
    return resolved;
  }
}
