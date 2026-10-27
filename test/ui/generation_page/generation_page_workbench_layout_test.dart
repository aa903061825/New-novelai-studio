import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_command/flutter_command.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/models/api_request.dart';
import 'package:novel_studio/data/models/character_config.dart';
import 'package:novel_studio/data/models/command_status.dart';
import 'package:novel_studio/data/models/generation_size.dart';
import 'package:novel_studio/data/models/i2i_config.dart';
import 'package:novel_studio/data/models/info_card_content.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/precise_reference_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/models/vibe_config.dart';
import 'package:novel_studio/data/models/vibe_config_v4.dart';
import 'package:novel_studio/data/services/nai_account_usage_service.dart';
import 'package:novel_studio/data/studio/services/studio_asset_catalog_service.dart';
import 'package:novel_studio/data/studio/services/studio_workbench_asset_service.dart';
import 'package:novel_studio/data/studio/services/workbench_transfer_service.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';
import 'package:novel_studio/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:novel_studio/ui/generation_page/widgets/generation_page_view.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_animated_presence.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_sequence.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_theme.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_editor.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_chip.dart';
import 'package:novel_studio/ui/studio_workbench/widgets/prompt_composer_panel.dart';
import 'package:novel_studio/ui/studio_workbench/widgets/workbench_asset_drawer.dart';
import 'package:novel_studio/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';

class _EnglishGenerationAssetLoader extends AssetLoader {
  const _EnglishGenerationAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    return {
      'generation_settings': 'Generation Settings',
      'generate_one_prompt': 'Generate One Prompt',
      'toggle_generation': 'Start/Stop Generation',
      'continue_from_last_time': 'Continue From Last Time',
      'continue_from_number': 'Continue From Number',
      'continue_from_number_title': 'Continue From Number',
      'continue_from_number_hint': 'Enter the generation number to resume from',
      'save_config_preview': 'Save Config Preview',
      'config_preview_saved': 'Saved {num} preview images.',
      'config_preview_no_images': 'Generate images first.',
      'image_size': 'Image Size',
      'enhance_presets': 'Redraw presets',
      'drag_and_drop_image_notice': 'Drop image here or press to upload',
      'override_random_prompts': 'Override random prompts',
      'enable_vibe_transfer': 'Enable Vibe Transfer',
      'enable_vibe_transfer_hint': 'Keeps your vibe list intact',
      'enable_precise_reference': 'Enable Precise Reference',
      'enable_precise_reference_hint': 'Only available on V4.5 models',
      'workbench_import': 'Import Workbench',
      'workbench_export': 'Export Workbench',
      'reset': 'Reset',
      'confirm': 'Confirm',
      'cancel': 'Cancel',
      'colon': ': ',
      'title': 'Title',
      'info': 'Info',
      'copy_to_clipboard': 'Copy',
      'info_export_to_clipboard': 'Copied ',
      'succeed': 'success',
    };
  }
}

class _FakeCatalogService extends StudioAssetCatalogService {
  final StudioAssetCatalogSummary summary;
  final StudioAssetCatalogSnapshot? snapshot;

  _FakeCatalogService({
    this.summary = const StudioAssetCatalogSummary(
      characterCount: 0,
      outfitCount: 0,
      artistChainCount: 0,
      recipeCount: 0,
      tagCount: 0,
      recipeCountsByBlock: {},
      tagCountsByBlock: {},
    ),
    this.snapshot,
  }) : super(workspaceService: WorkspaceService());

  @override
  Future<StudioAssetCatalogSummary> loadSummary() async {
    return summary;
  }

  @override
  Future<StudioAssetCatalogSnapshot> loadSnapshot({
    bool includeLegacyCodex = false,
    int legacyCodexLimit = 160,
    String legacyCodexQuery = '',
    String legacyCodexCategoryKey = StudioLegacyCodexCategories.allKey,
    bool persistCacheBeforeReturn = true,
  }) async {
    return snapshot ??
        StudioAssetCatalogSnapshot(
          summary: await loadSummary(),
          characters: [],
          artistChains: [],
          recipes: [],
          tags: [],
        );
  }
}

