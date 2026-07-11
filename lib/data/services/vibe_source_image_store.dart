import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:novel_studio/data/models/vibe_config_v4.dart';
import 'package:uuid/uuid.dart';

class VibeSourceImageStore {
  final Directory rootDirectory;

  const VibeSourceImageStore({
    required this.rootDirectory,
  });

  Future<String> savePng({
    required String configUuid,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final assetDir = Directory(
      '${rootDirectory.path}${Platform.pathSeparator}vibe-assets'
      '${Platform.pathSeparator}${_safeSegment(configUuid)}',
    );
    await assetDir.create(recursive: true);

    final safeName = _safeStem(fileName);
    final id = const Uuid().v4();
    final target = File(
      '${assetDir.path}${Platform.pathSeparator}$safeName-$id.png',
    );
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  Future<bool> externalizeV4Vibes({
    required String configUuid,
    required Iterable<VibeConfigV4> vibes,
  }) async {
    var changed = false;
    for (final vibe in vibes) {
      final bytes = vibe.imageBytes ?? _decodeLegacyImage(vibe.legacyImageB64);
      if (bytes == null ||
          vibe.sourceImagePath != null && vibe.sourceImagePath!.isNotEmpty) {
        continue;
      }
      vibe.sourceImagePath = await savePng(
        configUuid: configUuid,
        fileName: vibe.fileName,
        bytes: bytes,
      );
      vibe.imageBytes = null;
      vibe.legacyImageB64 = null;
      changed = true;
    }
    return changed;
  }

  Uint8List? _decodeLegacyImage(String? imageB64) {
    final trimmed = imageB64?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    try {
      return base64Decode(trimmed);
    } catch (_) {
      return null;
    }
  }

  String _safeSegment(String value) {
    final safe = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return safe.isEmpty ? 'current' : safe;
  }

  String _safeStem(String value) {
    final withoutExtension = value.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final safe = withoutExtension
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return safe.isEmpty ? 'vibe-source' : safe;
  }
}
