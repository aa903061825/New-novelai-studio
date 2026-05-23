import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_panel.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';

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
  });
}
