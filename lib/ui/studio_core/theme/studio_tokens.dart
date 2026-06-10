import 'package:flutter/material.dart';

class StudioTokens {
  static const surfaceBase = Color(0xFF0A0A0A);
  static const surface1 = Color(0xFF111111);
  static const surface2 = Color(0xFF141414);
  static const surface3 = Color(0xFF1C1C1C);
  static const surface4 = Color(0xFF242424);

  static const textPrimary = Color(0xFFF5F5F0);
  static const textSecondary = Color(0xFFB8B8AD);
  static const textMuted = Color(0xFF7A7A72);
  static const border = Color(0xFF30302B);
  static const borderStrong = Color(0xFF4B4B43);
  static const cardOutline = surfaceBase;

  static const primary = Color(0xFFFFE500);
  static const onPrimary = Color(0xFF151505);
  static const secondary = Color(0xFFA8E030);
  static const active = Color(0xFF4ADE80);
  static const danger = Color(0xFFFF4B4B);
  static const warning = Color(0xFFFF9A3C);
  static const info = Color(0xFF6EB9FF);

  static const radiusSmall = 8.0;
  static const radiusSlotValue = 10.0;
  static const radiusBadgeValue = 5.0;
  static const radiusTagValue = 10.0;
  static const radiusTagCutValue = 2.0;
  static const radiusTagStripeValue = 9.0;
  static const radiusTagStripeCutValue = 1.0;
  static const radiusMedium = 12.0;
  static const radiusLarge = 16.0;
  static const radiusPanel = 18.0;
  static const radiusPillValue = 999.0;
  static const radiusSharpValue = 4.0;
  static const radiusBadgeSharpValue = 2.0;

  static const cardBorderSide = BorderSide(color: cardOutline);
  static const cardBorder = Border.fromBorderSide(cardBorderSide);
  static const radiusPill = BorderRadius.all(Radius.circular(radiusPillValue));
  static const radiusCard = BorderRadius.only(
    topLeft: Radius.circular(radiusLarge),
    topRight: Radius.circular(radiusLarge),
    bottomLeft: Radius.circular(radiusLarge),
    bottomRight: Radius.circular(radiusSharpValue),
  );
  static const radiusSlot = BorderRadius.only(
    topLeft: Radius.circular(radiusSlotValue),
    topRight: Radius.circular(radiusSlotValue),
    bottomLeft: Radius.circular(radiusSlotValue),
    bottomRight: Radius.circular(radiusSharpValue),
  );
  static const radiusBadge = BorderRadius.only(
    topLeft: Radius.circular(radiusBadgeValue),
    topRight: Radius.circular(radiusBadgeValue),
    bottomLeft: Radius.circular(radiusBadgeValue),
    bottomRight: Radius.circular(radiusBadgeSharpValue),
  );
  static const radiusTag = BorderRadius.only(
    topLeft: Radius.circular(radiusTagValue),
    topRight: Radius.circular(radiusTagValue),
    bottomRight: Radius.circular(radiusTagValue),
    bottomLeft: Radius.circular(radiusTagCutValue),
  );
  static const radiusTagStripe = BorderRadius.only(
    topLeft: Radius.circular(radiusTagStripeValue),
    bottomLeft: Radius.circular(radiusTagStripeCutValue),
  );

  static const pagePadding = 24.0;
  static const panelPadding = 18.0;
  static const sidebarWidth = 236.0;
  static const compactSidebarWidth = 88.0;

  const StudioTokens._();
}
