# Script Exhibition Image Organization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace unsafe per-source-folder cleanup with deterministic Script Exhibition image organization and make future script-recast generation use the same script/version/frame folder layout.

**Architecture:** Add a focused organizer/path service under `lib/data/studio/services/` and keep Script Exhibition viewmodel/UI as orchestration layers. Future generation should use the same path policy from the production save path, so old-image organization and new-image output do not diverge.

**Tech Stack:** Dart/Flutter, existing `ProductionPlan`/`ProductionTask`, `StudioGalleryRecord`, `ScriptExhibitionRoomViewModel`, `WorkspaceService`, `ProductionNaiAdapterService`, Flutter widget tests.

**Repo Rule:** Beads says this project is in stealth/no-git-ops mode. Do not add commit steps; update Beads status instead.

---

## File Structure

- Create `lib/data/studio/services/script_exhibition_image_organizer_service.dart`
  - Owns safe path segment generation, script/version/frame naming, dry-run preview, file move plan, orphan detection, and apply result models.
  - Contains no UI code.
- Create `test/data/studio/services/script_exhibition_image_organizer_service_test.dart`
  - Covers naming, moving, reference updates, same-frame suffixes, original-source skip behavior, and orphan cleanup.
- Modify `lib/data/studio/services/production_nai_adapter_service.dart`
  - Use the shared path policy for script-recast output paths.
  - Keep manual generation behavior unchanged.
- Modify `lib/data/studio/services/production_executor_service.dart`
  - Pass the full `ProductionPlan` and `ProductionTask` to scoped save logic.
- Modify production tests:
  - `test/data/studio/services/production_nai_adapter_service_test.dart`
  - `test/data/studio/services/production_executor_service_test.dart`
- Modify `lib/ui/studio_shell/view_models/script_exhibition_room_viewmodel.dart`
  - Add organizer dependencies/callbacks.
  - Replace source-folder cleanup methods with script-image organization methods.
- Modify `lib/ui/studio_shell/widgets/script_exhibition_room_page.dart`
  - Replace the old "clean source folder" UI action with organize-script-images preview/apply flow.
- Modify tests:
  - `test/ui/studio_shell/script_exhibition_room_viewmodel_test.dart`
  - `test/ui/studio_shell/script_exhibition_room_page_test.dart`
- Modify `lib/ui/studio_shell/widgets/studio_shell_view.dart`
  - Wire `WorkspaceService`, `ProductionQueueService`, and `StudioGalleryService.saveRecords`/loaders into the viewmodel organizer callbacks.

---

### Task 1: Shared Organizer Path Policy

**Files:**
- Create: `lib/data/studio/services/script_exhibition_image_organizer_service.dart`
- Create: `test/data/studio/services/script_exhibition_image_organizer_service_test.dart`

- [ ] **Step 1: Write failing path-policy tests**

Add this test scaffold:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/services/script_exhibition_image_organizer_service.dart';

