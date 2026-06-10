import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/script_ai_role_extraction.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/models/script_recast_knowledge.dart';
import 'package:nai_casrand/data/studio/services/script_ai_role_extraction_service.dart';
import 'package:nai_casrand/data/studio/tools/translation_cache.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_script/view_models/studio_script_viewmodel.dart';
import 'package:nai_casrand/ui/studio_script/widgets/studio_script_page.dart';

const scriptStageLabelFixturePath = 'test/fixtures/script_recast/v4_slotted';

Widget buildScriptStageLabelPage({
  required StudioScriptViewModel viewModel,
}) {
  return MaterialApp(
    theme: StudioTheme.build(),
    home: StudioScriptPage(viewModel: viewModel),
  );
}

void main() {
  group('StudioScript stage labels', () {
    test('restored cache derives outfit names for generic stage labels',
        () async {
      var caches = <RecastScriptCache>[];
      final seedViewModel = StudioScriptViewModel(
        loadRecastCaches: () async => caches,
        saveRecastCaches: (next) async => caches = next,
      );
      await seedViewModel.importScriptPath(scriptStageLabelFixturePath);
      await seedViewModel.useFreshParseForChangedSource();
      final baseCache = caches.single;
      caches = [
        RecastScriptCache(
          scriptId: baseCache.scriptId,
          scriptName: baseCache.scriptName,
          sourceRootPath: baseCache.sourceRootPath,
          sourceFingerprint: baseCache.sourceFingerprint,
          updatedAt: baseCache.updatedAt,
          mapping: RecastMapping.defaults(baseCache.scriptId).copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'role-fujita',
                displayLabel: 'fujita kotone',
                sourceName: 'fujita kotone',
                stages: [
                  RoleAssemblyStage(
                    id: 'stage-5-2',
                    label: '服装 3',
                    frameIndexes: [5, 2],
                    sourceParts: RecastPromptParts(
                      upperBody: 'black bow',
                      upperClothing: 'clothed, collared shirt, oversized shirt',
                    ),
                  ),
                ],
              ),
            ],
          ),
          scriptSnapshot: baseCache.scriptSnapshot,
        ),
      ];
      final translationCache = TranslationCache()
        ..setManual('collared shirt', '有领衬衫')
        ..setManual('oversized shirt', '宽松衬衫');
      final viewModel = StudioScriptViewModel(
        translationCache: translationCache,
        loadRecastCaches: () async => caches,
        saveRecastCaches: (next) async => caches = next,
      );

      await viewModel.importScriptPath(scriptStageLabelFixturePath);

      final role = viewModel.roleMappings.singleWhere(
        (role) => role.sourceRoleId == 'role-fujita',
      );
      expect(role.stageItems.single.label, '有领衬衫 / 宽松衬衫');
    });

    test('restored cache localizes previously derived English outfit names',
        () async {
      var caches = <RecastScriptCache>[];
      final seedViewModel = StudioScriptViewModel(
        loadRecastCaches: () async => caches,
        saveRecastCaches: (next) async => caches = next,
      );
      await seedViewModel.importScriptPath(scriptStageLabelFixturePath);
      await seedViewModel.useFreshParseForChangedSource();
      final baseCache = caches.single;
      caches = [
        RecastScriptCache(
          scriptId: baseCache.scriptId,
          scriptName: baseCache.scriptName,
          sourceRootPath: baseCache.sourceRootPath,
          sourceFingerprint: baseCache.sourceFingerprint,
          updatedAt: baseCache.updatedAt,
          mapping: RecastMapping.defaults(baseCache.scriptId).copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'role-fujita',
                displayLabel: 'fujita kotone',
                sourceName: 'fujita kotone',
                stages: [
                  RoleAssemblyStage(
                    id: 'stage-5-2',
                    label: 'collared shirt / oversized shirt',
                    frameIndexes: [5, 2],
                    sourceParts: RecastPromptParts(
                      upperBody: 'black bow',
                      upperClothing: 'clothed, collared shirt, oversized shirt',
                    ),
                  ),
                ],
              ),
            ],
          ),
          scriptSnapshot: baseCache.scriptSnapshot,
        ),
      ];
      final translationCache = TranslationCache()
        ..setManual('collared shirt', '有领衬衫')
        ..setManual('oversized shirt', '宽松衬衫');
      final viewModel = StudioScriptViewModel(
        translationCache: translationCache,
        loadRecastCaches: () async => caches,
        saveRecastCaches: (next) async => caches = next,
      );

      await viewModel.importScriptPath(scriptStageLabelFixturePath);

      final role = viewModel.roleMappings.singleWhere(
        (role) => role.sourceRoleId == 'role-fujita',
      );
      expect(role.stageItems.single.label, '有领衬衫 / 宽松衬衫');
    });

    test('applying role extraction localizes common outfit labels to Chinese',
        () async {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        confidence: 0.9,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            displayName: 'AI Hero',
            confidence: 0.9,
            stages: [
              ScriptAiExtractedStage(
                stageId: 'nude-with-choker',
                label: 'Completely nude with choker',
                frameIndexes: [1],
                identity: 'ai hero',
                upperClothing: 'black choker',
                confidence: 0.9,
              ),
            ],
          ),
        ],
      );
      final viewModel = StudioScriptViewModel(
        scriptAiRoleExtractionService: const _StageLabelRoleExtractionService(
          extraction,
        ),
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );

      await viewModel.importScriptPath(scriptStageLabelFixturePath);
      await viewModel.generateAiRoleExtraction();
      await viewModel.applyHighConfidenceAiRoleExtraction();

      final stages = viewModel.roleMappings.first.stageItems;
      expect(stages, hasLength(1));
      expect(stages.single.id, 'nude-with-choker');
      expect(stages.single.label, isNot('Completely nude with choker'));
      expect(stages.single.sourceParts.identity, 'ai hero');
      expect(stages.single.sourceParts.upperClothing, 'black choker');
    });

    testWidgets('AI role extraction role card switches outfit tabs',
        (tester) async {
      final viewModel = StudioScriptViewModel()
        ..aiRoleExtraction = const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.92,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'Plana',
              confidence: 0.95,
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'school',
                  label: 'School uniform',
                  identity: 'plana (blue archive)',
                  upperClothing: 'school uniform, black coat',
                  lowerClothing: 'black pantyhose',
                  confidence: 0.95,
                ),
                ScriptAiExtractedStage(
                  stageId: 'nightgown',
                  label: 'Nightgown',
                  identity: 'plana (blue archive)',
                  upperClothing: 'see-through white nightgown',
                  lowerClothing: 'barefoot',
                  confidence: 0.9,
                ),
              ],
            ),
          ],
        );

      await tester.pumpWidget(buildScriptStageLabelPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      expect(find.text('校服'), findsOneWidget);
      expect(find.text('睡裙'), findsOneWidget);
      expect(find.text('服装 1'), findsNothing);
      expect(find.text('服装 2'), findsNothing);
      expect(find.textContaining('服装 1 · 校服'), findsOneWidget);
      expect(find.text('school uniform'), findsOneWidget);
      expect(find.text('see-through white nightgown'), findsNothing);

      final secondTab =
          find.byKey(const ValueKey('script-ai-role-stage-tab-2'));
      await tester.ensureVisible(secondTab);
      await tester.pumpAndSettle();
      await tester.tap(secondTab);
      await tester.pumpAndSettle();

      expect(find.textContaining('服装 2 · 睡裙'), findsOneWidget);
      expect(find.text('see-through white nightgown'), findsOneWidget);
      expect(find.text('school uniform'), findsNothing);
    });

    testWidgets('AI role extraction draft localizes derived outfit tabs',
        (tester) async {
      final translationCache = TranslationCache()
        ..setManual('multicolored jacket', '多色夹克')
        ..setManual('yellow shirt', '黄色衬衫');
      final viewModel = StudioScriptViewModel(
        translationCache: translationCache,
      )..aiRoleExtraction = const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.92,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'Yellow',
              confidence: 0.95,
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'stage-1',
                  label: 'Stage 1',
                  identity: 'yellow',
                  upperClothing: 'clothed, multicolored jacket, yellow shirt',
                  confidence: 0.95,
                ),
              ],
            ),
          ],
        );

      await tester.pumpWidget(buildScriptStageLabelPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      expect(find.text('多色夹克 / 黄色衬衫'), findsOneWidget);
      expect(find.textContaining('服装 1 · 多色夹克 / 黄色衬衫'), findsOneWidget);
      expect(find.text('multicolored jacket / yellow shirt'), findsNothing);
    });

    testWidgets('AI role extraction draft shows source frame indexes',
        (tester) async {
      final viewModel = StudioScriptViewModel()
        ..aiRoleExtraction = const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.92,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'role-pecorine',
              displayName: 'pecorine (princess connect!)',
              confidence: 0.66,
              frameIndexes: [2, 3, 22],
              appearances: [
                ScriptAiRoleAppearance(
                  sourceId: 'slot-0',
                  sourceKind: 'slot',
                  frameIndexes: [2, 3, 22],
                ),
              ],
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'main',
                  label: 'Stage 1',
                  identity: 'girl, pecorine (princess connect!)',
                  upperBody: 'animal hands, cat ear panties',
                  lowerBody: 'standing pose',
                  upperClothing: 'alternate costume, black panties',
                  frameIndexes: [2, 3, 22],
                  confidence: 0.64,
                ),
              ],
            ),
          ],
        );

      await tester.pumpWidget(buildScriptStageLabelPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      expect(find.text('所在帧 2, 3, 22'), findsWidgets);
    });

    testWidgets('AI role extraction draft keeps long labels bounded',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const longStageLabel =
          'main-outfit-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final viewModel = StudioScriptViewModel()
        ..aiRoleExtraction = const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.92,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'vulpisfoglia_(arknights)',
              confidence: 0.91,
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'main-outfit',
                  label: longStageLabel,
                  confidence: 0.9,
                ),
              ],
            ),
          ],
        );

      await tester.pumpWidget(buildScriptStageLabelPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('script-ai-role-extraction-draft-panel')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(find.byTooltip(longStageLabel), findsWidgets);
    });
  });
}

class _StageLabelRoleExtractionService
    implements ScriptAiRoleExtractionService {
  final ScriptAiRoleExtraction extraction;

  const _StageLabelRoleExtractionService(this.extraction);

  @override
  Future<ScriptAiRoleExtractionServiceResult> extractRoles({
    required ScriptAiRoleExtractionServiceRequest request,
  }) async {
    return ScriptAiRoleExtractionServiceResult(
      extraction: extraction,
      requestPreview: const {'schema_version': 1, 'request_kind': 'test'},
      aiRequestCount: 1,
    );
  }
}
