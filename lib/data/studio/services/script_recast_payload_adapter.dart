import 'package:novel_studio/core/constants/defaults.dart';
import 'package:novel_studio/core/constants/parameters.dart';
import 'package:novel_studio/data/models/generation_capabilities.dart';
import 'package:novel_studio/data/studio/tools/generation_prompt_sanitizer.dart';

class ScriptRecastPayloadAdapter {
  const ScriptRecastPayloadAdapter();

  Map<String, dynamic> toNaiRequestPayload(Map<String, dynamic> payload) {
    if (_isDirectRequestPayload(payload)) {
      return _normalizeDirectPayload(payload);
    }

    final model = _modelFromSource(payload['Source']);
    final capabilities = GenerationModelCapabilities.fromModel(model);
    final comment = _mapValue(payload['Comment']);
    final sourceParameters = _mapValue(payload['parameters']);
    final parameters = <String, dynamic>{
      ..._deepMutableMap(sourceParameters),
    };
    _removeDisallowedRequestParameters(parameters);
    _normalizePromptGenerationRequest(parameters);
    final baseCaption =
        sanitizeGenerationPrompt(_baseCaption(payload, comment));
    final v4Prompt = _promptMapFrom(
      comment: comment,
      key: 'v4_prompt',
      fallbackBaseCaption: baseCaption,
      defaultUseCoords: _boolValue(parameters['use_coords']) ?? true,
    );
    final v4NegativePrompt = _negativePromptMapFrom(
      comment: comment,
      fallbackBaseCaption: _negativeCaption(comment),
    );

    parameters['v4_prompt'] = v4Prompt;
    parameters['v4_negative_prompt'] = v4NegativePrompt;
    _applyDefaultBatchNegativePrompt(parameters);
    parameters.putIfAbsent('params_version', () => capabilities.paramsVersion);
    parameters.putIfAbsent('n_samples', () => 1);
    parameters.putIfAbsent('legacy_v3_extend', () => false);
    parameters.putIfAbsent('characterPrompts', () => const []);
    parameters.putIfAbsent('reference_image_multiple', () => const []);
    parameters.putIfAbsent('reference_strength_multiple', () => const []);
    parameters.putIfAbsent(
      'reference_information_extracted_multiple',
      () => const [],
    );
    _normalizeReferenceParameters(parameters);
    _applyModelCompatibility(parameters, capabilities);

    return {
      'input': baseCaption,
      'model': model,
      'action': 'generate',
      'parameters': _deepImmutableMap(parameters),
    };
  }

  bool _isDirectRequestPayload(Map<String, dynamic> payload) {
    return payload['input'] is String && payload['parameters'] is Map;
  }

  Map<String, dynamic> _normalizeDirectPayload(Map<String, dynamic> payload) {
    final model = _stringValue(payload['model']) ?? defaultGenerationModel;
    final capabilities = GenerationModelCapabilities.fromModel(model);
    final parameters = _deepMutableMap(_mapValue(payload['parameters']));
    _removeDisallowedRequestParameters(parameters);
    _normalizePromptGenerationRequest(parameters);
    _sanitizePromptParameter(parameters, 'v4_prompt');
    _sanitizePromptParameter(parameters, 'v4_negative_prompt');
    _applyDefaultBatchNegativePrompt(parameters);
    parameters.putIfAbsent('params_version', () => capabilities.paramsVersion);
    parameters.putIfAbsent('n_samples', () => 1);
    parameters.putIfAbsent('legacy_v3_extend', () => false);
    parameters.putIfAbsent('characterPrompts', () => const []);
    _normalizeReferenceParameters(parameters);
    _applyModelCompatibility(parameters, capabilities);
    return {
      'input': sanitizeGenerationPrompt(_stringValue(payload['input']) ?? ''),
      'model': model,
      'action': _stringValue(payload['action']) ?? 'generate',
      'parameters': _deepImmutableMap(parameters),
    };
  }

  void _applyDefaultBatchNegativePrompt(Map<String, dynamic> parameters) {
    final prompt = _deepMutableMap(_mapValue(parameters['v4_negative_prompt']));
    final caption = _ensureCaption(prompt);
    final merged = _mergeDefaultBatchNegativePrompt([
      _captionText(caption),
      _stringValue(parameters['negative_prompt']),
    ]);
    caption['base_caption'] = merged;
    caption.putIfAbsent('char_captions', () => const []);
    prompt.putIfAbsent('legacy_uc', () => false);
    parameters['negative_prompt'] = merged;
    parameters['v4_negative_prompt'] = _deepImmutableMap(prompt);
  }