void main() {
  group('ScriptExhibitionImagePathPolicy', () {
    test('builds script version frame paths under selected root', () {
      final root = Directory.systemTemp.createTempSync('organizer-path-root-');
      addTearDown(() => root.deleteSync(recursive: true));
      final path = ScriptExhibitionImagePathPolicy.destinationForTask(
        outputRoot: root.path,
        planName: 'Hero Version A',
        task: ProductionTask.scriptRecastFrame(
          id: 'task-1',
          planId: 'plan-1',
          title: 'Frame One',
          scriptId: 'script-1',
          scriptName: 'Rain Archive',
          scriptPath: r'C:\stories\rain',
          recastRunId: 'run-1',
          frameIndex: 1,
          sourceFileName: '001.json',
          payload: const {'input': 'frame'},
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
        existingDestinationKeys: const {},
      );

      expect(path, endsWith('Rain Archive${Platform.pathSeparator}Hero Version A${Platform.pathSeparator}001.png'));
    });

    test('adds same-frame suffixes without overwriting existing destinations', () {
      final root = Directory.systemTemp.createTempSync('organizer-collision-root-');
      addTearDown(() => root.deleteSync(recursive: true));
      final task = ProductionTask.scriptRecastFrame(
        id: 'task-2',
        planId: 'plan-1',
        title: 'Frame One Rerun',
        scriptId: 'script-1',
        scriptName: 'Rain: Archive',
        scriptPath: r'C:\stories\rain',
        recastRunId: 'run-1',
        frameIndex: 1,
        sourceFileName: '001.json',
        payload: const {'input': 'frame'},
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final first = ScriptExhibitionImagePathPolicy.destinationForTask(
        outputRoot: root.path,
        planName: 'Plan/Version',
        task: task,
        existingDestinationKeys: const {},
      );
      final second = ScriptExhibitionImagePathPolicy.destinationForTask(
        outputRoot: root.path,
        planName: 'Plan/Version',
        task: task,
        existingDestinationKeys: {
          ScriptExhibitionImagePathPolicy.normalizedPathKey(first),
        },
      );

      expect(first, endsWith('${Platform.pathSeparator}Rain- Archive${Platform.pathSeparator}Plan-Version${Platform.pathSeparator}001.png'));
      expect(second, endsWith('${Platform.pathSeparator}Rain- Archive${Platform.pathSeparator}Plan-Version${Platform.pathSeparator}001-2.png'));
    });
  });
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```powershell
flutter test test\data\studio\services\script_exhibition_image_organizer_service_test.dart
```

Expected: fails because `script_exhibition_image_organizer_service.dart` and `ScriptExhibitionImagePathPolicy` do not exist.

- [ ] **Step 3: Implement path policy**

Create `lib/data/studio/services/script_exhibition_image_organizer_service.dart` with:

```dart
import 'dart:io';

import 'package:novel_studio/data/studio/models/production_task.dart';

class ScriptExhibitionImagePathPolicy {
  static String destinationForTask({
    required String outputRoot,
    required String planName,
    required ProductionTask task,
    required Set<String> existingDestinationKeys,
  }) {
    final root = Directory(outputRoot.trim()).absolute.path;
    final script = safePathSegment(
      task.source.scriptName?.trim().isNotEmpty == true
          ? task.source.scriptName!
          : task.source.scriptId ?? 'script',
    );
    final version = safePathSegment(planName.trim().isEmpty ? task.planId : planName);
    final frameStem = frameStemForTask(task);
    var suffix = 1;
    while (true) {
      final fileName = suffix == 1 ? '$frameStem.png' : '$frameStem-$suffix.png';
      final path = [root, script, version, fileName].join(Platform.pathSeparator);
      if (!existingDestinationKeys.contains(normalizedPathKey(path)) &&
          !File(path).existsSync()) {
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
      return safePathSegment(dot <= 0 ? normalized : normalized.substring(0, dot));
    }
    return safePathSegment(task.id);
  }

  static String safePathSegment(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]+'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^[ .-]+|[ .-]+$'), '');
    return sanitized.isEmpty ? 'untitled' : sanitized;
  }

  static String normalizedPathKey(String path) {
    final normalized = File(path).absolute.path
        .trim()
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'/+$'), '');
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}
```

- [ ] **Step 4: Run path tests**

Run:

```powershell
flutter test test\data\studio\services\script_exhibition_image_organizer_service_test.dart
```

Expected: path-policy tests pass.

---

### Task 2: Future Script-Recast Output Layout

**Files:**
- Modify: `lib/data/studio/services/production_executor_service.dart`
- Modify: `lib/data/studio/services/production_nai_adapter_service.dart`
- Modify: `test/data/studio/services/production_executor_service_test.dart`
- Modify: `test/data/studio/services/production_nai_adapter_service_test.dart`

- [ ] **Step 1: Write failing adapter test for script layout**

In `test/data/studio/services/production_nai_adapter_service_test.dart`, replace the old default plan-id layout expectation with a script layout test:

```dart
test('saveScriptRecastImage writes under script and version folders', () async {
  final saves = <String>[];
  final adapter = ProductionNaiAdapterService(
    endpoint: '',
    proxy: '',
    headers: const {},
    outputDirectory: r'C:\Users\tester\Documents\nai-generated',
    fetchData: (_) async => throw UnimplementedError(),
    processResponse: (bytes) => bytes,
    savePictureToFile: (bytes, fileName, saveDir) async {
      saves.add('$saveDir|$fileName|${bytes.length}');
    },
    resolvePictureSavePath: (fileName, saveDir) async =>
        '$saveDir\\$fileName',
  );
  final now = DateTime.utc(2026);
  final task = ProductionTask.scriptRecastFrame(
    id: 'task-1',
    planId: 'plan-1',
    title: 'Frame One',
    scriptId: 'script-1',
    scriptName: 'Rain Archive',
    recastRunId: 'run-1',
    frameIndex: 1,
    sourceFileName: '001.json',
    payload: const {'input': 'frame one'},
    createdAt: now,
    updatedAt: now,
  );
  final plan = ProductionPlan(
    id: 'plan-1',
    name: 'Hero Version A',
    tasks: [task],
    createdAt: now,
    updatedAt: now,
  );

  final path = await adapter.saveScriptRecastImage(
    Uint8List.fromList([1, 2, 3]),
    plan,
    task,
  );

  expect(saves.single, r'C:\Users\tester\Documents\nai-generated|Rain Archive\Hero Version A\001.png|3');
  expect(path, r'C:\Users\tester\Documents\nai-generated\Rain Archive\Hero Version A\001.png');
});
```

Add `dart:typed_data` import if missing.

- [ ] **Step 2: Update executor test expectation**

In `test/data/studio/services/production_executor_service_test.dart`, update save callback signatures from:

```dart
savePlanImage: (bytes, fileName, planId, outputDirectory) async {
```

to:

```dart
savePlanImage: (bytes, fileName, plan, task) async {
```

For the specific test that checks scoped saving, assert that `plan.name`, `task.source.scriptName`, and `task.source.frameIndex` are available in the callback.

- [ ] **Step 3: Run production tests and verify failure**

Run:

```powershell
flutter test test\data\studio\services\production_nai_adapter_service_test.dart test\data\studio\services\production_executor_service_test.dart
```

Expected: fails due missing `saveScriptRecastImage` and old scoped callback signature.

- [ ] **Step 4: Change executor scoped save signature**

In `production_executor_service.dart`, change typedef:

```dart
typedef ProductionScopedImageSave = Future<String> Function(
  Uint8List bytes,
  String fileName,
  ProductionPlan plan,
  ProductionTask task,
);
```

Change `_executeTask` save call:

```dart
final outputPath = savePlanImage == null
    ? await saveImage(bytes, fileName)
    : await savePlanImage!(bytes, fileName, plan, runningTask);
```

- [ ] **Step 5: Add adapter script-recast save method**

In `production_nai_adapter_service.dart`, import:

```dart
import 'package:novel_studio/data/studio/services/script_exhibition_image_organizer_service.dart';
```

Add:

```dart
Future<String> saveScriptRecastImage(
  Uint8List bytes,
  ProductionPlan plan,
  ProductionTask task,
) async {
  final effectiveOutputDirectory =
      plan.executionSettings?.outputDirectory.trim().isNotEmpty == true
          ? plan.executionSettings!.outputDirectory
          : outputDirectory;
  final destination = ScriptExhibitionImagePathPolicy.destinationForTask(
    outputRoot: effectiveOutputDirectory,
    planName: plan.name,
    task: task,
    existingDestinationKeys: const {},
  );
  final root = Directory(effectiveOutputDirectory).absolute.path;
  final relativePath = _relativePathUnderRoot(destination, root);
  await savePictureToFile(bytes, relativePath, effectiveOutputDirectory);
  return resolvePictureSavePath(relativePath, effectiveOutputDirectory);
}

Future<String> savePlanImage(
  Uint8List bytes,
  String fileName,
  ProductionPlan plan,
  ProductionTask task,
) {
  if (task.taskType == ProductionTaskType.scriptRecastFrame) {
    return saveScriptRecastImage(bytes, plan, task);
  }
  return saveImage(bytes, fileName);
}
```

Add helper:

```dart
String _relativePathUnderRoot(String path, String root) {
  final pathKey = File(path).absolute.path.replaceAll('\\', '/');
  final rootKey = Directory(root).absolute.path.replaceAll('\\', '/');
  if (pathKey == rootKey || !pathKey.startsWith('$rootKey/')) {
    return path.split(RegExp(r'[\\/]')).last;
  }
  return pathKey.substring(rootKey.length + 1).replaceAll('/', Platform.pathSeparator);
}
```

- [ ] **Step 6: Update `main.dart` wiring if needed**

If the tear-off `adapter.savePlanImage` type now mismatches, update the call site in `lib/main.dart` to still pass `savePlanImage: adapter.savePlanImage`.

- [ ] **Step 7: Run production tests**

Run:

```powershell
flutter test test\data\studio\services\production_nai_adapter_service_test.dart test\data\studio\services\production_executor_service_test.dart
```

Expected: all pass after updating old test expectations.

---

### Task 3: Organizer Preview and Apply for Production/Gallery References

**Files:**
- Modify: `lib/data/studio/services/script_exhibition_image_organizer_service.dart`
- Modify: `test/data/studio/services/script_exhibition_image_organizer_service_test.dart`

- [ ] **Step 1: Write failing organizer apply test**

Add a test that creates temp files:

```dart
test('organizes current script production images and updates gallery provenance', () async {
  final root = Directory.systemTemp.createTempSync('script-organizer-root-');
  addTearDown(() => root.deleteSync(recursive: true));
  final mixed = Directory('${root.path}${Platform.pathSeparator}mixed')..createSync();
  final generated = File('${mixed.path}${Platform.pathSeparator}random.png')
    ..writeAsBytesSync([1, 2, 3]);
  final original = File('${mixed.path}${Platform.pathSeparator}001-source.png')
    ..writeAsBytesSync([9, 9, 9]);
  final orphan = File('${root.path}${Platform.pathSeparator}orphan.png')
    ..writeAsBytesSync([4, 5, 6]);
  final now = DateTime.utc(2026);
  final task = ProductionTask.scriptRecastFrame(
    id: 'task-1',
    planId: 'plan-1',
    title: 'Frame One',
    scriptId: 'script-1',
    scriptName: 'Rain Archive',
    recastRunId: 'run-1',
    frameIndex: 1,
    sourceFileName: '001.json',
    payload: const {'input': 'frame'},
    outputImagePath: generated.path,
    status: ProductionTaskStatus.completed,
    createdAt: now,
    updatedAt: now,
  );
  final plan = ProductionPlan(
    id: 'plan-1',
    name: 'Hero Version A',
    tasks: [task],
    createdAt: now,
    updatedAt: now,
  );
  final record = StudioGalleryRecord.fromRecastPayload(
    payload: const {'input': 'frame'},
    id: 'gallery-1',
    createdAt: now,
    title: 'Frame One',
    imagePath: generated.path,
    info: 'frame',
    provenance: StudioRecastProvenance(
      scriptId: 'script-1',
      scriptName: 'Rain Archive',
      productionPlanId: 'plan-1',
      productionPlanFingerprint: 'fp',
      taskId: 'task-1',
      frameIndex: 1,
      sourceFileName: '001.json',
      payloadFingerprint: 'payload',
      mappingConfigFingerprint: 'mapping',
      outputImagePath: generated.path,
    ),
  );
  final service = ScriptExhibitionImageOrganizerService(
    defaultOutputRoot: () async => root.path,
  );

  final preview = await service.preview(
    targetScriptId: 'script-1',
    targetScriptTitle: 'Rain Archive',
    productionPlans: [plan],
    galleryRecords: [record],
    generatedRoots: [root.path],
    originalSourcePaths: {original.path},
  );

  expect(preview.moves, hasLength(1));
  expect(preview.orphanImagePaths, [orphan.absolute.path]);

  final result = await service.apply(preview);

  final movedPath = result.updatedProductionPlans.single.tasks.single.outputImagePath!;
  expect(movedPath, endsWith('Rain Archive${Platform.pathSeparator}Hero Version A${Platform.pathSeparator}001.png'));
  expect(File(movedPath).existsSync(), isTrue);
  expect(generated.existsSync(), isFalse);
  expect(original.existsSync(), isTrue);
  expect(orphan.existsSync(), isFalse);
  expect(result.updatedGalleryRecords.single.imagePath, movedPath);
  expect(result.updatedGalleryRecords.single.provenance!.outputImagePath, movedPath);
});
```

Add imports for `StudioGalleryRecord`.

- [ ] **Step 2: Run organizer test and verify failure**

Run:

```powershell
flutter test test\data\studio\services\script_exhibition_image_organizer_service_test.dart
```

Expected: fails because preview/apply models do not exist.

- [ ] **Step 3: Implement preview/result models**

Add:

```dart
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
}
```

- [ ] **Step 4: Implement service preview**

Add `ScriptExhibitionImageOrganizerService` with:

```dart
class ScriptExhibitionImageOrganizerService {
  final DefaultOutputRootResolver defaultOutputRoot;

  const ScriptExhibitionImageOrganizerService({
    required this.defaultOutputRoot,
  });

  Future<ScriptExhibitionImageOrganizationPreview> preview({
    required String targetScriptId,
    required String targetScriptTitle,
    required List<ProductionPlan> productionPlans,
    required List<StudioGalleryRecord> galleryRecords,
    required List<String> generatedRoots,
    Set<String> originalSourcePaths = const {},
  }) async {
    final root = await defaultOutputRoot();
    final existingDestinations = <String>{};
    final moves = <ScriptExhibitionImageMovePlan>[];
    for (final plan in productionPlans) {
      for (final task in plan.tasks) {
        if (task.taskType != ProductionTaskType.scriptRecastFrame ||
            task.source.scriptId != targetScriptId ||
            task.outputImagePath?.trim().isNotEmpty != true) {
          continue;
        }
        final source = File(task.outputImagePath!.trim()).absolute.path;
        if (originalSourcePaths.contains(source) || !await File(source).exists()) {
          continue;
        }
        final destination = ScriptExhibitionImagePathPolicy.destinationForTask(
          outputRoot: plan.executionSettings?.outputDirectory.trim().isNotEmpty == true
              ? plan.executionSettings!.outputDirectory
              : root,
          planName: plan.name,
          task: task,
          existingDestinationKeys: existingDestinations,
        );
        existingDestinations.add(ScriptExhibitionImagePathPolicy.normalizedPathKey(destination));
        if (ScriptExhibitionImagePathPolicy.normalizedPathKey(source) ==
            ScriptExhibitionImagePathPolicy.normalizedPathKey(destination)) {
          continue;
        }
        moves.add(ScriptExhibitionImageMovePlan(
          sourcePath: source,
          destinationPath: destination,
          productionPlanId: plan.id,
          taskId: task.id,
        ));
      }
    }
    final referenced = _referencedImageKeys(productionPlans, galleryRecords);
    final orphans = await _findOrphans(generatedRoots, referenced, {
      for (final move in moves) ScriptExhibitionImagePathPolicy.normalizedPathKey(move.sourcePath),
    });
    return ScriptExhibitionImageOrganizationPreview(
      moves: List.unmodifiable(moves),
      orphanImagePaths: List.unmodifiable(orphans),
      productionPlans: productionPlans,
      galleryRecords: galleryRecords,
    );
  }
}
```

- [ ] **Step 5: Implement apply**

Add:

```dart
Future<ScriptExhibitionImageOrganizationResult> apply(
  ScriptExhibitionImageOrganizationPreview preview,
) async {
  final pathUpdates = <String, String>{};
  final moved = <String>[];
  final failed = <String>[];
  for (final move in preview.moves) {
    try {
      final source = File(move.sourcePath);
      final destination = File(move.destinationPath);
      await destination.parent.create(recursive: true);
      if (await source.exists()) {
        await source.rename(destination.path);
      }
      pathUpdates[ScriptExhibitionImagePathPolicy.normalizedPathKey(move.sourcePath)] =
          destination.absolute.path;
      moved.add(destination.absolute.path);
    } on FileSystemException {
      failed.add(move.sourcePath);
    }
  }

  final updatedPlans = _updateProductionPlanPaths(preview.productionPlans, pathUpdates);
  final updatedRecords = _updateGalleryRecordPaths(preview.galleryRecords, pathUpdates);

  final deleted = <String>[];
  if (failed.isEmpty) {
    for (final orphan in preview.orphanImagePaths) {
      try {
        final file = File(orphan);
        if (await file.exists()) {
          await file.delete();
          deleted.add(file.absolute.path);
        }
      } on FileSystemException {
        failed.add(orphan);
      }
    }
  }
  return ScriptExhibitionImageOrganizationResult(
    movedImagePaths: List.unmodifiable(moved),
    deletedOrphanImagePaths: List.unmodifiable(deleted),
    failedImagePaths: List.unmodifiable(failed),
    updatedProductionPlans: updatedPlans,
    updatedGalleryRecords: updatedRecords,
  );
}
```

Implement private helpers `_referencedImageKeys`, `_findOrphans`, `_updateProductionPlanPaths`, and `_updateGalleryRecordPaths`. For gallery records, rebuild `StudioGalleryRecord` and `StudioRecastProvenance` with updated `imagePath`/`outputImagePath`.

- [ ] **Step 6: Run organizer tests**

Run:

```powershell
flutter test test\data\studio\services\script_exhibition_image_organizer_service_test.dart
```

Expected: all organizer tests pass.

---

### Task 4: ViewModel Integration and Persistence Callbacks

**Files:**
- Modify: `lib/ui/studio_shell/view_models/script_exhibition_room_viewmodel.dart`
- Modify: `test/ui/studio_shell/script_exhibition_room_viewmodel_test.dart`

- [ ] **Step 1: Add viewmodel test for organization**

Add a test that injects:

```dart
final savedPlans = <List<ProductionPlan>>[];
final savedGalleryRecords = <List<StudioGalleryRecord>>[];
final viewModel = ScriptExhibitionRoomViewModel(
  loadScripts: () async => [_script()],
  loadProductionPlans: () async => [plan],
  loadGalleryRecords: () async => [record],
  saveProductionPlans: (plans) async => savedPlans.add(plans),
  saveGalleryRecords: (records) async => savedGalleryRecords.add(records),
  defaultGeneratedImageRoot: () async => root.path,
);
```

Then call:

```dart
await viewModel.load();
final preview = await viewModel.previewScriptImageOrganization(viewModel.snapshot.scripts.single);
expect(preview.moves, hasLength(1));
final result = await viewModel.organizeScriptImages(viewModel.snapshot.scripts.single, preview: preview);
expect(result.movedImagePaths, hasLength(1));
expect(savedPlans.single.single.tasks.single.outputImagePath, result.movedImagePaths.single);
expect(savedGalleryRecords.single.single.imagePath, result.movedImagePaths.single);
```

- [ ] **Step 2: Run viewmodel test and verify failure**

Run:

```powershell
flutter test test\ui\studio_shell\script_exhibition_room_viewmodel_test.dart --plain-name "organizes script images"
```

Expected: fails due missing callbacks/methods.

- [ ] **Step 3: Add typedefs and constructor parameters**

In viewmodel file add:

```dart
typedef ScriptExhibitionProductionPlansSaver = Future<void> Function(List<ProductionPlan> plans);
typedef ScriptExhibitionGalleryRecordsSaver = Future<void> Function(List<StudioGalleryRecord> records);
typedef ScriptExhibitionDefaultGeneratedImageRoot = Future<String> Function();
```

Add fields:

```dart
final ScriptExhibitionProductionPlansSaver? saveProductionPlans;
final ScriptExhibitionGalleryRecordsSaver? saveGalleryRecords;
final ScriptExhibitionDefaultGeneratedImageRoot? defaultGeneratedImageRoot;
```

Add optional constructor params.

- [ ] **Step 4: Add viewmodel methods**

Add:

```dart
Future<ScriptExhibitionImageOrganizationPreview> previewScriptImageOrganization(
  ScriptExhibitionScript script,
) async {
  final plans = await loadProductionPlans();
  final records = await loadGalleryRecords();
  final service = ScriptExhibitionImageOrganizerService(
    defaultOutputRoot: defaultGeneratedImageRoot ?? _defaultGeneratedRoot,
  );
  return service.preview(
    targetScriptId: script.scriptId,
    targetScriptTitle: script.title,
    productionPlans: plans,
    galleryRecords: records,
    generatedRoots: _generatedRootsForOrganization(plans),
    originalSourcePaths: _originalSourceImagePathsForScript(script),
  );
}

Future<ScriptExhibitionImageOrganizationResult> organizeScriptImages(
  ScriptExhibitionScript script, {
  ScriptExhibitionImageOrganizationPreview? preview,
}) async {
  final currentPreview = preview ?? await previewScriptImageOrganization(script);
  final service = ScriptExhibitionImageOrganizerService(
    defaultOutputRoot: defaultGeneratedImageRoot ?? _defaultGeneratedRoot,
  );
  final result = await service.apply(currentPreview);
  if (result.failedImagePaths.isEmpty) {
    await saveProductionPlans?.call(result.updatedProductionPlans);
    await saveGalleryRecords?.call(result.updatedGalleryRecords);
    await reloadAfterExternalChanges();
  }
  return result;
}
```

Use existing reload method if available. If not available, call `await load()`.

Add `_generatedRootsForOrganization(plans)` and `_originalSourceImagePathsForScript(script)` helpers.

- [ ] **Step 5: Keep old source-folder cleanup unreachable**

Remove or stop using `previewSourceFolderCleanup`/`cleanSourceFolderImages` from UI. It can remain private temporarily for old tests, but public UI should no longer call it.

- [ ] **Step 6: Run viewmodel tests**

Run:

```powershell
flutter test test\ui\studio_shell\script_exhibition_room_viewmodel_test.dart
```

Expected: all pass after updating old source-folder cleanup test or marking it as service-level legacy coverage.

---

### Task 5: Script Exhibition UI Replacement

**Files:**
- Modify: `lib/ui/studio_shell/widgets/script_exhibition_room_page.dart`
- Modify: `test/ui/studio_shell/script_exhibition_room_page_test.dart`

- [ ] **Step 1: Write UI preview/apply test**

Add widget test:

```dart
testWidgets('organize script images previews counts before applying', (tester) async {
  final preview = ScriptExhibitionImageOrganizationPreview(
    moves: const [
      ScriptExhibitionImageMovePlan(
        sourcePath: r'C:\mixed\old.png',
        destinationPath: r'C:\out\script\version\001.png',
        productionPlanId: 'plan-1',
        taskId: 'task-1',
      ),
    ],
    orphanImagePaths: const [r'C:\out\orphan.png'],
    productionPlans: const [],
    galleryRecords: const [],
  );
  var applied = false;
  final viewModel = _FakeOrganizingScriptExhibitionRoomViewModel(
    preview: preview,
    onApply: () => applied = true,
  );

  await tester.pumpWidget(MaterialApp(
    theme: StudioTheme.build(),
    home: ScriptExhibitionRoomPage(
      viewModel: viewModel,
      onSendToScriptWorkbench: (_) {},
      onSendToWorkbench: (_) {},
    ),
  ));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('script-exhibition-script-card-script-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('script-exhibition-organize-script-images-script-1')));
  await tester.pumpAndSettle();

  expect(find.textContaining('1'), findsWidgets);
  expect(find.byKey(const ValueKey('script-exhibition-confirm-organize-script-images')), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('script-exhibition-confirm-organize-script-images')));
  await tester.pumpAndSettle();
  expect(applied, isTrue);
});
```

If subclassing the viewmodel is awkward, inject real callbacks and temp file fixtures as in existing tests.

- [ ] **Step 2: Run UI test and verify failure**

Run:

```powershell
flutter test test\ui\studio_shell\script_exhibition_room_page_test.dart --plain-name "organize script images previews counts before applying"
```

Expected: fails due missing UI key/action.

- [ ] **Step 3: Replace clean-source-folder handler**

Rename `_cleaningSourceFolderScriptId` to `_organizingScriptImagesScriptId`.

Replace `_confirmCleanSourceFolder` with:

```dart
Future<void> _confirmOrganizeScriptImages(
  BuildContext context,
  ScriptExhibitionScript script,
) async {
  if (_organizingScriptImagesScriptId != null) return;
  setState(() => _organizingScriptImagesScriptId = script.scriptId);
  try {
    final preview = await widget.viewModel.previewScriptImageOrganization(script);
    if (!mounted || !context.mounted) return;
    final confirmed = await _showScriptImageOrganizationDialog(
      context: context,
      preview: preview,
    );
    if (!confirmed || !mounted || !context.mounted) return;
    final result = await widget.viewModel.organizeScriptImages(script, preview: preview);
    if (!mounted || !context.mounted) return;
    _showSnackBar(
      context,
      'Organized ${result.movedImagePaths.length} images and deleted ${result.deletedOrphanImagePaths.length} orphan images.',
    );
  } catch (error) {
    if (mounted && context.mounted) {
      _showSnackBar(context, 'Failed to organize script images: $error');
    }
  } finally {
    if (mounted && _organizingScriptImagesScriptId == script.scriptId) {
      setState(() => _organizingScriptImagesScriptId = null);
    }
  }
}
```

- [ ] **Step 4: Update detail header button**

Replace key:

```dart
ValueKey('script-exhibition-clean-source-folder-${script.scriptId}')
```

with:

```dart
ValueKey('script-exhibition-organize-script-images-${script.scriptId}')
```

Use tooltip text matching the existing Chinese UI style for "Organize script images".

- [ ] **Step 5: Add dialog**

Replace `_showSourceFolderCleanupDialog` with `_showScriptImageOrganizationDialog`:

```dart
Future<bool> _showScriptImageOrganizationDialog({
  required BuildContext context,
  required ScriptExhibitionImageOrganizationPreview preview,
}) async {
  final sampleMoves = preview.moves.take(6).toList();
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: StudioTokens.surface2,
      title: const Text('Organize script images'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Move ${preview.moves.length} current-script images and delete ${preview.orphanImagePaths.length} global orphan images.'),
            const SizedBox(height: 12),
            for (final move in sampleMoves)
              Text(
                '${_exhibitionFileNameFromPath(move.sourcePath)} -> ${_exhibitionFileNameFromPath(move.destinationPath)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const ValueKey('script-exhibition-confirm-organize-script-images'),
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.drive_file_move_outline),
          label: const Text('Organize'),
        ),
      ],
    ),
  );
  return result ?? false;
}
```

- [ ] **Step 6: Run UI tests**

Run:

```powershell
flutter test test\ui\studio_shell\script_exhibition_room_page_test.dart
```

Expected: all pass after removing/updating old clean-source-folder key assertions.

---

### Task 6: Shell Wiring

**Files:**
- Modify: `lib/ui/studio_shell/widgets/studio_shell_view.dart`

- [ ] **Step 1: Wire persistence callbacks**

In the `ScriptExhibitionRoomViewModel` construction around the existing `loadProductionPlans` and `loadGalleryRecords` arguments, add:

```dart
saveProductionPlans: GetIt.I<ProductionQueueService>().savePlans,
saveGalleryRecords: GetIt.I<StudioGalleryService>().saveRecords,
defaultGeneratedImageRoot: () async =>
    FileService().resolvePictureSavePath('', '').then((path) {
      final normalized = path.trim();
      if (normalized.isEmpty) return '';
      return File(normalized).parent.path;
    }),
```

If `resolvePictureSavePath('', '')` is invalid on the current implementation, add a small `FileService.defaultPictureSaveDirectory()` method and call that instead.

- [ ] **Step 2: Add focused shell compile/analyze check**

Run:

```powershell
flutter analyze lib\ui\studio_shell\widgets\studio_shell_view.dart lib\ui\studio_shell\view_models\script_exhibition_room_viewmodel.dart lib\data\studio\services\script_exhibition_image_organizer_service.dart
```

Expected: no issues.

---

### Task 7: Verification Pass

**Files:**
- No new source files unless previous tests expose gaps.

- [ ] **Step 1: Run focused service and UI tests**

Run:

```powershell
flutter test test\data\studio\services\script_exhibition_image_organizer_service_test.dart
flutter test test\data\studio\services\production_nai_adapter_service_test.dart
flutter test test\data\studio\services\production_executor_service_test.dart
flutter test test\ui\studio_shell\script_exhibition_room_viewmodel_test.dart
flutter test test\ui\studio_shell\script_exhibition_room_page_test.dart
```

Expected: all pass.

- [ ] **Step 2: Run targeted analyze**

Run:

```powershell
flutter analyze lib\data\studio\services\script_exhibition_image_organizer_service.dart lib\data\studio\services\production_nai_adapter_service.dart lib\data\studio\services\production_executor_service.dart lib\ui\studio_shell\view_models\script_exhibition_room_viewmodel.dart lib\ui\studio_shell\widgets\script_exhibition_room_page.dart lib\ui\studio_shell\widgets\studio_shell_view.dart
```

Expected: no issues.

- [ ] **Step 3: Update Beads**

Run after implementation is actually verified:

```powershell
bd close NAI_NEW-vlks --reason="Implemented Script Exhibition image organization, future script output layout, UI preview/apply flow, and focused verification."
```

Expected: issue closes only after all tests pass.
