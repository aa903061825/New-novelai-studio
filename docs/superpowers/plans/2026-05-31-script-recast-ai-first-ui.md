# Script Recast AI-First UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework Script Recast so local preprocessing deduplicates and batches script material for AI first, then the main workspace reviews the AI Recast plan while preserving candidate tools in secondary panels.

**Architecture:** Add a small UI-facing plan projection between `StudioScriptViewModel` and `StudioScriptPage`. Existing `ScriptAiBatchBuilder`, AI suggestions, role mappings, artist mappings, and frame previews remain the source data; the projection decides what belongs in the main plan, Needs Attention, Details, and keyframe review. UI changes stay inside `lib/ui/studio_script/` except for AI batch dedupe improvements in `lib/data/studio/services/script_ai_batch_builder.dart`.

**Tech Stack:** Flutter, Dart, existing `flutter_test` widget/model tests, current Studio theme/components.

---

## File Structure

- Create `lib/ui/studio_script/models/studio_script_recast_plan.dart`
  - UI projection models for the AI-first main workspace, issue queue, and keyframe token review.
- Modify `lib/data/studio/services/script_ai_batch_builder.dart`
  - Deduplicate repeated role captions before AI batching.
- Modify `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
  - Build `StudioScriptRecastPlan` and keyframe token review from existing script, mappings, AI suggestions, and frame data.
- Modify `lib/ui/studio_script/widgets/studio_script_page.dart`
  - Replace the main workspace stack with AI plan summary, Needs Attention, Details drawer, and revised keyframe review.
- Modify tests:
  - `test/data/studio/services/script_ai_batch_builder_test.dart`
  - `test/ui/studio_script/studio_script_page_test.dart`

Project Beads context says git workflow is stealth mode, so this plan intentionally does not include commit steps.

---

### Task 1: Add UI Projection Models

**Files:**
- Create: `lib/ui/studio_script/models/studio_script_recast_plan.dart`
- Test: model coverage can be driven through `test/ui/studio_script/studio_script_page_test.dart` in later tasks.

- [ ] **Step 1: Create the plan model file**

Create `lib/ui/studio_script/models/studio_script_recast_plan.dart` with these models:

```dart
enum StudioScriptPlanIssueKind {
  lowConfidence,
  duplicateRole,
  cacheConflict,
  assetConflict,
  aiBatchFailed,
  highImpact,
}

enum StudioScriptTokenCategory {
  character,
  upperBody,
  lowerBody,
  upperClothing,
  lowerClothing,
  action,
  scene,
  camera,
  artistChain,
  style,
  quality,
  negativeQuality,
  negativeBody,
  negativeArtist,
  negativeContent,
  other,
}

enum StudioScriptTokenEmphasis {
  normal,
  aiRecognized,
  cacheHit,
  userConfirmed,
  replacementAffected,
}

class StudioScriptRecastPlan {
  final List<StudioScriptPlanRole> roles;
  final StudioScriptPlanArtist artist;
  final List<StudioScriptPlanIssue> issues;
  final List<StudioScriptFrameReview> frameReviews;
  final bool hasAiBackedPlan;

  const StudioScriptRecastPlan({
    this.roles = const [],
    this.artist = const StudioScriptPlanArtist(),
    this.issues = const [],
    this.frameReviews = const [],
    this.hasAiBackedPlan = false,
  });
}

class StudioScriptPlanRole {
  final String sourceRoleId;
  final String label;
  final String sourceName;
  final String? selectedCharacterId;
  final String selectedStageLabel;
  final String statusLabel;
  final double confidence;

  const StudioScriptPlanRole({
    required this.sourceRoleId,
    required this.label,
    this.sourceName = '',
    this.selectedCharacterId,
    this.selectedStageLabel = '',
    this.statusLabel = '',
    this.confidence = 0,
  });
}

class StudioScriptPlanArtist {
  final String sourceLabel;
  final String? selectedArtistChainId;

