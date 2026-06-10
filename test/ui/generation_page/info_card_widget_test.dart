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
import 'package:nai_casrand/data/studio/tools/translation_cache.dart';
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

Command<void, InfoCardContent> _commandWithPromptInfo() {
  final content = InfoCardContent(
    title: 'prompt-only',
    info: 'blue eyes, long hair',
    additionalInfo: const {},
  );
  return Command.createAsyncNoParam(
    () async => content,
    initialValue: content,
  );
}

Command<void, InfoCardContent> _commandWithRoleLayeredImage() {
  final content = InfoCardContent(
    title: 'layered.png',
    info: 'base scene, first character, blue eyes, second character, red dress',
    additionalInfo: const {
      'v4_prompt': {
        'caption': {
          'base_caption': 'base scene',
          'char_captions': [
            {'char_caption': 'first character, blue eyes'},
            {'caption': 'second character, red dress'},
          ],
        },
      },
    },
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
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000)
        ..setManual('blue eyes', '蓝眼睛')
        ..setManual('long hair', '长发'),
    );
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

  testWidgets('detail page renders prompt info as translated tags', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: InfoCard(command: _commandWithPromptInfo()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(InfoCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('blue eyes'), findsWidgets);
    expect(find.text('蓝眼睛'), findsWidgets);
    expect(find.text('长发'), findsWidgets);
  });

  testWidgets('image detail page keeps role prompt groups before tag grouping',
      (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: InfoCard(command: _commandWithRoleLayeredImage()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byType(InfoCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final infoTile = find.ancestor(
      of: find.byKey(const ValueKey('info-card-prompt-groups')).first,
      matching: find.byType(ListTile),
    );
    final roleOneGroup = find.descendant(
      of: infoTile,
      matching: find.byKey(
        const ValueKey('info-card-prompt-group-role-1'),
        skipOffstage: false,
      ),
    );
    final roleTwoGroup = find.descendant(
      of: infoTile,
      matching: find.byKey(
        const ValueKey('info-card-prompt-group-role-2'),
        skipOffstage: false,
      ),
    );

    expect(roleOneGroup, findsOneWidget);
    expect(roleTwoGroup, findsOneWidget);
    expect(
      find.descendant(
        of: roleOneGroup,
        matching: find.text('first character'),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: roleOneGroup,
        matching: find.text('second character'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: roleTwoGroup,
        matching: find.text('second character'),
      ),
      findsWidgets,
    );
  });
}
