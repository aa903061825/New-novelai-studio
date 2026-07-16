import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/models/script_exhibition_recast_summary.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/models/studio_gallery_record.dart';
import 'package:novel_studio/data/studio/models/tokenizer_script.dart';
import 'package:novel_studio/ui/studio_shell/view_models/script_exhibition_room_viewmodel.dart';

class _ThrowingSearchImageItem extends ScriptExhibitionItem {
  _ThrowingSearchImageItem({required super.updatedAt})
      : super(
          id: 'lazy-item',
          scriptId: 'lazy-script',
          scriptTitle: 'Lazy Search Script',
          sourceFolder: r'C:\stories\lazy',
          versionId: 'lazy-version',
          versionLabel: 'Lazy',
          sourceKind: ScriptExhibitionItemSourceKind.generated,
          frameIndex: 1,
          sourceFileName: 'lazy-frame.json',
          sourcePath: r'C:\stories\lazy\lazy-frame.json',
          title: 'Lazy Frame',
          subtitle: 'Lazy item',
          prompt: 'lazy prompt text',
          imagePath: '',
          statusLabel: 'Ready',
        );

  @override
  String get imagePath => throw StateError('imagePath should stay lazy');
}

void main() {
  test('script search does not materialize image paths', () {
    final now = DateTime.parse('2026-06-04T10:00:00Z');
    final item = _ThrowingSearchImageItem(updatedAt: now);
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => const [],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    )..snapshot = ScriptExhibitionSnapshot(
        scripts: [
          ScriptExhibitionScript(
            scriptId: 'lazy-script',
            title: 'Lazy Search Script',
            sourceFolder: r'C:\stories\lazy',
            updatedAt: now,
            versions: [
              ScriptExhibitionVersion(
                id: 'lazy-version',
                label: 'Lazy',
                description: 'Lazy search version',
                updatedAt: now,
                items: [item],
              ),
            ],
            status: ScriptExhibitionScriptStatus.active,
            originalCount: 0,
            generatedImageCount: 1,
            imageLikeItemCount: 1,
            hasImage: true,
            coverItem: item,
            pendingCount: 0,
            firstNeedsActionItem: null,
          ),
        ],
        totalImageCount: 1,
        generatedImageCount: 1,
        needsActionCount: 0,
      );

    viewModel.updateScriptSearchQuery('lazy prompt');

    expect(viewModel.visibleScripts.single.scriptId, 'lazy-script');
  });

  test('loads original exhibition frames from recast script caches', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-exhibition-recast-cache-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final image = File('${tempDir.path}${Platform.pathSeparator}001.png');
    await image.writeAsBytes(const [0, 1, 2, 3]);
    final script = Script(
      id: 'recast-script',
      name: '重铸剧本',
      rootPath: tempDir.path,
      detectedSchema: ScriptSchema.baseInline,
      frames: [
        ScriptFrame(
          index: 1,
          fileName: '001.png',
          sourcePath: image.path,
          sourceImagePath: image.path,
          rawJson: '{}',
          parsed: const ParsedFrame(baseCaption: 'recast prompt'),
          detectedSchema: ScriptSchema.baseInline,
          parseStatus: ScriptFrameParseStatus.parsed,
        ),
      ],
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadRecastCaches: () async => [
        RecastScriptCache(
          scriptId: 'recast-script',
          scriptName: '重铸剧本',
          sourceRootPath: tempDir.path,
          sourceFingerprint: 'fingerprint',
          updatedAt: DateTime.parse('2026-06-04T10:00:00Z'),
          mapping: RecastMapping.defaults('recast-script'),
          scriptSnapshot: script.toJson(),
        ),
      ],
      loadScripts: () async => const [],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final exhibitionScript = viewModel.snapshot.scripts.single;
    expect(exhibitionScript.scriptId, 'recast-script');
    expect(exhibitionScript.title, '重铸剧本');
    final item = exhibitionScript.versions.single.items.single;
    expect(item.sourceKind, ScriptExhibitionItemSourceKind.original);
    expect(item.sourceFileName, '001.png');
    expect(item.imagePath, image.path);
    expect(item.prompt, 'recast prompt');
  });

  test('loads missing generation parameters from local png metadata lazily',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'script-exhibition-viewmodel-png-metadata-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final imageFile = File('${directory.path}/metadata.png');
    await imageFile.writeAsBytes(_pngWithTextChunks({
      'Description': 'metadata prompt, warm light',
      'Comment': jsonEncode({
        'seed': 424242,
        'steps': 31,
        'sampler': 'k_euler_ancestral',
        'scale': 5,
        'cfg_rescale': 0.45,
        'width': 832,
        'height': 1216,
        'noise_schedule': 'karras',
      }),
    }));
    final source = _source(
      'source-metadata',
      'metadata.png',
      imageFile.path,
      defaultImagePath: imageFile.path,
      kind: TokenizerScriptSourceKind.image,
    );
    final script = _script().copyWith(
      sourceFiles: [source],
      imageTasks: [
        _task(
          id: 'task-metadata',
          source: source,
          prompt: 'metadata prompt, warm light',
          status: TokenizerTaskReviewStatus.confirmed,
        ),
      ],
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [script],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final item = viewModel.snapshot.scripts.single.items.single;
    expect(item.generationParams, isEmpty);

    final params = await viewModel.loadGenerationParamsForItem(item);

    expect(params['seed'], 424242);
    expect(params['steps'], 31);
    expect(params['sampler'], 'k_euler_ancestral');
    expect(params['scale'], 5);
    expect(params['cfg_rescale'], 0.45);
    expect(params['width'], 832);
    expect(params['height'], 1216);
    expect(params['noise_schedule'], 'karras');
  });

  test(
      'supplements local png metadata when existing generation params only contain prompt data',
      () async {
    final imagePath =
        '${Uri.base.toFilePath()}assets${Platform.pathSeparator}appicon.png';
    final viewModel = ScriptExhibitionRoomViewModel(
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      loadImageGenerationParams: (_) async => const {
        'seed': 512780596,
        'steps': 28,
        'sampler': 'k_euler_ancestral',
        'scale': 4,
        'cfg_rescale': 0.4,
        'width': 832,
        'height': 1216,
        'noise_schedule': 'karras',
      },
    );
    final item = ScriptExhibitionItem(
      id: 'prompt-only-item',
      scriptId: 'script-1',
      scriptTitle: 'Script',
      sourceFolder: r'C:\stories\script',
      versionId: ScriptExhibitionVersion.originalId,
      versionLabel: 'Default',
      sourceKind: ScriptExhibitionItemSourceKind.original,
      frameIndex: 33,
      sourceFileName: 'p33.png',
      sourcePath: imagePath,
      title: '#33 p33.png',
      subtitle: 'Parsed',
      prompt: 'metadata prompt',
      imagePath: imagePath,
      statusLabel: 'Parsed',
      updatedAt: DateTime.parse('2026-06-20T10:00:00Z'),
      generationParams: const {
        'v4_prompt': {
          'caption': {'base_caption': 'metadata prompt'},
        },
      },
    );

    final params = await viewModel.loadGenerationParamsForItem(item);

    expect(params['v4_prompt'], isA<Map>());
    expect(params['seed'], 512780596);
    expect(params['steps'], 28);
    expect(params['sampler'], 'k_euler_ancestral');
    expect(params['scale'], 4);
    expect(params['cfg_rescale'], 0.4);
    expect(params['width'], 832);
    expect(params['height'], 1216);
    expect(params['noise_schedule'], 'karras');
  });

  test('loads full recast frame details only after selecting a summary script',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-exhibition-summary-detail-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final firstImage = File('${tempDir.path}${Platform.pathSeparator}001.png');
    final secondImage = File('${tempDir.path}${Platform.pathSeparator}002.png');
    await firstImage.writeAsBytes(const [0, 1, 2, 3]);
    await secondImage.writeAsBytes(const [0, 1, 2, 3]);
    final summary = RecastExhibitionScript(
      scriptId: 'summary-script',
      scriptName: 'Summary Script',
      sourceRootPath: tempDir.path,
      updatedAt: DateTime.parse('2026-06-04T10:00:00Z'),
      detectedSchema: ScriptSchema.unknown,
      summaryOnly: true,
      frameCount: 2,
      frames: [
        RecastExhibitionFrame(
          index: 1,
          fileName: '001.png',
          sourcePath: firstImage.path,
        ),
      ],
    );
    final detail = RecastExhibitionScript(
      scriptId: 'summary-script',
      scriptName: 'Summary Script',
      sourceRootPath: tempDir.path,
      updatedAt: DateTime.parse('2026-06-04T10:00:00Z'),
      detectedSchema: ScriptSchema.baseInline,
      frames: [
        RecastExhibitionFrame(
          index: 1,
          fileName: '001.png',
          sourcePath: firstImage.path,
          prompt: 'first prompt',
        ),
        RecastExhibitionFrame(
          index: 2,
          fileName: '002.png',
          sourcePath: secondImage.path,
          prompt: 'second prompt',
        ),
      ],
    );
    var detailLoadCount = 0;
    final viewModel = ScriptExhibitionRoomViewModel(
      loadRecastScripts: () async => [summary],
      loadRecastScript: (scriptId) async {
        detailLoadCount += 1;
        expect(scriptId, 'summary-script');
        return detail;
      },
      loadScripts: () async => const [],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    var script = viewModel.snapshot.scripts.single;
    expect(script.summaryOnly, isTrue);
    expect(script.originalCount, 2);
    expect(script.versions.single.items, hasLength(1));

    viewModel.selectScript('summary-script');
    await Future<void>.delayed(Duration.zero);

    script = viewModel.selectedScript!;
    expect(detailLoadCount, 1);
    expect(script.summaryOnly, isFalse);
    expect(script.originalCount, 2);
    expect(script.versions.single.items, hasLength(2));
    expect(script.versions.single.items.last.prompt, 'second prompt');
  });

  test('ignores stale summary detail after a newer full load publishes',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-exhibition-stale-detail-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final image = File('${tempDir.path}${Platform.pathSeparator}001.png');
    await image.writeAsBytes(const [0, 1, 2, 3]);
    final initialSummary = RecastExhibitionScript(
      scriptId: 'summary-script',
      scriptName: 'Initial summary',
      sourceRootPath: tempDir.path,
      updatedAt: DateTime.parse('2026-06-04T10:00:00Z'),
      detectedSchema: ScriptSchema.unknown,
      summaryOnly: true,
      frameCount: 1,
      frames: [
        RecastExhibitionFrame(
          index: 1,
          fileName: '001.png',
          sourcePath: image.path,
        ),
      ],
    );
    final refreshedSummary = RecastExhibitionScript(
      scriptId: 'summary-script',
      scriptName: 'Fresh summary',
      sourceRootPath: tempDir.path,
      updatedAt: DateTime.parse('2026-06-05T10:00:00Z'),
      detectedSchema: ScriptSchema.unknown,
      summaryOnly: true,
      frameCount: 1,
      frames: [
        RecastExhibitionFrame(
          index: 1,
          fileName: '001.png',
          sourcePath: image.path,
        ),
      ],
    );
    final staleDetail = RecastExhibitionScript(
      scriptId: 'summary-script',
      scriptName: 'Stale detail',
      sourceRootPath: tempDir.path,
      updatedAt: DateTime.parse('2026-06-04T10:00:00Z'),
      detectedSchema: ScriptSchema.baseInline,
      frames: [
        RecastExhibitionFrame(
          index: 1,
          fileName: '001.png',
          sourcePath: image.path,
          prompt: 'stale prompt',
        ),
      ],
    );
    final stalePendingDetail = Completer<RecastExhibitionScript?>();
    final currentPendingDetail = Completer<RecastExhibitionScript?>();
    var recastLoadCount = 0;
    var detailLoadCount = 0;
    final viewModel = ScriptExhibitionRoomViewModel(
      loadRecastScripts: () async {
        recastLoadCount += 1;
        return recastLoadCount == 1 ? [initialSummary] : [refreshedSummary];
      },
      loadRecastScript: (_) {
        detailLoadCount += 1;
        return detailLoadCount == 1
            ? stalePendingDetail.future
            : currentPendingDetail.future;
      },
      loadScripts: () async => const [],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();
    viewModel.selectScript('summary-script');
    await pumpEventQueue();

    await viewModel.load();
    expect(detailLoadCount, 2);
    expect(viewModel.snapshot.scripts.single.title, 'Fresh summary');

    stalePendingDetail.complete(staleDetail);
    await pumpEventQueue();

    expect(viewModel.snapshot.scripts.single.title, 'Fresh summary');
    expect(viewModel.snapshot.scripts.single.summaryOnly, isTrue);

    currentPendingDetail.complete(null);
    await pumpEventQueue();
  });

  test(
      'restarts selected summary detail when an older generation request is still pending',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-exhibition-detail-generation-retry-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final firstImage = File(
      '${tempDir.path}${Platform.pathSeparator}001.png',
    );
    final secondImage = File(
      '${tempDir.path}${Platform.pathSeparator}002.png',
    );
    await firstImage.writeAsBytes(const [0, 1, 2, 3]);
    await secondImage.writeAsBytes(const [0, 1, 2, 3]);

    RecastExhibitionScript summary(String id) => RecastExhibitionScript(
          scriptId: id,
          scriptName: 'Summary $id',
          sourceRootPath: '${tempDir.path}${Platform.pathSeparator}summary-$id',
          updatedAt: DateTime.parse('2026-07-13T09:00:00Z'),
          detectedSchema: ScriptSchema.unknown,
          frames: [
            RecastExhibitionFrame(
              index: 1,
              fileName: '001.png',
              sourcePath: firstImage.path,
            ),
          ],
          frameCount: 2,
          summaryOnly: true,
        );
    RecastExhibitionScript detail(String id) => RecastExhibitionScript(
          scriptId: id,
          scriptName: 'Detail $id',
          sourceRootPath: '${tempDir.path}${Platform.pathSeparator}summary-$id',
          updatedAt: DateTime.parse('2026-07-13T09:00:00Z'),
          detectedSchema: ScriptSchema.baseInline,
          frames: [
            RecastExhibitionFrame(
              index: 1,
              fileName: '001.png',
              sourcePath: firstImage.path,
              prompt: '$id first prompt',
            ),
            RecastExhibitionFrame(
              index: 2,
              fileName: '002.png',
              sourcePath: secondImage.path,
              prompt: '$id second prompt',
            ),
          ],
        );

    final oldScriptADetail = Completer<RecastExhibitionScript?>();
    var scriptADetailLoadCount = 0;
    final viewModel = ScriptExhibitionRoomViewModel(
      loadRecastScripts: () async => [summary('script-a'), summary('script-b')],
      loadRecastScript: (scriptId) {
        if (scriptId == 'script-a') {
          scriptADetailLoadCount += 1;
          if (scriptADetailLoadCount == 1) {
            return oldScriptADetail.future;
          }
        }
        return Future.value(detail(scriptId));
      },
      loadScripts: () async => const [],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();
    viewModel.selectScript('script-a');
    await pumpEventQueue();

    await viewModel.load();
    expect(scriptADetailLoadCount, 2);
    viewModel.selectScript('script-b');
    await pumpEventQueue();
    viewModel.selectScript('script-a');
    await pumpEventQueue();

    oldScriptADetail.complete(detail('script-a'));
    await pumpEventQueue();

    expect(scriptADetailLoadCount, 2);
    expect(viewModel.selectedScript?.scriptId, 'script-a');
    expect(viewModel.selectedScript?.summaryOnly, isFalse);
    expect(viewModel.selectedScript?.versions.single.items, hasLength(2));
  });

  test('does not publish an older detail snapshot after a newer script switch',
      () async {
    final updatedAt = DateTime.parse('2026-07-13T09:00:00Z');
    RecastExhibitionScript recastScript(
      String id, {
      required bool summaryOnly,
    }) {
      return RecastExhibitionScript(
        scriptId: id,
        scriptName: id,
        sourceRootPath: 'root-$id',
        updatedAt: updatedAt,
        detectedSchema:
            summaryOnly ? ScriptSchema.unknown : ScriptSchema.baseInline,
        frames: [
          RecastExhibitionFrame(
            index: 1,
            fileName: '001.png',
            sourcePath: 'root-$id/001.png',
            prompt: summaryOnly ? '' : '$id detail prompt',
          ),
        ],
        frameCount: 1,
        summaryOnly: summaryOnly,
      );
    }

    ScriptExhibitionSnapshot snapshotFor(
      List<RecastExhibitionScript> recastScripts,
    ) {
      return ScriptExhibitionSnapshot(
        scripts: [
          for (final script in recastScripts)
            ScriptExhibitionScript(
              scriptId: script.scriptId,
              title: script.scriptName,
              sourceFolder: script.sourceRootPath,
              updatedAt: script.updatedAt,
              versions: const [],
              status: ScriptExhibitionScriptStatus.active,
              originalCount: script.displayFrameCount,
              generatedImageCount: 0,
              imageLikeItemCount: script.displayFrameCount,
              hasImage: true,
              coverItem: null,
              pendingCount: 0,
              firstNeedsActionItem: null,
              summaryOnly: script.summaryOnly,
            ),
        ],
        totalImageCount: recastScripts.length,
        generatedImageCount: 0,
        needsActionCount: 0,
      );
    }

    final summaryA = recastScript('script-a', summaryOnly: true);
    final summaryB = recastScript('script-b', summaryOnly: true);
    final detailA = recastScript('script-a', summaryOnly: false);
    final detailB = recastScript('script-b', summaryOnly: false);
    final olderBuild = Completer<ScriptExhibitionSnapshot>();
    final newerBuild = Completer<ScriptExhibitionSnapshot>();
    late ScriptExhibitionSnapshot olderSnapshot;
    late ScriptExhibitionSnapshot newerSnapshot;
    var scriptBDetailLoadCount = 0;
    final viewModel = ScriptExhibitionRoomViewModel(
      loadRecastScripts: () async => [summaryA, summaryB],
      loadRecastScript: (scriptId) {
        if (scriptId == 'script-b') {
          scriptBDetailLoadCount += 1;
          return Future.value(detailB);
        }
        return Future.value(detailA);
      },
      snapshotBuilder: ({
        required recastScripts,
        required scripts,
        required plans,
        required records,
      }) {
        final scriptA = recastScripts.singleWhere(
          (script) => script.scriptId == 'script-a',
        );
        final scriptB = recastScripts.singleWhere(
          (script) => script.scriptId == 'script-b',
        );
        final snapshot = snapshotFor(recastScripts);
        if (scriptA.summaryOnly && scriptB.summaryOnly) {
          return Future.value(snapshot);
        }
        if (!scriptA.summaryOnly && scriptB.summaryOnly) {
          olderSnapshot = snapshot;
          return olderBuild.future;
        }
        newerSnapshot = snapshot;
        return newerBuild.future;
      },
      loadScripts: () async => const [],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();
    viewModel.selectScript('script-a');
    await pumpEventQueue();
    viewModel.selectScript('script-b');
    await pumpEventQueue();

    newerBuild.complete(newerSnapshot);
    await pumpEventQueue();
    expect(viewModel.selectedScript?.scriptId, 'script-b');
    expect(viewModel.selectedScript?.summaryOnly, isFalse);

    olderBuild.complete(olderSnapshot);
    await pumpEventQueue();

    expect(scriptBDetailLoadCount, 1);
    expect(viewModel.selectedScript?.scriptId, 'script-b');
    expect(viewModel.selectedScript?.summaryOnly, isFalse);
  });

  test('hides summary-only recast scripts when original images are missing',
      () async {
    final summary = RecastExhibitionScript(
      scriptId: 'missing-original-summary',
      scriptName: 'Missing Original Summary',
      sourceRootPath: r'C:\stories\missing-original',
      updatedAt: DateTime.parse('2026-06-04T10:00:00Z'),
      detectedSchema: ScriptSchema.unknown,
      summaryOnly: true,
      frameCount: 84,
      frames: const [
        RecastExhibitionFrame(
          index: 1,
          fileName: 'p00.png',
          sourcePath: r'C:\stories\missing-original\p00.png',
          sourceImagePath: r'C:\stories\missing-original\p00.png',
        ),
      ],
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadRecastScripts: () async => [summary],
      loadScripts: () async => const [],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    expect(viewModel.snapshot.scripts, isEmpty);
  });

  test('uses paired sidecar images for recast cache frames', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-exhibition-sidecar-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final jsonFile = File('${tempDir.path}${Platform.pathSeparator}001.json');
    final imageFile = File('${tempDir.path}${Platform.pathSeparator}001.png');
    await jsonFile.writeAsString('{}');
    await imageFile.writeAsBytes(const [0, 1, 2, 3]);
    final script = Script(
      id: 'sidecar-script',
      name: 'Sidecar Script',
      rootPath: tempDir.path,
      detectedSchema: ScriptSchema.baseInline,
      frames: [
        ScriptFrame(
          index: 1,
          fileName: '001.json',
          sourcePath: jsonFile.path,
          rawJson: '{}',
          parsed: const ParsedFrame(baseCaption: 'sidecar prompt'),
          detectedSchema: ScriptSchema.baseInline,
          parseStatus: ScriptFrameParseStatus.parsed,
        ),
      ],
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadRecastCaches: () async => [
        RecastScriptCache(
          scriptId: 'sidecar-script',
          scriptName: 'Sidecar Script',
          sourceRootPath: tempDir.path,
          sourceFingerprint: 'fingerprint',
          updatedAt: DateTime.parse('2026-06-04T10:00:00Z'),
          mapping: RecastMapping.defaults('sidecar-script'),
          scriptSnapshot: script.toJson(),
        ),
      ],
      loadScripts: () async => const [],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final item = viewModel.snapshot.scripts.single.versions.single.items.single;
    expect(item.imagePath, imageFile.path);
    expect(item.prompt, 'sidecar prompt');
  });

  test('falls back to root image index only when direct sidecar is missing',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-exhibition-indexed-sidecar-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final jsonFile = File('${tempDir.path}${Platform.pathSeparator}001.json');
    final nestedDir = Directory('${tempDir.path}${Platform.pathSeparator}img');
    await nestedDir.create();
    final imageFile = File('${nestedDir.path}${Platform.pathSeparator}001.png');
    await jsonFile.writeAsString('{}');
    await imageFile.writeAsBytes(const [0, 1, 2, 3]);
    final script = Script(
      id: 'indexed-sidecar-script',
      name: 'Indexed Sidecar Script',
      rootPath: tempDir.path,
      detectedSchema: ScriptSchema.baseInline,
      frames: [
        ScriptFrame(
          index: 1,
          fileName: '001.json',
          sourcePath: jsonFile.path,
          rawJson: '{}',
          parsed: const ParsedFrame(baseCaption: 'indexed sidecar prompt'),
          detectedSchema: ScriptSchema.baseInline,
          parseStatus: ScriptFrameParseStatus.parsed,
        ),
      ],
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadRecastCaches: () async => [
        RecastScriptCache(
          scriptId: 'indexed-sidecar-script',
          scriptName: 'Indexed Sidecar Script',
          sourceRootPath: tempDir.path,
          sourceFingerprint: 'fingerprint',
          updatedAt: DateTime.parse('2026-06-04T10:00:00Z'),
          mapping: RecastMapping.defaults('indexed-sidecar-script'),
          scriptSnapshot: script.toJson(),
        ),
      ],
      loadScripts: () async => const [],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final item = viewModel.snapshot.scripts.single.versions.single.items.single;
    expect(item.imagePath, imageFile.path);
    expect(item.prompt, 'indexed sidecar prompt');
  });

  test('cleans source folder images that are not in the exhibition', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-exhibition-source-cleanup-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final nestedDir = Directory('${tempDir.path}${Platform.pathSeparator}img');
    await nestedDir.create();
    final sourceJson = File('${tempDir.path}${Platform.pathSeparator}001.json');
    final sourceImage = File('${tempDir.path}${Platform.pathSeparator}001.png');
    final attachmentImage =
        File('${tempDir.path}${Platform.pathSeparator}manual.png');
    final extraImage =
        File('${tempDir.path}${Platform.pathSeparator}extra.jpg');
    final nestedExtraImage =
        File('${nestedDir.path}${Platform.pathSeparator}extra.webp');
    final noteFile = File('${tempDir.path}${Platform.pathSeparator}note.txt');
    await sourceJson.writeAsString('{}');
    await sourceImage.writeAsBytes(const [0, 1, 2, 3]);
    await attachmentImage.writeAsBytes(const [4, 5, 6, 7]);
    await extraImage.writeAsBytes(const [8, 9, 10, 11]);
    await nestedExtraImage.writeAsBytes(const [12, 13, 14, 15]);
    await noteFile.writeAsString('keep me');

    final source = _source(
      'source-cleanup-1',
      '001.json',
      sourceJson.path,
      defaultImagePath: sourceImage.path,
    );
    final script = _script().copyWith(
      sourceFolder: tempDir.path,
      sourceFiles: [source],
      imageTasks: [
        _task(
          id: 'task-cleanup-1',
          source: source,
          prompt: 'source prompt',
          status: TokenizerTaskReviewStatus.confirmed,
        ),
      ],
      imageAttachments: [
        TokenizerScriptImageAttachment(
          attachmentId: 'attachment-cleanup-1',
          imagePath: attachmentImage.path,
          label: 'Manual version',
          versionId: 'script-image-version-cleanup',
          versionLabel: 'Manual',
          frameIndex: 1,
          sourceFileName: '001.json',
          prompt: 'manual prompt',
          createdAt: DateTime.parse('2026-06-10T10:00:00Z'),
        ),
      ],
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [script],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final preview = await viewModel.previewSourceFolderCleanup(
      viewModel.snapshot.scripts.single,
    );

    expect(preview.sourceFolderExists, isTrue);
    expect(preview.retainedImagePaths.toSet(), {
      sourceImage.path,
      attachmentImage.path,
    });
    expect(preview.removableImagePaths.toSet(), {
      extraImage.path,
      nestedExtraImage.path,
    });

    final result = await viewModel.cleanSourceFolderImages(
      viewModel.snapshot.scripts.single,
      preview: preview,
    );

    expect(result.deletedImagePaths.toSet(), {
      extraImage.path,
      nestedExtraImage.path,
    });
    expect(await sourceImage.exists(), isTrue);
    expect(await attachmentImage.exists(), isTrue);
    expect(await extraImage.exists(), isFalse);
    expect(await nestedExtraImage.exists(), isFalse);
    expect(await sourceJson.exists(), isTrue);
    expect(await noteFile.exists(), isTrue);
  });

  test('loads legacy image attachments from recast script caches', () async {
    final attachmentCreatedAt = DateTime.parse('2026-06-04T11:00:00Z');
    final script = Script(
      id: 'recast-script',
      name: 'Recast Script',
      rootPath: r'C:\stories\recast',
      detectedSchema: ScriptSchema.baseInline,
      frames: [
        ScriptFrame(
          index: 1,
          fileName: '001.json',
          sourcePath: r'C:\stories\recast\001.json',
          sourceImagePath: r'C:\stories\recast\001.png',
          rawJson: '{}',
          parsed: const ParsedFrame(baseCaption: 'source prompt'),
          detectedSchema: ScriptSchema.baseInline,
          parseStatus: ScriptFrameParseStatus.parsed,
        ),
      ],
      meta: {
        'legacyImageAttachments': [
          TokenizerScriptImageAttachment(
            attachmentId: 'attachment-1',
            imagePath: r'C:\stories\recast\alt-001.png',
            label: 'Alt frame',
            versionId: 'script-image-version-1',
            versionLabel: 'Imported Image 1',
            frameIndex: 1,
            sourceFileName: '001.json',
            prompt: 'attachment prompt',
            createdAt: attachmentCreatedAt,
          ).toJson(),
        ],
      },
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadRecastCaches: () async => [
        RecastScriptCache(
          scriptId: 'recast-script',
          scriptName: 'Recast Script',
          sourceRootPath: r'C:\stories\recast',
          sourceFingerprint: 'fingerprint',
          updatedAt: DateTime.parse('2026-06-04T10:00:00Z'),
          mapping: RecastMapping.defaults('recast-script'),
          scriptSnapshot: script.toJson(),
        ),
      ],
      loadScripts: () async => const [],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final exhibitionScript = viewModel.snapshot.scripts.single;
    final attachmentVersion = exhibitionScript.versions.singleWhere(
      (version) => version.id == 'script-image-version-1',
    );
    final item = attachmentVersion.items.single;
    expect(item.sourceKind, ScriptExhibitionItemSourceKind.attachment);
    expect(item.imageAttachmentId, 'attachment-1');
    expect(item.imagePath, r'C:\stories\recast\alt-001.png');
    expect(item.prompt, 'attachment prompt');
    expect(item.versionLabel, 'Imported Image 1');
  });

  test('uses lightweight recast exhibition scripts before full caches',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-exhibition-lightweight-cache-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final image = File('${tempDir.path}${Platform.pathSeparator}001.png');
    await image.writeAsBytes(const [0, 1, 2, 3]);
    var fullCacheLoadCount = 0;
    final viewModel = ScriptExhibitionRoomViewModel(
      loadRecastScripts: () async => [
        RecastExhibitionScript(
          scriptId: 'light-script',
          scriptName: 'Light Script',
          sourceRootPath: tempDir.path,
          updatedAt: DateTime.parse('2026-06-04T10:00:00Z'),
          detectedSchema: ScriptSchema.baseInline,
          frames: [
            RecastExhibitionFrame(
              index: 1,
              fileName: '001.json',
              sourcePath: '${tempDir.path}${Platform.pathSeparator}001.json',
              sourceImagePath: image.path,
              prompt: 'light prompt',
              parseStatus: ScriptFrameParseStatus.parsed,
            ),
          ],
        ),
      ],
      loadRecastCaches: () async {
        fullCacheLoadCount += 1;
        return const [];
      },
      loadScripts: () async => const [],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    expect(fullCacheLoadCount, 0);
    final exhibitionScript = viewModel.snapshot.scripts.single;
    expect(exhibitionScript.scriptId, 'light-script');
    final item = exhibitionScript.versions.single.items.single;
    expect(item.sourceKind, ScriptExhibitionItemSourceKind.original);
    expect(item.sourceFileName, '001.json');
    expect(item.imagePath, image.path);
    expect(item.prompt, 'light prompt');
  });

  test('aggregates scripts, production batches, and gallery records', () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => [
        _galleryRecord(
          taskId: 'task-archived-only',
          imagePath: r'C:\gallery\frame-archived-only.png',
        ),
      ],
    );

    await viewModel.load();

    final snapshot = viewModel.snapshot;
    expect(snapshot.scripts, hasLength(1));
    expect(snapshot.totalScriptCount, 1);
    expect(snapshot.totalImageCount, 4);
    expect(snapshot.generatedImageCount, 2);
    expect(snapshot.needsActionCount, 1);

    final script = snapshot.scripts.single;
    expect(script.scriptId, 'script-1');
    expect(script.title, '雨夜档案');
    expect(script.sourceFolder, r'C:\stories\rain');
    expect(script.versions.map((version) => version.label), [
      '原始剧本',
      '主角版 A',
      '已收纳',
    ]);

    final original = script.versions[0];
    expect(original.items.map((item) => item.frameIndex), [1, 2]);
    expect(original.items.first.sourceKind,
        ScriptExhibitionItemSourceKind.original);

    final batch = script.versions[1];
    expect(batch.items.map((item) => item.title), [
      '新图: 入口雨幕',
      '旧书架前',
    ]);
    expect(batch.items.first.imagePath, r'C:\out\frame-01.png');
    expect(batch.items.first.versionLabel, '主角版 A');
    expect(batch.items.last.sourceKind, ScriptExhibitionItemSourceKind.failed);

    final archived = script.versions[2];
    expect(archived.items.single.sourceKind,
        ScriptExhibitionItemSourceKind.gallery);
    expect(archived.items.single.frameIndex, 1);
  });

  test('chooses a generated image as the script cover before originals',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final cover = viewModel.snapshot.scripts.single.coverItem;
    expect(cover, isNotNull);
    expect(cover!.sourceKind, ScriptExhibitionItemSourceKind.generated);
    expect(cover.imagePath, r'C:\out\frame-01.png');
  });

  test('uses a saved exhibition cover item before automatic cover ranking',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        _script().copyWith(
          exhibitionCoverItemId: 'original-script-1-task-2',
        ),
      ],
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final script = viewModel.snapshot.scripts.single;
    expect(script.coverItemId, 'original-script-1-task-2');
    final cover = script.coverItem;
    expect(cover, isNotNull);
    expect(cover!.id, 'original-script-1-task-2');
    expect(cover.sourceKind, ScriptExhibitionItemSourceKind.original);
    expect(cover.imagePath, r'C:\stories\rain\002.png');
  });

  test('sets a script cover item through the persistence callback', () async {
    var scripts = [_script()];
    final persistedItems = <ScriptExhibitionItem>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => const [],
      setCoverItemRecord: (item) async {
        persistedItems.add(item);
        scripts = [
          for (final script in scripts)
            script.scriptId == item.scriptId
                ? script.copyWith(exhibitionCoverItemId: item.id)
                : script,
        ];
      },
    );

    await viewModel.load();
    final item = viewModel.snapshot.scripts.single.versions
        .singleWhere((version) => version.id == 'production-plan-hero-a')
        .items
        .first;

    await viewModel.setCoverItem(item);

    expect(persistedItems.single.id, 'production-plan-hero-a-task-generated-1');
    expect(viewModel.snapshot.scripts.single.coverItem?.id,
        'production-plan-hero-a-task-generated-1');
    expect(
      viewModel.focusedItemId,
      'production-plan-hero-a-task-generated-1',
    );
  });

  test('falls back to an original image when a script has no generated cover',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final cover = viewModel.snapshot.scripts.single.coverItem;
    expect(cover, isNotNull);
    expect(cover!.sourceKind, ScriptExhibitionItemSourceKind.original);
    expect(cover.imagePath, r'C:\stories\rain\001.png');
  });

  test('skips gallery records already represented by production tasks',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => [_galleryRecord()],
    );

    await viewModel.load();

    final snapshot = viewModel.snapshot;
    final script = snapshot.scripts.single;
    expect(snapshot.totalImageCount, 3);
    expect(snapshot.generatedImageCount, 1);
    final productionItem = script.versions
        .singleWhere((version) => version.id == 'production-plan-hero-a')
        .items
        .first;
    expect(productionItem.galleryRecord?.id, 'gallery-1');
    expect(productionItem.galleryRecordId, isNull);
    expect(
      script.versions
          .any((version) => version.id == ScriptExhibitionVersion.galleryId),
      isFalse,
    );
  });

  test('strips heavy production reference images from exhibition snapshot',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [
        _plan(
          generatedPayload: {
            'input': 'library entrance, new heroine',
            'parameters': {
              'reference_image_multiple': [
                List.filled(50000, 'x').join(),
              ],
              'reference_strength_multiple': [0.45],
              'v4_prompt': {
                'caption': {
                  'base_caption': 'library entrance',
                  'char_captions': [
                    {'char_caption': 'new heroine'},
                  ],
                },
              },
              'v4_negative_prompt': {
                'caption': {
                  'base_caption': 'low quality',
                },
              },
              'prompt': 'legacy prompt',
              'uc': 'legacy negative',
            },
          },
        ),
      ],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final productionItem = viewModel.snapshot.scripts.single.versions
        .singleWhere((version) => version.id == 'production-plan-hero-a')
        .items
        .first;
    final payload = productionItem.assetCapturePayload;
    final parameters = payload?['parameters'] as Map<String, dynamic>?;

    expect(productionItem.prompt, contains('library entrance'));
    expect(parameters, isNotNull);
    expect(parameters, isNot(contains('reference_image_multiple')));
    expect(parameters, isNot(contains('reference_strength_multiple')));
    expect(parameters, contains('v4_prompt'));
    expect(parameters, contains('v4_negative_prompt'));
    expect(parameters, contains('prompt'));
    expect(parameters, contains('uc'));
  });

  test('applies custom exhibition version labels', () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        _script().copyWith(
          exhibitionVersionLabels: const {
            ScriptExhibitionVersion.galleryId: '精选收纳',
          },
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => [
        _galleryRecord(
          taskId: 'task-archived-only',
          imagePath: r'C:\gallery\frame-archived-only.png',
        ),
      ],
    );

    await viewModel.load();

    final galleryVersion = viewModel.snapshot.scripts.single.versions
        .singleWhere(
            (version) => version.id == ScriptExhibitionVersion.galleryId);
    expect(galleryVersion.label, '精选收纳');
    expect(galleryVersion.items.single.versionLabel, '精选收纳');
  });

  test(
      'renaming a dynamic version keeps the selected version and all items visible',
      () async {
    final summary = RecastExhibitionScript(
      scriptId: 'script-1',
      scriptName: 'Rain Archive',
      sourceRootPath: r'C:\stories\rain',
      updatedAt: DateTime.parse('2026-06-01T09:00:00Z'),
      detectedSchema: ScriptSchema.unknown,
      summaryOnly: true,
      frameCount: 2,
      frames: const [
        RecastExhibitionFrame(
          index: 1,
          fileName: '001.json',
          sourcePath: r'C:\stories\rain\001.json',
          sourceImagePath: r'C:\stories\rain\001.png',
        ),
      ],
    );
    var productionLoadCount = 0;
    final productionReload = Completer<List<ProductionPlan>>();
    final renamedVersions = <String, String>{};
    final viewModel = ScriptExhibitionRoomViewModel(
      loadRecastScripts: () async => [summary],
      loadScripts: () async => const [],
      loadProductionPlans: () {
        productionLoadCount += 1;
        if (productionLoadCount == 1) {
          return Future.value([_plan()]);
        }
        return productionReload.future;
      },
      loadGalleryRecords: () async => const [],
      renameVersionLabel: (script, version, label) async {
        renamedVersions[version.id] = label;
      },
    );

    await viewModel.load();
    viewModel.selectScript('script-1');
    viewModel.selectVersion('production-plan-hero-a');
    final script = viewModel.selectedScript!;
    final version = viewModel.selectedVersion!;

    final renameFuture = viewModel.renameVersionLabel(
      script,
      version,
      'Hero v2',
    );
    await pumpEventQueue();

    expect(renamedVersions, {'production-plan-hero-a': 'Hero v2'});
    expect(viewModel.selectedVersion?.id, 'production-plan-hero-a');
    expect(viewModel.selectedVersion?.label, 'Hero v2');
    expect(viewModel.visibleVersionItems, hasLength(2));

    productionReload.complete([_plan()]);
    await renameFuture;
  });

  test('keeps exhibition usable when gallery records fail to load', () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => throw const FormatException(
        'broken gallery index',
      ),
    );

    await viewModel.load();

    expect(viewModel.loadError, isNull);
    final script = viewModel.snapshot.scripts.single;
    expect(script.scriptId, 'script-1');
    expect(script.generatedImageCount, 1);
    expect(
      script.versions
          .any((version) => version.id == ScriptExhibitionVersion.galleryId),
      isFalse,
    );
  });

  test(
      'keeps gallery records when a reused plan task belongs to another script',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [
        _plan(
          scriptId: 'script-other',
          scriptName: 'Other Script',
          scriptPath: r'C:\stories\other',
        ),
      ],
      loadGalleryRecords: () async => [_galleryRecord()],
    );

    await viewModel.load();

    final originalScript = viewModel.snapshot.scripts
        .singleWhere((script) => script.scriptId == 'script-1');
    expect(originalScript.generatedImageCount, 1);
    expect(
      originalScript.versions
          .any((version) => version.id == ScriptExhibitionVersion.galleryId),
      isTrue,
    );

    final currentPlanScript = viewModel.snapshot.scripts
        .singleWhere((script) => script.scriptId == 'script-other');
    expect(currentPlanScript.generatedImageCount, 1);
  });

  test('creates a synthetic script bucket for production-only results',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => const [],
      loadProductionPlans: () async => [_plan(scriptId: 'script-missing')],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final script = viewModel.snapshot.scripts.single;
    expect(script.scriptId, 'script-missing');
    expect(script.title, '雨夜档案');
    expect(script.versions.single.label, '主角版 A');
    expect(script.generatedImageCount, 1);
  });

  test('joins production results by source path when script ids differ',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_plan(scriptId: 'script-regenerated')],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final snapshot = viewModel.snapshot;
    expect(snapshot.scripts, hasLength(1));
    final script = snapshot.scripts.single;
    expect(script.scriptId, 'script-1');
    expect(script.sourceFolder, r'C:\stories\rain');
    expect(script.versions.map((version) => version.label), [
      '原始剧本',
      '主角版 A',
    ]);
    expect(script.originalCount, 2);
    expect(script.generatedImageCount, 1);
  });

  test('joins production results by unique title and source frame evidence',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [
        _plan(
          scriptId: 'script-regenerated',
          scriptPath: r'C:\generated\cover-run',
        ),
      ],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final snapshot = viewModel.snapshot;
    expect(snapshot.scripts, hasLength(1));
    final script = snapshot.scripts.single;
    expect(script.scriptId, 'script-1');
    expect(script.sourceFolder, r'C:\stories\rain');
    expect(script.originalCount, 2);
    expect(script.generatedImageCount, 1);
    expect(script.versions.map((version) => version.id), [
      ScriptExhibitionVersion.originalId,
      'production-plan-hero-a',
    ]);
  });

  test('does not join same-title production results without frame evidence',
      () async {
    final now = DateTime.parse('2026-06-02T08:00:00Z');
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [
        ProductionPlan(
          id: 'plan-manual',
          name: 'Manual run',
          createdAt: now,
          updatedAt: now,
          tasks: [
            ProductionTask(
              id: 'task-manual',
              planId: 'plan-manual',
              taskType: ProductionTaskType.manualSingleFrame,
              title: 'Manual image',
              source: ProductionTaskSource(
                scriptId: 'script-other',
                scriptName: _script().name,
                scriptPath: r'C:\generated\manual-run',
              ),
              payload: const {'input': 'manual output'},
              status: ProductionTaskStatus.completed,
              outputImagePath: r'C:\out\manual.png',
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      ],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    expect(viewModel.snapshot.scripts, hasLength(2));
  });

  test('hides source-only scripts without image paths from exhibition',
      () async {
    final now = DateTime.parse('2026-06-01T09:00:00Z');
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        TokenizerScript(
          scriptId: 'script-source-only',
          name: '源文件剧本',
          sourceFolder: r'C:\stories\source-only',
          sourceMode: TokenizerScriptSourceMode.auto,
          createdAt: now,
          updatedAt: now,
          status: TokenizerScriptStatus.parsed,
          sourceFiles: [
            _source(
              'source-only-1',
              '001.json',
              r'C:\stories\source-only\001.json',
            ),
          ],
          sampleFileIds: const ['source-only-1'],
          characterIdentities: const [],
          styleStages: const [],
          knowledgeCandidates: const [],
          imageTasks: const [],
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    expect(viewModel.snapshot.scripts, isEmpty);
    expect(viewModel.snapshot.totalScriptCount, 0);
    expect(viewModel.snapshot.totalImageCount, 0);
  });

  test('uses paired sidecar images for tokenizer source files', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-exhibition-tokenizer-sidecar-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final jsonFile = File('${tempDir.path}${Platform.pathSeparator}001.json');
    final imageFile = File('${tempDir.path}${Platform.pathSeparator}001.png');
    await jsonFile.writeAsString('{}');
    await imageFile.writeAsBytes(const [0, 1, 2, 3]);
    final now = DateTime.parse('2026-06-01T09:00:00Z');
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        TokenizerScript(
          scriptId: 'tokenizer-sidecar',
          name: 'Tokenizer Sidecar',
          sourceFolder: tempDir.path,
          sourceMode: TokenizerScriptSourceMode.auto,
          createdAt: now,
          updatedAt: now,
          status: TokenizerScriptStatus.parsed,
          sourceFiles: [
            _source('source-sidecar', '001.json', jsonFile.path),
          ],
          sampleFileIds: const ['source-sidecar'],
          characterIdentities: const [],
          styleStages: const [],
          knowledgeCandidates: const [],
          imageTasks: const [],
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final item = viewModel.snapshot.scripts.single.versions.single.items.single;
    expect(item.imagePath, imageFile.path);
    expect(item.sourceFileName, '001.json');
  });

  test('uses paired source images as original exhibition images', () async {
    final now = DateTime.parse('2026-06-01T09:00:00Z');
    final source = _source(
      'source-paired-1',
      'p000.json',
      r'C:\stories\paired\p000.json',
      defaultImagePath: r'C:\stories\paired\p000.png',
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        TokenizerScript(
          scriptId: 'script-paired',
          name: '配图剧本',
          sourceFolder: r'C:\stories\paired',
          sourceMode: TokenizerScriptSourceMode.auto,
          createdAt: now,
          updatedAt: now,
          status: TokenizerScriptStatus.ready,
          sourceFiles: [source],
          sampleFileIds: const ['source-paired-1'],
          characterIdentities: const [],
          styleStages: const [],
          knowledgeCandidates: const [],
          imageTasks: [
            _task(
              id: 'task-paired-1',
              source: source,
              prompt: 'paired json prompt',
              status: TokenizerTaskReviewStatus.confirmed,
            ),
          ],
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final item = viewModel.snapshot.scripts.single.versions.single.items.single;
    expect(item.sourceFileName, 'p000.json');
    expect(item.imagePath, r'C:\stories\paired\p000.png');
  });

  test('labels image-only imported scripts as the default version', () async {
    final now = DateTime.parse('2026-06-01T09:00:00Z');
    final source = _source(
      'source-image-only-1',
      'p000.png',
      r'C:\stories\image-only\p000.png',
      kind: TokenizerScriptSourceKind.image,
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        TokenizerScript(
          scriptId: 'script-image-only',
          name: 'Image Only',
          sourceFolder: r'C:\stories\image-only',
          sourceMode: TokenizerScriptSourceMode.auto,
          createdAt: now,
          updatedAt: now,
          status: TokenizerScriptStatus.ready,
          sourceFiles: [source],
          sampleFileIds: const ['source-image-only-1'],
          characterIdentities: const [],
          styleStages: const [],
          knowledgeCandidates: const [],
          imageTasks: [
            _task(
              id: 'task-image-only-1',
              source: source,
              prompt: 'image metadata prompt',
              status: TokenizerTaskReviewStatus.confirmed,
            ),
          ],
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final version = viewModel.snapshot.scripts.single.versions.single;
    expect(version.id, ScriptExhibitionVersion.originalId);
    expect(version.label, '默认版本');
    expect(version.items.single.versionLabel, '默认版本');
    expect(version.items.single.imagePath, r'C:\stories\image-only\p000.png');
  });

  test('original exhibition items prefer original prompt over final prompt',
      () async {
    final now = DateTime.parse('2026-06-01T09:00:00Z');
    final source = _source(
      'source-original-prompt-1',
      'p000.json',
      r'C:\stories\paired\p000.json',
      defaultImagePath: r'C:\stories\paired\p000.png',
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        TokenizerScript(
          scriptId: 'script-original-prompt',
          name: 'Original Prompt',
          sourceFolder: r'C:\stories\paired',
          sourceMode: TokenizerScriptSourceMode.auto,
          createdAt: now,
          updatedAt: now,
          status: TokenizerScriptStatus.ready,
          sourceFiles: [source],
          sampleFileIds: const ['source-original-prompt-1'],
          characterIdentities: const [],
          styleStages: const [],
          knowledgeCandidates: const [],
          imageTasks: [
            _task(
              id: 'task-original-prompt-1',
              source: source,
              prompt: 'artist:ahemaru, year 2025',
              finalPrompt: '[artist-chain], year 2025, [character-lower-body]',
              status: TokenizerTaskReviewStatus.confirmed,
            ),
          ],
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final item = viewModel.snapshot.scripts.single.versions.single.items.single;
    expect(item.prompt, 'artist:ahemaru, year 2025');
    expect(item.prompt, isNot(contains('[artist-chain]')));
  });

  test('ignores legacy unversioned image attachments', () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        _script().copyWith(
          imageAttachments: [
            TokenizerScriptImageAttachment(
              attachmentId: 'attachment-1',
              imagePath: r'C:\stories\rain\manual_001.png',
              label: 'Default 1',
              frameIndex: 1,
              sourceFileName: '001.json',
              createdAt: DateTime.parse('2026-06-03T10:00:00Z'),
            ),
          ],
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    expect(
      viewModel.snapshot.scripts.single.versions.any(
        (version) => version.id == 'attachments',
      ),
      isFalse,
    );
    expect(
      viewModel.snapshot.scripts.single.items.any(
        (item) => item.sourceKind == ScriptExhibitionItemSourceKind.attachment,
      ),
      isFalse,
    );
  });

  test('aggregates imported image sequences as separate JSON-backed versions',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        _script().copyWith(
          imageAttachments: [
            TokenizerScriptImageAttachment(
              attachmentId: 'version-a-1',
              imagePath: r'C:\stories\rain\version_a_p1.png',
              label: 'Frame 1',
              versionId: 'script-image-version-a',
              versionLabel: '导入图片 1',
              frameIndex: 1,
              sourceFileName: '001.json',
              prompt: 'artist:a, imported json prompt 1',
              payload: const {
                'input': 'artist:a, imported json prompt 1',
                'parameters': {'width': 832, 'height': 1216},
              },
              createdAt: DateTime.parse('2026-06-10T10:00:00Z'),
            ),
            TokenizerScriptImageAttachment(
              attachmentId: 'version-a-2',
              imagePath: r'C:\stories\rain\version_a_p2.png',
              label: 'Frame 2',
              versionId: 'script-image-version-a',
              versionLabel: '导入图片 1',
              frameIndex: 2,
              sourceFileName: '002.json',
              prompt: 'artist:b, imported json prompt 2',
              payload: const {
                'input': 'artist:b, imported json prompt 2',
                'parameters': {'steps': 28},
              },
              createdAt: DateTime.parse('2026-06-10T10:00:01Z'),
            ),
          ],
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    final importedVersion = viewModel.snapshot.scripts.single.versions
        .singleWhere((version) => version.id == 'script-image-version-a');

    expect(importedVersion.label, '导入图片 1');
    expect(importedVersion.items.map((item) => item.title), [
      'Frame 1',
      'Frame 2',
    ]);
    expect(importedVersion.items.first.prompt, contains('imported json'));
    expect(importedVersion.items.first.assetCapturePayload?['parameters'], {
      'width': 832,
      'height': 1216,
    });
  });

  test('keeps the newest load result when concurrent loads finish out of order',
      () async {
    final firstCompleter = Completer<List<TokenizerScript>>();
    var requestCount = 0;
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () {
        requestCount += 1;
        if (requestCount == 1) {
          return firstCompleter.future;
        }
        return Future.value([
          _script().copyWith(
            scriptId: 'script-new',
            name: '新剧本',
          ),
        ]);
      },
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    final firstLoad = viewModel.load();
    await viewModel.load();
    firstCompleter.complete([_script()]);
    await firstLoad;

    expect(viewModel.snapshot.scripts.single.scriptId, 'script-new');
  });

  test('finishes loading after base snapshot before production enrichment',
      () async {
    final productionCompleter = Completer<List<ProductionPlan>>();
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () => productionCompleter.future,
      loadGalleryRecords: () async => const [],
    );

    final loadFuture = viewModel.load();
    await pumpEventQueue();

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.snapshot.scripts.single.scriptId, 'script-1');
    expect(
      viewModel.snapshot.scripts.single.items.any(
        (item) => item.sourceKind == ScriptExhibitionItemSourceKind.generated,
      ),
      isFalse,
    );

    productionCompleter.complete([_plan()]);
    await loadFuture;

    expect(viewModel.isLoading, isFalse);
    expect(
      viewModel.snapshot.scripts.single.items.any(
        (item) => item.sourceKind == ScriptExhibitionItemSourceKind.generated,
      ),
      isTrue,
    );
  });

  test('ensureLoaded reuses the loaded snapshot until a forced load', () async {
    var requestCount = 0;
    var scripts = [_script()];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async {
        requestCount += 1;
        return scripts;
      },
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.ensureLoaded();
    await viewModel.ensureLoaded();

    expect(requestCount, 1);
    expect(viewModel.snapshot.scripts.single.scriptId, 'script-1');

    scripts = [
      _script().copyWith(
        scriptId: 'script-2',
        name: 'Second script',
      ),
    ];
    await viewModel.load();

    expect(requestCount, 2);
    expect(viewModel.snapshot.scripts.single.scriptId, 'script-2');
  });

  test('deletes gallery-backed items and reloads the snapshot', () async {
    var records = [_galleryRecord()];
    final deletedItemIds = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => records,
      deleteItemRecord: (item, {bool deleteLocalFiles = false}) async {
        deletedItemIds.add(item.id);
        records = records
            .where((record) => record.id != item.galleryRecordId)
            .toList(growable: false);
      },
    );

    await viewModel.load();
    final galleryVersion = viewModel.snapshot.scripts.single.versions
        .singleWhere(
            (version) => version.id == ScriptExhibitionVersion.galleryId);
    final galleryItem = galleryVersion.items.single;

    expect(galleryItem.canDelete, isTrue);
    await viewModel.deleteItem(galleryItem);

    expect(deletedItemIds, ['gallery-gallery-1']);
    expect(
      viewModel.snapshot.scripts.single.versions
          .any((version) => version.id == ScriptExhibitionVersion.galleryId),
      isFalse,
    );
  });

  test('deleting one gallery item keeps the selected dynamic version',
      () async {
    var records = [
      _galleryRecord(
        id: 'gallery-1',
        taskId: 'archived-task-1',
        imagePath: r'C:\gallery\frame-01.png',
      ),
      _galleryRecord(
        id: 'gallery-2',
        taskId: 'archived-task-2',
        imagePath: r'C:\gallery\frame-02.png',
      ),
    ];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => records,
      deleteItemRecord: (item, {bool deleteLocalFiles = false}) async {
        records = records
            .where((record) => record.id != item.galleryRecordId)
            .toList(growable: false);
      },
    );

    await viewModel.load();
    viewModel.selectScript('script-1');
    viewModel.selectVersion(ScriptExhibitionVersion.galleryId);
    final deletedItem = viewModel.visibleVersionItems.singleWhere(
      (item) => item.galleryRecordId == 'gallery-1',
    );

    await viewModel.deleteItem(deletedItem);

    expect(viewModel.selectedScript?.scriptId, 'script-1');
    expect(viewModel.selectedVersion?.id, ScriptExhibitionVersion.galleryId);
    expect(
      viewModel.visibleVersionItems.map((item) => item.galleryRecordId),
      ['gallery-2'],
    );
  });

  test('deleting one production item keeps the selected production version',
      () async {
    var plans = [_plan()];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => plans,
      loadGalleryRecords: () async => const [],
      deleteItemRecord: (item, {bool deleteLocalFiles = false}) async {
        plans = [
          plans.single.copyWith(
            tasks: plans.single.tasks
                .where((task) => task.id != item.taskId)
                .toList(growable: false),
          ),
        ];
      },
    );

    await viewModel.load();
    viewModel.selectScript('script-1');
    viewModel.selectVersion('production-plan-hero-a');
    final deletedItem = viewModel.visibleVersionItems.singleWhere(
      (item) => item.taskId == 'task-generated-1',
    );

    await viewModel.deleteItem(deletedItem);

    expect(viewModel.selectedScript?.scriptId, 'script-1');
    expect(viewModel.selectedVersion?.id, 'production-plan-hero-a');
    expect(
      viewModel.visibleVersionItems.map((item) => item.taskId),
      ['task-failed-2'],
    );
  });

  test('deleting the last production image leaves the frame pending', () async {
    var plans = [
      _plan().copyWith(
        tasks: [_plan().tasks.first],
      ),
    ];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => plans,
      loadGalleryRecords: () async => const [],
      deleteItemRecord: (item, {bool deleteLocalFiles = false}) async {
        plans = [
          plans.single.copyWith(
            tasks: [
              plans.single.tasks.single.copyWith(
                status: ProductionTaskStatus.queued,
                attempts: 0,
                clearOutputImagePath: true,
                clearError: true,
                clearStartedAt: true,
                clearCompletedAt: true,
              ),
            ],
          ),
        ];
      },
    );

    await viewModel.load();
    viewModel.selectScript('script-1');
    viewModel.selectVersion('production-plan-hero-a');
    final deletedItem = viewModel.visibleVersionItems.single;

    await viewModel.deleteItem(deletedItem);

    expect(viewModel.selectedVersion?.id, 'production-plan-hero-a');
    expect(viewModel.visibleVersionItems, hasLength(1));
    final pendingItem = viewModel.visibleVersionItems.single;
    expect(pendingItem.taskId, deletedItem.taskId);
    expect(pendingItem.sourceKind, ScriptExhibitionItemSourceKind.queued);
    expect(pendingItem.needsAction, isTrue);
  });

  test('refreshDynamicVersions promotes completed batch output without reload',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-exhibition-live-refresh-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final outputFile =
        File('${tempDir.path}${Platform.pathSeparator}frame-01.png');
    await outputFile.writeAsBytes(const [0, 1, 2, 3]);
    final basePlan = _plan();
    final baseTask = basePlan.tasks.first;
    var plans = [
      basePlan.copyWith(
        tasks: [
          baseTask.copyWith(
            status: ProductionTaskStatus.queued,
            clearOutputImagePath: true,
            clearCompletedAt: true,
          ),
        ],
      ),
    ];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => plans,
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();
    viewModel.selectScript('script-1');
    viewModel.selectVersion('production-plan-hero-a');
    final queuedItem = viewModel.visibleVersionItems.single;
    expect(queuedItem.sourceKind, ScriptExhibitionItemSourceKind.queued);
    expect(queuedItem.imagePath, isEmpty);

    plans = [
      basePlan.copyWith(
        tasks: [
          baseTask.copyWith(
            status: ProductionTaskStatus.completed,
            outputImagePath: outputFile.path,
            completedAt: DateTime.parse('2026-06-02T09:00:00Z'),
            updatedAt: DateTime.parse('2026-06-02T09:00:00Z'),
          ),
        ],
      ),
    ];
    await viewModel.refreshDynamicVersions(reloadGalleryRecords: false);

    expect(viewModel.selectedVersion?.id, 'production-plan-hero-a');
    final completedItem = viewModel.visibleVersionItems.single;
    expect(completedItem.taskId, 'task-generated-1');
    expect(completedItem.sourceKind, ScriptExhibitionItemSourceKind.generated);
    expect(completedItem.imagePath, outputFile.path);
    expect(viewModel.selectedScript?.generatedImageCount, 1);
  });

  test('imports renames and deletes script-scoped image attachments', () async {
    var scripts = [_script()];
    final importedScripts = <String>[];
    final renamedLabels = <String>[];
    final deletedAttachmentIds = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      importScriptImages: (script) async {
        importedScripts.add(script.scriptId);
        scripts = [
          scripts.single.copyWith(
            imageAttachments: [
              TokenizerScriptImageAttachment(
                attachmentId: 'attachment-1',
                imagePath: r'C:\stories\rain\manual_001.png',
                label: 'Default 1',
                versionId: 'script-image-version-1',
                versionLabel: '导入图片 1',
                prompt: 'artist:manual, imported json prompt',
                createdAt: DateTime.parse('2026-06-03T10:00:00Z'),
              ),
            ],
          ),
        ];
      },
      renameImageAttachment: (item, label) async {
        renamedLabels.add(label);
        scripts = [
          scripts.single.copyWith(
            imageAttachments: [
              TokenizerScriptImageAttachment(
                attachmentId: item.imageAttachmentId!,
                imagePath: item.imagePath,
                label: label,
                versionId: item.versionId,
                versionLabel: item.versionLabel,
                prompt: item.prompt,
                createdAt: item.updatedAt,
              ),
            ],
          ),
        ];
      },
      deleteItemRecord: (item, {bool deleteLocalFiles = false}) async {
        deletedAttachmentIds.add(item.imageAttachmentId!);
        scripts = [scripts.single.copyWith(imageAttachments: const [])];
      },
    );

    await viewModel.load();
    await viewModel.importImagesForScript(viewModel.snapshot.scripts.single);
    var attachmentItem = viewModel.snapshot.scripts.single.versions
        .singleWhere((version) => version.id == 'script-image-version-1')
        .items
        .single;
    expect(importedScripts, ['script-1']);
    expect(viewModel.selectedScript?.scriptId, 'script-1');
    expect(viewModel.selectedVersion?.id, 'script-image-version-1');
    expect(viewModel.selectedVersion?.label, '导入图片 1');
    expect(attachmentItem.prompt, 'artist:manual, imported json prompt');
    expect(viewModel.visibleVersionItems, [attachmentItem]);
    expect(viewModel.focusedItemId, attachmentItem.id);

    await viewModel.renameItem(attachmentItem, 'Role swap 2');
    attachmentItem = viewModel.snapshot.scripts.single.versions
        .singleWhere((version) => version.id == 'script-image-version-1')
        .items
        .single;
    expect(renamedLabels, ['Role swap 2']);
    expect(attachmentItem.title, 'Role swap 2');

    await viewModel.deleteItem(attachmentItem);
    expect(deletedAttachmentIds, ['attachment-1']);
    expect(
        viewModel.snapshot.scripts.single.versions
            .any((version) => version.id == 'script-image-version-1'),
        isFalse);
  });

  test('renames scripts and reloads the snapshot', () async {
    var scripts = [_script()];
    final renamedLabels = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      renameScriptRecord: (script, label) async {
        renamedLabels.add(label);
        scripts = [
          scripts.single.copyWith(
            name: label,
            updatedAt: DateTime.parse('2026-06-04T10:00:00Z'),
          ),
        ];
      },
    );

    await viewModel.load();
    await viewModel.renameScript(
      viewModel.snapshot.scripts.single,
      'Renamed Script',
    );

    expect(renamedLabels, ['Renamed Script']);
    expect(viewModel.snapshot.scripts.single.title, 'Renamed Script');
  });

  test('defaults district cards to all and supports custom script districts',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        _script(),
        _script().copyWith(
          scriptId: 'script-2',
          name: '旁支档案',
          sourceFolder: r'C:\stories\branch',
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      customCategories: const [
        ScriptExhibitionUserCategory(
          id: 'favorites',
          title: '收藏馆区',
          description: '手动归入的剧本。',
          tags: ['自由分类'],
        ),
      ],
      customCategoryScriptIds: const {
        'favorites': ['script-1'],
      },
    );

    await viewModel.load();

    expect(viewModel.categories.map((category) => category.title), [
      '全部馆区',
      '未分类',
      '收藏馆区',
    ]);
    final uncategorized = viewModel.categories.singleWhere(
      (category) =>
          category.id == ScriptExhibitionRoomViewModel.uncategorizedCategoryId,
    );
    expect(uncategorized.count, 1);
    expect(
      viewModel.categories
          .map((category) => category.id)
          .contains(ScriptExhibitionRoomViewModel.activeCategoryId),
      isFalse,
    );
    expect(
      viewModel.categories
          .map((category) => category.id)
          .contains(ScriptExhibitionRoomViewModel.archivedCategoryId),
      isFalse,
    );
    expect(
      viewModel.categories
          .map((category) => category.id)
          .contains(ScriptExhibitionRoomViewModel.needsActionCategoryId),
      isFalse,
    );

    viewModel.selectCategory(
      ScriptExhibitionRoomViewModel.uncategorizedCategoryId,
    );

    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-2',
    ]);

    viewModel.selectCategory('favorites');

    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-1',
    ]);
  });

  test('custom category ids merge sidecar assignments with script categories',
      () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [
        _script().copyWith(categoryNames: const ['QAQ']),
        _script().copyWith(
          scriptId: 'script-2',
          name: 'Branch Archive',
          sourceFolder: r'C:\stories\branch',
        ),
        _script().copyWith(
          scriptId: 'script-3',
          name: 'Other Archive',
          sourceFolder: r'C:\stories\other',
        ),
      ],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      loadCustomCategories: () async => [_userCategory('QAQ')],
      loadCustomCategoryScriptIds: () async => const {
        'custom:QAQ': ['script-2'],
      },
    );

    await viewModel.load();

    final category = viewModel.categories.singleWhere(
      (category) => category.title == 'QAQ',
    );
    expect(category.count, 2);

    viewModel.selectCategory('custom:QAQ');

    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-1',
      'script-2',
    ]);
    expect(
      viewModel.categories
          .singleWhere(
            (category) =>
                category.id ==
                ScriptExhibitionRoomViewModel.uncategorizedCategoryId,
          )
          .count,
      1,
    );
  });

  test('persists empty custom categories across view model reloads', () async {
    var storedCategories = <ScriptExhibitionUserCategory>[
      _userCategory('QAQ'),
    ];
    final created = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => const [],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      loadCustomCategories: () async => storedCategories,
      createCategoryRecord: (categoryName) async {
        created.add(categoryName);
        storedCategories = [
          ...storedCategories,
          _userCategory(categoryName),
        ];
      },
    );

    await viewModel.load();
    await viewModel.createCategory('Empty zone');

    expect(created, ['Empty zone']);
    expect(viewModel.categories.map((category) => category.title).skip(2), [
      'Empty zone',
      'QAQ',
    ]);

    final reopened = ScriptExhibitionRoomViewModel(
      loadScripts: () async => const [],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      loadCustomCategories: () async => storedCategories,
    );

    await reopened.load();

    expect(reopened.categories.map((category) => category.title).skip(2), [
      'Empty zone',
      'QAQ',
    ]);
  });

  test('assigning a category updates the visible shelf before persistence ends',
      () async {
    final assignCompleter = Completer<void>();
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      assignScriptCategory: (script, categoryName) => assignCompleter.future,
    );

    await viewModel.load();
    final assignFuture = viewModel.assignScriptToCategory(
      viewModel.snapshot.scripts.single,
      'QAQ',
    );
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.selectedCategoryId,
        ScriptExhibitionRoomViewModel.allCategoryId);
    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-1',
    ]);
    expect(
        viewModel.categories
            .singleWhere((category) => category.title == 'QAQ')
            .count,
        1);

    assignCompleter.complete();
    await assignFuture;
  });

  test('delayed production enrichment keeps assigned recast categories',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'script_exhibition_delayed_recast_category_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final sourceJson = File('${root.path}${Platform.pathSeparator}001.json');
    final sourceImage = File('${root.path}${Platform.pathSeparator}001.png');
    await sourceJson.writeAsString('{}');
    await sourceImage.writeAsBytes([1, 2, 3]);
    final productionCompleter = Completer<List<ProductionPlan>>();
    final viewModel = ScriptExhibitionRoomViewModel(
      loadRecastScripts: () async => [
        RecastExhibitionScript(
          scriptId: 'recast-script',
          scriptName: 'Recast Script',
          sourceRootPath: root.path,
          updatedAt: DateTime.parse('2026-06-04T10:00:00Z'),
          detectedSchema: ScriptSchema.baseInline,
          frames: [
            RecastExhibitionFrame(
              index: 1,
              fileName: '001.json',
              sourcePath: sourceJson.path,
              sourceImagePath: sourceImage.path,
              prompt: 'recast prompt',
              parseStatus: ScriptFrameParseStatus.parsed,
            ),
          ],
        ),
      ],
      loadScripts: () async => const [],
      loadProductionPlans: () => productionCompleter.future,
      loadGalleryRecords: () async => const [],
      assignScriptCategory: (script, categoryName) async {},
    );

    final loadFuture = viewModel.load();
    await pumpEventQueue();

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'recast-script',
    ]);

    await viewModel.assignScriptToCategory(
      viewModel.snapshot.scripts.single,
      'QAQ',
    );

    expect(
      viewModel.categories.singleWhere((category) => category.title == 'QAQ'),
      isA<ScriptExhibitionCategory>().having(
        (category) => category.count,
        'count',
        1,
      ),
    );

    productionCompleter.complete([_plan()]);
    await loadFuture;

    final category = viewModel.categories.singleWhere(
      (category) => category.title == 'QAQ',
    );
    expect(category.count, 1);

    viewModel.selectCategory(category.id);
    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'recast-script',
    ]);
  });

  test('creates custom categories and assigns a single script', () async {
    var scripts = [
      _script(),
      _script().copyWith(
        scriptId: 'script-2',
        name: '旁支档案',
        sourceFolder: r'C:\stories\branch',
      ),
    ];
    final assigned = <String, String>{};
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      assignScriptCategory: (script, categoryName) async {
        assigned[script.scriptId] = categoryName;
        scripts = [
          for (final existing in scripts)
            existing.scriptId == script.scriptId
                ? existing.copyWith(categoryNames: [categoryName])
                : existing,
        ];
      },
    );

    await viewModel.load();
    await viewModel.createCategory('收藏馆区');
    await viewModel.assignScriptToCategory(
      viewModel.snapshot.scripts.firstWhere(
        (script) => script.scriptId == 'script-2',
      ),
      '收藏馆区',
    );

    expect(assigned, {'script-2': '收藏馆区'});
    expect(viewModel.categories.map((category) => category.title), [
      '全部馆区',
      '未分类',
      '收藏馆区',
    ]);

    viewModel.selectCategory('custom:收藏馆区');

    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-2',
    ]);
  });

  test('reloads persisted category assignments after assigning a script',
      () async {
    final scripts = [
      _script(),
      _script().copyWith(
        scriptId: 'script-2',
        name: 'Duplicate Archive',
        sourceFolder: r'C:\stories\duplicate',
      ),
    ];
    var assignments = <String, List<String>>{};
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      loadCustomCategoryScriptIds: () async => assignments,
      assignScriptCategory: (script, categoryName) async {
        assignments = {
          'custom:$categoryName': ['script-1', 'script-2'],
        };
      },
    );

    await viewModel.load();
    await viewModel.assignScriptToCategory(
      viewModel.snapshot.scripts.first,
      'QAQ',
    );

    expect(
      viewModel.categories
          .singleWhere(
            (category) =>
                category.id ==
                ScriptExhibitionRoomViewModel.uncategorizedCategoryId,
          )
          .count,
      0,
    );
    expect(
      viewModel.categories
          .singleWhere((category) => category.title == 'QAQ')
          .count,
      2,
    );
    viewModel.selectCategory('custom:QAQ');
    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-1',
      'script-2',
    ]);
  });

  test('assigns multiple selected scripts to a custom category', () async {
    var scripts = [
      _script(),
      _script().copyWith(
        scriptId: 'script-2',
        name: '旁支档案',
        sourceFolder: r'C:\stories\branch',
      ),
      _script().copyWith(
        scriptId: 'script-3',
        name: '留档档案',
        sourceFolder: r'C:\stories\archive',
      ),
    ];
    final assigned = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      assignScriptCategory: (script, categoryName) async {
        assigned.add('${script.scriptId}:$categoryName');
        scripts = [
          for (final existing in scripts)
            existing.scriptId == script.scriptId
                ? existing.copyWith(categoryNames: [
                    ...existing.categoryNames,
                    categoryName,
                  ])
                : existing,
        ];
      },
    );

    await viewModel.load();
    await viewModel.assignScriptsToCategory(
      viewModel.snapshot.scripts.take(2),
      '收藏馆区',
    );

    expect(assigned, ['script-1:收藏馆区', 'script-2:收藏馆区']);
    expect(viewModel.selectedCategoryId,
        ScriptExhibitionRoomViewModel.allCategoryId);
    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-1',
      'script-2',
      'script-3',
    ]);

    viewModel.selectCategory('custom:收藏馆区');

    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-1',
      'script-2',
    ]);
  });

  test('batch category assignment skips already assigned scripts', () async {
    final scripts = [
      _script().copyWith(categoryNames: const ['QAQ']),
      _script().copyWith(
        scriptId: 'script-2',
        name: 'Branch Archive',
        sourceFolder: r'C:\stories\branch',
      ),
      _script().copyWith(
        scriptId: 'script-3',
        name: 'Other Archive',
        sourceFolder: r'C:\stories\other',
      ),
    ];
    final batchCalls = <List<String>>[];
    final singleCalls = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      assignScriptCategory: (script, categoryName) async {
        singleCalls.add('${script.scriptId}:$categoryName');
      },
      assignScriptsCategory: (scripts, categoryName) async {
        batchCalls.add([
          for (final script in scripts) '${script.scriptId}:$categoryName',
        ]);
      },
    );

    await viewModel.load();
    await viewModel.assignScriptsToCategory([
      viewModel.snapshot.scripts[0],
      viewModel.snapshot.scripts[1],
      viewModel.snapshot.scripts[1],
    ], 'QAQ');

    expect(batchCalls, [
      ['script-2:QAQ'],
    ]);
    expect(singleCalls, isEmpty);
    expect(viewModel.selectedScriptIds, isEmpty);
    expect(
      viewModel.categories.singleWhere((category) => category.title == 'QAQ'),
      isA<ScriptExhibitionCategory>().having(
        (category) => category.count,
        'count',
        2,
      ),
    );
  });

  test('deletes a custom category without deleting scripts', () async {
    var scripts = [
      _script().copyWith(categoryNames: const ['收藏馆区', '备选馆区']),
      _script().copyWith(
        scriptId: 'script-2',
        name: '旁支档案',
        sourceFolder: r'C:\stories\branch',
        categoryNames: const ['收藏馆区'],
      ),
    ];
    final deletedCategories = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      deleteCategoryRecord: (categoryName) async {
        deletedCategories.add(categoryName);
        scripts = [
          for (final script in scripts)
            script.copyWith(
              categoryNames: script.categoryNames
                  .where(
                    (name) =>
                        name.trim().toLowerCase() !=
                        categoryName.trim().toLowerCase(),
                  )
                  .toList(growable: false),
            ),
        ];
      },
    );

    await viewModel.load();
    final category = viewModel.categories.singleWhere(
      (category) => category.title == '收藏馆区',
    );
    viewModel.selectCategory(category.id);
    await viewModel.deleteCategory(category);

    expect(deletedCategories, ['收藏馆区']);
    expect(viewModel.snapshot.scripts.map((script) => script.scriptId), [
      'script-1',
      'script-2',
    ]);
    expect(
      viewModel.categories.map((category) => category.title),
      isNot(contains('收藏馆区')),
    );
    expect(
      viewModel.categories.map((category) => category.title),
      contains('备选馆区'),
    );
    expect(viewModel.selectedCategoryId,
        ScriptExhibitionRoomViewModel.allCategoryId);
  });

  test('removes one script from the selected custom category', () async {
    var scripts = [
      _script().copyWith(categoryNames: const ['收藏馆区', '备选馆区']),
      _script().copyWith(
        scriptId: 'script-2',
        name: '旁支档案',
        sourceFolder: r'C:\stories\branch',
        categoryNames: const ['收藏馆区'],
      ),
    ];
    final removed = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
      removeScriptCategory: (script, categoryName) async {
        removed.add('${script.scriptId}:$categoryName');
        scripts = [
          for (final existing in scripts)
            existing.scriptId == script.scriptId
                ? existing.copyWith(
                    categoryNames: existing.categoryNames
                        .where(
                          (name) =>
                              name.trim().toLowerCase() !=
                              categoryName.trim().toLowerCase(),
                        )
                        .toList(growable: false),
                  )
                : existing,
        ];
      },
    );

    await viewModel.load();
    viewModel.selectCategory('custom:收藏馆区');
    await viewModel.removeScriptFromSelectedCategory(
      viewModel.visibleScripts.firstWhere(
        (script) => script.scriptId == 'script-1',
      ),
    );

    expect(removed, ['script-1:收藏馆区']);
    expect(viewModel.selectedCategoryId, 'custom:收藏馆区');
    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-2',
    ]);
    expect(viewModel.snapshot.scripts.map((script) => script.scriptId), [
      'script-1',
      'script-2',
    ]);
    expect(
      viewModel.snapshot.scripts
          .singleWhere((script) => script.scriptId == 'script-1')
          .categoryNames,
      ['备选馆区'],
    );
  });

  test('sorts visible scripts by the selected shelf order', () async {
    final scripts = [
      _script().copyWith(
        scriptId: 'script-beta',
        name: 'Beta',
        sourceFolder: r'C:\stories\beta',
        updatedAt: DateTime.parse('2026-06-01T09:00:00Z'),
      ),
      _script().copyWith(
        scriptId: 'script-alpha',
        name: 'Alpha',
        sourceFolder: r'C:\stories\alpha',
        updatedAt: DateTime.parse('2026-06-03T09:00:00Z'),
      ),
      _script().copyWith(
        scriptId: 'script-gamma',
        name: 'Gamma',
        sourceFolder: r'C:\stories\gamma',
        updatedAt: DateTime.parse('2026-05-31T09:00:00Z'),
      ),
    ];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => [
        _plan(
          scriptId: 'script-gamma',
          scriptName: 'Gamma',
          scriptPath: r'C:\stories\gamma',
        ),
      ],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-alpha',
      'script-gamma',
      'script-beta',
    ]);

    viewModel.selectScriptSort(ScriptExhibitionScriptSort.title);

    expect(viewModel.scriptSort, ScriptExhibitionScriptSort.title);
    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-alpha',
      'script-beta',
      'script-gamma',
    ]);

    viewModel.selectScriptSort(ScriptExhibitionScriptSort.imageCount);

    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-alpha',
      'script-gamma',
      'script-beta',
    ]);

    viewModel.selectScriptSort(ScriptExhibitionScriptSort.needsAction);

    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-gamma',
      'script-alpha',
      'script-beta',
    ]);
  });

  test('sorts image count by original script frame count', () {
    final now = DateTime.parse('2026-06-04T10:00:00Z');
    ScriptExhibitionScript script({
      required String id,
      required String title,
      required int originalCount,
      required int generatedImageCount,
      required int imageLikeItemCount,
    }) {
      return ScriptExhibitionScript(
        scriptId: id,
        title: title,
        sourceFolder: r'C:\stories\sort',
        updatedAt: now,
        versions: const [],
        status: ScriptExhibitionScriptStatus.active,
        originalCount: originalCount,
        generatedImageCount: generatedImageCount,
        imageLikeItemCount: imageLikeItemCount,
        hasImage: imageLikeItemCount > 0,
        coverItem: null,
        pendingCount: 0,
        firstNeedsActionItem: null,
      );
    }

    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => const [],
      loadProductionPlans: () async => const [],
      loadGalleryRecords: () async => const [],
    )..snapshot = ScriptExhibitionSnapshot(
        scripts: [
          script(
            id: 'generated-heavy',
            title: 'Generated Heavy',
            originalCount: 1,
            generatedImageCount: 6,
            imageLikeItemCount: 7,
          ),
          script(
            id: 'original-rich',
            title: 'Original Rich',
            originalCount: 4,
            generatedImageCount: 0,
            imageLikeItemCount: 4,
          ),
          script(
            id: 'middle-original',
            title: 'Middle Original',
            originalCount: 2,
            generatedImageCount: 0,
            imageLikeItemCount: 2,
          ),
        ],
        totalImageCount: 13,
        generatedImageCount: 6,
        needsActionCount: 0,
      );

    viewModel.selectScriptSort(ScriptExhibitionScriptSort.imageCount);

    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'original-rich',
      'middle-original',
      'generated-heavy',
    ]);
  });

  test('filters visible scripts by shelf search query', () async {
    final scripts = [
      _script().copyWith(
        scriptId: 'script-alpha',
        name: 'Alpha Archive',
        sourceFolder: r'C:\stories\alpha',
      ),
      _script().copyWith(
        scriptId: 'script-beta',
        name: 'Beta Branch',
        sourceFolder: r'C:\stories\branch',
      ),
      _script().copyWith(
        scriptId: 'script-gamma',
        name: 'Gamma Shelf',
        sourceFolder: r'C:\stories\gamma',
      ),
    ];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => scripts,
      loadProductionPlans: () async => [
        _plan(
          scriptId: 'script-gamma',
          scriptName: 'Gamma Shelf',
          scriptPath: r'C:\stories\gamma',
        ),
      ],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();
    viewModel.replaceShelfSelection(['script-alpha', 'script-beta']);

    viewModel.updateScriptSearchQuery('beta');

    expect(viewModel.scriptSearchQuery, 'beta');
    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-beta',
    ]);
    expect(viewModel.selectedScriptIds, {'script-beta'});

    viewModel.updateScriptSearchQuery('new heroine');

    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-gamma',
    ]);
    expect(viewModel.selectedScriptIds, isEmpty);

    viewModel.clearScriptSearchQuery();

    expect(viewModel.visibleScripts.map((script) => script.scriptId), [
      'script-gamma',
      'script-alpha',
      'script-beta',
    ]);
  });

  test(
      'coalesces production tasks by strong script identity on large snapshots',
      () async {
    final now = DateTime.parse('2026-06-02T08:00:00Z');
    final plan = ProductionPlan(
      id: 'large',
      name: 'Large Batch',
      createdAt: now,
      updatedAt: now,
      tasks: [
        for (var index = 1; index <= 40; index++)
          ProductionTask.scriptRecastFrame(
            id: 'task-$index',
            planId: 'large',
            title: 'Frame $index',
            scriptId: 'script-1',
            scriptName: 'Rain Archive',
            scriptPath: r'C:\stories\rain',
            recastRunId: 'run-large',
            frameIndex: index + 100,
            sourceFileName: 'generated-$index.json',
            payload: {'input': 'generated frame $index'},
            status: ProductionTaskStatus.completed,
            outputImagePath: r'C:\out\large.png',
            createdAt: now,
            updatedAt: now,
          ),
      ],
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [plan],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();

    expect(viewModel.snapshot.scripts, hasLength(1));
    final productionVersion = viewModel.snapshot.scripts.single.versions
        .singleWhere((version) => version.id == 'production-large');
    expect(productionVersion.items, hasLength(40));
  });

  test('sorts visible version items by the selected detail order', () async {
    final basePlan = _plan();
    final plan = basePlan.copyWith(
      updatedAt: DateTime.parse('2026-06-04T08:00:00Z'),
      tasks: [
        basePlan.tasks[0].copyWith(
          updatedAt: DateTime.parse('2026-06-02T08:00:00Z'),
        ),
        basePlan.tasks[1].copyWith(
          updatedAt: DateTime.parse('2026-06-04T08:00:00Z'),
        ),
      ],
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [plan],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();
    viewModel.selectScript('script-1');
    viewModel.selectVersion('production-plan-hero-a');

    expect(viewModel.visibleVersionItems.map((item) => item.id), [
      'production-plan-hero-a-task-generated-1',
      'production-plan-hero-a-task-failed-2',
    ]);

    viewModel.selectItemSort(ScriptExhibitionItemSort.recent);

    expect(viewModel.itemSort, ScriptExhibitionItemSort.recent);
    expect(viewModel.visibleVersionItems.map((item) => item.id), [
      'production-plan-hero-a-task-failed-2',
      'production-plan-hero-a-task-generated-1',
    ]);

    viewModel.selectItemSort(ScriptExhibitionItemSort.oldest);

    expect(viewModel.visibleVersionItems.map((item) => item.id), [
      'production-plan-hero-a-task-generated-1',
      'production-plan-hero-a-task-failed-2',
    ]);
  });

  test('organizes script images and persists updated references', () async {
    final root = await Directory.systemTemp.createTemp(
      'script_exhibition_organize_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final generatedRoot = Directory('${root.path}${Platform.pathSeparator}out');
    final imageFile = File(
      '${generatedRoot.path}${Platform.pathSeparator}frame-01.png',
    );
    await imageFile.parent.create(recursive: true);
    await imageFile.writeAsBytes([1, 2, 3]);

    final basePlan = _plan();
    final plan = basePlan.copyWith(
      executionSettings: ProductionPlanExecutionSettings(
        outputDirectory: generatedRoot.path,
      ),
      tasks: [
        basePlan.tasks.first.copyWith(outputImagePath: imageFile.path),
      ],
    );
    final record = _galleryRecord(imagePath: imageFile.path);
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

    await viewModel.load();
    viewModel.selectScript('script-1');
    viewModel.selectVersion('production-plan-hero-a');
    final preview = await viewModel.previewScriptImageOrganization(
      viewModel.snapshot.scripts.single,
    );
    expect(preview.moves, hasLength(1));

    final result = await viewModel.organizeScriptImages(
      viewModel.snapshot.scripts.single,
      preview: preview,
    );

    expect(result.movedImagePaths, hasLength(1));
    expect(
      savedPlans.single.single.tasks.single.outputImagePath,
      result.movedImagePaths.single,
    );
    expect(
      savedGalleryRecords.single.single.imagePath,
      result.movedImagePaths.single,
    );
    expect(viewModel.selectedScript?.scriptId, 'script-1');
    expect(viewModel.selectedVersion?.id, 'production-plan-hero-a');
  });

  test('organizeScriptImages covers every script in the exhibition snapshot',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'script_exhibition_all_scripts_organize_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final generatedRoot = Directory('${root.path}${Platform.pathSeparator}out');
    final firstImage = File(
      '${generatedRoot.path}${Platform.pathSeparator}first.png',
    );
    final secondImage = File(
      '${generatedRoot.path}${Platform.pathSeparator}second.png',
    );
    await generatedRoot.create(recursive: true);
    await firstImage.writeAsBytes([1, 2, 3]);
    await secondImage.writeAsBytes([4, 5, 6]);

    final secondScript = _script().copyWith(
      scriptId: 'script-2',
      name: 'Moon Archive',
      sourceFolder: r'C:\stories\moon',
    );
    final basePlan = _plan();
    final taskTemplate = basePlan.tasks.first;
    final plan = basePlan.copyWith(
      executionSettings: ProductionPlanExecutionSettings(
        outputDirectory: generatedRoot.path,
      ),
      tasks: [
        taskTemplate.copyWith(
          id: 'task-script-1',
          outputImagePath: firstImage.path,
          source: const ProductionTaskSource(
            scriptId: 'script-1',
            scriptName: 'Rain Archive',
            scriptPath: r'C:\stories\rain',
            recastRunId: 'run-hero-a',
            frameIndex: 1,
            sourceFileName: '001.json',
          ),
        ),
        taskTemplate.copyWith(
          id: 'task-script-2',
          outputImagePath: secondImage.path,
          source: const ProductionTaskSource(
            scriptId: 'script-2',
            scriptName: 'Moon Archive',
            scriptPath: r'C:\stories\moon',
            recastRunId: 'run-hero-a',
            frameIndex: 2,
            sourceFileName: '002.json',
          ),
        ),
      ],
    );
    final savedPlans = <List<ProductionPlan>>[];
    final savedGalleryRecords = <List<StudioGalleryRecord>>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script(), secondScript],
      loadProductionPlans: () async => [plan],
      loadGalleryRecords: () async => const [],
      saveProductionPlans: (plans) async => savedPlans.add(plans),
      saveGalleryRecords: (records) async => savedGalleryRecords.add(records),
      defaultGeneratedImageRoot: () async => root.path,
    );

    await viewModel.load();
    viewModel.selectScript('script-1');
    final preview = await viewModel.previewScriptImageOrganization(
      viewModel.snapshot.scripts.firstWhere(
        (script) => script.scriptId == 'script-1',
      ),
    );

    expect(preview.moves.map((move) => move.taskId), [
      'task-script-1',
      'task-script-2',
    ]);

    final result = await viewModel.organizeScriptImages(
      viewModel.selectedScript!,
      preview: preview,
    );

    expect(result.failedImagePaths, isEmpty);
    expect(result.movedImagePaths, hasLength(2));
    expect(await firstImage.exists(), isFalse);
    expect(await secondImage.exists(), isFalse);
    expect(
      savedPlans.single.single.tasks.map((task) => task.outputImagePath),
      everyElement(isNotNull),
    );
    expect(savedGalleryRecords.single, isEmpty);
  });

  test('organizeScriptImages requires savers before file mutation', () async {
    final root = await Directory.systemTemp.createTemp(
      'script_exhibition_missing_savers_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final generatedRoot = Directory('${root.path}${Platform.pathSeparator}out');
    final imageFile = File(
      '${generatedRoot.path}${Platform.pathSeparator}frame-01.png',
    );
    final orphanFile = File(
      '${generatedRoot.path}${Platform.pathSeparator}orphan.png',
    );
    await imageFile.parent.create(recursive: true);
    await imageFile.writeAsBytes([1, 2, 3]);
    await orphanFile.writeAsBytes([4, 5, 6]);

    final basePlan = _plan();
    final plan = basePlan.copyWith(
      executionSettings: ProductionPlanExecutionSettings(
        outputDirectory: generatedRoot.path,
      ),
      tasks: [
        basePlan.tasks.first.copyWith(outputImagePath: imageFile.path),
      ],
    );
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [plan],
      loadGalleryRecords: () async => const [],
      defaultGeneratedImageRoot: () async => root.path,
    );

    await viewModel.load();
    final preview = await viewModel.previewScriptImageOrganization(
      viewModel.snapshot.scripts.single,
    );

    await expectLater(
      viewModel.organizeScriptImages(
        viewModel.snapshot.scripts.single,
        preview: preview,
      ),
      throwsA(isA<StateError>()),
    );

    expect(await imageFile.exists(), isTrue);
    expect(await orphanFile.exists(), isTrue);
  });

  test('missing default generated root does not fall back to cwd', () async {
    final root = await Directory.systemTemp.createTemp(
      'script_exhibition_missing_default_root_',
    );
    final cwdProbeDir = Directory(
      '${Directory.current.path}${Platform.pathSeparator}'
      'script_exhibition_cwd_probe',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
      if (await cwdProbeDir.exists()) {
        await cwdProbeDir.delete(recursive: true);
      }
    });
    final imageFile = File('${root.path}${Platform.pathSeparator}frame-01.png');
    await imageFile.writeAsBytes([1, 2, 3]);
    await cwdProbeDir.create();
    final cwdOrphan = File(
      '${cwdProbeDir.path}${Platform.pathSeparator}cwd-orphan.png',
    );
    await cwdOrphan.writeAsBytes([4, 5, 6]);

    final basePlan = _plan();
    final plan = basePlan.copyWith(
      tasks: [
        basePlan.tasks.first.copyWith(outputImagePath: imageFile.path),
      ],
    );
    final savedPlans = <List<ProductionPlan>>[];
    final savedGalleryRecords = <List<StudioGalleryRecord>>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [plan],
      loadGalleryRecords: () async => const [],
      saveProductionPlans: (plans) async => savedPlans.add(plans),
      saveGalleryRecords: (records) async => savedGalleryRecords.add(records),
    );

    await viewModel.load();

    await expectLater(
      viewModel.organizeScriptImages(viewModel.snapshot.scripts.single),
      throwsA(isA<StateError>()),
    );

    expect(await imageFile.exists(), isTrue);
    expect(await cwdOrphan.exists(), isTrue);
    expect(savedPlans, isEmpty);
    expect(savedGalleryRecords, isEmpty);
  });

  test('protects original sidecar images while organizing generated output',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'script_exhibition_original_sidecar_protect_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final generatedRoot = Directory('${root.path}${Platform.pathSeparator}out');
    final originalDir = Directory(
      '${generatedRoot.path}${Platform.pathSeparator}original',
    );
    await originalDir.create(recursive: true);
    final sourceJson =
        File('${originalDir.path}${Platform.pathSeparator}001.json');
    final sourceSidecar =
        File('${originalDir.path}${Platform.pathSeparator}001.png');
    final generatedImage = File(
      '${generatedRoot.path}${Platform.pathSeparator}frame-01.png',
    );
    await sourceJson.writeAsString('{}');
    await sourceSidecar.writeAsBytes([1, 1, 1]);
    await generatedImage.writeAsBytes([2, 2, 2]);

    final script = Script(
      id: 'script-1',
      name: '闆ㄥ妗ｆ',
      rootPath: originalDir.path,
      detectedSchema: ScriptSchema.baseInline,
      frames: [
        ScriptFrame(
          index: 1,
          fileName: '001.json',
          sourcePath: sourceJson.path,
          sourceImagePath: sourceSidecar.path,
          rawJson: '{}',
          parsed: const ParsedFrame(baseCaption: 'source prompt'),
          detectedSchema: ScriptSchema.baseInline,
          parseStatus: ScriptFrameParseStatus.parsed,
        ),
      ],
    );
    final basePlan = _plan();
    final plan = basePlan.copyWith(
      executionSettings: ProductionPlanExecutionSettings(
        outputDirectory: generatedRoot.path,
      ),
      tasks: [
        basePlan.tasks.first.copyWith(outputImagePath: generatedImage.path),
      ],
    );
    final savedPlans = <List<ProductionPlan>>[];
    final savedGalleryRecords = <List<StudioGalleryRecord>>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadRecastCaches: () async => [
        RecastScriptCache(
          scriptId: 'script-1',
          scriptName: '闆ㄥ妗ｆ',
          sourceRootPath: originalDir.path,
          sourceFingerprint: 'fingerprint',
          updatedAt: DateTime.parse('2026-06-04T10:00:00Z'),
          mapping: RecastMapping.defaults('script-1'),
          scriptSnapshot: script.toJson(),
        ),
      ],
      loadScripts: () async => const [],
      loadProductionPlans: () async => [plan],
      loadGalleryRecords: () async => const [],
      saveProductionPlans: (plans) async => savedPlans.add(plans),
      saveGalleryRecords: (records) async => savedGalleryRecords.add(records),
      defaultGeneratedImageRoot: () async => root.path,
    );

    await viewModel.load();
    final preview = await viewModel.previewScriptImageOrganization(
      viewModel.snapshot.scripts.single,
    );
    expect(preview.moves, hasLength(1));
    expect(preview.orphanImagePaths, isNot(contains(sourceSidecar.path)));

    final result = await viewModel.organizeScriptImages(
      viewModel.snapshot.scripts.single,
      preview: preview,
    );

    expect(result.failedImagePaths, isEmpty);
    expect(await sourceSidecar.exists(), isTrue);
    expect(await generatedImage.exists(), isFalse);
    expect(await File(result.movedImagePaths.single).exists(), isTrue);
    expect(savedPlans.single.single.tasks.single.outputImagePath,
        result.movedImagePaths.single);
    expect(savedGalleryRecords.single, isEmpty);
  });

  test('deletes only the selected production version for the current script',
      () async {
    var plans = [_plan()];
    final deletedVersions = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => plans,
      loadGalleryRecords: () async => const [],
      deleteVersionRecord: (
        script,
        version, {
        bool deleteLocalFiles = false,
      }) async {
        deletedVersions.add('${script.scriptId}:${version.id}');
        plans = [
          for (final plan in plans)
            if (version.id == 'production-${plan.id}')
              plan.copyWith(tasks: const [])
            else
              plan,
        ].where((plan) => plan.tasks.isNotEmpty).toList(growable: false);
      },
    );

    await viewModel.load();
    viewModel.selectScript('script-1');
    viewModel.selectVersion('production-plan-hero-a');

    final script = viewModel.selectedScript!;
    final productionVersion = script.versions.singleWhere(
      (version) => version.id == 'production-plan-hero-a',
    );
    expect(viewModel.canDeleteVersion(script, productionVersion), isTrue);

    await viewModel.deleteVersion(script, productionVersion);

    expect(deletedVersions, ['script-1:production-plan-hero-a']);
    expect(viewModel.selectedScript?.scriptId, 'script-1');
    expect(
      viewModel.selectedScript!.versions.map((version) => version.id),
      contains(ScriptExhibitionVersion.originalId),
    );
    expect(
      viewModel.selectedScript!.versions.map((version) => version.id),
      isNot(contains('production-plan-hero-a')),
    );
    expect(viewModel.selectedVersion?.id, ScriptExhibitionVersion.originalId);
  });

  test('forwards local file deletion intent when deleting a version', () async {
    var plans = [_plan()];
    bool? requestedDeleteLocalFiles;
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => plans,
      loadGalleryRecords: () async => const [],
      deleteVersionRecord: (
        script,
        version, {
        bool deleteLocalFiles = false,
      }) async {
        requestedDeleteLocalFiles = deleteLocalFiles;
        plans = [
          for (final plan in plans)
            if (version.id == 'production-${plan.id}')
              plan.copyWith(tasks: const [])
            else
              plan,
        ].where((plan) => plan.tasks.isNotEmpty).toList(growable: false);
      },
    );

    await viewModel.load();
    viewModel.selectScript('script-1');

    final script = viewModel.selectedScript!;
    final productionVersion = script.versions.singleWhere(
      (version) => version.id == 'production-plan-hero-a',
    );

    await viewModel.deleteVersion(
      script,
      productionVersion,
      deleteLocalFiles: true,
    );

    expect(requestedDeleteLocalFiles, isTrue);
  });

  test('deletes multiple versions and falls back to the original version',
      () async {
    var plans = [_plan()];
    var records = [
      _galleryRecord(
        taskId: 'task-archived-only',
        imagePath: r'C:\gallery\frame-archived-only.png',
      ),
    ];
    final deletedVersions = <String>[];
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => plans,
      loadGalleryRecords: () async => records,
      deleteVersionRecord: (
        script,
        version, {
        bool deleteLocalFiles = false,
      }) async {
        deletedVersions.add(
          '${script.scriptId}:${version.id}:$deleteLocalFiles',
        );
        if (version.id == 'production-plan-hero-a') {
          plans = const [];
        }
        if (version.id == ScriptExhibitionVersion.galleryId) {
          records = const [];
        }
      },
    );

    await viewModel.load();
    viewModel.selectScript('script-1');
    viewModel.selectVersion('production-plan-hero-a');
    final script = viewModel.selectedScript!;
    final versions = [
      script.versions.singleWhere(
        (version) => version.id == 'production-plan-hero-a',
      ),
      script.versions.singleWhere(
        (version) => version.id == ScriptExhibitionVersion.galleryId,
      ),
    ];

    await viewModel.deleteVersions(
      script,
      versions,
      deleteLocalFiles: true,
    );

    expect(deletedVersions, [
      'script-1:production-plan-hero-a:true',
      'script-1:gallery:true',
    ]);
    expect(viewModel.selectedScript?.scriptId, 'script-1');
    expect(viewModel.selectedVersion?.id, ScriptExhibitionVersion.originalId);
    expect(
      viewModel.selectedScript!.versions.map((version) => version.id),
      isNot(contains('production-plan-hero-a')),
    );
    expect(
      viewModel.selectedScript!.versions.map((version) => version.id),
      isNot(contains(ScriptExhibitionVersion.galleryId)),
    );
  });

  test('deleteVersion returns after removing the version from current snapshot',
      () async {
    var plans = [_plan()];
    var productionLoadCount = 0;
    final refreshCompleter = Completer<List<ProductionPlan>>();
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () {
        productionLoadCount += 1;
        if (productionLoadCount == 1) {
          return Future.value(plans);
        }
        return refreshCompleter.future;
      },
      loadGalleryRecords: () async => const [],
      deleteVersionRecord: (
        script,
        version, {
        bool deleteLocalFiles = false,
      }) async {
        plans = [
          for (final plan in plans)
            if (version.id == 'production-${plan.id}')
              plan.copyWith(tasks: const [])
            else
              plan,
        ].where((plan) => plan.tasks.isNotEmpty).toList(growable: false);
      },
    );

    await viewModel.load();
    viewModel.selectScript('script-1');
    viewModel.selectVersion('production-plan-hero-a');

    final script = viewModel.selectedScript!;
    final productionVersion = script.versions.singleWhere(
      (version) => version.id == 'production-plan-hero-a',
    );

    final deleteFuture = viewModel.deleteVersion(script, productionVersion);
    try {
      await expectLater(
        deleteFuture.timeout(const Duration(milliseconds: 100)),
        completes,
      );
    } finally {
      if (!refreshCompleter.isCompleted) {
        refreshCompleter.complete(const []);
      }
      await deleteFuture;
    }

    expect(productionLoadCount, greaterThanOrEqualTo(2));
    expect(viewModel.selectedScript?.scriptId, 'script-1');
    expect(
      viewModel.selectedScript!.versions.map((version) => version.id),
      isNot(contains('production-plan-hero-a')),
    );
    expect(viewModel.selectedVersion?.id, ScriptExhibitionVersion.originalId);
  });

  test('does not delete the original source version', () async {
    var deleteCount = 0;
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => const [],
      deleteVersionRecord: (
        script,
        version, {
        bool deleteLocalFiles = false,
      }) async {
        deleteCount += 1;
      },
    );

    await viewModel.load();
    viewModel.selectScript('script-1');

    final script = viewModel.selectedScript!;
    final originalVersion = script.versions.singleWhere(
      (version) => version.id == ScriptExhibitionVersion.originalId,
    );
    expect(viewModel.canDeleteVersion(script, originalVersion), isFalse);

    await viewModel.deleteVersion(script, originalVersion);

    expect(deleteCount, 0);
    expect(
      viewModel.selectedScript!.versions.map((version) => version.id),
      contains(ScriptExhibitionVersion.originalId),
    );
  });

  test('jumps to the first production item that needs action', () async {
    final viewModel = ScriptExhibitionRoomViewModel(
      loadScripts: () async => [_script()],
      loadProductionPlans: () async => [_plan()],
      loadGalleryRecords: () async => const [],
    );

    await viewModel.load();
    viewModel.jumpToFirstNeedsAction();

    expect(viewModel.selectedScript?.scriptId, 'script-1');
    expect(viewModel.selectedVersion?.id, 'production-plan-hero-a');
    expect(viewModel.focusedItemId, 'production-plan-hero-a-task-failed-2');
    expect(viewModel.selectedDetailFilterId,
        ScriptExhibitionRoomViewModel.needsActionDetailFilterId);
    expect(viewModel.visibleVersionItems.map((item) => item.id), [
      'production-plan-hero-a-task-failed-2',
    ]);
  });
}

