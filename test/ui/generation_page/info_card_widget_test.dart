import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_command/flutter_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:image/image.dart' as img;
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/models/info_card_content.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/ui/generation_page/widgets/info_card.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_panel.dart';

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

Uint8List _squarePngBytes() {
  final image = img.Image(width: 800, height: 800, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(139, 92, 246));
  return Uint8List.fromList(img.encodePng(image));
}

Command<void, InfoCardContent> _commandWithImage() {
  final content = InfoCardContent(
    title: 'generated.png',
    info: 'prompt',
    additionalInfo: const {},
    imageBytes: _squarePngBytes(),
  );
  return Command.createAsyncNoParam(
    () async => content,
    initialValue: content,
  );
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<PayloadConfig>(_buildPayloadConfig());
    GetIt.I.registerSingleton<CommandStatus>(CommandStatus());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('generated image stays padded and height-limited inside card', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 560,
              child: InfoCard(command: _commandWithImage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surfaceRect = tester.getRect(find.byType(StudioPanel));
    final frameRect = tester.getRect(
      find.byKey(const ValueKey('generated-info-card-image-frame')),
    );

    expect(frameRect.left, greaterThan(surfaceRect.left + 12));
    expect(frameRect.right, lessThan(surfaceRect.right - 12));
    expect(frameRect.height, lessThanOrEqualTo(360));
  });
}
