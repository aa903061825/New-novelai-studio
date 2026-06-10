import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final cacheDir = Directory(options.cacheDir);
  final files = await cacheDir
      .list()
      .where((entity) => entity is File && entity.path.endsWith('.json'))
      .cast<File>()
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));

  final packets = <Map<String, dynamic>>[];
  for (final file in files) {
    final cache = jsonDecode(await file.readAsString(encoding: utf8))
        as Map<String, dynamic>;
    final scriptId = _string(cache['scriptId']);
    if (options.scriptIds.isNotEmpty && !options.scriptIds.contains(scriptId)) {
      continue;
    }
    final packet = _packetForCache(cache, file.path);
    final frames = packet['uncovered_base_frames'] as List<dynamic>;
    if (options.onlyUncovered && frames.isEmpty) {
      continue;
    }
    packets.add(packet);
  }

  if (options.outputDir == null) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(packets));
    return;
  }

  final outputDir = Directory(options.outputDir!);
  await outputDir.create(recursive: true);
  for (final packet in packets) {
    final scriptId = _string(packet['script_id']);
    final file = File(
      [outputDir.path, '${_safeFileName(scriptId)}.json']
          .join(Platform.pathSeparator),
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(packet),
      encoding: utf8,
    );
    stdout.writeln(
      'WROTE ${file.path} uncovered='
      '${(packet['uncovered_base_frames'] as List<dynamic>).length}',
    );
  }
}

Map<String, dynamic> _packetForCache(
  Map<String, dynamic> cache,
  String cacheFile,
) {
  final frames = _framesFromCacheOrSource(cache);
  final extraction = _map(cache['aiRoleExtraction']);
  final roles = _list(extraction['roles']).cast<Map<String, dynamic>>();
  final coveredBase = <int>{};
  for (final role in roles) {
    for (final appearance
        in _list(role['appearances']).cast<Map<String, dynamic>>()) {
      final sourceId = _string(appearance['source_id']).toLowerCase();
      final sourceKind = _string(appearance['source_kind']).toLowerCase();
      if (!_isBaseSource(sourceId) && !_isBaseSource(sourceKind)) {
        continue;
      }
      coveredBase.addAll(_intList(appearance['frame_indexes']));
    }
  }

  final byIndex = {
    for (final frame in frames) _int(frame['index']): frame,
  };
  final uncovered = <Map<String, dynamic>>[];
  for (final frame in frames) {
    final parsed = _map(frame['parsed']);
    if (_string(frame['parseStatus']) != 'parsed') {
      continue;
    }
    final base = _string(parsed['baseCaption']);
    if (base.trim().isEmpty) {
      continue;
    }
    final hasSlot = _list(parsed['charCaptions'])
        .map(_string)
        .any((caption) => caption.trim().isNotEmpty);
    if (hasSlot) {
      continue;
    }
    final index = _int(frame['index']);
    if (coveredBase.contains(index)) {
      continue;
    }
    uncovered.add({
      'frame_index': index,
      'file_name': _string(frame['fileName']),
      'base_caption': base,
      'nearby_context': [
        for (var offset = -3; offset <= 3; offset += 1)
          if (offset != 0 && byIndex[index + offset] != null)
            _frameContext(byIndex[index + offset]!),
      ],
      'candidate_roles_nearby': _candidateRolesNearFrame(roles, index),
    });
  }

  return {
    'script_id': _string(cache['scriptId']),
    'script_name': _string(cache['scriptName']),
    'cache_file': cacheFile,
    'instructions': [
      'Assign only frames whose base_caption clearly contains an identifiable character or generic role.',
      'Do not assign style, artist, quality, camera, scene, action-only, or relationship-count prompts.',
      'Use an existing role when possible. Create a new role only when the base frames consistently identify a character not present in existing roles.',
      'Return an assignment JSON file; do not edit the cache directly.',
    ],
    'roles': [
      for (final role in roles) _roleEvidence(role),
    ],
    'uncovered_base_frames': uncovered,
  };
}