ScriptExhibitionUserCategory _userCategory(String name) {
  return ScriptExhibitionUserCategory(
    id: 'custom:$name',
    title: name,
    description: 'Manual category',
    tags: const ['Manual'],
  );
}

TokenizerScript _script() {
  final now = DateTime.parse('2026-06-01T09:00:00Z');
  final source1 = _source(
    'source-1',
    '001.json',
    r'C:\stories\rain\001.json',
    defaultImagePath: r'C:\stories\rain\001.png',
  );
  final source2 = _source(
    'source-2',
    '002.json',
    r'C:\stories\rain\002.json',
    defaultImagePath: r'C:\stories\rain\002.png',
  );
  return TokenizerScript(
    scriptId: 'script-1',
    name: '雨夜档案',
    sourceFolder: r'C:\stories\rain',
    sourceMode: TokenizerScriptSourceMode.auto,
    createdAt: now,
    updatedAt: now,
    status: TokenizerScriptStatus.needsReview,
    sourceFiles: [source1, source2],
    sampleFileIds: const ['source-1'],
    characterIdentities: const [],
    styleStages: const [],
    knowledgeCandidates: const [],
    imageTasks: [
      _task(
        id: 'task-1',
        source: source1,
        prompt: 'library entrance, rainy night',
        status: TokenizerTaskReviewStatus.confirmed,
      ),
      _task(
        id: 'task-2',
        source: source2,
        prompt: 'old book shelf, wet coat',
        status: TokenizerTaskReviewStatus.needsReview,
      ),
    ],
  );
}

