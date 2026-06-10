# Script Exhibition Room IA Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the approved Studio navigation structure with an independent Script Exhibition Room entry and move the knowledge/rules workspace under Settings.

**Architecture:** Keep the current Script page as the Script Workbench and introduce a separate shell page for the Script Exhibition Room. Reuse the existing `StudioToolsPage` as the Settings knowledge/rules section so the current long-term knowledge, filter rules, translation cache, and AI cache affordances remain in one maintained implementation.

**Tech Stack:** Flutter widget UI, GetIt service lookup, existing Studio design tokens, widget tests with `flutter test`.

---

### Task 1: Lock Navigation IA With Tests

**Files:**
- Modify: `test/ui/navigation/novel_studio_navigation_test.dart`

- [ ] **Step 1: Write the failing navigation order test**

Replace the current product-area key loop with an ordered desktop nav assertion:

```dart
final navKeys = find
    .byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          ((widget.key! as ValueKey<String>).value).startsWith('studio-nav-'),
    )
    .evaluate()
    .map((element) => (element.widget.key! as ValueKey<String>).value)
    .toList();

expect(navKeys, [
  'studio-nav-home',
  'studio-nav-workbench',
  'studio-nav-assets',
  'studio-nav-script',
  'studio-nav-batch',
  'studio-nav-scriptExhibition',
  'studio-nav-gallery',
  'studio-nav-settings',
]);
expect(find.byKey(const ValueKey('studio-nav-tools')), findsNothing);
```

- [ ] **Step 2: Replace the old tools navigation test**

Tap Settings and assert that the knowledge/rules section lives there:

```dart
await tester.tap(find.byKey(const ValueKey('studio-nav-settings')).first);
await tester.pumpAndSettle();

expect(find.byKey(const ValueKey('settings-knowledge-and-rules-section')),
    findsOneWidget);
expect(find.byKey(const ValueKey('studio-tool-card-knowledge-base')),
    findsOneWidget);
expect(find.byKey(const ValueKey('studio-tools-open-script-review')),
    findsNothing);
```

- [ ] **Step 3: Add a Script Exhibition entry test**

Tap the new navigation item and assert the standalone page appears:

```dart
await tester.tap(
  find.byKey(const ValueKey('studio-nav-scriptExhibition')).first,
);
await tester.pumpAndSettle();

expect(find.byKey(const ValueKey('script-exhibition-room-page')),
    findsOneWidget);
expect(find.text('剧本展览室'), findsWidgets);
expect(find.text('发送到剧本工作台'), findsOneWidget);
```

- [ ] **Step 4: Run the navigation test and verify RED**

Run:

```bash
flutter test test/ui/navigation/novel_studio_navigation_test.dart
```

Expected: fails because `studio-nav-scriptExhibition` and the Settings knowledge section do not exist yet.

### Task 2: Implement Shell Routing

**Files:**
- Modify: `lib/ui/studio_shell/models/studio_shell_section.dart`
- Modify: `lib/ui/studio_shell/widgets/studio_shell_view.dart`
- Create: `lib/ui/studio_shell/widgets/script_exhibition_room_page.dart`

- [ ] **Step 1: Add the enum value**

Add `scriptExhibition` after `batch` in `StudioShellSection`.

- [ ] **Step 2: Add the route and destination**

In `StudioShellView`, import `script_exhibition_room_page.dart`, add a switch branch returning `ScriptExhibitionRoomPage(onSendToScriptWorkbench: () => _changeSection(StudioShellSection.script))`, and set `_destinations` to:

```dart
const _destinations = [
  _StudioDestination(
    section: StudioShellSection.home,
    icon: Icons.home_outlined,
    label: '主页',
  ),
  _StudioDestination(
    section: StudioShellSection.workbench,
    icon: Icons.dashboard_customize_outlined,
    label: '工作台',
  ),
  _StudioDestination(
    section: StudioShellSection.assets,
    icon: Icons.inventory_2_outlined,
    label: '素材库',
  ),
  _StudioDestination(
    section: StudioShellSection.script,
    icon: Icons.document_scanner_outlined,
    label: '剧本工作台',
  ),
  _StudioDestination(
    section: StudioShellSection.batch,
    icon: Icons.account_tree_outlined,
    label: '批量产线',
  ),
  _StudioDestination(
    section: StudioShellSection.scriptExhibition,
    icon: Icons.auto_stories_outlined,
    label: '剧本展览室',
  ),
  _StudioDestination(
    section: StudioShellSection.gallery,
    icon: Icons.photo_library_outlined,
    label: '画廊',
  ),
  _StudioDestination(
    section: StudioShellSection.settings,
    icon: Icons.tune,
    label: '设置',
  ),
];
```

- [ ] **Step 3: Create the minimal exhibition room page**

Create a Studio-styled page with key `script-exhibition-room-page`, title `剧本展览室`, a short description, placeholder category cards, and one `发送到剧本工作台` button wired to `onSendToScriptWorkbench`.

- [ ] **Step 4: Run the navigation test and verify partial GREEN**

Run:

```bash
flutter test test/ui/navigation/novel_studio_navigation_test.dart
```

Expected: only the Settings knowledge/rules assertion still fails if Task 3 is not implemented.

### Task 3: Move Knowledge And Rules Under Settings

**Files:**
- Modify: `lib/ui/settings_page/widgets/settings_page_view.dart`
- Modify: `lib/ui/studio_shell/widgets/studio_shell_view.dart`

