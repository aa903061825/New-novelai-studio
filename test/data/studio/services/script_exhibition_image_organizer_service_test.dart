import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/models/studio_gallery_record.dart';
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

      final expected = [
        root.path,
        'Rain Archive',
        'Hero Version A',
        '001.png',
      ].join(Platform.pathSeparator);

      expect(
        ScriptExhibitionImagePathPolicy.normalizedPathKey(path),
        ScriptExhibitionImagePathPolicy.normalizedPathKey(expected),
      );
    });

    test('adds same-frame suffixes without overwriting existing destinations',
        () {
      final root =
          Directory.systemTemp.createTempSync('organizer-collision-root-');
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

      expect(
        first,
        endsWith(
          '${Platform.pathSeparator}Rain- Archive${Platform.pathSeparator}Plan-Version${Platform.pathSeparator}001.png',
        ),
      );
      expect(
        second,
        endsWith(
          '${Platform.pathSeparator}Rain- Archive${Platform.pathSeparator}Plan-Version${Platform.pathSeparator}001-2.png',
        ),
      );
    });

    test('adds suffix when destination file already exists on disk', () {
      final root = Directory.systemTemp.createTempSync(
        'organizer-disk-collision-root-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final destinationDirectory = Directory(
        [
          root.path,
          'Rain- Archive',
          'Plan-Version',
        ].join(Platform.pathSeparator),
      )..createSync(recursive: true);
      File(
        [
          destinationDirectory.path,
          '001.png',
        ].join(Platform.pathSeparator),
      ).writeAsBytesSync(const [1, 2, 3]);

      final task = ProductionTask.scriptRecastFrame(
        id: 'task-3',
        planId: 'plan-1',
        title: 'Frame One Existing File',
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

      final destination = ScriptExhibitionImagePathPolicy.destinationForTask(
        outputRoot: root.path,
        planName: 'Plan/Version',
        task: task,
        existingDestinationKeys: const {},
      );

      expect(
        destination,
        endsWith(
          '${Platform.pathSeparator}Rain- Archive${Platform.pathSeparator}Plan-Version${Platform.pathSeparator}001-2.png',
        ),
      );
    });

    test('preserves valid internal hyphen runs while sanitizing segments', () {
      expect(
        ScriptExhibitionImagePathPolicy.safePathSegment('Hero---Version  A'),
        'Hero---Version A',
      );
      expect(
        ScriptExhibitionImagePathPolicy.safePathSegment('  .-///  '),
        'untitled',
      );
    });
  });

  group('ScriptExhibitionImageOrganizerService', () {
    test(
        'organizes current script production images and updates gallery provenance',
        () async {
      final root = Directory.systemTemp.createTempSync(
        'script-organizer-root-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final mixed = Directory('${root.path}${Platform.pathSeparator}mixed')
        ..createSync();
      final generated = File(
        '${mixed.path}${Platform.pathSeparator}random.png',
      )..writeAsBytesSync([1, 2, 3]);
      final original = File(
        '${mixed.path}${Platform.pathSeparator}001-source.png',
      )..writeAsBytesSync([9, 9, 9]);
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
        additionalInfo: const {'rating': 'keeper'},
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
        targetScriptTitlesById: const {'script-1': 'Rain Archive'},
        productionPlans: [plan],
        galleryRecords: [record],
        generatedRoots: [root.path],
        originalSourcePaths: {original.path},
      );

      expect(preview.moves, hasLength(1));
      expect(preview.orphanImagePaths, isEmpty);

      final result = await service.apply(preview);

      final movedPath =
          result.updatedProductionPlans.single.tasks.single.outputImagePath!;
      expect(
        movedPath,
        endsWith(
          'Rain Archive${Platform.pathSeparator}Hero Version A${Platform.pathSeparator}001.png',
        ),
      );
      expect(File(movedPath).existsSync(), isTrue);
      expect(generated.existsSync(), isTrue);
      expect(original.existsSync(), isTrue);
      expect(orphan.existsSync(), isTrue);
      expect(result.updatedGalleryRecords.single.imagePath, movedPath);
      expect(
        result.updatedGalleryRecords.single.provenance!.outputImagePath,
        movedPath,
      );
      expect(
        result.updatedGalleryRecords.single.additionalInfo['provenance']
            ['outputImagePath'],
        movedPath,
      );
      expect(
        result.updatedGalleryRecords.single.additionalInfo['rating'],
        'keeper',
      );
    });

    test('organizes generated images for every target exhibition script',
        () async {
      final root = Directory.systemTemp.createTempSync(
        'script-organizer-all-targets-root-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final loose = Directory('${root.path}${Platform.pathSeparator}loose')
        ..createSync();
      final firstGenerated = File(
        '${loose.path}${Platform.pathSeparator}first.png',
      )..writeAsBytesSync([1, 2, 3]);
      final secondGenerated = File(
        '${loose.path}${Platform.pathSeparator}second.png',
      )..writeAsBytesSync([4, 5, 6]);
      final ignoredGenerated = File(
        '${loose.path}${Platform.pathSeparator}ignored.png',
      )..writeAsBytesSync([7, 8, 9]);
      final now = DateTime.utc(2026);

      ProductionTask taskFor({
        required String id,
        required String scriptId,
        required String scriptName,
        required String outputPath,
        required int frameIndex,
      }) {
        return ProductionTask.scriptRecastFrame(
          id: id,
          planId: 'plan-1',
          title: 'Frame $frameIndex',
          scriptId: scriptId,
          scriptName: scriptName,
          recastRunId: 'run-1',
          frameIndex: frameIndex,
          sourceFileName: '${frameIndex.toString().padLeft(3, '0')}.json',
          payload: const {'input': 'frame'},
          outputImagePath: outputPath,
          status: ProductionTaskStatus.completed,
          createdAt: now,
          updatedAt: now,
        );
      }

      final plan = ProductionPlan(
        id: 'plan-1',
        name: 'Hero Version A',
        tasks: [
          taskFor(
            id: 'task-1',
            scriptId: 'script-1',
            scriptName: 'Rain Archive',
            outputPath: firstGenerated.path,
            frameIndex: 1,
          ),
          taskFor(
            id: 'task-2',
            scriptId: 'script-2',
            scriptName: 'Moon Archive',
            outputPath: secondGenerated.path,
            frameIndex: 2,
          ),
          taskFor(
            id: 'task-3',
            scriptId: 'script-outside',
            scriptName: 'Outside Archive',
            outputPath: ignoredGenerated.path,
            frameIndex: 3,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      final service = ScriptExhibitionImageOrganizerService(
        defaultOutputRoot: () async => root.path,
      );

      final preview = await service.preview(
        targetScriptTitlesById: const {
          'script-1': 'Rain Archive',
          'script-2': 'Moon Archive',
        },
        productionPlans: [plan],
        galleryRecords: const [],
        generatedRoots: const [],
      );

      expect(preview.moves.map((move) => move.taskId), ['task-1', 'task-2']);

      final result = await service.apply(preview);

      expect(result.failedImagePaths, isEmpty);
      expect(result.movedImagePaths, hasLength(2));
      expect(firstGenerated.existsSync(), isTrue);
      expect(secondGenerated.existsSync(), isTrue);
      expect(ignoredGenerated.existsSync(), isTrue);
      expect(
        result.updatedProductionPlans.single.tasks
            .where((task) => task.id != 'task-3')
            .map((task) => task.outputImagePath),
        everyElement(contains('${Platform.pathSeparator}Hero Version A')),
      );
      expect(
        result.updatedProductionPlans.single.tasks
            .singleWhere((task) => task.id == 'task-3')
            .outputImagePath,
        ignoredGenerated.path,
      );
    });

    test(
        'deduplicates duplicate source paths and updates every referencing task',
        () async {
      final root = Directory.systemTemp.createTempSync(
        'script-organizer-duplicate-source-root-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final generated = File('${root.path}${Platform.pathSeparator}random.png')
        ..writeAsBytesSync([1, 2, 3]);
      final now = DateTime.utc(2026);
      final firstTask = ProductionTask.scriptRecastFrame(
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
      final secondTask = ProductionTask.scriptRecastFrame(
        id: 'task-2',
        planId: 'plan-1',
        title: 'Frame One Duplicate',
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
        tasks: [firstTask, secondTask],
        createdAt: now,
        updatedAt: now,
      );
      final service = ScriptExhibitionImageOrganizerService(
        defaultOutputRoot: () async => root.path,
      );

      final preview = await service.preview(
        targetScriptTitlesById: const {'script-1': 'Rain Archive'},
        productionPlans: [plan],
        galleryRecords: const [],
        generatedRoots: [root.path],
      );

      expect(preview.moves, hasLength(1));

      final result = await service.apply(preview);

      expect(result.failedImagePaths, isEmpty);
      expect(result.movedImagePaths, hasLength(1));
      final updatedTasks = result.updatedProductionPlans.single.tasks;
      expect(updatedTasks[0].outputImagePath, result.movedImagePaths.single);
      expect(updatedTasks[1].outputImagePath, result.movedImagePaths.single);
      expect(generated.existsSync(), isTrue);
    });

    test(
        'preview skips already-organized images without treating source files as collisions',
        () async {
      final root = Directory.systemTemp.createTempSync(
        'script-organizer-idempotent-root-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final destinationDirectory = Directory(
        [
          root.path,
          'Rain Archive',
          'Hero Version A',
        ].join(Platform.pathSeparator),
      )..createSync(recursive: true);
      final first = File(
        [
          destinationDirectory.path,
          '001.png',
        ].join(Platform.pathSeparator),
      )..writeAsBytesSync([1, 2, 3]);
      final second = File(
        [
          destinationDirectory.path,
          '001-2.png',
        ].join(Platform.pathSeparator),
      )..writeAsBytesSync([4, 5, 6]);
      final now = DateTime.utc(2026);
      final firstTask = ProductionTask.scriptRecastFrame(
        id: 'task-1',
        planId: 'plan-1',
        title: 'Frame One',
        scriptId: 'script-1',
        scriptName: 'Rain Archive',
        recastRunId: 'run-1',
        frameIndex: 1,
        sourceFileName: '001.json',
        payload: const {'input': 'frame'},
        outputImagePath: first.path,
        status: ProductionTaskStatus.completed,
        createdAt: now,
        updatedAt: now,
      );
      final secondTask = ProductionTask.scriptRecastFrame(
        id: 'task-2',
        planId: 'plan-1',
        title: 'Frame One Rerun',
        scriptId: 'script-1',
        scriptName: 'Rain Archive',
        recastRunId: 'run-1',
        frameIndex: 1,
        sourceFileName: '001.json',
        payload: const {'input': 'frame'},
        outputImagePath: second.path,
        status: ProductionTaskStatus.completed,
        createdAt: now,
        updatedAt: now,
      );
      final plan = ProductionPlan(
        id: 'plan-1',
        name: 'Hero Version A',
        tasks: [firstTask, secondTask],
        createdAt: now,
        updatedAt: now,
      );
      final service = ScriptExhibitionImageOrganizerService(
        defaultOutputRoot: () async => root.path,
      );

      final preview = await service.preview(
        targetScriptTitlesById: const {'script-1': 'Rain Archive'},
        productionPlans: [plan],
        galleryRecords: const [],
        generatedRoots: [root.path],
      );

      expect(preview.moves, isEmpty);
      expect(preview.orphanImagePaths, isEmpty);
    });

    test(
        'preview skips already-organized higher suffixes when lower suffix is missing',
        () async {
      final root = Directory.systemTemp.createTempSync(
        'script-organizer-idempotent-gap-root-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final destinationDirectory = Directory(
        [
          root.path,
          'Rain Archive',
          'Hero Version A',
        ].join(Platform.pathSeparator),
      )..createSync(recursive: true);
      final first = File(
        [
          destinationDirectory.path,
          '001.png',
        ].join(Platform.pathSeparator),
      )..writeAsBytesSync([1, 2, 3]);
      final third = File(
        [
          destinationDirectory.path,
          '001-3.png',
        ].join(Platform.pathSeparator),
      )..writeAsBytesSync([4, 5, 6]);
      final now = DateTime.utc(2026);
      final firstTask = ProductionTask.scriptRecastFrame(
        id: 'task-1',
        planId: 'plan-1',
        title: 'Frame One',
        scriptId: 'script-1',
        scriptName: 'Rain Archive',
        recastRunId: 'run-1',
        frameIndex: 1,
        sourceFileName: '001.json',
        payload: const {'input': 'frame'},
        outputImagePath: first.path,
        status: ProductionTaskStatus.completed,
        createdAt: now,
        updatedAt: now,
      );
      final thirdTask = ProductionTask.scriptRecastFrame(
        id: 'task-3',
        planId: 'plan-1',
        title: 'Frame One Third Variant',
        scriptId: 'script-1',
        scriptName: 'Rain Archive',
        recastRunId: 'run-1',
        frameIndex: 1,
        sourceFileName: '001.json',
        payload: const {'input': 'frame'},
        outputImagePath: third.path,
        status: ProductionTaskStatus.completed,
        createdAt: now,
        updatedAt: now,
      );
      final plan = ProductionPlan(
        id: 'plan-1',
        name: 'Hero Version A',
        tasks: [firstTask, thirdTask],
        createdAt: now,
        updatedAt: now,
      );
      final service = ScriptExhibitionImageOrganizerService(
        defaultOutputRoot: () async => root.path,
      );

      final preview = await service.preview(
        targetScriptTitlesById: const {'script-1': 'Rain Archive'},
        productionPlans: [plan],
        galleryRecords: const [],
        generatedRoots: [root.path],
      );

      expect(preview.moves, isEmpty);
      expect(preview.orphanImagePaths, isEmpty);
    });

    test(
        'does not move non-completed script recast output paths but keeps them referenced',
        () async {
      final root = Directory.systemTemp.createTempSync(
        'script-organizer-non-completed-root-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final now = DateTime.utc(2026);
      final nonCompletedStatuses = [
        ProductionTaskStatus.queued,
        ProductionTaskStatus.running,
        ProductionTaskStatus.failed,
        ProductionTaskStatus.skipped,
      ];
      ProductionTask taskWithStatus(int index, ProductionTaskStatus status) {
        final output = File(
          '${root.path}${Platform.pathSeparator}stale-$index.png',
        )..writeAsBytesSync([index]);
        return ProductionTask.scriptRecastFrame(
          id: 'task-$index',
          planId: 'plan-1',
          title: 'Frame $index',
          scriptId: 'script-1',
          scriptName: 'Rain Archive',
          recastRunId: 'run-1',
          frameIndex: index,
          sourceFileName: '$index.json',
          payload: const {'input': 'frame'},
          outputImagePath: output.path,
          status: status,
          createdAt: now,
          updatedAt: now,
        );
      }

      final tasks = [
        for (final entry in nonCompletedStatuses.indexed)
          taskWithStatus(entry.$1, entry.$2),
      ];
      final plan = ProductionPlan(
        id: 'plan-1',
        name: 'Hero Version A',
        tasks: tasks,
        createdAt: now,
        updatedAt: now,
      );
      final service = ScriptExhibitionImageOrganizerService(
        defaultOutputRoot: () async => root.path,
      );

      final preview = await service.preview(
        targetScriptTitlesById: const {'script-1': 'Rain Archive'},
        productionPlans: [plan],
        galleryRecords: const [],
        generatedRoots: [root.path],
      );

      expect(preview.moves, isEmpty);
      expect(preview.orphanImagePaths, isEmpty);
    });

    test('keeps referenced gallery-only image under generated root', () async {
      final root = Directory.systemTemp.createTempSync(
        'script-organizer-gallery-root-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final galleryOnly =
          File('${root.path}${Platform.pathSeparator}gallery-only.png')
            ..writeAsBytesSync([1, 2, 3]);
      final now = DateTime.utc(2026);
      final record = StudioGalleryRecord.fromRecastPayload(
        payload: const {'input': 'frame'},
        id: 'gallery-1',
        createdAt: now,
        title: 'Frame One',
        imagePath: galleryOnly.path,
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
          outputImagePath: galleryOnly.path,
        ),
      );
      final service = ScriptExhibitionImageOrganizerService(
        defaultOutputRoot: () async => root.path,
      );

      final preview = await service.preview(
        targetScriptTitlesById: const {'script-1': 'Rain Archive'},
        productionPlans: const [],
        galleryRecords: [record],
        generatedRoots: [root.path],
      );

      expect(preview.moves, isEmpty);
      expect(preview.orphanImagePaths, isEmpty);
    });

    test('does not delete orphans when move source is missing at apply time',
        () async {
      final root = Directory.systemTemp.createTempSync(
        'script-organizer-missing-root-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final generated = File('${root.path}${Platform.pathSeparator}random.png')
        ..writeAsBytesSync([1, 2, 3]);
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
      final service = ScriptExhibitionImageOrganizerService(
        defaultOutputRoot: () async => root.path,
      );
      final preview = await service.preview(
        targetScriptTitlesById: const {'script-1': 'Rain Archive'},
        productionPlans: [plan],
        galleryRecords: const [],
        generatedRoots: [root.path],
      );

      generated.deleteSync();
      final result = await service.apply(preview);

      expect(result.failedImagePaths, [generated.absolute.path]);
      expect(result.movedImagePaths, isEmpty);
      expect(orphan.existsSync(), isTrue);
    });

    test('does not overwrite destination that appears before apply', () async {
      final root = Directory.systemTemp.createTempSync(
        'script-organizer-apply-collision-root-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final generated = File('${root.path}${Platform.pathSeparator}random.png')
        ..writeAsBytesSync([1, 2, 3]);
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
      final service = ScriptExhibitionImageOrganizerService(
        defaultOutputRoot: () async => root.path,
      );
      final preview = await service.preview(
        targetScriptTitlesById: const {'script-1': 'Rain Archive'},
        productionPlans: [plan],
        galleryRecords: const [],
        generatedRoots: [root.path],
      );
      final move = preview.moves.single;
      final destination = File(move.destinationPath)
        ..createSync(recursive: true)
        ..writeAsBytesSync([9, 9, 9]);

      final result = await service.apply(preview);

      expect(result.failedImagePaths, [generated.absolute.path]);
      expect(result.movedImagePaths, isEmpty);
      expect(result.deletedOrphanImagePaths, isEmpty);
      expect(generated.existsSync(), isTrue);
      expect(destination.readAsBytesSync(), [9, 9, 9]);
      expect(orphan.existsSync(), isTrue);
    });

    test('concurrent organization reserves a destination without overwriting',
        () async {
      final root = Directory.systemTemp.createTempSync('organizer-concurrent-');
      addTearDown(() => root.deleteSync(recursive: true));
      final first = File('${root.path}/first.png')..writeAsBytesSync([1, 2, 3]);
      final second = File('${root.path}/second.png')
        ..writeAsBytesSync([9, 8, 7, 6]);
      final destination = '${root.path}/organized/frame.png';
      final service = ScriptExhibitionImageOrganizerService(
        defaultOutputRoot: () async => root.path,
      );
      ScriptExhibitionImageOrganizationPreview preview(File source) =>
          ScriptExhibitionImageOrganizationPreview(
            moves: [
              ScriptExhibitionImageMovePlan(
                sourcePath: source.path,
                destinationPath: destination,
                productionPlanId: 'plan',
                taskId: 'task',
              ),
            ],
            orphanImagePaths: const [],
            productionPlans: const [],
            galleryRecords: const [],
          );
      final results = await Future.wait([
        service.apply(preview(first)),
        service.apply(preview(second)),
      ]);
      expect(
          results.expand((result) => result.organizedImagePaths), hasLength(1));
      expect(results.expand((result) => result.failedImagePaths), hasLength(1));
      final winner =
          results.first.organizedImagePaths.isNotEmpty ? first : second;
      expect(File(destination).readAsBytesSync(), winner.readAsBytesSync());
      expect(first.readAsBytesSync(), [1, 2, 3]);
      expect(second.readAsBytesSync(), [9, 8, 7, 6]);
    });
  });
}
