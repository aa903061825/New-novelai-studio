import 'dart:io';

import 'package:novel_studio/data/studio/tools/nai_metadata_parser.dart';

typedef NaiMetadataParserFn = NaiMetadataParseResult Function(dynamic payload);

class NaiMetadataBatchInput {
  final String fileName;
  final dynamic payload;

  const NaiMetadataBatchInput({
    required this.fileName,
    required this.payload,
  });
}

class NaiMetadataBatchFailure {
  final String fileName;
  final String error;

  const NaiMetadataBatchFailure({
    required this.fileName,
    required this.error,
  });
}

class NaiMetadataBatchResult {
  final List<String> fileNames;
  final String allSummaryContent;
  final String sceneSummaryContent;
  final Map<int, String> charSummaryContents;
  final String resolutionsContent;
  final String? coordsContent;
  final Map<String, String> outputFiles;
  final List<NaiMetadataBatchFailure> failures;

  const NaiMetadataBatchResult({
    required this.fileNames,
    required this.allSummaryContent,
    required this.sceneSummaryContent,
    required this.charSummaryContents,
    required this.resolutionsContent,
    required this.coordsContent,
    required this.outputFiles,
    required this.failures,
  });
}

class NaiMetadataBatchProcessor {
  const NaiMetadataBatchProcessor._();

  static NaiMetadataBatchResult processEntries(
    List<NaiMetadataBatchInput> entries, {
    NaiMetadataParserFn parser = NaiMetadataParser.parse,
  }) {
    final sorted = [...entries]..sort(
        (left, right) => _naturalCompare(left.fileName, right.fileName),
      );
    final rows = <_BatchRow>[];
    final failures = <NaiMetadataBatchFailure>[];

    for (final entry in sorted) {
      try {
        final parsed = parser(entry.payload);
        rows.add(_BatchRow.fromParsed(entry.fileName, parsed));
      } catch (error) {
        rows.add(_BatchRow.error(entry.fileName));
        failures.add(
          NaiMetadataBatchFailure(
            fileName: entry.fileName,
            error: error.toString(),
          ),
        );
      }
    }

    final allSummary = rows.map((row) => row.fullLine).join('\n');
    final sceneSummary = rows.map((row) => row.scene).join('\n');
    final resolutions = rows.map((row) => row.resolution).join('\n');
    final maxChars = rows.fold<int>(
      0,
      (max, row) =>
          row.charCaptions.length > max ? row.charCaptions.length : max,
    );
    final charSummaries = <int, String>{};
    for (var index = 0; index < maxChars; index++) {
      charSummaries[index + 1] = rows
          .map((row) =>
              index < row.charCaptions.length ? row.charCaptions[index] : ',')
          .join('\n');
    }

    final coordsLines = rows.map((row) => row.coordsLine).toList();
    final hasCoords = coordsLines.any((line) => line != ',' && line != 'ERR');
    final coordsContent = hasCoords ? coordsLines.join('\n') : null;

    final outputFiles = <String, String>{};
    outputFiles['_ALL_SUMMARY.txt'] = allSummary;
    outputFiles['_SUMMARY_SCENE.txt'] = sceneSummary;
    for (final entry in charSummaries.entries) {
      outputFiles['_SUMMARY_CHAR_${entry.key.toString().padLeft(2, '0')}.txt'] =
          entry.value;
    }
    outputFiles['_RESOLUTIONS.txt'] = resolutions;
    if (coordsContent != null) {
      outputFiles['_COORDS.txt'] = coordsContent;
    }

    return NaiMetadataBatchResult(
      fileNames: List.unmodifiable(sorted.map((entry) => entry.fileName)),
      allSummaryContent: allSummary,
      sceneSummaryContent: sceneSummary,
      charSummaryContents: Map.unmodifiable(charSummaries),
      resolutionsContent: resolutions,
      coordsContent: coordsContent,
      outputFiles: Map.unmodifiable(outputFiles),
      failures: List.unmodifiable(failures),
    );
  }

  static Future<NaiMetadataBatchResult> processDirectory(
    Directory directory, {
    NaiMetadataParserFn parser = NaiMetadataParser.parse,
  }) async {
    final entries = <NaiMetadataBatchInput>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      entries.add(
        NaiMetadataBatchInput(
          fileName: _baseName(entity.path),
          payload: await entity.readAsString(),
        ),
      );
    }

    final result = processEntries(entries, parser: parser);
    for (final entry in result.outputFiles.entries) {
      await File(
        '${directory.path}${Platform.pathSeparator}${entry.key}',
      ).writeAsString(entry.value);
    }
    return result;
  }

  static int _naturalCompare(String left, String right) {
    final leftParts = _naturalParts(left);
    final rightParts = _naturalParts(right);
    final count = leftParts.length < rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var index = 0; index < count; index++) {
      final leftPart = leftParts[index];
      final rightPart = rightParts[index];
      if (leftPart is int && rightPart is int) {
        final result = leftPart.compareTo(rightPart);
        if (result != 0) {
          return result;
        }
        continue;
      }
      final result = leftPart.toString().compareTo(rightPart.toString());
      if (result != 0) {
        return result;
      }
    }
    return leftParts.length.compareTo(rightParts.length);
  }

  static List<Object> _naturalParts(String value) {
    final result = <Object>[];
    for (final match in RegExp(r'\d+|\D+').allMatches(value.toLowerCase())) {
      final part = match.group(0)!;
      result.add(int.tryParse(part) ?? part);
    }
    return result;
  }

  static String _baseName(String path) {
    final slashIndex = path.lastIndexOf(Platform.pathSeparator);
    if (slashIndex == -1) {
      return path;
    }
    return path.substring(slashIndex + 1);
  }
}

class _BatchRow {
  final String fileName;
  final String scene;
  final List<String> charCaptions;
  final String resolution;
  final String coordsLine;
  final bool isError;

  const _BatchRow({
    required this.fileName,
    required this.scene,
    required this.charCaptions,
    required this.resolution,
    required this.coordsLine,
    this.isError = false,
  });

  factory _BatchRow.fromParsed(
    String fileName,
    NaiMetadataParseResult parsed,
  ) {
    final scene = _cleanSegment(parsed.prompt) ?? ',';
    final chars = parsed.charCaptions
        .map(_cleanSegment)
        .whereType<String>()
        .toList(growable: false);
    return _BatchRow(
      fileName: fileName,
      scene: scene,
      charCaptions: chars,
      resolution: parsed.resolution ?? 'Unknown',
      coordsLine: _coordsLine(parsed.coords),
    );
  }

  factory _BatchRow.error(String fileName) {
    return _BatchRow(
      fileName: fileName,
      scene: ',',
      charCaptions: const [],
      resolution: 'ERR',
      coordsLine: 'ERR',
      isError: true,
    );
  }

  String get fullLine {
    if (isError) {
      return 'ERR';
    }
    if (charCaptions.isEmpty) {
      return scene;
    }
    return [scene, ...charCaptions].join(', ');
  }

  static String? _cleanSegment(String? value) {
    final cleaned = value?.replaceAll('\n', ' ').replaceAll('\r', ' ').trim();
    if (cleaned == null || cleaned.isEmpty) {
      return null;
    }
    return cleaned;
  }

  static String _coordsLine(List<Map<String, num>> coords) {
    if (coords.isEmpty) {
      return ',';
    }
    return coords.map((coord) {
      return '${coord['x']},${coord['y']}';
    }).join(' | ');
  }
}
