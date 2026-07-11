import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/models/tokenizer_script.dart';

class RecastExhibitionFrame {
  final int index;
  final String fileName;
  final String sourcePath;
  final String sourceImagePath;
  final String prompt;
  final ScriptFrameParseStatus parseStatus;
  final Map<String, dynamic> generationParams;

  const RecastExhibitionFrame({
    required this.index,
    required this.fileName,
    required this.sourcePath,
    this.sourceImagePath = '',
    this.prompt = '',
    this.parseStatus = ScriptFrameParseStatus.parsed,
    this.generationParams = const {},
  });

  factory RecastExhibitionFrame.fromJson(Map<String, dynamic> json) {
    return RecastExhibitionFrame(
      index: (json['index'] as num?)?.toInt() ?? 0,
      fileName: json['fileName'] as String? ?? '',
      sourcePath: json['sourcePath'] as String? ?? '',
      sourceImagePath: json['sourceImagePath'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      parseStatus: _enumByNameOr(
        ScriptFrameParseStatus.values,
        json['parseStatus'] as String?,
        ScriptFrameParseStatus.parsed,
      ),
      generationParams:
          Map<String, dynamic>.from(json['generationParams'] as Map? ?? {}),
    );
  }

  factory RecastExhibitionFrame.fromScriptFrame(ScriptFrame frame) {
    return RecastExhibitionFrame(
      index: frame.index,
      fileName: frame.fileName,
      sourcePath: frame.sourcePath,
      sourceImagePath: frame.sourceImagePath,
      prompt: _promptFromRecastFrame(frame),
      parseStatus: frame.parseStatus,
      generationParams:
          Map<String, dynamic>.unmodifiable(frame.parsed.generationParams),
    );
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'fileName': fileName,
        'sourcePath': sourcePath,
        if (sourceImagePath.trim().isNotEmpty)
          'sourceImagePath': sourceImagePath,
        if (prompt.trim().isNotEmpty) 'prompt': prompt,
        'parseStatus': parseStatus.name,
        if (generationParams.isNotEmpty) 'generationParams': generationParams,
      };
}

class RecastExhibitionScript {
  final String scriptId;
  final String scriptName;
  final String sourceRootPath;
  final DateTime updatedAt;
  final ScriptSchema detectedSchema;
  final List<RecastExhibitionFrame> frames;
  final int? frameCount;
  final bool summaryOnly;
  final List<TokenizerScriptImageAttachment> imageAttachments;
  final List<String> categoryNames;
  final Map<String, String> versionLabels;
  final String? coverItemId;

  const RecastExhibitionScript({
    required this.scriptId,
    required this.scriptName,
    required this.sourceRootPath,
    required this.updatedAt,
    required this.detectedSchema,
    this.frames = const [],
    this.frameCount,
    this.summaryOnly = false,
    this.imageAttachments = const [],
    this.categoryNames = const [],
    this.versionLabels = const {},
    this.coverItemId,
  });

  int get displayFrameCount => frameCount ?? frames.length;

  RecastExhibitionScript copyWith({
    String? scriptId,
    String? scriptName,
    String? sourceRootPath,
    DateTime? updatedAt,
    ScriptSchema? detectedSchema,
    List<RecastExhibitionFrame>? frames,
    int? frameCount,
    bool? summaryOnly,
    List<TokenizerScriptImageAttachment>? imageAttachments,
    List<String>? categoryNames,
    Map<String, String>? versionLabels,
    String? coverItemId,
  }) {
    return RecastExhibitionScript(
      scriptId: scriptId ?? this.scriptId,
      scriptName: scriptName ?? this.scriptName,
      sourceRootPath: sourceRootPath ?? this.sourceRootPath,
      updatedAt: updatedAt ?? this.updatedAt,
      detectedSchema: detectedSchema ?? this.detectedSchema,
      frames: frames ?? this.frames,
      frameCount: frameCount ?? this.frameCount,
      summaryOnly: summaryOnly ?? this.summaryOnly,
      imageAttachments: imageAttachments ?? this.imageAttachments,
      categoryNames: categoryNames ?? this.categoryNames,
      versionLabels: versionLabels ?? this.versionLabels,
      coverItemId: coverItemId ?? this.coverItemId,
    );
  }

  bool get isImageOnly {
    if (frames.isEmpty) return false;
    return frames.every((frame) => _isImagePath(frame.sourcePath));
  }

