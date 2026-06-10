import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/studio/models/tokenizer_script.dart';
import 'package:nai_casrand/data/studio/services/tokenizer_script_service.dart';
import 'package:nai_casrand/data/studio/tools/translation_cache.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_tokenizer_script/widgets/tokenizer_script_page.dart';

class _FakeTokenizerScriptService extends TokenizerScriptService {
  _FakeTokenizerScriptService(this.scripts)
      : super(
          workspaceService: WorkspaceService(),
          translationCache: TranslationCache(clock: () => 1710000000)
            ..setManual('white hair', '白发')
            ..setManual('red eyes', '红眼')
            ..setManual('black dress', '黑裙')
            ..setManual('soft light', '柔光'),
        );

  List<TokenizerScript> scripts;
  int saveCount = 0;
  int scanCount = 0;

  @override
  Future<List<TokenizerScript>> loadScripts() async => scripts;

  @override
  Future<void> saveScript(TokenizerScript script) async {
    saveCount++;
    final next = [
      for (final existing in scripts)
        if (existing.scriptId == script.scriptId) script else existing,
    ];
    final replaced =
        scripts.any((existing) => existing.scriptId == script.scriptId);
    scripts = replaced ? next : [...scripts, script];
  }

  @override
  Future<TokenizerScriptDirectoryScanResult> scanDirectory(
    directory, {
    bool recursive = true,
  }) async {
    scanCount++;
    return const TokenizerScriptDirectoryScanResult(
      sources: [],
      failures: [],
      totalFilesSeen: 0,
      supportedFilesSeen: 0,
      jsonCount: 0,
      imageCount: 0,
    );
  }
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000)
        ..setManual('white hair', '白发')
        ..setManual('red eyes', '红眼')
        ..setManual('black dress', '黑裙')
        ..setManual('soft light', '柔光'),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('shows unified review queue and confirms pending tasks',
      (tester) async {
    final service = _FakeTokenizerScriptService([_scriptWithReviewTask()]);

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: Scaffold(body: TokenizerScriptPage(service: service)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('校验队列'), findsOneWidget);
    expect(find.text('手动校验 / AI 辅助'), findsOneWidget);
    expect(find.text('确认全部'), findsOneWidget);

    await tester.ensureVisible(find.text('确认全部'));
    await tester.tap(find.text('确认全部'));
    await tester.pumpAndSettle();

    expect(service.saveCount, 1);
    expect(service.scripts.single.needsReviewCount, 0);
    expect(service.scripts.single.confirmedCount, 1);
  });

  testWidgets('top actions are clickable and open their target surfaces',
      (tester) async {
    final service = _FakeTokenizerScriptService([_scriptWithReviewTask()]);

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: Scaffold(body: TokenizerScriptPage(service: service)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('导入剧本'));
    await tester.pumpAndSettle();
    expect(find.text('导入分词剧本'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('知识库'));
    await tester.tap(find.text('知识库'));
    await tester.pumpAndSettle();
    expect(find.text('知识库详情'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('待确认规则'));
    await tester.tap(find.text('待确认规则'));
    await tester.pumpAndSettle();
    expect(find.text('待确认规则详情'), findsOneWidget);
  });

  testWidgets('tokenizer page adapts to compact windows without overflow',
      (tester) async {
    final service = _FakeTokenizerScriptService([_scriptWithReviewTask()]);
    addTearDown(() => tester.view.resetPhysicalSize());
    tester.view.physicalSize = const Size(760, 1000);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: Scaffold(body: TokenizerScriptPage(service: service)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('导入剧本'), findsOneWidget);
    expect(find.text('知识库'), findsOneWidget);
    expect(find.text('待确认规则'), findsOneWidget);
  });

  testWidgets('tokenizer page uses wider canvas on desktop windows',
      (tester) async {
    final service = _FakeTokenizerScriptService([_scriptWithReviewTask()]);
    addTearDown(() => tester.view.resetPhysicalSize());
    tester.view.physicalSize = const Size(2100, 1200);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: Scaffold(body: TokenizerScriptPage(service: service)),
      ),
    );
    await tester.pumpAndSettle();

    final pagePanelWidth = tester
        .getSize(
          find
              .ancestor(
                of: find.text('分词剧本').first,
                matching: find.byType(DecoratedBox),
              )
              .first,
        )
        .width;
    expect(pagePanelWidth, greaterThan(1500));
  });

  testWidgets('large imported scripts do not render per-task cards',
      (tester) async {
    final service = _FakeTokenizerScriptService([_scriptWithTaskCount(180)]);

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: Scaffold(body: TokenizerScriptPage(service: service)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('任务 180'), findsWidgets);
    expect(find.byIcon(Icons.image_outlined), findsNothing);
  });

  testWidgets('large review queues do not render per-file rows',
      (tester) async {
    final service = _FakeTokenizerScriptService([
      _scriptWithTaskCount(
        180,
        reviewStatus: TokenizerTaskReviewStatus.needsReview,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: Scaffold(body: TokenizerScriptPage(service: service)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('待校验图片任务 180'), findsOneWidget);
    expect(find.text('frame_0.json'), findsNothing);
  });
}

TokenizerScript _scriptWithReviewTask() {
  final now = DateTime.parse('2026-05-24T00:00:00Z');
  const source = TokenizerSourceFile(
    fileId: 'source-1',
    fileName: '001.json',
    path: r'C:\shots\001.json',
    kind: TokenizerScriptSourceKind.json,
  );
  const task = TokenizerImageTask(
    taskId: 'task-1',
    sourceFile: source,
    parseStatus: 'parsed',
    originalPrompt: '1girl, white hair',
    promptMode: TokenizerScriptPromptMode.tag,
    parsedPrompt: '1girl, white hair',
    finalPrompt: '[角色A], white hair',
    generationParams: {
      'v4_prompt': {
        'caption': {
          'base_caption': 'base scene',
          'char_captions': [
            {'char_caption': 'first character, blue eyes'},
            {'char_caption': 'second character, red dress'},
          ],
        },
      },
    },
    artistEvidence: [],
    characterSlotMatches: ['[角色A] char1'],
    confidence: 0.62,
    warnings: ['画师串识别失败，需要校验。'],
    reviewStatus: TokenizerTaskReviewStatus.needsReview,
    details: TokenizerParseDetails(
      warnings: ['画师串识别失败，需要校验。'],
      characters: {
        '[角色A]': TokenizerCharacterDetails(
          identityTags: ['角色A'],
          upperBodyTags: ['white hair', 'red eyes'],
          upperClothingTags: ['black dress'],
          actionTags: ['soft light'],
        ),
      },
    ),
  );
  return TokenizerScript(
    scriptId: 'script-1',
    name: 'Review script',
    sourceFolder: r'C:\shots',
    sourceMode: TokenizerScriptSourceMode.auto,
    createdAt: now,
    updatedAt: now,
    status: TokenizerScriptStatus.needsReview,
    sourceFiles: const [source],
    sampleFileIds: const ['source-1'],
    characterIdentities: const [
      TokenizerCharacterIdentity(
        identityId: 'identity-a',
        displayName: '角色A',
        placeholder: '[角色A]',
      ),
    ],
    styleStages: const [],
    knowledgeCandidates: const [
      TokenizerKnowledgeCandidate(
        candidateId: 'candidate-1',
        type: 'artist',
        label: '画师串候选',
        evidence: '缺少 artist:*',
      ),
    ],
    imageTasks: const [task],
  );
}

TokenizerScript _scriptWithTaskCount(
  int count, {
  TokenizerTaskReviewStatus reviewStatus = TokenizerTaskReviewStatus.auto,
}) {
  final base = _scriptWithReviewTask();
  return base.copyWith(
    status: TokenizerScriptStatus.ready,
    sourceFiles: [
      for (var index = 0; index < count; index++)
        TokenizerSourceFile(
          fileId: 'source-$index',
          fileName: 'frame_$index.json',
          path: r'C:\shots\frame.json',
          kind: TokenizerScriptSourceKind.json,
        ),
    ],
    sampleFileIds: const ['source-0'],
    imageTasks: [
      for (var index = 0; index < count; index++)
        TokenizerImageTask(
          taskId: 'task-$index',
          sourceFile: TokenizerSourceFile(
            fileId: 'source-$index',
            fileName: 'frame_$index.json',
            path: r'C:\shots\frame.json',
            kind: TokenizerScriptSourceKind.json,
          ),
          parseStatus: 'parsed',
          originalPrompt: 'artist:demo, frame $index',
          promptMode: TokenizerScriptPromptMode.tag,
          parsedPrompt: 'artist:demo, frame $index',
          finalPrompt: 'artist:demo, frame $index',
          artistEvidence: reviewStatus == TokenizerTaskReviewStatus.needsReview
              ? const []
              : const ['artist:demo'],
          characterSlotMatches: const [],
          confidence: 0.9,
          warnings: reviewStatus == TokenizerTaskReviewStatus.needsReview
              ? const ['missing artist']
              : const [],
          reviewStatus: reviewStatus,
          details: TokenizerParseDetails(
            warnings: reviewStatus == TokenizerTaskReviewStatus.needsReview
                ? const ['missing artist']
                : const [],
          ),
        ),
    ],
  );
}
