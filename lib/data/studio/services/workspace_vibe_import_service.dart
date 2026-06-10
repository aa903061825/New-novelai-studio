import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/vibe_config_v4.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';

class WorkspaceVibeImportService {
  final PayloadConfig payloadConfig;
  final ConfigService? configService;

  const WorkspaceVibeImportService({
    required this.payloadConfig,
    this.configService,
  });

  Future<List<WorkspaceVibeReference>> pickAndImport({
    double initialReferenceStrength = 0.2,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'naiv4vibe', 'naiv4vibebundle'],
      allowMultiple: true,
      withData: false,
    );
    if (result == null) {
      return const [];
    }

    final importedConfigs = <VibeConfigV4>[];
    for (final file in result.files) {
      final configs = await _configsFromFile(
        file,
        initialReferenceStrength: initialReferenceStrength,
      );
      importedConfigs.addAll(
        configs.where((config) => config.vibeB64.trim().isNotEmpty),
      );
    }
    if (importedConfigs.isEmpty) {
      return const [];
    }

    for (final config in importedConfigs) {
      await _persistSourceImage(config);
    }
    final nextConfigs = payloadConfig.vibeConfigListV4.toList();
    final importedRefs = <WorkspaceVibeReference>[];
    for (final config in importedConfigs) {
      final existingIndex = nextConfigs.indexWhere(
        (existing) => existing.vibeB64.trim() == config.vibeB64.trim(),
      );
      if (existingIndex >= 0) {
        importedRefs
            .add(_referenceFor(existingIndex, nextConfigs[existingIndex]));
        continue;
      }
      nextConfigs.add(config);
      importedRefs.add(_referenceFor(nextConfigs.length - 1, config));
    }

    payloadConfig.setScriptVibeConfigV4List(nextConfigs);
    await configService?.saveConfig(payloadConfig.toJson());
    return importedRefs;
  }

  Future<List<VibeConfigV4>> _configsFromFile(
    PlatformFile file, {
    required double initialReferenceStrength,
  }) async {
    final fileName = file.name;
    final extension =
        (file.extension ?? _extensionFromName(fileName)).toLowerCase().trim();
    final bytes = await _bytesFor(file);
    return compute(
      _parseVibeConfigsFromBytes,
      _VibeConfigParseRequest(
        fileName: fileName,
        extension: extension,
        bytes: bytes,
        initialReferenceStrength: initialReferenceStrength,
      ),
      debugLabel: 'parse workspace vibe',
    );
  }

  Future<Uint8List> _bytesFor(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes != null) {
      return bytes;
    }
    final path = file.path;
    if (path == null || path.trim().isEmpty) {
      throw FormatException('Vibe file ${file.name} has no readable data.');
    }
    return File(path).readAsBytes();
  }

  Future<void> _persistSourceImage(VibeConfigV4 config) async {
    final bytes = config.imageBytes;
    if (bytes == null ||
        config.sourceImagePath != null ||
        configService == null) {
      return;
    }
    config.sourceImagePath = await configService!.saveV4VibeSourceImage(
      fileName: config.fileName,
      bytes: bytes,
    );
    config.imageBytes = null;
  }
}

class _VibeConfigParseRequest {
  final String fileName;
  final String extension;
  final Uint8List bytes;
  final double initialReferenceStrength;

  const _VibeConfigParseRequest({
    required this.fileName,
    required this.extension,
    required this.bytes,
    required this.initialReferenceStrength,
  });
}

List<VibeConfigV4> _parseVibeConfigsFromBytes(
  _VibeConfigParseRequest request,
) {
  final fileName = request.fileName;
  final extension = request.extension;
  final bytes = request.bytes;
  final initialReferenceStrength = request.initialReferenceStrength;

  if (extension == 'png') {
    return [
      VibeConfigV4.fromPngBytes(
        fileName,
        bytes,
        initialReferenceStrength,
      ),
    ];
  }
  if (extension == 'naiv4vibe') {
    final jsonData = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return [
      VibeConfigV4.fromNaiV4VibeJson(
        fileName,
        jsonData,
        initialReferenceStrength,
      ),
    ];
  }
  if (extension == 'naiv4vibebundle') {
    final bundleJsonData =
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final vibesListJson = bundleJsonData['vibes'] as List<dynamic>?;
    if (vibesListJson == null || vibesListJson.isEmpty) {
      throw const FormatException(
        "No vibes found or 'vibes' array is missing in .naiv4vibebundle file.",
      );
    }
    final vibes = <VibeConfigV4>[];
    for (final vibeJsonEntry in vibesListJson) {
      if (vibeJsonEntry is! Map<String, dynamic>) {
        continue;
      }
      vibes.add(
        VibeConfigV4.fromNaiV4VibeJson(
          '$fileName#${vibes.length}',
          vibeJsonEntry,
          initialReferenceStrength,
        ),
      );
    }
    return vibes;
  }

  throw FormatException('Unsupported Vibe file type: $extension');
}

WorkspaceVibeReference workspaceVibeReferenceForConfig(
  int index,
  VibeConfigV4 vibe,
) {
  return _referenceFor(index, vibe);
}

WorkspaceVibeReference _referenceFor(int index, VibeConfigV4 vibe) {
  return WorkspaceVibeReference(
    id: 'v4-vibe-$index-${_stableVibeId(vibe.fileName)}',
    name: vibe.fileName.trim().isEmpty ? 'Vibe ${index + 1}' : vibe.fileName,
    vibeB64: vibe.vibeB64,
    referenceStrength: vibe.referenceStrength,
  );
}

String _extensionFromName(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == fileName.length - 1) {
    return '';
  }
  return fileName.substring(dotIndex + 1);
}

String _stableVibeId(String value) {
  final slug = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'vibe' : slug;
}
