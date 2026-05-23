import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/character_config.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/prompt_replace_rule.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_workbench/widgets/workbench_overview_panel.dart';

void main() {
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
    expect(
      find.text('manual base, silver hair, blue eyes, cinematic lighting'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('清空素材栈'));
    await tester.pump();

    expect(service.fragments, isEmpty);
    expect(payload.overridePrompt, 'manual base');
    expect(find.text('角色 · 璃夏'), findsNothing);
  });
}
