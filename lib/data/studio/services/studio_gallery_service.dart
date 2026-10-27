import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/services/file_service.dart';
import 'package:novel_studio/data/studio/models/studio_gallery_record.dart';
import 'package:novel_studio/data/workspace/workspace_paths.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

typedef StudioGalleryResolvePicturePath = Future<String> Function(
  String fileName,
  String saveDir,
);

class StudioGalleryCreativeSummary {
  final int totalCount;
  final List<StudioGalleryRecord> recentRecords;

  const StudioGalleryCreativeSummary({
    required this.totalCount,
    required this.recentRecords,
  });
}

class StudioGalleryService {
  static final Map<String, Future<void>> _pendingRecordMutations = {};
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

  Future<List<StudioGalleryRecord>> loadRecastRecords() async {
    final file = _recordsFile();
    if (!await file.exists()) {
      return const [];
    }

    final records = await compute(_recastRecordsFromFile, file.path);
    return Future.wait(records.map(_resolveLegacyImagePath));
  }

  Future<List<StudioGalleryRecord>> loadCreativeRecords() async {
    final records = await loadRecords();
    return records
        .where((record) => record.provenance == null)
        .toList(growable: false);
  }

  Future<StudioGalleryCreativeSummary> loadCreativeRecordSummary({
    int recentLimit = 4,
  }) async {
    final file = _recordsFile();
    if (!await file.exists()) {
      return const StudioGalleryCreativeSummary(
        totalCount: 0,
        recentRecords: [],
      );
    }

    final payload = await compute(_creativeSummaryPayloadFromFile, {
      'path': file.path,
      'recentLimit': recentLimit,
    });
    final recentRecords = <StudioGalleryRecord>[];
    for (final json in payload.recentRecordJson) {
      recentRecords.add(
        await _resolveLegacyImagePath(StudioGalleryRecord.fromJson(json)),
      );
    }
    return StudioGalleryCreativeSummary(
      totalCount: payload.totalCount,
      recentRecords: List.unmodifiable(recentRecords),
    );
  }

  Future<StudioGalleryRecord> saveSnapshot({
    required PayloadConfig config,
    String? title,
    String? imagePath,
    String? info,
    Map<String, dynamic> additionalInfo = const {},
    DateTime? createdAt,
    String? id,
    StudioGalleryLineage? lineage,
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
      lineage: lineage,
    );
    await _prependRecord(record);
    return record;
  }

  Future<StudioGalleryRecord> saveOperationSnapshot({
    required PayloadConfig config,
    required StudioGalleryOperation operation,
    required String sourceRecordId,
    String? sourceImagePath,
    String? title,
    String? imagePath,
    String? info,
    Map<String, dynamic> parameters = const {},
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
      lineage: StudioGalleryLineage(
        operation: operation,
        sourceRecordId: sourceRecordId,
        sourceImagePath: sourceImagePath,
        parameters: parameters,
      ),
    );
    await _prependRecord(record);
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
    await _prependRecord(record);
    return record;
  }

  Future<void> saveRecords(List<StudioGalleryRecord> records) {
    return _mutateRecords(() => _saveRecordsNow(records));
  }

  /// Updates existing records without replacing unrelated or newer records.
  /// A deleted record is never resurrected from a stale organization preview.
  Future<void> mergeImagePaths(List<StudioGalleryRecord> updates) {
    final updatesById = {for (final record in updates) record.id: record};
    return _mutateRecords(() async {
      final current = await loadRecords();
      await _saveRecordsNow([
        for (final record in current)
          if (updatesById[record.id] case final update?)
            _mergeImagePaths(record, update)
          else
            record,
      ]);
    });
  }

  StudioGalleryRecord _mergeImagePaths(
    StudioGalleryRecord current,
    StudioGalleryRecord update,
  ) {
    final json = current.toJson();
    json['imagePath'] = update.imagePath;
    final provenance = current.provenance;
    final outputPath = update.provenance?.outputImagePath;
    if (provenance != null && outputPath != null) {
      final updatedProvenance = provenance.toJson()
        ..['outputImagePath'] = outputPath;
      json['provenance'] = updatedProvenance;
      final info = Map<String, dynamic>.from(current.additionalInfo);
      if (info.containsKey('provenance')) {
        info['provenance'] = updatedProvenance;
      }
      json['additionalInfo'] = info;
    }
    return StudioGalleryRecord.fromJson(json);
  }

