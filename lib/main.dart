import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/models/generation_runtime_state.dart';
import 'package:nai_casrand/data/models/global_generation_params.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/data/studio/studio_data_service.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/studio/services/studio_batch_plan_service.dart';
import 'package:nai_casrand/data/studio/services/studio_gallery_service.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/data/studio/services/workbench_transfer_service.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:nai_casrand/ui/navigation/widgets/navigation_view.dart';
import 'package:nai_casrand/ui/navigation/view_models/navigation_view_model.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:get_it/get_it.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  GetIt.instance.registerLazySingleton<ConfigService>(() => ConfigService());
  final workspaceService = WorkspaceService();
  final studioDataService = StudioDataService(
    workspaceService: workspaceService,
  );
  await studioDataService.initializeForApp();
  GetIt.instance.registerSingleton<WorkspaceService>(workspaceService);
  GetIt.instance.registerSingleton<StudioDataService>(studioDataService);
  GetIt.instance.registerLazySingleton(
    () => StudioAssetCatalogService(workspaceService: workspaceService),
  );
  GetIt.instance.registerLazySingleton(
    () => StudioBatchPlanService(workspaceService: workspaceService),
  );
  GetIt.instance.registerLazySingleton(
    () => StudioGalleryService(workspaceService: workspaceService),
  );
  final configService = GetIt.instance<ConfigService>();
  configService.packageInfo = await PackageInfo.fromPlatform();
  final savedConfig = await configService.loadSavedConfig();
  final payloadConfig = PayloadConfig.fromJson(savedConfig);
  payloadConfig.globalGenerationParams =
      configService.loadGlobalGenerationParams() ??
          GlobalGenerationParams.fromParamConfig(payloadConfig.paramConfig);
  payloadConfig.generationRuntimeState =
      configService.loadGenerationRuntimeState() ?? GenerationRuntimeState();

  GetIt.instance.registerLazySingleton(() => payloadConfig);
  GetIt.instance.registerLazySingleton(() => CommandStatus());
  GetIt.instance.registerLazySingleton(
    () => StudioWorkbenchAssetService(
      payloadConfig: payloadConfig,
      workspaceService: workspaceService,
    ),
  );
  GetIt.instance.registerLazySingleton(() => WorkbenchTransferService());
  GetIt.instance.registerFactory(
    () => WorkbenchTransferViewModel(
      payloadConfig: GetIt.I<PayloadConfig>(),
      transferService: GetIt.I<WorkbenchTransferService>(),
    ),
  );

  GetIt.instance.registerLazySingleton(() => GenerationPageViewmodel());

  final appWithLocales = EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
    path: 'assets/l10n',
    child: const MyApp(),
  );

  runApp(appWithLocales);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final config = GetIt.I<PayloadConfig>();
    final studioTheme = StudioTheme.build();
    return AdaptiveTheme(
      light: studioTheme,
      dark: studioTheme,
      initial: config.settings.theme,
      builder: (theme, darkTheme) => MaterialApp(
        theme: theme,
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        home: NavigationView(viewModel: NavigationViewModel()),
      ),
    );
  }
}
