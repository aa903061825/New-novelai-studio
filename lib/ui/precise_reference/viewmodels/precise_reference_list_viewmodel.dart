import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/precise_reference_config.dart';
import 'package:novel_studio/ui/core/utils/flushbar.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

class PreciseReferenceListViewmodel extends ChangeNotifier {
  PayloadConfig get payloadConfig => GetIt.I<PayloadConfig>();
  List<PreciseReferenceConfig> get referenceList =>
      payloadConfig.preciseReferenceList;

  static const _allowedImageExtensions = [
    'png',
    'jpg',
    'jpeg',
    'webp',
    'bmp',
  ];

  Future<void> pickAndAddNewConfig(
    BuildContext context, {
    double initialStrength = 1.0,
    double initialFidelity = 1.0,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: true,
        withData: true,
        allowedExtensions: _allowedImageExtensions,
      );
      if (result == null) return;

      int addedCount = 0;
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        _addByBytes(
          fileName: file.name,
          imageBytes: bytes,
          initialStrength: initialStrength,
          initialFidelity: initialFidelity,
        );
        addedCount += 1;
      }

      if (addedCount == 0) return;
      notifyListeners();
      if (!context.mounted) return;
      showInfoBar(context, 'Added $addedCount precise reference image(s).');
    } catch (e) {
      if (!context.mounted) return;
      showErrorBar(context, 'Failed to add precise reference: $e');
    }
  }

  Future<void> handleDropEvent(
    BuildContext context,
    PerformDropEvent event, {
    double initialStrength = 1.0,
    double initialFidelity = 1.0,
  }) async {
    final item = event.session.items.first;
    final reader = item.dataReader;
    if (reader == null) return;

    reader.getFile(null, (file) async {
      try {
        final bytes = await file.readAll();
        if (bytes.isEmpty) return;
        final fileName = file.fileName ?? 'Dropped image';
        _addByBytes(
          fileName: fileName,
          imageBytes: bytes,
          initialStrength: initialStrength,
          initialFidelity: initialFidelity,
        );
        notifyListeners();
        if (!context.mounted) return;
        showInfoBar(context, 'Added $fileName as precise reference.');
      } catch (e) {
        if (!context.mounted) return;
        showErrorBar(context, 'Failed to import dropped image: $e');
      }
    });
  }

  void removeAt(int index) {
    if (index < 0 || index >= referenceList.length) return;
    referenceList.removeAt(index);
    notifyListeners();
  }

  void _addByBytes({
    required String fileName,
    required Uint8List imageBytes,
    required double initialStrength,
    required double initialFidelity,
  }) {
    referenceList.add(
      PreciseReferenceConfig.fromBytes(
        imageBytes,
        fileName,
        type: 'character&style',
        strength: initialStrength,
        fidelity: initialFidelity,
      ),
    );
  }
}
