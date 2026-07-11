# Studio Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the approved Studio motion kit and first-pass animation polish.

**Architecture:** Add a small `lib/ui/studio_core/motion/` layer, then integrate it into the Studio shell and selected showcase/dense surfaces. Motion remains native Flutter, token-driven, layout-stable, and respects reduced-motion settings.

**Tech Stack:** Flutter, Material widgets, `flutter_test`, existing Studio tokens/widgets.

---

### Task 1: Motion Core

**Files:**
- Create: `lib/ui/studio_core/motion/studio_motion_tokens.dart`
- Create: `lib/ui/studio_core/motion/studio_motion_scope.dart`
- Create: `lib/ui/studio_core/motion/studio_reveal.dart`
- Create: `lib/ui/studio_core/motion/studio_page_transition.dart`
- Create: `lib/ui/studio_core/motion/studio_interactive_surface.dart`
- Test: `test/ui/studio_core/studio_motion_test.dart`

- [ ] **Step 1: Write failing tests**

Create tests that assert:

```dart
testWidgets('StudioReveal renders final state when animations are disabled',
    (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: StudioReveal(
          child: Text('Ready'),
        ),
      ),
    ),
  );

  expect(find.text('Ready'), findsOneWidget);
  final fade = tester.widget<FadeTransition>(find.byType(FadeTransition));
  expect(fade.opacity.value, 1);
});

testWidgets('StudioPageTransition switches content by keyed child',
    (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: StudioPageTransition(
        transitionKey: ValueKey('one'),
        child: Text('One'),
      ),
    ),
  );
  await tester.pumpWidget(
    const MaterialApp(
      home: StudioPageTransition(
        transitionKey: ValueKey('two'),
        child: Text('Two'),
      ),
    ),
  );

  expect(find.text('Two'), findsOneWidget);
});

testWidgets('StudioInteractiveSurface only lifts while hovered or pressed',
    (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Center(
        child: StudioInteractiveSurface(
          child: SizedBox(width: 100, height: 40),
        ),
      ),
    ),
  );

  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: tester.getCenter(find.byType(SizedBox)));
  await tester.pump(StudioMotionTokens.fast);

  final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
  expect(scale.scale, greaterThan(1));
});
```

- [ ] **Step 2: Verify RED**

Run:

```powershell
flutter test --no-pub test/ui/studio_core/studio_motion_test.dart -r expanded
```

Expected: fail because the motion classes do not exist.

- [ ] **Step 3: Implement minimal motion components**

Use:

```dart
class StudioMotionTokens {
  static const fast = Duration(milliseconds: 140);
  static const medium = Duration(milliseconds: 240);
  static const expressive = Duration(milliseconds: 420);
  static const utilityCurve = Curves.easeOutCubic;
  static const expressiveCurve = Curves.easeOutBack;
}
```

Implement reveal, transition, and interactive surface wrappers with `MediaQuery.disableAnimations`.

- [ ] **Step 4: Verify GREEN**

Run the same test command and ensure it passes.

### Task 2: Shell And Home Integration

**Files:**
- Modify: `lib/ui/studio_shell/widgets/studio_shell_view.dart`
- Modify: `lib/ui/studio_shell/widgets/studio_home_page.dart`
- Test: `test/ui/navigation/novel_studio_navigation_test.dart`

- [ ] **Step 1: Write failing tests**

Add assertions that shell pages are wrapped by `StudioPageTransition`, home content remains findable, and navigation still changes the current section.

- [ ] **Step 2: Verify RED**

Run:

```powershell
flutter test --no-pub test/ui/navigation/novel_studio_navigation_test.dart -r expanded
```

Expected: the new motion-wrapper assertion fails.

- [ ] **Step 3: Implement shell/home motion**

Wrap page content in `StudioPageTransition`, with showcase intensity for Home/Assets/Gallery/Settings and dense intensity for Workbench/Script/Batch.

Wrap Home hero, metric strip, and lower panels in `StudioReveal`.

- [ ] **Step 4: Verify GREEN**

Run the navigation test again.

### Task 3: Showcase Preview Integration

**Files:**
- Modify: `lib/ui/studio_core/widgets/studio_generated_image_gallery.dart`
- Modify: `lib/ui/studio_shell/widgets/asset_library_page.dart`
- Test: `test/ui/studio_core/studio_generated_image_gallery_test.dart`
- Test: `test/ui/studio_shell/asset_library_page_test.dart`

- [ ] **Step 1: Write failing tests**

Add tests for card hover/lift wrapper and asset detail preview interactive surface without changing click targets.

- [ ] **Step 2: Verify RED**

Run:

```powershell
flutter test --no-pub test/ui/studio_core/studio_generated_image_gallery_test.dart -r expanded
flutter test --no-pub test/ui/studio_shell/asset_library_page_test.dart -r expanded
```

Expected: motion-wrapper assertions fail before implementation.

- [ ] **Step 3: Implement showcase integration**

Use `StudioInteractiveSurface` around generated image cards and high-impact asset detail preview surfaces. Do not animate every waterfall asset on load.

- [ ] **Step 4: Verify GREEN**

Run the two test files again.

### Task 4: Script Workbench V2.3 Integration

**Files:**
- Modify: `lib/ui/studio_script/widgets/studio_script_page.dart`
- Test: `test/ui/studio_script/studio_script_page_test.dart`

- [ ] **Step 1: Write failing tests**

Add targeted tests that assert Script Workbench motion wrappers exist but do not include idle repeat/loop controllers by default, and drag/drop or hover feedback remains event-triggered.

- [ ] **Step 2: Verify RED**

Run:

```powershell
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart -r expanded
```

Expected: the new wrapper assertions fail.

- [ ] **Step 3: Implement V2.3 event-triggered motion**

Use `StudioInteractiveSurface` on drawer cards and selected mapping/drop surfaces. Avoid idle breathing, looping glow, and continuously floating cards.

- [ ] **Step 4: Verify GREEN**

Run the script page test again.

### Task 5: Final Verification

**Files:**
- No new production files beyond Tasks 1-4.

- [ ] **Step 1: Run focused core checks**

```powershell
flutter test --no-pub test/ui/studio_core/studio_motion_test.dart -r expanded
flutter test --no-pub test/ui/studio_core/studio_theme_test.dart -r expanded
flutter test --no-pub test/ui/studio_core/studio_visual_acceptance_contract_test.dart -r expanded
```

- [ ] **Step 2: Run page-specific checks**

```powershell
flutter test --no-pub test/ui/navigation/novel_studio_navigation_test.dart -r expanded
flutter test --no-pub test/ui/studio_core/studio_generated_image_gallery_test.dart -r expanded
flutter test --no-pub test/ui/studio_shell/asset_library_page_test.dart -r expanded
flutter test --no-pub test/ui/studio_script/studio_script_page_test.dart -r expanded
```

- [ ] **Step 3: Run analyzer**

```powershell
flutter analyze --no-pub
```

Expected: no new errors from the motion work.

## Notes

The project Beads memory says git workflow is stealth mode, so this plan does not require commits despite the generic planning skill recommending frequent commits.