  const StudioScriptPlanArtist({
    this.sourceLabel = '',
    this.selectedArtistChainId,
  });
}

class StudioScriptPlanIssue {
  final String id;
  final StudioScriptPlanIssueKind kind;
  final String title;
  final String detail;
  final List<int> frameIndexes;

  const StudioScriptPlanIssue({
    required this.id,
    required this.kind,
    required this.title,
    this.detail = '',
    this.frameIndexes = const [],
  });
}

class StudioScriptFrameReview {
  final int frameIndex;
  final String title;
  final List<StudioScriptReviewToken> positiveTokens;
  final List<StudioScriptReviewToken> negativeTokens;

  const StudioScriptFrameReview({
    required this.frameIndex,
    required this.title,
    this.positiveTokens = const [],
    this.negativeTokens = const [],
  });
}

class StudioScriptReviewToken {
  final String source;
  final String translation;
  final StudioScriptTokenCategory category;
  final StudioScriptTokenEmphasis emphasis;

  const StudioScriptReviewToken({
    required this.source,
    this.translation = '',
    this.category = StudioScriptTokenCategory.other,
    this.emphasis = StudioScriptTokenEmphasis.normal,
  });
}
```

- [ ] **Step 2: Run analyzer on the new file**

Run: `dart analyze lib/ui/studio_script/models/studio_script_recast_plan.dart`

Expected: `No issues found!`

---

### Task 2: Deduplicate AI Input Before Network Analysis

**Files:**
- Modify: `lib/data/studio/services/script_ai_batch_builder.dart`
- Test: `test/data/studio/services/script_ai_batch_builder_test.dart`

- [ ] **Step 1: Add failing test for deduped slotted captions**

Append to `test/data/studio/services/script_ai_batch_builder_test.dart`:

```dart
test('deduplicates repeated slotted captions before AI batching', () {
  final script = Script(
    id: 'script',
    name: 'script',
    rootPath: '',
    detectedSchema: ScriptSchema.v4Slotted,
    frames: [
      _frame(1, ['alice_(series), torn armor, black thighhighs']),
      _frame(2, ['alice_(series), torn armor, black thighhighs']),
      _frame(3, ['alice_(series), red dress, black thighhighs']),
    ],
  );

  final batches = const ScriptAiBatchBuilder().buildBatches(script);
  final role = batches.single.roles.single;

  expect(role.rawCaptions, [
    'alice_(series), torn armor, black thighhighs',
    'alice_(series), red dress, black thighhighs',
  ]);
  expect(batches.single.frameIndexes, [1, 2, 3]);
});
```

- [ ] **Step 2: Run the failing test**

Run: `flutter test test/data/studio/services/script_ai_batch_builder_test.dart --plain-name "deduplicates repeated slotted captions before AI batching"`

Expected: FAIL because `rawCaptions` still contains duplicate text.

- [ ] **Step 3: Implement dedupe in `_slottedBatch`**

In `lib/data/studio/services/script_ai_batch_builder.dart`, replace the caption collection for each slot with normalized dedupe:

```dart
final captions = _uniqueNormalizedCaptions([
  for (final frame in frames)
    if (slotIndex < frame.parsed.charCaptions.length)
      frame.parsed.charCaptions[slotIndex],
]);
```

Add this helper near `_uniqueStrings`:

```dart
List<String> _uniqueNormalizedCaptions(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  const normalizer = ScriptAiNormalizer();
  for (final value in values) {
    final trimmed = value.trim();
    final key = normalizer.normalizePromptKey(trimmed);
    if (trimmed.isEmpty || key.isEmpty || !seen.add(key)) {
      continue;
    }
    result.add(trimmed);
  }
  return List.unmodifiable(result);
}
```

- [ ] **Step 4: Run AI batch builder tests**

Run: `flutter test test/data/studio/services/script_ai_batch_builder_test.dart`

Expected: all tests pass.

---

### Task 3: Build Recast Plan Projection in the ViewModel

**Files:**
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
- Test: `test/ui/studio_script/studio_script_page_test.dart`

- [ ] **Step 1: Add failing ViewModel assertions through existing widget test file**

Add a ViewModel test to `test/ui/studio_script/studio_script_page_test.dart`:

```dart
test('recast plan projects AI suggestions and issues without exposing raw candidates first', () async {
  final viewModel = StudioScriptViewModel(
    scriptAiRecognitionService: _FakeRecognitionService(
      const ScriptAiRecognitionResult(
        aiRequestCount: 1,
        suggestions: [
          ScriptAiSuggestion(
            id: 'sug-1',
            batchId: 'batch',
            sourceRoleId: 'slot-0',
            cacheKey: 'role:hero|part:armor',
            source: ScriptAiSuggestionSource.ai,
            status: ScriptAiSuggestionStatus.suggested,
            confidence: 0.92,
            displayName: 'hero',
            parts: RecastPromptParts(identity: 'hero', upperClothing: 'armor'),
          ),
          ScriptAiSuggestion(
            id: 'sug-2',
            batchId: 'batch',
            sourceRoleId: 'slot-1',
            cacheKey: 'role:unclear|part:uniform',
            source: ScriptAiSuggestionSource.ai,
            status: ScriptAiSuggestionStatus.needsReview,
            confidence: 0.41,
            displayName: 'unclear',
          ),
        ],
      ),
    ),
    scriptAiBaseUrlProvider: () => 'https://script.example/v1',
    scriptAiTokenProvider: () => 'token',
    scriptAiModelProvider: () => 'gpt-4.1-mini',
  );

  await viewModel.importScriptPath(_fixturePath);
  await viewModel.analyzeScriptWithAi();

  expect(viewModel.recastPlan.hasAiBackedPlan, isTrue);
  expect(viewModel.recastPlan.roles, isNotEmpty);
  expect(viewModel.recastPlan.issues.map((issue) => issue.kind),
      contains(StudioScriptPlanIssueKind.lowConfidence));
});
```

Add the import:

```dart
import 'package:nai_casrand/ui/studio_script/models/studio_script_recast_plan.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "recast plan projects AI suggestions and issues without exposing raw candidates first"`

