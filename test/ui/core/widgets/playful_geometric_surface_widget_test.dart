import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/ui/core/widgets/playful_geometric_surface.dart';

void main() {
  testWidgets('surface hover, press, and tap use the same InkWell hit target', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PlayfulGeometricSurface(
              onTap: () {},
              wiggleOnHover: true,
              child: const SizedBox(width: 120, height: 64),
            ),
          ),
        ),
      ),
    );

    final pointerListeners = tester
        .widgetList<Listener>(
          find.descendant(
            of: find.byType(PlayfulGeometricSurface),
            matching: find.byType(Listener),
          ),
        )
        .where(
          (listener) =>
              listener.onPointerUp != null || listener.onPointerCancel != null,
        );
    expect(pointerListeners, isEmpty);

    final inkWell = tester.widget<InkWell>(find.byType(InkWell));
    expect(inkWell.onTap, isNotNull);
    expect(inkWell.onHover, isNotNull);
    expect(inkWell.onTapDown, isNotNull);
    expect(inkWell.onTapUp, isNotNull);
    expect(inkWell.onTapCancel, isNotNull);
  });
}
