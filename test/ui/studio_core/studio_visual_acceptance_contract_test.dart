import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';

void main() {
  group('Studio visual acceptance contract', () {
    test('tokens keep the ZZZ Studio visual anchors', () {
      final theme = StudioTheme.build();

      expect(StudioTokens.surfaceBase.computeLuminance(), lessThan(0.01));
      expect(StudioTokens.primary, const Color(0xFFFFE500));
      expect(StudioTokens.cardOutline, StudioTokens.surfaceBase);
      expect(StudioTokens.radiusCard.bottomRight, const Radius.circular(4));
      expect(StudioTokens.radiusPill.topLeft, const Radius.circular(999));
      expect(theme.chipTheme.shape, isA<RoundedRectangleBorder>());
      final chipShape = theme.chipTheme.shape! as RoundedRectangleBorder;
      expect(chipShape.borderRadius, StudioTokens.radiusTag);
      expect(theme.floatingActionButtonTheme.shape, isA<StadiumBorder>());
      expect(theme.textTheme.bodyMedium?.fontStyle, isNot(FontStyle.italic));
      expect(theme.textTheme.titleMedium?.fontStyle, isNot(FontStyle.italic));
    });
  });
}
