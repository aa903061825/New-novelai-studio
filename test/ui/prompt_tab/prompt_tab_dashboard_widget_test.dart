import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/character_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/prompt_replace_rule.dart';
import 'package:nai_casrand/ui/prompt_tab/view_models/prompt_tab_viewmodel.dart';
import 'package:nai_casrand/ui/prompt_tab/widgets/prompt_tab_view.dart';

const _promptReplaceRulesHintEn =
    'Applied in order before generation. A comma-separated source acts as a grouped tag rule: the earliest matched tag becomes the target and other matched tags are removed.';

const _promptReplaceRulesHintZh =
    '生成前按顺序执行。源文本使用逗号分隔时会作为一组提示词处理：实际最早命中的项替换为目标文本，其余命中的项会被删除。';

class _EnglishPromptAssetLoader extends AssetLoader {
  const _EnglishPromptAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    return {
      'prompt_dashboard_title': 'Prompt Workbench',
      'prompt_dashboard_hint': 'Use cards to focus one editor at a time.',
      'prompt_dashboard_base_title': 'Base Prompt',
      'prompt_dashboard_character_title': 'Character Prompts',
      'prompt_dashboard_character_subtitle': 'Character configs: {num}',
      'prompt_dashboard_replace_title': 'Global Replacements',
      'prompt_dashboard_replace_subtitle': 'Enabled: {enabled}/{total}',
      'prompt_dashboard_saved_title': 'Saved Prompt Configs',
      'prompt_dashboard_saved_subtitle': 'Saved configs: {num}',
      'characters': 'Characters',
      'add_character': 'Add character',
      'rearrange_characters': 'Rearrange characters',
      'there_is_no_saved_config': 'There is no saved config...',
      'prompt_replace_rules_title': 'Global Prompt Replacement Rules',
      'prompt_replace_rules_stats':
          'Rules: {total}, enabled: {enabled}, valid: {valid}, skipped: {skipped}',
      'prompt_replace_add_rule': 'Add rule',
      'prompt_replace_rules_hint': _promptReplaceRulesHintEn,
      'prompt_replace_rules_empty': 'No replacement rules yet.',
      'prompt_replace_rule_label': 'Rule #{num}',
      'prompt_replace_source': 'Source text',
      'prompt_replace_target': 'Target text',
      'prompt_replace_batch_input': 'Batch rule input',
      'prompt_replace_batch_placeholder':
          'pink dress, white jacket, short jacket',
      'prompt_replace_batch_hint':
          'Use commas or line breaks as separators. Each created rule remains editable.',
      'prompt_replace_batch_add': 'Create rules in batch',
      'prompt_replace_source_placeholder': '<Empty source: skipped>',
      'prompt_replace_target_placeholder': '<Empty target: delete>',
      'prompt_replace_duplicate': 'Duplicate',
      'prompt_replace_delete': 'Delete rule',
    };
  }
}

class _LocalizedPromptTabApp extends StatelessWidget {
  const _LocalizedPromptTabApp({required this.viewmodel});

  final PromptTabViewmodel viewmodel;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      home: PromptTabView(viewmodel: viewmodel),
    );
  }
}

const _sharedPreferencesChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

PromptTabViewmodel _buildViewmodel() {
  return PromptTabViewmodel(
    promptConfig: PromptConfig(
      comment: 'root',
      strs: const ['masterpiece'],
      prompts: const [],
    ),
    characterConfigList: <CharacterConfig>[],
    savedConfigList: <PromptConfig>[],
    promptReplaceRules: <PromptReplaceRule>[],
  );
}