  String _baseCaption(
    Map<String, dynamic> payload,
    Map<String, dynamic> comment,
  ) {
    final v4Base = _captionBase(comment, 'v4_prompt');
    if (v4Base != null) return v4Base;
    final commentPrompt = _stringValue(comment['prompt']);
    if (commentPrompt != null) return commentPrompt;
    final description = _stringValue(payload['Description']);
    if (description != null) return description;
    return '';
  }

  String _negativeCaption(Map<String, dynamic> comment) {
    return _captionBase(comment, 'v4_negative_prompt') ??
        _stringValue(comment['negative_prompt']) ??
        _stringValue(comment['uc']) ??
        '';
  }

  Map<String, dynamic> _promptMapFrom({
    required Map<String, dynamic> comment,
    required String key,
    required String fallbackBaseCaption,
    required bool defaultUseCoords,
  }) {
    final prompt = _deepMutableMap(_mapValue(comment[key]));
    final caption = _ensureCaption(prompt);
    caption.putIfAbsent('base_caption', () => fallbackBaseCaption);
    caption.putIfAbsent('char_captions', () => const []);
    final insertedDefaultCenters = _sanitizeCaption(caption);
    prompt.putIfAbsent('use_coords', () => defaultUseCoords);
    if (insertedDefaultCenters && prompt['use_coords'] == true) {
      prompt['use_coords'] = false;
    }
    prompt.putIfAbsent('use_order', () => true);
    return _deepImmutableMap(prompt);
  }

  Map<String, dynamic> _negativePromptMapFrom({
    required Map<String, dynamic> comment,
    required String fallbackBaseCaption,
  }) {
    final prompt = _deepMutableMap(_mapValue(comment['v4_negative_prompt']));
    final caption = _ensureCaption(prompt);
    caption.putIfAbsent('base_caption', () => fallbackBaseCaption);
    caption.putIfAbsent('char_captions', () => const []);
    _sanitizeCaption(caption);
    prompt.putIfAbsent('legacy_uc', () => false);
    return _deepImmutableMap(prompt);
  }

  Map<String, dynamic> _ensureCaption(Map<String, dynamic> prompt) {
    final existing = prompt['caption'];
    if (existing is Map) {
      final caption = _deepMutableMap(_mapValue(existing));
      prompt['caption'] = caption;
      return caption;
    }
    final caption = <String, dynamic>{};
    prompt['caption'] = caption;
    return caption;
  }

  String? _captionBase(Map<String, dynamic> comment, String key) {
    final prompt = _mapValue(comment[key]);
    final caption = _mapValue(prompt['caption']);
    return _stringValue(caption['base_caption']) ??
        _stringValue(caption['baseCaption']) ??
        _stringValue(caption['prompt']);
  }

  String _modelFromSource(Object? source) {
    final rawSource = _stringValue(source);
    if (rawSource == null) {
      return defaultGenerationModel;
    }
    final mapped = modelFromNovelAiSource(rawSource);
    if (mapped != null) {
      return mapped;
    }
    final normalized = rawSource.toLowerCase();
    if (normalized.contains('v5')) {
      return naiDiffusion5Curated;
    }
    if (normalized.contains('v4.5') || normalized.contains('v4 5')) {
      return 'nai-diffusion-4-5-full';
    }
    if (normalized.contains('v4')) {
      return 'nai-diffusion-4-full';
    }
    if (normalized.contains('furry')) {
      return 'nai-diffusion-furry-3';
    }
    return 'nai-diffusion-3';
  }

  void _sanitizePromptParameter(Map<String, dynamic> parameters, String key) {
    final prompt = parameters[key];
    if (prompt is! Map) {
      return;
    }
    final mutable = _deepMutableMap(_mapValue(prompt));
    final caption = _ensureCaption(mutable);
    final insertedDefaultCenters = _sanitizeCaption(caption);
    if (insertedDefaultCenters && mutable['use_coords'] == true) {
      mutable['use_coords'] = false;
    }
    parameters[key] = _deepImmutableMap(mutable);
  }

