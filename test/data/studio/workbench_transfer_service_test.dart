import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/models/workbench_document.dart';
import 'package:nai_casrand/data/studio/services/workbench_transfer_service.dart';

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
  test('exportText emits the workbench document envelope', () {
    final text = WorkbenchTransferService().exportText(_payload('soft light'));
    final json = jsonDecode(text) as Map<String, dynamic>;

    expect(json['kind'], WorkbenchDocument.kind);
    expect(json.toString(), contains('soft light'));
  });

  test('decode accepts a workbench document', () {
    final service = WorkbenchTransferService();
    final text = service.exportText(_payload('rainy street'));

    final document = service.decode(text);

    expect(document.payload['override_prompt'], 'rainy street');
  });

  test('decode accepts legacy CasRand payload json', () {
    final service = WorkbenchTransferService();
    final text = jsonEncode(_payload('legacy prompt').toJson());

    final document = service.decode(text);

    expect(document.payload['override_prompt'], 'legacy prompt');
    expect(document.toJson()['kind'], WorkbenchDocument.kind);
  });
}
