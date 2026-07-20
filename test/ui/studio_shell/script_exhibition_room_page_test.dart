import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/models/script_exhibition_recast_summary.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/studio_asset_capture.dart';
import 'package:novel_studio/data/studio/models/studio_gallery_record.dart';
import 'package:novel_studio/data/studio/services/script_exhibition_image_organizer_service.dart';
import 'package:novel_studio/data/studio/services/studio_asset_capture_service.dart';
import 'package:novel_studio/data/studio/models/tokenizer_script.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';
import 'package:novel_studio/ui/core/app_display_settings.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_staggered_reveal.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_display.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_theme.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_asset_capture_host.dart';
import 'package:novel_studio/ui/studio_shell/view_models/script_exhibition_room_viewmodel.dart';
import 'package:novel_studio/ui/studio_shell/widgets/script_exhibition_room_page.dart';

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

class _ThrowingOffscreenScriptExhibitionItem extends ScriptExhibitionItem {
  _ThrowingOffscreenScriptExhibitionItem({
    required super.id,
    required int frameIndex,
    required super.updatedAt,
  }) : super(
          scriptId: 'script-window',
          scriptTitle: 'Window Test',
          sourceFolder: r'C:\stories\window',
          versionId: 'version-window',
          versionLabel: 'Window',
          sourceKind: ScriptExhibitionItemSourceKind.generated,
          frameIndex: frameIndex,
          sourceFileName: 'frame-$frameIndex.json',
          title: 'Frame $frameIndex',
          subtitle: 'Window item',
          prompt: 'window test frame $frameIndex',
          imagePath: '',
          statusLabel: 'Ready',
        );

  @override
  String get imagePath => throw StateError('Offscreen item was materialized.');
}

class _CountingScriptCoverItem extends ScriptExhibitionItem {
  _CountingScriptCoverItem({
    required super.id,
    required super.scriptId,
    required super.scriptTitle,
    required super.sourceFolder,
    required super.versionId,
    required super.versionLabel,
    required int frameIndex,
    required super.updatedAt,
    required super.imagePath,
    required this.onImagePathRead,
  })  : _imagePath = imagePath,
        super(
          sourceKind: ScriptExhibitionItemSourceKind.generated,
          frameIndex: frameIndex,
          sourceFileName: 'cover-$frameIndex.png',
          title: 'Cover $frameIndex',
          subtitle: 'Cover item',
          prompt: 'cover prompt $frameIndex',
          statusLabel: 'Ready',
        );

  final String _imagePath;
  final VoidCallback onImagePathRead;

  @override
  String get imagePath {
    onImagePathRead();
    return _imagePath;
  }
}

class _OrganizeScriptImagesViewModel extends ScriptExhibitionRoomViewModel {
  _OrganizeScriptImagesViewModel({
    required this.preview,
    required this.result,
  }) : super(
          loadScripts: () async => [_script()],
          loadProductionPlans: () async => const [],
          loadGalleryRecords: () async => const [],
        );

  final ScriptExhibitionImageOrganizationPreview preview;
  final ScriptExhibitionImageOrganizationResult result;
  int previewCallCount = 0;
  int organizeCallCount = 0;
  ScriptExhibitionImageOrganizationPreview? organizedPreview;

  @override
  Future<ScriptExhibitionImageOrganizationPreview>
      previewScriptImageOrganization(ScriptExhibitionScript script) async {
    previewCallCount += 1;
    return preview;
  }

