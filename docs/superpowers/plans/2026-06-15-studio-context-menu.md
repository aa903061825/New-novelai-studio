# Studio Context Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a shared Studio-styled right-click menu and migrate the prompt tag editor/display menus to it without changing their action behavior.

**Architecture:** Add a focused `StudioContextMenu` widget helper under `lib/ui/studio_core/widgets/`. Keep Flutter's `showMenu` routing for this first slice, but centralize menu shape, rows, target label, dividers, tones, and keys behind a typed API.

**Tech Stack:** Flutter Material widgets, existing `StudioTokens`, existing `flutter_test` widget tests.

---

### Task 1: Add Shared Menu Tests

**Files:**
- Create: `test/ui/studio_core/studio_context_menu_test.dart`
- Create later in Task 2: `lib/ui/studio_core/widgets/studio_context_menu.dart`

- [ ] **Step 1: Write failing tests for anchor radius and menu rendering**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_context_menu.dart';

void main() {
  test('anchorBorderRadius squares only the requested anchor corner', () {
    final radius = StudioContextMenu.anchorBorderRadius(
      StudioContextMenuAnchorCorner.topLeft,
    );

    expect(radius.topLeft, Radius.zero);
    expect(radius.topRight, const Radius.circular(18));
    expect(radius.bottomRight, const Radius.circular(18));
    expect(radius.bottomLeft, const Radius.circular(18));
  });

  testWidgets('renders target label, icon row, shortcut, and destructive row',
      (tester) async {
    StudioContextMenuAction? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await StudioContextMenu.show<StudioContextMenuAction>(
                  context: context,
                  position: const Offset(120, 120),
                  targetLabel: 'city lights',
                  items: const [
                    StudioContextMenuItem(
                      value: StudioContextMenuAction.primary,
                      icon: Icons.open_in_new,
                      label: 'Open Wiki',
                      shortcut: 'Enter',
                      tone: StudioContextMenuItemTone.highlight,
                    ),
                    StudioContextMenuDivider(),
                    StudioContextMenuItem(
                      key: ValueKey('delete-row'),
                      value: StudioContextMenuAction.delete,
                      icon: Icons.close,
                      label: 'Delete',
                      shortcut: 'Del',
                      tone: StudioContextMenuItemTone.destructive,
                    ),
                  ],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('studio-context-menu-target-label')),
        findsOneWidget);
    expect(find.text('city lights'), findsOneWidget);
    expect(find.text('Open Wiki'), findsOneWidget);
    expect(find.text('Enter'), findsOneWidget);
    expect(find.byKey(const ValueKey('delete-row')), findsOneWidget);

    final deleteText = tester.widget<Text>(find.text('Delete'));
    expect(deleteText.style?.color, StudioTokens.danger);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(selected, StudioContextMenuAction.delete);
  });
}

enum StudioContextMenuAction { primary, delete }
```

- [ ] **Step 2: Run the new test to verify it fails**

Run:

```powershell
flutter test test/ui/studio_core/studio_context_menu_test.dart
```

Expected: fail because `studio_context_menu.dart` does not exist.

### Task 2: Implement `StudioContextMenu`

**Files:**
- Create: `lib/ui/studio_core/widgets/studio_context_menu.dart`
- Test: `test/ui/studio_core/studio_context_menu_test.dart`

- [ ] **Step 1: Add the shared menu API and row widgets**

Create `lib/ui/studio_core/widgets/studio_context_menu.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';

enum StudioContextMenuAnchorCorner { topLeft, topRight, bottomRight, bottomLeft }

enum StudioContextMenuItemTone { normal, highlight, destructive }

sealed class StudioContextMenuEntry<T> {
  const StudioContextMenuEntry();
}

class StudioContextMenuDivider<T> extends StudioContextMenuEntry<T> {
  const StudioContextMenuDivider();
}

class StudioContextMenuItem<T> extends StudioContextMenuEntry<T> {
  final Key? key;
  final T value;
  final IconData icon;
  final String label;
  final String? shortcut;
  final bool enabled;
  final StudioContextMenuItemTone tone;

  const StudioContextMenuItem({
    this.key,
    required this.value,
    required this.icon,
    required this.label,
    this.shortcut,
    this.enabled = true,
    this.tone = StudioContextMenuItemTone.normal,
  });
}

class StudioContextMenu {
  static Future<T?> show<T>({
    required BuildContext context,
    required Offset position,
    required List<StudioContextMenuEntry<T>> items,
    String? targetLabel,
    StudioContextMenuAnchorCorner anchorCorner =
        StudioContextMenuAnchorCorner.topLeft,
  }) {
    return showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: const Color(0xFF181818),
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: anchorBorderRadius(anchorCorner),
        side: const BorderSide(color: StudioTokens.borderStrong),
      ),
      constraints: const BoxConstraints(minWidth: 236, maxWidth: 320),
      items: [
        if (targetLabel != null && targetLabel.trim().isNotEmpty)
          PopupMenuItem<T>(
            enabled: false,
            height: 34,
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Text(
                targetLabel.trim(),
                key: const ValueKey('studio-context-menu-target-label'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: StudioTokens.textMuted,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ),
        for (final item in items) _entry(context, item),
      ],
    );
  }

