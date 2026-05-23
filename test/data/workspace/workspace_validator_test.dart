import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/models/workspace_validation.dart';
import 'package:nai_casrand/data/workspace/workspace_paths.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/data/workspace/workspace_validator.dart';

void main() {
  late Directory tempDir;
  late WorkspaceService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('novel-validator-test-');
    service = WorkspaceService();
    await service.createWorkspace(tempDir.path, name: 'Validator Studio');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('reports invalid blocks and duplicate IDs', () async {
    await service.saveRecipes('style', [
      const Recipe(id: 'r1', name: 'Good', block: 'style'),
      const Recipe(id: 'r1', name: 'Duplicate', block: 'bad_block'),
    ]);

    final report = await WorkspaceValidator(service).validate();

    expect(report.hasErrors, isTrue);
    expect(report.issues.any((issue) => issue.code == 'duplicate_id'), isTrue);
    expect(report.issues.any((issue) => issue.code == 'invalid_block'), isTrue);
  });

  test('blocks token-like values in generation profiles', () async {
    final file = _workspaceFile(
      tempDir,
      WorkspacePaths.generationProfileFile('profile-1'),
    );
    await file.writeAsString(
      jsonEncode({
        'id': 'profile-1',
        'name': 'Unsafe',
        'params': {'api_key': 'pst-secret-token'},
      }),
    );

    final report = await WorkspaceValidator(service).validate();

    expect(report.issues.any((issue) {
      return issue.severity == WorkspaceValidationSeverity.error &&
          issue.code == 'secret_in_workspace';
    }), isTrue);
  });

  test('allows generation profiles with only a secret reference', () async {
    await service.saveGenerationProfile(
      const GenerationProfile(
        id: 'profile-1',
        name: 'Safe',
        secretRef: 'default_nai_token',
      ),
    );

    final report = await WorkspaceValidator(service).validate();

    expect(
      report.issues.any((issue) => issue.code == 'secret_in_workspace'),
      isFalse,
    );
  });

  test('reports malformed generation profile JSON', () async {
    final file = _workspaceFile(
      tempDir,
      WorkspacePaths.generationProfileFile('profile-1'),
    );
    await file.writeAsString('{"id": "profile-1",');

    final report = await WorkspaceValidator(service).validate();

    expect(
      report.issues.any((issue) {
        return issue.severity == WorkspaceValidationSeverity.error &&
            issue.code == 'invalid_workspace_file' &&
            issue.path == WorkspacePaths.generationProfileFile('profile-1');
      }),
      isTrue,
    );
  });

  test('reports malformed recipe JSON without throwing', () async {
    final file = _workspaceFile(tempDir, WorkspacePaths.recipeFile('style'));
    await file.writeAsString('{"not": "a list"}');

    final report = await WorkspaceValidator(service).validate();

    expect(
      report.issues.any((issue) {
        return issue.severity == WorkspaceValidationSeverity.error &&
            issue.code == 'invalid_workspace_file' &&
            issue.path == WorkspacePaths.recipeFile('style');
      }),
      isTrue,
    );
  });

  test('reports malformed character JSON without throwing', () async {
    final file = _workspaceFile(tempDir, WorkspacePaths.characters);
    await file.writeAsString('{"not": "a list"}');

    final report = await WorkspaceValidator(service).validate();

    expect(
      report.issues.any((issue) {
        return issue.severity == WorkspaceValidationSeverity.error &&
            issue.code == 'invalid_workspace_file' &&
            issue.path == WorkspacePaths.characters;
      }),
      isTrue,
    );
  });
}

File _workspaceFile(Directory root, String relativePath) {
  return File(
    [
      root.path,
      ...relativePath.split('/'),
    ].join(Platform.pathSeparator),
  );
}
