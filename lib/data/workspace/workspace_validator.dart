import 'dart:convert';
import 'dart:io';

import 'package:novel_studio/data/workspace/models/workspace_manifest.dart';
import 'package:novel_studio/data/workspace/models/workspace_validation.dart';
import 'package:novel_studio/data/workspace/workspace_paths.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

class WorkspaceValidator {
  final WorkspaceService service;

  WorkspaceValidator(this.service);

  Future<WorkspaceValidationReport> validate() async {
    final issues = <WorkspaceValidationIssue>[];
    final root = service.root;
    final manifest = service.currentManifest;

    if (root == null || manifest == null) {
      issues.add(
        const WorkspaceValidationIssue(
          severity: WorkspaceValidationSeverity.error,
          code: 'missing_manifest',
          path: WorkspacePaths.manifest,
          message: 'Workspace manifest is not loaded.',
        ),
      );
      return WorkspaceValidationReport(issues);
    }

    if (manifest.schemaVersion > WorkspaceManifest.currentSchemaVersion) {
      issues.add(
        WorkspaceValidationIssue(
          severity: WorkspaceValidationSeverity.error,
          code: 'unsupported_schema_version',
          path: WorkspacePaths.manifest,
          message: 'Unsupported schema version ${manifest.schemaVersion}.',
        ),
      );
    }

    await _validateRecipes(issues, root);
    await _validateCharacters(issues, root);
    await _validateGenerationProfiles(issues, root);

    return WorkspaceValidationReport(issues);
  }

  Future<void> _validateRecipes(
    List<WorkspaceValidationIssue> issues,
    Directory root,
  ) async {
    final seenRecipeIds = <String, String>{};
    for (final block in WorkspacePaths.blocks) {
      final path = WorkspacePaths.recipeFile(block);
      final recipes = await _loadWorkspaceFile(
        issues: issues,
        path: path,
        load: () => service.loadRecipes(block),
      );
      if (recipes == null) continue;
      for (final recipe in recipes) {
        final issuePath = '$path#${recipe.id}';
        _addDuplicateIdIssue(
          issues: issues,
          seenIds: seenRecipeIds,
          id: recipe.id,
          path: issuePath,
          entityType: 'recipe',
        );
        if (!WorkspacePaths.blocks.contains(recipe.block)) {
          issues.add(
            WorkspaceValidationIssue(
              severity: WorkspaceValidationSeverity.error,
              code: 'invalid_block',
              path: issuePath,
              message:
                  'Recipe ${recipe.id} uses unknown block ${recipe.block}.',
            ),
          );
        }
        _validateImageRefs(
          issues: issues,
          root: root,
          refs: recipe.imageRefs,
          path: issuePath,
        );
      }
    }
  }

  Future<void> _validateCharacters(
    List<WorkspaceValidationIssue> issues,
    Directory root,
  ) async {
    final seenCharacterIds = <String, String>{};
    final characters = await _loadWorkspaceFile(
      issues: issues,
      path: WorkspacePaths.characters,
      load: service.loadCharacters,
    );
    if (characters == null) return;
    for (final character in characters) {
      final issuePath = '${WorkspacePaths.characters}#${character.id}';
      _addDuplicateIdIssue(
        issues: issues,
        seenIds: seenCharacterIds,
        id: character.id,
        path: issuePath,
        entityType: 'character',
      );
      if (character.traits.frontFull.trim().isEmpty) {
        issues.add(
          WorkspaceValidationIssue(
            severity: WorkspaceValidationSeverity.error,
            code: 'missing_front_full',
            path: '$issuePath.traits.front_full',
            message: 'Character ${character.id} is missing front_full traits.',
          ),
        );
      }
      _validateImageRefs(
        issues: issues,
        root: root,
        refs: character.imageRefs,
        path: issuePath,
      );

      for (final outfit in character.outfits) {
        final outfitPath = '$issuePath.outfits#${outfit.id}';
        if (outfit.tags.frontFull.trim().isEmpty) {
          issues.add(
            WorkspaceValidationIssue(
              severity: WorkspaceValidationSeverity.error,
              code: 'missing_front_full',
              path: '$outfitPath.tags.front_full',
              message: 'Outfit ${outfit.id} is missing front_full tags.',
            ),
          );
        }
        _validateImageRefs(
          issues: issues,
          root: root,
          refs: outfit.imageRefs,
          path: outfitPath,
        );
      }
    }
  }

