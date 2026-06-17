import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_theme.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_button.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_chip.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_panel.dart';

void main() {
  group('StudioTheme', () {
    test('uses the native Novel Studio token palette', () {
      final theme = StudioTheme.build();

      expect(StudioTokens.surfaceBase, const Color(0xFF0A0A0A));
      expect(StudioTokens.surface1, const Color(0xFF111111));
      expect(StudioTokens.surface3, const Color(0xFF1C1C1C));
      expect(StudioTokens.primary, const Color(0xFFFFE500));
      expect(StudioTokens.secondary, const Color(0xFFA8E030));
      expect(theme.scaffoldBackgroundColor, StudioTokens.surface1);
      expect(theme.colorScheme.primary, StudioTokens.primary);
      expect(theme.colorScheme.secondary, StudioTokens.secondary);
      expect(theme.colorScheme.error, StudioTokens.danger);
    });

    test('keeps panel cards sharp on the lower right', () {
      final theme = StudioTheme.build();
      final shape = theme.cardTheme.shape as RoundedRectangleBorder;

      expect(shape.borderRadius, StudioTokens.radiusCard);
      expect(StudioTokens.radiusCard.bottomRight, const Radius.circular(4));
      expect(StudioTokens.radiusPill.topLeft, const Radius.circular(999));
    });

    test('uses a dedicated dark outline for decorative cards', () {
      final theme = StudioTheme.build();
      final shape = theme.cardTheme.shape as RoundedRectangleBorder;
      const panel = StudioPanel(child: SizedBox());

      expect(StudioTokens.cardOutline, StudioTokens.surfaceBase);
      expect(shape.side.color, StudioTokens.cardOutline);
      expect(panel.borderColor, StudioTokens.cardOutline);
    });

    test('uses the shared tag silhouette for chips', () {
      final theme = StudioTheme.build();
      final chipShape = theme.chipTheme.shape as RoundedRectangleBorder;

      expect(chipShape.borderRadius, StudioTokens.radiusTag);
      expect(StudioTokens.radiusTag.topLeft, const Radius.circular(10));
      expect(StudioTokens.radiusTag.topRight, const Radius.circular(10));
      expect(StudioTokens.radiusTag.bottomRight, const Radius.circular(10));
      expect(StudioTokens.radiusTag.bottomLeft, const Radius.circular(2));
    });

    testWidgets('StudioChip uses the shared tag silhouette', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.build(),
          home: const Scaffold(
            body: StudioChip(
              key: ValueKey('studio-chip-shape-probe'),
              label: 'tag',
            ),
          ),
        ),
      );

      final material = tester.widget<Material>(
        find.descendant(
          of: find.byKey(const ValueKey('studio-chip-shape-probe')),
          matching: find.byType(Material),
        ),
      );
      final shape = material.shape! as RoundedRectangleBorder;

      expect(material.clipBehavior, Clip.antiAlias);
      expect(shape.borderRadius, StudioTokens.radiusTag);
    });

    test('button themes expose visible hovered states', () {
      final theme = StudioTheme.build();

      final filledStyle = theme.filledButtonTheme.style!;
      expect(
        filledStyle.backgroundColor!.resolve(const {}),
        StudioTokens.primary,
      );
      expect(
        filledStyle.backgroundColor!.resolve({WidgetState.hovered}),
        isNot(StudioTokens.primary),
      );

      final outlinedStyle = theme.outlinedButtonTheme.style!;
      expect(
        outlinedStyle.backgroundColor!.resolve(const {}),
        Colors.transparent,
      );
      expect(
        outlinedStyle.backgroundColor!.resolve({WidgetState.hovered}),
        StudioTokens.surface3,
      );
      expect(
        outlinedStyle.side!.resolve({WidgetState.hovered})?.color,
        StudioTokens.primary,
      );
    });

    test('segmented and icon button themes expose hovered states', () {
      final theme = StudioTheme.build();

      final segmentedStyle = theme.segmentedButtonTheme.style!;
      expect(
        segmentedStyle.backgroundColor!.resolve(const {}),
        Colors.transparent,
      );
      expect(
        segmentedStyle.backgroundColor!.resolve({WidgetState.hovered}),
        StudioTokens.surface3,
      );
      expect(
        segmentedStyle.backgroundColor!.resolve({
          WidgetState.selected,
          WidgetState.hovered,
        }),
        StudioTokens.secondary,
      );

      final iconStyle = theme.iconButtonTheme.style!;
      expect(
        iconStyle.backgroundColor!.resolve(const {}),
        Colors.transparent,
      );
      expect(
        iconStyle.backgroundColor!.resolve({WidgetState.hovered}),
        StudioTokens.surface3,
      );
    });

    testWidgets('StudioButton exposes a visible hovered state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: StudioTheme.build(),
          home: Scaffold(
            body: StudioButton(
              label: 'Run',
              onPressed: () {},
            ),
          ),
        ),
      );

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      final style = button.style!;

      expect(
        style.backgroundColor!.resolve(const {}),
        StudioTokens.primary,
      );
      expect(
        style.backgroundColor!.resolve({WidgetState.hovered}),
        isNot(StudioTokens.primary),
      );
    });
  });
}
