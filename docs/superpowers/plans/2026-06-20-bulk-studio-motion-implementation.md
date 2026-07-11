# Bulk Studio Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved B motion direction for dense Studio card grids and workbench multi-component screens.

**Architecture:** Extend the existing `lib/ui/studio_core/motion/` kit with two reusable wrappers: one for bounded repeated-item reveals and one for multi-region page choreography. Replace local duplicated upward fades in script shelves and asset cards, then apply layered workbench/drawer/chip motion without replaying animations on ordinary rebuilds.

**Tech Stack:** Flutter widgets, native animation primitives, `flutter_test`, existing Studio motion/theme tokens. No new package dependency.

---

### File Structure

- Create `lib/ui/studio_core/motion/studio_staggered_reveal.dart`
  Owns one-shot repeated-child reveal for visible batches. It computes bounded index or grid delays, respects reduced motion, and never changes final layout geometry.
- Create `lib/ui/studio_core/motion/studio_motion_sequence.dart`
  Owns large-region choreography for drawer/editor/controls/result areas using stable region directions and small delays.
- Modify `lib/ui/studio_shell/widgets/script_exhibition_room_page.dart`
  Replace `_ScriptShelfStreamEntry`'s raw `TweenAnimationBuilder` with `StudioStaggeredReveal`.
- Modify `lib/ui/studio_shell/widgets/asset_library_page.dart`
  Replace `_AssetCardStreamEntry`'s raw `TweenAnimationBuilder` with `StudioStaggeredReveal`.
- Modify `lib/ui/studio_workbench/widgets/workbench_asset_drawer.dart`
  Wrap drawer shell content, category lists, detail rows, expanded outfit rows, and prompt part cards with region/item reveals.
- Modify `lib/ui/studio_workbench/widgets/prompt_composer_panel.dart`
  Wrap inserted prompt blocks with a short item reveal.
- Modify `lib/ui/studio_workbench/widgets/workbench_single_image_console.dart`
  Wrap creative-input and generation-control regions with sequence regions; keep sliders and text editors stable.
- Modify `test/ui/studio_core/studio_motion_test.dart`
  Add core tests for stagger delay, reduced-motion final state, and sequence-region mapping.
- Modify `test/ui/studio_shell/script_exhibition_room_page_test.dart`
  Assert script shelf cards are wrapped by the new staggered reveal and remain findable/drag-safe.
- Modify `test/ui/studio_shell/asset_library_page_test.dart`
  Assert asset library cards use bounded stagger reveals where existing test fixtures already render cards.
- Modify `test/ui/studio_workbench/workbench_asset_drawer_test.dart`
  Assert drawer category/detail rows and expanded outfit rows use local reveals while existing drag/drop/hover behavior remains intact.

### Task 1: Core Motion Wrappers

**Files:**
- Create: `lib/ui/studio_core/motion/studio_staggered_reveal.dart`
- Create: `lib/ui/studio_core/motion/studio_motion_sequence.dart`
- Modify: `test/ui/studio_core/studio_motion_test.dart`

- [ ] **Step 1: Write failing tests for staggered reveal**

Append these tests to `test/ui/studio_core/studio_motion_test.dart` and add imports for the new files:

```dart
import 'package:novel_studio/ui/studio_core/motion/studio_motion_sequence.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_staggered_reveal.dart';
```

```dart
testWidgets('StudioStaggeredReveal renders final state when animations are disabled',
    (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: StudioStaggeredReveal(
          index: 6,
          columns: 3,
          child: Text('Card'),
        ),
      ),
    ),
  );

  final reveal = find.byType(StudioStaggeredReveal);
  final fade = tester.widget<FadeTransition>(
    find.descendant(of: reveal, matching: find.byType(FadeTransition)),
  );
  expect(find.text('Card'), findsOneWidget);
  expect(fade.opacity.value, 1);
});

testWidgets('StudioStaggeredReveal uses bounded grid delays', (tester) async {
  expect(
    StudioStaggeredReveal.delayFor(
      index: 8,
      columns: 4,
      itemDelay: const Duration(milliseconds: 24),
      maxStaggeredItems: 10,
    ),
    const Duration(milliseconds: 72),
  );
  expect(
    StudioStaggeredReveal.delayFor(
      index: 80,
      columns: 4,
      itemDelay: const Duration(milliseconds: 24),
      maxStaggeredItems: 10,
    ),
    const Duration(milliseconds: 216),
  );
});
```