Future<void> _pumpLocalizedPromptTabView(
  WidgetTester tester,
  PromptTabViewmodel viewmodel,
) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/l10n',
      assetLoader: const _EnglishPromptAssetLoader(),
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      saveLocale: false,
      child: _LocalizedPromptTabApp(viewmodel: viewmodel),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sharedPreferencesChannel,
            (methodCall) async {
      if (methodCall.method == 'getAll') {
        return <String, Object>{};
      }

      return true;
    });
    await EasyLocalization.ensureInitialized();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sharedPreferencesChannel, null);
  });

  testWidgets('tap replacement card shows replacement panel', (tester) async {
    final viewmodel = _buildViewmodel();
    viewmodel.setActivePanel(PromptDashboardPanel.characters);

    await _pumpLocalizedPromptTabView(tester, viewmodel);

    expect(viewmodel.activePanel, PromptDashboardPanel.characters);

    await tester.tap(find.text('Global Replacements'));
    await tester.pumpAndSettle();

    expect(viewmodel.activePanel, PromptDashboardPanel.replaceRules);
    expect(find.text('Global Prompt Replacement Rules'), findsOneWidget);
    expect(find.text('Add rule'), findsOneWidget);
    expect(find.text(_promptReplaceRulesHintEn), findsOneWidget);
  });

  test('replacement hint locale copy explains grouped source rules', () {
    final en = json.decode(
      File('assets/l10n/en.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final zh = json.decode(
      File('assets/l10n/zh-CN.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    expect(
      en['prompt_replace_rules_hint'],
      _promptReplaceRulesHintEn,
    );
    expect(
      zh['prompt_replace_rules_hint'],
      _promptReplaceRulesHintZh,
    );
  });

  testWidgets('batch input creates multiple replacement rules', (tester) async {
    final viewmodel = _buildViewmodel();
    viewmodel.setActivePanel(PromptDashboardPanel.replaceRules);

    await _pumpLocalizedPromptTabView(tester, viewmodel);

    expect(find.text('Batch rule input'), findsOneWidget);
    expect(
      find.text(
        'Use commas or line breaks as separators. Each created rule remains editable.',
      ),
      findsOneWidget,
    );
    expect(find.text('Create rules in batch'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('prompt_replace_batch_input_field')),
      'pink dress, white jacket\nblack boots',
    );
    await tester.pump();

    expect(
      viewmodel.batchReplaceRuleInput,
      'pink dress, white jacket\nblack boots',
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('prompt_replace_batch_add_button')),
    );
    await tester
        .tap(find.byKey(const ValueKey('prompt_replace_batch_add_button')));
    await tester.pumpAndSettle();

    expect(
      viewmodel.promptReplaceRules.map((rule) => rule.source).toList(),
      ['pink dress', 'white jacket', 'black boots'],
    );

    await tester.ensureVisible(find.text('pink dress', skipOffstage: false));

    expect(find.text('pink dress', skipOffstage: false), findsOneWidget);
    expect(find.text('white jacket', skipOffstage: false), findsOneWidget);
    expect(find.text('black boots', skipOffstage: false), findsOneWidget);
    expect(find.text('Delete rule', skipOffstage: false), findsNWidgets(3));
  });

  testWidgets('batch add button toggles state and clears input after create', (
    tester,
  ) async {
    final viewmodel = _buildViewmodel();
    viewmodel.setActivePanel(PromptDashboardPanel.replaceRules);
    final inputFinder = find.byKey(
      const ValueKey('prompt_replace_batch_input_field'),
    );
    final buttonFinder = find.byKey(
      const ValueKey('prompt_replace_batch_add_button'),
    );

    await _pumpLocalizedPromptTabView(tester, viewmodel);

    expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNull);
    expect(tester.widget<TextField>(inputFinder).controller!.text, isEmpty);

    await tester.enterText(inputFinder, 'red coat');
    await tester.pump();

    expect(
      tester.widget<FilledButton>(buttonFinder).onPressed,
      isNotNull,
    );

    await tester.ensureVisible(buttonFinder);
    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();

    expect(viewmodel.promptReplaceRules.map((rule) => rule.source).toList(), [
      'red coat',
    ]);
    expect(viewmodel.batchReplaceRuleInput, isEmpty);
    expect(tester.widget<TextField>(inputFinder).controller!.text, isEmpty);
    expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNull);
  });
}