List<Map<String, dynamic>> _framesFromCacheOrSource(
    Map<String, dynamic> cache) {
  final script = _map(cache['scriptSnapshot']);
  final snapshotFrames = _list(script['frames'])
      .map(_map)
      .where((frame) => frame.isNotEmpty)
      .toList(growable: false);
  if (snapshotFrames.isNotEmpty) {
    return snapshotFrames;
  }

  final root = Directory(_string(cache['sourceRootPath']));
  if (!root.existsSync()) {
    return const [];
  }
  final rawFiles = root.listSync().whereType<File>().where((file) {
    final lower = file.path.toLowerCase();
    return lower.endsWith('.json') || lower.endsWith('.png');
  }).toList();
  final filesByStem = <String, File>{};
  for (final file in rawFiles) {
    final stem = _fileStem(file.path);
    final existing = filesByStem[stem];
    if (existing == null || file.path.toLowerCase().endsWith('.json')) {
      filesByStem[stem] = file;
    }
  }
  final files = filesByStem.values.toList();
  files.sort((left, right) {
    final numberCompare =
        _fileNumber(left.path).number.compareTo(_fileNumber(right.path).number);
    if (numberCompare != 0) return numberCompare;
    return left.path.compareTo(right.path);
  });
  final parsedNumbers = [
    for (final file in files) _fileNumber(file.path),
  ];
  final zeroBased = parsedNumbers.any(
    (number) => number.found && number.number == 0,
  );

  final frames = <Map<String, dynamic>>[];
  for (final (offset, file) in files.indexed) {
    final fileNumber = parsedNumbers[offset];
    final index =
        fileNumber.found ? fileNumber.number + (zeroBased ? 1 : 0) : offset + 1;
    final source = _readSourceFile(file);
    final comment = _map(source['Comment']);
    final caption = _map(_map(_map(comment['v4_prompt'])['caption']));
    final baseCaption =
        _string(caption['base_caption'] ?? source['Description']);
    final rawCharCaptions = _list(caption['char_captions']);
    final charCaptions = [
      for (final raw in rawCharCaptions)
        if (raw is Map) _string(raw['char_caption']) else _string(raw),
    ];
    frames.add({
      'index': index,
      'fileName': _fileName(file.path),
      'parseStatus': 'parsed',
      'parsed': {
        'baseCaption': baseCaption,
        'charCaptions': charCaptions,
      },
    });
  }
  return frames;
}

Map<String, dynamic> _readSourceFile(File file) {
  if (file.path.toLowerCase().endsWith('.png')) {
    return _readPngMetadata(file);
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync(encoding: utf8));
    return _map(decoded);
  } catch (_) {
    return <String, dynamic>{};
  }
}

Map<String, dynamic> _readPngMetadata(File file) {
  try {
    final bytes = file.readAsBytesSync();
    final metadata = <String, dynamic>{};
    var offset = 8;
    while (offset + 8 <= bytes.length) {
      final length = _uint32(bytes, offset);
      final type = ascii.decode(bytes.sublist(offset + 4, offset + 8));
      final start = offset + 8;
      final end = start + length;
      if (end > bytes.length) {
        break;
      }
      if (type == 'tEXt') {
        final chunk = bytes.sublist(start, end);
        final zero = chunk.indexOf(0);
        if (zero > 0) {
          final key = latin1.decode(chunk.sublist(0, zero));
          final value = utf8.decode(
            chunk.sublist(zero + 1),
            allowMalformed: true,
          );
          metadata[key] = value;
        }
      } else if (type == 'iTXt') {
        final entry = _decodeInternationalText(bytes.sublist(start, end));
        if (entry != null) {
          metadata[entry.key] = entry.value;
        }
      } else if (type == 'zTXt') {
        final entry = _decodeCompressedText(bytes.sublist(start, end));
        if (entry != null) {
          metadata[entry.key] = entry.value;
        }
      }
      offset = end + 4;
    }
    final comment = metadata['Comment'];
    if (comment is String && comment.trim().isNotEmpty) {
      try {
        metadata['Comment'] = jsonDecode(comment);
      } catch (_) {
        // Keep the raw text if it is not JSON.
      }
    }
    return metadata;
  } catch (_) {
    return <String, dynamic>{};
  }
}

({String key, String value})? _decodeInternationalText(Uint8List chunk) {
  final keywordEnd = chunk.indexOf(0);
  if (keywordEnd <= 0 || keywordEnd + 2 >= chunk.length) {
    return null;
  }
  final key = latin1.decode(chunk.sublist(0, keywordEnd));
  final compressed = chunk[keywordEnd + 1] == 1;
  var cursor = keywordEnd + 3;
  for (var separators = 0; separators < 2; separators += 1) {
    final next = _indexOfZero(chunk, cursor);
    if (next < 0) {
      return null;
    }
    cursor = next + 1;
  }
  final textBytes = chunk.sublist(cursor);
  final decoded = compressed ? zlib.decode(textBytes) : textBytes;
  return (
    key: key,
    value: utf8.decode(decoded, allowMalformed: true),
  );
}

({String key, String value})? _decodeCompressedText(Uint8List chunk) {
  final keywordEnd = chunk.indexOf(0);
  if (keywordEnd <= 0 || keywordEnd + 2 >= chunk.length) {
    return null;
  }
  final key = latin1.decode(chunk.sublist(0, keywordEnd));
  final compressedBytes = chunk.sublist(keywordEnd + 2);
  return (
    key: key,
    value: utf8.decode(zlib.decode(compressedBytes), allowMalformed: true),
  );
}

int _indexOfZero(Uint8List bytes, int start) {
  for (var index = start; index < bytes.length; index += 1) {
    if (bytes[index] == 0) {
      return index;
    }
  }
  return -1;
}

