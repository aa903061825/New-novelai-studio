import 'dart:convert';
import 'dart:io';

import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/services/workbench_metadata_import_service.dart';
import 'package:novel_studio/data/studio/tools/stable_id.dart';
import 'package:novel_studio/data/studio/tools/nai_metadata_parser.dart';

typedef ScriptRecastParseProgressCallback = void Function(
  ScriptRecastParseProgress progress,
);

enum ScriptRecastParseProgressPhase {
  scanning,
  sourcesDiscovered,
  sourceParsing,
  sourceParsed,
  complete,
}

class ScriptRecastParseProgress {
  final ScriptRecastParseProgressPhase phase;
  final int totalSources;
  final int visitedSources;
  final int parsedFrames;
  final String? fileName;

  const ScriptRecastParseProgress({
    required this.phase,
    required this.totalSources,
    required this.visitedSources,
    required this.parsedFrames,
    this.fileName,
  });

  double? get fraction {
    if (totalSources <= 0) {
      return null;
    }
    return visitedSources.clamp(0, totalSources) / totalSources;
  }
}

class ScriptRecastParserService {
  final WorkbenchMetadataImportService? metadataImportService;

  const ScriptRecastParserService({
    this.metadataImportService,
  });

  static String scriptIdForDirectory(Directory directory) {
    final path = directory.absolute.path;
    final normalizedPath = path.replaceAll('\\', '/');
    final parts = normalizedPath
        .split('/')
        .where((part) => part.trim().isNotEmpty)
        .toList(growable: false);
    final label = parts.isEmpty ? 'script' : parts.last;
    return stableIdFromText(
      prefix: 'script',
      text: normalizedPath,
      label: label,
    );
  }

  Future<Script> parseDirectory(
    Directory directory, {
    ScriptRecastParseProgressCallback? onProgress,
  }) async {
    final frames = <ScriptFrame>[];
    onProgress?.call(const ScriptRecastParseProgress(
      phase: ScriptRecastParseProgressPhase.scanning,
      totalSources: 0,
      visitedSources: 0,
      parsedFrames: 0,
    ));
    final sources = await _scriptFrameSources(directory);
    onProgress?.call(ScriptRecastParseProgress(
      phase: ScriptRecastParseProgressPhase.sourcesDiscovered,
      totalSources: sources.length,
      visitedSources: 0,
      parsedFrames: 0,
    ));
    final metadataImporter =
        metadataImportService ?? WorkbenchMetadataImportService();

    for (var sourceIndex = 0; sourceIndex < sources.length; sourceIndex += 1) {
      final source = sources[sourceIndex];
      onProgress?.call(ScriptRecastParseProgress(
        phase: ScriptRecastParseProgressPhase.sourceParsing,
        totalSources: sources.length,
        visitedSources: sourceIndex,
        parsedFrames: frames.length,
        fileName: _fileName(source.file),
      ));
      final frame = await _parseFrameSource(
        source,
        frames.length + 1,
        metadataImporter,
      );
      if (frame != null) {
        frames.add(frame);
      }
      onProgress?.call(ScriptRecastParseProgress(
        phase: ScriptRecastParseProgressPhase.sourceParsed,
        totalSources: sources.length,
        visitedSources: sourceIndex + 1,
        parsedFrames: frames.length,
        fileName: _fileName(source.file),
      ));
    }
    onProgress?.call(ScriptRecastParseProgress(
      phase: ScriptRecastParseProgressPhase.complete,
      totalSources: sources.length,
      visitedSources: sources.length,
      parsedFrames: frames.length,
    ));

    final detectedSchema = _voteSchema(frames);
    final List<String> parseWarnings = frames.isEmpty
        ? const [
            'No prompt-bearing JSON, PNG, or WEBP script frames found in this directory.',
          ]
        : frames.expand((frame) => frame.warnings).toList(growable: false);

    return Script(
      id: scriptIdForDirectory(directory),
      name: _directoryName(directory),
      rootPath: directory.path,
      frames: List.unmodifiable(frames),
      detectedSchema: detectedSchema,
      parseWarnings: parseWarnings,
      meta: {
        'frameCount': frames.length,
      },
    );
  }

