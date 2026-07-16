# Script Exhibition Main-Navigation Entry Reset

## Purpose

Prevent a cached Script Exhibition detail selection from making a fresh entry
from Batch Production look as though the room contains only that version's few
images.

## Failing Mechanism

- `StudioShellView` keeps Script Exhibition mounted and cached across section
  changes.
- The production workspace uses lightweight exhibition summaries, so reloading
  the room preserves a still-valid `selectedScriptId` and `selectedVersionId`.
- Re-entering from Batch Production therefore renders the old nested detail
  instead of the top-level script shelf even though the complete summary list
  is still loaded.

## Entry Points

- `StudioShellView._changeSection`
- `ScriptExhibitionRoomViewModel.clearScriptSelection`

## Key Files

- `lib/ui/studio_shell/widgets/studio_shell_view.dart`
- `test/ui/navigation/novel_studio_navigation_test.dart`

## Verification

- `flutter test test/ui/navigation/novel_studio_navigation_test.dart --plain-name "script exhibition re-entry from batch returns to the script shelf"`
- `flutter test test/ui/navigation/novel_studio_navigation_test.dart --plain-name "script exhibition reloads when re-entering cached page"`
- `flutter test test/ui/studio_shell/script_exhibition_room_viewmodel_test.dart --plain-name "ignores stale summary detail after a newer full load publishes"`
- `flutter analyze --no-pub`

Last verified locally: 2026-07-13. Pending user acceptance in the desktop app.
