import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/studio/services/workbench_metadata_import_service.dart';
import 'package:novel_studio/data/studio/services/workbench_transfer_service.dart';
import 'package:novel_studio/data/studio/tools/nai_metadata_parser.dart';
import 'package:novel_studio/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';

PayloadConfig _payload(String prompt) {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: [prompt], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({'api_key': 'pst-current'}),
    overridePrompt: prompt,
    useOverridePrompt: true,
    useCharacterPromptWithOverride: false,
  );
}

void main() {
  test('importText updates payload and notifies listeners', () {
    final target = _payload('current');
    final text = WorkbenchTransferService().exportText(_payload('imported'));
    final viewModel = WorkbenchTransferViewModel(
      payloadConfig: target,
      transferService: WorkbenchTransferService(),
    );
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    viewModel.importText(text);

    expect(target.overridePrompt, 'imported');
    expect(notifications, 1);
  });

  test('exportText delegates to transfer service', () {
    final viewModel = WorkbenchTransferViewModel(
      payloadConfig: _payload('export me'),
      transferService: WorkbenchTransferService(),
    );

    expect(viewModel.exportText(), contains('export me'));
  });

  test('importFile parses from path before byte fallback', () async {
    final directory = await Directory.systemTemp.createTemp(
      'workbench-transfer-file-import-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}/metadata.png');
    await file.writeAsBytes(const [1, 2, 3]);
    final target = _payload('current');
    final metadataService = _PathOnlyMetadataImportService();
    final viewModel = WorkbenchTransferViewModel(
      payloadConfig: target,
      transferService: WorkbenchTransferService(),
      metadataImportService: metadataService,
    );
    var notifications = 0;
    viewModel.addListener(() => notifications += 1);
    await viewModel.importFile(
      _NoopBuildContext(),
      file,
      showFeedback: false,
    );

    expect(metadataService.parsedFile?.path, file.path);
    expect(metadataService.importBytesCallCount, 0);
    expect(target.overridePrompt, 'file prompt');
    expect(target.useOverridePrompt, isTrue);
    expect(notifications, 1);
  });
}

class _NoopBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PathOnlyMetadataImportService extends WorkbenchMetadataImportService {
  File? parsedFile;
  int importBytesCallCount = 0;

  @override
  Future<NaiMetadataParseResult> parseFile(File file) async {
    parsedFile = file;
    return const NaiMetadataParseResult(
      prompt: 'file prompt',
      source: null,
      negativePrompt: null,
      rawContent: '',
      parameters: {},
      width: null,
      height: null,
      charCaptions: [],
      negativeCharCaptions: [],
      coords: [],
      hasStructuredMetadata: true,
    );
  }

  @override
  Future<WorkbenchMetadataImportSummary> importBytes(
    PayloadConfig target,
    String fileName,
    Uint8List bytes,
  ) async {
    importBytesCallCount += 1;
    throw StateError('Byte import should not be used for file import.');
  }
}