  factory RecastExhibitionScript.fromJson(Map<String, dynamic> json) {
    return RecastExhibitionScript(
      scriptId: json['scriptId'] as String? ?? '',
      scriptName: json['scriptName'] as String? ?? '',
      sourceRootPath: json['sourceRootPath'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      detectedSchema: _enumByNameOr(
        ScriptSchema.values,
        json['detectedSchema'] as String?,
        ScriptSchema.unknown,
      ),
      frames: [
        for (final value in json['frames'] as List? ?? const [])
          if (value is Map)
            RecastExhibitionFrame.fromJson(value.cast<String, dynamic>()),
      ],
      frameCount: (json['frameCount'] as num?)?.toInt(),
      summaryOnly: json['summaryOnly'] == true,
      imageAttachments: [
        for (final value in json['imageAttachments'] as List? ?? const [])
          if (value is Map)
            TokenizerScriptImageAttachment.fromJson(
              value.cast<String, dynamic>(),
            ),
      ],
      categoryNames: [
        for (final value in json['categoryNames'] as List? ?? const [])
          if (value.toString().trim().isNotEmpty) value.toString(),
      ],
      versionLabels: {
        for (final entry in (json['versionLabels'] as Map? ?? const {}).entries)
          if (entry.key.toString().trim().isNotEmpty &&
              entry.value.toString().trim().isNotEmpty)
            entry.key.toString(): entry.value.toString(),
      },
      coverItemId: _nonEmptyString(json['coverItemId']),
    );
  }

  static RecastExhibitionScript? tryFromCache(RecastScriptCache cache) {
    if (cache.scriptSnapshot.isEmpty) {
      return null;
    }
    try {
      final script = Script.fromJson(cache.scriptSnapshot);
      final scriptId = _firstNonEmpty([script.id, cache.scriptId]) ?? '';
      final sourceRootPath =
          _firstNonEmpty([script.rootPath, cache.sourceRootPath]) ?? '';
      return RecastExhibitionScript(
        scriptId: scriptId,
        scriptName: _firstNonEmpty([script.name, cache.scriptName]) ?? '',
        sourceRootPath: sourceRootPath,
        updatedAt: cache.updatedAt,
        detectedSchema: script.detectedSchema,
        frames: [
          for (final frame in script.frames)
            RecastExhibitionFrame.fromScriptFrame(frame),
        ],
        frameCount: script.frames.length,
        imageAttachments: _legacyImageAttachmentsFromRecastScript(script),
        categoryNames: _normalizedCategoryNames([
          ...cache.exhibitionCategoryNames,
          ..._legacyCategoryNamesFromRecastScript(script),
        ]),
        versionLabels: _legacyVersionLabelsFromRecastScript(script),
        coverItemId: _legacyCoverItemIdFromRecastScript(script),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'scriptId': scriptId,
        'scriptName': scriptName,
        'sourceRootPath': sourceRootPath,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'detectedSchema': detectedSchema.name,
        'frames': frames.map((frame) => frame.toJson()).toList(),
        if (frameCount != null && frameCount != frames.length)
          'frameCount': frameCount,
        if (summaryOnly) 'summaryOnly': true,
        if (imageAttachments.isNotEmpty)
          'imageAttachments': imageAttachments
              .map((attachment) => attachment.toJson())
              .toList(),
        if (categoryNames.isNotEmpty) 'categoryNames': categoryNames,
        if (versionLabels.isNotEmpty) 'versionLabels': versionLabels,
        if (coverItemId?.trim().isNotEmpty == true)
          'coverItemId': coverItemId!.trim(),
      };
}

String _promptFromRecastFrame(ScriptFrame frame) {
  final rows = [
    if (frame.parsed.baseCaption.trim().isNotEmpty)
      frame.parsed.baseCaption.trim(),
    for (final caption in frame.parsed.charCaptions)
      if (caption.trim().isNotEmpty) caption.trim(),
  ];
  return rows.join(', ');
}

List<String> _legacyCategoryNamesFromRecastScript(Script script) {
  final raw = script.meta['legacyCategoryNames'];
  if (raw is! List) {
    return const [];
  }
  return _normalizedCategoryNames(raw);
}

List<String> _normalizedCategoryNames(Iterable<dynamic> values) {
  final namesByKey = <String, String>{};
  for (final value in values) {
    final normalized = value.toString().trim();
    if (normalized.isEmpty) continue;
    namesByKey.putIfAbsent(normalized.toLowerCase(), () => normalized);
  }
  return List.unmodifiable(namesByKey.values);
}

Map<String, String> _legacyVersionLabelsFromRecastScript(Script script) {
  final raw = script.meta['legacyExhibitionVersionLabels'];
  if (raw is! Map) {
    return const {};
  }
  return {
    for (final entry in raw.entries)
      if (entry.key.toString().trim().isNotEmpty &&
          entry.value.toString().trim().isNotEmpty)
        entry.key.toString(): entry.value.toString(),
  };
}

String? _legacyCoverItemIdFromRecastScript(Script script) {
  return _nonEmptyString(script.meta['legacyExhibitionCoverItemId']);
}

List<TokenizerScriptImageAttachment> _legacyImageAttachmentsFromRecastScript(
  Script script,
) {
  final raw = script.meta['legacyImageAttachments'];
  if (raw is! List) {
    return const [];
  }
  final attachments = <TokenizerScriptImageAttachment>[];
  for (final value in raw) {
    if (value is! Map) {
      continue;
    }
    try {
      attachments.add(
        TokenizerScriptImageAttachment.fromJson(value.cast<String, dynamic>()),
      );
    } catch (_) {
      // Ignore malformed legacy attachment records.
    }
  }
  return List.unmodifiable(attachments);
}

bool _isImagePath(String path) {
  final lower = path.toLowerCase();
  return const ['.png', '.jpg', '.jpeg', '.webp'].any(lower.endsWith);
}

String? _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

T _enumByNameOr<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  return fallback;
}
