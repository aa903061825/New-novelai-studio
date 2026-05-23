import 'dart:typed_data';

import 'package:flutter_command/flutter_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/models/info_card_content.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';

PayloadConfig _buildPayloadConfig() {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({}),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

class _PreviewConfigService extends ConfigService {
  int saveConfigIndexCallCount = 0;

  @override
  void saveConfigIndex() {
    saveConfigIndexCallCount++;
  }
}

class _PreviewGenerationPageViewmodel extends GenerationPageViewmodel {
  _PreviewGenerationPageViewmodel({this.nextRandomInt});

  final int Function(int upperBound)? nextRandomInt;
  final List<int> randomUpperBounds = [];

  @override
  String encodePreviewThumbnail(Uint8List imageBytes) {
    return 'thumb-${imageBytes.first}';
  }

  @override
  int randomInt(int upperBound) {
    randomUpperBounds.add(upperBound);
    return nextRandomInt?.call(upperBound) ?? 0;
  }
}

Command<void, InfoCardContent> _cardCommand({
  required String title,
  Uint8List? imageBytes,
}) {
  final command = Command.createSyncNoParam(
    () => InfoCardContent(
      title: title,
      info: '',
      additionalInfo: const {},
      imageBytes: imageBytes,
    ),
    initialValue: InfoCardContent.fromEmpty(),
  );
  command();
  return command;
}

void main() {
  late _PreviewConfigService configService;

  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<PayloadConfig>(_buildPayloadConfig());
    GetIt.I.registerSingleton<CommandStatus>(CommandStatus());
    configService = _PreviewConfigService()
      ..currentUuid = 'active'
      ..configIndex = {
        'active': SavedConfigInfo(
          title: 'Active',
          lastModified: DateTime.parse('2026-05-19T09:00:00Z'),
        ),
      };
    GetIt.I.registerSingleton<ConfigService>(configService);
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  test('saves the latest nine generated images as current config preview', () {
    final viewmodel = _PreviewGenerationPageViewmodel(
      nextRandomInt: (_) => 4,
    );
    for (var i = 0; i < 11; i++) {
      viewmodel.commandList.add(
        _cardCommand(title: 'card-$i', imageBytes: Uint8List.fromList([i])),
      );
    }
    viewmodel.commandList.add(_cardCommand(title: 'text-only'));

    final savedCount = viewmodel.saveCurrentConfigPreview();

    expect(savedCount, 9);
    expect(configService.configIndex['active']!.previewImages, [
      'thumb-10',
      'thumb-9',
      'thumb-8',
      'thumb-7',
      'thumb-6',
      'thumb-5',
      'thumb-4',
      'thumb-3',
      'thumb-2',
    ]);
    expect(configService.configIndex['active']!.previewCoverIndex, 4);
    expect(configService.saveConfigIndexCallCount, 1);
    expect(viewmodel.randomUpperBounds, [9]);
  });

  test('does not save a config preview when there are no generated images', () {
    final viewmodel = _PreviewGenerationPageViewmodel();
    viewmodel.commandList.add(_cardCommand(title: 'text-only'));

    final savedCount = viewmodel.saveCurrentConfigPreview();

    expect(savedCount, 0);
    expect(configService.configIndex['active']!.previewImages, isEmpty);
    expect(configService.saveConfigIndexCallCount, 0);
    expect(viewmodel.hasCurrentConfigPreviewSourceImages, isFalse);
  });
}