- [ ] **Step 2: Write failing tests for sequence regions**

Append:

```dart
testWidgets('StudioMotionSequenceRegion maps drawer to horizontal entrance',
    (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: StudioMotionSequenceRegion(
        region: StudioMotionRegion.drawer,
        child: Text('Drawer'),
      ),
    ),
  );

  final reveal = tester.widget<StudioReveal>(
    find.descendant(
      of: find.byType(StudioMotionSequenceRegion),
      matching: find.byType(StudioReveal),
    ),
  );
  expect(reveal.beginOffset.dx, lessThan(0));
  expect(reveal.beginOffset.dy, 0);
});
```

- [ ] **Step 3: Verify RED**

Run:

```powershell
flutter test --no-pub test/ui/studio_core/studio_motion_test.dart -r expanded
```

Expected: fails because `studio_staggered_reveal.dart`, `studio_motion_sequence.dart`, `StudioStaggeredReveal`, and `StudioMotionSequenceRegion` do not exist.

- [ ] **Step 4: Implement `StudioStaggeredReveal`**

Create `lib/ui/studio_core/motion/studio_staggered_reveal.dart`:

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_scope.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_tokens.dart';

class StudioStaggeredReveal extends StatefulWidget {
  final int index;
  final int columns;
  final int maxStaggeredItems;
  final Duration duration;
  final Duration itemDelay;
  final Curve curve;
  final Offset beginOffset;
  final double beginScale;
  final AlignmentGeometry alignment;
  final Widget child;

  const StudioStaggeredReveal({
    super.key,
    required this.index,
    required this.child,
    this.columns = 1,
    this.maxStaggeredItems = 12,
    this.duration = StudioMotionTokens.medium,
    this.itemDelay = const Duration(milliseconds: 26),
    this.curve = StudioMotionTokens.showcaseCurve,
    this.beginOffset = const Offset(0, 0.045),
    this.beginScale = 0.965,
    this.alignment = Alignment.topCenter,
  });

  static Duration delayFor({
    required int index,
    required int columns,
    required Duration itemDelay,
    required int maxStaggeredItems,
  }) {
    final safeColumns = max(1, columns);
    final cappedIndex = max(0, min(index, max(0, maxStaggeredItems - 1)));
    final row = cappedIndex ~/ safeColumns;
    final column = cappedIndex % safeColumns;
    final waveStep = row + column;
    return Duration(
      microseconds: itemDelay.inMicroseconds * waveStep,
    );
  }

  @override
  State<StudioStaggeredReveal> createState() => _StudioStaggeredRevealState();
}

class _StudioStaggeredRevealState extends State<StudioStaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _totalDuration(),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = _totalDuration();
    if (StudioMotionScope.animationsDisabled(context)) {
      _controller.value = 1;
      _started = true;
      return;
    }
    if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant StudioStaggeredReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = _totalDuration();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMicroseconds = _totalDuration().inMicroseconds;
    final delay = _delay();
    final intervalStart = totalMicroseconds <= 0
        ? 0.0
        : delay.inMicroseconds / totalMicroseconds;
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        intervalStart.clamp(0.0, 1.0),
        1,
        curve: widget.curve,
      ),
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: widget.beginOffset,
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          alignment: widget.alignment,
          scale: Tween<double>(
            begin: widget.beginScale,
            end: 1,
          ).animate(curved),
          child: widget.child,
        ),
      ),
    );
  }

  Duration _delay() {
    return StudioStaggeredReveal.delayFor(
      index: widget.index,
      columns: widget.columns,
      itemDelay: widget.itemDelay,
      maxStaggeredItems: widget.maxStaggeredItems,
    );
  }

  Duration _totalDuration() {
    return Duration(
      microseconds: _delay().inMicroseconds + widget.duration.inMicroseconds,
    );
  }
}
```

- [ ] **Step 5: Implement `StudioMotionSequenceRegion`**

Create `lib/ui/studio_core/motion/studio_motion_sequence.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_tokens.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_reveal.dart';

