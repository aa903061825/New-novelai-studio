import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/studio/services/studio_asset_capture_service.dart';
import 'package:novel_studio/data/studio/services/studio_asset_catalog_service.dart';
import 'package:novel_studio/data/studio/services/studio_asset_preview_generation_service.dart';
import 'package:novel_studio/data/studio/services/studio_gallery_service.dart';
import 'package:novel_studio/data/studio/services/studio_workbench_asset_service.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';
import 'package:novel_studio/ui/generation_page/view_models/generation_page_viewmodel.dart';

class StudioShellDependencies {
  final GetIt getIt;

  const StudioShellDependencies({required this.getIt});

  PayloadConfig get payloadConfig => getIt<PayloadConfig>();
  WorkspaceService get workspaceService => getIt<WorkspaceService>();
  StudioAssetCatalogService get catalogService =>
      getIt<StudioAssetCatalogService>();
  StudioWorkbenchAssetService get workbenchAssetService =>
      getIt<StudioWorkbenchAssetService>();
  StudioGalleryService get galleryService => getIt<StudioGalleryService>();
  StudioAssetPreviewGenerationService get previewGenerationService =>
      getIt<StudioAssetPreviewGenerationService>();
  StudioAssetCaptureService get assetCaptureService =>
      getIt<StudioAssetCaptureService>();
  GenerationPageViewmodel get generationPageViewModel =>
      getIt<GenerationPageViewmodel>();
}
