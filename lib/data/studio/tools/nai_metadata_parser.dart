import 'dart:convert';

class NaiMetadataParseResult {
  final String? prompt;
  final String rawContent;
  final Map<String, dynamic> parameters;
  final int? width;
  final int? height;
  final List<String> charCaptions;
  final List<Map<String, num>> coords;
  final bool hasStructuredMetadata;

  const NaiMetadataParseResult({
    required this.prompt,
    required this.rawContent,
    required this.parameters,
    required this.width,
    required this.height,
    required this.charCaptions,
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
      rawContent: payload,
      parameters: const {},
      width: null,
      height: null,
      charCaptions: const [],
      coords: const [],
      hasStructuredMetadata: false,
    );
  }

  static NaiMetadataParseResult parseMap(Map<String, dynamic> payload) {
    final rawContent = _rawContentFor(payload);
    final merged = <String, dynamic>{};
    final fallbackFragments = <String>[];

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
    absorb(payload['Comment']);
    absorb(payload['fullContent']);
    absorb(payload['Stealth_PNGInfo']);

    final prompt = _firstString([
      payload['Description'],
      payload['prompt'],
      payload['Prompt'],
      merged['Description'],
      merged['prompt'],
      merged['Prompt'],
      _v4BaseCaption(merged),
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
    final charCaptions = _extractCharCaptions(merged);
    final coords = _extractCoords(merged);
    final hasStructuredMetadata = merged.isNotEmpty ||
        prompt != null && payload.containsKey('Description') ||
        width != null ||
        height != null ||
        charCaptions.isNotEmpty ||
        coords.isNotEmpty;

    return NaiMetadataParseResult(
      prompt: prompt,
      rawContent: rawContent.isNotEmpty
          ? rawContent
          : fallbackFragments.join('\n').trim(),
      parameters: Map.unmodifiable(merged),
      width: width,
      height: height,
      charCaptions: List.unmodifiable(charCaptions),
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
    return jsonEncode(payload);
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

  static String? _v4BaseCaption(Map<String, dynamic> parameters) {
    final caption = _v4Caption(parameters);
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

  static Map<String, dynamic>? _v4Caption(Map<String, dynamic> parameters) {
    final v4Prompt = parameters['v4_prompt'];
    if (v4Prompt is! Map) {
      return null;
    }
    final caption = v4Prompt['caption'];
    if (caption is! Map) {
      return null;
    }
    return _stringKeyMap(caption);
  }

  static List<String> _extractCharCaptions(Map<String, dynamic> parameters) {
    final captions = _charCaptionEntries(parameters);
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
  ) {
    final caption = _v4Caption(parameters);
    final entries = caption?['char_captions'] ?? parameters['char_captions'];
    if (entries is! List) {
      return const [];
    }
    return entries
        .whereType<Map>()
        .map(_stringKeyMap)
        .toList(growable: false);
  }

  static List<Map<String, num>> _extractCoords(
    Map<String, dynamic> parameters,
  ) {
    final coords = <Map<String, num>>[];
    _addCoords(coords, parameters['coords']);
    for (final entry in _charCaptionEntries(parameters)) {
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

  static const _containerKeys = {
    'Comment',
    'Description',
    'fullContent',
    'Stealth_PNGInfo',
    'parameters',
    'Source',
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
