import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/ui/core/widgets/scroll_to_top_overlay.dart';

void main() {
  testWidgets('shows after scrolling and scrolls the active view to the top',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 420,
          height: 520,
          child: ScrollToTopOverlay(
            child: ListView.builder(
              controller: controller,
              itemCount: 60,
              itemBuilder: (context, index) => SizedBox(
                height: 64,
                child: Text('Row $index'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(ScrollToTopOverlay.floatingButtonKey), findsNothing);

    await tester.fling(find.byType(ListView), const Offset(0, -700), 1000);
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(ScrollToTopOverlay.showAfterOffset));
    expect(find.byKey(ScrollToTopOverlay.floatingButtonKey), findsOneWidget);

    await tester.tap(find.byKey(ScrollToTopOverlay.floatingButtonKey));
    await tester.pumpAndSettle();

    expect(controller.offset, 0);
    expect(find.byKey(ScrollToTopOverlay.floatingButtonKey), findsNothing);
  });

  testWidgets('can be dragged to a new on-screen position', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 420,
          height: 520,
          child: ScrollToTopOverlay(
            child: ListView.builder(
              controller: controller,
              itemCount: 60,
              itemBuilder: (context, index) => SizedBox(
                height: 64,
                child: Text('Row $index'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.fling(find.byType(ListView), const Offset(0, -700), 1000);
    await tester.pumpAndSettle();

    final button = find.byKey(ScrollToTopOverlay.floatingButtonKey);
    final start = tester.getCenter(button);

    await tester.drag(button, const Offset(-80, -60));
    await tester.pump();

    final end = tester.getCenter(button);
    expect(end.dx, lessThan(start.dx));
    expect(end.dy, lessThan(start.dy));
  });
}
