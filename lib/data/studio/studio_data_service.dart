import 'dart:io';

import 'package:nai_casrand/data/workspace/workspace_paths.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:path_provider/path_provider.dart';

class StudioDataService {
  final WorkspaceService workspaceService;

  StudioDataService({required this.workspaceService});

  Future<void> initializeForApp() async {
    final supportDir = await getApplicationSupportDirectory();
    final studioDir = Directory(
      '${supportDir.path}${Platform.pathSeparator}novel_studio',
    );
    await initializeAt(studioDir);
  }

  Future<void> initializeAt(Directory root) async {
    final manifest = File(
      '${root.path}${Platform.pathSeparator}${WorkspacePaths.manifest}',
    );
    if (await manifest.exists()) {
      await workspaceService.openWorkspace(root.path);
      return;
    }
    await workspaceService.createWorkspace(root.path);
  }
}