  @override
  Future<ScriptExhibitionImageOrganizationResult> organizeScriptImages(
    ScriptExhibitionScript script, {
    ScriptExhibitionImageOrganizationPreview? preview,
  }) async {
    organizeCallCount += 1;
    organizedPreview = preview;
    return result;
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

  testWidgets('script import failures stay inside the exhibition page', (
    tester,
  ) async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      importScriptFolder: () async {
        throw const FormatException('empty import folder');
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: Scaffold(
          body: ScriptExhibitionRoomPage(
            viewModel: viewModel,
            onSendToScriptWorkbench: (_) {},
            onSendToWorkbench: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-import-script')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('导入剧本失败'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('script-exhibition-room-page')),
      findsOneWidget,
    );
  });

  testWidgets('summary cover is replaced by a detail loading state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tempDir = Directory.systemTemp.createTempSync(
      'script-exhibition-summary-loading-',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final firstImage = File(
      '${tempDir.path}${Platform.pathSeparator}001.png',
    );
    final secondImage = File(
      '${tempDir.path}${Platform.pathSeparator}002.png',
    );
    firstImage.writeAsBytesSync(const [0, 1, 2, 3]);
    secondImage.writeAsBytesSync(const [0, 1, 2, 3]);

    final summary = RecastExhibitionScript(
      scriptId: 'summary-script',
      scriptName: 'Summary Script',
      sourceRootPath: tempDir.path,
      updatedAt: DateTime.parse('2026-07-13T09:00:00Z'),
      detectedSchema: ScriptSchema.unknown,
      frames: [
        RecastExhibitionFrame(
          index: 1,
          fileName: '001.png',
          sourcePath: firstImage.path,
        ),
      ],
      frameCount: 2,
      summaryOnly: true,
    );
    final detail = RecastExhibitionScript(
      scriptId: 'summary-script',
      scriptName: 'Summary Script',
      sourceRootPath: tempDir.path,
      updatedAt: DateTime.parse('2026-07-13T09:00:00Z'),
      detectedSchema: ScriptSchema.baseInline,
      frames: [
        RecastExhibitionFrame(
          index: 1,
          fileName: '001.png',
          sourcePath: firstImage.path,
          prompt: 'first prompt',
        ),
        RecastExhibitionFrame(
          index: 2,
          fileName: '002.png',
          sourcePath: secondImage.path,
          prompt: 'second prompt',
        ),
      ],
    );
    final detailCompleter = Completer<RecastExhibitionScript?>();
    final viewModel = ScriptExhibitionRoomViewModel(
      loadRecastScripts: () async => [summary],
      loadRecastScript: (_) => detailCompleter.future,
      loadScripts: () async => const [],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: Scaffold(
          body: ScriptExhibitionRoomPage(
            viewModel: viewModel,
            onSendToScriptWorkbench: (_) {},
            onSendToWorkbench: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(
      find.byKey(
        const ValueKey('script-exhibition-script-card-summary-script'),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey('script-exhibition-detail-loading-status'),
      ),
      findsOneWidget,
    );
    expect(find.text('正在加载完整剧本'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey(
          'script-exhibition-item-original-summary-script-frame-1',
        ),
      ),
      findsNothing,
    );

    detailCompleter.complete(detail);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byKey(
        const ValueKey('script-exhibition-detail-loading-status'),
      ),
      findsNothing,
    );
    expect(viewModel.selectedScript?.summaryOnly, isFalse);
    expect(viewModel.visibleVersionItems, hasLength(2));
  });

  testWidgets('browses versions, previews an image, and reruns a frame', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sentScriptFocuses = <ScriptExhibitionFocus>[];
    final sentWorkbenchFocuses = <ScriptExhibitionFocus>[];
    final rerunFocuses = <ScriptExhibitionFocus>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => const [],
      renameScriptRecord: (_, __) async {},
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: ScriptExhibitionRoomPage(
          viewModel: viewModel,
          onSendToScriptWorkbench: sentScriptFocuses.add,
          onSendToWorkbench: sentWorkbenchFocuses.add,
          onQuickRerunProductionTask: rerunFocuses.add,
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

    viewModel.selectScript('script-1');
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
    expect(
      find.descendant(of: generatedCard, matching: find.text('1')),
      findsOneWidget,
    );
    expect(find.text('新图: 入口雨幕'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey(
          'script-exhibition-rerun-production-plan-1-task-1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sentWorkbenchFocuses, isEmpty);
    expect(rerunFocuses, hasLength(1));
    expect(rerunFocuses.single.imagePath, r'C:\out\frame-01.png');
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
      find.byKey(const ValueKey('script-exhibition-preview-rerun')),
    );
    await tester.pumpAndSettle();

    expect(sentWorkbenchFocuses, isEmpty);
    expect(rerunFocuses, hasLength(2));
    expect(rerunFocuses.last.scriptId, 'script-1');
    expect(rerunFocuses.last.sourceFolder, r'C:\stories\rain');
    expect(rerunFocuses.last.frameIndex, 1);
    expect(rerunFocuses.last.productionPlanId, 'plan-1');
    expect(rerunFocuses.last.imagePath, r'C:\out\frame-01.png');
  });

  testWidgets('generated detail cards preserve file image aspect ratio',
      (tester) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tempDir = Directory.systemTemp.createTempSync(
      'script-exhibition-generated-image-height-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final imageFile = File(
      '${tempDir.path}${Platform.pathSeparator}generated.png',
    )..writeAsBytesSync(_pngBytes);
    final now = DateTime.parse('2026-06-02T08:00:00Z');
    final plan = ProductionPlan(
      id: 'plan-height',
      name: 'Height Stable',
      createdAt: now,
      updatedAt: now,
      tasks: [
        ProductionTask.scriptRecastFrame(
          id: 'task-1',
          planId: 'plan-height',
          title: 'Generated frame',
          scriptId: 'script-1',
          scriptName: '闆ㄥ妗ｆ',
          scriptPath: r'C:\stories\rain',
          recastRunId: 'run-height',
          frameIndex: 1,
          sourceFileName: '001.json',
          payload: const {'input': 'generated prompt'},
          status: ProductionTaskStatus.completed,
          outputImagePath: imageFile.path,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [plan],
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

    viewModel.selectScript('script-1');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('script-exhibition-version-production-plan-height'),
      ),
    );
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(
      find.byKey(
        const ValueKey('script-exhibition-image-production-plan-height-task-1'),
      ),
    );
    expect(image.height, isNull);
    final aspectRatio = tester.widget<AspectRatio>(
      find.ancestor(
        of: find.byKey(
          const ValueKey(
            'script-exhibition-image-production-plan-height-task-1',
          ),
        ),
        matching: find.byType(AspectRatio),
      ),
    );
    expect(aspectRatio.aspectRatio, 1);
  });

  testWidgets('organize script images previews counts before applying', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const preview = ScriptExhibitionImageOrganizationPreview(
      moves: [
        ScriptExhibitionImageMovePlan(
          sourcePath: r'C:\generated\loose\move-a.png',
          destinationPath: r'C:\generated\Rain Archive\Version\001.png',
          productionPlanId: 'plan-organize',
          taskId: 'task-a',
        ),
        ScriptExhibitionImageMovePlan(
          sourcePath: r'C:\generated\loose\move-b.png',
          destinationPath: r'C:\generated\Rain Archive\Version\002.png',
          productionPlanId: 'plan-organize',
          taskId: 'task-b',
        ),
      ],
      orphanImagePaths: [
        r'C:\generated\loose\orphan-a.png',
        r'C:\generated\loose\orphan-b.png',
        r'C:\generated\loose\orphan-c.png',
      ],
      productionPlans: [],
      galleryRecords: [],
    );
    const result = ScriptExhibitionImageOrganizationResult(
      movedImagePaths: [
        r'C:\generated\Rain Archive\Version\001.png',
        r'C:\generated\Rain Archive\Version\002.png',
      ],
      deletedOrphanImagePaths: [
        r'C:\generated\loose\orphan-a.png',
        r'C:\generated\loose\orphan-b.png',
        r'C:\generated\loose\orphan-c.png',
      ],
      failedImagePaths: [],
      updatedProductionPlans: [],
      updatedGalleryRecords: [],
    );
    final viewModel = _OrganizeScriptImagesViewModel(
      preview: preview,
      result: result,
    );
    await tester.runAsync(() async {
      await viewModel.load();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: Scaffold(
          body: ScriptExhibitionRoomPage(
            viewModel: viewModel,
            onSendToScriptWorkbench: (_) {},
            onSendToWorkbench: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    viewModel.selectScript('script-1');
    await tester.pumpAndSettle();
    final organizeButton = tester.widget<IconButton>(
      find.byKey(
        const ValueKey('script-exhibition-organize-script-images-script-1'),
      ),
    );
    expect(organizeButton.onPressed, isNotNull);
    await tester.tap(
      find.byKey(
        const ValueKey('script-exhibition-organize-script-images-script-1'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.textContaining('2')),
      findsWidgets,
    );
    expect(
      find.descendant(of: dialog, matching: find.textContaining('3')),
      findsWidgets,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('script-exhibition-confirm-organize-script-images'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(viewModel.previewCallCount, 1);
    expect(viewModel.organizeCallCount, 1);
    expect(viewModel.organizedPreview, same(preview));
  });

  testWidgets('original image preview translates prompt by default', (
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
    expect(tagDisplay.defaultTranslated, isTrue);
  });

  testWidgets('original image preview shows parsed generation parameters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        _script(
          generationParams: const {
            'seed': 1554536533,
            'steps': 28,
            'sampler': 'k_euler_ancestral',
            'scale': 4,
            'cfg_rescale': 0.4,
            'width': 832,
            'height': 1216,
            'noise_schedule': 'karras',
          },
        ),
      ],
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

    expect(find.text('Seed 1554536533'), findsOneWidget);
    expect(find.text('Steps 28'), findsOneWidget);
    expect(find.text('Sampler k_euler_ancestral'), findsOneWidget);
    expect(find.text('Scale 4'), findsOneWidget);
    expect(find.text('CFG 0.4'), findsOneWidget);
    expect(find.text('Size 832x1216'), findsOneWidget);
    expect(find.text('Noise karras'), findsOneWidget);
  });

  testWidgets('original image preview shows metadata-loaded parameters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final imagePath = '${Uri.base.toFilePath()}assets/appicon.png';
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        _script(
          sourceFileName: '001.png',
          sourcePath: imagePath,
          sourceKind: TokenizerScriptSourceKind.image,
          defaultImagePath: imagePath,
          generationParams: const {
            'v4_prompt': {
              'caption': {'base_caption': 'library entrance, rainy night'},
            },
          },
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      loadImageGenerationParams: (_) async => const {
        'seed': 512780596,
        'steps': 28,
        'sampler': 'k_euler_ancestral',
        'scale': 4,
        'cfg_rescale': 0.4,
        'width': 832,
        'height': 1216,
        'noise_schedule': 'karras',
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
      find.byKey(
        const ValueKey(
          'script-exhibition-item-original-script-1-source-task-1',
        ),
      ),
    );

    await _pumpUntilFound(tester, find.text('Seed 512780596'));

    expect(find.text('Steps 28'), findsOneWidget);
    expect(find.text('Sampler k_euler_ancestral'), findsOneWidget);
    expect(find.text('Scale 4'), findsOneWidget);
    expect(find.text('CFG 0.4'), findsOneWidget);
    expect(find.text('Size 832x1216'), findsOneWidget);
    expect(find.text('Noise karras'), findsOneWidget);
  });

  testWidgets('original image preview explains missing scalar metadata', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final imagePath = '${Uri.base.toFilePath()}assets/appicon.png';
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        _script(
          sourceFileName: '001.png',
          sourcePath: imagePath,
          sourceKind: TokenizerScriptSourceKind.image,
          defaultImagePath: imagePath,
          generationParams: const {
            'v4_prompt': {
              'caption': {'base_caption': 'soft lighting, light rays'},
            },
          },
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      loadImageGenerationParams: (_) async => const {
        'v4_prompt': {
          'caption': {'base_caption': 'soft lighting, light rays'},
        },
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
      find.byKey(
        const ValueKey(
          'script-exhibition-item-original-script-1-source-task-1',
        ),
      ),
    );

    await _pumpUntilFound(tester, find.text('未找到 Seed/Steps 元数据'));

    expect(find.text('Seed 512780596'), findsNothing);
    expect(find.text('Steps 28'), findsNothing);
  });

  testWidgets('renders shelf scripts as full cover wall cards', (tester) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sentScriptFocuses = <ScriptExhibitionFocus>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => const [],
      renameScriptRecord: (_, __) async {},
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: ScriptExhibitionRoomPage(
          viewModel: viewModel,
          onSendToScriptWorkbench: sentScriptFocuses.add,
          onSendToWorkbench: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('script-exhibition-script-cover-script-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('script-exhibition-script-cover-image-script-1'),
      ),
      findsOneWidget,
    );
    final coverImage = tester.widget<Image>(
      find.byKey(
        const ValueKey('script-exhibition-script-cover-image-script-1'),
      ),
    );
    expect(coverImage.image, isA<ResizeImage>());
    final coverProvider = coverImage.image as ResizeImage;
    expect(coverProvider.width, isNotNull);
    expect(coverProvider.height, isNotNull);
    expect(coverProvider.width, lessThanOrEqualTo(1024));
    expect(coverProvider.height, lessThanOrEqualTo(1024));
    expect(find.text('新图封面'), findsOneWidget);
    expect(find.text('原始剧本 1 / 新图 1 / 需处理 0'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('script-exhibition-rename-script-script-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('script-exhibition-delete-script-script-1')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-send-script-script-1')),
    );
    await tester.pumpAndSettle();

    expect(sentScriptFocuses.single.scriptId, 'script-1');
  });

  testWidgets('script workbench send shows pending state and blocks duplicates',
      (tester) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sentScriptFocuses = <ScriptExhibitionFocus>[];
    var pendingSend = Completer<void>();
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => const [],
      renameScriptRecord: (_, __) async {},
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: ScriptExhibitionRoomPage(
          viewModel: viewModel,
          onSendToScriptWorkbench: (focus) async {
            sentScriptFocuses.add(focus);
            await pendingSend.future;
          },
          onSendToWorkbench: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final shelfSend = find.byKey(
      const ValueKey('script-exhibition-send-script-script-1'),
    );
    await tester.tap(shelfSend);
    await tester.pump();

    expect(sentScriptFocuses, hasLength(1));
    expect(
      tester
          .widget<IconButton>(
            find.descendant(of: shelfSend, matching: find.byType(IconButton)),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(shelfSend);
    await tester.pump();
    expect(sentScriptFocuses, hasLength(1));

    pendingSend.complete();
    await tester.pumpAndSettle();

    final detailSend = find.byKey(
      const ValueKey('script-exhibition-detail-send-script-workbench'),
    );
    if (detailSend.evaluate().isEmpty) {
      await tester.tap(
        find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
      );
      await tester.pumpAndSettle();
    }
    pendingSend = Completer<void>();
    await tester.tap(detailSend);
    await tester.pump();

    expect(
      tester.widget<FilledButton>(detailSend).onPressed,
      isNull,
    );
    expect(
      find.descendant(
        of: detailSend,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    await tester.tap(detailSend);
    await tester.pump();
    expect(sentScriptFocuses, hasLength(2));

    pendingSend.complete();
    await tester.pumpAndSettle();

    expect(
      tester.widget<FilledButton>(detailSend).onPressed,
      isNotNull,
    );
  });

  testWidgets('script shelf cards use bounded row-column reveal wrappers', (
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

    final card = find.byKey(
      const ValueKey('script-exhibition-script-card-script-1'),
    );
    final reveal = find.ancestor(
      of: card,
      matching: find.byType(StudioStaggeredReveal),
    );
    expect(reveal, findsOneWidget);
    expect(
        tester.widget<StudioStaggeredReveal>(reveal).columns, greaterThan(1));
  });

  testWidgets('script drag feedback uses a same-size card preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => const [],
      renameScriptRecord: (_, __) async {},
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
    final dragHandle = find.byKey(
      const ValueKey('script-exhibition-drag-handle-script-1'),
    );
    final cardSize = tester.getSize(card);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.down(tester.getCenter(dragHandle));
    await tester.pump();
    await gesture.moveBy(const Offset(80, 40));
    await tester.pump();

    final feedback = find.byKey(
      const ValueKey('script-exhibition-drag-feedback-card-script-1'),
    );
    expect(feedback, findsOneWidget);
    expect(tester.getSize(feedback), cardSize);
    expect(
      find.descendant(
        of: feedback,
        matching: find.byKey(
          const ValueKey('script-exhibition-script-cover-image-script-1'),
        ),
      ),
      findsNothing,
    );
    expect(find.text('1 个剧本'), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('script card body drag starts dragging without marquee', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
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

    final card = find.byKey(
      const ValueKey('script-exhibition-script-card-script-1'),
    );
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.down(tester.getCenter(card));
    await tester.pump();
    await gesture.moveBy(const Offset(80, 40));
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey('script-exhibition-drag-feedback-card-script-1'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('script-exhibition-marquee-overlay')),
      findsNothing,
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(viewModel.selectedScriptIds, {'script-1'});
  });

  testWidgets('marquee starts from the shelf edge gutter and aligns to cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
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

    final card = find.byKey(
      const ValueKey('script-exhibition-script-card-script-1'),
    );
    final cardRect = tester.getRect(card);
    final start = Offset(cardRect.left - 16, cardRect.top + 24);
    final end = cardRect.center;
    expect(start.dx, lessThan(cardRect.left));

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();

    final overlayFinder = find.byKey(
      const ValueKey('script-exhibition-marquee-overlay'),
    );
    expect(overlayFinder, findsOneWidget);
    final overlayPaint = tester.widget<CustomPaint>(overlayFinder);
    final overlay = (overlayPaint.painter as dynamic).overlay as dynamic;
    final overlayOrigin = tester.getTopLeft(overlayFinder);
    final marqueeGlobal = (overlay.marqueeRect as Rect).shift(overlayOrigin);
    final selectedGlobal =
        ((overlay.selectedRects as List).single as Rect).shift(overlayOrigin);

    expect(marqueeGlobal.left, closeTo(start.dx, 0.5));
    expect(marqueeGlobal.top, closeTo(start.dy, 0.5));
    expect(selectedGlobal.left, closeTo(cardRect.left, 0.5));
    expect(selectedGlobal.top, closeTo(cardRect.top, 0.5));
    expect(selectedGlobal.right, closeTo(cardRect.right, 0.5));
    expect(selectedGlobal.bottom, closeTo(cardRect.bottom, 0.5));

    await gesture.up();
    await tester.pumpAndSettle();

    expect(viewModel.selectedScriptIds, {'script-1'});
  });

  testWidgets('marquee starts from the gap between script cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        _script(),
        _script().copyWith(
          scriptId: 'script-2',
          name: 'Gap Neighbor',
          sourceFolder: r'C:\stories\gap-neighbor',
        ),
      ],
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

    final firstCard = find.byKey(
      const ValueKey('script-exhibition-script-card-script-1'),
    );
    final secondCard = find.byKey(
      const ValueKey('script-exhibition-script-card-script-2'),
    );
    final firstRect = tester.getRect(firstCard);
    final secondRect = tester.getRect(secondCard);
    final start = Offset(
      (firstRect.right + secondRect.left) / 2,
      firstRect.top + 24,
    );
    final end = firstRect.center;
    expect(start.dx, greaterThan(firstRect.right));
    expect(start.dx, lessThan(secondRect.left));

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey('script-exhibition-drag-feedback-card-script-1'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('script-exhibition-marquee-overlay')),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(viewModel.selectedScriptIds, {'script-1'});
  });

  testWidgets('marquee starts from the gap between script rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scripts = [
      for (var index = 0; index < 16; index += 1)
        _script().copyWith(
          scriptId: 'script-$index',
          name: 'Row Gap Script $index',
          sourceFolder: 'C:\\stories\\row-gap\\$index',
        ),
    ];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );
    await tester.runAsync(() async {
      await viewModel.load();
    });

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

    String? topScriptId;
    String? bottomScriptId;
    Rect? topRect;
    Rect? bottomRect;
    for (var upperIndex = 0; upperIndex < scripts.length; upperIndex += 1) {
      final upperFinder = find.byKey(
        ValueKey('script-exhibition-script-card-script-$upperIndex'),
      );
      if (upperFinder.evaluate().isEmpty) {
        continue;
      }
      final upperRect = tester.getRect(upperFinder);
      for (var lowerIndex = upperIndex + 1;
          lowerIndex < scripts.length;
          lowerIndex += 1) {
        final lowerFinder = find.byKey(
          ValueKey('script-exhibition-script-card-script-$lowerIndex'),
        );
        if (lowerFinder.evaluate().isEmpty) {
          continue;
        }
        final lowerRect = tester.getRect(lowerFinder);
        final sameColumn = (upperRect.left - lowerRect.left).abs() < 1;
        final gap = lowerRect.top - upperRect.bottom;
        if (sameColumn && gap > 4 && gap < 32) {
          topScriptId = 'script-$upperIndex';
          bottomScriptId = 'script-$lowerIndex';
          topRect = upperRect;
          bottomRect = lowerRect;
          break;
        }
      }
      if (topScriptId != null) {
        break;
      }
    }
    expect(topScriptId, isNotNull);
    expect(bottomScriptId, isNotNull);
    final selectedBottomScriptId = bottomScriptId!;
    final currentTopRect = topRect!;
    final currentBottomRect = bottomRect!;
    final start = Offset(
      currentTopRect.left + 24,
      (currentTopRect.bottom + currentBottomRect.top) / 2,
    );
    final end = currentBottomRect.center;

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();

    expect(
      find.byKey(
        ValueKey('script-exhibition-drag-feedback-card-${topScriptId!}'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('script-exhibition-marquee-overlay')),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(viewModel.selectedScriptIds, {selectedBottomScriptId});
  });

  testWidgets('marquee selection stays aligned after scrolling the shelf', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scripts = [
      for (var index = 0; index < 60; index += 1)
        _script().copyWith(
          scriptId: 'script-$index',
          name: 'Scrolled Script $index',
          sourceFolder: 'C:\\stories\\scrolled\\$index',
        ),
    ];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );
    await tester.runAsync(() async {
      await viewModel.load();
    });

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

    final initiallyVisibleCard = find.byKey(
      const ValueKey('script-exhibition-script-card-script-0'),
    );
    final initialTop = tester.getTopLeft(initiallyVisibleCard).dy;
    final scrollView = find.byKey(
      const ValueKey('script-exhibition-scroll-view'),
    );
    await tester.drag(scrollView, const Offset(0, -160));
    await tester.pump();
    await tester.pump();
    final scrolledTop = tester.getTopLeft(initiallyVisibleCard).dy;
    expect(scrolledTop, lessThan(initialTop - 80));

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-marquee-mode-toggle')),
    );
    await tester.pumpAndSettle();

    String? firstScriptId;
    Rect? firstRect;
    Rect? secondRect;
    for (var leftIndex = 0; leftIndex < scripts.length; leftIndex += 1) {
      final leftFinder = find.byKey(
        ValueKey('script-exhibition-script-card-script-$leftIndex'),
      );
      if (leftFinder.evaluate().isEmpty) {
        continue;
      }
      final leftRect = tester.getRect(leftFinder);
      if (leftRect.top < 120 || leftRect.bottom > 940) {
        continue;
      }
      for (var rightIndex = leftIndex + 1;
          rightIndex < scripts.length;
          rightIndex += 1) {
        final rightFinder = find.byKey(
          ValueKey('script-exhibition-script-card-script-$rightIndex'),
        );
        if (rightFinder.evaluate().isEmpty) {
          continue;
        }
        final rightRect = tester.getRect(rightFinder);
        final sameRow = (leftRect.top - rightRect.top).abs() < 1;
        final gap = rightRect.left - leftRect.right;
        if (sameRow && gap > 4 && gap < 32) {
          firstScriptId = 'script-$leftIndex';
          firstRect = leftRect;
          secondRect = rightRect;
          break;
        }
      }
      if (firstScriptId != null) {
        break;
      }
    }
    expect(firstScriptId, isNotNull);
    final currentFirstRect = firstRect!;
    final currentSecondRect = secondRect!;
    final start = Offset(
      (currentFirstRect.right + currentSecondRect.left) / 2,
      currentFirstRect.top + 24,
    );
    final end = currentFirstRect.center;

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.down(start);
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();

    final overlayFinder = find.byKey(
      const ValueKey('script-exhibition-marquee-overlay'),
    );
    expect(overlayFinder, findsOneWidget);
    final overlayPaint = tester.widget<CustomPaint>(overlayFinder);
    final overlay = (overlayPaint.painter as dynamic).overlay as dynamic;
    expect(overlay.selectedRects, hasLength(1));
    final overlayOrigin = tester.getTopLeft(overlayFinder);
    final selectedGlobal =
        ((overlay.selectedRects as List).single as Rect).shift(overlayOrigin);

    expect(selectedGlobal.left, closeTo(currentFirstRect.left, 0.5));
    expect(selectedGlobal.top, closeTo(currentFirstRect.top, 0.5));
    expect(selectedGlobal.right, closeTo(currentFirstRect.right, 0.5));
    expect(selectedGlobal.bottom, closeTo(currentFirstRect.bottom, 0.5));

    await gesture.up();
    await tester.pumpAndSettle();

    expect(viewModel.selectedScriptIds, {firstScriptId});
  });

  testWidgets('ctrl marquee adds to the existing script selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        _script(),
        _script().copyWith(
          scriptId: 'script-2',
          name: 'Branch Archive',
          sourceFolder: r'C:\stories\branch',
        ),
        _script().copyWith(
          scriptId: 'script-3',
          name: 'Other Archive',
          sourceFolder: r'C:\stories\other',
        ),
      ],
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

    viewModel.replaceShelfSelection({'script-1'});
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-marquee-mode-toggle')),
    );
    await tester.pumpAndSettle();

    var controlPressed = false;
    addTearDown(() async {
      if (controlPressed) {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }
    });
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    controlPressed = true;
    final secondCard = find.byKey(
      const ValueKey('script-exhibition-script-card-script-2'),
    );
    final secondRect = tester.getRect(secondCard);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.down(secondRect.topLeft + const Offset(8, 8));
    await tester.pump();
    await gesture.moveTo(secondRect.bottomRight - const Offset(8, 8));
    await tester.pump();
    await gesture.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    controlPressed = false;
    await tester.pumpAndSettle();

    expect(viewModel.selectedScriptIds, {'script-1', 'script-2'});
  });

  testWidgets('marquee keeps selected scripts when the shelf scrolls mid-drag',
      (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scripts = [
      for (var index = 0; index < 60; index += 1)
        _script().copyWith(
          scriptId: 'script-$index',
          name: 'Scrollable Script $index',
          sourceFolder: 'C:\\stories\\scrollable\\$index',
        ),
    ];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );
    await tester.runAsync(() async {
      await viewModel.load();
    });

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
      find.byKey(const ValueKey('script-exhibition-marquee-mode-toggle')),
    );
    await tester.pumpAndSettle();

    String? selectedScriptId;
    Rect? selectedRect;
    for (var index = 0; index < scripts.length; index += 1) {
      final card = find.byKey(
        ValueKey('script-exhibition-script-card-script-$index'),
      );
      if (card.evaluate().isEmpty) continue;
      final rect = tester.getRect(card);
      if (rect.top >= 120 && rect.bottom <= 940) {
        selectedScriptId = 'script-$index';
        selectedRect = rect;
        break;
      }
    }
    expect(selectedScriptId, isNotNull);
    final firstRect = selectedRect!;
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.down(firstRect.topLeft + const Offset(8, 8));
    await tester.pump();
    await gesture.moveTo(firstRect.bottomRight - const Offset(8, 8));
    await tester.pump();

    final overlayPaint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('script-exhibition-marquee-overlay')),
    );
    final overlay = (overlayPaint.painter as dynamic).overlay as dynamic;
    expect(overlay.selectedRects, isNotEmpty);