Expected: FAIL because `recastPlan` does not exist yet.

- [ ] **Step 3: Add ViewModel property and builder**

In `studio_script_viewmodel.dart`, import:

```dart
import 'package:nai_casrand/ui/studio_script/models/studio_script_recast_plan.dart';
```

Add public property:

```dart
StudioScriptRecastPlan recastPlan = const StudioScriptRecastPlan();
```

Call `_refreshRecastPlan()` after:

- `aiSuggestions` updates,
- `roleMappings` updates,
- `artistMappings` updates,
- `_refreshSelectedFrameTagGroups()`.

Add builder methods:

```dart
void _refreshRecastPlan() {
  recastPlan = StudioScriptRecastPlan(
    roles: [
      for (final role in roleMappings)
        StudioScriptPlanRole(
          sourceRoleId: role.sourceRoleId,
          label: role.sourceLabel,
          sourceName: role.sourcePreview,
          selectedCharacterId: role.selectedCharacterId,
          selectedStageLabel: role.selectedStage?.label ?? '',
          statusLabel: _planStatusForRole(role.sourceRoleId),
          confidence: _confidenceForRole(role.sourceRoleId),
        ),
    ],
    artist: artistMappings.isEmpty
        ? const StudioScriptPlanArtist()
        : StudioScriptPlanArtist(
            sourceLabel: artistMappings.first.sourceLabel,
            selectedArtistChainId: artistMappings.first.selectedArtistChainId,
          ),
    issues: _planIssues(),
    frameReviews: _frameReviews(),
    hasAiBackedPlan: aiSuggestions.any(
      (item) =>
          item.source == ScriptAiSuggestionSource.ai ||
          item.source == ScriptAiSuggestionSource.cache,
    ),
  );
}
```

