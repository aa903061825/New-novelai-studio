import 'dart:convert';

class NaiMetadataParseResult {
  final String? prompt;
  final String? source;
  final String? negativePrompt;
  final String rawContent;
  final Map<String, dynamic> parameters;
  final int? width;
  final int? height;
  final List<String> charCaptions;
  final List<String> negativeCharCaptions;
  final List<Map<String, num>> coords;
  final bool hasStructuredMetadata;

  const NaiMetadataParseResult({
    required this.prompt,
    required this.source,
    required this.negativePrompt,
    required this.rawContent,
    required this.parameters,
    required this.width,
    required this.height,
    required this.charCaptions,
    required this.negativeCharCaptions,
    required this.coords,
    required this.hasStructuredMetadata,
  });

  String? get resolution {
    final parsedWidth = width;
    final parsedHeight = height;
    if (parsedWidth == null || parsedHeight == null) {
      return null;
    }
    return '${parsedWidth}x$parsedHeight';
  }
}

class _ComfyPromptMetadata {
  final String? prompt;
  final String? negativePrompt;
  final Map<String, dynamic> parameters;

  const _ComfyPromptMetadata({
    required this.prompt,
    required this.negativePrompt,
    required this.parameters,
  });
}

class _ComfyPromptCandidate {
  final String? prompt;
  final String? negativePrompt;
  final Map<String, dynamic> parameters;
  final int score;

  const _ComfyPromptCandidate({
    required this.prompt,
    required this.negativePrompt,
    required this.parameters,
    required this.score,
  });
}

class NaiMetadataParser {
  const NaiMetadataParser._();