  Future<void> _validateGenerationProfiles(
    List<WorkspaceValidationIssue> issues,
    Directory root,
  ) async {
    final directory = Directory(
      _resolve(root, 'configs/generation_profiles'),
    );
    if (!await directory.exists()) return;

    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final relativePath = _relativePath(root, entity);
      final rawContent = await entity.readAsString();
      try {
        final json = jsonDecode(rawContent);
        if (_containsSecretLikeValue(json)) {
          _addSecretIssue(issues, relativePath);
        }
      } on FormatException catch (error) {
        _addInvalidWorkspaceFileIssue(issues, relativePath, error);
        if (_containsSecretLikeText(rawContent)) {
          _addSecretIssue(issues, relativePath);
        }
      }
    }
  }

  void _addDuplicateIdIssue({
    required List<WorkspaceValidationIssue> issues,
    required Map<String, String> seenIds,
    required String id,
    required String path,
    required String entityType,
  }) {
    final firstPath = seenIds[id];
    if (firstPath != null) {
      issues.add(
        WorkspaceValidationIssue(
          severity: WorkspaceValidationSeverity.error,
          code: 'duplicate_id',
          path: path,
          message: 'Duplicate $entityType id $id also appears at $firstPath.',
        ),
      );
      return;
    }
    seenIds[id] = path;
  }

  Future<T?> _loadWorkspaceFile<T>({
    required List<WorkspaceValidationIssue> issues,
    required String path,
    required Future<T> Function() load,
  }) async {
    try {
      return await load();
    } catch (error) {
      _addInvalidWorkspaceFileIssue(issues, path, error);
      return null;
    }
  }

  void _addInvalidWorkspaceFileIssue(
    List<WorkspaceValidationIssue> issues,
    String path,
    Object error,
  ) {
    issues.add(
      WorkspaceValidationIssue(
        severity: WorkspaceValidationSeverity.error,
        code: 'invalid_workspace_file',
        path: path,
        message: 'Workspace file could not be read: $error',
      ),
    );
  }

  void _validateImageRefs({
    required List<WorkspaceValidationIssue> issues,
    required Directory root,
    required List<String> refs,
    required String path,
  }) {
    for (final ref in refs) {
      if (!File(_resolve(root, ref)).existsSync()) {
        issues.add(
          WorkspaceValidationIssue(
            severity: WorkspaceValidationSeverity.warning,
            code: 'missing_image_ref',
            path: path,
            message: 'Image reference $ref does not exist.',
          ),
        );
      }
    }
  }

  void _addSecretIssue(
    List<WorkspaceValidationIssue> issues,
    String path,
  ) {
    issues.add(
      WorkspaceValidationIssue(
        severity: WorkspaceValidationSeverity.error,
        code: 'secret_in_workspace',
        path: path,
        message: 'Generation profile contains token-like workspace data.',
      ),
    );
  }

  bool _containsSecretLikeValue(dynamic value, {String? key}) {
    if (key == 'secretRef') return false;
    if (key != null && _containsSecretLikeText(key)) return true;
    if (value is String) return _containsSecretLikeText(value);
    if (value is Map) {
      return value.entries.any(
        (entry) => _containsSecretLikeValue(entry.value, key: '${entry.key}'),
      );
    }
    if (value is List) {
      return value.any(_containsSecretLikeValue);
    }
    return false;
  }

  bool _containsSecretLikeText(String value) {
    final normalized = value.toLowerCase();
    return normalized.contains('api_key') ||
        normalized.contains('pst-') ||
        normalized.contains('bearer') ||
        normalized.contains('token') ||
        normalized.contains('password') ||
        normalized.contains('secret') ||
        normalized.contains('proxy');
  }

  String _resolve(Directory root, String relativePath) {
    return [
      root.path,
      ...relativePath.split('/'),
    ].join(Platform.pathSeparator);
  }

  String _relativePath(Directory root, File file) {
    final prefix = '${root.path}${Platform.pathSeparator}';
    if (!file.path.startsWith(prefix)) return file.path;
    return file.path
        .substring(prefix.length)
        .replaceAll(Platform.pathSeparator, '/');
  }
}
