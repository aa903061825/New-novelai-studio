import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/services/production_executor_service.dart';
import 'package:novel_studio/data/studio/services/production_queue_service.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';
import 'package:novel_studio/ui/core/app_display_settings.dart';
import 'package:novel_studio/ui/studio_batch/view_models/production_queue_viewmodel.dart';
import 'package:novel_studio/ui/studio_batch/widgets/studio_batch_page.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_theme.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_button.dart';
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

String _assetPath(String path) => Uri.base.resolve(path).toFilePath();

ProductionPlan _rerunVariantPlan({int variantCount = 5}) {
  final now = DateTime.utc(2026, 5, 25, 12);
  final variantPaths = [
    _assetPath('assets/appicon.png'),
    _assetPath('assets/qrcode1.jpg'),
    _assetPath('assets/qrcode2.jpg'),
  ];
  return ProductionPlan(
    id: 'plan-rerun-variants',
    name: 'Rerun Variant Queue',
    createdAt: now,
    updatedAt: now,
    tasks: [
      for (var index = 0; index < variantCount; index += 1)
        ProductionTask.scriptRecastFrame(
          id: index == 0 ? 'task-1' : 'task-1-rerun-$index',
          planId: 'plan-rerun-variants',
          title: 'Frame 1',
          scriptId: 'script-1',
          recastRunId: 'run-1',
          frameIndex: 1,
          sourceFileName: 'nai_1.json',
          payload: {
            'input': 'variant prompt $index',
            'parameters': {
              'seed': 123456 + index,
              'width': 1216,
              'height': 832,
            },
          },
          status: ProductionTaskStatus.completed,
          attempts: 1,
          outputImagePath: variantPaths[index % variantPaths.length],
          createdAt: now.add(Duration(seconds: index)),
          updatedAt: now.add(Duration(seconds: index)),
        ),
      ProductionTask.scriptRecastFrame(
        id: 'task-2',
        planId: 'plan-rerun-variants',
        title: 'Frame 2',
        scriptId: 'script-1',
        recastRunId: 'run-1',
        frameIndex: 2,
        sourceFileName: 'nai_2.json',
        payload: const {
          'input': 'second frame',
          'parameters': {'seed': 2},
        },
        status: ProductionTaskStatus.completed,
        attempts: 1,
        outputImagePath: _assetPath('assets/appicon.png'),
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

class _CountingProductionQueueService extends ProductionQueueService {
  int readOnlyLoadCount = 0;

  _CountingProductionQueueService()
      : super(workspaceService: WorkspaceService());

  @override
  Future<List<ProductionPlan>> loadPlansReadOnly() async {
    readOnlyLoadCount += 1;
    return [_fakePlan()];
  }

  @override
  Future<ProductionPlanExecutionSettings?> loadLastExecutionSettings() async {
    return null;
  }
}

void main() {
  testWidgets('skipInitialLoad defers the automatic queue load',
      (tester) async {
    final service = _CountingProductionQueueService();
    final viewModel = ProductionQueueViewModel(
      plans: const [],
      queueService: service,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(
          viewModel: viewModel,
          skipInitialLoad: true,
        ),
      ),
    );
    await tester.pump();

    expect(service.readOnlyLoadCount, 0);
  });

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
      find.byKey(const ValueKey('studio-production-cfg-rescale-use-original')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('studio-production-noise-schedule-use-original'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('studio-production-advanced-expansion')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('studio-production-sm-use-original')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('studio-production-sm-dyn-use-original')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('studio-production-dynamic-thresholding-use-original'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('studio-production-variety-use-original')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('studio-production-auto-position-use-original'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('studio-production-legacy-uc-use-original')),
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
    expect(find.text('重跑间隔'), findsOneWidget);
    expect(find.text(r'C:\outputs'), findsWidgets);
    expect(find.text('Frame 1'), findsWidgets);
    expect(find.text('Frame 2'), findsWidgets);
    await tester.ensureVisible(find.text('HTTP 429').first);
    await tester.pump();
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
    final frameBadge = find.byKey(
      const ValueKey('studio-production-result-frame-badge-task-1'),
    );
    expect(frameBadge, findsOneWidget);
    expect(
      find.descendant(of: frameBadge, matching: find.text('1')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: frameBadge,
        matching: find.text('\u7b2c 1 \u5e27'),
      ),
      findsNothing,
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

  testWidgets('batch generation terms expose hover explanations',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildProductionBatchPageWithFakePlan());
    await tester.pump();

    expect(
      find.byTooltip(
        'CFG（Prompt Guidance）控制画面遵循提示词的强度。数值越高越贴近提示词，但过高可能带来过饱和、对比失衡或伪影。',
      ),
      findsOneWidget,
    );
    expect(
      find.byTooltip(
        'CFG Rescale 用于缓和较高 CFG 引起的过曝和色彩失真，同时尽量保留提示词引导。',
      ),
      findsOneWidget,
    );
  });

  testWidgets('batch page edits the new core and advanced generation settings',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewModel = ProductionQueueViewModel(
      plans: [_fakePlan()],
      settings: const ProductionQueueExecutionSettings(
        model: 'nai-diffusion-4-curated-preview',
        cfgRescale: 0.1,
        noiseSchedule: 'karras',
        dynamicThresholding: false,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(viewModel: viewModel),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('studio-production-cfg-rescale-input')),
      '0.55',
    );
    expect(viewModel.batchCfgRescale, 0.55);

    await tester.tap(
      find.byKey(const ValueKey('studio-production-noise-schedule-select')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('exponential').last);
    await tester.pumpAndSettle();
    expect(viewModel.batchNoiseSchedule, 'exponential');

    final expansion =
        find.byKey(const ValueKey('studio-production-advanced-expansion'));
    await tester.ensureVisible(expansion);
    await tester.tap(expansion);
    await tester.pumpAndSettle();
    final thresholdSwitch = find.byKey(
      const ValueKey('studio-production-dynamic-thresholding-switch'),
    );
    await tester.ensureVisible(thresholdSwitch);
    await tester.tap(
      find.descendant(of: thresholdSwitch, matching: find.byType(Switch)),
    );
    await tester.pump();

    expect(viewModel.batchDynamicThresholding, isTrue);
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
    expect(find.text('重跑间隔'), findsOneWidget);
    expect(find.textContaining('重跑间隔 30s'), findsOneWidget);
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

  testWidgets('batch page shows queue tabs and switches the viewed plan',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final secondPlan = _queuedPlan().copyWith(name: 'Queue Two');
    final viewModel = ProductionQueueViewModel(
      plans: [_fakePlan(), secondPlan],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(
          viewModel: viewModel,
          skipInitialLoad: true,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('studio-production-plan-tabs')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('studio-production-plan-tab-plan-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('studio-production-plan-tab-plan-running'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('studio-production-plan-tab-plan-running'),
      ),
    );
    await tester.pump();

    expect(viewModel.selectedPlan?.id, secondPlan.id);
    expect(viewModel.selectedTask?.id, 'task-running');
  });

  testWidgets('switching tabs while running exposes a read-only queue',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requestStarted = Completer<void>();
    final requestCompleter = Completer<Uint8List>();
    final activePlan = _queuedPlan();
    final waitingPlan = _fakePlan();
    final viewModel = ProductionQueueViewModel(
      plans: [activePlan, waitingPlan],
      executorService: ProductionExecutorService(
        requestImage: (_) {
          if (!requestStarted.isCompleted) requestStarted.complete();
          return requestCompleter.future;
        },
        saveImage: (bytes, fileName) async => 'C:/out/$fileName',
        now: () => DateTime.utc(2026, 5, 25, 12),
      ),
    );
    final startFuture = viewModel.start();
    await requestStarted.future;

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(
          viewModel: viewModel,
          skipInitialLoad: true,
        ),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.byKey(
              const ValueKey('studio-production-delete-plan-plan-running'),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(
              const ValueKey('studio-production-delete-plan-plan-1'),
            ),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(
      find.byKey(const ValueKey('studio-production-plan-tab-plan-1')),
    );
    await tester.pump();

    expect(viewModel.selectedPlan?.id, waitingPlan.id);
    expect(viewModel.activePlan?.id, activePlan.id);
    expect(
      find.byKey(
        const ValueKey('studio-production-read-only-queue-notice'),
      ),
      findsOneWidget,
    );
    final modelField = tester.widget<DropdownButtonFormField<String>>(
      find.descendant(
        of: find.byKey(
          const ValueKey('studio-production-model-select'),
        ),
        matching: find.byType(DropdownButtonFormField<String>),
      ),
    );
    expect(modelField.onChanged, isNull);

    requestCompleter.complete(Uint8List.fromList([137, 80, 78, 71]));
    await startFuture;
  });

  testWidgets('queue tab delete confirms and removes only that plan',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final secondPlan = _queuedPlan().copyWith(name: 'Queue Two');
    final viewModel = ProductionQueueViewModel(
      plans: [_fakePlan(), secondPlan],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(
          viewModel: viewModel,
          skipInitialLoad: true,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(
        const ValueKey('studio-production-plan-tab-plan-running'),
      ),
    );
    await tester.pump();
    expect(viewModel.selectedPlan?.id, secondPlan.id);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(
              const ValueKey('studio-production-delete-plan-plan-1'),
            ),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(
      find.byKey(const ValueKey('studio-production-delete-plan-plan-1')),
    );
    await tester.pumpAndSettle();

    // The child delete button must not select its parent tab first.
    expect(viewModel.selectedPlan?.id, secondPlan.id);

    final deleteImagesCheckbox = tester.widget<CheckboxListTile>(
      find.byKey(
        const ValueKey('studio-production-delete-local-images'),
      ),
    );
    expect(deleteImagesCheckbox.value, isFalse);

    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(viewModel.selectedPlan?.id, secondPlan.id);
    expect(viewModel.plans.map((plan) => plan.id), [
      _fakePlan().id,
      secondPlan.id,
    ]);

    await tester.tap(
      find.byKey(const ValueKey('studio-production-delete-plan-plan-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('studio-production-confirm-delete-plan'),
      ),
    );
    await tester.pumpAndSettle();

    expect(viewModel.plans.map((plan) => plan.id), [secondPlan.id]);
    expect(
      find.byKey(const ValueKey('studio-production-plan-tab-plan-1')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('studio-production-plan-tab-plan-running'),
      ),
      findsOneWidget,
    );
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

  testWidgets('batch page task-row rerun starts a clone when idle',
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

    final rerunButton =
        find.byKey(const ValueKey('studio-production-rerun-task-1'));
    await tester.ensureVisible(rerunButton);
    await tester.tap(rerunButton);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(viewModel.isExecuting, isTrue);
    expect(viewModel.selectedPlan?.tasks.map((task) => task.id), [
      'task-1',
      'task-1-rerun',
      'task-2',
    ]);
    expect(viewModel.selectedTask?.id, 'task-1-rerun');
    expect(viewModel.selectedTask?.status, ProductionTaskStatus.running);
    expect(viewModel.selectedTask?.attempts, 1);
    expect(viewModel.selectedTask?.outputImagePath, isNull);
    await requestStarted.future.timeout(const Duration(seconds: 1));
    requestCompleter.complete(Uint8List.fromList([137, 80, 78, 71]));
    await tester.pumpAndSettle();

    expect(viewModel.isExecuting, isFalse);
    expect(viewModel.selectedTask?.status, ProductionTaskStatus.completed);
    expect(
      viewModel.selectedTask?.outputImagePath,
      'C:/rerun/task-1-rerun.png',
    );
    expect(find.byWidgetPredicate((widget) => widget is ErrorWidget),
        findsNothing);
  });

  testWidgets('result card quick rerun starts a clone when idle',
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
        now: () => DateTime.utc(2026, 5, 28, 10, 30),
      ),
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

    expect(viewModel.isExecuting, isTrue);
    expect(viewModel.selectedPlan?.tasks.map((task) => task.id), [
      'task-1',
      'task-1-rerun',
      'task-2',
    ]);
    expect(
        viewModel.selectedPlan?.tasks[1].status, ProductionTaskStatus.running);
    expect(viewModel.selectedPlan?.tasks[1].outputImagePath, isNull);
    await requestStarted.future.timeout(const Duration(seconds: 1));
    requestCompleter.complete(Uint8List.fromList([137, 80, 78, 71]));
    await tester.pumpAndSettle();

    expect(viewModel.isExecuting, isFalse);
    expect(
      viewModel.selectedPlan?.tasks[1].status,
      ProductionTaskStatus.completed,
    );
    expect(
      viewModel.selectedPlan?.tasks[1].outputImagePath,
      'C:/rerun/task-1-rerun.png',
    );
  });

  testWidgets('batch page groups rerun variants without hover preview',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewModel = ProductionQueueViewModel(
      plans: [_rerunVariantPlan()],
      now: () => DateTime.utc(2026, 5, 28, 10, 30),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(viewModel: viewModel),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('studio-production-rerun-task-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('studio-production-rerun-task-1-rerun-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('studio-production-result-card-task-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('studio-production-result-card-task-1-rerun-1'),
      ),
      findsNothing,
    );
    expect(find.text('Frame 1 x5'), findsWidgets);
    final productionImage = tester
        .widgetList<Image>(find.byType(Image))
        .firstWhere(
          (image) => image.key
              .toString()
              .contains('production-image-${_assetPath('assets/appicon.png')}'),
        );
    final resizeImage = productionImage.image as ResizeImage;
    expect(resizeImage.imageProvider, isA<FileImage>());
    expect(resizeImage.width, 768);
    expect(resizeImage.height, 768);

    final resultCard =
        find.byKey(const ValueKey('studio-production-result-card-task-1'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(resultCard));
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(
        const ValueKey('studio-production-result-hover-preview-task-1'),
      ),
      findsNothing,
    );

    await tester.tap(resultCard);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('studio-production-result-detail-dialog')),
      findsOneWidget,
    );
    expect(find.textContaining('appicon.png'), findsWidgets);
    expect(
      find.byKey(const ValueKey('studio-production-result-variant-dots')),
      findsOneWidget,
    );
    for (var index = 0; index < 5; index += 1) {
      expect(
        find.byKey(
            ValueKey('studio-production-result-variant-dot-task-1-$index')),
        findsOneWidget,
      );
    }

    await tester.tap(
      find.byKey(
        const ValueKey('studio-production-result-variant-dot-task-1-2'),
      ),
    );
    await tester.pump();

    expect(find.textContaining('qrcode2.jpg'), findsWidgets);
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

  testWidgets('batch page exposes clear completed with stable feedback',
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

    final clearButton = find.byKey(
      const ValueKey('studio-production-clear-completed'),
    );
    expect(clearButton, findsOneWidget);
    expect(find.text('清理已完成'), findsOneWidget);
    final statsActions = find.byKey(
      const ValueKey('studio-production-queue-stats-actions'),
    );
    expect(
      find.descendant(of: statsActions, matching: clearButton),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(clearButton).dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('studio-production-start')),
            )
            .dy,
      ),
    );
    expect(
      find.byTooltip('可清理 1 个已完成任务；生成结果保留'),
      findsOneWidget,
    );

    await tester.tap(clearButton);
    await tester.pump();

    expect(viewModel.completedTasksPendingDismissal, 0);
    expect(
      viewModel.plans.single.tasks.first.isQueueDismissed,
      isTrue,
    );
    expect(find.text('已清理 1 个已完成任务，生成结果已保留'), findsOneWidget);
  });

  testWidgets(
      'batch page clears completed work from a viewed inactive plan and keeps the active tab',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final requestStarted = Completer<void>();
    final requestCompleter = Completer<Uint8List>();
    final activePlan = _queuedPlan();
    final inactivePlan = _fakePlan();
    final viewModel = ProductionQueueViewModel(
      plans: [activePlan, inactivePlan],
      executorService: ProductionExecutorService(
        requestImage: (_) {
          requestStarted.complete();
          return requestCompleter.future;
        },
        saveImage: (bytes, fileName) async => 'C:/out/$fileName',
        now: () => DateTime.utc(2026, 5, 25, 12),
      ),
    );
    final startFuture = viewModel.start();
    await requestStarted.future;

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(
          viewModel: viewModel,
          skipInitialLoad: true,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('studio-production-plan-tab-plan-1')),
    );
    await tester.pump();

    final clearButton = find.byKey(
      const ValueKey('studio-production-clear-completed'),
    );
    expect(
      tester.widget<StudioButton>(clearButton).onPressed,
      isNotNull,
    );
    expect(viewModel.activePlan?.id, activePlan.id);
    expect(viewModel.selectedPlan?.id, inactivePlan.id);
    expect(
      find.byKey(const ValueKey('studio-production-plan-tab-plan-running')),
      findsOneWidget,
    );

    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    expect(find.text('已清理 1 个已完成任务，生成结果已保留'), findsOneWidget);
    expect(viewModel.activePlan?.id, activePlan.id);
    expect(viewModel.selectedPlan?.id, inactivePlan.id);
    expect(
      find.byKey(const ValueKey('studio-production-plan-tab-plan-running')),
      findsOneWidget,
    );
    expect(
        viewModel.activePlan!.tasks.first.status, ProductionTaskStatus.running);
    expect(viewModel.activePlan!.tasks.first.outputImagePath, isNull);
    expect(
        viewModel.plans
            .singleWhere((plan) => plan.id == inactivePlan.id)
            .tasks
            .first
            .isQueueDismissed,
        isTrue);

    requestCompleter.complete(Uint8List.fromList([137, 80, 78, 71]));
    await startFuture;
  });

  testWidgets('batch page disables clear when only the active plan qualifies',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final requestStarted = Completer<void>();
    final requestCompleter = Completer<Uint8List>();
    final viewModel = ProductionQueueViewModel(
      plans: [_partialQueuedPlan()],
      executorService: ProductionExecutorService(
        requestImage: (_) {
          requestStarted.complete();
          return requestCompleter.future;
        },
        saveImage: (bytes, fileName) async => 'C:/out/$fileName',
        now: () => DateTime.utc(2026, 5, 25, 12),
      ),
    );
    final startFuture = viewModel.start();
    await requestStarted.future;

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(
          viewModel: viewModel,
          skipInitialLoad: true,
        ),
      ),
    );
    await tester.pump();

    final clearButton = find.byKey(
      const ValueKey('studio-production-clear-completed'),
    );
    expect(tester.widget<StudioButton>(clearButton).onPressed, isNull);
    expect(viewModel.completedTasksPendingDismissal, 0);

    requestCompleter.complete(Uint8List.fromList([137, 80, 78, 71]));
    await startFuture;
  });

  testWidgets('queue overview command controls wrap at compact widths',
      (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(
          viewModel: ProductionQueueViewModel(plans: [_fakePlan()]),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('studio-production-start')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('studio-production-queue-stats-actions')),
      findsOneWidget,
    );
  });
}
