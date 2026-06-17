import 'dart:convert';

class CompactedJsonMap {
  final Map<String, dynamic> value;
  final bool changed;

  const CompactedJsonMap(this.value, this.changed);
}

class RecastCacheJsonCodec {
  const RecastCacheJsonCodec._();

  static CompactedJsonMap compact(Map<String, dynamic> json) {
    var changed = false;
    final result = Map<String, dynamic>.from(json);
    final scriptSnapshot = result['scriptSnapshot'];
    if (scriptSnapshot is Map) {
      final compacted = _compactRecastScriptSnapshot(_jsonMap(scriptSnapshot));
      if (compacted.changed) {
        result['scriptSnapshot'] = compacted.value;
        changed = true;
      }
    }
    return CompactedJsonMap(result, changed);
  }
}

class WorkspaceSanitizer {
  const WorkspaceSanitizer._();

  static Map<String, dynamic> sanitizeMap(Map<String, dynamic> value) {
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (_isSensitiveKey(entry.key)) {
        continue;
      }
      final sanitized = _sanitizeValue(entry.value);
      if (sanitized != null) {
        result[entry.key] = sanitized;
      }
    }
    return result;
  }
}

class _CompactedJsonValue {
  final dynamic value;
  final bool changed;

  const _CompactedJsonValue(this.value, this.changed);
}

const _recastHeavyPayloadKeys = <String>{
  'director_reference_descriptions',
  'director_reference_images',
  'director_reference_information_extracted',
  'director_reference_secondary_strength_values',
  'director_reference_strength_values',
  'reference_image',
  'reference_image_multiple',
  'reference_images',
  'reference_information_extracted',
  'reference_information_extracted_multiple',
  'reference_strength',
  'reference_strength_multiple',
};

const _recastHeavyPayloadKeyNames = <String>{
  'directorreferencedescriptions',
  'directorreferenceimages',
  'directorreferenceinformationextracted',
  'directorreferencesecondarystrengthvalues',
  'directorreferencestrengthvalues',
  'referenceimage',
  'referenceimagemultiple',
  'referenceimages',
  'referenceinformationextracted',
  'referenceinformationextractedmultiple',
  'referencestrength',
  'referencestrengthmultiple',
};

CompactedJsonMap _compactRecastScriptSnapshot(Map<String, dynamic> json) {
  var changed = false;
  final result = Map<String, dynamic>.from(json);
  final frames = result['frames'];
  if (frames is List) {
    var framesChanged = false;
    final nextFrames = <dynamic>[];
    for (final frame in frames) {
      if (frame is Map) {
        final compacted = _compactRecastFrameJson(_jsonMap(frame));
        nextFrames.add(compacted.value);
        framesChanged = framesChanged || compacted.changed;
      } else {
        nextFrames.add(frame);
      }
    }
    if (framesChanged) {
      result['frames'] = nextFrames;
      changed = true;
    }
  }

  final meta = result['meta'];
  if (meta is Map) {
    final compacted = _compactRecastPayloadMap(_jsonMap(meta));
    if (compacted.changed) {
      result['meta'] = compacted.value;
      changed = true;
    }
  }

  return CompactedJsonMap(result, changed);
}

CompactedJsonMap _compactRecastFrameJson(Map<String, dynamic> json) {
  var changed = false;
  final result = Map<String, dynamic>.from(json);

  final rawJson = _compactRecastRawJson(result['rawJson']);
  if (rawJson.changed) {
    result['rawJson'] = rawJson.value;
    changed = true;
  }

  final parsed = result['parsed'];
  if (parsed is Map) {
    final compacted = _compactRecastParsedFrameJson(_jsonMap(parsed));
    if (compacted.changed) {
      result['parsed'] = compacted.value;
      changed = true;
    }
  }

  return CompactedJsonMap(result, changed);
}

CompactedJsonMap _compactRecastParsedFrameJson(Map<String, dynamic> json) {
  var changed = false;
  final result = Map<String, dynamic>.from(json);

  for (final key in const ['generationParams', 'sourcePayload']) {
    final compacted = _compactRecastPayloadValue(result[key]);
    if (compacted.changed) {
      result[key] = compacted.value;
      changed = true;
    }
  }

  return CompactedJsonMap(result, changed);
}