    final scrollView = find.byKey(
      const ValueKey('script-exhibition-scroll-view'),
    );
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(scrollView),
        scrollDelta: const Offset(0, 720),
      ),
    );
    await tester.pump();
    await tester.pump();

    await gesture.up();
    await tester.pumpAndSettle();

    expect(viewModel.selectedScriptIds, contains(selectedScriptId));
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
    await tester.runAsync(() async {
      await viewModel.load();
    });

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
    await _pumpUntil(
      tester,
      () =>
          viewModel.selectedScript?.versions.any(
            (version) => version.id == 'production-large',
          ) ??
          false,
    );
    expect(
      viewModel.selectedScript?.versions.any(
        (version) => version.id == 'production-large',
      ),
      isTrue,
    );
    final largeProductionVersion = find.byKey(
      const ValueKey('script-exhibition-version-production-large'),
    );
    await _pumpUntilFound(tester, largeProductionVersion);
    await tester.tap(largeProductionVersion);
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

  testWidgets('keeps detail controls pinned while scrolling the waterfall', (
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
    await tester.runAsync(() async {
      await viewModel.load();
    });

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
    final largeProductionVersion = find.byKey(
      const ValueKey('script-exhibition-version-production-large'),
    );
    await _pumpUntilFound(tester, largeProductionVersion);
    await tester.tap(largeProductionVersion);
    await tester.pumpAndSettle();

    final scrollView = find.byKey(
      const ValueKey('script-exhibition-scroll-view'),
    );
    await tester.drag(scrollView, const Offset(0, -900));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final allCategory = find.byKey(
      const ValueKey('script-exhibition-category-all'),
    );
    final detailTitle = find.byKey(
      const ValueKey('script-exhibition-detail-title-script-1'),
    );
    final itemSortMenu = find.byKey(
      const ValueKey('script-exhibition-item-sort-menu'),
    );

    expect(detailTitle, findsOneWidget);
    expect(itemSortMenu, findsOneWidget);
    final categoryBottom = tester.getBottomLeft(allCategory).dy;
    final detailTop = tester.getTopLeft(detailTitle).dy;
    final sortBottom = tester.getBottomLeft(itemSortMenu).dy;
    expect(detailTop, greaterThanOrEqualTo(categoryBottom - 1));
    expect(sortBottom, lessThan(tester.view.physicalSize.height));
  });

  testWidgets('large detail boards do not materialize offscreen image paths', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.parse('2026-06-02T08:00:00Z');
    final items = [
      for (var index = 0; index < 40; index += 1)
        if (index < 12)
          _scriptExhibitionDetailItem(index, now)
        else
          _ThrowingOffscreenScriptExhibitionItem(
            id: 'window-item-$index',
            frameIndex: index,
            updatedAt: now,
          ),
    ];
    final script = ScriptExhibitionScript(
      scriptId: 'script-window',
      title: 'Window Test',
      sourceFolder: r'C:\stories\window',
      updatedAt: now,
      versions: [
        ScriptExhibitionVersion(
          id: 'version-window',
          label: 'Window',
          description: 'Large generated version',
          updatedAt: now,
          items: items,
        ),
      ],
      status: ScriptExhibitionScriptStatus.active,
      originalCount: 0,
      generatedImageCount: items.length,
      imageLikeItemCount: items.length,
      hasImage: true,
      coverItem: items.first,
      pendingCount: 0,
      firstNeedsActionItem: null,
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => const [],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    )
      ..snapshot = ScriptExhibitionSnapshot(
        scripts: [script],
        totalImageCount: items.length,
        generatedImageCount: items.length,
        needsActionCount: 0,
      )
      ..selectedScriptId = 'script-window'
      ..selectedVersionId = 'version-window'
      ..isLoading = true;

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
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('script-exhibition-item-window-item-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('script-exhibition-item-window-item-12')),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('script-exhibition-item-window-item-12')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reruns production-only images instead of sending to workbench', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sentScriptFocuses = <ScriptExhibitionFocus>[];
    final sentWorkbenchFocuses = <ScriptExhibitionFocus>[];
    final rerunFocuses = <ScriptExhibitionFocus>[];
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
          onQuickRerunProductionTask: rerunFocuses.add,
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
      find.byKey(const ValueKey('script-exhibition-preview-rerun')),
    );
    expect(button.onPressed, isNotNull);

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-preview-rerun')),
    );
    await tester.pumpAndSettle();
    expect(sentScriptFocuses, isEmpty);
    expect(sentWorkbenchFocuses, isEmpty);
    expect(rerunFocuses.single.imagePath, r'C:\out\frame-01.png');
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

    expect(
      find.byKey(
        const ValueKey('script-exhibition-item-production-plan-2-task-1'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('script-exhibition-item-production-plan-2-task-2'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('script-exhibition-item-production-plan-2-task-3'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'script-exhibition-variant-indicator-production-plan-2-task-2',
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('script-exhibition-item-production-plan-2-task-2'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('script-exhibition-zoomable-image-viewer')),
      findsOneWidget,
    );
    expect(find.textContaining('1/2'), findsOneWidget);
    expect(find.text('first generated frame'), findsNothing);
    expect(find.text('same frame rerun'), findsWidgets);
    expect(find.text('other frame'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(find.textContaining('1/2'), findsOneWidget);
    expect(find.text('first generated frame'), findsWidgets);
    expect(find.text('same frame rerun'), findsNothing);
    expect(find.text('other frame'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.textContaining('2/2'), findsOneWidget);
    expect(find.text('first generated frame'), findsNothing);
    expect(find.text('same frame rerun'), findsNothing);
    expect(find.text('other frame'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.textContaining('1/2'), findsOneWidget);
    expect(find.text('first generated frame'), findsNothing);
    expect(find.text('same frame rerun'), findsWidgets);
    expect(find.text('other frame'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.textContaining('1/2'), findsOneWidget);
    expect(find.text('first generated frame'), findsWidgets);
    expect(find.text('same frame rerun'), findsNothing);
    expect(find.text('other frame'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.textContaining('1/2'), findsOneWidget);
    expect(find.text('first generated frame'), findsNothing);
    expect(find.text('same frame rerun'), findsWidgets);
    expect(find.text('other frame'), findsNothing);

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
    expect(
      find.byKey(
        const ValueKey(
          'studio-generated-image-viewer-image-production-plan-2-task-2',
        ),
      ),
      findsOneWidget,
    );

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(
          find.byKey(const ValueKey('script-exhibition-zoomable-image-viewer')),
        ),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey(
          'studio-generated-image-viewer-image-production-plan-2-task-1',
        ),
      ),
      findsOneWidget,
    );

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(
          find.byKey(const ValueKey('script-exhibition-zoomable-image-viewer')),
        ),
        scrollDelta: const Offset(0, -120),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey(
          'studio-generated-image-viewer-image-production-plan-2-task-2',
        ),
      ),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey(
          'studio-generated-image-viewer-image-production-plan-2-task-1',
        ),
      ),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey(
          'studio-generated-image-viewer-image-production-plan-2-task-2',
        ),
      ),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey(
          'studio-generated-image-viewer-image-production-plan-2-task-3',
        ),
      ),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey(
          'studio-generated-image-viewer-image-production-plan-2-task-2',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'preview delete keeps details visible while confirming one image deletion',
    (tester) async {
      tester.view.physicalSize = const Size(1320, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final deletedItems = <ScriptExhibitionItem>[];
      final viewModel = ScriptExhibitionRoomViewModel(
        loadScripts: () async => [_script()],
        loadProductionPlans: () async => [_plan()],
        loadGalleryRecords: () async => const [],
        deleteItemRecord: (item, {bool deleteLocalFiles = false}) async {
          deletedItems.add(item);
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
        find.byKey(
            const ValueKey('script-exhibition-version-production-plan-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('script-exhibition-item-production-plan-1-task-1'),
        ),
      );
      await tester.pumpAndSettle();

      final preview = find.byKey(
        const ValueKey('script-exhibition-fullscreen-preview'),
      );
      expect(preview, findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('script-exhibition-preview-delete')),
      );
      await tester.pumpAndSettle();

      expect(preview, findsOneWidget);
      expect(find.text('删除图片'), findsWidgets);
      expect(find.textContaining('只会移除当前帧的当前图片'), findsOneWidget);
      expect(find.textContaining('不会删除整条版本'), findsOneWidget);

      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();

      expect(preview, findsOneWidget);
      expect(deletedItems, isEmpty);
    },
  );

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

  testWidgets('changes script shelf sort from the room sort menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        _script().copyWith(
          scriptId: 'script-beta',
          name: 'Beta',
          sourceFolder: r'C:\stories\beta',
          updatedAt: DateTime.parse('2026-06-01T09:00:00Z'),
        ),
        _script().copyWith(
          scriptId: 'script-alpha',
          name: 'Alpha',
          sourceFolder: r'C:\stories\alpha',
          updatedAt: DateTime.parse('2026-06-03T09:00:00Z'),
        ),
      ],
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

    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-alpha',
      'script-beta',
    ]);

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-script-sort-menu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-script-sort-title')),
    );
    await tester.pumpAndSettle();

    expect(viewModel.scriptSort, ScriptExhibitionScriptSort.title);
    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-alpha',
      'script-beta',
    ]);

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-script-sort-menu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('script-exhibition-script-sort-unbatchedFirst'),
      ),
    );
    await tester.pumpAndSettle();

    expect(viewModel.scriptSort, ScriptExhibitionScriptSort.unbatchedFirst);
  });

  testWidgets('searches the script shelf and clears the query', (tester) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        _script(),
        _script().copyWith(
          scriptId: 'script-2',
          name: 'Branch Archive',
          sourceFolder: r'C:\stories\branch',
        ),
      ],
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

    expect(
      find.byKey(const ValueKey('script-exhibition-search')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('script-exhibition-script-card-script-2')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('script-exhibition-search')),
      'branch',
    );
    await tester.pumpAndSettle();

    expect(viewModel.scriptSearchQuery, 'branch');
    expect(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('script-exhibition-script-card-script-2')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-clear-search')),
    );
    await tester.pumpAndSettle();

    expect(viewModel.scriptSearchQuery, isEmpty);
    expect(
      find.byKey(const ValueKey('script-exhibition-script-card-script-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('script-exhibition-script-card-script-2')),
      findsOneWidget,
    );
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
                versionId: 'script-image-version-1',
                versionLabel: '导入图片 1',
                frameIndex: 1,
                sourceFileName: '001.json',
                prompt: 'artist:manual, imported json prompt',
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
                versionId: item.versionId,
                versionLabel: item.versionLabel,
                frameIndex: item.frameIndex,
                sourceFileName: item.sourceFileName,
                prompt: item.prompt,
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

    final itemKey = const ValueKey(
      'script-exhibition-item-attachment-script-1-attachment-1',
    );
    expect(find.byKey(itemKey), findsOneWidget);
    expect(find.text('Default 1'), findsOneWidget);
    expect(viewModel.selectedVersion?.label, '导入图片 1');

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

  testWidgets(
      'deletes a version chip from its context menu without deleting the script',
      (tester) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var scripts = [_script()];
    var plans = [_plan()];
    var deletedScriptCount = 0;
    final deletedVersions = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => plans,
      loadGalleryRecords: () async => const [],
      deleteScriptRecord: (script, {bool deleteLocalFiles = false}) async {
        deletedScriptCount += 1;
        scripts = const [];
        plans = const [];
      },
      deleteVersionRecord: (
        script,
        version, {
        bool deleteLocalFiles = false,
      }) async {
        deletedVersions.add('${script.scriptId}:${version.id}');
        plans = [
          for (final plan in plans)
            if (version.id == 'production-${plan.id}')
              plan.copyWith(tasks: const [])
            else
              plan,
        ].where((plan) => plan.tasks.isNotEmpty).toList(growable: false);
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

    final productionVersion = find.byKey(
      const ValueKey('script-exhibition-version-production-plan-1'),
    );
    await tester.tapAt(
      tester.getCenter(productionVersion),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除版本'));
    await tester.pumpAndSettle();

    expect(find.textContaining('不会删除整条剧本展览记录'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-confirm-delete-version')),
    );
    await tester.pumpAndSettle();

    expect(deletedScriptCount, 0);
    expect(deletedVersions, ['script-1:production-plan-1']);
    expect(
      find.byKey(const ValueKey('script-exhibition-detail-script-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('script-exhibition-version-original')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('script-exhibition-version-production-plan-1'),
      ),
      findsNothing,
    );
  });

  testWidgets('delete version dialog can request local image deletion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var scripts = [_script()];
    var plans = [_plan()];
    bool? requestedDeleteLocalFiles;
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => plans,
      loadGalleryRecords: () async => const [],
      deleteVersionRecord: (
        script,
        version, {
        bool deleteLocalFiles = false,
      }) async {
        requestedDeleteLocalFiles = deleteLocalFiles;
        plans = [
          for (final plan in plans)
            if (version.id == 'production-${plan.id}')
              plan.copyWith(tasks: const [])
            else
              plan,
        ].where((plan) => plan.tasks.isNotEmpty).toList(growable: false);
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

    final productionVersion = find.byKey(
      const ValueKey('script-exhibition-version-production-plan-1'),
    );
    await tester.tapAt(
      tester.getCenter(productionVersion),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除版本'));
    await tester.pumpAndSettle();

    final localDelete = find.byKey(
      const ValueKey('script-exhibition-delete-version-local-files'),
    );
    expect(localDelete, findsOneWidget);

    await tester.tap(localDelete);
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-confirm-delete-version')),
    );
    await tester.pumpAndSettle();

    expect(requestedDeleteLocalFiles, isTrue);
  });

  testWidgets('selects multiple version chips for batch deletion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var plans = [_plan(), _planWithTwoCompletedImages()];
    final deletedVersions = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => plans,
      loadGalleryRecords: () async => const [],
      deleteVersionRecord: (
        script,
        version, {
        bool deleteLocalFiles = false,
      }) async {
        deletedVersions.add(
          '${script.scriptId}:${version.id}:$deleteLocalFiles',
        );
        plans = [
          for (final plan in plans)
            if (version.id == 'production-${plan.id}')
              plan.copyWith(tasks: const [])
            else
              plan,
        ].where((plan) => plan.tasks.isNotEmpty).toList(growable: false);
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
      find.byKey(
        const ValueKey('script-exhibition-version-select-production-plan-1'),
      ),
    );
    await tester.tap(
      find.byKey(
        const ValueKey('script-exhibition-version-select-production-plan-2'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已选 2 个版本'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-delete-selected-versions')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('将删除 2 个版本'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey(
            'script-exhibition-delete-selected-versions-local-files'),
      ),
    );
    await tester.tap(
      find.byKey(
        const ValueKey('script-exhibition-confirm-delete-selected-versions'),
      ),
    );
    await tester.pumpAndSettle();

    expect(deletedVersions, [
      'script-1:production-plan-1:true',
      'script-1:production-plan-2:true',
    ]);
    expect(
      find.byKey(const ValueKey('script-exhibition-version-original')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('script-exhibition-version-production-plan-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('script-exhibition-version-production-plan-2')),
      findsNothing,
    );
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

  testWidgets('marquee mode starts selection from script cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        _script(),
        _script().copyWith(
          scriptId: 'script-2',
          name: 'Branch Archive',
          sourceFolder: r'C:\stories\branch',
        ),
      ],
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

    var selectionNotifications = 0;
    void countSelectionNotification() {
      selectionNotifications += 1;
    }

    viewModel.addListener(countSelectionNotification);
    addTearDown(() => viewModel.removeListener(countSelectionNotification));

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-marquee-mode-toggle')),
    );
    await tester.pumpAndSettle();

    final firstCard = find.byKey(
      const ValueKey('script-exhibition-script-card-script-1'),
    );
    final secondCard = find.byKey(
      const ValueKey('script-exhibition-script-card-script-2'),
    );
    final firstRect = tester.getRect(firstCard);
    final secondRect = tester.getRect(secondCard);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.down(firstRect.topLeft + const Offset(8, 8));
    await tester.pump();
    await gesture.moveTo(secondRect.bottomRight - const Offset(8, 8));
    await tester.pump();

    expect(viewModel.selectedScriptIds, isEmpty);
    expect(selectionNotifications, 0);
    final overlayPaint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('script-exhibition-marquee-overlay')),
    );
    final overlay = (overlayPaint.painter as dynamic).overlay as dynamic;
    expect(overlay.selectedRects, hasLength(2));

    await gesture.up();
    await tester.pumpAndSettle();

    expect(viewModel.selectedScriptIds, {'script-1', 'script-2'});
    expect(selectionNotifications, 1);
    expect(
      find.byKey(const ValueKey('script-exhibition-clear-selection')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-clear-selection')),
    );
    await tester.pumpAndSettle();

    expect(viewModel.selectedScriptIds, isEmpty);
  });

  testWidgets('marquee selects scripts and drops them onto a category', (
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
      _script().copyWith(
        scriptId: 'script-3',
        name: '留档档案',
        sourceFolder: r'C:\stories\archive',
      ),
    ];
    final assignments = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      customCategories: const [
        ScriptExhibitionUserCategory(
          id: 'custom:收藏馆区',
          title: '收藏馆区',
          description: '手动归入的剧本。',
          tags: ['自由分类'],
        ),
      ],
      assignScriptCategory: (script, categoryName) async {
        assignments.add('${script.scriptId}:$categoryName');
        scripts = [
          for (final existing in scripts)
            existing.scriptId == script.scriptId
                ? existing.copyWith(categoryNames: [
                    ...existing.categoryNames,
                    categoryName,
                  ])
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

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-marquee-mode-toggle')),
    );
    await tester.pumpAndSettle();

    final firstCard = find.byKey(
      const ValueKey('script-exhibition-script-card-script-1'),
    );
    final secondCard = find.byKey(
      const ValueKey('script-exhibition-script-card-script-2'),
    );
    final firstRect = tester.getRect(firstCard);
    final secondRect = tester.getRect(secondCard);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.down(Offset(firstRect.left + 8, firstRect.top - 8));
    await tester.pump();
    await gesture.moveTo(secondRect.bottomRight + const Offset(8, 8));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(viewModel.selectedScriptIds, {'script-1', 'script-2'});

    final categoryCard = find.byKey(
      const ValueKey('script-exhibition-category-custom:收藏馆区'),
    );
    final firstDragHandle = find.byKey(
      const ValueKey('script-exhibition-drag-handle-script-1'),
    );
    await tester.dragFrom(
      tester.getCenter(firstDragHandle),
      tester.getCenter(categoryCard) - tester.getCenter(firstDragHandle),
      touchSlopY: 0,
    );
    await tester.pumpAndSettle();

    expect(assignments, ['script-1:收藏馆区', 'script-2:收藏馆区']);
    expect(viewModel.selectedScriptIds, isEmpty);
    expect(viewModel.selectedCategoryId,
        ScriptExhibitionRoomViewModel.allCategoryId);
    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-1',
      'script-2',
      'script-3',
    ]);
    expect(
        viewModel.categories
            .singleWhere((category) => category.title == '收藏馆区')
            .count,
        2);

    await tester.tap(categoryCard);
    await tester.pumpAndSettle();

    expect(viewModel.selectedCategoryId, 'custom:收藏馆区');
    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-1',
      'script-2',
    ]);
    expect(find.text('留档档案'), findsNothing);
  });

  testWidgets('dragging one unselected script card assigns it to a category',
      (tester) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var scripts = [
      _script(),
      _script().copyWith(
        scriptId: 'script-2',
        name: 'Branch Archive',
        sourceFolder: r'C:\stories\branch',
      ),
    ];
    final assignments = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      customCategories: const [
        ScriptExhibitionUserCategory(
          id: 'custom:QAQ',
          title: 'QAQ',
          description: 'Manual shelf',
          tags: ['Manual'],
        ),
      ],
      assignScriptCategory: (script, categoryName) async {
        assignments.add('${script.scriptId}:$categoryName');
        scripts = [
          for (final existing in scripts)
            existing.scriptId == script.scriptId
                ? existing.copyWith(categoryNames: [
                    ...existing.categoryNames,
                    categoryName,
                  ])
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

    final categoryCard = find.byKey(
      const ValueKey('script-exhibition-category-custom:QAQ'),
    );

    final firstDragHandle = find.byKey(
      const ValueKey('script-exhibition-drag-handle-script-1'),
    );
    await tester.dragFrom(
      tester.getCenter(firstDragHandle),
      tester.getCenter(categoryCard) - tester.getCenter(firstDragHandle),
      touchSlopY: 0,
    );
    await tester.pumpAndSettle();

    expect(assignments, ['script-1:QAQ']);
    expect(viewModel.selectedScriptIds, isEmpty);
    expect(viewModel.selectedCategoryId,
        ScriptExhibitionRoomViewModel.allCategoryId);
    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-1',
      'script-2',
    ]);
    expect(
        viewModel.categories
            .singleWhere((category) => category.title == 'QAQ')
            .count,
        1);

    await tester.tap(categoryCard);
    await tester.pumpAndSettle();

    expect(viewModel.selectedCategoryId, 'custom:QAQ');
    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-1',
    ]);
  });

  testWidgets('right-click deletes a custom category without deleting scripts',
      (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var scripts = [
      _script().copyWith(categoryNames: const ['收藏馆区']),
      _script().copyWith(
        scriptId: 'script-2',
        name: '旁支档案',
        sourceFolder: r'C:\stories\branch',
        categoryNames: const ['收藏馆区'],
      ),
    ];
    final deletedCategories = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      deleteCategoryRecord: (categoryName) async {
        deletedCategories.add(categoryName);
        scripts = [
          for (final script in scripts)
            script.copyWith(
              categoryNames: script.categoryNames
                  .where(
                    (name) =>
                        name.trim().toLowerCase() !=
                        categoryName.trim().toLowerCase(),
                  )
                  .toList(growable: false),
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

    final categoryCard = find.byKey(
      const ValueKey('script-exhibition-category-custom:收藏馆区'),
    );
    await tester.tapAt(
      tester.getCenter(categoryCard),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除分类'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-confirm-delete-category')),
    );
    await tester.pumpAndSettle();

    expect(deletedCategories, ['收藏馆区']);
    expect(find.text('雨夜档案'), findsWidgets);
    expect(find.text('旁支档案'), findsOneWidget);
    expect(find.text('收藏馆区'), findsNothing);
  });

  testWidgets('delete script button removes only the current category entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var scripts = [
      _script().copyWith(categoryNames: const ['收藏馆区', '备选馆区']),
      _script().copyWith(
        scriptId: 'script-2',
        name: '旁支档案',
        sourceFolder: r'C:\stories\branch',
        categoryNames: const ['收藏馆区'],
      ),
    ];
    final removedCategories = <String>[];
    var wholeScriptDeleteCount = 0;
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      deleteScriptRecord: (script, {bool deleteLocalFiles = false}) async {
        wholeScriptDeleteCount += 1;
        scripts = [
          for (final existing in scripts)
            if (existing.scriptId != script.scriptId) existing,
        ];
      },
      removeScriptCategory: (script, categoryName) async {
        removedCategories.add('${script.scriptId}:$categoryName');
        scripts = [
          for (final existing in scripts)
            existing.scriptId == script.scriptId
                ? existing.copyWith(
                    categoryNames: existing.categoryNames
                        .where(
                          (name) =>
                              name.trim().toLowerCase() !=
                              categoryName.trim().toLowerCase(),
                        )
                        .toList(growable: false),
                  )
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

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-category-custom:收藏馆区')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-delete-script-script-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('从当前分类移除'), findsOneWidget);
    expect(find.textContaining('不会删除剧本、图片、批量结果或原始目录'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey('script-exhibition-confirm-remove-script-category'),
      ),
    );
    await tester.pumpAndSettle();

    expect(wholeScriptDeleteCount, 0);
    expect(removedCategories, ['script-1:收藏馆区']);
    expect(find.text('雨夜档案'), findsNothing);
    expect(find.text('旁支档案'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-category-custom:备选馆区')),
    );
    await tester.pumpAndSettle();

    expect(find.text('雨夜档案'), findsWidgets);
    expect(find.text('旁支档案'), findsNothing);
  });

  testWidgets(
      'custom category script delete never falls back to deleting the whole record',
      (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var wholeScriptDeleteCount = 0;
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        _script().copyWith(categoryNames: const ['收藏馆区']),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      deleteScriptRecord: (script, {bool deleteLocalFiles = false}) async {
        wholeScriptDeleteCount += 1;
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
      find.byKey(const ValueKey('script-exhibition-category-custom:收藏馆区')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-delete-script-script-1')),
    );
    await tester.pumpAndSettle();

    expect(wholeScriptDeleteCount, 0);
    expect(find.text('删除剧本展览记录'), findsNothing);
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
      deleteScriptRecord: (script, {bool deleteLocalFiles = false}) async {
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

  testWidgets('delete script dialog can request local image deletion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var scripts = [_script()];
    bool? requestedDeleteLocalFiles;
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => const [],
      deleteScriptRecord: (script, {bool deleteLocalFiles = false}) async {
        scripts = const [];
        requestedDeleteLocalFiles = deleteLocalFiles;
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
      find.byKey(
        const ValueKey('script-exhibition-delete-script-detail-script-1'),
      ),
    );
    await tester.pumpAndSettle();

    final localDelete = find.byKey(
      const ValueKey('script-exhibition-delete-local-files'),
    );
    expect(localDelete, findsOneWidget);

    await tester.tap(localDelete);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-confirm-delete-script')),
    );
    await tester.pumpAndSettle();

    expect(requestedDeleteLocalFiles, isTrue);
  });

  testWidgets('deletes a gallery item from the waterfall', (tester) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var records = [_galleryRecord()];
    final deletedItems = <ScriptExhibitionItem>[];
    final deleteLocalFilesValues = <bool>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => records,
      deleteItemRecord: (item, {bool deleteLocalFiles = false}) async {
        deletedItems.add(item);
        deleteLocalFilesValues.add(deleteLocalFiles);
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

    final localDelete = find.byKey(
      const ValueKey('script-exhibition-delete-item-local-files'),
    );
    expect(localDelete, findsOneWidget);
    await tester.tap(localDelete);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('script-exhibition-confirm-delete-item')),
    );
    await tester.pumpAndSettle();

    expect(deletedItems.single.galleryRecordId, 'gallery-1');
    expect(deleteLocalFilesValues, [isTrue]);
    expect(find.byKey(itemKey), findsNothing);
  });

  testWidgets(
    'waterfall card sets the current script cover instead of saving assets',
    (tester) async {
      tester.view.physicalSize = const Size(1320, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final coverItems = <ScriptExhibitionItem>[];
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
        setCoverItemRecord: (item) async {
          coverItems.add(item);
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
      expect(saveAction, findsNothing);

      final setCoverAction = find.byKey(
        const ValueKey(
          'script-exhibition-set-cover-production-plan-1-task-1',
        ),
      );
      expect(setCoverAction, findsOneWidget);
      expect(
        tester.widget<IconButton>(setCoverAction).tooltip,
        '设为当前剧本封面',
      );

      await tester.tap(setCoverAction);
      await tester.pumpAndSettle();

      expect(coverItems.single.id, 'production-plan-1-task-1');
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

  testWidgets('script shelf expands large script lists near scroll end', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final scripts = [
      for (var index = 0; index < 60; index += 1)
        _script().copyWith(
          scriptId: 'script-$index',
          name: 'Script $index',
          sourceFolder: 'C:\\stories\\bulk\\$index',
        ),
    ];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );
    await tester.runAsync(() async {
      await viewModel.load();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ScriptExhibitionRoomPage(
          viewModel: viewModel,
          onSendToScriptWorkbench: (_) {},
          onSendToWorkbench: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    Finder scriptCards() => find.byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> &&
              key.value.startsWith('script-exhibition-script-card-');
        });

    final initialCount = scriptCards().evaluate().length;
    expect(initialCount, greaterThanOrEqualTo(12));
    expect(initialCount, lessThan(60));
    expect(
      find.byKey(const ValueKey('script-exhibition-script-card-script-40')),
      findsNothing,
    );

    final scrollView = find.byKey(
      const ValueKey('script-exhibition-scroll-view'),
    );
    for (var attempt = 0; attempt < 6; attempt += 1) {
      await tester.drag(scrollView, const Offset(0, -900));
      await tester.pump();
      await tester.pump();
      if (find
          .byKey(const ValueKey('script-exhibition-script-card-script-40'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    expect(scriptCards().evaluate().length, greaterThan(initialCount));
    expect(
      find.byKey(const ValueKey('script-exhibition-script-card-script-40')),
      findsOneWidget,
    );
  });

  testWidgets('keeps the category strip pinned while scrolling the shelf', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final scripts = [
      for (var index = 0; index < 48; index += 1)
        _script().copyWith(
          scriptId: 'script-$index',
          name: 'Script $index',
          sourceFolder: 'C:\\stories\\sticky\\$index',
        ),
    ];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );
    await tester.runAsync(() async {
      await viewModel.load();
    });

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

    final allCategory = find.byKey(
      const ValueKey('script-exhibition-category-all'),
    );
    final initialTop = tester.getTopLeft(allCategory).dy;
    expect(initialTop, greaterThan(0));

    final scrollView = find.byKey(
      const ValueKey('script-exhibition-scroll-view'),
    );
    await tester.drag(scrollView, const Offset(0, -900));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(allCategory, findsOneWidget);
    final pinnedTop = tester.getTopLeft(allCategory).dy;
    expect(pinnedTop, lessThan(initialTop));
    expect(pinnedTop, lessThanOrEqualTo(1));
  });

  testWidgets('script shelf enables cover image paths in small batches', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.parse('2026-06-02T08:00:00Z');
    final readCoverIndexes = <int>{};
    final scripts = [
      for (var index = 0; index < 20; index += 1)
        () {
          final scriptId = 'cover-script-$index';
          final item = _CountingScriptCoverItem(
            id: 'cover-item-$index',
            scriptId: scriptId,
            scriptTitle: 'Cover Script $index',
            sourceFolder: 'C:\\stories\\cover\\$index',
            versionId: 'cover-version-$index',
            versionLabel: 'Cover',
            frameIndex: index,
            updatedAt: now,
            imagePath: 'C:\\covers\\cover-$index.png',
            onImagePathRead: () => readCoverIndexes.add(index),
          );
          return ScriptExhibitionScript(
            scriptId: scriptId,
            title: 'Cover Script $index',
            sourceFolder: 'C:\\stories\\cover\\$index',
            updatedAt: now,
            versions: [
              ScriptExhibitionVersion(
                id: 'cover-version-$index',
                label: 'Cover',
                description: 'Cover batch test',
                updatedAt: now,
                items: [item],
              ),
            ],
            status: ScriptExhibitionScriptStatus.active,
            originalCount: 0,
            generatedImageCount: 1,
            imageLikeItemCount: 1,
            hasImage: true,
            coverItem: item,
            pendingCount: 0,
            firstNeedsActionItem: null,
          );
        }(),
    ];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => const [],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    )
      ..snapshot = ScriptExhibitionSnapshot(
        scripts: scripts,
        totalImageCount: scripts.length,
        generatedImageCount: scripts.length,
        needsActionCount: 0,
      )
      ..isLoading = true;

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
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(readCoverIndexes, {0, 1, 2, 3});

    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    expect(readCoverIndexes.containsAll({0, 1, 2, 3, 4, 5}), isTrue);
    expect(readCoverIndexes.length, lessThanOrEqualTo(12));

    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    expect(readCoverIndexes.containsAll({0, 1, 2, 3, 4, 5}), isTrue);
  });
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  await _pumpUntil(tester, () => finder.evaluate().isNotEmpty,
      timeout: timeout);
  expect(finder, findsOneWidget);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() isReady, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final end = tester.binding.clock.fromNowBy(timeout);
  while (tester.binding.clock.now().isBefore(end)) {
    if (isReady()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
}

ScriptExhibitionItem _scriptExhibitionDetailItem(
    int index, DateTime updatedAt) {
  return ScriptExhibitionItem(
    id: 'window-item-$index',
    scriptId: 'script-window',
    scriptTitle: 'Window Test',
    sourceFolder: r'C:\stories\window',
    versionId: 'version-window',
    versionLabel: 'Window',
    sourceKind: ScriptExhibitionItemSourceKind.generated,
    frameIndex: index,
    sourceFileName: 'frame-$index.json',
    title: 'Frame $index',
    subtitle: 'Window item',
    prompt: 'window test frame $index',
    imagePath: '',
    statusLabel: 'Ready',
    updatedAt: updatedAt,
  );
}

TokenizerScript _script({
  Map<String, dynamic> generationParams = const {},
  String sourceFileName = '001.json',
  String sourcePath = r'C:\stories\rain\001.json',
  TokenizerScriptSourceKind sourceKind = TokenizerScriptSourceKind.json,
  String defaultImagePath = r'C:\stories\rain\001.png',
}) {
  final now = DateTime.parse('2026-06-01T09:00:00Z');
  final source = TokenizerSourceFile(
    fileId: 'source-1',
    fileName: sourceFileName,
    path: sourcePath,
    kind: sourceKind,
    defaultImagePath: defaultImagePath,
  );
  return TokenizerScript(
    scriptId: 'script-1',
    name: '雨夜档案',
    sourceFolder: r'C:\stories\rain',
    sourceMode: TokenizerScriptSourceMode.auto,
    createdAt: now,
    updatedAt: now,
    status: TokenizerScriptStatus.ready,
    sourceFiles: [source],
    sampleFileIds: const ['source-1'],
    characterIdentities: const [],
    styleStages: const [],
    knowledgeCandidates: const [],
    imageTasks: [
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
        generationParams: generationParams,
        confidence: 0.9,
        reviewStatus: TokenizerTaskReviewStatus.confirmed,
        details: const TokenizerParseDetails(),
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
    defaultImagePath: r'C:\stories\rain\001.png',
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
        title: 'Same Frame Rerun',
        scriptId: 'script-1',
        scriptName: '雨夜档案',
        scriptPath: r'C:\stories\rain',
        recastRunId: 'run-2',
        frameIndex: 1,
        sourceFileName: '001-rerun.json',
        payload: const {'input': 'same frame rerun, green eyes'},
        status: ProductionTaskStatus.completed,
        outputImagePath: r'C:\out\frame-01-rerun.png',
        createdAt: now.add(const Duration(minutes: 1)),
        updatedAt: now.add(const Duration(minutes: 1)),
      ),
      ProductionTask.scriptRecastFrame(
        id: 'task-3',
        planId: 'plan-2',
        title: 'Other Frame',
        scriptId: 'script-1',
        scriptName: '雨夜档案',
        scriptPath: r'C:\stories\rain',
        recastRunId: 'run-2',
        frameIndex: 2,
        sourceFileName: '002.json',
        payload: const {'input': 'other frame, amber eyes'},
        status: ProductionTaskStatus.completed,
        outputImagePath: r'C:\out\frame-02.png',
        createdAt: now.add(const Duration(minutes: 2)),
        updatedAt: now.add(const Duration(minutes: 2)),
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

final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/l7G6GQAAAABJRU5ErkJggg==',
);
