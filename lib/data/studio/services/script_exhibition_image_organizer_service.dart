import 'dart:io';

import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/models/studio_gallery_record.dart';

typedef DefaultOutputRootResolver = Future<String> Function();

class ScriptExhibitionImageMovePlan {
  final String sourcePath;
  final String destinationPath;
  final String productionPlanId;
  final String taskId;

  const ScriptExhibitionImageMovePlan({
    required this.sourcePath,
    required this.destinationPath,
    required this.productionPlanId,
    required this.taskId,
  });
}

class ScriptExhibitionImageOrganizationPreview {
  final List<ScriptExhibitionImageMovePlan> moves;
  final List<String> orphanImagePaths;
  final List<ProductionPlan> productionPlans;
  final List<StudioGalleryRecord> galleryRecords;

  const ScriptExhibitionImageOrganizationPreview({
    required this.moves,
    required this.orphanImagePaths,
    required this.productionPlans,
    required this.galleryRecords,
  });
}

class ScriptExhibitionImageOrganizationResult {
  // Kept for existing callers; organization now creates copies and retains
  // every source file rather than moving or deleting user images.
  final List<String> movedImagePaths;
  final List<String> deletedOrphanImagePaths;
  final List<String> failedImagePaths;
  final List<ProductionPlan> updatedProductionPlans;
  final List<StudioGalleryRecord> updatedGalleryRecords;

  const ScriptExhibitionImageOrganizationResult({
    required this.movedImagePaths,
    required this.deletedOrphanImagePaths,
    required this.failedImagePaths,
    required this.updatedProductionPlans,
    required this.updatedGalleryRecords,
  });

  List<String> get organizedImagePaths => movedImagePaths;
}

class ScriptExhibitionImageOrganizerService {
  final DefaultOutputRootResolver defaultOutputRoot;

  const ScriptExhibitionImageOrganizerService({
    required this.defaultOutputRoot,
  });

  Future<ScriptExhibitionImageOrganizationPreview> preview({
    required Map<String, String> targetScriptTitlesById,
    required List<ProductionPlan> productionPlans,
    required List<StudioGalleryRecord> galleryRecords,
    required List<String> generatedRoots,
    Set<String> originalSourcePaths = const {},
  }) async {
    final root = await defaultOutputRoot();
    final targetTitlesById = {
      for (final entry in targetScriptTitlesById.entries)
        if (entry.key.trim().isNotEmpty) entry.key.trim(): entry.value.trim(),
    };
    final originalSourceKeys = {
      for (final path in originalSourcePaths)
        ScriptExhibitionImagePathPolicy.normalizedPathKey(path),
    };
    final existingDestinations = <String>{};
    final plannedSourceKeys = <String>{};
    final moves = <ScriptExhibitionImageMovePlan>[];

    for (final plan in productionPlans) {
      for (final task in plan.tasks) {
        final outputImagePath = task.outputImagePath?.trim();
        if (task.taskType != ProductionTaskType.scriptRecastFrame ||
            task.status != ProductionTaskStatus.completed ||
            !_targetsScript(task, targetTitlesById) ||
            outputImagePath == null ||
            outputImagePath.isEmpty) {
          continue;
        }
        final source = File(outputImagePath).absolute.path;
        final sourceKey =
            ScriptExhibitionImagePathPolicy.normalizedPathKey(source);
        if (originalSourceKeys.contains(sourceKey) ||
            !await File(source).exists()) {
          continue;
        }
        if (plannedSourceKeys.contains(sourceKey)) {
          continue;
        }
        final outputRoot =
            plan.executionSettings?.outputDirectory.trim().isNotEmpty == true
                ? plan.executionSettings!.outputDirectory
                : root;
        final destinationTask = _taskWithFallbackScriptTitle(
          task,
          targetTitlesById[task.source.scriptId?.trim()],
        );
        if (_isAlreadyOrganizedForTask(
          source: source,
          outputRoot: outputRoot,
          planName: plan.name,
          task: destinationTask,
        )) {
          existingDestinations.add(sourceKey);
          continue;
        }
        final destination = ScriptExhibitionImagePathPolicy.destinationForTask(
          outputRoot: outputRoot,
          planName: plan.name,
          task: destinationTask,
          existingDestinationKeys: existingDestinations,
          ignoredExistingPathKeys: {sourceKey},
        );
        final destinationKey =
            ScriptExhibitionImagePathPolicy.normalizedPathKey(destination);
        existingDestinations.add(destinationKey);
        if (sourceKey == destinationKey) {
          continue;
        }
        plannedSourceKeys.add(sourceKey);
        moves.add(ScriptExhibitionImageMovePlan(
          sourcePath: source,
          destinationPath: destination,
          productionPlanId: plan.id,
          taskId: task.id,
        ));
      }
    }

    // Missing references are not evidence that a file is disposable. In
    // particular, exhibition records are only a view of a shared image root.
    // Do not scan generatedRoots or turn unknown images into deletion targets.
    return ScriptExhibitionImageOrganizationPreview(
      moves: List.unmodifiable(moves),
      orphanImagePaths: const [],
      productionPlans: List.unmodifiable(productionPlans),
      galleryRecords: List.unmodifiable(galleryRecords),
    );
  }

