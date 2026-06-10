import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_command/flutter_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/character_config.dart';
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/models/info_card_content.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/models/studio_asset_capture.dart';
import 'package:nai_casrand/data/studio/models/studio_gallery_record.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_capture_service.dart';
import 'package:nai_casrand/data/studio/services/studio_gallery_service.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_classifier.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:nai_casrand/ui/core/app_display_settings.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_core/widgets/prompt_tag_display.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_asset_capture_host.dart';
import 'package:nai_casrand/ui/studio_shell/widgets/studio_gallery_page.dart';

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
  final List<String> restoredIds = [];

  @override
  Future<List<StudioGalleryRecord>> loadRecords() async {
    return records;
  }

  @override
  void restoreToWorkbench(StudioGalleryRecord record, PayloadConfig target) {
    restoredIds.add(record.id);
    record.restoreTo(target);
  }
}

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

StudioGalleryRecord _record({
  required String id,
  required String prompt,
  required String title,
  String? imagePath,
  String? info,
  Map<String, dynamic> additionalInfo = const {},
}) {
  return StudioGalleryRecord.fromPayloadConfig(
    config: _payload(prompt: prompt),
    id: id,
    createdAt: DateTime.parse('2026-05-22T08:00:00Z'),
    title: title,
    imagePath: imagePath,
    info: info ?? prompt,
    additionalInfo: additionalInfo,
  );
}