  Future<List<_ScriptFrameSource>> _scriptFrameSources(
    Directory directory,
  ) async {
    if (!await directory.exists()) {
      return const [];
    }

    final jsonFiles = <File>[];
    final pngFiles = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final kind = _scriptFrameFileKind(entity);
      if (kind == null) {
        continue;
      }
      switch (kind) {
        case _ScriptFrameSourceKind.json:
          jsonFiles.add(entity);
        case _ScriptFrameSourceKind.png:
          pngFiles.add(entity);
      }
    }

    jsonFiles.sort((left, right) => _naturalCompare(
          _fileName(left),
          _fileName(right),
        ));
    pngFiles.sort((left, right) => _naturalCompare(
          _fileName(left),
          _fileName(right),
        ));
    final sources = _pairedFrameSources(
      jsonFiles: jsonFiles,
      pngFiles: pngFiles,
    );
    return List.unmodifiable(sources);
  }

  Future<ScriptFrame?> _parseFrameSource(
    _ScriptFrameSource source,
    int index,
    WorkbenchMetadataImportService metadataImporter,
  ) {
    return switch (source.kind) {
      _ScriptFrameSourceKind.json => _parseJsonFrame(source, index),
      _ScriptFrameSourceKind.png => _parsePngFrame(
          source,
          index,
          metadataImporter,
        ),
    };
  }

  Future<ScriptFrame?> _parseJsonFrame(
    _ScriptFrameSource source,
    int index,
  ) async {
    final file = source.file;
    var rawJson = '';
    try {
      rawJson = await file.readAsString();
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) {
        return source.keepParseErrors
            ? _errorFrame(
                file: file,
                index: index,
                sourceImagePath: source.sourceImagePath,
                rawJson: rawJson,
                warning: 'Frame JSON root must be an object.',
              )
            : null;
      }

      final sourcePayload = _stringKeyMap(decoded);
      final metadata = NaiMetadataParser.parseMap(sourcePayload);
      if (!_hasPromptMetadata(metadata)) {
        return null;
      }
      return _frameFromMetadata(
        file: file,
        index: index,
        sourceImagePath: source.sourceImagePath,
        rawContent: rawJson,
        sourcePayload: sourcePayload,
        metadata: metadata,
      );
    } on FormatException catch (error) {
      return source.keepParseErrors
          ? _errorFrame(
              file: file,
              index: index,
              sourceImagePath: source.sourceImagePath,
              rawJson: rawJson,
              warning: 'Malformed JSON or text encoding: ${error.message}',
            )
          : null;
    } on FileSystemException catch (error) {
      if (!source.keepParseErrors) {
        return null;
      }
      final message = error.message.contains('decode')
          ? 'Malformed JSON or text encoding: ${error.message}'
          : 'Could not read frame: ${error.message}';
      return _errorFrame(
        file: file,
        index: index,
        sourceImagePath: source.sourceImagePath,
        rawJson: rawJson,
        warning: message,
      );
    } catch (error) {
      return source.keepParseErrors
          ? _errorFrame(
              file: file,
              index: index,
              sourceImagePath: source.sourceImagePath,
              rawJson: rawJson,
              warning: 'Could not parse frame: $error',
            )
          : null;
    }
  }

  Future<ScriptFrame?> _parsePngFrame(
    _ScriptFrameSource source,
    int index,
    WorkbenchMetadataImportService metadataImporter,
  ) async {
    final file = source.file;
    try {
      final metadata = await metadataImporter.parseFile(file);
      if (!_hasPromptMetadata(metadata)) {
        return null;
      }
      final sourcePayload = _sourcePayloadFromMetadata(metadata);
      return _frameFromMetadata(
        file: file,
        index: index,
        sourceImagePath: source.sourceImagePath,
        rawContent: metadata.rawContent.isEmpty
            ? jsonEncode(sourcePayload)
            : metadata.rawContent,
        sourcePayload: sourcePayload,
        metadata: metadata,
      );
    } catch (error) {
      return null;
    }
  }

  ScriptFrame _frameFromMetadata({
    required File file,
    required int index,
    required String sourceImagePath,
    required String rawContent,
    required Map<String, dynamic> sourcePayload,
    required NaiMetadataParseResult metadata,
  }) {
    final parsed = ParsedFrame(
      baseCaption: metadata.prompt ?? '',
      charCaptions: List.unmodifiable(metadata.charCaptions),
      negativeBase: metadata.negativePrompt ?? '',
      negativeCharCaptions: List.unmodifiable(metadata.negativeCharCaptions),
      coords: List.unmodifiable(
        metadata.coords.map(
          (coord) => RecastPoint(
            x: coord['x']!.toDouble(),
            y: coord['y']!.toDouble(),
          ),
        ),
      ),
      generationParams: Map.unmodifiable(metadata.parameters),
      sourcePayload: Map.unmodifiable(sourcePayload),
    );
    return ScriptFrame(
      index: index,
      fileName: _fileName(file),
      sourcePath: file.path,
      sourceImagePath: sourceImagePath,
      rawJson: rawContent,
      parsed: parsed,
      detectedSchema: _detectFrameSchema(parsed),
      parseStatus: ScriptFrameParseStatus.parsed,
    );
  }

  ScriptFrame _errorFrame({
    required File file,
    required int index,
    required String sourceImagePath,
    required String rawJson,
    required String warning,
  }) {
    return ScriptFrame(
      index: index,
      fileName: _fileName(file),
      sourcePath: file.path,
      sourceImagePath: sourceImagePath,
      rawJson: rawJson,
      parsed: const ParsedFrame(),
      detectedSchema: ScriptSchema.unknown,
      parseStatus: ScriptFrameParseStatus.error,
      warnings: [warning],
    );
  }

  ScriptSchema _detectFrameSchema(ParsedFrame parsed) {
    if (parsed.charCaptions.isNotEmpty) {
      final base = parsed.baseCaption.toLowerCase();
      final hasInlineCharacter = parsed.charCaptions.any((caption) {
        final anchor = caption.split(',').first.trim().toLowerCase();
        return anchor.isNotEmpty && base.contains(anchor);
      });
      return hasInlineCharacter
          ? ScriptSchema.v4Partial
          : ScriptSchema.v4Slotted;
    }

    if (parsed.baseCaption.trim().isNotEmpty) {
      return ScriptSchema.baseInline;
    }

    return ScriptSchema.unknown;
  }

  ScriptSchema _voteSchema(List<ScriptFrame> frames) {
    final votes = <ScriptSchema, int>{
      for (final schema in ScriptSchema.values) schema: 0,
    };
    for (final frame in frames) {
      if (frame.parseStatus == ScriptFrameParseStatus.parsed) {
        votes[frame.detectedSchema] = votes[frame.detectedSchema]! + 1;
      }
    }

    final ranked = [
      ScriptSchema.v4Partial,
      ScriptSchema.v4Slotted,
      ScriptSchema.baseInline,
      ScriptSchema.unknown,
    ];
    ranked.sort((a, b) {
      final byVotes = votes[b]!.compareTo(votes[a]!);
      if (byVotes != 0) {
        return byVotes;
      }
      return ranked.indexOf(a).compareTo(ranked.indexOf(b));
    });

    return votes[ranked.first] == 0 ? ScriptSchema.unknown : ranked.first;
  }

  Map<String, dynamic> _stringKeyMap(Map<dynamic, dynamic> map) {
    return map.map((key, value) => MapEntry(key.toString(), value));
  }

  bool _hasPromptMetadata(NaiMetadataParseResult metadata) {
    return metadata.prompt?.trim().isNotEmpty == true ||
        metadata.charCaptions.any((caption) => caption.trim().isNotEmpty);
  }

  Map<String, dynamic> _sourcePayloadFromMetadata(
    NaiMetadataParseResult metadata,
  ) {
    final payload = <String, dynamic>{};
    final prompt = metadata.prompt?.trim();
    if (prompt != null && prompt.isNotEmpty) {
      payload['Description'] = prompt;
    }
    final source = metadata.source?.trim();
    if (source != null && source.isNotEmpty) {
      payload['Source'] = source;
    }
    final comment = <String, dynamic>{
      ...metadata.parameters,
    };
    final negativePrompt = metadata.negativePrompt?.trim();
    if (negativePrompt != null && negativePrompt.isNotEmpty) {
      comment.putIfAbsent('uc', () => negativePrompt);
    }
    if (comment.isNotEmpty) {
      payload['Comment'] = comment;
    }
    if (metadata.width != null) {
      payload['width'] = metadata.width;
    }
    if (metadata.height != null) {
      payload['height'] = metadata.height;
    }
    return payload;
  }

  String _directoryName(Directory directory) {
    final normalized = directory.path.replaceAll('\\', '/');
    final parts = normalized.split('/').where((part) => part.isNotEmpty);
    return parts.isEmpty ? directory.path : parts.last;
  }

  static final _legacyScriptFrameFilePattern = RegExp(
    r'^(?:nai_|p)(\d+)\.json$',
    caseSensitive: false,
  );
}

