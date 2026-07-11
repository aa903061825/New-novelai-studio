# Script Exhibition Sticky Detail Controls

## Purpose

Keep the selected Script Exhibition detail controls visible while scrolling a
large image waterfall. The pinned region includes the selected script header,
version chips, status filters, and item sort toolbar.

## Entry Points

- `ScriptExhibitionRoomPage`
- `script-exhibition-scroll-view`
- `script-exhibition-detail-title-*`
- `script-exhibition-item-sort-menu`

## Key Files

- `lib/ui/studio_shell/widgets/script_exhibition_room_page.dart`
- `test/ui/studio_shell/script_exhibition_room_page_test.dart`

## Implementation Notes

- The category strip remains a pinned `SliverPersistentHeader`.
- The selected script detail controls now use `PinnedHeaderSliver`, so the
  child keeps its measured height and remains visible above the waterfall.
- The detail sort toolbar is grouped into the same pinned sliver as the detail
  header instead of living in a separate normal `SliverToBoxAdapter`.

## Verification

- `flutter test --no-pub test\ui\studio_shell\script_exhibition_room_page_test.dart --plain-name "keeps detail controls pinned while scrolling the waterfall" --reporter expanded --timeout 30s`
- `flutter test --no-pub test\ui\studio_shell\script_exhibition_room_page_test.dart --plain-name "keeps the category strip pinned while scrolling the shelf" --reporter expanded --timeout 30s`
- `flutter analyze --no-pub lib\ui\studio_shell\widgets\script_exhibition_room_page.dart test\ui\studio_shell\script_exhibition_room_page_test.dart`
- `flutter test --no-pub test\ui\studio_shell\script_exhibition_room_page_test.dart --reporter expanded --timeout 60s`

Last verified: 2026-06-26.
