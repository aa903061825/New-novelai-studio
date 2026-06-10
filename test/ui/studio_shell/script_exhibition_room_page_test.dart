import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/studio/models/production_task.dart';
import 'package:nai_casrand/data/studio/models/studio_asset_capture.dart';
import 'package:nai_casrand/data/studio/models/studio_gallery_record.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_capture_service.dart';
import 'package:nai_casrand/data/studio/models/tokenizer_script.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_classifier.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/core/app_display_settings.dart';
import 'package:nai_casrand/ui/studio_core/widgets/prompt_tag_display.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_asset_capture_host.dart';
import 'package:nai_casrand/ui/studio_shell/view_models/script_exhibition_room_viewmodel.dart';
import 'package:nai_casrand/ui/studio_shell/widgets/script_exhibition_room_page.dart';

class _PreviewCaptureService extends StudioAssetCaptureService {
  _PreviewCaptureService() : super(workspaceService: WorkspaceService());

  StudioAssetCaptureDraft? previewedDraft;

  @override
  Future<StudioAssetCapturePlan> previewSave(
    StudioAssetCaptureDraft draft,
  ) async {
    previewedDraft = draft;
    return StudioAssetCapturePlan(draft: draft);
  }
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
    AppDisplaySettings.setImagePreviewDialogHeight(
      AppDisplaySettings.defaultImagePreviewDialogHeight,
      persist: false,
    );
  });

  tearDown(() async {
    AppDisplaySettings.setImagePreviewDialogHeight(
      AppDisplaySettings.defaultImagePreviewDialogHeight,
      persist: false,
    );
    await GetIt.I.reset();
  });

  testWidgets('browses versions, previews an image, and sends focus', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sentScriptFocuses = <ScriptExhibitionFocus>[];
    final sentWorkbenchFocuses = <ScriptExhibitionFocus>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: ScriptExhibitionRoomPage(
          viewModel: viewModel,
          onSendToScriptWorkbench: sentScriptFocuses.add,
          onSendToWorkbench: sentWorkbenchFocuses.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('script-exhibition-room-page')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
      findsOneWidget,
    );
    expect(find.text('雨夜档案'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('script-exhibition-detail-script-1')),
      findsOneWidget,
    );
    expect(find.text('发送到剧本工作台'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey('script-exhibition-detail-send-script-workbench'),
      ),
    );
    await tester.pumpAndSettle();
    expect(sentScriptFocuses, hasLength(1));
    expect(sentScriptFocuses.single.scriptId, 'script-1');
    expect(sentScriptFocuses.single.sourceFolder, r'C:\stories\rain');

    expect(
      find.byKey(const ValueKey('script-exhibition-version-production-plan-1')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-version-production-plan-1')),
    );
    await tester.pumpAndSettle();

    final generatedCard = find.byKey(
      const ValueKey('script-exhibition-item-production-plan-1-task-1'),
    );
    expect(generatedCard, findsOneWidget);
    expect(find.text('新图: 入口雨幕'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey(
          'script-exhibition-send-workbench-production-plan-1-task-1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sentWorkbenchFocuses, hasLength(1));
    expect(sentWorkbenchFocuses.single.imagePath, r'C:\out\frame-01.png');
    expect(sentScriptFocuses, hasLength(1));

    await tester.tap(generatedCard);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('script-exhibition-fullscreen-preview')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('script-exhibition-fullscreen-preview')),
        matching: find.byType(PromptTagDisplay),
      ),
      findsOneWidget,
    );
    expect(find.text('library entrance'), findsWidgets);
    expect(find.text('generated heroine'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-preview-send')),
    );
    await tester.pumpAndSettle();

    expect(sentWorkbenchFocuses, hasLength(2));
    expect(sentWorkbenchFocuses.last.scriptId, 'script-1');
    expect(sentWorkbenchFocuses.last.sourceFolder, r'C:\stories\rain');
    expect(sentWorkbenchFocuses.last.frameIndex, 1);
    expect(sentWorkbenchFocuses.last.productionPlanId, 'plan-1');
    expect(sentWorkbenchFocuses.last.imagePath, r'C:\out\frame-01.png');
  });

  testWidgets('original image preview keeps prompt untranslated by default', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: ScriptExhibitionRoomPage(
          viewModel: viewModel,
          onSendToScriptWorkbench: (_) {},
          onSendToWorkbench: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey(
          'script-exhibition-item-original-script-1-source-task-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tagDisplay = tester.widget<PromptTagDisplay>(
      find.byKey(
        const ValueKey(
          'script-exhibition-preview-prompt-tags-original-script-1-source-task-1',
        ),
      ),
    );
    expect(tagDisplay.defaultTranslated, isFalse);
  });

  testWidgets('large version shelves build only visible waterfall cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_largePlan()],
      loadGalleryRecords: () async => const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: ScriptExhibitionRoomPage(
          viewModel: viewModel,
          onSendToScriptWorkbench: (_) {},
          onSendToWorkbench: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-version-production-large')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('script-exhibition-item-production-large-task-1'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('script-exhibition-item-production-large-task-80'),
      ),
      findsNothing,
    );
  });

  testWidgets('sends production-only images to the single-image workbench', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sentScriptFocuses = <ScriptExhibitionFocus>[];
    final sentWorkbenchFocuses = <ScriptExhibitionFocus>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => const [],
      loadProductionPlans: () async => [_planWithoutScriptPath()],
      loadGalleryRecords: () async => const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: ScriptExhibitionRoomPage(
          viewModel: viewModel,
          onSendToScriptWorkbench: sentScriptFocuses.add,
          onSendToWorkbench: sentWorkbenchFocuses.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-version-production-plan-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('script-exhibition-item-production-plan-1-task-1'),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('script-exhibition-preview-send')),
    );
    expect(button.onPressed, isNotNull);

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-preview-send')),
    );
    await tester.pumpAndSettle();
    expect(sentScriptFocuses, isEmpty);
    expect(sentWorkbenchFocuses.single.imagePath, r'C:\out\frame-01.png');
  });

  testWidgets('preview opens fit-to-window, enters fullscreen, and navigates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_planWithTwoCompletedImages()],
      loadGalleryRecords: () async => const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: ScriptExhibitionRoomPage(
          viewModel: viewModel,
          onSendToScriptWorkbench: (_) {},
          onSendToWorkbench: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-version-production-plan-2')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('script-exhibition-item-production-plan-2-task-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('script-exhibition-zoomable-image-viewer')),
      findsOneWidget,
    );
    expect(find.text('first generated frame'), findsWidgets);
    expect(find.text('second generated frame'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-preview-fullscreen-toggle')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('script-exhibition-image-viewer-fullscreen')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('script-exhibition-image-viewer-fullscreen'),
        ),
        matching: find.byType(PromptTagDisplay),
      ),
      findsNothing,
    );
    expect(find.text('first generated frame'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(find.textContaining('2/2'), findsOneWidget);
    expect(find.text('second generated frame'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(find.textContaining('1/2'), findsOneWidget);
    expect(find.text('first generated frame'), findsNothing);
  });

  testWidgets(
    'windowed preview translates tags and reserves readable prompt space',
    (tester) async {
      tester.view.physicalSize = const Size(1320, 1260);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppDisplaySettings.setImagePreviewDialogHeight(880, persist: false);

      final viewModel = ScriptExhibitionRoomViewModel(
        loadScripts: () async => [_script()],
        loadProductionPlans: () async => [_planWithLongPrompt()],
        loadGalleryRecords: () async => const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.build(),
          home: ScriptExhibitionRoomPage(
            viewModel: viewModel,
            onSendToScriptWorkbench: (_) {},
            onSendToWorkbench: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('script-exhibition-version-production-plan-3'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('script-exhibition-item-production-plan-3-task-1'),
        ),
      );
      await tester.pumpAndSettle();

      final tagDisplay = tester.widget<PromptTagDisplay>(
        find.byKey(
          const ValueKey(
            'script-exhibition-preview-prompt-tags-production-plan-3-task-1',
          ),
        ),
      );
      expect(tagDisplay.defaultTranslated, isTrue);

      final windowHeight = tester
          .getSize(
            find.byKey(
              const ValueKey('script-exhibition-image-viewer-windowed'),
            ),
          )
          .height;
      final imageHeight = tester
          .getSize(
            find.byKey(
              const ValueKey('script-exhibition-zoomable-image-viewer'),
            ),
          )
          .height;
      final promptHeight = tester
          .getSize(
            find.byKey(
              const ValueKey('script-exhibition-preview-prompt-scroll'),
            ),
          )
          .height;
      expect(windowHeight, 880);
      expect(imageHeight, greaterThan(420));
      expect(promptHeight, greaterThanOrEqualTo(300));
      expect(promptHeight, lessThanOrEqualTo(320));
    },
  );

  testWidgets('fills the available page width on wide screens', (tester) async {
    tester.view.physicalSize = const Size(1800, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: ScriptExhibitionRoomPage(
          viewModel: viewModel,
          onSendToScriptWorkbench: (_) {},
          onSendToWorkbench: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final headerSize = tester.getSize(
      find.byKey(const ValueKey('script-exhibition-header')),
    );
    expect(headerSize.width, greaterThan(1700));
  });

  testWidgets('imports a script folder from the room header', (tester) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var scripts = <TokenizerScript>[];
    var imported = false;
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      importScriptFolder: () async {
        imported = true;
        scripts = [_script()];
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: ScriptExhibitionRoomPage(
          viewModel: viewModel,
          onSendToScriptWorkbench: (_) {},
          onSendToWorkbench: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-import-script')),
    );
    await tester.pumpAndSettle();

    expect(imported, isTrue);
    expect(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
      findsOneWidget,
    );
  });

  testWidgets('needs-action metric opens the pending production version', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_planWithFailedAction()],
      loadGalleryRecords: () async => const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: ScriptExhibitionRoomPage(
          viewModel: viewModel,
          onSendToScriptWorkbench: (_) {},
          onSendToWorkbench: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey(
          'script-exhibition-category-${ScriptExhibitionRoomViewModel.needsActionCategoryId}',
        ),
      ),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-metric-needs-action')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('script-exhibition-detail-script-1')),
      findsOneWidget,
    );

    final versionChip = tester.widget<ChoiceChip>(
      find.byKey(
        const ValueKey('script-exhibition-version-production-plan-failed'),
      ),
    );
    expect(versionChip.selected, isTrue);

    final needsActionChip = tester.widget<ChoiceChip>(
      find.byKey(
        const ValueKey(
          'script-exhibition-detail-filter-${ScriptExhibitionRoomViewModel.needsActionDetailFilterId}',
        ),
      ),
    );
    expect(needsActionChip.selected, isTrue);
    expect(
      find.byKey(
        const ValueKey(
          'script-exhibition-item-production-plan-failed-task-failed',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'script-exhibition-item-production-plan-failed-task-completed',
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('imports and renames images under the selected script', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var scripts = [_script()];
    final importedScripts = <String>[];
    final renamedLabels = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      importScriptImages: (script) async {
        importedScripts.add(script.scriptId);
        scripts = [
          scripts.single.copyWith(
            imageAttachments: [
              TokenizerScriptImageAttachment(
                attachmentId: 'attachment-1',
                imagePath: r'C:\stories\rain\manual_001.png',
                label: 'Default 1',
                frameIndex: 1,
                sourceFileName: '001.json',
                createdAt: DateTime.parse('2026-06-03T10:00:00Z'),
              ),
            ],
          ),
        ];
      },
      renameImageAttachment: (item, label) async {
        renamedLabels.add(label);
        scripts = [
          scripts.single.copyWith(
            imageAttachments: [
              TokenizerScriptImageAttachment(
                attachmentId: item.imageAttachmentId!,
                imagePath: item.imagePath,
                label: label,
                frameIndex: item.frameIndex,
                sourceFileName: item.sourceFileName,
                createdAt: item.updatedAt,
              ),
            ],
          ),
        ];
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: ScriptExhibitionRoomPage(
          viewModel: viewModel,
          onSendToScriptWorkbench: (_) {},
          onSendToWorkbench: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-import-script-images')),
    );
    await tester.pumpAndSettle();
    expect(importedScripts, ['script-1']);

    await tester.tap(
      find.byKey(
        const ValueKey(
          'script-exhibition-version-${ScriptExhibitionVersion.attachmentsId}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final itemKey = const ValueKey(
      'script-exhibition-item-attachment-script-1-attachment-1',
    );
    expect(find.byKey(itemKey), findsOneWidget);
    expect(find.text('Default 1'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey(
          'script-exhibition-rename-item-attachment-script-1-attachment-1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('script-exhibition-rename-label-field')),
      'Role swap 2',
    );
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-confirm-rename-item')),
    );
    await tester.pumpAndSettle();

    expect(renamedLabels, ['Role swap 2']);
    expect(find.text('Role swap 2'), findsOneWidget);
  });

  testWidgets('renames a script from the shelf context menu', (tester) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var scripts = [_script()];
    final renamedLabels = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      renameScriptRecord: (script, label) async {
        renamedLabels.add(label);
        scripts = [scripts.single.copyWith(name: label)];
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: ScriptExhibitionRoomPage(
          viewModel: viewModel,
          onSendToScriptWorkbench: (_) {},
          onSendToWorkbench: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(
      const ValueKey('script-exhibition-script-card-script-1'),
    );
    await tester.tapAt(tester.getCenter(card), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名剧本'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('script-exhibition-rename-label-field')),
      'Renamed Script',
    );
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-confirm-rename-script')),
    );
    await tester.pumpAndSettle();

    expect(renamedLabels, ['Renamed Script']);
    expect(find.text('Renamed Script'), findsOneWidget);
  });

  testWidgets('renames a script from the detail title context menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var scripts = [_script()];
    final renamedLabels = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      renameScriptRecord: (script, label) async {
        renamedLabels.add(label);
        scripts = [scripts.single.copyWith(name: label)];
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: ScriptExhibitionRoomPage(
          viewModel: viewModel,
          onSendToScriptWorkbench: (_) {},
          onSendToWorkbench: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('script-exhibition-rename-script-title-script-1'),
      ),
      findsNothing,
    );

    final title = find.byKey(
      const ValueKey('script-exhibition-detail-title-script-1'),
    );
    await tester.tapAt(tester.getCenter(title), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名剧本'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('script-exhibition-rename-label-field')),
      'Renamed From Detail',
    );
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-confirm-rename-script')),
    );
    await tester.pumpAndSettle();

    expect(renamedLabels, ['Renamed From Detail']);
    expect(find.text('Renamed From Detail'), findsOneWidget);
  });

  testWidgets('renames a version chip from its context menu', (tester) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var scripts = [_script()];
    final renamedVersions = <String, String>{};
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => [_galleryRecord()],
      renameVersionLabel: (script, version, label) async {
        renamedVersions[version.id] = label;
        scripts = [
          scripts.single.copyWith(
            exhibitionVersionLabels: {
              ...scripts.single.exhibitionVersionLabels,
              version.id: label,
            },
          ),
        ];
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: ScriptExhibitionRoomPage(
          viewModel: viewModel,
          onSendToScriptWorkbench: (_) {},
          onSendToWorkbench: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
    );
    await tester.pumpAndSettle();

    final galleryVersion = find.byKey(
      const ValueKey('script-exhibition-version-gallery'),
    );
    await tester.tapAt(
      tester.getCenter(galleryVersion),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名版本'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('script-exhibition-rename-label-field')),
      '精选收纳',
    );
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-confirm-rename-version')),
    );
    await tester.pumpAndSettle();

    expect(renamedVersions, {ScriptExhibitionVersion.galleryId: '精选收纳'});
    expect(find.text('精选收纳 1'), findsOneWidget);
  });

  testWidgets('assigns one script to a custom category from the shelf menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var scripts = [
      _script(),
      _script().copyWith(
        scriptId: 'script-2',
        name: '旁支档案',
        sourceFolder: r'C:\stories\branch',
      ),
    ];
    final assignments = <String, String>{};
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      assignScriptCategory: (script, categoryName) async {
        assignments[script.scriptId] = categoryName;
        scripts = [
          for (final existing in scripts)
            existing.scriptId == script.scriptId
                ? existing.copyWith(categoryNames: [categoryName])
                : existing,
        ];
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: ScriptExhibitionRoomPage(
          viewModel: viewModel,
          onSendToScriptWorkbench: (_) {},
          onSendToWorkbench: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final secondCard = find.byKey(
      const ValueKey('script-exhibition-script-card-script-2'),
    );
    await tester.tapAt(
      tester.getCenter(secondCard),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('归入分类...'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('script-exhibition-category-name-field')),
      '收藏馆区',
    );
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-confirm-category')),
    );
    await tester.pumpAndSettle();

    expect(assignments, {'script-2': '收藏馆区'});
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-category-custom:收藏馆区')),
    );
    await tester.pumpAndSettle();

    expect(find.text('旁支档案'), findsOneWidget);
    expect(find.text('雨夜档案'), findsNothing);
  });

  testWidgets('deletes an entire script exhibition record', (tester) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var scripts = [_script()];
    var plans = [_plan()];
    var records = [_galleryRecord()];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => plans,
      loadGalleryRecords: () async => records,
      deleteScriptRecord: (script) async {
        scripts = const [];
        plans = const [];
        records = const [];
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: ScriptExhibitionRoomPage(
          viewModel: viewModel,
          onSendToScriptWorkbench: (_) {},
          onSendToWorkbench: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-delete-script-script-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-confirm-delete-script')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
      findsNothing,
    );
  });

  testWidgets('deletes a gallery item from the waterfall', (tester) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var records = [_galleryRecord()];
    final deletedItems = <ScriptExhibitionItem>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => records,
      deleteItemRecord: (item) async {
        deletedItems.add(item);
        records = records
            .where((record) => record.id != item.galleryRecordId)
            .toList(growable: false);
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: ScriptExhibitionRoomPage(
          viewModel: viewModel,
          onSendToScriptWorkbench: (_) {},
          onSendToWorkbench: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-version-gallery')),
    );
    await tester.pumpAndSettle();

    final itemKey = const ValueKey('script-exhibition-item-gallery-gallery-1');
    expect(find.byKey(itemKey), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey('script-exhibition-delete-item-gallery-gallery-1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-confirm-delete-item')),
    );
    await tester.pumpAndSettle();

    expect(deletedItems.single.galleryRecordId, 'gallery-1');
    expect(find.byKey(itemKey), findsNothing);
  });

  testWidgets(
    'shows save-as-asset for structured script gallery artist chains',
    (tester) async {
      tester.view.physicalSize = const Size(1320, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final viewModel = ScriptExhibitionRoomViewModel(
        loadScripts: () async => [_script()],
        loadProductionPlans: () async => [_plan()],
        loadGalleryRecords: () async => [
          _galleryRecord(
            payload: const {
              'input': 'artist:raw_input_is_not_used_for_capture',
              'parameters': {
                'v4_prompt': {
                  'caption': {
                    'base_caption': 'artist:ahemaru, watercolor, library',
                  },
                },
              },
            },
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.build(),
          home: ScriptExhibitionRoomPage(
            viewModel: viewModel,
            onSendToScriptWorkbench: (_) {},
            onSendToWorkbench: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('script-exhibition-version-production-plan-1'),
        ),
      );
      await tester.pumpAndSettle();

      final saveAction = find.byKey(
        const ValueKey(
          'script-exhibition-save-asset-production-plan-1-task-1-'
          'artist-chain-0',
        ),
      );
      expect(saveAction, findsOneWidget);
      expect(
        find.descendant(of: saveAction, matching: find.text('保存素材')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'preview shows save-as-asset for structured production artist chains',
    (tester) async {
      tester.view.physicalSize = const Size(1320, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final viewModel = ScriptExhibitionRoomViewModel(
        loadScripts: () async => [_script()],
        loadProductionPlans: () async => [_planWithStructuredV4Prompt()],
        loadGalleryRecords: () async => const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.build(),
          home: ScriptExhibitionRoomPage(
            viewModel: viewModel,
            onSendToScriptWorkbench: (_) {},
            onSendToWorkbench: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey(
            'script-exhibition-version-production-plan-structured',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey(
            'script-exhibition-item-production-plan-structured-task-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey(
            'script-exhibition-save-asset-preview-production-plan-structured-'
            'task-1-artist-chain-0',
          ),
        ),
        findsNothing,
      );
      final saveAction = find.byKey(
        const ValueKey(
          'script-exhibition-preview-prompt-save-asset-production-plan-structured-'
          'task-1-artist-chain-0',
        ),
      );
      expect(saveAction, findsOneWidget);
      expect(
        find.descendant(of: saveAction, matching: find.text('保存为素材')),
        findsOneWidget,
      );
    },
  );

  testWidgets('script preview save uses current artist block tags', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final classificationCache = PromptTagClassificationCache(
      clock: () => 1710000000,
    )..setCategory(
        'watercolor',
        PromptTagCategory.artist,
        source: 'manual-drag',
      );
    GetIt.I.registerSingleton<PromptTagClassificationCache>(
      classificationCache,
    );
    final captureService = _PreviewCaptureService();
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_planWithStructuredV4Prompt()],
      loadGalleryRecords: () async => const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioAssetCaptureHost(
          service: captureService,
          child: ScriptExhibitionRoomPage(
            viewModel: viewModel,
            onSendToScriptWorkbench: (_) {},
            onSendToWorkbench: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('script-exhibition-version-production-plan-structured'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey(
          'script-exhibition-item-production-plan-structured-task-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final saveAction = find.byKey(
      const ValueKey(
        'script-exhibition-preview-prompt-save-asset-production-plan-structured-'
        'task-1-artist-chain-0',
      ),
    );
    expect(saveAction, findsOneWidget);

    await tester.tap(saveAction);
    await tester.pump();

    final chain = captureService.previewedDraft?.artistChain;
    expect(chain?.tags, ['artist:ahemaru', 'watercolor']);
    expect(chain?.styleTags, isEmpty);
    expect(chain?.prompt, 'artist:ahemaru, watercolor');
  });

  testWidgets('original script preview shows save-as-asset for visible artists',
      (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_scriptWithBareArtistPrompt()],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: ScriptExhibitionRoomPage(
          viewModel: viewModel,
          onSendToScriptWorkbench: (_) {},
          onSendToWorkbench: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey(
          'script-exhibition-item-original-script-1-source-task-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey(
          'script-exhibition-save-asset-preview-original-script-1-source-task-1-'
          'artist-chain-0',
        ),
      ),
      findsNothing,
    );
    final saveAction = find.byKey(
      const ValueKey(
        'script-exhibition-preview-prompt-save-asset-original-script-1-source-task-1-'
        'artist-chain-0',
      ),
    );
    expect(saveAction, findsOneWidget);
    expect(
      find.descendant(of: saveAction, matching: find.text('保存为素材')),
      findsOneWidget,
    );
  });
}

TokenizerScript _script() {
  final now = DateTime.parse('2026-06-01T09:00:00Z');
  const source = TokenizerSourceFile(
    fileId: 'source-1',
    fileName: '001.json',
    path: r'C:\stories\rain\001.json',
    kind: TokenizerScriptSourceKind.json,
  );
  return TokenizerScript(
    scriptId: 'script-1',
    name: '雨夜档案',
    sourceFolder: r'C:\stories\rain',
    sourceMode: TokenizerScriptSourceMode.auto,
    createdAt: now,
    updatedAt: now,
    status: TokenizerScriptStatus.ready,
    sourceFiles: const [source],
    sampleFileIds: const ['source-1'],
    characterIdentities: const [],
    styleStages: const [],
    knowledgeCandidates: const [],
    imageTasks: const [
      TokenizerImageTask(
        taskId: 'source-task-1',
        sourceFile: source,
        parseStatus: 'parsed',
        originalPrompt: 'library entrance, rainy night',
        promptMode: TokenizerScriptPromptMode.tag,
        parsedPrompt: 'library entrance, rainy night',
        finalPrompt: 'library entrance, rainy night',
        artistEvidence: [],
        characterSlotMatches: [],
        confidence: 0.9,
        reviewStatus: TokenizerTaskReviewStatus.confirmed,
        details: TokenizerParseDetails(),
      ),
    ],
  );
}

TokenizerScript _scriptWithBareArtistPrompt() {
  final now = DateTime.parse('2026-06-01T09:00:00Z');
  const source = TokenizerSourceFile(
    fileId: 'source-1',
    fileName: '001.json',
    path: r'C:\stories\rain\001.json',
    kind: TokenizerScriptSourceKind.json,
  );
  const prompt =
      '1girl, arato_asato, ratatatat74, artist collaboration, bedroom';
  return TokenizerScript(
    scriptId: 'script-1',
    name: '雨夜档案',
    sourceFolder: r'C:\stories\rain',
    sourceMode: TokenizerScriptSourceMode.auto,
    createdAt: now,
    updatedAt: now,
    status: TokenizerScriptStatus.ready,
    sourceFiles: const [source],
    sampleFileIds: const ['source-1'],
    characterIdentities: const [],
    styleStages: const [],
    knowledgeCandidates: const [],
    imageTasks: const [
      TokenizerImageTask(
        taskId: 'source-task-1',
        sourceFile: source,
        parseStatus: 'parsed',
        originalPrompt: prompt,
        promptMode: TokenizerScriptPromptMode.tag,
        parsedPrompt: prompt,
        finalPrompt: prompt,
        artistEvidence: [],
        characterSlotMatches: [],
        confidence: 0.9,
        reviewStatus: TokenizerTaskReviewStatus.confirmed,
        details: TokenizerParseDetails(),
      ),
    ],
  );
}

ProductionPlan _plan() {
  final now = DateTime.parse('2026-06-02T08:00:00Z');
  return ProductionPlan(
    id: 'plan-1',
    name: '主角版 A',
    createdAt: now,
    updatedAt: now,
    tasks: [
      ProductionTask.scriptRecastFrame(
        id: 'task-1',
        planId: 'plan-1',
        title: '入口雨幕',
        scriptId: 'script-1',
        scriptName: '雨夜档案',
        scriptPath: r'C:\stories\rain',
        recastRunId: 'run-1',
        frameIndex: 1,
        sourceFileName: '001.json',
        payload: const {'input': 'library entrance, generated heroine'},
        status: ProductionTaskStatus.completed,
        outputImagePath: r'C:\out\frame-01.png',
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
}

ProductionPlan _planWithStructuredV4Prompt() {
  final now = DateTime.parse('2026-06-02T08:00:00Z');
  return ProductionPlan(
    id: 'plan-structured',
    name: 'Structured Prompt',
    createdAt: now,
    updatedAt: now,
    tasks: [
      ProductionTask.scriptRecastFrame(
        id: 'task-1',
        planId: 'plan-structured',
        title: 'Structured Frame',
        scriptId: 'script-1',
        scriptName: 'Rain Archive',
        scriptPath: r'C:\stories\rain',
        recastRunId: 'run-structured',
        frameIndex: 1,
        sourceFileName: '001.json',
        payload: const {
          'input': 'plain prompt text is display-only',
          'parameters': {
            'v4_prompt': {
              'caption': {
                'base_caption': 'artist:ahemaru, watercolor, library',
                'char_captions': [
                  {'char_caption': '1girl, fox ears'},
                ],
              },
            },
          },
        },
        status: ProductionTaskStatus.completed,
        outputImagePath: r'C:\out\structured-frame-01.png',
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
}

ProductionPlan _planWithFailedAction() {
  final now = DateTime.parse('2026-06-02T08:00:00Z');
  return ProductionPlan(
    id: 'plan-failed',
    name: '失败复刻',
    createdAt: now,
    updatedAt: now,
    tasks: [
      ProductionTask.scriptRecastFrame(
        id: 'task-failed',
        planId: 'plan-failed',
        title: '缺失帧',
        scriptId: 'script-1',
        scriptName: '雨夜档案',
        scriptPath: r'C:\stories\rain',
        recastRunId: 'run-failed',
        frameIndex: 2,
        sourceFileName: '002.json',
        payload: const {'input': 'missing generated frame'},
        status: ProductionTaskStatus.failed,
        error: 'missing output',
        createdAt: now,
        updatedAt: now,
      ),
      ProductionTask.scriptRecastFrame(
        id: 'task-completed',
        planId: 'plan-failed',
        title: '已完成帧',
        scriptId: 'script-1',
        scriptName: '雨夜档案',
        scriptPath: r'C:\stories\rain',
        recastRunId: 'run-failed',
        frameIndex: 3,
        sourceFileName: '003.json',
        payload: const {'input': 'completed generated frame'},
        status: ProductionTaskStatus.completed,
        outputImagePath: r'C:\out\frame-03.png',
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
}

ProductionPlan _largePlan() {
  final now = DateTime.parse('2026-06-02T08:00:00Z');
  return ProductionPlan(
    id: 'large',
    name: 'Large Batch',
    createdAt: now,
    updatedAt: now,
    tasks: [
      for (var index = 1; index <= 80; index++)
        ProductionTask.scriptRecastFrame(
          id: 'task-$index',
          planId: 'large',
          title: 'Frame $index',
          scriptId: 'script-1',
          scriptName: '雨夜档案',
          scriptPath: r'C:\stories\rain',
          recastRunId: 'run-large',
          frameIndex: index,
          sourceFileName: 'frame-$index.json',
          payload: {'input': 'generated frame $index'},
          status: ProductionTaskStatus.completed,
          outputImagePath: r'C:\out\large.png',
          createdAt: now,
          updatedAt: now,
        ),
    ],
  );
}

ProductionPlan _planWithTwoCompletedImages() {
  final now = DateTime.parse('2026-06-02T08:00:00Z');
  return ProductionPlan(
    id: 'plan-2',
    name: '导航测试',
    createdAt: now,
    updatedAt: now,
    tasks: [
      ProductionTask.scriptRecastFrame(
        id: 'task-1',
        planId: 'plan-2',
        title: 'First',
        scriptId: 'script-1',
        scriptName: '雨夜档案',
        scriptPath: r'C:\stories\rain',
        recastRunId: 'run-2',
        frameIndex: 1,
        sourceFileName: '001.json',
        payload: const {'input': 'first generated frame, blue eyes'},
        status: ProductionTaskStatus.completed,
        outputImagePath: r'C:\out\frame-01.png',
        createdAt: now,
        updatedAt: now,
      ),
      ProductionTask.scriptRecastFrame(
        id: 'task-2',
        planId: 'plan-2',
        title: 'Second',
        scriptId: 'script-1',
        scriptName: '雨夜档案',
        scriptPath: r'C:\stories\rain',
        recastRunId: 'run-2',
        frameIndex: 2,
        sourceFileName: '002.json',
        payload: const {'input': 'second generated frame, green eyes'},
        status: ProductionTaskStatus.completed,
        outputImagePath: r'C:\out\frame-02.png',
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
}

ProductionPlan _planWithLongPrompt() {
  final now = DateTime.parse('2026-06-02T08:00:00Z');
  return ProductionPlan(
    id: 'plan-3',
    name: 'Long Prompt',
    createdAt: now,
    updatedAt: now,
    tasks: [
      ProductionTask.scriptRecastFrame(
        id: 'task-1',
        planId: 'plan-3',
        title: 'Long Prompt Frame',
        scriptId: 'script-1',
        scriptName: '雨夜档案',
        scriptPath: r'C:\stories\rain',
        recastRunId: 'run-3',
        frameIndex: 1,
        sourceFileName: '009.json',
        payload: const {'input': _longPreviewPrompt},
        status: ProductionTaskStatus.completed,
        outputImagePath: r'C:\out\frame-09.png',
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
}

const _longPreviewPrompt =
    'detailed eyes, 1.3::best quality, amazing quality, very aesthetic, '
    'highres, incredibly absurdres, 0.9::artist:ahemaru, '
    '1.5::artist:channel, 2.5::artist:ie, -6.0::artist collaboration, '
    '1girl, 1boy, outdoors, street, arato asato, ratatatat74, eonsang, '
    'freng, null, year 2025, year 2024, motion lines, day, sunlight, '
    'japanese text, text, simple illustration, mature, white dress, '
    'blue eyes, long hair, standing, close-up, looking at viewer, smile';

ProductionPlan _planWithoutScriptPath() {
  final now = DateTime.parse('2026-06-02T08:00:00Z');
  return ProductionPlan(
    id: 'plan-1',
    name: '主角版 A',
    createdAt: now,
    updatedAt: now,
    tasks: [
      ProductionTask.scriptRecastFrame(
        id: 'task-1',
        planId: 'plan-1',
        title: '入口雨幕',
        scriptId: 'script-1',
        scriptName: '雨夜档案',
        recastRunId: 'run-1',
        frameIndex: 1,
        sourceFileName: '001.json',
        payload: const {'input': 'library entrance, generated heroine'},
        status: ProductionTaskStatus.completed,
        outputImagePath: r'C:\out\frame-01.png',
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
}

StudioGalleryRecord _galleryRecord({
  Map<String, dynamic> payload = const {
    'input': 'library entrance, archived version',
  },
}) {
  final now = DateTime.parse('2026-06-03T08:00:00Z');
  return StudioGalleryRecord.fromRecastPayload(
    payload: payload,
    id: 'gallery-1',
    createdAt: now,
    title: '收纳: 入口雨幕',
    imagePath: r'C:\gallery\frame-01.png',
    info: 'archived image prompt',
    provenance: const StudioRecastProvenance(
      scriptId: 'script-1',
      scriptName: '雨夜档案',
      scriptPath: r'C:\stories\rain',
      recastRunId: 'run-1',
      productionPlanId: 'plan-1',
      productionPlanFingerprint: 'fingerprint',
      taskId: 'task-1',
      frameIndex: 1,
      sourceFileName: '001.json',
      payloadFingerprint: 'payload-fingerprint',
      mappingConfigFingerprint: 'mapping-fingerprint',
      outputImagePath: r'C:\gallery\frame-01.png',
    ),
  );
}
