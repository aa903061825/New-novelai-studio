import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:image/image.dart' as img;
import 'package:novel_studio/data/models/command_status.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/studio/models/studio_director_tool.dart';
import 'package:novel_studio/data/studio/models/studio_gallery_record.dart';
import 'package:novel_studio/data/studio/services/studio_gallery_service.dart';
import 'package:novel_studio/data/studio/tools/translation_cache.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';
import 'package:novel_studio/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_theme.dart';
import 'package:novel_studio/ui/studio_shell/widgets/studio_gallery_page.dart';

PayloadConfig _payload({String prompt = ''}) {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: [prompt], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({}),
    overridePrompt: prompt,
    useOverridePrompt: prompt.isNotEmpty,
    useCharacterPromptWithOverride: false,
  );
}

class _FakeGalleryService extends StudioGalleryService {
  _FakeGalleryService(this.records)
      : super(workspaceService: WorkspaceService());

  final List<StudioGalleryRecord> records;

  @override
  Future<List<StudioGalleryRecord>> loadRecords() async => records;
}

class _TrackingGalleryOperationViewmodel extends GenerationPageViewmodel {
  final List<String> enhancedRecordIds = [];
  final List<String> upscaledRecordIds = [];
  final List<String> directorRecordIds = [];
  final List<StudioDirectorToolOptions> directorOptions = [];
  final List<String> inpaintRecordIds = [];
  final List<String> inpaintMaskPaths = [];
  Completer<void>? enhanceCompleter;

  @override
  Future<void> enhanceGalleryRecord(StudioGalleryRecord record) async {
    enhancedRecordIds.add(record.id);
    await enhanceCompleter?.future;
  }

  @override
  Future<void> upscaleGalleryRecord(StudioGalleryRecord record) async {
    upscaledRecordIds.add(record.id);
  }

  @override
  Future<void> runDirectorToolGalleryRecord(
    StudioGalleryRecord record,
    StudioDirectorToolOptions options,
  ) async {
    directorRecordIds.add(record.id);
    directorOptions.add(options);
  }

  @override
  Future<void> runInpaintGalleryRecord(
    StudioGalleryRecord record, {
    required String maskImagePath,
    double strength = 1.0,
  }) async {
    inpaintRecordIds.add(record.id);
    inpaintMaskPaths.add(maskImagePath);
  }
}

StudioGalleryRecord _record({
  required String id,
  required String prompt,
  required String title,
  String? imagePath,
  StudioGalleryLineage? lineage,
}) {
  return StudioGalleryRecord.fromPayloadConfig(
    config: _payload(prompt: prompt),
    id: id,
    createdAt: DateTime.parse('2026-05-22T08:00:00Z'),
    title: title,
    imagePath: imagePath,
    info: prompt,
    lineage: lineage,
  );
}