enum _ScriptFrameSourceKind { json, png }

class _ScriptFrameSource {
  final File file;
  final _ScriptFrameSourceKind kind;
  final String sourceImagePath;
  final bool keepParseErrors;

  const _ScriptFrameSource({
    required this.file,
    required this.kind,
    required this.sourceImagePath,
    required this.keepParseErrors,
  });
}

List<_ScriptFrameSource> _pairedFrameSources({
  required List<File> jsonFiles,
  required List<File> pngFiles,
}) {
  if (_shouldUsePngMetadataAsPrimary(
    jsonFiles: jsonFiles,
    pngFiles: pngFiles,
  )) {
    return List.unmodifiable([
      for (final png in pngFiles) _pngFrameSource(png),
    ]);
  }

  final usedJson = <File>{};
  final usedPng = <File>{};
  final paired = <_ScriptFrameSource>[];

  for (final json in jsonFiles) {
    final png = _firstMatchingPng(
      pngFiles,
      usedPng,
      (candidate) =>
          _sourceStem(_fileName(candidate)) == _sourceStem(_fileName(json)),
    );
    if (png == null) continue;
    usedJson.add(json);
    usedPng.add(png);
    paired.add(_jsonFrameSource(json, png));
  }

  _pairFrameSourcesBySequenceKey(
    jsonFiles: jsonFiles,
    pngFiles: pngFiles,
    usedJson: usedJson,
    usedPng: usedPng,
    paired: paired,
  );

  final remainingJson = [
    for (final file in jsonFiles)
      if (!usedJson.contains(file)) file,
  ];
  final remainingPng = [
    for (final file in pngFiles)
      if (!usedPng.contains(file)) file,
  ];
  if (remainingJson.isNotEmpty && remainingJson.length == remainingPng.length) {
    for (final (index, json) in remainingJson.indexed) {
      final png = remainingPng[index];
      usedJson.add(json);
      usedPng.add(png);
      paired.add(_jsonFrameSource(json, png));
    }
  }

  for (final json in jsonFiles) {
    if (usedJson.contains(json)) continue;
    paired.add(_jsonFrameSource(json, null));
  }
  for (final png in pngFiles) {
    if (usedPng.contains(png)) continue;
    paired.add(_pngFrameSource(png));
  }
  paired.sort((left, right) => _naturalCompare(
        _fileName(left.file),
        _fileName(right.file),
      ));
  return paired;
}

