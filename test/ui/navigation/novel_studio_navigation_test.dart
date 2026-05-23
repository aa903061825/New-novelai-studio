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
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/data/studio/models/studio_gallery_record.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/studio/services/studio_gallery_service.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/data/studio/services/workbench_transfer_service.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:nai_casrand/ui/navigation/view_models/navigation_view_model.dart';
import 'package:nai_casrand/ui/navigation/widgets/navigation_view.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _sharedPreferencesChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

class _NavigationAssetLoader extends AssetLoader {
  const _NavigationAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    return {
      'generation_settings': 'Generation settings',
      'generate_one_prompt': 'Generate one prompt',
      'save_config_preview': 'Save preview',
      'toggle_generation': 'Toggle generation',
      'workbench_import': 'Import workbench',
      'workbench_export': 'Export workbench',
      'press_again_to_exit': 'Press again to exit',
      'welcome_message_title': 'Welcome',
      'welcome_message_markdown': 'Welcome',
      'dont_show_again': 'Do not show again',
      'confirm': 'Confirm',
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

class _FakeGalleryService extends StudioGalleryService {
  _FakeGalleryService() : super(workspaceService: WorkspaceService());

  @override
  Future<List<StudioGalleryRecord>> loadRecords() async {
    return const [];
  }
}

PayloadConfig _payload() {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({'welcome_message_version': '1.0.0'}),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sharedPreferencesChannel, (call) async {
      if (call.method == 'getAll') return <String, Object>{};
      return true;
    });
    await EasyLocalization.ensureInitialized();
  });

  setUp(() async {
    await GetIt.I.reset();
    final configService = ConfigService();
    configService.packageInfo = PackageInfo(
      appName: 'Novel Studio',
      packageName: 'novel.studio',
      version: '1.0.0',
      buildNumber: '1',
    );
    final payload = _payload();
    GetIt.I.registerSingleton<ConfigService>(configService);
    GetIt.I.registerSingleton<PayloadConfig>(payload);
    GetIt.I.registerSingleton<CommandStatus>(CommandStatus());
    GetIt.I.registerSingleton<StudioAssetCatalogService>(_FakeCatalogService());
    GetIt.I.registerSingleton<StudioWorkbenchAssetService>(
      StudioWorkbenchAssetService(payloadConfig: payload),
    );
    GetIt.I.registerSingleton<StudioGalleryService>(_FakeGalleryService());
    GetIt.I.registerSingleton<WorkbenchTransferService>(
      WorkbenchTransferService(),
    );
    GetIt.I.registerFactory(
      () => WorkbenchTransferViewModel(
        payloadConfig: payload,
        transferService: GetIt.I<WorkbenchTransferService>(),
      ),
    );
    GetIt.I.registerSingleton<GenerationPageViewmodel>(
      GenerationPageViewmodel(),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sharedPreferencesChannel, null);
  });

  testWidgets('navigation exposes only the studio product areas',
      (tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/l10n',
        assetLoader: const _NavigationAssetLoader(),
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        saveLocale: false,
        child: Builder(
          builder: (context) => MaterialApp(
            theme: StudioTheme.build(),
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: NavigationView(viewModel: NavigationViewModel()),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('主页'), findsWidgets);
    expect(find.text('素材库'), findsWidgets);
    expect(find.text('工作台'), findsWidgets);
    expect(find.text('批量产线'), findsWidgets);
    expect(find.text('画廊'), findsWidgets);
    expect(find.text('设置'), findsWidgets);
    expect(find.text('素材工具'), findsNothing);
  });
}