  Future<ScriptExhibitionImageOrganizationResult> apply(
    ScriptExhibitionImageOrganizationPreview preview,
  ) async {
    final pathUpdates = <String, String>{};
    final moved = <String>[];
    final failed = <String>[];

    for (final move in preview.moves) {
      final source = File(move.sourcePath);
      final destination = File(move.destinationPath);
      try {
        if (!await source.exists()) {
          failed.add(source.absolute.path);
          continue;
        }
        final sourceKey = ScriptExhibitionImagePathPolicy.normalizedPathKey(
          source.absolute.path,
        );
        final destinationKey =
            ScriptExhibitionImagePathPolicy.normalizedPathKey(
          destination.absolute.path,
        );
        if (sourceKey == destinationKey) {
          continue;
        }
        if (await FileSystemEntity.type(destination.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          failed.add(source.absolute.path);
          continue;
        }
        await destination.parent.create(recursive: true);
        // Reserve the name atomically, including when two organization runs
        // share the same preview. An existing image must never be overwritten.
        await destination.create(exclusive: true);
        final movedFile = await source.copy(destination.path);
        if (await movedFile.length() != await source.length()) {
          throw FileSystemException(
              'Image copy is incomplete', destination.path);
        }
        final destinationPath = movedFile.absolute.path;
        pathUpdates[ScriptExhibitionImagePathPolicy.normalizedPathKey(
          move.sourcePath,
        )] = destinationPath;
        moved.add(destinationPath);
      } on FileSystemException {
        failed.add(source.absolute.path);
      }
    }

    final updatedPlans = _updateProductionPlanPaths(
      preview.productionPlans,
      pathUpdates,
    );
    final updatedRecords = _updateGalleryRecordPaths(
      preview.galleryRecords,
      pathUpdates,
    );

    return ScriptExhibitionImageOrganizationResult(
      movedImagePaths: List.unmodifiable(moved),
      deletedOrphanImagePaths: const [],
      failedImagePaths: List.unmodifiable(failed),
      updatedProductionPlans: updatedPlans,
      updatedGalleryRecords: updatedRecords,
    );
  }
}

bool _isAlreadyOrganizedForTask({
  required String source,
  required String outputRoot,
  required String planName,
  required ProductionTask task,
}) {
  final root = Directory(outputRoot.trim()).absolute.path;
  final script = ScriptExhibitionImagePathPolicy.safePathSegment(
    task.source.scriptName?.trim().isNotEmpty == true
        ? task.source.scriptName!
        : task.source.scriptId ?? 'script',
  );
  final version = ScriptExhibitionImagePathPolicy.safePathSegment(
    planName.trim().isEmpty ? task.planId : planName,
  );
  final expectedParentKey = ScriptExhibitionImagePathPolicy.normalizedPathKey(
    [root, script, version].join(Platform.pathSeparator),
  );
  final sourceFile = File(source).absolute;
  final sourceParentKey = ScriptExhibitionImagePathPolicy.normalizedPathKey(
    sourceFile.parent.path,
  );
  if (sourceParentKey != expectedParentKey) {
    return false;
  }

  final fileName = sourceFile.path.replaceAll('\\', '/').split('/').last;
  final frameStem = ScriptExhibitionImagePathPolicy.frameStemForTask(task);
  if (fileName == '$frameStem.png') {
    return true;
  }
  final match = RegExp(
    '^${RegExp.escape(frameStem)}-([0-9]+)\\.png\$',
  ).firstMatch(fileName);
  if (match == null) {
    return false;
  }
  final suffix = int.tryParse(match.group(1)!);
  return suffix != null && suffix >= 2;
}

bool _targetsScript(
  ProductionTask task,
  Map<String, String> targetScriptTitlesById,
) {
  final scriptId = task.source.scriptId?.trim();
  return scriptId != null &&
      scriptId.isNotEmpty &&
      targetScriptTitlesById.containsKey(scriptId);
}

class ScriptExhibitionImagePathPolicy {
  static String destinationForTask({
    required String outputRoot,
    required String planName,
    required ProductionTask task,
    required Set<String> existingDestinationKeys,
    Set<String> ignoredExistingPathKeys = const {},
  }) {
    final root = Directory(outputRoot.trim()).absolute.path;
    final script = safePathSegment(
      task.source.scriptName?.trim().isNotEmpty == true
          ? task.source.scriptName!
          : task.source.scriptId ?? 'script',
    );
    final version = safePathSegment(
      planName.trim().isEmpty ? task.planId : planName,
    );
    final frameStem = frameStemForTask(task);
    var suffix = 1;
    while (true) {
      final fileName =
          suffix == 1 ? '$frameStem.png' : '$frameStem-$suffix.png';
      final path =
          [root, script, version, fileName].join(Platform.pathSeparator);
      final pathKey = normalizedPathKey(path);
      final existsOnDisk =
          File(path).existsSync() && !ignoredExistingPathKeys.contains(pathKey);
      if (!existingDestinationKeys.contains(pathKey) && !existsOnDisk) {
        return path;
      }
      suffix += 1;
    }
  }