bool _shouldUsePngMetadataAsPrimary({
  required List<File> jsonFiles,
  required List<File> pngFiles,
}) {
  if (jsonFiles.isEmpty || pngFiles.isEmpty) {
    return false;
  }
  if (jsonFiles.length != pngFiles.length) {
    return true;
  }

  final jsonStems = {
    for (final json in jsonFiles) _sourceStem(_fileName(json)),
  };
  final pngStems = {
    for (final png in pngFiles) _sourceStem(_fileName(png)),
  };
  if (jsonStems.length != jsonFiles.length ||
      pngStems.length != pngFiles.length) {
    return true;
  }
  return !jsonStems.containsAll(pngStems) || !pngStems.containsAll(jsonStems);
}

_ScriptFrameSource _jsonFrameSource(File json, File? png) {
  return _ScriptFrameSource(
    file: json,
    kind: _ScriptFrameSourceKind.json,
    sourceImagePath: png?.path ?? '',
    keepParseErrors:
        ScriptRecastParserService._legacyScriptFrameFilePattern.hasMatch(
      _fileName(json),
    ),
  );
}

_ScriptFrameSource _pngFrameSource(File png) {
  return _ScriptFrameSource(
    file: png,
    kind: _ScriptFrameSourceKind.png,
    sourceImagePath: png.path,
    keepParseErrors: false,
  );
}