File _writePngFixture(Directory directory, String name) {
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  file.writeAsBytesSync(
    img.encodePng(img.Image(width: 1, height: 1, numChannels: 4)),
  );
  return file;
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<PayloadConfig>(_payload());
    GetIt.I.registerSingleton<CommandStatus>(CommandStatus());
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000)
        ..setCached(
          'enhanced prompt',
          'enhanced prompt',
          source: 'test',
        )
        ..setCached(
          'missing prompt',
          'missing prompt',
          source: 'test',
        ),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('gallery operations show feedback before async work finishes', (
    tester,
  ) async {
    final tempDir = Directory(
      '${Directory.current.path}${Platform.pathSeparator}'
      'build${Platform.pathSeparator}gallery_operation_feedback_test',
    );
    tempDir.createSync(recursive: true);
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final imageFile = _writePngFixture(tempDir, 'feedback.png');
    final viewModel = _TrackingGalleryOperationViewmodel()
      ..enhanceCompleter = Completer<void>();
    final record = _record(
      id: 'feedback-1',
      prompt: 'feedback prompt',
      title: 'feedback.png',
      imagePath: imageFile.path,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioGalleryPage(
          viewModel: viewModel,
          galleryService: _FakeGalleryService([record]),
          payloadConfig: GetIt.I<PayloadConfig>(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.ensureVisible(
      find.byKey(const ValueKey('gallery-detail-enhance')),
    );
    await tester.tap(find.byKey(const ValueKey('gallery-detail-enhance')));
    await tester.pump();

    expect(viewModel.enhancedRecordIds, ['feedback-1']);
    expect(find.text('正在提交增强...'), findsOneWidget);

    viewModel.enhanceCompleter!.complete();
    await tester.pumpAndSettle();

    expect(find.text('已开始增强'), findsOneWidget);
  });

  testWidgets(
    'operation lineage and actions are visible for readable gallery images',
    (tester) async {
      tester.view.physicalSize = const Size(1320, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir = Directory(
        '${Directory.current.path}${Platform.pathSeparator}'
        'build${Platform.pathSeparator}gallery_operation_actions_test',
      );
      tempDir.createSync(recursive: true);
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final imageFile = _writePngFixture(tempDir, 'one.png');
      final viewModel = _TrackingGalleryOperationViewmodel();
      final records = [
        _record(
          id: 'operation-1',
          prompt: 'enhanced prompt',
          title: 'enhanced.png',
          imagePath: imageFile.path,
          lineage: const StudioGalleryLineage(
            operation: StudioGalleryOperation.enhance,
            sourceRecordId: 'source-1',
            sourceImagePath: r'C:\outputs\source.png',
            parameters: {'strength': 0.35, 'noise': 0.1},
          ),
        ),
        _record(
          id: 'missing-image',
          prompt: 'missing prompt',
          title: 'missing.png',
          imagePath: r'C:\outputs\missing.png',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.build(),
          home: StudioGalleryPage(
            viewModel: viewModel,
            galleryService: _FakeGalleryService(records),
            payloadConfig: GetIt.I<PayloadConfig>(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byKey(const ValueKey('gallery-detail-lineage-operation-1')),
        findsOneWidget,
      );
      expect(find.text('Enhance'), findsNothing);
      expect(find.text('增强'), findsWidgets);
      expect(find.text('操作来源'), findsOneWidget);
      expect(find.text('source-1'), findsWidgets);
      expect(find.textContaining('strength: 0.35'), findsWidgets);
      expect(
        find.byKey(const ValueKey('gallery-card-more-operation-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('gallery-card-more-missing-image')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('gallery-card-details-operation-1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('gallery-card-use-as-i2i-operation-1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('gallery-card-restore-operation-1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('gallery-card-enhance-operation-1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('gallery-card-upscale-operation-1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('gallery-card-director-operation-1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('gallery-card-inpaint-operation-1')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('gallery-card-more-operation-1')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('gallery-card-menu-useAsI2i-operation-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('gallery-card-menu-restore-operation-1')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('gallery-detail-enhance')),
      );
      await tester.tap(
        find.byKey(const ValueKey('gallery-detail-enhance')),
      );
      await tester.pump();
      expect(viewModel.enhancedRecordIds, ['operation-1']);

      await tester.ensureVisible(
        find.byKey(const ValueKey('gallery-detail-upscale')),
      );
      await tester.tap(
        find.byKey(const ValueKey('gallery-detail-upscale')),
      );
      await tester.pump();
      expect(viewModel.upscaledRecordIds, ['operation-1']);

      await tester.ensureVisible(
        find.byKey(const ValueKey('gallery-detail-director')),
      );
      await tester.tap(
        find.byKey(const ValueKey('gallery-detail-director')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('gallery-director-tool-dialog')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('gallery-director-tool-option-colorize')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('gallery-director-tool-prompt')),
        'blue eyes',
      );
      await tester.tap(find.byKey(const ValueKey('gallery-director-tool-run')));
      await tester.pumpAndSettle();
      expect(viewModel.directorRecordIds, ['operation-1']);
      expect(
          viewModel.directorOptions.single.tool, StudioDirectorTool.colorize);
      expect(viewModel.directorOptions.single.prompt, 'blue eyes');

      await tester.ensureVisible(
        find.byKey(const ValueKey('gallery-detail-inpaint')),
      );
      await tester.tap(
        find.byKey(const ValueKey('gallery-detail-inpaint')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('gallery-inpaint-dialog')),
        findsOneWidget,
      );
      var runButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('gallery-inpaint-run')),
      );
      expect(runButton.onPressed, isNull);
      await tester
          .tap(find.byKey(const ValueKey('gallery-inpaint-paint-mask')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('gallery-inpaint-clear-mask')));
      await tester.pumpAndSettle();
      runButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('gallery-inpaint-run')),
      );
      expect(runButton.onPressed, isNull);
      await tester
          .tap(find.byKey(const ValueKey('gallery-inpaint-paint-mask')));
      await tester.pumpAndSettle();
      runButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('gallery-inpaint-run')),
      );
      expect(runButton.onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('gallery-inpaint-run')));
      await tester.pumpAndSettle();
      expect(viewModel.inpaintRecordIds, ['operation-1']);
      expect(viewModel.inpaintMaskPaths, hasLength(1));
      final maskBytes =
          File(viewModel.inpaintMaskPaths.single).readAsBytesSync();
      final maskImage = img.decodePng(maskBytes);
      expect(maskImage?.width, 1);
      expect(maskImage?.height, 1);

      await tester.ensureVisible(
        find.byKey(const ValueKey('gallery-detail-preview-operation-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('gallery-detail-preview-operation-1')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('gallery-preview-lineage-operation-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('gallery-preview-enhance')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('gallery-preview-upscale')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('gallery-preview-director')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('gallery-preview-inpaint')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'gallery detail actions stay localized inside the desktop drawer',
    (tester) async {
      tester.view.physicalSize = const Size(2200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir = Directory(
        '${Directory.current.path}${Platform.pathSeparator}'
        'build${Platform.pathSeparator}gallery_detail_actions_layout_test',
      );
      tempDir.createSync(recursive: true);
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final imageFile = _writePngFixture(tempDir, 'one.png');
      final records = [
        _record(
          id: 'operation-1',
          prompt: 'enhanced prompt',
          title: 'enhanced.png',
          imagePath: imageFile.path,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.build(),
          home: StudioGalleryPage(
            viewModel: _TrackingGalleryOperationViewmodel(),
            galleryService: _FakeGalleryService(records),
            payloadConfig: GetIt.I<PayloadConfig>(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Enhance'), findsNothing);
      expect(find.text('Upscale'), findsNothing);
      expect(find.text('Director'), findsNothing);
      expect(find.text('Inpaint'), findsNothing);
      expect(find.text('增强'), findsWidgets);
      expect(find.text('放大'), findsOneWidget);
      expect(find.text('导演工具'), findsOneWidget);
      expect(find.text('重绘'), findsOneWidget);
      expect(find.text('元数据缺失'), findsWidgets);

      final drawerRect = tester.getRect(
        find.byKey(const ValueKey('gallery-detail-drawer')),
      );
      final actionsRect = tester.getRect(
        find.byKey(const ValueKey('gallery-detail-actions')),
      );
      expect(actionsRect.left, greaterThanOrEqualTo(drawerRect.left));
      expect(actionsRect.right, lessThanOrEqualTo(drawerRect.right + 0.5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'inpaint and preview actions fit a constrained viewport',
    (tester) async {
      tester.view.physicalSize = const Size(520, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tempDir = Directory(
        '${Directory.current.path}${Platform.pathSeparator}'
        'build${Platform.pathSeparator}'
        'gallery_operation_actions_constrained_test',
      );
      tempDir.createSync(recursive: true);
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final imageFile = _writePngFixture(tempDir, 'one.png');
      final viewModel = _TrackingGalleryOperationViewmodel();
      final records = [
        _record(
          id: 'operation-1',
          prompt: 'enhanced prompt',
          title: 'enhanced.png',
          imagePath: imageFile.path,
          lineage: const StudioGalleryLineage(
            operation: StudioGalleryOperation.enhance,
            sourceRecordId: 'source-1',
            parameters: {'strength': 0.35},
          ),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.build(),
          home: StudioGalleryPage(
            viewModel: viewModel,
            galleryService: _FakeGalleryService(records),
            payloadConfig: GetIt.I<PayloadConfig>(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.ensureVisible(
        find.byKey(const ValueKey('gallery-detail-inpaint')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('gallery-detail-inpaint')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('gallery-inpaint-dialog')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('gallery-inpaint-run')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('gallery-detail-preview-operation-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('gallery-detail-preview-operation-1')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('gallery-preview-inpaint')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('gallery-preview-director')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
