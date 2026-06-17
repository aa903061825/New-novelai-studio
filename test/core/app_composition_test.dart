import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/core/app_composition.dart';
import 'package:novel_studio/data/services/config_service.dart';
import 'package:novel_studio/data/studio/studio_data_service.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

void main() {
  tearDown(() async {
    await GetIt.I.reset();
  });

  test('registerCoreServices provides stable service handles', () async {
    final services = await AppComposition.registerCoreServices(
      getIt: GetIt.I,
      initializeStudioData: false,
    );

    expect(services.configService, isA<ConfigService>());
    expect(services.workspaceService, isA<WorkspaceService>());
    expect(services.studioDataService, isA<StudioDataService>());
    expect(GetIt.I<ConfigService>(), same(services.configService));
    expect(GetIt.I<WorkspaceService>(), same(services.workspaceService));
    expect(GetIt.I<StudioDataService>(), same(services.studioDataService));
  });
}