  static BorderRadius anchorBorderRadius(
    StudioContextMenuAnchorCorner corner,
  ) {
    const round = Radius.circular(18);
    return BorderRadius.only(
      topLeft:
          corner == StudioContextMenuAnchorCorner.topLeft ? Radius.zero : round,
      topRight:
          corner == StudioContextMenuAnchorCorner.topRight ? Radius.zero : round,
      bottomRight: corner == StudioContextMenuAnchorCorner.bottomRight
          ? Radius.zero
          : round,
      bottomLeft: corner == StudioContextMenuAnchorCorner.bottomLeft
          ? Radius.zero
          : round,
    );
  }

  static PopupMenuEntry<T> _entry<T>(
    BuildContext context,
    StudioContextMenuEntry<T> entry,
  ) {
    return switch (entry) {
      StudioContextMenuDivider<T>() => const PopupMenuDivider(height: 12),
      StudioContextMenuItem<T>() => PopupMenuItem<T>(
          key: entry.key,
          value: entry.value,
          enabled: entry.enabled,
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _StudioContextMenuRow<T>(item: entry),
        ),
    };
  }

  const StudioContextMenu._();
}

class _StudioContextMenuRow<T> extends StatelessWidget {
  final StudioContextMenuItem<T> item;

  const _StudioContextMenuRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = switch (item.tone) {
      StudioContextMenuItemTone.destructive => StudioTokens.danger,
      StudioContextMenuItemTone.highlight => StudioTokens.textPrimary,
      StudioContextMenuItemTone.normal => StudioTokens.textPrimary,
    };
    final iconColor = switch (item.tone) {
      StudioContextMenuItemTone.destructive => StudioTokens.danger,
      StudioContextMenuItemTone.highlight => StudioTokens.primary,
      StudioContextMenuItemTone.normal => StudioTokens.primary,
    };
    final background = switch (item.tone) {
      StudioContextMenuItemTone.highlight => StudioTokens.primary.withAlpha(32),
      _ => Colors.transparent,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(item.icon, color: iconColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            if (item.shortcut != null && item.shortcut!.isNotEmpty) ...[
              const SizedBox(width: 12),
              Text(
                item.shortcut!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: StudioTokens.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run the shared menu test**

Run:

```powershell
flutter test test/ui/studio_core/studio_context_menu_test.dart
```

Expected: pass.

### Task 3: Migrate Prompt Tag Editor Menu

**Files:**
- Modify: `lib/ui/studio_core/widgets/prompt_tag_editor.dart`
- Test: `test/ui/studio_core/prompt_tag_editor_test.dart`

- [ ] **Step 1: Import the shared menu**

Add:

```dart
import 'package:nai_casrand/ui/studio_core/widgets/studio_context_menu.dart';
```

- [ ] **Step 2: Replace the editor `showMenu` call**

In `_showTagMenu`, replace the `showMenu<_PromptTagEditorMenuAction>` block with:

```dart
final choice = await StudioContextMenu.show<_PromptTagEditorMenuAction>(
  context: context,
  position: globalPosition,
  targetLabel: clickedDisplayTag,
  items: [
    StudioContextMenuItem(
      value: _PromptTagEditorMenuAction.openDanbooru,
      icon: Icons.open_in_new_outlined,
      label: '打开 Danbooru Wiki',
      tone: StudioContextMenuItemTone.highlight,
    ),
    StudioContextMenuItem(
      key: const ValueKey('prompt-tag-editor-ai-retranslate'),
      value: _PromptTagEditorMenuAction.aiRetranslate,
      icon: Icons.translate_outlined,
      label: _retranslateMenuLabel(),
    ),
    const StudioContextMenuItem(
      value: _PromptTagEditorMenuAction.editTag,
      icon: Icons.edit_outlined,
      label: '编辑标签',
      shortcut: 'Enter',
    ),
    StudioContextMenuItem(
      key: selectedCount > 1
          ? const ValueKey('prompt-tag-editor-copy-selected')
          : const ValueKey('prompt-tag-editor-copy-current'),
      value: _PromptTagEditorMenuAction.copy,
      icon: Icons.content_copy_outlined,
      label: selectedCount > 1 ? '复制选中' : '复制标签',
      shortcut: 'Ctrl C',
    ),
    if (addToFilterRules != null)
      const StudioContextMenuItem(
        key: ValueKey('prompt-tag-editor-add-to-filter-rules'),
        value: _PromptTagEditorMenuAction.addToFilterRules,
        icon: Icons.filter_alt_outlined,
        label: '加入屏蔽库',
      ),
    const StudioContextMenuDivider(),
    StudioContextMenuItem(
      key: selectedCount > 1
          ? const ValueKey('prompt-tag-editor-delete-selected')
          : const ValueKey('prompt-tag-editor-delete-current'),
      value: _PromptTagEditorMenuAction.delete,
      icon: Icons.close,
      label: selectedCount > 1 ? '删除选中' : '删除标签',
      shortcut: 'Del',
      tone: StudioContextMenuItemTone.destructive,
    ),
  ],
);
```

- [ ] **Step 3: Update editor tests for the new order**

The existing editor test currently expects delete above copy. Change it to
expect copy above delete, because destructive actions now live below the divider.

Run:

```powershell
flutter test test/ui/studio_core/prompt_tag_editor_test.dart
```

Expected: pass.

### Task 4: Migrate Prompt Tag Display Menu

**Files:**
- Modify: `lib/ui/studio_core/widgets/prompt_tag_display.dart`
- Test: `test/ui/studio_core/prompt_tag_display_test.dart`

- [ ] **Step 1: Import the shared menu**

Add:

```dart
import 'package:nai_casrand/ui/studio_core/widgets/studio_context_menu.dart';
```

- [ ] **Step 2: Replace the display `showMenu` call**

In `_showTagMenu`, replace the `showMenu<_PromptTagMenuChoice>` block with:

```dart
final choice = await StudioContextMenu.show<_PromptTagMenuChoice>(
  context: context,
  position: position,
  targetLabel: tag,
  items: [
    const StudioContextMenuItem(
      value: _PromptTagMenuChoice(_PromptTagMenuAction.openDanbooru),
      icon: Icons.open_in_new_outlined,
      label: '打开 Danbooru Wiki',
      tone: StudioContextMenuItemTone.highlight,
    ),
    StudioContextMenuItem(
      value: const _PromptTagMenuChoice(_PromptTagMenuAction.aiRetranslate),
      icon: Icons.translate_outlined,
      label: _retranslateMenuLabel(),
    ),
    const StudioContextMenuItem(
      value: _PromptTagMenuChoice(_PromptTagMenuAction.manualEdit),
      icon: Icons.edit_outlined,
      label: '手动编辑',
      shortcut: 'Enter',
    ),
    if (widget.onChanged != null)
      const StudioContextMenuItem(
        key: ValueKey('prompt-tag-edit-weight'),
        value: _PromptTagMenuChoice(_PromptTagMenuAction.editWeight),
        icon: Icons.monitor_weight_outlined,
        label: '编辑权重',
      ),
    const StudioContextMenuItem(
      key: ValueKey('prompt-tag-change-category'),
      value: _PromptTagMenuChoice(_PromptTagMenuAction.changeCategory),
      icon: Icons.category_outlined,
      label: '改分类...',
    ),
    const StudioContextMenuItem(
      key: ValueKey('prompt-tag-clear-category'),
      value: _PromptTagMenuChoice(_PromptTagMenuAction.clearCategory),
      icon: Icons.auto_fix_normal_outlined,
      label: '恢复自动分类',
    ),
    const StudioContextMenuDivider(),
    const StudioContextMenuItem(
      value: _PromptTagMenuChoice(_PromptTagMenuAction.copy),
      icon: Icons.content_copy_outlined,
      label: '复制标签',
      shortcut: 'Ctrl C',
    ),
    if (addToFilterRules != null)
      const StudioContextMenuItem(
        key: ValueKey('prompt-tag-add-to-filter-rules'),
        value: _PromptTagMenuChoice(_PromptTagMenuAction.addToFilterRules),
        icon: Icons.filter_alt_outlined,
        label: '加入屏蔽库',
      ),
  ],
);
```

- [ ] **Step 3: Run display tests**

Run:

```powershell
flutter test test/ui/studio_core/prompt_tag_display_test.dart
```

Expected: pass.

### Task 5: Verify Touched Surface

**Files:**
- Verify: `lib/ui/studio_core/widgets/studio_context_menu.dart`
- Verify: `lib/ui/studio_core/widgets/prompt_tag_editor.dart`
- Verify: `lib/ui/studio_core/widgets/prompt_tag_display.dart`

- [ ] **Step 1: Analyze touched files**

Run:

```powershell
flutter analyze lib/ui/studio_core/widgets/studio_context_menu.dart lib/ui/studio_core/widgets/prompt_tag_editor.dart lib/ui/studio_core/widgets/prompt_tag_display.dart
```

Expected: no new issues in touched files.

- [ ] **Step 2: Run focused tests together**

Run:

```powershell
flutter test test/ui/studio_core/studio_context_menu_test.dart test/ui/studio_core/prompt_tag_editor_test.dart test/ui/studio_core/prompt_tag_display_test.dart
```

Expected: pass.

- [ ] **Step 3: Check Beads and git status**

Run:

```powershell
bd show NAI_NEW-v8jv
git status --short
```

Expected: Beads issue is in progress; git status shows only expected right-click
menu files plus any pre-existing unrelated project changes.

## Self-Review

- The plan covers the shared component, prompt tag editor migration, prompt tag
  display migration, focused tests, and analyzer verification.
- The first implementation uses `showMenu` to preserve current behavior and
  avoid a risky overlay rewrite.
- The zero-radius anchor corner is testable through `anchorBorderRadius`.
- The rollout intentionally leaves script exhibition menus for a follow-up pass
  after prompt tag menus prove the shared component.