Add helper stubs with concrete behavior:

```dart
String _planStatusForRole(String sourceRoleId) {
  final suggestion = aiSuggestions
      .where((item) => item.sourceRoleId == sourceRoleId)
      .firstOrNull;
  if (suggestion == null) return '本地';
  return switch (suggestion.source) {
    ScriptAiSuggestionSource.ai => 'AI',
    ScriptAiSuggestionSource.cache => '缓存',
    ScriptAiSuggestionSource.needsReview => '需处理',
    ScriptAiSuggestionSource.failed => '失败',
    ScriptAiSuggestionSource.local => '本地',
  };
}

double _confidenceForRole(String sourceRoleId) {
  return aiSuggestions
          .where((item) => item.sourceRoleId == sourceRoleId)
          .firstOrNull
          ?.confidence ??
      0;
}

List<StudioScriptPlanIssue> _planIssues() {
  return [
    for (final suggestion in aiSuggestions)
      if (suggestion.status == ScriptAiSuggestionStatus.needsReview ||
          suggestion.source == ScriptAiSuggestionSource.needsReview ||
          (suggestion.confidence > 0 && suggestion.confidence < 0.6))
        StudioScriptPlanIssue(
          id: 'issue-${suggestion.id}',
          kind: StudioScriptPlanIssueKind.lowConfidence,
          title: suggestion.displayName.isEmpty
              ? '低置信 AI 建议'
              : '低置信：${suggestion.displayName}',
          detail: suggestion.warnings.join(', '),
        ),
    for (final suggestion in aiSuggestions)
      if (suggestion.status == ScriptAiSuggestionStatus.failed ||
          suggestion.source == ScriptAiSuggestionSource.failed)
        StudioScriptPlanIssue(
          id: 'issue-${suggestion.id}',
          kind: StudioScriptPlanIssueKind.aiBatchFailed,
          title: 'AI 批次失败',
          detail: suggestion.rawResponse,
        ),
  ];
}
```

The `_frameReviews()` method is implemented in Task 5.

- [ ] **Step 4: Run focused test**

Run: `flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "recast plan projects AI suggestions and issues without exposing raw candidates first"`

Expected: PASS.

---

### Task 4: Replace Main Workspace With AI Recast Plan Panels

**Files:**
- Modify: `lib/ui/studio_script/widgets/studio_script_page.dart`
- Test: `test/ui/studio_script/studio_script_page_test.dart`

- [ ] **Step 1: Add widget test for default main workspace**

Add to `test/ui/studio_script/studio_script_page_test.dart`:

```dart
testWidgets('main workspace shows recast plan and keeps raw candidates in details', (tester) async {
  final viewModel = StudioScriptViewModel();
  await tester.runAsync(() async {
    await viewModel.importScriptPath(_fixturePath);
    await viewModel.analyzeScriptRoles();
  });

  await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
  await tester.pump();

  expect(find.byKey(const ValueKey('script-recast-plan-panel')), findsOneWidget);
  expect(find.byKey(const ValueKey('script-needs-attention-panel')), findsOneWidget);
  expect(find.byKey(const ValueKey('script-details-candidate-expansion')), findsOneWidget);
  expect(find.byKey(ValueKey('role-candidate-${viewModel.roleCandidates.first.id}')), findsNothing);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "main workspace shows recast plan and keeps raw candidates in details"`

Expected: FAIL because the current workspace renders `_RoleCandidatesPanel` directly.

- [ ] **Step 3: Replace `mainWorkspace` composition**

In `StudioScriptPage.build`, replace:

```dart
final mainWorkspace = Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    _ArtistMapping(viewModel: viewModel),
    const SizedBox(height: 16),
    _RoleMapping(viewModel: viewModel),
    const SizedBox(height: 16),
    _RoleCandidatesPanel(viewModel: viewModel),
  ],
);
```