enum StudioMotionRegion { panel, drawer, editor, controls, result }

class StudioMotionSequenceRegion extends StatelessWidget {
  final StudioMotionRegion region;
  final int order;
  final Widget child;

  const StudioMotionSequenceRegion({
    super.key,
    required this.region,
    required this.child,
    this.order = 0,
  });

  @override
  Widget build(BuildContext context) {
    return StudioReveal(
      delay: Duration(milliseconds: 54 * order.clamp(0, 6)),
      duration: StudioMotionTokens.medium,
      curve: StudioMotionTokens.showcaseCurve,
      beginScale: _beginScale,
      beginOffset: _beginOffset,
      child: child,
    );
  }

  Offset get _beginOffset {
    return switch (region) {
      StudioMotionRegion.drawer => const Offset(-0.035, 0),
      StudioMotionRegion.controls => const Offset(0.035, 0),
      StudioMotionRegion.result => const Offset(0, 0.032),
      StudioMotionRegion.editor => const Offset(0, 0.026),
      StudioMotionRegion.panel => const Offset(0, 0.022),
    };
  }

  double get _beginScale {
    return switch (region) {
      StudioMotionRegion.drawer => 0.992,
      StudioMotionRegion.controls => 0.992,
      StudioMotionRegion.result => 0.985,
      StudioMotionRegion.editor => 0.988,
      StudioMotionRegion.panel => 0.99,
    };
  }
}
```

- [ ] **Step 6: Verify GREEN**

Run:

```powershell
flutter test --no-pub test/ui/studio_core/studio_motion_test.dart -r expanded
```

Expected: all `studio_motion_test.dart` tests pass.

### Task 2: Dense Card Grid Reveals

**Files:**
- Modify: `lib/ui/studio_shell/widgets/script_exhibition_room_page.dart`
- Modify: `lib/ui/studio_shell/widgets/asset_library_page.dart`
- Modify: `test/ui/studio_shell/script_exhibition_room_page_test.dart`
- Modify: `test/ui/studio_shell/asset_library_page_test.dart`

- [ ] **Step 1: Write failing script shelf test**

In `test/ui/studio_shell/script_exhibition_room_page_test.dart`, import:

```dart
import 'package:novel_studio/ui/studio_core/motion/studio_staggered_reveal.dart';
```

Append:

```dart
testWidgets('script shelf cards use bounded row-column reveal wrappers',
    (tester) async {
  tester.view.physicalSize = const Size(1320, 980);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final viewModel = ScriptExhibitionRoomViewModel(
    loadScripts: () async => [_script()],
    loadProductionPlans: () async => const [],
    loadGalleryRecords: () async => const [],
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: StudioTheme.build(),
      home: ScriptExhibitionRoomPage(
        viewModel: viewModel,
        onSendToScriptWorkbench: (_) {},
        onSendToWorkbench: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();

  final card = find.byKey(
    const ValueKey('script-exhibition-script-card-script-1'),
  );
  final reveal = find.ancestor(
    of: card,
    matching: find.byType(StudioStaggeredReveal),
  );
  expect(reveal, findsOneWidget);
  expect(tester.widget<StudioStaggeredReveal>(reveal).columns, greaterThan(1));
});
```

- [ ] **Step 2: Write failing asset library card test**

In `test/ui/studio_shell/asset_library_page_test.dart`, import:

```dart
import 'package:novel_studio/ui/studio_core/motion/studio_staggered_reveal.dart';
```

Add a focused assertion to an existing test that renders `asset-card-character-char-1`, or append:

```dart
expect(
  find.ancestor(
    of: find.byKey(const ValueKey('asset-card-character-char-1')),
    matching: find.byType(StudioStaggeredReveal),
  ),
  findsOneWidget,
);
```

- [ ] **Step 3: Verify RED**

Run:

```powershell
flutter test --no-pub test/ui/studio_shell/script_exhibition_room_page_test.dart --name "script shelf cards use bounded row-column reveal wrappers" -r expanded
flutter test --no-pub test/ui/studio_shell/asset_library_page_test.dart --name "asset card" -r expanded
```

Expected: new wrapper assertions fail because the pages still use local `TweenAnimationBuilder` stream entries.

- [ ] **Step 4: Replace script shelf entry animation**

In `lib/ui/studio_shell/widgets/script_exhibition_room_page.dart`:

1. Add the import:

```dart
import 'package:novel_studio/ui/studio_core/motion/studio_staggered_reveal.dart';
```

2. Change `_ScriptShelfStreamEntry` to accept `columns`.

3. Replace the `TweenAnimationBuilder` body with:

```dart
return StudioStaggeredReveal(
  index: index,
  columns: columns,
  maxStaggeredItems: _scriptShelfWindowStep,
  duration: const Duration(milliseconds: 280),
  itemDelay: const Duration(milliseconds: 22),
  beginOffset: const Offset(0, 0.038),
  beginScale: 0.955,
  child: child,
);
```

4. At the callsite pass `columns: columns`.

- [ ] **Step 5: Replace asset card entry animation**

In `lib/ui/studio_shell/widgets/asset_library_page.dart`:

1. Add the import:

```dart
import 'package:novel_studio/ui/studio_core/motion/studio_staggered_reveal.dart';
```

2. Change `_AssetCardStreamEntry` to accept `columns`.

3. Replace the local `TweenAnimationBuilder` with:

```dart
return StudioStaggeredReveal(
  index: index,
  columns: columns,
  maxStaggeredItems: _AssetLibraryPageState._assetRenderBatchSize,
  duration: const Duration(milliseconds: 260),
  itemDelay: const Duration(milliseconds: 20),
  beginOffset: const Offset(0, 0.034),
  beginScale: 0.958,
  child: child,
);
```

4. At the callsite pass `columns: columns`.

- [ ] **Step 6: Verify GREEN**

Run:

```powershell
flutter test --no-pub test/ui/studio_shell/script_exhibition_room_page_test.dart --name "script shelf cards use bounded row-column reveal wrappers" -r expanded
flutter test --no-pub test/ui/studio_shell/asset_library_page_test.dart --name "asset library" -r expanded
```

Expected: the new wrapper tests pass and existing card finders remain valid.

### Task 3: Workbench Layered Drawer Motion

**Files:**
- Modify: `lib/ui/studio_workbench/widgets/workbench_asset_drawer.dart`
- Modify: `test/ui/studio_workbench/workbench_asset_drawer_test.dart`

- [ ] **Step 1: Write failing drawer reveal tests**

In `test/ui/studio_workbench/workbench_asset_drawer_test.dart`, import:

```dart
import 'package:novel_studio/ui/studio_core/motion/studio_motion_sequence.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_staggered_reveal.dart';
```

Add this test near the existing drawer motion test:

```dart
testWidgets('drawer category and detail content use layered local reveals',
    (tester) async {
  const snapshot = StudioAssetCatalogSnapshot(
    summary: StudioAssetCatalogSummary(
      characterCount: 0,
      outfitCount: 0,
      artistChainCount: 0,
      recipeCount: 0,
      tagCount: 2,
      recipeCountsByBlock: {},
      tagCountsByBlock: {'camera': 2},
    ),
    characters: [],
    artistChains: [],
    recipes: [],
    tags: [
      TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
      TagEntry(id: 'tag-2', tag: 'low angle', block: 'camera'),
    ],
  );
  final workbench = StudioWorkbenchAssetService(payloadConfig: _payload());

  await tester.pumpWidget(
    _studioApp(
      WorkbenchAssetDrawer(
        catalogService: _FakeCatalogService(snapshot),
        workbenchAssetService: workbench,
      ),
    ),
  );
  await tester.pump();

  final categoryCard =
      find.byKey(const ValueKey('workbench-drawer-category-tag'));
  expect(
    find.ancestor(
      of: categoryCard,
      matching: find.byType(StudioMotionSequenceRegion),
    ),
    findsOneWidget,
  );
  expect(
    find.ancestor(
      of: categoryCard,
      matching: find.byType(StudioStaggeredReveal),
    ),
    findsOneWidget,
  );

  await tester.tap(categoryCard);
  await tester.pump();
  await tester.pump();

  final detailRow =
      find.byKey(const ValueKey('workbench-drawer-card-tag-tag-1'));
  expect(
    find.ancestor(
      of: detailRow,
      matching: find.byType(StudioStaggeredReveal),
    ),
    findsOneWidget,
  );
});
```

- [ ] **Step 2: Verify RED**

Run:

```powershell
flutter test --no-pub test/ui/studio_workbench/workbench_asset_drawer_test.dart --name "drawer category and detail content use layered local reveals" -r expanded
```

Expected: fails because drawer cards are not wrapped with sequence/stagger reveals.

- [ ] **Step 3: Implement drawer category/detail wrappers**

In `lib/ui/studio_workbench/widgets/workbench_asset_drawer.dart`:

1. Add imports:

```dart
import 'package:novel_studio/ui/studio_core/motion/studio_motion_sequence.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_staggered_reveal.dart';
```

2. Wrap the successful drawer `Column` body in:

```dart
return StudioMotionSequenceRegion(
  region: StudioMotionRegion.drawer,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ...
    ],
  ),
);
```

3. Wrap each `_CategoryCard` in `_CategoryCardList`:

```dart
return StudioStaggeredReveal(
  index: index,
  columns: 1,
  maxStaggeredItems: 8,
  duration: const Duration(milliseconds: 220),
  itemDelay: const Duration(milliseconds: 30),
  beginOffset: const Offset(-0.035, 0.018),
  beginScale: 0.982,
  child: _CategoryCard(...),
);
```

4. Wrap each `_DrawerAssetRow` in `_CategoryDetail`:

```dart
return StudioStaggeredReveal(
  index: index,
  columns: 1,
  maxStaggeredItems: 10,
  duration: const Duration(milliseconds: 230),
  itemDelay: const Duration(milliseconds: 28),
  beginOffset: const Offset(-0.026, 0.022),
  beginScale: 0.978,
  child: _DrawerAssetRow(...),
);
```

- [ ] **Step 4: Wrap expanded outfit rows and prompt part cards**

In `_DrawerAssetRowState.build`, wrap each `_DrawerOutfitRow`:

```dart
for (var index = 0; index < widget.outfits.length; index++)
  StudioStaggeredReveal(
    key: _drawerStateKey('outfit-reveal', widget.outfits[index].itemKey),
    index: index,
    columns: 1,
    maxStaggeredItems: 8,
    duration: const Duration(milliseconds: 200),
    itemDelay: const Duration(milliseconds: 24),
    beginOffset: const Offset(0, 0.026),
    beginScale: 0.984,
    child: _DrawerOutfitRow(
      key: _drawerStateKey('outfit-row', widget.outfits[index].itemKey),
      outfit: widget.outfits[index],
    ),
  )
