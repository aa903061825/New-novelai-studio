import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/generation_capabilities.dart';
import 'package:novel_studio/data/models/param_config.dart';

void main() {
  test('ParamConfig defaults new and model-less configs to Novel 5', () {
    expect(ParamConfig().model, defaultGenerationModel);
    expect(
      ParamConfig.fromJson(const {
        'sizes': [
          {'width': 832, 'height': 1216},
        ],
        'scale': 6.5,
        'sampler': 'k_euler_ancestral',
        'steps': 28,
        'n_samples': 1,
        'sm': true,
        'sm_dyn': true,
        'dynamic_thresholding': false,
        'controlnet_strength': 1.0,
        'legacy': false,
        'add_original_image': false,
        'uncond_scale': 1.0,
        'cfg_rescale': 0.1,
        'noise_schedule': 'native',
        'negative_prompt': '',
        'random_seed': true,
        'seed': 0,
      }).model,
      defaultGenerationModel,
    );
  });
}
