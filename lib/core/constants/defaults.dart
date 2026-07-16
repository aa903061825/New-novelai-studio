import '../../data/models/generation_size.dart';

const defaultWatermarkContent =
    '{"Description": "👻👻👻", "Software": "NovelAI", "Source": "Stable Diffusion XL 9CC2F394", "Generation time": "11.4514", "Comment": "{\\"prompt\\": \\"👻👻👻\\", \\"steps\\": 28, \\"height\\": 1024, \\"width\\": 1024, \\"scale\\": 5, \\"uncond_scale\\": 1.0, \\"cfg_rescale\\": 0.0, \\"seed\\": \\"\\", \\"n_samples\\": 1, \\"hide_debug_overlay\\": false, \\"noise_schedule\\": \\"native\\", \\"legacy_v3_extend\\": false, \\"reference_information_extracted_multiple\\": [], \\"reference_strength_multiple\\": [], \\"sampler\\": \\"k_euler_ancestral\\", \\"controlnet_strength\\": 1.0, \\"controlnet_model\\": null, \\"dynamic_thresholding\\": false, \\"dynamic_thresholding_percentile\\": 0.999, \\"dynamic_thresholding_mimic_scale\\": 10.0, \\"sm\\": false, \\"sm_dyn\\": false, \\"skip_cfg_below_sigma\\": 0.0, \\"lora_unet_weights\\": null, \\"lora_clip_weights\\": null, \\"uc\\": \\"\\", \\"request_type\\": \\"PromptGenerateRequest\\", \\"signed_hash\\": \\"\\"}"}';
const defaultUC =
    'lowres, {bad}, error, fewer, extra, missing, worst quality, jpeg artifacts, bad quality, watermark, unfinished, displeasing, chromatic aberration, signature, extra digits, artistic error, username, scan, [abstract], bad anatomy, bad hands';
const defaultBatchNegativePrompt =
    '{{{{{{{{{{bad quality, low quality, worst quality}}}}}}}}}}, '
    '3:: multiple_views ::, '
    '1.5:: bad pupils ::, '
    '1.5:: bad glabella ::, '
    '1.5:: glazed eye ::, '
    '1.5:: bad hands ::, '
    '1.5:: bad eyes ::, '
    '1.5:: displeasing ::, '
    '1.5:: very displeasing ::, '
    '1.5:: bad anatomy ::, '
    '1.5:: missing finger ::, '
    '1.5:: extra finger ::, '
    '1.5:: extra digits ::, '
    '1.5:: fewer digits ::, '
    '1.5:: bad face ::, '
    '1.5:: duplicate ::, '
    '1.5:: mutation ::, '
    '1.5:: deformed ::, '
    '1.5:: disfigured ::, '
    '1.5:: extra arms ::, '
    '1.5:: extra legs ::, '
    '1.5:: long neck ::, '
    '1.5:: bad feet ::, '
    '1.5:: bad proportions ::, '
    '1.5:: missing ::, '
    'censored}}}}}, '
    '{{{{artist:bkub, mosaic censoring, mosaic}}}}, '
    'chibi, flat color, bar censoring::, {{blurry}}, {bad}, lowres, '
    'artistic error, error, film grain, scan artifacts, jpeg artifacts, '
    'chromatic aberration, dithering, blank page, too many watermarks, '
    'speech bubble, text, greyscale, cropped, signature, watermark, username, '
    'pubic hair, artist name, bad perspective, bad aspect ratio, lightsaber, '
    'beam saber, artist collaboration';
const defaultFilenamePrefix = 'NAI-generated';
const defaultSizes = [
  GenerationSize(width: 704, height: 1472),
  GenerationSize(width: 832, height: 1216),
  GenerationSize(width: 1024, height: 1024),
  GenerationSize(width: 1216, height: 832),
  GenerationSize(width: 1472, height: 704),
];
