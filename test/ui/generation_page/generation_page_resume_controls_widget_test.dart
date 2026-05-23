import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_command/flutter_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/models/generation_runtime_state.dart';
import 'package:nai_casrand/data/models/info_card_content.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/services/config_service.dart';
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

class _PreviewConfigService extends ConfigService {
  int saveConfigIndexCallCount = 0;

  @override
  void saveConfigIndex() {
    saveConfigIndexCallCount++;
  }
}

class _EmptyCatalogService extends StudioAssetCatalogService {
  _EmptyCatalogService() : super(workspaceService: WorkspaceService());

  @override
  Future<StudioAssetCatalogSnapshot> loadSnapshot() async {
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

Command<void, InfoCardContent> _cardCommand(Uint8List imageBytes) {
  final content = InfoCardContent(
    title: 'generated.png',
    info: '',
    additionalInfo: const {},
    imageBytes: imageBytes,
  );
  return Command.createAsyncNoParam(
    () async => content,
    initialValue: content,
  );
}

Uint8List _onePixelPngBytes() {
  return base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
  );
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

  testWidgets(
      'shows continue buttons when resume is available and total is finite',
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

    expect(find.byTooltip('Continue From Last Time'), findsOneWidget);
    expect(find.byTooltip('Continue From Number'), findsOneWidget);
  });

  testWidgets(
      'hides continue buttons when no resume exists and total is unlimited',
      (tester) async {
    await GetIt.I.unregister<PayloadConfig>();
    GetIt.I.registerSingleton<PayloadConfig>(
      _buildPayloadConfig(
        numberOfRequests: 0,
        hasPendingBatchResume: false,
      ),
    );
    final viewmodel = _TestGenerationPageViewmodel();

    await _pumpGenerationPage(tester, viewmodel);

    expect(find.byTooltip('Continue From Last Time'), findsNothing);
    expect(find.byTooltip('Continue From Number'), findsNothing);
  });

  testWidgets('continue from number dialog forwards the entered value',
      (tester) async {
    await GetIt.I.unregister<PayloadConfig>();
    GetIt.I.registerSingleton<PayloadConfig>(
      _buildPayloadConfig(
        numberOfRequests: 8,
        hasPendingBatchResume: true,
      ),
    );
    final viewmodel = _TestGenerationPageViewmodel();

    await _pumpGenerationPage(tester, viewmodel);

    await tester.tap(find.byTooltip('Continue From Number'));
    await tester.pumpAndSettle();

    expect(find.text('Continue From Number'), findsWidgets);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '5',
    );
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(viewmodel.resumeFromNumberValue, 5);
  });

  testWidgets('save config preview button stores the current generated image',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final configService = _PreviewConfigService()
      ..currentUuid = 'active'
      ..configIndex = {
        'active': SavedConfigInfo(
          title: 'Active',
          lastModified: DateTime.parse('2026-05-19T09:00:00Z'),
        ),
      };
    GetIt.I.registerSingleton<ConfigService>(configService);
    final viewmodel = _TestGenerationPageViewmodel();
    viewmodel.commandList.add(_cardCommand(_onePixelPngBytes()));

    await _pumpGenerationPage(tester, viewmodel);

    await tester.tap(find.byTooltip('Save Config Preview'));

    expect(
        configService.configIndex['active']!.previewImages, ['thumb-widget']);
    expect(configService.saveConfigIndexCallCount, 1);
  });
}
