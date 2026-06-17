import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/models/character_config.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/prompt_replace_rule.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/studio/services/studio_workbench_asset_service.dart';
import 'package:novel_studio/data/studio/tools/translation_cache.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/ui/core/app_display_settings.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_theme.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_display.dart';
import 'package:novel_studio/ui/studio_workbench/widgets/workbench_overview_panel.dart';

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000)
        ..setManual('blue eyes', '蓝眼睛')
        ..setManual('long hair', '长发'),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('workbench overview summarizes current creative state',
      (tester) async {
    final payload = PayloadConfig(
      rootPromptConfig: PromptConfig(
        comment: 'Base idea',
        strs: const ['rainy city'],
        prompts: const [],
      ),
      characterConfigList: [
        CharacterConfig.fromEmpty(),
      ],
      savedPromptConfigList: [
        PromptConfig(strs: const ['saved'], prompts: const []),
      ],
      paramConfig: ParamConfig(steps: 33),
      settings: Settings.fromJson({}),
      overridePrompt: 'manual prompt',
      useOverridePrompt: true,
      useCharacterPromptWithOverride: false,
    );
    payload.promptReplaceRules = [
      PromptReplaceRule(
        id: 'rule-1',
        source: 'old',
        target: 'new',
        enabled: true,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: Scaffold(body: WorkbenchOverviewPanel(payloadConfig: payload)),
      ),
    );

    expect(find.text('工作台'), findsOneWidget);
    expect(find.text('manual prompt'), findsOneWidget);
    expect(find.text('角色 1'), findsOneWidget);
    expect(find.text('保存配置 1'), findsOneWidget);
    expect(find.text('替换规则 1'), findsOneWidget);
    expect(find.text('Steps 33'), findsOneWidget);
  });

  testWidgets('workbench overview shows material stack and can clear it',
      (tester) async {
    final payload = PayloadConfig(
      rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
      characterConfigList: const [],
      savedPromptConfigList: const [],
      paramConfig: ParamConfig(steps: 28),
      settings: Settings.fromJson({}),
      overridePrompt: 'manual base',
      useOverridePrompt: true,
      useCharacterPromptWithOverride: false,
    );
    final service = StudioWorkbenchAssetService(payloadConfig: payload);
    service.appendCharacter(
      const CharacterEntry(
        id: 'char-1',
        name: '璃夏',
        traits: ViewVariantTexts(frontFull: 'silver hair, blue eyes'),
      ),
    );
    service.appendTag(
      const TagEntry(
        id: 'tag-1',
        tag: 'cinematic lighting',
        zh: '电影光',
        block: 'camera',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: Scaffold(
          body: WorkbenchOverviewPanel(
            payloadConfig: payload,
            assetService: service,
          ),
        ),
      ),
    );

    expect(find.text('素材栈'), findsOneWidget);
    expect(find.text('角色 · 璃夏'), findsOneWidget);
    expect(find.text('Tag · 电影光'), findsOneWidget);
    expect(find.text('manual base'), findsOneWidget);
    expect(find.text('silver hair'), findsOneWidget);
    expect(find.text('blue eyes'), findsOneWidget);
    expect(find.text('cinematic lighting'), findsOneWidget);

    await tester.tap(find.byTooltip('清空素材栈'));
    await tester.pump();

    expect(service.fragments, isEmpty);
    expect(payload.overridePrompt, 'manual base');
    expect(find.text('角色 · 璃夏'), findsNothing);
  });

  testWidgets(
      'workbench overview keeps character prompt layers before grouping',
      (tester) async {
    final payload = PayloadConfig(
      rootPromptConfig: PromptConfig(
        comment: 'Root prompt',
        strs: const ['base scene'],
        prompts: const [],
      ),
      characterConfigList: [
        CharacterConfig(
          name: 'First',
          positions: const [],
          positivePromptConfig: PromptConfig(
            strs: const ['first character, blue eyes'],
            prompts: const [],
          ),
          negativePrompt: '',
          enabled: true,
        ),
        CharacterConfig(
          name: 'Second',
          positions: const [],
          positivePromptConfig: PromptConfig(
            strs: const ['second character, red dress'],
            prompts: const [],
          ),
          negativePrompt: '',
          enabled: true,
        ),
      ],
      savedPromptConfigList: const [],
      paramConfig: ParamConfig(),
      settings: Settings.fromJson({}),
      overridePrompt: '',
      useOverridePrompt: false,
      useCharacterPromptWithOverride: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: Scaffold(body: WorkbenchOverviewPanel(payloadConfig: payload)),
      ),
    );

    final roleOne = find.byKey(
      const ValueKey('workbench-overview-prompt-group-role-1'),
    );
    final roleTwo = find.byKey(
      const ValueKey('workbench-overview-prompt-group-role-2'),
    );
    final blueEyesTranslation = GetIt.I<TranslationCache>().getCached(
      'blue eyes',
    )!;

    expect(roleOne, findsOneWidget);
    expect(roleTwo, findsOneWidget);
    expect(
      find.descendant(of: roleOne, matching: find.text('first character')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: roleOne,
        matching: find.text(blueEyesTranslation),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: roleOne, matching: find.text('second character')),
      findsNothing,
    );
    expect(
      find.descendant(of: roleTwo, matching: find.text('second character')),
      findsOneWidget,
    );
  });

  testWidgets(
      'workbench overview translates the hovered prompt shortcut target',
      (tester) async {
    final payload = PayloadConfig(
      rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
      characterConfigList: const [],
      savedPromptConfigList: const [],
      paramConfig: ParamConfig(),
      settings: Settings.fromJson({}),
      overridePrompt: 'blue eyes, long hair',
      useOverridePrompt: true,
      useCharacterPromptWithOverride: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: Scaffold(body: WorkbenchOverviewPanel(payloadConfig: payload)),
      ),
    );

    expect(find.text('blue eyes'), findsOneWidget);
    expect(find.text('蓝眼睛'), findsNothing);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(
      location: tester.getCenter(find.byType(PromptTagDisplay)),
    );
    addTearDown(gesture.removePointer);
    await tester.pump();

    AppDisplaySettings.translateHoveredPromptCard();
    await tester.pump();

    expect(find.text('蓝眼睛'), findsOneWidget);
    expect(find.text('长发'), findsOneWidget);
  });
}
