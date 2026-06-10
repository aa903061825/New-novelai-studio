import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nai_casrand/data/studio/models/script_ai_role_extraction.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/models/script_recast_knowledge.dart';
import 'package:nai_casrand/data/studio/tools/nai_metadata_parser.dart';
import 'package:nai_casrand/data/studio/tools/stable_id.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:png_chunks_extract/png_chunks_extract.dart' as png_extract;

Future<void> main(List<String> args) async {
  final options = _ImportOptions.parse(args);
  final report = await importScriptRecastImageSetCaches(
    sourceRoot: options.sourceRoot,
    workspaceRoot: options.workspaceRoot,
    dryRun: options.dryRun,
    recursive: options.recursive,
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
  if (report.errors > 0) {
    exitCode = 1;
  }
}

Future<ImportScriptRecastImageSetCachesReport>
    importScriptRecastImageSetCaches({
  required String sourceRoot,
  required String workspaceRoot,
  bool dryRun = false,
  bool recursive = false,
}) async {
  final source = Directory(sourceRoot);
  if (!await source.exists()) {
    throw StateError('Source root does not exist: $sourceRoot');
  }

  final workspace = WorkspaceService();
  await workspace.openWorkspace(workspaceRoot);
  final existingCaches = await workspace.loadRecastScriptCaches();
  final rows = <ImportScriptRecastImageSetCacheRow>[];

  for (final directory in await _candidateDirectories(source, recursive)) {
    try {
      final script = await _parseDirectory(directory);
      if (script.frames.isEmpty) {
        rows.add(ImportScriptRecastImageSetCacheRow(
          status: 'skipped_no_frames',
          scriptId: script.id,
          scriptName: script.name,
          sourceRootPath: directory.path,
          frameCount: 0,
          cacheFileName: '',
        ));
        continue;
      }

      final fingerprint = _sourceFingerprint(script);
      final exactExisting = _bestExactCacheForScript(
        existingCaches,
        script: script,
        sourceFingerprint: fingerprint,
      );
      final relatedExisting = exactExisting ??
          _bestRelatedCacheForScript(existingCaches, script: script);
      final cache = _cacheForScript(
        script: script,
        sourceFingerprint: fingerprint,
        existing: relatedExisting,
        exactExisting: exactExisting,
      );

      if (!dryRun) {
        await workspace.saveRecastScriptCache(cache);
      }
      rows.add(ImportScriptRecastImageSetCacheRow(
        status: dryRun ? 'would_write' : 'written',
        scriptId: cache.scriptId,
        scriptName: cache.scriptName,
        sourceRootPath: cache.sourceRootPath,
        frameCount: script.frames.length,
        cacheFileName:
            '${safeWorkspaceEntityId(prefix: 'script', id: cache.scriptId)}.json',
        preservedAiDraft: exactExisting != null &&
            exactExisting.aiRoleExtraction.status !=
                ScriptAiRoleExtractionStatus.idle,
      ));
    } catch (error) {
      rows.add(ImportScriptRecastImageSetCacheRow(
        status: 'error',
        scriptId: '',
        scriptName: _directoryName(directory),
        sourceRootPath: directory.path,
        frameCount: 0,
        cacheFileName: '',
        message: error.toString(),
      ));
    }
  }

  return ImportScriptRecastImageSetCachesReport(
    sourceRoot: source.path,
    workspaceRoot: workspaceRoot,
    dryRun: dryRun,
    rows: List.unmodifiable(rows),
  );
}

class ImportScriptRecastImageSetCachesReport {
  final String sourceRoot;
  final String workspaceRoot;
  final bool dryRun;
  final List<ImportScriptRecastImageSetCacheRow> rows;

  const ImportScriptRecastImageSetCachesReport({
    required this.sourceRoot,
    required this.workspaceRoot,
    required this.dryRun,
    required this.rows,
  });

  int get written => rows.where((row) => row.status == 'written').length;

  int get wouldWrite => rows.where((row) => row.status == 'would_write').length;

  int get skipped =>
      rows.where((row) => row.status.startsWith('skipped')).length;

  int get errors => rows.where((row) => row.status == 'error').length;

  Map<String, dynamic> toJson() => {
        'source_root': sourceRoot,
        'workspace_root': workspaceRoot,
        'dry_run': dryRun,
        'written': written,
        'would_write': wouldWrite,
        'skipped': skipped,
        'errors': errors,
        'rows': [for (final row in rows) row.toJson()],
      };
}

class ImportScriptRecastImageSetCacheRow {
  final String status;
  final String scriptId;
  final String scriptName;
  final String sourceRootPath;
  final int frameCount;
  final String cacheFileName;
  final bool preservedAiDraft;
  final String message;

  const ImportScriptRecastImageSetCacheRow({
    required this.status,
    required this.scriptId,
    required this.scriptName,
    required this.sourceRootPath,
    required this.frameCount,
    required this.cacheFileName,
    this.preservedAiDraft = false,
    this.message = '',
  });

  Map<String, dynamic> toJson() => {
        'status': status,
        if (scriptId.isNotEmpty) 'script_id': scriptId,
        'script_name': scriptName,
        'source_root_path': sourceRootPath,
        'frame_count': frameCount,
        if (cacheFileName.isNotEmpty) 'cache_file_name': cacheFileName,
        if (preservedAiDraft) 'preserved_ai_draft': true,
        if (message.isNotEmpty) 'message': message,
      };
}

class _ImportOptions {
  final String sourceRoot;
  final String workspaceRoot;
  final bool dryRun;
  final bool recursive;

  const _ImportOptions({
    required this.sourceRoot,
    required this.workspaceRoot,
    required this.dryRun,
    required this.recursive,
  });

  factory _ImportOptions.parse(List<String> args) {
    final values = <String, String>{};
    final flags = <String>{};
    final positional = <String>[];
    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      if (!arg.startsWith('--')) {
        positional.add(arg);
        continue;
      }
      final equalIndex = arg.indexOf('=');
      if (equalIndex > 0) {
        values[arg.substring(2, equalIndex)] = arg.substring(equalIndex + 1);
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
    final sourceRoot = values['source-root'] ??
        values['source'] ??
        (positional.isEmpty ? '' : positional.first);
    if (sourceRoot.trim().isEmpty) {
      throw StateError('Pass --source-root <directory>.');
    }
    return _ImportOptions(
      sourceRoot: sourceRoot,
      workspaceRoot: values['workspace'] ?? _defaultWorkspaceRoot(),
      dryRun: flags.contains('dry-run'),
      recursive: flags.contains('recursive'),
    );
  }
}

Future<Script> _parseDirectory(Directory directory) async {
  final frames = <ScriptFrame>[];
  final sources = await _scriptFrameSources(directory);
  for (final source in sources) {
    final frame = await _parseFrameSource(source, frames.length + 1);
    if (frame != null) {
      frames.add(frame);
    }
  }
  final detectedSchema = _voteSchema(frames);
  final parseWarnings = frames.isEmpty
      ? const [
          'No prompt-bearing JSON or PNG script frames found in this directory.',
        ]
      : frames.expand((frame) => frame.warnings).toList(growable: false);
  return Script(
    id: _scriptIdForDirectory(directory),
    name: _directoryName(directory),
    rootPath: directory.path,
    frames: List.unmodifiable(frames),
    detectedSchema: detectedSchema,
    parseWarnings: parseWarnings,
    meta: {'frameCount': frames.length},
  );
}

String _scriptIdForDirectory(Directory directory) {
  final path = directory.absolute.path;
  final normalizedPath = path.replaceAll('\\', '/');
  final parts = normalizedPath
      .split('/')
      .where((part) => part.trim().isNotEmpty)
      .toList(growable: false);
  final label = parts.isEmpty ? 'script' : parts.last;
  return stableIdFromText(prefix: 'script', text: path, label: label);
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
        _fileName(left.path),
        _fileName(right.path),
      ));
  pngFiles.sort((left, right) => _naturalCompare(
        _fileName(left.path),
        _fileName(right.path),
      ));
  return _pairedFrameSources(jsonFiles: jsonFiles, pngFiles: pngFiles);
}