int _uint32(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

({bool found, int number}) _fileNumber(String path) {
  final name = _fileName(path);
  final match = RegExp(r'(\d+)').allMatches(name).lastOrNull;
  if (match == null) {
    return (found: false, number: 1 << 30);
  }
  return (
    found: true,
    number: int.tryParse(match.group(1) ?? '') ?? (1 << 30),
  );
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? normalized : normalized.substring(slash + 1);
}

String _fileStem(String path) {
  final name = _fileName(path);
  final dot = name.lastIndexOf('.');
  return dot < 0 ? name : name.substring(0, dot);
}

Map<String, dynamic> _roleEvidence(Map<String, dynamic> role) {
  return {
    'source_role_id': _string(role['source_role_id']),
    'display_name': _string(role['display_name']),
    'source_kind': _string(role['source_kind']),
    'confidence': role['confidence'],
    'frame_indexes': _intList(role['frame_indexes']),
    'appearances': [
      for (final appearance
          in _list(role['appearances']).cast<Map<String, dynamic>>())
        {
          'source_id': _string(appearance['source_id']),
          'source_kind': _string(appearance['source_kind']),
          'frame_indexes': _intList(appearance['frame_indexes']),
        },
    ],
    'stages': [
      for (final stage in _list(role['stages']).cast<Map<String, dynamic>>())
        {
          'stage_id': _string(stage['stage_id']),
          'label': _string(stage['label']),
          'frame_indexes': _intList(stage['frame_indexes']),
          'identity': _string(stage['identity']),
          'upper_body': _string(stage['upper_body']),
          'lower_body': _string(stage['lower_body']),
          'upper_clothing': _string(stage['upper_clothing']),
          'lower_clothing': _string(stage['lower_clothing']),
          'non_role': _string(stage['non_role']),
          'evidence_terms': _stringList(stage['evidence_terms']),
        },
    ],
  };
}

Map<String, dynamic> _frameContext(Map<String, dynamic> frame) {
  final parsed = _map(frame['parsed']);
  return {
    'frame_index': _int(frame['index']),
    'file_name': _string(frame['fileName']),
    'base_caption_excerpt': _excerpt(_string(parsed['baseCaption'])),
    'char_captions': [
      for (final caption in _list(parsed['charCaptions']))
        _excerpt(_string(caption)),
    ],
  };
}

List<Map<String, dynamic>> _candidateRolesNearFrame(
  List<Map<String, dynamic>> roles,
  int frameIndex,
) {
  final candidates = <Map<String, dynamic>>[];
  for (final role in roles) {
    var distance = 1000000;
    for (final index in _intList(role['frame_indexes'])) {
      final current = (index - frameIndex).abs();
      if (current < distance) {
        distance = current;
      }
    }
    if (distance <= 5) {
      candidates.add({
        'source_role_id': _string(role['source_role_id']),
        'display_name': _string(role['display_name']),
        'nearest_distance': distance,
      });
    }
  }
  candidates.sort(
    (left, right) => _int(left['nearest_distance'])
        .compareTo(_int(right['nearest_distance'])),
  );
  return candidates;
}

bool _isBaseSource(String value) {
  return value == 'base' ||
      value == 'global' ||
      value.startsWith('base-') ||
      value.startsWith('global-');
}

String _excerpt(String value) {
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length <= 600) {
    return normalized;
  }
  return '${normalized.substring(0, 600)}...';
}

String _safeFileName(String value) {
  return value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return <String, dynamic>{};
}

List<dynamic> _list(Object? value) => value is List ? value : const [];

String _string(Object? value) => value?.toString() ?? '';

List<String> _stringList(Object? value) {
  return [for (final item in _list(value)) _string(item)];
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(_string(value)) ?? 0;
}

List<int> _intList(Object? value) {
  final result = <int>[];
  for (final item in _list(value)) {
    result.add(_int(item));
  }
  result.sort();
  return List.unmodifiable(result);
}

class _Options {
  final String cacheDir;
  final Set<String> scriptIds;
  final String? outputDir;
  final bool onlyUncovered;

  const _Options({
    required this.cacheDir,
    required this.scriptIds,
    required this.outputDir,
    required this.onlyUncovered,
  });

  factory _Options.parse(List<String> args) {
    final values = <String, String>{};
    final flags = <String>{};
    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      if (!arg.startsWith('--')) continue;
      final equals = arg.indexOf('=');
      if (equals > 0) {
        values[arg.substring(2, equals)] = arg.substring(equals + 1);
        continue;
      }
      final key = arg.substring(2);
      if (index + 1 < args.length && !args[index + 1].startsWith('--')) {
        values[key] = args[index + 1];
        index += 1;
      } else {
        flags.add(key);
      }
    }
    final appData = Platform.environment['APPDATA'] ?? '';
    final cacheDir = values['cache-dir'] ??
        [
          appData,
          'org.exception0x0194',
          'nai3_autodraw',
          'novel_studio',
          'script_recast',
          'cache',
        ].join(Platform.pathSeparator);
    return _Options(
      cacheDir: cacheDir,
      scriptIds: {
        for (final id in (values['script-id'] ?? '').split(','))
          if (id.trim().isNotEmpty) id.trim(),
      },
      outputDir: values['out-dir'],
      onlyUncovered: !flags.contains('all'),
    );
  }
}
