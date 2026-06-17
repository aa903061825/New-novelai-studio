import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/services/production_executor_service.dart';
import 'package:novel_studio/ui/core/app_display_settings.dart';
import 'package:novel_studio/ui/studio_batch/view_models/production_queue_viewmodel.dart';
import 'package:novel_studio/ui/studio_batch/widgets/studio_batch_page.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_theme.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_display.dart';

ProductionPlan _fakePlan() {
  final now = DateTime.utc(2026, 5, 25, 12);
  return ProductionPlan(
    id: 'plan-1',
    name: 'Script Recast Queue',
    createdAt: now,
    updatedAt: now,
    tasks: [
      ProductionTask.scriptRecastFrame(
        id: 'task-1',
        planId: 'plan-1',
        title: 'Frame 1',
        scriptId: 'script-1',
        recastRunId: 'run-1',
        frameIndex: 1,
        sourceFileName: 'nai_1.json',
        payload: const {
          'input': 'city lights, new_heroine',
          'model': 'nai-diffusion-4-5-full',
          'parameters': {
            'seed': 123456,
            'width': 1216,
            'height': 832,
            'steps': 28,
            'scale': 6.5,
            'sampler': 'k_euler_ancestral',
            'negative_prompt': 'low quality, blurry',
            'reference_image_multiple': ['VERY_LONG_REFERENCE_BASE64'],
          },
        },
        status: ProductionTaskStatus.completed,
        attempts: 1,
        outputImagePath: r'C:\outputs\nai_1.png',
        createdAt: now,
        updatedAt: now,
      ),
      ProductionTask.scriptRecastFrame(
        id: 'task-2',
        planId: 'plan-1',
        title: 'Frame 2',
        scriptId: 'script-1',
        recastRunId: 'run-1',
        frameIndex: 2,
        sourceFileName: 'nai_2.json',
        payload: const {
          'input': 'rainy alley, new_heroine',
          'parameters': {
            'seed': 123457,
            'width': 1216,
            'height': 832,
          },
        },
        status: ProductionTaskStatus.failed,
        attempts: 2,
        error: 'HTTP 429',
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
}

ProductionPlan _queuedPlan() {
  final now = DateTime.utc(2026, 5, 25, 12);
  return ProductionPlan(
    id: 'plan-running',
    name: 'Script Recast Queue',
    createdAt: now,
    updatedAt: now,
    tasks: [
      ProductionTask.scriptRecastFrame(
        id: 'task-running',
        planId: 'plan-running',
        title: 'Frame 1',
        scriptId: 'script-1',
        recastRunId: 'run-1',
        frameIndex: 1,
        sourceFileName: 'nai_1.json',
        payload: const {
          'input': 'running prompt',
          'parameters': {'seed': 1},
        },
        createdAt: now,
        updatedAt: now,
      ),
      ProductionTask.scriptRecastFrame(
        id: 'task-running-2',
        planId: 'plan-running',
        title: 'Frame 2',
        scriptId: 'script-1',
        recastRunId: 'run-1',
        frameIndex: 2,
        sourceFileName: 'nai_2.json',
        payload: const {
          'input': 'second running prompt',
          'parameters': {'seed': 2},
        },
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
}

ProductionPlan _partialQueuedPlan() {
  final now = DateTime.utc(2026, 5, 25, 12);
  return ProductionPlan(
    id: 'plan-partial',
    name: 'Partial Script Recast Queue',
    createdAt: now,
    updatedAt: now,
    tasks: [
      ProductionTask.scriptRecastFrame(
        id: 'task-completed',
        planId: 'plan-partial',
        title: 'Frame 1',
        scriptId: 'script-1',
        recastRunId: 'run-1',
        frameIndex: 1,
        sourceFileName: 'nai_1.json',
        payload: const {
          'input': 'completed prompt',
          'parameters': {'seed': 1},
        },
        status: ProductionTaskStatus.completed,
        attempts: 1,
        outputImagePath: r'C:\out\nai_1.png',
        createdAt: now,
        updatedAt: now,
      ),
      ProductionTask.scriptRecastFrame(
        id: 'task-queued',
        planId: 'plan-partial',
        title: 'Frame 2',
        scriptId: 'script-1',
        recastRunId: 'run-1',
        frameIndex: 2,
        sourceFileName: 'nai_2.json',
        payload: const {
          'input': 'queued prompt',
          'parameters': {'seed': 2},
        },
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
}

ProductionPlan _manyQueuedPlan() {
  final now = DateTime.utc(2026, 5, 25, 12);
  return ProductionPlan(
    id: 'plan-many',
    name: 'Many Script Recast Queue',
    createdAt: now,
    updatedAt: now,
    tasks: [
      for (var index = 0; index < 48; index += 1)
        ProductionTask.scriptRecastFrame(
          id: 'task-many-$index',
          planId: 'plan-many',
          title: 'p${index.toString().padLeft(3, '0')}.json',
          scriptId: 'script-1',
          recastRunId: 'run-1',
          frameIndex: index + 1,
          sourceFileName: 'p${index.toString().padLeft(3, '0')}.json',
          payload: {
            'input':
                '1girl, 1boy, arato_asato, ratatatat74, censored, freng, artist:channel caststation, very long prompt fragment $index',
            'parameters': {
              'seed': index,
              'width': 1216,
              'height': 832,
            },
          },
          createdAt: now,
          updatedAt: now,
        ),
    ],
  );
}

ProductionPlan _badOutputPathPlan() {
  final now = DateTime.utc(2026, 5, 25, 12);
  return ProductionPlan(
    id: 'plan-bad-output-path',
    name: 'Bad Output Path Queue',
    createdAt: now,
    updatedAt: now,
    tasks: [
      ProductionTask.scriptRecastFrame(
        id: 'task-bad-output-path',
        planId: 'plan-bad-output-path',
        title: 'bad-output-path.json',
        scriptId: 'script-1',
        recastRunId: 'run-1',
        frameIndex: 1,
        sourceFileName: 'bad-output-path.json',
        payload: const {
          'input': 'bad output path prompt',
          'parameters': {'seed': 1},
        },
        status: ProductionTaskStatus.completed,
        attempts: 1,
        outputImagePath: '\u0000',
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
}

ProductionPlan _v4SlottedPromptPlan() {
  final now = DateTime.utc(2026, 5, 25, 12);
  return ProductionPlan(
    id: 'plan-v4-slotted',
    name: 'V4 Slotted Queue',
    createdAt: now,
    updatedAt: now,
    tasks: [
      ProductionTask.scriptRecastFrame(
        id: 'task-v4-slotted',
        planId: 'plan-v4-slotted',
        title: 'nai_v4.json',
        scriptId: 'script-1',
        recastRunId: 'run-1',
        frameIndex: 1,
        sourceFileName: 'nai_v4.json',
        payload: const {
          'input': 'base input only',
          'parameters': {
            'seed': 44,
            'v4_prompt': {
              'caption': {
                'base_caption': 'base scene, cinematic light',
                'char_captions': [
                  {'char_caption': 'first character, blue eyes'},
                  {'caption': 'second character, red dress'},
                  {'base_caption': 'third character fallback'},
                ],
              },
            },
            'v4_negative_prompt': {
              'caption': {
                'base_caption': 'bad anatomy',
                'char_captions': [
                  {'char_caption': 'bad hands'},
                ],
              },
            },
          },
        },
        createdAt: now,
        updatedAt: now,
      ),
    ],
  );
}

Widget _buildProductionBatchPageWithFakePlan() {
  return MaterialApp(
    theme: StudioTheme.build(),
    home: StudioBatchPage(
      viewModel: ProductionQueueViewModel(
        plans: [_fakePlan()],
        settings: const ProductionQueueExecutionSettings(
          model: 'nai-diffusion-4-curated-preview',
          sampler: 'k_euler',
          steps: 24,
          scale: 5.5,
          width: 832,
          height: 1216,
          tokenReference: 'workspace-token',
          requestIntervalSeconds: 4,
          requestIntervalRandomRangeSeconds: 8,
          retryCount: 3,
          outputDirectory: r'C:\outputs',
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('batch page shows deterministic production queue not config tree',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildProductionBatchPageWithFakePlan());
    await tester.pump();

    expect(
        find.byKey(const ValueKey('studio-batch-queue-panel')), findsOneWidget);
    expect(find.text('队列总览'), findsOneWidget);
    expect(find.text('执行设置'), findsOneWidget);
    expect(find.text('Script Recast Queue'), findsOneWidget);
    expect(find.text('任务 2'), findsOneWidget);
    expect(find.text('完成 1'), findsOneWidget);
    expect(find.text('失败 1'), findsOneWidget);
    expect(find.text('Token workspace-token'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('studio-production-model-use-original')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('studio-production-size-use-original')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('studio-production-sampler-use-original')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('studio-production-steps-use-original')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('studio-production-scale-use-original')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('studio-production-seed-use-original')),
      findsOneWidget,
    );
    expect(find.text('模型 nai-diffusion-4-curated-preview'), findsNothing);
    expect(find.text('尺寸 832x1216'), findsNothing);
    expect(find.text('采样 k_euler'), findsNothing);
    expect(find.text('步数 24'), findsNothing);
    expect(find.text('CFG 5.5'), findsNothing);
    expect(find.text('Seed random (-1)'), findsOneWidget);
    expect(find.text('seed (-1=random)'), findsOneWidget);
    expect(find.widgetWithText(TextField, '-1'), findsOneWidget);
    expect(find.textContaining('并发'), findsNothing);
    expect(find.text('间隔 4s'), findsOneWidget);
    expect(find.text('随机 +0~8s'), findsOneWidget);
    expect(find.textContaining('重试次数 3'), findsOneWidget);
    expect(find.text(r'C:\outputs'), findsWidgets);
    expect(find.text('Frame 1'), findsWidgets);
    expect(find.text('Frame 2'), findsWidgets);
    expect(find.text('HTTP 429'), findsWidgets);
    expect(find.text('重跑'), findsWidgets);
    expect(find.text('重跑异常'), findsOneWidget);
    expect(find.text('生成结果'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('studio-production-results-waterfall')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('studio-production-result-card-task-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('studio-production-result-card-prompt-tags-task-1'),
      ),
      findsNothing,
    );
    expect(find.text('正向提示词'), findsNothing);
    expect(find.text('负向提示词'), findsNothing);
    expect(find.textContaining('seed: 123456'), findsNothing);
    expect(find.text('导出 JSON'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('config-tree-editor-probe')), findsNothing);
    expect(find.text('Payload'), findsNothing);
    expect(find.textContaining('VERY_LONG_REFERENCE_BASE64'), findsNothing);
    expect(find.textContaining('cfg_rescale'), findsNothing);
    expect(find.textContaining('noise_schedule'), findsNothing);
    expect(find.textContaining('sm_dyn'), findsNothing);
  });

  testWidgets('batch page can mix original and edited parameter controls',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildProductionBatchPageWithFakePlan());
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('studio-production-model-use-original')),
    );
    await tester.pump();

    expect(find.text('nai-diffusion-4-5-full'), findsOneWidget);
    expect(find.text('模型 nai-diffusion-4-5-full'), findsNothing);
    expect(find.text('尺寸 832x1216'), findsNothing);
    expect(find.text('采样 k_euler'), findsNothing);
    expect(find.text('步数 24'), findsNothing);
    expect(find.text('CFG 5.5'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('studio-production-scale-input')),
      '7.25',
    );
    await tester.enterText(
      find.byKey(const ValueKey('studio-production-seed-input')),
      '777',
    );
    await tester.pump();

    expect(find.text('CFG 7.25'), findsNothing);
    expect(find.text('Seed 777'), findsOneWidget);
  });

  testWidgets('batch page exposes selectable model and sampler options',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildProductionBatchPageWithFakePlan());
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('studio-production-model-select')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('nai-diffusion-4-5-curated').last);
    await tester.pumpAndSettle();

    expect(find.text('nai-diffusion-4-5-curated'), findsOneWidget);
    expect(find.text('模型 nai-diffusion-4-5-curated'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('studio-production-sampler-select')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('k_dpmpp_2m_sde').last);
    await tester.pumpAndSettle();

    expect(find.text('k_dpmpp_2m_sde'), findsOneWidget);
    expect(find.text('采样 k_dpmpp_2m_sde'), findsNothing);
  });

  testWidgets('batch page edits sequential runtime execution settings',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildProductionBatchPageWithFakePlan());
    await tester.pump();

    expect(
      find.byKey(const ValueKey('studio-production-concurrency-input')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const ValueKey('studio-production-interval-input')),
      '12',
    );
    await tester.enterText(
      find.byKey(const ValueKey('studio-production-random-interval-input')),
      '20',
    );
    await tester.enterText(
      find.byKey(const ValueKey('studio-production-retry-input')),
      '4',
    );
    await tester.enterText(
      find.byKey(const ValueKey('studio-production-429-delay-input')),
      '30',
    );
    await tester.enterText(
      find.byKey(const ValueKey('studio-production-output-input')),
      r'D:\batch-output',
    );
    await tester.pump();

    expect(find.textContaining('并发'), findsNothing);
    expect(find.text('间隔 12s'), findsOneWidget);
    expect(find.text('随机 +0~20s'), findsOneWidget);
    expect(find.text('retry'), findsNothing);
    expect(find.textContaining('重试次数 4'), findsOneWidget);
    expect(find.textContaining('429 30s'), findsOneWidget);
    expect(find.text(r'D:\batch-output'), findsWidgets);
  });

  testWidgets('batch page can switch retry mode to infinite', (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewModel = ProductionQueueViewModel(
      plans: [_fakePlan()],
      settings: const ProductionQueueExecutionSettings(
        retryCount: 3,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(viewModel: viewModel),
      ),
    );
    await tester.pump();

    expect(find.textContaining('重试次数 3'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('studio-production-retry-infinite')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('studio-production-retry-infinite')),
    );
    await tester.pump();

    expect(viewModel.retryIndefinitely, isTrue);
    expect(find.textContaining('重试 无限'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('studio-production-retry-infinite')),
    );
    await tester.pump();

    expect(viewModel.retryIndefinitely, isFalse);
    expect(find.textContaining('重试次数 3'), findsOneWidget);
  });

  testWidgets('batch page lets output directory be typed or browsed',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewModel = ProductionQueueViewModel(
      plans: [_fakePlan()],
      settings: const ProductionQueueExecutionSettings(
        outputDirectory: r'C:\outputs',
      ),
      pickOutputDirectory: () async => r'E:\picked-output',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(viewModel: viewModel),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('studio-production-output-browse')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('studio-production-output-browse')),
    );
    await tester.pump();

    expect(viewModel.outputDirectory, r'E:\picked-output');
    expect(find.text(r'E:\picked-output'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('studio-production-output-input')),
      r'D:\typed-output',
    );
    await tester.pump();

    expect(viewModel.outputDirectory, r'D:\typed-output');
    expect(find.text(r'D:\typed-output'), findsWidgets);
  });

  testWidgets('batch page renames the current production queue',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildProductionBatchPageWithFakePlan());
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('studio-production-rename-plan')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('studio-production-rename-plan-field')),
      'Renamed Queue',
    );
    await tester.tap(
      find.byKey(const ValueKey('studio-production-confirm-rename-plan')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Renamed Queue'), findsOneWidget);
    expect(find.text('Script Recast Queue'), findsNothing);
  });

  testWidgets('batch result waterfall scrolls without debug error widgets',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(
          viewModel: ProductionQueueViewModel(
            plans: [_manyQueuedPlan()],
            settings: const ProductionQueueExecutionSettings(
              model: 'nai-diffusion-4-curated-preview',
              sampler: 'k_euler',
              steps: 24,
              scale: 5.5,
              width: 832,
              height: 1216,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final waterfall =
        find.byKey(const ValueKey('studio-production-results-waterfall'));
    await tester.drag(waterfall, const Offset(0, -2400));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byWidgetPredicate((widget) => widget is ErrorWidget),
        findsNothing);
  });

  testWidgets('batch result card tolerates invalid output image paths',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(
          viewModel: ProductionQueueViewModel(
            plans: [_badOutputPathPlan()],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byWidgetPredicate((widget) => widget is ErrorWidget),
        findsNothing);
    expect(find.text('结果文件尚未找到'), findsOneWidget);
  });

  testWidgets('batch page shows pause then continue on the primary control',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final requestStarted = Completer<void>();
    final requestCompleter = Completer<Uint8List>();
    final viewModel = ProductionQueueViewModel(
      plans: [_queuedPlan()],
      executorService: ProductionExecutorService(
        requestImage: (_) {
          requestStarted.complete();
          return requestCompleter.future;
        },
        saveImage: (bytes, fileName) async => 'C:/out/$fileName',
        now: () => DateTime.utc(2026, 5, 25, 12),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(viewModel: viewModel),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('studio-production-start')));
    await requestStarted.future;
    await tester.pump();

    expect(viewModel.isExecuting, isTrue);
    expect(find.text('运行中'), findsWidgets);
    expect(find.text('暂停'), findsOneWidget);
    final pauseButton = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const ValueKey('studio-production-start')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(
      pauseButton.style?.backgroundColor?.resolve({}),
      StudioTokens.warning,
    );
    expect(
      find.byKey(const ValueKey('studio-production-hard-stop')),
      findsOneWidget,
    );

    final startButton = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const ValueKey('studio-production-start')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(startButton.onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('studio-production-start')));
    await tester.pump();

    expect(viewModel.pauseRequested, isTrue);
    expect(find.text('暂停中'), findsWidgets);
    expect(find.text('等待暂停'), findsOneWidget);
    expect(find.text('运行中'), findsNothing);

    requestCompleter.complete(Uint8List.fromList([137, 80, 78, 71]));
    await tester.pumpAndSettle();

    expect(viewModel.isPaused, isTrue);
    expect(find.text('继续'), findsOneWidget);
  });

  testWidgets('batch page opens unfinished restored queues as continue',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewModel = ProductionQueueViewModel(
      plans: [_partialQueuedPlan()],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(viewModel: viewModel),
      ),
    );
    await tester.pump();

    expect(viewModel.canResume, isTrue);
    expect(find.text('继续'), findsOneWidget);
    expect(find.text('开始'), findsNothing);
  });

  testWidgets('batch page rerun abnormal button starts failed tasks',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final requestStarted = Completer<void>();
    final requestCompleter = Completer<Uint8List>();
    final viewModel = ProductionQueueViewModel(
      plans: [_fakePlan()],
      executorService: ProductionExecutorService(
        requestImage: (_) {
          requestStarted.complete();
          return requestCompleter.future;
        },
        saveImage: (bytes, fileName) async => 'C:/rerun/$fileName',
        now: () => DateTime.utc(2026, 5, 25, 12),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(viewModel: viewModel),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('studio-production-retry-failed')),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    await requestStarted.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    expect(viewModel.isExecuting, isTrue);
    expect(viewModel.selectedTask?.id, 'task-2');
    expect(viewModel.selectedTask?.status, ProductionTaskStatus.running);
    expect(viewModel.selectedTask?.attempts, 3);

    requestCompleter.complete(Uint8List.fromList([137, 80, 78, 71]));
    await tester.pumpAndSettle();

    expect(viewModel.isExecuting, isFalse);
    expect(viewModel.selectedTask?.status, ProductionTaskStatus.completed);
    expect(viewModel.selectedTask?.outputImagePath, 'C:/rerun/task-2.png');
  });

  testWidgets('batch page task-row rerun queues a clone without starting',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewModel = ProductionQueueViewModel(
      plans: [_fakePlan()],
      executorService: ProductionExecutorService(
        requestImage: (_) async => Uint8List.fromList([137, 80, 78, 71]),
        saveImage: (bytes, fileName) async => 'C:/rerun/$fileName',
        now: () => DateTime.utc(2026, 5, 25, 12),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(viewModel: viewModel),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('studio-production-rerun-task-1')),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(viewModel.isExecuting, isFalse);
    expect(viewModel.selectedPlan?.tasks.map((task) => task.id), [
      'task-1',
      'task-1-rerun',
      'task-2',
    ]);
    expect(viewModel.selectedTask?.id, 'task-1-rerun');
    expect(viewModel.selectedTask?.status, ProductionTaskStatus.queued);
    expect(viewModel.selectedTask?.attempts, 0);
    expect(viewModel.selectedTask?.outputImagePath, isNull);
    expect(find.byWidgetPredicate((widget) => widget is ErrorWidget),
        findsNothing);
  });

  testWidgets('result card quick rerun queues a clone without starting rerun',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewModel = ProductionQueueViewModel(
      plans: [_fakePlan()],
      now: () => DateTime.utc(2026, 5, 28, 10, 30),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(viewModel: viewModel),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('studio-production-quick-rerun-task-1')),
    );
    await tester.pump();

    expect(viewModel.isExecuting, isFalse);
    expect(viewModel.selectedPlan?.tasks.map((task) => task.id), [
      'task-1',
      'task-1-rerun',
      'task-2',
    ]);
    expect(
        viewModel.selectedPlan?.tasks[1].status, ProductionTaskStatus.queued);
    expect(viewModel.selectedPlan?.tasks[1].outputImagePath, isNull);
  });

  testWidgets('batch page shows result waterfall and detail dialog',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildProductionBatchPageWithFakePlan());
    await tester.pump();

    expect(
      find.byKey(const ValueKey('studio-production-results-waterfall')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('studio-production-result-card-task-1')),
      findsOneWidget,
    );
    expect(find.text('正向提示词'), findsNothing);
    expect(find.text('负向提示词'), findsNothing);
    expect(find.textContaining('VERY_LONG_REFERENCE_BASE64'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('studio-production-result-card-task-1')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('studio-production-result-detail-dialog')),
      findsOneWidget,
    );
    expect(find.text('正向提示词'), findsOneWidget);
    final positiveTags = tester.widget<PromptTagDisplay>(
      find.byKey(const ValueKey('studio-production-positive-prompt-tags')),
    );
    expect(positiveTags.text, 'city lights, new_heroine');
    expect(positiveTags.defaultTranslated, isTrue);
    expect(positiveTags.enableTagActions, isTrue);
    expect(positiveTags.initialLayoutMode, PromptTagLayoutMode.grouped);
    expect(find.text('负向提示词'), findsOneWidget);
    final negativeTags = tester.widget<PromptTagDisplay>(
      find.byKey(const ValueKey('studio-production-negative-prompt-tags')),
    );
    expect(negativeTags.text, 'low quality, blurry');
    expect(negativeTags.negative, isTrue);
    final parameters = find.byKey(
      const ValueKey('studio-production-parameter-summary'),
    );
    expect(parameters, findsOneWidget);
    expect(
      find.descendant(of: parameters, matching: find.text('生成参数')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: parameters, matching: find.text('核心')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: parameters, matching: find.text('种子')),
      findsWidgets,
    );
    expect(
      find.descendant(of: parameters, matching: find.text('123456')),
      findsWidgets,
    );
    expect(
      find.byKey(const ValueKey('studio-production-copy-parameters')),
      findsOneWidget,
    );
    expect(find.textContaining('VERY_LONG_REFERENCE_BASE64'), findsNothing);
  });

  testWidgets('detail dialog prioritizes full prompts over preview size',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppDisplaySettings.setImagePreviewDialogHeight(900, persist: false);
    addTearDown(() {
      AppDisplaySettings.setImagePreviewDialogHeight(
        AppDisplaySettings.defaultImagePreviewDialogHeight,
        persist: false,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(
          viewModel: ProductionQueueViewModel(
            plans: [_v4SlottedPromptPlan()],
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(
        const ValueKey('studio-production-result-card-task-v4-slotted'),
      ),
    );
    await tester.pumpAndSettle();

    final previewFinder =
        find.byKey(const ValueKey('studio-production-result-preview'));
    final promptFinder =
        find.byKey(const ValueKey('studio-production-positive-prompt'));
    final metadataFinder = find.byKey(
      const ValueKey('studio-production-result-detail-metadata'),
    );
    final previewSize = tester.getSize(previewFinder);
    final promptBlockSize = tester.getSize(promptFinder);

    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey('studio-production-result-detail-window'),
            ),
          )
          .height,
      855,
    );
    expect(previewSize.height, greaterThanOrEqualTo(380));
    expect(previewSize.height, lessThanOrEqualTo(420));
    expect(promptBlockSize.width, greaterThan(previewSize.width));
    expect(
      tester.getTopLeft(previewFinder).dy,
      lessThan(tester.getTopLeft(promptFinder).dy),
    );
    expect(
      tester.getTopLeft(promptFinder).dy,
      lessThan(tester.getTopLeft(metadataFinder).dy),
    );
    expect(
      tester.getTopLeft(promptFinder).dy,
      lessThan(760),
    );
    expect(
      tester
          .getSize(
            find.byKey(
                const ValueKey('studio-production-result-detail-dialog')),
          )
          .width,
      greaterThan(1000),
    );

    final positiveRoleOne = find.byKey(
      const ValueKey('studio-production-positive-prompt-tags-group-role-1'),
    );
    final positiveRoleTwo = find.byKey(
      const ValueKey('studio-production-positive-prompt-tags-group-role-2'),
    );
    final positiveRoleThree = find.byKey(
      const ValueKey('studio-production-positive-prompt-tags-group-role-3'),
    );
    final positiveBase = find.byKey(
      const ValueKey('studio-production-positive-prompt-tags-group-base'),
    );
    expect(positiveRoleOne, findsOneWidget);
    expect(positiveRoleTwo, findsOneWidget);
    expect(positiveRoleThree, findsOneWidget);
    expect(positiveBase, findsOneWidget);
    expect(
      tester.getTopLeft(positiveRoleOne).dy,
      lessThan(tester.getTopLeft(positiveRoleTwo).dy),
    );
    expect(
      tester.getTopLeft(positiveRoleThree).dy,
      lessThan(tester.getTopLeft(positiveBase).dy),
    );

    final positiveRoleOneTags = tester.widget<PromptTagDisplay>(
      find.byKey(
        const ValueKey(
          'studio-production-positive-prompt-tags-group-tags-role-1',
        ),
      ),
    );
    expect(positiveRoleOneTags.text, 'first character, blue eyes');

    final positiveBaseTags = tester.widget<PromptTagDisplay>(
      find.byKey(
        const ValueKey(
            'studio-production-positive-prompt-tags-group-tags-base'),
      ),
    );
    expect(positiveBaseTags.text, 'base scene, cinematic light');

    final negativeRoleTags = tester.widget<PromptTagDisplay>(
      find.byKey(
        const ValueKey(
          'studio-production-negative-prompt-tags-group-tags-role-1',
        ),
      ),
    );
    expect(negativeRoleTags.text, 'bad hands');

    final negativeBaseTags = tester.widget<PromptTagDisplay>(
      find.byKey(
        const ValueKey(
            'studio-production-negative-prompt-tags-group-tags-negative-base'),
      ),
    );
    expect(negativeBaseTags.text, 'bad anatomy');
  });

  testWidgets('batch page rates the selected completed task', (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewModel = ProductionQueueViewModel(
      plans: [_fakePlan()],
      now: () => DateTime.utc(2026, 5, 28, 10, 30),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(viewModel: viewModel),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('studio-production-result-card-task-1')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('production-task-rating-5')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('production-task-rating-5')),
    );
    await tester.tap(find.byKey(const ValueKey('production-task-rating-5')));
    await tester.pump();

    expect(viewModel.selectedTask?.rating, 5);
    expect(viewModel.selectedTask?.ratedAt, DateTime.utc(2026, 5, 28, 10, 30));
  });

  testWidgets('batch page can clear the current production queue',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewModel = ProductionQueueViewModel(
      plans: [_fakePlan()],
      now: () => DateTime.utc(2026, 5, 28, 10, 30),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(viewModel: viewModel),
      ),
    );
    await tester.pump();

    await tester
        .tap(find.byKey(const ValueKey('studio-production-clear-current')));
    await tester.pump();

    expect(viewModel.totalTasks, 0);
    expect(viewModel.selectedTask, isNull);
    expect(find.text('暂无生产任务'), findsOneWidget);
  });
}
