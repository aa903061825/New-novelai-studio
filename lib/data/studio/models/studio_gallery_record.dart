import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/studio/models/workbench_document.dart';

class StudioGalleryRecord {
  static const currentVersion = 1;

  final String id;
  final DateTime createdAt;
  final String title;
  final String? imagePath;
  final String info;
  final Map<String, dynamic> additionalInfo;
  final WorkbenchDocument document;

  const StudioGalleryRecord({
    required this.id,
    required this.createdAt,
    required this.title,
    required this.imagePath,
    required this.info,
    required this.additionalInfo,
    required this.document,
  });

  factory StudioGalleryRecord.fromJson(Map<String, dynamic> json) {
    final documentJson = json['document'];
    if (documentJson is! Map) {
      throw const FormatException('Gallery record document is missing.');
    }

    return StudioGalleryRecord(
      id: _stringValue(json['id'], 'id'),
      createdAt: DateTime.parse(_stringValue(json['createdAt'], 'createdAt')),
      title: json['title'] as String? ?? '',
      imagePath: json['imagePath'] as String?,
      info: json['info'] as String? ?? '',
      additionalInfo: _dynamicMap(json['additionalInfo']),
      document: WorkbenchDocument.fromJson(
        documentJson.cast<String, dynamic>(),
      ),
    );
  }

  factory StudioGalleryRecord.fromPayloadConfig({
    required PayloadConfig config,
    required String id,
    required DateTime createdAt,
    String? title,
    String? imagePath,
    String? info,
    Map<String, dynamic> additionalInfo = const {},
  }) {
    final document = WorkbenchDocument.fromPayloadConfig(config);
    return StudioGalleryRecord(
      id: id,
      createdAt: createdAt,
      title: title ?? _defaultTitle(config),
      imagePath: imagePath,
      info: info ?? config.overridePrompt,
      additionalInfo: Map.unmodifiable(additionalInfo),
      document: document,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': currentVersion,
      'id': id,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'title': title,
      if (imagePath != null) 'imagePath': imagePath,
      'info': info,
      'additionalInfo': additionalInfo,
      'document': document.toJson(),
    };
  }

  void restoreTo(PayloadConfig target) {
    document.applyTo(target);
  }
}

String _defaultTitle(PayloadConfig config) {
  final prompt = config.overridePrompt.trim();
  if (prompt.isEmpty) {
    return '未命名记录';
  }
  if (prompt.length <= 32) {
    return prompt;
  }
  return '${prompt.substring(0, 32)}...';
}

String _stringValue(dynamic value, String field) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('Gallery record $field is missing.');
}

Map<String, dynamic> _dynamicMap(dynamic value) {
  if (value == null) {
    return const {};
  }
  if (value is! Map) {
    throw const FormatException('Gallery record metadata must be an object.');
  }
  return Map.unmodifiable(value.cast<String, dynamic>());
}
