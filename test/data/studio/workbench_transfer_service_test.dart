import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/i2i_config.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/studio/models/workbench_document.dart';
import 'package:novel_studio/data/studio/services/workbench_transfer_service.dart';

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

  test('decode accepts legacy payload json', () {
    final service = WorkbenchTransferService();
    final text = jsonEncode(_payload('legacy prompt').toJson());

    final document = service.decode(text);

    expect(document.payload['override_prompt'], 'legacy prompt');
    expect(document.toJson()['kind'], WorkbenchDocument.kind);
  });

  test('export and decode preserve image-to-image config in document payload',
      () {
    final payload = _payload('i2i prompt')
      ..i2iConfig = I2IConfig(
        imageB64: 'source-image',
        width: 640,
        height: 960,
        strength: 0.65,
        noise: 0.12,
        overridePromptEnabled: true,
        overridePrompt: 'i2i override',
      );
    final service = WorkbenchTransferService();

    final document = service.decode(service.exportText(payload));
    final i2iJson = document.payload['i2i_config'] as Map<String, dynamic>;

    expect(i2iJson['image_b64'], 'source-image');
    expect(i2iJson['width'], 640);
    expect(i2iJson['height'], 960);
    expect(i2iJson['strength'], 0.65);
    expect(i2iJson['noise'], 0.12);
    expect(i2iJson['override_prompt_enabled'], isTrue);
    expect(i2iJson['override_prompt'], 'i2i override');
  });
}