class _WorkbenchLayoutViewmodel extends GenerationPageViewmodel {
  int? lastSingleImageGenerationCount;

  _WorkbenchLayoutViewmodel({super.naiAccountUsageService});

  @override
  void startSingleImageGeneration({int count = 1}) {
    lastSingleImageGenerationCount = count;
  }
}

NaiAccountUsageService _simulatedUsageService({
  required double percent,
  bool isNegative = false,
}) {
  return NaiAccountUsageService(
    fetchData: (_) async => ApiResponse(
      status: '200',
      data: Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'subscription': {
              'tier': 3,
              'active': true,
              'usage': {
                'percent': percent,
                'isNegative': isNegative,
                'timeUntilNextPercent': 7200,
              },
              'trainingStepsLeft': {
                'fixedTrainingStepsLeft': 1000,
                'purchasedTrainingSteps': 25,
              },
            },
          }),
        ),
      ),
    ),
  );
}

const _sharedPreferencesChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

PayloadConfig _payload() {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({'number_of_requests': 0}),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

class _LocalizedGenerationApp extends StatelessWidget {
  final GenerationPageViewmodel viewmodel;

  const _LocalizedGenerationApp({required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: StudioTheme.build(),
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      home: GenerationPageView(viewmodel: viewmodel),
    );
  }
}

Future<void> _pumpGenerationPage(
  WidgetTester tester,
  GenerationPageViewmodel viewmodel,
) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/l10n',
      assetLoader: const _EnglishGenerationAssetLoader(),
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      saveLocale: false,
      child: _LocalizedGenerationApp(viewmodel: viewmodel),
    ),
  );
  await tester.pump();
  await tester.pump();
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

  setUp(() async {
    await GetIt.I.reset();
    final payload = _payload();
    GetIt.I.registerSingleton<PayloadConfig>(payload);
    GetIt.I.registerSingleton<CommandStatus>(CommandStatus());
    GetIt.I.registerSingleton<StudioAssetCatalogService>(_FakeCatalogService());
    GetIt.I.registerSingleton<StudioWorkbenchAssetService>(
      StudioWorkbenchAssetService(payloadConfig: payload),
    );
    GetIt.I.registerSingleton<WorkbenchTransferService>(
      WorkbenchTransferService(),
    );
    GetIt.I.registerFactory(
      () => WorkbenchTransferViewModel(
        payloadConfig: GetIt.I<PayloadConfig>(),
        transferService: GetIt.I<WorkbenchTransferService>(),
      ),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sharedPreferencesChannel, null);
  });

  testWidgets('generation page hosts drawer composer and single image console',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    GetIt.I<PayloadConfig>().paramConfig.model = 'nai-diffusion-4-5-full';

    await _pumpGenerationPage(tester, _WorkbenchLayoutViewmodel());

    expect(find.byType(WorkbenchAssetDrawer), findsOneWidget);
    expect(find.byType(PromptComposerPanel), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workbench-single-image-console')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-creative-inputs-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-generation-results-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-core-output-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-randomness-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-reference-input-section')),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('workbench-reference-input-section')),
        matching: find.byType(StudioMotionSequenceRegion),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-character-section')),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('workbench-character-section')),
        matching: find.byType(StudioMotionSequenceRegion),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-advanced-section')),
      findsOneWidget,
    );
    expect(
        find.byKey(const ValueKey('workbench-model-control')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('workbench-size-control')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workbench-steps-slider')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-scale-slider')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-cfg-rescale-slider')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-sampler-control')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-noise-schedule-control')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-vibe-section-toggle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-i2i-section-toggle')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('workbench-vibe-editor')), findsNothing);
    expect(find.byKey(const ValueKey('workbench-i2i-editor')), findsNothing);
    expect(
      find.byKey(const ValueKey('workbench-prompt-control-section')),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('workbench-prompt-control-section')),
        matching: find.byType(StudioMotionSequenceRegion),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('workbench-start-generation-button')),
        matching: find.byType(StudioMotionSequenceRegion),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-negative-prompt-editor')),
      findsOneWidget,
    );
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(TabBarView), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('wide workbench gives asset drawer enough category width',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await GetIt.I.unregister<StudioAssetCatalogService>();
    GetIt.I.registerSingleton<StudioAssetCatalogService>(
      _FakeCatalogService(
        summary: const StudioAssetCatalogSummary(
          characterCount: 1,
          outfitCount: 0,
          artistChainCount: 1,
          recipeCount: 0,
          tagCount: 0,
          recipeCountsByBlock: {},
          tagCountsByBlock: {},
        ),
        snapshot: const StudioAssetCatalogSnapshot(
          summary: StudioAssetCatalogSummary(
            characterCount: 1,
            outfitCount: 0,
            artistChainCount: 1,
            recipeCount: 0,
            tagCount: 0,
            recipeCountsByBlock: {},
            tagCountsByBlock: {},
          ),
          characters: [
            CharacterEntry(
              id: 'char-1',
              name: '角色',
              traits: ViewVariantTexts(frontFull: 'girl'),
            ),
          ],
          artistChains: [
            ArtistChain(id: 'artist-1', name: '画师串', prompt: 'artist'),
          ],
          recipes: [],
          tags: [],
        ),
      ),
    );

    await _pumpGenerationPage(tester, _WorkbenchLayoutViewmodel());

    final drawer = find.byType(WorkbenchAssetDrawer);
    expect(drawer, findsOneWidget);
    expect(tester.getSize(drawer).width, greaterThanOrEqualTo(320));
    expect(
      find.byKey(const ValueKey('workbench-drawer-category-artist')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('workbench vibe and i2i sections activate independently',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final payload = GetIt.I<PayloadConfig>();
    payload.paramConfig = ParamConfig(model: 'nai-diffusion-4-5-full');
    payload.generationRuntimeState.vibeEnabled = false;

    await _pumpGenerationPage(tester, _WorkbenchLayoutViewmodel());

    expect(
      find.byKey(const ValueKey('workbench-vibe-section-toggle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-i2i-section-toggle')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('workbench-vibe-editor')), findsNothing);
    expect(find.byKey(const ValueKey('workbench-i2i-editor')), findsNothing);
    expect(
      tester
          .widget<StudioAnimatedPresence>(
            find.byKey(const ValueKey('workbench-vibe-presence')),
          )
          .visible,
      isFalse,
    );
    expect(
      tester
          .widget<StudioAnimatedPresence>(
            find.byKey(const ValueKey('workbench-i2i-presence')),
          )
          .visible,
      isFalse,
    );

    await tester
        .tap(find.byKey(const ValueKey('workbench-vibe-section-toggle')));
    await tester.pump();

    expect(payload.generationRuntimeState.vibeEnabled, isTrue);
    expect(
      tester
          .widget<StudioAnimatedPresence>(
            find.byKey(const ValueKey('workbench-vibe-presence')),
          )
          .visible,
      isTrue,
    );
    expect(find.byKey(const ValueKey('workbench-vibe-editor')), findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-i2i-editor')), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('workbench-i2i-section-toggle')));
    await tester.pump();

    expect(find.byKey(const ValueKey('workbench-vibe-editor')), findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-i2i-editor')), findsOneWidget);
    expect(
      tester
          .widget<StudioAnimatedPresence>(
            find.byKey(const ValueKey('workbench-i2i-presence')),
          )
          .visible,
      isTrue,
    );
    expect(
      find.byKey(const ValueKey('workbench-i2i-config-view')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-i2i-source-image')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-i2i-strength-slider')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-i2i-noise-slider')),
      findsOneWidget,
    );
    expect(find.textContaining('Redraw presets'), findsNothing);
    expect(find.text('Enable Vibe Transfer'), findsNothing);
    expect(find.text('Enable Precise Reference'), findsNothing);

    payload.i2iConfig.setImage(base64Decode(_tinyPngBase64));
    await tester.pump();

    expect(find.text('底图 1 x 1'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('V5 explains that saved Vibes are unavailable and disables them',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final payload = GetIt.I<PayloadConfig>();
    payload.paramConfig = ParamConfig(model: 'nai-diffusion-5-full');
    payload.generationRuntimeState.vibeEnabled = true;
    payload.vibeConfigListV4.add(
      VibeConfigV4(
        fileName: 'saved-vibe.png',
        vibeB64: 'saved-encoding',
        referenceStrength: 0.6,
      ),
    );

    await _pumpGenerationPage(tester, _WorkbenchLayoutViewmodel());

    expect(
      find.byKey(const ValueKey('workbench-vibe-unsupported-hint')),
      findsOneWidget,
    );
    expect(
      find.text(
        'V5 暂不支持 Vibe；已保留 1 条配置，切回 V4 / V4.5 后可继续使用。',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<StudioChip>(
            find.byKey(const ValueKey('workbench-vibe-section-toggle')),
          )
          .onTap,
      isNull,
    );
    expect(
      tester
          .widget<StudioAnimatedPresence>(
            find.byKey(const ValueKey('workbench-vibe-presence')),
          )
          .visible,
      isFalse,
    );
    expect(find.byKey(const ValueKey('workbench-vibe-editor')), findsNothing);
    expect(payload.generationRuntimeState.vibeEnabled, isTrue);
  });

  testWidgets('workbench shows pending Vibe encoding Anlas by generate',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final payload = GetIt.I<PayloadConfig>();
    payload.paramConfig.model = 'nai-diffusion-4-5-full';
    payload.vibeConfigListV4 = [
      VibeConfigV4(
        fileName: 'editable-vibe',
        vibeB64: 'encoded',
        infoExtracted: 0.42,
        encodedInfoExtracted: 0.76,
        referenceStrength: 0.3,
        imageBytes: base64Decode(_tinyPngBase64),
      ),
    ];

    await _pumpGenerationPage(tester, _WorkbenchLayoutViewmodel());

    expect(
      find.byKey(const ValueKey('workbench-known-extra-anlas')),
      findsOneWidget,
    );
    expect(find.text('额外 2 Anlas · Vibe 编码 +2'), findsOneWidget);
  });

  testWidgets('workbench hides batch execution and resume controls',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpGenerationPage(tester, _WorkbenchLayoutViewmodel());

    expect(
      find.byKey(const ValueKey('workbench-start-generation-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-generation-count-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-import-action')),
      findsOneWidget,
    );
    expect(find.byTooltip('Generate One Prompt'), findsNothing);
    expect(find.byTooltip('Start/Stop Generation'), findsNothing);
    expect(find.byTooltip('Continue From Last Time'), findsNothing);
    expect(find.byTooltip('Continue From Number'), findsNothing);
    expect(find.text('Global'), findsNothing);
    expect(find.text('batch_resolution_enable'), findsNothing);
    expect(find.text('batch_resolution_list'), findsNothing);
    expect(find.text('NAI Token'), findsNothing);
    expect(find.text('output_folder'), findsNothing);
    expect(find.text('proxy'), findsNothing);
    expect(find.text('metadata_erase'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('workbench seed field uses animated presence when revealed',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final payload = GetIt.I<PayloadConfig>();
    payload.paramConfig = ParamConfig(randomSeed: false, seed: 12345);

    await _pumpGenerationPage(tester, _WorkbenchLayoutViewmodel());

    final seedPresence = find.byKey(const ValueKey('workbench-seed-presence'));
    expect(seedPresence, findsOneWidget);
    expect(tester.widget<StudioAnimatedPresence>(seedPresence).visible, isTrue);
    expect(
      find.descendant(
        of: seedPresence,
        matching: find.byKey(const ValueKey('workbench-seed-field')),
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('workbench generation count is passed to single image start',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewmodel = _WorkbenchLayoutViewmodel();

    await _pumpGenerationPage(tester, viewmodel);

    final countField =
        find.byKey(const ValueKey('workbench-generation-count-field'));
    await tester.ensureVisible(countField);
    await tester.enterText(countField, '4');
    await tester.pump();

    await tester
        .tap(find.byKey(const ValueKey('workbench-start-generation-button')));
    await tester.pump();

    expect(viewmodel.lastSingleImageGenerationCount, 4);

    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('prompt edits and layout changes preserve generation count',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewmodel = _WorkbenchLayoutViewmodel();
    await _pumpGenerationPage(tester, viewmodel);
    final count =
        find.byKey(const ValueKey('workbench-generation-count-field'));
    await tester.ensureVisible(count);
    await tester.enterText(count, '4');
    await tester.pump();
    GetIt.I<StudioWorkbenchAssetService>()
        .setManualPositivePrompt('local regression prompt');
    await tester.pump();
    tester.view.physicalSize = const Size(640, 850);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final generate =
        find.byKey(const ValueKey('workbench-start-generation-button'));
    expect(generate, findsOneWidget);
    await tester.tap(generate);
    await tester.pump();
    expect(viewmodel.lastSingleImageGenerationCount, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('medium workbench keeps generation and results in the viewport',
      (tester) async {
    tester.view.physicalSize = const Size(1130, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpGenerationPage(tester, _WorkbenchLayoutViewmodel());
    expect(
        find.byKey(const ValueKey('workbench-medium-layout')), findsOneWidget);
    for (final key in [
      'workbench-start-generation-button',
      'workbench-generation-results-panel'
    ]) {
      final rect = tester.getRect(find.byKey(ValueKey(key)));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(850));
    }
    await tester.tap(find.byKey(const ValueKey('workbench-open-assets')));
    await tester.pumpAndSettle();
    expect(find.byType(WorkbenchAssetDrawer), findsOneWidget);
    await tester.tap(find.byTooltip('关闭素材'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 640.0]) {
    testWidgets(
        'compact workbench at $width keeps generation available on results tab',
        (tester) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpGenerationPage(tester, _WorkbenchLayoutViewmodel());
      await tester.tap(find.widgetWithText(Tab, '生成结果'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('workbench-generation-results-panel')),
          findsOneWidget);
      final generate =
          find.byKey(const ValueKey('workbench-start-generation-button'));
      expect(tester.getRect(generate).bottom, lessThanOrEqualTo(850));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('workbench generated image preview includes synced detail panel',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tempDir = Directory.systemTemp.createTempSync(
      'workbench-generated-image-path-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final imageFile = File(
      '${tempDir.path}${Platform.pathSeparator}generated.png',
    )..writeAsBytesSync(base64Decode(_tinyPngBase64));
    final content = InfoCardContent(
      title: 'generated.png',
      info: 'soft light, blue eyes',
      additionalInfo: const {
        'input': 'soft light, blue eyes',
      },
      contentOrderText: '#1',
      imageBytes: base64Decode(_tinyPngBase64),
      imagePath: imageFile.path,
    );
    GetIt.I<CommandStatus>().commandList.add(
          Command.createAsyncNoParam<InfoCardContent>(
            () async => content,
            initialValue: content,
          ),
        );

    await _pumpGenerationPage(tester, _WorkbenchLayoutViewmodel());

    final card = find.byKey(
      const ValueKey('studio-generated-image-card-workbench-1'),
    );
    await tester.ensureVisible(card);
    final cardImage = tester.widget<Image>(
      find.byKey(const ValueKey('studio-generated-image-workbench-1')),
    );
    expect(cardImage.image, isA<ResizeImage>());
    expect((cardImage.image as ResizeImage).imageProvider, isA<FileImage>());
    await tester.tap(card);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('studio-generated-image-viewer-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-generated-image-detail-preview')),
      findsOneWidget,
    );
    expect(find.text('generated.png'), findsWidgets);
    expect(find.text('soft light'), findsWidgets);
    expect(find.text('blue eyes'), findsWidgets);

    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
      'workbench generation failure shows its reason in the result card',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const content = InfoCardContent(
      title: '生成失败',
      info: 'HTTP 401: invalid access token',
      additionalInfo: {},
    );
    GetIt.I<CommandStatus>().commandList.add(
          Command.createAsyncNoParam<InfoCardContent>(
            () async => content,
            initialValue: content,
          ),
        );

    await _pumpGenerationPage(tester, _WorkbenchLayoutViewmodel());

    expect(find.textContaining('生成失败'), findsOneWidget);
    expect(find.text('HTTP 401: invalid access token'), findsOneWidget);
    expect(find.text('暂无图片'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('workbench commits typed size before starting generation',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final payload = GetIt.I<PayloadConfig>();
    final viewmodel = _WorkbenchLayoutViewmodel();

    await _pumpGenerationPage(tester, viewmodel);

    final widthField = find.byKey(const ValueKey('workbench-width-field'));
    final heightField = find.byKey(const ValueKey('workbench-height-field'));
    await tester.ensureVisible(widthField);
    await tester.enterText(widthField, '704');
    await tester.enterText(heightField, '1472');
    await tester.pump();

    expect(
      payload.paramConfig.sizes,
      const [GenerationSize(width: 832, height: 1216)],
    );

    await tester
        .tap(find.byKey(const ValueKey('workbench-start-generation-button')));
    await tester.pump();

    expect(
      payload.paramConfig.sizes,
      const [GenerationSize(width: 704, height: 1472)],
    );
    expect(viewmodel.lastSingleImageGenerationCount, 1);

    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('workbench reset action clears current creative state',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final payload = GetIt.I<PayloadConfig>();
    final workbench = GetIt.I<StudioWorkbenchAssetService>();
    payload.settings.apiKey = 'pst-secret';
    payload.settings.outputFolderPath = r'D:\nai-output';
    payload.paramConfig = ParamConfig(
      model: 'nai-diffusion-3',
      steps: 12,
      negativePrompt: 'bad anatomy',
      randomSeed: false,
      seed: 12345,
    );
    payload.characterConfigList = [
      CharacterConfig.fromEmpty(name: 'Heroine')
        ..positivePromptConfig.strs = ['silver hair'],
    ];
    payload.useCharacterPromptWithOverride = true;
    payload.i2iConfig = I2IConfig(imageB64: _tinyPngBase64);
    payload.vibeConfigList = [
      VibeConfig(
        imageB64: _tinyPngBase64,
        fileName: 'vibe.png',
        infoExtracted: 0.6,
        referenceStrength: 0.7,
      ),
    ];
    payload.vibeConfigListV4 = [
      VibeConfigV4(
        fileName: 'style.naiv4vibe',
        vibeB64: 'v4-vibe',
        referenceStrength: 0.8,
      ),
    ];
    payload.usePreciseReference = true;
    payload.preciseReferenceList = [
      PreciseReferenceConfig(
        imageB64: _tinyPngBase64,
        fileName: 'precise.png',
        type: 'character',
        strength: 0.9,
        fidelity: 0.5,
      ),
    ];
    workbench.setManualPositivePrompt('manual base');
    workbench.appendTag(
      const TagEntry(
        id: 'tag-1',
        tag: 'cinematic lighting',
        block: 'camera',
      ),
    );

    await _pumpGenerationPage(tester, _WorkbenchLayoutViewmodel());

    final resetButton = find.byKey(const ValueKey('workbench-reset-action'));
    expect(resetButton, findsOneWidget);

    await tester.tap(resetButton);
    await tester.pumpAndSettle();

    expect(workbench.fragments, isEmpty);
    expect(workbench.manualPositivePrompt, isEmpty);
    expect(payload.overridePrompt, isEmpty);
    expect(payload.useOverridePrompt, isFalse);
    expect(payload.useCharacterPromptWithOverride, isFalse);
    expect(payload.characterConfigList, isEmpty);
    expect(payload.i2iConfig.imageB64, isNull);
    expect(payload.vibeConfigList, isEmpty);
    expect(payload.vibeConfigListV4, isEmpty);
    expect(payload.usePreciseReference, isFalse);
    expect(payload.preciseReferenceList, isEmpty);
    expect(payload.paramConfig.model, ParamConfig().model);
    expect(payload.paramConfig.steps, ParamConfig().steps);
    expect(payload.paramConfig.negativePrompt, ParamConfig().negativePrompt);
    expect(payload.paramConfig.randomSeed, isTrue);
    expect(payload.settings.apiKey, 'pst-secret');
    expect(payload.settings.outputFolderPath, r'D:\nai-output');

    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('workbench suppresses nested desktop scrollbars', (tester) async {
    final previousTargetPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      tester.view.physicalSize = const Size(1500, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpGenerationPage(tester, _WorkbenchLayoutViewmodel());

      expect(
        find.descendant(
          of: find.byType(GenerationPageView),
          matching: find.byType(Scrollbar),
        ),
        findsNothing,
      );

      await tester.pump(const Duration(milliseconds: 1));
    } finally {
      debugDefaultTargetPlatformOverride = previousTargetPlatform;
    }
  });

  testWidgets('V5 workbench shows simulated Opus allowance', (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final payload = GetIt.I<PayloadConfig>();
    payload.settings.apiKey = 'pst-simulated';
    payload.paramConfig.model = 'nai-diffusion-5-full';
    final viewmodel = _WorkbenchLayoutViewmodel(
      naiAccountUsageService: _simulatedUsageService(percent: 42.5),
    );

    await _pumpGenerationPage(tester, viewmodel);
    await tester.pumpAndSettle();

    expect(find.text('V5 Opus 剩余 42.5%'), findsOneWidget);
    expect(find.textContaining('约 735 张普通生成'), findsOneWidget);
    expect(find.text('可用点数 1025 Anlas'), findsOneWidget);
    expect(find.text('订阅点数 1000 · 已购点数 25'), findsOneWidget);
  });

  testWidgets('V4.5 workbench shows Anlas balance and free estimate',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final payload = GetIt.I<PayloadConfig>();
    payload.settings.apiKey = 'pst-simulated';
    payload.paramConfig.model = 'nai-diffusion-4-5-full';
    final viewmodel = _WorkbenchLayoutViewmodel(
      naiAccountUsageService: _simulatedUsageService(percent: 42.5),
    );

    await _pumpGenerationPage(tester, viewmodel);
    await tester.pumpAndSettle();

    expect(find.text('可用点数 1025 Anlas'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workbench-generation-cost-estimate')),
      findsOneWidget,
    );
    expect(find.text('0 Anlas · 开始生成'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workbench-v5-opus-usage-panel')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('workbench-start-generation-button')),
    );
    await tester.pumpAndSettle();

    expect(viewmodel.lastSingleImageGenerationCount, 1);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('exhausted V5 allowance requires Anlas confirmation',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final payload = GetIt.I<PayloadConfig>();
    payload.settings.apiKey = 'pst-simulated';
    payload.paramConfig.model = 'nai-diffusion-5-curated';
    final viewmodel = _WorkbenchLayoutViewmodel(
      naiAccountUsageService: _simulatedUsageService(
        percent: -0.1,
        isNegative: true,
      ),
    );

    await _pumpGenerationPage(tester, viewmodel);
    await tester.pumpAndSettle();

    final startButton =
        find.byKey(const ValueKey('workbench-start-generation-button'));
    await tester.ensureVisible(startButton);
    await tester.tap(startButton);
    await tester.pumpAndSettle();

    expect(find.text('V5 Opus 免费额度已用尽'), findsWidgets);
    expect(find.textContaining('当前可用 Anlas：1025'), findsOneWidget);
    expect(find.textContaining('点数消耗预估：约'), findsOneWidget);
    expect(viewmodel.lastSingleImageGenerationCount, isNull);

    await tester.tap(
      find.byKey(const ValueKey('workbench-confirm-v5-anlas-generation')),
    );
    await tester.pumpAndSettle();

    expect(viewmodel.lastSingleImageGenerationCount, 1);
  });

  testWidgets('V5 workbench exposes freeform character position canvas',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final payload = GetIt.I<PayloadConfig>();
    payload.paramConfig.model = 'nai-diffusion-5-full';
    payload.characterConfigList = [
      CharacterConfig.fromEmpty(name: '角色 1')
        ..freeformPosition = const Point(0.5, 0.5),
    ];

    await _pumpGenerationPage(tester, _WorkbenchLayoutViewmodel());

    expect(
      find.byKey(const ValueKey('workbench-v5-character-position-canvas')),
      findsOneWidget,
    );
    expect(find.text('V5 自由角色位置'), findsOneWidget);
    expect(find.text('AI 自选'), findsOneWidget);
    expect(find.text('自定义'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workbench-character-position-marker-0')),
      findsOneWidget,
    );
  });

  testWidgets('character prompts render as compact cards that expand on tap',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final payload = GetIt.I<PayloadConfig>();
    payload.characterConfigList = [
      CharacterConfig.fromEmpty()
        ..name = '示例角色 1'
        ..positivePromptConfig.strs = ['heroine, silver hair'],
      CharacterConfig.fromEmpty()
        ..name = '反派'
        ..positivePromptConfig.strs = ['rival, red coat', 'dynamic pose'],
      CharacterConfig.fromEmpty()
        ..name = '辅助'
        ..positivePromptConfig.strs = ['support, blue ribbon'],
      CharacterConfig.fromEmpty()
        ..name = '角色 4'
        ..positivePromptConfig.strs = ['fourth prompt'],
      CharacterConfig.fromEmpty()
        ..name = '角色 5'
        ..positivePromptConfig.strs = ['fifth prompt'],
      CharacterConfig.fromEmpty()
        ..name = '角色 6'
        ..positivePromptConfig.strs = ['sixth prompt'],
    ];

    await _pumpGenerationPage(tester, _WorkbenchLayoutViewmodel());

    expect(
      find.byKey(const ValueKey('workbench-character-card-strip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-character-card-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-character-card-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-character-card-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-character-card-5')),
      findsOneWidget,
    );
    expect(find.text('示例角色 1'), findsOneWidget);
    expect(find.text('反派'), findsOneWidget);
    expect(find.textContaining('heroine'), findsNothing);
    expect(
      find.byKey(const ValueKey('workbench-character-prompt-1')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('workbench-character-card-1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('workbench-character-expanded-card-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-character-prompt-1')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('workbench-character-prompt-1')),
        matching: find.byType(PromptTagEditor),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-character-prompt-1-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-character-prompt-block-1-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-character-prompt-block-1-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-character-prompt-drop-1-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-character-prompt-drop-1-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-character-tagified-tags-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('workbench-character-name-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-character-prompt-0')),
      findsNothing,
    );

    final tagifyToggle =
        find.byKey(const ValueKey('workbench-character-tagify-toggle-1'));
    await tester.ensureVisible(tagifyToggle);
    await tester.pump();
    await tester.tap(tagifyToggle);
    await tester.pump(const Duration(milliseconds: 250));

    expect(payload.characterConfigList[1].positivePromptConfig.strs, [
      'rival',
      'red coat',
      'dynamic pose',
    ]);
    expect(
      find.byKey(const ValueKey('workbench-character-tagified-tags-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-character-prompt-block-1-0')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('workbench-character-prompt-drop-1-0')),
      findsNothing,
    );

    await tester.ensureVisible(tagifyToggle);
    await tester.pump();
    await tester.tap(tagifyToggle);
    await tester.pump(const Duration(milliseconds: 250));

    expect(payload.characterConfigList[1].positivePromptConfig.strs, [
      'rival, red coat',
      'dynamic pose',
    ]);
    expect(
      find.byKey(const ValueKey('workbench-character-prompt-block-1-0')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 1));
  });
}
