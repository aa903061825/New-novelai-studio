# Proposed Failure Pattern: Workbench Asset Drawer Return Motion

## Context

- Area: `WorkbenchAssetDrawer` in the generation/workbench UI.
- Date proposed: 2026-06-26.
- Status: proposed after local verification, not yet accepted into canonical project context.

## Pattern

When a drawer page uses a push-style `AnimatedSwitcher` plus per-item staggered reveal, returning from detail to the category list can replay multiple opacity animations on the first frame. Users perceive this as a brief flash or ghosted content. Separately, hover outlines can still look clipped even with list padding when the shared interactive surface clips its own hover chrome.

## Repair

- Do not wrap the workbench asset drawer body in push transition motion; keep only the local list reveal.
- Allow staggered reveal children to mount already revealed for return navigation.
- Let interactive hover chrome paint outside the surface bounds, and reserve hover inset on asset drawer lists so top-row outlines have room inside the viewport.

## Verification

- `flutter test --no-pub test/ui/studio_workbench/workbench_asset_drawer_test.dart --reporter expanded`
- `flutter test --no-pub test/ui/studio_core/studio_motion_test.dart --reporter expanded`
- `flutter test --no-pub test/ui/generation_page/generation_page_workbench_layout_test.dart --reporter expanded`
- `flutter analyze --no-pub lib/ui/studio_core/motion/studio_drawer_motion.dart lib/ui/studio_core/motion/studio_staggered_reveal.dart lib/ui/studio_core/motion/studio_interactive_surface.dart lib/ui/studio_workbench/widgets/workbench_asset_drawer.dart test/ui/studio_core/studio_motion_test.dart test/ui/studio_workbench/workbench_asset_drawer_test.dart`