```

In `_DrawerOutfitRowState.build`, wrap each `_DrawerPromptPartCard` similarly with `duration: const Duration(milliseconds: 180)` and `beginScale: 0.99`.

- [ ] **Step 5: Verify GREEN**

Run:

```powershell
flutter test --no-pub test/ui/studio_workbench/workbench_asset_drawer_test.dart --name "drawer category and detail content use layered local reveals" -r expanded
flutter test --no-pub test/ui/studio_workbench/workbench_asset_drawer_test.dart --name "drawer cards can be dragged into a composer drop position" -r expanded
```

Expected: reveal test passes and drag/drop still passes.

### Task 4: Prompt Composer And Workbench Region Choreography

**Files:**
- Modify: `lib/ui/studio_workbench/widgets/prompt_composer_panel.dart`
- Modify: `lib/ui/studio_workbench/widgets/workbench_single_image_console.dart`
- Modify: `test/ui/studio_workbench/workbench_asset_drawer_test.dart`

- [ ] **Step 1: Write failing prompt block reveal assertion**

In `test/ui/studio_workbench/workbench_asset_drawer_test.dart`, extend the existing `drawer cards can be dragged into a composer drop position` test after the drag completes:

```dart
final promptBlock = find.byKey(ValueKey('prompt-block-editor-${workbench.fragments.single.id}'));
expect(
  find.ancestor(
    of: promptBlock,
    matching: find.byType(StudioStaggeredReveal),
  ),
  findsOneWidget,
);
```

- [ ] **Step 2: Verify RED**

Run:

```powershell
flutter test --no-pub test/ui/studio_workbench/workbench_asset_drawer_test.dart --name "drawer cards can be dragged into a composer drop position" -r expanded
```

Expected: fails on the new `StudioStaggeredReveal` ancestor assertion.

- [ ] **Step 3: Wrap prompt blocks**

In `lib/ui/studio_workbench/widgets/prompt_composer_panel.dart`:

1. Import `studio_staggered_reveal.dart`.
2. In the fragment loop, wrap `_PromptBlockDraggable` with:

```dart
StudioStaggeredReveal(
  key: ValueKey('prompt-block-reveal-${service.fragments[index].id}'),
  index: index,
  columns: 1,
  maxStaggeredItems: 8,
  duration: const Duration(milliseconds: 190),
  itemDelay: const Duration(milliseconds: 22),
  beginOffset: const Offset(0, 0.026),
  beginScale: 0.985,
  child: _PromptBlockDraggable(...),
)
```

Keep `_PromptDropTarget` outside this reveal so drag target geometry stays stable.

- [ ] **Step 4: Add region wrappers to single-image console**

In `lib/ui/studio_workbench/widgets/workbench_single_image_console.dart`:

1. Import `studio_motion_sequence.dart`.
2. Wrap `_CharacterSection`, `_ReferenceInputSection`, and `_PromptControlSection` in `WorkbenchCreativeInputsPanel` with `StudioMotionSequenceRegion(region: StudioMotionRegion.editor, order: 0/1/2, child: ...)`.
3. Wrap the console's `_ExecutionSection` with `StudioMotionSequenceRegion(region: StudioMotionRegion.controls, order: 0, child: ...)`.
4. Do not wrap individual sliders, size chips, text fields, or model menus.

- [ ] **Step 5: Verify GREEN**

Run:

```powershell
flutter test --no-pub test/ui/studio_workbench/workbench_asset_drawer_test.dart --name "drawer cards can be dragged into a composer drop position" -r expanded
flutter test --no-pub test/ui/studio_workbench/workbench_asset_drawer_test.dart --name "workbench character cards use hover motion surfaces" -r expanded
```

Expected: prompt reveal assertion passes and hover motion still passes.

### Task 5: Focused Verification

**Files:**
- No new production files beyond Tasks 1-4.

- [ ] **Step 1: Run core motion tests**

```powershell
flutter test --no-pub test/ui/studio_core/studio_motion_test.dart -r expanded
```

Expected: all tests pass.

- [ ] **Step 2: Run changed page tests**

```powershell
flutter test --no-pub test/ui/studio_shell/script_exhibition_room_page_test.dart --name "script shelf cards use bounded row-column reveal wrappers" -r expanded
flutter test --no-pub test/ui/studio_workbench/workbench_asset_drawer_test.dart --name "drawer category and detail content use layered local reveals" -r expanded
flutter test --no-pub test/ui/studio_workbench/workbench_asset_drawer_test.dart --name "drawer cards can be dragged into a composer drop position" -r expanded
```

Expected: all targeted tests pass.

- [ ] **Step 3: Run analyzer on changed code**

```powershell
flutter analyze --no-pub
```

Expected: no new analyzer errors from the motion work.

## Notes

Project Beads memory says git workflow is stealth mode, so this plan intentionally omits commit steps. Do not create branches, stage, commit, or push unless the user asks.