CompactedJsonMap _compactRecastPayloadMap(Map<String, dynamic> json) {
  final compacted = _compactRecastPayloadValue(json);
  return CompactedJsonMap(
    Map<String, dynamic>.from(compacted.value as Map),
    compacted.changed,
  );
}

_CompactedJsonValue _compactRecastPayloadValue(dynamic value) {
  if (value is Map) {
    var changed = false;
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      final rawKey = entry.key;
      final key = rawKey is String ? rawKey : rawKey.toString();
      if (rawKey is! String) {
        changed = true;
      }
      if (_isHeavyRecastPayloadKey(key)) {
        changed = true;
        continue;
      }

      final compacted = key == 'Comment'
          ? _compactRecastCommentValue(entry.value)
          : _compactRecastPayloadValue(entry.value);
      result[key] = compacted.value;
      changed = changed || compacted.changed;
    }
    return _CompactedJsonValue(result, changed);
  }

  if (value is List) {
    var changed = false;
    final result = <dynamic>[];
    for (final item in value) {
      final compacted = _compactRecastPayloadValue(item);
      result.add(compacted.value);
      changed = changed || compacted.changed;
    }
    return _CompactedJsonValue(changed ? result : value, changed);
  }

  return _CompactedJsonValue(value, false);
}

_CompactedJsonValue _compactRecastCommentValue(dynamic value) {
  if (value is! String) {
    return _compactRecastPayloadValue(value);
  }
  if (!_containsHeavyRecastPayloadKey(value)) {
    return _CompactedJsonValue(value, false);
  }

  try {
    final decoded = jsonDecode(value);
    final compacted = _compactRecastPayloadValue(decoded);
    if (compacted.changed) {
      return _CompactedJsonValue(jsonEncode(compacted.value), true);
    }
  } on FormatException {
    if (value.length > 32768) {
      return const _CompactedJsonValue('', true);
    }
  }

  return _CompactedJsonValue(value, false);
}

_CompactedJsonValue _compactRecastRawJson(dynamic value) {
  if (value is! String || !_containsHeavyRecastPayloadKey(value)) {
    return _CompactedJsonValue(value, false);
  }

  try {
    final decoded = jsonDecode(value);
    final compacted = _compactRecastPayloadValue(decoded);
    if (compacted.changed) {
      return _CompactedJsonValue(jsonEncode(compacted.value), true);
    }
  } on FormatException {
    if (value.length > 32768) {
      return const _CompactedJsonValue('', true);
    }
  }

  return _CompactedJsonValue(value, false);
}

bool _containsHeavyRecastPayloadKey(String value) {
  for (final key in _recastHeavyPayloadKeys) {
    if (value.contains(key)) {
      return true;
    }
  }
  return false;
}

bool _isHeavyRecastPayloadKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return _recastHeavyPayloadKeys.contains(key) ||
      _recastHeavyPayloadKeyNames.contains(normalized);
}

dynamic _sanitizeValue(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return _isSensitiveString(value) ? null : value;
  }
  if (value is Map) {
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String || _isSensitiveKey(key)) {
        continue;
      }
      final sanitized = _sanitizeValue(entry.value);
      if (sanitized != null) {
        result[key] = sanitized;
      }
    }
    return result;
  }
  if (value is List) {
    final result = <dynamic>[];
    for (final item in value) {
      final sanitized = _sanitizeValue(item);
      if (sanitized != null) {
        result.add(sanitized);
      }
    }
    return result;
  }
  if (value is num || value is bool) {
    return value;
  }
  return value.toString();
}

bool _isSensitiveKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return normalized.contains('apikey') ||
      normalized.contains('token') ||
      normalized.contains('authorization') ||
      normalized.contains('bearer') ||
      normalized.contains('password') ||
      normalized.contains('secret') ||
      normalized.contains('private') ||
      normalized.contains('proxy') ||
      normalized.contains('url');
}

bool _isSensitiveString(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.startsWith('bearer ') || normalized.contains('pst-');
}

Map<String, dynamic> _jsonMap(dynamic json) {
  if (json is! Map) {
    throw const FormatException('Expected a JSON object.');
  }

  return json.map((key, value) {
    if (key is! String) {
      throw const FormatException('JSON object keys must be strings.');
    }
    return MapEntry(key, value);
  });
}
