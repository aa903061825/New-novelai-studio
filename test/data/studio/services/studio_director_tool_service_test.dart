import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/studio/models/studio_director_tool.dart';
import 'package:novel_studio/data/studio/services/studio_director_tool_service.dart';

PayloadConfig _payloadConfig() {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const ['unused'], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson(const {
      'api_key': 'pst-token',
      'proxy': '127.0.0.1:7890',
    }),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

void main() {
  group('StudioDirectorToolService', () {
    test('builds augment-image requests for basic Director Tools', () {
      final request = const StudioDirectorToolService().buildRequest(
        config: _payloadConfig(),
        sourceImageB64: 'source-image',
        sourceWidth: 832,
        sourceHeight: 1216,
        options: const StudioDirectorToolOptions(
          tool: StudioDirectorTool.lineArt,
        ),
      );

      expect(request.endpoint, 'https://image.novelai.net/ai/augment-image');
      expect(request.proxy, '127.0.0.1:7890');
      expect(request.headers['authorization'], 'Bearer pst-token');
      expect(request.timeout, const Duration(seconds: 60));
      expect(request.payload, {
        'image': 'source-image',
        'width': 832,
        'height': 1216,
        'req_type': 'lineart',
      });
    });

    test('builds colorize requests with prompt and defry', () {
      final request = const StudioDirectorToolService().buildRequest(
        config: _payloadConfig(),
        sourceImageB64: 'source-image',
        sourceWidth: 512,
        sourceHeight: 512,
        options: const StudioDirectorToolOptions(
          tool: StudioDirectorTool.colorize,
          prompt: 'red hair, blue eyes',
          defry: 7,
        ),
      );

      expect(request.payload['req_type'], 'colorize');
      expect(request.payload['prompt'], 'red hair, blue eyes');
      expect(request.payload['defry'], 5);
    });

    test('rejects missing source image dimensions before request creation', () {
      expect(
        () => const StudioDirectorToolService().buildRequest(
          config: _payloadConfig(),
          sourceImageB64: 'source-image',
          sourceWidth: 0,
          sourceHeight: 512,
          options: const StudioDirectorToolOptions(
            tool: StudioDirectorTool.sketch,
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('decodes all image files from an augment-image zip response', () {
      final archive = Archive()
        ..addFile(ArchiveFile('image_1.png', 1, Uint8List.fromList([2])))
        ..addFile(ArchiveFile('notes.txt', 1, Uint8List.fromList([9])))
        ..addFile(ArchiveFile('image_0.png', 1, Uint8List.fromList([1])));
      final response = Uint8List.fromList(ZipEncoder().encode(archive)!);

      final images = const StudioDirectorToolService().decodeResultImages(
        response,
      );

      expect(images, hasLength(2));
      expect(images.map((image) => image.variantIndex), [0, 1]);
      expect(images.map((image) => image.variantName), ['image_0', 'image_1']);
      expect(images.map((image) => image.bytes.single), [1, 2]);
    });
  });
}
