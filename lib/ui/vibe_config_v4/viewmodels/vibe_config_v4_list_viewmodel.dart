import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/vibe_config_v4.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/ui/core/utils/flushbar.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

class VibeConfigV4ListViewmodel extends ChangeNotifier {
  PayloadConfig get payloadConfig => GetIt.I<PayloadConfig>();
  ConfigService get configService => GetIt.I<ConfigService>();

  List<VibeConfigV4> get vibeList => payloadConfig.vibeConfigListV4;

  Future<void> pickAndAddNewConfig(
    BuildContext context, {
    double initialReferenceStrength = 0.2,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'naiv4vibe', 'naiv4vibebundle'],
        allowMultiple: true,
        withData: true,
      );

      if (result == null) {
        if (!context.mounted) return;
        showInfoBar(context, 'File selection canceled or file is empty.');
        return;
      }

      final imported = <_ImportedVibe>[];
      for (final file in result.files) {
        final bytes = await _bytesFor(file);
        imported.addAll(
          await _configsFromBytes(
            fileName: file.name,
            extension: (file.extension ?? _extensionFromName(file.name))
                .toLowerCase()
                .trim(),
            bytes: bytes,
            initialReferenceStrength: initialReferenceStrength,
          ),
        );
      }

      _addScriptVibes(imported.map((entry) => entry.config));
      await _saveCache();
      if (!context.mounted) return;
      showInfoBar(context, _importMessage(imported));
    } catch (e) {
      if (!context.mounted) return;
      showErrorBar(context, 'Error adding vibe config: $e');
      if (kDebugMode) {
        print('Error picking/processing file: $e');
      }
    }
  }

  void removeConfig(VibeConfigV4 configToRemove) {
    final removed = vibeList.remove(configToRemove);
    if (removed) {
      notifyListeners();
      _saveCache();
    }
  }

  void removeConfigAtIndex(int index) {
    if (index >= 0 && index < vibeList.length) {
      vibeList.removeAt(index);
      notifyListeners();
      _saveCache();
    }
  }

  Future<void> handleVibeDropEvent(
    BuildContext context,
    PerformDropEvent event, {
    double initialReferenceStrength = 0.2,
  }) async {
    final item = event.session.items.first;
    final reader = item.dataReader;
    if (reader == null) return;

    reader.getFile(null, (file) async {
      final fileName = file.fileName ?? 'Imported file';
      try {
        final imported = await _configsFromBytes(
          fileName: fileName,
          extension: _extensionFromName(fileName).toLowerCase().trim(),
          bytes: await file.readAll(),
          initialReferenceStrength: initialReferenceStrength,
        );

        _addScriptVibes(imported.map((entry) => entry.config));
        await _saveCache();
        if (!context.mounted) return;
        showInfoBar(context, _importMessage(imported));
      } catch (e) {
        if (!context.mounted) return;
        showErrorBar(context, 'Error adding vibe config: $e');
        if (kDebugMode) {
          print('Error picking/processing file: $e');
        }
      }
    });
  }

  Future<List<_ImportedVibe>> _configsFromBytes({
    required String fileName,
    required String extension,
    required Uint8List bytes,
    required double initialReferenceStrength,
  }) async {
    if (extension == 'png') {
      final config = VibeConfigV4.fromPngBytes(
        fileName,
        bytes,
        initialReferenceStrength,
      );
      config.sourceImagePath = await configService.saveV4VibeSourceImage(
        fileName: fileName,
        bytes: bytes,
      );
      config.imageBytes = null;
      return [
        _ImportedVibe(
          config: config,
          message: 'Added V4 Vibe ${config.fileName} from PNG.',
        ),
      ];
    }

    if (extension == 'naiv4vibe') {
      final jsonData = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final config = VibeConfigV4.fromNaiV4VibeJson(
        fileName,
        jsonData,
        initialReferenceStrength,
      );
      return [
        _ImportedVibe(
          config: config,
          message: 'Added V4 Vibe ${config.fileName}.',
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
      final imported = <_ImportedVibe>[];
      for (final vibeJsonEntry in vibesListJson) {
        if (vibeJsonEntry is! Map<String, dynamic>) continue;
        final config = VibeConfigV4.fromNaiV4VibeJson(
          '$fileName#${imported.length}',
          vibeJsonEntry,
          initialReferenceStrength,
        );
        imported.add(
          _ImportedVibe(
            config: config,
            message: 'Added V4 Vibe ${config.fileName} from bundle.',
          ),
        );
      }
      if (imported.isNotEmpty) return imported;
      throw FormatException(
        "No valid vibes successfully imported from '$fileName'.",
      );
    }

    throw FormatException('Unsupported file type: $extension');
  }

  Future<Uint8List> _bytesFor(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes != null) return bytes;

    final path = file.path;
    if (path == null || path.trim().isEmpty) {
      throw FormatException('Vibe file ${file.name} has no readable data.');
    }
    return File(path).readAsBytes();
  }

  void _addScriptVibes(Iterable<VibeConfigV4> configs) {
    final next = payloadConfig.vibeConfigListV4.toList();
    for (final config in configs) {
      if (config.vibeB64.trim().isEmpty) continue;
      final existingIndex = next.indexWhere(
        (existing) => existing.vibeB64.trim() == config.vibeB64.trim(),
      );
      if (existingIndex >= 0) {
        next[existingIndex] = config;
      } else {
        next.add(config);
      }
    }
    payloadConfig.setScriptVibeConfigV4List(next);
    notifyListeners();
  }

  Future<void> _saveCache() {
    return configService.saveConfig(payloadConfig.toJson());
  }
}

String _importMessage(List<_ImportedVibe> imported) {
  if (imported.isEmpty) {
    return 'No readable V4 Vibe was imported.';
  }
  if (imported.length == 1) {
    return imported.single.message;
  }
  return 'Added ${imported.length} V4 Vibes.';
}

class _ImportedVibe {
  final VibeConfigV4 config;
  final String message;

  const _ImportedVibe({
    required this.config,
    required this.message,
  });
}

String _extensionFromName(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == fileName.length - 1) {
    return '';
  }
  return fileName.substring(dotIndex + 1);
}