Future<ScriptFrame?> _parseFrameSource(
  _ScriptFrameSource source,
  int index,
) {
  return switch (source.kind) {
    _ScriptFrameSourceKind.json => _parseJsonFrame(source, index),
    _ScriptFrameSourceKind.png => _parsePngFrame(source, index),
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
) async {
  final file = source.file;
  try {
    final metadata = _parsePngMetadata(await file.readAsBytes());
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
  } catch (_) {
    return null;
  }
}

NaiMetadataParseResult _parsePngMetadata(Uint8List bytes) {
  final chunkMetadata = _extractPngTextChunks(bytes);
  if (chunkMetadata.isNotEmpty) {
    final parsed = NaiMetadataParser.parseMap(chunkMetadata);
    if (parsed.hasStructuredMetadata || _hasPromptMetadata(parsed)) {
      return parsed;
    }
  }
  throw const FormatException('No NovelAI metadata found in PNG.');
}

Map<String, dynamic> _extractPngTextChunks(Uint8List bytes) {
  final chunks = png_extract.extractChunks(bytes);
  final metadata = <String, dynamic>{};
  for (final chunk in chunks) {
    final name = chunk['name'];
    final dataValue = chunk['data'];
    final data = switch (dataValue) {
      Uint8List value => value,
      List<int> value => Uint8List.fromList(value),
      _ => null,
    };
    if (data == null) continue;
    switch (name) {
      case 'tEXt':
        final entry = _parseTextChunk(data);
        if (entry != null) metadata[entry.key] = entry.value;
        break;
      case 'iTXt':
        final entry = _parseInternationalTextChunk(data);
        if (entry != null) metadata[entry.key] = entry.value;
        break;
      case 'zTXt':
        final entry = _parseCompressedTextChunk(data);
        if (entry != null) metadata[entry.key] = entry.value;
        break;
    }
  }
  return metadata;
}

MapEntry<String, String>? _parseTextChunk(Uint8List data) {
  final separator = data.indexOf(0);
  if (separator <= 0) return null;
  return MapEntry(
    utf8.decode(data.sublist(0, separator), allowMalformed: true),
    utf8.decode(data.sublist(separator + 1), allowMalformed: true),
  );
}

MapEntry<String, String>? _parseCompressedTextChunk(Uint8List data) {
  final separator = data.indexOf(0);
  if (separator <= 0 || separator + 2 > data.length) return null;
  final compressionMethod = data[separator + 1];
  if (compressionMethod != 0) return null;
  final inflated = ZLibCodec().decode(data.sublist(separator + 2));
  return MapEntry(
    utf8.decode(data.sublist(0, separator), allowMalformed: true),
    utf8.decode(inflated, allowMalformed: true),
  );
}

MapEntry<String, String>? _parseInternationalTextChunk(Uint8List data) {
  final keywordEnd = data.indexOf(0);
  if (keywordEnd <= 0 || keywordEnd + 5 > data.length) return null;
  final keyword = utf8.decode(
    data.sublist(0, keywordEnd),
    allowMalformed: true,
  );
  var cursor = keywordEnd + 1;
  final compressionFlag = data[cursor++];
  final compressionMethod = data[cursor++];
  if (compressionFlag != 0 && compressionMethod != 0) return null;

  final languageEnd = data.indexOf(0, cursor);
  if (languageEnd < 0) return null;
  cursor = languageEnd + 1;
  final translatedEnd = data.indexOf(0, cursor);
  if (translatedEnd < 0) return null;
  cursor = translatedEnd + 1;

  final textBytes = data.sublist(cursor);
  final text = compressionFlag == 0
      ? utf8.decode(textBytes, allowMalformed: true)
      : utf8.decode(ZLibCodec().decode(textBytes), allowMalformed: true);
  return MapEntry(keyword, text);
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
    fileName: _fileName(file.path),
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
    fileName: _fileName(file.path),
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
    return hasInlineCharacter ? ScriptSchema.v4Partial : ScriptSchema.v4Slotted;
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
    if (byVotes != 0) return byVotes;
    return ranked.indexOf(a).compareTo(ranked.indexOf(b));
  });

  return votes[ranked.first] == 0 ? ScriptSchema.unknown : ranked.first;
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

