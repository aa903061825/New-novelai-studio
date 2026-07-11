# Startup Script Workbench Open Request

## Purpose

Allow local automation and agent workflows to launch Novel Studio directly into the Script Workbench for a cached Script Recast script.

## Entry Points

- `Novel_Studio.exe --open-script <scriptId>`
- Optional source folder override: `--open-script-source <folder>` or `--script-source=<folder>`
- Optional frame focus: `--open-script-frame <frameIndex>` or `--script-frame=<frameIndex>`
- Alias for script id: `--script-id` or `--open-script-id`

## Key Files

- `lib/ui/studio_shell/models/studio_startup_open_request.dart`
- `lib/main.dart`
- `lib/ui/navigation/widgets/navigation_view.dart`
- `lib/ui/studio_shell/widgets/studio_shell_view.dart`
- `test/ui/studio_shell/studio_startup_open_request_test.dart`
- `test/ui/navigation/novel_studio_navigation_test.dart`

## Behavior

At startup, command line arguments are parsed into `StudioStartupOpenRequest`.
When a request is present, `StudioShellView` switches to the script section and
calls the existing `StudioScriptViewModel.openScriptFromExhibition` path. If no
source folder is provided, it resolves the source from the local recast cache by
script id and never invokes Script AI analysis.

## Verification

- `flutter test test\ui\studio_shell\studio_startup_open_request_test.dart`
- `flutter test test\ui\navigation\novel_studio_navigation_test.dart --plain-name "startup open request opens cached script in script workbench"`
- `dart analyze lib\ui\studio_shell\models\studio_startup_open_request.dart lib\ui\navigation\widgets\navigation_view.dart lib\ui\studio_shell\widgets\studio_shell_view.dart lib\main.dart test\ui\studio_shell\studio_startup_open_request_test.dart`
- `flutter build windows --debug`
- Manual launch: `build\windows\x64\runner\Debug\Novel_Studio.exe --open-script script-01c52bffa4037de8`

## Last Verified

2026-07-07
