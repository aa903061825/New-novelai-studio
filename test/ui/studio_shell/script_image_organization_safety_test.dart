import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/models/studio_gallery_record.dart';
import 'package:novel_studio/data/studio/models/workbench_document.dart';
import 'package:novel_studio/data/studio/services/script_exhibition_image_organizer_service.dart';
import 'package:novel_studio/data/studio/services/studio_gallery_service.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';
import 'package:novel_studio/ui/studio_shell/view_models/script_exhibition_room_viewmodel.dart';

// Audit-only safety expectations. Every file operation uses a freshly created
// system temporary directory; no active workspace, credentials, or API is used.
void main() {
  late Directory root;
  late Directory output;
  late WorkspaceService workspace;
  late StudioGalleryService gallery;
  final now = DateTime.utc(2026, 10, 3);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('novel-studio-safety-audit-');
    workspace = WorkspaceService();
    await workspace.createWorkspace(root.path);
    output = await Directory('${root.path}/generated').create();
    gallery = StudioGalleryService(workspaceService: workspace);
  });

  tearDown(() async {
    // Only the fixture root created by setUp can be removed by this harness.
    await root.delete(recursive: true);
  });

  Future<File> image(String name) async {
    final file = File('${output.path}/$name.png');
    await file.writeAsBytes([1, 2, 3]);
    return file;
  }

  ProductionPlan plan(List<File> files) => ProductionPlan(
        id: 'audit-plan',
        name: 'Audit Version',
        executionSettings: ProductionPlanExecutionSettings(
          outputDirectory: output.path,
        ),
        tasks: [
          for (final entry in files.indexed)
            ProductionTask.scriptRecastFrame(
              id: 'task-${entry.$1}',
              planId: 'audit-plan',
              title: 'Audit Frame',
              scriptId: 'audit-script',
              scriptName: 'Audit Script',
              recastRunId: 'audit-run',
              frameIndex: entry.$1 + 1,
              sourceFileName: '${entry.$1 + 1}.json',
              payload: const {'input': 'audit only'},
              outputImagePath: entry.$2.path,
              status: ProductionTaskStatus.completed,
              createdAt: now,
              updatedAt: now,
            ),
        ],
        createdAt: now,
        updatedAt: now,
      );

  ScriptExhibitionScript script() => ScriptExhibitionScript(
        scriptId: 'audit-script',
        title: 'Audit Script',
        sourceFolder: '',
        updatedAt: now,
        versions: const [],
        status: ScriptExhibitionScriptStatus.active,
        originalCount: 0,
        generatedImageCount: 0,
        imageLikeItemCount: 0,
        hasImage: false,
        coverItem: null,
        pendingCount: 0,
        firstNeedsActionItem: null,
      );

  Future<void> creativeRecord(File file) => gallery.saveRecords([
        StudioGalleryRecord(
          id: 'creative-record',
          createdAt: now,
          title: 'Saved Creative Image',
          imagePath: file.path,
          info: 'audit only',
          additionalInfo: const {},
          document: WorkbenchDocument.fromPayloadJson(const {}),
        ),
      ]);

  test('missing reference records must not authorize deleting all images',
      () async {
    final images = [await image('first'), await image('second')];
    final organizer = ScriptExhibitionImageOrganizerService(
      defaultOutputRoot: () async => output.path,
    );
    final preview = await organizer.preview(
      targetScriptTitlesById: const {'audit-script': 'Audit Script'},
      productionPlans: const [],
      galleryRecords: const [],
      generatedRoots: [output.path],
    );
    final result = await organizer.apply(preview);
    expect(result.deletedOrphanImagePaths, isEmpty);
    for (final file in images) {
      expect(await file.exists(), isTrue);
    }
  });

  for (final check in ['file', 'record']) {
    test('exhibition wiring must preserve a creative gallery $check', () async {
      final creative = await image('saved-creative');
      final generated = await image('script-generated');
      await creativeRecord(creative);
      await gallery.saveRecastFrameSnapshot(
        payload: const {'input': 'audit only'},
        title: 'Script image',
        imagePath: generated.path,
        info: 'audit only',
        id: 'script-record',
        provenance: StudioRecastProvenance(
          scriptId: 'audit-script',
          scriptName: 'Audit Script',
          productionPlanId: 'audit-plan',
          productionPlanFingerprint: 'plan',
          taskId: 'task-0',
          frameIndex: 1,
          sourceFileName: '1.json',
          payloadFingerprint: 'payload',
          mappingConfigFingerprint: 'mapping',
          outputImagePath: generated.path,
        ),
      );
      var plans = [
        plan([generated])
      ];
      final viewModel = ScriptExhibitionRoomViewModel(
        loadProductionPlans: () async => plans,
        // Complete reference reader and partial-update writer used by the shell.
        loadGalleryRecords: gallery.loadRecords,
        saveGalleryRecords: gallery.mergeImagePaths,
        saveProductionPlans: (updated) async => plans = updated,
        defaultGeneratedImageRoot: () async => output.path,
      );
      addTearDown(viewModel.dispose);
      await viewModel.organizeScriptImages(script());
      if (check == 'file') {
        expect(await creative.exists(), isTrue);
      } else {
        final records = await gallery.loadRecords();
        expect(records.map((record) => record.id), contains('creative-record'));
        expect(records.singleWhere((r) => r.id == 'script-record').imagePath,
            plans.single.tasks.single.outputImagePath);
      }
    });
  }

  test('partial move failure must persist successful path changes', () async {
    final first = await image('first');
    final second = await image('second');
    final originalPlan = plan([first, second]);
    var storedPlans = [originalPlan];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadProductionPlans: () async => storedPlans,
      loadGalleryRecords: () async => const [],
      saveProductionPlans: (updated) async => storedPlans = updated,
      saveGalleryRecords: (_) async {},
      defaultGeneratedImageRoot: () async => output.path,
    );
    addTearDown(viewModel.dispose);
    final preview = await viewModel.previewScriptImageOrganization(script());
    // Simulate a source disappearing after preview, without touching real data.
    await second.delete();
    final result =
        await viewModel.organizeScriptImages(script(), preview: preview);
    expect(result.movedImagePaths, hasLength(1));
    expect(result.failedImagePaths, hasLength(1));
    expect(storedPlans.single.tasks.first.outputImagePath,
        result.movedImagePaths.single);
  });

  test('persistence failure must leave the recorded source recoverable',
      () async {
    final generated = await image('script-generated');
    final originalPlan = plan([generated]);
    final viewModel = ScriptExhibitionRoomViewModel(
      loadProductionPlans: () async => [originalPlan],
      loadGalleryRecords: () async => const [],
      saveProductionPlans: (_) async => throw StateError('audit disk failure'),
      saveGalleryRecords: (_) async {},
      defaultGeneratedImageRoot: () async => output.path,
    );
    addTearDown(viewModel.dispose);
    await expectLater(
        viewModel.organizeScriptImages(script()), throwsStateError);
    expect(await generated.exists(), isTrue);
  });
}
