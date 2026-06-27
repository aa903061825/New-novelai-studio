import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/models/studio_asset_capture.dart';
import 'package:novel_studio/data/studio/services/production_queue_service.dart';
import 'package:novel_studio/data/studio/services/script_ai_role_extraction_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_engine.dart';
import 'package:novel_studio/data/studio/services/script_recast_asset_context_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_parser_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_production_service.dart';
import 'package:novel_studio/data/studio/services/studio_asset_capture_service.dart';
import 'package:novel_studio/data/studio/tools/filter_rule_config.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/tools/translation_cache.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_animated_presence.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_drawer_motion.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_interactive_surface.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_tokens.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_staggered_reveal.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_theme.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_chip.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_display.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_editor.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_asset_capture_host.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_asset_drawer_shell.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_button.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_panel.dart';
import 'package:novel_studio/ui/studio_script/models/studio_script_asset_focus.dart';
import 'package:novel_studio/ui/studio_script/models/studio_script_recast_plan.dart';
import 'package:novel_studio/ui/studio_script/view_models/studio_script_viewmodel.dart';
import 'package:novel_studio/ui/studio_script/widgets/studio_script_page.dart';

const _fixturePath = 'test/fixtures/script_recast/v4_slotted';
final _fixtureScriptId = ScriptRecastParserService.scriptIdForDirectory(
  Directory(_fixturePath),
);

Widget buildScriptPage({
  StudioScriptViewModel? viewModel,
  StudioScriptAssetFocus? assetFocus,
  Future<Set<String>> Function()? loadAssetFavoriteKeys,
  Future<void> Function(String key, bool isFavorite)? setAssetFavorite,
}) {
  return MaterialApp(
    theme: StudioTheme.build(),
    home: StudioScriptPage(
      viewModel: viewModel ?? StudioScriptViewModel(),
      assetFocus: assetFocus,
      loadAssetFavoriteKeys: loadAssetFavoriteKeys,
      setAssetFavorite: setAssetFavorite,
    ),
  );
}

Future<void> _dragSelectedTagTo(
  WidgetTester tester,
  Finder selectedChip,
  Finder target,
) async {
  final start = tester.getCenter(selectedChip);
  final end = tester.getCenter(target);
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: start);
  await tester.pump();
  await mouse.down(start);
  await mouse.moveTo(end);
  await tester.pump();
  await mouse.up();
  await tester.pumpAndSettle();
  await mouse.removePointer();
}

String _baseCaptionFromPayload(Map<String, dynamic> payload) {
  final input = payload['input'];
  if (input is String) {
    return input;
  }
  final parameters = payload['parameters'];
  if (parameters is Map) {
    final prompt = parameters['v4_prompt'];
    if (prompt is Map) {
      final caption = prompt['caption'];
      if (caption is Map && caption['base_caption'] is String) {
        return caption['base_caption'] as String;
      }
    }
  }
  final comment = payload['Comment'] as Map;
  final prompt = comment['v4_prompt'] as Map;
  final caption = prompt['caption'] as Map;
  return caption['base_caption'] as String;
}

String _sourceFingerprintForTest(Script script) {
  final parts = [
    script.id,
    script.rootPath,
    for (final frame in script.frames)
      '${frame.index}:${frame.fileName}:${frame.sourcePath}:'
          '${_stableContentHashForTest(frame.rawJson)}',
  ];
  return parts.join('|');
}

String _stableContentHashForTest(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

void main() {
  group('StudioScriptViewModel', () {
    test(
      'imports fixture directory and derives state from parsed script',
      () async {
        final viewModel = StudioScriptViewModel();

        await viewModel.importScriptPath(_fixturePath);

        expect(viewModel.folderStatus, contains('v4_slotted'));
        expect(viewModel.frameCount, 2);
        expect(viewModel.parsedCount, 2);
        expect(viewModel.warningCount, 0);
        expect(viewModel.schemaLabel, 'v4Slotted');
        expect(viewModel.roleCount, 2);
        expect(viewModel.roles, contains('角色 1 -> unknown'));
        expect(viewModel.roles, contains('角色 2 -> unknown'));
        expect(viewModel.roles, isNot(anyElement(startsWith('slot-0'))));
        expect(
          viewModel.artistChains,
          contains('source artist:terasu_mc -> target unchanged'),
        );
        expect(viewModel.timeline.map((item) => item.label), ['1帧', '2帧']);
        expect(viewModel.diff.original, contains('artist:terasu_mc'));
        expect(viewModel.diff.recast, contains('artist:terasu_mc'));
      },
    );

    test('imports script without guessing temporary character cards', () async {
      final viewModel = StudioScriptViewModel(
        loadCharacters: () async => const [],
        loadArtistChains: () async => const [],
      );

      await viewModel.importScriptPath(_fixturePath);

      expect(viewModel.characterOptions, isEmpty);
      expect(
        viewModel.artistChainOptions.single.prompt,
        contains('artist:terasu_mc'),
      );
    });

    test('records parser failures without throwing out of import', () async {
      final viewModel = StudioScriptViewModel(
        parserService: _ThrowingParserService(),
      );

      await viewModel.importScriptPath('missing-or-broken-script');

      expect(viewModel.folderStatus, contains('导入失败'));
      expect(viewModel.frameCount, 0);
      expect(viewModel.parsedCount, 0);
      expect(viewModel.warningCount, 1);
      expect(viewModel.warnings.single, contains('parser exploded'));
      expect(viewModel.timeline, isEmpty);
    });

    test('shows import progress while parser is still working', () async {
      final parser = _PendingProgressParserService(
        _singleFrameScript(baseCaption: 'artist:progress, city lights'),
      );
      final viewModel = StudioScriptViewModel(
        parserService: parser,
        loadCharacters: () async => const [],
        loadArtistChains: () async => const [],
        loadVibes: () async => const [],
      );

      final importFuture = viewModel.importScriptPath('large-png-script');
      await parser.started.future;

      expect(viewModel.isImportingScript, isTrue);
      expect(viewModel.importProgressLabel, contains('1/3'));
      expect(viewModel.importProgressLabel, contains('p000.png'));
      expect(viewModel.importProgressValue, closeTo(1 / 3, 0.001));

      parser.complete();
      await importFuture;

      expect(viewModel.isImportingScript, isFalse);
      expect(viewModel.importProgressLabel, isEmpty);
      expect(viewModel.importProgressValue, isNull);
    });

    testWidgets('renders import progress in the script header', (tester) async {
      final viewModel = StudioScriptViewModel()
        ..isImportingScript = true
        ..importProgressLabel = '正在解析剧本帧 1/3 · p000.png'
        ..importProgressValue = 1 / 3;

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));

      expect(
        find.byKey(const ValueKey('script-import-progress-banner')),
        findsOneWidget,
      );
      expect(find.textContaining('1/3'), findsWidgets);
      final indicator = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('script-import-progress-bar')),
      );
      expect(indicator.value, closeTo(1 / 3, 0.001));
    });

    testWidgets('hides heavy script workspace while import is running',
        (tester) async {
      final viewModel = StudioScriptViewModel()
        ..isImportingScript = true
        ..importProgressLabel = '正在打开剧本工作台...'
        ..importProgressValue = 0.28
        ..frameCount = 144
        ..parsedCount = 144
        ..timeline = [
          for (var index = 1; index <= 144; index++)
            StudioScriptTimelineItem(
              frameIndex: index,
              label: '$index帧',
              selected: index == 1,
            ),
        ];

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('script-import-queue-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('script-layout-main-workspace')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('script-layout-bottom-timeline')),
        findsNothing,
      );
    });

    test('saves a parsed PNG script snapshot for the next import', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'studio-script-auto-png-snapshot-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      await File(
        '${tempDir.path}${Platform.pathSeparator}p000.png',
      ).writeAsBytes(const [137, 80, 78, 71]);
      var caches = <RecastScriptCache>[];
      final script = _singleFrameScript(
        id: ScriptRecastParserService.scriptIdForDirectory(tempDir),
        name: 'auto png snapshot',
        rootPath: tempDir.path,
        baseCaption: 'artist:progress-cache, city lights',
      );
      final viewModel = StudioScriptViewModel(
        parserService: _FakeParserService([script]),
        loadCharacters: () async => const [],
        loadArtistChains: () async => const [],
        loadVibes: () async => const [],
        loadRecastCaches: () async => caches,
        saveRecastCaches: (next) async => caches = next,
      );

      await viewModel.importScriptPath(tempDir.path);

      expect(caches, hasLength(1));
      expect(caches.single.scriptSnapshot, isNotEmpty);

      final restored = StudioScriptViewModel(
        parserService: _ThrowingParserService(),
        loadRecastCaches: () async => caches,
      );
      await restored.importScriptPath(tempDir.path);

      expect(restored.frameCount, 1);
      expect(restored.folderStatus, contains('auto png snapshot'));
    });

    test('saving a parsed PNG snapshot preserves existing AI draft', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'studio-script-png-snapshot-preserve-ai-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      await File(
        '${tempDir.path}${Platform.pathSeparator}p000.png',
      ).writeAsBytes(const [137, 80, 78, 71]);
      final script = _singleFrameScript(
        id: ScriptRecastParserService.scriptIdForDirectory(tempDir),
        name: 'preserve ai snapshot',
        rootPath: tempDir.path,
        baseCaption: 'artist:preserve-ai, city lights',
      );
      var caches = [
        RecastScriptCache(
          scriptId: script.id,
          scriptName: script.name,
          sourceRootPath: script.rootPath,
          sourceFingerprint: _testSourceFingerprint(script),
          updatedAt: DateTime.utc(2026, 6, 8),
          mapping: RecastMapping.defaults(script.id),
          aiRoleExtraction: const ScriptAiRoleExtraction(
            status: ScriptAiRoleExtractionStatus.ready,
            roles: [
              ScriptAiExtractedRole(
                sourceRoleId: 'slot-0',
                displayName: 'AI Hero',
                stages: [
                  ScriptAiExtractedStage(
                    stageId: 'main-outfit',
                    frameIndexes: [1],
                    identity: 'ai hero',
                    upperClothing: 'blue jacket',
                  ),
                ],
              ),
            ],
          ),
        ),
      ];
      final viewModel = StudioScriptViewModel(
        parserService: _FakeParserService([script]),
        loadCharacters: () async => const [],
        loadArtistChains: () async => const [],
        loadVibes: () async => const [],
        loadRecastCaches: () async => caches,
        saveRecastCaches: (next) async => caches = next,
      );

      await viewModel.importScriptPath(tempDir.path);

      expect(caches, hasLength(1));
      expect(caches.single.scriptSnapshot, isNotEmpty);
      expect(caches.single.aiRoleExtraction.isReady, isTrue);
      expect(
        caches.single.aiRoleExtraction.roles.single.displayName,
        'AI Hero',
      );
    });

    test('role outfit stage labels and frame indexes can be edited and saved',
        () async {
      final script = _scriptWithFrames(
        [
          (
            index: 1,
            base: 'artist:test, bedroom',
            chars: ['ai hero, blue jacket'],
          ),
          (
            index: 2,
            base: 'artist:test, hallway',
            chars: ['ai hero, blue jacket'],
          ),
          (
            index: 3,
            base: 'artist:test, beach',
            chars: ['ai hero, white bikini'],
          ),
        ],
        id: 'editable-stage-script',
        name: 'Editable Stage Script',
        rootPath: 'editable-stage-script',
      );
      final cache = RecastScriptCache(
        scriptId: script.id,
        scriptName: script.name,
        sourceRootPath: script.rootPath,
        sourceFingerprint: _normalizedSourceFingerprintForTest(script),
        updatedAt: DateTime.utc(2026, 6, 13),
        mapping: RecastMapping.defaults(script.id).copyWith(
          roleAssemblies: const [
            RoleAssembly(
              sourceRoleId: 'slot-0',
              displayLabel: 'AI Hero',
              sourceName: 'AI Hero',
              stages: [
                RoleAssemblyStage(
                  id: 'main-outfit',
                  label: 'main outfit',
                  frameIndexes: [1, 2],
                  sourceParts: RecastPromptParts(
                    upperClothing: 'blue jacket',
                  ),
                ),
              ],
            ),
          ],
        ),
        scriptSnapshot: script.toJson(),
      );
      final savedCaches = <RecastScriptCache>[];
      final viewModel = StudioScriptViewModel(
        parserService: _FakeParserService([script]),
        loadRecastCacheByScriptId: (_) async => cache,
        saveRecastCache: (cache) async => savedCaches.add(cache),
      );

      await viewModel.importScriptPath(script.rootPath);

      final role = viewModel.roleMappings.single;
      final stageId = role.selectedStage!.id;
      viewModel.renameRoleStage(
        sourceRoleId: role.sourceRoleId,
        stageId: stageId,
        label: 'black raincoat',
      );
      viewModel.setRoleStageFrameIndexes(
        sourceRoleId: role.sourceRoleId,
        stageId: stageId,
        frameIndexes: [3, 1, 3, 2],
      );

      final updatedStage = viewModel.roleMappings.single.selectedStage!;
      expect(updatedStage.label, 'black raincoat');
      expect(updatedStage.frameIndexes, [1, 2, 3]);

      await Future<void>.delayed(const Duration(milliseconds: 550));
      await Future<void>.delayed(Duration.zero);

      expect(savedCaches, isNotEmpty);
      final savedStage =
          savedCaches.last.mapping.roleAssemblies.single.stages.single;
      expect(savedStage.label, 'black raincoat');
      expect(savedStage.frameIndexes, [1, 2, 3]);
    });

    test('restores PNG cache snapshot through single-cache loader', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'studio-script-single-cache-loader-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      await File(
        '${tempDir.path}${Platform.pathSeparator}p000.png',
      ).writeAsBytes(const [137, 80, 78, 71]);
      final script = _singleFrameScript(
        id: ScriptRecastParserService.scriptIdForDirectory(tempDir),
        name: 'single cache script',
        rootPath: tempDir.path,
        baseCaption: 'artist:single-cache, city lights',
      );
      final cache = RecastScriptCache(
        scriptId: script.id,
        scriptName: script.name,
        sourceRootPath: tempDir.path,
        sourceFingerprint: 'fingerprint',
        updatedAt: DateTime.utc(2026, 6, 8),
        mapping: RecastMapping.defaults(script.id),
        scriptSnapshot: script.toJson(),
      );
      var targetedLoadCount = 0;
      final viewModel = StudioScriptViewModel(
        parserService: _ThrowingParserService(),
        loadRecastCacheByScriptId: (scriptId) async {
          targetedLoadCount += 1;
          return scriptId == script.id ? cache : null;
        },
        loadRecastCaches: () async {
          throw StateError('Bulk cache loader should not be used.');
        },
      );

      await viewModel.importScriptPath(tempDir.path);

      expect(targetedLoadCount, 1);
      expect(viewModel.frameCount, 1);
      expect(viewModel.folderStatus, contains('single cache script'));
    });

    test('restores PNG cache snapshot through direct snapshot restore',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'studio-script-direct-cache-loader-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      await File(
        '${tempDir.path}${Platform.pathSeparator}p000.png',
      ).writeAsBytes(const [137, 80, 78, 71]);
      final script = _singleFrameScript(
        id: ScriptRecastParserService.scriptIdForDirectory(tempDir),
        name: 'direct cache script',
        rootPath: tempDir.path,
        baseCaption: 'artist:direct-cache, city lights',
      );
      final cache = RecastScriptCache(
        scriptId: script.id,
        scriptName: script.name,
        sourceRootPath: tempDir.path,
        sourceFingerprint: 'fingerprint',
        updatedAt: DateTime.utc(2026, 6, 27, 12),
        mapping: RecastMapping.defaults(script.id),
        scriptSnapshot: const {},
      );
      var directRestoreCalls = 0;
      var mapHydratorCalls = 0;
      final viewModel = StudioScriptViewModel(
        parserService: _ThrowingParserService(),
        loadRecastCacheByScriptId: (_) async {
          throw StateError('Full cache loader should not be used.');
        },
        loadRecastCaches: () async {
          throw StateError('Bulk cache loader should not be used.');
        },
        restoreRecastCacheSnapshotByScriptId: ({
          required String scriptId,
          String? importPath,
        }) async {
          directRestoreCalls += 1;
          expect(scriptId, script.id);
          expect(importPath, tempDir.path);
          return RecastScriptCacheSnapshotRestore(
            cache: cache,
            script: script,
          );
        },
        hydrateCachedScriptSnapshot: ({
          required Map<String, dynamic> scriptSnapshot,
          String? importPath,
        }) {
          mapHydratorCalls += 1;
          throw StateError('Map snapshot hydrator should not be used.');
        },
      );

      await viewModel.importScriptPath(tempDir.path);

      expect(directRestoreCalls, 1);
      expect(mapHydratorCalls, 0);
      expect(viewModel.frameCount, 1);
      expect(viewModel.folderStatus, contains('direct cache script'));
    });

    test('opens exhibition script from cache without parsing directory',
        () async {
      final script = _singleFrameScript(
        id: 'script-exhibition-fast-open',
        name: 'Exhibition Fast Open',
        rootPath: r'C:\scripts\exhibition-fast-open',
        baseCaption: 'artist:fast-cache, city lights',
      );
      final cache = RecastScriptCache(
        scriptId: script.id,
        scriptName: script.name,
        sourceRootPath: script.rootPath,
        sourceFingerprint: _testSourceFingerprint(script),
        updatedAt: DateTime.utc(2026, 6, 20, 8),
        mapping: RecastMapping.defaults(script.id),
        scriptSnapshot: script.toJson(),
      );
      var targetedLoadCount = 0;
      final viewModel = StudioScriptViewModel(
        parserService: _ThrowingParserService(),
        loadRecastCacheByScriptId: (scriptId) async {
          targetedLoadCount += 1;
          return scriptId == script.id ? cache : null;
        },
      );

      await viewModel.openScriptFromExhibition(
        scriptId: script.id,
        sourceFolder: script.rootPath,
        frameIndex: 1,
      );

      expect(targetedLoadCount, 1);
      expect(viewModel.frameCount, 1);
      expect(viewModel.folderStatus, contains('Exhibition Fast Open'));
      expect(viewModel.selectedFrameIndex, 1);
    });

    test('opens exhibition cache before asset context finishes loading',
        () async {
      final script = _singleFrameScript(
        id: 'script-exhibition-no-asset-block',
        name: 'Exhibition No Asset Block',
        rootPath: r'C:\scripts\exhibition-no-asset-block',
        baseCaption: 'artist:slow-assets, city lights',
      );
      final cache = RecastScriptCache(
        scriptId: script.id,
        scriptName: script.name,
        sourceRootPath: script.rootPath,
        sourceFingerprint: _testSourceFingerprint(script),
        updatedAt: DateTime.utc(2026, 6, 20, 10),
        mapping: RecastMapping.defaults(script.id),
        scriptSnapshot: script.toJson(),
      );
      final pendingAssetContext = Completer<ScriptRecastAssetContext>();
      var assetContextLoadCount = 0;
      final viewModel = StudioScriptViewModel(
        parserService: _ThrowingParserService(),
        loadRecastCacheByScriptId: (scriptId) async {
          return scriptId == script.id ? cache : null;
        },
        loadAssetContext: () {
          assetContextLoadCount += 1;
          return pendingAssetContext.future;
        },
      );

      await expectLater(
        viewModel
            .openScriptFromExhibition(
              scriptId: script.id,
              sourceFolder: script.rootPath,
              frameIndex: 1,
            )
            .timeout(const Duration(milliseconds: 80)),
        completes,
      );

      expect(assetContextLoadCount, 1);
      expect(viewModel.isImportingScript, isFalse);
      expect(viewModel.importProgressLabel, isEmpty);
      expect(viewModel.frameCount, 1);
      expect(viewModel.selectedFrameIndex, 1);

      pendingAssetContext.complete(
        ScriptRecastAssetContext(
          characters: const [],
          outfits: const [],
          artistChains: const [],
          filterRules: const FilterRuleConfig(),
          filterMetadata: const ScriptRecastFilterMetadata.empty(),
        ),
      );
      await Future<void>.delayed(Duration.zero);
    });

    test('opens exhibition cache through async snapshot hydrator with timings',
        () async {
      final script = _singleFrameScript(
        id: 'script-exhibition-hydrator',
        name: 'Exhibition Hydrator',
        rootPath: r'C:\scripts\exhibition-hydrator',
        baseCaption: 'artist:hydrator, city lights',
      );
      final cache = RecastScriptCache(
        scriptId: script.id,
        scriptName: script.name,
        sourceRootPath: script.rootPath,
        sourceFingerprint: _testSourceFingerprint(script),
        updatedAt: DateTime.utc(2026, 6, 20, 11),
        mapping: RecastMapping.defaults(script.id),
        scriptSnapshot: script.toJson(),
      );
      final hydrateStarted = Completer<void>();
      final hydratedScript = Completer<Script>();
      final hydrateCalls = <({Map<String, dynamic> snapshot, String? path})>[];
      final timings = <StudioScriptOpenTiming>[];
      final viewModel = StudioScriptViewModel(
        parserService: _ThrowingParserService(),
        loadRecastCacheByScriptId: (scriptId) async {
          return scriptId == script.id ? cache : null;
        },
        hydrateCachedScriptSnapshot: ({
          required Map<String, dynamic> scriptSnapshot,
          String? importPath,
        }) {
          hydrateCalls.add((snapshot: scriptSnapshot, path: importPath));
          if (!hydrateStarted.isCompleted) {
            hydrateStarted.complete();
          }
          return hydratedScript.future;
        },
        openTimingSink: timings.add,
      );

      final openFuture = viewModel.openScriptFromExhibition(
        scriptId: script.id,
        sourceFolder: script.rootPath,
        frameIndex: 1,
      );
      await hydrateStarted.future.timeout(const Duration(milliseconds: 80));

      expect(hydrateCalls.single.path, script.rootPath);
      expect(viewModel.isImportingScript, isTrue);

      hydratedScript.complete(script);
      await openFuture.timeout(const Duration(milliseconds: 250));

      expect(viewModel.isImportingScript, isFalse);
      expect(viewModel.frameCount, 1);
      expect(viewModel.selectedFrameIndex, 1);
      expect(
        timings.map((timing) => timing.stage),
        containsAllInOrder([
          'load-cache',
          'hydrate-cache-snapshot',
          'apply-cache',
          'complete-cache-hit',
        ]),
      );
    });

    test('opens exhibition cache through direct snapshot restore', () async {
      final script = _singleFrameScript(
        id: 'script-exhibition-direct-restore',
        name: 'Exhibition Direct Restore',
        rootPath: r'C:\scripts\exhibition-direct-restore',
        baseCaption: 'artist:direct-restore, city lights',
      );
      final cache = RecastScriptCache(
        scriptId: script.id,
        scriptName: script.name,
        sourceRootPath: script.rootPath,
        sourceFingerprint: _testSourceFingerprint(script),
        updatedAt: DateTime.utc(2026, 6, 27, 11),
        mapping: RecastMapping.defaults(script.id),
        scriptSnapshot: const {},
      );
      var directRestoreCalls = 0;
      var mapHydratorCalls = 0;
      final timings = <StudioScriptOpenTiming>[];
      final viewModel = StudioScriptViewModel(
        parserService: _ThrowingParserService(),
        loadRecastCacheByScriptId: (_) async {
          throw StateError('Full cache loader should not be used.');
        },
        restoreRecastCacheSnapshotByScriptId: ({
          required String scriptId,
          String? importPath,
        }) async {
          directRestoreCalls += 1;
          expect(scriptId, script.id);
          expect(importPath, script.rootPath);
          return RecastScriptCacheSnapshotRestore(
            cache: cache,
            script: script,
          );
        },
        hydrateCachedScriptSnapshot: ({
          required Map<String, dynamic> scriptSnapshot,
          String? importPath,
        }) {
          mapHydratorCalls += 1;
          throw StateError('Map snapshot hydrator should not be used.');
        },
        openTimingSink: timings.add,
      );

      await viewModel.openScriptFromExhibition(
        scriptId: script.id,
        sourceFolder: script.rootPath,
        frameIndex: 1,
      );

      expect(directRestoreCalls, 1);
      expect(mapHydratorCalls, 0);
      expect(viewModel.frameCount, 1);
      expect(viewModel.folderStatus, contains('Exhibition Direct Restore'));
      expect(viewModel.selectedFrameIndex, 1);
      expect(
        timings.map((timing) => timing.stage),
        containsAllInOrder([
          'load-cache',
          'hydrate-cache-snapshot',
          'apply-cache',
          'complete-cache-hit',
        ]),
      );
    });

    test('opens exhibition cache without rebuilding preview twice', () async {
      final script = _singleFrameScript(
        id: 'script-exhibition-single-preview',
        name: 'Exhibition Single Preview',
        rootPath: r'C:\scripts\exhibition-single-preview',
        baseCaption: 'artist:single-preview, city lights',
      );
      final cache = RecastScriptCache(
        scriptId: script.id,
        scriptName: script.name,
        sourceRootPath: script.rootPath,
        sourceFingerprint: _testSourceFingerprint(script),
        updatedAt: DateTime.utc(2026, 6, 27, 10),
        mapping: RecastMapping.defaults(script.id),
        scriptSnapshot: script.toJson(),
      );
      final engine = _CountingRecastEngine();
      final viewModel = StudioScriptViewModel(
        parserService: _ThrowingParserService(),
        recastEngine: engine,
        loadRecastCacheByScriptId: (scriptId) async {
          return scriptId == script.id ? cache : null;
        },
      );

      await viewModel.openScriptFromExhibition(
        scriptId: script.id,
        sourceFolder: script.rootPath,
        frameIndex: 1,
      );

      expect(engine.frameResolveCallCount, 1);
      expect(viewModel.frameCount, 1);
      expect(viewModel.selectedFrameIndex, 1);
    });

    test(
      'restores named cache when current PNG path only has an empty stub',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'studio-script-empty-stub-cache-',
        );
        addTearDown(() async {
          if (await tempRoot.exists()) {
            await tempRoot.delete(recursive: true);
          }
        });
        final importDir = Directory(
          '${tempRoot.path}${Platform.pathSeparator}Moved Script',
        );
        await importDir.create(recursive: true);
        await File(
          '${importDir.path}${Platform.pathSeparator}p000.png',
        ).writeAsBytes(const [137, 80, 78, 71]);
        final importScriptId =
            ScriptRecastParserService.scriptIdForDirectory(importDir);
        final emptyScript = Script(
          id: importScriptId,
          name: 'Moved Script',
          rootPath: importDir.path,
          frames: const [],
          detectedSchema: ScriptSchema.unknown,
          parseWarnings: const [
            'No prompt-bearing JSON or PNG script frames found in this directory.',
          ],
        );
        final emptyStub = RecastScriptCache(
          scriptId: importScriptId,
          scriptName: emptyScript.name,
          sourceRootPath: emptyScript.rootPath,
          sourceFingerprint: 'empty-stub',
          sourceContentFingerprint: 'schema:unknown|frames:0',
          updatedAt: DateTime.utc(2026, 6, 10, 9),
          mapping: RecastMapping.defaults(importScriptId),
          scriptSnapshot: emptyScript.toJson(),
        );
        final readyScript = _singleFrameScript(
          id: 'script-old-path',
          name: 'Moved Script',
          rootPath: r'E:\codeximage\ntr-story-cache-source\Moved Script',
          baseCaption: 'artist:moved-cache, city lights',
        );
        final readyCache = RecastScriptCache(
          scriptId: readyScript.id,
          scriptName: readyScript.name,
          sourceRootPath: readyScript.rootPath,
          sourceFingerprint: _testSourceFingerprint(readyScript),
          updatedAt: DateTime.utc(2026, 6, 10, 8),
          mapping: RecastMapping.defaults(readyScript.id),
          aiRoleExtraction: const ScriptAiRoleExtraction(
            status: ScriptAiRoleExtractionStatus.ready,
            roles: [
              ScriptAiExtractedRole(
                sourceRoleId: 'slot-0',
                displayName: 'Recovered AI Hero',
              ),
            ],
          ),
          scriptSnapshot: readyScript.toJson(),
        );
        var bulkLoadCount = 0;
        final viewModel = StudioScriptViewModel(
          parserService: _ThrowingParserService(),
          loadRecastCacheByScriptId: (scriptId) async {
            expect(scriptId, importScriptId);
            return emptyStub;
          },
          loadRecastCaches: () async {
            bulkLoadCount += 1;
            return [emptyStub, readyCache];
          },
        );

        await viewModel.importScriptPath(importDir.path);

        expect(bulkLoadCount, 1);
        expect(viewModel.frameCount, 1);
        expect(
          viewModel.aiRoleExtraction.status,
          ScriptAiRoleExtractionStatus.ready,
        );
        expect(
          viewModel.aiRoleExtraction.roles.single.displayName,
          'Recovered AI Hero',
        );
      },
    );

    test(
      'restores named cache for non-ASCII PNG path when single-cache misses',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp(
          'studio-script-nonascii-cache-miss-',
        );
        addTearDown(() async {
          if (await tempRoot.exists()) {
            await tempRoot.delete(recursive: true);
          }
        });
        final importDir = Directory(
          '${tempRoot.path}${Platform.pathSeparator}モナ 合并',
        );
        await importDir.create(recursive: true);
        await File(
          '${importDir.path}${Platform.pathSeparator}p000.png',
        ).writeAsBytes(const [137, 80, 78, 71]);
        final readyScript = _singleFrameScript(
          id: 'script-alias-path',
          name: 'モナ 合并',
          rootPath: r'E:\codeximage\ntr-story-cache-source\モナ 合并',
          baseCaption: 'artist:nonascii-cache, city lights',
        );
        final readyCache = RecastScriptCache(
          scriptId: readyScript.id,
          scriptName: readyScript.name,
          sourceRootPath: readyScript.rootPath,
          sourceFingerprint: _testSourceFingerprint(readyScript),
          updatedAt: DateTime.utc(2026, 6, 10, 8),
          mapping: RecastMapping.defaults(readyScript.id),
          scriptSnapshot: readyScript.toJson(),
        );
        var bulkLoadCount = 0;
        final viewModel = StudioScriptViewModel(
          parserService: _ThrowingParserService(),
          loadRecastCacheByScriptId: (_) async => null,
          loadRecastCaches: () async {
            bulkLoadCount += 1;
            return [readyCache];
          },
        );

        await viewModel.importScriptPath(importDir.path);

        expect(bulkLoadCount, 1);
        expect(viewModel.frameCount, 1);
        expect(viewModel.folderStatus, contains('モナ 合并'));
      },
    );

    test('rebases restored named cache image paths to current import directory',
        () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'studio-script-rebased-cache-paths-',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
      final importDir = Directory(
        '${tempRoot.path}${Platform.pathSeparator}Moved Story',
      );
      await importDir.create(recursive: true);
      final jsonFile = File(
        '${importDir.path}${Platform.pathSeparator}nai_1.json',
      );
      final imageFile = File(
        '${importDir.path}${Platform.pathSeparator}nai_1.png',
      );
      await jsonFile.writeAsString('{"Description":"blue eyes"}');
      await imageFile.writeAsBytes(const [137, 80, 78, 71]);

      const oldRoot = r'E:\old-cache-root\Moved Story';
      final oldScript = Script(
        id: 'script-old-cache-root',
        name: 'Moved Story',
        rootPath: oldRoot,
        frames: const [
          ScriptFrame(
            index: 1,
            fileName: 'nai_1.json',
            sourcePath: r'E:\old-cache-root\Moved Story\nai_1.json',
            sourceImagePath: r'E:\old-cache-root\Moved Story\nai_1.png',
            rawJson: '{"Description":"blue eyes"}',
            parsed: ParsedFrame(baseCaption: 'blue eyes'),
            detectedSchema: ScriptSchema.baseInline,
            parseStatus: ScriptFrameParseStatus.parsed,
          ),
        ],
        detectedSchema: ScriptSchema.baseInline,
      );
      final readyCache = RecastScriptCache(
        scriptId: oldScript.id,
        scriptName: oldScript.name,
        sourceRootPath: oldScript.rootPath,
        sourceFingerprint: _testSourceFingerprint(oldScript),
        updatedAt: DateTime.utc(2026, 6, 10, 8),
        mapping: RecastMapping.defaults(oldScript.id),
        scriptSnapshot: oldScript.toJson(),
      );
      RecastScriptCache? savedCache;
      final viewModel = StudioScriptViewModel(
        parserService: _ThrowingParserService(),
        loadRecastCacheByScriptId: (_) async => null,
        loadRecastCaches: () async => [readyCache],
        saveRecastCache: (cache) async {
          savedCache = cache;
        },
      );

      await viewModel.importScriptPath(importDir.path);
      await viewModel.collapseAiRoleExtractionDraft();

      final saved = savedCache;
      expect(saved, isNotNull);
      expect(
        saved!.scriptId,
        ScriptRecastParserService.scriptIdForDirectory(importDir),
      );
      expect(saved.sourceRootPath, importDir.path);
      final snapshot = Script.fromJson(saved.scriptSnapshot);
      expect(snapshot.rootPath, importDir.path);
      expect(snapshot.frames.single.sourcePath, jsonFile.path);
      expect(snapshot.frames.single.sourceImagePath, imageFile.path);
    });

    test('does not save empty PNG script snapshots as recast cache', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'studio-script-empty-png-snapshot-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      await File(
        '${tempDir.path}${Platform.pathSeparator}p000.png',
      ).writeAsBytes(const [137, 80, 78, 71]);
      final script = Script(
        id: ScriptRecastParserService.scriptIdForDirectory(tempDir),
        name: 'empty png snapshot',
        rootPath: tempDir.path,
        frames: const [],
        detectedSchema: ScriptSchema.unknown,
        parseWarnings: const [
          'No prompt-bearing JSON or PNG script frames found in this directory.',
        ],
      );
      RecastScriptCache? savedCache;
      final viewModel = StudioScriptViewModel(
        parserService: _FakeParserService([script]),
        loadCharacters: () async => const [],
        loadArtistChains: () async => const [],
        loadVibes: () async => const [],
        loadRecastCacheByScriptId: (_) async => null,
        saveRecastCache: (cache) async {
          savedCache = cache;
        },
      );

      await viewModel.importScriptPath(tempDir.path);

      expect(viewModel.frameCount, 0);
      expect(savedCache, isNull);
    });

    test(
      'saves PNG script snapshots without scanning all recast caches',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'studio-script-single-cache-save-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
        await File(
          '${tempDir.path}${Platform.pathSeparator}p000.png',
        ).writeAsBytes(const [137, 80, 78, 71]);
        final script = _singleFrameScript(
          id: ScriptRecastParserService.scriptIdForDirectory(tempDir),
          name: 'single cache save script',
          rootPath: tempDir.path,
          baseCaption: 'artist:single-cache-save, city lights',
        );
        var targetedLoadCount = 0;
        var bulkLoadCount = 0;
        RecastScriptCache? savedCache;
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadCharacters: () async => const [],
          loadArtistChains: () async => const [],
          loadVibes: () async => const [],
          loadRecastCacheByScriptId: (scriptId) async {
            targetedLoadCount += 1;
            return null;
          },
          saveRecastCache: (cache) async {
            savedCache = cache;
          },
          loadRecastCaches: () async {
            bulkLoadCount += 1;
            return const <RecastScriptCache>[];
          },
        );

        await viewModel.importScriptPath(tempDir.path);

        expect(savedCache, isNotNull);
        expect(targetedLoadCount, greaterThanOrEqualTo(1));
        expect(bulkLoadCount, 0);
      },
    );

    test(
      'keeps multiple artist chain candidates available in drawer',
      () async {
        final viewModel = StudioScriptViewModel(
          loadArtistChains: () async => const [
            ArtistChain(
              id: 'artist-1',
              name: 'artist 1',
              prompt: 'artist:first',
            ),
            ArtistChain(
              id: 'artist-2',
              name: 'artist 2',
              prompt: 'artist:second',
            ),
          ],
        );

        await viewModel.importScriptPath(_fixturePath);

        expect(viewModel.artistChainOptions, hasLength(2));
        expect(viewModel.artistMappings, hasLength(1));
        expect(viewModel.artistChainOptions.map((chain) => chain.prompt), [
          'artist:first',
          'artist:second',
        ]);
      },
    );

    test(
      'role mappings expose friendly labels without default outfit stages',
      () async {
        final viewModel = StudioScriptViewModel();

        await viewModel.importScriptPath(_fixturePath);

        expect(viewModel.roleMappings.first.sourceLabel, '瑙掕壊 1');
        expect(viewModel.roleMappings.first.stageItems, isEmpty);
        expect(viewModel.roleMappings.first.sourceRoleId, 'slot-0');
      },
    );

    test(
      'refreshes stale automatic role assemblies restored from cache',
      () async {
        var caches = <RecastScriptCache>[];
        final seedViewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );
        await seedViewModel.importScriptPath(_fixturePath);
        await seedViewModel.useFreshParseForChangedSource();
        final cache = caches.single;
        caches = [
          RecastScriptCache(
            scriptId: cache.scriptId,
            scriptName: cache.scriptName,
            sourceRootPath: cache.sourceRootPath,
            sourceFingerprint: cache.sourceFingerprint,
            updatedAt: cache.updatedAt,
            mapping: cache.mapping.copyWith(
              roleAssemblies: const [
                RoleAssembly(
                  sourceRoleId: 'slot-0',
                  displayLabel: '瑙掕壊 1',
                  sourceName: 'official style',
                  stages: [
                    RoleAssemblyStage(
                      id: 'main-outfit',
                      label: '鏈嶈 1',
                      frameIndexes: [1],
                      sourceSummary: 'pov hands',
                    ),
                    RoleAssemblyStage(
                      id: 'slot-0-stage-2',
                      label: '鏈嶈 2',
                      frameIndexes: [2],
                      sourceSummary: 'dynamic pose',
                    ),
                  ],
                ),
              ],
            ),
            scriptSnapshot: cache.scriptSnapshot,
          ),
        ];

        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );

        await viewModel.importScriptPath(_fixturePath);

        expect(viewModel.roleMappings.first.sourcePreview, 'unknown');
        expect(viewModel.roleMappings.first.stageItems, isEmpty);
      },
    );

    test(
      'restored cache drops stale local default stage mixed with ai stages',
      () async {
        var caches = <RecastScriptCache>[];
        final seedViewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );
        await seedViewModel.importScriptPath(_fixturePath);
        await seedViewModel.useFreshParseForChangedSource();
        final cache = caches.single;
        caches = [
          RecastScriptCache(
            scriptId: cache.scriptId,
            scriptName: cache.scriptName,
            sourceRootPath: cache.sourceRootPath,
            sourceFingerprint: cache.sourceFingerprint,
            updatedAt: cache.updatedAt,
            mapping: cache.mapping.copyWith(
              roleAssemblies: const [
                RoleAssembly(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'Ako (Dress) Blue Archive',
                  sourceName: 'Ako (Dress) Blue Archive',
                  stages: [
                    RoleAssemblyStage(
                      id: 'main-outfit',
                      label: '服装 1',
                      frameIndexes: [1, 2, 3],
                      sourceParts: RecastPromptParts(upperBody: 'top-down'),
                    ),
                    RoleAssemblyStage(
                      id: 'see-through-dress',
                      label: '透视连衣裙',
                      frameIndexes: [1, 2],
                      sourceParts: RecastPromptParts(
                        lowerClothing: 'see-through dress',
                      ),
                    ),
                    RoleAssemblyStage(
                      id: 'dress',
                      label: '连衣裙',
                      frameIndexes: [3],
                      sourceParts: RecastPromptParts(lowerClothing: 'dress'),
                    ),
                  ],
                ),
              ],
            ),
            scriptSnapshot: cache.scriptSnapshot,
          ),
        ];
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );

        await viewModel.importScriptPath(_fixturePath);

        final stages = viewModel.roleMappings.first.stageItems;
        expect(stages.map((stage) => stage.id), ['see-through-dress', 'dress']);
        expect(stages.map((stage) => stage.label), isNot(contains('服装 1')));
      },
    );

    test(
      'restored cache prunes empty slot assemblies mixed with ai roles',
      () async {
        var caches = <RecastScriptCache>[];
        final seedViewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );
        await seedViewModel.importScriptPath(_fixturePath);
        await seedViewModel.useFreshParseForChangedSource();
        final cache = caches.single;
        caches = [
          RecastScriptCache(
            scriptId: cache.scriptId,
            scriptName: cache.scriptName,
            sourceRootPath: cache.sourceRootPath,
            sourceFingerprint: cache.sourceFingerprint,
            updatedAt: cache.updatedAt,
            mapping: cache.mapping.copyWith(
              roleAssemblies: const [
                RoleAssembly(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'Slot 1',
                  sourceName: 'nude',
                ),
                RoleAssembly(
                  sourceRoleId: 'slot-1',
                  displayLabel: 'Slot 2',
                  sourceName: 'nagasaki soyo',
                ),
                RoleAssembly(
                  sourceRoleId: 'role-1',
                  displayLabel: 'Nagasaki Soyo',
                  sourceName: 'Nagasaki Soyo',
                  stages: [
                    RoleAssemblyStage(
                      id: 'stg-nagasaki-nude',
                      label: 'nude',
                      frameIndexes: [1, 2],
                      sourceParts: RecastPromptParts(identity: 'nagasaki soyo'),
                      manualParts: RecastPromptParts(
                        identity: 'papyrus_(arknights)',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            scriptSnapshot: cache.scriptSnapshot,
          ),
        ];
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );

        await viewModel.importScriptPath(_fixturePath);

        final roleIds =
            viewModel.roleMappings.map((role) => role.sourceRoleId).toList();
        expect(roleIds, isNot(contains('slot-0')));
        expect(roleIds, isNot(contains('slot-1')));
        expect(roleIds, contains('role-1'));
        final aiRole = viewModel.roleMappings.singleWhere(
          (role) => role.sourceRoleId == 'role-1',
        );
        expect(aiRole.stageItems.single.id, 'stg-nagasaki-nude');
      },
    );

    test(
      'restored ready AI cache materializes source fields over automatic split',
      () async {
        var caches = <RecastScriptCache>[];
        final seedViewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );
        await seedViewModel.importScriptPath(_fixturePath);
        await seedViewModel.useFreshParseForChangedSource();
        final baseCache = caches.single;
        caches = [
          RecastScriptCache(
            scriptId: baseCache.scriptId,
            scriptName: baseCache.scriptName,
            sourceRootPath: baseCache.sourceRootPath,
            sourceFingerprint: baseCache.sourceFingerprint,
            updatedAt: baseCache.updatedAt,
            mapping: RecastMapping.defaults(baseCache.scriptId),
            aiRoleExtraction: const ScriptAiRoleExtraction(
              status: ScriptAiRoleExtractionStatus.ready,
              roles: [
                ScriptAiExtractedRole(
                  sourceRoleId: 'role-cached-hero',
                  sourceKind: 'cross_slot',
                  displayName: 'cached hero',
                  appearances: [
                    ScriptAiRoleAppearance(
                      sourceId: 'slot-0',
                      sourceKind: 'slot',
                      frameIndexes: [1, 2],
                    ),
                  ],
                  stages: [
                    ScriptAiExtractedStage(
                      stageId: 'ai-main',
                      label: 'AI main',
                      frameIndexes: [1, 2],
                      identity: 'cached hero',
                      upperBody: 'brown hair',
                      upperClothing: 'blue jacket',
                      confidence: 0.95,
                    ),
                  ],
                ),
              ],
            ),
            scriptSnapshot: baseCache.scriptSnapshot,
          ),
        ];
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );

        await viewModel.importScriptPath(_fixturePath);

        final roleIds =
            viewModel.roleMappings.map((role) => role.sourceRoleId).toList();
        expect(roleIds, contains('role-cached-hero'));
        expect(roleIds, isNot(contains('slot-0')));
        final stage = viewModel.roleMappings
            .singleWhere((role) => role.sourceRoleId == 'role-cached-hero')
            .stageItems
            .single;
        expect(stage.sourceParts.identity, 'cached hero');
        expect(stage.sourceParts.upperBody, 'brown hair');
        expect(stage.sourceParts.upperClothing, 'blue jacket');
      },
    );

    test(
      'restored ready AI cache prunes stale generated edited stage',
      () async {
        var caches = <RecastScriptCache>[];
        final seedViewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );
        await seedViewModel.importScriptPath(_fixturePath);
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
                  sourceRoleId: 'role-soyo',
                  displayLabel: 'nagasaki soyo',
                  sourceName: 'nagasaki soyo',
                  stages: [
                    RoleAssemblyStage(
                      id: 'stage-1',
                      label: 'Stage 1',
                      frameIndexes: [2, 3],
                      sourceParts: RecastPromptParts(
                        identity: 'girl, nagasaki soyo',
                        lowerBody: 'barefoot',
                        upperClothing: 'wearing navy blue school uniform',
                      ),
                      targetCharacterId: 'target-papyrus',
                      targetUpperOutfitId: 'default-outfit',
                      manualParts: RecastPromptParts(upperBody: 'brown_hair'),
                    ),
                    RoleAssemblyStage(
                      id: 'stage-5',
                      label: 'Stage 5',
                      frameIndexes: [22],
                      sourceParts: RecastPromptParts(
                        identity: 'girl, nagasaki soyo',
                        upperClothing: 'wearing navy blue school uniform',
                      ),
                      targetCharacterId: 'target-papyrus',
                      targetUpperOutfitId: 'default-outfit',
                      manualParts: RecastPromptParts(upperBody: 'brown_hair'),
                    ),
                  ],
                ),
              ],
            ),
            aiRoleExtraction: const ScriptAiRoleExtraction(
              status: ScriptAiRoleExtractionStatus.ready,
              roles: [
                ScriptAiExtractedRole(
                  sourceRoleId: 'role-soyo',
                  sourceKind: 'cross_slot',
                  displayName: 'nagasaki soyo',
                  appearances: [
                    ScriptAiRoleAppearance(
                      sourceId: 'slot-0',
                      sourceKind: 'slot',
                      frameIndexes: [2, 3, 22],
                    ),
                  ],
                  stages: [
                    ScriptAiExtractedStage(
                      stageId: 'stage-1',
                      label: 'Stage 1',
                      frameIndexes: [2, 3, 22],
                      identity: 'girl, nagasaki soyo',
                      lowerBody: 'barefoot',
                      upperClothing: 'wearing navy blue school uniform',
                      nonRole: 'starting to take off her top',
                      nonRoleMaterialized: true,
                    ),
                  ],
                ),
              ],
            ),
            scriptSnapshot: baseCache.scriptSnapshot,
          ),
        ];
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );

        await viewModel.importScriptPath(_fixturePath);

        final role = viewModel.roleMappings.singleWhere(
          (role) => role.sourceRoleId == 'role-soyo',
        );
        expect(role.stageItems, hasLength(1));
        final stage = role.stageItems.single;
        expect(stage.id, 'stage-1');
        expect(stage.frameIndexes, [2, 3, 22]);
        expect(stage.sourceParts.lowerBody, 'barefoot');
        expect(
          stage.sourceParts.upperClothing,
          'wearing navy blue school uniform',
        );
        expect(stage.selectedCharacterId, 'target-papyrus');
        expect(stage.parts.upperBody, 'brown_hair');
      },
    );

    test(
      'restored ready AI cache migrates edited automatic stages to merged AI stage',
      () async {
        var caches = <RecastScriptCache>[];
        final seedViewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );
        await seedViewModel.importScriptPath(_fixturePath);
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
                  sourceRoleId: 'role-soyo',
                  displayLabel: 'nagasaki soyo',
                  sourceName: 'nagasaki soyo',
                  stages: [
                    RoleAssemblyStage(
                      id: 'stage-1',
                      label: 'Stage 1',
                      frameIndexes: [2, 3],
                      sourceParts: RecastPromptParts(
                        identity: 'girl, nagasaki soyo',
                        lowerBody: 'barefoot',
                        upperClothing: 'wearing navy blue school uniform',
                      ),
                      targetCharacterId: 'target-papyrus',
                      targetUpperOutfitId: 'default-outfit',
                      manualParts: RecastPromptParts(upperBody: 'brown_hair'),
                    ),
                    RoleAssemblyStage(
                      id: 'stage-5',
                      label: 'Stage 5',
                      frameIndexes: [22],
                      sourceParts: RecastPromptParts(
                        identity: 'girl, nagasaki soyo',
                        upperClothing: 'wearing navy blue school uniform',
                      ),
                      targetLowerOutfitId: 'barefoot-outfit',
                      manualParts: RecastPromptParts(
                        lowerClothing: 'custom_socks',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            aiRoleExtraction: const ScriptAiRoleExtraction(
              status: ScriptAiRoleExtractionStatus.ready,
              roles: [
                ScriptAiExtractedRole(
                  sourceRoleId: 'role-soyo',
                  sourceKind: 'cross_slot',
                  displayName: 'nagasaki soyo',
                  appearances: [
                    ScriptAiRoleAppearance(
                      sourceId: 'slot-0',
                      sourceKind: 'slot',
                      frameIndexes: [2, 3, 22],
                    ),
                  ],
                  stages: [
                    ScriptAiExtractedStage(
                      stageId: 'merged-ai-main',
                      label: 'Merged main',
                      frameIndexes: [2, 3, 22],
                      identity: 'girl, nagasaki soyo',
                      lowerBody: 'barefoot',
                      upperClothing: 'wearing navy blue school uniform',
                      nonRole: 'starting to take off her top',
                      nonRoleMaterialized: true,
                    ),
                  ],
                ),
              ],
            ),
            scriptSnapshot: baseCache.scriptSnapshot,
          ),
        ];
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );

        await viewModel.importScriptPath(_fixturePath);

        final role = viewModel.roleMappings.singleWhere(
          (role) => role.sourceRoleId == 'role-soyo',
        );
        expect(role.stageItems, hasLength(1));
        final stage = role.stageItems.single;
        expect(stage.id, 'merged-ai-main');
        expect(stage.selectedCharacterId, 'target-papyrus');
        expect(stage.selectedUpperOutfitId, 'default-outfit');
        expect(stage.selectedLowerOutfitId, 'barefoot-outfit');
        expect(stage.parts.upperBody, 'brown_hair');
        expect(stage.parts.lowerClothing, 'custom_socks');
      },
    );

    test(
      'restored ai role display uses confirmed source name as preview',
      () async {
        var caches = <RecastScriptCache>[];
        final seedViewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );
        await seedViewModel.importScriptPath(_fixturePath);
        await seedViewModel.useFreshParseForChangedSource();
        final cache = caches.single;
        caches = [
          RecastScriptCache(
            scriptId: cache.scriptId,
            scriptName: cache.scriptName,
            sourceRootPath: cache.sourceRootPath,
            sourceFingerprint: cache.sourceFingerprint,
            updatedAt: cache.updatedAt,
            mapping: cache.mapping.copyWith(
              roleAssemblies: const [
                RoleAssembly(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'Wakamo',
                  sourceName: 'Wakamo',
                  stages: [
                    RoleAssemblyStage(
                      id: 'main-outfit',
                      label: '姣斿熀灏间笂琛?',
                      frameIndexes: [1, 2],
                      sourceSummary: 'bikini top only, fox ears',
                    ),
                  ],
                ),
              ],
            ),
            scriptSnapshot: cache.scriptSnapshot,
          ),
        ];
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );

        await viewModel.importScriptPath(_fixturePath);

        expect(viewModel.roleMappings.first.sourceLabel, 'Wakamo');
        expect(viewModel.roleMappings.first.sourcePreview, 'Wakamo');
      },
    );

    test(
      'restored role source name is visible as source identity part',
      () async {
        final script = _singleFrameScript(
          id: 'hoshino-script',
          name: 'Hoshino Script',
          rootPath: r'C:\scripts\hoshino',
          baseCaption: 'classroom',
          charCaptions: const [
            'hoshino (blue archive), blue hair, school uniform',
          ],
        );
        var caches = [
          RecastScriptCache(
            scriptId: script.id,
            scriptName: script.name,
            sourceRootPath: script.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(script),
            updatedAt: DateTime.utc(2026, 6, 11),
            mapping: RecastMapping.defaults(script.id).copyWith(
              roleAssemblies: const [
                RoleAssembly(
                  sourceRoleId: 'role-hoshino',
                  displayLabel: 'hoshino (blue archive)',
                  sourceName: 'hoshino (blue archive)',
                  sourceAppearances: [
                    RoleAssemblySourceAppearance(
                      sourceId: 'slot-0',
                      sourceKind: 'slot',
                      frameIndexes: [1],
                    ),
                  ],
                ),
              ],
            ),
            scriptSnapshot: script.toJson(),
          ),
        ];
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
          loadCharacters: () async => const [
            CharacterEntry(
              id: 'replacement',
              name: 'Replacement',
              traits: ViewVariantTexts(frontFull: 'replacement_hero, red eyes'),
              anchorTags: ['replacement_hero'],
              identityTags: ['red eyes'],
            ),
          ],
          loadArtistChains: () async => const [],
        );

        await viewModel.importScriptPath(script.rootPath);

        final role = viewModel.roleMappings.single;
        final stage = role.stageItems.single;
        expect(role.sourcePreview, 'hoshino (blue archive)');
        expect(stage.id, 'role-hoshino-source-stage');
        expect(stage.frameIndexes, [1]);
        expect(stage.sourceParts.identity, 'hoshino (blue archive)');

        viewModel.setRoleCharacter(role.sourceRoleId, 'replacement');

        expect(viewModel.diff.recast, contains('replacement_hero'));
        expect(viewModel.diff.recast, isNot(contains('hoshino')));
        expect(viewModel.diff.recast, isNot(contains('blue archive')));
      },
    );

    test(
      'restored AI extraction stages are materialized when cache mapping has appearances only',
      () async {
        final script = _singleFrameScript(
          id: 'hoshino-ai-stage-script',
          name: 'Hoshino AI Stage Script',
          rootPath: r'C:\scripts\hoshino-ai-stage',
          baseCaption: 'classroom',
          charCaptions: const [
            'hoshino (blue archive), white shirt, black skirt',
          ],
        );
        var caches = [
          RecastScriptCache(
            scriptId: script.id,
            scriptName: script.name,
            sourceRootPath: script.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(script),
            updatedAt: DateTime.utc(2026, 6, 11),
            mapping: RecastMapping.defaults(script.id).copyWith(
              roleAssemblies: const [
                RoleAssembly(
                  sourceRoleId: 'role-hoshino-blue-archive',
                  displayLabel: 'hoshino (blue archive)',
                  sourceName: 'hoshino (blue archive)',
                  sourceAppearances: [
                    RoleAssemblySourceAppearance(
                      sourceId: 'slot-0',
                      sourceKind: 'slot',
                      frameIndexes: [1],
                    ),
                  ],
                ),
              ],
            ),
            aiRoleExtraction: const ScriptAiRoleExtraction(
              status: ScriptAiRoleExtractionStatus.ready,
              confidence: 0.9,
              roles: [
                ScriptAiExtractedRole(
                  sourceRoleId: 'role-hoshino-blue-archive',
                  displayName: 'hoshino (blue archive)',
                  appearances: [
                    ScriptAiRoleAppearance(
                      sourceId: 'slot-0',
                      sourceKind: 'slot',
                      frameIndexes: [1],
                    ),
                  ],
                  stages: [
                    ScriptAiExtractedStage(
                      stageId: 'role-hoshino-blue-archive-stage-1',
                      label: '校服',
                      frameIndexes: [1],
                      identity: 'hoshino (blue archive)',
                      upperClothing: 'white shirt',
                      lowerClothing: 'black skirt',
                    ),
                  ],
                ),
              ],
            ),
            aiRoleExtractionDraftCollapsed: true,
            scriptSnapshot: script.toJson(),
          ),
        ];
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
          loadCharacters: () async => const [],
          loadArtistChains: () async => const [],
        );

        await viewModel.importScriptPath(script.rootPath);

        final role = viewModel.roleMappings.single;
        final stage = role.stageItems.single;
        expect(role.sourceLabel, 'hoshino (blue archive)');
        expect(stage.id, 'role-hoshino-blue-archive-stage-1');
        expect(stage.sourceParts.identity, 'hoshino (blue archive)');
        expect(stage.sourceParts.upperClothing, 'white shirt');
        expect(stage.sourceParts.lowerClothing, 'black skirt');
      },
    );

    test(
      'restored source stage with local default id is not pruned when it has source fields',
      () async {
        final script = _singleFrameScript(
          id: 'hoshino-default-stage-script',
          name: 'Hoshino Default Stage Script',
          rootPath: r'C:\scripts\hoshino-default-stage',
          baseCaption: 'classroom',
          charCaptions: const [
            'hoshino (blue archive), blue hair, school uniform',
          ],
        );
        var caches = [
          RecastScriptCache(
            scriptId: script.id,
            scriptName: script.name,
            sourceRootPath: script.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(script),
            updatedAt: DateTime.utc(2026, 6, 11),
            mapping: RecastMapping.defaults(script.id).copyWith(
              roleAssemblies: const [
                RoleAssembly(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'hoshino (blue archive)',
                  sourceName: 'hoshino (blue archive)',
                  stages: [
                    RoleAssemblyStage(
                      id: 'slot-0-stage-1',
                      label: 'main outfit',
                      frameIndexes: [1],
                      sourceSummary: 'hoshino (blue archive)',
                      sourceParts: RecastPromptParts(
                        identity: 'hoshino (blue archive)',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            scriptSnapshot: script.toJson(),
          ),
        ];
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
          loadCharacters: () async => const [],
          loadArtistChains: () async => const [],
        );

        await viewModel.importScriptPath(script.rootPath);

        final stage = viewModel.roleMappings.single.stageItems.single;
        expect(stage.id, 'slot-0-stage-1');
        expect(stage.sourceParts.identity, 'hoshino (blue archive)');
      },
    );

    test('manual role part edits update preview payload', () async {
      final viewModel = StudioScriptViewModel(
        loadCharacters: () async => const [
          CharacterEntry(
            id: 'char-hero',
            name: 'library character',
            traits: ViewVariantTexts(frontFull: 'green eyes'),
            anchorTags: ['library_hero'],
          ),
        ],
      );

      await viewModel.importScriptPath(_fixturePath);
      viewModel.setRoleCharacter('slot-0', 'char-hero');
      viewModel.setRoleStagePart(
        sourceRoleId: 'slot-0',
        stageId: viewModel.roleMappings.first.stageItems.first.id,
        part: StudioScriptRolePart.upperClothing,
        value: 'custom cape',
      );

      expect(viewModel.diff.recast, contains('custom cape'));
      expect(
        viewModel.roleMappings.first.stageItems.first.parts.upperClothing,
        'custom cape',
      );
    });

    test('batched manual role part edits notify once', () async {
      var caches = <RecastScriptCache>[];
      final seedViewModel = StudioScriptViewModel(
        loadRecastCaches: () async => caches,
        saveRecastCaches: (next) async => caches = next,
      );
      await seedViewModel.importScriptPath(_fixturePath);
      await seedViewModel.useFreshParseForChangedSource();
      final cache = caches.single;
      caches = [
        RecastScriptCache(
          scriptId: cache.scriptId,
          scriptName: cache.scriptName,
          sourceRootPath: cache.sourceRootPath,
          sourceFingerprint: cache.sourceFingerprint,
          updatedAt: cache.updatedAt,
          mapping: cache.mapping.copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'slot-0',
                displayLabel: 'Wakamo',
                sourceName: 'Wakamo',
                stages: [
                  RoleAssemblyStage(
                    id: 'main-outfit',
                    label: 'Main outfit',
                    frameIndexes: [1, 2],
                  ),
                ],
              ),
            ],
          ),
          scriptSnapshot: cache.scriptSnapshot,
        ),
      ];
      final viewModel = StudioScriptViewModel(
        loadRecastCaches: () async => caches,
        saveRecastCaches: (next) async => caches = next,
      );

      await viewModel.importScriptPath(_fixturePath);
      final role = viewModel.roleMappings.single;
      final stageId = role.stageItems.first.id;
      var notifications = 0;
      viewModel.addListener(() {
        notifications += 1;
      });

      viewModel.batchRoleStageEdits(() {
        viewModel.setRoleStagePart(
          sourceRoleId: role.sourceRoleId,
          stageId: stageId,
          part: StudioScriptRolePart.upperClothing,
          value: 'cat ears',
        );
        viewModel.setRoleStagePart(
          sourceRoleId: role.sourceRoleId,
          stageId: stageId,
          part: StudioScriptRolePart.lowerClothing,
          value: 'cat tail',
        );
      });

      expect(notifications, 1);
      final stage = viewModel.roleMappings
          .where((candidate) => candidate.sourceRoleId == role.sourceRoleId)
          .single
          .stageItems
          .where((candidate) => candidate.id == stageId)
          .single;
      expect(stage.parts.upperClothing, 'cat ears');
      expect(stage.parts.lowerClothing, 'cat tail');
    });

    test('manual role output edits persist to cache after debounce', () async {
      var caches = <RecastScriptCache>[];
      final viewModel = StudioScriptViewModel(
        loadRecastCaches: () async => caches,
        saveRecastCaches: (next) async => caches = next,
      );

      await viewModel.importScriptPath(_fixturePath);
      final role = viewModel.roleMappings.firstWhere(
        (candidate) => candidate.selectedStage != null,
      );
      final stageId = role.stageItems.first.id;
      viewModel.setRoleStagePart(
        sourceRoleId: role.sourceRoleId,
        stageId: stageId,
        part: StudioScriptRolePart.upperClothing,
        value: 'cat ears, fox ears',
      );
      viewModel.setRoleStagePart(
        sourceRoleId: role.sourceRoleId,
        stageId: stageId,
        part: StudioScriptRolePart.upperClothing,
        value: 'fox ears',
      );

      await Future<void>.delayed(const Duration(milliseconds: 650));

      expect(caches, hasLength(1));
      final cachedStage = caches.single.mapping.roleAssemblies
          .where((assembly) => assembly.sourceRoleId == role.sourceRoleId)
          .single
          .stages
          .where((stage) => stage.id == stageId)
          .single;
      expect(cachedStage.manualParts.upperClothing, 'fox ears');

      final restored = StudioScriptViewModel(
        loadRecastCaches: () async => caches,
        saveRecastCaches: (next) async => caches = next,
      );
      await restored.importScriptPath(_fixturePath);

      final restoredStage = restored.roleMappings.first.stageItems
          .where((stage) => stage.id == stageId)
          .single;
      expect(restoredStage.parts.upperClothing, 'fox ears');
    });

    test(
      'role replacement removes the visible detected source identity',
      () async {
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => const [
            CharacterEntry(
              id: 'char-hero',
              name: 'library character',
              traits: ViewVariantTexts(frontFull: 'green eyes'),
              anchorTags: ['library_hero'],
              identityTags: ['green eyes'],
            ),
          ],
        );

        await viewModel.importScriptPath(_fixturePath);
        final role = viewModel.roleMappings.first;
        final sourceIdentity = role.sourcePreview.trim();
        expect(sourceIdentity, isNotEmpty);

        viewModel.setRoleCharacter(role.sourceRoleId, 'char-hero');

        expect(viewModel.diff.recast, contains('library_hero'));
        expect(viewModel.diff.recast, isNot(contains(sourceIdentity)));
      },
    );

    test('empty role part edits keep source blocks unchanged', () async {
      final viewModel = StudioScriptViewModel(
        loadCharacters: () async => const [
          CharacterEntry(
            id: 'char-hero',
            name: 'library character',
            traits: ViewVariantTexts(
              frontFull: 'green eyes',
              frontUpper: 'green eyes, long hair',
              frontLower: 'short skirt',
            ),
            anchorTags: ['library_hero'],
            identityTags: ['green eyes'],
          ),
        ],
        scriptAiRoleExtractionService: const _FakeRoleExtractionService(
          _highConfidenceSlotExtraction,
        ),
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );

      await viewModel.importScriptPath(_fixturePath);
      await viewModel.generateAiRoleExtraction();
      await viewModel.applyHighConfidenceAiRoleExtraction();
      viewModel.setRoleCharacter('slot-0', 'char-hero');
      final stageId = viewModel.roleMappings.first.stageItems.first.id;

      viewModel.setRoleStagePart(
        sourceRoleId: 'slot-0',
        stageId: stageId,
        part: StudioScriptRolePart.identity,
        value: '',
      );
      viewModel.setRoleStagePart(
        sourceRoleId: 'slot-0',
        stageId: stageId,
        part: StudioScriptRolePart.upperBody,
        value: '',
      );

      var stage = viewModel.roleMappings.first.stageItems.first;
      expect(stage.parts.identity, isEmpty);
      expect(stage.parts.upperBody, isEmpty);
      expect(stage.omittedParts, isNot(contains(RecastPromptPart.identity)));
      expect(stage.omittedParts, isNot(contains(RecastPromptPart.upperBody)));
      expect(viewModel.diff.recast, contains('vulpisfoglia_(arknights)'));
      expect(viewModel.diff.recast, isNot(contains('library_hero')));

      viewModel.setRoleStagePart(
        sourceRoleId: 'slot-0',
        stageId: stageId,
        part: StudioScriptRolePart.identity,
        value: 'manual heroine',
      );

      stage = viewModel.roleMappings.first.stageItems.first;
      expect(stage.parts.identity, 'manual heroine');
      expect(stage.omittedParts, isNot(contains(RecastPromptPart.identity)));
      expect(stage.omittedParts, isNot(contains(RecastPromptPart.upperBody)));
    });

    test('explicit role part deletion marks only that block omitted', () async {
      final viewModel = StudioScriptViewModel(
        loadCharacters: () async => const [
          CharacterEntry(
            id: 'char-hero',
            name: 'library character',
            traits: ViewVariantTexts(frontFull: 'green eyes'),
            anchorTags: ['library_hero'],
            identityTags: ['green eyes'],
          ),
        ],
        scriptAiRoleExtractionService: const _FakeRoleExtractionService(
          _highConfidenceSlotExtraction,
        ),
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );

      await viewModel.importScriptPath(_fixturePath);
      await viewModel.generateAiRoleExtraction();
      await viewModel.applyHighConfidenceAiRoleExtraction();
      viewModel.setRoleCharacter('slot-0', 'char-hero');
      final stageId = viewModel.roleMappings.first.stageItems.first.id;

      viewModel.setRoleStagePartDeleted(
        sourceRoleId: 'slot-0',
        stageId: stageId,
        part: StudioScriptRolePart.identity,
        deleted: true,
      );

      var stage = viewModel.roleMappings.first.stageItems.first;
      expect(stage.parts.identity, isEmpty);
      expect(stage.omittedParts, contains(RecastPromptPart.identity));
      expect(stage.omittedParts, isNot(contains(RecastPromptPart.upperBody)));

      viewModel.setRoleStagePartDeleted(
        sourceRoleId: 'slot-0',
        stageId: stageId,
        part: StudioScriptRolePart.identity,
        deleted: false,
      );

      stage = viewModel.roleMappings.first.stageItems.first;
      expect(stage.omittedParts, isNot(contains(RecastPromptPart.identity)));
    });

    test(
      'style and quality prompt blocks can replace and delete source terms',
      () async {
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([
            _singleFrameScript(
              id: 'prompt-block-script',
              rootPath: 'prompt-block-script',
              baseCaption:
                  'masterpiece, best quality, official style, city_lights',
            ),
          ]),
        );

        await viewModel.importScriptPath('prompt-block-script');
        viewModel.setPromptBlockSource('style', 'official style');
        viewModel.setPromptBlockSource('quality', 'masterpiece, best quality');

        viewModel.setPromptBlockManualPrompt('style', 'watercolor');
        viewModel.setPromptBlockDeleted('quality', true);

        expect(viewModel.diff.recast, contains('watercolor'));
        expect(viewModel.diff.recast, contains('city_lights'));
        expect(viewModel.diff.recast, isNot(contains('official style')));
        expect(viewModel.diff.recast, isNot(contains('masterpiece')));
        expect(viewModel.diff.recast, isNot(contains('best quality')));

        viewModel.setPromptBlockManualPrompt('style', '');
        viewModel.setPromptBlockDeleted('quality', false);

        expect(viewModel.diff.recast, contains('official style'));
        expect(viewModel.diff.recast, contains('masterpiece'));
        expect(viewModel.diff.recast, contains('best quality'));
      },
    );

    test(
      'artist source can be explicitly deleted without replacement',
      () async {
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([
            _singleFrameScript(
              id: 'artist-delete-script',
              rootPath: 'artist-delete-script',
              baseCaption: 'arato_asato, artist:old_painter, city_lights',
            ),
          ]),
        );

        await viewModel.importScriptPath('artist-delete-script');
        viewModel.setArtistSourceLabel('arato_asato, artist:old_painter');
        viewModel.setArtistSourceDeleted(true);

        expect(viewModel.diff.recast, contains('city_lights'));
        expect(viewModel.diff.recast, isNot(contains('arato_asato')));
        expect(viewModel.diff.recast, isNot(contains('old_painter')));

        viewModel.setArtistSourceDeleted(false);

        expect(viewModel.diff.recast, contains('arato_asato'));
        expect(viewModel.diff.recast, contains('artist:old_painter'));
      },
    );

    test(
      'dragged character traits use pre-split body and clothing fields',
      () async {
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => const [
            CharacterEntry(
              id: 'char-hero',
              name: 'library character',
              traits: ViewVariantTexts(
                frontFull: 'library_hero, shirt-shaped birthmark, '
                    'white shirt, skirt-shaped tail ornament, black skirt',
                frontUpper: 'shirt-shaped birthmark, white shirt',
                frontLower: 'skirt-shaped tail ornament, black skirt',
              ),
              anchorTags: ['library_hero'],
              identityTags: [
                'library_hero',
                'actual identity',
                'shirt-shaped birthmark',
                'white shirt',
                'skirt-shaped tail ornament',
                'black skirt',
              ],
              defaultOutfitId: 'default',
              outfits: [
                WorkspaceOutfit(
                  id: 'default',
                  name: 'Default',
                  tags: ViewVariantTexts(frontFull: 'white shirt, black skirt'),
                  partTags: WorkspaceOutfitPartTags(
                    upperBodyTags: ['shirt-shaped birthmark'],
                    upperClothingTags: ['white shirt'],
                    lowerBodyTags: ['skirt-shaped tail ornament'],
                    lowerClothingTags: ['black skirt'],
                  ),
                ),
              ],
            ),
          ],
        );

        await viewModel.importScriptPath(_fixturePath);
        viewModel.setRoleCharacter('slot-0', 'char-hero');

        final stage = viewModel.roleMappings.first.selectedStage!;
        expect(stage.parts.identity, 'library_hero, actual identity');
        expect(stage.parts.upperBody, 'shirt-shaped birthmark');
        expect(stage.parts.upperClothing, 'white shirt');
        expect(stage.parts.lowerBody, 'skirt-shaped tail ornament');
        expect(stage.parts.lowerClothing, 'black skirt');
      },
    );

    test(
      'dropping a replacement outfit replaces existing outfit prompt parts',
      () async {
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => const [
            CharacterEntry(
              id: 'char-hero',
              name: 'library character',
              defaultOutfitId: 'default',
              traits: ViewVariantTexts(frontFull: 'library_hero'),
              anchorTags: ['library_hero'],
              outfits: [
                WorkspaceOutfit(
                  id: 'default',
                  name: 'Default',
                  tags: ViewVariantTexts(frontFull: 'default outfit'),
                  partTags: WorkspaceOutfitPartTags(
                    upperBodyTags: ['default upper body'],
                    upperClothingTags: ['default jacket'],
                    lowerBodyTags: ['default lower body'],
                    lowerClothingTags: ['default skirt'],
                  ),
                ),
                WorkspaceOutfit(
                  id: 'variant-1',
                  name: 'Variant 1',
                  tags: ViewVariantTexts(frontFull: 'variant outfit'),
                  partTags: WorkspaceOutfitPartTags(
                    upperBodyTags: ['variant upper body'],
                    upperClothingTags: ['variant hoodie'],
                    lowerBodyTags: ['variant lower body'],
                    lowerClothingTags: ['variant boots'],
                  ),
                ),
              ],
            ),
          ],
        );

        await viewModel.importScriptPath(_fixturePath);
        viewModel.setRoleCharacter('slot-0', 'char-hero');
        expect(
          viewModel.roleMappings.first.stageItems.first.parts.upperClothing,
          'default jacket',
        );

        viewModel.setRoleOutfit('slot-0', 'variant-1');

        final stage = viewModel.roleMappings.first.stageItems.first;
        expect(stage.selectedUpperOutfitId, 'variant-1');
        expect(stage.selectedLowerOutfitId, 'variant-1');
        expect(stage.parts.upperBody, 'variant upper body');
        expect(stage.parts.upperClothing, 'variant hoodie');
        expect(stage.parts.lowerBody, 'variant lower body');
        expect(stage.parts.lowerClothing, 'variant boots');
      },
    );

    test(
      'dropping a replacement outfit replaces previous target identity and outfit parts',
      () async {
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => const [
            CharacterEntry(
              id: 'old-hero',
              name: 'old target',
              traits: ViewVariantTexts(frontFull: 'old_hero'),
              anchorTags: ['old_hero'],
              outfits: [
                WorkspaceOutfit(
                  id: 'old-default',
                  name: 'Old default',
                  tags: ViewVariantTexts(frontFull: 'old outfit'),
                  partTags: WorkspaceOutfitPartTags(
                    upperBodyTags: ['old upper body'],
                    upperClothingTags: ['old jacket'],
                    lowerBodyTags: ['old lower body'],
                    lowerClothingTags: ['old boots'],
                  ),
                ),
              ],
              defaultOutfitId: 'old-default',
            ),
            CharacterEntry(
              id: 'pepe',
              name: 'Pepe',
              traits: ViewVariantTexts(frontFull: 'pepe_(arknights)'),
              anchorTags: ['pepe_(arknights)'],
              outfits: [
                WorkspaceOutfit(
                  id: 'pepe-variant-1',
                  name: 'Variant 1',
                  tags: ViewVariantTexts(frontFull: 'pepe variant outfit'),
                  partTags: WorkspaceOutfitPartTags(
                    upperBodyTags: ['cat ears', 'long hair'],
                    upperClothingTags: ['animal ear hood', 'black jacket'],
                    lowerBodyTags: ['cat tail'],
                    lowerClothingTags: ['black shorts', 'black shoes'],
                  ),
                ),
              ],
              defaultOutfitId: 'pepe-variant-1',
            ),
          ],
        );

        await viewModel.importScriptPath(_fixturePath);
        viewModel.setRoleCharacter('slot-0', 'old-hero');
        expect(
          viewModel.roleMappings.first.stageItems.first.parts.identity,
          'old_hero',
        );

        viewModel.setRoleCharacter('slot-0', 'pepe');
        viewModel.setRoleOutfit('slot-0', 'pepe-variant-1');

        final stage = viewModel.roleMappings.first.stageItems.first;
        expect(stage.selectedCharacterId, 'pepe');
        expect(stage.selectedUpperOutfitId, 'pepe-variant-1');
        expect(stage.selectedLowerOutfitId, 'pepe-variant-1');
        expect(stage.parts.identity, 'pepe_(arknights)');
        expect(stage.parts.upperBody, 'cat ears, long hair');
        expect(stage.parts.upperClothing, 'animal ear hood, black jacket');
        expect(stage.parts.lowerBody, 'cat tail');
        expect(stage.parts.lowerClothing, 'black shorts, black shoes');
      },
    );

    test(
      'dropping a split replacement outfit leaves missing identity blank and fills body parts',
      () async {
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => const [
            CharacterEntry(
              id: 'pepe',
              name: 'Pepe',
              traits: ViewVariantTexts(
                frontFull: 'girl, 2::loli::, pepe_(arknights), cat ears, '
                    'long hair, cat tail, animal ear hood, black jacket, '
                    'black shorts',
                frontUpper: 'cat ears, long hair',
                frontLower: 'cat tail',
              ),
              outfits: [
                WorkspaceOutfit(
                  id: 'default',
                  name: 'Default',
                  tags: ViewVariantTexts(
                    frontFull: 'animal ear hood, black jacket, black shorts',
                  ),
                  partTags: WorkspaceOutfitPartTags(
                    upperClothingTags: ['animal ear hood', 'black jacket'],
                    lowerClothingTags: ['black shorts'],
                  ),
                ),
                WorkspaceOutfit(
                  id: 'variant-1',
                  name: 'Variant 1',
                  tags: ViewVariantTexts(
                    frontFull:
                        'ancient egyptian clothes, sleeveless dress, white dress',
                  ),
                  partTags: WorkspaceOutfitPartTags(
                    upperClothingTags: [
                      'ancient egyptian clothes',
                      'sleeveless dress',
                      'white dress',
                    ],
                    lowerClothingTags: ['black shoes', 'black shorts'],
                  ),
                ),
              ],
              defaultOutfitId: 'default',
            ),
          ],
        );

        await viewModel.importScriptPath(_fixturePath);
        viewModel.setRoleCharacter('slot-0', 'pepe');
        viewModel.setRoleOutfit('slot-0', 'variant-1');

        final stage = viewModel.roleMappings.first.stageItems.first;
        expect(stage.parts.identity, isEmpty);
        expect(stage.parts.identity, isNot(contains('animal ear hood')));
        expect(stage.parts.identity, isNot(contains('black jacket')));
        expect(stage.parts.upperBody, 'cat ears, long hair');
        expect(stage.parts.lowerBody, 'cat tail');
        expect(
          stage.parts.upperClothing,
          'ancient egyptian clothes, sleeveless dress, white dress',
        );
        expect(stage.parts.lowerClothing, 'black shoes, black shorts');
      },
    );

    test(
      'dropping an outfit without part tags does not use frontFull as clothing',
      () async {
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => const [
            CharacterEntry(
              id: 'pepe',
              name: 'Pepe',
              traits: ViewVariantTexts(
                frontFull: 'pepe_(arknights), cat ears, cat tail',
                frontUpper: 'cat ears',
                frontLower: 'cat tail',
              ),
              anchorTags: ['pepe_(arknights)'],
              outfits: [
                WorkspaceOutfit(
                  id: 'skin-front-full-only',
                  name: 'Skin Front Full Only',
                  tags: ViewVariantTexts(
                    frontFull:
                        'pepe_(nuit_of_the_nightsky)_(arknights), white dress',
                    frontUpper: 'white dress',
                    frontLower: 'purple skirt',
                  ),
                ),
              ],
            ),
          ],
        );

        await viewModel.importScriptPath(_fixturePath);
        viewModel.applyRoleOutfitDrop(
          sourceRoleId: 'slot-0',
          characterId: 'pepe',
          outfitId: 'skin-front-full-only',
        );

        final stage = viewModel.roleMappings.first.stageItems.first;
        expect(stage.parts.identity, 'pepe_(arknights)');
        expect(stage.parts.upperClothing, isEmpty);
        expect(stage.parts.lowerClothing, isEmpty);
      },
    );

    test(
      'outfit full prompt does not suppress explicit split character identity',
      () async {
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => const [
            CharacterEntry(
              id: 'papyrus',
              name: '鑾庤崏',
              traits: ViewVariantTexts(
                frontFull: 'girl, papyrus_(arknights), animal ears, cat ears, '
                    'green eyes, orange hair, long hair, tail ornament',
                frontUpper:
                    'animal ears, cat ears, green eyes, orange hair, long hair',
                frontLower: 'tail ornament, fluffy tail',
              ),
              anchorTags: ['papyrus_(arknights)'],
              outfits: [
                WorkspaceOutfit(
                  id: 'pink',
                  name: '绮夎壊鐫¤。',
                  tags: ViewVariantTexts(
                    frontFull: 'girl, papyrus_(arknights), pink pajamas, '
                        'dress, hood, brown gloves',
                  ),
                  partTags: WorkspaceOutfitPartTags(
                    upperClothingTags: ['pink pajamas', 'dress', 'hood'],
                    lowerClothingTags: ['brown gloves'],
                  ),
                ),
              ],
              defaultOutfitId: 'pink',
            ),
          ],
        );

        await viewModel.importScriptPath(_fixturePath);
        viewModel.applyRoleOutfitDrop(
          sourceRoleId: 'slot-0',
          characterId: 'papyrus',
          outfitId: 'pink',
        );

        final stage = viewModel.roleMappings.first.stageItems.first;
        expect(stage.parts.identity, contains('papyrus_(arknights)'));
        expect(stage.parts.identity, isNot(contains('pink pajamas')));
        expect(stage.parts.identity, isNot(contains('animal ears')));
        expect(stage.parts.upperBody, contains('green eyes'));
        expect(stage.parts.lowerBody, contains('tail ornament'));
        expect(stage.parts.upperClothing, 'pink pajamas, dress, hood');
        expect(stage.parts.lowerClothing, 'brown gloves');
      },
    );

    test(
      'dropping an outfit on an existing target only replaces clothing',
      () async {
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => const [
            CharacterEntry(
              id: 'pepe',
              name: 'Pepe',
              traits: ViewVariantTexts(
                frontFull: 'pepe_(arknights), cat ears, long hair, cat tail',
                frontUpper: 'cat ears, long hair',
                frontLower: 'cat tail',
              ),
              anchorTags: ['pepe_(arknights)'],
              outfits: [
                WorkspaceOutfit(
                  id: 'default',
                  name: 'Default',
                  tags: ViewVariantTexts(frontFull: 'animal ear hood'),
                  partTags: WorkspaceOutfitPartTags(
                    upperBodyTags: ['default ears'],
                    upperClothingTags: ['animal ear hood'],
                    lowerBodyTags: ['default tail'],
                    lowerClothingTags: ['black shorts'],
                  ),
                ),
                WorkspaceOutfit(
                  id: 'variant-1',
                  name: 'Variant 1',
                  tags: ViewVariantTexts(frontFull: 'white dress'),
                  partTags: WorkspaceOutfitPartTags(
                    upperBodyTags: ['variant ears should not replace'],
                    upperClothingTags: ['white dress'],
                    lowerBodyTags: ['variant tail should not replace'],
                    lowerClothingTags: ['black shoes'],
                  ),
                ),
              ],
              defaultOutfitId: 'default',
            ),
          ],
        );

        await viewModel.importScriptPath(_fixturePath);
        viewModel.applyRoleOutfitDrop(
          sourceRoleId: 'slot-0',
          characterId: 'pepe',
          outfitId: 'default',
        );

        final firstStage = viewModel.roleMappings.first.stageItems.first;
        expect(firstStage.parts.identity, 'pepe_(arknights)');
        expect(firstStage.parts.upperBody, 'default ears');
        expect(firstStage.parts.lowerBody, 'default tail');
        expect(firstStage.parts.upperClothing, 'animal ear hood');
        expect(firstStage.parts.lowerClothing, 'black shorts');

        viewModel.applyRoleOutfitDrop(
          sourceRoleId: 'slot-0',
          characterId: 'pepe',
          outfitId: 'variant-1',
        );

        final stage = viewModel.roleMappings.first.stageItems.first;
        expect(stage.parts.identity, 'pepe_(arknights)');
        expect(stage.parts.upperBody, 'default ears');
        expect(stage.parts.lowerBody, 'default tail');
        expect(stage.parts.upperClothing, 'white dress');
        expect(stage.parts.lowerClothing, 'black shoes');
      },
    );

    test(
      'dropping an outfit fills empty character fields even when a target id exists',
      () async {
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => const [
            CharacterEntry(
              id: 'old-target',
              name: 'Old Target',
              traits: ViewVariantTexts(
                frontFull: 'old_target_(series), old ears, old tail',
                frontUpper: 'old ears',
                frontLower: 'old tail',
              ),
              anchorTags: ['old_target_(series)'],
              outfits: [
                WorkspaceOutfit(
                  id: 'old-default',
                  name: 'Old Default',
                  tags: ViewVariantTexts(frontFull: 'old dress'),
                  partTags: WorkspaceOutfitPartTags(
                    upperClothingTags: ['old dress'],
                  ),
                ),
              ],
              defaultOutfitId: 'old-default',
            ),
            CharacterEntry(
              id: 'papyrus',
              name: 'Papyrus',
              traits: ViewVariantTexts(
                frontFull: 'girl, papyrus_(arknights), animal ears, cat ears, '
                    'green eyes, orange hair, tail ornament',
                frontUpper: 'animal ears, cat ears, green eyes, orange hair',
                frontLower: 'tail ornament',
              ),
              anchorTags: ['papyrus_(arknights)'],
              outfits: [
                WorkspaceOutfit(
                  id: 'pink',
                  name: 'Pink Pajamas',
                  tags: ViewVariantTexts(
                    frontFull: 'girl, papyrus_(arknights), pink pajamas, dress',
                  ),
                  partTags: WorkspaceOutfitPartTags(
                    upperClothingTags: ['pink pajamas', 'dress'],
                  ),
                ),
              ],
              defaultOutfitId: 'pink',
            ),
          ],
        );

        await viewModel.importScriptPath(_fixturePath);
        viewModel.setRoleCharacter('slot-0', 'old-target');
        final stageId = viewModel.roleMappings.first.stageItems.first.id;
        viewModel.setRoleStagePart(
          sourceRoleId: 'slot-0',
          stageId: stageId,
          part: StudioScriptRolePart.identity,
          value: '',
        );
        viewModel.setRoleStagePart(
          sourceRoleId: 'slot-0',
          stageId: stageId,
          part: StudioScriptRolePart.upperBody,
          value: '',
        );
        viewModel.setRoleStagePart(
          sourceRoleId: 'slot-0',
          stageId: stageId,
          part: StudioScriptRolePart.lowerBody,
          value: '',
        );
        final emptyCharacterStage =
            viewModel.roleMappings.first.stageItems.first;
        expect(emptyCharacterStage.selectedCharacterId, 'old-target');
        expect(emptyCharacterStage.parts.identity, isEmpty);
        expect(emptyCharacterStage.parts.upperBody, isEmpty);
        expect(emptyCharacterStage.parts.lowerBody, isEmpty);

        viewModel.applyRoleOutfitDrop(
          sourceRoleId: 'slot-0',
          characterId: 'papyrus',
          outfitId: 'pink',
        );

        final stage = viewModel.roleMappings.first.stageItems.first;
        expect(stage.selectedCharacterId, 'papyrus');
        expect(stage.parts.identity, 'papyrus_(arknights)');
        expect(
          stage.parts.upperBody,
          'animal ears, cat ears, green eyes, orange hair',
        );
        expect(stage.parts.lowerBody, 'tail ornament');
        expect(stage.parts.upperClothing, 'pink pajamas, dress');
      },
    );

    test(
      'clearing a role stage target removes every replacement output part',
      () async {
        var caches = <RecastScriptCache>[];
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => const [
            CharacterEntry(
              id: 'pepe',
              name: 'Pepe',
              traits: ViewVariantTexts(
                frontFull: 'pepe_(arknights)',
                frontUpper: 'cat ears',
                frontLower: 'cat tail',
              ),
              anchorTags: ['pepe_(arknights)'],
              outfits: [
                WorkspaceOutfit(
                  id: 'default',
                  name: 'Default',
                  tags: ViewVariantTexts(frontFull: 'animal ear hood'),
                  partTags: WorkspaceOutfitPartTags(
                    upperClothingTags: ['animal ear hood'],
                    lowerClothingTags: ['black shorts'],
                  ),
                ),
              ],
              defaultOutfitId: 'default',
            ),
          ],
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );

        await viewModel.importScriptPath(_fixturePath);
        viewModel.applyRoleOutfitDrop(
          sourceRoleId: 'slot-0',
          characterId: 'pepe',
          outfitId: 'default',
        );
        final stageId = viewModel.roleMappings.first.stageItems.first.id;

        viewModel.clearRoleStageTarget(
          sourceRoleId: 'slot-0',
          stageId: stageId,
        );

        final stage = viewModel.roleMappings.first.stageItems.first;
        expect(stage.selectedCharacterId, isNull);
        expect(stage.selectedUpperOutfitId, isNull);
        expect(stage.selectedLowerOutfitId, isNull);
        expect(stage.parts.isEmpty, isTrue);
        expect(stage.omittedParts, contains(RecastPromptPart.identity));
        expect(stage.omittedParts, contains(RecastPromptPart.upperBody));
        expect(stage.omittedParts, contains(RecastPromptPart.lowerBody));
        expect(stage.omittedParts, contains(RecastPromptPart.upperClothing));
        expect(stage.omittedParts, contains(RecastPromptPart.lowerClothing));
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(caches.single.mapping.roleSwaps, isEmpty);
      },
    );

    test('assembly target edits do not write hidden role swaps', () async {
      var caches = <RecastScriptCache>[];
      final viewModel = StudioScriptViewModel(
        loadCharacters: () async => const [
          CharacterEntry(
            id: 'shamare',
            name: 'Shamare',
            traits: ViewVariantTexts(
              frontFull: 'shamare_(arknights), fox ears, fox tail',
              frontUpper: 'fox ears',
              frontLower: 'fox tail',
            ),
            anchorTags: ['shamare_(arknights)'],
            outfits: [
              WorkspaceOutfit(
                id: 'default',
                name: 'Default',
                tags: ViewVariantTexts(frontFull: 'black dress'),
                partTags: WorkspaceOutfitPartTags(
                  lowerClothingTags: ['black dress'],
                ),
              ),
              WorkspaceOutfit(
                id: 'variant',
                name: 'Variant',
                tags: ViewVariantTexts(frontFull: 'see-through dress'),
                partTags: WorkspaceOutfitPartTags(
                  lowerClothingTags: ['see-through dress'],
                ),
              ),
            ],
            defaultOutfitId: 'default',
          ),
        ],
        loadRecastCaches: () async => caches,
        saveRecastCaches: (next) async => caches = next,
      );

      await viewModel.importScriptPath(_fixturePath);
      viewModel.setRoleCharacter('slot-0', 'shamare');
      await Future<void>.delayed(const Duration(milliseconds: 600));

      var stage = viewModel.roleMappings.first.stageItems.single;
      expect(stage.selectedCharacterId, 'shamare');
      expect(stage.selectedUpperOutfitId, 'default');
      expect(caches.single.mapping.roleSwaps, isEmpty);

      viewModel.setRoleOutfit('slot-0', 'variant');
      await Future<void>.delayed(const Duration(milliseconds: 600));

      stage = viewModel.roleMappings.first.stageItems.single;
      expect(stage.selectedUpperOutfitId, 'variant');
      expect(stage.parts.lowerClothing, 'see-through dress');
      expect(caches.single.mapping.roleSwaps, isEmpty);
    });

    test(
      'can copy the selected replacement target to all outfit stages',
      () async {
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            _twoStageSlotExtraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();
        await viewModel.applyAiRoleExtraction();
        final sourceRoleId = viewModel.roleMappings.first.sourceRoleId;
        final templateStageId =
            viewModel.roleMappings.first.stageItems.first.id;

        viewModel.setRoleStagePart(
          sourceRoleId: sourceRoleId,
          stageId: templateStageId,
          part: StudioScriptRolePart.upperClothing,
          value: '',
        );
        viewModel.setRoleStagePart(
          sourceRoleId: sourceRoleId,
          stageId: templateStageId,
          part: StudioScriptRolePart.lowerClothing,
          value: 'shared skirt',
        );
        viewModel.copyRoleStageTargetToAllOutfits(
          sourceRoleId: sourceRoleId,
          stageId: templateStageId,
        );

        final stages = viewModel.roleMappings.first.stageItems;
        expect(stages, hasLength(2));
        for (final stage in stages) {
          expect(stage.parts.upperClothing, isEmpty);
          expect(stage.parts.lowerClothing, 'shared skirt');
        }
      },
    );

    test(
      'can copy the selected replacement target to one outfit stage only',
      () async {
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            ScriptAiRoleExtraction(
              status: ScriptAiRoleExtractionStatus.ready,
              confidence: 0.9,
              roles: [
                ScriptAiExtractedRole(
                  sourceRoleId: 'slot-0',
                  displayName: 'hero',
                  confidence: 0.9,
                  stages: [
                    ScriptAiExtractedStage(
                      stageId: 'stage-school',
                      label: 'school',
                      frameIndexes: [1],
                      identity: 'hero',
                      upperClothing: 'school jacket',
                      lowerClothing: 'school skirt',
                      confidence: 0.9,
                    ),
                    ScriptAiExtractedStage(
                      stageId: 'stage-swim',
                      label: 'swim',
                      frameIndexes: [2],
                      identity: 'hero',
                      upperClothing: 'swim top',
                      lowerClothing: 'swim shorts',
                      confidence: 0.9,
                    ),
                    ScriptAiExtractedStage(
                      stageId: 'stage-hood',
                      label: 'hood',
                      frameIndexes: [3],
                      identity: 'hero',
                      upperClothing: 'hoodie',
                      lowerClothing: 'cargo shorts',
                      confidence: 0.9,
                    ),
                  ],
                ),
              ],
            ),
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );
        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();
        await viewModel.applyAiRoleExtraction();
        viewModel.setRoleStagePart(
          sourceRoleId: 'slot-0',
          stageId: 'stage-school',
          part: StudioScriptRolePart.upperClothing,
          value: 'school jacket',
        );
        viewModel.setRoleStagePart(
          sourceRoleId: 'slot-0',
          stageId: 'stage-school',
          part: StudioScriptRolePart.lowerClothing,
          value: 'school skirt',
        );
        viewModel.setRoleStagePart(
          sourceRoleId: 'slot-0',
          stageId: 'stage-swim',
          part: StudioScriptRolePart.upperClothing,
          value: 'swim top',
        );
        viewModel.setRoleStagePart(
          sourceRoleId: 'slot-0',
          stageId: 'stage-swim',
          part: StudioScriptRolePart.lowerClothing,
          value: 'swim shorts',
        );
        viewModel.setRoleStagePart(
          sourceRoleId: 'slot-0',
          stageId: 'stage-hood',
          part: StudioScriptRolePart.upperClothing,
          value: 'hoodie',
        );
        viewModel.setRoleStagePart(
          sourceRoleId: 'slot-0',
          stageId: 'stage-hood',
          part: StudioScriptRolePart.lowerClothing,
          value: 'cargo shorts',
        );

        viewModel.copyRoleStageTargetToStage(
          sourceRoleId: 'slot-0',
          templateStageId: 'stage-school',
          targetStageId: 'stage-hood',
        );

        final stages = viewModel.roleMappings.single.stageItems;
        final swim = stages.singleWhere((stage) => stage.id == 'stage-swim');
        final hood = stages.singleWhere((stage) => stage.id == 'stage-hood');

        expect(swim.parts.upperClothing, 'swim top');
        expect(swim.parts.lowerClothing, 'swim shorts');

        expect(hood.parts.upperClothing, 'school jacket');
        expect(hood.parts.lowerClothing, 'school skirt');
      },
    );

    test(
      'role stage selection survives prompt edits after preview refresh',
      () async {
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            _twoStageSlotExtraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();
        await viewModel.applyAiRoleExtraction();
        final sourceRoleId = viewModel.roleMappings.first.sourceRoleId;
        final secondStageId = viewModel.roleMappings.first.stageItems.last.id;

        viewModel.selectRoleStage(sourceRoleId, secondStageId);
        viewModel.setRoleStagePart(
          sourceRoleId: sourceRoleId,
          stageId: secondStageId,
          part: StudioScriptRolePart.upperClothing,
          value: 'second stage jacket',
        );

        final selectedStage = viewModel.roleMappings.first.selectedStage!;
        expect(selectedStage.id, secondStageId);
        expect(selectedStage.parts.upperClothing, 'second stage jacket');
        expect(
          viewModel.roleMappings.first.stageItems.first.parts.upperClothing,
          isNot('second stage jacket'),
        );
      },
    );

    test(
      'AI role extraction fills draft without mutating preview until apply',
      () async {
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            _highConfidenceSlotExtraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        final beforeDiff = viewModel.diff.recast;
        await viewModel.generateAiRoleExtraction();

        expect(
          viewModel.aiRoleExtraction.status,
          ScriptAiRoleExtractionStatus.ready,
        );
        expect(viewModel.aiRoleExtraction.roles.single.displayName, 'AI Hero');
        expect(viewModel.aiRoleExtractionRequestPreview['schema_version'], 1);
        expect(viewModel.diff.recast, beforeDiff);
      },
    );

    test(
      'AI role extraction keeps prompt and scene replacement terms when applied',
      () async {
        const extraction = ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.92,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'AI Hero',
              confidence: 0.9,
              promptTerms: [
                ScriptAiExtractedPromptTerm(
                  id: 'ai-hero',
                  text: 'ai hero',
                  category: PromptTagCategory.character,
                  sourcePhrase: 'ai hero, blue jacket',
                  sourceLocation: 'slot-0 prompt',
                  frameIndexes: [1, 2],
                ),
                ScriptAiExtractedPromptTerm(
                  id: 'blue-jacket',
                  text: 'blue jacket',
                  category: PromptTagCategory.upperClothing,
                  sourcePhrase: 'ai hero, blue jacket',
                  sourceLocation: 'slot-0 prompt',
                  frameIndexes: [1, 2],
                ),
              ],
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'main-outfit',
                  label: 'main outfit',
                  frameIndexes: [1, 2],
                  identity: 'ai hero',
                  upperClothing: 'blue jacket',
                ),
              ],
            ),
          ],
          sceneTerms: [
            ScriptAiExtractedPromptTerm(
              id: 'rainy-street',
              text: 'rainy city street',
              category: PromptTagCategory.scene,
              sourcePhrase: 'in a rainy city street',
              sourceLocation: 'base prompt',
              frameIndexes: [1, 2],
            ),
          ],
        );
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            extraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();

        expect(
          viewModel.aiRoleExtraction.roles.single.promptTerms
              .map((term) => term.text),
          orderedEquals(['ai hero', 'blue jacket']),
        );
        expect(
          viewModel.aiRoleExtraction.sceneTerms.single.text,
          'rainy city street',
        );

        await viewModel.applyAiRoleExtraction();

        expect(viewModel.roleReplacementMappings, hasLength(1));
        expect(
          viewModel.roleReplacementMappings.single.rules
              .map((rule) => rule.sourceTerms.single.text),
          orderedEquals(['ai hero', 'blue jacket']),
        );
        expect(viewModel.sceneReplacementMappings, hasLength(1));
        expect(
          viewModel.sceneReplacementMappings.single.rules.single.sourceTerms
              .single.text,
          'rainy city street',
        );
      },
    );

    test(
      'AI role extraction applies scene replacement rules even without roles',
      () async {
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            ScriptAiRoleExtraction(
              status: ScriptAiRoleExtractionStatus.ready,
              sceneTerms: [
                ScriptAiExtractedPromptTerm(
                  id: 'night',
                  text: 'night',
                  category: PromptTagCategory.scene,
                  sourcePhrase: 'city street at night',
                  sourceLocation: 'base prompt',
                  frameIndexes: [1],
                ),
              ],
            ),
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();
        await viewModel.applyAiRoleExtraction();

        expect(viewModel.roleReplacementMappings, isEmpty);
        expect(viewModel.sceneReplacementMappings, hasLength(1));
        expect(
          viewModel.sceneReplacementMappings.single.rules.single.sourceTerms
              .single.text,
          'night',
        );
      },
    );

    test(
      'frame review source terms can be added to selected replacement rule',
      () async {
        final script = _singleFrameScript(
          id: 'frame-review-source-add-script',
          name: 'Frame Review Source Add Script',
          rootPath: 'frame-review-source-add-script',
          baseCaption: 'city lights, rain',
          charCaptions: const ['source hero, fox ears, blue jacket'],
        );
        final cache = RecastScriptCache(
          scriptId: script.id,
          scriptName: script.name,
          sourceRootPath: script.rootPath,
          sourceFingerprint: _normalizedSourceFingerprintForTest(script),
          updatedAt: DateTime.utc(2026, 6, 17),
          mapping: RecastMapping.defaults(script.id).copyWith(
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourcePreview: 'source hero',
                rules: [
                  ScriptPromptReplacementRule(
                    id: 'rule-hero',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'term-source-hero',
                        text: 'source hero',
                        category: PromptTagCategory.character,
                        frameIndexes: [1],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          scriptSnapshot: script.toJson(),
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadRecastCacheByScriptId: (_) async => cache,
        );

        await viewModel.importScriptPath(script.rootPath);
        viewModel.setRoleReplacementRuleSelected('slot-0', 'rule-hero', true);

        final added = viewModel.addFrameReviewTermsToSelectedReplacementRule(
          frameIndex: 1,
          sourceLocation: '角色 1',
          terms: const [
            StudioScriptReplacementSourceTermDraft(
              text: 'fox ears',
              category: PromptTagCategory.upperBody,
            ),
          ],
        );

        expect(added, isTrue);
        final rule = viewModel.roleReplacementMappings.single.rules.single;
        expect(
          rule.sourceTerms.map((term) => term.text),
          orderedEquals(['source hero', 'fox ears']),
        );
        expect(rule.sourceTerms.last.frameIndexes, [1]);
        expect(rule.sourceTerms.last.sourceLocation, '角色 1');
      },
    );

    test(
      'frame review source terms can directly create a role replacement rule',
      () async {
        final script = _singleFrameScript(
          id: 'frame-review-direct-add-script',
          name: 'Frame Review Direct Add Script',
          rootPath: 'frame-review-direct-add-script',
          baseCaption: 'city lights, rain',
          charCaptions: const ['source hero, fox ears, blue jacket'],
        );
        final cache = RecastScriptCache(
          scriptId: script.id,
          scriptName: script.name,
          sourceRootPath: script.rootPath,
          sourceFingerprint: _normalizedSourceFingerprintForTest(script),
          updatedAt: DateTime.utc(2026, 6, 18),
          mapping: RecastMapping.defaults(script.id).copyWith(
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourcePreview: 'source hero',
              ),
            ],
          ),
          scriptSnapshot: script.toJson(),
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadRecastCacheByScriptId: (_) async => cache,
        );

        await viewModel.importScriptPath(script.rootPath);

        final added = viewModel.addFrameReviewTermsToReplacementArea(
          frameIndex: 1,
          sourceGroupId: 'role-1',
          sourceLocation: '角色 1',
          terms: const [
            StudioScriptReplacementSourceTermDraft(
              text: 'fox ears',
              category: PromptTagCategory.upperBody,
            ),
            StudioScriptReplacementSourceTermDraft(
              text: 'blue jacket',
              category: PromptTagCategory.upperClothing,
            ),
          ],
        );

        expect(added, isTrue);
        final rules = viewModel.roleReplacementMappings.single.rules;
        expect(rules, hasLength(1));
        expect(
          rules.single.sourceTerms.map((term) => term.text),
          orderedEquals(['fox ears', 'blue jacket']),
        );
        expect(rules.single.targetPrompt, isEmpty);
        expect(rules.single.sourceTerms.first.sourceLocation, '角色 1');
      },
    );

    test(
      'frame review source terms target current frame slot when replacement order differs',
      () async {
        final script = _singleFrameScript(
          id: 'frame-review-slot-target-script',
          name: 'Frame Review Slot Target Script',
          rootPath: 'frame-review-slot-target-script',
          baseCaption: 'city lights, rain',
          charCaptions: const [
            'slot zero hero, stray ribbon, green eyes',
            'slot one hero, blue eyes',
          ],
        );
        final cache = RecastScriptCache(
          scriptId: script.id,
          scriptName: script.name,
          sourceRootPath: script.rootPath,
          sourceFingerprint: _normalizedSourceFingerprintForTest(script),
          updatedAt: DateTime.utc(2026, 6, 22),
          mapping: RecastMapping.defaults(script.id).copyWith(
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-1',
                displayLabel: 'Role 2',
                sourcePreview: 'slot one hero',
              ),
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourcePreview: 'slot zero hero',
              ),
            ],
          ),
          scriptSnapshot: script.toJson(),
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadRecastCacheByScriptId: (_) async => cache,
        );

        await viewModel.importScriptPath(script.rootPath);

        final added = viewModel.addFrameReviewTermsToReplacementArea(
          frameIndex: 1,
          sourceGroupId: 'role-1',
          sourceLocation: 'Role 1',
          terms: const [
            StudioScriptReplacementSourceTermDraft(
              text: 'stray ribbon',
              category: PromptTagCategory.upperClothing,
            ),
          ],
        );

        expect(added, isTrue);
        final targetReplacement = viewModel.roleReplacementMappings
            .singleWhere((replacement) => replacement.sourceRoleId == 'slot-0');
        final otherReplacement = viewModel.roleReplacementMappings
            .singleWhere((replacement) => replacement.sourceRoleId == 'slot-1');
        final rule = targetReplacement.rules.single;
        expect(rule.sourceTerms.single.text, 'stray ribbon');
        expect(rule.selected, isTrue);
        expect(otherReplacement.rules, isEmpty);

        viewModel.setRoleReplacementRuleDeleted('slot-0', rule.id, true);

        final roleOneGroup = viewModel.selectedFrameTagGroups
            .singleWhere((group) => group.id == 'role-1');
        expect(roleOneGroup.tags, isNot(contains('stray ribbon')));
      },
    );

    test(
      'frame review source terms select an existing inactive role replacement rule',
      () async {
        final script = _singleFrameScript(
          id: 'frame-review-existing-rule-script',
          name: 'Frame Review Existing Rule Script',
          rootPath: 'frame-review-existing-rule-script',
          baseCaption: 'city lights, rain',
          charCaptions: const ['source hero, small breasts'],
        );
        final cache = RecastScriptCache(
          scriptId: script.id,
          scriptName: script.name,
          sourceRootPath: script.rootPath,
          sourceFingerprint: _normalizedSourceFingerprintForTest(script),
          updatedAt: DateTime.utc(2026, 6, 22),
          mapping: RecastMapping.defaults(script.id).copyWith(
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourcePreview: 'source hero',
                rules: [
                  ScriptPromptReplacementRule(
                    id: 'rule-small-breasts',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'term-small-breasts',
                        text: 'small breasts',
                        category: PromptTagCategory.upperBody,
                        frameIndexes: [1],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          scriptSnapshot: script.toJson(),
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadRecastCacheByScriptId: (_) async => cache,
        );

        await viewModel.importScriptPath(script.rootPath);

        final added = viewModel.addFrameReviewTermsToReplacementArea(
          frameIndex: 1,
          sourceGroupId: 'role-1',
          sourceLocation: 'Role 1',
          terms: const [
            StudioScriptReplacementSourceTermDraft(
              text: 'small breasts',
              category: PromptTagCategory.upperBody,
            ),
          ],
        );

        expect(added, isTrue);
        final rule = viewModel.roleReplacementMappings.single.rules.single;
        expect(rule.id, 'rule-small-breasts');
        expect(rule.selected, isTrue);

        viewModel.setRoleReplacementRuleDeleted('slot-0', rule.id, true);

        expect(
          viewModel.roleReplacementMappings.single.rules.single.action,
          ScriptPromptReplacementAction.delete,
        );
      },
    );

    test(
      'frame review role terms expand to all matching source role frames',
      () async {
        final script = _scriptWithFrames(
          [
            (
              index: 1,
              base: 'city lights',
              chars: ['source hero, fox ears', 'other girl'],
            ),
            (
              index: 2,
              base: 'city lights',
              chars: ['source hero, blue jacket', 'other girl, fox ears'],
            ),
            (
              index: 3,
              base: 'rain',
              chars: ['source hero, fox ears, smile'],
            ),
          ],
          id: 'frame-review-role-expansion-script',
          name: 'Frame Review Role Expansion Script',
          rootPath: 'frame-review-role-expansion-script',
        );
        final cache = RecastScriptCache(
          scriptId: script.id,
          scriptName: script.name,
          sourceRootPath: script.rootPath,
          sourceFingerprint: _normalizedSourceFingerprintForTest(script),
          updatedAt: DateTime.utc(2026, 6, 20),
          mapping: RecastMapping.defaults(script.id).copyWith(
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourcePreview: 'source hero',
              ),
            ],
          ),
          scriptSnapshot: script.toJson(),
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadRecastCacheByScriptId: (_) async => cache,
        );

        await viewModel.importScriptPath(script.rootPath);

        final added = viewModel.addFrameReviewTermsToReplacementArea(
          frameIndex: 1,
          sourceGroupId: 'role-1',
          sourceLocation: '瑙掕壊 1',
          terms: const [
            StudioScriptReplacementSourceTermDraft(
              text: 'fox ears',
              category: PromptTagCategory.upperBody,
            ),
          ],
        );

        expect(added, isTrue);
        final rule = viewModel.roleReplacementMappings.single.rules.single;
        expect(rule.sourceTerms.single.frameIndexes, [1, 3]);
      },
    );

    test(
      'frame review role terms scan all matching source slot frames',
      () async {
        final script = _scriptWithFrames(
          [
            (
              index: 1,
              base: 'city lights',
              chars: ['source hero, fox ears'],
            ),
            (
              index: 2,
              base: 'city lights',
              chars: ['source hero, blue jacket'],
            ),
            (
              index: 3,
              base: 'rain',
              chars: ['source hero, fox ears, smile'],
            ),
            (
              index: 4,
              base: 'forest',
              chars: ['source hero, fox ears, late frame'],
            ),
            (
              index: 5,
              base: 'forest',
              chars: ['source hero, blue jacket', 'other girl, fox ears'],
            ),
          ],
          id: 'frame-review-ai-role-expansion-script',
          name: 'Frame Review AI Role Expansion Script',
          rootPath: 'frame-review-ai-role-expansion-script',
        );
        final cache = RecastScriptCache(
          scriptId: script.id,
          scriptName: script.name,
          sourceRootPath: script.rootPath,
          sourceFingerprint: _normalizedSourceFingerprintForTest(script),
          updatedAt: DateTime.utc(2026, 6, 20),
          mapping: RecastMapping.defaults(script.id).copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'role-source-hero',
                displayLabel: 'Source Hero',
                sourceAppearances: [
                  RoleAssemblySourceAppearance(
                    sourceId: 'slot-0',
                    sourceKind: 'slot',
                    frameIndexes: [1, 3],
                  ),
                ],
                stages: [
                  RoleAssemblyStage(
                    id: 'source-hero-stage',
                    label: 'Source Hero',
                    frameIndexes: [1, 3],
                  ),
                ],
              ),
            ],
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'role-source-hero',
                displayLabel: 'Source Hero',
                sourcePreview: 'source hero',
              ),
            ],
          ),
          scriptSnapshot: script.toJson(),
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadRecastCacheByScriptId: (_) async => cache,
        );

        await viewModel.importScriptPath(script.rootPath);

        final added = viewModel.addFrameReviewTermsToReplacementArea(
          frameIndex: 1,
          sourceGroupId: 'role-1',
          sourceLocation: '瑙掕壊 1',
          terms: const [
            StudioScriptReplacementSourceTermDraft(
              text: 'fox ears',
              category: PromptTagCategory.upperBody,
            ),
          ],
        );

        expect(added, isTrue);
        final rule = viewModel.roleReplacementMappings.single.rules.single;
        expect(rule.sourceTerms.single.frameIndexes, [1, 3, 4]);
      },
    );

    test(
      'frame review scene terms expand to all matching base prompt frames',
      () async {
        final script = _scriptWithFrames(
          [
            (
              index: 1,
              base: 'city lights, rain',
              chars: ['source hero'],
            ),
            (
              index: 2,
              base: 'city lights, night',
              chars: ['source hero'],
            ),
            (
              index: 3,
              base: 'forest',
              chars: ['source hero, city lights'],
            ),
          ],
          id: 'frame-review-scene-expansion-script',
          name: 'Frame Review Scene Expansion Script',
          rootPath: 'frame-review-scene-expansion-script',
        );
        final cache = RecastScriptCache(
          scriptId: script.id,
          scriptName: script.name,
          sourceRootPath: script.rootPath,
          sourceFingerprint: _normalizedSourceFingerprintForTest(script),
          updatedAt: DateTime.utc(2026, 6, 20),
          mapping: RecastMapping.defaults(script.id),
          scriptSnapshot: script.toJson(),
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadRecastCacheByScriptId: (_) async => cache,
        );

        await viewModel.importScriptPath(script.rootPath);

        final added = viewModel.addFrameReviewTermsToReplacementArea(
          frameIndex: 1,
          sourceGroupId: 'base',
          sourceLocation: '基础提示词',
          terms: const [
            StudioScriptReplacementSourceTermDraft(
              text: 'city lights',
              category: PromptTagCategory.scene,
            ),
          ],
        );

        expect(added, isTrue);
        final rule = viewModel.sceneReplacementMappings.single.rules.single;
        expect(rule.sourceTerms.single.frameIndexes, [1, 2]);
      },
    );

    test(
      'AI role extraction materializes role-local candidates from covered frames',
      () async {
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([
            _scriptWithFrames([
              (
                index: 1,
                base: 'cinematic lighting, city street',
                chars: [
                  'ai hero, fox ears, blue jacket, smile',
                  'other girl, red dress',
                ],
              ),
              (
                index: 2,
                base: 'city street, rain',
                chars: [
                  'ai hero, white skirt, looking at viewer',
                  'other girl, black boots',
                ],
              ),
            ]),
          ]),
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            ScriptAiRoleExtraction(
              status: ScriptAiRoleExtractionStatus.ready,
              confidence: 0.9,
              roles: [
                ScriptAiExtractedRole(
                  sourceRoleId: 'slot-0',
                  displayName: 'AI Hero',
                  confidence: 0.9,
                  stages: [
                    ScriptAiExtractedStage(
                      stageId: 'main-outfit',
                      label: 'main outfit',
                      frameIndexes: [1, 2],
                      identity: 'ai hero',
                      upperBody: 'fox ears',
                      upperClothing: 'blue jacket',
                      lowerClothing: 'white skirt',
                      confidence: 0.88,
                    ),
                  ],
                ),
              ],
            ),
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath('stage-non-role-script');
        await viewModel.generateAiRoleExtraction();

        final stage = viewModel.aiRoleExtraction.roles.single.stages.single;
        expect(stage.nonRoleMaterialized, isTrue);
        expect(stage.nonRole, 'smile, looking at viewer');
      },
    );

    test(
      'AI role extraction saves chunk checkpoints before final failure',
      () async {
        var caches = <RecastScriptCache>[];
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async {
            caches = next;
          },
          scriptAiRoleExtractionService:
              const _CheckpointingFailureRoleExtractionService(),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();

        expect(caches, hasLength(1));
        expect(caches.single.aiRoleExtractionChunks, hasLength(1));
        expect(caches.single.aiRoleExtractionChunks.single.chunkId, 'chunk-1');
        expect(caches.single.aiRoleExtraction.isFailed, isTrue);
      },
    );

    test(
      'manual AI role extraction clears current script cache before rerun',
      () async {
        var caches = <RecastScriptCache>[];
        final seedViewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            ScriptAiRoleExtraction(status: ScriptAiRoleExtractionStatus.ready),
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );
        await seedViewModel.importScriptPath(_fixturePath);
        await seedViewModel.generateAiRoleExtraction();
        final baseCache = caches.single;
        caches = [
          RecastScriptCache(
            scriptId: baseCache.scriptId,
            scriptName: baseCache.scriptName,
            sourceRootPath: baseCache.sourceRootPath,
            sourceFingerprint: baseCache.sourceFingerprint,
            updatedAt: DateTime.utc(2026, 6, 6),
            mapping: baseCache.mapping,
            aiRoleExtraction: const ScriptAiRoleExtraction(
              status: ScriptAiRoleExtractionStatus.ready,
              roles: [
                ScriptAiExtractedRole(
                  sourceRoleId: 'slot-0',
                  displayName: 'cached old role',
                ),
              ],
            ),
            aiRoleExtractionChunks: const [
              ScriptAiRoleExtraction(
                status: ScriptAiRoleExtractionStatus.ready,
                chunkId: 'cached-chunk',
              ),
            ],
            aiRoleExtractionDraftCollapsed: true,
            scriptSnapshot: baseCache.scriptSnapshot,
          ),
        ];
        final service = _RecordingRoleExtractionService(
          const ScriptAiRoleExtraction(
            status: ScriptAiRoleExtractionStatus.ready,
            roles: [
              ScriptAiExtractedRole(
                sourceRoleId: 'slot-0',
                displayName: 'fresh role',
              ),
            ],
          ),
        );
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
          scriptAiRoleExtractionService: service,
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        expect(viewModel.aiRoleExtractionChunks, hasLength(1));
        expect(
          viewModel.aiRoleExtraction.roles.single.displayName,
          'cached old role',
        );

        await viewModel.generateAiRoleExtraction();

        expect(service.completedChunkCounts, [0]);
        expect(viewModel.aiRoleExtractionChunks, isEmpty);
        expect(
          viewModel.aiRoleExtraction.roles.single.displayName,
          'fresh role',
        );
        expect(viewModel.isAiRoleExtractionDraftCollapsed, isFalse);
        expect(
          caches.single.aiRoleExtraction.roles.single.displayName,
          'fresh role',
        );
        expect(caches.single.aiRoleExtractionChunks, isEmpty);
        expect(caches.single.aiRoleExtractionDraftCollapsed, isFalse);
      },
    );

    test(
      'AI role extraction stops before request when script has no frames',
      () async {
        const emptyScript = Script(
          id: 'script-empty',
          name: 'empty-script',
          rootPath: 'empty-script',
          frames: [],
          detectedSchema: ScriptSchema.unknown,
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService(const [emptyScript]),
          scriptAiRoleExtractionService:
              const _FailIfCalledRoleExtractionService(),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath('empty-script');
        await viewModel.generateAiRoleExtraction();

        expect(viewModel.frameCount, 0);
        expect(viewModel.parsedCount, 0);
        expect(
          viewModel.aiRoleExtraction.status,
          ScriptAiRoleExtractionStatus.failed,
        );
        expect(viewModel.aiRoleExtractionRequestCount, 0);
        expect(viewModel.aiStatus, contains('娌℃湁鍙В鏋愮殑鍓ф湰甯?'));
        expect(viewModel.aiStatus, contains('JSON'));
        expect(viewModel.aiStatus, contains('PNG'));
        expect(
          viewModel.aiRoleExtraction.attentionItems.single.kind,
          'no_parsed_frames',
        );
      },
    );

    test('AI role extraction exposes request progress while pending', () async {
      final service = _PendingRoleExtractionService(
        startedPreview: const {
          'schema_version': 1,
          'request_kind': 'chunk_extract',
          'chunk_id': 'chunk-1',
        },
      );
      final viewModel = StudioScriptViewModel(
        scriptAiRoleExtractionService: service,
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );

      await viewModel.importScriptPath(_fixturePath);

      unawaited(viewModel.generateAiRoleExtraction());
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.aiRoleExtractionRequestCount, 1);
      expect(
        viewModel.aiRoleExtractionRequestPreview['request_kind'],
        'chunk_extract',
      );
      expect(viewModel.aiRoleExtractionRequestPreview['chunk_id'], 'chunk-1');

      service.complete(
        const ScriptAiRoleExtractionServiceResult(
          extraction: _highConfidenceSlotExtraction,
          requestPreview: {
            'schema_version': 1,
            'request_kind': 'chunk_extract',
            'chunk_id': 'chunk-1',
          },
          aiRequestCount: 1,
        ),
      );
      await Future<void>.delayed(Duration.zero);
    });

    testWidgets('AI role extraction trace shows follow-up request summary', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = _FakeRoleExtractionService.withRequestTrace(
        extraction: const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.9,
        ),
        requestPreviews: const [
          {
            'schema_version': 2,
            'request_kind': 'chunk_extract_v2',
            'chunk_id': 'chunk-1',
          },
          {
            'schema_version': 2,
            'request_kind': 'evidence_followup',
            'chunk_id': 'chunk-1',
            'evidence': [
              {'frame_index': 1, 'source_id': 'slot-0'},
            ],
          },
        ],
        aiRequestCount: 2,
      );

      final viewModel = StudioScriptViewModel(
        scriptAiRoleExtractionService: service,
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );

      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();
      });
      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      expect(viewModel.aiRoleExtractionRequestCount, 2);
      expect(
        viewModel.aiRoleExtractionRequestPreview['request_kind'],
        'evidence_followup',
      );
      expect(find.textContaining('evidence_followup'), findsWidgets);

      await tester.tap(find.byIcon(Icons.subject_outlined).first);
      await tester.pumpAndSettle();

      final fullLogs = find.text('瀹屾暣鏃ュ織涓庤瘉鎹?');
      await tester.ensureVisible(fullLogs);
      await tester.pump();
      await tester.tap(fullLogs);
      await tester.pumpAndSettle();
      final fullRequestJson = find.text('瀹屾暣璇锋眰 JSON');
      await tester.ensureVisible(fullRequestJson);
      await tester.pump();
      await tester.tap(fullRequestJson);
      await tester.pumpAndSettle();

      expect(find.textContaining('"evidence"'), findsWidgets);
      expect(find.textContaining('"frame_index": 1'), findsWidgets);
      expect(find.textContaining('"source_id": "slot-0"'), findsWidgets);
    });

    testWidgets(
      'AI progress panel hides role details button without role extraction trace',
      (tester) async {
        final viewModel = StudioScriptViewModel();
        viewModel
          ..aiProgressTitle = 'AI cache analysis'
          ..aiStatus = 'Analyzing cache suggestions'
          ..aiProgressSteps = const [
            StudioScriptAiProgressStep(
              label: 'Analyze cache',
              state: StudioScriptAiProgressStepState.active,
            ),
          ];

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pump();

        final progressPanel = find.byKey(
          const ValueKey('script-ai-progress-panel'),
        );
        expect(progressPanel, findsOneWidget);
        expect(
          find.descendant(
            of: progressPanel,
            matching: find.byIcon(Icons.subject_outlined),
          ),
          findsNothing,
        );
      },
    );

    test(
      'AI role extraction preserves request progress after failure',
      () async {
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService:
              const _StartedThrowingRoleExtractionService(
            startedPreview: {
              'schema_version': 1,
              'request_kind': 'chunk_extract',
              'chunk_id': 'chunk-1',
            },
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();

        expect(
          viewModel.aiRoleExtraction.status,
          ScriptAiRoleExtractionStatus.failed,
        );
        expect(viewModel.aiRoleExtractionRequestCount, 1);
        expect(
          viewModel.aiRoleExtractionRequestPreview['request_kind'],
          'chunk_extract',
        );
        expect(viewModel.aiRoleExtractionRequestPreview['chunk_id'], 'chunk-1');
      },
    );

    test(
      'applying high confidence role extraction keeps target fields clean',
      () async {
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            _highConfidenceSlotExtraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();
        await viewModel.applyHighConfidenceAiRoleExtraction();

        final stage = viewModel.roleMappings.first.stageItems.first;
        expect(stage.label, 'main outfit');
        expect(viewModel.roleMappings.first.sourceLabel, 'AI Hero');
        expect(viewModel.roleMappings.first.sourcePreview, 'AI Hero');
        expect(stage.sourceSummary, contains('blue jacket'));
        expect(stage.parts.identity, isEmpty);
        expect(stage.parts.upperBody, isEmpty);
        expect(stage.parts.lowerBody, isEmpty);
        expect(stage.parts.upperClothing, isEmpty);
        expect(stage.parts.lowerClothing, isEmpty);
        expect(viewModel.diff.recast, isNot(contains('blue jacket')));
        expect(
          viewModel.aiRoleExtraction.status,
          ScriptAiRoleExtractionStatus.ready,
        );
      },
    );

    test(
      'applying role extraction prunes empty automatic local slots',
      () async {
        const extraction = ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.95,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'ai-role-0',
              sourceKind: 'cross_slot',
              displayName: 'Nagasaki Soyo',
              confidence: 0.95,
              appearances: [
                ScriptAiRoleAppearance(
                  sourceId: 'slot-0',
                  sourceKind: 'slot',
                  frameIndexes: [1, 2],
                ),
              ],
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'nude-stage',
                  label: 'nude',
                  frameIndexes: [1, 2],
                  identity: 'nagasaki soyo, girl',
                  confidence: 0.95,
                ),
              ],
            ),
            ScriptAiExtractedRole(
              sourceRoleId: 'ai-role-1',
              sourceKind: 'cross_slot',
              displayName: 'Togawa Sakiko',
              confidence: 0.94,
              appearances: [
                ScriptAiRoleAppearance(
                  sourceId: 'slot-1',
                  sourceKind: 'slot',
                  frameIndexes: [1, 2],
                ),
              ],
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'uniform-stage',
                  label: 'uniform',
                  frameIndexes: [1, 2],
                  identity: 'togawa sakiko, girl',
                  upperClothing: 'school uniform',
                  confidence: 0.94,
                ),
              ],
            ),
          ],
        );
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            extraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        expect(viewModel.roleMappings.map((role) => role.sourceRoleId), [
          'slot-0',
          'slot-1',
        ]);

        await viewModel.generateAiRoleExtraction();
        await viewModel.applyHighConfidenceAiRoleExtraction();

        expect(viewModel.roleMappings.map((role) => role.sourceRoleId), [
          'ai-role-0',
          'ai-role-1',
        ]);
        expect(
          viewModel.roleMappings.any(
            (role) => role.sourceRoleId.startsWith('slot-'),
          ),
          isFalse,
        );
      },
    );

    test(
      'applying cross-slot role extraction persists source appearances',
      () async {
        var caches = <RecastScriptCache>[];
        const extraction = ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.9,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'role-0',
              sourceKind: 'cross_slot',
              displayName: 'Alice',
              confidence: 0.9,
              frameIndexes: [1, 2],
              appearances: [
                ScriptAiRoleAppearance(
                  sourceId: 'slot-0',
                  sourceKind: 'slot',
                  frameIndexes: [1],
                ),
                ScriptAiRoleAppearance(
                  sourceId: 'slot-1',
                  sourceKind: 'slot',
                  frameIndexes: [2],
                ),
              ],
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'main-outfit',
                  label: 'main outfit',
                  frameIndexes: [1, 2],
                  identity: 'alice_(series)',
                  upperClothing: 'white shirt',
                  confidence: 0.9,
                ),
              ],
            ),
          ],
        );
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            extraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();
        await viewModel.applyHighConfidenceAiRoleExtraction();

        final assembly = caches.single.mapping.roleAssemblies.singleWhere(
          (item) => item.sourceRoleId == 'role-0',
        );
        expect(assembly.displayLabel, 'Alice');
        expect(assembly.sourceAppearances.map((item) => item.sourceId), [
          'slot-0',
          'slot-1',
        ]);
        expect(assembly.sourceAppearances.first.frameIndexes, [1]);
        expect(assembly.sourceAppearances.last.frameIndexes, [2]);
        expect(assembly.stages.single.sourceParts.identity, 'alice_(series)');
        expect(assembly.stages.single.sourceParts.upperClothing, 'white shirt');
      },
    );

    test('applying role extraction ignores confidence percentages', () async {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        confidence: 0.1,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            displayName: 'AI Hero Low Confidence',
            confidence: 0.1,
            stages: [
              ScriptAiExtractedStage(
                stageId: 'low-confidence-stage',
                label: 'low confidence stage',
                frameIndexes: [1],
                identity: 'ai hero',
                upperBody: 'green eyes',
                upperClothing: 'blue jacket',
                confidence: 0.1,
              ),
            ],
          ),
        ],
      );
      final viewModel = StudioScriptViewModel(
        scriptAiRoleExtractionService: const _FakeRoleExtractionService(
          extraction,
        ),
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );

      await viewModel.importScriptPath(_fixturePath);
      await viewModel.generateAiRoleExtraction();
      await viewModel.applyHighConfidenceAiRoleExtraction();

      final role = viewModel.roleMappings.first;
      final stage = role.stageItems.first;
      expect(role.sourceLabel, 'AI Hero Low Confidence');
      expect(role.sourcePreview, 'AI Hero Low Confidence');
      expect(stage.sourceParts.identity, 'ai hero');
      expect(stage.sourceParts.upperBody, 'green eyes');
      expect(stage.sourceParts.upperClothing, 'blue jacket');
      expect(stage.parts.identity, isEmpty);
      expect(stage.parts.upperClothing, isEmpty);
    });

    testWidgets(
      'applied role extraction shows source fields without filling replacement output',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            _highConfidenceSlotExtraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
          await viewModel.generateAiRoleExtraction();
          await viewModel.applyHighConfidenceAiRoleExtraction();
        });
        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final sourceUpperBody = find.byKey(
          const ValueKey('role-source-part-slot-0-main-outfit-upperBody'),
        );
        final sourceUpperClothing = find.byKey(
          const ValueKey('role-source-part-slot-0-main-outfit-upperClothing'),
        );
        final sourceLowerClothing = find.byKey(
          const ValueKey('role-source-part-slot-0-main-outfit-lowerClothing'),
        );
        final targetUpperBody = find.byKey(
          const ValueKey('role-output-part-slot-0-main-outfit-upperBody'),
        );
        final targetUpperClothing = find.byKey(
          const ValueKey('role-output-part-slot-0-main-outfit-upperClothing'),
        );

        expect(sourceUpperBody, findsOneWidget);
        expect(sourceUpperClothing, findsOneWidget);
        expect(sourceLowerClothing, findsOneWidget);
        expect(
          find.descendant(
            of: sourceUpperBody,
            matching: find.textContaining('green eyes'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: sourceUpperClothing,
            matching: find.textContaining('blue jacket'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: sourceLowerClothing,
            matching: find.textContaining('white skirt'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: targetUpperBody,
            matching: find.textContaining('green eyes'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: targetUpperClothing,
            matching: find.textContaining('blue jacket'),
          ),
          findsNothing,
        );
      },
    );

    test('role extraction stage id collision preserves target ids', () async {
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
                stageId: 'slot-0-stage-1',
                label: 'ai refreshed label',
                frameIndexes: [1, 2],
                identity: 'ai hero',
                upperBody: 'green eyes',
                lowerBody: 'black boots',
                upperClothing: 'blue jacket',
                lowerClothing: 'white skirt',
                confidence: 0.9,
              ),
            ],
          ),
        ],
      );
      final viewModel = StudioScriptViewModel(
        loadCharacters: () async => const [
          CharacterEntry(
            id: 'char-hero',
            name: 'Hero',
            defaultOutfitId: 'outfit-main',
            traits: ViewVariantTexts(frontFull: 'hero identity'),
            outfits: [
              WorkspaceOutfit(
                id: 'outfit-main',
                name: 'Main outfit',
                tags: ViewVariantTexts(frontFull: 'library outfit'),
              ),
            ],
          ),
        ],
        scriptAiRoleExtractionService: const _FakeRoleExtractionService(
          extraction,
        ),
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );

      await viewModel.importScriptPath(_fixturePath);
      viewModel.setRoleCharacter('slot-0', 'char-hero');
      viewModel.setRoleOutfit('slot-0', 'outfit-main');
      viewModel.setRoleStagePart(
        sourceRoleId: 'slot-0',
        stageId: 'slot-0-stage-1',
        part: StudioScriptRolePart.upperClothing,
        value: 'custom cape',
      );
      await viewModel.generateAiRoleExtraction();
      await viewModel.applyHighConfidenceAiRoleExtraction();

      final stage = viewModel.roleMappings.first.stageItems.single;
      expect(stage.id, 'slot-0-stage-1');
      expect(stage.label, 'ai refreshed label');
      expect(stage.selectedCharacterId, 'char-hero');
      expect(stage.selectedUpperOutfitId, 'outfit-main');
      expect(stage.selectedLowerOutfitId, 'outfit-main');
      expect(stage.sourceSummary, contains('blue jacket'));
      expect(stage.parts.upperClothing, 'custom cape');
      expect(stage.parts.lowerClothing, isNot('white skirt'));
    });

    test(
      'single role extraction stage merges into existing target stage',
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
                  stageId: 'see-through-dress',
                  label: 'see-through dress',
                  frameIndexes: [1, 2],
                  identity: 'ai hero',
                  upperBody: 'green eyes',
                  lowerBody: 'wide hips',
                  upperClothing: '',
                  lowerClothing: 'see-through dress',
                  confidence: 0.9,
                ),
              ],
            ),
          ],
        );
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => const [
            CharacterEntry(
              id: 'shamare',
              name: 'Shamare',
              defaultOutfitId: 'outfit-main',
              anchorTags: ['shamare_(arknights)'],
              traits: ViewVariantTexts(
                frontFull: 'shamare_(arknights), fox ears, fox tail',
                frontUpper: 'fox ears',
                frontLower: 'fox tail',
              ),
              outfits: [
                WorkspaceOutfit(
                  id: 'outfit-main',
                  name: 'Main outfit',
                  tags: ViewVariantTexts(frontFull: 'old dress'),
                  partTags: WorkspaceOutfitPartTags(
                    lowerClothingTags: ['old dress'],
                  ),
                ),
              ],
            ),
          ],
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            extraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        viewModel.setRoleCharacter('slot-0', 'shamare');
        await viewModel.generateAiRoleExtraction();
        await viewModel.applyHighConfidenceAiRoleExtraction();

        final stages = viewModel.roleMappings.first.stageItems;
        expect(stages, hasLength(1));
        expect(stages.single.id, 'slot-0-stage-1');
        expect(stages.single.label, 'see-through dress');
        expect(stages.single.selectedCharacterId, 'shamare');
        expect(stages.single.sourceParts.lowerClothing, 'see-through dress');
        expect(stages.single.parts.identity, 'shamare_(arknights)');
        expect(stages.single.parts.lowerClothing, 'old dress');
      },
    );

    test(
      'role extraction replaces local default stage instead of appending it',
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
                  stageId: 'see-through-dress',
                  label: 'see-through dress',
                  frameIndexes: [1],
                  lowerClothing: 'see-through dress',
                  confidence: 0.9,
                ),
                ScriptAiExtractedStage(
                  stageId: 'dress',
                  label: 'dress',
                  frameIndexes: [2],
                  lowerClothing: 'dress',
                  confidence: 0.9,
                ),
              ],
            ),
          ],
        );
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => const [
            CharacterEntry(
              id: 'shamare',
              name: 'Shamare',
              defaultOutfitId: 'outfit-main',
              anchorTags: ['shamare_(arknights)'],
              traits: ViewVariantTexts(
                frontFull: 'shamare_(arknights), fox ears, fox tail',
                frontUpper: 'fox ears',
                frontLower: 'fox tail',
              ),
              outfits: [
                WorkspaceOutfit(
                  id: 'outfit-main',
                  name: 'Main outfit',
                  tags: ViewVariantTexts(frontFull: 'old dress'),
                  partTags: WorkspaceOutfitPartTags(
                    lowerClothingTags: ['old dress'],
                  ),
                ),
              ],
            ),
          ],
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            extraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        expect(viewModel.roleMappings.first.stageItems, isEmpty);
        await viewModel.generateAiRoleExtraction();
        await viewModel.applyHighConfidenceAiRoleExtraction();

        final stages = viewModel.roleMappings.first.stageItems;
        expect(stages.map((stage) => stage.label), [
          'see-through dress',
          'dress',
        ]);
        expect(stages.map((stage) => stage.label), isNot(contains('鏈嶈 1')));
        expect(stages.first.sourceParts.lowerClothing, 'see-through dress');
        expect(stages.last.sourceParts.lowerClothing, 'dress');
        expect(stages.first.selectedCharacterId, isNull);
        expect(stages.first.parts.isEmpty, isTrue);
      },
    );

    test(
      'AI draft pending field omits transient role-state leftovers',
      () async {
        const extraction = ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.9,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'fujita kotone',
              confidence: 0.66,
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'stage-5-2',
                  label: 'Stage 5 2',
                  frameIndexes: [1],
                  identity: 'fujita kotone, girl, twin braids',
                  upperBody: 'black bow, medium breasts, wet hair',
                  upperClothing:
                      'collared shirt, naked shirt, open shirt, oversized shirt',
                  nonRole: 'blush, embarrassed, arms, legs, breasts, tail, '
                      'long sleeves, pussy, standing, wet, white shirt',
                  nonRoleMaterialized: true,
                  evidenceTerms: [
                    'wet hair',
                    'long sleeves',
                    'pussy',
                    'white shirt',
                  ],
                  confidence: 0.66,
                ),
              ],
            ),
          ],
        );
        final script = _singleFrameScript(
          baseCaption: 'artist:test',
          charCaptions: const [
            'fujita kotone, girl, twin braids, black bow, medium breasts, '
                'collared shirt, oversized shirt, white shirt, open shirt, '
                'naked shirt, blush, embarrassed, arms, legs, breasts, tail, '
                'standing, long sleeves, '
                'pussy, wet, wet hair',
          ],
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadCharacters: () async => const [],
          loadArtistChains: () async => const [],
          loadVibes: () async => const [],
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            extraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(script.rootPath);
        await viewModel.generateAiRoleExtraction();

        final stage = viewModel.aiRoleExtraction.roles.single.stages.single;
        expect(stage.nonRole, 'standing');
        expect(stage.lowerBody, isEmpty);
        expect(stage.upperBody, 'black bow, medium breasts');
        expect(
          stage.upperClothing,
          'collared shirt, oversized shirt, white shirt, long sleeves',
        );
        expect(stage.evidenceTerms, ['long sleeves', 'white shirt']);
      },
    );

    test(
      'manual role stage deletion can be restored by reapplying ai extraction',
      () async {
        const extraction = ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.9,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'Ako (Dress) Blue Archive',
              confidence: 0.9,
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'see-through-dress',
                  label: 'see-through dress',
                  frameIndexes: [1, 2],
                  lowerClothing: 'see-through dress',
                  confidence: 0.9,
                ),
                ScriptAiExtractedStage(
                  stageId: 'dress',
                  label: 'dress',
                  frameIndexes: [3],
                  lowerClothing: 'dress',
                  confidence: 0.9,
                ),
              ],
            ),
          ],
        );
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            extraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();
        await viewModel.applyHighConfidenceAiRoleExtraction();

        final firstStageId = viewModel.roleMappings.first.stageItems.first.id;
        viewModel.deleteRoleStage(
          sourceRoleId: 'slot-0',
          stageId: firstStageId,
        );

        var stages = viewModel.roleMappings.first.stageItems;
        expect(stages.map((stage) => stage.label), ['dress']);
        expect(stages.single.id, 'dress');

        await viewModel.applyHighConfidenceAiRoleExtraction();

        stages = viewModel.roleMappings.first.stageItems;
        expect(stages.map((stage) => stage.label), [
          'see-through dress',
          'dress',
        ]);

        viewModel.deleteRoleStage(
          sourceRoleId: 'slot-0',
          stageId: 'see-through-dress',
        );
        viewModel.deleteRoleStage(sourceRoleId: 'slot-0', stageId: 'dress');

        stages = viewModel.roleMappings.first.stageItems;
        expect(stages, isEmpty);
        expect(viewModel.roleMappings.first.selectedStage, isNull);

        await viewModel.applyHighConfidenceAiRoleExtraction();

        stages = viewModel.roleMappings.first.stageItems;
        expect(stages.map((stage) => stage.label), [
          'see-through dress',
          'dress',
        ]);
      },
    );

    test('applying role extraction preserves empty clothing fields', () async {
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
                stageId: 'empty-clothing',
                label: 'empty clothing',
                frameIndexes: [1],
                identity: 'ai hero',
                upperBody: 'green eyes',
                lowerBody: 'black boots',
                upperClothing: '',
                lowerClothing: '',
                confidence: 0.9,
              ),
            ],
          ),
        ],
      );
      final viewModel = StudioScriptViewModel(
        scriptAiRoleExtractionService: const _FakeRoleExtractionService(
          extraction,
        ),
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );

      await viewModel.importScriptPath(_fixturePath);
      await viewModel.generateAiRoleExtraction();
      await viewModel.applyHighConfidenceAiRoleExtraction();

      final stage = viewModel.roleMappings.first.stageItems.first;
      expect(viewModel.roleMappings.first.sourceLabel, 'AI Hero');
      expect(viewModel.roleMappings.first.sourcePreview, 'AI Hero');
      expect(stage.sourceSummary, contains('green eyes'));
      expect(stage.sourceSummary, contains('black boots'));
      expect(stage.parts.identity, isEmpty);
      expect(stage.parts.upperBody, isEmpty);
      expect(stage.parts.lowerBody, isEmpty);
      expect(stage.parts.upperClothing, isEmpty);
      expect(stage.parts.lowerClothing, isEmpty);
    });

    test(
      'role extraction draft does not write source parts into role mapping',
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
                  stageId: 'school-uniform-stage',
                  label: 'School uniform',
                  frameIndexes: [1],
                  identity: 'ai hero',
                  upperClothing: 'blue blazer',
                  lowerClothing: 'pleated skirt',
                  confidence: 0.9,
                ),
              ],
            ),
          ],
        );
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            extraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();

        expect(
          viewModel.aiRoleExtraction.roles.single.stages.single.upperClothing,
          'blue blazer',
        );
        expect(
          viewModel.aiRoleExtraction.roles.single.stages.single.lowerClothing,
          'pleated skirt',
        );
        final role = viewModel.roleMappings.first;
        expect(role.stageItems, isEmpty);
      },
    );

    test(
      'manual role field edits persist term overrides without auto replay',
      () async {
        const noisyExtraction = ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.9,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'AI Hero',
              confidence: 0.9,
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'main-outfit',
                  label: 'main outfit',
                  frameIndexes: [1],
                  identity: 'ai hero',
                  upperBody: 'braids, large breasts',
                  lowerBody: '',
                  upperClothing: 'blue jacket',
                  lowerClothing: '',
                  confidence: 0.9,
                ),
              ],
            ),
          ],
        );
        final classificationCache = PromptTagClassificationCache(
          clock: () => 1780000000,
        );
        var extraction = noisyExtraction;
        var savedClassificationCache = false;
        final viewModel = StudioScriptViewModel(
          classificationCache: classificationCache,
          saveClassificationCache: (_) async {
            savedClassificationCache = true;
          },
          scriptAiRoleExtractionService: _DeferredRoleExtractionService(
            () => extraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();
        viewModel.setAiRoleExtractionStageField(
          sourceRoleId: 'slot-0',
          stageId: 'main-outfit',
          part: StudioScriptRolePart.lowerBody,
          value: 'braids',
        );
        viewModel.setAiRoleExtractionStageField(
          sourceRoleId: 'slot-0',
          stageId: 'main-outfit',
          part: StudioScriptRolePart.upperBody,
          value: '',
        );

        final braidsEntry = classificationCache.entryFor('braids');
        final breastsEntry = classificationCache.entryFor('large breasts');
        expect(braidsEntry?.category, PromptTagCategory.lowerBody);
        expect(braidsEntry?.source, 'manual-role-field');
        expect(breastsEntry?.category, PromptTagCategory.other);
        expect(breastsEntry?.source, 'manual-role-omit');
        expect(savedClassificationCache, isTrue);

        extraction = noisyExtraction;
        await viewModel.generateAiRoleExtraction();

        final stage = viewModel.aiRoleExtraction.roles.single.stages.single;
        expect(stage.upperBody, 'braids, large breasts');
        expect(stage.lowerBody, isEmpty);
        expect(stage.upperClothing, 'blue jacket');
      },
    );

    test('apply cache adjustment rearranges visible AI draft only', () async {
      final classificationCache = PromptTagClassificationCache(
        clock: () => 1780000000,
      );
      classificationCache.setCategory(
        'braids',
        PromptTagCategory.lowerBody,
        source: 'manual-role-field',
      );
      classificationCache.setCategory(
        'large breasts',
        PromptTagCategory.other,
        source: 'manual-role-omit',
      );
      final viewModel = StudioScriptViewModel(
        classificationCache: classificationCache,
        parserService: _FakeParserService([
          _scriptWithFrames([
            (
              index: 1,
              base: 'city street',
              chars: ['ai hero, braids, large breasts, blue jacket'],
            ),
          ]),
        ]),
        scriptAiRoleExtractionService: const _FakeRoleExtractionService(
          ScriptAiRoleExtraction(
            status: ScriptAiRoleExtractionStatus.ready,
            confidence: 0.9,
            roles: [
              ScriptAiExtractedRole(
                sourceRoleId: 'slot-0',
                displayName: 'AI Hero',
                confidence: 0.9,
                stages: [
                  ScriptAiExtractedStage(
                    stageId: 'main-outfit',
                    label: 'main outfit',
                    frameIndexes: [1],
                    identity: 'ai hero',
                    upperBody: 'braids, large breasts',
                    upperClothing: 'blue jacket',
                    confidence: 0.9,
                  ),
                ],
              ),
            ],
          ),
        ),
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );

      await viewModel.importScriptPath('cache-adjust-script');
      await viewModel.generateAiRoleExtraction();

      var stage = viewModel.aiRoleExtraction.roles.single.stages.single;
      expect(stage.upperBody, 'braids, large breasts');
      expect(stage.lowerBody, isEmpty);
      expect(stage.nonRole, isEmpty);

      await viewModel.applyAiRoleExtractionCacheAdjustment();

      stage = viewModel.aiRoleExtraction.roles.single.stages.single;
      expect(stage.upperBody, isEmpty);
      expect(stage.lowerBody, 'braids');
      expect(stage.nonRole, 'large breasts');
      expect(viewModel.isAiRoleExtractionDraftCollapsed, isFalse);
    });

    test(
      'cache adjustment promotes costume-qualified candidate to identity',
      () async {
        final viewModel = StudioScriptViewModel()
          ..aiRoleExtraction = const ScriptAiRoleExtraction(
            status: ScriptAiRoleExtractionStatus.ready,
            roles: [
              ScriptAiExtractedRole(
                sourceRoleId: 'slot-0',
                stages: [
                  ScriptAiExtractedStage(
                    stageId: 'main-outfit',
                    identity: 'girl',
                    lowerClothing: 'see-through dress',
                    nonRole: 'ako (dress) (blue archive), smile',
                    nonRoleMaterialized: true,
                  ),
                ],
              ),
            ],
          );

        expect(viewModel.hasAiRoleExtractionCacheAdjustments, isTrue);

        await viewModel.applyAiRoleExtractionCacheAdjustment();

        final stage = viewModel.aiRoleExtraction.roles.single.stages.single;
        expect(stage.identity, 'girl, ako (dress) (blue archive)');
        expect(stage.nonRole, 'smile');
      },
    );

    test(
      'cleared non-role draft does not refill from stage evidence',
      () async {
        var caches = <RecastScriptCache>[];
        final seedViewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
          parserService: _FakeParserService([
            _scriptWithFrames([
              (
                index: 1,
                base: 'city street',
                chars: ['ai hero, blue jacket, smile'],
              ),
            ], rootPath: 'non-role-clear-script'),
          ]),
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            ScriptAiRoleExtraction(
              status: ScriptAiRoleExtractionStatus.ready,
              roles: [
                ScriptAiExtractedRole(
                  sourceRoleId: 'slot-0',
                  stages: [
                    ScriptAiExtractedStage(
                      stageId: 'main-outfit',
                      frameIndexes: [1],
                      identity: 'ai hero',
                      upperClothing: 'blue jacket',
                      confidence: 0.9,
                    ),
                  ],
                ),
              ],
            ),
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await seedViewModel.importScriptPath('non-role-clear-script');
        await seedViewModel.generateAiRoleExtraction();
        seedViewModel.setAiRoleExtractionStageField(
          sourceRoleId: 'slot-0',
          stageId: 'main-outfit',
          part: StudioScriptRolePart.nonRole,
          value: '',
        );
        await Future<void>.delayed(Duration.zero);

        var stage = seedViewModel.aiRoleExtraction.roles.single.stages.single;
        expect(stage.nonRoleMaterialized, isTrue);
        expect(stage.nonRole, isEmpty);

        final restoredViewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
          parserService: _FakeParserService([
            _scriptWithFrames([
              (
                index: 1,
                base: 'city street',
                chars: ['ai hero, blue jacket, smile'],
              ),
            ], rootPath: 'non-role-clear-script'),
          ]),
        );
        await restoredViewModel.importScriptPath('non-role-clear-script');

        stage = restoredViewModel.aiRoleExtraction.roles.single.stages.single;
        expect(stage.nonRoleMaterialized, isTrue);
        expect(stage.nonRole, isEmpty);
      },
    );

    test('editing non-role records manual other classification', () {
      final classificationCache = PromptTagClassificationCache(
        clock: () => 1710000000,
      );
      final viewModel =
          StudioScriptViewModel(classificationCache: classificationCache)
            ..aiRoleExtraction = const ScriptAiRoleExtraction(
              status: ScriptAiRoleExtractionStatus.ready,
              roles: [
                ScriptAiExtractedRole(
                  sourceRoleId: 'slot-0',
                  stages: [
                    ScriptAiExtractedStage(
                      stageId: 'main-outfit',
                      nonRoleMaterialized: true,
                    ),
                  ],
                ),
              ],
            );

      viewModel.setAiRoleExtractionStageField(
        sourceRoleId: 'slot-0',
        stageId: 'main-outfit',
        part: StudioScriptRolePart.nonRole,
        value: 'city street',
      );

      final entry = classificationCache.entryFor('city street');
      expect(entry?.category, PromptTagCategory.other);
      expect(entry?.source, 'manual-role-omit');
    });

    test('editing AI role stage fields syncs visible prompt terms', () {
      final viewModel = StudioScriptViewModel()
        ..aiRoleExtraction = const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              promptTerms: [
                ScriptAiExtractedPromptTerm(
                  id: 'old-jacket',
                  text: 'old jacket',
                  category: PromptTagCategory.upperClothing,
                ),
              ],
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'main-outfit',
                  identity: 'ai hero',
                  upperClothing: 'blue jacket',
                  frameIndexes: [1, 2],
                ),
              ],
            ),
          ],
        );

      viewModel.setAiRoleExtractionStageField(
        sourceRoleId: 'slot-0',
        stageId: 'main-outfit',
        part: StudioScriptRolePart.upperClothing,
        value: 'white dress',
      );

      expect(
        viewModel.aiRoleExtraction.roles.single.promptTerms
            .map((term) => term.text),
        orderedEquals(['ai hero', 'white dress']),
      );
      expect(
        viewModel.aiRoleExtraction.roles.single.promptTerms
            .map((term) => term.category),
        orderedEquals([
          PromptTagCategory.character,
          PromptTagCategory.upperClothing,
        ]),
      );
    });

    test('visible role prompt terms preserve stage prompt weights', () {
      final viewModel = StudioScriptViewModel()
        ..aiRoleExtraction = const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              promptTerms: [
                ScriptAiExtractedPromptTerm(
                  id: 'red-halo',
                  text: 'red halo',
                  category: PromptTagCategory.upperBody,
                ),
              ],
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'main-outfit',
                  identity: 'ai hero',
                  upperBody: '1.25:: red halo ::',
                  upperClothing: '0.75:: white dress ::',
                  frameIndexes: [1, 2],
                ),
              ],
            ),
          ],
        );

      viewModel.setAiRoleExtractionStageField(
        sourceRoleId: 'slot-0',
        stageId: 'main-outfit',
        part: StudioScriptRolePart.upperClothing,
        value: '0.8:: black jacket ::',
      );

      expect(
        viewModel.aiRoleExtraction.roles.single.promptTerms
            .map((term) => term.text),
        orderedEquals([
          'ai hero',
          '1.25:: red halo ::',
          '0.8:: black jacket ::',
        ]),
      );
    });

    test(
      'visible role prompt terms preserve exact existing frame indexes',
      () {
        final viewModel = StudioScriptViewModel()
          ..aiRoleExtraction = const ScriptAiRoleExtraction(
            status: ScriptAiRoleExtractionStatus.ready,
            roles: [
              ScriptAiExtractedRole(
                sourceRoleId: 'slot-0',
                promptTerms: [
                  ScriptAiExtractedPromptTerm(
                    id: 'sparse-body-term',
                    text: 'sparse body term',
                    category: PromptTagCategory.upperBody,
                    frameIndexes: [2],
                  ),
                ],
                stages: [
                  ScriptAiExtractedStage(
                    stageId: 'broad-stage',
                    upperBody: 'sparse body term',
                    upperClothing: 'blue jacket',
                    frameIndexes: [1, 2, 3],
                  ),
                ],
              ),
            ],
          );

        viewModel.setAiRoleExtractionStageField(
          sourceRoleId: 'slot-0',
          stageId: 'broad-stage',
          part: StudioScriptRolePart.upperClothing,
          value: 'white dress',
        );

        final terms = viewModel.aiRoleExtraction.roles.single.promptTerms;
        expect(
          terms
              .singleWhere((term) => term.text == 'sparse body term')
              .frameIndexes,
          [2],
        );
        expect(
          terms.singleWhere((term) => term.text == 'white dress').frameIndexes,
          [1, 2, 3],
        );
      },
    );

    test(
      'visible role prompt terms skip terms already covered by stage fields',
      () {
        final viewModel = StudioScriptViewModel()
          ..aiRoleExtraction = const ScriptAiRoleExtraction(
            status: ScriptAiRoleExtractionStatus.ready,
            roles: [
              ScriptAiExtractedRole(
                sourceRoleId: 'slot-0',
                promptTerms: [
                  ScriptAiExtractedPromptTerm(
                    id: 'black-kimono',
                    text: 'black kimono',
                    category: PromptTagCategory.clothing,
                  ),
                  ScriptAiExtractedPromptTerm(
                    id: 'panties-aside',
                    text: 'panties aside',
                    category: PromptTagCategory.clothing,
                  ),
                ],
                stages: [
                  ScriptAiExtractedStage(
                    stageId: 'main-outfit',
                    upperClothing: 'black kimono',
                    lowerClothing: 'black panties',
                    frameIndexes: [1, 2],
                  ),
                ],
              ),
            ],
          );

        viewModel.setAiRoleExtractionStageField(
          sourceRoleId: 'slot-0',
          stageId: 'main-outfit',
          part: StudioScriptRolePart.upperClothing,
          value: 'black kimono',
        );

        expect(
          viewModel.aiRoleExtraction.roles.single.promptTerms.map(
            (term) => '${term.category.name}:${term.text}',
          ),
          orderedEquals([
            'upperClothing:black kimono',
            'lowerClothing:black panties',
            'clothing:panties aside',
          ]),
        );
      },
    );

    test('visible role prompt terms merge repeated stage terms per role', () {
      final viewModel = StudioScriptViewModel()
        ..aiRoleExtraction = const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'main-outfit',
                  upperClothing: 'black kimono',
                  frameIndexes: [1],
                ),
                ScriptAiExtractedStage(
                  stageId: 'variant-outfit',
                  upperClothing: 'black kimono',
                  frameIndexes: [2, 3],
                ),
              ],
            ),
          ],
        );

      viewModel.setAiRoleExtractionStageField(
        sourceRoleId: 'slot-0',
        stageId: 'main-outfit',
        part: StudioScriptRolePart.upperClothing,
        value: 'black kimono',
      );

      expect(
        viewModel.aiRoleExtraction.roles.single.promptTerms.map(
          (term) => '${term.category.name}:${term.text}',
        ),
        orderedEquals(['upperClothing:black kimono']),
      );
      expect(
        viewModel.aiRoleExtraction.roles.single.promptTerms.single.frameIndexes,
        orderedEquals([1, 2, 3]),
      );
    });

    test(
      'apply AI role extraction uses edited stage fields as replacement source terms',
      () async {
        const extraction = ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.9,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'AI Hero',
              promptTerms: [
                ScriptAiExtractedPromptTerm(
                  id: 'stale-jacket',
                  text: 'old jacket',
                  category: PromptTagCategory.upperClothing,
                  sourcePhrase: 'old jacket evidence',
                  sourceLocation: 'slot-0 prompt',
                  frameIndexes: [1, 2],
                ),
              ],
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'main-outfit',
                  label: 'main outfit',
                  identity: 'ai hero',
                  upperClothing: 'blue jacket',
                  frameIndexes: [1, 2],
                ),
              ],
            ),
          ],
        );
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            extraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();
        viewModel.setAiRoleExtractionStageField(
          sourceRoleId: 'slot-0',
          stageId: 'main-outfit',
          part: StudioScriptRolePart.upperClothing,
          value: 'white dress',
        );
        await viewModel.applyAiRoleExtraction();

        expect(
          viewModel.roleReplacementMappings.single.rules
              .map((rule) => rule.sourceTerms.single.text),
          orderedEquals(['ai hero', 'white dress']),
        );
      },
    );

    test(
      'reapplying role extraction replaces previous AI-only stages',
      () async {
        var extraction = const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.9,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'AI Hero',
              confidence: 0.9,
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'first-ai-stage',
                  label: 'first ai stage',
                  frameIndexes: [1],
                  identity: 'ai hero',
                  upperClothing: '',
                  lowerClothing: 'first skirt',
                  confidence: 0.9,
                  missingFields: ['missing_upper_clothing'],
                ),
              ],
            ),
          ],
        );
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: _DeferredRoleExtractionService(
            () => extraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();
        await viewModel.applyHighConfidenceAiRoleExtraction();

        extraction = const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.9,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'AI Hero Refined',
              confidence: 0.9,
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'refined-ai-stage',
                  label: 'refined ai stage',
                  frameIndexes: [1, 2],
                  identity: 'ai hero refined',
                  upperClothing: 'refined jacket',
                  lowerClothing: 'refined skirt',
                  confidence: 0.9,
                ),
              ],
            ),
          ],
        );
        await viewModel.generateAiRoleExtraction();
        await viewModel.applyHighConfidenceAiRoleExtraction();

        final stages = viewModel.roleMappings.first.stageItems;
        expect(stages.map((stage) => stage.id), ['refined-ai-stage']);
        expect(viewModel.roleMappings.first.sourceLabel, 'AI Hero Refined');
        expect(viewModel.roleMappings.first.sourcePreview, 'AI Hero Refined');
        expect(stages.single.sourceSummary, contains('refined jacket'));
      },
    );

    test(
      'high confidence global role extraction creates role assembly',
      () async {
        const extraction = ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.9,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'global-0',
              displayName: 'Narrator',
              confidence: 0.91,
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'narrator-main',
                  label: 'narrator main',
                  frameIndexes: [1],
                  identity: 'narrator',
                  upperBody: 'silver hair',
                  lowerBody: 'boots',
                  upperClothing: 'cloak',
                  lowerClothing: 'trousers',
                  confidence: 0.86,
                ),
              ],
            ),
          ],
        );
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            extraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();
        await viewModel.applyHighConfidenceAiRoleExtraction();

        final globalRole = viewModel.roleMappings
            .where((role) => role.sourceRoleId == 'global-0')
            .single;
        expect(globalRole.sourceLabel, 'Narrator');
        expect(globalRole.sourcePreview, 'Narrator');
        expect(globalRole.stageItems.single.sourceSummary, contains('cloak'));
        expect(globalRole.stageItems.single.parts.identity, isEmpty);
        expect(globalRole.stageItems.single.parts.upperClothing, isEmpty);
      },
    );

    test(
      'slotless base role extraction can replace base caption via mapping',
      () async {
        const extraction = ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.9,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'global-0',
              sourceKind: 'global',
              displayName: 'Alice',
              confidence: 0.9,
              appearances: [
                ScriptAiRoleAppearance(
                  sourceId: 'base',
                  sourceKind: 'base',
                  frameIndexes: [1],
                ),
              ],
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'alice-base-main',
                  label: 'Alice base',
                  frameIndexes: [1],
                  identity: 'alice_(series)',
                  upperClothing: 'white shirt',
                  confidence: 0.9,
                ),
              ],
            ),
          ],
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([
            _singleFrameScript(
              id: 'slotless-base-script',
              name: 'Slotless Base Script',
              rootPath: 'slotless-base-script',
              baseCaption: 'alice_(series), white shirt, classroom',
            ),
          ]),
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            extraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath('slotless-base-script');
        await viewModel.generateAiRoleExtraction();
        await viewModel.applyHighConfidenceAiRoleExtraction();
        viewModel.setRoleStagePart(
          sourceRoleId: 'global-0',
          stageId: 'alice-base-main',
          part: StudioScriptRolePart.identity,
          value: 'target_alice',
        );

        final globalRole = viewModel.roleMappings.singleWhere(
          (role) => role.sourceRoleId == 'global-0',
        );
        expect(
          globalRole.stageItems.single.sourceParts.identity,
          'alice_(series)',
        );
        expect(viewModel.diff.recast, contains('target_alice'));
        expect(viewModel.diff.recast, isNot(contains('alice_(series)')));
        expect(viewModel.diff.recast, contains('white shirt'));
        expect(viewModel.diff.recast, contains('classroom'));
      },
    );

    test(
      'duplicate global role extraction source id creates one assembly',
      () async {
        const extraction = ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.9,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'global-0',
              displayName: 'Narrator',
              confidence: 0.91,
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'narrator-main',
                  frameIndexes: [1],
                  identity: 'narrator',
                  upperClothing: 'cloak',
                  confidence: 0.86,
                ),
              ],
            ),
            ScriptAiExtractedRole(
              sourceRoleId: 'global-0',
              displayName: 'Narrator duplicate',
              confidence: 0.92,
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'narrator-alt',
                  frameIndexes: [2],
                  identity: 'narrator duplicate',
                  upperClothing: 'coat',
                  confidence: 0.87,
                ),
              ],
            ),
          ],
        );
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            extraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();
        await viewModel.applyHighConfidenceAiRoleExtraction();

        final globalRoles = viewModel.roleMappings
            .where((role) => role.sourceRoleId == 'global-0')
            .toList();
        expect(globalRoles, hasLength(1));
        expect(globalRoles.single.sourcePreview, 'Narrator');
        expect(
          globalRoles.single.stageItems.single.sourceSummary,
          contains('cloak'),
        );
        expect(globalRoles.single.stageItems.single.parts.identity, isEmpty);
      },
    );

    test(
      'low confidence global role extraction applies when requested',
      () async {
        const extraction = ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.9,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'global-0',
              displayName: 'Unclear Extra',
              confidence: 0.5,
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'unclear-main',
                  frameIndexes: [1],
                  identity: 'unclear extra',
                  upperClothing: 'coat',
                  confidence: 0.9,
                ),
              ],
            ),
          ],
        );
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            extraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();
        await viewModel.applyHighConfidenceAiRoleExtraction();

        expect(
          viewModel.aiRoleExtraction.roles.single.displayName,
          'Unclear Extra',
        );
        final globalRole = viewModel.roleMappings
            .where((role) => role.sourceRoleId == 'global-0')
            .single;
        expect(globalRole.sourceLabel, 'Unclear Extra');
        expect(globalRole.sourcePreview, 'Unclear Extra');
        expect(
          globalRole.stageItems.single.sourceParts.identity,
          'unclear extra',
        );
        expect(globalRole.stageItems.single.sourceParts.upperClothing, 'coat');
        expect(globalRole.stageItems.single.parts.identity, isEmpty);
      },
    );

    test('applying role extraction appends strong filter keywords', () async {
      var filterRules = <String, dynamic>{};
      final viewModel = StudioScriptViewModel(
        loadFilterRules: () async => filterRules,
        saveFilterRules: (next) async => filterRules = next,
        scriptAiRoleExtractionService: const _FakeRoleExtractionService(
          ScriptAiRoleExtraction(
            status: ScriptAiRoleExtractionStatus.ready,
            confidence: 0.9,
            strongFilterKeywords: [
              ScriptAiStrongFilterKeyword(term: 'mosaic'),
              ScriptAiStrongFilterKeyword(term: 'censor bar'),
            ],
            roles: [
              ScriptAiExtractedRole(
                sourceRoleId: 'slot-0',
                displayName: 'AI Hero',
                confidence: 0.9,
                stages: [
                  ScriptAiExtractedStage(
                    stageId: 'main',
                    frameIndexes: [1],
                    identity: 'ai hero',
                    upperClothing: 'armor',
                    confidence: 0.9,
                  ),
                ],
              ),
            ],
          ),
        ),
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );

      await viewModel.importScriptPath(_fixturePath);
      await viewModel.generateAiRoleExtraction();
      await viewModel.applyHighConfidenceAiRoleExtraction();

      expect(filterRules['strong_filter_keywords'], contains('mosaic'));
      expect(filterRules['strong_filter_keywords'], contains('censor bar'));
    });

    test(
      'imports exact recast cache including AI role extraction draft',
      () async {
        var caches = <RecastScriptCache>[];
        final seedViewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            _highConfidenceSlotExtraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );
        await seedViewModel.importScriptPath(_fixturePath);
        await seedViewModel.generateAiRoleExtraction();

        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );
        await viewModel.importScriptPath(_fixturePath);

        expect(
          viewModel.aiRoleExtraction.status,
          ScriptAiRoleExtractionStatus.ready,
        );
        expect(viewModel.aiRoleExtraction.roles.single.displayName, 'AI Hero');
        expect(viewModel.aiStatus, contains('AI 瑙掕壊瀛楁鑽夌'));
      },
    );

    test(
      'imports cached script snapshot without reparsing source directory',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'studio-script-cached-png-snapshot-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
        await File(
          'test/fixtures/script_recast/v4_slotted/nai_1.json',
        ).copy('${tempDir.path}${Platform.pathSeparator}nai_1.json');
        await File(
          'test/fixtures/script_recast/v4_slotted/nai_2.json',
        ).copy('${tempDir.path}${Platform.pathSeparator}nai_2.json');
        await File(
          '${tempDir.path}${Platform.pathSeparator}nai_1.png',
        ).writeAsBytes(const [137, 80, 78, 71]);
        await File(
          '${tempDir.path}${Platform.pathSeparator}nai_2.png',
        ).writeAsBytes(const [137, 80, 78, 71]);
        final parsedScript =
            await const ScriptRecastParserService().parseDirectory(tempDir);
        final caches = [
          RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: tempDir.path,
            sourceFingerprint: 'cached-snapshot',
            updatedAt: DateTime.utc(2026, 6, 8, 8),
            mapping: RecastMapping.defaults(parsedScript.id),
            aiRoleExtraction: _highConfidenceSlotExtraction,
            scriptSnapshot: parsedScript.toJson(),
          ),
        ];
        final viewModel = StudioScriptViewModel(
          parserService: _ThrowingParserService(),
          loadRecastCaches: () async => caches,
        );

        await viewModel.importScriptPath(tempDir.path);

        expect(viewModel.frameCount, parsedScript.frames.length);
        expect(
          viewModel.aiRoleExtraction.status,
          ScriptAiRoleExtractionStatus.ready,
        );
        expect(viewModel.aiRoleExtraction.roles.single.displayName, 'AI Hero');
      },
    );

    test(
      'restored AI extraction materializes source fields from cache',
      () async {
        var caches = <RecastScriptCache>[];
        final seedViewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            _highConfidenceSlotExtraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );
        await seedViewModel.importScriptPath(_fixturePath);
        await seedViewModel.generateAiRoleExtraction();
        final cache = caches.single;
        caches = [
          RecastScriptCache(
            scriptId: cache.scriptId,
            scriptName: cache.scriptName,
            sourceRootPath: cache.sourceRootPath,
            sourceFingerprint: cache.sourceFingerprint,
            updatedAt: cache.updatedAt,
            mapping: cache.mapping.copyWith(
              roleAssemblies: const [
                RoleAssembly(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourceName: 'vulpisfoglia_(arknights)',
                  stages: [
                    RoleAssemblyStage(
                      id: 'main-outfit',
                      label: 'main outfit',
                      frameIndexes: [1, 2],
                      sourceSummary:
                          'blue jacket, white skirt, green eyes, black boots',
                    ),
                  ],
                ),
              ],
            ),
            aiRoleExtraction: cache.aiRoleExtraction,
            scriptSnapshot: cache.scriptSnapshot,
          ),
        ];

        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );
        await viewModel.importScriptPath(_fixturePath);

        final role = viewModel.roleMappings.first;
        final stage = role.stageItems.single;
        expect(role.sourcePreview, 'AI Hero');
        expect(stage.sourceParts.identity, 'ai hero');
        expect(stage.sourceParts.upperBody, 'green eyes');
        expect(stage.sourceParts.lowerBody, 'black boots');
        expect(stage.sourceParts.upperClothing, 'blue jacket');
        expect(stage.sourceParts.lowerClothing, 'white skirt');
        expect(stage.parts.upperClothing, isEmpty);
      },
    );

    test(
      'restored AI extraction recovers replacement terms from cached raw response',
      () async {
        final parsedScript = await const ScriptRecastParserService()
            .parseDirectory(Directory(_fixturePath));
        const rawResponse = '''
{
  "status": "ready",
  "confidence": 0.93,
  "roles": [
    {
      "source_role_id": "slot-0",
      "display_name": "AI Hero",
      "prompt_terms": [
        {
          "id": "blue-jacket",
          "text": "blue jacket",
          "category": "upper_clothing",
          "source_phrase": "ai hero, blue jacket",
          "source_location": "slot-0 prompt",
          "frame_indexes": [1, 2]
        },
        {
          "id": "stomach-bulge",
          "text": "stomach bulge",
          "category": "body",
          "source_phrase": "ai hero, stomach bulge",
          "source_location": "slot-0 prompt",
          "frame_indexes": [2]
        }
      ],
      "stages": [
        {
          "stage_id": "main-outfit",
          "label": "main outfit",
          "frame_indexes": [1, 2],
          "identity": "ai hero",
          "upper_clothing": "blue jacket"
        }
      ]
    }
  ],
  "scene_terms": [
    {
      "id": "rainy-street",
      "text": "rainy city street",
      "category": "scene",
      "source_phrase": "in a rainy city street",
      "source_location": "base prompt",
      "frame_indexes": [1, 2]
    }
  ]
}
''';
        final caches = [
          RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: _fixturePath,
            sourceFingerprint: _sourceFingerprintForTest(parsedScript),
            updatedAt: DateTime.utc(2026, 6, 15, 12),
            mapping: RecastMapping.defaults(parsedScript.id),
            aiRoleExtraction: ScriptAiRoleExtraction(
              status: ScriptAiRoleExtractionStatus.ready,
              roles: [
                ScriptAiExtractedRole(
                  sourceRoleId: 'slot-0',
                  displayName: 'AI Hero',
                  stages: [
                    ScriptAiExtractedStage(
                      stageId: 'main-outfit',
                      label: 'main outfit',
                      frameIndexes: [1, 2],
                      identity: 'ai hero',
                      upperClothing: 'blue jacket',
                    ),
                  ],
                ),
              ],
              rawResponse: rawResponse,
            ),
            scriptSnapshot: parsedScript.toJson(),
          ),
        ];
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
        );

        await viewModel.importScriptPath(_fixturePath);

        expect(
          viewModel.aiRoleExtraction.roles.single.promptTerms
              .map((term) => term.text),
          orderedEquals(['ai hero', 'blue jacket', 'stomach bulge']),
        );
        expect(
          viewModel.aiRoleExtraction.sceneTerms.single.text,
          'rainy city street',
        );

        await viewModel.applyAiRoleExtraction();

        expect(
          viewModel.roleReplacementMappings.single.rules
              .map((rule) => rule.sourceTerms.single.text),
          orderedEquals(['ai hero', 'blue jacket', 'stomach bulge']),
        );
        expect(
          viewModel.sceneReplacementMappings.single.rules.single.sourceTerms
              .single.text,
          'rainy city street',
        );
      },
    );

    test('restored cache narrows replacement term frames to source evidence',
        () async {
      final parsedScript = await const ScriptRecastParserService()
          .parseDirectory(Directory(_fixturePath));
      final caches = [
        RecastScriptCache(
          scriptId: parsedScript.id,
          scriptName: parsedScript.name,
          sourceRootPath: _fixturePath,
          sourceFingerprint: _sourceFingerprintForTest(parsedScript),
          updatedAt: DateTime.utc(2026, 6, 20, 3),
          mapping: RecastMapping(
            id: 'mapping-${parsedScript.id}',
            scriptId: parsedScript.id,
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-0',
                displayLabel: 'slot 0',
                rules: [
                  ScriptPromptReplacementRule(
                    id: 'fox-tail',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'fox-tail-term',
                        text: 'fox_tail',
                        category: PromptTagCategory.lowerBody,
                        frameIndexes: [1, 2],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          aiRoleExtraction: const ScriptAiRoleExtraction(),
          scriptSnapshot: parsedScript.toJson(),
        ),
      ];
      final viewModel = StudioScriptViewModel(
        loadRecastCaches: () async => caches,
      );

      await viewModel.importScriptPath(_fixturePath);

      final rule = viewModel.roleReplacementMappings.single.rules.single;
      expect(rule.sourceTerms.single.frameIndexes, [1]);
    });

    test(
      'restored AI extraction owns source fields over stale cache parts',
      () async {
        var caches = <RecastScriptCache>[];
        final seedViewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            _highConfidenceSlotExtraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );
        await seedViewModel.importScriptPath(_fixturePath);
        await seedViewModel.generateAiRoleExtraction();
        final cache = caches.single;
        caches = [
          RecastScriptCache(
            scriptId: cache.scriptId,
            scriptName: cache.scriptName,
            sourceRootPath: cache.sourceRootPath,
            sourceFingerprint: cache.sourceFingerprint,
            updatedAt: cache.updatedAt,
            mapping: cache.mapping.copyWith(
              roleAssemblies: const [
                RoleAssembly(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourceName: 'AI Hero',
                  stages: [
                    RoleAssemblyStage(
                      id: 'main-outfit',
                      label: 'main outfit',
                      frameIndexes: [1, 2],
                      sourceSummary: 'blue jacket',
                      sourceParts: RecastPromptParts(
                        upperClothing: 'blue jacket',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            aiRoleExtraction: cache.aiRoleExtraction,
            scriptSnapshot: cache.scriptSnapshot,
          ),
        ];

        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );
        await viewModel.importScriptPath(_fixturePath);

        final stage = viewModel.roleMappings.first.stageItems.single;
        expect(stage.sourceParts.identity, 'ai hero');
        expect(stage.sourceParts.upperBody, 'green eyes');
        expect(stage.sourceParts.lowerBody, 'black boots');
        expect(stage.sourceParts.upperClothing, 'blue jacket');
        expect(stage.sourceParts.lowerClothing, 'white skirt');
      },
    );

    test(
      'structured source identity does not spill summary into source clothing',
      () async {
        var caches = <RecastScriptCache>[];
        final seedViewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );
        await seedViewModel.importScriptPath(_fixturePath);
        await seedViewModel.useFreshParseForChangedSource();
        final cache = caches.single;
        caches = [
          RecastScriptCache(
            scriptId: cache.scriptId,
            scriptName: cache.scriptName,
            sourceRootPath: cache.sourceRootPath,
            sourceFingerprint: cache.sourceFingerprint,
            updatedAt: cache.updatedAt,
            mapping: cache.mapping.copyWith(
              roleAssemblies: const [
                RoleAssembly(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'Nagasaki Soyo',
                  sourceName: 'Nagasaki Soyo',
                  stages: [
                    RoleAssemblyStage(
                      id: 'identity-only',
                      label: 'nude',
                      frameIndexes: [1],
                      sourceSummary:
                          'nagasaki soyo, girl, sweat droplets, lying on back',
                      sourceParts: RecastPromptParts(
                        identity: 'nagasaki soyo, girl',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            scriptSnapshot: cache.scriptSnapshot,
          ),
        ];
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
        );
        await viewModel.importScriptPath(_fixturePath);

        final stage = viewModel.roleMappings.first.stageItems.single;
        expect(stage.sourceParts.identity, 'nagasaki soyo, girl');
        expect(stage.sourceParts.upperClothing, isEmpty);
      },
    );

    test(
      'does not restore exact cache when same length raw json content changes',
      () async {
        final parsedScript = await const ScriptRecastParserService()
            .parseDirectory(Directory(_fixturePath));
        final changedScript = _scriptWithChangedSameLengthRawJson(parsedScript);
        var caches = <RecastScriptCache>[];
        const extraction = ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.9,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'Stale Same Length AI Hero',
              confidence: 0.9,
            ),
          ],
        );
        final seedViewModel = StudioScriptViewModel(
          parserService: _FakeParserService([parsedScript]),
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            extraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );
        await seedViewModel.importScriptPath(_fixturePath);
        await seedViewModel.generateAiRoleExtraction();

        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([changedScript]),
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );
        await viewModel.importScriptPath(_fixturePath);

        expect(
          viewModel.aiRoleExtraction.status,
          ScriptAiRoleExtractionStatus.idle,
        );
        expect(viewModel.aiRoleExtraction.roles, isEmpty);
      },
    );

    test(
      'restores recast cache when identical script content moves path',
      () async {
        final originalScript = _singleFrameScript(
          id: 'script-old-path',
          name: 'Moved Script',
          rootPath: r'C:\scripts\old-path',
          baseCaption: 'artist:moved-cache, city lights',
        );
        final movedScript = _singleFrameScript(
          id: 'script-new-path',
          name: 'Moved Script',
          rootPath: r'D:\scripts\new-path',
          baseCaption: 'artist:moved-cache, city lights',
        );
        final caches = [
          RecastScriptCache(
            scriptId: originalScript.id,
            scriptName: originalScript.name,
            sourceRootPath: originalScript.rootPath,
            sourceFingerprint: _testSourceFingerprint(originalScript),
            updatedAt: DateTime.utc(2026, 6, 9),
            mapping: RecastMapping.defaults(originalScript.id),
            aiRoleExtraction: const ScriptAiRoleExtraction(
              status: ScriptAiRoleExtractionStatus.ready,
              roles: [
                ScriptAiExtractedRole(
                  sourceRoleId: 'slot-0',
                  displayName: 'Moved AI Hero',
                ),
              ],
            ),
            scriptSnapshot: originalScript.toJson(),
          ),
        ];
        var targetedLoadCount = 0;
        var bulkLoadCount = 0;
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([movedScript]),
          loadRecastCacheByScriptId: (scriptId) async {
            targetedLoadCount += 1;
            expect(scriptId, movedScript.id);
            return null;
          },
          loadRecastCaches: () async {
            bulkLoadCount += 1;
            return caches;
          },
        );

        await viewModel.importScriptPath(movedScript.rootPath);

        expect(targetedLoadCount, 1);
        expect(bulkLoadCount, greaterThanOrEqualTo(1));
        expect(
          viewModel.aiRoleExtraction.status,
          ScriptAiRoleExtractionStatus.ready,
        );
        expect(
          viewModel.aiRoleExtraction.roles.single.displayName,
          'Moved AI Hero',
        );
      },
    );

    test(
      'does not restore moved recast cache when script content changes',
      () async {
        final originalScript = _singleFrameScript(
          id: 'script-old-path',
          name: 'Moved Script',
          rootPath: r'C:\scripts\old-path',
          baseCaption: 'artist:moved-cache, city lights',
        );
        final movedScript = _scriptWithChangedSameLengthRawJson(
          _singleFrameScript(
            id: 'script-new-path',
            name: 'Moved Script',
            rootPath: r'D:\scripts\new-path',
            baseCaption: 'artist:moved-cache, city lights',
          ),
        );
        final caches = [
          RecastScriptCache(
            scriptId: originalScript.id,
            scriptName: originalScript.name,
            sourceRootPath: originalScript.rootPath,
            sourceFingerprint: _testSourceFingerprint(originalScript),
            updatedAt: DateTime.utc(2026, 6, 9),
            mapping: RecastMapping.defaults(originalScript.id),
            aiRoleExtraction: const ScriptAiRoleExtraction(
              status: ScriptAiRoleExtractionStatus.ready,
              roles: [
                ScriptAiExtractedRole(
                  sourceRoleId: 'slot-0',
                  displayName: 'Stale Moved AI Hero',
                ),
              ],
            ),
            scriptSnapshot: originalScript.toJson(),
          ),
        ];
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([movedScript]),
          loadRecastCaches: () async => caches,
        );

        await viewModel.importScriptPath(movedScript.rootPath);

        expect(
          viewModel.aiRoleExtraction.status,
          ScriptAiRoleExtractionStatus.idle,
        );
        expect(viewModel.aiRoleExtraction.roles, isEmpty);
      },
    );

    test('manual vibe selection is included in production payloads', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'studio-script-manual-vibe-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final workspaceService = WorkspaceService();
      await workspaceService.createWorkspace(tempDir.path);
      final productionService = ScriptRecastProductionService(
        queueService: ProductionQueueService(
          workspaceService: workspaceService,
        ),
        now: () => DateTime.utc(2026, 5, 28, 8),
      );
      final viewModel = StudioScriptViewModel(
        productionService: productionService,
        loadCharacters: workspaceService.loadCharacters,
        loadArtistChains: workspaceService.loadArtistChains,
        loadVibes: () async => const [
          WorkspaceVibeReference(
            id: 'manual-vibe',
            name: 'Manual Vibe',
            vibeB64: 'encoded-manual-vibe',
            referenceStrength: 0.55,
          ),
        ],
      );

      await viewModel.importScriptPath(_fixturePath);
      viewModel.setManualVibe('manual-vibe', true);
      viewModel.setManualVibeStrength('manual-vibe', 0.72);
      await viewModel.sendToProduction();

      final plans = await workspaceService.loadProductionPlans();
      final parameters = plans.single.tasks.first.payload['parameters']
          as Map<String, dynamic>;
      expect(parameters['reference_image_multiple'], ['encoded-manual-vibe']);
      expect(parameters['reference_strength_multiple'], [0.72]);
      expect(viewModel.selectedManualVibes.single.name, 'Manual Vibe');
      expect(viewModel.selectedManualVibes.single.referenceStrength, 0.72);
    });

    test('manual vibe edits do not recompute every script frame', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'studio-script-vibe-lightweight-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final workspaceService = WorkspaceService();
      await workspaceService.createWorkspace(tempDir.path);
      final productionService = ScriptRecastProductionService(
        queueService: ProductionQueueService(
          workspaceService: workspaceService,
        ),
        now: () => DateTime.utc(2026, 6, 3, 13),
      );
      final recastEngine = _CountingRecastEngine();
      final viewModel = StudioScriptViewModel(
        recastEngine: recastEngine,
        productionService: productionService,
        loadVibes: () async => const [
          WorkspaceVibeReference(
            id: 'manual-vibe',
            name: 'Manual Vibe',
            vibeB64: 'encoded-manual-vibe',
            referenceStrength: 0.55,
          ),
        ],
      );

      await viewModel.importScriptPath(_fixturePath);
      recastEngine.resolveCallCount = 0;

      viewModel.setManualVibe('manual-vibe', true);
      viewModel.setManualVibeStrength('manual-vibe', 0.72);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(recastEngine.resolveCallCount, 0);

      await viewModel.sendToProduction();
      expect(recastEngine.resolveCallCount, 1);
    });

    test(
      'role edits refresh selected preview without resolving full script',
      () async {
        final recastEngine = _CountingRecastEngine();
        final script = _largeScript(frameCount: 360, roleSlots: 3);
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          recastEngine: recastEngine,
          loadCharacters: () async => const [
            CharacterEntry(
              id: 'char-large',
              name: 'Large Hero',
              traits: ViewVariantTexts(frontFull: 'large hero'),
              anchorTags: ['large_hero'],
            ),
          ],
        );

        await viewModel.importScriptPath('large-script');
        recastEngine.resolveCallCount = 0;

        final sourceRoleId = viewModel.roleMappings.first.sourceRoleId;
        final stageId = viewModel.roleMappings.first.stageItems.first.id;
        viewModel.setRoleCharacter(sourceRoleId, 'char-large');
        viewModel.setRoleStagePart(
          sourceRoleId: sourceRoleId,
          stageId: stageId,
          part: StudioScriptRolePart.upperClothing,
          value: 'custom jacket',
        );

        expect(recastEngine.resolveCallCount, 0);
        expect(viewModel.diff.recast, contains('large_hero'));
        expect(viewModel.diff.recast, contains('custom jacket'));
      },
    );

    test(
      'selecting frames keeps mapping lists stable for large scripts',
      () async {
        final recastEngine = _CountingRecastEngine();
        final script = _largeScript(frameCount: 360, roleSlots: 3);
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          recastEngine: recastEngine,
        );

        await viewModel.importScriptPath('large-script');
        final roleMappings = viewModel.roleMappings;
        final artistMappings = viewModel.artistMappings;
        final promptBlockMappings = viewModel.promptBlockMappings;
        recastEngine.resolveCallCount = 0;
        recastEngine.frameResolveCallCount = 0;

        viewModel.selectFrame(240);

        expect(recastEngine.resolveCallCount, 0);
        expect(recastEngine.frameResolveCallCount, 1);
        expect(identical(viewModel.roleMappings, roleMappings), isTrue);
        expect(identical(viewModel.artistMappings, artistMappings), isTrue);
        expect(
          identical(viewModel.promptBlockMappings, promptBlockMappings),
          isTrue,
        );
        expect(viewModel.recastPlan.frameReviews.single.frameIndex, 240);
      },
    );

    test(
      'artist edits preserve unrelated mapping lists for large scripts',
      () async {
        final recastEngine = _CountingRecastEngine();
        final script = _largeScript(frameCount: 360, roleSlots: 3);
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          recastEngine: recastEngine,
        );

        await viewModel.importScriptPath('large-script');
        recastEngine.resolveCallCount = 0;
        final roleMappings = viewModel.roleMappings;
        final promptBlockMappings = viewModel.promptBlockMappings;

        viewModel.setManualArtistPrompt('artist:new_large_artist');

        expect(recastEngine.resolveCallCount, 0);
        expect(identical(viewModel.roleMappings, roleMappings), isTrue);
        expect(
          identical(viewModel.promptBlockMappings, promptBlockMappings),
          isTrue,
        );
        expect(
          viewModel.artistMappings.single.manualPrompt,
          'artist:new_large_artist',
        );
        expect(viewModel.diff.recast, contains('artist:new_large_artist'));
      },
    );

    test(
      'prompt block edits preserve unrelated mapping lists for large scripts',
      () async {
        final recastEngine = _CountingRecastEngine();
        final script = _largeScript(frameCount: 360, roleSlots: 3);
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          recastEngine: recastEngine,
        );

        await viewModel.importScriptPath('large-script');
        recastEngine.resolveCallCount = 0;
        final roleMappings = viewModel.roleMappings;
        final artistMappings = viewModel.artistMappings;

        viewModel.setPromptBlockSource('style', 'city lights');
        viewModel.setPromptBlockManualPrompt('style', 'watercolor skyline');

        expect(recastEngine.resolveCallCount, 0);
        expect(identical(viewModel.roleMappings, roleMappings), isTrue);
        expect(identical(viewModel.artistMappings, artistMappings), isTrue);
        expect(
          viewModel.promptBlockMappings
              .singleWhere((item) => item.block == 'style')
              .manualPrompt,
          'watercolor skyline',
        );
        expect(viewModel.diff.recast, contains('watercolor skyline'));
      },
    );

    test('role stage edits preserve unrelated mapping objects', () async {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        confidence: 0.9,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'role-a',
            displayName: 'Role A',
            confidence: 0.9,
            stages: [
              ScriptAiExtractedStage(
                stageId: 'role-a-main',
                label: 'main',
                frameIndexes: [1],
                identity: 'role a',
                upperClothing: 'blue jacket',
                confidence: 0.9,
              ),
            ],
          ),
          ScriptAiExtractedRole(
            sourceRoleId: 'role-b',
            displayName: 'Role B',
            confidence: 0.9,
            stages: [
              ScriptAiExtractedStage(
                stageId: 'role-b-main',
                label: 'main',
                frameIndexes: [1],
                identity: 'role b',
                upperClothing: 'red jacket',
                confidence: 0.9,
              ),
            ],
          ),
        ],
      );
      final viewModel = StudioScriptViewModel(
        scriptAiRoleExtractionService: const _FakeRoleExtractionService(
          extraction,
        ),
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );

      await viewModel.importScriptPath(_fixturePath);
      await viewModel.generateAiRoleExtraction();
      await viewModel.applyHighConfidenceAiRoleExtraction();
      final beforeRoleA = viewModel.roleMappings[0];
      final beforeRoleB = viewModel.roleMappings[1];
      final beforeArtistMappings = viewModel.artistMappings;
      final beforePromptBlockMappings = viewModel.promptBlockMappings;

      viewModel.setRoleStagePart(
        sourceRoleId: beforeRoleA.sourceRoleId,
        stageId: beforeRoleA.stageItems.first.id,
        part: StudioScriptRolePart.upperClothing,
        value: 'custom jacket',
      );

      expect(identical(viewModel.roleMappings[0], beforeRoleA), isFalse);
      expect(identical(viewModel.roleMappings[1], beforeRoleB), isTrue);
      expect(identical(viewModel.artistMappings, beforeArtistMappings), isTrue);
      expect(
        identical(viewModel.promptBlockMappings, beforePromptBlockMappings),
        isTrue,
      );
      expect(
        viewModel.roleMappings[0].stageItems.first.parts.upperClothing,
        'custom jacket',
      );
    });

    testWidgets('role edits keep unrelated page regions stable', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel(
        loadCharacters: () async => const [
          CharacterEntry(
            id: 'char-page',
            name: 'Page Hero',
            traits: ViewVariantTexts(frontFull: 'page hero'),
            anchorTags: ['page_hero'],
          ),
        ],
      );

      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });
      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();

      final drawerFinder = find.byKey(
        const ValueKey('script-layout-left-drawer'),
      );
      final timelineFinder = find.byKey(
        const ValueKey('script-layout-bottom-timeline'),
      );
      expect(drawerFinder, findsOneWidget);
      expect(timelineFinder, findsOneWidget);
      final drawerBefore = tester.widget(drawerFinder);
      final timelineBefore = tester.widget(timelineFinder);
      final sourceRoleId = viewModel.roleMappings.first.sourceRoleId;

      viewModel.setRoleCharacter(sourceRoleId, 'char-page');
      await tester.pump();

      expect(identical(tester.widget(drawerFinder), drawerBefore), isTrue);
      expect(identical(tester.widget(timelineFinder), timelineBefore), isTrue);
      expect(viewModel.roleMappings.first.selectedCharacterId, 'char-page');
    });

    test('selected frame is split into tagged review cards', () async {
      final viewModel = StudioScriptViewModel();

      await viewModel.importScriptPath(_fixturePath);

      expect(viewModel.selectedFrameTagGroups.map((group) => group.id), [
        'role-1',
        'role-2',
        'artist-chain',
        'quality',
        'scene',
      ]);
      expect(viewModel.selectedFrameTagGroups[0].tags, contains('fox_tail'));
      expect(
        viewModel.selectedFrameTagGroups[2].tags,
        contains('0.8:: artist:terasu_mc ::'),
      );
      expect(viewModel.selectedFrameTagGroups[4].tags, contains('city lights'));

      viewModel.selectFrame(2);

      expect(
        viewModel.selectedFrameTagGroups[4].tags,
        containsAll(['train platform', 'night rain']),
      );
    });

    test(
      'role source cards show stage source fields after frame selection changes',
      () async {
        final script = _scriptWithFrames(
          [
            (
              index: 1,
              base: 'artist:test, street',
              chars: [
                'boy, caelus_(honkai:_star_rail), black gloves, white shirt',
                'sparkle (honkai: star rail), smile, looking at viewer',
              ],
            ),
            (
              index: 2,
              base: 'artist:test, street',
              chars: [
                'boy, caelus_(honkai:_star_rail), black gloves, white shirt',
                'sparkle (honkai: star rail), fox mask, flower tattoo, '
                    'black gloves',
              ],
            ),
          ],
          id: 'frame-scoped-role-source-script',
          name: 'Frame Scoped Role Source Script',
          rootPath: r'C:\scripts\frame-scoped-role-source-script',
        );
        final caches = [
          RecastScriptCache(
            scriptId: script.id,
            scriptName: script.name,
            sourceRootPath: script.rootPath,
            sourceFingerprint: _testSourceFingerprint(script),
            updatedAt: DateTime.utc(2026, 6, 9),
            mapping: RecastMapping.defaults(script.id).copyWith(
              roleAssemblies: const [
                RoleAssembly(
                  sourceRoleId: 'role-sparkle',
                  displayLabel: 'Sparkle (Honkai: Star Rail)',
                  sourceName: 'Sparkle (Honkai: Star Rail)',
                  stages: [
                    RoleAssemblyStage(
                      id: 'sparkle-stage',
                      label: 'red dress',
                      frameIndexes: [1, 2],
                      sourceParts: RecastPromptParts(
                        identity: 'sparkle (honkai: star rail)',
                        upperBody: 'fox mask often present, flower tattoo',
                        upperClothing: 'black gloves in some early frames',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ];
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadRecastCaches: () async => caches,
        );

        await viewModel.importScriptPath(script.rootPath);

        final frameOneStage = viewModel.roleMappings.single.stageItems.single;
        expect(
          frameOneStage.sourceParts.upperBody,
          'fox mask often present, flower tattoo',
        );
        expect(
          frameOneStage.sourceParts.upperClothing,
          'black gloves in some early frames',
        );
        expect(
          frameOneStage.visibleSourceParts.identity,
          'sparkle (honkai: star rail)',
        );
        expect(
          frameOneStage.visibleSourceParts.upperBody,
          'fox mask often present, flower tattoo',
        );
        expect(
          frameOneStage.visibleSourceParts.upperClothing,
          'black gloves in some early frames',
        );
        expect(frameOneStage.currentFrameSourceParts?.upperBody, isEmpty);
        expect(frameOneStage.currentFrameSourceParts?.upperClothing, isEmpty);
        expect(frameOneStage.isCurrentFrameSourceScoped, isFalse);

        viewModel.selectFrame(2);

        final frameTwoStage = viewModel.roleMappings.single.stageItems.single;
        expect(
          frameTwoStage.visibleSourceParts.upperBody,
          'fox mask often present, flower tattoo',
        );
        expect(
          frameTwoStage.visibleSourceParts.upperClothing,
          'black gloves in some early frames',
        );
        expect(
          frameTwoStage.currentFrameSourceParts?.upperBody,
          'fox mask, flower tattoo',
        );
        expect(
          frameTwoStage.currentFrameSourceParts?.upperClothing,
          'black gloves',
        );
      },
    );

    test(
      'role mapping selects the outfit stage that contains the current frame',
      () async {
        final script = _scriptWithFrames(
          [
            (
              index: 1,
              base: 'artist:test, workshop',
              chars: [
                'girl, aoi (princess connect!), black tank top, overall skirt',
              ],
            ),
            (
              index: 2,
              base: 'artist:test, bedroom',
              chars: [
                'girl, aoi (princess connect!), completely nude',
              ],
            ),
          ],
          id: 'frame-stage-selection-script',
          name: 'Frame Stage Selection Script',
          rootPath: r'C:\scripts\frame-stage-selection-script',
        );
        final caches = [
          RecastScriptCache(
            scriptId: script.id,
            scriptName: script.name,
            sourceRootPath: script.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(script),
            updatedAt: DateTime.utc(2026, 6, 12),
            mapping: RecastMapping.defaults(script.id).copyWith(
              roleAssemblies: const [
                RoleAssembly(
                  sourceRoleId: 'role-aoi',
                  displayLabel: 'aoi (princess connect!) / Aoi',
                  sourceName: 'aoi (princess connect!)',
                  stages: [
                    RoleAssemblyStage(
                      id: 'tank-top',
                      label: '黑色背心 / 背带裙',
                      frameIndexes: [1],
                      sourceParts: RecastPromptParts(
                        identity: 'aoi (princess connect!), girl',
                        upperClothing: 'black tank top',
                        lowerClothing: 'overall skirt',
                      ),
                    ),
                    RoleAssemblyStage(
                      id: 'nude',
                      label: '裸体',
                      frameIndexes: [2],
                      sourceParts: RecastPromptParts(
                        identity: 'aoi (princess connect!), girl',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            scriptSnapshot: script.toJson(),
          ),
        ];
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadRecastCacheByScriptId: (_) async => caches.single,
        );

        await viewModel.importScriptPath(script.rootPath);

        expect(viewModel.roleMappings.single.selectedStage!.id, 'tank-top');

        viewModel.selectFrame(2);

        expect(viewModel.roleMappings.single.selectedStage!.id, 'nude');
        expect(viewModel.roleMappings.single.selectedStage!.label, '裸体');

        viewModel.selectRoleStage('role-aoi', 'tank-top');
        viewModel.setRoleStagePart(
          sourceRoleId: 'role-aoi',
          stageId: 'tank-top',
          part: StudioScriptRolePart.upperClothing,
          value: 'manual replacement tank top',
        );

        expect(viewModel.roleMappings.single.selectedStage!.id, 'tank-top');
      },
    );

    test(
      'selected frame tags and review tokens preserve prompt weights',
      () async {
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([
            _singleFrameScript(
              baseCaption:
                  'artist:test, 1.1::city lights::, 1.5::blue eyes, long hair::, masterpiece',
            ),
          ]),
        );

        await viewModel.importScriptPath('weighted-frame-script');

        final sceneTags = viewModel.selectedFrameTagGroups
            .where((group) => group.id == 'scene')
            .single
            .tags;
        expect(sceneTags, contains('1.1:: city lights ::'));
        expect(sceneTags, contains('1.5:: blue eyes ::'));
        expect(sceneTags, contains('1.5:: long hair ::'));

        final token = viewModel.recastPlan.frameReviews.single.positiveTokens
            .where((token) => token.source == '1.1:: city lights ::')
            .single;
        final tokenSources = viewModel
            .recastPlan.frameReviews.single.positiveTokens
            .map((token) => token.source)
            .toList(growable: false);
        expect(tokenSources, contains('1.1:: city lights ::'));
        expect(tokenSources, contains('1.5:: blue eyes ::'));
        expect(tokenSources, contains('1.5:: long hair ::'));
        expect(token.translation, '鍩庡競鐏厜');
      },
    );

    test('keyframe review tokens use injected translation cache', () async {
      final cache = TranslationCache()
        ..setManual('city lights', 'cached city lights');
      final viewModel = StudioScriptViewModel(translationCache: cache);

      await viewModel.importScriptPath(_fixturePath);

      final token = viewModel.recastPlan.frameReviews.single.positiveTokens
          .where((token) => token.source == 'city lights')
          .single;
      expect(token.translation, 'cached city lights');
    });

    test(
      'review tag category precedence is manual override then AI artist evidence then heuristic',
      () async {
        final classificationCache = PromptTagClassificationCache(
          clock: () => 1710000000,
        );
        const extraction = ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.9,
          artistChains: [
            ScriptAiArtistChainEvidence(
              label: 'AI artist chain',
              terms: ['arata_asato'],
              evidenceTerms: ['arata_asato'],
              confidence: 0.9,
            ),
          ],
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([
            _singleFrameScript(baseCaption: 'arata_asato, city lights'),
          ]),
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            extraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
          classificationCache: classificationCache,
        );

        await viewModel.importScriptPath('artist-name-script');

        var token = viewModel.recastPlan.frameReviews.single.positiveTokens
            .where((token) => token.source == 'arata_asato')
            .single;
        expect(token.category, isNot(StudioScriptTokenCategory.artistChain));

        await viewModel.generateAiRoleExtraction();

        token = viewModel.recastPlan.frameReviews.single.positiveTokens
            .where((token) => token.source == 'arata_asato')
            .single;
        expect(token.category, StudioScriptTokenCategory.artistChain);

        await viewModel.setReviewTagCategory(
          'arata_asato',
          StudioScriptTokenCategory.scene,
          negative: false,
        );

        token = viewModel.recastPlan.frameReviews.single.positiveTokens
            .where((token) => token.source == 'arata_asato')
            .single;
        expect(token.category, StudioScriptTokenCategory.scene);
        expect(
          classificationCache.entryFor('arata_asato')?.category,
          PromptTagCategory.scene,
        );
        expect(classificationCache.entryFor('arata_asato')?.source, 'manual');

        await viewModel.clearReviewTagCategory('arata_asato', negative: false);

        token = viewModel.recastPlan.frameReviews.single.positiveTokens
            .where((token) => token.source == 'arata_asato')
            .single;
        expect(token.category, StudioScriptTokenCategory.artistChain);
      },
    );

    test(
      'review tag categories honor refined classification cache entries',
      () async {
        final classificationCache =
            PromptTagClassificationCache(clock: () => 1710000000)
              ..setCategory(
                'eonsang',
                PromptTagCategory.artist,
                source: 'gpt-5.4-mini-refine',
              )
              ..setCategory(
                'official style',
                PromptTagCategory.artist,
                source: 'gpt-5.4-mini-refine',
              );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([
            _singleFrameScript(
              baseCaption: 'eonsang, official style, city lights',
            ),
          ]),
          classificationCache: classificationCache,
        );

        await viewModel.importScriptPath('artist-cache-script');

        final tokens = viewModel.recastPlan.frameReviews.single.positiveTokens;
        expect(
          tokens.where((token) => token.source == 'eonsang').single.category,
          StudioScriptTokenCategory.artistChain,
        );
        expect(
          tokens
              .where((token) => token.source == 'official style')
              .single
              .category,
          StudioScriptTokenCategory.artistChain,
        );
      },
    );

    test('selected frame exposes before and after split previews', () async {
      final viewModel = StudioScriptViewModel(
        loadArtistChains: () async => const [
          ArtistChain(
            id: 'artist-chain-1',
            name: 'combined chain',
            prompt: 'artist:replacement',
          ),
        ],
      );

      await viewModel.importScriptPath(_fixturePath);

      expect(viewModel.selectedFramePreviews.map((preview) => preview.id), [
        'before',
        'after',
      ]);
      expect(
        viewModel.selectedFramePreviews.first.groups[2].tags,
        contains('artist:terasu_mc'),
      );

      viewModel.setArtistChain('artist-chain-1');

      expect(
        viewModel.selectedFramePreviews.last.groups[2].tags,
        contains('artist:replacement'),
      );
    });

    test('sendToProduction writes deterministic plan into workspace', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'studio-script-viewmodel-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final workspaceService = WorkspaceService();
      await workspaceService.createWorkspace(tempDir.path);
      final productionService = ScriptRecastProductionService(
        queueService: ProductionQueueService(
          workspaceService: workspaceService,
        ),
        now: () => DateTime.utc(2026, 5, 26, 8),
      );
      final viewModel = StudioScriptViewModel(
        productionService: productionService,
        loadCharacters: workspaceService.loadCharacters,
        loadArtistChains: workspaceService.loadArtistChains,
      );

      await viewModel.importScriptPath(_fixturePath);
      await viewModel.sendToProduction();

      expect(viewModel.sentToProduction, isTrue);
      expect(viewModel.lastProductionPlanId, 'script-recast-v4_slotted');
      expect(viewModel.lastProductionPlanName, 'v4_slotted Recast');

      final plans = await workspaceService.loadProductionPlans();
      expect(plans.single.id, viewModel.lastProductionPlanId);
      expect(plans.single.name, viewModel.lastProductionPlanName);
      expect(plans.single.tasks, hasLength(2));
      expect(
        plans.single.tasks.first.payload.toString(),
        contains('city lights'),
      );
    });

    test(
      'global prompt prefix refreshes preview and production payload',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'studio-script-global-prompt-prefix-test-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
        final workspaceService = WorkspaceService();
        await workspaceService.createWorkspace(tempDir.path);
        final productionService = ScriptRecastProductionService(
          queueService: ProductionQueueService(
            workspaceService: workspaceService,
          ),
          now: () => DateTime.utc(2026, 6, 6, 8),
        );
        final viewModel = StudioScriptViewModel(
          productionService: productionService,
        );

        await viewModel.importScriptPath(_fixturePath);
        viewModel.setGlobalPromptPrefix('best quality, detailed lighting');

        expect(viewModel.globalPromptPrefix, 'best quality, detailed lighting');
        expect(
          viewModel.diff.recast,
          startsWith('best quality, detailed lighting, '),
        );

        await viewModel.sendToProduction();

        final plans = await workspaceService.loadProductionPlans();
        expect(
          _baseCaptionFromPayload(plans.single.tasks.first.payload),
          startsWith('best quality, detailed lighting, '),
        );
        expect(
          _baseCaptionFromPayload(plans.single.tasks.last.payload),
          startsWith('best quality, detailed lighting, '),
        );
      },
    );

    test(
      'global prompt prefix persists as a workspace-wide script setting',
      () async {
        var rules = <String, dynamic>{};
        final seedViewModel = StudioScriptViewModel(
          parserService: _FakeParserService([
            _singleFrameScript(
              id: 'script-a',
              name: 'Script A',
              rootPath: r'C:\scripts\a',
              baseCaption: 'city lights',
            ),
          ]),
          loadFilterRules: () async => rules,
          saveFilterRules: (nextRules) async {
            rules = nextRules;
          },
        );

        await seedViewModel.importScriptPath(r'C:\scripts\a');
        seedViewModel.setGlobalPromptPrefix('best quality, detailed lighting');
        await Future<void>.delayed(Duration.zero);

        expect(
          rules['global_prompt_prefix'],
          'best quality, detailed lighting',
        );

        final restoredViewModel = StudioScriptViewModel(
          parserService: _FakeParserService([
            _singleFrameScript(
              id: 'script-b',
              name: 'Script B',
              rootPath: r'C:\scripts\b',
              baseCaption: 'night rain',
            ),
          ]),
          loadFilterRules: () async => rules,
          saveFilterRules: (nextRules) async {
            rules = nextRules;
          },
        );

        await restoredViewModel.importScriptPath(r'C:\scripts\b');

        expect(
          restoredViewModel.globalPromptPrefix,
          'best quality, detailed lighting',
        );
        expect(
          restoredViewModel.diff.recast,
          startsWith('best quality, detailed lighting, '),
        );
      },
    );

    test(
      'sendToProduction does not sync ready AI source parts invisibly',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'studio-script-production-ai-source-parts-test-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final workspaceService = WorkspaceService();
        await workspaceService.createWorkspace(tempDir.path);
        final productionService = ScriptRecastProductionService(
          queueService: ProductionQueueService(
            workspaceService: workspaceService,
          ),
          now: () => DateTime.utc(2026, 6, 5, 8),
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([
            _singleFrameScript(
              id: 'yoshino-recast-script',
              name: 'Yoshino Recast Script',
              rootPath: r'C:\scripts\yoshino-recast',
              baseCaption: 'classroom',
              charCaptions: const [
                'himekawa yoshino (date a live), white dress, long hair',
              ],
            ),
          ]),
          productionService: productionService,
          loadCharacters: () async => const [
            CharacterEntry(
              id: 'char-replacement',
              name: 'Replacement',
              traits: ViewVariantTexts(frontFull: 'replacement_hero, boy'),
              anchorTags: ['replacement_hero'],
              identityTags: ['boy'],
            ),
          ],
          loadArtistChains: () async => const [],
        );

        await viewModel.importScriptPath(r'C:\scripts\yoshino-recast');
        viewModel.setRoleCharacter('slot-0', 'char-replacement');
        final stageId = viewModel.roleMappings.first.stageItems.first.id;
        viewModel.aiRoleExtraction = ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.95,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'himekawa yoshino (date a live)',
              confidence: 0.95,
              stages: [
                ScriptAiExtractedStage(
                  stageId: stageId,
                  label: 'source outfit',
                  frameIndexes: const [1],
                  identity: 'himekawa yoshino (date a live)',
                  upperClothing: 'white dress',
                  upperBody: 'long hair',
                  confidence: 0.95,
                ),
              ],
            ),
          ],
        );

        await viewModel.sendToProduction();

        final plans = await workspaceService.loadProductionPlans();
        final payloadText = plans.single.tasks.single.payload.toString();
        expect(payloadText, contains('replacement_hero'));
        expect(payloadText, contains('boy'));
        expect(payloadText, contains('himekawa yoshino'));
        expect(payloadText, contains('date a live'));
      },
    );

    test(
      'sendToProduction persists ready AI role draft confirmation',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'studio-script-production-ai-draft-confirm-test-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        var caches = <RecastScriptCache>[];
        final workspaceService = WorkspaceService();
        await workspaceService.createWorkspace(tempDir.path);
        final productionService = ScriptRecastProductionService(
          queueService: ProductionQueueService(
            workspaceService: workspaceService,
          ),
          now: () => DateTime.utc(2026, 6, 26, 8),
        );
        final script = _singleFrameScript(
          id: 'ai-draft-confirm-script',
          name: 'AI Draft Confirm Script',
          rootPath: r'C:\scripts\ai-draft-confirm',
          baseCaption: 'classroom',
          charCaptions: const ['hina (blue archive), school uniform'],
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          productionService: productionService,
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
          loadCharacters: () async => const [],
          loadArtistChains: () async => const [],
        );

        await viewModel.importScriptPath(script.rootPath);
        viewModel.aiRoleExtraction = const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.95,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'hina (blue archive)',
              confidence: 0.95,
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'slot-0-default',
                  label: 'default',
                  frameIndexes: [1],
                  identity: 'hina (blue archive)',
                  upperClothing: 'school uniform',
                  confidence: 0.95,
                ),
              ],
            ),
          ],
        );

        expect(viewModel.isAiRoleExtractionDraftCollapsed, isFalse);

        await viewModel.sendToProduction();

        expect(viewModel.isAiRoleExtractionDraftCollapsed, isTrue);
        expect(caches.single.aiRoleExtractionDraftCollapsed, isTrue);
        expect(
          caches.single.aiRoleExtraction.status,
          ScriptAiRoleExtractionStatus.ready,
        );
      },
    );

    test(
      'sendToProduction strips unconfirmed automatic role assemblies',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'studio-script-production-auto-role-assemblies-test-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
        final scriptDir = Directory('${tempDir.path}\\auto-assembly-recast');
        await scriptDir.create(recursive: true);
        await File('${scriptDir.path}\\p000.png').writeAsBytes(const [0]);
        final script = _singleFrameScript(
          id: 'auto-assembly-script',
          name: 'Auto Assembly Script',
          rootPath: scriptDir.path,
          baseCaption: 'classroom',
          charCaptions: const ['alice, red jacket'],
        );
        final cache = RecastScriptCache(
          scriptId: script.id,
          scriptName: script.name,
          sourceRootPath: script.rootPath,
          sourceFingerprint: _testSourceFingerprint(script),
          updatedAt: DateTime.utc(2026, 6, 5, 10),
          mapping: RecastMapping.defaults(script.id).copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'role-alice',
                displayLabel: 'Alice',
                sourceAppearances: [
                  RoleAssemblySourceAppearance(
                    sourceId: 'slot-0',
                    sourceKind: 'slot',
                    frameIndexes: [1],
                  ),
                ],
                stages: [
                  RoleAssemblyStage(
                    id: 'alice-auto-stage',
                    label: 'Auto',
                    frameIndexes: [1],
                    sourceParts: RecastPromptParts(
                      identity: 'alice',
                      upperClothing: 'red jacket',
                    ),
                  ),
                ],
              ),
            ],
          ),
          scriptSnapshot: script.toJson(),
        );

        final workspaceService = WorkspaceService();
        await workspaceService.createWorkspace(tempDir.path);
        final productionService = ScriptRecastProductionService(
          queueService: ProductionQueueService(
            workspaceService: workspaceService,
          ),
          now: () => DateTime.utc(2026, 6, 5, 10),
        );
        final recastEngine = _CountingRecastEngine();
        final viewModel = StudioScriptViewModel(
          recastEngine: recastEngine,
          productionService: productionService,
          loadRecastCaches: () async => [cache],
        );

        await viewModel.importScriptPath(script.rootPath);
        expect(viewModel.roleMappings.first.stageItems, isNotEmpty);

        await viewModel.sendToProduction();

        expect(recastEngine.lastMapping?.roleAssemblies, isEmpty);
      },
    );

    test(
      'sendToProduction keeps candidate identity out of production until targeted',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'studio-script-production-replacement-appearances-test-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
        final scriptDir = Directory('${tempDir.path}\\wakamo-recast');
        await scriptDir.create(recursive: true);
        await File('${scriptDir.path}\\p000.png').writeAsBytes(const [0]);
        final script = _singleFrameScript(
          id: 'replacement-appearance-script',
          name: 'Replacement Appearance Script',
          rootPath: scriptDir.path,
          baseCaption: 'bedroom',
          charCaptions: const [
            'wakamo_(blue_archive), white tanktop, lying',
          ],
        );
        final cache = RecastScriptCache(
          scriptId: script.id,
          scriptName: script.name,
          sourceRootPath: script.rootPath,
          sourceFingerprint: _testSourceFingerprint(script),
          updatedAt: DateTime.utc(2026, 6, 16, 12),
          mapping: RecastMapping.defaults(script.id).copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'role-wakamo-blue-archive',
                displayLabel: 'Wakamo',
                sourceAppearances: [
                  RoleAssemblySourceAppearance(
                    sourceId: 'slot-0',
                    sourceKind: 'slot',
                    frameIndexes: [1],
                  ),
                ],
                stages: [
                  RoleAssemblyStage(
                    id: 'wakamo-stage',
                    label: 'Auto',
                    frameIndexes: [1],
                    sourceParts: RecastPromptParts(
                      identity: 'wakamo_(blue_archive)',
                      upperClothing: 'white tanktop',
                    ),
                  ),
                ],
              ),
            ],
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'role-wakamo-blue-archive',
                displayLabel: 'Wakamo',
                targetIdentityPrompt: 'pepe_(arknights)',
                rules: [
                  ScriptPromptReplacementRule(
                    id: 'rule-wakamo',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'term-wakamo',
                        text: 'wakamo_(blue_archive)',
                        category: PromptTagCategory.character,
                      ),
                    ],
                  ),
                  ScriptPromptReplacementRule(
                    id: 'rule-tanktop',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'term-tanktop',
                        text: 'white tanktop',
                        category: PromptTagCategory.clothing,
                      ),
                    ],
                    targetPrompt: 'black jacket',
                  ),
                ],
              ),
            ],
          ),
          scriptSnapshot: script.toJson(),
        );

        final workspaceService = WorkspaceService();
        await workspaceService.createWorkspace(tempDir.path);
        final productionService = ScriptRecastProductionService(
          queueService: ProductionQueueService(
            workspaceService: workspaceService,
          ),
          now: () => DateTime.utc(2026, 6, 16, 12),
        );
        final viewModel = StudioScriptViewModel(
          productionService: productionService,
          loadRecastCaches: () async => [cache],
          loadCharacters: () async => const [],
          loadArtistChains: () async => const [],
        );

        await viewModel.importScriptPath(script.rootPath);
        await viewModel.sendToProduction();

        final plans = await workspaceService.loadProductionPlans();
        final payloadText = plans.single.tasks.single.payload.toString();
        expect(payloadText, contains('wakamo_(blue_archive)'));
        expect(payloadText, contains('black jacket'));
        expect(payloadText, isNot(contains('pepe_(arknights)')));
        expect(payloadText, isNot(contains('white tanktop')));
      },
    );

    test(
      'sendToProduction respects manually cleared AI source identity',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'studio-script-manual-source-keep-test-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final workspaceService = WorkspaceService();
        await workspaceService.createWorkspace(tempDir.path);
        final productionService = ScriptRecastProductionService(
          queueService: ProductionQueueService(
            workspaceService: workspaceService,
          ),
          now: () => DateTime.utc(2026, 6, 5, 9),
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([
            _singleFrameScript(
              id: 'keep-source-role-script',
              name: 'Keep Source Role Script',
              rootPath: r'C:\scripts\keep-source-role',
              baseCaption: 'classroom',
              charCaptions: const [
                'himekawa yoshino (date a live), white dress, long hair',
              ],
            ),
          ]),
          productionService: productionService,
          loadCharacters: () async => const [
            CharacterEntry(
              id: 'char-replacement',
              name: 'Replacement',
              traits: ViewVariantTexts(frontFull: 'replacement_hero, boy'),
              anchorTags: ['replacement_hero'],
              identityTags: ['boy'],
            ),
          ],
          loadArtistChains: () async => const [],
        );

        await viewModel.importScriptPath(r'C:\scripts\keep-source-role');
        viewModel.setRoleCharacter('slot-0', 'char-replacement');
        final stageId = viewModel.roleMappings.first.stageItems.first.id;
        viewModel.setRoleStageSourcePart(
          sourceRoleId: 'slot-0',
          stageId: stageId,
          part: StudioScriptRolePart.identity,
          value: 'himekawa yoshino (date a live)',
        );
        viewModel.setRoleStageSourcePart(
          sourceRoleId: 'slot-0',
          stageId: stageId,
          part: StudioScriptRolePart.identity,
          value: '',
        );
        viewModel.aiRoleExtraction = ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.95,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'himekawa yoshino (date a live)',
              confidence: 0.95,
              stages: [
                ScriptAiExtractedStage(
                  stageId: stageId,
                  label: 'source outfit',
                  frameIndexes: const [1],
                  identity: 'himekawa yoshino (date a live)',
                  upperClothing: 'white dress',
                  upperBody: 'long hair',
                  confidence: 0.95,
                ),
              ],
            ),
          ],
        );

        await viewModel.sendToProduction();

        final plans = await workspaceService.loadProductionPlans();
        final payloadText = plans.single.tasks.single.payload.toString();
        expect(payloadText, contains('replacement_hero'));
        expect(payloadText, contains('himekawa yoshino'));
        expect(payloadText, contains('date a live'));
      },
    );

    test(
      'sendToProduction gives non-ASCII script names distinct plan ids',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'studio-script-non-ascii-plan-id-test-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final workspaceService = WorkspaceService();
        await workspaceService.createWorkspace(tempDir.path);
        final productionService = ScriptRecastProductionService(
          queueService: ProductionQueueService(
            workspaceService: workspaceService,
          ),
          now: () => DateTime.utc(2026, 5, 26, 8),
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([
            _singleFrameScript(
              id: 'script-wakamo',
              name: '鐙愬潅銉偒銉?瀵濆彇銈夈倢',
              rootPath: r'C:\stories\wakamo',
              baseCaption: 'wakamo beach',
            ),
            _singleFrameScript(
              id: 'script-ayaka',
              name: '绁為噷缍捐彲 鎮爼銇¤鏁?',
              rootPath: r'C:\stories\ayaka',
              baseCaption: 'ayaka shrine',
            ),
          ]),
          productionService: productionService,
          loadCharacters: workspaceService.loadCharacters,
          loadArtistChains: workspaceService.loadArtistChains,
        );

        await viewModel.importScriptPath(r'C:\stories\wakamo');
        await viewModel.sendToProduction();
        final firstPlanId = viewModel.lastProductionPlanId;

        await viewModel.importScriptPath(r'C:\stories\ayaka');
        await viewModel.sendToProduction();
        final secondPlanId = viewModel.lastProductionPlanId;

        expect(firstPlanId, isNot(secondPlanId));
        final plans = await workspaceService.loadProductionPlans();
        expect(plans.map((plan) => plan.id).toSet(), {
          firstPlanId,
          secondPlanId,
        });
      },
    );

    test(
      'global block words affect production payloads and can be saved',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'studio-script-global-block-words-test-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final workspaceService = WorkspaceService();
        await workspaceService.createWorkspace(tempDir.path);
        final productionService = ScriptRecastProductionService(
          queueService: ProductionQueueService(
            workspaceService: workspaceService,
          ),
          now: () => DateTime.utc(2026, 5, 26, 9),
        );
        final viewModel = StudioScriptViewModel(
          productionService: productionService,
          loadCharacters: workspaceService.loadCharacters,
          loadArtistChains: workspaceService.loadArtistChains,
          loadFilterRules: workspaceService.loadFilterRules,
          saveFilterRules: workspaceService.saveFilterRules,
        );

        await viewModel.importScriptPath(_fixturePath);
        await viewModel.saveGlobalBlockWords('city lights, lowres');

        await viewModel.sendToProduction();

        final plans = await workspaceService.loadProductionPlans();
        expect(plans.single.tasks, hasLength(2));
        expect(
          plans.single.tasks.first.payload.toString(),
          isNot(contains('city lights')),
        );
        expect(
          plans.single.tasks.first.payload.toString(),
          isNot(contains('lowres')),
        );
        expect(viewModel.timeline.map((item) => item.statuses), [
          contains(StudioScriptTimelineStatus.sent),
          contains(StudioScriptTimelineStatus.sent),
        ]);

        final rules = await workspaceService.loadFilterRules();
        expect(rules['delete_keywords'], 'city lights, lowres');
      },
    );

    test(
      'sendToProduction exposes busy state and blocks duplicate sends',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'studio-script-send-busy-test-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final workspaceService = WorkspaceService();
        await workspaceService.createWorkspace(tempDir.path);
        final productionService = _PendingProductionService(
          queueService: ProductionQueueService(
            workspaceService: workspaceService,
          ),
        );
        final viewModel = StudioScriptViewModel(
          productionService: productionService,
          loadCharacters: workspaceService.loadCharacters,
          loadArtistChains: workspaceService.loadArtistChains,
        );

        await viewModel.importScriptPath(_fixturePath);

        final firstSend = viewModel.sendToProduction();
        expect(viewModel.isSendingToProduction, isTrue);
        expect(await viewModel.sendToProduction(), isFalse);

        productionService.complete();
        expect(await firstSend, isTrue);
        expect(viewModel.isSendingToProduction, isFalse);
        expect(productionService.enqueueCount, 1);
      },
    );

    test('selected tags can be appended to the shared filter rules', () async {
      var rules = <String, dynamic>{
        'delete_keywords': 'lowres',
        'strong_filter_keywords': 'mosaic',
        'replace_rules': 'old -> new',
      };
      final viewModel = StudioScriptViewModel(
        loadFilterRules: () async => rules,
        saveFilterRules: (nextRules) async {
          rules = nextRules;
        },
      );

      await viewModel.addTagsToFilterRulesLibrary([
        'lowres',
        'city lights',
        'night rain',
      ]);

      expect(rules['delete_keywords'], 'lowres, city lights, night rain');
      expect(rules['strong_filter_keywords'], 'mosaic');
      expect(rules['replace_rules'], 'old -> new');
      expect(viewModel.globalBlockWords, 'lowres, city lights, night rain');
    });

    test(
      'timeline can express warning, error, sent and failed states',
      () async {
        final viewModel = StudioScriptViewModel();

        await viewModel.importScriptPath('test/fixtures/script_recast/broken');
        viewModel.applyFrameResults(const [
          FrameResult(
            frameIndex: 1,
            sourceFileName: 'nai_1.json',
            taskId: 'task-1',
            status: FrameResultStatus.failed,
            payloadFingerprint: 'payload-1',
            error: 'boom',
          ),
          FrameResult(
            frameIndex: 2,
            sourceFileName: 'nai_2.json',
            taskId: 'task-2',
            status: FrameResultStatus.completed,
            payloadFingerprint: 'payload-2',
          ),
        ]);

        final byFrame = {
          for (final item in viewModel.timeline) item.frameIndex: item,
        };

        expect(byFrame[2]!.statuses, contains(StudioScriptTimelineStatus.sent));
        expect(
          byFrame[1]!.statuses,
          containsAll([
            StudioScriptTimelineStatus.error,
            StudioScriptTimelineStatus.failed,
          ]),
        );
      },
    );

    testWidgets(
      'selected frame split cards render translated interactive tags',
      (tester) async {
        final viewModel = StudioScriptViewModel();

        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });
        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pump();

        expect(find.text('city lights'), findsWidgets);
        expect(find.text('鍩庡競鐏厜'), findsWidgets);
      },
    );

    testWidgets('global prompt prefix is its own panel before AI draft panel', (
      tester,
    ) async {
      final viewModel = StudioScriptViewModel()
        ..aiRoleExtraction = const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
        );

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();

      final header = find.byKey(const ValueKey('script-header-panel'));
      final globalPanel = find.byKey(
        const ValueKey('script-global-prompt-prefix-panel'),
      );
      final aiPanel = find.byKey(
        const ValueKey('script-ai-role-extraction-draft-panel'),
      );
      final row = find.byKey(const ValueKey('script-global-prompt-prefix-row'));
      final editor = find.descendant(
        of: row,
        matching: find.byType(PromptTagEditor),
      );

      expect(globalPanel, findsOneWidget);
      expect(aiPanel, findsOneWidget);
      expect(row, findsOneWidget);
      expect(find.descendant(of: header, matching: row), findsNothing);
      expect(find.descendant(of: globalPanel, matching: row), findsOneWidget);
      expect(find.descendant(of: aiPanel, matching: row), findsNothing);
      expect(
        find.descendant(of: globalPanel, matching: find.byType(StudioPanel)),
        findsOneWidget,
      );
      expect(editor, findsOneWidget);
      expect(tester.widget<PromptTagEditor>(editor).inlineLabel, isFalse);
      expect(
        tester.getTopLeft(globalPanel).dy,
        lessThan(tester.getTopLeft(aiPanel).dy),
      );

      tester
          .widget<PromptTagEditor>(editor)
          .onChanged('best quality, detailed lighting');
      await tester.pump();

      expect(viewModel.globalPromptPrefix, 'best quality, detailed lighting');
    });

    testWidgets('timeline shows replaced prompt tags below the frame strip', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1900, 1050);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel(
        loadArtistChains: () async => const [
          ArtistChain(
            id: 'artist-chain-1',
            name: 'combined chain',
            prompt: 'artist:replacement',
          ),
        ],
      );

      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });
      viewModel.setArtistChain('artist-chain-1');

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();

      final panel = find.byKey(
        const ValueKey('script-layout-bottom-replaced-prompt'),
      );
      expect(panel, findsOneWidget);
      expect(
        find.descendant(
          of: panel,
          matching: find.text('\u66ff\u6362\u540e\u7684\u63d0\u793a\u8bcd'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('artist:replacement')),
        findsWidgets,
      );
      expect(
        tester.getTopLeft(panel).dy,
        greaterThan(
          tester
              .getBottomLeft(
                find.byKey(const ValueKey('script-layout-bottom-timeline')),
              )
              .dy,
        ),
      );
    });

    testWidgets('replaced prompt preview hides tag warning chrome', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1900, 1050);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel();

      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });
      viewModel.setGlobalPromptPrefix('male smile');

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();

      final panel = find.byKey(
        const ValueKey('script-layout-bottom-replaced-prompt'),
      );
      final chipFinder = find.descendant(
        of: panel,
        matching: find.byWidgetPredicate(
          (widget) => widget is PromptTagChip && widget.label == 'male smile',
        ),
      );

      expect(chipFinder, findsOneWidget);
      expect(tester.widget<PromptTagChip>(chipFinder).warning, isFalse);
    });

    testWidgets('replaced prompt diff highlights added and removed tags', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1900, 1050);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel(
        loadArtistChains: () async => const [
          ArtistChain(
            id: 'artist-chain-1',
            name: 'combined chain',
            prompt: 'artist:replacement',
          ),
        ],
      );

      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });
      viewModel.setArtistChain('artist-chain-1');

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();

      final panel = find.byKey(
        const ValueKey('script-layout-bottom-replaced-prompt'),
      );
      final diffToggle = find.descendant(
        of: panel,
        matching: find.byKey(
          const ValueKey('script-replaced-prompt-diff-toggle'),
        ),
      );
      final removedArtistChip = find.descendant(
        of: panel,
        matching: find.byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> &&
              key.value.startsWith('prompt-tag-chip-diff-removed-') &&
              key.value.contains('terasu_mc');
        }),
      );
      final addedArtistSystemMarker = find.descendant(
        of: panel,
        matching: find.byKey(
          const ValueKey('prompt-tag-chip-marker-artist:replacement-0'),
        ),
      );
      final addedArtistDiffPrefix = find.descendant(
        of: panel,
        matching: find.byKey(
          const ValueKey('prompt-tag-chip-diff-added-artist:replacement-0'),
        ),
      );
      final unchangedCitySystemMarker = find.descendant(
        of: panel,
        matching: find.byKey(
          const ValueKey('prompt-tag-chip-marker-city lights-1'),
        ),
      );

      expect(diffToggle, findsOneWidget);
      expect(addedArtistDiffPrefix, findsNothing);
      expect(
        removedArtistChip,
        findsNothing,
      );

      await tester.ensureVisible(diffToggle);
      await tester.pumpAndSettle();
      await tester.tap(diffToggle);
      await tester.pumpAndSettle();

      expect(addedArtistSystemMarker, findsOneWidget);
      expect(addedArtistDiffPrefix, findsOneWidget);
      expect(
        removedArtistChip,
        findsOneWidget,
      );
      expect(unchangedCitySystemMarker, findsOneWidget);
    });

    testWidgets('replaced prompt keeps role groups before grouping tags', (
      tester,
    ) async {
      final viewModel = StudioScriptViewModel(
        scriptAiRoleExtractionService: const _FakeRoleExtractionService(
          _highConfidenceSlotExtraction,
        ),
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();
        await viewModel.applyHighConfidenceAiRoleExtraction();
      });

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();

      final panel = find.byKey(
        const ValueKey('script-layout-bottom-replaced-prompt'),
      );
      final roleOneGroup = find.descendant(
        of: panel,
        matching: find.byKey(
          const ValueKey('script-replaced-prompt-group-role-1'),
          skipOffstage: false,
        ),
      );
      final roleTwoGroup = find.descendant(
        of: panel,
        matching: find.byKey(
          const ValueKey('script-replaced-prompt-group-role-2'),
          skipOffstage: false,
        ),
      );

      expect(roleOneGroup, findsOneWidget);
      expect(roleTwoGroup, findsOneWidget);
      expect(
        find.descendant(of: roleOneGroup, matching: find.text('瑙掕壊 1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: roleTwoGroup, matching: find.text('瑙掕壊 2')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: roleOneGroup,
          matching: find.text('vulpisfoglia_(arknights)'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: roleOneGroup,
          matching: find.text('suzuran_(arknights)'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: roleTwoGroup,
          matching: find.text('suzuran_(arknights)'),
        ),
        findsWidgets,
      );

      final toggle = find.byKey(
        const ValueKey('script-replaced-prompt-layout-toggle'),
      );
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: roleOneGroup,
          matching: find.byKey(
            const ValueKey('prompt-tag-group-character'),
            skipOffstage: false,
          ),
        ),
        findsWidgets,
      );
    });

    testWidgets('large script timeline uses compact frame labels and scrolls', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel()
        ..timeline = [
          for (var index = 1; index <= 240; index++)
            StudioScriptTimelineItem(
              frameIndex: index,
              label: '$index帧',
              selected: index == 1,
            ),
        ];

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();

      final timelinePanel = find.byKey(
        const ValueKey('script-layout-bottom-timeline'),
      );
      expect(timelinePanel, findsOneWidget);
      expect(
        find.descendant(of: timelinePanel, matching: find.text('1帧')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: timelinePanel, matching: find.text('240帧')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: timelinePanel, matching: find.byType(Scrollbar)),
        findsOneWidget,
      );
      final renderedChipCount = find
          .descendant(of: timelinePanel, matching: find.byType(ActionChip))
          .evaluate()
          .length;
      expect(renderedChipCount, 240);
    });

    testWidgets('large script timeline keeps frame chips inside a scroller', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel()
        ..timeline = [
          for (var index = 1; index <= 48; index++)
            StudioScriptTimelineItem(
              frameIndex: index,
              label: '$index帧',
              selected: index == 1,
            ),
        ];

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();

      final timelinePanel = find.byKey(
        const ValueKey('script-layout-bottom-timeline'),
      );
      await tester.ensureVisible(timelinePanel);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: timelinePanel, matching: find.byType(Scrollbar)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: timelinePanel, matching: find.text('48帧')),
        findsOneWidget,
      );
    });

    testWidgets('large role mapping list only builds visible role cards', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final script = _largeScript(frameCount: 4, roleSlots: 80);
      final viewModel = StudioScriptViewModel(
        parserService: _FakeParserService([script]),
      );

      await tester.runAsync(() async {
        await viewModel.importScriptPath('large-role-script');
      });
      expect(viewModel.roleMappings, hasLength(80));

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();

      final mainWorkspace = find.byKey(
        const ValueKey('script-layout-main-workspace'),
      );
      expect(mainWorkspace, findsOneWidget);
      final renderedRoleCards = find
          .byWidgetPredicate((widget) {
            final key = widget.key;
            return key is ValueKey<String> &&
                key.value.startsWith('role-card-');
          })
          .evaluate()
          .length;
      expect(renderedRoleCards, lessThan(30));
      expect(find.byKey(const ValueKey('role-card-slot-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('role-card-slot-79')), findsNothing);
    });

    testWidgets('ten role mapping cards stay directly laid out', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final script = _largeScript(frameCount: 4, roleSlots: 10);
      final viewModel = StudioScriptViewModel(
        parserService: _FakeParserService([script]),
      );

      await tester.runAsync(() async {
        await viewModel.importScriptPath('ten-role-script');
      });
      expect(viewModel.roleMappings, hasLength(10));

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('script-role-mapping-virtual-list')),
        findsNothing,
      );
      final renderedRoleCards = find
          .byWidgetPredicate((widget) {
            final key = widget.key;
            return key is ValueKey<String> &&
                key.value.startsWith('role-card-');
          })
          .evaluate()
          .length;
      expect(renderedRoleCards, 10);
    });

    testWidgets(
      'virtualized role mapping viewport reserves a full-role viewing height',
      (tester) async {
        tester.view.physicalSize = const Size(1300, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final script = _largeScript(frameCount: 4, roleSlots: 11);
        const longSource = 'tag01, tag02, tag03, tag04, tag05, tag06, tag07';
        const longTarget =
            'swap01, swap02, swap03, swap04, swap05, swap06, swap07, swap08, swap09';
        final cache = RecastScriptCache(
          scriptId: script.id,
          scriptName: script.name,
          sourceRootPath: script.rootPath,
          sourceFingerprint: _normalizedSourceFingerprintForTest(script),
          updatedAt: DateTime.utc(2026, 6, 12),
          mapping: RecastMapping.defaults(script.id).copyWith(
            roleAssemblies: [
              for (var slot = 0; slot < 11; slot += 1)
                RoleAssembly(
                  sourceRoleId: 'slot-$slot',
                  displayLabel: 'source_role_$slot',
                  sourceName: 'source_role_$slot',
                  stages: const [
                    RoleAssemblyStage(
                      id: 'main-outfit',
                      label: 'Main outfit',
                      frameIndexes: [1, 2, 3, 4],
                      sourceSummary: longSource,
                      sourceParts: RecastPromptParts(
                        identity: longSource,
                        upperBody: longSource,
                        lowerBody: longSource,
                        upperClothing: longSource,
                        lowerClothing: longSource,
                      ),
                      manualParts: RecastPromptParts(
                        identity: longTarget,
                        upperBody: longTarget,
                        lowerBody: longTarget,
                        upperClothing: longTarget,
                        lowerClothing: longTarget,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          scriptSnapshot: script.toJson(),
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadRecastCaches: () async => [cache],
        );

        await tester.runAsync(() async {
          await viewModel.importScriptPath('virtualized-role-height-script');
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final virtualList = find.byKey(
          const ValueKey('script-role-mapping-virtual-list'),
        );
        final firstRoleCard = find.byKey(const ValueKey('role-card-slot-0'));
        expect(virtualList, findsOneWidget);
        expect(firstRoleCard, findsOneWidget);
        expect(tester.getSize(firstRoleCard).height, greaterThan(880));
        expect(
          tester.getSize(virtualList).height,
          greaterThanOrEqualTo(880),
        );
      },
    );

    testWidgets('large role stage list renders every chip in wrapping rows', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel()
        ..recastPlan = const StudioScriptRecastPlan(
          roles: [
            StudioScriptPlanRole(
              sourceRoleId: 'role-heavy',
              label: 'Heavy role',
              sourceName: 'source role',
            ),
          ],
          hasAiBackedPlan: true,
        )
        ..roleMappings = [
          StudioScriptRoleMappingItem(
            sourceRoleId: 'role-heavy',
            sourceLabel: 'Heavy role',
            sourcePreview: 'source role',
            selectedStageId: 'stage-0',
            stageItems: [
              for (var index = 0; index < 80; index += 1)
                StudioScriptRoleStageItem(
                  id: 'stage-$index',
                  label: 'Stage $index',
                  frameIndexes: [index + 1],
                ),
            ],
          ),
        ];

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('role-stage-virtual-list-role-heavy')),
        findsNothing,
      );
      final renderedStageChips = find
          .byWidgetPredicate((widget) {
            final key = widget.key;
            return key is ValueKey<String> &&
                key.value.startsWith('role-stage-role-heavy-');
          })
          .evaluate()
          .length;
      expect(renderedStageChips, 80);
      expect(
        find.byKey(const ValueKey('role-stage-role-heavy-stage-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('role-stage-role-heavy-stage-79')),
        findsOneWidget,
      );
    });

    testWidgets(
      'role outfit stage chips stay inside the role card when labels overflow',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final viewModel = StudioScriptViewModel()
          ..recastPlan = const StudioScriptRecastPlan(
            roles: [
              StudioScriptPlanRole(
                sourceRoleId: 'slot-0',
                label: 'Bremerton',
                sourceName: 'source role',
              ),
            ],
            hasAiBackedPlan: true,
          )
          ..roleMappings = [
            StudioScriptRoleMappingItem(
              sourceRoleId: 'slot-0',
              sourceLabel: 'Bremerton',
              sourcePreview: 'source role',
              selectedStageId: 'stage-0',
              stageItems: [
                for (var index = 0; index < 12; index += 1)
                  StudioScriptRoleStageItem(
                    id: 'stage-$index',
                    label: index == 11
                        ? 'short top / tennis uniform / black panties / blue jacket / long alternate outfit'
                        : 'outfit $index / source clothing',
                    frameIndexes: [index + 1],
                  ),
              ],
            ),
          ];

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('role-stage-virtual-list-slot-0')),
          findsNothing,
        );
        final card = find.byKey(const ValueKey('role-card-slot-0'));
        final overflowingChip = find.byKey(
          const ValueKey('role-stage-slot-0-stage-11'),
        );
        expect(card, findsOneWidget);
        expect(overflowingChip, findsOneWidget);

        final cardRect = tester.getRect(card);
        final chipRect = tester.getRect(overflowingChip);
        expect(chipRect.left, greaterThanOrEqualTo(cardRect.left - 0.1));
        expect(chipRect.right, lessThanOrEqualTo(cardRect.right + 0.1));
        expect(chipRect.top, greaterThanOrEqualTo(cardRect.top - 0.1));
        expect(chipRect.bottom, lessThanOrEqualTo(cardRect.bottom + 0.1));
      },
    );

    testWidgets('large script timeline uses vertical scrolling only', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel()
        ..timeline = [
          for (var index = 1; index <= 240; index++)
            StudioScriptTimelineItem(
              frameIndex: index,
              label: '$index帧',
              selected: index == 1,
            ),
        ];

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();

      final timelinePanel = find.byKey(
        const ValueKey('script-layout-bottom-timeline'),
      );
      expect(timelinePanel, findsOneWidget);
      await tester.ensureVisible(timelinePanel);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: timelinePanel, matching: find.byType(Scrollbar)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: timelinePanel, matching: find.text('240帧')),
        findsOneWidget,
      );
    });

    testWidgets('keyframe review separates positive and negative tokens', (
      tester,
    ) async {
      final viewModel = StudioScriptViewModel(
        scriptAiRoleExtractionService: const _FakeRoleExtractionService(
          _highConfidenceSlotExtraction,
        ),
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();
        await viewModel.applyHighConfidenceAiRoleExtraction();
      });

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('script-keyframe-positive-column')),
        findsWidgets,
      );
      expect(
        find.byKey(const ValueKey('script-keyframe-negative-column')),
        findsWidgets,
      );
      expect(find.text('姝ｅ悜婧愯瘝'), findsWidgets);
      expect(find.text('璐熼潰婧愯瘝'), findsWidgets);
      expect(
        find.byKey(const ValueKey('script-keyframe-negative-strategy')),
        findsWidgets,
      );
      expect(find.text('lowres'), findsWidgets);
      expect(find.text('bad hands'), findsWidgets);
    });

    testWidgets('keyframe review keeps role groups before grouping tags', (
      tester,
    ) async {
      final viewModel = StudioScriptViewModel();
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();

      final positiveColumn =
          find.byKey(const ValueKey('script-keyframe-positive-column')).first;
      final roleOneGroup = find.descendant(
        of: positiveColumn,
        matching: find.byKey(
          const ValueKey('script-keyframe-positive-group-role-1'),
          skipOffstage: false,
        ),
      );
      final roleTwoGroup = find.descendant(
        of: positiveColumn,
        matching: find.byKey(
          const ValueKey('script-keyframe-positive-group-role-2'),
          skipOffstage: false,
        ),
      );

      expect(roleOneGroup, findsOneWidget);
      expect(roleTwoGroup, findsOneWidget);
      expect(
        find.descendant(
          of: roleOneGroup,
          matching: find.text('vulpisfoglia_(arknights)'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: roleOneGroup,
          matching: find.text('suzuran_(arknights)'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: roleTwoGroup,
          matching: find.text('suzuran_(arknights)'),
        ),
        findsWidgets,
      );
    });

    testWidgets('selected frame prompt chips match the preview shell style', (
      tester,
    ) async {
      final viewModel = StudioScriptViewModel();
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();

      final tokenChips = find.byWidgetPredicate((widget) {
        final key = widget.key;
        if (widget is! AnimatedContainer || key is! ValueKey) {
          return false;
        }
        final value = key.value.toString();
        return value.startsWith('prompt-tag-chip-');
      }, skipOffstage: false);

      expect(tokenChips, findsWidgets);

      final chip = tester.widget<AnimatedContainer>(tokenChips.first);
      final decoration = chip.decoration! as BoxDecoration;
      final border = decoration.border! as Border;

      expect(decoration.color, const Color(0xFF181818));
      expect(decoration.borderRadius, StudioTokens.radiusTag);
      expect(border.top.color, StudioTokens.border);
      expect(
        find.byWidgetPredicate((widget) {
          final key = widget.key;
          return widget is DecoratedBox &&
              key is ValueKey &&
              key.value.toString().startsWith('prompt-tag-chip-marker-');
        }, skipOffstage: false),
        findsWidgets,
      );
    });

    testWidgets(
      'keyframe positive tokens can switch to grouped package layout',
      (tester) async {
        final viewModel = StudioScriptViewModel();
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pump();

        expect(
          find.byKey(const ValueKey('script-keyframe-positive-layout-toggle')),
          findsWidgets,
        );
        final positiveColumn =
            find.byKey(const ValueKey('script-keyframe-positive-column')).first;
        final roleOneGroup = find.descendant(
          of: positiveColumn,
          matching: find.byKey(
            const ValueKey('script-keyframe-positive-group-role-1'),
            skipOffstage: false,
          ),
        );
        expect(roleOneGroup, findsOneWidget);
        expect(
          find.descendant(
            of: roleOneGroup,
            matching: find.byKey(
              const ValueKey('prompt-tag-group-character'),
              skipOffstage: false,
            ),
          ),
          findsNothing,
        );

        await tester.ensureVisible(
          find
              .byKey(const ValueKey('script-keyframe-positive-layout-toggle'))
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .byKey(const ValueKey('script-keyframe-positive-layout-toggle'))
              .first,
        );
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: roleOneGroup,
            matching: find.byKey(
              const ValueKey('prompt-tag-group-character'),
              skipOffstage: false,
            ),
          ),
          findsWidgets,
        );
        expect(
          find.descendant(
            of: roleOneGroup,
            matching: find.byKey(
              const ValueKey('prompt-tag-group-clothing'),
              skipOffstage: false,
            ),
          ),
          findsWidgets,
        );

        await tester.ensureVisible(
          find
              .byKey(const ValueKey('script-keyframe-positive-layout-toggle'))
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .byKey(const ValueKey('script-keyframe-positive-layout-toggle'))
              .first,
        );
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: roleOneGroup,
            matching: find.byKey(
              const ValueKey('prompt-tag-group-character'),
              skipOffstage: false,
            ),
          ),
          findsNothing,
        );
      },
    );

    testWidgets('replaced prompt tokens can switch to grouped package layout', (
      tester,
    ) async {
      final viewModel = StudioScriptViewModel();
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();

      final toggle = find.byKey(
        const ValueKey('script-replaced-prompt-layout-toggle'),
      );
      final panel = find.byKey(
        const ValueKey('script-layout-bottom-replaced-prompt'),
      );
      final roleOneGroup = find.descendant(
        of: panel,
        matching: find.byKey(
          const ValueKey('script-replaced-prompt-group-role-1'),
          skipOffstage: false,
        ),
      );
      expect(toggle, findsOneWidget);
      expect(roleOneGroup, findsOneWidget);

      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: roleOneGroup,
          matching: find.byKey(
            const ValueKey('prompt-tag-group-character'),
            skipOffstage: false,
          ),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: roleOneGroup,
          matching: find.byKey(
            const ValueKey('prompt-tag-group-clothing'),
            skipOffstage: false,
          ),
        ),
        findsWidgets,
      );

      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: roleOneGroup,
          matching: find.byKey(
            const ValueKey('prompt-tag-group-character'),
            skipOffstage: false,
          ),
        ),
        findsNothing,
      );
    });

    testWidgets(
      'script page shows primary actions and filter rules library entry',
      (tester) async {
        await tester.pumpWidget(buildScriptPage());

        expect(find.byIcon(Icons.folder_open_outlined), findsOneWidget);
        expect(
          find.widgetWithIcon(StudioButton, Icons.auto_awesome_outlined),
          findsOneWidget,
        );
        expect(find.text('AI 鏁寸悊瑙掕壊瀛楁'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('script-filter-rules-library-button')),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.outbox_outlined), findsOneWidget);
        expect(
          find.byKey(const ValueKey('script-advanced-tools-panel')),
          findsNothing,
        );
        expect(find.text('妤傛楠囩拫鍐╂殻'), findsNothing);
        expect(find.text('涓夋€佹帶鍒?'), findsNothing);
        expect(find.text('鏉╁洦鎶ら崨鎴掕厬閺勫海绮?'), findsNothing);
        expect(find.text('甯ц寖鍥磋鐩?'), findsNothing);
        expect(find.text('鍙戦€佸墠鍙樻洿姹囨€?'), findsNothing);
        expect(find.byKey(const ValueKey('frame-range-start')), findsNothing);
        expect(
          find.byKey(const ValueKey('filter-hit-range-start-lowres')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('frame-range-apply-param')),
          findsNothing,
        );
        expect(find.textContaining('cfg_rescale'), findsNothing);
        expect(find.textContaining('noise_schedule'), findsNothing);
      },
    );

    testWidgets(
      'import button uses injected picker and shows real fixture state',
      (tester) async {
        final viewModel = StudioScriptViewModel(
          pickScriptDirectory: () async => _fixturePath,
        );

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));

        await tester.runAsync(() async {
          tester.widget<FilledButton>(_importButton()).onPressed!();
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
        expect(viewModel.frameCount, 2);

        expect(find.textContaining('v4_slotted'), findsOneWidget);
        expect(find.text('2'), findsAtLeastNWidgets(3));
        expect(find.text('0'), findsOneWidget);
        expect(
          find.textContaining('vulpisfoglia_(arknights)'),
          findsAtLeastNWidgets(1),
        );
        expect(find.textContaining('artist:terasu_mc'), findsWidgets);
        expect(find.text('nai_1.json'), findsOneWidget);
        expect(find.text('nai_2.json'), findsOneWidget);
      },
    );

    testWidgets('filter rules library dialog updates the view model', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var savedRules = <String, dynamic>{};
      final viewModel = StudioScriptViewModel(
        pickScriptDirectory: () async => _fixturePath,
        loadFilterRules: () async => const {
          'delete_keywords': 'lowres',
          'strong_filter_keywords': 'mosaic',
          'replace_rules': 'old -> new',
          'remove_weights': true,
          'exact_match': true,
          'delete_artist_tags': false,
        },
        saveFilterRules: (rules) async {
          savedRules = rules;
        },
      );

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));

      await tester.tap(
        find.byKey(const ValueKey('script-filter-rules-library-button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('filter-rule-section-delete')),
        findsOneWidget,
      );

      final addSceneDelete = find.byKey(
        const ValueKey('filter-rule-section-add-delete'),
      );
      await tester.ensureVisible(addSceneDelete);
      await tester.pumpAndSettle();
      await tester.tap(addSceneDelete);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('filter-rule-tag-edit-field')),
        'city lights',
      );
      await tester.tap(find.byKey(const ValueKey('filter-rule-tag-edit-save')));
      await tester.pumpAndSettle();

      final addCharacterStrong = find.byKey(
        const ValueKey('filter-rule-section-add-strong'),
      );
      await tester.ensureVisible(addCharacterStrong);
      await tester.pumpAndSettle();
      await tester.tap(addCharacterStrong);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('filter-rule-tag-edit-field')),
        'bad anatomy',
      );
      await tester.tap(find.byKey(const ValueKey('filter-rule-tag-edit-save')));
      await tester.pumpAndSettle();

      tester
          .widget<FilledButton>(find.byKey(const ValueKey('filter-rules-save')))
          .onPressed!();
      await tester.pumpAndSettle();

      expect(viewModel.globalBlockWords, 'lowres, city lights');
      expect(savedRules['delete_keywords'], 'lowres, city lights');
      expect(savedRules['strong_filter_keywords'], 'mosaic, bad anatomy');
      expect(savedRules['replace_rules'], 'old -> new');
      expect(savedRules['remove_weights'], isTrue);
      expect(savedRules['exact_match'], isTrue);
      expect(savedRules['delete_artist_tags'], isFalse);
    });

    testWidgets('keyframe source tags can be right clicked into filter rules', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var savedRules = <String, dynamic>{
        'delete_keywords': 'lowres',
        'strong_filter_keywords': '',
        'replace_rules': '',
      };
      final viewModel = StudioScriptViewModel(
        loadFilterRules: () async => savedRules,
        saveFilterRules: (rules) async {
          savedRules = rules;
        },
      );
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final positiveColumn =
          find.byKey(const ValueKey('script-keyframe-positive-column')).first;
      final cityLights = find
          .descendant(of: positiveColumn, matching: find.text('city lights'))
          .first;
      await tester.ensureVisible(cityLights);
      await tester.pumpAndSettle();
      await tester.tap(cityLights);
      await tester.pump();
      await tester.tap(cityLights, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('prompt-tag-add-to-filter-rules')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('prompt-tag-filter-target-delete')),
      );
      await tester.pumpAndSettle();

      expect(savedRules['delete_keywords'], contains('lowres'));
      expect(savedRules['delete_keywords'], contains('city lights'));
    });

    testWidgets(
      'keyframe source tag menu can add tokens to selected replacement rule',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final script = _singleFrameScript(
          id: 'frame-source-menu-script',
          name: 'Frame Source Menu Script',
          rootPath: 'frame-source-menu-script',
          baseCaption: 'city lights, rain',
          charCaptions: const ['source hero, fox ears, blue jacket'],
        );
        final cache = RecastScriptCache(
          scriptId: script.id,
          scriptName: script.name,
          sourceRootPath: script.rootPath,
          sourceFingerprint: _normalizedSourceFingerprintForTest(script),
          updatedAt: DateTime.utc(2026, 6, 17),
          mapping: RecastMapping.defaults(script.id).copyWith(
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourcePreview: 'source hero',
                rules: [
                  ScriptPromptReplacementRule(
                    id: 'rule-hero',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'term-source-hero',
                        text: 'source hero',
                        category: PromptTagCategory.character,
                        frameIndexes: [1],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          scriptSnapshot: script.toJson(),
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadRecastCacheByScriptId: (_) async => cache,
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(script.rootPath);
        });
        viewModel.setRoleReplacementRuleSelected('slot-0', 'rule-hero', true);

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final positiveColumn =
            find.byKey(const ValueKey('script-keyframe-positive-column')).first;
        final foxEars = find
            .descendant(of: positiveColumn, matching: find.text('fox ears'))
            .first;
        await tester.ensureVisible(foxEars);
        await tester.pumpAndSettle();
        await tester.tap(foxEars, buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(
            const ValueKey('script-frame-add-to-current-replacement-rule'),
          ),
        );
        await tester.pumpAndSettle();

        final rule = viewModel.roleReplacementMappings.single.rules.single;
        expect(
          rule.sourceTerms.map((term) => term.text),
          orderedEquals(['source hero', 'fox ears']),
        );
      },
    );

    testWidgets(
      'keyframe source tag multi-selection can directly create a replacement rule',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final script = _singleFrameScript(
          id: 'frame-source-menu-direct-script',
          name: 'Frame Source Menu Direct Script',
          rootPath: 'frame-source-menu-direct-script',
          baseCaption: 'city lights, rain',
          charCaptions: const ['source hero, fox ears, blue jacket'],
        );
        final cache = RecastScriptCache(
          scriptId: script.id,
          scriptName: script.name,
          sourceRootPath: script.rootPath,
          sourceFingerprint: _normalizedSourceFingerprintForTest(script),
          updatedAt: DateTime.utc(2026, 6, 18),
          mapping: RecastMapping.defaults(script.id).copyWith(
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourcePreview: 'source hero',
              ),
            ],
          ),
          scriptSnapshot: script.toJson(),
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadRecastCacheByScriptId: (_) async => cache,
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(script.rootPath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final positiveColumn =
            find.byKey(const ValueKey('script-keyframe-positive-column')).first;
        final foxEars = find
            .descendant(of: positiveColumn, matching: find.text('fox ears'))
            .first;
        final blueJacket = find
            .descendant(of: positiveColumn, matching: find.text('blue jacket'))
            .first;
        await tester.ensureVisible(foxEars);
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.tap(foxEars);
        await tester.pump();
        await tester.tap(blueJacket);
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        await tester.tap(foxEars, buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('script-frame-add-to-replacement-area')),
        );
        await tester.pumpAndSettle();

        final rule = viewModel.roleReplacementMappings.single.rules.single;
        expect(
          rule.sourceTerms.map((term) => term.text),
          orderedEquals(['fox ears', 'blue jacket']),
        );
      },
    );

    testWidgets(
      'keyframe source comparison highlights tags already in replacement area',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final script = _singleFrameScript(
          id: 'frame-source-replacement-comparison-script',
          name: 'Frame Source Replacement Comparison Script',
          rootPath: 'frame-source-replacement-comparison-script',
          baseCaption: 'city lights, rain',
          charCaptions: const ['source hero, fox ears, blue jacket'],
        );
        final cache = RecastScriptCache(
          scriptId: script.id,
          scriptName: script.name,
          sourceRootPath: script.rootPath,
          sourceFingerprint: _normalizedSourceFingerprintForTest(script),
          updatedAt: DateTime.utc(2026, 6, 26),
          mapping: RecastMapping.defaults(script.id).copyWith(
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourcePreview: 'source hero',
                rules: [
                  ScriptPromptReplacementRule(
                    id: 'rule-fox-ears',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'term-fox-ears',
                        text: 'fox ears',
                        category: PromptTagCategory.upperBody,
                        sourceLocation: 'Role 1',
                        frameIndexes: [1],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          scriptSnapshot: script.toJson(),
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadRecastCacheByScriptId: (_) async => cache,
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(script.rootPath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final positiveColumn =
            find.byKey(const ValueKey('script-keyframe-positive-column')).first;
        PromptTagChip sourceChip(String label) {
          return tester.widget<PromptTagChip>(
            find
                .descendant(
                  of: positiveColumn,
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is PromptTagChip && widget.label == label,
                  ),
                )
                .first,
          );
        }

        expect(
          sourceChip('fox ears').diffState,
          PromptTagChipDiffState.unchanged,
        );

        final compareToggle = find.descendant(
          of: positiveColumn,
          matching: find.byKey(
            const ValueKey('script-keyframe-replacement-compare-toggle'),
          ),
        );
        expect(compareToggle, findsOneWidget);
        await tester.ensureVisible(compareToggle);
        await tester.pumpAndSettle();
        await tester.tap(compareToggle);
        await tester.pumpAndSettle();

        expect(sourceChip('fox ears').diffState, PromptTagChipDiffState.added);
        expect(
          sourceChip('blue jacket').diffState,
          PromptTagChipDiffState.removed,
        );
      },
    );

    testWidgets(
      'keyframe source tag can be assigned to a chosen replacement role',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final script = _singleFrameScript(
          id: 'frame-source-menu-target-picker-script',
          name: 'Frame Source Menu Target Picker Script',
          rootPath: 'frame-source-menu-target-picker-script',
          baseCaption: 'city lights, rain',
          charCaptions: const [
            'source hero, fox ears',
            'source rival, blue jacket',
          ],
        );
        final cache = RecastScriptCache(
          scriptId: script.id,
          scriptName: script.name,
          sourceRootPath: script.rootPath,
          sourceFingerprint: _normalizedSourceFingerprintForTest(script),
          updatedAt: DateTime.utc(2026, 6, 20),
          mapping: RecastMapping.defaults(script.id).copyWith(
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourcePreview: 'source hero',
              ),
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-1',
                displayLabel: 'Role 2',
                sourcePreview: 'source rival',
              ),
            ],
          ),
          scriptSnapshot: script.toJson(),
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadRecastCacheByScriptId: (_) async => cache,
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(script.rootPath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final positiveColumn =
            find.byKey(const ValueKey('script-keyframe-positive-column')).first;
        final foxEars = find
            .descendant(of: positiveColumn, matching: find.text('fox ears'))
            .first;
        await tester.ensureVisible(foxEars);
        await tester.pumpAndSettle();

        await tester.tap(foxEars, buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('script-frame-add-to-replacement-area')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('script-replacement-target-picker')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(
            const ValueKey('script-replacement-target-role-slot-1'),
          ),
        );
        await tester.pumpAndSettle();

        expect(viewModel.roleReplacementMappings[0].rules, isEmpty);
        final rule = viewModel.roleReplacementMappings[1].rules.single;
        expect(
          rule.sourceTerms.map((term) => term.text),
          orderedEquals(['fox ears']),
        );
        expect(rule.sourceTerms.single.sourceLocation, 'Role 2');
      },
    );

    testWidgets(
      'keyframe positive source groups with negative-content tags can create a replacement rule',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final script = _singleFrameScript(
          id: 'frame-source-negative-content-menu-script',
          name: 'Frame Source Negative Content Menu Script',
          rootPath: 'frame-source-negative-content-menu-script',
          baseCaption: 'city lights, rain',
          charCaptions: const ['source hero, uncensored, fox ears'],
        );
        final cache = RecastScriptCache(
          scriptId: script.id,
          scriptName: script.name,
          sourceRootPath: script.rootPath,
          sourceFingerprint: _normalizedSourceFingerprintForTest(script),
          updatedAt: DateTime.utc(2026, 6, 20),
          mapping: RecastMapping.defaults(script.id).copyWith(
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourcePreview: 'source hero',
              ),
            ],
          ),
          scriptSnapshot: script.toJson(),
        );
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadRecastCacheByScriptId: (_) async => cache,
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(script.rootPath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final positiveColumn =
            find.byKey(const ValueKey('script-keyframe-positive-column')).first;
        final foxEars = find
            .descendant(of: positiveColumn, matching: find.text('fox ears'))
            .first;
        await tester.ensureVisible(foxEars);
        await tester.pumpAndSettle();

        await tester.tap(foxEars, buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('script-frame-add-to-replacement-area')),
        );
        await tester.pumpAndSettle();

        final rule = viewModel.roleReplacementMappings.single.rules.single;
        expect(
          rule.sourceTerms.map((term) => term.text),
          orderedEquals(['fox ears']),
        );
        expect(rule.sourceTerms.single.frameIndexes, [1]);
        expect(rule.sourceTerms.single.sourceLocation, '角色 1');
      },
    );

    testWidgets(
      'keyframe source tags can be right clicked into script-only block words',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var savedRules = <String, dynamic>{
          'delete_keywords': 'lowres',
          'strong_filter_keywords': '',
          'replace_rules': '',
        };
        final viewModel = StudioScriptViewModel(
          loadFilterRules: () async => savedRules,
          saveFilterRules: (rules) async {
            savedRules = rules;
          },
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });
        expect(viewModel.diff.recast, contains('city lights'));

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final positiveColumn =
            find.byKey(const ValueKey('script-keyframe-positive-column')).first;
        final cityLights = find
            .descendant(of: positiveColumn, matching: find.text('city lights'))
            .first;
        await tester.ensureVisible(cityLights);
        await tester.pumpAndSettle();
        await tester.tap(cityLights);
        await tester.pump();
        await tester.tap(cityLights, buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('prompt-tag-add-to-filter-rules')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('prompt-tag-filter-target-script')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('prompt-tag-filter-target-script')),
        );
        await tester.pumpAndSettle();

        expect(viewModel.scriptBlockWords, 'city lights');
        expect(viewModel.diff.recast, isNot(contains('city lights')));
        expect(savedRules['delete_keywords'], 'lowres');
      },
    );

    testWidgets('script page uses a left drawer and bottom frame review area', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1900, 1050);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel();
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();

      final pageBox = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('studio-script-page-body')),
      );
      expect(pageBox.size.width, greaterThan(1800));
      expect(
        find.byKey(const ValueKey('script-layout-left-drawer')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('script-layout-main-workspace')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('script-layout-bottom-timeline')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('script-layout-bottom-frame-cards')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('script-keyframe-positive-column')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('script-keyframe-negative-column')),
        findsOneWidget,
      );
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('script-layout-left-drawer')))
            .dx,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('script-layout-main-workspace')),
              )
              .dx,
        ),
      );
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('script-layout-bottom-timeline')),
            )
            .dy,
        greaterThan(
          tester
              .getBottomLeft(
                find.byKey(const ValueKey('script-layout-main-workspace')),
              )
              .dy,
        ),
      );
      expect(
        find.byKey(const ValueKey('script-keyframe-negative-strategy')),
        findsOneWidget,
      );
      expect(find.text('city lights'), findsWidgets);
      expect(find.text('lowres'), findsWidgets);
    });

    testWidgets(
      'script drawer stretches with the main workspace on wide layouts',
      (tester) async {
        tester.view.physicalSize = const Size(1300, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final viewModel = StudioScriptViewModel();
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final drawerBottom = tester
            .getBottomLeft(
              find.byKey(const ValueKey('script-layout-left-drawer')),
            )
            .dy;
        final workspaceBottom = tester
            .getBottomLeft(
              find.byKey(const ValueKey('script-layout-main-workspace')),
            )
            .dy;

        expect(drawerBottom, greaterThanOrEqualTo(workspaceBottom - 1));
      },
    );

    testWidgets(
      'script drawer matches workbench drawer width and hover inset',
      (tester) async {
        tester.view.physicalSize = const Size(1300, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final viewModel = StudioScriptViewModel();
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final drawer = find.byKey(const ValueKey('script-layout-left-drawer'));
        final category = find.byKey(
          const ValueKey('script-drawer-category-artist'),
        );
        expect(drawer, findsOneWidget);
        expect(category, findsOneWidget);
        expect(
          find.descendant(
            of: drawer,
            matching: find.byType(StudioAssetDrawerShell),
          ),
          findsOneWidget,
        );

        expect(tester.getSize(drawer).width, greaterThanOrEqualTo(320));
        expect(
          tester.getTopLeft(category).dx - tester.getTopLeft(drawer).dx,
          greaterThanOrEqualTo(18),
        );

        final categoryList = find.ancestor(
          of: category,
          matching: find.byType(ListView),
        );
        expect(categoryList, findsOneWidget);

        final viewportRect = tester.getRect(categoryList);
        final categoryRect = tester.getRect(category);
        expect(
          categoryRect.left,
          greaterThanOrEqualTo(viewportRect.left + studioAssetDrawerHoverInset),
        );
        expect(
          categoryRect.top,
          greaterThanOrEqualTo(viewportRect.top + studioAssetDrawerHoverInset),
        );
      },
    );

    testWidgets(
      'role mapping renders cards without slot labels and keeps artist separate',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final viewModel = StudioScriptViewModel();
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('role-card-slot-0')), findsOneWidget);
        expect(find.text('瑙掕壊 1'), findsWidgets);
        expect(find.text('鏈嶈 1'), findsWidgets);
        expect(find.text('婧愯鑹叉彁绀鸿瘝'), findsWidgets);
        expect(find.text('鏇挎崲鍚庤緭鍑?'), findsWidgets);
        expect(find.text('婧愯鑹茶韩浠?'), findsWidgets);
        expect(find.text('鏇挎崲瑙掕壊韬唤'), findsWidgets);
        expect(find.text('鎵嬪姩瑕嗙洊杈撳嚭鏍囩'), findsNothing);
        expect(
          find.byKey(
            const ValueKey(
              'role-output-part-slot-0-slot-0-stage-1-upperClothing',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const ValueKey('role-part-slot-0-slot-0-stage-1-upperClothing'),
          ),
          findsNothing,
        );
        expect(
          find.byKey(
            const ValueKey(
              'role-part-slot-0-slot-0-stage-1-upperClothing-tags',
            ),
          ),
          findsNothing,
        );
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.textContaining('slot-0'), findsNothing);
        expect(
          find.byKey(const ValueKey('script-artist-mapping-section')),
          findsOneWidget,
        );
      },
    );

    testWidgets('replacement output parts can be edited as tags', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel();
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });
      final role = viewModel.roleMappings.first;
      final stageId = role.selectedStage!.id;

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final fieldKey = ValueKey(
        'role-output-part-${role.sourceRoleId}-$stageId-upperClothing',
      );
      final field = find.byKey(fieldKey);
      expect(field, findsOneWidget);
      expect(
        find.descendant(of: field, matching: find.byType(PromptTagEditor)),
        findsOneWidget,
      );

      await tester.ensureVisible(field);
      await tester.pumpAndSettle();

      final before = viewModel
          .roleMappings.first.selectedStage!.parts.upperClothing
          .trim();
      await tester.tap(
        find.descendant(
          of: field,
          matching: find.byKey(const ValueKey('prompt-tag-editor-add')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: field,
          matching: find.byKey(const ValueKey('prompt-tag-editor-input')),
        ),
        'manual silver jacket, fur trim',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        viewModel.roleMappings.first.selectedStage!.parts.upperClothing,
        before.isEmpty
            ? 'manual silver jacket, fur trim'
            : '$before, manual silver jacket, fur trim',
      );
      expect(find.text('manual silver jacket'), findsWidgets);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    });

    testWidgets('role outfit stages can be renamed and assigned frames', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final script = _scriptWithFrames(
        [
          (
            index: 1,
            base: 'artist:test, bedroom',
            chars: ['ai hero, blue jacket'],
          ),
          (
            index: 2,
            base: 'artist:test, hallway',
            chars: ['ai hero, blue jacket'],
          ),
          (
            index: 3,
            base: 'artist:test, beach',
            chars: ['ai hero, white bikini'],
          ),
        ],
        id: 'editable-stage-widget-script',
        name: 'Editable Stage Widget Script',
        rootPath: 'editable-stage-widget-script',
      );
      final cache = RecastScriptCache(
        scriptId: script.id,
        scriptName: script.name,
        sourceRootPath: script.rootPath,
        sourceFingerprint: _normalizedSourceFingerprintForTest(script),
        updatedAt: DateTime.utc(2026, 6, 13),
        mapping: RecastMapping.defaults(script.id).copyWith(
          roleAssemblies: const [
            RoleAssembly(
              sourceRoleId: 'slot-0',
              displayLabel: 'AI Hero',
              sourceName: 'AI Hero',
              stages: [
                RoleAssemblyStage(
                  id: 'main-outfit',
                  label: 'main outfit',
                  frameIndexes: [1, 2],
                  sourceParts: RecastPromptParts(
                    upperClothing: 'blue jacket',
                  ),
                ),
              ],
            ),
          ],
        ),
        scriptSnapshot: script.toJson(),
      );
      final viewModel = StudioScriptViewModel(
        parserService: _FakeParserService([script]),
        loadRecastCacheByScriptId: (_) async => cache,
      );
      await tester.runAsync(() async {
        await viewModel.importScriptPath(script.rootPath);
      });
      final role = viewModel.roleMappings.single;
      final stageId = role.selectedStage!.id;

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final renameButton = find.byKey(
        ValueKey('role-rename-stage-${role.sourceRoleId}-$stageId'),
      );
      await tester.tap(renameButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const ValueKey('role-stage-rename-input')),
        'black raincoat',
      );
      await tester.tap(find.byKey(const ValueKey('role-stage-rename-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
          viewModel.roleMappings.single.selectedStage!.label, 'black raincoat');
      expect(find.text('black raincoat'), findsWidgets);

      final framesButton = find.byKey(
        ValueKey('role-edit-stage-frames-${role.sourceRoleId}-$stageId'),
      );
      await tester.tap(framesButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const ValueKey('role-stage-frames-input')),
        '3, 5-6, 5',
      );
      await tester.tap(find.byKey(const ValueKey('role-stage-frames-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
          viewModel.roleMappings.single.selectedStage!.frameIndexes, [3, 5, 6]);
      expect(find.text('帧 3, 5, 6'), findsOneWidget);
    });

    testWidgets(
      'wide role compare rows keep source and output cells equal height',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late final Script parsedScript;
        await tester.runAsync(() async {
          parsedScript = await const ScriptRecastParserService().parseDirectory(
            Directory(_fixturePath),
          );
        });
        final longOutput = [
          'cat ears',
          'animal ear fluff',
          'animal ears',
          'hair ornament',
          'jewelry',
          'long hair',
          'skin fang',
          'lotus flower headdress',
        ].join(', ');
        final caches = [
          RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _sourceFingerprintForTest(parsedScript),
            updatedAt: DateTime.utc(2026, 6, 7),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              roleAssemblies: [
                RoleAssembly(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourceName: 'AI Hero',
                  stages: [
                    RoleAssemblyStage(
                      id: 'main-outfit',
                      label: 'main outfit',
                      frameIndexes: const [1, 2],
                      sourceParts: const RecastPromptParts(
                        upperBody: 'blue cat ear headband',
                      ),
                      manualParts: RecastPromptParts(upperBody: longOutput),
                    ),
                  ],
                ),
              ],
            ),
            scriptSnapshot: parsedScript.toJson(),
          ),
        ];
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });
        final role = viewModel.roleMappings.first;
        final stageId = role.selectedStage!.id;

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pump(const Duration(milliseconds: 500));

        final sourceField = find.byKey(
          ValueKey('role-source-part-${role.sourceRoleId}-$stageId-upperBody'),
        );
        final outputCell = find.byKey(
          ValueKey(
            'role-output-part-drop-${role.sourceRoleId}-$stageId-upperBody',
          ),
        );
        expect(sourceField, findsOneWidget);
        expect(outputCell, findsOneWidget);
        await tester.ensureVisible(sourceField);
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          tester.getSize(sourceField).height,
          closeTo(tester.getSize(outputCell).height, 0.1),
        );
      },
    );

    testWidgets('replacement delete keeps stale source selections untouched', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel();
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });
      final role = viewModel.roleMappings.first;
      final stageId = role.selectedStage!.id;
      viewModel.setRoleStageSourcePart(
        sourceRoleId: role.sourceRoleId,
        stageId: stageId,
        part: StudioScriptRolePart.upperClothing,
        value: 'source keep, source stale',
      );
      viewModel.setRoleStagePart(
        sourceRoleId: role.sourceRoleId,
        stageId: stageId,
        part: StudioScriptRolePart.upperClothing,
        value: 'target keep, target stale',
      );

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      final sourceField = find.byKey(
        ValueKey(
          'role-source-part-${role.sourceRoleId}-$stageId-upperClothing',
        ),
      );
      final targetField = find.byKey(
        ValueKey(
          'role-output-part-${role.sourceRoleId}-$stageId-upperClothing',
        ),
      );
      expect(sourceField, findsOneWidget);
      expect(targetField, findsOneWidget);
      await tester.ensureVisible(sourceField);
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(of: sourceField, matching: find.text('source stale')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: targetField, matching: find.text('target stale')),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      final stage = viewModel.roleMappings.first.selectedStage!;
      expect(stage.sourceParts.upperClothing, 'source keep, source stale');
      expect(stage.parts.upperClothing, 'target keep');
    });

    testWidgets(
      'replacement editor resets local text when switching outfit stages',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final viewModel = StudioScriptViewModel();
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
          viewModel.aiRoleExtraction = const ScriptAiRoleExtraction(
            status: ScriptAiRoleExtractionStatus.ready,
            confidence: 0.9,
            roles: [
              ScriptAiExtractedRole(
                sourceRoleId: 'slot-0',
                displayName: 'Stage Hero',
                confidence: 0.9,
                stages: [
                  ScriptAiExtractedStage(
                    stageId: 'stage-one',
                    label: 'first outfit',
                    frameIndexes: [1],
                    identity: 'stage hero',
                    upperClothing: 'source jacket one',
                    confidence: 0.9,
                  ),
                  ScriptAiExtractedStage(
                    stageId: 'stage-two',
                    label: 'second outfit',
                    frameIndexes: [2],
                    identity: 'stage hero',
                    upperClothing: 'source jacket two',
                    confidence: 0.9,
                  ),
                ],
              ),
            ],
          );
          await viewModel.applyHighConfidenceAiRoleExtraction();
        });
        final role = viewModel.roleMappings.first;
        final sourceRoleId = role.sourceRoleId;
        final firstStageId = role.stageItems.first.id;
        final secondStageId = role.stageItems.last.id;
        viewModel.setRoleStagePart(
          sourceRoleId: sourceRoleId,
          stageId: firstStageId,
          part: StudioScriptRolePart.upperClothing,
          value: 'shared jacket',
        );
        viewModel.setRoleStagePart(
          sourceRoleId: sourceRoleId,
          stageId: secondStageId,
          part: StudioScriptRolePart.upperClothing,
          value: 'shared jacket',
        );
        viewModel.selectRoleStage(sourceRoleId, firstStageId);

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final firstField = find.byKey(
          ValueKey(
            'role-output-part-$sourceRoleId-$firstStageId-upperClothing',
          ),
        );
        expect(firstField, findsOneWidget);
        await tester.ensureVisible(firstField);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(
          find.descendant(
            of: firstField,
            matching: find.byKey(const ValueKey('prompt-tag-editor-delete-0')),
          ),
        );

        viewModel.selectRoleStage(sourceRoleId, secondStageId);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final secondField = find.byKey(
          ValueKey(
            'role-output-part-$sourceRoleId-$secondStageId-upperClothing',
          ),
        );
        expect(secondField, findsOneWidget);
        expect(
          viewModel.roleMappings.first.selectedStage!.parts.upperClothing,
          'shared jacket',
        );
        expect(
          find.descendant(
            of: secondField,
            matching: find.text('shared jacket'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('source prompt parts use read-only selectable tag display', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final translationCache = TranslationCache();
      final viewModel = StudioScriptViewModel(
        translationCache: translationCache,
        loadCharacters: () async => const [
          CharacterEntry(
            id: 'char-hero',
            name: 'library character',
            traits: ViewVariantTexts(frontFull: 'green eyes'),
            anchorTags: ['library_hero'],
            identityTags: ['green eyes'],
          ),
        ],
      );
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });
      final role = viewModel.roleMappings.first;
      final stageId = role.selectedStage!.id;
      final sourceTag = role.sourcePreview.trim();
      expect(sourceTag, isNotEmpty);
      translationCache.setManual(sourceTag, 'cached source role');
      viewModel.setRoleCharacter(role.sourceRoleId, 'char-hero');

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      final fieldKey = ValueKey(
        'role-source-part-${role.sourceRoleId}-$stageId-identity',
      );
      final field = find.byKey(fieldKey);
      expect(field, findsOneWidget);
      expect(
        find.descendant(of: field, matching: find.byType(PromptTagDisplay)),
        findsOneWidget,
      );
      final tagDisplay = tester.widget<PromptTagDisplay>(
        find.descendant(of: field, matching: find.byType(PromptTagDisplay)),
      );
      expect(tagDisplay.initialLayoutMode, PromptTagLayoutMode.sourceOrder);
      expect(
        find.descendant(of: field, matching: find.byType(PromptTagEditor)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: field,
          matching: find.byKey(const ValueKey('prompt-tag-selection-area')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: field, matching: find.text('cached source role')),
        findsOneWidget,
      );

      await tester.ensureVisible(field);
      await tester.tap(
        find.descendant(of: field, matching: find.text(sourceTag)).first,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('澶嶅埗鏍囩'), findsOneWidget);
    });

    testWidgets(
      'role source prompt parts keep source order without auto groups',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final viewModel = StudioScriptViewModel();
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });
        final role = viewModel.roleMappings.first;
        final stageId = role.selectedStage!.id;
        viewModel.setRoleStageSourcePart(
          sourceRoleId: role.sourceRoleId,
          stageId: stageId,
          part: StudioScriptRolePart.upperClothing,
          value: 'black jacket, best quality',
        );

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final field = find.byKey(
          ValueKey(
            'role-source-part-${role.sourceRoleId}-$stageId-upperClothing',
          ),
        );
        expect(field, findsOneWidget);
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();

        final tagDisplay = tester.widget<PromptTagDisplay>(
          find.descendant(of: field, matching: find.byType(PromptTagDisplay)),
        );
        expect(tagDisplay.initialLayoutMode, PromptTagLayoutMode.sourceOrder);
        expect(tagDisplay.respectInitialLayoutMode, isTrue);
        expect(
          find.descendant(
            of: field,
            matching: find.byKey(const ValueKey('prompt-tag-group-quality')),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: field,
            matching: find.byKey(const ValueKey('prompt-tag-group-clothing')),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: field,
            matching: find.byKey(
              const ValueKey('prompt-tag-chip-black jacket-0-idle'),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: field,
            matching: find.byKey(
              const ValueKey('prompt-tag-chip-best quality-1-idle'),
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'selected source outfit tags can be deleted from current stage',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            _highConfidenceSlotExtraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
          await viewModel.generateAiRoleExtraction();
          await viewModel.applyHighConfidenceAiRoleExtraction();
        });
        final role = viewModel.roleMappings.first;
        final stageId = role.selectedStage!.id;
        final beforeSummary = role.selectedStage!.sourceSummary;
        final tags = beforeSummary
            .split(',')
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toList(growable: false);
        expect(tags.length, greaterThan(1));
        final deletedTag = tags.first;
        final keptTag = tags.last;

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final field = find.byKey(
          ValueKey(
            'role-source-part-${role.sourceRoleId}-$stageId-upperClothing',
          ),
        );
        expect(field, findsOneWidget);
        await tester.ensureVisible(field);
        await tester.tap(
          find.descendant(of: field, matching: find.text(deletedTag)).first,
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pumpAndSettle();

        final afterSummary =
            viewModel.roleMappings.first.selectedStage!.sourceSummary;
        expect(afterSummary, isNot(contains(deletedTag)));
        expect(afterSummary, contains(keptTag));
        expect(
          find.descendant(of: field, matching: find.text(deletedTag)),
          findsNothing,
        );
      },
    );

    testWidgets(
      'role replacement output tags drag between parts and update stage',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 3600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final viewModel = StudioScriptViewModel();
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });
        final role = viewModel.roleMappings.first;
        final stageId = role.selectedStage!.id;
        viewModel.setRoleStagePart(
          sourceRoleId: role.sourceRoleId,
          stageId: stageId,
          part: StudioScriptRolePart.upperClothing,
          value: 'cat ears, fox ears',
        );
        viewModel.setRoleStagePart(
          sourceRoleId: role.sourceRoleId,
          stageId: stageId,
          part: StudioScriptRolePart.lowerClothing,
          value: 'cat tail',
        );

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final upperField = find.byKey(
          ValueKey(
            'role-output-part-${role.sourceRoleId}-$stageId-upperClothing',
          ),
        );
        final lowerField = find.byKey(
          ValueKey(
            'role-output-part-${role.sourceRoleId}-$stageId-lowerClothing',
          ),
        );
        expect(upperField, findsOneWidget);
        expect(lowerField, findsOneWidget);
        await tester.ensureVisible(upperField);
        await tester.pumpAndSettle();

        final upperChip = find.descendant(
          of: upperField,
          matching: find.byKey(const ValueKey('prompt-tag-editor-chip-0')),
        );
        final lowerDropArea = find.descendant(
          of: lowerField,
          matching: find.byKey(
            const ValueKey('prompt-tag-editor-selection-area'),
          ),
        );
        await tester.tap(upperChip);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: upperField,
            matching: find.byKey(
              const ValueKey('prompt-tag-editor-chip-check-0'),
            ),
          ),
          findsOneWidget,
        );
        await _dragSelectedTagTo(tester, upperChip, lowerDropArea);

        final stage = viewModel.roleMappings.first.selectedStage!;
        expect(stage.parts.upperClothing, 'fox ears');
        expect(stage.parts.lowerClothing, 'cat tail, cat ears');
      },
    );

    testWidgets('role replacement output tags show and edit weights', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel();
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });
      final role = viewModel.roleMappings.first;
      final stageId = role.selectedStage!.id;
      viewModel.setRoleStagePart(
        sourceRoleId: role.sourceRoleId,
        stageId: stageId,
        part: StudioScriptRolePart.upperClothing,
        value: '1.25::cat ears::, fox ears',
      );

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      final field = find.byKey(
        ValueKey(
          'role-output-part-${role.sourceRoleId}-$stageId-upperClothing',
        ),
      );
      expect(field, findsOneWidget);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: field, matching: find.text('cat ears')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: field, matching: find.text('x1.25')),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(of: field, matching: find.text('cat ears')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('prompt-tag-editor-edit-weight')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('prompt-tag-editor-edit-weight-field')),
        '0.75',
      );
      await tester.tap(
        find.byKey(const ValueKey('prompt-tag-editor-edit-weight-save')),
      );
      await tester.pumpAndSettle();

      final stage = viewModel.roleMappings.first.selectedStage!;
      expect(stage.parts.upperClothing, '0.75:: cat ears ::, fox ears');
      expect(
        find.descendant(of: field, matching: find.text('x0.75')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: field, matching: find.text('x1.25')),
        findsNothing,
      );
    });

    testWidgets('role source tags show weights', (tester) async {
      tester.view.physicalSize = const Size(1600, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel();
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });
      final role = viewModel.roleMappings.first;
      final stageId = role.selectedStage!.id;
      viewModel.setRoleStageSourcePart(
        sourceRoleId: role.sourceRoleId,
        stageId: stageId,
        part: StudioScriptRolePart.upperClothing,
        value: '1.25::cat ears::, fox ears',
      );

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      final field = find.byKey(
        ValueKey(
          'role-source-part-${role.sourceRoleId}-$stageId-upperClothing',
        ),
      );
      expect(field, findsOneWidget);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: field, matching: find.text('cat ears')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: field, matching: find.text('x1.25')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: field, matching: find.text('1.25::cat ears::')),
        findsNothing,
      );
    });

    testWidgets('role source tags can edit weights', (tester) async {
      tester.view.physicalSize = const Size(1600, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel();
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });
      final role = viewModel.roleMappings.first;
      final stageId = role.selectedStage!.id;
      viewModel.setRoleStageSourcePart(
        sourceRoleId: role.sourceRoleId,
        stageId: stageId,
        part: StudioScriptRolePart.upperClothing,
        value: '1.25::cat ears::, fox ears',
      );

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      final field = find.byKey(
        ValueKey(
          'role-source-part-${role.sourceRoleId}-$stageId-upperClothing',
        ),
      );
      expect(field, findsOneWidget);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(of: field, matching: find.text('cat ears')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('prompt-tag-edit-weight')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('prompt-tag-edit-weight-field')),
        '0.75',
      );
      await tester.tap(
        find.byKey(const ValueKey('prompt-tag-edit-weight-save')),
      );
      await tester.pumpAndSettle();

      final stage = viewModel.roleMappings.first.selectedStage!;
      expect(stage.sourceParts.upperClothing, '0.75:: cat ears ::, fox ears');
      expect(
        find.descendant(of: field, matching: find.text('x0.75')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: field, matching: find.text('x1.25')),
        findsNothing,
      );
    });

    testWidgets('role source tags drag between parts and update source stage', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel();
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });
      final role = viewModel.roleMappings.first;
      final stageId = role.selectedStage!.id;
      viewModel.setRoleStageSourcePart(
        sourceRoleId: role.sourceRoleId,
        stageId: stageId,
        part: StudioScriptRolePart.upperClothing,
        value: 'cat ears, fox ears',
      );
      viewModel.setRoleStageSourcePart(
        sourceRoleId: role.sourceRoleId,
        stageId: stageId,
        part: StudioScriptRolePart.lowerClothing,
        value: 'cat tail',
      );

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      final upperField = find.byKey(
        ValueKey(
          'role-source-part-${role.sourceRoleId}-$stageId-upperClothing',
        ),
      );
      final lowerField = find.byKey(
        ValueKey(
          'role-source-part-${role.sourceRoleId}-$stageId-lowerClothing',
        ),
      );
      expect(upperField, findsOneWidget);
      expect(lowerField, findsOneWidget);
      await tester.ensureVisible(upperField);
      await tester.pumpAndSettle();

      final idleUpperChip = find.descendant(
        of: upperField,
        matching: find.byKey(const ValueKey('prompt-tag-chip-cat ears-0-idle')),
      );
      final lowerDropArea = find.descendant(
        of: lowerField,
        matching: find.byKey(const ValueKey('prompt-tag-selection-area')),
      );
      await tester.tap(idleUpperChip);
      await tester.pumpAndSettle();
      final selectedUpperChip = find.descendant(
        of: upperField,
        matching: find.byKey(
          const ValueKey('prompt-tag-chip-cat ears-0-selected'),
        ),
      );
      await _dragSelectedTagTo(tester, selectedUpperChip, lowerDropArea);

      final stage = viewModel.roleMappings.first.selectedStage!;
      expect(stage.sourceParts.upperClothing, 'fox ears');
      expect(stage.sourceParts.lowerClothing, 'cat tail, cat ears');
      expect(stage.sourceSummary, contains('fox ears'));
      expect(stage.sourceSummary, contains('cat tail'));
      expect(stage.sourceSummary, contains('cat ears'));
    });

    testWidgets('role source tags support marquee selection across part rows', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel();
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });
      final role = viewModel.roleMappings.first;
      final stageId = role.selectedStage!.id;
      viewModel.setRoleStageSourcePart(
        sourceRoleId: role.sourceRoleId,
        stageId: stageId,
        part: StudioScriptRolePart.upperClothing,
        value: 'cat ears',
      );
      viewModel.setRoleStageSourcePart(
        sourceRoleId: role.sourceRoleId,
        stageId: stageId,
        part: StudioScriptRolePart.lowerClothing,
        value: 'cat tail',
      );

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      final upperField = find.byKey(
        ValueKey(
          'role-source-part-${role.sourceRoleId}-$stageId-upperClothing',
        ),
      );
      final lowerField = find.byKey(
        ValueKey(
          'role-source-part-${role.sourceRoleId}-$stageId-lowerClothing',
        ),
      );
      expect(upperField, findsOneWidget);
      expect(lowerField, findsOneWidget);
      await tester.ensureVisible(upperField);
      await tester.pumpAndSettle();

      final upperChip = find.descendant(
        of: upperField,
        matching: find.byKey(const ValueKey('prompt-tag-chip-cat ears-0-idle')),
      );
      final lowerChip = find.descendant(
        of: lowerField,
        matching: find.byKey(const ValueKey('prompt-tag-chip-cat tail-0-idle')),
      );
      final start = tester.getTopLeft(upperChip) - const Offset(8, 4);
      final end = tester.getBottomRight(lowerChip) + const Offset(8, 4);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: start);
      await tester.pump();
      await mouse.down(start);
      await mouse.moveTo(end);
      await tester.pump();

      Color previewBorderColor(Finder finder) {
        final chip = tester.widget<AnimatedContainer>(finder);
        final decoration = chip.decoration! as BoxDecoration;
        final border = decoration.border! as Border;
        return border.top.color;
      }

      expect(previewBorderColor(upperChip), StudioTokens.info);
      expect(previewBorderColor(lowerChip), StudioTokens.info);

      await mouse.up();
      await tester.pumpAndSettle();
      await mouse.removePointer();

      expect(
        find.descendant(
          of: upperField,
          matching: find.byKey(
            const ValueKey('prompt-tag-chip-cat ears-0-selected'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: lowerField,
          matching: find.byKey(
            const ValueKey('prompt-tag-chip-cat tail-0-selected'),
          ),
        ),
        findsOneWidget,
      );
      final comparePanel = find.byKey(
        const ValueKey('role-prompt-compare-panel'),
      );
      expect(
        find.descendant(
          of: comparePanel,
          matching: find.byKey(const ValueKey('prompt-tag-selection-toolbar')),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: comparePanel,
          matching: find.byKey(
            const ValueKey('prompt-tag-editor-selection-toolbar'),
          ),
        ),
        findsNothing,
      );
    });

    testWidgets(
      'cross-row selected source tags copy into an empty output part',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 3600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final viewModel = StudioScriptViewModel();
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });
        final role = viewModel.roleMappings.first;
        final stageId = role.selectedStage!.id;
        viewModel.setRoleStageSourcePart(
          sourceRoleId: role.sourceRoleId,
          stageId: stageId,
          part: StudioScriptRolePart.upperClothing,
          value: 'cat ears',
        );
        viewModel.setRoleStageSourcePart(
          sourceRoleId: role.sourceRoleId,
          stageId: stageId,
          part: StudioScriptRolePart.lowerClothing,
          value: 'cat tail',
        );
        viewModel.setRoleStagePart(
          sourceRoleId: role.sourceRoleId,
          stageId: stageId,
          part: StudioScriptRolePart.lowerClothing,
          value: '',
        );

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final upperSourceField = find.byKey(
          ValueKey(
            'role-source-part-${role.sourceRoleId}-$stageId-upperClothing',
          ),
        );
        final lowerSourceField = find.byKey(
          ValueKey(
            'role-source-part-${role.sourceRoleId}-$stageId-lowerClothing',
          ),
        );
        final lowerOutputField = find.byKey(
          ValueKey(
            'role-output-part-${role.sourceRoleId}-$stageId-lowerClothing',
          ),
        );
        await tester.ensureVisible(upperSourceField);
        await tester.pumpAndSettle();

        final upperChip = find.descendant(
          of: upperSourceField,
          matching: find.byKey(
            const ValueKey('prompt-tag-chip-cat ears-0-idle'),
          ),
        );
        final lowerChip = find.descendant(
          of: lowerSourceField,
          matching: find.byKey(
            const ValueKey('prompt-tag-chip-cat tail-0-idle'),
          ),
        );
        final marqueeStart = tester.getTopLeft(upperChip) - const Offset(8, 4);
        final marqueeEnd =
            tester.getBottomRight(lowerChip) + const Offset(8, 4);
        final marquee = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await marquee.addPointer(location: marqueeStart);
        await tester.pump();
        await marquee.down(marqueeStart);
        await marquee.moveTo(marqueeEnd);
        await tester.pump();
        await marquee.up();
        await tester.pumpAndSettle();
        await marquee.removePointer();

        final selectedUpperChip = find.descendant(
          of: upperSourceField,
          matching: find.byKey(
            const ValueKey('prompt-tag-chip-cat ears-0-selected'),
          ),
        );
        final outputDropArea = find.descendant(
          of: lowerOutputField,
          matching: find.byKey(
            const ValueKey('prompt-tag-editor-selection-area'),
          ),
        );
        await _dragSelectedTagTo(tester, selectedUpperChip, outputDropArea);

        final stage = viewModel.roleMappings.first.selectedStage!;
        expect(stage.sourceParts.upperClothing, 'cat ears');
        expect(stage.sourceParts.lowerClothing, 'cat tail');
        expect(stage.parts.lowerClothing, 'cat ears, cat tail');
      },
    );

    testWidgets(
      'copied source tag is not dragged again with its output target',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late final Script parsedScript;
        await tester.runAsync(() async {
          parsedScript = await const ScriptRecastParserService().parseDirectory(
            Directory(_fixturePath),
          );
        });
        final caches = [
          RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _sourceFingerprintForTest(parsedScript),
            updatedAt: DateTime.utc(2026, 6, 8),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              roleAssemblies: const [
                RoleAssembly(
                  sourceRoleId: 'role-source-drag-copy',
                  displayLabel: 'Role drag copy',
                  sourceName: 'source character',
                  stages: [
                    RoleAssemblyStage(
                      id: 'main-outfit',
                      label: 'main outfit',
                      frameIndexes: [1],
                      sourceParts: RecastPromptParts(upperClothing: 'cat ears'),
                    ),
                  ],
                ),
              ],
            ),
            scriptSnapshot: parsedScript.toJson(),
          ),
        ];
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });
        final role = viewModel.roleMappings.singleWhere(
          (candidate) => candidate.sourceRoleId == 'role-source-drag-copy',
        );
        final stageId = role.stageItems.single.id;

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final sourceField = find.byKey(
          ValueKey(
            'role-source-part-${role.sourceRoleId}-$stageId-upperClothing',
          ),
        );
        final upperOutputField = find.byKey(
          ValueKey(
            'role-output-part-${role.sourceRoleId}-$stageId-upperClothing',
          ),
        );
        final lowerOutputField = find.byKey(
          ValueKey(
            'role-output-part-${role.sourceRoleId}-$stageId-lowerClothing',
          ),
        );
        await tester.ensureVisible(sourceField);
        await tester.pumpAndSettle();

        final sourceChip = find.descendant(
          of: sourceField,
          matching: find.byKey(
            const ValueKey('prompt-tag-chip-cat ears-0-idle'),
          ),
        );
        final lowerDropArea = find.descendant(
          of: lowerOutputField,
          matching: find.byKey(
            const ValueKey('prompt-tag-editor-selection-area'),
          ),
        );
        await tester.tap(sourceChip);
        await tester.pumpAndSettle();
        final selectedSourceChip = find.descendant(
          of: sourceField,
          matching: find.byKey(
            const ValueKey('prompt-tag-chip-cat ears-0-selected'),
          ),
        );
        await _dragSelectedTagTo(tester, selectedSourceChip, lowerDropArea);

        expect(
          find.descendant(
            of: sourceField,
            matching: find.byKey(
              const ValueKey('prompt-tag-chip-cat ears-0-selected'),
            ),
          ),
          findsNothing,
        );
        final lowerOutputChip = find.descendant(
          of: lowerOutputField,
          matching: find.byKey(const ValueKey('prompt-tag-editor-chip-0')),
        );
        final upperDropArea = find.descendant(
          of: upperOutputField,
          matching: find.byKey(
            const ValueKey('prompt-tag-editor-selection-area'),
          ),
        );
        await _dragSelectedTagTo(tester, lowerOutputChip, upperDropArea);

        final stage = viewModel.roleMappings.first.selectedStage!;
        expect(stage.sourceParts.upperClothing, 'cat ears');
        expect(stage.parts.upperClothing, 'cat ears');
        expect(stage.parts.lowerClothing, '');
      },
    );

    testWidgets(
      'role compare marquee keeps source and output selections apart',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late final Script parsedScript;
        await tester.runAsync(() async {
          parsedScript = await const ScriptRecastParserService().parseDirectory(
            Directory(_fixturePath),
          );
        });
        final caches = [
          RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _sourceFingerprintForTest(parsedScript),
            updatedAt: DateTime.utc(2026, 6, 8),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              roleAssemblies: const [
                RoleAssembly(
                  sourceRoleId: 'role-marquee-split',
                  displayLabel: 'Role marquee split',
                  sourceName: 'source character',
                  stages: [
                    RoleAssemblyStage(
                      id: 'main-outfit',
                      label: 'main outfit',
                      frameIndexes: [1],
                      sourceParts: RecastPromptParts(upperClothing: 'cat ears'),
                      manualParts: RecastPromptParts(
                        upperClothing: 'target jacket',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            scriptSnapshot: parsedScript.toJson(),
          ),
        ];
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });
        final role = viewModel.roleMappings.singleWhere(
          (candidate) => candidate.sourceRoleId == 'role-marquee-split',
        );
        final stageId = role.stageItems.single.id;

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final sourceField = find.byKey(
          ValueKey(
            'role-source-part-${role.sourceRoleId}-$stageId-upperClothing',
          ),
        );
        final outputField = find.byKey(
          ValueKey(
            'role-output-part-${role.sourceRoleId}-$stageId-upperClothing',
          ),
        );
        await tester.ensureVisible(sourceField);
        await tester.pumpAndSettle();

        final sourceChip = find.descendant(
          of: sourceField,
          matching: find.byKey(
            const ValueKey('prompt-tag-chip-cat ears-0-idle'),
          ),
        );
        final outputChip = find.descendant(
          of: outputField,
          matching: find.byKey(const ValueKey('prompt-tag-editor-chip-0')),
        );
        final marqueeStart = tester.getTopLeft(sourceChip) - const Offset(8, 4);
        final marqueeEnd =
            tester.getBottomRight(outputChip) + const Offset(8, 4);
        final marquee = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await marquee.addPointer(location: marqueeStart);
        await tester.pump();
        await marquee.down(marqueeStart);
        await marquee.moveTo(marqueeEnd);
        await tester.pump();
        await marquee.up();
        await tester.pumpAndSettle();
        await marquee.removePointer();

        expect(
          find.descendant(
            of: sourceField,
            matching: find.byKey(
              const ValueKey('prompt-tag-chip-cat ears-0-selected'),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: outputField,
            matching: find.byKey(
              const ValueKey('prompt-tag-editor-chip-check-0'),
            ),
          ),
          findsNothing,
        );
      },
    );

    test(
      'role part quick copy overwrites matching output and keeps source',
      () async {
        var caches = <RecastScriptCache>[];
        final seedViewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );
        await seedViewModel.importScriptPath(_fixturePath);
        await seedViewModel.useFreshParseForChangedSource();
        final cache = caches.single;
        caches = [
          RecastScriptCache(
            scriptId: cache.scriptId,
            scriptName: cache.scriptName,
            sourceRootPath: cache.sourceRootPath,
            sourceFingerprint: cache.sourceFingerprint,
            updatedAt: cache.updatedAt,
            mapping: cache.mapping.copyWith(
              roleAssemblies: const [
                RoleAssembly(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'Role 1',
                  sourceName: 'source character',
                  stages: [
                    RoleAssemblyStage(
                      id: 'main-outfit',
                      label: 'main outfit',
                      frameIndexes: [1],
                      sourceParts: RecastPromptParts(upperClothing: 'cat ears'),
                      manualParts: RecastPromptParts(
                        upperClothing: 'old jacket',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            scriptSnapshot: cache.scriptSnapshot,
          ),
        ];
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );
        await viewModel.importScriptPath(_fixturePath);
        final role = viewModel.roleMappings.first;
        final stageId = role.stageItems.single.id;
        final source = role.stageItems.single.sourceParts.upperClothing.trim();

        viewModel.setRoleStagePart(
          sourceRoleId: role.sourceRoleId,
          stageId: stageId,
          part: StudioScriptRolePart.upperClothing,
          value: source,
        );

        final stage = viewModel.roleMappings.first.selectedStage!;
        expect(stage.sourceParts.upperClothing, 'cat ears');
        expect(stage.parts.upperClothing, 'cat ears');
      },
    );

    testWidgets(
      'artist mapping renders translated source and replacement tags',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final translationCache = TranslationCache()
          ..setManual('artist:terasu_mc', 'cached source artist')
          ..setManual('artist:replacement', 'cached replacement artist');
        final viewModel = StudioScriptViewModel(
          translationCache: translationCache,
          loadArtistChains: () async => const [
            ArtistChain(
              id: 'artist-chain-1',
              name: 'Replacement Chain',
              prompt: 'artist:replacement',
            ),
          ],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final sourceTags = find.byKey(const ValueKey('artist-source-tags-0'));
        final outputTags = find.byKey(const ValueKey('artist-output-tags-0'));
        expect(sourceTags, findsOneWidget);
        expect(outputTags, findsOneWidget);
        expect(
          find.byKey(const ValueKey('artist-drop-target-0')),
          findsOneWidget,
        );
        expect(
          find.ancestor(
            of: find.byKey(const ValueKey('artist-drop-target-0')),
            matching: find.byType(StudioStaggeredReveal),
          ),
          findsOneWidget,
        );
        expect(
          tester.getTopLeft(sourceTags).dy < tester.getTopLeft(outputTags).dy,
          isTrue,
        );
        expect(
          find.descendant(of: sourceTags, matching: find.text('源画师串')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: outputTags, matching: find.text('替换后画师串')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: sourceTags,
            matching: find.byType(PromptTagDisplay),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: sourceTags,
            matching: find.text('artist:terasu_mc'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: sourceTags,
            matching: find.text('cached source artist'),
          ),
          findsOneWidget,
        );

        viewModel.setArtistChain('artist-chain-1');
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: outputTags,
            matching: find.text('artist:replacement'),
          ),
          findsWidgets,
        );
        expect(
          find.descendant(
            of: outputTags,
            matching: find.text('cached replacement artist'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('artist mapping target prompt can be typed manually', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel();
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      const manualPrompt = 'artist:manual_style, soft watercolor lighting';
      final input = find.byKey(const ValueKey('artist-output-input-0'));
      expect(input, findsOneWidget);
      await tester.ensureVisible(input);
      await tester.enterText(input, manualPrompt);
      await tester.pumpAndSettle();

      expect(viewModel.artistMappings.single.selectedArtistChainId, isNull);
      expect(viewModel.artistMappings.single.manualPrompt, manualPrompt);
      final afterTags = viewModel.selectedFramePreviews.last.groups
          .expand((group) => group.tags)
          .toList(growable: false);
      expect(afterTags, contains('artist:manual_style'));
      expect(afterTags, contains('soft watercolor lighting'));
    });

    testWidgets(
      'manual artist mapping target exposes visible save asset action',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final viewModel = StudioScriptViewModel();
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('artist-output-input-0')),
          'artist:manual_style, soft watercolor lighting',
        );
        await tester.pumpAndSettle();

        final action = find.byKey(
          const ValueKey('script-artist-mapping-save-target-0'),
        );
        expect(action, findsOneWidget);
        expect(
          find.descendant(of: action, matching: find.text('淇濆瓨绱犳潗')),
          findsOneWidget,
        );
      },
    );

    testWidgets('source artist mapping exposes visible save asset action', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel();
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      final action = find.byKey(
        const ValueKey('script-artist-mapping-save-source-0'),
      );
      expect(action, findsOneWidget);
      expect(
        find.descendant(of: action, matching: find.text('淇濆瓨绱犳潗')),
        findsOneWidget,
      );
    });

    testWidgets('source artist mapping save dialog uses Chinese default name', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final viewModel = StudioScriptViewModel();
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.build(),
          home: StudioAssetCaptureHost(
            service: _ImmediateCaptureService(),
            child: StudioScriptPage(viewModel: viewModel),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('script-artist-mapping-save-source-0')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('婧愮敾甯堜覆 1'), findsOneWidget);
      expect(find.text('Source artist chain 1'), findsNothing);
    });

    testWidgets('artist mapping row places source and target vibes correctly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel(
        loadArtistChains: () async => const [
          ArtistChain(
            id: 'artist-chain-1',
            name: 'chain with vibe',
            prompt: 'artist:replacement',
            vibeRefs: [
              WorkspaceVibeReference(
                id: 'bound-vibe',
                name: 'Bound Vibe',
                vibeB64: 'encoded-bound-vibe',
                referenceStrength: 0.4,
              ),
            ],
          ),
        ],
        loadVibes: () async => const [
          WorkspaceVibeReference(
            id: 'manual-vibe',
            name: 'Manual Vibe',
            vibeB64: 'encoded-manual-vibe',
            referenceStrength: 0.55,
          ),
        ],
      );
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      viewModel.setArtistChain('artist-chain-1');
      await tester.pumpAndSettle();

      final sourceTags = find.byKey(const ValueKey('artist-source-tags-0'));
      final outputTags = find.byKey(const ValueKey('artist-output-tags-0'));
      expect(sourceTags, findsOneWidget);
      expect(outputTags, findsOneWidget);
      expect(viewModel.selectedManualVibes.map((vibe) => vibe.id), [
        'bound-vibe',
      ]);
      expect(
        find.descendant(
          of: sourceTags,
          matching: find.byKey(const ValueKey('artist-vibe-source-bound-vibe')),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: sourceTags,
          matching: find.byKey(
            const ValueKey('artist-vibe-source-manual-vibe'),
          ),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: outputTags,
          matching: find.byKey(const ValueKey('artist-vibe-active-bound-vibe')),
        ),
        findsOneWidget,
      );
      final boundRemove = find.byKey(
        const ValueKey('artist-vibe-remove-bound-vibe'),
      );
      expect(boundRemove, findsOneWidget);
      expect(tester.widget<IconButton>(boundRemove).tooltip, '绉婚櫎 Vibe');
      await tester.tap(boundRemove);
      await tester.pumpAndSettle();
      expect(viewModel.selectedManualVibes, isEmpty);
      expect(
        find.byKey(const ValueKey('artist-vibe-active-bound-vibe')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('artist-drop-target-0')),
          matching: find.textContaining('璺?'),
        ),
        findsNothing,
      );

      expect(find.text('Bound Vibe'), findsNothing);
      expect(find.text('Manual Vibe'), findsNothing);
    });

    testWidgets(
      'artist mapping shows only Vibes from script metadata as source',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([
            _singleFrameScript(
              baseCaption: 'official art',
              generationParams: const {
                'reference_image_multiple': ['encoded-source-vibe'],
                'reference_strength_multiple': [0.42],
                'reference_information_extracted_multiple': [0.84],
              },
            ),
          ]),
          loadVibes: () async => const [
            WorkspaceVibeReference(
              id: 'source-vibe',
              name: 'Source Vibe',
              vibeB64: 'encoded-source-vibe',
              referenceStrength: 0.33,
            ),
            WorkspaceVibeReference(
              id: 'global-only-vibe',
              name: 'Global Only Vibe',
              vibeB64: 'encoded-global-only-vibe',
            ),
          ],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath('script-with-source-vibe');
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final sourceTags = find.byKey(const ValueKey('artist-source-tags-0'));
        final outputTags = find.byKey(const ValueKey('artist-output-tags-0'));
        expect(
          find.descendant(
            of: sourceTags,
            matching: find.byKey(
              const ValueKey('artist-vibe-source-source-vibe'),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: sourceTags,
            matching: find.byKey(
              const ValueKey('artist-vibe-source-global-only-vibe'),
            ),
          ),
          findsNothing,
        );

        final sourceVibe = find.byKey(
          const ValueKey('artist-vibe-source-source-vibe'),
        );
        final dropZone = find.byKey(
          const ValueKey('artist-vibe-active-drop-zone-0'),
        );
        await tester.dragFrom(
          tester.getCenter(sourceVibe),
          tester.getCenter(dropZone) - tester.getCenter(sourceVibe),
        );
        await tester.pumpAndSettle();

        expect(viewModel.selectedManualVibes.single.id, 'source-vibe');
        expect(viewModel.selectedManualVibes.single.referenceStrength, 0.42);
        expect(viewModel.selectedManualVibes.single.infoExtracted, 0.84);
        expect(
          find.descendant(
            of: outputTags,
            matching: find.byKey(
              const ValueKey('artist-vibe-active-source-vibe'),
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('artist vibe slot imports a manual vibe from the row', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel(
        importVibes: () async => const [
          WorkspaceVibeReference(
            id: 'imported-vibe',
            name: 'Imported Vibe',
            vibeB64: 'encoded-imported-vibe',
            referenceStrength: 0.61,
          ),
        ],
      );
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      final addButton = find.byKey(const ValueKey('artist-vibe-add-0'));
      expect(addButton, findsOneWidget);
      await tester.ensureVisible(addButton);
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      expect(viewModel.selectedManualVibes.single.name, 'Imported Vibe');
      expect(
        find.byKey(const ValueKey('artist-vibe-active-imported-vibe')),
        findsOneWidget,
      );
      expect(find.text('Imported Vibe'), findsWidgets);
    });

    testWidgets(
      'selected source artist tags can be deleted from artist mapping',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const deletedTag = 'artist:ai_removed';
        const keptAiTag = 'artist:ai_kept';
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            ScriptAiRoleExtraction(
              status: ScriptAiRoleExtractionStatus.ready,
              confidence: 0.9,
              artistChains: [
                ScriptAiArtistChainEvidence(
                  terms: [deletedTag, keptAiTag],
                  confidence: 0.9,
                ),
              ],
            ),
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
          loadArtistChains: () async => const [
            ArtistChain(
              id: 'artist-chain-1',
              name: 'Replacement Chain',
              prompt: 'artist:replacement',
            ),
          ],
        );

        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
          await viewModel.generateAiRoleExtraction();
        });
        expect(
          viewModel.artistMappings.single.sourceLabel,
          contains('artist:terasu_mc'),
        );
        expect(
          viewModel.artistMappings.single.sourceLabel,
          contains(deletedTag),
        );
        expect(
          viewModel.artistMappings.single.sourceLabel,
          contains(keptAiTag),
        );

        viewModel.setArtistChain('artist-chain-1');
        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final sourceTags = find.byKey(const ValueKey('artist-source-tags-0'));
        final outputTags = find.byKey(const ValueKey('artist-output-tags-0'));
        expect(sourceTags, findsOneWidget);
        expect(outputTags, findsOneWidget);
        await tester.ensureVisible(sourceTags);
        await tester.tap(
          find
              .descendant(of: sourceTags, matching: find.text(deletedTag))
              .first,
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pumpAndSettle();

        expect(
          viewModel.artistMappings.single.sourceLabel,
          contains('artist:terasu_mc'),
        );
        expect(
          viewModel.artistMappings.single.sourceLabel,
          contains(keptAiTag),
        );
        expect(
          viewModel.artistMappings.single.sourceLabel,
          isNot(contains(deletedTag)),
        );
        expect(
          viewModel.artistMappings.single.selectedArtistChainId,
          'artist-chain-1',
        );
        expect(
          find.descendant(of: sourceTags, matching: find.text(deletedTag)),
          findsNothing,
        );
        expect(
          find.descendant(
            of: outputTags,
            matching: find.text('artist:replacement'),
          ),
          findsWidgets,
        );
      },
    );

    testWidgets(
      'undetected upper clothing row is grey but editable; role extraction does not omit target upper clothing on apply',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
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
                  stageId: 'slot-0-stage-1',
                  label: 'main outfit',
                  frameIndexes: [1],
                  identity: 'ai hero',
                  upperClothing: '',
                  lowerClothing: 'pleated skirt',
                  confidence: 0.9,
                  missingFields: ['missing_upper_clothing'],
                ),
              ],
            ),
          ],
        );
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            extraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
          await viewModel.generateAiRoleExtraction();
          await viewModel.applyHighConfidenceAiRoleExtraction();
        });
        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final field = find.byKey(
          const ValueKey(
            'role-output-part-slot-0-slot-0-stage-1-upperClothing',
          ),
        );
        expect(field, findsOneWidget);
        expect(
          find.ancestor(
            of: field,
            matching: find.byWidgetPredicate((widget) {
              final decoration =
                  widget is AnimatedContainer ? widget.decoration : null;
              return decoration is BoxDecoration &&
                  decoration.color == StudioTokens.surface1;
            }),
          ),
          findsWidgets,
        );
        expect(
          find.descendant(of: field, matching: find.textContaining('鏈媶鍒?')),
          findsNothing,
        );
        expect(
          find.descendant(of: field, matching: find.textContaining('榛樿涓嶄紶鍏?')),
          findsOneWidget,
        );

        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: field,
            matching: find.byKey(const ValueKey('prompt-tag-editor-add')),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: field,
            matching: find.byKey(const ValueKey('prompt-tag-editor-input')),
          ),
          'manual blouse',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        final stage = viewModel.roleMappings.first.selectedStage!;
        expect(stage.parts.upperClothing, 'manual blouse');
        expect(
          stage.omittedParts,
          isNot(contains(RecastPromptPart.upperClothing)),
        );
      },
    );

    testWidgets('applying role extraction collapses the draft panel', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel(
        scriptAiRoleExtractionService: const _FakeRoleExtractionService(
          _highConfidenceSlotExtraction,
        ),
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );

      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();
        await viewModel.applyHighConfidenceAiRoleExtraction();
      });
      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('script-ai-role-extraction-draft-panel')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('script-ai-progress-panel')),
        findsNothing,
      );
      expect(viewModel.roleMappings.first.sourceLabel, 'AI Hero');
      expect(viewModel.roleMappings.first.sourcePreview, 'AI Hero');
    });

    testWidgets(
      'script asset drawer character card can be dropped into replacement pending area',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 3600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final previewPath = '${Uri.base.toFilePath()}assets/appicon.png';
        late final RecastScriptCache cache;
        await tester.runAsync(() async {
          final parsedScript = await const ScriptRecastParserService()
              .parseDirectory(Directory(_fixturePath));
          cache = RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(
              parsedScript,
            ),
            updatedAt: DateTime.utc(2026, 6, 15),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              rolePromptReplacements: const [
                ScriptRolePromptReplacement(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourcePreview: 'ai hero',
                ),
              ],
            ),
          );
        });
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => [
            CharacterEntry(
              id: 'char-hero',
              name: 'library character',
              traits: const ViewVariantTexts(
                frontFull: 'library_hero, green eyes',
              ),
              anchorTags: const ['library_hero'],
              imageRefs: [previewPath],
              defaultOutfitId: 'outfit-hero-default',
              outfits: [
                WorkspaceOutfit(
                  id: 'outfit-hero-default',
                  name: 'default outfit',
                  tags: const ViewVariantTexts(
                    frontFull: 'white shirt, black skirt',
                    frontUpper: 'white shirt',
                    frontLower: 'black skirt',
                  ),
                  partTags: const WorkspaceOutfitPartTags(
                    upperBodyTags: ['silver hair'],
                    upperClothingTags: ['white shirt'],
                    lowerClothingTags: ['black skirt'],
                  ),
                  imageRefs: [previewPath],
                ),
              ],
            ),
          ],
          loadArtistChains: () async => [
            ArtistChain(
              id: 'artist-chain-1',
              name: 'test artist chain',
              imageRefs: [previewPath],
            ),
          ],
          loadRecastCaches: () async => [cache],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          find.byKey(const ValueKey('script-drawer-category-character')),
          findsOneWidget,
        );
        expect(
          find.ancestor(
            of: find.byKey(const ValueKey('script-drawer-category-character')),
            matching: find.byType(StudioInteractiveSurface),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('script-drawer-category-outfit')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('script-drawer-category-artist')),
          findsOneWidget,
        );
        final drawer = find.byKey(const ValueKey('script-layout-left-drawer'));
        expect(
          find.descendant(
            of: drawer,
            matching: find.byKey(
              const ValueKey('script-drawer-scrollbar-suppression'),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: drawer, matching: find.byType(RawScrollbar)),
          findsNothing,
        );

        await tester.tap(
          find.byKey(const ValueKey('script-drawer-category-character')),
        );
        await tester.pump(const Duration(milliseconds: 250));

        final characterPreview = find.byKey(
          const ValueKey('script-asset-preview-character-char-hero'),
        );
        expect(characterPreview, findsOneWidget);
        expect(
          find.descendant(of: characterPreview, matching: find.byType(Image)),
          findsOneWidget,
        );

        final characterCard = find.byKey(
          const ValueKey('script-asset-character-char-hero'),
        );
        expect(
          find.ancestor(
            of: characterCard,
            matching: find.byType(StudioInteractiveSurface),
          ),
          findsOneWidget,
        );
        await tester.tap(characterCard);
        await tester.pumpAndSettle();

        final identityDropTarget = find.byKey(
          const ValueKey('role-replacement-identity-drop-slot-0'),
        );
        expect(identityDropTarget, findsOneWidget);
        await tester.pump(const Duration(milliseconds: 300));

        Future<void> dragToPendingArea(Finder draggable) async {
          final dragStart = tester.getCenter(draggable);
          final dragEnd =
              tester.getTopLeft(identityDropTarget) + const Offset(120, 24);
          await tester.timedDragFrom(
            dragStart,
            dragEnd - dragStart,
            const Duration(milliseconds: 450),
          );
          await tester.pumpAndSettle();
        }

        final outfitCard = find.byKey(
          const ValueKey(
            'script-asset-character-char-hero-outfit-outfit-hero-default',
          ),
        );
        expect(outfitCard, findsOneWidget);
        expect(
          find.ancestor(
            of: outfitCard,
            matching: find.byType(StudioInteractiveSurface),
          ),
          findsOneWidget,
        );
        await tester.tap(outfitCard);
        await tester.pumpAndSettle();
        final upperBodyPart = find.byKey(
          const ValueKey(
            'script-asset-part-character-char-hero-outfit-outfit-hero-default-upper-body',
          ),
        );
        expect(upperBodyPart, findsOneWidget);
        final upperBodyDraggable = find
            .ancestor(
              of: upperBodyPart,
              matching: find.byWidgetPredicate((widget) => widget is Draggable),
            )
            .first;
        await dragToPendingArea(upperBodyDraggable);

        expect(
          viewModel.roleReplacementMappings.first.targetIdentityPrompt,
          contains('silver hair'),
        );

        final characterDraggable = find
            .ancestor(
              of: characterCard,
              matching: find.byWidgetPredicate((widget) => widget is Draggable),
            )
            .last;
        await dragToPendingArea(characterDraggable);

        expect(
          viewModel.roleReplacementMappings.first.targetCharacterId,
          'char-hero',
        );
        expect(
          viewModel.roleReplacementMappings.first.targetIdentityPrompt,
          contains('library_hero'),
        );
        expect(
          viewModel.roleReplacementMappings.first.targetIdentityPrompt,
          contains('white shirt'),
        );
        expect(
          viewModel.roleReplacementMappings.first.targetIdentityPrompt,
          contains('black skirt'),
        );
        expect(
          viewModel.roleReplacementMappings.first.targetIdentityPrompt,
          contains('silver hair'),
        );
      },
    );

    testWidgets(
      'role replacement pending tag drag appends to rule target',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 3600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late final RecastScriptCache cache;
        await tester.runAsync(() async {
          final parsedScript = await const ScriptRecastParserService()
              .parseDirectory(Directory(_fixturePath));
          cache = RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(
              parsedScript,
            ),
            updatedAt: DateTime.utc(2026, 6, 16),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              rolePromptReplacements: const [
                ScriptRolePromptReplacement(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourcePreview: 'source hero',
                  targetIdentityPrompt: 'red halo, 1.25:: blue dress ::',
                  rules: [
                    ScriptPromptReplacementRule(
                      id: 'rule-jacket',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-jacket',
                          text: 'source jacket',
                          category: PromptTagCategory.clothing,
                          frameIndexes: [1],
                        ),
                      ],
                      action: ScriptPromptReplacementAction.replace,
                      targetPrompt: 'red halo',
                    ),
                  ],
                ),
              ],
            ),
          );
        });
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => [cache],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final pendingArea = find.byKey(
          const ValueKey('role-replacement-identity-slot-0'),
        );
        expect(pendingArea, findsOneWidget);
        final pendingBlueDress = find.descendant(
          of: pendingArea,
          matching: find.byKey(
            const ValueKey('prompt-tag-editor-chip-1'),
          ),
        );
        expect(pendingBlueDress, findsOneWidget);
        final ruleTarget = find.byKey(
          const ValueKey(
              'replacement-rule-prompt-drop-role-slot-0-rule-jacket'),
        );
        expect(ruleTarget, findsOneWidget);
        final ruleInternalDrag = await tester.startGesture(
          tester.getCenter(ruleTarget),
        );
        await tester.pump();
        await ruleInternalDrag.moveBy(const Offset(120, 24));
        await tester.pump(const Duration(milliseconds: 120));
        expect(
          find.byKey(const ValueKey('replacement-rule-marquee-overlay')),
          findsNothing,
        );
        await ruleInternalDrag.up();
        await tester.pumpAndSettle();

        await _dragSelectedTagTo(tester, pendingBlueDress, ruleTarget);
        await tester.pumpAndSettle();

        final rule = viewModel.roleReplacementMappings.single.rules.single;
        expect(rule.targetPrompt, 'red halo, 1.25:: blue dress ::');
        expect(rule.action, ScriptPromptReplacementAction.replace);
        expect(
          viewModel.roleReplacementMappings.single.targetIdentityPrompt,
          'red halo',
        );
        final targetDisplay = find.byKey(
          const ValueKey('replacement-rule-target-role-slot-0-rule-jacket'),
        );
        expect(targetDisplay, findsOneWidget);
        final targetDisplayWidget =
            tester.widget<PromptTagDisplay>(targetDisplay);
        expect(
          targetDisplayWidget.sourceOrderCollapsedTagMaxWidth,
          144,
        );
        expect(
          targetDisplayWidget.sourceOrderHoveredTagMaxWidth,
          144,
        );
        expect(
          find.descendant(
            of: targetDisplay,
            matching: find.byWidgetPredicate((widget) {
              final key = widget.key;
              return key is ValueKey &&
                  key.value.toString().startsWith('prompt-tag-group-');
            }),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'role replacement target tag drag moves directly to another rule target',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 3600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late final RecastScriptCache cache;
        await tester.runAsync(() async {
          final parsedScript = await const ScriptRecastParserService()
              .parseDirectory(Directory(_fixturePath));
          cache = RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(
              parsedScript,
            ),
            updatedAt: DateTime.utc(2026, 6, 20),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              rolePromptReplacements: const [
                ScriptRolePromptReplacement(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourcePreview: 'source hero',
                  rules: [
                    ScriptPromptReplacementRule(
                      id: 'rule-headwear',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-headwear',
                          text: 'old headwear',
                          category: PromptTagCategory.upperClothing,
                          frameIndexes: [1],
                        ),
                      ],
                      action: ScriptPromptReplacementAction.replace,
                      targetPrompt: 'cat_ears, hair_ribbon',
                    ),
                    ScriptPromptReplacementRule(
                      id: 'rule-dress',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-dress',
                          text: 'old dress',
                          category: PromptTagCategory.upperClothing,
                          frameIndexes: [1],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        });
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => [cache],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final sourceTarget = find.byKey(
          const ValueKey(
            'replacement-rule-target-role-slot-0-rule-headwear',
          ),
        );
        final hairRibbonChip = find.descendant(
          of: sourceTarget,
          matching: find.byKey(
            const ValueKey('prompt-tag-chip-hair_ribbon-1-idle'),
          ),
        );
        final targetRule = find.byKey(
          const ValueKey('replacement-rule-prompt-drop-role-slot-0-rule-dress'),
        );
        expect(hairRibbonChip, findsOneWidget);
        expect(targetRule, findsOneWidget);

        await _dragSelectedTagTo(tester, hairRibbonChip, targetRule);
        await tester.pumpAndSettle();

        final rules = {
          for (final rule in viewModel.roleReplacementMappings.single.rules)
            rule.id: rule,
        };
        expect(rules['rule-headwear']!.targetPrompt, 'cat_ears');
        expect(rules['rule-dress']!.targetPrompt, 'hair_ribbon');
        expect(
          rules['rule-dress']!.action,
          ScriptPromptReplacementAction.replace,
        );
      },
    );

    testWidgets(
      'role replacement weight multiplier stores a block target weight',
      (tester) async {
        late final RecastScriptCache cache;
        await tester.runAsync(() async {
          final parsedScript = await const ScriptRecastParserService()
              .parseDirectory(Directory(_fixturePath));
          cache = RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(
              parsedScript,
            ),
            updatedAt: DateTime.utc(2026, 6, 16),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              rolePromptReplacements: const [
                ScriptRolePromptReplacement(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourcePreview: 'source hero',
                  rules: [
                    ScriptPromptReplacementRule(
                      id: 'rule-ears',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-fox-ears',
                          text: 'fox ears',
                          category: PromptTagCategory.upperBody,
                          frameIndexes: [1],
                        ),
                      ],
                      action: ScriptPromptReplacementAction.replace,
                      targetPrompt: '1.5:: cat ears ::, fox ears',
                    ),
                  ],
                ),
              ],
            ),
          );
        });
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => [cache],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        viewModel.scaleRoleReplacementRuleWeight(
          'slot-0',
          'rule-ears',
          1.2,
        );

        final rule = viewModel.roleReplacementMappings.single.rules.single;
        expect(rule.targetPrompt, '1.5:: cat ears ::, fox ears');
        expect(rule.targetWeightMultiplier, 1.2);
        expect(rule.action, ScriptPromptReplacementAction.replace);
      },
    );

    testWidgets(
      'role replacement weight multiplier replaces existing block target weight',
      (tester) async {
        late final RecastScriptCache cache;
        await tester.runAsync(() async {
          final parsedScript = await const ScriptRecastParserService()
              .parseDirectory(Directory(_fixturePath));
          cache = RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(
              parsedScript,
            ),
            updatedAt: DateTime.utc(2026, 6, 16),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              rolePromptReplacements: const [
                ScriptRolePromptReplacement(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourcePreview: 'source hero',
                  rules: [
                    ScriptPromptReplacementRule(
                      id: 'rule-ears',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-fox-ears',
                          text: 'fox ears',
                          category: PromptTagCategory.upperBody,
                          frameIndexes: [1],
                        ),
                      ],
                      action: ScriptPromptReplacementAction.replace,
                      targetPrompt: 'cat ears',
                      targetWeightMultiplier: 1.5,
                    ),
                  ],
                ),
              ],
            ),
          );
        });
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => [cache],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        viewModel.scaleRoleReplacementRuleWeight(
          'slot-0',
          'rule-ears',
          1.2,
        );

        final rule = viewModel.roleReplacementMappings.single.rules.single;
        expect(rule.targetPrompt, 'cat ears');
        expect(rule.targetWeightMultiplier, 1.2);
        expect(rule.action, ScriptPromptReplacementAction.replace);
      },
    );

    testWidgets(
      'role replacement weight multiplier keeps empty target as source weight',
      (tester) async {
        late final RecastScriptCache cache;
        await tester.runAsync(() async {
          final parsedScript = await const ScriptRecastParserService()
              .parseDirectory(Directory(_fixturePath));
          cache = RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(
              parsedScript,
            ),
            updatedAt: DateTime.utc(2026, 6, 16),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              rolePromptReplacements: const [
                ScriptRolePromptReplacement(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourcePreview: 'source hero',
                  rules: [
                    ScriptPromptReplacementRule(
                      id: 'rule-source-only',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-cat-ears',
                          text: '1.5:: cat ears ::',
                          category: PromptTagCategory.upperBody,
                          frameIndexes: [1],
                        ),
                        ScriptPromptReplacementTerm(
                          id: 'term-fox-ears',
                          text: 'fox ears',
                          category: PromptTagCategory.upperBody,
                          frameIndexes: [1],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        });
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => [cache],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        viewModel.scaleRoleReplacementRuleWeight(
          'slot-0',
          'rule-source-only',
          1.2,
        );

        final rule = viewModel.roleReplacementMappings.single.rules.single;
        expect(rule.targetPrompt, isEmpty);
        expect(rule.targetWeightMultiplier, 1.2);
        expect(rule.action, ScriptPromptReplacementAction.none);
        expect(rule.effectiveAction, ScriptPromptReplacementAction.replace);

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        expect(find.text('x1.20'), findsOneWidget);
        expect(
          find.byKey(
            const ValueKey(
              'replacement-rule-target-role-slot-0-rule-source-only',
            ),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'role replacement rule card opens weight multiplier dialog',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 3600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late final RecastScriptCache cache;
        await tester.runAsync(() async {
          final parsedScript = await const ScriptRecastParserService()
              .parseDirectory(Directory(_fixturePath));
          cache = RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(
              parsedScript,
            ),
            updatedAt: DateTime.utc(2026, 6, 16),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              rolePromptReplacements: const [
                ScriptRolePromptReplacement(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourcePreview: 'source hero',
                  rules: [
                    ScriptPromptReplacementRule(
                      id: 'rule-ears',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-fox-ears',
                          text: 'fox ears',
                          category: PromptTagCategory.upperBody,
                          frameIndexes: [1],
                        ),
                      ],
                      action: ScriptPromptReplacementAction.replace,
                      targetPrompt: '1.5:: cat ears ::, fox ears',
                    ),
                  ],
                ),
              ],
            ),
          );
        });
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => [cache],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final scaleButton = find.byKey(
          const ValueKey('replacement-rule-scale-weight-role-slot-0-rule-ears'),
        );
        expect(scaleButton, findsOneWidget);
        await tester.ensureVisible(scaleButton);
        await tester.tap(scaleButton);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(
              const ValueKey('replacement-rule-weight-multiplier-field')),
          '1.2',
        );
        await tester.tap(
          find.byKey(const ValueKey('replacement-rule-weight-multiplier-save')),
        );
        await tester.pumpAndSettle();

        final rule = viewModel.roleReplacementMappings.single.rules.single;
        expect(rule.targetPrompt, '1.5:: cat ears ::, fox ears');
        expect(rule.targetWeightMultiplier, 1.2);
        expect(find.text('x1.80'), findsNothing);
        expect(find.text('x1.20'), findsOneWidget);
      },
    );

    testWidgets(
      'role replacement targets stay horizontal and blank tap clears selection',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 3600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late final RecastScriptCache cache;
        await tester.runAsync(() async {
          final parsedScript = await const ScriptRecastParserService()
              .parseDirectory(Directory(_fixturePath));
          cache = RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(
              parsedScript,
            ),
            updatedAt: DateTime.utc(2026, 6, 16),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              rolePromptReplacements: const [
                ScriptRolePromptReplacement(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourcePreview: 'source hero',
                  rules: [
                    ScriptPromptReplacementRule(
                      id: 'rule-accessory',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-fox-ears',
                          text: 'fox ears',
                          category: PromptTagCategory.upperBody,
                          frameIndexes: [1],
                        ),
                        ScriptPromptReplacementTerm(
                          id: 'term-red-halo',
                          text: 'red halo',
                          category: PromptTagCategory.upperBody,
                          frameIndexes: [1],
                        ),
                      ],
                      action: ScriptPromptReplacementAction.replace,
                      targetPrompt: 'cat_ears, lotus_flower_hair_ornament',
                    ),
                  ],
                ),
              ],
            ),
          );
        });
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => [cache],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });
        viewModel.setRoleReplacementRuleSelected(
          'slot-0',
          'rule-accessory',
          true,
        );

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final targetDisplay = find.byKey(
          const ValueKey(
            'replacement-rule-target-role-slot-0-rule-accessory',
          ),
        );
        final targetDisplayWidget =
            tester.widget<PromptTagDisplay>(targetDisplay);
        expect(
          targetDisplayWidget.sourceOrderCollapsedTagMaxWidth,
          144,
        );
        expect(
          targetDisplayWidget.sourceOrderHoveredTagMaxWidth,
          144,
        );
        final sourceDisplay = find.byKey(
          const ValueKey(
            'replacement-rule-source-role-slot-0-rule-accessory',
          ),
        );
        final dragHandle = find.byKey(
          const ValueKey(
            'replacement-rule-drag-handle-role-slot-0-rule-accessory',
          ),
        );
        expect(sourceDisplay, findsOneWidget);
        expect(dragHandle, findsOneWidget);
        expect(
          tester.getCenter(dragHandle).dx,
          lessThan(tester.getTopLeft(sourceDisplay).dx),
        );
        final catEarsChip = find.descendant(
          of: targetDisplay,
          matching: find.byKey(
            const ValueKey('prompt-tag-chip-cat_ears-0-idle'),
          ),
        );
        final lotusChip = find.descendant(
          of: targetDisplay,
          matching: find.byKey(
            const ValueKey(
              'prompt-tag-chip-lotus_flower_hair_ornament-1-idle',
            ),
          ),
        );
        expect(catEarsChip, findsOneWidget);
        expect(lotusChip, findsOneWidget);
        expect(
          (tester.getTopLeft(catEarsChip).dy - tester.getTopLeft(lotusChip).dy)
              .abs(),
          lessThan(2),
        );
        expect(
          viewModel.roleReplacementMappings.single.rules.single.selected,
          isTrue,
        );

        final roleCard = find.byKey(
          const ValueKey('role-replacement-card-slot-0'),
        );
        final blankPoint =
            tester.getBottomLeft(roleCard) + const Offset(24, -8);
        await tester.tapAt(blankPoint);
        await tester.pumpAndSettle();

        expect(
          viewModel.roleReplacementMappings.single.rules.single.selected,
          isFalse,
        );
      },
    );

    testWidgets('role replacement cards can collapse and expand', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 3600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late final RecastScriptCache cache;
      await tester.runAsync(() async {
        final parsedScript = await const ScriptRecastParserService()
            .parseDirectory(Directory(_fixturePath));
        cache = RecastScriptCache(
          scriptId: parsedScript.id,
          scriptName: parsedScript.name,
          sourceRootPath: parsedScript.rootPath,
          sourceFingerprint: _normalizedSourceFingerprintForTest(
            parsedScript,
          ),
          updatedAt: DateTime.utc(2026, 6, 26),
          mapping: RecastMapping.defaults(parsedScript.id).copyWith(
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-0',
                displayLabel: 'AI Hero',
                sourcePreview: 'source hero preview',
                rules: [
                  ScriptPromptReplacementRule(
                    id: 'rule-ears',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'term-fox-ears',
                        text: 'fox ears',
                        category: PromptTagCategory.upperBody,
                        frameIndexes: [1],
                      ),
                    ],
                    action: ScriptPromptReplacementAction.replace,
                    targetPrompt: 'cat ears',
                  ),
                ],
              ),
            ],
          ),
        );
      });
      final viewModel = StudioScriptViewModel(
        loadRecastCaches: () async => [cache],
      );
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      final resetButton = find.byKey(
        const ValueKey('role-replacement-reset-slot-0'),
      );
      expect(resetButton, findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('role-replacement-collapsed-summary-slot-0'),
        ),
        findsNothing,
      );

      final collapseButton = find.byKey(
        const ValueKey('role-replacement-collapse-slot-0'),
      );
      expect(collapseButton, findsOneWidget);
      await tester.ensureVisible(collapseButton);
      await tester.tap(collapseButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(resetButton, findsNothing);
      expect(
        find.byKey(
          const ValueKey('role-replacement-collapsed-summary-slot-0'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('1 个'), findsWidgets);
      expect(find.textContaining('1 个已映射'), findsWidgets);

      final expandButton = find.byKey(
        const ValueKey('role-replacement-expand-slot-0'),
      );
      expect(expandButton, findsOneWidget);
      await tester.tap(expandButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(resetButton, findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('role-replacement-collapsed-summary-slot-0'),
        ),
        findsNothing,
      );
    });

    testWidgets(
      'role replacement target stays beside overflowing source terms',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 3600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late final RecastScriptCache cache;
        await tester.runAsync(() async {
          final parsedScript = await const ScriptRecastParserService()
              .parseDirectory(Directory(_fixturePath));
          cache = RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(
              parsedScript,
            ),
            updatedAt: DateTime.utc(2026, 6, 20),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              rolePromptReplacements: const [
                ScriptRolePromptReplacement(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourcePreview: 'source hero',
                  rules: [
                    ScriptPromptReplacementRule(
                      id: 'rule-overflow-hair',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-absurdly-long-hair',
                          text: 'absurdly long hair',
                          category: PromptTagCategory.upperBody,
                        ),
                        ScriptPromptReplacementTerm(
                          id: 'term-straight-hair',
                          text: 'straight hair',
                          category: PromptTagCategory.upperBody,
                        ),
                        ScriptPromptReplacementTerm(
                          id: 'term-very-long-hair',
                          text: 'very long hair',
                          category: PromptTagCategory.upperBody,
                        ),
                        ScriptPromptReplacementTerm(
                          id: 'term-white-hair',
                          text: 'white hair',
                          category: PromptTagCategory.upperBody,
                        ),
                      ],
                      action: ScriptPromptReplacementAction.replace,
                      targetPrompt: 'animal_ear_fluff, animal_ears, long_hair',
                    ),
                  ],
                ),
              ],
            ),
          );
        });
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => [cache],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });
        viewModel.setRoleReplacementRuleSelected(
          'slot-0',
          'rule-overflow-hair',
          true,
        );

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final sourceDisplay = find.byKey(
          const ValueKey(
            'replacement-rule-source-role-slot-0-rule-overflow-hair',
          ),
        );
        final targetDisplay = find.byKey(
          const ValueKey(
            'replacement-rule-target-role-slot-0-rule-overflow-hair',
          ),
        );
        expect(sourceDisplay, findsOneWidget);
        expect(targetDisplay, findsOneWidget);

        final sourceRect = tester.getRect(sourceDisplay);
        final targetRect = tester.getRect(targetDisplay);
        expect(targetRect.left, greaterThan(sourceRect.right + 8));
        expect(targetRect.top, lessThan(sourceRect.bottom));
        expect(targetRect.bottom, greaterThan(sourceRect.top));
      },
    );

    testWidgets(
      'role replacement source tag drag merges source terms',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 3600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late final RecastScriptCache cache;
        await tester.runAsync(() async {
          final parsedScript = await const ScriptRecastParserService()
              .parseDirectory(Directory(_fixturePath));
          cache = RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(
              parsedScript,
            ),
            updatedAt: DateTime.utc(2026, 6, 16),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              rolePromptReplacements: const [
                ScriptRolePromptReplacement(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourcePreview: 'source hero',
                  rules: [
                    ScriptPromptReplacementRule(
                      id: 'rule-wakamo',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-wakamo',
                          text: 'wakamo (blue_archive)',
                          category: PromptTagCategory.character,
                          frameIndexes: [1],
                        ),
                        ScriptPromptReplacementTerm(
                          id: 'term-hood',
                          text: '1.25:: hood ::',
                          category: PromptTagCategory.upperClothing,
                          frameIndexes: [2],
                        ),
                      ],
                    ),
                    ScriptPromptReplacementRule(
                      id: 'rule-pepe',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-pepe',
                          text: 'pepe (arknights)',
                          category: PromptTagCategory.character,
                          frameIndexes: [3],
                        ),
                      ],
                      action: ScriptPromptReplacementAction.replace,
                      targetPrompt: 'lace-up boots',
                    ),
                  ],
                ),
              ],
            ),
          );
        });
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => [cache],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final sourceDisplay = find.byKey(
          const ValueKey('replacement-rule-source-role-slot-0-rule-wakamo'),
        );
        expect(sourceDisplay, findsOneWidget);
        final sourceHoodChip = find.descendant(
          of: sourceDisplay,
          matching: find.byKey(
            const ValueKey('prompt-tag-chip-hood-1-idle'),
          ),
        );
        expect(sourceHoodChip, findsOneWidget);
        final targetRule = find.byKey(
          const ValueKey('replacement-rule-prompt-drop-role-slot-0-rule-pepe'),
        );
        expect(targetRule, findsOneWidget);

        await _dragSelectedTagTo(tester, sourceHoodChip, targetRule);
        await tester.pumpAndSettle();

        final rules = {
          for (final rule in viewModel.roleReplacementMappings.single.rules)
            rule.id: rule,
        };
        expect(
          rules['rule-wakamo']!.sourceTerms.map((term) => term.text),
          ['wakamo (blue_archive)'],
        );
        expect(
          rules['rule-pepe']!.sourceTerms.map((term) => term.text),
          ['pepe (arknights)', '1.25:: hood ::'],
        );
        expect(rules['rule-pepe']!.targetPrompt, 'lace-up boots');
        expect(
          rules['rule-pepe']!.action,
          ScriptPromptReplacementAction.replace,
        );
      },
    );

    testWidgets(
      'role replacement multi-selected source tags merge into an existing block',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 3600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late final RecastScriptCache cache;
        await tester.runAsync(() async {
          final parsedScript = await const ScriptRecastParserService()
              .parseDirectory(Directory(_fixturePath));
          cache = RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(
              parsedScript,
            ),
            updatedAt: DateTime.utc(2026, 6, 20),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              rolePromptReplacements: const [
                ScriptRolePromptReplacement(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourcePreview: 'source hero',
                  rules: [
                    ScriptPromptReplacementRule(
                      id: 'rule-hair-block',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-hair-flower',
                          text: 'hair flower',
                          category: PromptTagCategory.upperBody,
                        ),
                      ],
                      action: ScriptPromptReplacementAction.replace,
                      targetPrompt: 'animal_ear_fluff, long_hair',
                    ),
                    ScriptPromptReplacementRule(
                      id: 'rule-high-ponytail',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-high-ponytail',
                          text: 'high ponytail',
                          category: PromptTagCategory.upperBody,
                        ),
                      ],
                    ),
                    ScriptPromptReplacementRule(
                      id: 'rule-ponytail',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-ponytail',
                          text: 'ponytail',
                          category: PromptTagCategory.upperBody,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        });
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => [cache],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final highSource = find.byKey(
          const ValueKey(
            'replacement-rule-source-role-slot-0-rule-high-ponytail',
          ),
        );
        final ponySource = find.byKey(
          const ValueKey('replacement-rule-source-role-slot-0-rule-ponytail'),
        );
        final highChip = find.descendant(
          of: highSource,
          matching: find.byKey(
            const ValueKey('prompt-tag-chip-high ponytail-0-idle'),
          ),
        );
        final ponyChip = find.descendant(
          of: ponySource,
          matching: find.byKey(
            const ValueKey('prompt-tag-chip-ponytail-0-idle'),
          ),
        );
        expect(highChip, findsOneWidget);
        expect(ponyChip, findsOneWidget);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.tap(highChip);
        await tester.pump();
        await tester.tap(ponyChip);
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        final selectedHighChip = find.descendant(
          of: highSource,
          matching: find.byKey(
            const ValueKey('prompt-tag-chip-high ponytail-0-selected'),
          ),
        );
        final selectedPonyChip = find.descendant(
          of: ponySource,
          matching: find.byKey(
            const ValueKey('prompt-tag-chip-ponytail-0-selected'),
          ),
        );
        expect(selectedHighChip, findsOneWidget);
        expect(selectedPonyChip, findsOneWidget);

        final targetRuleSource = find.byKey(
          const ValueKey(
            'replacement-rule-source-role-slot-0-rule-hair-block',
          ),
        );
        expect(targetRuleSource, findsOneWidget);

        await _dragSelectedTagTo(tester, selectedHighChip, targetRuleSource);
        await tester.pumpAndSettle();

        final rules = {
          for (final rule in viewModel.roleReplacementMappings.single.rules)
            rule.id: rule,
        };
        expect(
          rules.keys,
          ['rule-hair-block'],
        );
        expect(
          rules['rule-hair-block']!.sourceTerms.map((term) => term.text),
          ['hair flower', 'high ponytail', 'ponytail'],
        );
        expect(
          rules['rule-hair-block']!.targetPrompt,
          'animal_ear_fluff, long_hair',
        );
      },
    );

    testWidgets(
      'role replacement card drag merges only the dragged source into target',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 3600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late final RecastScriptCache cache;
        await tester.runAsync(() async {
          final parsedScript = await const ScriptRecastParserService()
              .parseDirectory(Directory(_fixturePath));
          cache = RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(
              parsedScript,
            ),
            updatedAt: DateTime.utc(2026, 6, 17),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              rolePromptReplacements: const [
                ScriptRolePromptReplacement(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourcePreview: 'source hero',
                  rules: [
                    ScriptPromptReplacementRule(
                      id: 'rule-accessory',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-accessory',
                          text: 'cat ears',
                          category: PromptTagCategory.upperClothing,
                        ),
                      ],
                    ),
                    ScriptPromptReplacementRule(
                      id: 'rule-hood',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-hood',
                          text: 'hood',
                          category: PromptTagCategory.upperClothing,
                        ),
                      ],
                    ),
                    ScriptPromptReplacementRule(
                      id: 'rule-boots',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-boots',
                          text: 'lace-up boots',
                          category: PromptTagCategory.lowerClothing,
                        ),
                      ],
                      action: ScriptPromptReplacementAction.replace,
                      targetPrompt: 'black boots',
                    ),
                  ],
                ),
              ],
            ),
          );
        });
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => [cache],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });
        viewModel.setRoleReplacementRuleSelected(
          'slot-0',
          'rule-accessory',
          true,
        );

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final sourceHandle = find.byKey(
          const ValueKey(
            'replacement-rule-drag-handle-role-slot-0-rule-hood',
          ),
        );
        final targetRule = find.byKey(
          const ValueKey('replacement-rule-prompt-drop-role-slot-0-rule-boots'),
        );
        expect(sourceHandle, findsOneWidget);
        expect(targetRule, findsOneWidget);

        await _dragSelectedTagTo(tester, sourceHandle, targetRule);
        await tester.pumpAndSettle();

        final rules = {
          for (final rule in viewModel.roleReplacementMappings.single.rules)
            rule.id: rule,
        };
        expect(rules.keys, ['rule-accessory', 'rule-boots']);
        expect(
          rules['rule-accessory']!.sourceTerms.map((term) => term.text),
          ['cat ears'],
        );
        expect(
          rules['rule-boots']!.sourceTerms.map((term) => term.text),
          ['lace-up boots', 'hood'],
        );
        expect(rules['rule-boots']!.targetPrompt, 'black boots');
        expect(
          viewModel.roleReplacementMappings.single.rules
              .where((rule) => rule.selected)
              .map((rule) => rule.id),
          ['rule-boots'],
        );
      },
    );

    testWidgets(
      'role replacement source tag drag can split a merged term out',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 3600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late final RecastScriptCache cache;
        await tester.runAsync(() async {
          final parsedScript = await const ScriptRecastParserService()
              .parseDirectory(Directory(_fixturePath));
          cache = RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(
              parsedScript,
            ),
            updatedAt: DateTime.utc(2026, 6, 17),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              rolePromptReplacements: const [
                ScriptRolePromptReplacement(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourcePreview: 'source hero',
                  rules: [
                    ScriptPromptReplacementRule(
                      id: 'rule-accessories',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-white-bow',
                          text: 'white bow',
                          category: PromptTagCategory.upperClothing,
                        ),
                        ScriptPromptReplacementTerm(
                          id: 'term-red-hairband',
                          text: 'red hairband',
                          category: PromptTagCategory.upperClothing,
                        ),
                        ScriptPromptReplacementTerm(
                          id: 'term-red-collar',
                          text: 'red collar',
                          category: PromptTagCategory.upperClothing,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        });
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => [cache],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final sourceDisplay = find.byKey(
          const ValueKey(
            'replacement-rule-source-role-slot-0-rule-accessories',
          ),
        );
        final redCollarChip = find.descendant(
          of: sourceDisplay,
          matching: find.byKey(
            const ValueKey('prompt-tag-chip-red collar-2-idle'),
          ),
        );
        final splitTarget = find.byKey(
          const ValueKey('replacement-rule-split-drop-role-slot-0'),
        );
        expect(redCollarChip, findsOneWidget);
        expect(splitTarget, findsOneWidget);

        await _dragSelectedTagTo(tester, redCollarChip, splitTarget);
        await tester.pumpAndSettle();

        final rules = viewModel.roleReplacementMappings.single.rules;
        final original =
            rules.singleWhere((rule) => rule.id == 'rule-accessories');
        final split = rules.singleWhere(
          (rule) => rule.id != 'rule-accessories',
        );
        expect(
          original.sourceTerms.map((term) => term.text),
          ['white bow', 'red hairband'],
        );
        expect(split.sourceTerms.map((term) => term.text), ['red collar']);
        expect(
          rules.where((rule) => rule.selected).map((rule) => rule.id),
          [split.id],
        );
      },
    );

    testWidgets(
      'role replacement source tag drag out splits without explicit target',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 3600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late final RecastScriptCache cache;
        await tester.runAsync(() async {
          final parsedScript = await const ScriptRecastParserService()
              .parseDirectory(Directory(_fixturePath));
          cache = RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(
              parsedScript,
            ),
            updatedAt: DateTime.utc(2026, 6, 18),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              rolePromptReplacements: const [
                ScriptRolePromptReplacement(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourcePreview: 'source hero',
                  rules: [
                    ScriptPromptReplacementRule(
                      id: 'rule-identity',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-hikari',
                          text: 'hikari (blue archive)',
                          category: PromptTagCategory.character,
                        ),
                        ScriptPromptReplacementTerm(
                          id: 'term-girl',
                          text: 'girl',
                          category: PromptTagCategory.character,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        });
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => [cache],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final sourceDisplay = find.byKey(
          const ValueKey(
            'replacement-rule-source-role-slot-0-rule-identity',
          ),
        );
        final girlChip = find.descendant(
          of: sourceDisplay,
          matching: find.byKey(
            const ValueKey('prompt-tag-chip-girl-1-idle'),
          ),
        );
        expect(girlChip, findsOneWidget);

        final start = tester.getCenter(girlChip);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: start);
        await tester.pump();
        await mouse.down(start);
        await mouse.moveTo(start + const Offset(460, 0));
        await tester.pump();
        await mouse.up();
        await tester.pumpAndSettle();
        await mouse.removePointer();

        final rules = viewModel.roleReplacementMappings.single.rules;
        final original =
            rules.singleWhere((rule) => rule.id == 'rule-identity');
        final split = rules.singleWhere((rule) => rule.id != 'rule-identity');
        expect(
          original.sourceTerms.map((term) => term.text),
          ['hikari (blue archive)'],
        );
        expect(split.sourceTerms.map((term) => term.text), ['girl']);
        expect(
          rules.where((rule) => rule.selected).map((rule) => rule.id),
          [split.id],
        );
      },
    );

    testWidgets(
      'role replacement card drag shows a full-card feedback surface',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 3600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late final RecastScriptCache cache;
        await tester.runAsync(() async {
          final parsedScript = await const ScriptRecastParserService()
              .parseDirectory(Directory(_fixturePath));
          cache = RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(
              parsedScript,
            ),
            updatedAt: DateTime.utc(2026, 6, 17),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              rolePromptReplacements: const [
                ScriptRolePromptReplacement(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourcePreview: 'source hero',
                  rules: [
                    ScriptPromptReplacementRule(
                      id: 'rule-accessories',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-white-bow',
                          text: 'white bow',
                          category: PromptTagCategory.upperClothing,
                        ),
                        ScriptPromptReplacementTerm(
                          id: 'term-red-collar',
                          text: 'red collar',
                          category: PromptTagCategory.upperClothing,
                        ),
                      ],
                      action: ScriptPromptReplacementAction.replace,
                      targetPrompt: 'black collar',
                    ),
                  ],
                ),
              ],
            ),
          );
        });
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => [cache],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final sourceHandle = find.byKey(
          const ValueKey(
            'replacement-rule-drag-handle-role-slot-0-rule-accessories',
          ),
        );
        expect(sourceHandle, findsOneWidget);
        final start = tester.getCenter(sourceHandle);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: start);
        await tester.pump();
        await mouse.down(start);
        await mouse.moveBy(const Offset(120, 80));
        await tester.pump();

        final feedback = find.byKey(
          const ValueKey(
            'replacement-rule-card-feedback-role-slot-0-rule-accessories',
          ),
        );
        expect(feedback, findsOneWidget);
        expect(tester.getSize(feedback).width, greaterThan(220));

        await mouse.up();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'role replacement remove button removes a rule card',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 3600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late final RecastScriptCache cache;
        await tester.runAsync(() async {
          final parsedScript = await const ScriptRecastParserService()
              .parseDirectory(Directory(_fixturePath));
          cache = RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(
              parsedScript,
            ),
            updatedAt: DateTime.utc(2026, 6, 17),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              rolePromptReplacements: const [
                ScriptRolePromptReplacement(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourcePreview: 'source hero',
                  rules: [
                    ScriptPromptReplacementRule(
                      id: 'rule-hood',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-hood',
                          text: 'hood',
                          category: PromptTagCategory.upperClothing,
                        ),
                      ],
                    ),
                    ScriptPromptReplacementRule(
                      id: 'rule-boots',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-boots',
                          text: 'lace-up boots',
                          category: PromptTagCategory.lowerClothing,
                        ),
                      ],
                      action: ScriptPromptReplacementAction.replace,
                      targetPrompt: 'black boots',
                    ),
                  ],
                ),
              ],
            ),
          );
        });
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => [cache],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final removeButton = find.byKey(
          const ValueKey('replacement-rule-remove-role-slot-0-rule-hood'),
        );
        expect(removeButton, findsOneWidget);

        await tester.tap(removeButton);
        await tester.pumpAndSettle();

        final rules = {
          for (final rule in viewModel.roleReplacementMappings.single.rules)
            rule.id: rule,
        };
        expect(rules.keys, ['rule-boots']);
        expect(rules['rule-boots']!.targetPrompt, 'black boots');
      },
    );

    test(
      'role replacement source term merge persists across immediate reimport',
      () async {
        var caches = <RecastScriptCache>[];
        final parsedScript = await const ScriptRecastParserService()
            .parseDirectory(Directory(_fixturePath));
        caches = [
          RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(
              parsedScript,
            ),
            updatedAt: DateTime.utc(2026, 6, 16),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              rolePromptReplacements: const [
                ScriptRolePromptReplacement(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourcePreview: 'source hero',
                  rules: [
                    ScriptPromptReplacementRule(
                      id: 'rule-wakamo',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-wakamo',
                          text: 'wakamo (blue_archive)',
                          category: PromptTagCategory.character,
                          frameIndexes: [1],
                        ),
                        ScriptPromptReplacementTerm(
                          id: 'term-hood',
                          text: '1.25:: hood ::',
                          category: PromptTagCategory.upperClothing,
                          frameIndexes: [2],
                        ),
                      ],
                    ),
                    ScriptPromptReplacementRule(
                      id: 'rule-pepe',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-pepe',
                          text: 'pepe (arknights)',
                          category: PromptTagCategory.character,
                          frameIndexes: [3],
                        ),
                      ],
                      action: ScriptPromptReplacementAction.replace,
                      targetPrompt: 'lace-up boots',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ];
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );
        await viewModel.importScriptPath(_fixturePath);

        viewModel.mergeRoleReplacementSourceTerms(
          sourceRoleId: 'slot-0',
          sourceRuleId: 'rule-wakamo',
          targetRuleId: 'rule-pepe',
          tags: const ['1.25:: hood ::'],
        );
        await viewModel.importScriptPath(_fixturePath);

        final rules = {
          for (final rule in viewModel.roleReplacementMappings.single.rules)
            rule.id: rule,
        };
        expect(
          rules['rule-wakamo']!.sourceTerms.map((term) => term.text),
          ['wakamo (blue_archive)'],
        );
        expect(
          rules['rule-pepe']!.sourceTerms.map((term) => term.text),
          ['pepe (arknights)', '1.25:: hood ::'],
        );
        expect(rules['rule-pepe']!.targetPrompt, 'lace-up boots');
      },
    );

    test(
      'role replacement source term merge persists after immediate dispose',
      () async {
        var caches = <RecastScriptCache>[];
        final parsedScript = await const ScriptRecastParserService()
            .parseDirectory(Directory(_fixturePath));
        caches = [
          RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(
              parsedScript,
            ),
            updatedAt: DateTime.utc(2026, 6, 16),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              rolePromptReplacements: const [
                ScriptRolePromptReplacement(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  sourcePreview: 'source hero',
                  rules: [
                    ScriptPromptReplacementRule(
                      id: 'rule-wakamo',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-wakamo',
                          text: 'wakamo (blue_archive)',
                          category: PromptTagCategory.character,
                          frameIndexes: [1],
                        ),
                        ScriptPromptReplacementTerm(
                          id: 'term-hood',
                          text: '1.25:: hood ::',
                          category: PromptTagCategory.upperClothing,
                          frameIndexes: [2],
                        ),
                      ],
                    ),
                    ScriptPromptReplacementRule(
                      id: 'rule-pepe',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'term-pepe',
                          text: 'pepe (arknights)',
                          category: PromptTagCategory.character,
                          frameIndexes: [3],
                        ),
                      ],
                      action: ScriptPromptReplacementAction.replace,
                      targetPrompt: 'lace-up boots',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ];
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );
        await viewModel.importScriptPath(_fixturePath);

        viewModel.mergeRoleReplacementSourceTerms(
          sourceRoleId: 'slot-0',
          sourceRuleId: 'rule-wakamo',
          targetRuleId: 'rule-pepe',
          tags: const ['1.25:: hood ::'],
        );
        viewModel.dispose();
        await Future<void>.delayed(Duration.zero);

        final restored = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );
        await restored.importScriptPath(_fixturePath);

        final rules = {
          for (final rule in restored.roleReplacementMappings.single.rules)
            rule.id: rule,
        };
        expect(
          rules['rule-wakamo']!.sourceTerms.map((term) => term.text),
          ['wakamo (blue_archive)'],
        );
        expect(
          rules['rule-pepe']!.sourceTerms.map((term) => term.text),
          ['pepe (arknights)', '1.25:: hood ::'],
        );
        expect(rules['rule-pepe']!.targetPrompt, 'lace-up boots');
      },
    );

    test(
      'saved role replacement source term merge survives AI refresh on reopen',
      () async {
        late final RecastScriptCache cache;
        final parsedScript = await const ScriptRecastParserService()
            .parseDirectory(Directory(_fixturePath));
        cache = RecastScriptCache(
          scriptId: parsedScript.id,
          scriptName: parsedScript.name,
          sourceRootPath: parsedScript.rootPath,
          sourceFingerprint: _normalizedSourceFingerprintForTest(
            parsedScript,
          ),
          updatedAt: DateTime.utc(2026, 6, 17),
          mapping: RecastMapping.defaults(parsedScript.id).copyWith(
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-0',
                displayLabel: 'AI Hero',
                sourcePreview: 'source hero',
                rules: [
                  ScriptPromptReplacementRule(
                    id: 'role-slot-0-wakamo',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'wakamo',
                        text: 'wakamo (blue_archive)',
                        category: PromptTagCategory.character,
                        frameIndexes: [1],
                      ),
                    ],
                  ),
                  ScriptPromptReplacementRule(
                    id: 'role-slot-0-pepe',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'pepe',
                        text: 'pepe (arknights)',
                        category: PromptTagCategory.character,
                        frameIndexes: [3],
                      ),
                      ScriptPromptReplacementTerm(
                        id: 'hood',
                        text: '1.25:: hood ::',
                        category: PromptTagCategory.upperClothing,
                        frameIndexes: [2],
                      ),
                    ],
                    action: ScriptPromptReplacementAction.replace,
                    targetPrompt: 'lace-up boots',
                  ),
                ],
              ),
            ],
          ),
          aiRoleExtraction: const ScriptAiRoleExtraction(
            status: ScriptAiRoleExtractionStatus.ready,
            roles: [
              ScriptAiExtractedRole(
                sourceRoleId: 'slot-0',
                displayName: 'AI Hero',
                promptTerms: [
                  ScriptAiExtractedPromptTerm(
                    id: 'wakamo',
                    text: 'wakamo (blue_archive)',
                    category: PromptTagCategory.character,
                    frameIndexes: [1],
                  ),
                  ScriptAiExtractedPromptTerm(
                    id: 'pepe',
                    text: 'pepe (arknights)',
                    category: PromptTagCategory.character,
                    frameIndexes: [3],
                  ),
                  ScriptAiExtractedPromptTerm(
                    id: 'hood',
                    text: '1.25:: hood ::',
                    category: PromptTagCategory.upperClothing,
                    frameIndexes: [2],
                  ),
                ],
              ),
            ],
          ),
        );
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => [cache],
        );

        await viewModel.importScriptPath(_fixturePath);

        final rules = {
          for (final rule in viewModel.roleReplacementMappings.single.rules)
            rule.id: rule,
        };
        expect(rules.keys, ['role-slot-0-wakamo', 'role-slot-0-pepe']);
        expect(
          rules['role-slot-0-pepe']!.sourceTerms.map((term) => term.text),
          ['pepe (arknights)', '1.25:: hood ::'],
        );
        expect(rules['role-slot-0-pepe']!.targetPrompt, 'lace-up boots');
      },
    );

    test(
      'role replacement reset restores AI group defaults',
      () async {
        late final RecastScriptCache cache;
        final parsedScript = await const ScriptRecastParserService()
            .parseDirectory(Directory(_fixturePath));
        cache = RecastScriptCache(
          scriptId: parsedScript.id,
          scriptName: parsedScript.name,
          sourceRootPath: parsedScript.rootPath,
          sourceFingerprint: _normalizedSourceFingerprintForTest(
            parsedScript,
          ),
          updatedAt: DateTime.utc(2026, 6, 17),
          mapping: RecastMapping.defaults(parsedScript.id).copyWith(
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-0',
                displayLabel: 'AI Hero',
                sourcePreview: 'source hero',
                targetCharacterId: 'char-hero',
                targetIdentityPrompt: 'target identity',
                rules: [
                  ScriptPromptReplacementRule(
                    id: 'role-slot-0-pepe',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'pepe',
                        text: 'pepe (arknights)',
                        category: PromptTagCategory.character,
                        frameIndexes: [3],
                      ),
                      ScriptPromptReplacementTerm(
                        id: 'hood',
                        text: '1.25:: hood ::',
                        category: PromptTagCategory.upperClothing,
                        frameIndexes: [2],
                      ),
                    ],
                    excludedTermIds: ['hood'],
                    action: ScriptPromptReplacementAction.replace,
                    matchMode: ScriptPromptReplacementMatchMode.all,
                    targetPrompt: 'lace-up boots',
                  ),
                  ScriptPromptReplacementRule(
                    id: 'role-slot-0-wakamo',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'wakamo',
                        text: 'wakamo (blue_archive)',
                        category: PromptTagCategory.character,
                        frameIndexes: [1],
                      ),
                    ],
                    action: ScriptPromptReplacementAction.delete,
                  ),
                ],
              ),
            ],
          ),
          aiRoleExtraction: const ScriptAiRoleExtraction(
            status: ScriptAiRoleExtractionStatus.ready,
            roles: [
              ScriptAiExtractedRole(
                sourceRoleId: 'slot-0',
                displayName: 'AI Hero',
                promptTerms: [
                  ScriptAiExtractedPromptTerm(
                    id: 'wakamo',
                    text: 'wakamo (blue_archive)',
                    category: PromptTagCategory.character,
                    frameIndexes: [1],
                  ),
                  ScriptAiExtractedPromptTerm(
                    id: 'pepe',
                    text: 'pepe (arknights)',
                    category: PromptTagCategory.character,
                    frameIndexes: [3],
                  ),
                  ScriptAiExtractedPromptTerm(
                    id: 'hood',
                    text: '1.25:: hood ::',
                    category: PromptTagCategory.upperClothing,
                    frameIndexes: [2],
                  ),
                ],
              ),
            ],
          ),
        );
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => [cache],
        );

        await viewModel.importScriptPath(_fixturePath);
        viewModel.resetRoleReplacementGroup('slot-0');

        final replacement = viewModel.roleReplacementMappings.single;
        expect(replacement.targetCharacterId, isNull);
        expect(replacement.targetIdentityPrompt, isEmpty);
        final rules = {for (final rule in replacement.rules) rule.id: rule};
        expect(
          rules.keys,
          ['role-slot-0-wakamo', 'role-slot-0-pepe', 'role-slot-0-hood'],
        );
        for (final rule in rules.values) {
          expect(rule.sourceTerms, hasLength(1));
          expect(rule.excludedTermIds, isEmpty);
          expect(rule.action, ScriptPromptReplacementAction.none);
          expect(rule.matchMode, ScriptPromptReplacementMatchMode.any);
          expect(rule.targetPrompt, isEmpty);
        }
      },
    );

    test(
      'scene replacement reset restores AI group defaults',
      () async {
        late final RecastScriptCache cache;
        final parsedScript = await const ScriptRecastParserService()
            .parseDirectory(Directory(_fixturePath));
        cache = RecastScriptCache(
          scriptId: parsedScript.id,
          scriptName: parsedScript.name,
          sourceRootPath: parsedScript.rootPath,
          sourceFingerprint: _normalizedSourceFingerprintForTest(
            parsedScript,
          ),
          updatedAt: DateTime.utc(2026, 6, 17),
          mapping: RecastMapping.defaults(parsedScript.id).copyWith(
            scenePromptReplacements: const [
              ScriptScenePromptReplacement(
                id: 'scene-ai',
                label: 'Scene',
                rules: [
                  ScriptPromptReplacementRule(
                    id: 'scene-night',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'night',
                        text: 'night',
                        category: PromptTagCategory.scene,
                        frameIndexes: [1],
                      ),
                      ScriptPromptReplacementTerm(
                        id: 'rain',
                        text: 'rain',
                        category: PromptTagCategory.scene,
                        frameIndexes: [2],
                      ),
                    ],
                    excludedTermIds: ['rain'],
                    action: ScriptPromptReplacementAction.replace,
                    targetPrompt: 'sunny day',
                  ),
                  ScriptPromptReplacementRule(
                    id: 'scene-extra',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'extra',
                        text: 'manual scene',
                        category: PromptTagCategory.scene,
                      ),
                    ],
                    action: ScriptPromptReplacementAction.delete,
                  ),
                ],
              ),
            ],
          ),
          aiRoleExtraction: const ScriptAiRoleExtraction(
            status: ScriptAiRoleExtractionStatus.ready,
            sceneTerms: [
              ScriptAiExtractedPromptTerm(
                id: 'night',
                text: 'night',
                category: PromptTagCategory.scene,
                frameIndexes: [1],
              ),
              ScriptAiExtractedPromptTerm(
                id: 'rain',
                text: 'rain',
                category: PromptTagCategory.scene,
                frameIndexes: [2],
              ),
            ],
          ),
        );
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => [cache],
        );

        await viewModel.importScriptPath(_fixturePath);
        viewModel.resetSceneReplacementGroup('scene-ai');

        final rules = {
          for (final rule in viewModel.sceneReplacementMappings.single.rules)
            rule.id: rule,
        };
        expect(rules.keys, ['scene-night', 'scene-rain']);
        for (final rule in rules.values) {
          expect(rule.sourceTerms, hasLength(1));
          expect(rule.excludedTermIds, isEmpty);
          expect(rule.action, ScriptPromptReplacementAction.none);
          expect(rule.matchMode, ScriptPromptReplacementMatchMode.any);
          expect(rule.targetPrompt, isEmpty);
        }
      },
    );

    testWidgets(
      'role replacement reset button restores group defaults',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late final RecastScriptCache cache;
        await tester.runAsync(() async {
          final parsedScript = await const ScriptRecastParserService()
              .parseDirectory(Directory(_fixturePath));
          cache = RecastScriptCache(
            scriptId: parsedScript.id,
            scriptName: parsedScript.name,
            sourceRootPath: parsedScript.rootPath,
            sourceFingerprint: _normalizedSourceFingerprintForTest(
              parsedScript,
            ),
            updatedAt: DateTime.utc(2026, 6, 17),
            mapping: RecastMapping.defaults(parsedScript.id).copyWith(
              rolePromptReplacements: const [
                ScriptRolePromptReplacement(
                  sourceRoleId: 'slot-0',
                  displayLabel: 'AI Hero',
                  targetIdentityPrompt: 'target identity',
                  rules: [
                    ScriptPromptReplacementRule(
                      id: 'role-slot-0-pepe',
                      sourceTerms: [
                        ScriptPromptReplacementTerm(
                          id: 'pepe',
                          text: 'pepe (arknights)',
                          category: PromptTagCategory.character,
                        ),
                      ],
                      action: ScriptPromptReplacementAction.replace,
                      targetPrompt: 'lace-up boots',
                    ),
                  ],
                ),
              ],
            ),
            aiRoleExtraction: const ScriptAiRoleExtraction(
              status: ScriptAiRoleExtractionStatus.ready,
              roles: [
                ScriptAiExtractedRole(
                  sourceRoleId: 'slot-0',
                  displayName: 'AI Hero',
                  promptTerms: [
                    ScriptAiExtractedPromptTerm(
                      id: 'pepe',
                      text: 'pepe (arknights)',
                      category: PromptTagCategory.character,
                    ),
                  ],
                ),
              ],
            ),
          );
        });
        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => [cache],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();
        expect(
          find.ancestor(
            of: find.byKey(const ValueKey('script-recast-plan-panel')),
            matching: find.byType(StudioStaggeredReveal),
          ),
          findsOneWidget,
        );
        expect(
          find.ancestor(
            of: find.byKey(const ValueKey('role-replacement-card-slot-0')),
            matching: find.byType(StudioStaggeredReveal),
          ),
          findsWidgets,
        );
        final resetButton = find.byKey(
          const ValueKey('role-replacement-reset-slot-0'),
        );
        expect(resetButton, findsOneWidget);

        await tester.ensureVisible(resetButton);
        await tester.tap(resetButton);
        await tester.pumpAndSettle();

        final replacement = viewModel.roleReplacementMappings.single;
        expect(replacement.targetIdentityPrompt, isEmpty);
        expect(replacement.rules.single.targetPrompt, isEmpty);
        expect(
          replacement.rules.single.action,
          ScriptPromptReplacementAction.none,
        );
      },
    );

    testWidgets('script asset drawer favorites pin category assets', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final favoriteKeys = <String>{'artist:artist-chain-2'};
      final viewModel = StudioScriptViewModel(
        loadCharacters: () async => const [],
        loadArtistChains: () async => const [
          ArtistChain(
            id: 'artist-chain-1',
            name: 'first artist chain',
            prompt: 'artist:first',
          ),
          ArtistChain(
            id: 'artist-chain-2',
            name: 'second artist chain',
            prompt: 'artist:second',
          ),
        ],
      );
      await tester.runAsync(() async {
        await viewModel.ensureAssetsLoaded();
      });

      await tester.pumpWidget(
        buildScriptPage(
          viewModel: viewModel,
          loadAssetFavoriteKeys: () async => {...favoriteKeys},
          setAssetFavorite: (key, isFavorite) async {
            if (isFavorite) {
              favoriteKeys.add(key);
            } else {
              favoriteKeys.remove(key);
            }
          },
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('script-drawer-category-artist')),
      );
      await tester.pumpAndSettle();

      final firstCard = find.byKey(
        const ValueKey('script-asset-artist-artist-chain-1'),
      );
      final secondCard = find.byKey(
        const ValueKey('script-asset-artist-artist-chain-2'),
      );
      expect(
        tester.getTopLeft(secondCard).dy,
        lessThan(tester.getTopLeft(firstCard).dy),
      );

      await tester.tap(
        find.byKey(
          const ValueKey('script-asset-favorite-artist-artist-chain-1'),
        ),
      );
      await tester.pumpAndSettle();

      expect(favoriteKeys, contains('artist:artist-chain-1'));
      expect(
        tester.getTopLeft(firstCard).dy,
        lessThan(tester.getTopLeft(secondCard).dy),
      );
    });

    testWidgets(
      'script asset drawer detail rows use visible shared hover feedback',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final viewModel = StudioScriptViewModel(
          loadArtistChains: () async => const [
            ArtistChain(id: 'artist-chain-1', name: 'test artist chain'),
          ],
        );
        await tester.runAsync(() async {
          await viewModel.ensureAssetsLoaded();
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pump();
        await tester.pump();

        await tester.tap(
          find.byKey(const ValueKey('script-drawer-category-artist')),
        );
        await tester.pumpAndSettle();

        final artistCard = find.byKey(
          const ValueKey('script-asset-artist-artist-chain-1'),
        );
        expect(artistCard, findsOneWidget);

        final surfaceFinder = find
            .ancestor(
              of: artistCard,
              matching: find.byType(StudioInteractiveSurface),
            )
            .first;
        final surface = tester.widget<StudioInteractiveSurface>(surfaceFinder);
        expect(surface.hoverOverlayColor, isNotNull);
        expect(surface.hoverBorderColor, isNotNull);

        final mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: tester.getCenter(artistCard));
        await tester.pump(StudioMotionTokens.fast);

        final hoverChrome = tester.widget<AnimatedContainer>(
          find.descendant(
            of: surfaceFinder,
            matching: find.byType(AnimatedContainer),
          ),
        );
        final decoration = hoverChrome.decoration! as BoxDecoration;
        final border = decoration.border! as Border;
        expect(border.top.color, surface.hoverBorderColor);
      },
    );

    testWidgets(
      'script asset drawer avoids stacked push motion and uses shelf motion',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final previewPath = '${Uri.base.toFilePath()}assets/appicon.png';
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => [
            CharacterEntry(
              id: 'char-hero',
              name: 'library character',
              traits: const ViewVariantTexts(frontFull: 'green eyes'),
              imageRefs: [previewPath],
              defaultOutfitId: 'outfit-hero-default',
              outfits: [
                WorkspaceOutfit(
                  id: 'outfit-hero-default',
                  name: 'default outfit',
                  tags: const ViewVariantTexts(frontFull: 'white shirt'),
                  partTags: const WorkspaceOutfitPartTags(
                    upperClothingTags: ['white shirt'],
                  ),
                  imageRefs: [previewPath],
                ),
              ],
            ),
          ],
        );
        await tester.runAsync(() async {
          await viewModel.ensureAssetsLoaded();
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pump();
        await tester.pump();

        final categoryCard = find.byKey(
          const ValueKey('script-drawer-category-character'),
        );
        expect(categoryCard, findsOneWidget);
        expect(
          find.ancestor(
            of: categoryCard,
            matching: find.byType(StudioDrawerPushTransition),
          ),
          findsNothing,
        );
        expect(
          find.ancestor(
            of: categoryCard,
            matching: find.byType(StudioStaggeredReveal),
          ),
          findsOneWidget,
        );

        await tester.tap(categoryCard);
        await tester.pumpAndSettle();

        final characterCard = find.byKey(
          const ValueKey('script-asset-character-char-hero'),
        );
        expect(characterCard, findsOneWidget);
        expect(
          find.ancestor(
            of: characterCard,
            matching: find.byType(StudioDrawerPushTransition),
          ),
          findsNothing,
        );
        expect(
          find.ancestor(
            of: characterCard,
            matching: find.byType(StudioStaggeredReveal),
          ),
          findsOneWidget,
        );

        await tester.tap(characterCard);
        await tester.pumpAndSettle();

        final outfitCard = find.byKey(
          const ValueKey(
            'script-asset-character-char-hero-outfit-outfit-hero-default',
          ),
        );
        expect(outfitCard, findsOneWidget);
        expect(tester.getSize(outfitCard).height, lessThan(66));
        expect(
          find.ancestor(
            of: outfitCard,
            matching: find.byType(StudioDrawerShelf),
          ),
          findsOneWidget,
        );

        await tester.ensureVisible(outfitCard);
        await tester.pumpAndSettle();
        await tester.tap(outfitCard);
        await tester.pumpAndSettle();

        final outfitPart = find.byKey(
          const ValueKey(
            'script-asset-part-character-char-hero-outfit-outfit-hero-default-upper-clothing',
          ),
        );
        expect(outfitPart, findsOneWidget);
        expect(
          find.ancestor(
            of: outfitPart,
            matching: find.byType(StudioDrawerShelf),
          ),
          findsWidgets,
        );
        expect(
          tester
              .widgetList<StudioDrawerShelf>(
                find.ancestor(
                  of: outfitPart,
                  matching: find.byType(StudioDrawerShelf),
                ),
              )
              .map((shelf) => shelf.railOpacity),
          everyElement(0),
        );
      },
    );

    testWidgets(
      'script asset drawer back restores categories without replaying reveal',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => const [
            CharacterEntry(
              id: 'char-hero',
              name: 'library character',
              traits: ViewVariantTexts(frontFull: 'green eyes'),
            ),
          ],
        );
        await tester.runAsync(() async {
          await viewModel.ensureAssetsLoaded();
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pump();
        await tester.pump();

        final categoryCard = find.byKey(
          const ValueKey('script-drawer-category-character'),
        );
        expect(categoryCard, findsOneWidget);

        await tester.tap(categoryCard);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('script-asset-character-char-hero')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('script-drawer-back')));
        await tester.pump();

        expect(categoryCard, findsOneWidget);
        final categoryFades = tester
            .widgetList<FadeTransition>(
              find.ancestor(
                of: categoryCard,
                matching: find.byType(FadeTransition),
              ),
            )
            .map((transition) => transition.opacity.value)
            .toList(growable: false);
        expect(categoryFades, isNotEmpty);
        expect(categoryFades, everyElement(moreOrLessEquals(1)));
      },
    );

    testWidgets(
      'script drawer nested outfit hover stays inside drawer bounds',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final previewPath = '${Uri.base.toFilePath()}assets/appicon.png';
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => [
            CharacterEntry(
              id: 'char-hero',
              name: 'library character',
              traits: const ViewVariantTexts(
                frontFull:
                    'long character prompt, silver hair, fox ears, blue eyes',
              ),
              imageRefs: [previewPath],
              defaultOutfitId: 'outfit-hero-default',
              outfits: [
                WorkspaceOutfit(
                  id: 'outfit-hero-default',
                  name: 'default outfit',
                  tags: const ViewVariantTexts(
                    frontFull:
                        'dress, sleeveless, long skirt, ribbon, layered cloth',
                  ),
                  partTags: const WorkspaceOutfitPartTags(
                    upperClothingTags: ['dress', 'sleeveless', 'ribbon'],
                  ),
                  imageRefs: [previewPath],
                ),
              ],
            ),
          ],
        );
        await tester.runAsync(() async {
          await viewModel.ensureAssetsLoaded();
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('script-drawer-category-character')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('script-asset-character-char-hero')),
        );
        await tester.pumpAndSettle();

        final outfitCard = find.byKey(
          const ValueKey(
            'script-asset-character-char-hero-outfit-outfit-hero-default',
          ),
        );
        expect(outfitCard, findsOneWidget);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: tester.getCenter(outfitCard));
        await tester.pump(const Duration(milliseconds: 260));

        final shelf = tester.widget<StudioDrawerShelf>(
          find.ancestor(
            of: outfitCard,
            matching: find.byType(StudioDrawerShelf),
          ),
        );
        expect(shelf.margin.resolve(TextDirection.ltr).right, greaterThan(0));

        await mouse.removePointer();
      },
    );

    testWidgets('script optional workflow panels use animated presence', (
      tester,
    ) async {
      final viewModel = StudioScriptViewModel();

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      final aiPresence = find.byKey(
        const ValueKey('script-ai-progress-presence'),
      );
      expect(aiPresence, findsOneWidget);
      expect(
        tester.widget<StudioAnimatedPresence>(aiPresence).visible,
        isFalse,
      );

      final cachePresence = find.byKey(
        const ValueKey('script-changed-source-cache-presence'),
      );
      expect(cachePresence, findsOneWidget);
      expect(
        tester.widget<StudioAnimatedPresence>(cachePresence).visible,
        isFalse,
      );
    });

    testWidgets(
      'script drawer character rows expand into explicit outfit cards only',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final previewPath = '${Uri.base.toFilePath()}assets/appicon.png';
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => [
            CharacterEntry(
              id: 'char-hero',
              name: 'library character',
              traits: const ViewVariantTexts(
                frontFull: 'green eyes, fox tail',
                frontUpper: 'white shirt',
                frontLower: 'black skirt',
              ),
              imageRefs: [previewPath],
              defaultOutfitId: 'outfit-hero-default',
              outfits: [
                WorkspaceOutfit(
                  id: 'outfit-hero-default',
                  name: 'default outfit',
                  tags: const ViewVariantTexts(
                    frontFull: 'white shirt, black skirt',
                    frontUpper: 'white shirt',
                    frontLower: 'black skirt',
                  ),
                  partTags: const WorkspaceOutfitPartTags(
                    upperClothingTags: ['white shirt'],
                    lowerClothingTags: ['black skirt'],
                  ),
                  imageRefs: [previewPath],
                ),
              ],
            ),
          ],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('script-drawer-category-character')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(
            const ValueKey('script-asset-character-char-hero-outfit-original'),
          ),
          findsNothing,
        );

        await tester.tap(
          find.byKey(const ValueKey('script-asset-character-char-hero')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(
            const ValueKey('script-asset-character-char-hero-outfit-original'),
          ),
          findsNothing,
        );
        expect(
          find.byKey(
            const ValueKey(
              'script-asset-character-char-hero-outfit-outfit-hero-default',
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('script drawer does not duplicate explicit default outfit', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previewPath = '${Uri.base.toFilePath()}assets/appicon.png';
      final viewModel = StudioScriptViewModel(
        loadCharacters: () async => [
          CharacterEntry(
            id: 'char-pepe',
            name: '浣╀僵',
            traits: const ViewVariantTexts(
              frontFull: 'pepe_(arknights), cat ears, cat tail',
              frontUpper: 'cat ears',
              frontLower: 'cat tail',
            ),
            imageRefs: [previewPath],
            defaultOutfitId: 'default-outfit',
            outfits: [
              WorkspaceOutfit(
                id: 'default-outfit',
                name: '榛樿鏈嶈',
                tags: const ViewVariantTexts(
                  frontFull: 'black jacket, black shorts',
                  frontUpper: 'black jacket',
                  frontLower: 'black shorts',
                ),
                partTags: const WorkspaceOutfitPartTags(
                  upperClothingTags: ['black jacket'],
                  lowerClothingTags: ['black shorts'],
                ),
                imageRefs: [previewPath],
              ),
              WorkspaceOutfit(
                id: 'legacy-character-sheet-r14-outfit-4',
                name: '鍙樹綋 1',
                tags: const ViewVariantTexts(
                  frontFull: 'ancient egyptian clothes, white dress',
                  frontUpper: 'ancient egyptian clothes, white dress',
                  frontLower: 'purple skirt',
                ),
                partTags: const WorkspaceOutfitPartTags(
                  upperClothingTags: [
                    'ancient egyptian clothes',
                    'white dress',
                  ],
                  lowerClothingTags: ['purple skirt'],
                ),
                imageRefs: [previewPath],
              ),
            ],
          ),
        ],
      );
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('script-drawer-category-character')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('script-asset-character-char-pepe')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('script-asset-character-char-pepe-outfit-original'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey(
            'script-asset-character-char-pepe-outfit-default-outfit',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey(
            'script-asset-character-char-pepe-outfit-legacy-character-sheet-r14-outfit-4',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('榛樿鏈嶈'), findsOneWidget);
      expect(find.text('鍙樹綋 1'), findsOneWidget);
    });

    testWidgets(
      'nested script drawer outfit cards can be dropped into role targets',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final tempDir = Directory.systemTemp.createTempSync(
          'script-drawer-preview-wheel-',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final source = File('${Uri.base.toFilePath()}assets/appicon.png');
        final first = File('${tempDir.path}${Platform.pathSeparator}first.png')
          ..writeAsBytesSync(source.readAsBytesSync());
        final second = File(
          '${tempDir.path}${Platform.pathSeparator}second.png',
        )..writeAsBytesSync(source.readAsBytesSync());
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => [
            CharacterEntry(
              id: 'char-hero',
              name: 'library character',
              traits: const ViewVariantTexts(frontFull: 'green eyes'),
              imageRefs: [first.path, second.path],
              defaultOutfitId: 'outfit-hero-default',
              outfits: [
                WorkspaceOutfit(
                  id: 'outfit-hero-default',
                  name: 'default outfit',
                  tags: const ViewVariantTexts(frontFull: 'white shirt'),
                  partTags: const WorkspaceOutfitPartTags(
                    upperClothingTags: ['white shirt'],
                  ),
                  imageRefs: [first.path, second.path],
                ),
              ],
            ),
          ],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('script-drawer-category-character')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('script-asset-character-char-hero')),
        );
        await tester.pumpAndSettle();

        final outfitCard = find.byKey(
          const ValueKey(
            'script-asset-character-char-hero-outfit-outfit-hero-default',
          ),
        );
        await tester.tap(outfitCard);
        await tester.pumpAndSettle();

        final outfitDraggable = find
            .ancestor(
              of: outfitCard,
              matching: find.byWidgetPredicate((widget) => widget is Draggable),
            )
            .last;
        final outfitDragStart = tester.getCenter(outfitDraggable);
        final outfitDropRect = tester.getRect(
          find.byKey(const ValueKey('role-drop-target-slot-0')),
        );
        await tester.timedDragFrom(
          outfitDragStart,
          outfitDropRect.center - outfitDragStart,
          const Duration(milliseconds: 400),
        );
        await tester.pumpAndSettle();

        expect(viewModel.roleMappings.first.selectedCharacterId, 'char-hero');
        expect(
          viewModel.roleMappings.first.selectedOutfitId,
          'outfit-hero-default',
        );
      },
    );

    testWidgets(
      'script drawer outfit parts can be dropped into matching replacement output cells',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final previewPath = '${Uri.base.toFilePath()}assets/appicon.png';
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => [
            CharacterEntry(
              id: 'char-hero',
              name: 'library character',
              traits: const ViewVariantTexts(frontFull: 'green eyes'),
              imageRefs: [previewPath],
              defaultOutfitId: 'outfit-hero-default',
              outfits: [
                WorkspaceOutfit(
                  id: 'outfit-hero-default',
                  name: 'default outfit',
                  tags: const ViewVariantTexts(frontFull: 'full outfit'),
                  partTags: const WorkspaceOutfitPartTags(
                    upperClothingTags: ['armored jacket'],
                    lowerClothingTags: ['pleated skirt'],
                  ),
                  imageRefs: [previewPath],
                ),
              ],
            ),
          ],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });
        final role = viewModel.roleMappings.first;
        final stageId = role.selectedStage!.id;

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('script-drawer-category-character')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('script-asset-character-char-hero')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey(
              'script-asset-character-char-hero-outfit-outfit-hero-default',
            ),
          ),
        );
        await tester.pumpAndSettle();

        final partCard = find.byKey(
          const ValueKey(
            'script-asset-part-character-char-hero-outfit-outfit-hero-default-upper-clothing',
          ),
        );
        final dropTarget = find.byKey(
          ValueKey(
            'role-output-part-drop-${role.sourceRoleId}-$stageId-upperClothing',
          ),
        );
        final partDraggable = find
            .ancestor(
              of: partCard,
              matching: find.byWidgetPredicate((widget) => widget is Draggable),
            )
            .last;
        expect(partCard, findsOneWidget);
        expect(partDraggable, findsOneWidget);
        expect(dropTarget, findsOneWidget);
        expect(find.text('armored jacket'), findsWidgets);
        final dropRect = tester.getRect(dropTarget);

        final dragStart = tester.getCenter(partDraggable);
        await tester.dragFrom(dragStart, dropRect.center - dragStart);
        await tester.pumpAndSettle();

        expect(viewModel.roleMappings.first.selectedCharacterId, isNull);
        expect(
          viewModel.roleMappings.first.selectedStage!.parts.upperClothing,
          'armored jacket',
        );
        expect(find.text('armored jacket'), findsWidgets);
      },
    );

    testWidgets(
      'role copy target outfit chip defines hover styling before dragging',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final script = _scriptWithFrames(
          [
            (
              index: 1,
              base: 'artist:test',
              chars: ['hero, school jacket, shared skirt'],
            ),
            (
              index: 2,
              base: 'artist:test',
              chars: ['hero, swim top, swim shorts'],
            ),
          ],
          id: 'role-copy-hover-script',
          name: 'Role Copy Hover Script',
          rootPath: 'role-copy-hover-script',
        );
        final cache = RecastScriptCache(
          scriptId: script.id,
          scriptName: script.name,
          sourceRootPath: script.rootPath,
          sourceFingerprint: _normalizedSourceFingerprintForTest(script),
          updatedAt: DateTime.utc(2026, 6, 12),
          mapping: RecastMapping.defaults(script.id).copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'slot-0',
                displayLabel: 'hero',
                sourceName: 'hero',
                stages: [
                  RoleAssemblyStage(
                    id: 'stage-school',
                    label: 'school',
                    frameIndexes: [1],
                    manualParts: RecastPromptParts(
                      upperClothing: '',
                      lowerClothing: 'shared skirt',
                    ),
                  ),
                  RoleAssemblyStage(
                    id: 'stage-swim',
                    label: 'swim',
                    frameIndexes: [2],
                    manualParts: RecastPromptParts(
                      upperClothing: 'swim top',
                      lowerClothing: 'swim shorts',
                    ),
                  ),
                ],
              ),
            ],
          ),
          scriptSnapshot: script.toJson(),
        );

        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadRecastCaches: () async => [cache],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(script.rootPath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        final stageChip = tester.widget<ChoiceChip>(
          find.byKey(const ValueKey('role-stage-slot-0-stage-swim')),
        );
        expect(
          stageChip.color?.resolve(const {WidgetState.hovered}),
          StudioTokens.primary.withAlpha(18),
        );
        expect(stageChip.color?.resolve(const {}), isNull);
      },
    );

    testWidgets(
      'role replacement target drag handle can copy output to another outfit chip',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final script = _scriptWithFrames(
          [
            (
              index: 1,
              base: 'artist:test',
              chars: ['hero, school jacket, shared skirt'],
            ),
            (
              index: 2,
              base: 'artist:test',
              chars: ['hero, swim top, swim shorts'],
            ),
          ],
          id: 'role-copy-drag-script',
          name: 'Role Copy Drag Script',
          rootPath: 'role-copy-drag-script',
        );
        final cache = RecastScriptCache(
          scriptId: script.id,
          scriptName: script.name,
          sourceRootPath: script.rootPath,
          sourceFingerprint: _normalizedSourceFingerprintForTest(script),
          updatedAt: DateTime.utc(2026, 6, 12),
          mapping: RecastMapping.defaults(script.id).copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'slot-0',
                displayLabel: 'hero',
                sourceName: 'hero',
                stages: [
                  RoleAssemblyStage(
                    id: 'stage-school',
                    label: 'school',
                    frameIndexes: [1],
                    manualParts: RecastPromptParts(
                      upperClothing: '',
                      lowerClothing: 'shared skirt',
                    ),
                  ),
                  RoleAssemblyStage(
                    id: 'stage-swim',
                    label: 'swim',
                    frameIndexes: [2],
                    manualParts: RecastPromptParts(
                      upperClothing: 'swim top',
                      lowerClothing: 'swim shorts',
                    ),
                  ),
                ],
              ),
            ],
          ),
          scriptSnapshot: script.toJson(),
        );

        final viewModel = StudioScriptViewModel(
          parserService: _FakeParserService([script]),
          loadRecastCaches: () async => [cache],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(script.rootPath);
        });

        final role = viewModel.roleMappings.first;
        final sourceStageId = role.stageItems.first.id;
        final targetStageId = role.stageItems.last.id;

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        final dragHandle = find.byKey(
          ValueKey(
            'role-copy-target-drag-${role.sourceRoleId}-$sourceStageId',
          ),
        );
        final targetChip = find.byKey(
          ValueKey('role-stage-${role.sourceRoleId}-$targetStageId'),
        );

        expect(dragHandle, findsOneWidget);
        expect(targetChip, findsOneWidget);

        await tester.ensureVisible(dragHandle);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final dragStart = tester.getCenter(dragHandle);
        final dragTarget = tester.getCenter(targetChip);
        await tester.timedDragFrom(
          dragStart,
          dragTarget - dragStart,
          const Duration(milliseconds: 400),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        final targetStage = viewModel.roleMappings.first.stageItems.last;
        expect(targetStage.parts.upperClothing, isEmpty);
        expect(targetStage.parts.lowerClothing, 'shared skirt');
      },
    );

    testWidgets('script drawer outfit parts require explicit partTags', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previewPath = '${Uri.base.toFilePath()}assets/appicon.png';
      final viewModel = StudioScriptViewModel(
        loadCharacters: () async => [
          CharacterEntry(
            id: 'char-hero',
            name: 'library character',
            traits: const ViewVariantTexts(frontFull: 'green eyes'),
            imageRefs: [previewPath],
            outfits: [
              WorkspaceOutfit(
                id: 'front-fields-only',
                name: 'front fields only',
                tags: const ViewVariantTexts(
                  frontFull: 'skin identity, white dress, purple skirt',
                  frontUpper: 'white dress',
                  frontLower: 'purple skirt',
                ),
                imageRefs: [previewPath],
              ),
            ],
          ),
        ],
      );
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('script-drawer-category-character')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('script-asset-character-char-hero')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey(
            'script-asset-character-char-hero-outfit-front-fields-only',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final partCard = find.byKey(
        const ValueKey(
          'script-asset-part-character-char-hero-outfit-front-fields-only-upper-clothing',
        ),
      );
      expect(partCard, findsOneWidget);
      expect(
        find.descendant(of: partCard, matching: find.text('white dress')),
        findsNothing,
      );
    });

    testWidgets(
      'complete drawer skin outfit dropped on output rows uses skin identity',
      (tester) async {
        tester.view.physicalSize = const Size(1800, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final previewPath = '${Uri.base.toFilePath()}assets/appicon.png';
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => [
            CharacterEntry(
              id: 'pepe',
              name: 'Pepe',
              traits: const ViewVariantTexts(
                frontFull: 'girl, 2::loli::, pepe_(arknights), cat ears, '
                    'long hair, cat tail, animal ear hood, black jacket',
                frontUpper: 'cat ears, long hair',
                frontLower: 'cat tail',
              ),
              anchorTags: const ['pepe_(arknights)'],
              imageRefs: [previewPath],
              defaultOutfitId: 'default',
              outfits: [
                WorkspaceOutfit(
                  id: 'default',
                  name: 'Default',
                  tags: const ViewVariantTexts(
                    frontFull: 'animal ear hood, black jacket',
                  ),
                  partTags: const WorkspaceOutfitPartTags(
                    upperClothingTags: ['animal ear hood', 'black jacket'],
                  ),
                  imageRefs: [previewPath],
                ),
                WorkspaceOutfit(
                  id: 'variant-1',
                  name: 'Nuit of the Nightsky',
                  tags: const ViewVariantTexts(
                    frontFull: 'pepe_(arknights), '
                        'pepe_(nuit_of_the_nightsky)_(arknights), '
                        'ancient egyptian clothes, sleeveless dress',
                  ),
                  partTags: const WorkspaceOutfitPartTags(
                    upperClothingTags: [
                      'ancient egyptian clothes',
                      'sleeveless dress',
                    ],
                    lowerClothingTags: ['black shorts', 'black shoes'],
                  ),
                  imageRefs: [previewPath],
                ),
              ],
            ),
          ],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });
        final role = viewModel.roleMappings.first;
        final stageId = role.selectedStage!.id;

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('script-drawer-category-character')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('script-asset-character-pepe')),
        );
        await tester.pumpAndSettle();

        final outfitCard = find.byKey(
          const ValueKey('script-asset-character-pepe-outfit-variant-1'),
        );
        final dropTarget = find.byKey(
          ValueKey(
            'role-output-part-drop-${role.sourceRoleId}-$stageId-upperClothing',
          ),
        );
        expect(outfitCard, findsOneWidget);
        expect(dropTarget, findsOneWidget);

        final dragStart = tester.getTopLeft(outfitCard) + const Offset(80, 28);
        final dropCenter = tester.getCenter(dropTarget);
        await tester.timedDragFrom(
          dragStart,
          dropCenter - dragStart,
          const Duration(milliseconds: 400),
        );
        await tester.pumpAndSettle();

        final stage = viewModel.roleMappings.first.selectedStage!;
        expect(stage.selectedCharacterId, 'pepe');
        expect(stage.selectedUpperOutfitId, 'variant-1');
        expect(stage.selectedLowerOutfitId, 'variant-1');
        expect(
          stage.parts.identity,
          'pepe_(arknights), pepe_(nuit_of_the_nightsky)_(arknights)',
        );
        expect(stage.parts.upperBody, 'cat ears, long hair');
        expect(stage.parts.lowerBody, 'cat tail');
        expect(
          stage.parts.upperClothing,
          'ancient egyptian clothes, sleeveless dress',
        );
        expect(stage.parts.lowerClothing, 'black shorts, black shoes');
      },
    );

    testWidgets('role mapping target has a one-click clear all action', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewModel = StudioScriptViewModel(
        loadCharacters: () async => const [
          CharacterEntry(
            id: 'pepe',
            name: 'Pepe',
            traits: ViewVariantTexts(
              frontFull: 'pepe_(arknights)',
              frontUpper: 'cat ears',
              frontLower: 'cat tail',
            ),
            anchorTags: ['pepe_(arknights)'],
            outfits: [
              WorkspaceOutfit(
                id: 'default',
                name: 'Default',
                tags: ViewVariantTexts(frontFull: 'animal ear hood'),
                partTags: WorkspaceOutfitPartTags(
                  upperClothingTags: ['animal ear hood'],
                  lowerClothingTags: ['black shorts'],
                ),
              ),
            ],
            defaultOutfitId: 'default',
          ),
        ],
      );
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });
      viewModel.applyRoleOutfitDrop(
        sourceRoleId: 'slot-0',
        characterId: 'pepe',
        outfitId: 'default',
      );
      final stageId = viewModel.roleMappings.first.selectedStage!.id;

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      final clearButton = find.byKey(
        ValueKey('role-clear-target-all-slot-0-$stageId'),
      );
      expect(clearButton, findsOneWidget);
      await tester.tap(clearButton);
      await tester.pumpAndSettle();

      final stage = viewModel.roleMappings.first.selectedStage!;
      expect(stage.selectedCharacterId, isNull);
      expect(stage.parts.isEmpty, isTrue);
      expect(stage.omittedParts, contains(RecastPromptPart.identity));
      expect(stage.omittedParts, contains(RecastPromptPart.upperClothing));
    });

    testWidgets(
      'cleared target fields do not fall back to selected character',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => const [
            CharacterEntry(
              id: 'shamare',
              name: 'Shamare',
              traits: ViewVariantTexts(
                frontFull: 'shamare_(arknights), fox ears, fox tail',
                frontUpper: 'fox ears',
                frontLower: 'fox tail',
              ),
              anchorTags: ['shamare_(arknights)'],
              outfits: [
                WorkspaceOutfit(
                  id: 'default',
                  name: 'Default',
                  tags: ViewVariantTexts(frontFull: 'black dress'),
                  partTags: WorkspaceOutfitPartTags(
                    lowerClothingTags: ['black dress'],
                  ),
                ),
              ],
              defaultOutfitId: 'default',
            ),
          ],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });
        viewModel.setRoleCharacter('slot-0', 'shamare');
        final stageId = viewModel.roleMappings.first.selectedStage!.id;
        for (final part in const [
          StudioScriptRolePart.identity,
          StudioScriptRolePart.upperBody,
          StudioScriptRolePart.lowerBody,
        ]) {
          viewModel.setRoleStagePart(
            sourceRoleId: 'slot-0',
            stageId: stageId,
            part: part,
            value: '',
          );
        }

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final identityField = find.byKey(
          ValueKey('role-output-part-slot-0-$stageId-identity'),
        );
        final upperBodyField = find.byKey(
          ValueKey('role-output-part-slot-0-$stageId-upperBody'),
        );
        final lowerBodyField = find.byKey(
          ValueKey('role-output-part-slot-0-$stageId-lowerBody'),
        );
        expect(identityField, findsOneWidget);
        expect(upperBodyField, findsOneWidget);
        expect(lowerBodyField, findsOneWidget);
        expect(
          find.descendant(
            of: identityField,
            matching: find.textContaining('shamare'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: upperBodyField, matching: find.text('fox ears')),
          findsNothing,
        );
        expect(
          find.descendant(of: lowerBodyField, matching: find.text('fox tail')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'script drawer hover preview matches workbench behavior for outfit assets',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final tempDir = Directory.systemTemp.createTempSync(
          'script-drawer-preview-wheel-',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final source = File('${Uri.base.toFilePath()}assets/appicon.png');
        final first = File('${tempDir.path}${Platform.pathSeparator}first.png')
          ..writeAsBytesSync(source.readAsBytesSync());
        final second = File(
          '${tempDir.path}${Platform.pathSeparator}second.png',
        )..writeAsBytesSync(source.readAsBytesSync());
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => [
            CharacterEntry(
              id: 'char-hero',
              name: 'library character',
              traits: const ViewVariantTexts(frontFull: 'green eyes'),
              imageRefs: [first.path, second.path],
              defaultOutfitId: 'outfit-hero-default',
              outfits: [
                WorkspaceOutfit(
                  id: 'outfit-hero-default',
                  name: 'default outfit',
                  tags: const ViewVariantTexts(frontFull: 'white shirt'),
                  imageRefs: [first.path, second.path],
                ),
              ],
            ),
          ],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('script-drawer-category-character')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
            find.byKey(const ValueKey('script-asset-character-char-hero')));
        await tester.pumpAndSettle();

        String imagePathFor(Finder root) {
          final image = tester
              .widgetList<Image>(
                find.descendant(of: root, matching: find.byType(Image)),
              )
              .single;
          return (image.image as FileImage).file.path;
        }

        final preview = find.byKey(
          const ValueKey(
            'script-asset-preview-character-char-hero-outfit-outfit-hero-default',
          ),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(
          location: tester.getCenter(
            find.byKey(
              const ValueKey(
                'script-asset-character-char-hero-outfit-outfit-hero-default',
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(
            const ValueKey(
              'script-asset-preview-character-char-hero-outfit-outfit-hero-default-overlay',
            ),
          ),
          findsNothing,
        );

        await mouse.moveTo(tester.getCenter(preview));
        await tester.pump();

        final overlay = find.byKey(
          const ValueKey(
            'script-asset-preview-character-char-hero-outfit-outfit-hero-default-overlay',
          ),
        );
        expect(overlay, findsOneWidget);
        expect(tester.getSize(overlay), const Size(704, 960));
        expect(imagePathFor(preview), first.path);
        expect(imagePathFor(overlay), first.path);

        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(preview),
            scrollDelta: const Offset(0, 120),
          ),
        );
        await tester.pump();

        expect(imagePathFor(preview), second.path);
        expect(imagePathFor(overlay), second.path);

        await mouse.moveTo(Offset.zero);
        await tester.pump();

        expect(overlay, findsNothing);
      },
    );

    testWidgets(
      'script drawer character cards fall back to outfit previews',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final tempDir = Directory.systemTemp.createTempSync(
          'script-drawer-character-preview-',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final source = File('${Uri.base.toFilePath()}assets/appicon.png');
        final preview = File(
          '${tempDir.path}${Platform.pathSeparator}outfit.png',
        )..writeAsBytesSync(source.readAsBytesSync());
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => [
            CharacterEntry(
              id: 'char-hero',
              name: 'library character',
              traits: const ViewVariantTexts(frontFull: 'green eyes'),
              defaultOutfitId: 'outfit-hero-default',
              outfits: [
                WorkspaceOutfit(
                  id: 'outfit-hero-default',
                  name: 'default outfit',
                  tags: const ViewVariantTexts(frontFull: 'white shirt'),
                  imageRefs: [preview.path],
                ),
              ],
            ),
          ],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('script-drawer-category-character')),
        );
        await tester.pumpAndSettle();

        final characterPreview = find.byKey(
          const ValueKey('script-asset-preview-character-char-hero'),
        );
        final image = tester
            .widgetList<Image>(
              find.descendant(
                of: characterPreview,
                matching: find.byType(Image),
              ),
            )
            .single;

        expect((image.image as FileImage).file.path, preview.path);
      },
    );

    testWidgets(
      'script asset drawer opens and highlights focused library asset',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => const [
            CharacterEntry(
              id: 'char-hero',
              name: 'library character',
              traits: ViewVariantTexts(frontFull: 'green eyes'),
              outfits: [
                WorkspaceOutfit(
                  id: 'outfit-hero-default',
                  name: 'default outfit',
                  tags: ViewVariantTexts(frontFull: 'white shirt'),
                ),
              ],
            ),
          ],
          loadArtistChains: () async => const [
            ArtistChain(
              id: 'artist-chain-1',
              name: 'test artist chain',
              prompt: 'artist:replacement',
            ),
          ],
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(
          buildScriptPage(
            viewModel: viewModel,
            assetFocus: const StudioScriptAssetFocus.outfit(
              characterId: 'char-hero',
              outfitId: 'outfit-hero-default',
            ),
          ),
        );
        await tester.pumpAndSettle();

        final focusedCard = find.byKey(
          const ValueKey(
            'script-asset-character-char-hero-outfit-outfit-hero-default',
          ),
        );
        expect(
          find.byKey(const ValueKey('script-drawer-category-outfit')),
          findsNothing,
        );
        expect(focusedCard, findsOneWidget);

        final decorated = tester.widget<Container>(
          find
              .descendant(of: focusedCard, matching: find.byType(Container))
              .first,
        );
        final decoration = decorated.decoration as BoxDecoration;
        final border = decoration.border as Border;
        expect(border.top.color, StudioTokens.primary);
      },
    );

    testWidgets(
      'script asset focus scrolls the matching drawer card into view',
      (tester) async {
        tester.view.physicalSize = const Size(1300, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final viewModel = StudioScriptViewModel(
          loadCharacters: () async => [
            for (var index = 0; index < 24; index += 1)
              CharacterEntry(
                id: 'char-$index',
                name: '瑙掕壊 $index',
                traits: const ViewVariantTexts(frontFull: 'green eyes'),
                outfits: [
                  WorkspaceOutfit(
                    id: 'outfit-$index',
                    name: '鏈嶈 $index',
                    tags: const ViewVariantTexts(frontFull: 'white shirt'),
                  ),
                ],
              ),
          ],
          loadArtistChains: () async => const [],
        );
        await tester.runAsync(() async {
          await viewModel.ensureAssetsLoaded();
        });

        await tester.pumpWidget(
          buildScriptPage(
            viewModel: viewModel,
            assetFocus: const StudioScriptAssetFocus.outfit(
              characterId: 'char-23',
              outfitId: 'outfit-23',
            ),
          ),
        );
        await tester.pumpAndSettle();

        final focusedCard = find.byKey(
          const ValueKey('script-asset-character-char-23-outfit-outfit-23'),
        );
        expect(
          find.byKey(const ValueKey('script-drawer-category-outfit')),
          findsNothing,
        );
        expect(focusedCard, findsOneWidget);

        final focusedTop = tester.getTopLeft(focusedCard).dy;
        final drawerBottom = tester
            .getBottomLeft(
              find.byKey(const ValueKey('script-layout-left-drawer')),
            )
            .dy;
        expect(focusedTop, lessThan(drawerBottom - 80));
      },
    );

    testWidgets('script page exposes role extraction controls only', (
      tester,
    ) async {
      final viewModel = StudioScriptViewModel();
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      expect(find.text('AI 鍒嗘瀽鍓ф湰'), findsNothing);
      expect(
        find.widgetWithIcon(StudioButton, Icons.smart_toy_outlined),
        findsNothing,
      );
      expect(find.text('AI 鏁寸悊瑙掕壊瀛楁'), findsOneWidget);
      expect(find.text('璇诲彇鍘嗗彶 AI 寤鸿'), findsNothing);
      expect(find.text('鍙娇鐢ㄧ紦瀛樺缓璁?'), findsNothing);
      expect(find.text('閲嶈瘯澶辫触椤?'), findsNothing);
      expect(find.text('閲嶈瘯澶辫触鎵规'), findsNothing);
      expect(
        find.byKey(const ValueKey('script-ai-progress-panel')),
        findsNothing,
      );
    });

    testWidgets('script page shows AI role extraction action and draft panel', (
      tester,
    ) async {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        confidence: 0.92,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            displayName: 'vulpisfoglia_(arknights)',
            confidence: 0.91,
            warnings: ['missing lower body evidence'],
            stages: [
              ScriptAiExtractedStage(
                stageId: 'main-outfit',
                label: 'main outfit',
                frameIndexes: [1, 2],
                identity: 'vulpisfoglia_(arknights)',
                upperBody: 'fox ears',
                lowerBody: '',
                upperClothing: 'blue jacket',
                lowerClothing: 'white skirt',
                evidenceTerms: ['fox ears', 'blue jacket'],
                missingFields: ['lower_body'],
                warnings: ['lower_body is empty'],
                confidence: 0.9,
              ),
            ],
            unassignedTerms: [
              ScriptAiUnassignedTerm(
                term: 'mystery accessory',
                frameIndexes: [2],
                reason: 'role-local evidence needs review',
              ),
            ],
          ),
        ],
        unassignedTerms: [
          ScriptAiUnassignedTerm(
            term: 'floating scarf',
            frameIndexes: [1],
            reason: 'cannot safely assign to a role',
          ),
        ],
        artistChains: [
          ScriptAiArtistChainEvidence(
            label: 'artist chain',
            terms: ['artist:terasu_mc'],
            evidenceTerms: ['terasu_mc'],
            confidence: 0.86,
          ),
        ],
        strongFilterKeywords: [
          ScriptAiStrongFilterKeyword(
            term: 'bad hands',
            reason: 'strong filter term',
          ),
        ],
        attentionItems: [
          ScriptAiExtractionAttentionItem(
            id: 'missing-lower-body',
            kind: 'missing_field',
            message: 'lower_body needs review',
            sourceRoleId: 'slot-0',
          ),
        ],
      );
      final viewModel = StudioScriptViewModel(
        scriptAiRoleExtractionService: const _FakeRoleExtractionService(
          extraction,
        ),
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );

      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();
      });
      viewModel.aiProgressTitle = '';
      viewModel.aiProgressSteps = const [];

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      final draftPanel = find.byKey(
        const ValueKey('script-ai-role-extraction-draft-panel'),
      );
      expect(draftPanel, findsOneWidget);
      expect(
        find.descendant(
          of: draftPanel,
          matching: find.text('AI 角色字段草稿'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('vulpisfoglia_(arknights)'), findsWidgets);
      expect(
        find.byKey(
          const ValueKey(
            'script-ai-role-field-slot-0-main-outfit-upperClothing',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('script-ai-role-field-slot-0-main-outfit-nonRole'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('script-ai-role-pending-evidence')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: draftPanel,
          matching: find.text('floating scarf'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: draftPanel,
          matching: find.text('mystery accessory'),
        ),
        findsNothing,
      );
      final nonRoleField = find.byKey(
        const ValueKey('script-ai-role-field-slot-0-main-outfit-nonRole'),
      );
      final nonRoleEditor = tester.widget<PromptTagEditor>(nonRoleField);
      expect(nonRoleEditor.autoTranslateTagLimit, isNull);
      expect(
        find.descendant(
          of: nonRoleField,
          matching: find.byWidgetPredicate((widget) {
            final key = widget.key;
            return key is ValueKey<String> &&
                key.value.startsWith('prompt-tag-editor-group-');
          }),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(of: draftPanel, matching: find.text('blue jacket')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: draftPanel,
          matching: find.text('artist:terasu_mc'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: draftPanel, matching: find.text('bad hands')),
        findsNothing,
      );
      final roleSave = find.byKey(const ValueKey('script-ai-role-save-slot-0'));
      expect(roleSave, findsOneWidget);
      expect(
        find.descendant(of: roleSave, matching: find.text('保存素材')),
        findsOneWidget,
      );

      final upperClothingField = find.byKey(
        const ValueKey('script-ai-role-field-slot-0-main-outfit-upperClothing'),
      );
      await tester.ensureVisible(upperClothingField);
      await tester.pumpAndSettle();
      final addUpperClothingTag = find.descendant(
        of: upperClothingField,
        matching: find.byKey(const ValueKey('prompt-tag-editor-add')),
      );
      await tester.ensureVisible(addUpperClothingTag);
      await tester.pumpAndSettle();
      await tester.tap(addUpperClothingTag);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: upperClothingField,
          matching: find.byKey(const ValueKey('prompt-tag-editor-input')),
        ),
        'gold trim',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        viewModel.aiRoleExtraction.roles.single.stages.single.upperClothing,
        'blue jacket, gold trim',
      );
      expect(find.text('gold trim'), findsOneWidget);

      final detailsButton = find.byTooltip('查看 AI 处理详情');
      await tester.ensureVisible(detailsButton);
      await tester.pump();
      await tester.tap(detailsButton);
      await tester.pumpAndSettle();

      final fullLogs = find.text('完整日志与证据');
      await tester.ensureVisible(fullLogs);
      await tester.pump();
      await tester.tap(fullLogs);
      await tester.pumpAndSettle();
      final hiddenEvidence = find.text('隐藏证据');
      await tester.ensureVisible(hiddenEvidence);
      await tester.pump();
      await tester.tap(hiddenEvidence);
      await tester.pumpAndSettle();

      expect(find.text('隐藏证据'), findsOneWidget);
      expect(find.text('artist:terasu_mc'), findsWidgets);
      expect(find.text('bad hands'), findsWidgets);
      final artistEvidenceSave = find.byKey(
        const ValueKey('script-ai-artist-chain-save-0'),
      );
      expect(artistEvidenceSave, findsOneWidget);
      expect(
        find.descendant(of: artistEvidenceSave, matching: find.text('保存素材')),
        findsOneWidget,
      );
    });

    testWidgets('AI role draft shows apply cache adjustment action', (
      tester,
    ) async {
      final classificationCache = PromptTagClassificationCache();
      classificationCache.setCategory(
        'fox tail',
        PromptTagCategory.lowerBody,
        source: 'manual-role-field',
      );
      final viewModel = StudioScriptViewModel(
        parserService: _FakeParserService([
          _scriptWithFrames([
            (index: 1, base: 'forest', chars: ['ai hero, fox tail']),
          ]),
        ]),
        classificationCache: classificationCache,
        scriptAiRoleExtractionService: const _FakeRoleExtractionService(
          ScriptAiRoleExtraction(
            status: ScriptAiRoleExtractionStatus.ready,
            roles: [
              ScriptAiExtractedRole(
                sourceRoleId: 'slot-0',
                stages: [
                  ScriptAiExtractedStage(
                    stageId: 'main-outfit',
                    frameIndexes: [1],
                    identity: 'ai hero',
                    upperBody: 'fox tail',
                    confidence: 0.9,
                  ),
                ],
              ),
            ],
          ),
        ),
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );

      await tester.runAsync(() async {
        await viewModel.importScriptPath('cache-button-script');
        await viewModel.generateAiRoleExtraction();
      });
      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      final cacheButton = find.byKey(
        const ValueKey('script-ai-role-apply-cache-adjustment'),
      );
      expect(cacheButton, findsOneWidget);

      await tester.ensureVisible(cacheButton);
      await tester.pumpAndSettle();
      await tester.tap(cacheButton);
      await tester.pumpAndSettle();

      expect(
        viewModel.aiRoleExtraction.roles.single.stages.single.lowerBody,
        'fox tail',
      );
      expect(viewModel.isAiRoleExtractionDraftCollapsed, isFalse);
    });

    testWidgets('AI role draft prioritizes female roles before male roles', (
      tester,
    ) async {
      final viewModel = StudioScriptViewModel(
        parserService: _FakeParserService([
          _scriptWithFrames([
            (index: 1, base: 'school yard', chars: ['heroine, guard']),
          ]),
        ]),
        scriptAiRoleExtractionService: const _FakeRoleExtractionService(
          ScriptAiRoleExtraction(
            status: ScriptAiRoleExtractionStatus.ready,
            roles: [
              ScriptAiExtractedRole(
                sourceRoleId: 'slot-1',
                displayName: 'Guard',
                stages: [
                  ScriptAiExtractedStage(
                    stageId: 'guard-main',
                    frameIndexes: [1],
                    identity: 'guard, boy',
                    confidence: 0.82,
                  ),
                ],
              ),
              ScriptAiExtractedRole(
                sourceRoleId: 'slot-0',
                displayName: 'Heroine',
                stages: [
                  ScriptAiExtractedStage(
                    stageId: 'heroine-main',
                    frameIndexes: [1],
                    identity: 'heroine, girl',
                    confidence: 0.91,
                  ),
                ],
              ),
            ],
          ),
        ),
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );

      await tester.runAsync(() async {
        await viewModel.importScriptPath('ai-draft-gender-priority-script');
        await viewModel.generateAiRoleExtraction();
      });
      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      final heroine = find.textContaining('Heroine');
      final guard = find.textContaining('Guard');
      expect(heroine, findsOneWidget);
      expect(guard, findsOneWidget);
      expect(
        tester.getTopLeft(heroine).dy,
        lessThan(tester.getTopLeft(guard).dy),
      );
    });

    testWidgets('AI role draft marks manual role cache hit tags', (
      tester,
    ) async {
      final classificationCache = PromptTagClassificationCache();
      classificationCache.setCategory(
        'fox tail',
        PromptTagCategory.lowerBody,
        source: 'manual-role-field',
      );
      final viewModel = StudioScriptViewModel(
        parserService: _FakeParserService([
          _scriptWithFrames([
            (index: 1, base: 'forest', chars: ['ai hero, fox tail']),
          ]),
        ]),
        classificationCache: classificationCache,
        scriptAiRoleExtractionService: const _FakeRoleExtractionService(
          ScriptAiRoleExtraction(
            status: ScriptAiRoleExtractionStatus.ready,
            roles: [
              ScriptAiExtractedRole(
                sourceRoleId: 'slot-0',
                stages: [
                  ScriptAiExtractedStage(
                    stageId: 'main-outfit',
                    frameIndexes: [1],
                    identity: 'ai hero',
                    upperBody: 'fox tail',
                    confidence: 0.9,
                  ),
                ],
              ),
            ],
          ),
        ),
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );

      await tester.runAsync(() async {
        await viewModel.importScriptPath('cache-badge-script');
        await viewModel.generateAiRoleExtraction();
      });
      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('prompt-tag-editor-cache-hit-fox tail')),
        findsOneWidget,
      );
    });

    testWidgets('AI role draft filter-rule action removes visible field tags', (
      tester,
    ) async {
      final viewModel = StudioScriptViewModel(
        parserService: _FakeParserService([
          _scriptWithFrames([
            (index: 1, base: 'forest', chars: ['ai hero, fox tail']),
          ]),
        ]),
        scriptAiRoleExtractionService: const _FakeRoleExtractionService(
          ScriptAiRoleExtraction(
            status: ScriptAiRoleExtractionStatus.ready,
            roles: [
              ScriptAiExtractedRole(
                sourceRoleId: 'slot-0',
                stages: [
                  ScriptAiExtractedStage(
                    stageId: 'main-outfit',
                    frameIndexes: [1],
                    identity: 'ai hero',
                    upperBody: 'fox tail',
                    confidence: 0.9,
                  ),
                ],
              ),
            ],
          ),
        ),
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );

      await tester.runAsync(() async {
        await viewModel.importScriptPath('filter-rule-ai-draft-script');
        await viewModel.generateAiRoleExtraction();
      });
      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      final upperBodyField = find.byKey(
        const ValueKey('script-ai-role-field-slot-0-main-outfit-upperBody'),
      );
      await tester.ensureVisible(upperBodyField);
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(of: upperBodyField, matching: find.text('fox tail')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('prompt-tag-editor-add-to-filter-rules')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('prompt-tag-editor-filter-target-delete')),
      );
      await tester.pumpAndSettle();

      expect(
        viewModel.aiRoleExtraction.roles.single.stages.single.upperBody,
        isEmpty,
      );
      expect(
        find.descendant(of: upperBodyField, matching: find.text('fox tail')),
        findsNothing,
      );
    });

    testWidgets(
      'AI role extraction action is not duplicated in the page header',
      (tester) async {
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            _highConfidenceSlotExtraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
          await viewModel.generateAiRoleExtraction();
        });
        viewModel.aiProgressTitle = '';
        viewModel.aiProgressSteps = const [];

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        expect(find.text('瀵煎叆鍓ф湰'), findsOneWidget);
        expect(find.text('瀵煎叆鍓ф湰鐩綍'), findsNothing);
        expect(find.text('搴旂敤瀛楁'), findsOneWidget);
      },
    );

    testWidgets('review token right-click menu can change category', (
      tester,
    ) async {
      final classificationCache = PromptTagClassificationCache(
        clock: () => 1710000000,
      );
      final viewModel = StudioScriptViewModel(
        parserService: _FakeParserService([
          _singleFrameScript(baseCaption: 'arata_asato, city lights'),
        ]),
        classificationCache: classificationCache,
      );

      await viewModel.importScriptPath('artist-name-script');
      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      final positiveColumn = find.byKey(
        const ValueKey('script-keyframe-positive-column'),
      );
      final tokenText = find
          .descendant(of: positiveColumn, matching: find.text('arata_asato'))
          .first;
      await tester.ensureVisible(tokenText);
      await tester.pumpAndSettle();
      await tester.tap(tokenText, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      final changeCategoryItem = find.byKey(
        const ValueKey('prompt-tag-change-category'),
      );
      expect(changeCategoryItem, findsOneWidget);

      await tester.tap(changeCategoryItem);
      await tester.pumpAndSettle();

      final artistCategoryOption = find.byKey(
        const ValueKey('prompt-tag-category-option-artist'),
      );
      expect(artistCategoryOption, findsOneWidget);

      await tester.tap(artistCategoryOption);
      await tester.pumpAndSettle();

      expect(
        classificationCache.entryFor('arata_asato')?.category,
        PromptTagCategory.artist,
      );
      expect(classificationCache.entryFor('arata_asato')?.source, 'manual');

      final token = viewModel.recastPlan.frameReviews.single.positiveTokens
          .where((token) => token.source == 'arata_asato')
          .single;
      expect(token.category, StudioScriptTokenCategory.artistChain);
    });

    testWidgets(
      'AI role extraction draft can be expanded after apply collapse',
      (tester) async {
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            _highConfidenceSlotExtraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
          await viewModel.generateAiRoleExtraction();
          await viewModel.applyHighConfidenceAiRoleExtraction();
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('script-ai-role-extraction-draft-panel')),
          findsNothing,
        );
        expect(
          find.byKey(
            const ValueKey('script-ai-role-extraction-draft-collapsed'),
          ),
          findsOneWidget,
        );

        final expandButton = find.byTooltip('灞曞紑 AI 瑙掕壊瀛楁鑽夌');
        await tester.ensureVisible(expandButton);
        await tester.pumpAndSettle();
        await tester.tap(expandButton);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('script-ai-role-extraction-draft-panel')),
          findsOneWidget,
        );
        expect(find.textContaining('AI Hero'), findsWidgets);
      },
    );

    testWidgets(
      'AI role extraction draft collapse persists through cache import',
      (tester) async {
        var caches = <RecastScriptCache>[];
        final seedViewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
          scriptAiRoleExtractionService: const _FakeRoleExtractionService(
            _highConfidenceSlotExtraction,
          ),
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );

        await tester.runAsync(() async {
          await seedViewModel.importScriptPath(_fixturePath);
          await seedViewModel.generateAiRoleExtraction();
          await seedViewModel.applyHighConfidenceAiRoleExtraction();
        });

        final viewModel = StudioScriptViewModel(
          loadRecastCaches: () async => caches,
          saveRecastCaches: (next) async => caches = next,
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('script-ai-role-extraction-draft-panel')),
          findsNothing,
        );
        expect(
          find.byKey(
            const ValueKey('script-ai-role-extraction-draft-collapsed'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('AI role extraction progress is Chinese and detailed', (
      tester,
    ) async {
      final service = _PendingRoleExtractionService();
      final viewModel = StudioScriptViewModel(
        scriptAiRoleExtractionService: service,
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        unawaited(viewModel.generateAiRoleExtraction());
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();

      final panel = find.byKey(const ValueKey('script-ai-progress-panel'));
      expect(panel, findsOneWidget);
      expect(panel, findsOneWidget);
      expect(
        find.descendant(
          of: panel,
          matching: find.byKey(const ValueKey('script-ai-progress-hero')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: panel,
          matching: find.byKey(const ValueKey('script-ai-progress-step-rail')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: panel,
          matching: find.byKey(
            const ValueKey('script-ai-progress-current-step'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('AI 整理角色字段')),
        findsOneWidget,
      );
      expect(find.text('检查导入剧本'), findsOneWidget);
      expect(find.text('压缩原始标签证据'), findsOneWidget);
      expect(find.text('准备 AI 请求'), findsOneWidget);
      expect(find.text('请求 AI 角色字段'), findsOneWidget);
      expect(find.text('解析角色与服装阶段'), findsOneWidget);
      expect(find.text('整理画师串和强过滤词'), findsOneWidget);
      expect(find.text('写入草稿缓存'), findsOneWidget);
      expect(
        find.descendant(of: panel, matching: find.text('正在请求 AI 提取角色字段...')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: panel,
          matching: find.textContaining('进度 4/7 · 52%'),
        ),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        service.complete(
          const ScriptAiRoleExtractionServiceResult(
            extraction: ScriptAiRoleExtraction(
              status: ScriptAiRoleExtractionStatus.ready,
              confidence: 0.9,
            ),
            requestPreview: {'schema_version': 1},
            aiRequestCount: 1,
            reasoningContent: '先检查 slot-0，再整理服装字段。',
          ),
        );
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: panel, matching: find.text('AI 角色字段草稿已生成')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: panel,
          matching: find.textContaining('进度 7/7 · 100%'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('瀹屾垚')),
        findsNothing,
      );
      expect(
        find.descendant(of: panel, matching: find.text('已完成')),
        findsNWidgets(7),
      );

      await tester.tap(
        find.descendant(of: panel, matching: find.byTooltip('查看 AI 处理详情')),
      );
      await tester.pumpAndSettle();

      expect(find.text('AI 处理详情'), findsOneWidget);
      expect(find.text('请求摘要'), findsOneWidget);
      expect(find.text('DeepSeek 思考过程'), findsOneWidget);
      expect(find.text('AI 请求次数：1'), findsOneWidget);
      expect(find.text('先检查 slot-0，再整理服装字段。'), findsWidgets);
    });

    testWidgets('AI role extraction can be stopped and ignores late results', (
      tester,
    ) async {
      final service = _PendingRoleExtractionService();
      final viewModel = StudioScriptViewModel(
        scriptAiRoleExtractionService: service,
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        unawaited(viewModel.generateAiRoleExtraction());
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();

      expect(viewModel.isAiBusy, isTrue);
      final stopButton = find.byKey(
        const ValueKey('script-ai-stop-processing'),
      );
      expect(stopButton, findsOneWidget);

      await tester.tap(stopButton);
      await tester.pump();

      expect(viewModel.isAiBusy, isFalse);
      expect(viewModel.aiStatus, contains('鍋滄'));

      await tester.runAsync(() async {
        service.complete(
          const ScriptAiRoleExtractionServiceResult(
            extraction: _highConfidenceSlotExtraction,
            requestPreview: {'schema_version': 1},
            aiRequestCount: 1,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();

      expect(viewModel.aiRoleExtraction.isReady, isFalse);
      expect(viewModel.aiStatus, contains('鍋滄'));
    });

    testWidgets(
      'AI processing details show live reasoning and response stream',
      (tester) async {
        final service = _PendingRoleExtractionService(
          startedPreview: const {
            'schema_version': 1,
            'request_kind': 'chunk_extract',
            'chunk_id': 'chunk-1',
          },
        );
        final viewModel = StudioScriptViewModel(
          scriptAiRoleExtractionService: service,
          scriptAiBaseUrlProvider: () => 'https://script.example/v1',
          scriptAiTokenProvider: () => 'token',
          scriptAiModelProvider: () => 'gpt-4.1-mini',
        );
        await tester.runAsync(() async {
          await viewModel.importScriptPath(_fixturePath);
        });

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        await tester.runAsync(() async {
          unawaited(viewModel.generateAiRoleExtraction());
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pump();

        final panel = find.byKey(const ValueKey('script-ai-progress-panel'));
        expect(panel, findsOneWidget);
        await tester.tap(
          find.descendant(
            of: panel,
            matching: find.byIcon(Icons.subject_outlined),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('script-ai-live-stream')),
          findsOneWidget,
        );

        service.emitStreamDelta(
          const ScriptAiRoleExtractionStreamDelta(
            reasoningContentDelta: '姝ｅ湪妫€鏌?chunk-1 鐨?slot-0',
          ),
        );
        await tester.pump();

        expect(
          viewModel.aiRoleExtractionTraceEvents.where(
            (event) => event.kind == StudioScriptAiTraceEventKind.reasoning,
          ),
          isEmpty,
        );
        expect(find.textContaining('姝ｅ湪妫€鏌?chunk-1 鐨?slot-0'), findsOneWidget);

        service.emitStreamDelta(
          const ScriptAiRoleExtractionStreamDelta(
            contentDelta: '{"schema_version":1',
          ),
        );
        await tester.pump(const Duration(milliseconds: 130));

        expect(
          viewModel.aiRoleExtractionTraceEvents.where(
            (event) => event.kind == StudioScriptAiTraceEventKind.content,
          ),
          isEmpty,
        );
        expect(find.textContaining('{"schema_version":1'), findsWidgets);

        service.complete(
          const ScriptAiRoleExtractionServiceResult(
            extraction: ScriptAiRoleExtraction(
              status: ScriptAiRoleExtractionStatus.ready,
              confidence: 0.9,
            ),
            requestPreview: {
              'schema_version': 1,
              'request_kind': 'chunk_extract',
              'chunk_id': 'chunk-1',
            },
            aiRequestCount: 1,
            reasoningContent: 'final reasoning',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('final reasoning'), findsOneWidget);
      },
    );

    testWidgets('AI processing details default to recent compact snippets', (
      tester,
    ) async {
      final service = _PendingRoleExtractionService(
        startedPreview: const {
          'schema_version': 1,
          'request_kind': 'chunk_extract_v2',
          'chunk_id': 'chunk-1',
          'sources': [
            {
              'source_id': 'source-early',
              'source_kind': 'base',
              'tag_evidence': [
                {'tag': 'early-source-tag-hidden-by-default'},
              ],
            },
          ],
        },
      );
      final viewModel = StudioScriptViewModel(
        scriptAiRoleExtractionService: service,
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        unawaited(viewModel.generateAiRoleExtraction());
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();

      service.emitStreamDelta(
        ScriptAiRoleExtractionStreamDelta(
          reasoningContentDelta: [
            'EARLY_REASONING_SHOULD_BE_COLLAPSED',
            List.filled(260, 'middle-reasoning-token').join(' '),
            'LATEST_REASONING_SHOULD_BE_VISIBLE',
          ].join('\n\n'),
          contentDelta: [
            'EARLY_RESPONSE_SHOULD_BE_COLLAPSED',
            List.filled(220, 'middle-response-token').join(' '),
            'LATEST_RESPONSE_SHOULD_BE_VISIBLE',
          ].join('\n'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 130));

      final panel = find.byKey(const ValueKey('script-ai-progress-panel'));
      await tester.tap(
        find.descendant(
          of: panel,
          matching: find.byIcon(Icons.subject_outlined),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('LATEST_REASONING_SHOULD_BE_VISIBLE'),
        findsOneWidget,
      );
      expect(
        find.textContaining('LATEST_RESPONSE_SHOULD_BE_VISIBLE'),
        findsOneWidget,
      );
      expect(
        find.textContaining('EARLY_REASONING_SHOULD_BE_COLLAPSED'),
        findsNothing,
      );
      expect(
        find.textContaining('EARLY_RESPONSE_SHOULD_BE_COLLAPSED'),
        findsNothing,
      );
      expect(
        find.textContaining('early-source-tag-hidden-by-default'),
        findsNothing,
      );

      final fullLogs = find.text('瀹屾暣鏃ュ織涓庤瘉鎹?');
      await tester.ensureVisible(fullLogs);
      await tester.pump();
      await tester.tap(fullLogs);
      await tester.pumpAndSettle();
      final fullReasoning = find.text('瀹屾暣 DeepSeek 鎬濊€冭繃绋?');
      await tester.ensureVisible(fullReasoning);
      await tester.pump();
      await tester.tap(fullReasoning);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('EARLY_REASONING_SHOULD_BE_COLLAPSED'),
        findsOneWidget,
      );
    });

    testWidgets(
      'AI role extraction apply action is disabled while apply is running',
      (tester) async {
        final viewModel = _SlowApplyingViewModel()
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
                    label: 'main outfit',
                    confidence: 0.9,
                  ),
                ],
              ),
            ],
          );

        await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
        await tester.pumpAndSettle();

        final extractButton = _studioButtonByIcon(Icons.auto_awesome_outlined);
        final applyButton = _studioButtonByIcon(
          Icons.playlist_add_check_outlined,
        );
        expect(
          tester
              .widgetList<FilledButton>(extractButton)
              .every((button) => button.onPressed != null),
          isTrue,
        );
        expect(
          tester
              .widgetList<FilledButton>(applyButton)
              .every((button) => button.onPressed != null),
          isTrue,
        );

        await tester.ensureVisible(applyButton.first);
        await tester.pumpAndSettle();
        await tester.tap(applyButton.first);
        await tester.pump();

        expect(viewModel.applyCallCount, 1);
        expect(
          tester
              .widgetList<FilledButton>(extractButton)
              .every((button) => button.onPressed == null),
          isTrue,
        );
        expect(
          tester
              .widgetList<FilledButton>(applyButton)
              .every((button) => button.onPressed == null),
          isTrue,
        );

        await tester.ensureVisible(applyButton.first);
        await tester.pumpAndSettle();
        await tester.tap(applyButton.first);
        await tester.pump();

        expect(viewModel.applyCallCount, 1);

        viewModel.completeApply();
        await tester.pumpAndSettle();

        expect(
          tester
              .widgetList<FilledButton>(extractButton)
              .every((button) => button.onPressed != null),
          isTrue,
        );
        expect(
          tester
              .widgetList<FilledButton>(applyButton)
              .every((button) => button.onPressed != null),
          isTrue,
        );
      },
    );

    testWidgets('script page shows failed AI role extraction raw response', (
      tester,
    ) async {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.failed,
        rawResponse: '[]',
        attentionItems: [
          ScriptAiExtractionAttentionItem(
            id: 'parse-failure',
            kind: 'parse_failure',
            message: 'Missing JSON object',
            blocking: true,
          ),
        ],
      );
      final viewModel = StudioScriptViewModel(
        scriptAiRoleExtractionService: const _FakeRoleExtractionService(
          extraction,
        ),
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );

      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();
      });
      viewModel.aiProgressTitle = '';
      viewModel.aiProgressSteps = const [];

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('script-ai-role-extraction-draft-panel')),
        findsOneWidget,
      );
      expect(find.text('瑙掕壊瀛楁鏁寸悊澶辫触'), findsOneWidget);
      expect(find.text('AI 杩斿洖瑙ｆ瀽澶辫触锛歁issing JSON object'), findsOneWidget);
      expect(find.text('[]'), findsOneWidget);
      expect(find.text('鎵嬪姩閲嶈繛'), findsOneWidget);
    });

    testWidgets('script page separates non-blocking AI notes from failures', (
      tester,
    ) async {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        confidence: 0.87,
        rawResponse:
            '{"schema_version":1,"roles":[{"source_role_id":"slot-0"}]}',
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            displayName: 'Plana',
            confidence: 0.9,
            stages: [
              ScriptAiExtractedStage(
                stageId: 'main-outfit',
                label: 'main outfit',
                identity: 'plana',
                upperBody: 'blue eyes',
                upperClothing: 'school uniform',
                confidence: 0.85,
              ),
            ],
          ),
        ],
        attentionItems: [
          ScriptAiExtractionAttentionItem(
            id: 'merge-failed',
            kind: 'merge_request_failed',
            message: 'AI 瑙掕壊瀛楁璇锋眰澶辫触锛涜姹傜被鍨嬶細merge_extractions',
          ),
          ScriptAiExtractionAttentionItem(
            id: 'black-screen',
            kind: 'parse_failure',
            message: 'Black screen frames are excluded.',
          ),
          ScriptAiExtractionAttentionItem(
            id: 'male-confidence',
            kind: 'low_confidence',
            message: 'Male role lacks specific identity.',
          ),
        ],
      );
      final viewModel = StudioScriptViewModel(
        scriptAiRoleExtractionService: const _FakeRoleExtractionService(
          extraction,
        ),
        scriptAiBaseUrlProvider: () => 'https://script.example/v1',
        scriptAiTokenProvider: () => 'token',
        scriptAiModelProvider: () => 'gpt-4.1-mini',
      );

      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
        await viewModel.generateAiRoleExtraction();
      });
      viewModel.aiProgressTitle = '';
      viewModel.aiProgressSteps = const [];

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      await tester.pumpAndSettle();

      expect(find.textContaining('鍙簲鐢ㄨ崏绋?'), findsOneWidget);
      expect(
        find.textContaining('AI 鍚堝苟璇锋眰鏈畬鎴愶紝宸蹭娇鐢ㄥ垎鍧楃粨鏋滈檷绾у悎骞?'),
        findsOneWidget,
      );
      expect(
        find.text('AI 澶勭悊鎻愰啋锛欱lack screen frames are excluded.'),
        findsOneWidget,
      );
      expect(
        find.text('缃俊搴︽彁閱掞細Male role lacks specific identity.'),
        findsOneWidget,
      );
      expect(find.textContaining('AI 杩斿洖瑙ｆ瀽澶辫触'), findsNothing);
      expect(find.textContaining('瑙掕壊瀛楁鏁寸悊澶辫触'), findsNothing);
      expect(find.textContaining('"schema_version"'), findsNothing);
    });

    testWidgets('script page ignores recast cache recovery on import', (
      tester,
    ) async {
      var caches = [
        RecastScriptCache(
          scriptId: _fixtureScriptId,
          scriptName: 'v4_slotted',
          sourceRootPath: _fixturePath,
          sourceFingerprint: 'old-fingerprint',
          updatedAt: DateTime.utc(2026, 5, 26),
          mapping: RecastMapping.defaults(_fixtureScriptId),
        ),
      ];
      final viewModel = StudioScriptViewModel(
        loadRecastCaches: () async => caches,
        saveRecastCaches: (nextCaches) async {
          caches = nextCaches;
        },
      );
      await tester.runAsync(() async {
        await viewModel.importScriptPath(_fixturePath);
      });

      await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
      expect(viewModel.hasChangedSourceCache, isFalse);
      expect(viewModel.cacheStatus, isNotEmpty);
      expect(
        find.byKey(const ValueKey('use-fresh-recast-parse')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('restore-changed-source-cache')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('reanalyze-with-current-knowledge')),
        findsNothing,
      );
    });
  });
}

Finder _importButton() {
  return find.ancestor(
    of: find.byIcon(Icons.folder_open_outlined),
    matching: find.byType(FilledButton),
  );
}

Finder _studioButtonByIcon(IconData icon) {
  return find.ancestor(
    of: find.byIcon(icon),
    matching: find.byType(FilledButton),
  );
}

const _twoStageSlotExtraction = ScriptAiRoleExtraction(
  status: ScriptAiRoleExtractionStatus.ready,
  confidence: 0.9,
  roles: [
    ScriptAiExtractedRole(
      sourceRoleId: 'slot-0',
      displayName: 'vulpisfoglia_(arknights)',
      confidence: 0.9,
      stages: [
        ScriptAiExtractedStage(
          stageId: 'stage-1',
          label: 'main outfit',
          frameIndexes: [1],
          identity: 'vulpisfoglia_(arknights)',
          upperClothing: 'blue jacket',
          lowerClothing: 'white skirt',
          confidence: 0.9,
        ),
        ScriptAiExtractedStage(
          stageId: 'stage-2',
          label: 'alternate outfit',
          frameIndexes: [2],
          identity: 'vulpisfoglia_(arknights)',
          upperClothing: 'red dress',
          lowerClothing: 'black boots',
          confidence: 0.9,
        ),
      ],
    ),
  ],
);

const _highConfidenceSlotExtraction = ScriptAiRoleExtraction(
  status: ScriptAiRoleExtractionStatus.ready,
  confidence: 0.9,
  roles: [
    ScriptAiExtractedRole(
      sourceRoleId: 'slot-0',
      displayName: 'AI Hero',
      confidence: 0.9,
      stages: [
        ScriptAiExtractedStage(
          stageId: 'main-outfit',
          label: 'main outfit',
          frameIndexes: [1, 2],
          identity: 'ai hero',
          upperBody: 'green eyes',
          lowerBody: 'black boots',
          upperClothing: 'blue jacket',
          lowerClothing: 'white skirt',
          confidence: 0.88,
        ),
      ],
    ),
  ],
);

class _FakeRoleExtractionService implements ScriptAiRoleExtractionService {
  final ScriptAiRoleExtraction extraction;
  final List<Map<String, dynamic>> requestPreviews;
  final int aiRequestCount;

  const _FakeRoleExtractionService(this.extraction)
      : requestPreviews = const [
          {'schema_version': 1, 'request_kind': 'test'},
        ],
        aiRequestCount = 1;

  const _FakeRoleExtractionService.withRequestTrace({
    required this.extraction,
    required this.requestPreviews,
    required this.aiRequestCount,
  });

  @override
  Future<ScriptAiRoleExtractionServiceResult> extractRoles({
    required ScriptAiRoleExtractionServiceRequest request,
  }) async {
    for (final preview in requestPreviews) {
      request.onRequestStarted?.call(preview);
    }
    final requestPreview = requestPreviews.isEmpty
        ? const {'schema_version': 1, 'request_kind': 'test'}
        : requestPreviews.last;
    return ScriptAiRoleExtractionServiceResult(
      extraction: extraction,
      requestPreview: requestPreview,
      aiRequestCount: aiRequestCount,
    );
  }
}

class _RecordingRoleExtractionService implements ScriptAiRoleExtractionService {
  final ScriptAiRoleExtraction extraction;
  final List<int> completedChunkCounts = [];

  _RecordingRoleExtractionService(this.extraction);

  @override
  Future<ScriptAiRoleExtractionServiceResult> extractRoles({
    required ScriptAiRoleExtractionServiceRequest request,
  }) async {
    completedChunkCounts.add(request.completedChunkExtractions.length);
    request.onRequestStarted?.call(const {
      'schema_version': 1,
      'request_kind': 'fresh',
    });
    return ScriptAiRoleExtractionServiceResult(
      extraction: extraction,
      requestPreview: const {'schema_version': 1, 'request_kind': 'fresh'},
      aiRequestCount: 1,
    );
  }
}

class _DeferredRoleExtractionService implements ScriptAiRoleExtractionService {
  final ScriptAiRoleExtraction Function() extractionBuilder;

  const _DeferredRoleExtractionService(this.extractionBuilder);

  @override
  Future<ScriptAiRoleExtractionServiceResult> extractRoles({
    required ScriptAiRoleExtractionServiceRequest request,
  }) async {
    return ScriptAiRoleExtractionServiceResult(
      extraction: extractionBuilder(),
      requestPreview: const {'schema_version': 1},
      aiRequestCount: 1,
    );
  }
}

class _CheckpointingFailureRoleExtractionService
    implements ScriptAiRoleExtractionService {
  const _CheckpointingFailureRoleExtractionService();

  @override
  Future<ScriptAiRoleExtractionServiceResult> extractRoles({
    required ScriptAiRoleExtractionServiceRequest request,
  }) async {
    const checkpoint = ScriptAiRoleExtraction(
      status: ScriptAiRoleExtractionStatus.ready,
      chunkId: 'chunk-1',
      confidence: 0.8,
      roles: [
        ScriptAiExtractedRole(
          sourceRoleId: 'slot-0',
          displayName: 'checkpointed role',
          confidence: 0.8,
        ),
      ],
    );
    await request.onChunkCompleted?.call(checkpoint, const {
      'request_kind': 'chunk_extract_v2',
      'chunk_id': 'chunk-1',
    });
    return ScriptAiRoleExtractionServiceResult(
      extraction: ScriptAiRoleExtraction.failure(
        message: 'chunk-2 failed',
        rawResponse: '',
      ),
      requestPreview: const {
        'request_kind': 'chunk_extract_v2',
        'chunk_id': 'chunk-2',
      },
      aiRequestCount: 2,
    );
  }
}

class _PendingRoleExtractionService implements ScriptAiRoleExtractionService {
  final Map<String, dynamic> startedPreview;

  final Completer<ScriptAiRoleExtractionServiceResult> _completer =
      Completer<ScriptAiRoleExtractionServiceResult>();
  ScriptAiRoleExtractionServiceRequest? _request;

  _PendingRoleExtractionService({this.startedPreview = const {}});

  void emitStreamDelta(ScriptAiRoleExtractionStreamDelta delta) {
    _request?.onStreamDelta?.call(delta);
  }

  void complete(ScriptAiRoleExtractionServiceResult result) {
    if (!_completer.isCompleted) {
      _completer.complete(result);
    }
  }

  @override
  Future<ScriptAiRoleExtractionServiceResult> extractRoles({
    required ScriptAiRoleExtractionServiceRequest request,
  }) {
    _request = request;
    if (startedPreview.isNotEmpty) {
      request.onRequestStarted?.call(startedPreview);
    }
    return _completer.future;
  }
}

class _StartedThrowingRoleExtractionService
    implements ScriptAiRoleExtractionService {
  final Map<String, dynamic> startedPreview;

  const _StartedThrowingRoleExtractionService({required this.startedPreview});

  @override
  Future<ScriptAiRoleExtractionServiceResult> extractRoles({
    required ScriptAiRoleExtractionServiceRequest request,
  }) async {
    request.onRequestStarted?.call(startedPreview);
    throw Exception('timeout');
  }
}

class _FailIfCalledRoleExtractionService
    implements ScriptAiRoleExtractionService {
  const _FailIfCalledRoleExtractionService();

  @override
  Future<ScriptAiRoleExtractionServiceResult> extractRoles({
    required ScriptAiRoleExtractionServiceRequest request,
  }) async {
    throw StateError('AI role extraction service should not be called');
  }
}

class _SlowApplyingViewModel extends StudioScriptViewModel {
  final Completer<void> _applyCompleter = Completer<void>();
  int applyCallCount = 0;

  @override
  Future<void> applyAiRoleExtraction() async {
    if (isApplyingAiRoleExtraction) {
      return;
    }
    isApplyingAiRoleExtraction = true;
    applyCallCount += 1;
    notifyListeners();
    try {
      await _applyCompleter.future;
    } finally {
      isApplyingAiRoleExtraction = false;
      notifyListeners();
    }
  }

  void completeApply() {
    if (!_applyCompleter.isCompleted) {
      _applyCompleter.complete();
    }
  }
}

class _FakeParserService extends ScriptRecastParserService {
  final List<Script> scripts;
  int _index = 0;

  _FakeParserService(this.scripts);

  @override
  Future<Script> parseDirectory(
    Directory directory, {
    ScriptRecastParseProgressCallback? onProgress,
  }) async {
    final script = scripts[_index];
    _index += 1;
    return script;
  }
}

class _PendingProgressParserService extends ScriptRecastParserService {
  final Script script;
  final Completer<void> started = Completer<void>();
  final Completer<void> _complete = Completer<void>();

  _PendingProgressParserService(this.script);

  @override
  Future<Script> parseDirectory(
    Directory directory, {
    ScriptRecastParseProgressCallback? onProgress,
  }) async {
    onProgress?.call(
      const ScriptRecastParseProgress(
        phase: ScriptRecastParseProgressPhase.sourceParsed,
        totalSources: 3,
        visitedSources: 1,
        parsedFrames: 1,
        fileName: 'p000.png',
      ),
    );
    if (!started.isCompleted) {
      started.complete();
    }
    await _complete.future;
    onProgress?.call(
      ScriptRecastParseProgress(
        phase: ScriptRecastParseProgressPhase.complete,
        totalSources: 3,
        visitedSources: 3,
        parsedFrames: script.frames.length,
      ),
    );
    return script;
  }

  void complete() {
    if (!_complete.isCompleted) {
      _complete.complete();
    }
  }
}

class _CountingRecastEngine extends ScriptRecastEngine {
  int resolveCallCount = 0;
  int frameResolveCallCount = 0;
  RecastMapping? lastMapping;

  @override
  ScriptRecastFramePayload resolveFramePayload({
    required Script script,
    required ScriptFrame frame,
    required RecastMapping mapping,
    required List<CharacterEntry> characters,
    required List<ArtistChain> artistChains,
    String globalBlockWords = '',
    String globalPromptPrefix = '',
    FilterRuleConfig? filterRuleConfig,
  }) {
    frameResolveCallCount += 1;
    lastMapping = mapping;
    return super.resolveFramePayload(
      script: script,
      frame: frame,
      mapping: mapping,
      characters: characters,
      artistChains: artistChains,
      globalBlockWords: globalBlockWords,
      globalPromptPrefix: globalPromptPrefix,
      filterRuleConfig: filterRuleConfig,
    );
  }

  @override
  ScriptRecastResult resolvePayloads({
    required Script script,
    required RecastMapping mapping,
    required List<CharacterEntry> characters,
    required List<ArtistChain> artistChains,
    String globalBlockWords = '',
    String globalPromptPrefix = '',
    FilterRuleConfig? filterRuleConfig,
  }) {
    resolveCallCount += 1;
    lastMapping = mapping;
    return super.resolvePayloads(
      script: script,
      mapping: mapping,
      characters: characters,
      artistChains: artistChains,
      globalBlockWords: globalBlockWords,
      globalPromptPrefix: globalPromptPrefix,
      filterRuleConfig: filterRuleConfig,
    );
  }

  @override
  Future<ScriptRecastResult> resolvePayloadsAsync({
    required Script script,
    required RecastMapping mapping,
    required List<CharacterEntry> characters,
    required List<ArtistChain> artistChains,
    String globalBlockWords = '',
    String globalPromptPrefix = '',
    FilterRuleConfig? filterRuleConfig,
    int yieldEveryFrames = 12,
  }) {
    resolveCallCount += 1;
    lastMapping = mapping;
    return super.resolvePayloadsAsync(
      script: script,
      mapping: mapping,
      characters: characters,
      artistChains: artistChains,
      globalBlockWords: globalBlockWords,
      globalPromptPrefix: globalPromptPrefix,
      filterRuleConfig: filterRuleConfig,
      yieldEveryFrames: yieldEveryFrames,
    );
  }
}

class _PendingProductionService extends ScriptRecastProductionService {
  final Completer<void> _completer = Completer<void>();
  int enqueueCount = 0;

  _PendingProductionService({required super.queueService})
      : super(now: DateTime.now);

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  @override
  Future<ProductionPlan> enqueueRecastResult({
    required ScriptRecastResult result,
    required String planId,
    required String planName,
    required String recastRunId,
    String? scriptName,
    String? scriptPath,
  }) async {
    enqueueCount += 1;
    await _completer.future;
    return super.enqueueRecastResult(
      result: result,
      planId: planId,
      planName: planName,
      recastRunId: recastRunId,
      scriptName: scriptName,
      scriptPath: scriptPath,
    );
  }
}

class _ThrowingParserService extends ScriptRecastParserService {
  @override
  Future<Script> parseDirectory(
    Directory directory, {
    ScriptRecastParseProgressCallback? onProgress,
  }) async {
    throw StateError('parser exploded');
  }
}

class _ImmediateCaptureService extends StudioAssetCaptureService {
  _ImmediateCaptureService() : super(workspaceService: WorkspaceService());

  @override
  Future<StudioAssetCapturePlan> previewSave(
    StudioAssetCaptureDraft draft,
  ) async {
    return StudioAssetCapturePlan(draft: draft);
  }

  @override
  Future<StudioAssetCaptureResult> save(
    StudioAssetCaptureDraft draft, {
    String? targetId,
    bool forceNew = false,
    String? nameOverride,
    String? noteOverride,
  }) async {
    return StudioAssetCaptureResult(
      kind: draft.kind,
      savedId: 'saved-asset',
      name: nameOverride ?? draft.name,
      merged: false,
    );
  }
}

Script _scriptWithChangedSameLengthRawJson(Script script) {
  final firstFrame = script.frames.first;
  final changedRawJson = _sameLengthDifferentText(firstFrame.rawJson);
  return Script(
    id: script.id,
    name: script.name,
    rootPath: script.rootPath,
    detectedSchema: script.detectedSchema,
    parseWarnings: script.parseWarnings,
    meta: script.meta,
    frames: [
      ScriptFrame(
        index: firstFrame.index,
        fileName: firstFrame.fileName,
        sourcePath: firstFrame.sourcePath,
        rawJson: changedRawJson,
        parsed: firstFrame.parsed,
        detectedSchema: firstFrame.detectedSchema,
        parseStatus: firstFrame.parseStatus,
        warnings: firstFrame.warnings,
      ),
      ...script.frames.skip(1),
    ],
  );
}

String _sameLengthDifferentText(String value) {
  final codeUnits = value.codeUnits.toList();
  codeUnits[0] = codeUnits[0] == 123 ? 91 : 123;
  return String.fromCharCodes(codeUnits);
}

Script _largeScript({required int frameCount, required int roleSlots}) {
  return Script(
    id: 'large-script',
    name: 'Large Script',
    rootPath: r'C:\scripts\large-script',
    detectedSchema: ScriptSchema.v4Slotted,
    frames: [
      for (var index = 1; index <= frameCount; index += 1)
        ScriptFrame(
          index: index,
          fileName: 'nai_$index.json',
          sourcePath: r'C:\scripts\large-script\nai_$index.json',
          rawJson: '{"index":$index}',
          parsed: ParsedFrame(
            baseCaption: 'artist:source_artist, city lights, frame $index',
            charCaptions: [
              for (var slot = 0; slot < roleSlots; slot += 1)
                'source_role_$slot, source outfit $index, standing',
            ],
            negativeBase: 'lowres',
            negativeCharCaptions: [
              for (var slot = 0; slot < roleSlots; slot += 1) 'bad hands',
            ],
            generationParams: const {'seed': 123},
            sourcePayload: {
              'Comment': {
                'v4_prompt': {
                  'caption': {
                    'base_caption': 'artist:source_artist, city lights',
                    'char_captions': [
                      for (var slot = 0; slot < roleSlots; slot += 1)
                        {'char_caption': ''},
                    ],
                  },
                },
                'v4_negative_prompt': {
                  'caption': {
                    'base_caption': 'lowres',
                    'char_captions': [
                      for (var slot = 0; slot < roleSlots; slot += 1)
                        {'char_caption': ''},
                    ],
                  },
                },
              },
            },
          ),
          detectedSchema: ScriptSchema.v4Slotted,
          parseStatus: ScriptFrameParseStatus.parsed,
        ),
    ],
  );
}

Script _singleFrameScript({
  required String baseCaption,
  List<String> charCaptions = const [],
  Map<String, dynamic> generationParams = const {'seed': 123},
  String id = 'single-frame-script',
  String name = 'Single Frame Script',
  String rootPath = r'C:\scripts\single-frame-script',
}) {
  return Script(
    id: id,
    name: name,
    rootPath: rootPath,
    detectedSchema: ScriptSchema.v4Slotted,
    frames: [
      ScriptFrame(
        index: 1,
        fileName: 'nai_1.json',
        sourcePath: '$rootPath\\nai_1.json',
        rawJson: '{"index":1}',
        parsed: ParsedFrame(
          baseCaption: baseCaption,
          charCaptions: charCaptions,
          generationParams: generationParams,
          sourcePayload: {
            'Comment': {
              'v4_prompt': {
                'caption': {
                  'base_caption': baseCaption,
                  'char_captions': [
                    for (final caption in charCaptions)
                      {'char_caption': caption},
                  ],
                },
              },
            },
          },
        ),
        detectedSchema: ScriptSchema.v4Slotted,
        parseStatus: ScriptFrameParseStatus.parsed,
      ),
    ],
  );
}

Script _scriptWithFrames(
  List<({int index, String base, List<String> chars})> frames, {
  String id = 'script-stage-non-role',
  String name = 'Stage Non-role Script',
  String rootPath = 'stage-non-role-script',
}) {
  return Script(
    id: id,
    name: name,
    rootPath: rootPath,
    detectedSchema: ScriptSchema.v4Slotted,
    frames: [
      for (final frame in frames)
        ScriptFrame(
          index: frame.index,
          fileName: 'nai_${frame.index}.json',
          sourcePath: '$rootPath\\nai_${frame.index}.json',
          rawJson: '{"index":${frame.index}}',
          parsed: ParsedFrame(
            baseCaption: frame.base,
            charCaptions: frame.chars,
            generationParams: const {'seed': 123},
            sourcePayload: {
              'Comment': {
                'v4_prompt': {
                  'caption': {
                    'base_caption': frame.base,
                    'char_captions': [
                      for (final caption in frame.chars)
                        {'char_caption': caption},
                    ],
                  },
                },
              },
            },
          ),
          detectedSchema: ScriptSchema.v4Slotted,
          parseStatus: ScriptFrameParseStatus.parsed,
        ),
    ],
  );
}

String _testSourceFingerprint(Script script) {
  final parts = [
    script.id,
    script.rootPath,
    for (final frame in script.frames)
      '${frame.index}:${frame.fileName}:${frame.sourcePath}:'
          '${_testStableContentHash(frame.rawJson)}',
  ];
  return parts.join('|');
}

String _normalizedSourceFingerprintForTest(Script script) {
  String normalize(String value) =>
      value.trim().replaceAll('\\', '/').toLowerCase();

  final parts = [
    script.id,
    normalize(script.rootPath),
    for (final frame in script.frames)
      '${frame.index}:${frame.fileName}:${normalize(frame.sourcePath)}:'
          '${_testStableContentHash(frame.rawJson)}',
  ];
  return parts.join('|');
}

String _testStableContentHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