with:

```dart
final mainWorkspace = _ScriptRecastPlanWorkspace(viewModel: viewModel);
```

Add `_ScriptRecastPlanWorkspace`:

```dart
class _ScriptRecastPlanWorkspace extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _ScriptRecastPlanWorkspace({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RecastPlanPanel(viewModel: viewModel),
        const SizedBox(height: 16),
        _NeedsAttentionPanel(viewModel: viewModel),
        const SizedBox(height: 16),
        _ScriptDetailsExpansion(viewModel: viewModel),
      ],
    );
  }
}
```

- [ ] **Step 4: Add plan, issue, and details widgets**

Add widgets below `_ArtistMapping` or near `_RoleCandidatesPanel`:

```dart
class _RecastPlanPanel extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _RecastPlanPanel({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final plan = viewModel.recastPlan;
    return _SectionPanel(
      key: const ValueKey('script-recast-plan-panel'),
      title: 'AI Recast 方案',
      icon: Icons.auto_awesome_outlined,
      children: [
        if (!plan.hasAiBackedPlan)
          const _EmptyHint(text: '导入剧本后先让 AI 分析，主方案会显示在这里。'),
        _ArtistMapping(viewModel: viewModel),
        const SizedBox(height: 12),
        _RoleMapping(viewModel: viewModel),
      ],
    );
  }
}

class _NeedsAttentionPanel extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _NeedsAttentionPanel({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final issues = viewModel.recastPlan.issues;
    return _SectionPanel(
      key: const ValueKey('script-needs-attention-panel'),
      title: '需要处理',
      icon: Icons.report_problem_outlined,
      children: [
        if (issues.isEmpty)
          const _EmptyHint(text: '暂无低置信、冲突或 AI 批次失败。'),
        for (final issue in issues)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.warning_amber_outlined),
            title: Text(issue.title),
            subtitle: issue.detail.isEmpty ? null : Text(issue.detail),
          ),
      ],
    );
  }
}

class _ScriptDetailsExpansion extends StatelessWidget {
  final StudioScriptViewModel viewModel;

  const _ScriptDetailsExpansion({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: const ValueKey('script-details-candidate-expansion'),
      title: const Text('详情：候选、证据与缓存'),
      initiallyExpanded: false,
      children: [
        _RoleCandidatesPanel(viewModel: viewModel),
      ],
    );
  }
}
```

- [ ] **Step 5: Run widget test**

Run: `flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "main workspace shows recast plan and keeps raw candidates in details"`

Expected: PASS.

---

### Task 5: Rebuild Keyframe Review With Positive and Negative Columns

**Files:**
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
- Modify: `lib/ui/studio_script/widgets/studio_script_page.dart`
- Test: `test/ui/studio_script/studio_script_page_test.dart`

- [ ] **Step 1: Add widget test for separate prompt columns**

Add to `test/ui/studio_script/studio_script_page_test.dart`:

```dart
testWidgets('keyframe review separates positive and negative tokens', (tester) async {
  final viewModel = StudioScriptViewModel();
  await tester.runAsync(() async {
    await viewModel.importScriptPath(_fixturePath);
  });

  await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
  await tester.pump();

  expect(find.byKey(const ValueKey('script-keyframe-positive-column')), findsWidgets);
  expect(find.byKey(const ValueKey('script-keyframe-negative-column')), findsWidgets);
  expect(find.text('正向源词'), findsWidgets);
  expect(find.text('负面源词'), findsWidgets);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "keyframe review separates positive and negative tokens"`

Expected: FAIL because the current keyframe preview groups do not split positive and negative columns.

- [ ] **Step 3: Build frame reviews in ViewModel**

In `_refreshRecastPlan`, set `frameReviews: _frameReviews()`.

Add:

