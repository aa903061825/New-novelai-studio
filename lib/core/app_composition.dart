import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/services/config_service.dart';
import 'package:novel_studio/data/studio/studio_data_service.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

class AppCompositionServices {
  final ConfigService configService;
  final WorkspaceService workspaceService;
  final StudioDataService studioDataService;

  const AppCompositionServices({
    required this.configService,
    required this.workspaceService,
    required this.studioDataService,
  });
}

class AppComposition {
  const AppComposition._();

  static Future<AppCompositionServices> registerCoreServices({
    required GetIt getIt,
    bool initializeStudioData = true,
  }) async {
    if (!getIt.isRegistered<ConfigService>()) {
      getIt.registerLazySingleton<ConfigService>(() => ConfigService());
    }
    final configService = getIt<ConfigService>();

    final workspaceService = getIt.isRegistered<WorkspaceService>()
        ? getIt<WorkspaceService>()
        : WorkspaceService();
    if (!getIt.isRegistered<WorkspaceService>()) {
      getIt.registerSingleton<WorkspaceService>(workspaceService);
    }

    final studioDataService = getIt.isRegistered<StudioDataService>()
        ? getIt<StudioDataService>()
        : StudioDataService(workspaceService: workspaceService);
    if (!getIt.isRegistered<StudioDataService>()) {
      getIt.registerSingleton<StudioDataService>(studioDataService);
    }

    if (initializeStudioData) {
      await studioDataService.initializeForApp();
    }

    return AppCompositionServices(
      configService: configService,
      workspaceService: workspaceService,
      studioDataService: studioDataService,
    );
  }
}
