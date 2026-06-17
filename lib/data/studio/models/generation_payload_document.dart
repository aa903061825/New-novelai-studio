class GenerationPayloadDocument {
  final Map<String, dynamic> payload;
  final Map<String, dynamic> parameters;

  const GenerationPayloadDocument._({
    required this.payload,
    required this.parameters,
  });

  factory GenerationPayloadDocument.fromMap(Map<String, dynamic> payload) {
    final normalizedPayload = Map<String, dynamic>.unmodifiable(
      payload.map((key, value) => MapEntry(key.toString(), value)),
    );
    return GenerationPayloadDocument._(
      payload: normalizedPayload,
      parameters: Map<String, dynamic>.unmodifiable(
        _mapValue(normalizedPayload['parameters']),
      ),
    );
  }

  Map<String, dynamic> get positiveV4Prompt {
    return _mapValue(parameters['v4_prompt']);
  }

  Map<String, dynamic> get negativeV4Prompt {
    return _mapValue(parameters['v4_negative_prompt']);
  }

  String get positivePrompt {
    return _captionPrompt(positiveV4Prompt) ??
        _stringValue(payload['input']) ??
        _stringValue(payload['Description']) ??
        '';
  }

  String get negativePrompt {
    return _captionPrompt(negativeV4Prompt) ??
        _stringValue(parameters['negative_prompt']) ??
        _stringValue(parameters['uc']) ??
        '';
  }

  List<GenerationParameterGroup> get visibleParameterGroups {
    final byKey = <String, GenerationParameter>{};
    void add(String key, Object? value) {
      if (_hiddenNaiParams.contains(key)) return;
      if (_isLargeOrNestedParameter(value)) return;
      byKey.putIfAbsent(key, () => _visibleParameter(key, value));
    }

    final model = _stringValue(payload['model']);
    if (model != null) add('model', model);
    for (final entry in parameters.entries) {
      add(entry.key, entry.value);
    }

    final byGroup = <String, List<GenerationParameter>>{};
    for (final parameter in byKey.values) {
      byGroup.putIfAbsent(parameter.groupId, () => []).add(parameter);
    }

    return [
      for (final spec in _parameterGroupSpecs)
        if (byGroup[spec.id] case final parameters?)
          GenerationParameterGroup(
            id: spec.id,
            parameters: List.unmodifiable(
              parameters..sort(_compareVisibleParameters),
            ),
          ),
    ];
  }
}

class GenerationParameterGroup {
  final String id;
  final List<GenerationParameter> parameters;

  const GenerationParameterGroup({
    required this.id,
    required this.parameters,
  });
}

class GenerationParameter {
  final String key;
  final Object? rawValue;
  final String groupId;
  final bool highlight;
  final bool monospace;

  const GenerationParameter({
    required this.key,
    required this.rawValue,
    required this.groupId,
    required this.highlight,
    required this.monospace,
  });
}

class _ParameterGroupSpec {
  final String id;
  final String title;

  const _ParameterGroupSpec(this.id, this.title);
}

const _parameterGroupSpecs = [
  _ParameterGroupSpec('core', 'Core'),
  _ParameterGroupSpec('quality', 'Quality'),
  _ParameterGroupSpec('request', 'Request'),
  _ParameterGroupSpec('other', 'Other'),
];

const _parameterOrder = [
  'model',
  'width',
  'height',
  'steps',
  'scale',
  'sampler',
  'seed',
  'cfg_schedule_eligibility',
  'controlnet_strength',
  'deliberate_euler_ancestral_bug',
  'dynamic_thresholding_mimic_scale',
  'dynamic_thresholding_percentile',
  'eplike_fine_detail',
  'minimize_sigma_inf',
  'prefer_brownian',
  'skip_cfg_above_sigma',
  'skip_cfg_below_sigma',
  'uncond_per_vibe',
  'wonky_vibe_correlation',
  'request_type',
  'n_samples',
  'params_version',
  'version',
  'signed_hash',
];

const _coreParameterKeys = {
  'model',
  'width',
  'height',
  'steps',
  'scale',
  'sampler',
  'seed',
};