Map<String, dynamic> _stringKeyMap(Map<dynamic, dynamic> map) {
  return map.map((key, value) => MapEntry(key.toString(), value));
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
          _sourceStem(_fileName(candidate.path)) ==
          _sourceStem(_fileName(json.path)),
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
        _fileName(left.file.path),
        _fileName(right.file.path),
      ));
  return List.unmodifiable(paired);
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
    for (final json in jsonFiles) _sourceStem(_fileName(json.path)),
  };
  final pngStems = {
    for (final png in pngFiles) _sourceStem(_fileName(png.path)),
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
    keepParseErrors: _legacyScriptFrameFilePattern.hasMatch(
      _fileName(json.path),
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
    final key = _sequenceKey(_fileName(json.path));
    if (key == null) continue;
    (jsonByKey[key] ??= []).add(json);
  }
  for (final png in pngFiles) {
    if (usedPng.contains(png)) continue;
    final key = _sequenceKey(_fileName(png.path));
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
  final lowerName = _fileName(file.path).toLowerCase();
  if (lowerName.endsWith('.json')) {
    return _ScriptFrameSourceKind.json;
  }
  if (lowerName.endsWith('.png')) {
    return _ScriptFrameSourceKind.png;
  }
  return null;
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

final _legacyScriptFrameFilePattern = RegExp(
  r'^(?:nai_|p)(\d+)\.json$',
  caseSensitive: false,
);

Future<List<Directory>> _candidateDirectories(
  Directory sourceRoot,
  bool recursive,
) async {
  final result = <Directory>[];
  if (await _hasFrameSourceFiles(sourceRoot)) {
    result.add(sourceRoot);
  }
  if (recursive) {
    await for (final entity in sourceRoot.list(recursive: true)) {
      if (entity is Directory && await _hasFrameSourceFiles(entity)) {
        result.add(entity);
      }
    }
  } else {
    await for (final entity in sourceRoot.list()) {
      if (entity is Directory) {
        result.add(entity);
      }
    }
  }
  result.sort((left, right) => _naturalCompare(left.path, right.path));
  return List.unmodifiable(result);
}

Future<bool> _hasFrameSourceFiles(Directory directory) async {
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File) continue;
    final lower = _fileName(entity.path).toLowerCase();
    if (lower.endsWith('.png') || lower.endsWith('.json')) {
      return true;
    }
  }
  return false;
}