  bool _sanitizeCaption(Map<String, dynamic> caption) {
    var insertedDefaultCenters = false;
    final baseCaption = _stringValue(caption['base_caption']);
    if (baseCaption != null) {
      caption['base_caption'] = sanitizeGenerationPrompt(baseCaption);
    }
    final charCaptions = caption['char_captions'];
    if (charCaptions is List) {
      caption['char_captions'] = [
        for (final entry in charCaptions)
          if (entry is Map)
            _sanitizeCharCaptionEntry(
              _mapValue(entry),
              onDefaultCentersInserted: () {
                insertedDefaultCenters = true;
              },
            )
          else
            entry,
      ];
    }
    return insertedDefaultCenters;
  }

  Map<String, dynamic> _sanitizeCharCaptionEntry(
    Map<String, dynamic> entry, {
    required void Function() onDefaultCentersInserted,
  }) {
    final mutable = _deepMutableMap(entry);
    final charCaption = _stringValue(mutable['char_caption']);
    if (charCaption != null) {
      mutable['char_caption'] = sanitizeGenerationPrompt(charCaption);
    }
    if (!_hasUsableCenters(mutable['centers'])) {
      mutable['centers'] = const [
        {'x': 0.5, 'y': 0.5},
      ];
      onDefaultCentersInserted();
    }
    return _deepImmutableMap(mutable);
  }
}

String _mergeDefaultBatchNegativePrompt(Iterable<String?> originalPrompts) {
  final originals = <String>[];
  for (final value in originalPrompts) {
    var normalized = value?.trim() ?? '';
    if (normalized == defaultBatchNegativePrompt) {
      continue;
    }
    final generatedPrefix = '$defaultBatchNegativePrompt, ';
    if (normalized.startsWith(generatedPrefix)) {
      normalized = normalized.substring(generatedPrefix.length).trim();
    }
    if (normalized.isNotEmpty && !originals.contains(normalized)) {
      originals.add(normalized);
    }
  }
  return [defaultBatchNegativePrompt, ...originals].join(', ');
}

String? _captionText(Map<String, dynamic> caption) {
  return _stringValue(caption['base_caption']) ??
      _stringValue(caption['baseCaption']) ??
      _stringValue(caption['prompt']);
}

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, child) => MapEntry(key.toString(), child));
  }
  return const {};
}

