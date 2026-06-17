import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/prompt_replace_rule.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/services/prompt_translation_service.dart';
import 'package:novel_studio/data/studio/tools/online_ai_tools.dart';
import 'package:novel_studio/data/studio/tools/filter_rule_config.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/tools/translation_cache.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_shell/widgets/studio_tools_page.dart';

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

    expect(find.byKey(const ValueKey('studio-tools-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('studio-tools-heading')), findsOneWidget);
    expect(find.text('知识与规则'), findsOneWidget);
    expect(find.text('替换规则'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2));
  });

  testWidgets('tools page exposes knowledge and rules entry cards',
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

    for (final key in const [
      'studio-tool-card-knowledge-base',
      'studio-tool-card-filter-rules',
      'studio-tool-card-translation-cache',
      'studio-tool-card-ai-classifier',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }

    final card = tester.widget<Container>(
      find.byKey(const ValueKey('studio-tool-card-knowledge-base')),
    );
    final decoration = card.decoration! as BoxDecoration;
    expect(decoration.borderRadius, StudioTokens.radiusCard);
    expect(decoration.border, StudioTokens.cardBorder);
  });

  testWidgets('tools page does not show redundant quick entry shortcuts',
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

    expect(find.text('快速入口'), findsNothing);
    expect(find.byKey(const ValueKey('studio-tools-open-script-review')),
        findsNothing);
    expect(
        find.byKey(const ValueKey('studio-tools-open-settings')), findsNothing);
  });

  testWidgets('tools page cards expand storage rules in place', (tester) async {
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

    expect(find.text('script_recast/knowledge.json'), findsNothing);

    for (final key in const [
      'studio-tool-card-knowledge-base',
      'studio-tool-card-filter-rules',
      'studio-tool-card-translation-cache',
      'studio-tool-card-ai-classifier',
    ]) {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }

    expect(find.text('script_recast/knowledge.json'), findsOneWidget);
    expect(find.text('configs/filter_rules.json'), findsOneWidget);
    expect(find.text(r'E:\NAI的脚本群\trans_cache.json'), findsOneWidget);
    expect(find.textContaining('script_recast/cache/<scriptId>.json'),
        findsAtLeastNWidgets(1));
    expect(
        find.textContaining('confirmed long-term knowledge'), findsOneWidget);
    expect(find.textContaining('什么时候生效'), findsAtLeastNWidgets(4));
  });

  testWidgets('tools page opens the shared filter rules library in place',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    FilterRuleConfig? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: StudioToolsPage(
          payloadConfig: payload,
          loadFilterRuleConfig: () async =>
              const FilterRuleConfig(deleteKeywords: 'lowres'),
          saveFilterRuleConfig: (config) async {
            saved = config;
          },
        ),
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('studio-tool-card-filter-rules')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('studio-tools-filter-rules-open')),
    );
    await tester
        .tap(find.byKey(const ValueKey('studio-tools-filter-rules-open')));
    await tester.pumpAndSettle();

    final addDelete =
        find.byKey(const ValueKey('filter-rule-section-add-delete'));
    await tester.ensureVisible(addDelete);
    await tester.pumpAndSettle();
    await tester.tap(addDelete);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('filter-rule-tag-edit-field')),
      'city lights',
    );
    await tester.tap(find.byKey(const ValueKey('filter-rule-tag-edit-save')));
    await tester.pumpAndSettle();
    tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('filter-rules-save')),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    expect(saved?.deleteKeywords, 'lowres, city lights');
  });

  testWidgets('tools page opens a long-term knowledge overview',
      (tester) async {
    final payload = _emptyPayload();

    await tester.pumpWidget(
      MaterialApp(
        home: StudioToolsPage(
          payloadConfig: payload,
          loadRecastKnowledgeBase: () async => {
            'scripts': {
              'script-1': {
                'roles': [
                  {
                    'candidateId': 'role-1',
                    'displayName': 'Alice',
                    'importance': 'protagonist',
                    'aliases': ['A'],
                    'evidenceTags': ['blue eyes'],
                    'frameIndexes': [1, 2],
                    'mappedCharacterId': 'asset-alice',
                  },
                  {
                    'candidateId': 'role-2',
                    'displayName': 'Bob',
                    'importance': 'supporting',
                  },
                ],
              },
            },
          },
        ),
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('studio-tool-card-knowledge-base')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('studio-tools-knowledge-open')),
    );
    await tester.tap(find.byKey(const ValueKey('studio-tools-knowledge-open')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('knowledge-overview-dialog')),
        findsOneWidget);
    expect(find.text('长期知识概览'), findsOneWidget);
    expect(find.text('脚本 1'), findsOneWidget);
    expect(find.text('已确认角色 2'), findsOneWidget);
    expect(find.textContaining('主角 1'), findsOneWidget);
    expect(find.textContaining('配角 1'), findsOneWidget);
    expect(find.textContaining('Alice'), findsOneWidget);
  });

  testWidgets('tools page edits and AI retranslates translation cache entries',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final payload = _emptyPayload();
    final cache = TranslationCache(
      entries: {
        TranslationCache.cacheKey('blue eyes'): const TranslationCacheEntry(
          translation: '蓝眼',
          source: 'legacy',
          ts: 1,
        ),
      },
    );
    final classificationCache = PromptTagClassificationCache()
      ..setCategory(
        'blue eyes',
        PromptTagCategory.upperBody,
        source: 'manual-test',
      );
    TranslationCache? saved;
    final service = _FakePromptTranslationService((request) async {
      expect(request.text, 'blue eyes');
      return const OnlineTranslationResult(
        text: '蓝色眼睛',
        source: OnlineAiResultSource.online,
        providerName: 'ai',
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: StudioToolsPage(
          payloadConfig: payload,
          translationCache: cache,
          classificationCache: classificationCache,
          saveTranslationCache: (next) async {
            saved = next;
          },
          translationService: service,
        ),
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('studio-tool-card-translation-cache')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('studio-tools-translation-open')),
    );
    await tester
        .tap(find.byKey(const ValueKey('studio-tools-translation-open')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('translation-cache-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('translation-cache-entry-list')),
      findsOneWidget,
    );
    expect(find.text('blue eyes'), findsOneWidget);
    expect(find.text('上身'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey('translation-cache-entry-blue eyes_en2zh'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('正在编辑：blue eyes'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('translation-cache-edit-blue-eyes')),
      '蓝瞳',
    );
    await tester.tap(
      find.byKey(const ValueKey('translation-cache-retranslate-blue-eyes')),
    );
    await tester.pumpAndSettle();
    expect(find.text('蓝色眼睛'), findsAtLeastNWidgets(1));

    await tester.tap(find.byKey(const ValueKey('translation-cache-save')));
    await tester.pumpAndSettle();

    expect(
      saved?.getCached('blue eyes'),
      '蓝色眼睛',
    );
    expect(
      saved?.entryFor('blue eyes')?.source,
      'ai-refresh',
    );
  });

  testWidgets('translation cache dialog virtualizes large cache entries',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final payload = _emptyPayload();
    final cache = TranslationCache(
      entries: {
        for (var index = 0; index < 18000; index++)
          TranslationCache.cacheKey(
            'tag-${index.toString().padLeft(5, '0')}',
          ): TranslationCacheEntry(
            translation: 'zh-$index',
            source: 'bulk',
            ts: index,
          ),
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StudioToolsPage(
          payloadConfig: payload,
          translationCache: cache,
          saveTranslationCache: (_) async {},
        ),
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('studio-tool-card-translation-cache')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('studio-tools-translation-open')),
    );
    await tester
        .tap(find.byKey(const ValueKey('studio-tools-translation-open')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('translation-cache-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('translation-cache-entry-list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('translation-cache-tag-display')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('translation-cache-entry-tag-17999_en2zh')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const ValueKey('translation-cache-search')),
      'tag-17999',
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('translation-cache-entry-tag-17999_en2zh')),
      findsOneWidget,
    );
    expect(find.text('zh-17999'), findsAtLeastNWidgets(1));
  });

  testWidgets(
      'tools page groups AI role extraction drafts by script and deletes one group',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final payload = _emptyPayload();
    final scriptWithAi = _scriptCache(
      scriptId: 'script-1',
      scriptName: 'Opening',
      extraction: const ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            sourceKind: 'slot',
            displayName: 'Alice',
            confidence: 0.9,
            stages: [
              ScriptAiExtractedStage(stageId: 'main', label: 'main'),
            ],
          ),
        ],
      ),
    );
    final scriptWithoutAi = _scriptCache(
      scriptId: 'script-2',
      scriptName: 'Quiet scene',
      extraction: const ScriptAiRoleExtraction(),
    );
    List<RecastScriptCache>? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: StudioToolsPage(
          payloadConfig: payload,
          loadRecastCaches: () async => [scriptWithAi, scriptWithoutAi],
          saveRecastCaches: (caches) async {
            saved = caches;
          },
        ),
      ),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('studio-tool-card-ai-classifier')),
    );
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('studio-tool-card-ai-classifier')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('studio-tools-ai-analysis-open')),
    );
    await tester
        .tap(find.byKey(const ValueKey('studio-tools-ai-analysis-open')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ai-analysis-dialog')), findsOneWidget);
    expect(find.text('Opening'), findsOneWidget);
    expect(find.text('Quiet scene'), findsNothing);
    expect(find.textContaining('角色 1'), findsOneWidget);
    expect(find.textContaining('分块 0'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('ai-analysis-delete-script-script-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-analysis-delete-confirm')));
    await tester.pumpAndSettle();

    final updated = saved!.firstWhere((cache) => cache.scriptId == 'script-1');
    expect(updated.aiRoleExtraction.status, ScriptAiRoleExtractionStatus.idle);
    expect(updated.aiRoleExtractionChunks, isEmpty);
  });
}

PayloadConfig _emptyPayload() {
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

RecastScriptCache _scriptCache({
  required String scriptId,
  required String scriptName,
  required ScriptAiRoleExtraction extraction,
}) {
  return RecastScriptCache(
    scriptId: scriptId,
    scriptName: scriptName,
    sourceRootPath: '',
    sourceFingerprint: scriptId,
    updatedAt: DateTime.utc(2026, 6, 2),
    mapping: RecastMapping.defaults(scriptId),
    aiRoleExtraction: extraction,
  );
}

class _FakePromptTranslationService implements PromptTranslationService {
  final Future<OnlineTranslationResult> Function(OnlineTranslationRequest)
      handler;

  const _FakePromptTranslationService(this.handler);

  @override
  OnlineAiMode get currentMode => OnlineAiMode.ai;

  @override
  Future<OnlineTranslationResult> translate(
    OnlineTranslationRequest request, {
    bool preferCache = true,
  }) {
    return handler(request);
  }
}