  static NaiMetadataParseResult parse(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      return parseMap(payload);
    }
    if (payload is Map) {
      return parseMap(_stringKeyMap(payload));
    }
    return parseString(payload?.toString() ?? '');
  }

  static NaiMetadataParseResult parseString(String payload) {
    final decoded = _tryDecodeJson(payload);
    if (decoded is Map) {
      return parseMap(_stringKeyMap(decoded));
    }

    return NaiMetadataParseResult(
      prompt: payload.trim().isEmpty ? null : payload,
      source: null,
      negativePrompt: null,
      rawContent: payload,
      parameters: const {},
      width: null,
      height: null,
      charCaptions: const [],
      negativeCharCaptions: const [],
      coords: const [],
      hasStructuredMetadata: false,
    );
  }

  static NaiMetadataParseResult parseMap(Map<String, dynamic> payload) {
    final rawContent = _rawContentFor(payload);
    final merged = <String, dynamic>{};
    final fallbackFragments = <String>[];
    final comfyMetadata = _comfyPromptMetadata(payload['prompt']);

    void absorb(dynamic value) {
      if (value == null) {
        return;
      }
      final decoded = _decodePayload(value);
      if (decoded is Map) {
        final normalized = _stringKeyMap(decoded);
        _mergeIfStructured(merged, normalized);
        absorb(normalized['Comment']);
        absorb(normalized['Description']);
        absorb(normalized['fullContent']);
        absorb(normalized['Stealth_PNGInfo']);
      } else if (decoded is String && decoded.trim().isNotEmpty) {
        fallbackFragments.add(decoded);
      }
    }

    _mergeIfStructured(merged, payload);
    if (comfyMetadata != null) {
      _mergeMetadata(merged, comfyMetadata.parameters);
    }
    absorb(payload['Comment']);
    absorb(payload['fullContent']);
    absorb(payload['Stealth_PNGInfo']);

    final prompt = _firstString([
      payload['Description'],
      comfyMetadata?.prompt,
      if (comfyMetadata == null) payload['prompt'],
      payload['Prompt'],
      merged['Description'],
      if (comfyMetadata == null) merged['prompt'],
      merged['Prompt'],
      _v4BaseCaption(merged, 'v4_prompt'),
    ]);
    final source = _firstString([
      payload['Source'],
      payload['source'],
      merged['Source'],
      merged['source'],
    ]);
    final negativePrompt = _firstString([
      payload['negative_prompt'],
      payload['uc'],
      comfyMetadata?.negativePrompt,
      merged['negative_prompt'],
      merged['uc'],
      _v4BaseCaption(merged, 'v4_negative_prompt'),
    ]);

    final width = _firstInt([
      payload['width'],
      payload['Width'],
      merged['width'],
      merged['Width'],
      _resolutionPart(payload['resolution'], 0),
      _resolutionPart(payload['Resolution'], 0),
      _resolutionPart(merged['resolution'], 0),
      _resolutionPart(merged['Resolution'], 0),
    ]);
    final height = _firstInt([
      payload['height'],
      payload['Height'],
      merged['height'],
      merged['Height'],
      _resolutionPart(payload['resolution'], 1),
      _resolutionPart(payload['Resolution'], 1),
      _resolutionPart(merged['resolution'], 1),
      _resolutionPart(merged['Resolution'], 1),
    ]);
    final charCaptions = _extractCharCaptions(merged, 'v4_prompt');
    final negativeCharCaptions =
        _extractCharCaptions(merged, 'v4_negative_prompt');
    final coords = _extractCoords(merged);
    final hasStructuredMetadata = merged.isNotEmpty ||
        comfyMetadata != null ||
        prompt != null && payload.containsKey('Description') ||
        negativePrompt != null ||
        width != null ||
        height != null ||
        charCaptions.isNotEmpty ||
        negativeCharCaptions.isNotEmpty ||
        coords.isNotEmpty;

    return NaiMetadataParseResult(
      prompt: prompt,
      source: source,
      negativePrompt: negativePrompt,
      rawContent: rawContent.isNotEmpty
          ? rawContent
          : fallbackFragments.join('\n').trim(),
      parameters: Map.unmodifiable(merged),
      width: width,
      height: height,
      charCaptions: List.unmodifiable(charCaptions),
      negativeCharCaptions: List.unmodifiable(negativeCharCaptions),
      coords: List.unmodifiable(
        coords.map((coord) => Map<String, num>.unmodifiable(coord)),
      ),
      hasStructuredMetadata: hasStructuredMetadata,
    );
  }

  static void _mergeIfStructured(
    Map<String, dynamic> target,
    Map<String, dynamic> source,
  ) {
    if (_looksStructured(source)) {
      _mergeMetadata(target, source);
    }
  }

  static void _mergeMetadata(
    Map<String, dynamic> target,
    Map<String, dynamic> source,
  ) {
    for (final entry in source.entries) {
      if (entry.key == 'parameters' && entry.value is Map) {
        target.addAll(_stringKeyMap(entry.value as Map));
        continue;
      }
      if (entry.key == 'parameters' && entry.value is String) {
        final parametersMetadata = _parametersTextMetadata(entry.value);
        if (parametersMetadata != null) {
          if (parametersMetadata.prompt != null) {
            target.putIfAbsent('prompt', () => parametersMetadata.prompt);
          }
          if (parametersMetadata.negativePrompt != null) {
            target.putIfAbsent(
              'negative_prompt',
              () => parametersMetadata.negativePrompt,
            );
          }
          target.addAll(parametersMetadata.parameters);
        }
        continue;
      }
      if (entry.key == 'prompt') {
        final comfyMetadata = _comfyPromptMetadata(entry.value);
        if (comfyMetadata != null) {
          target.addAll(comfyMetadata.parameters);
          continue;
        }
      }
      if (_containerKeys.contains(entry.key)) {
        continue;
      }
      if (entry.value != null) {
        target[entry.key] = entry.value;
      }
    }
  }

  static bool _looksStructured(Map<String, dynamic> source) {
    return source.keys.any(_structuredKeys.contains);
  }

  static String _rawContentFor(Map<String, dynamic> payload) {
    const preferredKeys = [
      'Description',
      'Comment',
      'fullContent',
      'Stealth_PNGInfo',
    ];
    final parts = <String>[];
    for (final key in preferredKeys) {
      final value = payload[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        parts.add(value.toString());
      }
    }
    if (parts.isNotEmpty) {
      return parts.join('\n');
    }
    final safePayload = <String, dynamic>{};
    for (final entry in payload.entries) {
      if (entry.key == 'imageBytes') {
        continue;
      }
      safePayload[entry.key] = entry.value;
    }
    return safePayload.isEmpty ? '' : jsonEncode(safePayload);
  }

  static dynamic _decodePayload(dynamic value) {
    if (value is String) {
      return _tryDecodeJson(value) ?? value;
    }
    return value;
  }

  static dynamic _tryDecodeJson(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        !(trimmed.startsWith('{') ||
            trimmed.startsWith('[') ||
            trimmed.startsWith('"'))) {
      return null;
    }
    try {
      return jsonDecode(trimmed);
    } on FormatException {
      return null;
    }
  }

  static _ComfyPromptMetadata? _parametersTextMetadata(dynamic value) {
    if (value is! String) {
      return null;
    }
    final text = value.trim();
    if (text.isEmpty) {
      return null;
    }

    final negativeMatch = RegExp(
      r'(?:^|\n)\s*Negative prompt:\s*',
      caseSensitive: false,
    ).firstMatch(text);
    final stepsMatch = RegExp(
      r'(?:^|\n)\s*Steps:\s*',
      caseSensitive: false,
    ).firstMatch(text);

    final promptEnd = negativeMatch?.start ?? stepsMatch?.start ?? text.length;
    final prompt = text.substring(0, promptEnd).trim();

    String? negativePrompt;
    if (negativeMatch != null) {
      final negativeEnd =
          stepsMatch != null && stepsMatch.start > negativeMatch.end
              ? stepsMatch.start
              : text.length;
      negativePrompt = text.substring(negativeMatch.end, negativeEnd).trim();
    }

    final settingsText = stepsMatch == null
        ? ''
        : text.substring(stepsMatch.start).trim().replaceFirst(
              RegExp(r'^Steps:\s*', caseSensitive: false),
              'Steps: ',
            );
    final parameters = _parametersTextValues(settingsText);

    if (prompt.isEmpty &&
        (negativePrompt == null || negativePrompt.isEmpty) &&
        parameters.isEmpty) {
      return null;
    }
    return _ComfyPromptMetadata(
      prompt: prompt.isEmpty ? null : prompt,
      negativePrompt: negativePrompt == null || negativePrompt.isEmpty
          ? null
          : negativePrompt,
      parameters: parameters,
    );
  }

  static Map<String, dynamic> _parametersTextValues(String settingsText) {
    final parameters = <String, dynamic>{};
    if (settingsText.trim().isEmpty) {
      return parameters;
    }
    for (final part in settingsText.split(',')) {
      final index = part.indexOf(':');
      if (index <= 0) {
        continue;
      }
      final key = part.substring(0, index).trim().toLowerCase();
      final value = part.substring(index + 1).trim();
      if (value.isEmpty) {
        continue;
      }
      switch (key) {
        case 'steps':
          parameters['steps'] = _toInt(value) ?? value;
        case 'sampler':
          parameters['sampler'] = value;
        case 'cfg scale':
          parameters['scale'] = _firstNum([value]) ?? value;
        case 'seed':
          parameters['seed'] = _toInt(value) ?? value;
        case 'size':
          final width = _resolutionPart(value, 0);
          final height = _resolutionPart(value, 1);
          if (width != null) parameters['width'] = width;
          if (height != null) parameters['height'] = height;
        case 'model':
          parameters['model'] = value;
        case 'model hash':
          parameters['model_hash'] = value;
      }
    }
    return parameters;
  }

  static Map<String, dynamic> _stringKeyMap(Map<dynamic, dynamic> map) {
    return map.map((key, value) => MapEntry(key.toString(), value));
  }

  static String? _firstString(List<dynamic> values) {
    for (final value in values) {
      if (value is String && value.trim().isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static int? _firstInt(List<dynamic> values) {
    for (final value in values) {
      final parsed = _toInt(value);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  static int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  static int? _resolutionPart(dynamic value, int index) {
    if (value is List && value.length > index) {
      return _toInt(value[index]);
    }
    if (value is! String) {
      return null;
    }
    final match = RegExp(r'(\d+)\s*[xX*]\s*(\d+)').firstMatch(value);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(index + 1)!);
  }

  static String? _v4BaseCaption(
    Map<String, dynamic> parameters,
    String key,
  ) {
    final caption = _v4Caption(parameters, key);
    if (caption == null) {
      return null;
    }
    return _firstString([
      caption['base_caption'],
      caption['baseCaption'],
      caption['prompt'],
      caption['caption'],
    ]);
  }

  static Map<String, dynamic>? _v4Caption(
    Map<String, dynamic> parameters,
    String key,
  ) {
    final v4Prompt = parameters[key];
    if (v4Prompt is! Map) {
      return null;
    }
    final caption = v4Prompt['caption'];
    if (caption is! Map) {
      return null;
    }
    return _stringKeyMap(caption);
  }

  static List<String> _extractCharCaptions(
    Map<String, dynamic> parameters,
    String key,
  ) {
    final captions = _charCaptionEntries(parameters, key);
    return captions
        .map(
          (entry) => _firstString([
            entry['char_caption'],
            entry['caption'],
            entry['prompt'],
            entry['base_caption'],
          ]),
        )
        .whereType<String>()
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> _charCaptionEntries(
    Map<String, dynamic> parameters,
    String key,
  ) {
    final caption = _v4Caption(parameters, key);
    final entries = key == 'v4_prompt'
        ? (caption == null ? null : caption['char_captions']) ??
            parameters['char_captions']
        : caption == null
            ? null
            : caption['char_captions'];
    if (entries is! List) {
      return const [];
    }
    return entries.whereType<Map>().map(_stringKeyMap).toList(growable: false);
  }

  static List<Map<String, num>> _extractCoords(
    Map<String, dynamic> parameters,
  ) {
    final coords = <Map<String, num>>[];
    _addCoords(coords, parameters['coords']);
    for (final entry in _charCaptionEntries(parameters, 'v4_prompt')) {
      _addCoords(coords, entry['coords']);
      _addCoords(coords, entry['centers']);
      _addCoords(coords, entry['center']);
    }
    return coords;
  }

  static void _addCoords(List<Map<String, num>> target, dynamic value) {
    if (value is List) {
      for (final item in value) {
        _addCoords(target, item);
      }
      return;
    }
    if (value is! Map) {
      return;
    }
    final map = _stringKeyMap(value);
    final x = map['x'];
    final y = map['y'];
    if (x is num && y is num) {
      target.add({'x': x, 'y': y});
    }
  }

  static _ComfyPromptMetadata? _comfyPromptMetadata(dynamic value) {
    final graph = _comfyPromptGraph(value);
    if (graph == null) {
      return null;
    }
    return _extractComfyPromptMetadata(graph);
  }

  static Map<String, dynamic>? _comfyPromptGraph(dynamic value) {
    final decoded = _decodePayload(value);
    if (decoded is! Map) {
      return null;
    }
    final graph = _stringKeyMap(decoded);
    if (!_looksLikeComfyPromptGraph(graph)) {
      return null;
    }
    return graph;
  }

  static bool _looksLikeComfyPromptGraph(Map<String, dynamic> graph) {
    if (graph.isEmpty) {
      return false;
    }
    for (final value in graph.values) {
      if (value is! Map) {
        continue;
      }
      final node = _stringKeyMap(value);
      if (node['class_type'] is String && node['inputs'] is Map) {
        return true;
      }
    }
    return false;
  }

  static _ComfyPromptMetadata _extractComfyPromptMetadata(
    Map<String, dynamic> graph,
  ) {
    final nodes = <String, Map<String, dynamic>>{};
    for (final entry in graph.entries) {
      if (entry.value is Map) {
        nodes[entry.key] = _stringKeyMap(entry.value as Map);
      }
    }

    final candidates = <_ComfyPromptCandidate>[];
    for (final entry in nodes.entries) {
      final node = entry.value;
      final inputs = _comfyInputs(node);
      if (!inputs.containsKey('positive') && !inputs.containsKey('negative')) {
        continue;
      }
      final positive = _resolveComfyText(
        inputs['positive'],
        nodes,
        <String>{entry.key},
      );
      final negative = _resolveComfyText(
        inputs['negative'],
        nodes,
        <String>{entry.key},
      );
      if (positive == null && negative == null) {
        continue;
      }
      candidates.add(
        _ComfyPromptCandidate(
          prompt: positive,
          negativePrompt: negative,
          parameters: _comfyParametersFor(inputs, nodes),
          score: _comfyCandidateScore(node, inputs, positive, negative),
        ),
      );
    }

    if (candidates.isNotEmpty) {
      candidates.sort((left, right) => right.score.compareTo(left.score));
      final best = candidates.first;
      return _ComfyPromptMetadata(
        prompt: best.prompt,
        negativePrompt: best.negativePrompt,
        parameters: best.parameters,
      );
    }

    final encodedText = <String>[];
    for (final entry in nodes.entries) {
      final className = nodes[entry.key]?['class_type']?.toString() ?? '';
      if (!className.contains('CLIPTextEncode')) {
        continue;
      }
      final text = _resolveComfyText(
        _comfyInputs(entry.value)['text'],
        nodes,
        <String>{entry.key},
      );
      if (text != null) {
        encodedText.add(text);
      }
    }
    return _ComfyPromptMetadata(
      prompt: encodedText.isEmpty ? null : encodedText.first,
      negativePrompt: encodedText.length > 1 ? encodedText[1] : null,
      parameters: _comfyParametersFor(const {}, nodes),
    );
  }

  static int _comfyCandidateScore(
    Map<String, dynamic> node,
    Map<String, dynamic> inputs,
    String? positive,
    String? negative,
  ) {
    final className = node['class_type']?.toString().toLowerCase() ?? '';
    var score = 0;
    if (positive != null) score += 100;
    if (negative != null) score += 25;
    if (className.contains('sampler')) score += 12;
    if (className.contains('loader')) score += 10;
    if (inputs.containsKey('seed')) score += 4;
    if (inputs.containsKey('steps')) score += 4;
    if (inputs.containsKey('cfg')) score += 3;
    if (className.contains('text')) score -= 10;
    return score;
  }

  static Map<String, dynamic> _comfyInputs(Map<String, dynamic> node) {
    final inputs = node['inputs'];
    return inputs is Map ? _stringKeyMap(inputs) : const {};
  }

  static String? _resolveComfyText(
    dynamic value,
    Map<String, Map<String, dynamic>> nodes,
    Set<String> seen,
  ) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      if (_comfyPromptGraph(value) != null) {
        return null;
      }
      return _cleanComfyText(value);
    }
    if (value is List) {
      if (value.isNotEmpty) {
        final id = value.first.toString();
        if (nodes.containsKey(id)) {
          return _resolveComfyNodeText(id, nodes, seen);
        }
      }
      final parts = value
          .map((item) => _resolveComfyText(item, nodes, {...seen}))
          .whereType<String>()
          .toList(growable: false);
      return _joinComfyText(parts, ' ');
    }
    if (value is Map) {
      final map = _stringKeyMap(value);
      for (final key in const [
        'text',
        'positive',
        'prompt',
        'caption',
        'source',
      ]) {
        final resolved = _resolveComfyText(map[key], nodes, {...seen});
        if (resolved != null) {
          return resolved;
        }
      }
    }
    return null;
  }

  static String? _resolveComfyNodeText(
    String id,
    Map<String, Map<String, dynamic>> nodes,
    Set<String> seen,
  ) {
    if (seen.contains(id)) {
      return null;
    }
    final node = nodes[id];
    if (node == null) {
      return null;
    }
    seen.add(id);
    final inputs = _comfyInputs(node);

    final joined = _resolveComfyJoinedStrings(inputs, nodes, seen);
    if (joined != null) {
      return joined;
    }

    for (final key in const [
      'text',
      'positive',
      'prompt',
      'caption',
      'source',
    ]) {
      final resolved = _resolveComfyText(inputs[key], nodes, {...seen});
      if (resolved != null) {
        return resolved;
      }
    }
    return null;
  }

  static String? _resolveComfyJoinedStrings(
    Map<String, dynamic> inputs,
    Map<String, Map<String, dynamic>> nodes,
    Set<String> seen,
  ) {
    final entries = inputs.entries
        .where((entry) => RegExp(r'^string_\d+$').hasMatch(entry.key))
        .toList(growable: false)
      ..sort((left, right) {
        final leftIndex = int.tryParse(left.key.split('_').last) ?? 0;
        final rightIndex = int.tryParse(right.key.split('_').last) ?? 0;
        return leftIndex.compareTo(rightIndex);
      });
    if (entries.isEmpty) {
      return null;
    }
    final delimiter =
        inputs['delimiter'] is String ? inputs['delimiter'] as String : ' ';
    final parts = entries
        .map((entry) => _resolveComfyText(entry.value, nodes, {...seen}))
        .whereType<String>()
        .toList(growable: false);
    return _joinComfyText(parts, delimiter);
  }

  static String? _cleanComfyText(String value) {
    final cleaned = value.trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  static String? _joinComfyText(List<String> parts, String delimiter) {
    final cleaned = parts
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (cleaned.isEmpty) {
      return null;
    }
    return cleaned.join(delimiter);
  }

  static Map<String, dynamic> _comfyParametersFor(
    Map<String, dynamic> primaryInputs,
    Map<String, Map<String, dynamic>> nodes,
  ) {
    final parameters = <String, dynamic>{};
    void add(String key, dynamic value, {bool overwrite = true}) {
      if (value != null && (overwrite || !parameters.containsKey(key))) {
        parameters[key] = value;
      }
    }

    void absorbInputs(Map<String, dynamic> inputs, {bool overwrite = true}) {
      add('seed', _firstInt([inputs['seed']]), overwrite: overwrite);
      add('steps', _firstInt([inputs['steps']]), overwrite: overwrite);
      add('scale', _firstNum([inputs['cfg']]), overwrite: overwrite);
      add(
        'sampler',
        _firstString([inputs['sampler_name'], inputs['sampler']]),
        overwrite: overwrite,
      );
      add(
        'noise_schedule',
        _firstString([inputs['scheduler']]),
        overwrite: overwrite,
      );
      add(
        'width',
        _firstInt([inputs['width'], inputs['empty_latent_width']]),
        overwrite: overwrite,
      );
      add(
        'height',
        _firstInt([inputs['height'], inputs['empty_latent_height']]),
        overwrite: overwrite,
      );
    }

    absorbInputs(primaryInputs);
    for (final node in nodes.values) {
      final inputs = _comfyInputs(node);
      if (!parameters.containsKey('width') ||
          !parameters.containsKey('height')) {
        absorbInputs(inputs, overwrite: false);
      }
      if (parameters.containsKey('width') &&
          parameters.containsKey('height') &&
          parameters.containsKey('seed') &&
          parameters.containsKey('steps')) {
        break;
      }
    }
    return parameters;
  }

  static num? _firstNum(List<dynamic> values) {
    for (final value in values) {
      if (value is num) {
        return value;
      }
      if (value is String) {
        final parsed = num.tryParse(value.trim());
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  static const _containerKeys = {
    'Comment',
    'Description',
    'fullContent',
    'Stealth_PNGInfo',
    'parameters',
    'Source',
    'workflow',
  };

  static const _structuredKeys = {
    'Prompt',
    'prompt',
    'parameters',
    'width',
    'Width',
    'height',
    'Height',
    'resolution',
    'Resolution',
    'v4_prompt',
    'v4_negative_prompt',
    'char_captions',
    'coords',
    'steps',
    'seed',
    'scale',
    'sampler',
    'uc',
    'negative_prompt',
  };
}
