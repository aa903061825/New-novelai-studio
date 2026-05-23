import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/prompt_replace_rule.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_shell/widgets/studio_tools_page.dart';

void main() {
  testWidgets('tools page reflects current reusable config counts',
      (tester) async {
    final payload = PayloadConfig(
      rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
      characterConfigList: const [],
      savedPromptConfigList: [
        PromptConfig(strs: const ['saved'], prompts: const []),
      ],
      paramConfig: ParamConfig(),
      settings: Settings.fromJson({}),
      overridePrompt: '',
      useOverridePrompt: false,
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
      MaterialApp(home: StudioToolsPage(payloadConfig: payload)),
    );

    expect(find.text('素材工具'), findsOneWidget);
    expect(find.text('替换规则'), findsOneWidget);
    expect(find.text('保存配置'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2));
  });

  testWidgets('tools page exposes material tool entries with ZZZ cards',
      (tester) async {
    final payload = PayloadConfig(
      rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
      characterConfigList: const [],
      savedPromptConfigList: const [],
      paramConfig: ParamConfig(),
      settings: Settings.fromJson({}),
      overridePrompt: '',
      useOverridePrompt: false,
      useCharacterPromptWithOverride: false,
    );

    await tester.pumpWidget(
      MaterialApp(home: StudioToolsPage(payloadConfig: payload)),
    );

    expect(find.text('标签拆分'), findsOneWidget);
    expect(find.text('过滤规则'), findsOneWidget);
    expect(find.text('Metadata 整理'), findsOneWidget);
    expect(find.text('翻译缓存'), findsOneWidget);
    expect(find.text('AI 分类'), findsOneWidget);

    final card = tester.widget<Container>(
      find.byKey(const ValueKey('studio-tool-card-tag-splitter')),
    );
    final decoration = card.decoration! as BoxDecoration;
    expect(decoration.borderRadius, StudioTokens.radiusCard);
    expect(decoration.border, StudioTokens.cardBorder);
  });
}
