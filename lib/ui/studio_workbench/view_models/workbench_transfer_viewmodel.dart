import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/services/file_service.dart';
import 'package:novel_studio/data/studio/services/studio_workbench_asset_service.dart';
import 'package:novel_studio/data/studio/services/workbench_metadata_import_service.dart';
import 'package:novel_studio/data/studio/services/workbench_transfer_service.dart';
import 'package:novel_studio/ui/core/utils/flushbar.dart';

class WorkbenchTransferViewModel extends ChangeNotifier {
  final PayloadConfig payloadConfig;
  final WorkbenchTransferService transferService;
  final WorkbenchMetadataImportService metadataImportService;

  WorkbenchTransferViewModel({
    required this.payloadConfig,
    required this.transferService,
    WorkbenchMetadataImportService? metadataImportService,
  }) : metadataImportService =
            metadataImportService ?? WorkbenchMetadataImportService();

  String exportText() => transferService.exportText(payloadConfig);

  void importText(String text) {
    transferService.importText(payloadConfig, text);
    notifyListeners();
  }

  Future<void> importFromFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'png'],
      withData: true,
    );
    if (result == null) return;
    if (!context.mounted) return;
    try {
      final file = result.files.single;
      final path = file.path?.trim();
      if (path != null && path.isNotEmpty) {
        await importFile(context, File(path));
        return;
      }
      final bytes = file.bytes;
      if (bytes == null) {
        throw const FormatException('Selected import file is empty.');
      }
      await importBytes(context, file.name, bytes);
    } catch (error) {
      if (!context.mounted) return;
      showErrorBar(
        context,
        '${context.tr('workbench_import_failed')}: $error',
      );
    }
  }

  Future<void> importFile(
    BuildContext context,
    File file, {
    bool showFeedback = true,
  }) async {
    try {
      final fileName = _fileName(file);
      final lowerName = fileName.toLowerCase();
      if (lowerName.endsWith('.json')) {
        try {
          importText(await file.readAsString());
          _refreshWorkbenchAssetService();
          if (!showFeedback || !context.mounted) return;
          showInfoBar(context, context.tr('workbench_import_succeeded'));
          return;
        } on FormatException {
          // Fall through: NovelAI metadata JSON is also JSON, but not a
          // workbench transfer document.
        }
      }

      final parsed = await metadataImportService.parseFile(file);
      final summary = metadataImportService.applyParsed(
        payloadConfig,
        fileName,
        parsed,
      );
      _refreshWorkbenchAssetService();
      notifyListeners();
      if (!showFeedback || !context.mounted) return;
      showInfoBar(
        context,
        '已导入 ${summary.fileName}，${summary.fieldsLoaded} 个参数，${summary.charactersLoaded} 个角色',
      );
    } catch (error) {
      if (!showFeedback) rethrow;
      if (!context.mounted) return;
      showErrorBar(
        context,
        '${context.tr('workbench_import_failed')}: $error',
      );
    }
  }

  Future<void> importBytes(
    BuildContext context,
    String fileName,
    Uint8List bytes,
  ) async {
    try {
      final lowerName = fileName.toLowerCase();
      if (lowerName.endsWith('.json')) {
        try {
          importText(utf8.decode(bytes));
          _refreshWorkbenchAssetService();
          if (!context.mounted) return;
          showInfoBar(context, context.tr('workbench_import_succeeded'));
          return;
        } on FormatException {
          // Fall through: NovelAI metadata JSON is also JSON, but not a
          // workbench transfer document.
        }
      }

      final summary = await metadataImportService.importBytes(
        payloadConfig,
        fileName,
        bytes,
      );
      _refreshWorkbenchAssetService();
      notifyListeners();
      if (!context.mounted) return;
      showInfoBar(
        context,
        '已导入 ${summary.fileName}：${summary.fieldsLoaded} 个参数，${summary.charactersLoaded} 个角色',
      );
    } catch (error) {
      if (!context.mounted) return;
      showErrorBar(
        context,
        '${context.tr('workbench_import_failed')}: $error',
      );
    }
  }

  Future<void> exportToFile() async {
    final name =
        'novel-studio-workbench-${FileService().generateRandomString()}.json';
    await FileService().saveStringToFile(exportText(), name);
  }

  void _refreshWorkbenchAssetService() {
    if (!GetIt.I.isRegistered<StudioWorkbenchAssetService>()) return;
    GetIt.I<StudioWorkbenchAssetService>().refreshFromPayload();
  }

  String _fileName(File file) {
    final segments = file.uri.pathSegments;
    if (segments.isEmpty) return file.path;
    return Uri.decodeComponent(segments.last);
  }
}
