import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_context_menu.dart';

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

  testWidgets('renders target label, shortcut, and destructive row',
      (tester) async {
    StudioContextMenuAction? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected =
                    await StudioContextMenu.show<StudioContextMenuAction>(
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

    expect(
      find.byKey(const ValueKey('studio-context-menu-target-label')),
      findsOneWidget,
    );
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
