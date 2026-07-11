import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_wheel_zoom.dart';

void main() {
  testWidgets('wheel zoom coalesces bursty scroll events into one frame update',
      (tester) async {
    final transform = TransformationController();
    addTearDown(transform.dispose);
    final zoom = StudioWheelZoomController(
      transformationController: transform,
      minScale: 1,
      maxScale: 8,
    );
    addTearDown(zoom.dispose);
    var changeCount = 0;
    transform.addListener(() {
      changeCount += 1;
    });

    for (var i = 0; i < 5; i += 1) {
      zoom.handlePointerSignal(
        const PointerScrollEvent(
          position: Offset(80, 60),
          scrollDelta: Offset(0, -120),
        ),
      );
    }

    expect(changeCount, 0);
    expect(transform.value.getMaxScaleOnAxis(), 1);

    await tester.pump();

    expect(changeCount, 1);
    expect(
      transform.value.getMaxScaleOnAxis(),
      closeTo(
        StudioWheelZoomController.defaultZoomInFactor *
            StudioWheelZoomController.defaultZoomInFactor *
            StudioWheelZoomController.defaultZoomInFactor *
            StudioWheelZoomController.defaultZoomInFactor *
            StudioWheelZoomController.defaultZoomInFactor,
        0.0001,
      ),
    );
  });

  testWidgets('reset clears pending wheel zoom before the next frame',
      (tester) async {
    final transform = TransformationController();
    addTearDown(transform.dispose);
    final zoom = StudioWheelZoomController(
      transformationController: transform,
      minScale: 1,
      maxScale: 8,
    );
    addTearDown(zoom.dispose);
    var changeCount = 0;
    transform.addListener(() {
      changeCount += 1;
    });
    transform.value = Matrix4.diagonal3Values(2, 2, 1);
    changeCount = 0;

    zoom.handlePointerSignal(
      const PointerScrollEvent(
        position: Offset(80, 60),
        scrollDelta: Offset(0, -120),
      ),
    );
    zoom.reset();
    await tester.pump();

    expect(changeCount, 1);
    expect(transform.value.getMaxScaleOnAxis(), 1);
  });

  testWidgets('control modifier can be required for wheel zoom',
      (tester) async {
    final transform = TransformationController();
    addTearDown(transform.dispose);
    final zoom = StudioWheelZoomController(
      transformationController: transform,
      minScale: 1,
      maxScale: 8,
      requireControlModifier: true,
    );
    addTearDown(zoom.dispose);

    expect(
      zoom.handlePointerSignal(
        const PointerScrollEvent(
          position: Offset(80, 60),
          scrollDelta: Offset(0, -120),
        ),
      ),
      isFalse,
    );
    await tester.pump();
    expect(transform.value.getMaxScaleOnAxis(), 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    addTearDown(() => tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft));
    expect(
      zoom.handlePointerSignal(
        const PointerScrollEvent(
          position: Offset(80, 60),
          scrollDelta: Offset(0, -120),
        ),
      ),
      isTrue,
    );
    await tester.pump();

    expect(
      transform.value.getMaxScaleOnAxis(),
      closeTo(StudioWheelZoomController.defaultZoomInFactor, 0.0001),
    );
  });
}