TokenizerSourceFile _source(
  String id,
  String fileName,
  String path, {
  String defaultImagePath = '',
  TokenizerScriptSourceKind kind = TokenizerScriptSourceKind.json,
}) {
  return TokenizerSourceFile(
    fileId: id,
    fileName: fileName,
    path: path,
    kind: kind,
    defaultImagePath: defaultImagePath,
  );
}

TokenizerImageTask _task({
  required String id,
  required TokenizerSourceFile source,
  required String prompt,
  String? finalPrompt,
  required TokenizerTaskReviewStatus status,
}) {
  return TokenizerImageTask(
    taskId: id,
    sourceFile: source,
    parseStatus: 'parsed',
    originalPrompt: prompt,
    promptMode: TokenizerScriptPromptMode.tag,
    parsedPrompt: prompt,
    finalPrompt: finalPrompt ?? prompt,
    artistEvidence: const [],
    characterSlotMatches: const [],
    confidence: 0.9,
    reviewStatus: status,
    details: const TokenizerParseDetails(),
  );
}

ProductionPlan _plan({
  String scriptId = 'script-1',
  String scriptName = '雨夜档案',
  String scriptPath = r'C:\stories\rain',
  Map<String, dynamic>? generatedPayload,
}) {
  final now = DateTime.parse('2026-06-02T08:00:00Z');
  return ProductionPlan(
    id: 'plan-hero-a',
    name: '主角版 A',
    createdAt: now,
    updatedAt: now,
    tasks: [
      ProductionTask.scriptRecastFrame(
        id: 'task-generated-1',
        planId: 'plan-hero-a',
        title: '入口雨幕',
        scriptId: scriptId,
        scriptName: scriptName,
        scriptPath: scriptPath,
        recastRunId: 'run-hero-a',
        frameIndex: 1,
        sourceFileName: '001.json',
        payload: generatedPayload ??
            const {
              'input': 'library entrance, new heroine',
            },
        status: ProductionTaskStatus.completed,
        outputImagePath: r'C:\out\frame-01.png',
        createdAt: now,
        updatedAt: now,
      ),
      ProductionTask.scriptRecastFrame(
        id: 'task-failed-2',
        planId: 'plan-hero-a',
        title: '旧书架前',
        scriptId: scriptId,
        scriptName: scriptName,
        scriptPath: scriptPath,
        recastRunId: 'run-hero-a',
        frameIndex: 2,
        sourceFileName: '002.json',
        payload: const {
          'input': 'old shelf, failed generation',
        },
        status: ProductionTaskStatus.failed,
        error: 'rate limited',
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
}

StudioGalleryRecord _galleryRecord({
  String id = 'gallery-1',
  String taskId = 'task-generated-1',
  String imagePath = r'C:\gallery\frame-01.png',
}) {
  final now = DateTime.parse('2026-06-03T08:00:00Z');
  return StudioGalleryRecord.fromRecastPayload(
    payload: const {
      'input': 'library entrance, archived version',
    },
    id: id,
    createdAt: now,
    title: '收纳: 入口雨幕',
    imagePath: imagePath,
    info: 'archived image prompt',
    provenance: StudioRecastProvenance(
      scriptId: 'script-1',
      scriptName: '雨夜档案',
      scriptPath: r'C:\stories\rain',
      recastRunId: 'run-hero-a',
      productionPlanId: 'plan-hero-a',
      productionPlanFingerprint: 'fingerprint',
      taskId: taskId,
      frameIndex: 1,
      sourceFileName: '001.json',
      payloadFingerprint: 'payload-fingerprint',
      mappingConfigFingerprint: 'mapping-fingerprint',
      outputImagePath: imagePath,
    ),
  );
}

Uint8List _pngWithTextChunks(Map<String, String> textChunks) {
  final base = File(
    '${Uri.base.toFilePath()}assets${Platform.pathSeparator}appicon.png',
  ).readAsBytesSync();
  final bytes = BytesBuilder(copy: false);
  bytes.add(base.sublist(0, 8));
  var offset = 8;
  var inserted = false;
  while (offset + 12 <= base.length) {
    final length = ByteData.sublistView(
      Uint8List.sublistView(base, offset, offset + 4),
    ).getUint32(0, Endian.big);
    final chunkEnd = offset + 12 + length;
    if (chunkEnd > base.length) {
      break;
    }
    final type = ascii.decode(base.sublist(offset + 4, offset + 8));
    bytes.add(base.sublist(offset, chunkEnd));
    offset = chunkEnd;
    if (!inserted && type == 'IHDR') {
      for (final entry in textChunks.entries) {
        bytes.add(_pngChunk(
          'tEXt',
          Uint8List.fromList([
            ...utf8.encode(entry.key),
            0,
            ...utf8.encode(entry.value),
          ]),
        ));
      }
      inserted = true;
    }
  }
  return inserted ? bytes.toBytes() : base;
}

Uint8List _pngChunk(String type, Uint8List data) {
  final typeBytes = ascii.encode(type);
  final crcInput = Uint8List.fromList([...typeBytes, ...data]);
  return Uint8List.fromList([
    ..._uint32(data.length),
    ...typeBytes,
    ...data,
    ..._uint32(_crc32(crcInput)),
  ]);
}

Uint8List _uint32(int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.big);
  return data.buffer.asUint8List();
}

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