- [ ] **Step 1: Let Settings accept an optional knowledge section**

Add a nullable `Widget? knowledgeAndRulesSection` constructor parameter to `SettingsPageView`.

- [ ] **Step 2: Render the section in Settings**

Insert the section after AI settings, wrapped in a `KeyedSubtree` with key `settings-knowledge-and-rules-section`.

- [ ] **Step 3: Pass the existing tools page from the shell**

In the Settings branch of `StudioShellView`, build `SettingsPageView(knowledgeAndRulesSection: _buildKnowledgeAndRulesPage())`. Extract the old `StudioShellSection.tools` branch content into `_buildKnowledgeAndRulesPage()` and keep the old enum branch returning the same widget for non-navigation callers.

- [ ] **Step 4: Run targeted tests and verify GREEN**

Run:

```bash
flutter test test/ui/navigation/novel_studio_navigation_test.dart test/ui/settings_page/settings_page_view_widget_test.dart test/ui/studio_shell/studio_tools_page_test.dart
```

Expected: all targeted tests pass.

### Task 4: Format And Record Status

**Files:**
- Format modified Dart files.
- Update Beads notes for `NAI_NEW-pnjz`.

- [ ] **Step 1: Format**

Run:

```bash
dart format lib/ui/studio_shell/models/studio_shell_section.dart lib/ui/studio_shell/widgets/studio_shell_view.dart lib/ui/studio_shell/widgets/script_exhibition_room_page.dart lib/ui/settings_page/widgets/settings_page_view.dart test/ui/navigation/novel_studio_navigation_test.dart
```

- [ ] **Step 2: Final verification**

Run:

```bash
flutter test test/ui/navigation/novel_studio_navigation_test.dart test/ui/settings_page/settings_page_view_widget_test.dart test/ui/studio_shell/studio_tools_page_test.dart
```

Expected: all targeted tests pass.

- [ ] **Step 3: Update task tracker**

Run:

```bash
bd update NAI_NEW-pnjz --notes="First implementation slice done: Studio nav now follows the approved order, Script Exhibition Room has an independent shell entry, Script page is labeled Script Workbench, and Knowledge/Rules are reachable under Settings. Remaining data aggregation, script version grouping, waterfall cards, and send-to-workbench payload behavior still need follow-up slices."
```

### Task 5: Aggregate Real Exhibition Data

**Files:**
- Create: `lib/ui/studio_shell/view_models/script_exhibition_room_viewmodel.dart`
- Test: `test/ui/studio_shell/script_exhibition_room_viewmodel_test.dart`

- [ ] **Step 1: Write the failing aggregation test**

Create a view model test that loads one tokenizer script, one production plan, and one gallery record. Assert that the resulting snapshot has one script, versions for `原始剧本`, the production batch, and `已收纳`, and items ordered by `frameIndex`.

- [ ] **Step 2: Verify RED**

Run:

```bash
flutter test test/ui/studio_shell/script_exhibition_room_viewmodel_test.dart
```

Expected: FAIL because the view model does not exist.

- [ ] **Step 3: Implement the view model**

Build immutable view model data classes for category, script, version, and image item. Load scripts from `TokenizerScriptService`, production plans from `ProductionQueueService`, and gallery records from `StudioGalleryService`, then group by script id/name.

- [ ] **Step 4: Verify GREEN**

Run the same test and expect PASS.

### Task 6: Build Browsable Exhibition UI

**Files:**
- Modify: `lib/ui/studio_shell/widgets/script_exhibition_room_page.dart`
- Test: `test/ui/studio_shell/script_exhibition_room_page_test.dart`

- [ ] **Step 1: Write the failing interaction test**

Pump the page with fake loaders, wait for data, click a script shelf card, select a generated batch version, click an image card, assert a full-screen preview dialog appears, then click `发送到剧本工作台` and assert the emitted focus contains the script id and frame index.

- [ ] **Step 2: Verify RED**

Run:

```bash
flutter test test/ui/studio_shell/script_exhibition_room_page_test.dart
```

Expected: FAIL because the placeholder UI has no real data or dialog.

- [ ] **Step 3: Replace the placeholder page**

Render real loading/error/empty states, horizontal category cards, script shelf, detail mode with version chips, ordered waterfall cards, and a full-screen image preview dialog.

- [ ] **Step 4: Verify GREEN**

Run the same test and expect PASS.

### Task 7: Wire Shell Handoff

**Files:**
- Modify: `lib/ui/studio_shell/widgets/studio_shell_view.dart`
- Test: `test/ui/navigation/novel_studio_navigation_test.dart`

- [ ] **Step 1: Add a navigation handoff test**

Open the Script Exhibition Room from the shell, tap a script card send action, and assert the shell navigates to the Script Workbench page.

- [ ] **Step 2: Implement handoff**

Pass `TokenizerScriptService`, `ProductionQueueService`, and `StudioGalleryService` into the room view model. On send, switch to Script Workbench, import `focus.sourceFolder` when available, and call `selectFrame(focus.frameIndex)` when available.

- [ ] **Step 3: Verify targeted tests**

Run:

```bash
flutter test test/ui/navigation/novel_studio_navigation_test.dart test/ui/studio_shell/script_exhibition_room_viewmodel_test.dart test/ui/studio_shell/script_exhibition_room_page_test.dart
```

Expected: PASS.