const _qualityParameterKeys = {
  'cfg_schedule_eligibility',
  'controlnet_strength',
  'deliberate_euler_ancestral_bug',
  'dynamic_thresholding_mimic_scale',
  'dynamic_thresholding_percentile',
  'eplike_fine_detail',
  'minimize_sigma_inf',
  'prefer_brownian',
  'skip_cfg_above_sigma',
  'skip_cfg_below_sigma',
  'uncond_per_vibe',
  'wonky_vibe_correlation',
};

const _requestParameterKeys = {
  'n_samples',
  'params_version',
  'request_type',
  'signed_hash',
  'version',
};

const _highlightParameterKeys = {
  'model',
  'width',
  'height',
  'steps',
  'scale',
  'sampler',
  'seed',
};

const _hiddenNaiParams = {
  'sm',
  'sm_dyn',
  'cfg_rescale',
  'noise_schedule',
  'uncond_scale',
  'dynamic_thresholding',
  'eta',
  'negative_momentum',
  'legacy_v3_extend',
  'negative_prompt',
  'uc',
  'v4_prompt',
  'v4_negative_prompt',
  'characterPrompts',
  'reference_image_multiple',
  'reference_strength_multiple',
  'reference_information_extracted_multiple',
  'director_reference_images',
  'director_reference_strength_values',
  'director_reference_secondary_strength_values',
  'director_reference_information_extracted',
  'director_reference_descriptions',
};

GenerationParameter _visibleParameter(String key, Object? value) {
  final groupId = _parameterGroupForKey(key);
  final valueText = _valueText(value);
  return GenerationParameter(
    key: key,
    rawValue: value,
    groupId: groupId,
    highlight: _highlightParameterKeys.contains(key),
    monospace: _isTechnicalParameter(key, valueText),
  );
}

int _compareVisibleParameters(GenerationParameter a, GenerationParameter b) {
  final aIndex = _parameterOrder.indexOf(a.key);
  final bIndex = _parameterOrder.indexOf(b.key);
  if (aIndex != bIndex) {
    if (aIndex == -1) return 1;
    if (bIndex == -1) return -1;
    return aIndex.compareTo(bIndex);
  }
  return a.key.compareTo(b.key);
}

String _parameterGroupForKey(String key) {
  if (_coreParameterKeys.contains(key)) return 'core';
  if (_qualityParameterKeys.contains(key) ||
      key.contains('cfg') ||
      key.contains('sigma') ||
      key.contains('threshold')) {
    return 'quality';
  }
  if (_requestParameterKeys.contains(key) || key.contains('hash')) {
    return 'request';
  }
  return 'other';
}

bool _isTechnicalParameter(String key, String value) {
  return key.contains('hash') ||
      key.contains('fingerprint') ||
      key.contains('request') ||
      value.length > 32;
}

bool _isLargeOrNestedParameter(Object? value) {
  return value is Map || value is List;
}

String _valueText(Object? value) {
  return switch (value) {
    null => '-',
    bool() => value ? 'true' : 'false',
    num() => value.toString(),
    _ => value.toString(),
  };
}

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
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

String? _captionPrompt(Map<String, dynamic> prompt) {
  final caption = _mapValue(prompt['caption']);
  final parts = <String>[];
  final base = _firstStringValue([
    caption['base_caption'],
    caption['baseCaption'],
    caption['prompt'],
    caption['caption'],
  ]);
  if (base != null) parts.add(base);

  final charCaptions = caption['char_captions'] ?? prompt['char_captions'];
  if (charCaptions is Iterable) {
    for (final entry in charCaptions) {
      final value = entry is Map
          ? _firstStringValue([
              entry['char_caption'],
              entry['caption'],
              entry['base_caption'],
              entry['baseCaption'],
              entry['prompt'],
            ])
          : _stringValue(entry);
      if (value != null) parts.add(value);
    }
  }

  if (parts.isEmpty) return null;
  return parts.map((part) => part.trim()).where((part) => part.isNotEmpty).join(
        ', ',
      );
}

String? _firstStringValue(Iterable<Object?> values) {
  for (final value in values) {
    final string = _stringValue(value);
    if (string != null) return string;
  }
  return null;
}