  Future<void> _prependRecord(StudioGalleryRecord record) {
    return _mutateRecords(() async {
      final records = await loadRecords();
      await _saveRecordsNow([
        record,
        ...records.where((existing) => existing.id != record.id),
      ]);
    });
  }

  Future<void> _saveRecordsNow(List<StudioGalleryRecord> records) {
    return workspaceService.saveGalleryRecordData([
      for (final record in records) record.toJson(),
    ]);
  }

  Future<void> _mutateRecords(Future<void> Function() action) {
    final path = _recordsFile().absolute.path;
    final key = Platform.isWindows ? path.toLowerCase() : path;
    final previous = _pendingRecordMutations[key] ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then((_) => action());
    _pendingRecordMutations[key] = next;
    return next.whenComplete(() {
      if (identical(_pendingRecordMutations[key], next)) {
        _pendingRecordMutations.remove(key);
      }
    });
  }

  Future<void> removeRecord(
    String id, {
    bool deleteImageFile = false,
  }) {
    return _mutateRecords(() async {
      final records = await loadRecords();
      StudioGalleryRecord? removedRecord;
      final remainingRecords = <StudioGalleryRecord>[];
      for (final record in records) {
        if (record.id == id) {
          removedRecord ??= record;
        } else {
          remainingRecords.add(record);
        }
      }
      await _saveRecordsNow(remainingRecords);
      if (deleteImageFile) {
        await _deleteRecordImageFile(removedRecord);
      }
    });
  }

  void restoreToWorkbench(
    StudioGalleryRecord record,
    PayloadConfig target,
  ) {
    record.restoreTo(target);
  }

  Future<void> useRecordAsI2iSource(
    StudioGalleryRecord record,
    PayloadConfig target,
  ) async {
    final imagePath = record.imagePath?.trim();
    if (imagePath == null || imagePath.isEmpty) {
      throw StateError('Gallery record has no image path.');
    }

    final file = File(imagePath);
    if (!await file.exists()) {
      throw StateError('Gallery image file does not exist: $imagePath');
    }

    target.i2iConfig.setImage(await file.readAsBytes());
  }

  File _recordsFile() {
    final root = workspaceService.root;
    if (root == null) {
      throw StateError('No workspace is open.');
    }
    return File(_resolve(root, WorkspacePaths.galleryRecords));
  }

  Future<void> _deleteRecordImageFile(StudioGalleryRecord? record) async {
    final imagePath = record?.imagePath?.trim();
    if (imagePath == null || imagePath.isEmpty) return;

    final file = File(imagePath);
    if (await file.exists()) {
      await file.delete();
    }
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
        lineage: record.lineage,
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

_CreativeSummaryPayload _creativeSummaryPayloadFromFile(
  Map<String, Object?> request,
) {
  final path = request['path'] as String? ?? '';
  final recentLimit = request['recentLimit'] as int? ?? 4;
  final source = path.isEmpty ? '[]' : File(path).readAsStringSync();
  final decoded = jsonDecode(source);
  if (decoded is! List) {
    throw const FormatException('Gallery records must be a JSON array.');
  }

  var totalCount = 0;
  final recentRecordJson = <Map<String, dynamic>>[];
  for (final value in decoded) {
    final record = _jsonMap(value);
    if (record['provenance'] != null) {
      continue;
    }
    totalCount += 1;
    if (recentRecordJson.length < recentLimit) {
      recentRecordJson.add(record);
    }
  }

  return _CreativeSummaryPayload(
    totalCount: totalCount,
    recentRecordJson: recentRecordJson,
  );
}

List<StudioGalleryRecord> _recastRecordsFromFile(String path) {
  final source = path.isEmpty ? '[]' : File(path).readAsStringSync();
  final decoded = jsonDecode(source);
  if (decoded is! List) {
    throw const FormatException('Gallery records must be a JSON array.');
  }

  return [
    for (final value in decoded)
      if (value is Map)
        if (_hasRecastProvenance(value))
          StudioGalleryRecord.fromRecastSummaryJson(_jsonMap(value)),
  ];
}

bool _hasRecastProvenance(Map<dynamic, dynamic> value) {
  if (value['provenance'] != null) {
    return true;
  }
  final additionalInfo = value['additionalInfo'];
  return additionalInfo is Map && additionalInfo['provenance'] != null;
}

class _CreativeSummaryPayload {
  final int totalCount;
  final List<Map<String, dynamic>> recentRecordJson;

  const _CreativeSummaryPayload({
    required this.totalCount,
    required this.recentRecordJson,
  });
}
