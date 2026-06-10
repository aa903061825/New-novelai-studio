import 'dart:convert';
import 'dart:io';

import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/services/file_service.dart';
import 'package:nai_casrand/data/studio/models/studio_gallery_record.dart';
import 'package:nai_casrand/data/workspace/workspace_paths.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

typedef StudioGalleryResolvePicturePath = Future<String> Function(
  String fileName,
  String saveDir,
);

class StudioGalleryService {
  final WorkspaceService workspaceService;
  final StudioGalleryResolvePicturePath? resolvePictureSavePath;

  const StudioGalleryService({
    required this.workspaceService,
    this.resolvePictureSavePath,
  });

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

    final records = decoded
        .map((json) => StudioGalleryRecord.fromJson(_jsonMap(json)))
        .toList(growable: false);
    return Future.wait(records.map(_resolveLegacyImagePath));
  }

  Future<List<StudioGalleryRecord>> loadCreativeRecords() async {
    final records = await loadRecords();
    return records
        .where((record) => record.provenance == null)
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

  Future<StudioGalleryRecord> saveRecastFrameSnapshot({
    required Map<String, dynamic> payload,
    required String title,
    required String imagePath,
    required String info,
    required StudioRecastProvenance provenance,
    Map<String, dynamic> additionalInfo = const {},
    DateTime? createdAt,
    String? id,
  }) async {
    final created = createdAt ?? DateTime.now().toUtc();
    final record = StudioGalleryRecord.fromRecastPayload(
      payload: payload,
      id: id ?? 'gallery-${created.microsecondsSinceEpoch}',
      createdAt: created,
      title: title,
      imagePath: imagePath,
      info: info,
      provenance: provenance,
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

  Future<StudioGalleryRecord> _resolveLegacyImagePath(
    StudioGalleryRecord record,
  ) async {
    final imagePath = record.imagePath?.trim();
    if (imagePath == null ||
        imagePath.isEmpty ||
        _looksLikeAbsolutePath(imagePath)) {
      return record;
    }

    try {
      final resolver =
          resolvePictureSavePath ?? FileService().resolvePictureSavePath;
      final resolved = (await resolver(imagePath, '')).trim();
      if (resolved.isEmpty || resolved == imagePath) {
        return record;
      }
      if (!await File(resolved).exists()) {
        return record;
      }
      return StudioGalleryRecord(
        id: record.id,
        createdAt: record.createdAt,
        title: record.title,
        imagePath: resolved,
        info: record.info,
        additionalInfo: record.additionalInfo,
        provenance: record.provenance,
        document: record.document,
      );
    } catch (_) {
      return record;
    }
  }
}

bool _looksLikeAbsolutePath(String path) {
  final trimmed = path.trim();
  return File(trimmed).isAbsolute ||
      RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(trimmed) ||
      trimmed.startsWith(r'\\') ||
      trimmed.startsWith('//');
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
