import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/data/studio/services/workbench_transfer_service.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:nai_casrand/ui/generation_page/widgets/generation_page_view.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
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
      'workbench_import': 'Import Workbench',
      'workbench_export': 'Export Workbench',
      'confirm': 'Confirm',
      'cancel': 'Cancel',
    };
  }
}

class _FakeCatalogService extends StudioAssetCatalogService {
  _FakeCatalogService() : super(workspaceService: WorkspaceService());

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

class _WorkbenchLayoutViewmodel extends GenerationPageViewmodel {}

const _sharedPreferencesChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

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
        .setMockMethodCallHandler(_sharedPreferencesChannel, (methodCall) async {
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

  testWidgets('generation page hosts drawer composer and generation tabs',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpGenerationPage(tester, _WorkbenchLayoutViewmodel());

    expect(find.text('素材抽屉'), findsOneWidget);
    expect(find.text('Prompt 编排'), findsOneWidget);
    expect(find.text('结果'), findsOneWidget);
    expect(find.text('参数'), findsOneWidget);
    expect(find.text('参考'), findsOneWidget);
  });
}