```dart
List<StudioScriptFrameReview> _frameReviews() {
  final script = _script;
  if (script == null) return const [];
  final frame = script.frames
          .where((candidate) => candidate.index == _selectedFrameIndex)
          .firstOrNull ??
      script.frames.firstOrNull;
  if (frame == null || frame.parseStatus != ScriptFrameParseStatus.parsed) {
    return const [];
  }
  return [
    StudioScriptFrameReview(
      frameIndex: frame.index,
      title: frame.fileName,
      positiveTokens: _reviewTokensForText(
        [
          _frameBaseCaption(frame),
          ...frame.parsed.charCaptions,
        ].where((value) => value.trim().isNotEmpty).join(', '),
        negative: false,
      ),
      negativeTokens: _reviewTokensForText(
        [
          frame.parsed.negativeBase,
          ...frame.parsed.negativeCharCaptions,
        ].where((value) => value.trim().isNotEmpty).join(', '),
        negative: true,
      ),
    ),
  ];
}
```

Add tokenization helpers:

```dart
List<StudioScriptReviewToken> _reviewTokensForText(
  String text, {
  required bool negative,
}) {
  return [
    for (final tag in PromptTagProcessor.splitWorkshopTags(text))
      StudioScriptReviewToken(
        source: PromptTagProcessor.cleanTagDisplay(tag),
        category: _reviewCategoryForTag(tag, negative: negative),
        emphasis: _reviewEmphasisForTag(tag),
      ),
  ];
}

StudioScriptTokenCategory _reviewCategoryForTag(
  String tag, {
  required bool negative,
}) {
  final key = PromptTagProcessor.normalizeMatchKey(tag);
  if (negative) {
    if (key.contains('artist')) return StudioScriptTokenCategory.negativeArtist;
    if (key.contains('hand') || key.contains('body') || key.contains('anatomy')) {
      return StudioScriptTokenCategory.negativeBody;
    }
    if (key.contains('lowres') || key.contains('quality')) {
      return StudioScriptTokenCategory.negativeQuality;
    }
    return StudioScriptTokenCategory.negativeContent;
  }
  if (key.contains('artist')) return StudioScriptTokenCategory.artistChain;
  if (ScriptRecastRoleTagHeuristics.looksLikeOutfitEvidence(tag)) {
    return StudioScriptTokenCategory.upperClothing;
  }
  if (key.contains('standing') || key.contains('sitting')) {
    return StudioScriptTokenCategory.action;
  }
  if (key.contains('background') || key.contains('city') || key.contains('room')) {
    return StudioScriptTokenCategory.scene;
  }
  if (key.contains('quality') || key.contains('masterpiece')) {
    return StudioScriptTokenCategory.quality;
  }
  return StudioScriptTokenCategory.other;
}

StudioScriptTokenEmphasis _reviewEmphasisForTag(String tag) {
  final key = PromptTagProcessor.normalizeMatchKey(tag);
  for (final suggestion in aiSuggestions) {
    final values = [
      suggestion.displayName,
      suggestion.parts.identity,
      suggestion.parts.upperBody,
      suggestion.parts.lowerBody,
      suggestion.parts.upperClothing,
      suggestion.parts.lowerClothing,
      ...suggestion.evidence,
    ];
    if (values.any((value) => PromptTagProcessor.normalizeMatchKey(value) == key)) {
      return switch (suggestion.source) {
        ScriptAiSuggestionSource.cache => StudioScriptTokenEmphasis.cacheHit,
        ScriptAiSuggestionSource.ai => StudioScriptTokenEmphasis.aiRecognized,
        _ => StudioScriptTokenEmphasis.normal,
      };
    }
  }
  return StudioScriptTokenEmphasis.normal;
}
```

- [ ] **Step 4: Replace `_SelectedFrameCards` body**

In `_SelectedFrameCards`, render `viewModel.recastPlan.frameReviews` before falling back to old `selectedFramePreviews`.