RecastScriptCache _cacheForScript({
  required Script script,
  required String sourceFingerprint,
  required RecastScriptCache? existing,
  required RecastScriptCache? exactExisting,
}) {
  final preservedAi = exactExisting?.aiRoleExtraction.status ==
          ScriptAiRoleExtractionStatus.idle
      ? null
      : exactExisting;
  return RecastScriptCache(
    scriptId: script.id,
    scriptName: script.name,
    sourceRootPath: script.rootPath,
    sourceFingerprint: sourceFingerprint,
    updatedAt: DateTime.now().toUtc(),
    roleCandidates: existing?.roleCandidates ?? const [],
    mapping: existing?.mapping ?? RecastMapping.defaults(script.id),
    aiRoleExtraction:
        preservedAi?.aiRoleExtraction ?? const ScriptAiRoleExtraction(),
    aiRoleExtractionChunks: preservedAi?.aiRoleExtractionChunks ?? const [],
    aiRoleExtractionDraftCollapsed:
        preservedAi?.aiRoleExtractionDraftCollapsed ?? false,
    scriptBlockWords: existing?.scriptBlockWords ?? '',
    scriptSnapshot: script.toJson(),
  );
}

RecastScriptCache? _bestExactCacheForScript(
  Iterable<RecastScriptCache> caches, {
  required Script script,
  required String sourceFingerprint,
}) {
  return _bestCache([
    for (final cache in caches)
      if (_cacheBelongsToScript(cache, script) &&
          cache.sourceFingerprint == sourceFingerprint)
        cache,
  ]);
}

RecastScriptCache? _bestRelatedCacheForScript(
  Iterable<RecastScriptCache> caches, {
  required Script script,
}) {
  return _bestCache([
    for (final cache in caches)
      if (_cacheBelongsToScript(cache, script)) cache,
  ]);
}

RecastScriptCache? _bestCache(List<RecastScriptCache> caches) {
  if (caches.isEmpty) return null;
  caches.sort((left, right) {
    final byAi = _cacheAiDraftScore(right).compareTo(_cacheAiDraftScore(left));
    if (byAi != 0) return byAi;
    return right.updatedAt.compareTo(left.updatedAt);
  });
  return caches.first;
}

int _cacheAiDraftScore(RecastScriptCache cache) {
  final extraction = cache.aiRoleExtraction;
  if (extraction.status == ScriptAiRoleExtractionStatus.ready) {
    return 3000 + extraction.roles.length;
  }
  if (extraction.status == ScriptAiRoleExtractionStatus.failed) {
    return 1000;
  }
  if (cache.aiRoleExtractionChunks.isNotEmpty) {
    return 2000 + cache.aiRoleExtractionChunks.length;
  }
  return 0;
}

bool _cacheBelongsToScript(RecastScriptCache cache, Script script) {
  return cache.scriptId == script.id ||
      _normalizeScriptPath(cache.sourceRootPath) ==
          _normalizeScriptPath(script.rootPath);
}

String _sourceFingerprint(Script script) {
  final parts = [
    script.id,
    script.rootPath,
    for (final frame in script.frames)
      '${frame.index}:${frame.fileName}:${frame.sourcePath}:'
          '${_stableContentHash(frame.rawJson)}',
  ];
  return parts.join('|');
}

String _stableContentHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String _defaultWorkspaceRoot() {
  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.trim().isEmpty) {
    throw StateError('APPDATA is not set; pass --workspace explicitly.');
  }
  return [
    appData,
    'org.exception0x0194',
    'nai3_autodraw',
    'novel_studio',
  ].join(Platform.pathSeparator);
}

String _normalizeScriptPath(String path) {
  final normalized = path.trim().replaceAll('\\', '/');
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

String _directoryName(Directory directory) {
  final normalized = directory.path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty);
  return parts.isEmpty ? directory.path : parts.last;
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.split('/').last;
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
