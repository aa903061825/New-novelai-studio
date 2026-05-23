import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/studio_data_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_paths.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('studio-data-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('initializeAt creates the internal studio manifest', () async {
    final service = StudioDataService(workspaceService: WorkspaceService());

    await service.initializeAt(tempDir);

    final manifest = File(
      '${tempDir.path}${Platform.pathSeparator}${WorkspacePaths.manifest}',
    );
    expect(await manifest.exists(), isTrue);
  });

  test('initializeAt opens existing studio data without clearing characters',
      () async {
    final workspaceService = WorkspaceService();
    final service = StudioDataService(workspaceService: workspaceService);
    await service.initializeAt(tempDir);
    await workspaceService.saveCharacters([
      const CharacterEntry(
        id: 'char-1',
        name: 'Heroine',
        traits: ViewVariantTexts(frontFull: 'blue eyes'),
      ),
    ]);

    final reopenedWorkspaceService = WorkspaceService();
    final reopenedService = StudioDataService(
      workspaceService: reopenedWorkspaceService,
    );
    await reopenedService.initializeAt(tempDir);
    final characters = await reopenedWorkspaceService.loadCharacters();

    expect(characters.single.id, 'char-1');
    expect(characters.single.traits.frontFull, 'blue eyes');
  });
}
