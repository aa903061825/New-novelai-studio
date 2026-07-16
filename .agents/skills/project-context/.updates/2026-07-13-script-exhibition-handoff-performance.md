# Script Exhibition Handoff Performance

## Purpose

Keep the Script Exhibition to Script Workbench handoff responsive for large
cached scripts without weakening source-term frame-evidence repair or allowing
deferred asset refreshes to overwrite newer workbench edits.

## Failing Mechanism

- Targeted cache I/O was already fast and did not scan the full cache
  directory.
- Cache application repaired AI-extraction terms and mapping terms separately.
  Every term rescanned every parsed frame and split/normalized the same long
  captions again, producing term x frame x caption-tag work twice.
- The handoff mounted the previous full workbench before starting the new open,
  so a stale large workbench was built on the click frame.
- Deferred asset refresh reapplied the original cache, repeating repair work
  and risking replacement of edits made after the fast open completed.

## Repair

- Build a per-script source-term frame index that normalizes each unique
  caption once, keeps the existing role/scene scope rules, and memoizes term
  lookups shared by extraction and mapping repair.
- Start `openScriptFromExhibition` synchronously before switching sections so
  the workbench mounts in its lightweight import-progress state.
- Skip deferred asset reload when assets are already available and refresh the
  current mapping after the first asset load instead of reapplying the original
  cache.

## Entry Points

- `StudioScriptViewModel.openScriptFromExhibition`
- `StudioScriptViewModel._sourceFrameIndexesForPromptTerm`
- `StudioScriptViewModel._scheduleDeferredAssetRefresh`
- `StudioShellView._openScriptExhibitionFocus`

## Key Files

- `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
- `lib/ui/studio_shell/widgets/studio_shell_view.dart`
- `test/ui/studio_script/script_exhibition_handoff_performance_test.dart`
- `test/ui/studio_script/studio_script_page_test.dart`
- `test/ui/navigation/novel_studio_navigation_test.dart`

## Local Benchmark

- Dataset: existing 11 MiB cache with 447 frames from a 335-file, roughly
  776 MiB workspace cache directory.
- Targeted cache read: about 0.24 seconds before and after.
- Main-thread cache apply plus script derivation: about 11.6 seconds before,
  about 1.9 seconds after.
- Synthetic mechanism regression: about 12.8 seconds before, about 0.26
  seconds after in the final focused run.

## Verification

- `flutter test --no-pub test/ui/studio_script/script_exhibition_handoff_performance_test.dart -r expanded`
- Focused Script Workbench cache-open, frame-evidence, and deferred-asset tests
  in `test/ui/studio_script/studio_script_page_test.dart`.
- Focused Script Exhibition handoff and mount-order tests in
  `test/ui/navigation/novel_studio_navigation_test.dart`.
- `flutter analyze --no-pub`
- `git diff --check`

Full-file Script Workbench and navigation runs were also attempted, but the
large suites did not finish inside the local 5-minute and 3-minute command
limits; no failing assertion was emitted before timeout.

Last verified locally: 2026-07-13. Pending user acceptance in the desktop app.
