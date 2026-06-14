import 'dart:io';

import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/services/script_recast_parser_service.dart';

Script rebindCachedScriptToImportDirectory(
  Script cachedScript,
  Directory importDirectory,
) {
  final filesByLeaf = _filesByLeaf(importDirectory);
  final currentRootPath = importDirectory.path;
  return Script(
    id: ScriptRecastParserService.scriptIdForDirectory(importDirectory),
    name: cachedScript.name,
    rootPath: currentRootPath,
    frames: [
      for (final frame in cachedScript.frames)
        _rebindFrame(
          frame,
          rootPath: currentRootPath,
          filesByLeaf: filesByLeaf,
        ),
    ],
    detectedSchema: cachedScript.detectedSchema,
    parseWarnings: cachedScript.parseWarnings,
    meta: cachedScript.meta,
  );
}

ScriptFrame _rebindFrame(
  ScriptFrame frame, {
  required String rootPath,
  required Map<String, File> filesByLeaf,
}) {
  final sourceLeaf = _firstNonEmpty([
    _pathLeaf(frame.sourcePath),
    frame.fileName,
  ]);
  final sourceFile = _fileForLeaf(filesByLeaf, sourceLeaf);
  final reboundSourcePath = sourceFile?.path ?? _joinPath(rootPath, sourceLeaf);

  final imageLeaf = _pathLeaf(frame.sourceImagePath);
  final imageFile =
      imageLeaf.isEmpty ? null : _fileForLeaf(filesByLeaf, imageLeaf);
  final sourceImageFile =
      _isImagePath(sourceFile?.path ?? '') ? sourceFile : null;
  final pairedImageFile = sourceLeaf.isEmpty
      ? null
      : _pairedImageForSource(filesByLeaf, sourceLeaf);
  final reboundImagePath =
      imageFile?.path ?? sourceImageFile?.path ?? pairedImageFile?.path ?? '';

  return ScriptFrame(
    index: frame.index,
    fileName: frame.fileName,
    sourcePath: reboundSourcePath,
    sourceImagePath: reboundImagePath,
    rawJson: frame.rawJson,
    parsed: frame.parsed,
    detectedSchema: frame.detectedSchema,
    parseStatus: frame.parseStatus,
    warnings: frame.warnings,
  );
}

Map<String, File> _filesByLeaf(Directory root) {
  if (!root.existsSync()) {
    return const {};
  }
  final files = root
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .toList()
    ..sort((left, right) {
      final byDepth = _pathDepth(left.path).compareTo(_pathDepth(right.path));
      if (byDepth != 0) return byDepth;
      return left.path.compareTo(right.path);
    });
  final result = <String, File>{};
  for (final file in files) {
    result.putIfAbsent(_fileKey(_pathLeaf(file.path)), () => file);
  }
  return Map.unmodifiable(result);
}

File? _fileForLeaf(Map<String, File> filesByLeaf, String leaf) {
  final key = _fileKey(leaf);
  if (key.isEmpty) {
    return null;
  }
  return filesByLeaf[key];
}

File? _pairedImageForSource(Map<String, File> filesByLeaf, String sourceLeaf) {
  final stem = _pathStem(sourceLeaf);
  if (stem.isEmpty) {
    return null;
  }
  return _fileForLeaf(filesByLeaf, '$stem.png');
}

String _firstNonEmpty(List<String> values) {
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '';
}

String _joinPath(String rootPath, String leaf) {
  final trimmedLeaf = leaf.trim();
  if (trimmedLeaf.isEmpty) {
    return '';
  }
  return '$rootPath${Platform.pathSeparator}$trimmedLeaf';
}

bool _isImagePath(String path) {
  final normalized = path.toLowerCase();
  return normalized.endsWith('.png') ||
      normalized.endsWith('.jpg') ||
      normalized.endsWith('.jpeg') ||
      normalized.endsWith('.webp');
}

String _pathLeaf(String path) {
  final segments = path
      .trim()
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty && segment != '.')
      .toList(growable: false);
  return segments.isEmpty ? '' : segments.last;
}

String _pathStem(String path) {
  final leaf = _pathLeaf(path);
  final dot = leaf.lastIndexOf('.');
  if (dot <= 0) {
    return leaf;
  }
  return leaf.substring(0, dot);
}

String _fileKey(String leaf) {
  return leaf.trim().toLowerCase();
}

int _pathDepth(String path) {
  return path
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .length;
}
