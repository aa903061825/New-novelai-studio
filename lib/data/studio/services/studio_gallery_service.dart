import 'dart:convert';
import 'dart:io';

import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/studio/models/studio_gallery_record.dart';
import 'package:nai_casrand/data/workspace/workspace_paths.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

class StudioGalleryService {
  final WorkspaceService workspaceService;

  const StudioGalleryService({required this.workspaceService});

  Future<List<StudioGalleryRecord>> loadRecords() async {
    final file = _recordsFile();
    if (!await file.exists()) {
      return const [];
    }

    final source = await file.readAsString();
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException('Gallery records must be a JSON array.');
    }

    return decoded
        .map((json) => StudioGalleryRecord.fromJson(_jsonMap(json)))
        .toList(growable: false);
  }

  Future<StudioGalleryRecord> saveSnapshot({
    required PayloadConfig config,
    String? title,
    String? imagePath,
    String? info,
    Map<String, dynamic> additionalInfo = const {},
    DateTime? createdAt,
    String? id,
  }) async {
    final created = createdAt ?? DateTime.now().toUtc();
    final record = StudioGalleryRecord.fromPayloadConfig(
      config: config,
      id: id ?? 'gallery-${created.microsecondsSinceEpoch}',
      createdAt: created,
      title: title,
      imagePath: imagePath,
      info: info,
      additionalInfo: additionalInfo,
    );
    final records = await loadRecords();
    await saveRecords([record, ...records]);
    return record;
  }

  Future<void> saveRecords(List<StudioGalleryRecord> records) async {
    final file = _recordsFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      '${encoder.convert(records.map((record) => record.toJson()).toList())}\n',
    );
  }

  Future<void> removeRecord(String id) async {
    final records = await loadRecords();
    await saveRecords(
      records.where((record) => record.id != id).toList(growable: false),
    );
  }

  void restoreToWorkbench(
    StudioGalleryRecord record,
    PayloadConfig target,
  ) {
    record.restoreTo(target);
  }

  File _recordsFile() {
    final root = workspaceService.root;
    if (root == null) {
      throw StateError('No workspace is open.');
    }
    return File(_resolve(root, WorkspacePaths.galleryRecords));
  }

  String _resolve(Directory root, String relativePath) {
    final segments = relativePath.split('/');
    for (final segment in segments) {
      if (segment.isEmpty ||
          segment == '.' ||
          segment == '..' ||
          segment.contains('\\') ||
          segment.contains(Platform.pathSeparator)) {
        throw ArgumentError.value(
          relativePath,
          'relativePath',
          'Studio paths must stay under the internal data root.',
        );
      }
    }

    return [
      root.path,
      ...segments,
    ].join(Platform.pathSeparator);
  }
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
