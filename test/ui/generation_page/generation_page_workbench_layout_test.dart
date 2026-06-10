import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/character_config.dart';
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/models/i2i_config.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/precise_reference_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/models/vibe_config.dart';
import 'package:nai_casrand/data/models/vibe_config_v4.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/data/studio/services/workbench_transfer_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:nai_casrand/ui/generation_page/widgets/generation_page_view.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_core/widgets/prompt_tag_editor.dart';
import 'package:nai_casrand/ui/studio_workbench/widgets/prompt_composer_panel.dart';
import 'package:nai_casrand/ui/studio_workbench/widgets/workbench_asset_drawer.dart';
import 'package:nai_casrand/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';

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
      'enhance_presets': 'Enhance parameter presets',
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
    };
  }
}

class _FakeCatalogService extends StudioAssetCatalogService {
  _FakeCatalogService() : super(workspaceService: WorkspaceService());

  @override
  Future<StudioAssetCatalogSummary> loadSummary() async {
    return const StudioAssetCatalogSummary(
      characterCount: 0,
      outfitCount: 0,
      artistChainCount: 0,
      recipeCount: 0,
      tagCount: 0,
      recipeCountsByBlock: {},
      tagCountsByBlock: {},
    );
  }

  @override
  Future<StudioAssetCatalogSnapshot> loadSnapshot({
    bool includeLegacyCodex = false,
    int legacyCodexLimit = 160,
    String legacyCodexQuery = '',
    String legacyCodexCategoryKey = StudioLegacyCodexCategories.allKey,
  }) async {
    return StudioAssetCatalogSnapshot(
      summary: await loadSummary(),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [],
    );
  }
}

class _WorkbenchLayoutViewmodel extends GenerationPageViewmodel {}

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
      find.byKey(const ValueKey('workbench-character-section')),
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
      find.byKey(const ValueKey('workbench-reference-editor')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-prompt-control-section')),
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

  testWidgets('workbench reference editor exposes i2i and reference controls',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final payload = GetIt.I<PayloadConfig>();
    payload.paramConfig = ParamConfig(model: 'nai-diffusion-4-5-full');

    await _pumpGenerationPage(tester, _WorkbenchLayoutViewmodel());

    expect(
      find.byKey(const ValueKey('workbench-reference-editor')),
      findsOneWidget,
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
    expect(find.text('Enable Vibe Transfer'), findsOneWidget);
    expect(find.text('Enable Precise Reference'), findsOneWidget);
    expect(find.text('I2I 0'), findsOneWidget);

    payload.i2iConfig.setImage(base64Decode(_tinyPngBase64));
    await tester.pump();

    expect(find.text('I2I 1'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));
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