String? _stringValue(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

bool? _boolValue(Object? value) {
  return value is bool ? value : null;
}

bool _hasUsableCenters(Object? value) {
  if (value is! List || value.isEmpty) {
    return false;
  }
  return value.every((entry) {
    if (entry is! Map) {
      return false;
    }
    final x = entry['x'];
    final y = entry['y'];
    return x is num && y is num;
  });
}

void _removeDisallowedRequestParameters(Map<String, dynamic> parameters) {
  parameters.removeWhere((key, _) {
    final normalized = key.toLowerCase();
    return normalized == 'extra_passthrough_testing' ||
        normalized.startsWith('extra_passthrough_testing.');
  });
}

void _normalizePromptGenerationRequest(Map<String, dynamic> parameters) {
  final requestType = _stringValue(parameters['request_type']);
  final hasEditParameters = _editOnlyParameterKeys.any(parameters.containsKey);
  if (requestType == null && !hasEditParameters) {
    return;
  }
  parameters['request_type'] = _promptGenerateRequestType;
  for (final key in _editOnlyParameterKeys) {
    parameters.remove(key);
  }
}

void _applyModelCompatibility(
  Map<String, dynamic> parameters,
  GenerationModelCapabilities capabilities,
) {
  parameters['params_version'] = capabilities.paramsVersion;
  if (!capabilities.supportsSmeaControls) {
    parameters.remove('sm');
    parameters.remove('sm_dyn');
    if (parameters['sampler'] == 'ddim_v3') {
      parameters['sampler'] = 'k_euler_ancestral';
    }
  }
  if (!capabilities.supportsNoiseSchedule) {
    parameters['noise_schedule'] = 'karras';
  } else if (capabilities.isV4 && parameters['noise_schedule'] == 'native') {
    parameters['noise_schedule'] = 'karras';
  }
  if (!capabilities.supportsVarietyPlus) {
    parameters.remove('skip_cfg_above_sigma');
  }
  if (!capabilities.supportsDynamicThresholding) {
    parameters['dynamic_thresholding'] = false;
  }
  if (!capabilities.supportsLegacyUc) {
    parameters['legacy_uc'] = false;
    final negativePrompt = parameters['v4_negative_prompt'];
    if (negativePrompt is Map) {
      parameters['v4_negative_prompt'] = <String, dynamic>{
        ..._mapValue(negativePrompt),
        'legacy_uc': false,
      };
    }
  }
  if (capabilities.isKnownModel &&
      !capabilities.supportsVibeTransfer &&
      !capabilities.supportsPreciseReference) {
    for (final key in const [
      'reference_image_multiple',
      'reference_strength_multiple',
      'reference_information_extracted_multiple',
      'director_reference_images',
      'director_reference_strength_values',
      'director_reference_secondary_strength_values',
      'director_reference_information_extracted',
      'director_reference_descriptions',
    ]) {
      parameters.remove(key);
    }
  }
}

void _normalizeReferenceParameters(Map<String, dynamic> parameters) {
  _normalizeGroupedReferenceArrays(
    parameters,
    anchorKey: 'reference_image_multiple',
    companionDefaults: {
      'reference_strength_multiple': () => 0.6,
      'reference_information_extracted_multiple': () => 1.0,
    },
    removeWhenEmpty: false,
  );
  _normalizeGroupedReferenceArrays(
    parameters,
    anchorKey: 'director_reference_images',
    companionDefaults: {
      'director_reference_strength_values': () => 0.6,
      'director_reference_secondary_strength_values': () => 0.0,
      'director_reference_information_extracted': () => 1.0,
      'director_reference_descriptions': _defaultDirectorReferenceDescription,
    },
    removeWhenEmpty: true,
  );
}

void _normalizeGroupedReferenceArrays(
  Map<String, dynamic> parameters, {
  required String anchorKey,
  required Map<String, Object? Function()> companionDefaults,
  required bool removeWhenEmpty,
}) {
  final anchor = _mutableList(parameters[anchorKey]);
  if (anchor == null || anchor.isEmpty) {
    if (removeWhenEmpty) {
      parameters.remove(anchorKey);
    } else {
      parameters[anchorKey] = const [];
    }
    for (final key in companionDefaults.keys) {
      if (removeWhenEmpty) {
        parameters.remove(key);
      } else {
        parameters[key] = const [];
      }
    }
    return;
  }

  parameters[anchorKey] = List.unmodifiable(anchor);
  final expectedLength = anchor.length;
  for (final entry in companionDefaults.entries) {
    parameters[entry.key] = List.unmodifiable(
      _normalizeSiblingList(
        parameters[entry.key],
        expectedLength: expectedLength,
        fallbackFactory: entry.value,
      ),
    );
  }
}

List<Object?> _normalizeSiblingList(
  Object? rawValue, {
  required int expectedLength,
  required Object? Function() fallbackFactory,
}) {
  final values = _mutableList(rawValue) ?? <Object?>[];
  if (values.length > expectedLength) {
    values.removeRange(expectedLength, values.length);
  }
  while (values.length < expectedLength) {
    values.add(fallbackFactory());
  }
  return values;
}

List<Object?>? _mutableList(Object? value) {
  if (value is List) {
    return value.map(_deepMutableValue).toList(growable: true);
  }
  return null;
}

Object? _defaultDirectorReferenceDescription() {
  return const {
    'caption': {
      'base_caption': 'character&style',
      'char_captions': [],
    },
    'legacy_uc': false,
  };
}

Map<String, dynamic> _deepMutableMap(Map<String, dynamic> value) {
  return value.map((key, child) => MapEntry(key, _deepMutableValue(child)));
}

Object? _deepMutableValue(Object? value) {
  if (value is Map) {
    return _deepMutableMap(_mapValue(value));
  }
  if (value is Iterable) {
    return value.map(_deepMutableValue).toList(growable: true);
  }
  return value;
}

const _promptGenerateRequestType = 'PromptGenerateRequest';

const _editOnlyParameterKeys = {
  'add_original_image',
  'image',
  'img2img',
  'mask',
  'strength',
};

Map<String, dynamic> _deepImmutableMap(Map<String, dynamic> value) {
  return Map.unmodifiable(
    value.map((key, child) => MapEntry(key, _deepImmutableValue(child))),
  );
}

Object? _deepImmutableValue(Object? value) {
  if (value is Map) {
    return _deepImmutableMap(_mapValue(value));
  }
  if (value is Iterable) {
    return List.unmodifiable(value.map(_deepImmutableValue));
  }
  return value;
}
