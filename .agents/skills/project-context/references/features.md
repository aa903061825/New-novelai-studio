# Accepted Features

### Restrained React Bits-inspired home motion

- Purpose: Add a lightweight pointer spotlight to the home hero and count-up feedback to numeric overview metrics while preserving native Flutter branding, business logic, and reduced-motion behavior.
- Entry points:
  - `StudioHomePage._HomeHero`
  - `StudioHomePage._MetricStrip`
  - `StudioMetricCard.animateNumericValue`
- Key files:
  - `lib/ui/studio_core/motion/studio_spotlight_surface.dart`
  - `lib/ui/studio_core/motion/studio_animated_number.dart`
  - `lib/ui/studio_core/widgets/studio_metric_card.dart`
  - `lib/ui/studio_shell/widgets/studio_home_page.dart`
  - `test/ui/studio_core/studio_motion_test.dart`
- How to use: Use StudioSpotlightSurface only around a focal dark surface; set StudioMetricCard.animateNumericValue only for stable dashboard counts; keep dense editors, galleries, and batch controls free from additional decorative effects.
- Verification:
  - `flutter analyze --no-pub`
  - `flutter test --no-pub test/ui/studio_core/studio_motion_test.dart test/ui/studio_core/studio_theme_test.dart test/ui/studio_core/studio_visual_acceptance_contract_test.dart -r expanded`
  - `flutter build windows --debug`
  - Live desktop and 860px compact visual checks.
- Last verified: 2026-07-13

### Persistence and async-state safety repairs

- Purpose: preserve existing workspace/config data and prevent stale asynchronous work from overwriting or notifying newer/disposed UI state.
- Entry points: `StudioDataService.initializeAt`, `ConfigService` save/delete methods, `ProductionExecutorService.runPlan`, `StudioScriptViewModel` import/open/send methods, and Asset Library character/outfit mutations.
- Key files: `lib/data/studio/studio_data_service.dart`, `lib/data/workspace/workspace_service.dart`, `lib/data/services/config_service.dart`, `lib/data/studio/services/production_executor_service.dart`, `lib/ui/studio_batch/view_models/production_queue_viewmodel.dart`, `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`, and `lib/ui/studio_shell/widgets/asset_library_page.dart`.
- Invariants: recover a missing manifest before legacy-root comparison; distinguish queue continuation from accepting an in-flight result; bind script operations to generation, script identity, and disposal state; serialize every character/outfit write against the latest working catalog, including after widget disposal; commit workspace JSON and Codex JSONL through per-relative-path ordered atomic replacement; discard Script Exhibition detail loads from an older full-load generation.
- Compatibility: Script Exhibition intentionally continues deleting unreferenced images under configured generated roots.
- Verification: focused regression suites for workspace/config/executor/script lifecycle, the full Production Queue ViewModel suite, the full Asset Library page suite, `flutter analyze --no-pub`, MJS syntax checks, and workflow YAML parsing.
- Last verified: 2026-07-11.