StudioGalleryRecord _scriptRecord({
  required String id,
  required String prompt,
  required String title,
  String imagePath = r'C:\script-out\frame-01.png',
}) {
  return StudioGalleryRecord.fromRecastPayload(
    payload: {'input': prompt},
    id: id,
    createdAt: DateTime.parse('2026-05-22T08:30:00Z'),
    title: title,
    imagePath: imagePath,
    info: prompt,
    provenance: StudioRecastProvenance(
      scriptId: 'script-1',
      scriptName: 'Pilot Script',
      scriptPath: r'C:\stories\pilot',
      recastRunId: 'run-1',
      productionPlanId: 'plan-1',
      productionPlanFingerprint: 'plan-fingerprint',
      taskId: 'task-1',
      frameIndex: 1,
      sourceFileName: 'nai_1.json',
      payloadFingerprint: 'payload-fingerprint',
      mappingConfigFingerprint: 'mapping-fingerprint',
      outputImagePath: imagePath,
    ),
  );
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<PayloadConfig>(_payload());
    GetIt.I.registerSingleton<CommandStatus>(CommandStatus());
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

  testWidgets('gallery page reflects current generated result count', (
    tester,
  ) async {
    final commandStatus = GetIt.I<CommandStatus>();
    commandStatus.commandList.add(
      Command.createSyncNoParam<InfoCardContent>(
        () =>
            const InfoCardContent(title: 'one', info: 'ok', additionalInfo: {}),
        initialValue: const InfoCardContent(
          title: 'one',
          info: 'ok',
          additionalInfo: {},
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioGalleryPage(
          viewModel: GenerationPageViewmodel(),
          galleryService: _FakeGalleryService(const []),
          payloadConfig: GetIt.I<PayloadConfig>(),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('gallery-header-title')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gallery-session-metric')),
      findsOneWidget,
    );
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('gallery page restores a saved record to the workbench', (
    tester,
  ) async {
    final payload = GetIt.I<PayloadConfig>();
    final record = _record(
      id: 'record-1',
      prompt: 'gallery prompt',
      title: 'favorite.png',
      info: 'gallery prompt',
      additionalInfo: const {'seed': 777},
    );
    final galleryService = _FakeGalleryService([record]);

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioGalleryPage(
          viewModel: GenerationPageViewmodel(),
          galleryService: galleryService,
          payloadConfig: payload,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('favorite.png'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey('gallery-card-restore-record-1')),
    );
    await tester.pump();

    expect(galleryService.restoredIds, ['record-1']);
    expect(payload.overridePrompt, 'gallery prompt');
  });

  testWidgets('gallery page filters by search and metadata status', (
    tester,
  ) async {
    final records = [
      _record(
        id: 'parsed-1',
        prompt: 'city prompt',
        title: 'city-night.png',
        additionalInfo: const {'seed': 12983122, 'model': 'NAI Diffusion'},
      ),
      _record(
        id: 'missing-1',
        prompt: 'fallback prompt',
        title: 'fallback.png',
        imagePath: r'C:\outputs\fallback.png',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioGalleryPage(
          viewModel: GenerationPageViewmodel(),
          galleryService: _FakeGalleryService(records),
          payloadConfig: GetIt.I<PayloadConfig>(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('gallery-card-parsed-1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gallery-card-missing-1')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('gallery-search')),
      'city',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('gallery-card-parsed-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('gallery-card-missing-1')), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('gallery-search')), '');
    await tester.tap(find.byKey(const ValueKey('gallery-filter-missing')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('gallery-card-parsed-1')), findsNothing);
    expect(
      find.byKey(const ValueKey('gallery-card-missing-1')),
      findsOneWidget,
    );
  });

  testWidgets('gallery page shows detail drawer and fallback file info', (
    tester,
  ) async {
    final payload = GetIt.I<PayloadConfig>();
    final records = [
      _record(
        id: 'parsed-1',
        prompt: 'artist:gallery_artist, watercolor',
        title: 'city-night.png',
        additionalInfo: const {'seed': 12983122, 'sampler': 'k_euler'},
      ),
      _record(
        id: 'missing-1',
        prompt: 'fallback prompt',
        title: 'fallback.png',
        imagePath: r'C:\outputs\fallback.png',
      ),
    ];
    final galleryService = _FakeGalleryService(records);

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioGalleryPage(
          viewModel: GenerationPageViewmodel(),
          galleryService: galleryService,
          payloadConfig: payload,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.ensureVisible(
      find.byKey(const ValueKey('gallery-card-parsed-1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('gallery-card-details-parsed-1')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('gallery-detail-drawer')), findsOneWidget);
    expect(find.text('12983122'), findsOneWidget);
    expect(find.text('k_euler'), findsOneWidget);
    expect(find.text('保存为素材'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gallery-save-asset-parsed-1-artist-chain-0')),
      findsOneWidget,
    );
    expect(find.text('保存素材'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('gallery-card-missing-1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('gallery-card-details-missing-1')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(r'C:\outputs\fallback.png'), findsWidgets);

    final restoreButton = find.byKey(const ValueKey('gallery-detail-restore'));
    await tester.ensureVisible(restoreButton);
    await tester.tap(restoreButton);
    await tester.pump();

    expect(galleryService.restoredIds, ['missing-1']);
    expect(payload.overridePrompt, 'fallback prompt');
  });

  testWidgets('gallery page leaves script-scoped records out of the gallery', (
    tester,
  ) async {
    final records = [
      _record(
        id: 'creative-1',
        prompt: 'standalone prompt',
        title: 'standalone.png',
      ),
      _scriptRecord(
        id: 'script-1',
        prompt: 'script generated prompt',
        title: 'script-frame.png',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioGalleryPage(
          viewModel: GenerationPageViewmodel(),
          galleryService: _FakeGalleryService(records),
          payloadConfig: GetIt.I<PayloadConfig>(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const ValueKey('gallery-card-creative-1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('gallery-card-script-1')), findsNothing);
    expect(find.text('script-frame.png'), findsNothing);
  });

  testWidgets(
    'gallery image preview keeps workbench character layers before grouping',
    (tester) async {
      tester.view.physicalSize = const Size(1320, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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
      final record = StudioGalleryRecord.fromPayloadConfig(
        config: payload,
        id: 'role-image',
        createdAt: DateTime.parse('2026-05-22T08:00:00Z'),
        title: 'role.png',
        imagePath: r'C:\outputs\role.png',
        info: 'base scene, first character, second character',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.build(),
          home: StudioGalleryPage(
            viewModel: GenerationPageViewmodel(),
            galleryService: _FakeGalleryService([record]),
            payloadConfig: GetIt.I<PayloadConfig>(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byKey(const ValueKey('gallery-card-role-image')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final roleOne = find.byKey(
        const ValueKey('gallery-preview-prompt-group-role-image-role-1'),
      );
      final roleTwo = find.byKey(
        const ValueKey('gallery-preview-prompt-group-role-image-role-2'),
      );
      expect(roleOne, findsOneWidget);
      expect(roleTwo, findsOneWidget);
      expect(
        find.descendant(of: roleOne, matching: find.text('first character')),
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
    },
  );

  testWidgets(
    'gallery page previews actual image records like the exhibition',
    (tester) async {
      tester.view.physicalSize = const Size(1320, 980);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final record = _record(
        id: 'image-1',
        prompt: 'artist:gallery_artist, watercolor, blue dress',
        title: 'one.png',
        imagePath: r'C:\outputs\one.png',
      );
      final nextRecord = _record(
        id: 'image-2',
        prompt: 'gallery second prompt, red cloak',
        title: 'two.png',
        imagePath: r'C:\outputs\two.png',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.build(),
          home: StudioGalleryPage(
            viewModel: GenerationPageViewmodel(),
            galleryService: _FakeGalleryService([record, nextRecord]),
            payloadConfig: GetIt.I<PayloadConfig>(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byKey(const ValueKey('gallery-card-image-image-1')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('gallery-card-image-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byKey(const ValueKey('gallery-image-viewer-dialog')),
        findsOneWidget,
      );
      final restoreButton = find.byKey(
        const ValueKey('gallery-preview-restore'),
      );
      expect(
        find.descendant(of: restoreButton, matching: find.text('送回工作台')),
        findsOneWidget,
      );
      expect(find.text('Restore'), findsNothing);
      expect(
        find.byKey(const ValueKey('gallery-zoomable-image-viewer')),
        findsOneWidget,
      );
      final tagDisplay = tester.widget<PromptTagDisplay>(
        find.byKey(const ValueKey('gallery-preview-prompt-tags-image-1')),
      );
      expect(tagDisplay.text, 'artist:gallery_artist, watercolor, blue dress');
      expect(tagDisplay.defaultTranslated, isTrue);
      expect(tagDisplay.initialLayoutMode, PromptTagLayoutMode.grouped);
      expect(
        find.byKey(
          const ValueKey('gallery-preview-save-asset-image-1-artist-chain-0'),
        ),
        findsNothing,
      );
      final saveAction = find.byKey(
        const ValueKey(
          'gallery-preview-prompt-save-asset-image-1-artist-chain-0',
        ),
      );
      expect(saveAction, findsOneWidget);
      expect(
        find.descendant(of: saveAction, matching: find.text('保存为素材')),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('2/2'), findsOneWidget);
      expect(find.text('gallery second prompt'), findsWidgets);

      await tester.tap(
        find.byKey(const ValueKey('gallery-preview-fullscreen-toggle')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byKey(const ValueKey('gallery-image-viewer-fullscreen')),
        findsOneWidget,
      );
    },
  );

  testWidgets('gallery preview save uses current artist block tags', (
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
    final record = _record(
      id: 'image-1',
      prompt: 'artist:gallery_artist, watercolor, blue dress',
      title: 'one.png',
      imagePath: r'C:\outputs\one.png',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioAssetCaptureHost(
          service: captureService,
          child: StudioGalleryPage(
            viewModel: GenerationPageViewmodel(),
            galleryService: _FakeGalleryService([record]),
            payloadConfig: GetIt.I<PayloadConfig>(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const ValueKey('gallery-card-image-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final saveAction = find.byKey(
      const ValueKey(
        'gallery-preview-prompt-save-asset-image-1-artist-chain-0',
      ),
    );
    expect(saveAction, findsOneWidget);

    await tester.tap(saveAction);
    await tester.pump();

    final chain = captureService.previewedDraft?.artistChain;
    expect(chain?.tags, ['artist:gallery_artist', 'watercolor']);
    expect(chain?.styleTags, isEmpty);
    expect(chain?.prompt, 'artist:gallery_artist, watercolor');
  });

  testWidgets('gallery preview reserves the same readable prompt space', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1480, 1260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppDisplaySettings.setImagePreviewDialogHeight(880, persist: false);

    final record = _record(
      id: 'long-image-1',
      prompt: _longPreviewPrompt,
      title: 'long-prompt.png',
      imagePath: r'C:\outputs\long-prompt.png',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioGalleryPage(
          viewModel: GenerationPageViewmodel(),
          galleryService: _FakeGalleryService([record]),
          payloadConfig: GetIt.I<PayloadConfig>(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const ValueKey('gallery-card-long-image-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final tagDisplay = tester.widget<PromptTagDisplay>(
      find.byKey(const ValueKey('gallery-preview-prompt-tags-long-image-1')),
    );
    expect(tagDisplay.defaultTranslated, isTrue);
    expect(tagDisplay.showLayoutControls, isTrue);
    expect(tagDisplay.initialLayoutMode, PromptTagLayoutMode.grouped);

    final windowHeight = tester
        .getSize(find.byKey(const ValueKey('gallery-image-viewer-windowed')))
        .height;
    final imageHeight = tester
        .getSize(find.byKey(const ValueKey('gallery-zoomable-image-viewer')))
        .height;
    final promptHeight = tester
        .getSize(find.byKey(const ValueKey('gallery-preview-prompt-scroll')))
        .height;
    expect(windowHeight, 880);
    expect(imageHeight, greaterThan(420));
    expect(promptHeight, greaterThanOrEqualTo(300));
    expect(promptHeight, lessThanOrEqualTo(320));
  });
}

const _longPreviewPrompt =
    'detailed eyes, 1.3::best quality, amazing quality, very aesthetic, '
    'highres, incredibly absurdres, 0.9::artist:ahemaru, '
    '1.5::artist:channel, 2.5::artist:ie, -6.0::artist collaboration, '
    '1girl, 1boy, outdoors, street, arato asato, ratatatat74, eonsang, '
    'freng, null, year 2025, year 2024, motion lines, day, sunlight, '
    'japanese text, text, simple illustration, mature, white dress, '
    'blue eyes, long hair, standing, close-up, looking at viewer, smile';
