import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/services/file_service.dart';
import 'package:nai_casrand/data/studio/services/workbench_transfer_service.dart';
import 'package:nai_casrand/ui/core/utils/flushbar.dart';

class WorkbenchTransferViewModel extends ChangeNotifier {
  final PayloadConfig payloadConfig;
  final WorkbenchTransferService transferService;

  WorkbenchTransferViewModel({
    required this.payloadConfig,
    required this.transferService,
  });

  String exportText() => transferService.exportText(payloadConfig);

  void importText(String text) {
    transferService.importText(payloadConfig, text);
    notifyListeners();
  }

  Future<void> importFromFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null) return;
    try {
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        throw const FormatException('Selected workbench file is empty.');
      }
      importText(utf8.decode(bytes));
      if (!context.mounted) return;
      showInfoBar(context, context.tr('workbench_import_succeeded'));
    } catch (error) {
      if (!context.mounted) return;
      showErrorBar(
        context,
        '${context.tr('workbench_import_failed')}: $error',
      );
    }
  }

  Future<void> exportToFile() {
    final name =
        'novel-studio-workbench-${FileService().generateRandomString()}.json';
    return FileService().saveStringToFile(exportText(), name);
  }
}
