import 'package:novel_studio/data/models/generation_capabilities.dart';

const models = generationModels;
const samplers = [
  'k_euler',
  'k_euler_ancestral',
  'k_dpmpp_2s_ancestral',
  'k_dpmpp_2m_sde',
  'k_dpmpp_sde',
  'k_dpmpp_2m',
  'ddim_v3'
];
const samplersV4 = [
  'k_euler',
  'k_euler_ancestral',
  'k_dpmpp_2s_ancestral',
  'k_dpmpp_2m_sde',
  'k_dpmpp_sde',
  'k_dpmpp_2m',
];
const noiseSchedules = [
  'native',
  'karras',
  'exponential',
  'polyexponential',
];
const noiseSchedulesV4 = [
  'karras',
  'exponential',
  'polyexponential',
];

const List<String> commentKeys = [
  'uc',
  'scale',
  'sampler',
  'steps',
  'n_samples',
  'ucPreset',
  'qualityToggle',
  'tag_hint_qt',
  'tag_hint_uc_preset',
  'tag_hint_transparent_background',
  'straight_alpha',
  'sm',
  'sm_dyn',
  'dynamic_thresholding',
  'controlnet_strength',
  'legacy',
  'add_original_image',
  'uncond_scale',
  'cfg_rescale',
  'noise_schedule',
  'negative_prompt',
  'seed',
  'use_coords',
];

const Map<String, String> sourceToModel = {
  'Stable Diffusion XL C1E1DE52': 'nai-diffusion-3',
  'Stable Diffusion XL 7BCCAA2C': 'nai-diffusion-3',
  'Stable Diffusion XL 9CC2F394': 'nai-diffusion-furry-3',
  'NovelAI Diffusion V4 F6E18726': 'nai-diffusion-4-curated-preview',
  'NovelAI Diffusion V4 79F47848': 'nai-diffusion-4-full',
  'NovelAI Diffusion V4.5 4BDE2A90': 'nai-diffusion-4-5-full',
  'NovelAI Diffusion V5 657484A5': naiDiffusion5Full,
  'NovelAI Diffusion V5 0ADF9AB7': naiDiffusion5Full,
};

String? modelFromNovelAiSource(Object? source) {
  final rawSource = source?.toString().trim();
  if (rawSource == null || rawSource.isEmpty) return null;
  final exact = sourceToModel[rawSource];
  if (exact != null) return exact;
  if (rawSource.toLowerCase().contains('novelai diffusion v5')) {
    return naiDiffusion5Curated;
  }
  return null;
}
