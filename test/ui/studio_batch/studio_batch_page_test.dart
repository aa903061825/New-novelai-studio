import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/services/studio_batch_plan_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:nai_casrand/ui/studio_batch/widgets/studio_batch_page.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';

PayloadConfig _payload() {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const ['base'], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({
      'api_key': 'local-key',
      'proxy': '127.0.0.1:7890',
      'output_folder': r'C:\outputs',
      'batch_count': 2,
      'number_of_requests': 4,
    }),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

class _BatchPageViewmodel extends GenerationPageViewmodel {}

class _FakeBatchPlanService extends StudioBatchPlanService {
  _FakeBatchPlanService(this.plans)
      : super(workspaceService: WorkspaceService());

  final List<StudioBatchQueuePlan> plans;
  final StudioBatchPlanService _delegate =
      StudioBatchPlanService(workspaceService: WorkspaceService());

  @override
  Future<List<StudioBatchQueuePlan>> loadQueuePlans() async {
    return plans;
  }

  @override
  StudioBatchApplyResult applyQueueItem({
    required StudioBatchQueueItem item,
    required PayloadConfig target,
  }) {
    return _delegate.applyQueueItem(item: item, target: target);
  }
}

StudioBatchQueuePlan _queuePlan({
  Map<String, dynamic> raw = const {
    'title': 'City shot',
    'prompt': 'rainy alley, neon puddles',
    'negativePrompt': 'bad anatomy',
    'params': {'width': 1024, 'height': 1024, 'scale': 5.5},
    'settings': {'batchCount': 1, 'numberOfRequests': 3},
  },
}) {
  final plan = BatchPlan(
    id: 'batch-1',
    name: 'Night Queue',
    items: [raw],
    createdAt: DateTime.parse('2026-05-23T00:00:00Z'),
    updatedAt: DateTime.parse('2026-05-23T00:00:00Z'),
  );
  return StudioBatchQueuePlan(
    plan: plan,
    items: [
      StudioBatchQueueItem(
        id: 'batch-1:0',
        planId: plan.id,
        planName: plan.name,
        index: 0,
        title: 'City shot',
        summary: 'prompt: rainy alley, neon puddles',
        raw: raw,
      ),
    ],
  );
}

class _ConfigEditorProbe extends StatelessWidget {
  const _ConfigEditorProbe();

  @override
  Widget build(BuildContext context) {
    return const Placeholder(
      key: ValueKey('config-tree-editor-probe'),
    );
  }
}

class _ResultPanelProbe extends StatelessWidget {
  const _ResultPanelProbe();

  @override
  Widget build(BuildContext context) {
    return const Placeholder(
      key: ValueKey('result-panel-probe'),
    );
  }
}

void main() {
  late PayloadConfig payload;

  setUp(() async {
    await GetIt.I.reset();
    payload = _payload();
    GetIt.I.registerSingleton<PayloadConfig>(payload);
    GetIt.I.registerSingleton<CommandStatus>(CommandStatus());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('renders queue controls config tree and result panel',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(
          viewmodel: _BatchPageViewmodel(),
          batchPlanService: _FakeBatchPlanService([_queuePlan()]),
          configEditor: const _ConfigEditorProbe(),
          resultPanel: const _ResultPanelProbe(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
        find.byKey(const ValueKey('studio-batch-queue-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('studio-batch-execution-panel')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('config-tree-editor-probe')), findsOneWidget);
    expect(find.text('Night Queue'), findsOneWidget);
    expect(find.text('City shot'), findsOneWidget);
    expect(find.text('执行控制'), findsOneWidget);
    expect(find.byKey(const ValueKey('result-panel-probe')), findsOneWidget);
  });

  testWidgets('applies a batch plan queue item to current payload',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioBatchPage(
          viewmodel: _BatchPageViewmodel(),
          batchPlanService: _FakeBatchPlanService([_queuePlan()]),
          configEditor: const _ConfigEditorProbe(),
          resultPanel: const _ResultPanelProbe(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(
      find.byKey(const ValueKey('studio-batch-apply-batch-1:0')),
    );
    await tester.pump();

    expect(payload.overridePrompt, 'rainy alley, neon puddles');
    expect(payload.useOverridePrompt, isTrue);
    expect(payload.paramConfig.negativePrompt, 'bad anatomy');
    expect(payload.paramConfig.sizes.single.width, 1024);
    expect(payload.paramConfig.sizes.single.height, 1024);
    expect(payload.paramConfig.scale, 5.5);
    expect(payload.settings.batchCount, 1);
    expect(payload.settings.numberOfRequests, 3);
    expect(payload.settings.apiKey, 'local-key');
    expect(payload.settings.proxy, '127.0.0.1:7890');
    expect(payload.settings.outputFolderPath, r'C:\outputs');
    expect(find.byKey(const ValueKey('studio-batch-last-applied')),
        findsOneWidget);
  });
}