File? _firstMatchingPng(
  List<File> pngFiles,
  Set<File> usedPng,
  bool Function(File png) matches,
) {
  for (final png in pngFiles) {
    if (usedPng.contains(png)) continue;
    if (matches(png)) return png;
  }
  return null;
}

void _pairFrameSourcesBySequenceKey({
  required List<File> jsonFiles,
  required List<File> pngFiles,
  required Set<File> usedJson,
  required Set<File> usedPng,
  required List<_ScriptFrameSource> paired,
}) {
  final jsonByKey = <String, List<File>>{};
  final pngByKey = <String, List<File>>{};
  for (final json in jsonFiles) {
    if (usedJson.contains(json)) continue;
    final key = _sequenceKey(_fileName(json));
    if (key == null) continue;
    (jsonByKey[key] ??= []).add(json);
  }
  for (final png in pngFiles) {
    if (usedPng.contains(png)) continue;
    final key = _sequenceKey(_fileName(png));
    if (key == null) continue;
    (pngByKey[key] ??= []).add(png);
  }
  final keys = jsonByKey.keys.toList()..sort(_naturalCompare);
  for (final key in keys) {
    final jsonGroup = jsonByKey[key] ?? const [];
    final pngGroup = pngByKey[key] ?? const [];
    if (jsonGroup.isEmpty || jsonGroup.length != pngGroup.length) {
      continue;
    }
    for (final (index, json) in jsonGroup.indexed) {
      final png = pngGroup[index];
      usedJson.add(json);
      usedPng.add(png);
      paired.add(_jsonFrameSource(json, png));
    }
  }
}

_ScriptFrameSourceKind? _scriptFrameFileKind(File file) {
  final lowerName = _fileName(file).toLowerCase();
  if (lowerName.endsWith('.json')) {
    return _ScriptFrameSourceKind.json;
  }
  if (lowerName.endsWith('.png') || lowerName.endsWith('.webp')) {
    return _ScriptFrameSourceKind.png;
  }
  return null;
}

String _fileName(File file) {
  final normalized = file.path.replaceAll('\\', '/');
  return normalized.split('/').last;
}

String _basenameWithoutExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot <= 0 ? fileName : fileName.substring(0, dot);
}

String _sourceStem(String fileName) =>
    _basenameWithoutExtension(fileName).toLowerCase();

String? _sequenceKey(String fileName) {
  final matches = RegExp(r'\d+').allMatches(_sourceStem(fileName)).toList();
  if (matches.isEmpty) return null;
  final digits = matches.last.group(0)!.replaceFirst(RegExp(r'^0+'), '');
  return digits.isEmpty ? '0' : digits;
}

int _naturalCompare(String left, String right) {
  final leftParts = _naturalSortParts(left);
  final rightParts = _naturalSortParts(right);
  final sharedLength = leftParts.length < rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < sharedLength; index += 1) {
    final leftPart = leftParts[index];
    final rightPart = rightParts[index];
    final leftNumber = int.tryParse(leftPart);
    final rightNumber = int.tryParse(rightPart);
    final comparison = leftNumber != null && rightNumber != null
        ? leftNumber.compareTo(rightNumber)
        : leftPart.toLowerCase().compareTo(rightPart.toLowerCase());
    if (comparison != 0) {
      return comparison;
    }
  }
  return leftParts.length.compareTo(rightParts.length);
}

List<String> _naturalSortParts(String value) {
  return RegExp(r'\d+|\D+')
      .allMatches(value)
      .map((match) => match.group(0)!)
      .toList(growable: false);
}