  static String frameStemForTask(ProductionTask task) {
    final index = task.source.frameIndex;
    if (index != null) {
      return index.toString().padLeft(3, '0');
    }
    final sourceFileName = task.source.sourceFileName?.trim();
    if (sourceFileName != null && sourceFileName.isNotEmpty) {
      final normalized = sourceFileName.replaceAll('\\', '/').split('/').last;
      final dot = normalized.lastIndexOf('.');
      return safePathSegment(
          dot <= 0 ? normalized : normalized.substring(0, dot));
    }
    return safePathSegment(task.id);
  }

  static String safePathSegment(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]+'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[ .-]+|[ .-]+$'), '');
    return sanitized.isEmpty ? 'untitled' : sanitized;
  }

  static String normalizedPathKey(String path) {
    final normalized = File(path)
        .absolute
        .path
        .trim()
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'/+$'), '');
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}

ProductionTask _taskWithFallbackScriptTitle(
  ProductionTask task,
  String? targetScriptTitle,
) {
  final fallbackTitle = targetScriptTitle?.trim();
  if (task.source.scriptName?.trim().isNotEmpty == true ||
      fallbackTitle == null ||
      fallbackTitle.isEmpty) {
    return task;
  }
  return task.copyWith(
    source: ProductionTaskSource(
      scriptId: task.source.scriptId,
      scriptName: fallbackTitle,
      scriptPath: task.source.scriptPath,
      recastRunId: task.source.recastRunId,
      mappingConfigFingerprint: task.source.mappingConfigFingerprint,
      frameIndex: task.source.frameIndex,
      sourceFileName: task.source.sourceFileName,
    ),
  );
}

List<ProductionPlan> _updateProductionPlanPaths(
  List<ProductionPlan> productionPlans,
  Map<String, String> pathUpdates,
) {
  if (pathUpdates.isEmpty) {
    return List.unmodifiable(productionPlans);
  }
  return List.unmodifiable([
    for (final plan in productionPlans)
      plan.copyWith(
        tasks: [
          for (final task in plan.tasks)
            if (_updatedPath(task.outputImagePath, pathUpdates)
                case final updated?)
              task.copyWith(outputImagePath: updated)
            else
              task,
        ],
        planFingerprint: plan.planFingerprint,
      ),
  ]);
}

List<StudioGalleryRecord> _updateGalleryRecordPaths(
  List<StudioGalleryRecord> galleryRecords,
  Map<String, String> pathUpdates,
) {
  if (pathUpdates.isEmpty) {
    return List.unmodifiable(galleryRecords);
  }
  return List.unmodifiable([
    for (final record in galleryRecords)
      _updatedGalleryRecord(record, pathUpdates),
  ]);
}

StudioGalleryRecord _updatedGalleryRecord(
  StudioGalleryRecord record,
  Map<String, String> pathUpdates,
) {
  final updatedImagePath = _updatedPath(record.imagePath, pathUpdates);
  final provenance = record.provenance;
  final updatedProvenancePath = _updatedPath(
    provenance?.outputImagePath,
    pathUpdates,
  );
  final updatedProvenance = provenance == null || updatedProvenancePath == null
      ? provenance
      : StudioRecastProvenance(
          scriptId: provenance.scriptId,
          scriptName: provenance.scriptName,
          scriptPath: provenance.scriptPath,
          recastRunId: provenance.recastRunId,
          productionPlanId: provenance.productionPlanId,
          productionPlanFingerprint: provenance.productionPlanFingerprint,
          taskId: provenance.taskId,
          frameIndex: provenance.frameIndex,
          sourceFileName: provenance.sourceFileName,
          payloadFingerprint: provenance.payloadFingerprint,
          mappingConfigFingerprint: provenance.mappingConfigFingerprint,
          outputImagePath: updatedProvenancePath,
        );
  if (updatedImagePath == null && updatedProvenance == provenance) {
    return record;
  }
  final additionalInfo = Map<String, dynamic>.from(record.additionalInfo);
  if (updatedProvenance != null) {
    additionalInfo['provenance'] = updatedProvenance.toJson();
  }
  return StudioGalleryRecord(
    id: record.id,
    createdAt: record.createdAt,
    title: record.title,
    imagePath: updatedImagePath ?? record.imagePath,
    info: record.info,
    additionalInfo: Map.unmodifiable(additionalInfo),
    provenance: updatedProvenance,
    lineage: record.lineage,
    document: record.document,
  );
}

String? _updatedPath(String? path, Map<String, String> pathUpdates) {
  final trimmed = path?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return pathUpdates[ScriptExhibitionImagePathPolicy.normalizedPathKey(
    trimmed,
  )];
}
