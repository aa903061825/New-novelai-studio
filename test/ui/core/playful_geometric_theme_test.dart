import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/ui/core/theme/playful_geometric_theme.dart';

void main() {
  group('PlayfulGeometricTheme', () {
    test('defines the playful geometric color and component defaults', () {
      final theme = PlayfulGeometricTheme.build();

      expect(PlayfulGeometricColors.background, const Color(0xFFFFFDF5));
      expect(PlayfulGeometricColors.foreground, const Color(0xFF1E293B));
      expect(PlayfulGeometricColors.accent, const Color(0xFF8B5CF6));
      expect(PlayfulGeometricColors.secondary, const Color(0xFFF472B6));
      expect(PlayfulGeometricColors.tertiary, const Color(0xFFFBBF24));
      expect(PlayfulGeometricColors.quaternary, const Color(0xFF34D399));
      expect(theme.scaffoldBackgroundColor, PlayfulGeometricColors.background);
      expect(theme.colorScheme.primary, PlayfulGeometricColors.accent);
      expect(theme.colorScheme.secondary, PlayfulGeometricColors.secondary);
      expect(theme.colorScheme.tertiary, PlayfulGeometricColors.tertiary);
      expect(theme.colorScheme.outline, PlayfulGeometricColors.foreground);
      expect(theme.textTheme.headlineSmall?.fontFamily, 'Outfit');
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Plus Jakarta Sans');

      final cardShape = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(cardShape.side.color, PlayfulGeometricColors.foreground);
      expect(cardShape.side.width, PlayfulGeometricBorders.chunky);
      expect(cardShape.borderRadius, BorderRadius.circular(24));
      expect(theme.cardTheme.elevation, 0);
      expect(theme.cardTheme.color, PlayfulGeometricColors.card);

      final inputBorder =
          theme.inputDecorationTheme.enabledBorder as OutlineInputBorder;
      expect(inputBorder.borderSide.color, const Color(0xFFCBD5E1));
      expect(inputBorder.borderSide.width, PlayfulGeometricBorders.chunky);
      expect(inputBorder.borderRadius, BorderRadius.circular(24));
    });

    test('surface decorations use rounded sticker shadows', () {
      final decoration = PlayfulGeometricDecorations.sticker(
        color: PlayfulGeometricColors.tertiary,
        shadowColor: PlayfulGeometricColors.secondary,
      );

      final border = decoration.border as Border;
      final shadow = decoration.boxShadow!.single;

      expect(decoration.color, PlayfulGeometricColors.tertiary);
      expect(decoration.borderRadius, BorderRadius.circular(24));
      expect(border.top.color, PlayfulGeometricColors.foreground);
      expect(border.top.width, PlayfulGeometricBorders.chunky);
      expect(shadow.color, PlayfulGeometricColors.secondary);
      expect(shadow.offset, const Offset(8, 8));
      expect(shadow.blurRadius, 0);
      expect(shadow.spreadRadius, 0);
    });
  });
}
