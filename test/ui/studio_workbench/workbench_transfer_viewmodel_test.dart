import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/studio/services/workbench_transfer_service.dart';
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
}