Add `_KeyframeReviewPanel`, `_KeyframeTokenColumn`, and `_ReviewTokenChip`:

```dart
class _KeyframeReviewPanel extends StatelessWidget {
  final StudioScriptFrameReview review;

  const _KeyframeReviewPanel({required this.review});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final positive = _KeyframeTokenColumn(
          key: const ValueKey('script-keyframe-positive-column'),
          title: '正向源词',
          tokens: review.positiveTokens,
        );
        final negative = _KeyframeTokenColumn(
          key: const ValueKey('script-keyframe-negative-column'),
          title: '负面源词',
          tokens: review.negativeTokens,
        );
        return wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: positive),
                  const SizedBox(width: 12),
                  Expanded(child: negative),
                ],
              )
            : Column(children: [positive, const SizedBox(height: 12), negative]);
      },
    );
  }
}

class _KeyframeTokenColumn extends StatelessWidget {
  final String title;
  final List<StudioScriptReviewToken> tokens;

  const _KeyframeTokenColumn({
    super.key,
    required this.title,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final token in tokens) _ReviewTokenChip(token: token),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewTokenChip extends StatelessWidget {
  final StudioScriptReviewToken token;

  const _ReviewTokenChip({required this.token});

  @override
  Widget build(BuildContext context) {
    final color = _tokenCategoryColor(token.category);
    final strong = token.emphasis != StudioScriptTokenEmphasis.normal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(strong ? 42 : 20),
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(color: color.withAlpha(strong ? 230 : 120), width: strong ? 2 : 1),
      ),
      child: Text(token.source),
    );
  }
}
```

Add `_tokenCategoryColor` returning fixed colors from `StudioTokens` or `Colors`.

- [ ] **Step 5: Run keyframe widget test**

Run: `flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "keyframe review separates positive and negative tokens"`

Expected: PASS.

---

### Task 6: Regression Pass and Acceptance Checks

**Files:**
- Modify only if tests expose gaps.
- Test: existing Script Recast suites.

- [ ] **Step 1: Run data tests**

Run:

```powershell
flutter test test/data/studio/services/script_ai_batch_builder_test.dart test/data/studio/services/script_recast_analysis_service_test.dart test/data/studio/services/script_recast_parser_service_test.dart
```

Expected: all tests pass.

- [ ] **Step 2: Run Script page widget tests**

Run:

```powershell
flutter test test/ui/studio_script/studio_script_page_test.dart
```

Expected: all tests pass.

- [ ] **Step 3: Analyze touched files**

Run:

```powershell
dart analyze lib/data/studio/services/script_ai_batch_builder.dart lib/ui/studio_script/models/studio_script_recast_plan.dart lib/ui/studio_script/view_models/studio_script_viewmodel.dart lib/ui/studio_script/widgets/studio_script_page.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Manual visual check**

Run the app with the existing project command used for local Flutter testing. Open the Script page and verify:

- left asset drawer remains visible,
- top AI progress panel still appears during AI analysis,
- main workspace shows AI Recast plan first,
- raw candidates are hidden in Details by default,
- Needs Attention shows low-confidence or failed AI results,
- keyframe review has positive and negative prompt columns,
- token category colors differ,
- AI/cache hit tokens are more visually emphasized than ordinary classified tokens.

---

## Self-Review

- Spec coverage:
  - AI-first flow: Tasks 2 and 3.
  - Main workspace redesign: Task 4.
  - Preserve existing candidate tools: Task 4 details expansion.
  - Keyframe colors and positive/negative split: Task 5.
  - Regression testing: Task 6.
- Placeholder scan:
  - No placeholder markers or intentionally vague implementation steps remain.
- Type consistency:
  - `StudioScriptRecastPlan`, `StudioScriptPlanIssue`, and keyframe token classes are introduced in Task 1 and used consistently in Tasks 3-5.
