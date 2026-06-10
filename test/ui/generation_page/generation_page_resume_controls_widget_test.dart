import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/models/generation_runtime_state.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:nai_casrand/ui/generation_page/widgets/generation_page_view.dart';

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
      'confirm': 'Confirm',
      'cancel': 'Cancel',
    };
  }
}

PayloadConfig _buildPayloadConfig({
  int numberOfRequests = 3,
  bool hasPendingBatchResume = false,
}) {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({
      'number_of_requests': numberOfRequests,
    }),
    generationRuntimeState: GenerationRuntimeState(
      hasPendingBatchResume: hasPendingBatchResume,
      resumeTargetTotalCount: hasPendingBatchResume ? numberOfRequests : 0,
      resumeCompletedCount: hasPendingBatchResume ? 1 : 0,
      resumeStartedAt:
          hasPendingBatchResume ? DateTime.parse('2026-05-17T08:00:00Z') : null,
    ),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

class _TestGenerationPageViewmodel extends GenerationPageViewmodel {
  bool resumeFromLastCalled = false;
  int? resumeFromNumberValue;

  @override
  String encodePreviewThumbnail(Uint8List imageBytes) {
    return 'thumb-widget';
  }

  @override
  void resumeBatchFromLast() {
    resumeFromLastCalled = true;
  }

  @override
  void resumeBatchFromNumber(int startNumber) {
    resumeFromNumberValue = startNumber;
  }
}

class _EmptyCatalogService extends StudioAssetCatalogService {
  _EmptyCatalogService() : super(workspaceService: WorkspaceService());

  @override
  Future<StudioAssetCatalogSnapshot> loadSnapshot({
    bool includeLegacyCodex = false,
    int legacyCodexLimit = 160,
    String legacyCodexQuery = '',
    String legacyCodexCategoryKey = StudioLegacyCodexCategories.allKey,
  }) async {
    return const StudioAssetCatalogSnapshot(
      summary: StudioAssetCatalogSummary(
        characterCount: 0,
        outfitCount: 0,
        artistChainCount: 0,
        recipeCount: 0,
        tagCount: 0,
        recipeCountsByBlock: {},
        tagCountsByBlock: {},
      ),
      characters: [],
      artistChains: [],
      recipes: [],
      tags: [],
    );
  }
}

class _LocalizedGenerationApp extends StatelessWidget {
  const _LocalizedGenerationApp({required this.viewmodel});

  final GenerationPageViewmodel viewmodel;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      home: GenerationPageView(viewmodel: viewmodel),
    );
  }
}

const _sharedPreferencesChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

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
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
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
    final payload = _buildPayloadConfig();
    GetIt.I.registerSingleton<PayloadConfig>(payload);
    GetIt.I.registerSingleton<CommandStatus>(CommandStatus());
    GetIt.I.registerSingleton<StudioAssetCatalogService>(
      _EmptyCatalogService(),
    );
    GetIt.I.registerSingleton<StudioWorkbenchAssetService>(
      StudioWorkbenchAssetService(payloadConfig: payload),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sharedPreferencesChannel, null);
  });

  testWidgets('workbench hides batch controls even when resume is available',
      (tester) async {
    await GetIt.I.unregister<PayloadConfig>();
    GetIt.I.registerSingleton<PayloadConfig>(
      _buildPayloadConfig(
        numberOfRequests: 3,
        hasPendingBatchResume: true,
      ),
    );
    final viewmodel = _TestGenerationPageViewmodel();

    await _pumpGenerationPage(tester, viewmodel);

    expect(find.byTooltip('Continue From Last Time'), findsNothing);
    expect(find.byTooltip('Continue From Number'), findsNothing);
    expect(find.byTooltip('Start/Stop Generation'), findsNothing);
  });

  testWidgets('workbench does not keep preview actions as floating buttons',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewmodel = _TestGenerationPageViewmodel();

    await _pumpGenerationPage(tester, viewmodel);

    expect(find.byTooltip('Save Config Preview'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
