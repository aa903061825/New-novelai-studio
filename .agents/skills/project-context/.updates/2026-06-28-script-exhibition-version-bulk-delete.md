# Script Exhibition Version Bulk Delete

Status: proposed, pending user acceptance
Date: 2026-06-28

## Purpose

Script Exhibition detail view now supports selecting multiple deletable version chips and deleting them in one confirmation flow.

## Entry Points

- `ScriptExhibitionRoomViewModel.toggleVersionSelection`
- `ScriptExhibitionRoomViewModel.deleteVersions`
- `ScriptExhibitionRoomPage` version chip checkboxes and selected-version toolbar

## Key Files

- `lib/ui/studio_shell/view_models/script_exhibition_room_viewmodel.dart`
- `lib/ui/studio_shell/widgets/script_exhibition_room_page.dart`
- `test/ui/studio_shell/script_exhibition_room_viewmodel_test.dart`
- `test/ui/studio_shell/script_exhibition_room_page_test.dart`

## Verification

- `flutter analyze --no-pub lib/ui/studio_shell/view_models/script_exhibition_room_viewmodel.dart lib/ui/studio_shell/widgets/script_exhibition_room_page.dart test/ui/studio_shell/script_exhibition_room_viewmodel_test.dart test/ui/studio_shell/script_exhibition_room_page_test.dart`
- `flutter test --no-pub test/ui/studio_shell/script_exhibition_room_viewmodel_test.dart --plain-name "deletes multiple versions and falls back to the original version" --reporter expanded`
- `flutter test --no-pub test/ui/studio_shell/script_exhibition_room_viewmodel_test.dart --plain-name "deletes only the selected production version for the current script" --reporter expanded`
- `flutter test --no-pub test/ui/studio_shell/script_exhibition_room_page_test.dart --plain-name "selects multiple version chips for batch deletion" --reporter expanded`

## Notes

The full `script_exhibition_room_viewmodel_test.dart` file still has unrelated recast/category fixture failures in the current dirty workspace. The focused deletion paths and the full page widget test passed.
